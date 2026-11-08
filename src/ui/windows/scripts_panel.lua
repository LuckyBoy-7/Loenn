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

function scriptsPanel.open(script, context, runCallback, options)
    options = options or {}

    if not script.fieldOrder or #script.fieldOrder == 0 then
        return
    end

    local language = languageRegistry.getLanguage()

    local function closePanel()
        if currentWindow then
            widgetUtils.closeWindow(currentWindow)
            currentWindow = nil
            ui.root:recollect()
        end
    end

    scriptsPanel.close = closePanel

    local buttons = {
        {
            text = tostring(options.runButtonText or language.ui.script_window.run_script),
            formMustBeValid = true,
            callback = function(formFields)
                local values = form.getFormData(formFields)

                -- The script can keep the panel open (e.g. when its input was invalid)
                local closeAfterRun = not options.keepOpenOnRun

                if runCallback then
                    closeAfterRun = runCallback(values) ~= false and closeAfterRun
                end

                if closeAfterRun and currentWindow then
                    widgetUtils.closeWindow(currentWindow)
                    currentWindow = nil
                end
            end
        }
    }

    for _, extraButton in ipairs(options.extraButtons or {}) do
        table.insert(buttons, {
            text = tostring(extraButton.text),
            callback = function()
                extraButton.callback()
            end
        })
    end

    local fieldInformation = utils.deepcopy(script.fieldInformation or {})

    for _, field in ipairs(script.fieldOrder) do
        local info = fieldInformation[field] or {}
        fieldInformation[field] = info

        if not info.displayName then
            info.displayName = utils.humanizeVariableName(field)
        end

        if script.tooltips and script.tooltips[field] and not info.tooltipText then
            info.tooltipText = script.tooltips[field]
        end
    end

    local body = form.getForm(buttons, utils.deepcopy(script.defaultData or {}), {
        fields = fieldInformation,
        fieldOrder = script.fieldOrder or {},
        formFieldChanged = function() end
    })

    local previousWindow = currentWindow
    local previousX = previousWindow and previousWindow.x
    local previousY = previousWindow and previousWindow.y

    if previousWindow then
        currentWindow = nil
    end

    -- Creating the window during the input event leaves the UI hit test tree stale until the next
    -- refresh (the window could not be dragged or clicked). Build it after the event instead.
    ui.runLate(function()
        local window = uiElements.window(script.title, body)

        -- Add an optional header (e.g. a style dropdown) directly to the window content: wrapping
        -- the form body in another container left it with a zero height
        if script.header then
            local header = type(script.header) == "function" and script.header() or script.header

            table.insert(window.inner.children, 1, header)
        end

        currentWindow = window

        -- Windows belong in the window group: adding to the root directly would draw the panel
        -- above the tooltip overlay, so tooltips appeared behind the panel
        local uiRoot = require("ui.ui_root")
        local parent = uiRoot.getWindowGroup and uiRoot.getWindowGroup()
            or (panelGroup and panelGroup.parent)
            or ui.root

        parent:addChild(window)

        if previousWindow then
            previousWindow:removeSelf()
        end

        widgetUtils.addWindowCloseButton(window, function(w)
            currentWindow = nil

            w:removeSelf()
            ui.root:recollect()

            return true
        end)
        widgetUtils.preventOutOfBoundsMovement(window)
        widgetUtils.consumeKeyboardEvents(window)
        form.prepareScrollableWindow(window)

        window:layout()
        window:layoutLate()

        -- When the panel is rebuilt (e.g. after switching the style), keep the old position
        if previousX then
            widgetUtils.moveWindow(window, previousX, previousY, 0, 0, 0)

        else
            widgetUtils.centerWindow(window)
        end

        window:layoutLate()

        if ui.root then
            ui.root:recollect()
        end
    end)
end

function scriptsPanel.getWindow()
    panelGroup = uiElements.group({})

    return panelGroup
end

-- Currently open panel window, if any (used for debugging/tests)
function scriptsPanel.getOpenWindow()
    return currentWindow
end

return scriptsPanel
