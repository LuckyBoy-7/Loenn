-- Add Spikes Around Object: right-click a spike to copy its configuration, then left-click an
-- entity or a foreground tile to place outward-facing spikes around its outline.

local notifications = require("ui.notification")
local utils = require("utils")
local entities = require("entities")
local placementUtils = require("placement_utils")
local snapshotUtils = require("snapshot_utils")
local history = require("history")
local toolUtils = require("tool_utils")
local loadedState = require("loaded_state")
local languageRegistry = require("language_registry")

local script = {}

script.name = "addSpikesAroundObject"
script.title = "Add Spikes Around Object"
script.description = "Adds spikes around an entity or around the outline of a foreground tile area."

local DIRECTIONS = {
    up = "Up",
    down = "Down",
    left = "Left",
    right = "Right"
}

local DIRECTION_ORDER = {"up", "down", "left", "right"}
local HORIZONTAL_DIRECTIONS = {up = true, down = true}

local defaultSpikeConfig = {
    _editorLayer = 0,
    _fromLayer = "entities",
    _id = 4584,
    _name = "spikesUp",
    attachToSolid = true,
    type = "default",
    width = 24,
    x = 448,
    y = 416
}

local copiedSpikeConfig
local copiedSpikePrefix = "spikes"

local function languageText(key)
    local language = languageRegistry.getLanguage()
    local value = language.scripts
        and language.scripts.addSpikesAroundObject
        and language.scripts.addSpikesAroundObject[key]

    if value and value._exists ~= false then
        return tostring(value)
    end

    return key
end

--- Helpers

local function isEmptyTile(tile)
    return tile == nil or tile == "0" or tile == "" or tile == " "
end

local function getSpikeDirection(name)
    if type(name) ~= "string" then
        return nil
    end

    local lower = name:lower()

    if not lower:find("spike", 1, true) then
        return nil
    end

    for _, direction in ipairs(DIRECTION_ORDER) do
        if lower:sub(-#direction) == direction then
            return direction
        end
    end

    return nil
end

local function getSpikePrefix(name, direction)
    -- Keep the original casing. Mod spikes can use names like "Aqua/Gravity Spike Down"; lowering
    -- the first character would produce an entity name the registry does not know.
    return name:sub(1, #name - #direction)
end

local function getRoom(context)
    local room = context and context.focusedItem

    if room and utils.typeof(room) == "room" then
        return room
    end

    return loadedState.getSelectedRoom()
end

local function getMouseRoomPosition(context, room)
    return (context.mouseMapX or 0) - (room.x or 0),
        (context.mouseMapY or 0) - (room.y or 0)
end

local function rectangleContains(rectangle, x, y)
    return rectangle
        and x >= rectangle.x
        and x < rectangle.x + rectangle.width
        and y >= rectangle.y
        and y < rectangle.y + rectangle.height
end

local function getEntityAt(room, x, y)
    local found

    for _, entity in ipairs(room.entities or {}) do
        local rectangle = entities.getSelection(room, entity)

        if rectangleContains(rectangle, x, y) then
            found = entity
        end
    end

    return found
end

local function getTileSize(room)
    local matrix = room.tilesFg and room.tilesFg.matrix
        or room.tilesBg and room.tilesBg.matrix

    if matrix then
        return matrix:size()
    end

    return math.max(1, math.ceil((room.width or 320) / 8)),
        math.max(1, math.ceil((room.height or 184) / 8))
end

local function cellKey(x, y)
    return x .. ":" .. y
end

local function getOccupiedSpikeCells(room)
    local occupied = {}

    for _, entity in ipairs(room.entities or {}) do
        local direction = getSpikeDirection(entity._name)

        if direction then
            local horizontal = HORIZONTAL_DIRECTIONS[direction]

            if horizontal then
                local length = math.max(8, tonumber(entity.width) or 8)
                local airY

                if direction == "up" then
                    airY = math.floor(((entity.y or 0) - 1) / 8) + 1

                else
                    airY = math.floor((entity.y or 0) / 8) + 1
                end

                for offset = 0, length - 1, 8 do
                    local airX = math.floor(((entity.x or 0) + offset) / 8) + 1

                    occupied[cellKey(airX, airY)] = true
                end

            else
                local length = math.max(8, tonumber(entity.height) or 8)
                local airX

                if direction == "right" then
                    airX = math.floor((entity.x or 0) / 8) + 1

                else
                    airX = math.floor(((entity.x or 0) - 1) / 8) + 1
                end

                for offset = 0, length - 1, 8 do
                    local airY = math.floor(((entity.y or 0) + offset) / 8) + 1

                    occupied[cellKey(airX, airY)] = true
                end
            end
        end
    end

    return occupied
end

--- Spikes

local function addSpikeSegment(room, direction, startCoord, fixedCoord, length, occupied)
    if length <= 0 then
        return 0
    end

    local width, height = getTileSize(room)
    local horizontal = HORIZONTAL_DIRECTIONS[direction]

    if horizontal then
        if fixedCoord < 1 or fixedCoord > height
            or startCoord < 1 or startCoord + length - 1 > width then
            return 0
        end

    else
        if fixedCoord < 1 or fixedCoord > width
            or startCoord < 1 or startCoord + length - 1 > height then
            return 0
        end
    end

    local spike = utils.deepcopy(copiedSpikeConfig or defaultSpikeConfig)

    spike._name = copiedSpikePrefix .. DIRECTIONS[direction]
    spike._id = nil
    spike._type = "entity"
    spike._editorLayer = 0
    spike._fromLayer = "entities"
    spike.nodes = nil

    -- Only the axis used by the spike direction is meaningful
    spike.width = nil
    spike.height = nil

    local segmentLength = length * 8

    if direction == "up" then
        spike.x = (startCoord - 1) * 8
        spike.y = fixedCoord * 8
        spike.width = segmentLength

    elseif direction == "down" then
        spike.x = (startCoord - 1) * 8
        spike.y = (fixedCoord - 1) * 8
        spike.width = segmentLength

    elseif direction == "left" then
        spike.x = fixedCoord * 8
        spike.y = (startCoord - 1) * 8
        spike.height = segmentLength

    else
        spike.x = (fixedCoord - 1) * 8
        spike.y = (startCoord - 1) * 8
        spike.height = segmentLength
    end

    placementUtils.placeItem(room, "entities", 0, spike)

    for offset = 0, length - 1 do
        if horizontal then
            occupied[cellKey(startCoord + offset, fixedCoord)] = true

        else
            occupied[cellKey(fixedCoord, startCoord + offset)] = true
        end
    end

    return 1
end

-- Merge a consecutive range into one long spike, splitting it only where an existing spike already
-- occupies a cell. This avoids placing one entity per tile along straight edges.
local function addSpikeRun(room, direction, fixedCoord, startCoord, endCoord, occupied)
    local width, height = getTileSize(room)
    local horizontal = HORIZONTAL_DIRECTIONS[direction]

    if horizontal then
        if fixedCoord < 1 or fixedCoord > height then
            return 0
        end

        startCoord = math.max(1, startCoord)
        endCoord = math.min(width, endCoord)

    else
        if fixedCoord < 1 or fixedCoord > width then
            return 0
        end

        startCoord = math.max(1, startCoord)
        endCoord = math.min(height, endCoord)
    end

    if startCoord > endCoord then
        return 0
    end

    local added = 0
    local runStart

    for position = startCoord, endCoord do
        local key

        if horizontal then
            key = cellKey(position, fixedCoord)

        else
            key = cellKey(fixedCoord, position)
        end

        if occupied[key] then
            if runStart then
                added = added + addSpikeSegment(room, direction, runStart, fixedCoord,
                    position - runStart, occupied)
                runStart = nil
            end

        else
            runStart = runStart or position
        end
    end

    if runStart then
        added = added + addSpikeSegment(room, direction, runStart, fixedCoord,
            endCoord - runStart + 1, occupied)
    end

    return added
end

local function addAroundRectangle(room, rectangle, occupied)
    if not rectangle or rectangle.width <= 0 or rectangle.height <= 0 then
        return 0
    end

    local left = math.floor(rectangle.x / 8) + 1
    local right = math.ceil((rectangle.x + rectangle.width) / 8)
    local top = math.floor(rectangle.y / 8) + 1
    local bottom = math.ceil((rectangle.y + rectangle.height) / 8)
    local added = 0

    -- Horizontal strips first, then vertical ones. This keeps the same air cell from receiving
    -- two different spikes at concave corners.
    added = added + addSpikeRun(room, "up", top - 1, left, right, occupied)
    added = added + addSpikeRun(room, "down", bottom + 1, left, right, occupied)
    added = added + addSpikeRun(room, "left", left - 1, top, bottom, occupied)
    added = added + addSpikeRun(room, "right", right + 1, top, bottom, occupied)

    return added
end

local function getForegroundComponent(room, tileX, tileY)
    local tiles = room.tilesFg

    if not tiles or not tiles.matrix then
        return nil
    end

    local matrix = tiles.matrix
    local width, height = matrix:size()

    if tileX < 1 or tileY < 1 or tileX > width or tileY > height then
        return nil
    end

    local filled = {}

    for y = 1, height do
        filled[y] = {}

        for x = 1, width do
            filled[y][x] = not isEmptyTile(matrix:get(x, y, "0"))
        end
    end

    if not filled[tileY][tileX] then
        return nil
    end

    local component = {}
    local visited = {}
    local stack = {{tileX, tileY}}
    visited[tileY] = {[tileX] = true}

    while #stack > 0 do
        local cell = table.remove(stack)
        local x, y = cell[1], cell[2]

        table.insert(component, {x = x, y = y})

        for _, offset in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
            local nx, ny = x + offset[1], y + offset[2]

            if filled[ny] and filled[ny][nx] and not (visited[ny] and visited[ny][nx]) then
                visited[ny] = visited[ny] or {}
                visited[ny][nx] = true
                table.insert(stack, {nx, ny})
            end
        end
    end

    return component, filled
end

local function addEdge(edges, fixed, position)
    local positions = edges[fixed]

    if not positions then
        positions = {}
        edges[fixed] = positions
    end

    table.insert(positions, position)
end

local function collectRuns(edges)
    local runs = {}

    for fixed, positions in pairs(edges) do
        table.sort(positions)

        local start = positions[1]
        local previous = start

        for index = 2, #positions do
            local position = positions[index]

            if position == previous + 1 then
                previous = position

            else
                table.insert(runs, {fixed = fixed, start = start, stop = previous})
                start = position
                previous = position
            end
        end

        table.insert(runs, {fixed = fixed, start = start, stop = previous})
    end

    table.sort(runs, function(a, b)
        if a.fixed == b.fixed then
            return a.start < b.start
        end

        return a.fixed < b.fixed
    end)

    return runs
end

local function addEdgeRuns(room, edges, direction, occupied)
    local added = 0

    for _, run in ipairs(collectRuns(edges)) do
        added = added + addSpikeRun(room, direction, run.fixed, run.start, run.stop, occupied)
    end

    return added
end

local function addAroundForeground(room, component, filled, occupied)
    local top = {}
    local bottom = {}
    local left = {}
    local right = {}

    for _, cell in ipairs(component) do
        if not (filled[cell.y - 1] and filled[cell.y - 1][cell.x]) then
            addEdge(top, cell.y - 1, cell.x)
        end

        if not (filled[cell.y + 1] and filled[cell.y + 1][cell.x]) then
            addEdge(bottom, cell.y + 1, cell.x)
        end

        if not (filled[cell.y] and filled[cell.y][cell.x - 1]) then
            addEdge(left, cell.x - 1, cell.y)
        end

        if not (filled[cell.y] and filled[cell.y][cell.x + 1]) then
            addEdge(right, cell.x + 1, cell.y)
        end
    end

    local added = 0

    -- Horizontal first, then vertical. Runs are merged along the same row/column, and
    -- addSpikeRun splits them again where an existing spike already occupies a cell.
    added = added + addEdgeRuns(room, top, "up", occupied)
    added = added + addEdgeRuns(room, bottom, "down", occupied)
    added = added + addEdgeRuns(room, left, "left", occupied)
    added = added + addEdgeRuns(room, right, "right", occupied)

    return added
end

local function addWithHistory(room, callback)
    local added = 0
    local snapshot = snapshotUtils.roomLayerSnapshot(function()
        added = callback()
    end, room, "entities", "Add Spikes Around Object")

    if added > 0 then
        history.addSnapshot(snapshot)
        toolUtils.redrawTargetLayer(room, "entities")
    end

    return added
end

--- Entry points

function script.onSelected()
    notifications.notify(languageText("hint"))
end

function script.rightclick(context)
    local room = getRoom(context)

    if not room then
        notifications.notify(languageText("no_room"))
        return
    end

    local mouseX, mouseY = getMouseRoomPosition(context, room)
    local entity = getEntityAt(room, mouseX, mouseY)
    local direction = entity and getSpikeDirection(entity._name)

    if not direction then
        notifications.notify(languageText("copy_failed"))
        return
    end

    copiedSpikeConfig = utils.deepcopy(entity)
    copiedSpikePrefix = getSpikePrefix(entity._name, direction)

    notifications.notify(string.format(languageText("copy_success"), entity._name))
end

function script.open(context)
    local room = getRoom(context)

    if not room then
        notifications.notify(languageText("no_target"))
        return
    end

    local mouseX, mouseY = getMouseRoomPosition(context, room)
    local entity = getEntityAt(room, mouseX, mouseY)
    local occupied = getOccupiedSpikeCells(room)
    local added

    if entity then
        local rectangle = entities.getSelection(room, entity)

        if not rectangle then
            notifications.notify(languageText("no_target"))
            return
        end

        added = addWithHistory(room, function()
            return addAroundRectangle(room, rectangle, occupied)
        end)

    else
        local tileX = math.floor(mouseX / 8) + 1
        local tileY = math.floor(mouseY / 8) + 1
        local component, filled = getForegroundComponent(room, tileX, tileY)

        if not component then
            notifications.notify(languageText("no_target"))
            return
        end

        added = addWithHistory(room, function()
            return addAroundForeground(room, component, filled, occupied)
        end)
    end

    if added and added > 0 then
        notifications.notify(string.format(languageText("added"), added))

    else
        notifications.notify(languageText("none"))
    end
end

return script
