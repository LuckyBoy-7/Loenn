-- Add Spinners In Area: right-click a spinner to copy its configuration, then left-click to grow
-- spinners inside a circular area. Alt + mouse wheel changes the radius.

local notifications = require("ui.notification")
local utils = require("utils")
local entities = require("entities")
local placementUtils = require("placement_utils")
local snapshotUtils = require("snapshot_utils")
local history = require("history")
local toolUtils = require("tool_utils")
local loadedState = require("loaded_state")
local languageRegistry = require("language_registry")
local keyboardHelper = require("utils.keyboard")
local colors = require("consts.colors")

local script = {}

script.name = "addSpinnersInArea"
script.title = "Add Spinners In Area"
script.description = "Grows spinners inside a circular area and copies an existing spinner's configuration with right click."

local MIN_RADIUS = 3
local MAX_RADIUS = 10
local DEFAULT_RADIUS = 6

-- Celeste draws connector lines between spinners closer than 24px, so anything below that
-- distance is visually connected. Parent-to-child growth is the only intentional connection.
local SPINNER_CONNECTION_DISTANCE = 24

local SPINNER_MIN_STEP = 18
local SPINNER_MAX_STEP = 22

local defaultSpinnerConfig = {
    _editorLayer = 0,
    _fromLayer = "entities",
    _id = 4587,
    _name = "spinner",
    attachToSolid = false,
    color = "blue",
    dust = false,
    x = 80,
    y = 152
}

local radius = DEFAULT_RADIUS
local copiedSpinnerConfig

local function languageText(key)
    local language = languageRegistry.getLanguage()
    local value = language.scripts
        and language.scripts.addSpinnersInArea
        and language.scripts.addSpinnersInArea[key]

    if value and value._exists ~= false then
        return tostring(value)
    end

    return key
end

local function random()
    return love.math.random()
end

local function randomRange(minimum, maximum)
    return minimum + random() * (maximum - minimum)
end

local function isSpinner(entity)
    local name = entity and entity._name

    return type(name) == "string" and name:lower():find("spinner", 1, true) ~= nil
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

local function collectSpinners(room)
    local spinners = {}

    for _, entity in ipairs(room.entities or {}) do
        if isSpinner(entity) then
            table.insert(spinners, {
                x = entity.x or 0,
                y = entity.y or 0,
                entity = entity
            })
        end
    end

    return spinners
end

local function insideCircle(x, y, centerX, centerY, radiusPixels)
    local dx, dy = x - centerX, y - centerY

    return dx * dx + dy * dy <= radiusPixels * radiusPixels
end

local function insideRoom(x, y, width, height)
    return x >= 0 and y >= 0 and x <= width and y <= height
end

local function isTooClose(spinners, x, y, minimumDistance, ignore)
    local minimumSquared = minimumDistance * minimumDistance

    for _, spinner in ipairs(spinners) do
        if spinner ~= ignore then
            local dx, dy = x - spinner.x, y - spinner.y

            if dx * dx + dy * dy <= minimumSquared then
                return true
            end
        end
    end

    return false
end

local function roundPixel(value)
    return math.floor(value + 0.5)
end

local function placeSpinner(room, x, y)
    local spinner = utils.deepcopy(copiedSpinnerConfig or defaultSpinnerConfig)

    spinner._id = nil
    spinner._type = "entity"
    spinner._editorLayer = 0
    spinner._fromLayer = "entities"
    spinner.x = math.floor(x + 0.5)
    spinner.y = math.floor(y + 0.5)

    placementUtils.placeItem(room, "entities", 0, spinner)
end

local function buildSpinners(centerX, centerY, radiusPixels, existingSpinners, roomWidth, roomHeight)
    -- Use the same 24px cutoff the editor uses to draw spinner connectors. Only the parent-child
    -- growth connection may be below that distance; pre-existing spinners and separate branches
    -- must stay unconnected.
    local originSpinners = existingSpinners
    local newSpinners = {}
    local sampleCount = math.max(1, math.min(4, math.floor(radius / 2)))

    for _ = 1, sampleCount do
        for _ = 1, 32 do
            local angle = randomRange(0, math.pi * 2)
            local distance = math.sqrt(random()) * radiusPixels
            local x = roundPixel(centerX + math.cos(angle) * distance)
            local y = roundPixel(centerY + math.sin(angle) * distance)

            if insideRoom(x, y, roomWidth, roomHeight)
                and insideCircle(x, y, centerX, centerY, radiusPixels)
                and not isTooClose(originSpinners, x, y, SPINNER_CONNECTION_DISTANCE, nil)
                and not isTooClose(newSpinners, x, y, SPINNER_CONNECTION_DISTANCE, nil) then
                local spinner = {x = x, y = y}

                table.insert(newSpinners, spinner)

                break
            end
        end
    end

    if #newSpinners == 0 then
        return newSpinners
    end

    -- Rough upper bound: one spinner per 24x24 area inside the circle
    local maximumSpinners = math.max(1,
        math.floor((math.pi * radiusPixels * radiusPixels) / (SPINNER_CONNECTION_DISTANCE * SPINNER_CONNECTION_DISTANCE)))

    local frontier = {}

    for _, spinner in ipairs(newSpinners) do
        table.insert(frontier, spinner)
    end

    local guard = 0

    while #frontier > 0 and #newSpinners < maximumSpinners and guard < 600 do
        guard = guard + 1

        local index = love.math.random(1, #frontier)
        local parent = frontier[index]
        local placed = false

        for _ = 1, 32 do
            local angle = randomRange(0, math.pi * 2)
            local distance = randomRange(SPINNER_MIN_STEP, SPINNER_MAX_STEP)
            local x = roundPixel(parent.x + math.cos(angle) * distance)
            local y = roundPixel(parent.y + math.sin(angle) * distance)

            if insideRoom(x, y, roomWidth, roomHeight)
                and insideCircle(x, y, centerX, centerY, radiusPixels)
                and not isTooClose(originSpinners, x, y, SPINNER_CONNECTION_DISTANCE, nil)
                and not isTooClose(newSpinners, x, y, SPINNER_CONNECTION_DISTANCE, parent) then
                local spinner = {x = x, y = y}

                table.insert(newSpinners, spinner)
                table.insert(frontier, spinner)

                placed = true
                break
            end
        end

        if not placed then
            table.remove(frontier, index)
        end
    end

    return newSpinners
end

--- Drawing

function script.draw(mouseMapX, mouseMapY)
    local radiusPixels = radius * 8

    love.graphics.setColor(colors.selectionFillColor)
    love.graphics.circle("fill", mouseMapX, mouseMapY, radiusPixels)

    love.graphics.setColor(colors.selectionBorderColor)
    love.graphics.circle("line", mouseMapX, mouseMapY, radiusPixels)
end

--- Entry points

function script.onSelected()
    notifications.notify(languageText("hint"))
end

function script.wheelmoved(dx, dy)
    if not keyboardHelper.modifierHeld("alt") then
        return false
    end

    if dy == 0 then
        return false
    end

    local newRadius = radius + (dy > 0 and 1 or -1)

    newRadius = math.max(MIN_RADIUS, math.min(MAX_RADIUS, newRadius))

    if newRadius ~= radius then
        radius = newRadius
        notifications.notify(string.format(languageText("radius"), radius))
    end

    return true
end

function script.rightclick(context)
    local room = getRoom(context)

    if not room then
        notifications.notify(languageText("no_room"))
        return
    end

    local mouseX, mouseY = getMouseRoomPosition(context, room)
    local entity = getEntityAt(room, mouseX, mouseY)

    if not isSpinner(entity) then
        notifications.notify(languageText("copy_failed"))
        return
    end

    copiedSpinnerConfig = utils.deepcopy(entity)

    notifications.notify(string.format(languageText("copy_success"), entity._name))
end

function script.open(context)
    local room = getRoom(context)

    if not room then
        notifications.notify(languageText("no_room"))
        return
    end

    local mouseX, mouseY = getMouseRoomPosition(context, room)
    local radiusPixels = radius * 8
    local existingSpinners = collectSpinners(room)
    local newSpinners = buildSpinners(mouseX, mouseY, radiusPixels, existingSpinners,
        room.width or 320, room.height or 184)

    if #newSpinners == 0 then
        notifications.notify(languageText("none"))
        return
    end

    local added = 0
    local snapshot = snapshotUtils.roomLayerSnapshot(function()
        for _, spinner in ipairs(newSpinners) do
            placeSpinner(room, spinner.x, spinner.y)
            added = added + 1
        end
    end, room, "entities", "Add Spinners In Area")

    if added > 0 then
        history.addSnapshot(snapshot)
        toolUtils.redrawTargetLayer(room, "entities")
        notifications.notify(string.format(languageText("added"), added))

    else
        notifications.notify(languageText("none"))
    end
end

return script
