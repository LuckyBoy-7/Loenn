-- "Add Defaults": copies the tilesets of every other mod (and the pack bundled with Loenn) into
-- the mod the current map belongs to, writes the rules into the map's tileset XML and keeps track
-- of where every tileset came from.
--
-- Used by the tile material list of the tools window (see ui/windows/tools.lua).

local utils = require("utils")
local filesystem = require("utils.filesystem")
local fileLocations = require("file_locations")
local modHandler = require("mods")
local virtualFs = require("virtual_fs")
local loadedState = require("loaded_state")
local notifications = require("ui.notification")
local languageRegistry = require("language_registry")
local logging = require("logging")
local celesteRender = require("celeste_render")

local tilesetDefaults = {}

-- Bundled default pack, built by bench/build_tileset_pack.py
tilesetDefaults.packRoot = "assets/tile_pack"

-- Where the images and rules are written inside the target mod
tilesetDefaults.imageFolder = "Graphics/Atlases/Gameplay/tilesets/Loenn"
tilesetDefaults.ruleFolder = "Graphics/Loenn"

-- Foreground and background tilesets must not share an image folder: Only Keep Used on the
-- background layer would otherwise delete foreground images that its own XML does not reference.
function tilesetDefaults.getImageSubFolder(layer)
    return layer == "tilesBg" and "Background" or "Foreground"
end

function tilesetDefaults.getImageFolder(layer)
    return utils.joinpath(tilesetDefaults.imageFolder, tilesetDefaults.getImageSubFolder(layer))
end

function tilesetDefaults.getImageRelativeFolder(layer)
    return "Loenn/" .. tilesetDefaults.getImageSubFolder(layer)
end

-- Single character ids for the new tilesets. Chinese characters are used because mods already
-- use most of the ascii alphabet for their own ids.
local idPool =
    "天地玄黄宇宙洪荒日月盈昃辰宿列张寒来暑往秋收冬藏闰余成岁律吕调阳云腾致雨露结为霜金生丽水玉出昆冈剑号巨阙珠称夜光果珍李柰菜重芥姜海咸河淡鳞潜羽翔龙师火帝鸟官人皇始制文字乃服衣裳推位让国有虞陶唐吊民伐罪周发殷汤坐朝问道垂拱平章爱育黎首臣伏戎羌遐迩一体率宾归王鸣凤在竹白驹食场化被草木赖及万方"

-- Tileset ids have to be a single character, but any character works: ASCII first (some mods
-- already use a few), then the whole CJK block. XML special characters are left out on purpose,
-- they would have to be escaped in the id.
local asciiIdPool =
    "0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ!@#$%^*()[]{}?.,;:~|"

local function encodeUtf8(codePoint)
    if codePoint < 0x80 then
        return string.char(codePoint)
    end

    if codePoint < 0x800 then
        return string.char(0xC0 + math.floor(codePoint / 0x40), 0x80 + codePoint % 0x40)
    end

    return string.char(
        0xE0 + math.floor(codePoint / 0x1000),
        0x80 + math.floor(codePoint / 0x40) % 0x40,
        0x80 + codePoint % 0x40
    )
end

-- Flat candidate list, built once
local idCandidates

local function getIdCandidates()
    if idCandidates then
        return idCandidates
    end

    idCandidates = {}

    -- Hand picked characters first, so early ids stay readable
    local index = 1

    while index <= #idPool - 2 do
        local character = string.sub(idPool, index, index + 2)

        if #character == 3 then
            table.insert(idCandidates, character)
        end

        index = index + 3
    end

    -- The whole CJK block before the ASCII pool: vanilla tilesets use single ASCII characters,
    -- so an ASCII id would shadow a vanilla tileset and make it impossible to tell them apart
    -- (the map only stores the id). CJK ids are only exhausted after about 20k tilesets.
    for codePoint = 0x4E00, 0x9FFF do
        table.insert(idCandidates, encodeUtf8(codePoint))
    end

    for position = 1, #asciiIdPool do
        table.insert(idCandidates, string.sub(asciiIdPool, position, position))
    end

    return idCandidates
end

local pack

local function getPack()
    if pack == nil then
        local success, loaded = utils.tryrequire("assets/tile_pack/index")

        logging.info(string.format("[tileset-defaults] pack load: %s (%s)", tostring(success), tostring(loaded)))

        pack = success and loaded or false
    end

    return pack or {}
end

local templateCache = {}

-- Content of the tracked templates (the <set> children only)
function tilesetDefaults.getTemplateBody(name)
    if templateCache[name] ~= nil then
        return templateCache[name] or nil
    end

    local text = utils.readAll(tilesetDefaults.packRoot .. "/templates/" .. name .. ".xml")

    if not text then
        templateCache[name] = false

        return nil
    end

    local body = string.match(text, "<Tileset[^>]*>(.-)</Tileset>")

    templateCache[name] = body or false

    return body
end

-- ---------------------------------------------------------------------------
-- XML helpers
-- ---------------------------------------------------------------------------

local function parseTilesets(text)
    local entries = {}
    local lowered = string.lower(text or "")
    local position = 1

    while true do
        local tagStart = string.find(lowered, "<tileset", position, true)

        if not tagStart then
            break
        end

        local tagEnd = string.find(text, ">", tagStart, true)

        if not tagEnd then
            break
        end

        local attributes = string.sub(text, tagStart + 8, tagEnd - 1)
        local selfClosing = string.sub(text, tagEnd - 1, tagEnd - 1) == "/"
        local body = ""

        position = tagEnd + 1

        if not selfClosing then
            local closeStart = string.find(lowered, "</tileset", tagEnd, true)

            if closeStart then
                body = string.sub(text, tagEnd + 1, closeStart - 1)
                position = closeStart + 9
            end
        end

        local id = string.match(attributes, 'id%s*=%s*"([^"]*)"')
        local path = string.match(attributes, 'path%s*=%s*"([^"]*)"')
        local copy = string.match(attributes, 'copy%s*=%s*"([^"]*)"')
        local scanWidth = string.match(attributes, 'scanWidth%s*=%s*"([^"]*)"')
        local scanHeight = string.match(attributes, 'scanHeight%s*=%s*"([^"]*)"')

        if id or path then
            table.insert(entries, {
                id = id,
                path = path,
                copy = copy,
                scanWidth = scanWidth,
                scanHeight = scanHeight,
                body = body
            })
        end
    end

    return entries
end

-- Raw <Tileset> blocks of a file, used to carry the vanilla definitions over into a mods file
local function extractTilesetBlocks(text)
    local blocks = {}
    local lines = {}

    for line in string.gmatch((text or "") .. "\n", "([^\n]*)\n") do
        table.insert(lines, line)
    end

    local index = 1

    while index <= #lines do
        if string.match(lines[index], "^%s*<[Tt]ileset") then
            local block = {lines[index]}

            if not string.match(lines[index], "/>%s*$") then
                index = index + 1

                while index <= #lines do
                    table.insert(block, lines[index])

                    if string.find(string.lower(lines[index]), "</tileset", 1, true) then
                        break
                    end

                    index = index + 1
                end
            end

            local id = string.match(block[1], 'id%s*=%s*"([^"]*)"')

            if id then
                table.insert(blocks, {id = id, text = table.concat(block, "\n")})
            end
        end

        index = index + 1
    end

    return blocks
end

local function getTilesetIds(text)
    local ids = {}

    for id in string.gmatch(text or "", 'id%s*=%s*"([^"]*)"') do
        ids[id] = true    end

    return ids
end

local function nextId(usedIds)
    for _, character in ipairs(getIdCandidates()) do
        local length = #character

        if (length == 3 or length == 1) and not usedIds[character] then
            return character
        end
    end
end

-- ---------------------------------------------------------------------------
-- Target mod
-- ---------------------------------------------------------------------------

-- Returns the real folder of the mod the current map belongs to, or nil and a reason
function tilesetDefaults.getMapModFolder()
    local filename = loadedState.filename

    if not filename then
        return nil, "noMap"
    end

    local celesteModsDir = utils.joinpath(fileLocations.getCelesteDir(), "Mods")
    local unixFilename = utils.convertToUnixPath(filename)
    local unixModsDir = utils.convertToUnixPath(celesteModsDir)

    if not utils.startsWith(unixFilename, unixModsDir .. "/") then
        return nil, "notInMods"
    end

    local relative = string.sub(unixFilename, #unixModsDir + 2)
    local modName = string.match(relative, "^([^/]+)/")

    if not modName then
        return nil, "notInMod"
    end

    local modFolder = utils.joinpath(celesteModsDir, modName)
    local attributes = filesystem.pathAttributes(modFolder)

    if not attributes then
        return nil, "modFolderMissing"
    end

    if attributes.mode ~= "directory" then
        return nil, "packedMod"
    end

    return modFolder, modName
end

-- The same message must not be pushed twice in a row (e.g. two runs of the same action)
local lastMessage
local lastMessageTime = 0

local function notifyMessage(key, ...)
    local text = languageRegistry.getLanguage().ui.notifications[key]
    local message = string.format(tostring(text), ...)
    local now = love.timer.getTime()

    if message == lastMessage and now - lastMessageTime < 2 then
        return
    end

    lastMessage = message
    lastMessageTime = now

    notifications.notify(message)
end

-- ---------------------------------------------------------------------------
-- Collecting tilesets
-- ---------------------------------------------------------------------------

-- mask -> first tile coordinate of a tileset body, used to recognise the known templates
local function getMaskTiles(body)
    local result = {}

    for mask, tiles in string.gmatch(body or "", 'mask%s*=%s*"([^"]*)"%s*tiles%s*=%s*"([^"]*)"') do
        local first = string.match(tiles, "^%s*([^;]-)%s*;") or tiles
        local x, y = string.match(first, "(%d+)%s*,%s*(%d+)")

        if x then
            result[mask] = {x = tonumber(x), y = tonumber(y)}
        end
    end

    return result
end

local templateTiles

local function getTemplateTiles()
    if templateTiles then
        return templateTiles
    end

    templateTiles = {}

    for _, name in ipairs({"z", "y", "spoooky"}) do
        local body = tilesetDefaults.getTemplateBody(name)

        if body then
            templateTiles[name] = getMaskTiles(body)
        end
    end

    return templateTiles
end

-- Returns the template name when the body is exactly one of the known templates
function tilesetDefaults.classifyBody(body)
    local candidate = getMaskTiles(body)

    if next(candidate) == nil then
        return nil
    end

    for _, name in ipairs({"z", "y", "spoooky"}) do
        local template = getTemplateTiles()[name]

        if template then
            local matches = true

            for mask, tile in pairs(candidate) do
                local expected = template[mask]

                if not expected or expected.x ~= tile.x or expected.y ~= tile.y then
                    matches = false

                    break
                end
            end

            if matches then
                return name
            end
        end
    end
end

-- Every tileset of every mod that has both rules and an image
function tilesetDefaults.collectFromMods(backgroundOnly)
    local candidates = {}
    local xmlCount, entriesCount, imageCount = 0, 0, 0
    local modsCount, filesCount, xmlNames = 0, 0, 0
    local readFail, noTag = 0, 0

    local zBody = tilesetDefaults.getTemplateBody("z")
    local yBody = tilesetDefaults.getTemplateBody("y")

    for modFolderName in pairs(modHandler.loadedMods) do
        local filenames = modHandler.getOrCacheFilenames(modFolderName) or {}
        local fileLookup = {}

        modsCount = modsCount + 1
        filesCount = filesCount + #filenames

        for _, filename in ipairs(filenames) do
            fileLookup[string.lower(filename)] = true

            if string.sub(string.lower(filename), -4) == ".xml" then
                xmlNames = xmlNames + 1
            end
        end

        -- First pass: every tileset of this mod, so "copy=" can be followed across files
        local parsedFiles = {}
        local modById = {}

        for _, filename in ipairs(filenames) do
            local lowered = string.lower(filename)

            if string.sub(lowered, -4) == ".xml" then
                local text = utils.readAll(filename, "rb", true)

                if not text then
                    readFail = readFail + 1

                elseif not string.find(string.lower(text), "<tileset", 1, true) then
                    noTag = noTag + 1

                else
                    local isBackground = string.find(lowered, "background", 1, true) ~= nil

                    if isBackground == backgroundOnly then
                        local entries = parseTilesets(text)

                        xmlCount = xmlCount + 1
                        entriesCount = entriesCount + #entries

                        table.insert(parsedFiles, {filename = filename, entries = entries})

                        for _, entry in ipairs(entries) do
                            if entry.id then
                                modById[entry.id] = entry
                            end
                        end
                    end
                end
            end
        end

        -- Second pass: resolve the rules and check that the image is there
        local function resolveBody(entry)
            local body = entry.body and entry.body ~= "" and entry.body or nil
            local copyId = entry.copy
            local seen = {}

            while not body and copyId and not seen[copyId] do
                seen[copyId] = true

                local source = modById[copyId]

                if source then
                    body = source.body and source.body ~= "" and source.body or nil
                    copyId = source.copy

                elseif copyId == "z" then
                    body = zBody
                    break

                elseif copyId == "y" then
                    body = yBody
                    break

                else
                    break
                end
            end

            return body
        end

        for _, parsed in ipairs(parsedFiles) do
            local modName = string.match(parsed.filename, "^%$([^%$]+)%$/") or ""

            for _, entry in ipairs(parsed.entries) do
                if entry.path then
                    local imageSuffix = "/graphics/atlases/gameplay/tilesets/" .. string.lower(entry.path) .. ".png"
                    local imagePath = "$" .. modName .. "$/Graphics/Atlases/Gameplay/tilesets/" .. entry.path .. ".png"

                    if fileLookup["$" .. string.lower(modName) .. "$" .. imageSuffix] then
                        imageCount = imageCount + 1

                        local body = resolveBody(entry)
                        local template = body and tilesetDefaults.classifyBody(body)

                        -- Only the three well known templates are used
                        if template then
                            table.insert(candidates, {
                                mod = modName,
                                xml = parsed.filename,
                                id = entry.id,
                                name = filesystem.filename(entry.path, "/"),
                                path = entry.path,
                                image = imagePath,
                                body = body,
                                template = template,
                                copy = entry.copy,
                                scanWidth = entry.scanWidth
                                    or (entry.copy and modById[entry.copy] and modById[entry.copy].scanWidth),
                                scanHeight = entry.scanHeight
                                    or (entry.copy and modById[entry.copy] and modById[entry.copy].scanHeight),
                                source = string.format("%s (%s)", modName, entry.path)
                            })
                        end
                    end
                end
            end
        end
    end

    logging.info(string.format("[tsd-scan] mods=%d files=%d xmlNames=%d readFail=%d noTag=%d xml=%d entries=%d images=%d candidates=%d",
        modsCount, filesCount, xmlNames, readFail, noTag, xmlCount, entriesCount, imageCount, #candidates))

    return candidates
end

local function getModDisplayName(modFolderName)
    if not modFolderName then
        return nil
    end

    local info = modHandler.loadedMods and modHandler.loadedMods[modFolderName]
    local metadata = info and info.metadata

    if not metadata then
        metadata = modHandler.modMetadata and modHandler.modMetadata[modFolderName]
    end

    if metadata then
        local names = modHandler.getModNamesFromMetadata(metadata)

        if names and names[1] then
            return names[1]
        end
    end

    return nil
end

function tilesetDefaults.collectFromPack(backgroundOnly)
    local candidates = {}

    for _, entry in ipairs(getPack()) do
        if (entry.background == true) == backgroundOnly then
            local body = entry.body

            if not body then
                local template = entry.template

                if template == "y" or template == "z" or template == "spoooky" then
                    body = tilesetDefaults.getTemplateBody(template)
                end
            end

            local source = "Loenn defaults"
            local sourceGroup = "celeste"

            if entry.sources and entry.sources[1] then
                local modFolderName = entry.sources[1].mod or ""
                local displayName = getModDisplayName(modFolderName) or modFolderName

                -- The readable mod name is recorded (and later used for grouping), not the
                -- archive folder name
                source = string.format("%s (%s)", displayName, entry.sources[1].xml)
                sourceGroup = string.lower(displayName)
            end

            -- Entries are filtered by file name when they are written: an entry whose name is
            -- already in the rule file is skipped there, so offering all of them here is correct
            table.insert(candidates, {
                mod = "Loenn",
                id = entry.hash,
                name = entry.name or (entry.path and filesystem.filename(entry.path, "/")),
                path = entry.path or entry.file,
                image = tilesetDefaults.packRoot .. "/" .. entry.file,
                body = body,
                template = entry.template,
                sound = entry.sound,
                ignores = entry.ignores,
                scanWidth = entry.scanWidth,
                scanHeight = entry.scanHeight,
                source = source,
                sourceGroup = sourceGroup
            })
        end
    end

    return candidates
end

-- ---------------------------------------------------------------------------
-- Writing
-- ---------------------------------------------------------------------------

local function readTargetFile(path)
    -- utils.readAll falls back to io.open, which changes into the file's directory and throws
    -- for paths that do not exist yet, so check first
    if not filesystem.pathAttributes(path) then
        return nil
    end

    return utils.readAll(path, "rb", false)
end

local function writeTargetFile(path, content)
    filesystem.mkpath(filesystem.dirname(path))

    local handle = utils.getFileHandle(path, "wb")

    if not handle then
        return false
    end

    handle:write(content)
    handle:close()

    return true
end

local function fileExists(path)
    local attributes = filesystem.pathAttributes(path)

    return attributes ~= nil and attributes.mode ~= "directory"
end

-- Copies the image into the target mod, returns the tileset path (relative to tilesets/) or nil
local function copyImage(candidate, modFolder, usedNames, layer)
    local resolved = virtualFs.resolve(candidate.image) or candidate.image
    local imageBytes = utils.readAll(resolved, "rb", true)

    if not imageBytes then
        return nil
    end

    local baseName = candidate.name or filesystem.filename(candidate.path or "", "/")
    baseName = string.gsub(baseName, "%.png$", "")
    baseName = string.gsub(baseName, "[^%w_%-%.]", "_")

    if baseName == "" then
        baseName = "tileset"
    end

    local name = baseName
    local index = 2
    local relativeFolder = tilesetDefaults.getImageRelativeFolder(layer)

    while true do
        local relative = relativeFolder .. "/" .. name .. ".png"
        local target = utils.joinpath(modFolder, tilesetDefaults.getImageFolder(layer), name .. ".png")

        if usedNames[relative] then
            name = string.format("%s_%d", baseName, index)
            index = index + 1

        elseif fileExists(target) then
            local existing = readTargetFile(target)

            if existing == imageBytes then
                usedNames[relative] = true

                return relative
            end

            name = string.format("%s_%d", baseName, index)
            index = index + 1

        else
            usedNames[relative] = true

            if tilesetDefaults.dryRun then
                return relative
            end

            if writeTargetFile(target, imageBytes) then
                return relative
            end

            return nil
        end
    end
end

local function getRuleFile(modFolder, layer)
    local metaKey = layer == "tilesBg" and "BackgroundTiles" or "ForegroundTiles"
    local meta = loadedState.side and loadedState.side.meta
    local configured = meta and meta[metaKey]

    -- Map metadata strings may carry trailing control characters (the binary stores a null
    -- terminated string)
    if type(configured) == "string" then
        configured = string.gsub(configured, "%c", "")
        configured = string.match(configured, "^(.-%.xml)") or configured
    end

    -- The generated rule file lives next to the mod's own graphics, in a folder named after the
    -- mod itself (the mod folder name is the one under Celeste/Mods)
    -- The folder name only: modFolder is a native path, so it has to be converted first or
    -- filename() would treat the whole path as one name
    local modFolderName = filesystem.filename(utils.convertToUnixPath(modFolder), "/")
    local ruleName = layer == "tilesBg" and "Backgrounds.xml" or "Foregrounds.xml"
    local defaultRelative = "Graphics/" .. modFolderName .. "/" .. ruleName

    if configured == nil or configured == "" then
        return utils.joinpath(modFolder, defaultRelative), defaultRelative, metaKey, true
    end

    -- Extra parentheses: convertToUnixPath also returns the substitution count, and a call in
    -- tail position would pass it as a third path part
    local fullPath = utils.joinpath(modFolder, (utils.convertToUnixPath(configured)))
    local text = readTargetFile(fullPath)

    if not text then
        logging.info(string.format("[tileset-defaults] rule file missing: meta=%q path=%q", configured, fullPath))

        return nil, configured, metaKey, false, "missing"
    end

    if not string.find(text, "<Data", 1, true) then
        return nil, configured, metaKey, false, "invalid"
    end

    return fullPath, configured, metaKey, false
end

function tilesetDefaults.addDefaults(layer, onDone, targetFolder)
    layer = layer or "tilesFg"

    local modFolder, modName = tilesetDefaults.getMapModFolder()

    -- Optional target folder (tests pass a temporary folder here)
    if targetFolder then
        modFolder, modName = targetFolder, "Target"
    end

    if not modFolder then
        notifyMessage("tilesetDefaultsInvalidMod")

        return false, modName
    end

    local rulePath, ruleRelative, metaKey, created, problem = getRuleFile(modFolder, layer)

    if not rulePath then
        notifyMessage("tilesetDefaultsInvalidXml", tostring(ruleRelative), tostring(problem))

        return false, problem
    end

    local xmlText = readTargetFile(rulePath)

    if not xmlText then
        -- The map now points at its own file: start from the vanilla definitions, otherwise the
        -- vanilla tilesets would be replaced by our file instead of being extended
        local vanillaName = layer == "tilesBg" and "BackgroundTiles.xml" or "ForegroundTiles.xml"
        local vanillaPath = utils.joinpath(fileLocations.getCelesteDir(), "Content", "Graphics", vanillaName)

        xmlText = readTargetFile(vanillaPath) or "<Data>\n</Data>\n"

        created = true
    end

    -- Top up the vanilla definitions. An earlier version created rule files that only contained
    -- the imported tilesets, which silently replaced the vanilla ones: add every vanilla tileset
    -- the file does not define yet.
    local vanillaNameForText = layer == "tilesBg" and "BackgroundTiles.xml" or "ForegroundTiles.xml"
    local vanillaPathForText = utils.joinpath(fileLocations.getCelesteDir(), "Content", "Graphics", vanillaNameForText)
    local vanillaText = readTargetFile(vanillaPathForText)

    if vanillaText then
        local existingIds = getTilesetIds(xmlText)
        local missingBlocks = {}

        for _, block in ipairs(extractTilesetBlocks(vanillaText)) do
            if not existingIds[block.id] then
                table.insert(missingBlocks, block.text)
            end
        end

        if #missingBlocks > 0 then
            local insertAt = string.find(xmlText, "</Data>", 1, true)

            if insertAt then
                xmlText = string.sub(xmlText, 1, insertAt - 1) .. table.concat(missingBlocks, "\n") .. "\n" .. string.sub(xmlText, insertAt)
            end
        end
    end

    -- Ids that are already taken by the file itself (and by the entries written in this run,
    -- see below). Nothing else is pre-recorded: a new id only has to be unique in the file it is
    -- appended to.
    local usedIds = getTilesetIds(xmlText)
    local usedNames = {}
    local vanillaMeta = layer == "tilesBg" and celesteRender.tilesMetaBgVanilla or celesteRender.tilesMetaFgVanilla

    -- Keep track of tilesets that are already part of the target file
    local existingPaths = {}

    for _, entry in ipairs(parseTilesets(xmlText)) do
        if entry.path then
            existingPaths[entry.path] = true
        end
    end

    local backgroundOnly = layer == "tilesBg"

    -- Only the bundled pack is added: scanning every mod on click was slow and pulled in a lot of
    -- near duplicates. The pack itself was built from the mods and is deduplicated already.
    local candidates = tilesetDefaults.collectFromPack(backgroundOnly)

    -- Image names the rule file already refers to: those tilesets must not be added again
    local existingNames = {}

    for _, entry in ipairs(parseTilesets(xmlText)) do
        if entry.path then
            local entryName = string.lower(string.gsub(filesystem.filename(entry.path, "/"), "%.png$", ""))

            existingNames[entryName] = true
        end
    end

    local added = 0
    local skipped = 0
    local blocks = {}
    local addedNames = {}
    local copiedImages = {}

    -- Rule sets that were already written once: later tilesets with the same rules only store
    -- copy="<id of the first one>", which keeps the file small
    local copyBases = {}

    -- Preferred material packs come first in the list grouping
    local groupPriority = {celeste = 0, spoooky = 1, underdragon = 2}

    local function getSourceGroup(candidate)
        local group = string.lower(candidate.sourceGroup or "celeste")

        -- Folder names come with archive suffixes and sometimes a hash postfix
        group = string.gsub(group, "%.zip$", "")
        group = string.gsub(group, "_zip$", "")
        group = string.gsub(group, "_%x+$", "")
        group = string.gsub(group, "_%x+$", "")
        group = string.gsub(group, "%s+", "")

        if string.match(group, "spoo+ky") then
            return "spoooky"

        elseif string.find(group, "underdragon", 1, true) then
            return "underdragon"

        elseif group == "" or string.find(group, "celeste", 1, true) then
            return "celeste"
        end

        return group
    end

    table.sort(candidates, function(lhs, rhs)
        local lhsGroup = getSourceGroup(lhs)
        local rhsGroup = getSourceGroup(rhs)
        local lhsPriority = groupPriority[lhsGroup] or 100
        local rhsPriority = groupPriority[rhsGroup] or 100

        if lhsPriority ~= rhsPriority then
            return lhsPriority < rhsPriority
        end

        return tostring(lhs.name) < tostring(rhs.name)
    end)

    for _, candidate in ipairs(candidates) do
        local body = candidate.body
        local name = candidate.name or (candidate.path and filesystem.filename(candidate.path, "/")) or ""

        name = string.lower(string.gsub(name, "%.png$", ""))

        -- Same file name = same tileset, only the first one (preferred) is kept. Tilesets that
        -- the rule file already contains are left alone, so the users own configuration is kept
        if body and not addedNames[name] and not existingNames[name]
            and string.find(string.lower(body), "<set", 1, true) then
            -- Ask for an id first: a map can only hold so many tilesets, and images must not be
            -- copied for entries that can not be added
            local id = nextId(usedIds)
            local idLength = id and #id or 0

            if not id or (idLength ~= 1 and idLength ~= 3) then
                skipped = skipped + 1

            else
                local imageRelative = copyImage(candidate, modFolder, usedNames, layer)

                if imageRelative and not existingPaths[imageRelative] then
                    usedIds[id] = true
                    existingPaths[imageRelative] = true
                    addedNames[name] = true

                    table.insert(copiedImages, imageRelative)

                    -- "path" attributes have no extension, the game adds .png
                    local relative = string.gsub(imageRelative, "%.png$", "")

                    local bodyKey = string.gsub(body, "%s+", "")

                    if body:sub(1, 1) == "\n" then
                        body = body:gsub("^%s*\n", "")
                    end

                    local attributes = ""

                    if candidate.scanWidth then
                        attributes = attributes .. string.format(" scanWidth=\"%s\"", candidate.scanWidth)
                    end

                    if candidate.scanHeight then
                        attributes = attributes .. string.format(" scanHeight=\"%s\"", candidate.scanHeight)
                    end

                    if candidate.sound then
                        attributes = attributes .. string.format(" sound=\"%d\"", candidate.sound)
                    end

                    if candidate.ignores then
                        attributes = attributes .. string.format(" ignores=\"%s\"", candidate.ignores)
                    end

                    if copyBases[bodyKey] then
                        table.insert(blocks, string.format(
                            "  <!-- Loenn Add Defaults: %s -->\n  <Tileset id=\"%s\" copy=\"%s\" path=\"%s\"%s/>\n",
                            candidate.source or "unknown", id, copyBases[bodyKey], relative, attributes
                        ))

                    else
                        copyBases[bodyKey] = id

                        table.insert(blocks, string.format(
                            "  <!-- Loenn Add Defaults: %s -->\n  <Tileset id=\"%s\" path=\"%s\"%s>\n%s\n  </Tileset>\n",
                            candidate.source or "unknown", id, relative, attributes, body
                        ))
                    end

                    added = added + 1
                end
            end
        end
    end

    if added == 0 then
        -- AnimatedTiles is a foreground-only feature. Background Add Defaults must not touch it.
        if layer == "tilesFg" and not tilesetDefaults.dryRun then
            tilesetDefaults.mergeAnimatedTiles(modFolder)

            local debugUtils = require("debug_utils")
            debugUtils.reloadKnownModFilenames()
            debugUtils.redrawMap()
        end

        notifyMessage("tilesetDefaultsNothingAdded")

        return false, "nothing"
    end

    -- Insert before the closing tag. No gsub: the generated text may contain "%" (it is a valid
    -- tileset id), which gsub would treat as an escape in the replacement
    local insertAt = string.find(xmlText, "</Data>", 1, true)

    if not insertAt then
        -- Never append to a file that is not a tileset file: that would corrupt the users file
        notifyMessage("tilesetDefaultsInvalidXml", tostring(ruleRelative), "no </Data> tag")

        return false, "invalid"
    end

    local newText = string.sub(xmlText, 1, insertAt - 1) .. table.concat(blocks) .. string.sub(xmlText, insertAt)

    if tilesetDefaults.dryRun then
        logging.info(string.format("[tileset-defaults] dry run: %d tilesets for %s", added, ruleRelative))

        return true, added
    end

    -- Keep a copy of the file the way it was before the first Add Defaults run
    local backupPath = rulePath .. ".loenn-backup"

    if readTargetFile(rulePath) and not readTargetFile(backupPath) then
        writeTargetFile(backupPath, xmlText)
    end

    if not writeTargetFile(rulePath, newText) then
        notifyMessage("tilesetDefaultsWriteFailed")

        return false, "writeFailed"
    end

    -- Point the map metadata at the rule file
    if loadedState.side and loadedState.side.meta then
        loadedState.side.meta[metaKey] = utils.convertToUnixPath(ruleRelative)
    end

    logging.info(string.format("[tileset-defaults] added %d tilesets to %s (%s)", added, ruleRelative, modName))

    -- Same refresh as Ctrl+F5: drop the runtime atlas cache, refresh the current mods filename
    -- index and redraw the map. External sprites are then loaded from disk on first use, so the
    -- copied tilesets are available right away.
    local debugUtils = require("debug_utils")

    debugUtils.reloadKnownModFilenames()
    debugUtils.redrawMap()

    -- The tile tools keep their own copy of the tileset list: rebuild it so the new tilesets show
    -- up without switching the layer first
    local metaCount = 0
    local loadedMeta = layer == "tilesBg" and celesteRender.tilesMetaBg or celesteRender.tilesMetaFg

    for _ in pairs(loadedMeta or {}) do
        metaCount = metaCount + 1
    end

    logging.info(string.format("[tileset-defaults] tileset meta now holds %d tilesets", metaCount))

    -- Animated tiles are collected as well: vanilla, the other mods and the maps own definitions.
    -- They are only relevant to foreground tiles, so a background Add Defaults must not touch them.
    if layer == "tilesFg" then
        tilesetDefaults.mergeAnimatedTiles(modFolder)
    end

    local toolHandler = require("tools")
    local currentTool = toolHandler.currentTool

    if currentTool and currentTool.setLayer then
        currentTool.setLayer(toolHandler.getLayer())
    end

    if onDone then
        onDone(added)
    end

    if skipped > 0 then
        notifyMessage("tilesetDefaultsAddedSkipped", added, skipped)

    else
        notifyMessage("tilesetDefaultsAdded", added)
    end

    return true, added
end

-- ---------------------------------------------------------------------------
-- Only Keep Used
-- ---------------------------------------------------------------------------

-- Tileset ids referenced by any tile of the map
function tilesetDefaults.collectUsedIds()
    local used = {}
    local map = loadedState.side and loadedState.side.map

    if not map then
        return used
    end

    for _, room in ipairs(map.rooms or {}) do
        for _, layer in ipairs({"tilesFg", "tilesBg"}) do
            local layerTiles = room[layer]
            local matrix = layerTiles and layerTiles.matrix

            if matrix then
                local width, height = matrix:size()

                for x = 1, width do
                    for y = 1, height do
                        local tile = matrix:getInbounds(x, y)

                        if tile and tile ~= "0" and tile ~= "" then
                            used[tile] = true
                        end
                    end
                end
            end
        end
    end

    return used
end

-- Removes every tileset of the rule file that the map does not use. Vanilla tilesets and the
-- rules other tilesets copy from are always kept.
function tilesetDefaults.keepUsed(layer, onDone, targetFolder)
    layer = layer or "tilesFg"

    local modFolder, modName = tilesetDefaults.getMapModFolder()

    if targetFolder then
        modFolder, modName = targetFolder, "Target"
    end

    if not modFolder then
        notifyMessage("tilesetDefaultsInvalidMod")

        return false, "notInMod"
    end

    local rulePath, ruleRelative, metaKey, created, problem = getRuleFile(modFolder, layer)

    if not rulePath then
        notifyMessage("tilesetDefaultsInvalidXml", tostring(ruleRelative), tostring(problem))

        return false, problem
    end

    local xmlText = readTargetFile(rulePath)

    if not xmlText or not string.find(xmlText, "</Data>", 1, true) then
        notifyMessage("tilesetDefaultsInvalidXml", tostring(ruleRelative), "no </Data> tag")

        return false, "invalid"
    end

    local keep = tilesetDefaults.collectUsedIds()
    local vanillaMeta = layer == "tilesBg" and celesteRender.tilesMetaBgVanilla or celesteRender.tilesMetaFgVanilla
    local vanilla = {}

    for id in pairs(vanillaMeta or {}) do
        vanilla[id] = true
    end

    -- Split the file into lines and walk the <Tileset> blocks
    local lines = {}

    for line in string.gmatch(xmlText .. "\n", "([^\n]*)\n") do
        table.insert(lines, (string.gsub(line, "\r$", "")))
    end

    local function getIdOf(line)
        local id = string.match(line, 'id%s*=%s*"([^"]*)"')
        local copy = string.match(line, 'copy%s*=%s*"([^"]*)"')

        return id, copy
    end

    -- Collect the blocks first: the ones that stay may copy="..." a block that is unused itself
    local blocks = {}
    local index = 1

    while index <= #lines do
        local line = lines[index]
        local lowered = string.lower(line)

        if string.find(lowered, "<tileset", 1, true) then
            local block = {startLine = index, lines = {line}, id = getIdOf(line)}
            -- Self closing only when the opening tag itself ends with "/>". Checking the whole
            -- line for "/>" would match tilesets that have <set .../> children and the block
            -- would be cut short, which left the body behind when the tileset was removed
            local complete = string.match(line, "/>%s*$") ~= nil

            while not complete and index < #lines do
                index = index + 1
                table.insert(block.lines, lines[index])

                if string.find(string.lower(lines[index]), "</tileset", 1, true) then
                    complete = true
                end
            end

            blocks[#blocks + 1] = block
        end

        index = index + 1
    end

    -- Simple rule: a tileset of our own image folder ("Loenn/...") stays only when its id is used
    -- by a tile of the map. Everything else keeps working: the authors own entries and the vanilla
    -- tilesets are not touched. Copy="..." targets of kept entries are kept too, otherwise the
    -- kept entry would reference a missing tileset.
    local isOwnImagePath = function(path)
        return path ~= nil and string.sub(path, 1, 6) == "Loenn/"
    end

    local function blockInfo(block)
        local line = block.lines[1]
        local id, copy = getIdOf(line)
        local path = string.match(line, 'path%s*=%s*"([^"]*)"')

        return id, copy, path
    end

    local removed = 0
    local keptText = {}
    local keepPaths = {}
    local keepCopy = {}
    local blockIndex = 1
    local lineIndex = 1
    local keptBlocks = {}

    -- First pass: decide which blocks stay
    for _, block in ipairs(blocks) do
        local id, copy, path = blockInfo(block)
        local keepBlock

        if isOwnImagePath(path) then
            -- Our own images: keep only when used. An id that is also a vanilla id is a leftover
            -- from an older run that did not avoid the ASCII ids: the tiles under that id belong
            -- to the vanilla tileset, so the generated block goes away.
            keepBlock = keep[id] == true and not vanilla[id]
        else
            -- Not one of our images: keep it (author entry or a vanilla definition)
            keepBlock = true
        end

        block.keep = keepBlock

        if keepBlock then
            table.insert(keptBlocks, block)

            if path then
                keepPaths[path] = true
            end
        end
    end

    -- Copy targets of kept blocks must survive as well
    local changed = true

    while changed do
        changed = false

        for _, block in ipairs(keptBlocks) do
            local id, copy = getIdOf(block.lines[1])

            if copy and not keepCopy[copy] then
                keepCopy[copy] = true
                changed = true
            end
        end

        for _, block in ipairs(blocks) do
            local id = getIdOf(block.lines[1])

            if not block.keep and keepCopy[id] then
                block.keep = true

                local _, _, path = blockInfo(block)

                if path then
                    keepPaths[path] = true
                end

                table.insert(keptBlocks, block)
                changed = true
            end
        end
    end

    -- Second pass: rebuild the text
    while lineIndex <= #lines do
        local block = blocks[blockIndex]
        local line = lines[lineIndex]

        if block and lineIndex == block.startLine then
            if block.keep then
                for _, blockLine in ipairs(block.lines) do
                    table.insert(keptText, blockLine)
                end

            else
                removed = removed + 1

                -- Drop the comment that was written in front of this tileset
                local previous = keptText[#keptText]

                if previous and string.find(previous, "Loenn Add Defaults:", 1, true) then
                    table.remove(keptText)
                end
            end

            lineIndex = block.startLine + #block.lines
            blockIndex = blockIndex + 1

        else
            table.insert(keptText, line)
            lineIndex = lineIndex + 1
        end
    end

    if removed == 0 then
        notifyMessage("tilesetDefaultsNothingRemoved")

        return true, 0
    end

    local newText = table.concat(keptText, "\n")

    if tilesetDefaults.dryRun then
        logging.info(string.format("[tileset-defaults] dry run: would remove %d tilesets", removed))

        return true, removed
    end

    if not writeTargetFile(rulePath, newText) then
        notifyMessage("tilesetDefaultsWriteFailed")

        return false, "writeFailed"
    end

    logging.info(string.format("[tileset-defaults] removed %d unused tilesets from %s (%s)", removed, ruleRelative, modName))

    -- Also drop the images of the removed tilesets, but only the ones in this layer's folder.
    -- Foreground and background image folders are separate, so this never touches the other
    -- layer's tilesets (or legacy images in the shared Loenn/ folder).
    local removedImages = 0
    local imageFolder = utils.joinpath(modFolder, tilesetDefaults.getImageFolder(layer))
    local relativeFolder = tilesetDefaults.getImageRelativeFolder(layer)

    if filesystem.isDirectory(imageFolder) then
        for fileName in filesystem.listDir(imageFolder) do
            if string.lower(filesystem.fileExtension(fileName) or "") == "png" then
                local relative = relativeFolder .. "/" .. string.gsub(fileName, "%.png$", "")

                if not keepPaths[relative] then
                    if filesystem.remove(utils.joinpath(imageFolder, fileName)) then
                        removedImages = removedImages + 1
                    end
                end
            end
        end
    end

    if removedImages > 0 then
        logging.info(string.format("[tileset-defaults] removed %d unused images", removedImages))
    end

    -- Animated tiles are referenced by the "sprites" attribute of foreground tileset rules;
    -- background tilesets do not own AnimatedTiles entries.
    local trimmedAnimated = 0

    if layer == "tilesFg" then
        trimmedAnimated = tilesetDefaults.pruneAnimatedTiles(modFolder)
    end

    if trimmedAnimated > 0 then
        logging.info(string.format("[tileset-defaults] removed %d unreferenced animated tiles", trimmedAnimated))
    end

    -- Refresh like Ctrl+F5 so the removed images/rules are not kept alive by the atlas cache
    local debugUtils = require("debug_utils")

    debugUtils.reloadKnownModFilenames()
    debugUtils.redrawMap()

    local toolHandler = require("tools")
    local currentTool = toolHandler.currentTool

    if currentTool and currentTool.setLayer then
        currentTool.setLayer(toolHandler.getLayer())
    end

    if onDone then
        onDone(removed)
    end

    notifyMessage("tilesetDefaultsRemoved", removed)

    return true, removed
end

-- ---------------------------------------------------------------------------
-- Animated tiles
-- ---------------------------------------------------------------------------

local SPRITE_PATTERN = "<sprite%s+([^>]-)/>"

-- Reads <sprite .../> entries of an AnimatedTiles.xml style file into a name -> entry map
local function parseAnimatedSprites(text, into)
    into = into or {}

    for attributes in string.gmatch(text or "", SPRITE_PATTERN) do
        local name = string.match(attributes, 'name%s*=%s*"([^"]*)"')

        if name then
            into[name] = {attributes = attributes}
        end
    end

    return into
end

-- Copy of every AnimatedTiles entry the project can see, prebuilt with the tileset pack
local function formatSprite(entry)
    return string.format("<sprite %s/>", entry.attributes)
end

local function collectAnimatedTilesSources(modFolder)
    local sources = {}
    local success, entries = utils.tryrequire("assets/tile_pack/animated_tiles")

    if success and entries then
        local groups = {}
        local order = {}

        for _, entry in ipairs(entries) do
            -- The pack stores the archive file name, the editor mounts mods as "<name>_zip"
            local modName = entry.mod and (string.gsub(entry.mod, "%.zip$", "_zip")) or nil
            local key = modName or "__vanilla"

            if not groups[key] then
                groups[key] = {
                    name = modName and (getModDisplayName(modName) or modName) or "Celeste",
                    mod = modName,
                    text = {}
                }

                table.insert(order, key)
            end

            table.insert(groups[key].text, formatSprite(entry))
        end

        for _, key in ipairs(order) do
            local group = groups[key]

            table.insert(sources, {
                name = group.name,
                mod = group.mod,
                text = "<Data>" .. table.concat(group.text) .. "</Data>"
            })
        end
    end

    -- The maps own file, if it is already referenced by the metadata
    local configured = loadedState.side and loadedState.side.meta and loadedState.side.meta.AnimatedTiles

    if type(configured) == "string" then
        configured = string.gsub(configured, "%z", "")
    end

    if configured and configured ~= "" then
        local ownPath = utils.joinpath(modFolder, (utils.convertToUnixPath(configured)))
        local ownText = readTargetFile(ownPath)

        if ownText then
            table.insert(sources, {name = "This Mod", text = ownText, mod = nil, ownPath = ownPath})
        end
    end

    return sources
end

-- Removes the animated tiles no tileset refers to any more. Tilesets reference them through the
-- "sprites" attribute of their <set> rules.
function tilesetDefaults.pruneAnimatedTiles(modFolder)
    local meta = loadedState.side and loadedState.side.meta

    if not meta then
        return 0
    end

    local animatedRelative = meta.AnimatedTiles

    if type(animatedRelative) ~= "string" then
        return 0
    end

    animatedRelative = string.gsub(animatedRelative, "%z", "")

    if animatedRelative == "" then
        return 0
    end

    local animatedFile = utils.joinpath(modFolder, (utils.convertToUnixPath(animatedRelative)))
    local text = readTargetFile(animatedFile)

    if not text then
        return 0
    end

    -- Every sprite name the foreground and background tileset files still use
    local referenced = {}

    for _, key in ipairs({"ForegroundTiles", "BackgroundTiles"}) do
        local ruleRelative = meta[key]

        if type(ruleRelative) == "string" then
            ruleRelative = string.gsub(ruleRelative, "%z", "")

            if ruleRelative ~= "" then
                local ruleText = readTargetFile(utils.joinpath(modFolder, (utils.convertToUnixPath(ruleRelative))))

                for list in string.gmatch(ruleText or "", 'sprites%s*=%s*"([^"]*)"') do
                    for spriteName in string.gmatch(list, "[^,%s]+") do
                        referenced[spriteName] = true
                    end
                end
            end
        end
    end

    local kept = {}
    local removed = 0

    for attributes in string.gmatch(text, "<sprite%s+([^>]-)/>") do
        local name = string.match(attributes, 'name%s*=%s*"([^"]*)"')

        if name and referenced[name] then
            table.insert(kept, string.format("  <sprite %s/>\n", attributes))

        else
            removed = removed + 1
        end
    end

    if removed == 0 or tilesetDefaults.dryRun then
        return removed
    end

    writeTargetFile(animatedFile, "<Data>\n" .. table.concat(kept) .. "</Data>\n")

    return removed
end

-- Merges every AnimatedTiles.xml into the mods own file. The images the entries point to are
-- copied along, otherwise the entries would reference sprites of other mods.
function tilesetDefaults.mergeAnimatedTiles(modFolder, onDone)
    local modFolderName = filesystem.filename(utils.convertToUnixPath(modFolder), "/")
    local configured = loadedState.side and loadedState.side.meta and loadedState.side.meta.AnimatedTiles

    if type(configured) == "string" then
        configured = string.gsub(configured, "%z", "")
    end

    -- If the map already points at an AnimatedTiles.xml, append to that file instead of creating
    -- a second one under the default Graphics/<mod>/ name.
    local targetRelative

    if configured and configured ~= "" then
        targetRelative = utils.convertToUnixPath(configured)
    else
        targetRelative = "Graphics/" .. modFolderName .. "/AnimatedTiles.xml"
    end

    local targetPath = utils.joinpath(modFolder, (utils.convertToUnixPath(targetRelative)))
    local targetText = readTargetFile(targetPath)

    local sources = collectAnimatedTilesSources(modFolder)
    local entries = {}
    local order = {}

    for _, source in ipairs(sources) do
        for name, entry in pairs(parseAnimatedSprites(source.text)) do
            if not entries[name] then
                entries[name] = {sources = {}}
                table.insert(order, name)
            end

            -- Later sources win: the maps own definitions must stay untouched. All sources are
            -- kept around so the frame images can be looked up in any of them.
            table.insert(entries[name].sources, source)
            entries[name].attributes = entry.attributes
        end
    end

    if #order == 0 then
        return 0
    end

    -- Copy the frame images of the entries into the mod. They live in the prebuilt pack (one
    -- folder per source mod) so the mod does not depend on other mods being installed.
    local copiedFrames = 0
    local missingFrames = 0

    local function sanitizeName(value)
        return (string.gsub(value or "", "[^%w_%-%.]", "_"))
    end

    local function getModSlug(modFile)
        local base = filesystem.filename(utils.convertToUnixPath(modFile or ""), "/")
        base = string.gsub(base, "%.[^%.]+$", "")
        -- Mounted archive folders carry a "_zip" suffix the pack folder name does not have
        base = string.gsub(base, "[_%.]zip$", "")
        base = string.gsub(base, "[_%.]folder$", "")
        base = string.gsub(base, "'", "")
        base = sanitizeName(base)

        return base ~= "" and base or nil
    end

    for _, name in ipairs(order) do
        local entry = entries[name]
        local path = string.match(entry.attributes, 'path%s*=%s*"([^"]*)"')

        if path then
            local folder = string.match(path, "^(.*)/") or ""
            local baseName = string.lower(string.match(path, "([^/]+)$") or path)

            -- Prefer the pack copy: the source mod may be gone, but the pack keeps the artwork
            local copied = false

            -- The pack stores the frames without the "animatedTiles/" prefix
            local packRelative = string.gsub(folder, "^[Aa][Nn][Ii][Mm][Aa][Tt][Ee][Dd][Tt][Ii][Ll][Ee][Ss]/", "")

            local function copyFramesFromPack(packFolder)
                if copied or not love.filesystem.getInfo(packFolder) then
                    return
                end

                for _, frame in ipairs(love.filesystem.getDirectoryItems(packFolder)) do
                    local lowers = string.lower(frame)

                    if string.sub(lowers, 1, #baseName) == baseName and string.match(lowers, "%.png$") then
                        local relative = "Graphics/Atlases/Gameplay/" .. folder .. "/" .. frame
                        local target = utils.joinpath(modFolder, (utils.convertToUnixPath(relative)))
                        local bytes = utils.readAll(packFolder .. "/" .. frame, "rb", true)

                        if bytes and not fileExists(target) and writeTargetFile(target, bytes) then
                            copiedFrames = copiedFrames + 1
                        end

                        copied = true
                    end
                end
            end

            -- First the mods the definition came from
            for index = #entry.sources, 1, -1 do
                local modFile = entry.sources[index].mod
                local slug = modFile and getModSlug(modFile)

                if slug then
                    copyFramesFromPack(tilesetDefaults.packRoot .. "/images/animated_tiles/" .. slug .. "/" .. packRelative)
                end
            end

            -- Asset packs ship the frames without defining the sprites themselves, so fall back to
            -- looking through every mod folder of the pack
            if not copied then
                -- love.filesystem needs forward slashes: joinpath would produce backslashes here
                local packRoot = tilesetDefaults.packRoot .. "/images/animated_tiles"

                for _, slug in ipairs(love.filesystem.getDirectoryItems(packRoot)) do
                    copyFramesFromPack(packRoot .. "/" .. slug .. "/" .. packRelative)

                    if copied then
                        break
                    end
                end
            end

            if not copied then
                -- Vanilla only sprites are expected here: their frames ship with the game
                missingFrames = missingFrames + 1
            end
        end
    end

    local blocks = {"<Data>\n"}
    local newBlocks = {}
    local existingNames = parseAnimatedSprites(targetText)

    for _, name in ipairs(order) do
        table.insert(blocks, string.format("  <sprite %s/>\n", entries[name].attributes))

        if not existingNames[name] then
            table.insert(newBlocks, string.format("  <sprite %s/>\n", entries[name].attributes))
        end
    end

    table.insert(blocks, "</Data>\n")

    if targetText then
        -- The configured file already exists: append only the entries it does not have, so its
        -- formatting, comments and any hand-written definitions stay intact.
        if #newBlocks > 0 then
            local insertAt = string.find(targetText, "</Data>", 1, true)

            if not insertAt then
                notifyMessage("tilesetDefaultsInvalidXml", tostring(targetRelative), "no </Data> tag")

                return false, "invalid"
            end

            local newText = string.sub(targetText, 1, insertAt - 1) .. table.concat(newBlocks)
                .. string.sub(targetText, insertAt)

            if not tilesetDefaults.dryRun and not writeTargetFile(targetPath, newText) then
                notifyMessage("tilesetDefaultsWriteFailed")

                return false,
                    "writeFailed"
            end
        end

    elseif not tilesetDefaults.dryRun then
        if not writeTargetFile(targetPath, table.concat(blocks)) then
            notifyMessage("tilesetDefaultsWriteFailed")

            return false, "writeFailed"
        end
    end

    if loadedState.side and loadedState.side.meta then
        loadedState.side.meta.AnimatedTiles = utils.convertToUnixPath(targetRelative)
    end

    logging.info(string.format("[tileset-defaults] animated tiles: %d entries from %d sources, %d added, %d frames copied, %d without frames -> %s",
        #order, #sources, #newBlocks, copiedFrames, missingFrames, tostring(targetRelative)))

    if onDone then
        onDone(#order)
    end

    return #order
end

return tilesetDefaults
