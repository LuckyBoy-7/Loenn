local drawing = require("utils.drawing")
local utils = require("utils")
local fonts = require("fonts")

local drawableText = {}
local drawableTextMt = {}
drawableTextMt.__index = {}

function drawableTextMt.__index:draw()
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
        drawing.printCenteredText(self.text, self.x, self.y, self.width, self.height, self.font, self.fontSize)

    else
        local previousFont

        if self.font then
            previousFont = love.graphics.getFont()

            love.graphics.setFont(self.font)
        end

        love.graphics.print(self.text, self.x, self.y, 0, self.fontSize, self.fontSize, 0, 0)

        if self.font then
            love.graphics.setFont(previousFont)
        end
    end

    if previousColor then
        love.graphics.setColor(previousColor)
    end
end

function drawableTextMt.__index:addToBatch(batch)
    if self.width and self.height then
        drawing.addCenteredText(batch, self.text, self.x, self.y, self.width, self.height, self.font, self.fontSize, self.color)

    else
        local text = self.text

        if self.color then
            text = {self.color, text}
        end

        batch:add(text, self.x, self.y, 0, self.fontSize, self.fontSize, 0, 0)
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

-- font/fontSize can be given explicitly. Sizes used throughout the editor are
-- designed for the vanilla font, whose glyphs are half the height of the hi-res
-- one, so sizes used with the editor font are scaled to it.
function drawableText.fromText(text, x, y, width, height, font, fontSize, color)
    local drawable = {
        _type = "drawableText"
    }

    drawable.text = text

    drawable.x = x
    drawable.y = y

    drawable.width = width
    drawable.height = height

    local editorFont = love.graphics.getFont()

    drawable.font = font or editorFont

    if not font or font == editorFont then
        drawable.fontSize = (fontSize or 1) * fonts.pixelFactor

    else
        drawable.fontSize = fontSize
    end

    if color then
        setColor(drawable, color)
    end

    return setmetatable(drawable, drawableTextMt)
end

return drawableText