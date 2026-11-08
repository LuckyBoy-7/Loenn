-- Create Template Mod: creates a new mod folder with the standard XML files, dialog text, sample
-- images, an empty map and the map metadata already pointing at the new files.

local utils = require("utils")
local filesystem = require("utils.filesystem")
local fileLocations = require("file_locations")
local notifications = require("ui.notification")

local script = {}

script.name = "createTemplateMod"
script.title = "Create Template Mod"
script.description = "Creates a new mod folder with a blank map and the default Celeste XML files."

local ASSET_FOLDER = "assets/mod_template/"
local XML_FILES = {
    "AnimatedTiles.xml",
    "BackgroundTiles.xml",
    "ForegroundTiles.xml",
    "Portraits.xml",
    "Sprites.xml"
}

local fields = {"modName", "authorName", "mapName"}

local fieldInformation = {
    modName = {
        displayName = "Mod Name",
        tooltipText = "Letters, numbers and underscores only. Also used as the Mods folder name."
    },
    authorName = {
        displayName = "Author Name",
        tooltipText = "Letters, numbers and underscores only."
    },
    mapName = {
        displayName = "Map Name",
        tooltipText = "Letters, numbers and underscores only. Used for the map file and checkpoint."
    }
}

local function isValidName(name)
    return type(name) == "string" and name ~= "" and name:match("^[%w_]+$") ~= nil
end

local function ensureDirectory(path)
    filesystem.mkpath(path)
end

local function writeFile(path, content)
    ensureDirectory(filesystem.dirname(path))

    local handle = utils.getFileHandle(path, "wb")

    if not handle then
        return false
    end

    handle:write(content)
    handle:close()

    return true
end

local function readAsset(path)
    return utils.readAll(path, "rb", true)
end

local function copyAsset(assetName, target)
    local content = readAsset(ASSET_FOLDER .. assetName)

    if not content then
        return false
    end

    return writeFile(target, content)
end

local function templateRoomData(authorName, modName)
    return {
        __name = "level",
        __children = {
            {
                __name = "bg",
                innerText = "dddddddddddddddddddddddddddddddddddddddd\ndddddddddddddddddddddddddddddddddddddddd\n00dddddddddddddddddddddddddddddddddddddd\n00dddddddddddddddddddddddddddd00000ddddd\n00000ddddd0000dddddddddddd000000000ddddd\n00000ddddd0000ddd\n\n\n\n000000000000000000000000000000000000dddd\n000000000000000000000000000000000000dddd\n000000000000000000000000000000000000dddd\nddd00000000000000000000000000000dddddddd\nddd000000000dddd0000000000000000dddddddd\nddddddddddd0dddd0000000000000000dddddddd\nddddddddddd0dddd0000ddd000000000dddddddd\nddddddddddd0ddddddddddd00000dddddddddddd\nddddddddddd0ddddddddddd00000dddddd00dddd\nddddddddddd0ddddddddddd00000dddddd\nddddddddddd0ddddddddddd00000dddddd\n00ddddd00000dddd000000000000dddddd\n0000000000000000000000000000000ddd"
            },
            {
                __name = "fgtiles",
                innerText = ""
            },
            {
                __name = "objtiles",
                innerText = ""
            },
            {
                __name = "solids",
                innerText = "\n\n\n\n\n\n\n\n\n\n\n0000000000000000000000000000000000000033\n0000000000000000000000000000000000000033\n0000000000000000000000000000000000000033\n0000000000000000000000000000000000001111\n0000000333333300000000333333000003331111\n0000011113333300000000333333000003331111\n1111111113333301111110333333000111133333\n1111111113333301111113333333330111133333\n1111111113333331111113333333330111133333\n1111111113333331111113333333333111133333\n1111133333333331111113333333333111133333\n3333333333333333333333333333333333333333"
            },
            {
                __name = "bgtiles",
                innerText = ""
            },
            {
                __name = "entities",
                __children = {
                    {
                        __name = "player",
                        id = 1652,
                        isDefaultSpawn = false,
                        x = 95,
                        y = 120
                    },
                    {
                        __name = "blackGem",
                        fake = false,
                        fakeHeartDialog = "CH9_FAKE_HEART",
                        id = 1653,
                        keepGoingDialog = "CH9_KEEP_GOING",
                        removeCameraTriggers = false,
                        x = 208,
                        y = 56
                    },
                    {
                        __name = "XaphanHelper/CustomEndScreenController",
                        atlas = "EndScreens/" .. authorName .. "/" .. modName,
                        hideVanillaTimer = false,
                        id = 0,
                        images = "end_screen",
                        itemPercentColor = "FFFFFF",
                        itemPercentMaxColor = "FFD700",
                        mapPercentColor = "FFFFFF",
                        mapPercentMaxColor = "FFD700",
                        music = "",
                        priority = 0,
                        requiredFlags = "",
                        requiredItemPercent = 0,
                        requiredMapPercent = 0,
                        requiredStrawberries = 0,
                        requiredTime = 0,
                        requirementsCheck = "Chapter",
                        showItemPercent = false,
                        showMapPercent = false,
                        showStrawberries = false,
                        showTime = false,
                        showTitle = true,
                        strawberriesColor = "FFFFFF",
                        strawberriesMaxColor = "FFD700",
                        subText1 = "",
                        subText1Color = "FFFFFF",
                        subText2 = "",
                        subText2Color = "FFFFFF",
                        title = "",
                        x = 136,
                        y = 40
                    }
                }
            }
        },
        alt_music = "",
        ambience = "",
        ambienceProgress = "",
        c = 0,
        cameraOffsetX = 0,
        cameraOffsetY = 0,
        dark = false,
        delayAltMusicFade = false,
        disableDownTransition = false,
        height = 184,
        music = "",
        musicLayer1 = true,
        musicLayer2 = true,
        musicLayer3 = true,
        musicLayer4 = true,
        musicProgress = "",
        name = "A_01",
        space = false,
        underwater = false,
        whisper = false,
        width = 320,
        windPattern = "None",
        x = -2096,
        y = 5168
    }
end

local function encodeBlankMap(path, mapName, authorName, modName)
    local mapStruct = require("structs.map")
    local roomStruct = require("structs.room")
    local sideStruct = require("structs.side")
    local mapcoder = require("mapcoder")

    local side = {
        _type = "side",
        map = mapStruct.decode({})
    }

    side.map.package = ""
    side.map.rooms = {roomStruct.decode(templateRoomData(authorName, modName))}
    -- Like File -> New, only write the metadata that is actually needed. The metadata window
    -- merges the defaults when it is opened, and empty strings here would be invalid enum values
    -- for the game (e.g. CoreMode = "" throws while parsing MapMeta)
    side.meta = {
        AnimatedTiles = "Graphics/" .. authorName .. "/" .. modName .. "/AnimatedTiles.xml",
        BackgroundTiles = "Graphics/" .. authorName .. "/" .. modName .. "/BackgroundTiles.xml",
        ForegroundTiles = "Graphics/" .. authorName .. "/" .. modName .. "/ForegroundTiles.xml",
        Portraits = "Graphics/" .. authorName .. "/" .. modName .. "/Portraits.xml",
        Sprites = "Graphics/" .. authorName .. "/" .. modName .. "/Sprites.xml",
        Icon = "areas/" .. authorName .. "/" .. modName .. "/city",
        mode = {
            StartLevel = "A_01",
            HeartIsEnd = true
        }
    }

    local encoded = coroutine.create(function()
        local encodedData = sideStruct.encode(side)

        mapcoder.encodeFile(path, encodedData)
    end)
    local success, reason = coroutine.resume(encoded)

    while success and coroutine.status(encoded) ~= "dead" do
        success, reason = coroutine.resume(encoded)
    end

    return success, reason
end

local function createTemplate(values, options)
    options = options or {}

    local modName = utils.trim(values.modName or "")
    local authorName = utils.trim(values.authorName or "")
    local mapName = utils.trim(values.mapName or "")

    if not isValidName(modName) or not isValidName(authorName) or not isValidName(mapName) then
        notifications.notify("Create Template Mod: names may only contain letters, numbers and underscores.")

        return false
    end

    local modsDirectory = options.baseDirectory or utils.joinpath(fileLocations.getCelesteDir(), "Mods")
    local modFolder = utils.joinpath(modsDirectory, modName)

    if filesystem.pathAttributes(modFolder) then
        notifications.notify(string.format("Create Template Mod: '%s' already exists in the Mods folder.", modName))

        return false
    end

    ensureDirectory(modFolder)

    -- everest.yaml
    local yamlContent = string.format(
        "- Name: %s\n  Version: 1.0.0\n  Dependencies:\n    - Name: Everest\n      Version: 1.5577.0\n    - Name: XaphanHelper\n      Version: 1.0.79\n",
        modName)

    if not writeFile(utils.joinpath(modFolder, "everest.yaml"), yamlContent) then
        notifications.notify("Create Template Mod: could not create everest.yaml.")

        return false
    end

    -- Dialog files
    local english = string.format(
        "%s_%s_%s= This is my map\n%s_%s= This is my Mod\npoem_%s_%s_%s_A= Heart Epilogue\n",
        authorName, modName, mapName, authorName, modName, authorName, modName, mapName)
    local chinese = string.format(
        "%s_%s_%s= 这是我的地图\n%s_%s= 这是我的 Mod\npoem_%s_%s_%s_A= 吃心结语\n",
        authorName, modName, mapName, authorName, modName, authorName, modName, mapName)

    writeFile(utils.joinpath(modFolder, "Dialog", "English.txt"), english)
    writeFile(utils.joinpath(modFolder, "Dialog", "Simplified Chinese.txt"), chinese)

    -- XML files
    local graphicsFolder = utils.joinpath(modFolder, "Graphics", authorName, modName)

    for _, xmlFile in ipairs(XML_FILES) do
        copyAsset("official_xmls/" .. xmlFile, utils.joinpath(graphicsFolder, xmlFile))
    end

    -- Checkpoint + area samples
    local checkpointFolder = utils.joinpath(modFolder, "Graphics", "Atlases", "Checkpoints",
        authorName, modName, mapName, "A")

    copyAsset("start.png", utils.joinpath(checkpointFolder, "start.png"))

    local areasFolder = utils.joinpath(modFolder, "Graphics", "Atlases", "Gui", "areas", authorName, modName)

    copyAsset("city.png", utils.joinpath(areasFolder, "city.png"))
    copyAsset("city_back.png", utils.joinpath(areasFolder, "city_back.png"))

    local endScreensFolder = utils.joinpath(modFolder, "Graphics", "Atlases", "EndScreens", authorName, modName)

    copyAsset("end_screen.png", utils.joinpath(endScreensFolder, "end_screen.png"))

    -- Empty map
    local mapPath = utils.joinpath(modFolder, "Maps", authorName, modName, mapName .. ".bin")
    ensureDirectory(filesystem.dirname(mapPath))

    local encoded, encodeReason = encodeBlankMap(mapPath, mapName, authorName, modName)

    if not encoded then
        notifications.notify(string.format("Create Template Mod: could not create the map file (%s).",
            tostring(encodeReason)))

        return false
    end

    -- Make the new mod's assets visible to the editor, then open the map
    if options.openMap ~= false then
        local mods = require("mods")
        mods.mountMod(modFolder, true)

        -- The atlases were loaded at startup: reload them so the new area icon and checkpoints
        -- from this mod can be found
        local success, debugUtils = pcall(require, "debug_utils")

        if success then
            debugUtils.redrawMap()
        end

        require("ui").runLate(function()
            local loadedState = require("loaded_state")

            loadedState.loadFile(mapPath, nil, function()
                -- Save once after the map is loaded, so the file on disk is already the same
                -- cleaned-up map the editor is showing
                loadedState.saveFile(loadedState.filename, nil, false, nil, false)
            end)
        end)
    end

    notifications.notify(string.format("Create Template Mod: created '%s'.", modName))

    return true
end

-- Also usable by tests/other tools; options.baseDirectory and options.openMap are optional
script.create = createTemplate

function script.open()
    local scriptsPanel = require("ui.windows.scripts_panel")

    local panelScript = {
        name = script.name .. "Panel",
        title = script.title,
        fieldOrder = fields,
        defaultData = {
            modName = "YourModName",
            authorName = "YourName",
            mapName = "Map"
        },
        fieldInformation = fieldInformation
    }

    scriptsPanel.open(panelScript, nil, function(values)
        return createTemplate(values)
    end, {
        runButtonText = "Create",
        extraButtons = {
            {
                text = "Close Window",
                callback = function()
                    scriptsPanel.close()
                end
            }
        }
    })
end

return script
