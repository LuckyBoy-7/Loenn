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

    for position = 1, #asciiIdPool do
        table.insert(idCandidates, string.sub(asciiIdPool, position, position))
    end

    -- Then every CJK unified ideograph, which is about 20k more ids
    for codePoint = 0x4E00, 0x9FFF do
        table.insert(idCandidates, encodeUtf8(codePoint))
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

        if id or path then
            table.insert(entries, {id = id, path = path, copy = copy, body = body})
        end
    end

    return entries
end

local function getTilesetIds(text)
    local ids = {}

    for id in string.gmatch(text or "", 'id%s*=%s*"([^"]*)"') do
        ids[id] = true
    end

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

local function notifyMessage(key, ...)
    local text = languageRegistry.getLanguage().ui.notifications[key]

    notifications.notify(string.format(tostring(text), ...))
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
        -- The archived mods have to be mounted to read their files. This only happens when the
        -- user actually asks for the defaults
        modHandler.ensureModMounted(modFolderName)

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
                source = string.format("%s (%s)", entry.sources[1].mod, entry.sources[1].xml)
                sourceGroup = string.lower(string.gsub(entry.sources[1].mod or "", "_zip$", ""))
                sourceGroup = string.gsub(sourceGroup, "%d+$", "")
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
local function copyImage(candidate, modFolder, usedNames)
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

    while true do
        local relative = "Loenn/" .. name .. ".png"
        local target = utils.joinpath(modFolder, tilesetDefaults.imageFolder, name .. ".png")

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
    local modFolderName = filesystem.filename(modFolder, "/")
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
        xmlText = "<Data>\n</Data>\n"

        created = true
    end

    -- Ids that are already taken by the file itself (and by the entries written in this run,
    -- see below). Nothing else is pre-recorded: a new id only has to be unique in the file it is
    -- appended to.
    local usedIds = getTilesetIds(xmlText)
    local usedNames = {}

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
                local imageRelative = copyImage(candidate, modFolder, usedNames)

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

                    if copyBases[bodyKey] then
                        table.insert(blocks, string.format(
                            "  <!-- Loenn Add Defaults: %s -->\n  <Tileset id=\"%s\" copy=\"%s\" path=\"%s\"/>\n",
                            candidate.source or "unknown", id, copyBases[bodyKey], relative
                        ))

                    else
                        copyBases[bodyKey] = id

                        table.insert(blocks, string.format(
                            "  <!-- Loenn Add Defaults: %s -->\n  <Tileset id=\"%s\" path=\"%s\">\n%s\n  </Tileset>\n",
                            candidate.source or "unknown", id, relative, body
                        ))
                    end

                    added = added + 1
                end
            end
        end
    end

    if added == 0 then
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
            local complete = string.find(line, "/>", 1, true) ~= nil

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

    -- Our own blocks only survive when the map uses them. A block belongs to us when the comment
    -- written by Add Defaults sits in front of it (look a few lines back: blank lines may have
    -- been inserted in between by hand)
    local isGenerated = {}

    for _, block in ipairs(blocks) do
        local generated = false

        for offset = 1, 3 do
            local previous = lines[block.startLine - offset]

            if not previous then
                break
            end

            if string.find(previous, "Loenn Add Defaults:", 1, true) then
                generated = true

                break
            end

            if not string.match(previous, "^%s*$") then
                break
            end
        end

        isGenerated[block.startLine] = generated
    end

    for _, block in ipairs(blocks) do
        local id = getIdOf(block.lines[1])

        if isGenerated[block.startLine] then
            -- A generated tileset that shadows a vanilla id: whatever the map uses under that
            -- id is the vanilla tileset, so our block has to go
            if vanilla[id] then
                keep[id] = nil
            end

        elseif vanilla[id] then
            -- Blocks that are not ours are kept when they define a vanilla id
            keep[id] = true
        end
    end

    -- Follow copy="..." chains of the kept tilesets
    local changed = true

    while changed do
        changed = false

        for _, block in ipairs(blocks) do
            local id, copy = getIdOf(block.lines[1])

            if keep[id] and copy and not keep[copy] then
                keep[copy] = true
                changed = true
            end
        end
    end

    local removed = 0
    local keptText = {}
    local keepPaths = {}
    local blockIndex = 1
    local lineIndex = 1

    while lineIndex <= #lines do
        local block = blocks[blockIndex]
        local line = lines[lineIndex]

        if block and lineIndex == block.startLine then
            local id = getIdOf(line)

            if keep[id] then
                local path = string.match(line, 'path%s*=%s*"([^"]*)"')

                if path then
                    keepPaths[path] = true
                end

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

    -- Also drop the images of the removed tilesets, but only the ones in the folder this feature
    -- manages: never touch the rest of the mod
    local removedImages = 0
    local imageFolder = utils.joinpath(modFolder, tilesetDefaults.imageFolder)

    if filesystem.isDirectory(imageFolder) then
        for fileName in filesystem.listDir(imageFolder) do
            if string.lower(filesystem.fileExtension(fileName) or "") == "png" then
                local relative = "Loenn/" .. string.gsub(fileName, "%.png$", "")

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

return tilesetDefaults
