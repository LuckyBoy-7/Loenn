-- Transfer Used Decals: copies decals used by the current map that come from other mods into the
-- current map mod, renaming them when the target folder already has the same name.

local utils = require("utils")
local bit = require("bit")
local filesystem = require("utils.filesystem")
local notifications = require("ui.notification")
local virtualFs = require("virtual_fs")
local modHandler = require("mods")

local script = {}

script.name = "transferUsedDecals"
script.title = "Transfer Used Decals"
script.description = "Copies decals used by the map from other mods into the current mod."

local DECALS_ROOT = "Graphics/Atlases/Gameplay/decals"
local LETTERS = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"

local function normalizePath(path)
    path = utils.trim(path or "")
    path = path:gsub("\\", "/")
    path = path:gsub("^/+", "")
    path = path:gsub("/+$", "")
    path = path:gsub("//+", "/")

    return path
end

local function normalizeModName(name)
    name = string.lower(name or "")
    name = name:gsub("_zip$", "")
    name = name:gsub("_folder$", "")

    return name
end

local function readFile(path)
    local handle = io.open(path, "rb")

    if not handle then
        return nil
    end

    local data = handle:read("*a")

    handle:close()

    return data
end

local function writeFile(path, data)
    filesystem.mkpath(filesystem.dirname(path))

    local handle = utils.getFileHandle(path, "wb")

    if not handle then
        return false
    end

    handle:write(data)
    handle:close()

    return true
end

local function listDirectory(path)
    local result = {}

    if not filesystem.isDirectory(path) then
        return result
    end

    for name in utils.listDir(path) do
        if name ~= "." and name ~= ".." then
            table.insert(result, name)
        end
    end

    return result
end

-- Returns the base name (without trailing animation numbers) and the frame suffix
local function splitFrameName(name)
    local stem = name:gsub("%.png$", "")
    local base = stem:gsub("%d+$", "")

    if base == "" then
        base = stem
    end

    return base, stem:sub(#base + 1)
end

local function hashString(value)
    local hash = 2166136261

    for index = 1, #value do
        hash = bit.bxor(hash, value:byte(index))
        hash = bit.band(hash * 16777619, 0xFFFFFFFF)
    end

    return string.format("%08x", hash)
end

-- Hash of a whole decal group (frame suffixes + frame contents), so identical images can reuse
-- an existing target file while updated mod images are treated as new
local function hashGroup(frames)
    local parts = {}

    for _, frame in ipairs(frames) do
        table.insert(parts, frame.suffix .. ":" .. hashString(frame.data))
    end

    return hashString(table.concat(parts, "|"))
end

local function collectTargetGroups(root)
    local groups = {}
    local index = {}

    for _, name in ipairs(listDirectory(root)) do
        if name:match("%.png$") then
            local base, suffix = splitFrameName(name)
            groups[base] = groups[base] or {}
            table.insert(groups[base], {suffix = suffix, name = name})
        end
    end

    for base, frames in pairs(groups) do
        table.sort(frames, function(a, b)
            return a.suffix < b.suffix
        end)

        local hashedFrames = {}

        for _, frame in ipairs(frames) do
            local data = readFile(utils.joinpath(root, frame.name))

            if data then
                table.insert(hashedFrames, {suffix = frame.suffix, data = data, name = frame.name})
            end
        end

        if #hashedFrames > 0 then
            index[hashGroup(hashedFrames)] = {
                base = base,
                frames = hashedFrames
            }
        end
    end

    return index
end

local function collectUsedDecals(map)
    local textures = {}
    local seen = {}

    for _, room in ipairs(map.rooms or {}) do
        for _, layer in ipairs({"decalsFg", "decalsBg"}) do
            for _, decal in ipairs(room[layer] or {}) do
                local texture = decal.texture

                if texture and texture ~= "" and not seen[texture] then
                    seen[texture] = true
                    table.insert(textures, texture)
                end
            end
        end
    end

    return textures
end

local function collectSourceGroup(owner, texture, base)
    local relative = texture:match("^decals/(.*)$")

    if not relative then
        return nil
    end

    local directory = relative:match("^(.*)/[^/]*$") or ""
    local folder = DECALS_ROOT

    if directory ~= "" then
        folder = folder .. "/" .. directory
    end

    local files = modHandler.findModFiletype(folder, "png", {owner})
    local group = {}

    for _, filename in ipairs(files) do
        local name = filename:match("([^/]+)$")
        local fileBase = splitFrameName(name)

        if fileBase == base then
            table.insert(group, {filename = filename, name = name})
        end
    end

    return group
end

local function hasNameCollision(existing, base)
    for name in pairs(existing) do
        local stem = name:gsub("%.png$", "")

        if stem == base or stem:match("^" .. base:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0") .. "%d+$") then
            return true
        end
    end

    return false
end

local function pickTargetBase(existing, base)
    if not hasNameCollision(existing, base) then
        return base
    end

    for index = 1, #LETTERS do
        local candidate = base .. LETTERS:sub(index, index)

        if not hasNameCollision(existing, candidate) then
            return candidate
        end
    end

    return base .. "X" .. tostring(os.time())
end

local function transfer(modFolder, modName, transferPath)
    local map = require("loaded_state").map

    if not map then
        notifications.notify("Transfer Used Decals: no map is loaded.")

        return false
    end

    local targetRoot = utils.joinpath(modFolder, DECALS_ROOT, transferPath)
    local existing = {}
    local copied = 0
    local copiedGroups = 0
    local reused = 0
    local reusedGroups = 0
    local sourceGroups = {}
    local mapping = {}
    local currentMod = normalizeModName(modName)

    for _, name in ipairs(listDirectory(targetRoot)) do
        existing[name] = true
    end

    local targetGroups = collectTargetGroups(targetRoot)

    local textures = collectUsedDecals(map)

    for _, texture in ipairs(textures) do
        local owner = virtualFs.getOwner("Graphics/Atlases/Gameplay/" .. texture .. ".png")
        local normalizedOwner = normalizeModName(owner)

        if owner and owner ~= ""
            and normalizedOwner ~= currentMod and normalizedOwner ~= "celeste" then
            local relative = texture:match("^decals/(.*)$")

            if relative then
                local directory = relative:match("^(.*)/[^/]*$") or ""
                local stem = relative:match("([^/]*)$") or ""
                local base = stem:gsub("%d+$", "")

                if base == "" then
                    base = stem
                end

                local groupKey = owner .. "|" .. directory .. "|" .. base

                if not sourceGroups[groupKey] then
                    sourceGroups[groupKey] = true

                    local group = collectSourceGroup(owner, texture, base)

                    if group and #group > 0 then
                        local sourceFrames = {}
                        local success = true

                        for _, file in ipairs(group) do
                            local _, suffix = splitFrameName(file.name)
                            local data = utils.readAll(file.filename, "rb", true)

                            if not data then
                                success = false

                                break
                            end

                            table.insert(sourceFrames, {
                                suffix = suffix,
                                name = file.name,
                                data = data
                            })
                        end

                        if success and #sourceFrames > 0 then
                            table.sort(sourceFrames, function(a, b)
                                return a.suffix < b.suffix
                            end)

                            local groupHash = hashGroup(sourceFrames)
                            local existingGroup = targetGroups[groupHash]

                            if existingGroup then
                                -- Same frames and same image contents already exist: reuse them and
                                -- only point the map at the existing files
                                local existingBySuffix = {}

                                for _, frame in ipairs(existingGroup.frames) do
                                    existingBySuffix[frame.suffix] = frame.name
                                end

                                for _, file in ipairs(group) do
                                    local _, suffix = splitFrameName(file.name)
                                    local targetName = existingBySuffix[suffix]

                                    if targetName then
                                        local oldStem = file.name:gsub("%.png$", "")
                                        local newStem = targetName:gsub("%.png$", "")

                                        mapping["decals/" .. directory .. "/" .. oldStem] =
                                            "decals/" .. transferPath .. "/" .. newStem

                                        reused = reused + 1
                                    end
                                end

                                reusedGroups = reusedGroups + 1

                            else
                                local targetBase = pickTargetBase(existing, base)
                                local writtenFrames = {}

                                for _, frame in ipairs(sourceFrames) do
                                    local targetName = targetBase .. frame.suffix .. ".png"

                                    if not writeFile(utils.joinpath(targetRoot, targetName), frame.data) then
                                        success = false

                                        break
                                    end

                                    local oldStem = frame.name:gsub("%.png$", "")
                                    local newStem = targetBase .. frame.suffix

                                    mapping["decals/" .. directory .. "/" .. oldStem] =
                                        "decals/" .. transferPath .. "/" .. newStem

                                    existing[targetName] = true
                                    copied = copied + 1

                                    table.insert(writtenFrames, {
                                        suffix = frame.suffix,
                                        name = targetName,
                                        data = frame.data
                                    })
                                end

                                if success then
                                    copiedGroups = copiedGroups + 1
                                    targetGroups[groupHash] = {base = targetBase, frames = writtenFrames}
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if copied == 0 and reused == 0 then
        notifications.notify("Transfer Used Decals: no decals from other mods were found.")

        return false
    end

    -- Point the map's decals at the copied files (including renamed animation frames). The path
    -- replacement is intentionally not added to the undo history.
    local applyScript = {
        name = "transferUsedDecalsApply",
        title = script.title,
        silent = true
    }

    function applyScript.run(room, args)
        for _, layer in ipairs({"decalsFg", "decalsBg"}) do
            for _, decal in ipairs(room[layer] or {}) do
                local replacement = args.mapping[decal.texture]

                if replacement then
                    decal.texture = replacement
                end
            end
        end
    end

    local celesteRender = require("celeste_render")

    for _, room in ipairs(map.rooms) do
        applyScript.run(room, {mapping = mapping})
        celesteRender.invalidateRoomCache(room)
    end

    notifications.notify(string.format(
        "Transfer Used Decals: copied %d files (%d groups), reused %d files (%d groups) in 'Graphics/Atlases/Gameplay/decals/%s'.",
        copied, copiedGroups, reused, reusedGroups, transferPath))

    -- Same as Ctrl+F5: save the map first, then reload atlases/mods so the newly copied textures
    -- are picked up
    require("ui").runLate(function()
        local loadedState = require("loaded_state")
        local debugUtils = require("debug_utils")

        if not loadedState.filename then
            debugUtils.reloadEverything()

            return
        end

        loadedState.saveFile(loadedState.filename, function(filename, state)
            loadedState.defaultAfterSaveCallback(filename, state)

            require("ui").runLate(function()
                debugUtils.reloadEverything()
            end)
        end, false, nil, false)
    end)

    return true
end

-- Also callable from tests/other tools
script.transfer = transfer

function script.open()
    local tilesetDefaults = require("tileset_defaults")
    local scriptsPanel = require("ui.windows.scripts_panel")
    local modFolder, modName = tilesetDefaults.getMapModFolder()

    if not modFolder then
        notifications.notify("Transfer Used Decals: the current map is not inside a valid, unpacked Mod folder.")

        return
    end

    local panelScript = {
        name = script.name .. "Panel",
        title = script.title,
        fieldOrder = {"transferPath"},
        defaultData = {
            transferPath = "YourName/YourMap/"
        },
        fieldInformation = {
            transferPath = {
                displayName = "Transfer To Path",
                tooltipText = "Path below Graphics/Atlases/Gameplay/decals where the copied decals are placed."
            }
        }
    }

    scriptsPanel.open(panelScript, nil, function(values)
        local transferPath = normalizePath(values.transferPath)

        if transferPath == "" then
            notifications.notify("Transfer Used Decals: please enter a target path.")

            return false
        end

        return transfer(modFolder, modName, transferPath)
    end, {
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
