-- Converts vanilla fillers into real rooms, taking the tiles from the surrounding rooms.
-- Ported from AnotherLoennPlugin's "Convert Fillers to Rooms".

local state = require("loaded_state")
local utils = require("utils")
local matrixLib = require("utils.matrix")
local mapItemUtils = require("map_item_utils")
local snapshot = require("structs.snapshot")

local fillerStruct = require("structs.filler")
local roomStruct = require("structs.room")
local tilesStruct = require("structs.tiles")

local script = {}

script.name = "convertFillersToRooms"
script.title = "Convert Fillers to Rooms"
script.description = "Makes vanilla fillers into rooms, with tiles from the surrounding rooms."

local function getTile(tx, ty, rooms)
    for _, room in ipairs(rooms) do
        local roomTX, roomTY = math.floor(room.x / 8), math.floor(room.y / 8)
        local x, y = tx - roomTX, ty - roomTY

        if room.tilesFg and room.tilesFg.matrix and room.tilesFg.matrix:inbounds0(x, y) then
            return room.tilesFg.matrix:get0Inbounds(x, y)
        end
    end

    return "0"
end

local function makeMatrix(x, y, w, h)
    local rooms = {}

    for _, room in ipairs(state.map.rooms) do
        if room.tilesFg and room.tilesFg.matrix and utils.aabbCheckInline(x, y, w, h,
            math.floor(room.x / 8) - 1,
            math.floor(room.y / 8) - 1,
            math.floor(room.width / 8) + 2,
            math.floor(room.height / 8) + 2) then
            table.insert(rooms, room)
        end
    end

    local matrix = matrixLib.filled("0", w, h)

    for i = 1, w do
        for j = 1, h do
            local tileX, tileY = x + i - 1, y + j - 1

            -- Take the first non empty tile around this cell: above, left, right, below
            local material = getTile(tileX, tileY - 1, rooms)

            if material == "0" then
                material = getTile(tileX - 1, tileY, rooms)
            end

            if material == "0" then
                material = getTile(tileX + 1, tileY, rooms)
            end

            if material == "0" then
                material = getTile(tileX, tileY + 1, rooms)
            end

            matrix:set(i, j, material)
        end
    end

    return matrix
end

local function convert(filler, name)
    local x, y = fillerStruct.getPosition(filler)
    local w, h = fillerStruct.getSize(filler)
    local matrix = makeMatrix(filler.x, filler.y, filler.width, filler.height)

    local room = roomStruct.decode({
        name = name,
        x = x,
        y = y,
        width = w,
        height = h,
        __children = {
            {
                __name = "solids",
                innerText = tilesStruct.matrixToTileStringMinimized(matrix)
            },
            {__name = "bg", innerText = ""},
            {__name = "objtiles", innerText = ""},
            {__name = "fgtiles", innerText = ""},
            {__name = "bgtiles", innerText = ""}
        }
    })

    mapItemUtils.addRoom(state.map, room)

    return room
end

local function getTargets(layer, context)
    if layer == "allRooms" then
        return utils.deepcopy(state.map.fillers)
    end

    -- Current Room only converts the focused filler; a room never converts its neighbours
    local focusedItem = context and context.focusedItem

    if focusedItem and utils.typeof(focusedItem) == "filler" then
        return {focusedItem}
    end

    return {}
end

function script.prerun(args, layer, context)
    local fillers = getTargets(layer, context)

    if #fillers == 0 then
        return nil
    end

    local createdRooms = {}

    local function forward()
        local existingFillers = {}

        for _, room in ipairs(state.map.rooms) do
            if room.name:sub(1, 8) == "_filler_" then
                table.insert(existingFillers, room)
            end
        end

        for _, filler in ipairs(fillers) do
            local x = (filler.x < 0 and "n" or "") .. math.abs(filler.x)
            local y = (filler.y < 0 and "n" or "") .. math.abs(filler.y)

            local name = "_filler_" .. x .. "_" .. y
            local taken = 0

            for _, room in ipairs(existingFillers) do
                if room.name:sub(1, #name) == name then
                    taken = taken + 1
                end
            end

            if taken > 0 then
                name = name .. "_" .. tostring(taken)
            end

            local room = convert(filler, name)

            createdRooms[room.name] = room
            mapItemUtils.deleteFiller(state.map, filler)
        end
    end

    local function backward()
        for _, filler in ipairs(fillers) do
            mapItemUtils.addFiller(state.map, filler)
        end

        for _, room in pairs(createdRooms) do
            mapItemUtils.deleteRoom(state.map, room)
        end

        createdRooms = {}
    end

    forward()

    return snapshot.create(script.name, {}, backward, forward)
end

return script
