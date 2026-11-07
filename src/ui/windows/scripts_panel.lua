-- Floating parameter panel for scripts that need configuration before running

local ui = require("ui")
local uiElements = require("ui.elements")
local widgetUtils = require("ui.widgets.utils")
local form = require("ui.forms.form")
local languageRegistry = require("language_registry")
local utils = require("utils")

local scriptsPanel = {}

local panelGroup
local currentWindow

function scriptsPanel.open(script, context, runCallback)
    if not script.fieldOrder or #script.fieldOrder == 0 then
        return
    end

    local language = languageRegistry.getLanguage()

    local buttons = {
        {
            text = tostring(language.ui.script_window.run_script),
            formMustBeValid = true,
            callback = function(formFields)
                local values = form.getFormData(formFields)

                if currentWindow then
                    widgetUtils.closeWindow(currentWindow)
                    currentWindow = nil
                end

                runCallback(values)
            end
        }
    }

    local body = form.getForm(buttons, utils.deepcopy(script.defaultData or {}), {
        fields = script.fieldInformation or {},
        fieldOrder = script.fieldOrder or {},
        formFieldChanged = function() end
    })

    if currentWindow then
        widgetUtils.closeWindow(currentWindow)
    end

    local window = uiElements.window(script.title, body)

    currentWindow = window

    local parent = panelGroup and panelGroup.parent or ui.root

    parent:addChild(window)
    widgetUtils.addWindowCloseButton(window, function(w)
        currentWindow = nil

        return true
    end)
    widgetUtils.preventOutOfBoundsMovement(window)
    widgetUtils.consumeKeyboardEvents(window)
    widgetUtils.centerWindow(window)
end

function scriptsPanel.getWindow()
    panelGroup = uiElements.group({})

    return panelGroup
end

return scriptsPanel
