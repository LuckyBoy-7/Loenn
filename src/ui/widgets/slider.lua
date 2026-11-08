-- Simple horizontal slider widget used by the numeric form fields. Values are always clamped to
-- the given range; integer sliders snap to whole numbers, float sliders keep two decimals.

local uiElements = require("ui.elements")
local uiu = require("ui.utils")

local sliders = {}

local function snap(value, minimum, maximum, integer)
    value = math.max(minimum, math.min(maximum, value))

    if integer then
        return math.floor(value + 0.5)
    end

    return math.floor(value * 100 + 0.5) / 100
end

function sliders.new(options)
    local minimum = options.minimum
    local maximum = options.maximum
    local integer = options.integer
    local width = options.width or 160
    local height = options.height or 18

    local element = uiElements.panel({}):with({
        width = width,
        minWidth = width,
        height = height,
        minHeight = height,
        maxHeight = height,
        padding = 0,
        style = {
            bg = {0, 0, 0, 0},
            border = {0, 0, 0, 0}
        }
    })

    element.interactive = 1
    element.minimum = minimum
    element.maximum = maximum
    element.integer = integer
    element.value = snap(options.value or minimum, minimum, maximum, integer)
    element.onChanged = options.onChanged

    function element:setValue(value, silent)
        value = snap(value, self.minimum, self.maximum, self.integer)

        if self.value == value then
            return
        end

        self.value = value
        self:repaint()

        if not silent and self.onChanged then
            self.onChanged(value)
        end
    end

    local function setFromPosition(self, x)
        local trackWidth = self.width
        local ratio = trackWidth > 0 and (x - self.screenX) / trackWidth or 0

        self:setValue(self.minimum + (self.maximum - self.minimum) * ratio)
    end

    element:hook({
        draw = function(orig, self)
            orig(self)

            local x, y = self.screenX, self.screenY
            local w, h = self.width, self.height
            local ratio = (self.value - self.minimum) / math.max(1e-9, self.maximum - self.minimum)
            local trackY = y + math.floor(h / 2) - 3

            uiu.setColor(0.18, 0.18, 0.18, 1)
            love.graphics.rectangle("fill", x, trackY, w, 6, 3, 3)

            uiu.setColor(0.45, 0.65, 0.95, 1)
            love.graphics.rectangle("fill", x, trackY, w * ratio, 6, 3, 3)

            uiu.setColor(0.95, 0.95, 0.95, 1)
            love.graphics.circle("fill", x + w * ratio, y + h / 2, 6)

            uiu.setColor(1, 1, 1, 1)
        end,

        onPress = function(orig, self, x, y, button)
            if button ~= 1 then
                return false
            end

            setFromPosition(self, x)

            return true
        end,

        onDrag = function(orig, self, x, y, dx, dy)
            setFromPosition(self, x)
        end
    })

    return element
end

return sliders
