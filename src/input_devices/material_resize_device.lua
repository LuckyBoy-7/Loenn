local device = {
    _enabled = true,
    _type = "device"
}

local function toolsWindow()
    local success, module = pcall(require, "ui/windows/tools")

    return success and module or nil
end

function device.mousepressed(x, y, button)
    local window = toolsWindow()

    if window and window.materialResizePressed then
        return window.materialResizePressed(x, y, button)
    end

    return false
end

function device.mousemoved(x, y, dx, dy)
    local window = toolsWindow()

    if window and window.materialResizeDragged then
        return window.materialResizeDragged(x, y)
    end

    return false
end

function device.mousereleased(x, y, button)
    local window = toolsWindow()

    if window and window.materialResizeReleased then
        return window.materialResizeReleased(x, y, button)
    end

    return false
end

return device
