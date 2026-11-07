-- Tile Credits: checks which tiles the map uses, finds the ones that came from the bundled
-- default tileset pack and copies the source mods to the clipboard.
-- Only tilesets imported from the pack ("Add Defaults") are reported: their path starts with
-- "Loenn/", which is where the pack images are copied to.

local brushHelper = require("brushes")
local modHandler = require("mods")
local utils = require("utils")
local notifications = require("ui.notification")

local script = {}

script.name = "tileCredits"
script.title = "Get Default Tile Credits"
script.description = "Copies the mods whose bundled default tilesets are used by the map."
-- The script only reads data and does not modify the map, so the tool should not report an
-- undo step / success message for it
script.silent = true

local packIndex

local function getPackIndex()
    if packIndex == nil then
        local success, loaded = utils.tryrequire("assets/tile_pack/index")
        packIndex = success and loaded or false
    end

    return packIndex or nil
end

-- Imported tilesets are named after the pack entry. Names can get a "_2" suffix when the image
-- name was already taken, so this is tried as a fallback.
local function findPackEntry(entryByName, tilesetPath)
    local baseName = string.match(tilesetPath, "([^/]+)$")

    if not baseName then
        return nil
    end

    local entry = entryByName[string.lower(baseName)]

    if entry then
        return entry
    end

    local withoutSuffix = string.match(baseName, "^(.-)_%d+$")

    return withoutSuffix and entryByName[string.lower(withoutSuffix)] or nil
end

local function getSourceName(modFile)
    local folder = string.gsub(modFile or "", "%.zip$", "")
    folder = string.gsub(folder, "%.love$", "")

    local metadata = modHandler.modMetadata and modHandler.modMetadata[folder]
    local names = metadata and modHandler.getModNamesFromMetadata(metadata)

    if names and names[1] then
        return names[1]
    end

    return utils.humanizeVariableName(folder)
end

-- Collects every tile id used by the map's tile layers
local function getUsedTiles(map)
    local used = {}

    for _, room in ipairs(map.rooms or {}) do
        for _, layer in ipairs({"tilesFg", "tilesBg"}) do
            local tiles = room[layer]

            if tiles and tiles.matrix then
                local width, height = tiles.matrix:size()

                for y = 1, height do
                    for x = 1, width do
                        local tile = tiles.matrix:get(x, y)

                        if tile and tile ~= "" then
                            used[tile] = true
                        end
                    end
                end
            end
        end
    end

    return used
end

local function collectCredits(map)
    local entries = getPackIndex()

    if not entries then
        return {}
    end

    local entryByName = {}

    for _, entry in ipairs(entries) do
        if entry.name then
            entryByName[string.lower(entry.name)] = entry
        end
    end

    local usedTiles = getUsedTiles(map)
    local sources = {}
    local sourceLookup = {}

    for _, layer in ipairs({"tilesFg", "tilesBg"}) do
        local tilerMeta = brushHelper.getTilerMeta(layer) or {}

        for tile in pairs(usedTiles) do
            local tileset = tilerMeta[tile]

            if tileset and tileset.path then
                local path = string.gsub(tileset.path, "^tilesets/", "")

                -- Only the Loenn imported defaults are credited
                if string.find(path, "^Loenn/") then
                    local entry = findPackEntry(entryByName, path)

                    if entry then
                        -- Only the primary source is credited: identical images can appear in
                        -- several mods, and Add Defaults always imports the first one
                        local source = entry.sources and entry.sources[1]

                        if source then
                            local sourceName = getSourceName(source.mod)

                            if sourceName and not sourceLookup[sourceName] then
                                sourceLookup[sourceName] = true
                                table.insert(sources, sourceName)
                            end
                        end
                    end
                end
            end
        end
    end

    table.sort(sources)

    return sources
end

function script.prerun()
    local map = require("loaded_state").map

    if not map then
        return nil
    end

    local sources = collectCredits(map)
    local text = table.concat(sources, ", ")

    love.system.setClipboardText(text)

    if #sources == 0 then
        notifications.notify("Tile Credits: no default tilesets are used by this map.")

    else
        notifications.notify(string.format("Tile Credits copied: %s", text))
    end

    return nil
end

return script
