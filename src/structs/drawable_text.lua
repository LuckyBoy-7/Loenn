local drawing = require("utils.drawing")
local utils = require("utils")

local drawableText = {}
local drawableTextMt = {}
drawableTextMt.__index = {}

function drawableTextMt.__index:draw()
    -- Unselected rooms are cached in a low resolution canvas, where thin hi-res
    -- text turns into a blob. Such drawables can carry a canvas font which is
    -- used instead whenever they are drawn into a canvas.
    local font = self.font
    local fontSize = self.fontSize

    if self.canvasFont and love.graphics.getCanvas() then
        font = self.canvasFont
        fontSize = self.canvasFontSize or 1
    end

    -- Direct draws (like the placement preview, which tints everything white)
    -- have to respect the color of this drawable, otherwise e.g. the dark
    -- trigger label shadow would show up white. The current alpha is kept so
    -- previews still fade out.
    local previousColor

    if self.color then
        local r, g, b, a = love.graphics.getColor()

        previousColor = {r, g, b, a}

        love.graphics.setColor(self.color[1] or 1, self.color[2] or 1, self.color[3] or 1, (self.color[4] or 1) * a)
    end

    if self.width and self.height then
        drawing.printCenteredText(self.text, self.x, self.y, self.width, self.height, font, fontSize)

    else
        local previousFont

        if font then
            previousFont = love.graphics.getFont()

            love.graphics.setFont(font)
        end

        love.graphics.print(self.text, self.x, self.y, 0, fontSize, fontSize, 0, 0)

        if font then
            love.graphics.setFont(previousFont)
        end
    end

    if previousColor then
        love.graphics.setColor(previousColor)
    end
end

-- font/fontSize can be overridden to bake the same text for another font
function drawableTextMt.__index:addToBatch(batch, font, fontSize)
    font = font or self.font
    fontSize = fontSize or self.fontSize

    if self.width and self.height then
        drawing.addCenteredText(batch, self.text, self.x, self.y, self.width, self.height, font, fontSize, self.color)

    else
        local text = self.text

        if self.color then
            text = {self.color, text}
        end

        batch:add(text, self.x, self.y, 0, fontSize, fontSize, 0, 0)
    end
end

local function setColor(target, color)
    local tableColor = utils.getColor(color)

    if tableColor then
        target.color = tableColor
    end

    return tableColor ~= nil
end

function drawableTextMt.__index:setColor(color)
    return setColor(self, color)
end

function drawableText.fromText(text, x, y, width, height, font, fontSize, color)
    local drawable = {
        _type = "drawableText"
    }

    drawable.text = text

    drawable.x = x
    drawable.y = y

    drawable.width = width
    drawable.height = height

    drawable.font = font or love.graphics.getFont()
    drawable.fontSize = fontSize

    if color then
        setColor(drawable, color)
    end

    return setmetatable(drawable, drawableTextMt)
end

return drawableText