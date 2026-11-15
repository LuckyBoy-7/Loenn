-- Change Attributes: replaces every entity of one type with another type.
-- Based on LoennScripts' Change Attributes, but the second (generated) parameter window is built
-- from the destination entity's placement data, so its attributes can be set in one go.
--
-- Flow:
--   click the workspace -> pick source/destination type in the first panel
--   -> the second panel lists the destination attributes (and optional "replace" toggles)
--   -> Run Scripts applies the change to every room in the current scope.

local entities = require("entities")
local utils = require("utils")
local namePreviewFocus = require("ui.name_preview_focus")

local script = {}

script.name = "changeAttributes"
script.title = "Change Attributes"
script.description = "Changes every entity of one type into another type."
-- The first stage only opens the generated panel, the "successfully ran" notification would be
-- misleading there
script.silent = true

--- First panel: source and destination type.

script.fieldOrder = {"type", "replaceWith", "allowPreserving"}
script.defaultData = {
    type = "",
    replaceWith = "",
    allowPreserving = false
}

script.fieldInformation = {
    type = {editable = true, onFocus = namePreviewFocus.onFocus, onBlur = namePreviewFocus.onBlur},
    replaceWith = {editable = true, onFocus = namePreviewFocus.onFocus, onBlur = namePreviewFocus.onBlur}
}

script.tooltips = {
    type = "Entity type name that will be changed (like spikesUp, strawberry, etc.).",
    replaceWith = "Type the entities become. Leave empty to only change the attributes of the same type.",
    allowPreserving = "Adds a replace toggle per attribute, so only the checked attributes are overwritten."
}

-- Placement data of an entity type, without the properties that belong to the placed instance
local function getEntityHandler(entityName)
    -- rawget: the registry has a metatable that returns a fallback handler for unknown names
    return rawget(entities.registeredEntities, entityName)
end

local function getDefaultData(entityName)
    local handler = getEntityHandler(entityName)

    if not handler or not handler.placements then
        return {}
    end

    local placements = utils.callIfFunction(handler.placements)

    if not placements then
        return {}
    end

    local placement = placements.default or placements[1] or placements
    local data = placement and placement.data

    if not data then
        return {}
    end

    data = utils.deepcopy(data)

    data.x, data.y, data.width, data.height = nil, nil, nil, nil

    return data
end

local function getChangePropName(propertyName)
    return "replace_" .. propertyName
end

-- The actual per-room replacement, run by the scripts tool so snapshots/history are handled there
local applyScript = {
    name = "changeAttributesApply",
    title = "Change Attributes"
}

function applyScript.run(room, args)
    if not room or not room.entities then
        return
    end

    local source, target = args._source, args._target

    if not source or not target then
        return
    end

    for _, entity in ipairs(room.entities) do
        if entity._name == source then
            entity._name = target

            for propertyName, defaultValue in pairs(args._properties) do
                -- The values from the second panel are what the user configured; the placement
                -- data is only the fallback when a field was not part of the form
                local value = args[propertyName]

                if value == nil then
                    value = defaultValue
                end

                -- Without "allow preserving" every attribute is overwritten; with it only the
                -- checked ones are
                if not args._allowPreserving or args[getChangePropName(propertyName)] ~= false then
                    entity[propertyName] = utils.deepcopy(value)
                end
            end
        end
    end
end

--- prerun builds the second panel from the destination entity's placement data.

function script.prerun(args)
    local notifications = require("ui.notification")
    local source = args.type

    if not source or source == "" then
        notifications.notify("Change Attributes: please enter the entity type to change.")

        -- Keep the panel open so the input can be corrected
        return nil, true
    end

    if not getEntityHandler(source) then
        notifications.notify(string.format("Change Attributes: unknown entity type '%s'.", source))

        return nil, true
    end

    local target = args.replaceWith

    if not target or target == "" then
        target = source
    end

    if not getEntityHandler(target) then
        notifications.notify(string.format("Change Attributes: unknown entity type '%s'.", target))

        return nil, true
    end

    local properties = getDefaultData(target)
    local handler = getEntityHandler(target)
    -- Reuse the destination handler's field information so enums keep their dropdown options,
    -- minimums, editable flags, etc. (this is what the LoennScripts version does as well)
    local handlerFieldInformation = utils.deepcopy(handler and handler.fieldInformation or {})
    local propertyNames = {}

    for propertyName in pairs(properties) do
        table.insert(propertyNames, propertyName)
    end

    table.sort(propertyNames)

    local fieldOrder = {}
    local defaultData = {}
    local fieldInformation = {}

    for _, propertyName in ipairs(propertyNames) do
        table.insert(fieldOrder, propertyName)

        defaultData[propertyName] = utils.deepcopy(properties[propertyName])

        -- Options/enums and other field settings come from the destination entity handler
        local info = handlerFieldInformation[propertyName] or {}
        fieldInformation[propertyName] = info

        if not info.displayName then
            info.displayName = utils.humanizeVariableName(propertyName)
        end

        if args.allowPreserving then
            local replaceName = getChangePropName(propertyName)

            table.insert(fieldOrder, replaceName)

            defaultData[replaceName] = false
            fieldInformation[replaceName] = {
                displayName = string.format("Replace %s", utils.humanizeVariableName(propertyName))
            }
        end
    end

    local panelScript = {
        name = "changeAttributesApply",
        title = string.format("Change all %s", source),
        fieldOrder = fieldOrder,
        defaultData = defaultData,
        fieldInformation = fieldInformation
    }

    -- The second panel runs the replacement through the scripts tool, which creates the undo
    -- snapshots per target room. Both modules are required lazily: the scripts tool loads this
    -- script while it is being registered.
    local toolHandler = require("tools")
    local scriptsPanel = require("ui.windows.scripts_panel")

    scriptsPanel.open(panelScript, nil, function(values)
        local applyArgs = {
            _source = source,
            _target = target,
            _allowPreserving = args.allowPreserving == true,
            _properties = properties
        }

        for key, value in pairs(values) do
            applyArgs[key] = value
        end

        -- Focus switching temporarily selects Preview -> Name, so currentTool is not necessarily
        -- the Scripts tool here. Always run through the Scripts tool that owns executeScript.
        local scriptsTool = toolHandler.tools.scripts or toolHandler.currentTool

        if scriptsTool and scriptsTool.executeScript then
            scriptsTool.executeScript(applyScript, applyArgs)
        end
    end)

    return nil
end

return script
