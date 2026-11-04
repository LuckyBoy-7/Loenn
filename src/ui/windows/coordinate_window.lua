-- Floating cursor coordinate panel: screen, world (map), world tile, world snap and the same three
-- relative to the selected room.
--
-- Toggled with the "toggleCoordinatePanel" hotkey (grave accent by default). There is deliberately
-- no close button: the hotkey is the only way to dismiss it, so it can't be closed by accident
-- while painting. While it is open the cursor also gets a tile snapped crosshair, drawn with the
-- map (below the UI).

local uiElements = require("ui.elements")

local languageRegistry = require("language_registry")
local viewportHandler = require("viewport_handler")
local loadedState = require("loaded_state")
local celesteRender = require("celeste_render")
local drawing = require("utils.drawing")

local widgetUtils = require("ui.widgets.utils")

local windowPersister = require("ui.window_position_persister")
local windowPersisterName = "coordinate_window"

local coordinateWindow = {}

-- Registered as a window so the UI knows about this module (the window itself is
-- added to the window group on demand)
local coordinateWindowGroup = uiElements.group({})

local currentWindow
local currentTitle
local currentLabels

-- Rows, in display order. The room name row is filled separately, the rest are coordinate pairs.
local rowKeys = {
    "roomName",
    "screen",
    "world",
    "worldTiles",
    "worldSnap",
    "room",
    "roomTiles",
    "roomSnap"
}

-- Fallback width for the panel when every entry is short
local minimumWindowWidth = 150

local function formatPair(x, y)
    return string.format("%d, %d", x, y)
end

local function tile(value)
    return math.floor(value / 8 + 0.4)
end

-- Where the cursor is right now
local function getCursorInfo()
    local mouseX, mouseY = viewportHandler.getMousePosition()
    local mapX, mapY = viewportHandler.getMapCoordinates(mouseX, mouseY)

    local worldTileX, worldTileY = tile(mapX), tile(mapY)

    local info = {
        screen = {mouseX, mouseY},
        world = {mapX, mapY},
        worldTiles = {worldTileX, worldTileY},
        worldSnap = {worldTileX * 8, worldTileY * 8},
        worldTileX = worldTileX,
        worldTileY = worldTileY,
        worldX = mapX,
        worldY = mapY
    }

    local room = loadedState.getSelectedRoom()

    if room then
        info.roomName = room.name

        -- Room coordinates are relative to the room origin, in room pixels
        local roomX, roomY = mapX - room.x, mapY - room.y
        local roomTileX, roomTileY = tile(roomX), tile(roomY)

        info.room = {roomX, roomY}
        info.roomTiles = {roomTileX, roomTileY}
        info.roomSnap = {roomTileX * 8, roomTileY * 8}
    end

    return info
end

local function updateLabels(labels)
    local text = languageRegistry.getLanguage().ui.coordinate_window
    local info = getCursorInfo()

    for _, key in ipairs(rowKeys) do
        if key == "roomName" then
            labels.roomName:setText(info.roomName or "-")

        else
            local pair = info[key]

            labels[key]:setText(pair and formatPair(pair[1], pair[2]) or "-")
        end
    end

    -- The title is static (Debug Info): the room is a row of its own
    local title = tostring(text.title)

    if title ~= currentTitle then
        currentTitle = title

        if currentWindow then
            currentWindow.title = title
        end
    end
end

-- Tile snapped crosshair, drawn over the map but below the UI
local function drawCrosshair()
    if not coordinateWindow.isOpen() then
        return
    end

    -- The map is drawn every frame, so the labels are refreshed from here as well: that keeps them
    -- live even if the window element were only updated on some frames
    if currentLabels then
        updateLabels(currentLabels)
    end

    local viewport = viewportHandler.viewport
    local mouseX, mouseY = viewportHandler.getMousePosition()

    if mouseX < 0 or mouseY < 0 or mouseX >= viewport.width or mouseY >= viewport.height then
        return
    end

    local info = getCursorInfo()
    local length = 6 / viewport.scale

    drawing.callKeepOriginalColor(function()
        local lineWidth = love.graphics.getLineWidth()

        love.graphics.setLineWidth(math.max(1, lineWidth / viewport.scale))

        love.graphics.push()
        love.graphics.translate(math.floor(-viewport.x), math.floor(-viewport.y))
        love.graphics.scale(viewport.scale)

        -- Red: snapped to the tile grid
        love.graphics.setColor(1, 0, 0, 1)
        love.graphics.line(info.worldTileX * 8 - length, info.worldTileY * 8,
            info.worldTileX * 8 + length, info.worldTileY * 8)
        love.graphics.line(info.worldTileX * 8, info.worldTileY * 8 - length,
            info.worldTileX * 8, info.worldTileY * 8 + length)

        -- Yellow: exact world pixel
        love.graphics.setColor(1, 1, 0, 1)
        love.graphics.line(info.worldX - length, info.worldY, info.worldX + length, info.worldY)
        love.graphics.line(info.worldX, info.worldY - length, info.worldX, info.worldY + length)

        love.graphics.pop()
        love.graphics.setLineWidth(lineWidth)
    end)
end

local overlayHooked = false

local function ensureOverlayHook()
    if overlayHooked then
        return
    end

    overlayHooked = true

    local originalDrawMap = celesteRender.drawMap

    celesteRender.drawMap = function(...)
        originalDrawMap(...)
        drawCrosshair()
    end
end

function coordinateWindow.isOpen()
    local parent = currentWindow and currentWindow.parent

    return parent ~= nil and parent ~= false
end

function coordinateWindow.close()
    if currentWindow then
        windowPersister.removeActiveWindow(windowPersisterName, currentWindow)
        currentWindow:removeSelf()
        currentWindow = nil
        currentTitle = nil
        currentLabels = nil
    end
end

function coordinateWindow.toggle()
    if coordinateWindow.isOpen() then
        coordinateWindow.close()

        return
    end

    local windowGroup = require("ui.ui_root").getWindowGroup()

    if not windowGroup then
        return
    end

    ensureOverlayHook()

    local text = languageRegistry.getLanguage().ui.coordinate_window

    local columnSpacing = 16
    local contentPadding = 8

    local labels = {}
    local leftChildren, rightChildren = {}, {}

    for _, key in ipairs(rowKeys) do
        table.insert(leftChildren, uiElements.label(tostring(text[key])))
        table.insert(rightChildren, uiElements.label("-"))

        labels[key] = rightChildren[#rightChildren]
    end

    local content = uiElements.row({
        uiElements.column(leftChildren),
        uiElements.column(rightChildren)
    }):with({
        style = {
            spacing = columnSpacing,
            padding = contentPadding
        }
    })

    local window = uiElements.window(tostring(text.title), content)

    window:hook({
        update = function(orig, self, dt)
            orig(self, dt)

            updateLabels(labels)
        end
    })

    content:layout()

    updateLabels(labels)

    -- The panel is as wide as its longest entry, with a fallback minimum so it never becomes a
    -- tiny sliver when every value is short
    local leftWidth, rightWidth = 0, 0

    for index, key in ipairs(rowKeys) do
        local nameLabel = leftChildren[index]
        local nameFont = nameLabel.style.font or love.graphics.getFont()

        leftWidth = math.max(leftWidth, nameFont:getWidth(nameLabel:getText() or ""))

        local valueLabel = labels[key]
        local valueFont = valueLabel.style.font or love.graphics.getFont()

        rightWidth = math.max(rightWidth, valueFont:getWidth(valueLabel:getText() or ""))
    end

    -- content padding + spacing + window padding/border
    local requiredWidth = leftWidth + rightWidth + columnSpacing + contentPadding * 2 + 4

    window.minWidth = math.max(minimumWindowWidth, math.ceil(requiredWidth))

    windowPersister.trackWindow(windowPersisterName, window)

    windowGroup:addChild(window)

    -- The window is created after the UI tree was collected: without this the element is drawn
    -- (draw walks the children) but never updated, which left the coordinates frozen
    local ui = require("ui")

    if ui.root then
        ui.root:recollect()
    end

    widgetUtils.preventOutOfBoundsMovement(window)
    widgetUtils.consumeKeyboardEvents(window)

    currentWindow = window
    currentLabels = labels

    updateLabels(labels)

    return window
end

function coordinateWindow.getWindow()
    return coordinateWindowGroup
end

return coordinateWindow
