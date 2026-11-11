local configs = require("configs")

local device = {
    _enabled = true,
    _type = "device"
}

-- Tab is also used by OlympUI focus traversal. Handle the toolbar toggle before the UI device so
-- the configured key is not consumed as a focus change.
function device.keypressed(key, scancode, isrepeat)
    local activator = configs.hotkeys.toggleToolbar

    if type(activator) ~= "string" or activator == "" then
        return false
    end

    activator = activator:lower()

    if activator:find("+", 1, true) then
        return false
    end

    if key ~= activator then
        return false
    end

    local success, toolsWindow = pcall(require, "ui/windows/tools")

    if success and toolsWindow and toolsWindow.toggleToolbar then
        toolsWindow.toggleToolbar()

        return true
    end

    return false
end

return device
