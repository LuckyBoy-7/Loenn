-- Auto Add Background Tiles Around: fills background tiles around foreground tile edges and/or
-- spinner entities using the background tile that was clicked. The generated area is limited to
-- Radius tiles and each cell is filled according to Density, with a small bonus for cells that
-- already have background tile neighbours.

local notifications = require("ui.notification")

local script = {}

script.name = "autoBackgroundTilesAround"
script.title = "Auto Add Background Tiles Around"
script.description = "Fills background tiles around foreground tile edges and spinner entities."

local bit = require("bit")

local current
local seed = os.time()

local MIN_RADIUS = 1
local MAX_RADIUS = 10
local DEFAULT_RADIUS = 2

local MIN_SMOOTHING_ITERATIONS = 0
local MAX_SMOOTHING_ITERATIONS = 10
local DEFAULT_SMOOTHING_ITERATIONS = 4

--- Random

local function hash(x, y, channel)
    local value = x * 374761393 + y * 668265263 + seed * 144665 + channel * 1013904223
    value = bit.bxor(value, bit.rshift(value, 13))
    value = value * 1274126177
    value = bit.band(value, 0x7fffffff)

    return value / 0x7fffffff
end

--- Helpers

local function isEmptyTile(tile)
    return tile == nil or tile == "0" or tile == "" or tile == " "
end

local function isFilled(matrix, x, y, width, height)
    if x < 1 or y < 1 or x > width or y > height then
        return false
    end

    return not isEmptyTile(matrix:get(x, y, "0"))
end

local function addAnchor(anchors, seen, x, y)
    local key = x .. ":" .. y

    if not seen[key] then
        seen[key] = true
        table.insert(anchors, {x = x, y = y})
    end
end

-- The edge of every 4-connected foreground tile component. A tile is an edge tile when at
-- least one of its four direct neighbours is empty (or outside the room).
local function collectForegroundEdgeAnchors(room)
    local anchors = {}
    local tiles = room.tilesFg

    if not tiles or not tiles.matrix then
        return anchors
    end

    local matrix = tiles.matrix
    local width, height = matrix:size()
    local filled = {}

    for y = 1, height do
        filled[y] = {}

        for x = 1, width do
            filled[y][x] = isFilled(matrix, x, y, width, height)
        end
    end

    local visited = {}
    local directions = {{1, 0}, {-1, 0}, {0, 1}, {0, -1}}

    for y = 1, height do
        for x = 1, width do
            if filled[y][x] and not (visited[y] and visited[y][x]) then
                local stack = {{x, y}}
                visited[y] = visited[y] or {}
                visited[y][x] = true

                while #stack > 0 do
                    local cell = table.remove(stack)
                    local cx, cy = cell[1], cell[2]
                    local isEdge = false

                    for _, direction in ipairs(directions) do
                        local nx, ny = cx + direction[1], cy + direction[2]

                        if not (filled[ny] and filled[ny][nx]) then
                            isEdge = true
                        end

                        if filled[ny] and filled[ny][nx] and not (visited[ny] and visited[ny][nx]) then
                            visited[ny] = visited[ny] or {}
                            visited[ny][nx] = true
                            table.insert(stack, {nx, ny})
                        end
                    end

                    if isEdge then
                        table.insert(anchors, {x = cx, y = cy})
                    end
                end
            end
        end
    end

    return anchors
end

-- Element positions are room-local pixels; spinner entities are treated as occupying the tile
-- their top-left corner is in.
local function collectSpinnerAnchors(room)
    local anchors = {}

    for _, entity in ipairs(room.entities or {}) do
        local name = entity._name

        if type(name) == "string" and name:lower():find("spinner", 1, true)
            and type(entity.x) == "number" and type(entity.y) == "number" then
            table.insert(anchors, {
                x = math.floor(entity.x / 8) + 1,
                y = math.floor(entity.y / 8) + 1
            })
        end
    end

    return anchors
end

local function collectAnchors(room, args)
    args = args or {}
    local anchors = {}
    local seen = {}

    if args.aroundForegroundTiles ~= false then
        for _, anchor in ipairs(collectForegroundEdgeAnchors(room)) do
            addAnchor(anchors, seen, anchor.x, anchor.y)
        end
    end

    if args.aroundSpinner ~= false then
        for _, anchor in ipairs(collectSpinnerAnchors(room)) do
            addAnchor(anchors, seen, anchor.x, anchor.y)
        end
    end

    return anchors
end

local function countBackgroundNeighbours(matrix, x, y, width, height)
    local count = 0

    for oy = -1, 1 do
        for ox = -1, 1 do
            if ox ~= 0 or oy ~= 0 then
                if isFilled(matrix, x + ox, y + oy, width, height) then
                    count = count + 1
                end
            end
        end
    end

    return count
end

-- One synchronous cellular automaton pass over the candidate cells. Isolated tiles are removed,
-- while empty cells with enough filled neighbours are filled in to connect nearby clusters.
local function smoothPass(matrix, candidates, width, height, tile)
    local updates = {}

    for index, cell in ipairs(candidates) do
        local neighbours = countBackgroundNeighbours(matrix, cell.x, cell.y, width, height)
        local filled = not isEmptyTile(matrix:get(cell.x, cell.y, "0"))

        if filled then
            updates[index] = neighbours >= 1

        else
            updates[index] = neighbours >= 5
        end
    end

    for index, cell in ipairs(candidates) do
        matrix:set(cell.x, cell.y, updates[index] and tile or "0")
    end
end

--- Applying

function script.applyAround(room, args, tile)
    local tiles = room.tilesBg

    if not tiles or not tiles.matrix then
        return
    end

    args = args or {}

    local anchors = collectAnchors(room, args)

    if #anchors == 0 then
        notifications.notify("Auto Add Background Tiles Around: no foreground tile edges or spinner entities found.")
        return
    end

    local matrix = tiles.matrix
    local width, height = matrix:size()

    local radius = math.max(MIN_RADIUS, math.min(MAX_RADIUS, tonumber(args.radius) or DEFAULT_RADIUS))
    local density = math.max(0, math.min(1, tonumber(args.density) or 0.5))
    local smoothingIterations = math.max(MIN_SMOOTHING_ITERATIONS,
        math.min(MAX_SMOOTHING_ITERATIONS,
            math.floor(tonumber(args.iterations) or DEFAULT_SMOOTHING_ITERATIONS)))
    local radiusSquared = radius * radius

    -- Only cells inside the radius are re-rolled. Everything outside keeps its existing tiles,
    -- which also lets those existing tiles contribute to the neighbour bonus at the border.
    -- Marking the radius around each anchor is cheaper than testing every room cell against every
    -- anchor, especially for large rooms with many edge tiles.
    local near = {}

    for _, anchor in ipairs(anchors) do
        local minX = math.max(1, math.floor(anchor.x - radius))
        local maxX = math.min(width, math.ceil(anchor.x + radius))
        local minY = math.max(1, math.floor(anchor.y - radius))
        local maxY = math.min(height, math.ceil(anchor.y + radius))

        for y = minY, maxY do
            near[y] = near[y] or {}

            for x = minX, maxX do
                local dx, dy = x - anchor.x, y - anchor.y

                if dx * dx + dy * dy <= radiusSquared then
                    near[y][x] = true
                end
            end
        end
    end

    local candidates = {}

    for y = 1, height do
        for x = 1, width do
            if near[y] and near[y][x] then
                table.insert(candidates, {
                    x = x,
                    y = y,
                    order = hash(x, y, 31)
                })
            end
        end
    end

    -- Process in a stable pseudo-random order so newly placed tiles can influence later cells
    -- without always favouring one side of the room.
    table.sort(candidates, function(a, b)
        return a.order < b.order
    end)

    for _, cell in ipairs(candidates) do
        local neighbours = countBackgroundNeighbours(matrix, cell.x, cell.y, width, height)

        -- Density is the base chance. Existing neighbours add a small, density-scaled bonus so
        -- clusters grow together instead of looking like isolated noise. Multiplying keeps
        -- Density 0 empty even when the area is surrounded by existing tiles.
        local bonus = math.min(0.35, neighbours * 0.05)
        local probability = math.min(1, density * (1 + bonus))

        if probability >= 1 or hash(cell.x, cell.y, 32) < probability then
            matrix:set(cell.x, cell.y, tile)

        else
            matrix:set(cell.x, cell.y, "0")
        end
    end

    -- Run the requested number of cellular automaton passes to remove isolated single tiles and
    -- fill small holes. Density 0 and 1 are already uniform, so there is nothing to smooth.
    if density > 0 and density < 1 then
        for _ = 1, smoothingIterations do
            smoothPass(matrix, candidates, width, height, tile)
        end
    end

    -- Regenerate the autotiled quads for the whole layer
    require("brushes").placeTile(room, 1, 1, matrix, "tilesBg")
end

local applyScript = {
    name = "autoBackgroundTilesAroundApply",
    title = script.title
}

function applyScript.run(room, args)
    if not current or not current.room or room.name ~= current.room.name then
        return
    end

    script.applyAround(room, args, current.tile)
end

--- Panel

local function getDefaults()
    return {
        radius = DEFAULT_RADIUS,
        aroundForegroundTiles = true,
        aroundSpinner = true,
        density = 0.5,
        iterations = DEFAULT_SMOOTHING_ITERATIONS
    }
end

local fieldInformation = {
    radius = {
        fieldType = "number",
        displayName = "Radius",
        tooltipText = "Radius in tiles around the reference points (1-10). Fractional values are allowed.",
        minimumValue = MIN_RADIUS,
        maximumValue = MAX_RADIUS
    },
    aroundForegroundTiles = {
        displayName = "Around Foreground Tiles",
        tooltipText = "Use the edge tiles of every connected foreground tile area as reference points."
    },
    aroundSpinner = {
        displayName = "Around Spinner",
        tooltipText = "Use entities whose name contains 'spinner' as reference points."
    },
    density = {
        fieldType = "number",
        displayName = "Density",
        tooltipText = "Chance that a tile inside the radius is filled. Tiles with filled neighbours get a small bonus.",
        minimumValue = 0,
        maximumValue = 1
    },
    iterations = {
        fieldType = "integer",
        displayName = "CA Iterations",
        tooltipText = "Number of cellular automaton smoothing passes. 0 disables smoothing.",
        minimumValue = MIN_SMOOTHING_ITERATIONS,
        maximumValue = MAX_SMOOTHING_ITERATIONS
    }
}

local function openPanel()
    -- Lazy: the scripts tool loads this module while it is being registered
    local scriptsPanel = require("ui.windows.scripts_panel")
    local toolHandler = require("tools")
    local defaults = getDefaults()

    if current.values then
        for key, value in pairs(current.values) do
            defaults[key] = value
        end
    end

    -- Values saved by an older version may be outside the current slider range
    defaults.radius = math.max(MIN_RADIUS,
        math.min(MAX_RADIUS, tonumber(defaults.radius) or DEFAULT_RADIUS))
    defaults.density = math.max(0, math.min(1, tonumber(defaults.density) or 0.5))
    defaults.iterations = math.max(MIN_SMOOTHING_ITERATIONS,
        math.min(MAX_SMOOTHING_ITERATIONS,
            math.floor(tonumber(defaults.iterations) or DEFAULT_SMOOTHING_ITERATIONS)))

    local panelScript = {
        name = script.name .. "Panel",
        title = script.title,
        fieldOrder = {"radius", "aroundForegroundTiles", "aroundSpinner", "density", "iterations"},
        defaultData = defaults,
        fieldInformation = fieldInformation
    }

    scriptsPanel.open(panelScript, nil, function(values)
        local aroundForegroundTiles = values.aroundForegroundTiles ~= false
        local aroundSpinner = values.aroundSpinner ~= false

        if not aroundForegroundTiles and not aroundSpinner then
            notifications.notify("Auto Add Background Tiles Around: enable at least one Around option.")
            return false
        end

        if #collectAnchors(current.room, values) == 0 then
            notifications.notify("Auto Add Background Tiles Around: no foreground tile edges or spinner entities found.")
            return false
        end

        current.values = values

        -- The seed changes on every run
        seed = os.time() + math.floor(love.timer.getTime() * 1000) % 2147483647

        -- Focus switching temporarily selects Preview/Name, so currentTool is not necessarily
        -- the Scripts tool here. Always run through the Scripts tool that owns executeScript.
        local scriptsTool = toolHandler.tools.scripts or toolHandler.currentTool

        if scriptsTool and scriptsTool.executeScript then
            scriptsTool.executeScript(applyScript, values, nil, {current.room})
        end

        -- Keep the panel open so the density/radius can be adjusted and rerun
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

--- Entry point

function script.open(context)
    local loadedState = require("loaded_state")
    local room = context and context.focusedItem

    if not room or require("utils").typeof(room) ~= "room" then
        room = loadedState.getSelectedRoom()
    end

    local message

    if not room then
        message = "Auto Add Background Tiles Around: click on an existing background tile first."

    elseif not room.tilesBg or not room.tilesBg.matrix then
        message = "Auto Add Background Tiles Around: this room has no background tile layer."

    else
        local mouseMapX = context and context.mouseMapX or 0
        local mouseMapY = context and context.mouseMapY or 0
        local tileX = math.floor((mouseMapX - (room.x or 0)) / 8) + 1
        local tileY = math.floor((mouseMapY - (room.y or 0)) / 8) + 1
        local width, height = room.tilesBg.matrix:size()

        if tileX < 1 or tileY < 1 or tileX > width or tileY > height then
            message = "Auto Add Background Tiles Around: click on an existing background tile first."

        else
            local tile = room.tilesBg.matrix:get(tileX, tileY, "0")

            if isEmptyTile(tile) then
                message = "Auto Add Background Tiles Around: click on an existing background tile first."

            else
                current = {
                    room = room,
                    tile = tile,
                    values = current and current.values or nil
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
