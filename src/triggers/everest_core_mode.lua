local enums = require("consts.celeste_enums")

local everestCoreMode = {}

everestCoreMode.name = "everest/coreModeTrigger"
everestCoreMode.associatedMods = {"Everest"}
everestCoreMode.fieldInformation = {
    mode = {
        options = enums.core_modes,
        editable = false,
    }
}
everestCoreMode.placements = {
    name = "core_mode",
    data = {
        mode = "None",
        playEffects = true
    }
}

-- Extended text: the core mode that is switched to
everestCoreMode._lonnExt_extendedText = function(trigger)
    return trigger.mode
end

return everestCoreMode