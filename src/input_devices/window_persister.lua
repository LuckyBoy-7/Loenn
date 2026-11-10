local persistence = require("persistence")
local config = require("utils.config")

local device = {_enabled = true, _type = "device"}

local updateRate = 2.5
local deltaTimeAcc = 0

local function persistWindowData()
    local windowX, windowY, windowDisplay = love.window.getPosition()
    local windowWidth, windowHeight = love.graphics.getDimensions()
    local windowMaximized = love.window.isMaximized()
    local windowMinimized = love.window.isMinimized()
    local fullscreen, fullscreenType = love.window.getFullscreen()

    persistence.windowDisplay = windowDisplay
    persistence.windowMaximized = windowMaximized
    persistence.windowFullscreen = fullscreen
    persistence.windowFullscreenType = fullscreenType

    if not windowMaximized and not windowMinimized and not fullscreen then
        persistence.windowX = windowX
        persistence.windowY = windowY

        persistence.windowWidth = windowWidth
        persistence.windowHeight = windowHeight
    end
end

function device.update(dt)
    deltaTimeAcc += dt

    if deltaTimeAcc > updateRate then
        deltaTimeAcc -= updateRate

        persistWindowData()
    end
end

-- Saving is normally buffered for five minutes. Window state is cheap to write and must survive
-- a normal quit even when the editor was not open long enough for the periodic update.
function device.persistNow()
    persistWindowData()

    config.writeConfig(persistence, true)
end

return device