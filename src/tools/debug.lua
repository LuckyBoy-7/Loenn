-- Debug tool: lists the entities / triggers that are actually used in the map and draws a line
-- from the top of the window to every usage of the selected one. It takes over the job the
-- coordinate panel had before: selecting this tool opens the panel, leaving it closes the panel.
-- Clicking inside the focused room teleports the running game there through Everest's DebugRC.

local loadedState = require("loaded_state")
local viewportHandler = require("viewport_handler")
local drawing = require("utils.drawing")
local configs = require("configs")
local keyboardHelper = require("utils.keyboard")
local languageRegistry = require("language_registry")
local notifications = require("ui.notification")
local drawableSprite = require("structs.drawable_sprite")
local debugRC = require("debug_rc")

local tool = {}

tool._type = "tool"
tool.name = "debug"
tool.group = "debug"
tool.order = 10

-- Room logic is left to the default handling, so clicking a room changes focus
-- like it does for every other tool

-- The two lists the tool can show, both with an eye in the tools window
tool.validLayers = {"entities", "triggers"}

tool.layer = "entities"
tool.subLayer = -1

-- Entity / trigger name whose usages are highlighted
local selectedName

-- Player preview that shows where a click would teleport to
local playerSprite

-- Room relative position of the cursor, snapped to the tile grid unless the precision
-- modifier is held. Returns nil when the cursor is outside of the room
local function getRoomCursorPosition(room, x, y)
    local precise = keyboardHelper.modifierHeld(configs.editor.precisionModifier)
    local roomX, roomY = viewportHandler.getRoomCoordinates(room, x, y)

    if not precise then
        -- Vertically snapped to the bottom of the tile, so the player stands on the ground
        roomX = math.floor(roomX / 8 + 0.5) * 8
        roomY = math.floor(roomY / 8 + 1) * 8
    end

    if roomX < 0 or roomY < 0 or roomX >= (room.width or 0) or roomY >= (room.height or 0) then
        return
    end

    return roomX, roomY
end

local function getUsedNames(layer)
    local map = loadedState.map
    local counts = {}

    if not map then
        return counts
    end

    for _, room in ipairs(map.rooms or {}) do
        for _, item in ipairs(room[layer] or {}) do
            local name = item._name

            if name then
                counts[name] = (counts[name] or 0) + 1
            end
        end
    end

    return counts
end

local function getLeafName(name)
    return string.match(name, "([^/]+)$") or name
end

-- Materials for the tools window: every used entity / trigger, grouped by mod there
function tool.getMaterials(layer)
    layer = layer or tool.layer

    local counts = getUsedNames(layer)
    local names = table.keys(counts)

    table.sort(names)

    local materials = {}

    for _, name in ipairs(names) do
        local modName = string.match(name, "^([^/]+)/")

        table.insert(materials, {
            name = name,
            associatedMods = modName and {modName} or nil,
            displayNameNoMods = string.format("%s (%d)", getLeafName(name), counts[name])
        })
    end

    return materials
end

function tool.setMaterial(name)
    selectedName = name

    return true
end

function tool.getMaterial()
    return selectedName
end

function tool.setLayer(layer, subLayer)
    tool.layer = layer or "entities"
    tool.subLayer = subLayer or -1
    selectedName = nil

    return true
end

function tool.selected()
    require("ui/windows/coordinate_window").open()
end

function tool.unselected()
    selectedName = nil
    tool.material = nil

    require("ui/windows/coordinate_window").close()
end

-- Teleports the running game to the clicked position inside the focused room
function tool.mouseclicked(x, y, button)
    if button ~= configs.editor.toolActionButton then
        return
    end

    local room = loadedState.getSelectedRoom()

    if not room then
        return
    end

    local roomX, roomY = getRoomCursorPosition(room, x, y)

    if not roomX then
        return
    end

    local success = debugRC.request("/tp", {
        level = room.name,
        x = roomX,
        y = roomY
    })

    if not success then
        notifications.notify(tostring(languageRegistry.getLanguage().ui.notifications.teleportFailed))
    end
end

-- The player preview is drawn one body above the teleport position, which is where the game
-- actually puts the player (its origin is the bottom of the body)
local previewVerticalOffset = 16

-- Kept translucent so the coordinate crosshair below the cursor stays readable
local previewAlpha = 0.35

local function drawPlayerPreview(room)
    local mouseX, mouseY = viewportHandler.getMousePosition()
    local roomX, roomY = getRoomCursorPosition(room, mouseX, mouseY)

    if not roomX then
        return
    end

    if playerSprite == nil then
        local success, sprite = pcall(drawableSprite.fromTexture, "characters/player/sitDown00", {
            justification = {0.5, 1.0}
        })

        if success and sprite then
            sprite.color = {1, 1, 1, previewAlpha}

            playerSprite = sprite

        else
            playerSprite = false
        end
    end

    if not playerSprite then
        return
    end

    playerSprite.x = roomX
    playerSprite.y = roomY - previewVerticalOffset

    viewportHandler.drawRelativeTo(room.x, room.y, function()
        playerSprite:draw()
    end)
end

-- One line per usage, from the top of the window to the item. Drawn after the map, so it sits
-- behind the UI like the other editor overlays
function tool.draw()
    local room = loadedState.getSelectedRoom()

    if room then
        drawPlayerPreview(room)
    end

    if not selectedName then
        return
    end

    local layer = tool.layer

    -- Hidden layers draw nothing
    if not layer or not loadedState.getLayerVisible(layer) then
        return
    end

    local map = loadedState.map

    if not map then
        return
    end

    local viewport = viewportHandler.viewport
    local windowHeight = viewport.height

    drawing.callKeepOriginalColor(function()
        love.graphics.setLineWidth(1)
        love.graphics.setColor(0.35, 0.85, 1, 0.65)

        for _, targetRoom in ipairs(map.rooms or {}) do
            for _, item in ipairs(targetRoom[layer] or {}) do
                if item._name == selectedName then
                    local x = (targetRoom.x or 0) + (item.x or 0) + (item.width or 0) / 2
                    local y = (targetRoom.y or 0) + (item.y or 0) + (item.height or 0) / 2

                    local screenX, screenY = viewportHandler.getWindowCoordinates(x, y)

                    if screenY and screenY >= 0 and screenY <= windowHeight then
                        love.graphics.line(screenX, 0, screenX, screenY)
                        love.graphics.rectangle("fill", screenX - 2, screenY - 2, 5, 5)
                    end
                end
            end
        end
    end)
end

return tool
