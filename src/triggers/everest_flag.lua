local enums = require("consts.celeste_enums")

local everestFlag = {}

everestFlag.name = "everest/flagTrigger"
everestFlag.associatedMods = {"Everest"}
everestFlag.fieldInformation = {
    death_count = {
        fieldType = "integer",
    },
    mode = {
        options = enums.everest_flag_trigger_modes,
        editable = false
    }
}
everestFlag.placements = {
    name = "flag",
    data = {
        flag = "",
        state = true,
        mode = "OnPlayerEnter",
        only_once = false,
        death_count = -1
    }
}

-- Extended text: the flag name, "!" meaning the flag is cleared
everestFlag._lonnExt_extendedText = function(trigger)
    if trigger.state then
        return trigger.flag

    else
        return "!" .. tostring(trigger.flag or "")
    end
end

return everestFlag