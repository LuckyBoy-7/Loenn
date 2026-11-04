-- Layout of trigger labels: the text rectangle, stretching so whole words stay
-- visible, moving overlapping labels apart and hit testing clicks on them.
--
-- Ported from FontLoennPlugin so the editor does not need the mod anymore.

local configs = require("configs")
local fonts = require("fonts")
local utils = require("utils")

local triggerText = {}

local PADDING = 3
local MAX_ITERATIONS = 16
local CENTER_TOLERANCE = 7
local NEIGHBOUR_PADDING = 3
local NEIGHBOUR_PADDING_MAX = 6

local wordWidthCache = {}
local roomRects = {}
local roomSignatures = {}

-- --------------------------------------------------------------------------
-- Text rectangle
-- --------------------------------------------------------------------------

-- Rectangle the label actually covers inside the trigger, centered like
-- drawableText draws it
function triggerText.getRect(text, x, y, width, height, font, fontSize)
    font = font or fonts.font
    fontSize = fontSize or 1

    text = utils.trim(text)

    local fontHeight = font:getHeight()
    local fontLineHeight = font:getLineHeight()
    local _, lines = font:getWrap(text, width / fontSize)
    local textHeight = (#lines - 1) * (fontHeight * fontLineHeight) + fontHeight

    local maxWidth = 0

    for i = 1, #lines do
        local lineWidth = font:getWidth(lines[i])

        if lineWidth > maxWidth then
            maxWidth = lineWidth
        end
    end

    local actualWidth = maxWidth * fontSize
    local offsetX = math.floor((width - actualWidth) / 2) + 1
    local offsetY = math.floor((height - textHeight * fontSize) / 2) + 1

    return {
        x = x + offsetX,
        y = y + offsetY,
        width = actualWidth,
        height = textHeight * fontSize
    }
end

-- Widens the box around its center when the longest word does not fit, so words
-- are not cut in half. Uses the same font metrics the label is drawn with.
function triggerText.stretchRect(x, y, width, height, text, fontSize)
    if not configs.font.showCompleteTriggerText then
        return x, y, width, height
    end

    fontSize = fontSize or 1

    local maxWidth = wordWidthCache[text]

    if not maxWidth then
        maxWidth = 0

        for line in (text .. "\n"):gmatch("(.-)\n") do
            line = utils.trim(line)

            local parenthesized = line:sub(1, 1) == "(" and line:sub(-1) == ")"

            if parenthesized then
                maxWidth = math.max(maxWidth, fonts.font:getWidth(line) * fontSize)

            else
                for word in line:gmatch("[^%s]+") do
                    maxWidth = math.max(maxWidth, fonts.font:getWidth(word) * fontSize)
                end
            end
        end

        -- Wrapping divides the width by the font size again, rounding errors
        -- would otherwise split an exactly fitting word into two lines
        maxWidth = math.ceil(maxWidth) + 1

        wordWidthCache[text] = maxWidth
    end

    if maxWidth > width then
        x = x - (maxWidth - width) / 2
        width = maxWidth
    end

    return x, y, width, height
end

-- --------------------------------------------------------------------------
-- Overlap extrusion (small separation solver, ported from the plugin)
-- --------------------------------------------------------------------------

local function center(rect)
    return rect.x + rect.width / 2, rect.y + rect.height / 2
end

local function isOutsideRoom(rect, roomRect)
    if not roomRect or not configs.font.ignoreOutOfRoomTextExtruding then
        return false
    end

    return rect.x + rect.width < roomRect.x
        or rect.x > roomRect.x + roomRect.width
        or rect.y + rect.height < roomRect.y
        or rect.y > roomRect.y + roomRect.height
end

local function isOverlapping(a, b, padding)
    return not (a.x + a.width <= b.x - 2 * padding
        or a.x >= b.x + b.width + 2 * padding
        or a.y + a.height <= b.y - 2 * padding
        or a.y >= b.y + b.height + 2 * padding)
end

local function getOverlap(a, b, padding)
    local overlapX = math.min(a.x + a.width, b.x + b.width) - math.max(a.x, b.x) + 2 * padding
    local overlapY = math.min(a.y + a.height, b.y + b.height) - math.max(a.y, b.y) + 2 * padding

    return overlapX, overlapY
end

local function centersClose(a, b)
    local ax, ay = center(a)
    local bx, by = center(b)

    return math.abs(ax - bx) <= CENTER_TOLERANCE and math.abs(ay - by) <= CENTER_TOLERANCE
end

local function sign(value)
    return value > 0 and 1 or value < 0 and -1 or 0
end

-- --------------------------------------------------------------------------
-- Spatial grid
--
-- The solver only ever compares labels that are close to each other, so a
-- uniform grid keeps it from testing every pair in the room (which made big
-- rooms with many triggers very slow).
-- --------------------------------------------------------------------------

local GRID_CELL_SIZE = 64

local function gridKey(gx, gy)
    return gx * 100003 + gy
end

local function addToGrid(grid, index, rect)
    local firstX = math.floor(rect.x / GRID_CELL_SIZE)
    local firstY = math.floor(rect.y / GRID_CELL_SIZE)
    local lastX = math.floor((rect.x + rect.width) / GRID_CELL_SIZE)
    local lastY = math.floor((rect.y + rect.height) / GRID_CELL_SIZE)

    for gx = firstX, lastX do
        for gy = firstY, lastY do
            local key = gridKey(gx, gy)
            local cell = grid[key]

            if not cell then
                cell = {}
                grid[key] = cell
            end

            cell[#cell + 1] = index
        end
    end
end

local function buildGrid(rects)
    local grid = {}

    for index, rect in ipairs(rects) do
        addToGrid(grid, index, rect)
    end

    return grid
end

-- Calls the callback for every pair of labels that share a grid cell, each pair
-- exactly once
local function forEachNearbyPair(grid, callback)
    local seen = {}

    for _, cell in pairs(grid) do
        local count = #cell

        for i = 1, count - 1 do
            local a = cell[i]

            for j = i + 1, count do
                local b = cell[j]
                local low, high = a, b

                if low > high then
                    low, high = high, low
                end

                local key = low * 100003 + high

                if not seen[key] then
                    seen[key] = true

                    callback(low, high)
                end
            end
        end
    end
end

-- Rectangles whose centers are close are arranged in a row or column instead of
-- being pushed around
local function disperseGroups(rects, roomRect)
    local grid = {}
    local processed = {}

    for i = 1, #rects do
        if not isOutsideRoom(rects[i], roomRect) then
            local cx, cy = center(rects[i])

            local key = gridKey(math.floor(cx / GRID_CELL_SIZE), math.floor(cy / GRID_CELL_SIZE))
            local cell = grid[key]

            if not cell then
                cell = {}
                grid[key] = cell
            end

            cell[#cell + 1] = i
        end
    end

    for _, cell in pairs(grid) do
        local count = #cell

        for i = 1, count - 1 do
            local firstIndex = cell[i]

            if not processed[firstIndex] then
                processed[firstIndex] = true

                local group = {firstIndex}

                for j = i + 1, count do
                    local otherIndex = cell[j]

                    if not processed[otherIndex] and centersClose(rects[firstIndex], rects[otherIndex]) then
                        group[#group + 1] = otherIndex
                        processed[otherIndex] = true
                    end
                end

                if #group > 1 then
                    local base = rects[group[1]]
                    local baseX, baseY = center(base)
                    local totalWidth = (PADDING + base.width) * #group - PADDING
                    local totalHeight = (PADDING + base.height) * #group - PADDING
                    local startX = baseX - totalWidth / 2
                    local startY = baseY - totalHeight / 2

                    for position, rectIndex in ipairs(group) do
                        local rect = rects[rectIndex]
                        local newX, newY

                        if rect.height > rect.width then
                            newX = startX + (position - 1) * (PADDING + base.width)
                            newY = baseY - rect.height / 2

                        else
                            newY = startY + (position - 1) * (PADDING + base.height)
                            newX = baseX - rect.width / 2
                        end

                        rect.offsetX = (rect.offsetX or 0) + newX - rect.x
                        rect.offsetY = (rect.offsetY or 0) + newY - rect.y
                        rect.x = newX
                        rect.y = newY
                    end
                end
            end
        end
    end
end

local function separate(rects, roomRect, neighbourCount, outOfRoom)
    local moves = {}

    for i = 1, #rects do
        moves[i] = {dx = 0, dy = 0, count = 0}
    end

    local grid = buildGrid(rects)

    forEachNearbyPair(grid, function(i, j)
        if outOfRoom[i] or outOfRoom[j] then
            return
        end

        local density = (neighbourCount[i] + neighbourCount[j]) / 2
        local padding = math.min(PADDING * density / NEIGHBOUR_PADDING_MAX, PADDING)
        local overlapX, overlapY = getOverlap(rects[i], rects[j], padding)

        if overlapX > 0 and overlapY > 0 then
            local ax, ay = center(rects[i])
            local bx, by = center(rects[j])
            local dx, dy = bx - ax, by - ay
            local distance = math.sqrt(dx * dx + dy * dy)

            if distance < 0.001 then
                dx, dy = 0, 1
                distance = 1
            end

            local directionX, directionY = dx / distance, dy / distance
            local separation = math.min(overlapX, overlapY) / 2

            if overlapX < overlapY then
                directionX = sign(directionX)
                directionY = 0

            else
                directionX = 0
                directionY = sign(directionY)
            end

            moves[i].dx = moves[i].dx - directionX * separation
            moves[i].dy = moves[i].dy - directionY * separation
            moves[i].count = moves[i].count + 1

            moves[j].dx = moves[j].dx + directionX * separation
            moves[j].dy = moves[j].dy + directionY * separation
            moves[j].count = moves[j].count + 1
        end
    end)

    for i = 1, #rects do
        local move = moves[i]

        if move.count > 0 then
            local dx, dy = move.dx / move.count, move.dy / move.count

            rects[i].offsetX = (rects[i].offsetX or 0) + dx
            rects[i].offsetY = (rects[i].offsetY or 0) + dy
            rects[i].x = rects[i].x + dx
            rects[i].y = rects[i].y + dy
        end
    end
end

-- Moves overlapping labels apart and returns nothing, the result is stored in
-- the rects themselves as offsetX/offsetY
local function extrude(rects, roomRect)
    local neighbourCount = {}
    local outOfRoom = {}

    for i = 1, #rects do
        neighbourCount[i] = 0
        outOfRoom[i] = isOutsideRoom(rects[i], roomRect)
    end

    forEachNearbyPair(buildGrid(rects), function(i, j)
        if isOverlapping(rects[i], rects[j], NEIGHBOUR_PADDING) then
            neighbourCount[i] = neighbourCount[i] + 1
            neighbourCount[j] = neighbourCount[j] + 1
        end
    end)

    disperseGroups(rects, roomRect)

    for _ = 1, MAX_ITERATIONS do
        separate(rects, roomRect, neighbourCount, outOfRoom)
    end
end

-- --------------------------------------------------------------------------
-- Per room cache
-- --------------------------------------------------------------------------

-- Computes (and caches) where every trigger label is drawn in the room.
--
-- This runs on every frame that rebuilds the room batches, so it first checks a
-- cheap signature and only runs the (quadratic) overlap solver when a label
-- actually changed.
function triggerText.updateRoom(room, triggerList)
    local roomName = room.name
    local triggers = require("triggers")

    -- Same size the label is drawn with, otherwise the boxes and the overlap
    -- solver work with the wrong text metrics
    local fontSize = fonts.size(triggers.triggerFontSize)

    -- Cheap numeric signature: this runs on every frame that the room batches
    -- are requested, so it must not build strings or call into trigger text
    local signature = #triggerList

    for index, trigger in ipairs(triggerList) do
        signature = signature * 31
            + (trigger.x or 0) * 3
            + (trigger.y or 0) * 5
            + (trigger.width or 16) * 7
            + (trigger.height or 16) * 11

        signature = signature % 1000000007
    end

    signature = signature + (fonts.useHires and 0.5 or 0)

    if roomSignatures[roomName] == signature then
        return
    end

    roomSignatures[roomName] = signature

    local rects = {}
    local byTrigger = {}

    for index, trigger in ipairs(triggerList) do
        local text = triggers.triggerText(room, trigger)
        local x, y = trigger.x or 0, trigger.y or 0
        local width, height = trigger.width or 16, trigger.height or 16

        x, y, width, height = triggerText.stretchRect(x, y, width, height, text, fontSize)
        rects[index] = triggerText.getRect(text, x, y, width, height, fonts.font, fontSize)
    end

    if configs.font.extrudeOverlappingTriggerText then
        extrude(rects, {x = 0, y = 0, width = room.width or 0, height = room.height or 0})
    end

    for index, trigger in ipairs(triggerList) do
        byTrigger[trigger] = rects[index]
    end

    roomRects[roomName] = byTrigger
end

function triggerText.invalidate(room)
    if room and room.name then
        roomSignatures[room.name] = nil
    end
end

function triggerText.getOffset(trigger, room)
    local rects = room and roomRects[room.name]

    if not rects or not rects[trigger] then
        return 0, 0
    end

    return rects[trigger].offsetX or 0, rects[trigger].offsetY or 0
end

-- Returns the trigger whose label contains the point, if any
function triggerText.findTriggerAt(room, x, y)
    local rects = roomRects[room.name]

    if not rects then
        return nil
    end

    for trigger, rect in pairs(rects) do
        if x >= rect.x and x < rect.x + rect.width and y >= rect.y and y < rect.y + rect.height then
            return trigger
        end
    end
end

function triggerText.clearCache()
    wordWidthCache = {}
    roomRects = {}
    roomSignatures = {}
end

-- Text metrics change with the font, and so do the cached label rectangles
fonts.addOnChanged(function()
    triggerText.clearCache()

    local success, celesteRender = pcall(require, "celeste_render")

    if success then
        celesteRender.clearBatchingTasks()
        celesteRender.invalidateRoomCache()
    end
end)

return triggerText
