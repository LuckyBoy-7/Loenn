-- Shared text layout helpers for trigger labels and mod entity labels.
-- Keeping these here avoids each screen-space text path growing its own wrapping,
-- centering and word-stretching implementation.

local fonts = require("fonts")
local utils = require("utils")

local textLayout = {}

local wordWidthCache = {}

function textLayout.getLines(text, width, font, fontSize)
    font = font or fonts.font
    fontSize = fontSize or 1

    local _, lines = font:getWrap(utils.trim(text), width / fontSize)

    return lines
end

-- Returns the actual text rectangle inside the supplied label box.
function textLayout.getRect(text, x, y, width, height, font, fontSize)
    font = font or fonts.font
    fontSize = fontSize or 1

    text = utils.trim(text)

    local fontHeight = font:getHeight()
    local fontLineHeight = font:getLineHeight()
    local lines = textLayout.getLines(text, width, font, fontSize)
    local textHeight = (#lines - 1) * (fontHeight * fontLineHeight) + fontHeight

    local maxWidth = 0

    for index = 1, #lines do
        local lineWidth = font:getWidth(lines[index])

        if lineWidth > maxWidth then
            maxWidth = lineWidth
        end
    end

    local actualWidth = maxWidth * fontSize
    local offsetX = math.floor((width - actualWidth) / 2) + 1
    local offsetY = math.floor((height - textHeight * fontSize) / 2) + 1

    return {
        x = x + offsetX,
        y = y + offsetY,
        width = actualWidth,
        height = textHeight * fontSize,
        lines = lines
    }
end

-- Widens the box around its center when the longest word does not fit, so words
-- are not cut in half. Parenthesized lines normally stay on one line, but a line
-- that is far wider than the (possibly already widened) trigger is allowed to wrap
-- instead of stretching the label across the whole room.
function textLayout.stretchRect(x, y, width, height, text, fontSize, font)
    fontSize = fontSize or 1
    font = font or fonts.font

    local cacheKey = text .. "|" .. tostring(fontSize) .. "|" .. tostring(font) .. "|" .. tostring(width)
    local maxWidth = wordWidthCache[cacheKey]

    if not maxWidth then
        local wordWidth = 0
        local parenthesizedWidths = {}

        for line in (text .. "\n"):gmatch("(.-)\n") do
            line = utils.trim(line)

            local parenthesized = line:sub(1, 1) == "(" and line:sub(-1) == ")"

            if parenthesized then
                table.insert(parenthesizedWidths, font:getWidth(line) * fontSize)

            else
                for word in line:gmatch("[^%s]+") do
                    wordWidth = math.max(wordWidth, font:getWidth(word) * fontSize)
                end
            end
        end

        local effectiveWidth = math.max(width, wordWidth)
        maxWidth = wordWidth

        for _, lineWidth in ipairs(parenthesizedWidths) do
            if lineWidth <= effectiveWidth * 2 then
                maxWidth = math.max(maxWidth, lineWidth)
            end
        end

        maxWidth = math.ceil(maxWidth) + 1
        wordWidthCache[cacheKey] = maxWidth
    end

    if maxWidth > width then
        x = x - (maxWidth - width) / 2
        width = maxWidth
    end

    return x, y, width, height
end

function textLayout.clearCache()
    wordWidthCache = {}
end

fonts.addOnChanged(textLayout.clearCache)

return textLayout
