-- Preview tool: lists images from the game/editor asset folders so their paths can be copied.
-- The secondary entries below the tool are its layers (Gameplay, ColorGrading); the tools window
-- shows the images of the selected folder as buttons.

local tool = {}

tool._type = "tool"
tool.name = "preview"
tool.group = "preview"
-- Right below Stylegrounds
tool.order = 9.6

-- Secondary entries: asset folders whose images are listed on the right
tool.validLayers = {"bg", "collectables", "danger", "objects"}

tool.layer = "bg"
tool.subLayer = -1

function tool.getMaterials()
    return {}
end

function tool.setMaterial()
    return false
end

function tool.setLayer(layer, subLayer)
    tool.layer = layer or "bg"
    tool.subLayer = subLayer or -1

    return true
end

function tool.selected()
    return true
end

function tool.unselected()
    return true
end

return tool
