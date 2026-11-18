-- Shared UI / trigger font choices. The same font can be used in either scope, so both lists
-- expose the same union.
local bundledFonts = {
    {"Roboto Bold", "assets/fonts/Roboto-Bold.ttf"},
    {"Open Sans Bold", "assets/fonts/OpenSans-Bold.ttf"},
    {"Lato Bold", "assets/fonts/Lato-Bold.ttf"},
    {"Source Sans 3 Bold", "assets/fonts/SourceSans3-Bold.ttf"},
    {"Noto Sans CJK SC Bold", "assets/fonts/NotoSansCJKsc-Bold.otf"},
    {"Renogare Soft", "assets/fonts/RenogareSoft-Regular.ttf"},
    {"8bit Operator Bold", "assets/fonts/8bitOperatorPlus-Bold.ttf"},
    {"Mojang", "assets/fonts/Mojang-Regular.ttf"},
    {"VCR OSD Mono", "assets/fonts/VCR_OSD_MONO.ttf"},
}

local fontOptions = {
    bold = bundledFonts,
    ui = {{"Default UI Font", ""}},
    trigger = {{"Built-in Sans", ""}},
}

for _, option in ipairs(bundledFonts) do
    table.insert(fontOptions.ui, option)
    table.insert(fontOptions.trigger, option)
end

function fontOptions.isValidUIFont(path)
    for _, option in ipairs(fontOptions.ui) do
        if option[2] == path then
            return true
        end
    end

    return false
end

function fontOptions.isValidTriggerFont(path)
    for _, option in ipairs(fontOptions.trigger) do
        if option[2] == path then
            return true
        end
    end

    return false
end

return fontOptions
