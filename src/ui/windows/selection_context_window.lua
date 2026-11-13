local ui = require("ui")
local uiElements = require("ui.elements")
local uiUtils = require("ui.utils")

local languageRegistry = require("language_registry")
local utils = require("utils")
local widgetUtils = require("ui.widgets.utils")
local form = require("ui.forms.form")
local snapshotUtils = require("snapshot_utils")
local history = require("history")
local layerHandlers = require("layer_handlers")
local formUtils = require("ui.utils.forms")
local tiles = require("tiles")
local selectionUtils = require("selections")

local windowPersister = require("ui.window_position_persister")
local windowPersisterName = "selection_context_window"

local contextWindow = {}

local contextGroup

local function editorSelectionContextMenuCallback(group, selections, bestSelection, room)
    contextWindow.createContextMenu(selections, bestSelection, room)
end

local function getWindowTitle(language, selections, bestSelection)
    local baseTitle = tostring(language.ui.selection_context_window.title)
    local titleParts = {baseTitle}
    local targetLayer = bestSelection.layer

    if targetLayer == "entities" or targetLayer == "triggers" then
        -- Add entity/trigger name
        table.insert(titleParts, bestSelection.item._name)
    end

    -- Add id for selected items
    local ids = {}
    local seenIds = {}

    for _, selection in ipairs(selections) do
        local selectionId = selection.item._id
        local selectionLayer = selection.layer

        if selectionLayer == "entities" or selectionLayer == "triggers" then
            if selectionId and not seenIds[selectionId] then
                seenIds[selectionId] = true

                table.insert(ids, tostring(selectionId))
            end
        end
    end

    if #ids > 0 then
        table.insert(titleParts, string.format("ID: %s", table.concat(ids, ", ")))
    end

    return table.concat(titleParts, " - ")
end

local function getIgnoredFieldSet(handler, multiple, layer, item)
    local set = {}

    if handler then
        local ignored = utils.callIfFunction(handler.ignoredFields, layer, item) or {}

        for _, name in ipairs(ignored) do
            set[name] = true
        end

        if multiple then
            local ignoredMultiple = utils.callIfFunction(handler.ignoredFieldsMultiple, layer, item) or {}

            for _, name in ipairs(ignoredMultiple) do
                set[name] = true
            end
        end
    end

    return set
end

local function ignoredFieldSetsEqual(lhs, rhs)
    for name in pairs(lhs) do
        if not rhs[name] then
            return false
        end
    end

    for name in pairs(rhs) do
        if not lhs[name] then
            return false
        end
    end

    return true
end

function contextWindow.saveChangesCallback(room, selections, dummyData, bestSelection, windowState)
    return function(formFields)
        local newData = form.getFormData(formFields)
        local layers = selectionUtils.selectionTargetLayers(selections)
        local handler = bestSelection and layerHandlers.getHandler(bestSelection.layer)
        local multiple = #selections > 1
        local ignoredBefore = handler and getIgnoredFieldSet(handler, multiple,
            bestSelection.layer, bestSelection.item) or nil

        local snapshot = snapshotUtils.roomLayersSnapshot(function()
            for _, selection in ipairs(selections) do
                local item = selection.item

                -- Apply nil values from new data
                for k, v in pairs(dummyData) do
                    if newData[k] == nil then
                        item[k] = nil
                    end
                end

                for k, v in pairs(newData) do
                    item[k] = v
                end
            end

            if room then
                selectionUtils.updateSelectionRectangles(room, selections)
                selectionUtils.redrawTargetLayers(room, selections)
            end

            form.formDataSaved(formFields)
        end, room, layers, "Property menu save")

        history.addSnapshot(snapshot)

        -- Handlers can hide fields depending on the values that were just saved (ignoredFields).
        -- Only rebuild when the effective ignored set actually changed: every entity/trigger
        -- handler exposes ignoredFields, even when it returns the same fields before and after.
        local ignoredAfter = handler and getIgnoredFieldSet(handler, multiple,
            bestSelection.layer, bestSelection.item) or nil
        local needsRebuild = handler and ignoredBefore and ignoredAfter
            and not ignoredFieldSetsEqual(ignoredBefore, ignoredAfter)

        if needsRebuild then
            ui.runLate(function()
                -- Rebuild the window that owns this form. contextWindow.currentWindow is whichever
                -- property window was opened last, which may be a different object.
                local window = windowState and windowState.window

                if not window or not window.parent then
                    return
                end

                local x, y = window.x, window.y

                widgetUtils.closeWindow(window)

                local newWindow = contextWindow.createContextMenu(selections, bestSelection, room, {x, y})

                if newWindow then
                    windowState.window = newWindow
                    contextWindow.currentWindow = newWindow
                end
            end)
        end
    end
end

local function prepareFormData(selections, targetSelection, language)
    local item = targetSelection.item
    local layer = targetSelection.layer

    local handler = layerHandlers.getHandler(layer)
    local options = {}

    -- Decals have a simpler path than the default for entities/trigger
    if layer == "decalsFg" or layer == "decalsBg" then
        options.namePath = {"attribute"}
        options.tooltipPath = {"description"}
    end

    options.multiple = #selections > 1

    return formUtils.prepareFormData(handler, item, options, {layer, item})
end

-- Filter out selections that don't match the best selection
-- For example decals shouldn't be changed when the first item is a refill
-- Triggers and entities should only work on ones with the same name
local function findCompatibleSelections(selections, targetSelection)
    local compatible = {}

    local item = targetSelection.item
    local layer = targetSelection.layer

    for _, target in ipairs(selections) do
        if target.layer == layer and not tiles.tileLayers[target.layer] then
            if layer == "entities" or layer == "triggers" then
                if item._name == target.item._name then
                    table.insert(compatible, target)
                end

            else
                table.insert(compatible, target)
            end
        end
    end

    return compatible
end

function contextWindow.createContextMenu(selections, bestSelection, room, position)
    local language = languageRegistry.getLanguage()

    -- Filter out selections that would end up making a mess
    selections = findCompatibleSelections(selections, bestSelection)

    if #selections == 0 then
        return
    end

    local dummyData, fieldInformation, fieldOrder = prepareFormData(selections, bestSelection, language)

    -- Window would be empty, nothing to show
    if utils.countKeys(dummyData) == 0 then
        return
    end

    local windowState = {}

    local buttons = {
        {
            text = tostring(language.ui.selection_context_window.save_changes),
            formMustBeValid = true,
            callback = contextWindow.saveChangesCallback(room, selections, dummyData, bestSelection,
                windowState)
        }
    }

    local windowTitle = getWindowTitle(language, selections, bestSelection)
    local selectionForm, formFields = form.getForm(buttons, dummyData, {
        fields = fieldInformation,
        fieldOrder = fieldOrder,
        fieldMetadata = {
            formData = dummyData,
            selections = selections,
        },
    })

    local window = uiElements.window(windowTitle, selectionForm)
    local windowCloseCallback = windowPersister.getWindowCloseCallback(windowPersisterName)

    windowState.window = window
    contextWindow.currentWindow = window

    windowPersister.trackWindow(windowPersisterName, window, position)
    contextGroup.parent:addChild(window)
    widgetUtils.addWindowCloseButton(window, windowCloseCallback)
    widgetUtils.preventOutOfBoundsMovement(window)
    widgetUtils.consumeKeyboardEvents(window)
    form.prepareScrollableWindow(window)
    form.addTitleChangeHandler(window, windowTitle, formFields)
    form.focusFirstElement(selectionForm)

    return window
end

-- Group to get access to the main group and sanely inject windows in it
function contextWindow.getWindow()
    contextGroup = uiElements.group({}):with({
        editorSelectionContextMenu = editorSelectionContextMenuCallback
    })

    return contextGroup
end

return contextWindow