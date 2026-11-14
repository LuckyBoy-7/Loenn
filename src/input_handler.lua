local inputDevice = require("input_device")
local sceneHandler = require("scene_handler")

local inputHandler = {}

local mouseButtonsPressed = {}
local dragTreshold = 2

local windowFocused = true
local usingMacOS = love.system.getOS() == "OS X"

local function isStylegroundsShortcutKey(key)
    if key == "delete" then
        return true
    end

    return (key == "c" or key == "x" or key == "v")
        and (love.keyboard.isDown("lctrl", "rctrl"))
end

-- Keep the Windows IME candidate window aligned with whatever text field the UI focused after a
-- mouse press. This lives here so the OlympUI submodule stays untouched.
local function updateImeFocus()
    local imeLoaded, ime = pcall(require, "ime")

    if not imeLoaded then
        return
    end

    local uiLoaded, ui = pcall(require, "ui")

    if not uiLoaded or not ui then
        return
    end

    local focusing = ui.focusing

    if focusing and focusing.__type == "field" then
        ime.updateTextInputRect(focusing)

    else
        ime.disableTextInput()
    end
end

-- Keeps the candidate window next to the caret while typing. This does not restart text input,
-- so an active composition is not disturbed.
local function moveImeFocus()
    local imeLoaded, ime = pcall(require, "ime")

    if not imeLoaded then
        return
    end

    local uiLoaded, ui = pcall(require, "ui")

    if not uiLoaded or not ui then
        return
    end

    local focusing = ui.focusing

    if focusing and focusing.__type == "field" then
        ime.moveTextInputRect(focusing)
    end
end

-- The stylegrounds panel is a floating panel, so its keyboard shortcuts are routed by cursor
-- position instead of focus: when the cursor is over the panel, the workspace tool must not also
-- handle the same key (for example pasting a room and a styleground at the same time).
local function routeStylegroundsShortcut(key)
    if not isStylegroundsShortcutKey(key) then
        return false
    end

    local loaded, stylegrounds = pcall(require, "ui.windows.stylegrounds_window")

    if not loaded or not stylegrounds.shouldCaptureShortcut or not stylegrounds.shouldCaptureShortcut(key) then
        return false
    end

    -- The UI device runs after this handler, so the panel shortcut has to be executed here.
    -- Form/text fields report false from handleKeyboardShortcut and keep their normal text
    -- editing shortcuts.
    return stylegrounds.handleKeyboardShortcut(key)
end

function inputHandler.getMouseDrag(x, y, button)
    local from = mouseButtonsPressed[button]
    local startX, startY = from[1], from[2]
    local dx, dy = x - startX, y - startY
    local consideredDrag = math.abs(dx) >= dragTreshold and math.abs(dy) >= dragTreshold

    return startX, startY, dx, dy, consideredDrag
end

function inputHandler.getMouseDragDelta(x, y, button, istouch)
    local from = mouseButtonsPressed[button]
    local prevX, prevY = from[3], from[4]
    local dx, dy = x - prevX, y - prevY

    from[3] = x
    from[4] = y

    return x, y, dx, dy, button, istouch
end

function love.keypressed(key, scancode, isrepeat)
    -- Tab is normally consumed by UI focus traversal before the scoped hotkey device sees it.
    -- Toggle the toolbar here, before dispatching the key to the scene, so the configured key
    -- always works in the editor.
    if key == "tab" and not isrepeat then
        local success, configs = pcall(require, "configs")

        if success and configs.hotkeys and configs.hotkeys.toggleToolbar == "tab" then
            local toolsSuccess, toolsWindow = pcall(require, "ui/windows/tools")

            if toolsSuccess and toolsWindow and toolsWindow.toggleToolbar then
                toolsWindow.toggleToolbar()

                return
            end
        end
    end

    if routeStylegroundsShortcut(key) then
        return
    end

    sceneHandler.sendEvent("keypressed", key, scancode, isrepeat)
    moveImeFocus()
end

function love.keyreleased(key, scancode)
    sceneHandler.sendEvent("keyreleased", key, scancode)
end

function love.textinput(text)
    sceneHandler.sendEvent("textinput", text)
    moveImeFocus()
end

-- LÖVE exposes SDL_TEXTEDITING through this optional callback. It is not dispatched through the
-- editor scene, so forward the composition text directly to the focused text field.
function love.textedited(text, start, length)
    local ui = package.loaded["ui"]
    local field = ui and ui.focusing

    if field and field.__type == "field" and field.setPreedit then
        local direction = 0

        if love.keyboard.isDown("left") then
            direction = -1

        elseif love.keyboard.isDown("right") then
            direction = 1
        end

        field:setPreedit(text, start, length, direction)
    end
end

function love.mousemoved(x, y, dx, dy, istouch)
    -- Mouse events on Mac should only be handled if window is focused
    if not windowFocused and usingMacOS then
        return
    end

    for button, data <- mouseButtonsPressed do
        sceneHandler.sendEvent("mousedragmoved", inputHandler.getMouseDragDelta(x, y, button, istouch))
    end

    sceneHandler.sendEvent("mousemoved", x, y, dx, dy, istouch)
end

function love.mousepressed(x, y, button, istouch, presses)
    -- Mouse events on Mac should only be handled if window is focused
    if not windowFocused and usingMacOS then
        return
    end

    mouseButtonsPressed[button] = {x, y, x, y}

    sceneHandler.sendEvent("mousepressed", x, y, button, istouch, presses)
    updateImeFocus()
end

function love.mousereleased(x, y, button, istouch, presses)
    -- Mouse events on Mac should only be handled if window is focused
    if not windowFocused and usingMacOS then
        return
    end

    local startX, startY, dx, dy, consideredDrag = inputHandler.getMouseDrag(x, y, button)

    if consideredDrag then
        sceneHandler.sendEvent("mousedragged", startX, startY, button, dx, dy)

    else
        sceneHandler.sendEvent("mouseclicked", startX, startY, button, istouch, presses)
    end

    sceneHandler.sendEvent("mousereleased", x, y, button, istouch, presses, not consideredDrag)

    mouseButtonsPressed[button] = nil
end

function love.resize(width, height)
    sceneHandler.sendEvent("resize", width, height)
end

function love.wheelmoved(dx, dy)
    sceneHandler.sendEvent("wheelmoved", dx, dy)
end

function love.visible(visible)
    sceneHandler.sendEvent("visible", visible)
end

function love.focus(focus)
    windowFocused = focus

    sceneHandler.sendEvent("focus", focus)
end

function love.filedropped(file)
    sceneHandler.sendEvent("filedropped", file)
end

function love.directorydropped(path)
    sceneHandler.sendEvent("directorydropped", path)
end

function love.quit(arg)
    local _, preventQuit = sceneHandler.quit(arg)

    return preventQuit
end

return inputHandler