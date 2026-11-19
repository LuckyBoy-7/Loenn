-- Shared UI / trigger font choices. The same font can be used in either scope, so both lists
-- expose the same union.
local lfs = require("lib.lfs_ffi")

local bundledFonts = {
    {"Roboto Bold", "assets/fonts/Roboto-Bold.ttf"},
    {"Open Sans Bold", "assets/fonts/OpenSans-Bold.ttf"},
    {"Lato Bold", "assets/fonts/Lato-Bold.ttf"},
    {"Source Sans 3 Bold", "assets/fonts/SourceSans3-Bold.ttf"},
    {"Noto Sans CJK SC Bold", "assets/fonts/NotoSansCJKsc-Bold.otf"},
    {"Source Han Sans CN", "assets/fonts/SourceHanSansCN-Regular.ttf"},
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

local customFonts = {}
local customOptionMarker = "_customFont"

local function addFontDirectory(directories, seen, path)
    if not path then
        return
    end

    path = path:gsub("\\", "/"):gsub("/+$", "")

    if path ~= "" and not seen[path] then
        seen[path] = true

        table.insert(directories, path)
    end
end

-- Custom fonts live in a "Fonts" folder next to the executable (when packaged) or next to the
-- source directory (when running from source).
local function getFontDirectories()
    local directories = {}
    local seen = {}

    -- Source first: when the same file exists in both places, fonts.resolveFontPath prefers the
    -- source copy as well.
    local source = love.filesystem.getSource()

    if source and not source:lower():match("%.love$") then
        addFontDirectory(directories, seen, source .. "/Fonts")
    end

    local successBase, baseDirectory = pcall(love.filesystem.getSourceBaseDirectory)

    if successBase and baseDirectory then
        addFontDirectory(directories, seen, baseDirectory .. "/Fonts")
    end

    return directories
end

local function isFontFilename(filename)
    local extension = filename:match("%.([^%.]+)$")

    if not extension then
        return false
    end

    extension = extension:lower()

    return extension == "ttf" or extension == "otf" or extension == "ttc"
end

local MAX_FONT_SCAN_DEPTH = 8

local function scanFontDirectory(directory, relativeDirectory, depth, fonts, seenPaths)
    if depth > MAX_FONT_SCAN_DEPTH then
        return
    end

    local success, attributes = pcall(lfs.attributes, directory)

    if not success or not attributes or attributes.mode ~= "directory" then
        return
    end

    pcall(function()
        for filename in lfs.dir(directory) do
            if filename ~= "." and filename ~= ".." then
                local fullPath = directory .. "/" .. filename
                local relativePath = relativeDirectory and (relativeDirectory .. "/" .. filename) or filename
                local entryMode

                -- Do not follow symlinks: a Fonts folder containing a link back to itself would
                -- otherwise make this scan recurse forever.
                local linkSuccess, linkMode = pcall(lfs.symlinkattributes, fullPath, "mode")

                if not linkSuccess or linkMode ~= "link" then
                    local entrySuccess, entryAttributes = pcall(lfs.attributes, fullPath)

                    if entrySuccess and entryAttributes then
                        entryMode = entryAttributes.mode
                    end
                end

                if entryMode == "directory" then
                    scanFontDirectory(fullPath, relativePath, depth + 1, fonts, seenPaths)

                elseif entryMode and isFontFilename(filename) then
                    local key = relativePath:lower()

                    if not seenPaths[key] then
                        seenPaths[key] = true

                        table.insert(fonts, {
                            name = relativePath:gsub("%.[^%.]+$", ""),
                            path = "Fonts/" .. relativePath
                        })
                    end
                end
            end
        end
    end)
end

local function scanCustomFonts()
    local fonts = {}
    local seenPaths = {}

    for _, directory in ipairs(getFontDirectories()) do
        scanFontDirectory(directory, nil, 0, fonts, seenPaths)
    end

    table.sort(fonts, function(a, b)
        return a.name:lower() < b.name:lower()
    end)

    return fonts
end

local function removeCustomOptions(options)
    for index = #options, 1, -1 do
        if options[index][customOptionMarker] then
            table.remove(options, index)
        end
    end
end

local function addCustomOptions(options, fonts)
    for _, font in ipairs(fonts) do
        table.insert(options, {
            font.name,
            font.path,
            [customOptionMarker] = true
        })
    end
end

function fontOptions.refreshCustomFonts()
    customFonts = scanCustomFonts()

    removeCustomOptions(fontOptions.ui)
    removeCustomOptions(fontOptions.trigger)

    addCustomOptions(fontOptions.ui, customFonts)
    addCustomOptions(fontOptions.trigger, customFonts)
end

fontOptions.refreshCustomFonts()

local function isCustomFontPath(path)
    if type(path) ~= "string" then
        return false
    end

    local relativePath = path:gsub("\\", "/"):match("^Fonts/(.+)$")

    if not relativePath or relativePath:find("%.%.") then
        return false
    end

    local filename = relativePath:match("([^/\\]+)$")

    return filename ~= nil and isFontFilename(filename)
end

function fontOptions.isValidUIFont(path)
    for _, option in ipairs(fontOptions.ui) do
        if option[2] == path then
            return true
        end
    end

    return isCustomFontPath(path)
end

function fontOptions.isValidTriggerFont(path)
    for _, option in ipairs(fontOptions.trigger) do
        if option[2] == path then
            return true
        end
    end

    return isCustomFontPath(path)
end

return fontOptions
