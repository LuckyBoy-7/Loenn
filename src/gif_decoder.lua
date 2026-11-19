-- Minimal pure Lua GIF87a/GIF89a decoder.
--
-- LÖVE has no GIF decoder (its stb_image build only enables JPEG/BMP/TGA/HDR), so preview GIFs
-- are decoded here into RGBA frames and then uploaded as regular love Images by the caller.
--
-- The decoder handles the parts that matter for previews: global/local color tables, frame
-- offsets, interlacing, transparency and the three disposal methods. Frames are composed into
-- full logical-screen RGBA strings, so the caller does not have to stitch deltas together.

local gifDecoder = {}

-- Bigger images are not useful as previews and would make the pure Lua fallback crawl.
gifDecoder.MAX_PIXELS = 2048 * 2048
gifDecoder.MAX_FRAMES = 300

local hasFfi, ffi = pcall(require, "ffi")

local function u16(data, position)
    local a, b = data:byte(position, position + 1)

    return a + b * 256
end

local function readPalette(data, position, count)
    local palette = {}

    for index = 0, count - 1 do
        local r, g, b = data:byte(position, position + 2)
        palette[index] = r + g * 256 + b * 65536

        position = position + 3
    end

    return palette, position
end

-- Concatenates the GIF sub-block chain starting at `position` and returns the new position
-- (past the block terminator).
local function readSubBlocks(data, position)
    local parts = {}

    while true do
        local length = data:byte(position)

        if not length or length == 0 then
            return table.concat(parts), position + 1
        end

        parts[#parts + 1] = data:sub(position + 1, position + length)

        position = position + length + 1
    end
end

local function skipSubBlocks(data, position)
    local _, newPosition = readSubBlocks(data, position)

    return newPosition
end

-- LZW decompression used by GIF image data. Returns a string of palette indices (one byte per
-- pixel) or nil plus an error message.
local function lzwDecode(data, minCodeSize, pixelCount)
    if minCodeSize < 2 or minCodeSize > 8 then
        return nil, "invalid LZW minimum code size"
    end

    local clearCode = 2 ^ minCodeSize
    local endCode = clearCode + 1
    local codeSize = minCodeSize + 1
    local nextCode = endCode + 1
    local dictionary
    local previous

    local function reset()
        dictionary = {}

        for index = 0, clearCode - 1 do
            dictionary[index] = string.char(index)
        end

        codeSize = minCodeSize + 1
        nextCode = endCode + 1
        previous = nil
    end

    local bitBuffer = 0
    local bitCount = 0
    local position = 1
    local dataLength = #data

    local function readCode()
        while bitCount < codeSize do
            if position > dataLength then
                return nil
            end

            bitBuffer = bitBuffer + data:byte(position) * (2 ^ bitCount)

            position = position + 1
            bitCount = bitCount + 8
        end

        local code = bitBuffer % (2 ^ codeSize)

        bitBuffer = math.floor(bitBuffer / 2 ^ codeSize)
        bitCount = bitCount - codeSize

        return code
    end

    local output = {}
    local outputLength = 0

    reset()

    while true do
        local code = readCode()

        if code == nil or code == endCode then
            break
        end

        if code == clearCode then
            reset()

        else
            local entry

            if dictionary[code] then
                entry = dictionary[code]

            elseif code == nextCode and previous then
                entry = previous .. previous:sub(1, 1)

            else
                return nil, "invalid LZW code"
            end

            output[#output + 1] = entry
            outputLength = outputLength + #entry

            if outputLength >= pixelCount then
                break
            end

            if previous and nextCode < 4096 then
                dictionary[nextCode] = previous .. entry:sub(1, 1)
                nextCode = nextCode + 1

                if nextCode == 2 ^ codeSize and codeSize < 12 then
                    codeSize = codeSize + 1
                end
            end

            previous = entry
        end
    end

    local result = table.concat(output)

    if #result < pixelCount then
        result = result .. string.rep("\0", pixelCount - #result)

    elseif #result > pixelCount then
        result = result:sub(1, pixelCount)
    end

    return result
end

local function canvasToRGBA(canvas, width, height)
    local count = width * height

    if hasFfi then
        local buffer = ffi.new("uint8_t[?]", count * 4)
        local offset = 0

        for index = 1, count do
            local color = canvas[index]

            if color then
                buffer[offset] = color % 256
                buffer[offset + 1] = math.floor(color / 256) % 256
                buffer[offset + 2] = math.floor(color / 65536) % 256
                buffer[offset + 3] = 255
            end

            offset = offset + 4
        end

        return ffi.string(buffer, count * 4)
    end

    local parts = {}

    for index = 1, count do
        local color = canvas[index]

        if color then
            parts[index] = string.char(color % 256, math.floor(color / 256) % 256,
                math.floor(color / 65536) % 256, 255)

        else
            parts[index] = "\0\0\0\0"
        end
    end

    return table.concat(parts)
end

local function copyCanvas(canvas)
    local copy = {}

    for index, color in pairs(canvas) do
        copy[index] = color
    end

    return copy
end

local function clearRect(canvas, left, top, width, height, screenWidth, screenHeight)
    for y = 0, height - 1 do
        local canvasY = top + y

        if canvasY >= 0 and canvasY < screenHeight then
            for x = 0, width - 1 do
                local canvasX = left + x

                if canvasX >= 0 and canvasX < screenWidth then
                    canvas[canvasY * screenWidth + canvasX + 1] = nil
                end
            end
        end
    end
end

local function interlaceRows(height)
    local rows = {}
    local starts = {0, 4, 2, 1}
    local steps = {8, 8, 4, 2}

    for pass = 1, 4 do
        for y = starts[pass], height - 1, steps[pass] do
            rows[#rows + 1] = y
        end
    end

    return rows
end

function gifDecoder.decode(data)
    if type(data) ~= "string" or #data < 13 then
        return nil, "not a GIF file"
    end

    local signature = data:sub(1, 6)

    if signature ~= "GIF87a" and signature ~= "GIF89a" then
        return nil, "not a GIF file"
    end

    local width, height = u16(data, 7), u16(data, 9)

    if width <= 0 or height <= 0 then
        return nil, "invalid GIF dimensions"
    end

    if width * height > gifDecoder.MAX_PIXELS then
        return nil, "GIF is too large for a preview"
    end

    local packed = data:byte(11)
    local position = 14
    local globalPalette

    if packed >= 128 then
        local count = 2 ^ ((packed % 8) + 1)

        globalPalette, position = readPalette(data, position, count)
    end

    local canvas = {}
    local frames = {}
    local disposal = 0
    local delay = 0
    local transparent

    while true do
        local block = data:byte(position)

        if block == nil or block == 0x3B then
            break
        end

        position = position + 1

        if block == 0x21 then
            local label = data:byte(position)

            position = position + 1

            if label == 0xF9 then
                local size = data:byte(position)

                position = position + 1

                local flags = data:byte(position)

                disposal = math.floor(flags / 4) % 8
                delay = u16(data, position + 1)
                transparent = (flags % 2 == 1) and data:byte(position + 3) or nil

                position = position + size + 1

            else
                position = skipSubBlocks(data, position)
            end

        elseif block == 0x2C then
            local left = u16(data, position)
            local top = u16(data, position + 2)
            local frameWidth = u16(data, position + 4)
            local frameHeight = u16(data, position + 6)
            local flags = data:byte(position + 8)

            position = position + 9

            local palette = globalPalette

            if flags >= 128 then
                local count = 2 ^ ((flags % 8) + 1)

                palette, position = readPalette(data, position, count)
            end

            if not palette then
                palette = {}

                for index = 0, 255 do
                    palette[index] = index * 0x010101
                end
            end

            local minCodeSize = data:byte(position)

            position = position + 1

            local imageData

            imageData, position = readSubBlocks(data, position)

            local indices, lzwError = lzwDecode(imageData, minCodeSize, frameWidth * frameHeight)

            if not indices then
                return nil, lzwError
            end

            local savedCanvas

            if disposal == 3 then
                savedCanvas = copyCanvas(canvas)
            end

            local rows

            if math.floor(flags / 64) % 2 == 1 then
                rows = interlaceRows(frameHeight)

            else
                rows = {}

                for y = 0, frameHeight - 1 do
                    rows[#rows + 1] = y
                end
            end

            local pixelIndex = 1

            for _, row in ipairs(rows) do
                local canvasY = top + row

                if canvasY >= 0 and canvasY < height then
                    local canvasRow = canvasY * width

                    for x = 0, frameWidth - 1 do
                        local colorIndex = indices:byte(pixelIndex)

                        pixelIndex = pixelIndex + 1

                        local canvasX = left + x

                        if colorIndex ~= transparent and canvasX >= 0 and canvasX < width then
                            canvas[canvasRow + canvasX + 1] = palette[colorIndex]
                        end
                    end
                end
            end

            frames[#frames + 1] = {
                rgba = canvasToRGBA(canvas, width, height),
                delay = delay / 100
            }

            if #frames >= gifDecoder.MAX_FRAMES then
                break
            end

            if disposal == 2 then
                clearRect(canvas, left, top, frameWidth, frameHeight, width, height)

            elseif disposal == 3 and savedCanvas then
                canvas = savedCanvas
            end

            disposal = 0
            delay = 0
            transparent = nil
        else
            return nil, "unexpected GIF block"
        end
    end

    if #frames == 0 then
        return nil, "GIF contains no frames"
    end

    return {
        width = width,
        height = height,
        frames = frames
    }
end

return gifDecoder
