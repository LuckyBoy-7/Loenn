-- Reusable horizontal resize handle for side-by-side panels. The owner supplies the current width
-- and a setter; the handle itself only handles the cursor and drag distance.
local uiElements = require("ui.elements")
local uiUtils = require("ui.utils")
local cursorUtils = require("utils.cursor")

local splitter = {}

local function clamp(value, minimum, maximum)
    if minimum and value < minimum then
        value = minimum
    end

    if maximum and value > maximum then
        value = maximum
    end

    return value
end

function splitter.create(options)
    options = options or {}

    local thickness = options.thickness or 4
    local direction = options.direction or 1
    local element = uiElements.panel({}):with({
        width = thickness,
        minWidth = thickness,
        maxWidth = thickness,
        interactive = 1,
        cacheable = false,
        style = {
            padding = 0,
            radius = 0,
            bg = {0, 0, 0, 0},
            border = {0, 0, 0, 0}
        }
    }):with(uiUtils.fillHeight(false))

    element:with({
        onEnter = function(self)
            cursorUtils.useResizeCursor(-1, 0)
        end,

        onLeave = function(self)
            if not self._dragging then
                cursorUtils.useDefaultCursor()
            end
        end,

        onPress = function(self, x, y, button)
            if button ~= 1 then
                return false
            end

            self._dragging = true
            self._dragStartX = x
            self._dragStartWidth = options.getWidth and options.getWidth() or 0
            self._targetWidth = self._dragStartWidth
            self._didDrag = false

            if options.onDragStart then
                options.onDragStart(self)
            end

            cursorUtils.useResizeCursor(-1, 0)

            return true
        end,

        onDrag = function(self, x, y, dx)
            if not self._dragging then
                return false
            end

            -- Use the drag start as the fixed origin. The splitter itself moves while resizing,
            -- so accumulating per-event deltas would drift.
            local newWidth

            if options.getWidthFromMouse then
                newWidth = options.getWidthFromMouse(x)
            else
                newWidth = self._dragStartWidth + (x - self._dragStartX) * direction
            end

            self._targetWidth = clamp(newWidth, options.minWidth, options.maxWidth)

            if self._targetWidth ~= self._dragStartWidth then
                self._didDrag = true
            end

            if self._didDrag and options.setWidth then
                options.setWidth(self._targetWidth)
            end

            return true
        end,

        onRelease = function(self)
            if self._didDrag and self._targetWidth and options.setWidth then
                -- Apply the width once, after the drag has ended. Running list reflows while the
                -- mouse is still generating drag events can recursively re-enter the UI layout.
                options.setWidth(self._targetWidth)
            end

            self._dragging = false
            self._targetWidth = nil
            self._didDrag = false

            cursorUtils.useDefaultCursor()
        end
    })

    if options.line then
        element:hook({
            draw = function(orig, self)
                orig(self)

                local x = math.floor(self.screenX + self.width * 0.5)
                local color = options.lineColor or {1, 1, 1, 0.18}
                local previous = {love.graphics.getColor()}

                love.graphics.setColor(color)
                love.graphics.rectangle("fill", x, self.screenY, 1, self.height)
                love.graphics.setColor(previous)
            end
        })
    end

    return element
end

return splitter
