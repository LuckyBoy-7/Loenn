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

local coordinateWindow = {}

-- Registered as a window so the UI knows about this module (the window itself is
-- added to the window group on demand)
local coordinateWindowGroup = uiElements.group({})

local currentWindow
local currentTitle
local currentLabels

-- Distance of the fixed panel from the workspace edges
local workspaceMargin = 8

-- Left edge of the workspace: the right edge of the panels pinned to the left (the room list)
local function getWorkspaceLeft()
    local group = require("ui.ui_root").getWindowGroup()

    if not group or not group.children then
        return 0
    end

    local left = 0

    for _, child in ipairs(group.children) do
        local screenX, width = child.screenX, child.width

        if child._pinnedEdge == "left" and screenX and width and screenX <= 0 then
            left = math.max(left, screenX + width)
        end
    end

    return left
end

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

-- Crosshair size and thickness are screen space constants: scaling them with the zoom made the
-- two lines merge into a blob at some zoom levels
local crosshairLength = 6
local crosshairLineWidth = 1

local function drawCrosshairShape(screenX, screenY, color)
    drawing.callKeepOriginalColor(function()
        love.graphics.setLineWidth(crosshairLineWidth)
        love.graphics.setColor(color)

        love.graphics.line(screenX - crosshairLength, screenY, screenX + crosshairLength, screenY)
        love.graphics.line(screenX, screenY - crosshairLength, screenX, screenY + crosshairLength)
    end)
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

    local snappedX, snappedY = viewportHandler.getWindowCoordinates(info.worldTileX * 8, info.worldTileY * 8)
    local pixelX, pixelY = viewportHandler.getWindowCoordinates(info.worldX, info.worldY)

    -- Red: snapped to the tile grid
    drawCrosshairShape(snappedX, snappedY, {1, 0, 0, 1})

    -- Yellow: exact world pixel
    drawCrosshairShape(pixelX, pixelY, {1, 1, 0, 1})
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

-- Opens the panel if it is not open yet
function coordinateWindow.open()
    if not coordinateWindow.isOpen() then
        return coordinateWindow.toggle()
    end

    return currentWindow
end

function coordinateWindow.close()
    if currentWindow then
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

    -- The panel has a fixed position: no position tracking and no titlebar drag
    if window.titlebar then
        window.titlebar.interactive = 0

        window.titlebar:hook({
            onPress = function() end,
            onRelease = function() end,
            onDrag = function() end
        })
    end

    windowGroup:addChild(window)

    -- The window is created after the UI tree was collected: without this the element is drawn
    -- (draw walks the children) but never updated, which left the coordinates frozen
    local ui = require("ui")

    if ui.root then
        ui.root:recollect()
    end

    widgetUtils.consumeKeyboardEvents(window)

    -- Fixed position: top left corner of the workspace, next to the pinned room list. Set once
    -- here and once after the layout pass, where the final window size is known
    local fixedX, fixedY = getWorkspaceLeft() + workspaceMargin, workspaceMargin

    window.x, window.y = fixedX, fixedY

    ui.runLate(function()
        if window.parent and window.width then
            widgetUtils.moveWindow(window, getWorkspaceLeft() + workspaceMargin, workspaceMargin, 0)
        end
    end)

    currentWindow = window
    currentLabels = labels

    updateLabels(labels)

    return window
end

function coordinateWindow.getWindow()
    return coordinateWindowGroup
end

return coordinateWindow
