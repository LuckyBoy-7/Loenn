local toolHandler = require("tools")
local toolUtils = require("tool_utils")

local state = require("loaded_state")
local viewport = require("viewport_handler")
local utils = require("utils")
local persistence = require("persistence")
local configs = require("configs")
local keyboardHelper = require("utils.keyboard")
local subLayers = require("sub_layers")
local hotkeyStruct = require("structs.hotkey")
local hotkeyHandler = require("hotkey_handler")

local function getToolEventHandler(event)
    if state.map ~= nil then
        local currentTool = toolHandler.currentTool

        if currentTool and currentTool[event] then
            return currentTool[event]
        end
    end

    return function(...) end
end

local toolProxyMt = {
    __index = function(self, event)
        return getToolEventHandler(event)
    end
}

local device = setmetatable({_enabled = true, _type = "device"}, toolProxyMt)

-- The selection can hold a copy of the clicked item, so compare by value: a reference check made
-- every click on an already selected filler look like a new selection and swallowed the click
local function sameItem(a, b)
    if a == b then
        return true
    end

    if not a or not b then
        return false
    end

    local typeA, typeB = utils.typeof(a), utils.typeof(b)

    if typeA ~= typeB then
        return false
    end

    if typeA == "room" then
        return a.name == b.name
    end

    if typeA == "filler" then
        return a.x == b.x and a.y == b.y and a.width == b.width and a.height == b.height
    end

    return false
end

local function tryRoomSwap(x, y, button, istouch, presses)
    if state.map ~= nil then
        local currentTool = toolHandler.currentTool
        local actionButton = configs.editor.toolActionButton
        local addModifier = configs.editor.selectionAddModifier

        -- Tools are unloaded and reloaded by the debug reload actions, and a plugin tool may fail
        -- to load. Do not let a click during that window crash the editor.
        if not currentTool then
            return false
        end

        if currentTool.manualRoomLogic then
            return false
        end

        if button == actionButton then
            local mapX, mapY = viewport.getMapCoordinates(x, y)
            local itemClicked = utils.getRoomAtCoords(mapX, mapY, state.map) or utils.getFillerAtCoords(mapX, mapY, state.map)
            local addModifierHeld = keyboardHelper.modifierHeld(addModifier)
            local currentItem = state.getSelectedItem()

            if itemClicked and not sameItem(itemClicked, currentItem) then
                state.selectItem(itemClicked, addModifierHeld)

                return true
            end
        end
    end
end

-- Make sure we don't send release/click events for room swaps
local consumeNextRelease = false

function device.mousereleased(x, y, button, istouch, presses, click)
    if consumeNextRelease then
        consumeNextRelease = false

        return true
    end

    local currentTool = toolHandler.currentTool

    if click then
        local consume = tryRoomSwap(x, y, button, istouch, presses)

        if consume then
            consumeNextRelease = true

            return true
        end
    end

    if currentTool and currentTool.mousereleased then
        currentTool.mousereleased(x, y, button, istouch, presses, click)
    end
end

function device.mouseclicked(x, y, button, istouch, presses)
    consumeNextRelease = false

    local consume = tryRoomSwap(x, y, button, istouch, presses)
    local currentTool = toolHandler.currentTool

    if consume then
        consumeNextRelease = true

        return true
    end

    if currentTool and currentTool.mouseclicked then
        currentTool.mouseclicked(x, y, button, istouch, presses)
    end
end

function device.editorToolChanged(tool)
    persistence.toolName = tool.name
end

function device.editorToolModeChanged(tool, mode)
    toolUtils.setPersistenceMode(tool, mode)
end

function device.editorToolLayerChanged(tool, layer, subLayer)
    local layerName = subLayers.formatLayerName(layer, subLayer)

    toolUtils.setPersistenceLayer(tool, layerName)
end

function device.editorToolMaterialChanged(tool, layer, material)
    toolUtils.setPersistenceMaterial(tool, layer, material)
end

function device.keypressed(...)
    local scopes = {}
    local registeredHotkeys = hotkeyHandler.registeredHotkeys

    toolHandler.addHotkeyScopes(scopes)

    local handled = hotkeyStruct.callbackFirstActive(registeredHotkeys, scopes, ...)

    if not handled then
        return getToolEventHandler("keypressed")(...)
    end

    return handled
end

return device