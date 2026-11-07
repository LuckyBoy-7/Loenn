-- Stylegrounds tool: lists every background in the right column, adds the clicked one to the
-- selected side of the map and opens the stylegrounds window. Closing the window switches back
-- to the selection tool, so no empty list is left behind.

local loadedState = require("loaded_state")
local parallax = require("parallax")
-- Dot notation on purpose: the UI root requires modules this way, a slash path would load a
-- second copy of the module (with its own window state)
local stylegroundWindow = require("ui.windows.stylegrounds_window")

local tool = {}

tool._type = "tool"
tool.name = "stylegrounds"
tool.group = "stylegrounds"
-- Between the rooms tool (9) and the debug tool (10), with a separator blank line on both sides
tool.order = 9.5

-- No layer rows below the tool entry (like the rooms tool): the window handles the lists
tool.hideLayers = true

tool.validLayers = {"stylegrounds"} -- single pseudo layer; the side is chosen inside the window
tool.layer = "stylegrounds"
tool.subLayer = -1

local selectedName

local function capitalize(name)
    return (string.upper(string.sub(name, 1, 1)) .. string.sub(name, 2))
end

-- Every background name, so the tools window can offer them as entries
function tool.getMaterials(layer)
    local names = parallax.getParallaxNames() or {}
    local materials = {}

    table.sort(names)

    for _, name in ipairs(names) do
        table.insert(materials, {
            name = name,
            displayNameNoMods = capitalize(name)
        })
    end

    return materials
end

-- Clicking an entry adds that background to the map instead of only selecting it. The window is
-- where the foreground/background side is configured, so new ones go to the foreground.
function tool.setMaterial(name)
    if not name then
        return false
    end

    selectedName = name

    -- The window decides whether new styles belong to the foreground or background list
    stylegroundWindow.addStyle(name)

    return true
end

function tool.getMaterial()
    return selectedName
end

function tool.setLayer(layer, subLayer)
    tool.layer = layer or "stylegrounds"
    tool.subLayer = subLayer or -1

    return true
end

function tool.selected()
    stylegroundWindow.editStylegrounds(loadedState.map)

    return true
end

function tool.unselected()
    -- The window stays open when another tool is selected: it is a standalone panel and closing
    -- it here made it disappear whenever the user briefly switched tools
    return true
end

return tool
