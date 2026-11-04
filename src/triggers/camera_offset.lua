local utils = require("utils")

local cameraOffset = {}

cameraOffset.name = "cameraOffsetTrigger"
cameraOffset.category = "camera"
cameraOffset.placements = {
    name = "camera_offset",
    data = {
        cameraX = 0.0,
        cameraY = 0.0
    }
}

-- Extended text: the offset values
cameraOffset._lonnExt_extendedText = function(trigger)
    return string.format("%s, %s", utils.prettifyFloat(trigger.cameraX or 0), utils.prettifyFloat(trigger.cameraY or 0))
end

return cameraOffset