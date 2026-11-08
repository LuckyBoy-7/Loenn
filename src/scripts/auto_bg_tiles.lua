-- Auto Add Background Tiles: fills a room's background tile layer with a generated pattern using
-- the background tile that was clicked. The pattern can be configured and rerun without closing
-- the panel; the random seed comes from the system time.

local uiElements = require("ui.elements")
local dropdowns = require("ui.widgets.dropdown")
local brushes = require("brushes")
local notifications = require("ui.notification")

local script = {}

script.name = "autoBackgroundTiles"
script.title = "Auto Add Background Tiles"
script.description = "Fills the room background with a generated pattern using the clicked background tile."

local styleOrder = {"perlin", "fractal", "mixed", "warped", "worley", "cave"}

local styles = {
    perlin = {
        label = "Perlin Noise",
        fields = {"scale", "threshold", "smooth", "invert"}
    },
    fractal = {
        label = "Fractal Noise",
        fields = {"scale", "octaves", "threshold", "smooth", "invert"}
    },
    mixed = {
        label = "Mixed Noise",
        fields = {"scale", "octaves", "threshold", "smooth", "invert"}
    },
    warped = {
        label = "Warped Noise",
        fields = {"scale", "octaves", "threshold", "smooth", "invert"}
    },
    worley = {
        label = "Worley Noise",
        fields = {"scale", "threshold", "smooth", "invert"}
    },
    cave = {
        label = "Cellular Cave",
        fields = {"density", "iterations", "tunnels", "invert"}
    }
}

local fieldInformation = {
    scale = {
        displayName = "Scale",
        tooltipText = "Size of the noise cells in tiles. Lower values give more, smaller blobs.",
        minimumValue = 1,
        maximumValue = 64
    },
    octaves = {
        displayName = "Octaves",
        tooltipText = "How many noise layers are added together. More octaves add smaller details.",
        minimumValue = 1,
        maximumValue = 8
    },
    threshold = {
        fieldType = "number",
        displayName = "Threshold",
        tooltipText = "Noise values above this are filled with tiles. Higher values leave more empty space.",
        minimumValue = 0,
        maximumValue = 1
    },
    smooth = {
        displayName = "Smooth",
        tooltipText = "Removes single tiles and fills single holes, which makes the edges look less noisy."
    },
    invert = {
        displayName = "Invert",
        tooltipText = "Fills the areas that would normally stay empty."
    },
    density = {
        fieldType = "number",
        displayName = "Density",
        tooltipText = "How much of the room starts filled before the cave is carved.",
        minimumValue = 0,
        maximumValue = 1
    },
    iterations = {
        displayName = "Iterations",
        tooltipText = "How many times the cave rules are applied. More iterations give smoother caves.",
        minimumValue = 1,
        maximumValue = 8
    },
    tunnels = {
        displayName = "Tunnels",
        tooltipText = "Number of random tunnels that connect otherwise separated areas.",
        minimumValue = 0,
        maximumValue = 20
    }
}

local current
local seed = os.time()

--- Noise

local bit = require("bit")

local function hash(x, y, channel, range)
    local value = x * 374761393 + y * 668265263 + seed * 144665 + channel * 1013904223
    value = bit.bxor(value, bit.rshift(value, 13))
    value = value * 1274126177
    value = bit.band(value, 0x7fffffff)

    if range then
        return (value % 1000000) / 1000000 * range
    end

    return value / 0x7fffffff
end

local function fade(value)
    return value * value * value * (value * (value * 6 - 15) + 10)
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local function valueNoise(x, y)
    local x0, y0 = math.floor(x), math.floor(y)
    local fx, fy = x - x0, y - y0
    local u, v = fade(fx), fade(fy)

    local v00 = hash(x0, y0, 1)
    local v10 = hash(x0 + 1, y0, 1)
    local v01 = hash(x0, y0 + 1, 1)
    local v11 = hash(x0 + 1, y0 + 1, 1)

    return lerp(lerp(v00, v10, u), lerp(v01, v11, u), v)
end

local function perlinNoise(x, y)
    local x0, y0 = math.floor(x), math.floor(y)
    local fx, fy = x - x0, y - y0
    local u, v = fade(fx), fade(fy)

    -- Gradient at each grid corner has to use the vector from that corner to the sample point
    local function gradient(ix, iy, dx, dy)
        local angle = hash(ix, iy, 2) * math.pi * 2

        return math.cos(angle) * dx + math.sin(angle) * dy
    end

    local n00 = gradient(x0, y0, fx, fy)
    local n10 = gradient(x0 + 1, y0, fx - 1, fy)
    local n01 = gradient(x0, y0 + 1, fx, fy - 1)
    local n11 = gradient(x0 + 1, y0 + 1, fx - 1, fy - 1)

    return math.max(0, math.min(1, lerp(lerp(n00, n10, u), lerp(n01, n11, u), v) * 0.7 + 0.5))
end

local function fractalNoise(x, y, octaves)
    local sum, amplitude, frequency, total = 0, 1, 1, 0
    octaves = math.max(1, math.floor(octaves or 1))

    for _ = 1, octaves do
        sum = sum + valueNoise(x * frequency, y * frequency) * amplitude
        total = total + amplitude
        amplitude = amplitude * 0.5
        frequency = frequency * 2
    end

    return sum / total
end

local function worleyNoise(x, y)
    local x0, y0 = math.floor(x), math.floor(y)
    local nearest = math.huge

    for oy = -1, 1 do
        for ox = -1, 1 do
            local cx, cy = x0 + ox, y0 + oy
            local px = cx + hash(cx, cy, 3)
            local py = cy + hash(cx, cy, 4)
            local dx, dy = px - x, py - y
            local distance = dx * dx + dy * dy

            if distance < nearest then
                nearest = distance
            end
        end
    end

    return 1 - math.min(1, math.sqrt(nearest))
end

local function mixedNoise(x, y, octaves)
    local base = fractalNoise(x, y, octaves)
    local cells = worleyNoise(x * 0.6 + 17.3, y * 0.6 - 9.1)

    -- Mostly large fractal shapes with a bit of cellular structure on top
    return math.max(0, math.min(1, base * 0.7 + cells * 0.3))
end

local function warpedNoise(x, y, octaves)
    -- Distort the sample position with two other noise fields: organic, cave-like contours
    local warp = 0.6
    local warpX = fractalNoise(x * 0.5 + 31.7, y * 0.5 + 7.1, 3)
    local warpY = fractalNoise(x * 0.5 - 12.3, y * 0.5 + 45.9, 3)

    return fractalNoise(x + (warpX - 0.5) * warp * 4, y + (warpY - 0.5) * warp * 4, octaves)
end

local function getNoise(style, x, y, scale, octaves)
    if style == "perlin" then
        return perlinNoise(x / scale, y / scale)

    elseif style == "fractal" then
        return fractalNoise(x / scale, y / scale, octaves)

    elseif style == "mixed" then
        return mixedNoise(x / scale, y / scale, octaves)

    elseif style == "warped" then
        return warpedNoise(x / scale, y / scale, octaves)

    elseif style == "worley" then
        return worleyNoise(x / scale, y / scale)
    end

    return 0
end

local function getDefaults()
    return {
        scale = 20,
        octaves = 3,
        threshold = 0.58,
        smooth = true,
        invert = false,
        density = 0.48,
        iterations = 4,
        tunnels = 3
    }
end

-- Cellular automata cave: start with random rock, apply the 4-5 rule a few times, keep the
-- largest open cave and connect the rest with a few tunnels
local function generateCave(width, height, density, iterations, tunnels)
    local grid = {}

    for y = 1, height do
        grid[y] = {}

        for x = 1, width do
            grid[y][x] = hash(x, y, 21) < density
        end
    end

    for _ = 1, math.max(1, iterations) do
        local nextGrid = {}

        for y = 1, height do
            nextGrid[y] = {}

            for x = 1, width do
                local filled = 0

                for oy = -1, 1 do
                    for ox = -1, 1 do
                        local nx, ny = x + ox, y + oy

                        if nx >= 1 and ny >= 1 and nx <= width and ny <= height then
                            if grid[ny][nx] then
                                filled = filled + 1
                            end
                        end
                    end
                end

                nextGrid[y][x] = filled + (grid[y][x] and 1 or 0) >= 5
            end
        end

        grid = nextGrid
    end

    -- Only remove tiny isolated holes. Keeping just the largest hole made the rest of the room
    -- solid rock, so every reasonably sized open area is kept
    local visited = {}
    local components = {}

    for y = 1, height do
        for x = 1, width do
            if not grid[y][x] and not (visited[y] and visited[y][x]) then
                local stack = {{x, y}}
                local cells = {}
                visited[y] = visited[y] or {}
                visited[y][x] = true

                while #stack > 0 do
                    local cell = table.remove(stack)
                    local cx, cy = cell[1], cell[2]

                    table.insert(cells, cell)

                    for _, offset in ipairs({{1, 0}, {-1, 0}, {0, 1}, {0, -1}}) do
                        local nx, ny = cx + offset[1], cy + offset[2]

                        if nx >= 1 and ny >= 1 and nx <= width and ny <= height
                            and not grid[ny][nx] and not (visited[ny] and visited[ny][nx]) then
                            visited[ny] = visited[ny] or {}
                            visited[ny][nx] = true
                            table.insert(stack, {nx, ny})
                        end
                    end
                end

                table.insert(components, cells)
            end
        end
    end

    for _, cells in ipairs(components) do
        if #cells < 4 then
            for _, cell in ipairs(cells) do
                grid[cell[2]][cell[1]] = true
            end
        end
    end

    -- Tunnels carve through the rock and connect separated areas
    for tunnel = 1, math.max(0, tunnels) do
        local x = 1 + math.floor(hash(tunnel, 1, 22) * width)
        local y = 1 + math.floor(hash(tunnel, 2, 22) * height)
        local steps = 12 + math.floor(hash(tunnel, 3, 22) * 20)

        for step = 1, steps do
            if x >= 1 and y >= 1 and x <= width and y <= height then
                grid[y][x] = false
            end

            local direction = math.floor(hash(tunnel, step, 23) * 4)

            if direction == 0 then
                x = x + 1

            elseif direction == 1 then
                x = x - 1

            elseif direction == 2 then
                y = y + 1

            else
                y = y - 1
            end
        end
    end

    return grid
end

function script.applyPattern(room, style, args, tile)
    local tiles = room.tilesBg

    if not tiles or not tiles.matrix then
        return
    end

    local matrix = tiles.matrix
    local width, height = matrix:size()

    local scale = math.max(1, args.scale or 16)
    local octaves = math.max(1, math.floor(args.octaves or 4))
    local threshold = math.max(0, math.min(1, args.threshold or 0.5))
    local smooth = args.smooth ~= false
    local invert = args.invert == true

    -- Clear the whole background layer first
    for y = 1, height do
        for x = 1, width do
            matrix:set(x, y, "0")
        end
    end

    local filled = {}

    if style == "cave" then
        filled = generateCave(width, height,
            math.max(0, math.min(1, args.density or 0.48)),
            math.floor(args.iterations or 4),
            math.floor(args.tunnels or 3))

        if invert then
            for y = 1, height do
                for x = 1, width do
                    filled[y][x] = not filled[y][x]
                end
            end
        end

    else
        for y = 1, height do
            filled[y] = {}

            for x = 1, width do
                local value = getNoise(style, x, y, scale, octaves)

                if invert then
                    filled[y][x] = value <= threshold

                else
                    filled[y][x] = value > threshold
                end
            end
        end

        -- Remove single tiles and fill holes. Noise alone gives very ragged edges; official maps
        -- use larger connected shapes, so this runs twice
        if smooth then
            local function smoothPass(grid)
                local smoothed = {}

                for y = 1, height do
                    smoothed[y] = {}

                    for x = 1, width do
                        local neighbours = 0

                        for oy = -1, 1 do
                            for ox = -1, 1 do
                                if ox ~= 0 or oy ~= 0 then
                                    local nx, ny = x + ox, y + oy

                                    if nx >= 1 and ny >= 1 and nx <= width and ny <= height and grid[ny][nx] then
                                        neighbours = neighbours + 1
                                    end
                                end
                            end
                        end

                        if grid[y][x] then
                            smoothed[y][x] = neighbours >= 2

                        else
                            smoothed[y][x] = neighbours >= 7
                        end
                    end
                end

                return smoothed
            end

            filled = smoothPass(smoothPass(filled))
        end
    end

    for y = 1, height do
        for x = 1, width do
            if filled[y][x] then
                matrix:set(x, y, tile)
            end
        end
    end

    -- Regenerate the autotiled quads for the whole layer
    brushes.placeTile(room, 1, 1, matrix, "tilesBg")
end

local applyScript = {
    name = "autoBackgroundTilesApply",
    title = script.title
}

function applyScript.run(room, args)
    if not current or not current.room or room.name ~= current.room.name then
        return
    end

    script.applyPattern(room, current.style, args, current.tile)
end

local function openPanel()
    -- Lazy: the scripts tool loads this module while it is being registered
    local scriptsPanel = require("ui.windows.scripts_panel")
    local toolHandler = require("tools")
    local style = current.style
    local styleData = styles[style]
    local defaults = getDefaults(style)

    if current.values then
        for key, value in pairs(current.values) do
            defaults[key] = value
        end
    end

    local styleIndex = 1

    for index, key in ipairs(styleOrder) do
        if key == style then
            styleIndex = index
        end
    end

    local labels = {}

    for _, key in ipairs(styleOrder) do
        table.insert(labels, styles[key].label)
    end

    local function buildHeader()
        local styleDropdown = dropdowns.fromList(function(_, value)
            for key, data in pairs(styles) do
                if data.label == value and key ~= current.style then
                    current.style = key
                    current.values = nil

                    -- Rebuild after the input event, the panel is replaced
                    require("ui").runLate(openPanel)

                    return
                end
            end
        end, labels, {initialItem = styleIndex})

        return uiElements.column({
            uiElements.label("Style"),
            styleDropdown
        }):with({spacing = 4})
    end

    local panelScript = {
        name = script.name .. "Panel",
        title = script.title,
        header = buildHeader,
        fieldOrder = styleData.fields,
        defaultData = defaults,
        fieldInformation = fieldInformation
    }

    scriptsPanel.open(panelScript, nil, function(values)
        current.values = values
        current.style = style

        -- The seed changes on every run
        seed = os.time() + math.floor(love.timer.getTime() * 1000) % 2147483647

        toolHandler.currentTool.executeScript(applyScript, values, nil, {current.room})

        -- Keep the panel open so the pattern can be adjusted and rerun
        return false
    end, {
        keepOpenOnRun = true,
        extraButtons = {
            {
                text = "Close Window",
                callback = function()
                    current = nil
                    scriptsPanel.close()
                end
            }
        }
    })
end

-- Validates the click and opens the pattern panel
function script.open(context)
    local loadedState = require("loaded_state")
    local room = context and context.focusedItem

    if not room or require("utils").typeof(room) ~= "room" then
        room = loadedState.getSelectedRoom()
    end

    local message

    if not room then
        message = "Auto Add Background Tiles: click on an existing background tile first."

    elseif not room.tilesBg or not room.tilesBg.matrix then
        message = "Auto Add Background Tiles: this room has no background tile layer."

    else
        local mouseMapX = context and context.mouseMapX or 0
        local mouseMapY = context and context.mouseMapY or 0
        local tileX = math.floor((mouseMapX - (room.x or 0)) / 8) + 1
        local tileY = math.floor((mouseMapY - (room.y or 0)) / 8) + 1
        local width, height = room.tilesBg.matrix:size()

        if tileX < 1 or tileY < 1 or tileX > width or tileY > height then
            message = "Auto Add Background Tiles: click on an existing background tile first."

        else
            local tile = room.tilesBg.matrix:get(tileX, tileY, "0")

            if not tile or tile == "0" or tile == "" or tile == " " then
                message = "Auto Add Background Tiles: click on an existing background tile first."

            else
                current = {
                    room = room,
                    tile = tile,
                    style = current and current.style or "fractal"
                }

                openPanel()
            end
        end
    end

    if message then
        notifications.notify(message)
    end
end

return script
