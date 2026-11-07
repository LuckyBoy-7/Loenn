-- Decal Credits: collects the sources of every decal used by the map and copies the owning mods
-- to the clipboard (comma separated). Vanilla decals are reported as "Celeste".

local virtualFs = require("virtual_fs")
local modHandler = require("mods")
local utils = require("utils")
local notifications = require("ui.notification")

local script = {}

script.name = "decalCredits"
script.title = "Get Decal Credits"
script.description = "Copies the mods whose decals are used by the map."
-- Only reads the map, no undo step / success notification
script.silent = true

local function getDecalSourceName(texture)
    -- texture is stored as "decals/<path>"; the atlas resource is the same path plus .png
    local owner = virtualFs.getOwner("Graphics/Atlases/Gameplay/" .. texture .. ".png")

    if not owner or owner == "" then
        return "Celeste"
    end

    local metadata = modHandler.modMetadata and modHandler.modMetadata[owner]
    local names = metadata and modHandler.getModNamesFromMetadata(metadata)

    if names and names[1] then
        return names[1]
    end

    return utils.humanizeVariableName((string.gsub(owner, "_zip$", "")):gsub("_folder$", ""))
end

local function collectCredits(map)
    local sources = {}
    local sourceLookup = {}

    for _, room in ipairs(map.rooms or {}) do
        for _, layer in ipairs({"decalsFg", "decalsBg"}) do
            for _, decal in ipairs(room[layer] or {}) do
                if decal.texture and decal.texture ~= "" then
                    local sourceName = getDecalSourceName(decal.texture)

                    if sourceName and not sourceLookup[sourceName] then
                        sourceLookup[sourceName] = true
                        table.insert(sources, sourceName)
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
        notifications.notify("Decal Credits: no decals are used by this map.")

    else
        notifications.notify(string.format("Decal Credits copied: %s", text))
    end

    return nil
end

return script
