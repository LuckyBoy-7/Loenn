-- Shared focus bridge for text fields that should open Preview -> Name. It records which form
-- field was focused, switches the tool to Preview -> Name, and lets a Name row replace that field.

local utf8 = require("utf8")

local focus = {}

local focusedFormField
local namePreviewActive = false

local function getToolsWindow()
    local success, toolsWindow = pcall(require, "ui/windows/tools")

    return success and toolsWindow or nil
end

local function switchToNamePreview()
    local toolHandler = require("tools")
    local currentName = toolHandler.currentToolName
    local currentLayer = currentName and toolHandler.getLayer(currentName)
    local targetMode = currentName == "preview" and currentLayer == "name"
        and toolHandler.getMode() or "currentRoom"

    local toolsWindow = getToolsWindow()

    if toolsWindow and toolsWindow.selectTool and toolsWindow.selectLayer then
        toolsWindow.selectTool("preview", true)

        -- Apply the layer and mode before the next frame so the list is never drawn with the
        -- preview tool's previous layer/mode first.
        toolsWindow.selectLayer("name", true, targetMode)

    else
        toolHandler.selectTool("preview")
        toolHandler.setLayer("name")
        toolHandler.setMode(targetMode)
    end

    namePreviewActive = true
end

function focus.onFocus(formField)
    focusedFormField = formField

    local toolHandler = require("tools")

    if not namePreviewActive or toolHandler.currentToolName ~= "preview"
        or toolHandler.getLayer() ~= "name" then
        namePreviewActive = false
        switchToNamePreview()
    end
end

function focus.onBlur(formField)
    if focusedFormField == formField then
        focusedFormField = nil
    end
end

function focus.replaceFocusedField(name)
    if not focusedFormField then
        return false
    end

    focusedFormField:setValue(name)

    local field = focusedFormField.field

    if field then
        field.index = utf8.len(name) or #name
        field.blinkTime = 0
        field:repaint()
    end

    if focusedFormField.notifyFieldChanged then
        focusedFormField:notifyFieldChanged()
    end

    return true
end

return focus
