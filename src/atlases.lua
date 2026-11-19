local modHandler = require("mods")
local fileLocations = require("file_locations")
local spriteLoader = require("sprite_loader")
local utils = require("utils")
local logging = require("logging")

local atlases = {}
local atlasNames = {}

local atlasesMt = {}

function atlasesMt.__index(self, key)
    local target = rawget(self, key) or rawget(self, atlasNames[key])

    if target then
        return target

    else
        for name, atlas in pairs(atlases) do
            if name:lower() == key:lower() then
                atlasNames[key] = name

                return atlas
            end
        end
    end
end

setmetatable(atlases, atlasesMt)

local celesteAtlasRelativePath = utils.joinpath("Content", "Graphics", "Atlases")
local gameplayMeta = "Gameplay.meta"
local guiMeta = "Gui.meta"

local function addAtlasMetatable(name)
    local atlas = atlases[name] or {}
    local atlasMt = {
        __index = function(self, key)
            return atlases.getResource(key, name, self)
        end
    }

    atlases[name] = setmetatable(atlas, atlasMt)
end

function atlases.loadCelesteAtlas(name, meta, path)
    local atlas = spriteLoader.getCacheOrLoadSpriteAtlas(meta, path)
    local fakeFilename = atlas._imageMeta[1].filename

    spriteLoader.addAtlasToRuntimeAtlas(atlas, fakeFilename)

    -- Remember what the game itself provides. Mod atlases are loaded into this same table
    -- afterwards and would otherwise make vanilla resources look like they come from a mod.
    local vanillaResources = {}

    for resource, sprite in pairs(atlas) do
        if type(sprite) == "table" and sprite.image then
            vanillaResources[resource] = sprite
        end
    end

    atlases[name] = atlas
    atlas.__vanillaResources = vanillaResources

    addAtlasMetatable(name)
end

function atlases.createAtlas(name)
    addAtlasMetatable(name)
end

function atlases.loadCelesteAtlases()
    local celesteAtlasPath = utils.joinpath(fileLocations.getCelesteDir(), celesteAtlasRelativePath)

    atlases.loadCelesteAtlas("Gameplay", gameplayMeta, celesteAtlasPath)
    atlases.loadCelesteAtlas("Gui", guiMeta, celesteAtlasPath)
end

-- Loads another vanilla Celeste atlas (Overworld, Misc, Portraits, ...) the first time a preview
-- references it. Only Gameplay and Gui used to be loaded, so resources from the other atlases
-- could not be resolved at all.
--
-- spriteLoader.loadSpriteAtlas yields while it works (it is normally driven by a loading task), so
-- the load runs in its own coroutine and is resumed to completion here. Calling it directly from
-- the UI update would yield from the main thread and fail.
function atlases.loadCelesteAtlasIfAvailable(name)
    if type(name) ~= "string" or not name:match("^[%w_-]+$") then
        return
    end

    if rawget(atlases, name) then
        return atlases[name]
    end

    local celesteAtlasPath = utils.joinpath(fileLocations.getCelesteDir(), celesteAtlasRelativePath)
    local meta = name .. ".meta"

    if not utils.isFile(utils.joinpath(celesteAtlasPath, meta)) then
        return
    end

    -- No-packing atlases store one .data per resource and are loaded by loadCelesteResource;
    -- loadSpriteAtlas only understands packed pages.
    if utils.isDirectory(utils.joinpath(celesteAtlasPath, name)) then
        return
    end

    local thread = coroutine.create(function()
        atlases.loadCelesteAtlas(name, meta, celesteAtlasPath)
    end)
    local success, message = coroutine.resume(thread)

    while success and coroutine.status(thread) ~= "dead" do
        success, message = coroutine.resume(thread)
    end

    if not success then
        logging.warning(string.format("Could not load the '%s' atlas: %s", name, tostring(message)))

        return
    end

    return atlases[name]
end

-- Remove everything until after the atlas name
local function getResourceName(filename)
    local parts = filename:split("/")()
    local resourceNameWithExt = table.concat({select(5, unpack(parts))}, "/")

    return utils.stripExtension(resourceNameWithExt)
end

function atlases.loadExternalAtlas(name)
    atlases[name] = atlases[name] or {}

    local atlas = atlases[name]
    local atlasModsDir = modHandler.commonModContent .. "/" .. "Graphics/Atlases/" .. name
    local filenames = {}

    utils.getFilenames(atlasModsDir, true, filenames, function(filename)
        return utils.fileExtension(filename) == "png"
    end)

    for i, filename in ipairs(filenames) do
        local resourceName = getResourceName(filename)
        local sprite = spriteLoader.loadExternalSprite(filename)

        atlas[resourceName] = sprite

        if i > 0 and i % 10 == 0 then
            coroutine.yield()
        end
    end
end

function atlases.addInternalPrefix(resource)
    return modHandler.internalModContent .. "/" .. resource
end

function atlases.getInternalResource(resource, name)
    if utils.startsWith(resource, modHandler.internalModContent) then
        -- Remove internal mod prefix and first /
        local internalResource = resource:sub(#modHandler.internalModContent + 2)
        local filename = string.format("assets/atlases/%s/%s.png", name, internalResource)
        local sprite = spriteLoader.loadExternalSprite(filename)

        if sprite then
            atlases[name][resource] = sprite

            return sprite
        end
    end
end

-- Whether the vanilla atlas stores one .data file per resource instead of one packed page.
function atlases.isNoPackingAtlas(name)
    if type(name) ~= "string" or not name:match("^[%w_-]+$") then
        return false
    end

    return utils.isDirectory(utils.joinpath(fileLocations.getCelesteDir(), celesteAtlasRelativePath,
        name))
end

-- Most Celeste atlases other than Gameplay/Gui use "--no-packing": every resource has its own
-- .data file under Content/Graphics/Atlases/<atlas>/. Load just the requested resource instead of
-- the whole atlas. This is what makes Overworld textures (snow, overlay, ...) resolvable.
function atlases.loadCelesteResource(name, resource)
    if type(name) ~= "string" or not name:match("^[%w_-]+$") then
        return
    end

    if type(resource) ~= "string" then
        return
    end

    local resourcePath = resource:gsub("\\", "/")

    if resourcePath:find("%.%.") then
        return
    end

    local path = utils.joinpath(fileLocations.getCelesteDir(), celesteAtlasRelativePath,
        name, resourcePath .. ".data")

    if not utils.isFile(path) then
        return
    end

    local image, imageData
    local thread = coroutine.create(function()
        image, imageData = spriteLoader.loadDataImage(path)
    end)
    local success, message = coroutine.resume(thread)

    while success and coroutine.status(thread) ~= "dead" do
        success, message = coroutine.resume(thread)
    end

    if not success or not image then
        logging.warning(string.format("Could not load the '%s/%s' texture: %s", name, resourcePath,
            tostring(message)))

        return
    end

    local width, height = image:getDimensions()
    local sprite = {
        x = 0,
        y = 0,
        width = width,
        height = height,
        offsetX = 0,
        offsetY = 0,
        realWidth = width,
        realHeight = height,
        image = image,
        imageData = imageData,
        meta = {
            image = image,
            imageData = imageData,
            width = width,
            height = height,
            filename = path,
            dataName = name .. "/" .. resourcePath
        },
        filename = path,
        realFilename = path,
        internalFile = true,
        fromZipFile = false,
        loadedAt = os.time()
    }

    sprite.quad = love.graphics.newQuad(0, 0, width, height, width, height)

    if not atlases[name] then
        atlases.createAtlas(name)
    end

    atlases[name].__noPacking = true
    atlases[name].__vanillaResources = rawget(atlases[name], "__vanillaResources") or {}
    atlases[name].__vanillaResources[resource] = sprite
    atlases[name][resource] = sprite

    return sprite
end

-- TODO - Make it possible to refetch the resource
function atlases.getResource(resource, name, atlas)
    if not resource then
        return
    end

    if not atlas then
        name = name or "Gameplay"

        if not atlases[name] then
            atlases.loadCelesteAtlasIfAvailable(name)
        end

        if not atlases[name] then
            atlases.createAtlas(name)
            atlases[name].__noPacking = atlases.isNoPackingAtlas(name)
        end

        atlas = atlases[name]
    end

    local targetResource = rawget(atlas, resource)

    -- No-packing vanilla atlases (Overworld, Misc, Portraits, ...): resolve a single resource
    -- from its own .data file on demand. Read the marker raw: the atlas metatable forwards unknown
    -- keys to getResource, so atlas.__noPacking would recurse forever.
    if not targetResource and (rawget(atlas, "__noPacking") or atlases.isNoPackingAtlas(name)) then
        local vanilla = atlases.loadCelesteResource(name, resource)

        if vanilla then
            return vanilla
        end
    end

    -- First attempt to see if this is an external resource
    -- Then check if it is an internal one
    if not targetResource then
        local filename = string.format("%s/Graphics/Atlases/%s/%s.png", modHandler.commonModContent, name, resource)
        local sprite = spriteLoader.loadExternalSprite(filename)

        if sprite then
            atlases[name][resource] = sprite

            return sprite

        else
            return atlases.getInternalResource(resource, name)
        end
    end

    return targetResource
end

-- Reloads (or adds) one atlas resource from a concrete mounted file. Used for custom tileset images
-- that changed on disk without reloading every filename of the mod.
function atlases.reloadResourceFromFile(resource, filename, name)
    name = name or "Gameplay"

    if not atlases[name] then
        atlases.createAtlas(name)
    end

    local atlas = atlases[name]
    local previous = rawget(atlas, resource)
    local sprite = spriteLoader.loadExternalSprite(filename)

    if sprite then
        if previous and previous.loadedAt then
            spriteLoader.removeExternalSprite(previous)
        end

        rawset(atlas, resource, sprite)

        return sprite
    end

    return nil
end

function atlases.loadExternalAtlases()
    atlases.loadExternalAtlas("Gameplay")
end

return atlases