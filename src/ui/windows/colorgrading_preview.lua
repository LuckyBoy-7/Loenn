-- Left window with a 3x3 preview of the built-in color grading sample images. While a color
-- grading texture is hovered in the Preview tool's ColorGrading layer, the samples are shown with
-- that grade applied (when the texture is a valid 256x16 grading LUT).

local ui = require("ui")
local uiElements = require("ui.elements")
local uiRoot = require("ui.ui_root")
local uiUtils = require("ui.utils")
local widgetUtils = require("ui.widgets.utils")
local modHandler = require("mods")
local utils = require("utils")

local colorGradingPreview = {}

local window
local previewElements = {}
local baseImages = {}
local baseData = {}
local gradeCache = {}

local GRID_COLUMNS = 3
local GRID_ROWS = 4
local CELL_WIDTH = 300
local CELL_HEIGHT = 200
local ASSET_FOLDER = "assets/colorgrading_preview/"

--- Image helpers

-- Loads an image from a virtual/mod path, mounting the owning mod when needed
local function loadImage(path)
    local image

    local success, result = pcall(love.graphics.newImage, path)

    if success then
        image = result
    end

    if not image and path:sub(1, 1) == "$" then
        local modFolder = string.match(path, "^%$([^%$]+)%$")

        if modFolder and modHandler.ensureModMounted(modFolder) then
            local ok, retried = pcall(love.graphics.newImage, path)

            if ok then
                image = retried
            end
        end
    end

    -- Absolute paths (vanilla content) and archive paths that the graphics loader can not read
    if not image then
        local bytes = utils.readAll(path, "rb")

        if bytes then
            local ok, data = pcall(function()
                return love.image.newImageData(love.filesystem.newFileData(bytes, "color_grading.png"))
            end)

            if ok then
                image = love.graphics.newImage(data)
            end
        end
    end

    return image
end

-- Sample image scaled into a cell sized canvas, so grading is done on small data
local function loadBasePreview(index)
    if baseImages[index] then
        return
    end

    local image = loadImage(string.format("%s%02d.png", ASSET_FOLDER, index - 1))

    if not image then
        return
    end

    local imageWidth, imageHeight = image:getDimensions()
    local scale = math.min(CELL_WIDTH / imageWidth, CELL_HEIGHT / imageHeight)
    local drawWidth, drawHeight = imageWidth * scale, imageHeight * scale

    local canvas = love.graphics.newCanvas(CELL_WIDTH, CELL_HEIGHT)
    local previousCanvas = love.graphics.getCanvas()

    canvas:renderTo(function()
        love.graphics.clear(0.08, 0.08, 0.08, 1)
        love.graphics.setColor(1, 1, 1, 1)
        love.graphics.draw(image, (CELL_WIDTH - drawWidth) / 2, (CELL_HEIGHT - drawHeight) / 2,
            0, scale, scale)
    end)

    love.graphics.setCanvas(previousCanvas)

    local data = canvas:newImageData()

    baseData[index] = data
    baseImages[index] = love.graphics.newImage(data)
end

--- Color grading

-- Loads ImageData from a virtual/mod/absolute path
local function loadImageData(path)
    local success, data = pcall(love.image.newImageData, path)

    if success and data then
        return data
    end

    if path:sub(1, 1) == "$" then
        local modFolder = string.match(path, "^%$([^%$]+)%$")

        if modFolder and modHandler.ensureModMounted(modFolder) then
            local ok, retried = pcall(love.image.newImageData, path)

            if ok then
                return retried
            end
        end
    end

    local bytes
    local readSuccess, readResult = pcall(function()
        if path:sub(1, 1) == "$" then
            return utils.readAll(path, "rb", true)
        end

        -- Absolute content paths: read with plain io, the editor filesystem changes the working
        -- directory for external files and chokes on some of them
        local file = io.open(path, "rb")

        if file then
            local contents = file:read("*a")

            file:close()

            return contents
        end

        return utils.readAll(path, "rb", false)
    end)

    if readSuccess then
        bytes = readResult
    end

    if bytes then
        local ok, fromBytes = pcall(function()
            return love.image.newImageData(love.filesystem.newFileData(bytes, "color_grading.png"))
        end)

        if ok then
            return fromBytes
        end
    end
end

local function getGradeData(path)
    if gradeCache[path] ~= nil then
        return gradeCache[path] or nil
    end

    local data = loadImageData(path)

    if data then
        local width, height = data:getDimensions()

        if width ~= 256 or height ~= 16 then
            data = nil
        end
    end

    gradeCache[path] = data or false

    return data or nil
end

-- The grading texture is a 16x16x16 color cube: blocks of 16 columns per blue slice, red on the
-- x axis and green on the y axis (see the Celeste ColorGrade shader)
local function gradePixel(grade, r, g, b)
    local red = math.min(15, math.floor(r * 16))
    local green = math.min(15, math.floor(g * 16))
    local blue = math.min(15, math.floor(b * 16))

    return grade:getPixel(blue * 16 + red, green)
end

local function buildGradedImages(path)
    local grade = getGradeData(path)

    if not grade then
        return nil
    end

    local images = {}

    for index = 1, GRID_COLUMNS * GRID_ROWS do
        local source = baseData[index]

        if source then
            local data = source:clone()
            local width, height = data:getDimensions()

            for y = 0, height - 1 do
                for x = 0, width - 1 do
                    local r, g, b, a = data:getPixel(x, y)

                    if a > 0 then
                        local gr, gg, gb = gradePixel(grade, r, g, b)

                        data:setPixel(x, y, gr, gg, gb, a)
                    end
                end
            end

            table.insert(images, love.graphics.newImage(data))
        end
    end

    return images
end

function colorGradingPreview.setGrade(path)
    if not window then
        return
    end

    local images = path and buildGradedImages(path) or nil

    for index, element in ipairs(previewElements) do
        element:setImage(images and images[index] or baseImages[index])
    end
end

--- Window

local function createWindow()
    local rows = {}

    for row = 1, GRID_ROWS do
        local rowElements = {}

        for column = 1, GRID_COLUMNS do
            local index = (row - 1) * GRID_COLUMNS + column
            local element = uiElements.image(baseImages[index] or "ui:icons/close"):with({
                width = CELL_WIDTH,
                height = CELL_HEIGHT
            })

            previewElements[index] = element

            table.insert(rowElements, element)
        end

        table.insert(rows, uiElements.row(rowElements):with({spacing = 4}))
    end

    local content = uiElements.column(rows):with({spacing = 4})
    local result = uiElements.window("Color Grading Preview", content)

    return result
end

function colorGradingPreview.show()
    if window and window.parent then
        return
    end

    for index = 1, GRID_COLUMNS * GRID_ROWS do
        loadBasePreview(index)
    end

    if not window then
        window = createWindow()

        widgetUtils.addWindowCloseButton(window, function(w)
            w:removeSelf()
            window = nil
            ui.root:recollect()
        end)
        widgetUtils.preventOutOfBoundsMovement(window)
        widgetUtils.consumeKeyboardEvents(window)
    end

    local parent = uiRoot.getWindowGroup and uiRoot.getWindowGroup() or ui.root

    parent:addChild(window)
    window:layout()
    window:layoutLate()

    -- Center in the area left of the right toolbar, clamped to the window
    local parentWidth = parent.width or love.graphics.getWidth()
    local parentHeight = parent.height or love.graphics.getHeight()
    local toolbarWidth = 0
    local success, windowsHandler = pcall(require, "ui.windows")

    if success and windowsHandler.windows and windowsHandler.windows.tools then
        local toolsWindow = windowsHandler.windows.tools

        toolbarWidth = (toolsWindow.width or 0) + (toolsWindow.style and toolsWindow.style.padding or 0)
    end

    local availableWidth = math.max(window.width, parentWidth - toolbarWidth)
    local x = math.floor((availableWidth - window.width) / 2)
    local y = math.floor((parentHeight - window.height) / 2)

    x = math.max(0, math.min(x, parentWidth - window.width))
    y = math.max(0, math.min(y, parentHeight - window.height))

    widgetUtils.moveWindow(window, x, y, 0, 0, 0)

    ui.root:recollect()
end

function colorGradingPreview.hide()
    if window and window.parent then
        window:removeSelf()
    end
end

function colorGradingPreview.isShown()
    return window ~= nil and window.parent ~= nil
end

-- The windows loader expects a getWindow function; the preview window itself is created on demand
-- when the ColorGrading layer is selected
function colorGradingPreview.getWindow()
    return uiElements.group({})
end

return colorGradingPreview
