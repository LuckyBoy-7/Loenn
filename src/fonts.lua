-- Text fonts used by the editor: the vanilla pico8 style font and an optional
-- hi-res pixel font.
--
-- The hi-res font has larger glyphs, so every size designed for the vanilla
-- font is multiplied by `font.pixelFactor` to keep the same visual size.
-- `font.fontScale` is the scale used by UI text and already includes it.

local font = {}

local vanilla = {
    path = "fonts/pico8_font.png",
    glyphs = [=[abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ"'`-_/1234567890!?[](){}.,;:<>+=%#^*~ ]=]
}

local hires = {
    path = "assets/fonts/hi-res_pixel_font.png",
    glyphs = [=[abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.,!?-+/():;%&`'*#=[]"_{}<>^~ ]=]
}

local vanillaFont = love.graphics.newImageFont(vanilla.path, vanilla.glyphs, 1)
local hiresFont = love.graphics.newImageFont(hires.path, hires.glyphs, 1)

font.vanillaFont = vanillaFont
font.hiresFont = hiresFont

font.font = vanillaFont
font.fontString = vanilla.glyphs
font.fontScale = 4
font.pixelFactor = 1
font.useHires = false

font.font:setLineHeight(1.25)
hiresFont:setLineHeight(1.25)

local listeners = {}

function font.addOnChanged(listener)
    table.insert(listeners, listener)
end

local function notifyChanged()
    for _, listener in ipairs(listeners) do
        listener()
    end
end

-- Sizes designed for the vanilla font multiplied by this give the same visual
-- size with the current font
function font.size(size)
    return (size or 1) * font.pixelFactor
end

function font.setUseHires(useHires)
    useHires = useHires and true or false

    if font.useHires == useHires then
        return
    end

    font.useHires = useHires
    font.font = useHires and hiresFont or vanillaFont
    font.fontString = useHires and hires.glyphs or vanilla.glyphs
    font.pixelFactor = vanillaFont:getHeight() / font.font:getHeight()
    font.fontScale = 4 * font.pixelFactor

    love.graphics.setFont(font.font)

    notifyChanged()
end

-- Applies the font settings, taking the automatic zoom based switching into
-- account
function font.applyConfig(fontConfig)
    if fontConfig.autoSwitchFont then
        local success, viewportHandler = pcall(require, "viewport_handler")
        local scale = success and viewportHandler.viewport and viewportHandler.viewport.scale or 1

        font.setUseHires(scale > 1)

    else
        font.setUseHires(fontConfig.useHiresPixelFont)
    end
end

return font
