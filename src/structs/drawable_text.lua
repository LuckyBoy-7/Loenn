local drawing = require("utils.drawing")
local utils = require("utils")
local fonts = require("fonts")

local drawableText = {}
local drawableTextMt = {}
drawableTextMt.__index = {}

-- Trigger labels are laid out with the pixel font but may be drawn with a custom display font.
-- The screen-space renderer in celeste_render lays them out with `layoutFont`/`layoutFontSize`
-- and rasterizes the display font at the final screen size. Direct draws (the placement ghost and
-- tool previews) have to do the same, otherwise a custom trigger font shows up huge, wraps at the
-- wrong width, or is scaled down and blurred compared to the placed label.
local function drawWithLayout(drawable)
    local font = drawable.font

    if not font or font == fonts.font then
        font = fonts.getTriggerFont()
    end

    local layoutFont = drawable.layoutFont
    local layoutFontSize = drawable.layoutFontSize or drawable.fontSize or 1

    local _, lines = layoutFont:getWrap(drawable.text, drawable.width / layoutFontSize)

    -- The drawable is positioned in room coordinates, but the label has to be rasterized at the
    -- size it ends up on screen (just like celeste_render.drawScreenText does). The current
    -- transform (the viewport transform for the placement ghost) tells us that scale.
    local screenX, screenY = love.graphics.transformPoint(drawable.x, drawable.y)
    local nextX, nextY = love.graphics.transformPoint(drawable.x + 1, drawable.y)
    local screenScale = math.sqrt((nextX - screenX) ^ 2 + (nextY - screenY) ^ 2)

    if screenScale <= 0 then
        screenScale = 1
    end

    local screenSize = math.max(1, math.floor(layoutFont:getHeight() * layoutFontSize * screenScale + 0.5))
    local screenFont = fonts.getScreenFont(screenSize, font)
    local screenWidth = drawable.width * screenScale
    local screenHeight = drawable.height * screenScale
    local lineHeight = screenFont:getHeight() * screenFont:getLineHeight()
    local textHeight = (#lines - 1) * lineHeight + screenFont:getHeight()
    local offsetY = math.floor((screenHeight - textHeight) / 2 + 0.5)

    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setFont(screenFont)

    for index, line in ipairs(lines) do
        line = utils.trim(line)

        local lineWidth = screenFont:getWidth(line)
        local lineX = math.floor((screenWidth - lineWidth) / 2 + 0.5)
        local lineY = math.floor(screenY + offsetY + (index - 1) * lineHeight + 0.5)

        love.graphics.print(line, math.floor(screenX + lineX + 0.5), lineY)
    end

    love.graphics.pop()
end

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
        if self.layoutFont then
            drawWithLayout(self)

        else
            drawing.printCenteredText(self.text, self.x, self.y, self.width, self.height, self.font, self.fontSize)
        end

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