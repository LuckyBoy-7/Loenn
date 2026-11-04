local loadedState = require("loaded_state")
local utils = require("utils")
local celesteRender = require("celeste_render")
local mapItemUtils = require("map_item_utils")

local mapImageGenerator = {}

-- The map is rendered in tiles of this size so that huge maps do not need a
-- single canvas, which would exceed the maximum texture size
local maxTileSize = 2048

local function getImageState(map, resolutionScale, bounds)
    local imageState = utils.deepcopy(loadedState)

    imageState.map = map
    imageState.viewport = {
        visible = true,
        scale = resolutionScale,
        x = bounds.x * resolutionScale,
        y = bounds.y * resolutionScale,
        width = bounds.width * resolutionScale,
        height = bounds.height * resolutionScale
    }
    imageState.selectedItemType = "table"
    imageState.selectedItem = {}
    imageState.showRoomBackground = false
    imageState.showRoomBorders = false

    -- TODO - Improve, this is a bit of a hack
    function imageState.getLayerVisible(layer)
        if layer == "triggers" then
            return false
        end

        return true
    end

    return imageState
end

-- Renders the whole map into an ImageData. The room canvases are rendered at a
-- higher resolution when the hi-res font is in use, so the image is rendered at
-- that resolution as well: downscaling it to the map resolution would resample
-- the text and break the glyphs
function mapImageGenerator.getMapImageData(map)
    map = map or loadedState.map

    if not map then
        return
    end

    local tlx, tly, brx, bry = mapItemUtils.getMapBounds(map)
    local width, height = brx - tlx, bry - tly
    local resolutionScale = celesteRender.getCanvasResolutionScale()
    local bounds = {x = tlx, y = tly, width = width, height = height}

    local imageWidth, imageHeight = width * resolutionScale, height * resolutionScale
    local success, imageData = pcall(love.image.newImageData, imageWidth, imageHeight)

    if not success then
        return
    end

    local imageState = getImageState(map, resolutionScale, bounds)

    -- Redraw all rooms with new state info
    for _, room in ipairs(map.rooms) do
        celesteRender.forceRedrawRoom(room, imageState, true)
    end

    local viewport = imageState.viewport

    for tileY = 0, height - 1, maxTileSize do
        for tileX = 0, width - 1, maxTileSize do
            local tileWidth = math.min(maxTileSize, width - tileX)
            local tileHeight = math.min(maxTileSize, height - tileY)

            viewport.x = (tlx + tileX) * resolutionScale
            viewport.y = (tly + tileY) * resolutionScale
            viewport.width = tileWidth * resolutionScale
            viewport.height = tileHeight * resolutionScale

            local canvas = love.graphics.newCanvas(tileWidth * resolutionScale, tileHeight * resolutionScale)

            canvas:renderTo(function()
                celesteRender.drawMap(imageState)
            end)

            imageData:paste(canvas:newImageData(), tileX * resolutionScale, tileY * resolutionScale)

            canvas:release()
        end
    end

    celesteRender.invalidateRoomCache()

    return imageData
end

function mapImageGenerator.saveMapImage(filename, map)
    local imageData = mapImageGenerator.getMapImageData(map)

    if not imageData then
        return false
    end

    local encoded = imageData:encode("png")

    if not encoded then
        return false
    end

    local fh = io.open(filename, "wb")

    if not fh then
        return false
    end

    local data = encoded:getString()

    fh:write(data)
    fh:close()

    -- Validate that the png is valid. LÖVE's filesystem only sees its own
    -- directories, so the written file is fed back as FileData instead
    local success = pcall(function()
        return love.image.newImageData(love.filesystem.newFileData(data, "map_image.png"))
    end)

    return success
end

return mapImageGenerator
