-- Flip Room: mirrors the room content (tiles, entities, triggers, decals) and/or moves the room
-- itself to the other side of the map. Ported from LuckyHelper's flip_room script and refactored
-- for the scripts tool: the undo snapshots are created by the tool itself.

local brushHelper = require("brushes")
local selectionUtils = require("selections")

local script = {}

script.name = "flipRoom"
script.title = "Flip Room"
script.description = "Flips the room content and/or the room position."

script.fieldOrder = {
    "flipContentHorizontal",
    "flipContentVertical",
    "flipRoomHorizontal",
    "flipRoomVertical",
    "radicalFlip"
}

script.defaultData = {
    flipContentHorizontal = true,
    flipContentVertical = false,
    flipRoomHorizontal = false,
    flipRoomVertical = false,
    radicalFlip = true
}

script.tooltips = {
    radicalFlip = "Also swaps directions in entity names (spikesLeft to spikesRight, spikesUp to spikesDown, ...). May break some entities."
}

--- Position corrections for entities whose graphic anchor is not their hitbox (spikes, springs)

local entityOffset = {
    triggerspike = {
        horizontal = {left = {3, 0}, right = {3, 0}},
        vertical = {up = {0, 3}, down = {0, 3}}
    },
    spike = {
        horizontal = {left = {6, 0}, right = {6, 0}},
        vertical = {up = {0, 6}, down = {0, 6}}
    },
    spring = {
        horizontal = {left = {3, 0}, right = {3, 0}, down = {12, 0}, up = {12, 0}},
        vertical = {left = {0, 12}, right = {0, 12}, down = {0, 3}, up = {0, 3}}
    }
}

local horizontalDirectionMapping = {left = "right", right = "left", Left = "Right", Right = "Left"}
local verticalDirectionMapping = {up = "down", down = "up", Up = "Down", Down = "Up"}

local axisX = {
    getPos = function(value) return value.x end,
    setPos = function(value, position) value.x = position end,
    getSize = function(value) return value.width end
}

local axisY = {
    getPos = function(value) return value.y end,
    setPos = function(value, position) value.y = position end,
    getSize = function(value) return value.height end
}

local function entityNameIs(entity, text)
    return entity._name and entity._name:lower():find(text) ~= nil
end

local function entityIsSpecial(entity)
    for key in pairs(entityOffset) do
        if entityNameIs(entity, key) then
            return true
        end
    end

    return false
end

local function flipRectangle(room, rectangle)
    rectangle.x = room.width - rectangle.x - rectangle.width
    rectangle.y = room.height - rectangle.y - rectangle.height

    return rectangle
end

-- Flipped position based on the selection rectangle: keeps scaled/justified items in place
local function getFlippedPosWithSelectionRectangle(room, entity, selectionRectangle, axis)
    local size = axis.getSize(selectionRectangle)
    local leftPadding = axis.getPos(entity) - axis.getPos(selectionRectangle)
    local rightPadding = size - leftPadding

    return axis.getSize(room) - axis.getPos(selectionRectangle) - rightPadding
end

-- Flipped position based on the entity position: used for spikes/springs, whose selection is
-- based on their sprite and differs between directions
local function getFlippedPosWithEntityPos(room, entity, selectionRectangle, axis)
    local size = axis.getSize(entity)

    if size == nil then
        size = axis.getSize(selectionRectangle)
    end

    return axis.getSize(room) - axis.getPos(entity) - size
end

local function addCorrectedOffsetToEntity(entity, horizontal)
    local name = entity._name:lower()
    local direction = "up"

    if name:find("left") then
        direction = "left"

    elseif name:find("right") then
        direction = "right"

    elseif name:find("down") then
        direction = "down"
    end

    -- Longest matching key wins (triggerSpike before spike)
    local matchedType

    for key in pairs(entityOffset) do
        if name:find(key, 1, true) and (not matchedType or #key > #matchedType) then
            matchedType = key
        end
    end

    if not matchedType then
        return
    end

    local axisType = horizontal and "horizontal" or "vertical"
    local offset = entityOffset[matchedType][axisType][direction] or {0, 0}

    entity.x = entity.x + offset[1]
    entity.y = entity.y + offset[2]
end

local function invertLeftField(entity, horizontal)
    if not horizontal then
        return
    end

    if type(entity.left) == "boolean" then
        entity.left = not entity.left
    end

    if type(entity.leftSide) == "boolean" then
        entity.leftSide = not entity.leftSide
    end

    -- Puffer (eyebomb) stores its direction in "right"
    if entityNameIs(entity, "eyebomb") and type(entity.right) == "boolean" then
        entity.right = not entity.right
    end
end

local function invertDownField(entity, vertical)
    if vertical and entityNameIs(entity, "dashswitch") and type(entity.ceiling) == "boolean" then
        entity.ceiling = not entity.ceiling
    end
end

local function invertDirection(entity, horizontal)
    if not entityNameIs(entity, "moveblock") or entity.direction == nil then
        return
    end

    local mapping = horizontal and horizontalDirectionMapping or verticalDirectionMapping
    local flipped = mapping[entity.direction]

    if flipped then
        entity.direction = flipped
    end
end

local function swapDirectionInName(entity, horizontal)
    local name = entity._name

    if not name then
        return
    end

    if horizontal then
        name = name:gsub("Left", "__TMP__"):gsub("Right", "Left"):gsub("__TMP__", "Right")
        name = name:gsub("left", "__tmp__"):gsub("right", "left"):gsub("__tmp__", "right")
        name = name:gsub("LEFT", "__TMP2__"):gsub("RIGHT", "LEFT"):gsub("__TMP2__", "RIGHT")

    else
        name = name:gsub("Up", "__TMP3__"):gsub("Down", "Up"):gsub("__TMP3__", "Down")
        name = name:gsub("up", "__tmp4__"):gsub("down", "up"):gsub("__tmp4__", "down")
        name = name:gsub("UP", "__TMP5__"):gsub("DOWN", "UP"):gsub("__TMP5__", "DOWN")
    end

    entity._name = name
end

-- Decals are flipped by their sprite, which can contain empty space: after mirroring the scale the
-- sprite position has to be corrected so the visible part stays inside the flipped rectangle
local function reverseDecalScale(entity, room, layer, horizontal, flippedRectangle)
    local flipX = entity.scaleX ~= nil and horizontal
    local flipY = entity.scaleY ~= nil and not horizontal

    if flipX then
        entity.scaleX = entity.scaleX * -1
    end

    if flipY then
        entity.scaleY = entity.scaleY * -1
    end

    local selection = selectionUtils.getSelectionsForItem(room, layer, entity)
    local rectangleAfterScale = selection and selection[1]

    if not rectangleAfterScale then
        return
    end

    if flipX then
        entity.x = entity.x + flippedRectangle.x - rectangleAfterScale.x
    end

    if flipY then
        entity.y = entity.y + flippedRectangle.y - rectangleAfterScale.y
    end
end

local function flipItemByAxis(room, entity, layer, axis, radicalFlip)
    if entity == nil then
        return
    end

    local isEntity = layer == "entities"
    local isDecal = layer == "decalsBg" or layer == "decalsFg"
    local horizontal = axis == axisX
    local selection = selectionUtils.getSelectionsForItem(room, layer, entity)

    if not selection or not selection[1] then
        return
    end

    -- Nodes are flipped relative to their own rectangles first
    if entity.nodes then
        for index, node in ipairs(entity.nodes) do
            local nodeRectangle = selection[index + 1]

            if nodeRectangle then
                axis.setPos(node, getFlippedPosWithSelectionRectangle(room, node, nodeRectangle, axis))
            end
        end
    end

    local mainRectangle = selection[1]

    if isEntity and entityIsSpecial(entity) then
        axis.setPos(entity, getFlippedPosWithEntityPos(room, entity, mainRectangle, axis))
        addCorrectedOffsetToEntity(entity, horizontal)

    else
        axis.setPos(entity, getFlippedPosWithSelectionRectangle(room, entity, mainRectangle, axis))
    end

    if isEntity and radicalFlip then
        swapDirectionInName(entity, horizontal)
        invertLeftField(entity, horizontal)
        invertDownField(entity, not horizontal)
        invertDirection(entity, horizontal)
    end

    if isDecal then
        reverseDecalScale(entity, room, layer, horizontal, flipRectangle(room, mainRectangle))
    end
end

local function flipItem(room, item, layer, horizontal, vertical, radicalFlip)
    if horizontal then
        flipItemByAxis(room, item, layer, axisX, radicalFlip)
    end

    if vertical then
        flipItemByAxis(room, item, layer, axisY, radicalFlip)
    end
end

local function flipItems(room, horizontal, vertical, radicalFlip)
    for _, entity in ipairs(room.entities or {}) do
        flipItem(room, entity, "entities", horizontal, vertical, radicalFlip)
    end

    for _, trigger in ipairs(room.triggers or {}) do
        flipItem(room, trigger, "triggers", horizontal, vertical, false)
    end

    for _, decal in ipairs(room.decalsFg or {}) do
        flipItem(room, decal, "decalsFg", horizontal, vertical, false)
    end

    for _, decal in ipairs(room.decalsBg or {}) do
        flipItem(room, decal, "decalsBg", horizontal, vertical, false)
    end
end

local function flipTiles(room, horizontal, vertical)
    for _, layer in ipairs({"tilesFg", "tilesBg"}) do
        local tiles = room[layer]

        if tiles and tiles.matrix then
            tiles.matrix:flip(horizontal, vertical)

            -- Re-run the autotile pass so the flipped edges get the correct tiles
            brushHelper.placeTile(room, 1, 1, tiles.matrix, layer)
        end
    end
end

local function flipRoomPosition(room, horizontal, vertical)
    if horizontal then
        room.x = -room.x - room.width
    end

    if vertical then
        room.y = -room.y - room.height
    end
end

function script.run(room, args)
    if not room then
        return
    end

    local horizontal = args.flipContentHorizontal == true
    local vertical = args.flipContentVertical == true

    flipTiles(room, horizontal, vertical)
    flipItems(room, horizontal, vertical, args.radicalFlip == true)

    flipRoomPosition(room, args.flipRoomHorizontal == true, args.flipRoomVertical == true)
end

return script
