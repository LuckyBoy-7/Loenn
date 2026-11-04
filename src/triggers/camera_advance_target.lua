local enums = require("consts.celeste_enums")

local cameraAdvanceTarget = {}

cameraAdvanceTarget.name = "cameraAdvanceTargetTrigger"
cameraAdvanceTarget.category = "camera"
cameraAdvanceTarget.nodeLimits = {1, 1}
cameraAdvanceTarget.fieldInformation = {
    positionModeX = {
        options = enums.trigger_position_modes,
        editable = false
    },
    positionModeY = {
        options = enums.trigger_position_modes,
        editable = false
    }
}
cameraAdvanceTarget.placements = {
    name = "camera_advance_target",
    data = {
        lerpStrengthX = 1.0,
        lerpStrengthY = 1.0,
        positionModeX = "NoEffect",
        positionModeY = "NoEffect",
        xOnly = false,
        yOnly = false
    }
}

-- Extended text: which axis the target applies to
cameraAdvanceTarget._lonnExt_extendedText = function(trigger)
    if trigger.xOnly and trigger.yOnly then
        return "xy"
    end

    if trigger.xOnly then
        return "x"
    end

    if trigger.yOnly then
        return "y"
    end
end

return cameraAdvanceTarget