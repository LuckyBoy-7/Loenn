-- Preview tool: lists images from the game/editor asset folders so their paths can be copied.
-- The secondary entries below the tool are its layers; the tools window shows the images of the
-- selected folder as buttons. With the ColorGrading layer selected, a window on the left shows the
-- built-in grading samples with the hovered grade applied.

local tool = {}

tool._type = "tool"
tool.name = "preview"
tool.group = "preview"
-- Right below Stylegrounds
tool.order = 9.6

-- Secondary entries: asset folders whose images are listed on the right. The Name layer lists raw
-- entity/trigger names and uses the mode panel to choose Current Room vs All Rooms.
tool.validLayers = {"bg", "collectables", "danger", "objects", "name", "colorGrading"}

tool.layer = "bg"
tool.subLayer = -1
tool.mode = "currentRoom"

function tool.getModes()
    if tool.layer == "name" then
        return {"currentRoom", "allRooms"}
    end

    return {}
end

function tool.getMode()
    return tool.mode
end

function tool.setMode(mode)
    if mode == "currentRoom" or mode == "allRooms" then
        tool.mode = mode

        return true
    end

    return false
end

tool.layer = "bg"
tool.subLayer = -1

-- The sample window is only relevant for the color grading layer
local function updateColorGradingPreview()
    local colorGradingPreview = require("ui.windows.colorgrading_preview")

    if tool.layer == "colorGrading" then
        colorGradingPreview.show()

    else
        colorGradingPreview.hide()
        colorGradingPreview.setGrade(nil)
    end
end

function tool.getMaterials()
    return {}
end

function tool.setMaterial()
    return false
end

function tool.setLayer(layer, subLayer)
    local previousLayer = tool.layer

    tool.layer = layer or "bg"
    tool.subLayer = subLayer or -1

    if tool.layer == "name" and previousLayer ~= "name" then
        tool.mode = "currentRoom"
    end

    updateColorGradingPreview()

    return true
end

function tool.selected()
    updateColorGradingPreview()

    return true
end

function tool.unselected()
    local colorGradingPreview = require("ui.windows.colorgrading_preview")

    colorGradingPreview.hide()
    colorGradingPreview.setGrade(nil)

    return true
end

return tool
