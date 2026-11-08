-- "float" is an alias for the regular float ("number") field type. Plugins commonly declare
-- fieldType = "float", so the same field implementation is registered under both names.

local numberField = require("ui.forms.fields.number")

local floatField = {}

floatField.fieldType = "float"

function floatField.getElement(name, value, options)
    return numberField.getElement(name, value, options)
end

return floatField
