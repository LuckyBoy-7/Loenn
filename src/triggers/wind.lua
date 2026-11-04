local enums = require("consts.celeste_enums")

local wind = {}

wind.name = "windTrigger"
wind.fieldInformation = {
    pattern = {
        options = enums.wind_patterns,
        editable = false
    }
}
wind.placements = {
    name = "wind",
    data = {
        pattern = "None"
    }
}

-- Extended text: shows the wind direction below the trigger name
wind._lonnExt_extendedText = function(trigger)
    return trigger.pattern
end

return wind