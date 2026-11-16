-- Auto Add Filler: extends solid tiles outward from room edges and covers the result with normal
-- rooms named zzzz_Auto_Added_Filler_N. This intentionally does not use the map's filler rectangles.
--
-- The script operates on the whole map in prerun, so it runs once regardless of the selected
-- Scripts scope.

local state = require("loaded_state")
local selectionUtils = require("selections")
local roomStruct = require("structs.room")
local snapshotStruct = require("structs.snapshot")
local mapItemUtils = require("map_item_utils")
local history = require("history")

local script = {}

script.name = "autoAddFiller"
script.title = "Auto Add Filler"
script.description = "Expands solid tiles around room edges and creates full-tile filler rooms."

script.fieldOrder = {
    "horizontalExpand",
    "verticalExpand",
    "cornerExpand",
    "clearPrevious"
}

script.defaultData = {
    horizontalExpand = 6,
    verticalExpand = 6,
    cornerExpand = 6,
    clearPrevious = true
}

script.fieldInformation = {
    horizontalExpand = {
        fieldType = "integer",
        displayName = "Horizontal Expand",
        tooltipText = "Tiles to extend left/right edge bricks outward.",
        minimumValue = 0,
        maximumValue = 10
    },
    verticalExpand = {
        fieldType = "integer",
        displayName = "Vertical Expand",
        tooltipText = "Tiles to extend top/bottom edge bricks outward.",
        minimumValue = 0,
        maximumValue = 10
    },
    cornerExpand = {
        fieldType = "integer",
        displayName = "Corner Expand",
        tooltipText = "Tiles to extend corner bricks diagonally outward.",
        minimumValue = 0,
        maximumValue = 10
    },
    clearPrevious = {
        displayName = "Clear Previous Auto Added Filler",
        tooltipText = "Removes Auto_Added_Filler_ rooms touching the current room(s); in All Rooms removes every Auto_Added_Filler_ room."
    }
}

script.tooltips = {
    horizontalExpand = "Tiles to extend left/right edge bricks outward.",
    verticalExpand = "Tiles to extend top/bottom edge bricks outward.",
    cornerExpand = "Tiles to extend corner bricks diagonally outward.",
    clearPrevious = "Remove Auto_Added_Filler_ rooms touching the current room(s); All Rooms removes all of them."
}

local PREFIX = "zzzz_Auto_Added_Filler_"
local LEGACY_PREFIX = "Auto_Added_Filler_"

local function isAutoFiller(room)
    if type(room.name) ~= "string" then
        return false
    end

    return room.name:sub(1, #PREFIX) == PREFIX
        or room.name:sub(1, #LEGACY_PREFIX) == LEGACY_PREFIX
end

local function clampInteger(value)
    value = math.floor(tonumber(value) or 0)

    return math.max(0, math.min(64, value))
end

local function key(x, y)
    return x .. "," .. y
end

local function getTileRect(room)
    local matrix = room.tilesFg and room.tilesFg.matrix
    local width, height

    if matrix then
        width, height = matrix:size()

    else
        width = math.max(1, math.ceil(room.width / 8))
        height = math.max(1, math.ceil(room.height / 8))
    end

    local x = math.floor(room.x / 8)
    local y = math.floor(room.y / 8)

    return {
        x1 = x,
        y1 = y,
        x2 = x + width - 1,
        y2 = y + height - 1,
        width = width,
        height = height
    }
end

local function getBoundaryTile(room, x, y)
    local matrix = room.tilesFg and room.tilesFg.matrix

    if not matrix then
        return nil
    end

    local tile = matrix:get(x, y, "0")

    if tile and tile ~= "0" and tile ~= 0 then
        return tostring(tile)
    end

    return nil
end

local function getTargetRooms(map, layer)
    local rooms

    if layer == "allRooms" then
        rooms = map.rooms

    else
        rooms = selectionUtils.getSelectedRooms()

        if #rooms == 0 then
            local selected = state.getSelectedRoom()

            if selected then
                rooms = {selected}
            end
        end
    end

    rooms = rooms or {}

    local result = {}

    for _, room in ipairs(rooms) do
        if not isAutoFiller(room) then
            table.insert(result, room)
        end
    end

    return result
end

local function rectanglesTouch(a, b)
    local gapX = math.max(b.x1 - a.x2 - 1, a.x1 - b.x2 - 1, 0)
    local gapY = math.max(b.y1 - a.y2 - 1, a.y1 - b.y2 - 1, 0)

    return gapX == 0 and gapY == 0
end

local function autoFillerTouchesRooms(room, targetRooms)
    local roomRect = getTileRect(room)

    for _, targetRoom in ipairs(targetRooms) do
        if rectanglesTouch(roomRect, getTileRect(targetRoom)) then
            return true
        end
    end

    return false
end

function script.clear()
    local map = state.map

    if not map then
        return false
    end

    local toolHandler = require("tools")
    local layer = toolHandler.getLayer()
    local targetRooms = getTargetRooms(map, layer)
    local notifications = require("ui.notification")
    local removedRooms = {}

    for index = #map.rooms, 1, -1 do
        local room = map.rooms[index]

        if isAutoFiller(room)
            and (layer == "allRooms" or autoFillerTouchesRooms(room, targetRooms)) then
            table.insert(removedRooms, room)
            mapItemUtils.deleteItem(map, room, false)
        end
    end

    if #removedRooms == 0 then
        notifications.notify("No Auto Added Filler rooms to clear.")

        return false
    end

    local function applyForward()
        for _, room in ipairs(removedRooms) do
            mapItemUtils.deleteItem(map, room, false)
        end
    end

    local function applyBackward()
        for _, room in ipairs(removedRooms) do
            mapItemUtils.addItem(map, room, false)
        end
    end

    history.addSnapshot(snapshotStruct.create(
        "Clear Auto Added Filler", {}, applyBackward, applyForward))

    notifications.notify(string.format("Cleared %d Auto Added Filler room(s).", #removedRooms))

    return true
end

script.extraButtons = {
    {
        text = "Clear",
        callback = script.clear
    }
}

-- Run one expansion ray. Cells already claimed by the same source room are skipped; cells
-- claimed by another room stop the ray so two expansions never overwrite each other.
local function isInsideAnyRoom(roomRects, x, y)
    for _, rect in ipairs(roomRects) do
        if x >= rect.x1 and x <= rect.x2 and y >= rect.y1 and y <= rect.y2 then
            return true
        end
    end

    return false
end

local function claimCell(claimed, roomRects, sourceRoom, x, y, tile)
    if isInsideAnyRoom(roomRects, x, y) then
        return "room"
    end

    local cellKey = key(x, y)
    local existing = claimed[cellKey]

    if existing then
        if existing.source ~= sourceRoom then
            return "collision"
        end

        return "same"
    end

    claimed[cellKey] = {
        x = x,
        y = y,
        tile = tile,
        source = sourceRoom
    }

    return "new"
end

local function expandRay(claimed, roomRects, sourceRoom, startX, startY, stepX, stepY, steps, tile)
    for index = 1, steps do
        local x = startX + stepX * (index - 1)
        local y = startY + stepY * (index - 1)
        local result = claimCell(claimed, roomRects, sourceRoom, x, y, tile)

        if result == "room" or result == "collision" then
            return
        end
    end
end

local function collectExpandedTiles(targetRooms, roomRects, horizontal, vertical, corner)
    local claimed = {}

    for _, room in ipairs(targetRooms) do
        local rect = getTileRect(room)
        local matrix = room.tilesFg and room.tilesFg.matrix

        if matrix then
            -- Left/right edges
            for row = 1, rect.height do
                local y = rect.y1 + row - 1
                local leftTile = getBoundaryTile(room, 1, row)

                if leftTile and horizontal > 0 then
                    expandRay(claimed, roomRects, room, rect.x1 - 1, y, -1, 0, horizontal, leftTile)
                end

                local rightTile = getBoundaryTile(room, rect.width, row)

                if rightTile and horizontal > 0 then
                    expandRay(claimed, roomRects, room, rect.x2 + 1, y, 1, 0, horizontal, rightTile)
                end
            end

            -- Top/bottom edges
            for column = 1, rect.width do
                local x = rect.x1 + column - 1
                local topTile = getBoundaryTile(room, column, 1)

                if topTile and vertical > 0 then
                    expandRay(claimed, roomRects, room, x, rect.y1 - 1, 0, -1, vertical, topTile)
                end

                local bottomTile = getBoundaryTile(room, column, rect.height)

                if bottomTile and vertical > 0 then
                    expandRay(claimed, roomRects, room, x, rect.y2 + 1, 0, 1, vertical, bottomTile)
                end
            end

            -- Corner blocks: fill a C x C square outside each corner so the corner cells connect
            -- to the horizontal and vertical edge expansions.
            local corners = {
                {column = 1, row = 1, stepX = -1, stepY = -1},
                {column = rect.width, row = 1, stepX = 1, stepY = -1},
                {column = 1, row = rect.height, stepX = -1, stepY = 1},
                {column = rect.width, row = rect.height, stepX = 1, stepY = 1}
            }

            for _, cornerData in ipairs(corners) do
                local tile = getBoundaryTile(room, cornerData.column, cornerData.row)

                if tile and corner > 0 then
                    local cornerX = rect.x1 + cornerData.column - 1
                    local cornerY = rect.y1 + cornerData.row - 1
                    local blocked = false

                    for offsetX = 1, corner do
                        for offsetY = 1, corner do
                            local x = cornerX + cornerData.stepX * offsetX
                            local y = cornerY + cornerData.stepY * offsetY
                            local result = claimCell(claimed, roomRects, room, x, y, tile)

                            if result == "room" or result == "collision" then
                                blocked = true

                                break
                            end
                        end

                        if blocked then
                            break
                        end
                    end
                end
            end
        end
    end

    return claimed
end

-- Grow the expanded brick region by one cell in every direction (including diagonals). This is
-- the "expand one air tile" step: the generated full-tile rooms naturally become one tile larger
-- and adjacent regions merge before the rectangle cover runs.
local function dilateExpandedTiles(claimed, roomRects)
    local result = {}

    for _, cell in pairs(claimed) do
        result[key(cell.x, cell.y)] = cell
    end

    for _, cell in pairs(claimed) do
        local neighbours = {
            {1, 0},
            {-1, 0},
            {0, 1},
            {0, -1}
        }

        for _, offset in ipairs(neighbours) do
            local x = cell.x + offset[1]
            local y = cell.y + offset[2]
            local cellKey = key(x, y)

            if not result[cellKey] and not isInsideAnyRoom(roomRects, x, y) then
                result[cellKey] = {
                    x = x,
                    y = y,
                    tile = cell.tile,
                    source = cell.source,
                    air = true
                }
            end
        end
    end

    -- Fill the outer diagonal corners of the one-tile border as well. This only happens when
    -- both adjacent side cells are already part of the border, so it cannot grow extra wings.
    local diagonalCandidates = {}

    for _, cell in pairs(result) do
        for _, offset in ipairs({{-1, -1}, {-1, 1}, {1, -1}, {1, 1}}) do
            local x = cell.x + offset[1]
            local y = cell.y + offset[2]
            local cellKey = key(x, y)

            if not result[cellKey] and not isInsideAnyRoom(roomRects, x, y)
                and result[key(cell.x + offset[1], cell.y)]
                and result[key(cell.x, cell.y + offset[2])] then
                diagonalCandidates[cellKey] = {
                    x = x,
                    y = y,
                    tile = cell.tile,
                    source = cell.source,
                    air = true
                }
            end
        end
    end

    for cellKey, cell in pairs(diagonalCandidates) do
        if not result[cellKey] then
            result[cellKey] = cell
        end
    end

    return result
end

-- Greedy rectangle cover for the expanded tiles. Starting from the top-leftmost unclaimed tile,
-- grow right and down as far as no existing room is touched. Growing over empty cells is fine:
-- every generated room is a full-tile room by construction.
local function cellsToRectanglesForComponent(cells, roomRects)
    local list = {}
    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge

    for _, cell in ipairs(cells) do
        table.insert(list, cell)
        minX = math.min(minX, cell.x)
        minY = math.min(minY, cell.y)
        maxX = math.max(maxX, cell.x)
        maxY = math.max(maxY, cell.y)
    end

    table.sort(list, function(lhs, rhs)
        if lhs.y ~= rhs.y then
            return lhs.y < rhs.y
        end

        return lhs.x < rhs.x
    end)

    local covered = {}

    local function isFree(x, y)
        if x < minX or x > maxX or y < minY or y > maxY then
            return false
        end

        if covered[key(x, y)] then
            return false
        end

        for _, rect in ipairs(roomRects) do
            if x >= rect.x1 and x <= rect.x2 and y >= rect.y1 and y <= rect.y2 then
                return false
            end
        end

        return true
    end

    local function isRectFree(x1, y1, x2, y2)
        for y = y1, y2 do
            for x = x1, x2 do
                if not isFree(x, y) then
                    return false
                end
            end
        end

        return true
    end

    local function makeRectangle(x1, y1, x2, y2)
        return {
            x1 = x1,
            y1 = y1,
            x2 = x2,
            y2 = y2
        }
    end

    local rectangles = {}

    for _, cell in ipairs(list) do
        if not covered[key(cell.x, cell.y)] and isFree(cell.x, cell.y) then
            local x1, y1 = cell.x, cell.y
            local x2 = x1

            while isRectFree(x1, y1, x2 + 1, y1) do
                x2 = x2 + 1
            end

            local y2 = y1

            while isRectFree(x1, y1, x2, y2 + 1) do
                y2 = y2 + 1
            end

            local wideRectangle = makeRectangle(x1, y1, x2, y2)

            -- Also try a tall first pass; whichever covers more area usually needs fewer rooms.
            local tallX2 = x1
            local tallY2 = y1

            while isRectFree(x1, y1, x1, tallY2 + 1) do
                tallY2 = tallY2 + 1
            end

            while isRectFree(x1, y1, tallX2 + 1, tallY2) do
                tallX2 = tallX2 + 1
            end

            local tallRectangle = makeRectangle(x1, y1, tallX2, tallY2)
            local chosen = wideRectangle

            if (tallX2 - x1 + 1) * (tallY2 - y1 + 1)
                > (x2 - x1 + 1) * (y2 - y1 + 1) then
                chosen = tallRectangle
            end

            table.insert(rectangles, chosen)

            for y = chosen.y1, chosen.y2 do
                for x = chosen.x1, chosen.x2 do
                    covered[key(x, y)] = true
                end
            end
        end
    end

    return rectangles
end

local function cellsToRectangles(cells, roomRects)
    local byKey = {}

    for _, cell in ipairs(cells) do
        byKey[key(cell.x, cell.y)] = cell
    end

    local visited = {}
    local components = {}

    for _, cell in ipairs(cells) do
        local startKey = key(cell.x, cell.y)

        if not visited[startKey] then
            local component = {}
            local queue = {cell}
            local queueIndex = 1

            visited[startKey] = true

            while queueIndex <= #queue do
                local current = queue[queueIndex]
                queueIndex = queueIndex + 1

                table.insert(component, current)

                local neighbours = {
                    {current.x + 1, current.y},
                    {current.x - 1, current.y},
                    {current.x, current.y + 1},
                    {current.x, current.y - 1}
                }

                for _, neighbour in ipairs(neighbours) do
                    local neighbourKey = key(neighbour[1], neighbour[2])

                    if byKey[neighbourKey] and not visited[neighbourKey] then
                        visited[neighbourKey] = true
                        table.insert(queue, byKey[neighbourKey])
                    end
                end
            end

            table.insert(components, component)
        end
    end

    table.sort(components, function(lhs, rhs)
        local lhsFirst = lhs[1]
        local rhsFirst = rhs[1]

        if lhsFirst.y ~= rhsFirst.y then
            return lhsFirst.y < rhsFirst.y
        end

        return lhsFirst.x < rhsFirst.x
    end)

    local rectangles = {}

    for _, component in ipairs(components) do
        local componentRoomRects = {}

        for _, rect in ipairs(roomRects) do
            table.insert(componentRoomRects, rect)
        end

        -- Previously generated filler rooms also block later components, so rectangles from
        -- different components cannot overlap.
        for _, rect in ipairs(rectangles) do
            table.insert(componentRoomRects, rect)
        end

        local componentRectangles = cellsToRectanglesForComponent(component, componentRoomRects)

        for _, rect in ipairs(componentRectangles) do
            table.insert(rectangles, rect)
        end
    end

    return rectangles
end

local function rectHitsRooms(rectangle, roomRects)
    for _, roomRect in ipairs(roomRects) do
        if not (rectangle.x2 < roomRect.x1 or rectangle.x1 > roomRect.x2
            or rectangle.y2 < roomRect.y1 or rectangle.y1 > roomRect.y2) then
            return true
        end
    end

    return false
end

local function rectanglesAdjacent(a, b)
    return not (a.x2 + 1 < b.x1 or b.x2 + 1 < a.x1
        or a.y2 + 1 < b.y1 or b.y2 + 1 < a.y1)
end

-- Merge overlapping or touching padded rectangles. Merging is skipped when the resulting
-- bounding box would enter another room.
local function mergeRectangles(rectangles, roomRects)
    local changed = true

    while changed do
        changed = false

        for i = 1, #rectangles - 1 do
            for j = i + 1, #rectangles do
                local a = rectangles[i]
                local b = rectangles[j]

                if rectanglesAdjacent(a, b) then
                    local merged = {
                        x1 = math.min(a.x1, b.x1),
                        y1 = math.min(a.y1, b.y1),
                        x2 = math.max(a.x2, b.x2),
                        y2 = math.max(a.y2, b.y2)
                    }

                    if not rectHitsRooms(merged, roomRects) then
                        rectangles[i] = merged
                        table.remove(rectangles, j)
                        changed = true

                        break
                    end
                end
            end

            if changed then
                break
            end
        end
    end

    return rectangles
end

local function createFillerRoom(name, rectangle, claimed)
    local width = rectangle.x2 - rectangle.x1 + 1
    local height = rectangle.y2 - rectangle.y1 + 1
    local rows = {}

    for y = rectangle.y1, rectangle.y2 do
        local row = {}

        for x = rectangle.x1, rectangle.x2 do
            local cell = claimed[key(x, y)]
            local tile = "0"

            if cell and not cell.air then
                tile = cell.tile
            end

            table.insert(row, tile)
        end

        table.insert(rows, table.concat(row))
    end

    return roomStruct.decode({
        name = name,
        x = rectangle.x1 * 8,
        y = rectangle.y1 * 8,
        width = width * 8,
        height = height * 8,
        __children = {
            {
                __name = "solids",
                innerText = table.concat(rows, "\n")
            }
        }
    })
end

local function getNextName(usedNames)
    local index = 1

    while usedNames[PREFIX .. index] do
        index = index + 1
    end

    return PREFIX .. index
end

local function rectangleHasSolid(rectangle, solidClaimed)
    for y = rectangle.y1, rectangle.y2 do
        for x = rectangle.x1, rectangle.x2 do
            if solidClaimed[key(x, y)] then
                return true
            end
        end
    end

    return false
end

function script.prerun(args, layer)
    args = args or {}

    local map = state.map

    if not map then
        return nil
    end

    local horizontal = clampInteger(args.horizontalExpand)
    local vertical = clampInteger(args.verticalExpand)
    local corner = clampInteger(args.cornerExpand)
    local clearPrevious = args.clearPrevious ~= false

    local targetRooms = getTargetRooms(map, layer)
    local removedRooms = {}

    if clearPrevious then
        for index = #map.rooms, 1, -1 do
            local room = map.rooms[index]

            if isAutoFiller(room)
                and (layer == "allRooms" or autoFillerTouchesRooms(room, targetRooms)) then
                table.insert(removedRooms, room)
                mapItemUtils.deleteItem(map, room, false)
            end
        end
    end

    local roomRects = {}

    for _, room in ipairs(map.rooms) do
        table.insert(roomRects, getTileRect(room))
    end

    local solidClaimed = collectExpandedTiles(targetRooms, roomRects, horizontal, vertical, corner)

    -- The solid tiles stay exactly as far as the Expand settings say. The extra air cells only
    -- enlarge the room rectangle so the tile border can render.
    local claimed = dilateExpandedTiles(solidClaimed, roomRects)
    local cells = {}

    for _, cell in pairs(claimed) do
        table.insert(cells, cell)
    end

    local rectangles = cellsToRectangles(cells, roomRects)
    rectangles = mergeRectangles(rectangles, roomRects)

    -- A padded rectangle can consist only of the surrounding air cells. Never create an empty
    -- filler room for it.
    local filledRectangles = {}

    for _, rectangle in ipairs(rectangles) do
        if rectangleHasSolid(rectangle, solidClaimed) then
            table.insert(filledRectangles, rectangle)
        end
    end

    rectangles = filledRectangles
    local usedNames = {}

    for _, room in ipairs(map.rooms) do
        usedNames[room.name] = true
    end

    local addedRooms = {}

    for _, rectangle in ipairs(rectangles) do
        local name = getNextName(usedNames)

        usedNames[name] = true

        local room = createFillerRoom(name, rectangle, claimed)

        table.insert(addedRooms, room)
        mapItemUtils.addItem(map, room, false)
    end

    if #removedRooms == 0 and #addedRooms == 0 then
        return nil
    end

    local function applyForward()
        for _, room in ipairs(removedRooms) do
            mapItemUtils.deleteItem(map, room, false)
        end

        for _, room in ipairs(addedRooms) do
            mapItemUtils.addItem(map, room, false)
        end
    end

    local function applyBackward()
        for index = #addedRooms, 1, -1 do
            mapItemUtils.deleteItem(map, addedRooms[index], false)
        end

        for _, room in ipairs(removedRooms) do
            mapItemUtils.addItem(map, room, false)
        end
    end

    return snapshotStruct.create("Auto Add Filler", {}, applyBackward, applyForward)
end

return script
