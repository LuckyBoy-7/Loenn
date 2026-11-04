local enums = require("consts.celeste_enums")

local cameraTarget = {}

cameraTarget.name = "cameraTargetTrigger"
cameraTarget.category = "camera"
cameraTarget.nodeLimits = {1, 1}
cameraTarget.fieldInformation = {
    positionMode = {
        options = enums.trigger_position_modes,
        editable = false
    }
}
cameraTarget.placements = {
    name = "camera_target",
    data = {
        lerpStrength = 1.0,
        positionMode = "NoEffect",
        xOnly = false,
        yOnly = false,
        deleteFlag = ""
    }
}

-- Extended text: which axis the target applies to
cameraTarget._lonnExt_extendedText = function(trigger)
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

return cameraTarget