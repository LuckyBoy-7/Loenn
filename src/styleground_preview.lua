-- Styleground previews.
--
-- The per-effect configuration lives in assets/stylegrounds/index.lua. This module only knows how
-- to turn that configuration (plus the current effect attributes) into drawable sprites:
--   * a static preview image from assets/stylegrounds/
--   * a texture referenced by one of the effect's attributes
--   * the extra textures listed in `otherTextures`, in one of the four supported styles
--
-- Every lookup falls back to assets/stylegrounds/placeholder.png, so an effect without an index
-- entry still shows something instead of an empty preview box.

local utils = require("utils")
local atlases = require("atlases")
local virtualFs = require("virtual_fs")
local logging = require("logging")
local gifDecoder = require("gif_decoder")

local stylegroundPreview = {}

stylegroundPreview.PLACEHOLDER = "assets/stylegrounds/placeholder.png"
stylegroundPreview.DEFAULT_BASE_PATH = "Graphics/Atlases/Gameplay"
stylegroundPreview.MAX_TEXTURE_CELLS = 36

local INDEX_MODULE = "assets/stylegrounds/index"

local index
local rawImages = {}
local rawSprites = {}
local placeholderSprite
local folderCache = {}
local gifCache = {}

local function logWarning(message)
    logging.warning("[stylegrounds] " .. message)
end

-- Called when the stylegrounds window opens: lets the user drop a replacement image into
-- assets/stylegrounds/ and see it by reopening the panel, without restarting the editor.
function stylegroundPreview.clearImageCache()
    rawImages = {}
    rawSprites = {}
    placeholderSprite = nil
    folderCache = {}
    gifCache = {}

    -- Also reload the index, so edits to assets/stylegrounds/index.lua are picked up on reopen
    index = nil
    utils.unrequire(INDEX_MODULE)
end

function stylegroundPreview.isGif(path)
    return type(path) == "string" and path:lower():sub(-4) == ".gif"
end

-- Decodes a GIF into one love Image per frame. Frames are composed into full RGBA images by the
-- decoder; only the texture upload happens here. Returns nil when the file is not a usable GIF.
function stylegroundPreview.getGif(path)
    local cached = gifCache[path]

    if cached ~= nil then
        return cached or nil
    end

    local contents
    local success, result = pcall(love.filesystem.read, path)

    if success and result then
        contents = result

    else
        success, result = pcall(love.filesystem.read, "@ModsCommon@/" .. path:gsub("^/+", ""))

        if success and result then
            contents = result
        end
    end

    if not contents then
        logWarning("could not read GIF '" .. path .. "'")
        gifCache[path] = false

        return nil
    end

    local decoded, decodeError = gifDecoder.decode(contents)

    if not decoded then
        logWarning("could not decode GIF '" .. path .. "': " .. tostring(decodeError))
        gifCache[path] = false

        return nil
    end

    -- Keep the memory used by one preview reasonable: 96 MB of raw RGBA across all frames
    local frameCount = #decoded.frames
    local bytesPerFrame = decoded.width * decoded.height * 4

    if bytesPerFrame > 0 then
        frameCount = math.min(frameCount, math.max(1, math.floor(96 * 1024 * 1024 / bytesPerFrame)))
    end

    local frames = {}
    local delays = {}

    for frameIndex = 1, frameCount do
        local frame = decoded.frames[frameIndex]
        local ok, imageData = pcall(love.image.newImageData, decoded.width, decoded.height, "rgba8", frame.rgba)

        if not ok then
            break
        end

        local imageOk, image = pcall(love.graphics.newImage, imageData)

        imageData:release()

        if not imageOk then
            break
        end

        frames[frameIndex] = image
        delays[frameIndex] = math.max(frame.delay or 0, 0.02)
    end

    if #frames == 0 then
        logWarning("GIF '" .. path .. "' produced no usable frames")
        gifCache[path] = false

        return nil
    end

    local gif = {
        width = decoded.width,
        height = decoded.height,
        frames = frames,
        delays = delays
    }

    gifCache[path] = gif

    return gif
end

local function normalizePath(path)
    return (path:gsub("\\", "/"):gsub("/+", "/"))
end

local function stripPng(path)
    return (path:gsub("%.[Pp][Nn][Gg]$", ""))
end

local function joinPath(base, value)
    base = base or stylegroundPreview.DEFAULT_BASE_PATH
    value = value or ""

    if value:match("^[Gg]raphics/") or value:match("^assets/") then
        return normalizePath(value)
    end

    return normalizePath((base:gsub("/+$", "")) .. "/" .. (value:gsub("^/+", "")))
end

-- Splits "Graphics/Atlases/Gameplay/bgs/00/bg0" into the atlas name and the resource path used by
-- the atlas registry. Returns nil when the path is not an atlas path.
local function splitAtlasPath(path)
    local atlas, resource = path:match("^[Gg]raphics/[Aa]tlases/([^/]+)/(.+)$")

    if atlas and resource and resource ~= "" then
        return atlas, stripPng(resource)
    end
end

local function makeSprite(image)
    local width, height = image:getDimensions()

    return {
        image = image,
        quad = love.graphics.newQuad(0, 0, width, height, width, height),
        width = width,
        height = height,
        realWidth = width,
        realHeight = height,
        offsetX = 0,
        offsetY = 0
    }
end

-- Loads a file bundled with the editor (assets/...). Mod paths are tried through the shared mount
-- as a fallback, so an index entry may also point at a mod texture directly.
function stylegroundPreview.getRawImage(path)
    if type(path) ~= "string" or path == "" then
        return nil
    end

    local cached = rawImages[path]

    if cached ~= nil then
        return cached or nil
    end

    local image
    local success, result = pcall(love.graphics.newImage, path)

    if success then
        image = result

    else
        success, result = pcall(love.graphics.newImage, "@ModsCommon@/" .. path:gsub("^/+", ""))

        if success then
            image = result
        end
    end

    if not image then
        logWarning("could not load preview image '" .. path .. "'")
    end

    rawImages[path] = image or false

    return image
end

-- Used when assets/stylegrounds/placeholder.png is missing (for example in a packaged build that
-- predates the file): a small checkerboard keeps previews visible instead of silently empty.
local function makeFallbackPlaceholder()
    local size = 64
    local data = love.image.newImageData(size, size)

    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local light = (math.floor(x / 8) + math.floor(y / 8)) % 2 == 0
            local value = light and 0.24 or 0.16

            data:setPixel(x, y, value, value, value, 1)
        end
    end

    return love.graphics.newImage(data)
end

function stylegroundPreview.getPlaceholderSprite()
    if placeholderSprite ~= nil then
        return placeholderSprite or nil
    end

    placeholderSprite = stylegroundPreview.getImageSprite(stylegroundPreview.PLACEHOLDER) or false

    if not placeholderSprite then
        local image = makeFallbackPlaceholder()

        placeholderSprite = image and makeSprite(image) or false
    end

    return placeholderSprite or nil
end

-- Bundled image as a sprite meta, cached so hovering does not allocate a new quad every frame.
function stylegroundPreview.getImageSprite(path)
    local cached = rawSprites[path]

    if cached ~= nil then
        return cached or nil
    end

    if stylegroundPreview.isGif(path) then
        local gif = stylegroundPreview.getGif(path)

        if gif then
            local sprite = makeSprite(gif.frames[1])

            -- The window and the hover preview animate this; the sprite itself is the first frame
            sprite.animation = gif
            sprite.gifPath = path

            rawSprites[path] = sprite

            return sprite
        end

        rawSprites[path] = false

        return nil
    end

    local image = stylegroundPreview.getRawImage(path)
    local sprite = image and makeSprite(image) or false

    rawSprites[path] = sprite

    return sprite or nil
end

function stylegroundPreview.getIndex()
    if index ~= nil then
        return index
    end

    local success, result = utils.tryrequire(INDEX_MODULE, false)
    index = success and type(result) == "table" and result or {}

    return index
end

function stylegroundPreview.getEntry(effectName)
    if type(effectName) ~= "string" then
        return nil
    end

    local t = stylegroundPreview.getIndex()

    return t[effectName] or t["*"]
end

local function getTextureFromPath(path)
    local atlas, resource = splitAtlasPath(path)

    if atlas then
        return atlases.getResource(resource, atlas)
    end

    return stylegroundPreview.getImageSprite(path)
end

-- Resolves one attribute value (a texture path) against the configured base path.
function stylegroundPreview.getTexture(basePath, value)
    if type(value) ~= "string" then
        return nil
    end

    value = value:gsub("^%s+", ""):gsub("%s+$", "")

    if value == "" then
        return nil
    end

    return getTextureFromPath(joinPath(basePath, value))
end

local function textureKey(sprite)
    if not sprite or not sprite.quad or not sprite.image then
        return nil
    end

    local x, y, width, height = sprite.quad:getViewport()

    return table.concat({tostring(sprite.image), x, y, width, height}, ":")
end

local function appendUnique(list, seen, sprite, label)
    local key = textureKey(sprite)

    if sprite and key and not seen[key] then
        seen[key] = true
        table.insert(list, {sprite = sprite, label = label})
    end
end

local function sortResources(resources)
    table.sort(resources, function(a, b)
        local aNumber = tonumber(a:match("(%d+)$") or "")
        local bNumber = tonumber(b:match("(%d+)$") or "")

        if aNumber and bNumber and aNumber ~= bNumber then
            return aNumber < bNumber
        end

        return a < b
    end)
end

-- Lists direct image children of an atlas folder. Includes both the vanilla atlas and every mod
-- that contributes to the shared mod namespace.
function stylegroundPreview.listAtlasFolder(atlasName, folder)
    folder = (folder or ""):gsub("/+$", "")
    folder = folder:gsub("^/+", "")

    local cacheKey = atlasName .. "/" .. folder

    if folderCache[cacheKey] then
        return folderCache[cacheKey]
    end

    local resources = {}
    local seen = {}

    local function add(resource)
        resource = resource and stripPng(resource)

        if resource and resource ~= "" and not seen[resource] then
            seen[resource] = true
            table.insert(resources, resource)
        end
    end

    local atlas = rawget(atlases, atlasName)
    local vanilla = atlas and rawget(atlas, "__vanillaResources")

    if vanilla then
        local prefix = folder ~= "" and (folder .. "/") or ""
        local prefixLength = #prefix

        for resource in pairs(vanilla) do
            if resource:sub(1, prefixLength) == prefix then
                local rest = resource:sub(prefixLength + 1)

                if rest ~= "" and not rest:find("/", 1, true) then
                    add(resource)
                end
            end
        end
    end

    local directory = "@ModsCommon@/Graphics/Atlases/" .. atlasName .. "/" .. folder
    local names = virtualFs.list(directory)

    for _, name in ipairs(names or {}) do
        if name:match("%.[Pp][Nn][Gg]$") then
            add(folder ~= "" and (folder .. "/" .. name) or name)
        end
    end

    sortResources(resources)
    folderCache[cacheKey] = resources

    return resources
end

-- Enumerates the frames next to the given resource: trim the trailing number, then take every
-- sibling that shares the trimmed name.
function stylegroundPreview.getAnimationFrames(atlasName, resource)
    local directory, filename = resource:match("^(.*)/([^/]*)$")

    if not filename then
        directory, filename = "", resource
    end

    local stem = filename:gsub("%d+$", "")
    local frames = {}
    local all = stylegroundPreview.listAtlasFolder(atlasName, directory)

    for _, candidate in ipairs(all) do
        local candidateDirectory, candidateName = candidate:match("^(.*)/([^/]*)$")

        if not candidateName then
            candidateDirectory, candidateName = "", candidate
        end

        -- Compare trimmed names instead of requiring the original value to exist: the first frame
        -- is often named "star0" while the stored value is only the "star" prefix.
        if candidateDirectory == directory and candidateName:gsub("%d+$", "") == stem then
            table.insert(frames, candidate)
        end
    end

    if #frames == 0 then
        return {resource}
    end

    sortResources(frames)

    return frames
end

local function splitTextureList(value, separator)
    separator = type(separator) == "string" and separator or ","
    local list = {}

    for part in (value .. separator):gmatch("(.-)" .. separator:gsub("%p", "%%%0")) do
        part = part:gsub("^%s+", ""):gsub("%s+$", "")

        if part ~= "" then
            table.insert(list, part)
        end
    end

    return list
end

local function collectOtherTextures(config, data, list, seen, basePath)
    local kind = config.type or config.enum or "texture"
    local attribute = config.attribute

    if type(attribute) ~= "string" then
        return
    end

    local value = data and data[attribute]

    if value == nil then
        return
    end

    basePath = config.basePath or basePath

    if kind == "texture" then
        appendUnique(list, seen, stylegroundPreview.getTexture(basePath, value), tostring(value))

    elseif kind == "textureList" then
        if type(value) == "string" then
            for _, part in ipairs(splitTextureList(value, config.separator)) do
                appendUnique(list, seen, stylegroundPreview.getTexture(basePath, part), part)
            end
        end

    elseif kind == "animation" then
        if type(value) == "string" and value ~= "" then
            local path = joinPath(basePath, value)
            local atlasName, resource = splitAtlasPath(path)

            if atlasName then
                for _, frame in ipairs(stylegroundPreview.getAnimationFrames(atlasName, resource)) do
                    appendUnique(list, seen, atlases.getResource(frame, atlasName), frame)

                    if #list >= stylegroundPreview.MAX_TEXTURE_CELLS then
                        return
                    end
                end

            else
                appendUnique(list, seen, getTextureFromPath(stripPng(path)), value)
            end
        end

    elseif kind == "folder" then
        if type(value) == "string" and value ~= "" then
            local path = joinPath(basePath, value)
            local atlasName, folder = splitAtlasPath(path)

            if atlasName then
                for _, resource in ipairs(stylegroundPreview.listAtlasFolder(atlasName, folder)) do
                    appendUnique(list, seen, atlases.getResource(resource, atlasName), resource)

                    if #list >= stylegroundPreview.MAX_TEXTURE_CELLS then
                        return
                    end
                end
            end
        end
    end
end

local function normalizePreviewConfig(preview)
    if type(preview) == "string" then
        return {
            type = "image",
            image = preview
        }
    end

    if type(preview) ~= "table" then
        return {
            type = "image",
            image = stylegroundPreview.PLACEHOLDER
        }
    end

    return preview
end

-- "image" (default) or "attribute". Used by the window to decide whether the preview is a static
-- reference image or a live value read from the effect attributes.
function stylegroundPreview.getPreviewType(entry)
    local preview = normalizePreviewConfig(entry and entry.preview)

    return preview.type or "image"
end

-- Main preview box sprite: either a bundled image or a texture resolved from an effect attribute.
function stylegroundPreview.getPreviewSprite(entry, data)
    local preview = normalizePreviewConfig(entry and entry.preview)

    if preview.type == "attribute" then
        local value = preview.attribute and data and data[preview.attribute]

        if type(value) == "string" and value ~= "" then
            local sprite = stylegroundPreview.getTexture(preview.basePath, value)

            if sprite then
                return sprite
            end
        end

        return stylegroundPreview.getPlaceholderSprite()
    end

    local sprite = stylegroundPreview.getImageSprite(preview.image or stylegroundPreview.PLACEHOLDER)

    return sprite or stylegroundPreview.getPlaceholderSprite()
end

-- Extra texture cells shown to the right of the preview box.
-- Natural order for display: split digit runs so bg2 comes before bg10 instead of after it.
local function naturalCompare(a, b)
    local ai, bi = 1, 1

    while ai <= #a and bi <= #b do
        local aDigits = a:match("^%d+", ai)
        local bDigits = b:match("^%d+", bi)

        if aDigits and bDigits then
            local aNumber, bNumber = tonumber(aDigits), tonumber(bDigits)

            if aNumber ~= bNumber then
                return aNumber < bNumber
            end

            ai = ai + #aDigits
            bi = bi + #bDigits

        else
            local aChar, bChar = a:sub(ai, ai), b:sub(bi, bi)

            if aChar ~= bChar then
                return aChar < bChar
            end

            ai = ai + 1
            bi = bi + 1
        end
    end

    return (#a - ai) < (#b - bi)
end

function stylegroundPreview.getOtherTextures(entry, data)
    local list = {}
    local seen = {}

    for _, config in ipairs(entry and entry.otherTextures or {}) do
        collectOtherTextures(config, data, list, seen, nil)

        if #list >= stylegroundPreview.MAX_TEXTURE_CELLS then
            break
        end
    end

    table.sort(list, function(a, b)
        local aLabel = tostring(a.label or ""):match("^%s*(.-)%s*$")
        local bLabel = tostring(b.label or ""):match("^%s*(.-)%s*$")

        return naturalCompare(aLabel, bLabel)
    end)

    return list
end

-- Content for the floating hover preview of a styleground list row. Effect attributes can be
-- inherited from the parent apply group, so the caller passes the merged table.
local function spriteContent(sprite)
    return {
        image = sprite.image,
        quad = sprite.quad,
        layer = sprite.layer,
        width = sprite.width,
        height = sprite.height,
        -- GIF frames for the caller to animate; nil for static images
        animation = sprite.animation
    }
end

function stylegroundPreview.getHoverContent(style, data)
    local styleType = utils.typeof(style)

    if styleType == "effect" then
        local entry = stylegroundPreview.getEntry(style._name)
        local sprite

        -- An explicit hoverPreview wins over the panel preview. Useful when the panel preview is
        -- attribute-driven but the list hover should show a fixed reference image.
        if entry and entry.hoverPreview ~= nil then
            sprite = stylegroundPreview.getPreviewSprite({preview = entry.hoverPreview}, data or style)

            if sprite == stylegroundPreview.getPlaceholderSprite() then
                sprite = nil
            end
        end

        if not sprite then
            sprite = stylegroundPreview.getPreviewSprite(entry, data or style)
        end

        if not sprite then
            return nil
        end

        return spriteContent(sprite)

    elseif styleType == "parallax" then
        local texture = (data and data.texture) or style.texture

        if not texture then
            return nil
        end

        local sprite = atlases.getResource(texture)

        if not sprite then
            return nil
        end

        return spriteContent(sprite)
    end
end

return stylegroundPreview
