local stringField = require("ui.forms.fields.string")
local utils = require("utils")

local integerField = {}

integerField.fieldType = "integer"

-- Any integers outside of this range are not safe to save
local largestInt = math.floor(2^31 - 1)
local smallestInt = math.floor(-2^31)

local function valueValidator(raw, value, allowEmpty, minimum, maximum)
    if raw == "" then
        return allowEmpty
    end

    local number = tonumber(value)

    return utils.isInteger(number) and number <= maximum and number >= minimum
end

function integerField.getElement(name, value, options)
    -- Add extra options and pass it onto string field

    local minimumValue = math.max(options.minimumValue or smallestInt, smallestInt)
    local maximumValue = math.min(options.maximumValue or largestInt, largestInt)
    local warningBelowValue = options.warningBelowValue or minimumValue
    local warningAboveValue = options.warningAboveValue or maximumValue
    local allowEmpty = options.allowEmpty or false

    options.valueTransformer = tonumber
    options.displayTransformer = function(v)
        if v == nil or type(v) ~= "number" then
            return ""
        end

        return tostring(v)
    end
    options.warningValidator = function(v, raw)
        return valueValidator(raw, v, allowEmpty, warningBelowValue, warningAboveValue)
    end
    options.validator = function(v, raw)
        return valueValidator(raw, v, allowEmpty, minimumValue, maximumValue)
    end

    local formField = stringField.getElement(name, value, options)

    return integerField.attachSlider(formField, options, true)
end

-- Adds a slider next to the input. Plugins can enable it explicitly with
-- fieldInformation[field].useScrollBar = true.
function integerField.attachSlider(formField, options, integer)
    if options.useScrollBar == false or options.slider == false then
        return formField
    end

    local minimum = options.minimumValue
    local maximum = options.maximumValue

    if not minimum or not maximum or maximum <= minimum then
        return formField
    end

    if options.useScrollBar ~= true and options.slider ~= true and maximum - minimum > 4096 then
        return formField
    end

    local slider = require("ui.widgets.slider").new({
        minimum = minimum,
        maximum = maximum,
        value = formField.currentValue,
        integer = integer,
        onChanged = function(newValue)
            formField.field:setText(tostring(newValue))
        end
    })

    formField.slider = slider
    table.insert(formField.elements, slider)
    formField.width = 3

    -- Keep the slider in sync when the value is typed into the text field
    local originalCallback = formField.field.cb

    formField.field.cb = function(element, new, old)
        originalCallback(element, new, old)

        local number = tonumber(formField.field:getText())

        if number then
            slider:setValue(number, true)
        end
    end

    return formField
end

return integerField