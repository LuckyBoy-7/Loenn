-- Ghost silhouettes: reads the player/holdable states written by the LoennHelper game mod and draws
-- the latest state of each room in the editor.

local loadedState = require("loaded_state")
local configs = require("configs")
local fileLocations = require("file_locations")
local utils = require("utils")
local virtualFs = require("virtual_fs")
local viewportHandler = require("viewport_handler")
local drawableSprite = require("structs.drawable_sprite")
local drawableRectangle = require("structs.drawable_rectangle")
local smartDrawingBatch = require("structs.smart_drawing_batch")

local ghost = {
    _type = "device",
    _enabled = true,
    name = "GhostDevice"
}

local STATE_FOLDER = "ModFiles/LoennHelper"
local SILHOUETTE_FOLDER = "Graphics/Atlases/Gameplay/characters/loennhelper_silhouette"
local PLAYER_TEXTURE = "madeline"
local PLAYER_CROUCH_TEXTURE = "madeline_crouch"
local PLAYER_HITBOX_TEXTURE = "madeline_hitbox"
local PLAYER_CROUCH_HITBOX_TEXTURE = "madeline_crouch_hitbox"
local SPINNER_HITBOX_TEXTURE = "spinner_hitbox"
local OPACITY = 0.33
local HITBOX_OPACITY = 0.66
local HEARTBEAT_INTERVAL = 3
local DATA_INTERVAL = 1

local playerStates = {}
local holdableStates = {}
local batch = smartDrawingBatch.createOrderedBatch()
local images = {}
local lastRoomName
local heartbeatTime = 0
local dataTime = 0

if not configs.ghost then
    configs.ghost = {
        showPlayer = false,
        showPlayerHitbox = false,
        showHoldables = false,
        showHitboxes = true
    }
end

local function gamePath(name)
    return utils.joinpath(fileLocations.getCelesteDir(), STATE_FOLDER, name)
end

local function readStateFile(name)
    local handle = io.open(gamePath(name), "r")

    if not handle then
        return nil
    end

    local content = handle:read("*a")

    handle:close()

    return content
end

local function touchHeartbeat()
    local handle = io.open(gamePath("loennOpen"), "w")

    if handle then
        handle:close()
    end
end

local function parseCsv(line)
    local values = {}

    for value in (line .. ","):gmatch("(.-),") do
        table.insert(values, value)
    end

    return values
end

local function parsePlayerStates(content)
    local states = {}
    local lines = {}

    for line in content:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end

    local count = tonumber(lines[1] and lines[1]:match("^(%d+)"))

    if not count then
        return states
    end

    for index = 2, count + 1 do
        local values = lines[index] and parseCsv(lines[index])

        if values and values[1] then
            local id = tonumber(values[1])
            local x = tonumber(values[3])
            local y = tonumber(values[4])

            if id and x and y then
                table.insert(states, {
                    id = id,
                    roomName = values[2] or "",
                    x = x,
                    y = y,
                    color = values[5] or "FFFFFF",
                    flipX = values[6] == "True",
                    flipY = values[7] == "True",
                    ducking = values[8] == "True"
                })
            end
        end
    end

    return states
end

local function parseHoldableStates(content)
    local states = {}
    local lines = {}

    for line in content:gmatch("[^\r\n]+") do
        table.insert(lines, line)
    end

    local count = tonumber(lines[1] and lines[1]:match("^(%d+)"))

    if not count then
        return states
    end

    for index = 2, count + 1 do
        local values = lines[index] and parseCsv(lines[index])

        if values and values[1] then
            local id = tonumber(values[1])
            local x = tonumber(values[3])
            local y = tonumber(values[4])

            if id and x and y and values[5] then
                table.insert(states, {
                    id = id,
                    roomName = values[2] or "",
                    x = x,
                    y = y,
                    sprite = values[5],
                    flipX = values[6] == "True",
                    flipY = values[7] == "True"
                })
            end
        end
    end

    return states
end

local function getSilhouetteImage(name)
    local cached = images[name]

    if cached ~= nil then
        return cached or nil
    end

    local image
    local relative = SILHOUETTE_FOLDER .. "/" .. name .. ".png"
    local owner = virtualFs.getOwner(relative)
    local paths = {}

    if owner then
        table.insert(paths, "$" .. owner .. "$/" .. relative)
    end

    table.insert(paths, "$LoennHelper$/" .. relative)

    for _, path in ipairs(paths) do
        local success, result = pcall(love.graphics.newImage, path)

        if success then
            image = result

            break
        end
    end

    images[name] = image or false

    return image
end

local function getSilhouetteMeta(name)
    local image = getSilhouetteImage(name)

    if not image then
        return nil
    end

    local width, height = image:getDimensions()

    return {
        image = image,
        width = width,
        height = height,
        realWidth = width,
        realHeight = height,
        offsetX = 0,
        offsetY = 0,
        quad = love.graphics.newQuad(0, 0, width, height, width, height)
    }
end

local function getColor(colorHex, alpha)
    local success, r, g, b = utils.parseHexColor(colorHex or "FFFFFF")

    if not success then
        r, g, b = 1, 1, 1
    end

    return {r, g, b, alpha}
end

local function createPlayerSprite(state, textureName, opacity, colorHex)
    local meta = getSilhouetteMeta(textureName)

    if not meta then
        return nil
    end

    local sprite = drawableSprite.fromMeta(meta, {
        x = state.x,
        y = state.y,
        scaleX = state.flipX and -1 or 1,
        scaleY = state.flipY and -1 or 1,
        color = getColor(colorHex or state.color, opacity),
        justificationX = 0.5,
        justificationY = 0.5,
        depth = 0
    })

    -- Keep the sprite's feet on the recorded position, matching the game's origin
    sprite.y = sprite.y - ((state.flipY and -1 or 1) * meta.height / 2)

    return sprite
end

local function createHoldableSprite(state)
    local sprite = drawableSprite.fromTexture(state.sprite, {
        x = state.x,
        y = state.y,
        scaleX = state.flipX and -1 or 1,
        scaleY = state.flipY and -1 or 1,
        color = {1, 1, 1, OPACITY},
        justificationX = 0.5,
        justificationY = 0.5,
        depth = 0
    })

    if sprite then
        -- Same origin correction as the source plugin: center the sprite on the holdable
        sprite.y = sprite.y - ((state.flipY and -1 or 1) * sprite.meta.height / 2)
    end

    return sprite
end

local function roomMatches(stateRoom, selectedRoom)
    return stateRoom == selectedRoom or ("lvl_" .. stateRoom) == selectedRoom
end

local function getPlayerStates(roomName)
    local states = {}

    for _, state in ipairs(playerStates) do
        if roomMatches(state.roomName, roomName) then
            table.insert(states, state)
        end
    end

    table.sort(states, function(a, b)
        return a.id < b.id
    end)

    return states
end

local function getHoldableStates(roomName)
    local states = {}

    for _, state in ipairs(holdableStates) do
        if roomMatches(state.roomName, roomName) then
            table.insert(states, state)
        end
    end

    table.sort(states, function(a, b)
        return a.id < b.id
    end)

    return states
end

local function addPlayer(roomName)
    local states = getPlayerStates(roomName)

    for _, state in ipairs(states) do
        if configs.ghost.showPlayer then
            local texture

            if state.ducking then
                texture = PLAYER_CROUCH_TEXTURE
            else
                texture = PLAYER_TEXTURE
            end

            local sprite = createPlayerSprite(state, texture, OPACITY, state.color)

            if sprite then
                batch:addFromDrawable(sprite)
            end
        end

        if configs.ghost.showPlayerHitbox then
            local texture

            if state.ducking then
                texture = PLAYER_CROUCH_HITBOX_TEXTURE
            else
                texture = PLAYER_HITBOX_TEXTURE
            end

            -- Hitbox silhouettes are white; tinting them with the hair color makes them
            -- almost invisible on dark rooms
            local sprite = createPlayerSprite(state, texture, HITBOX_OPACITY, "FFFFFF")

            if sprite then
                batch:addFromDrawable(sprite)
            end
        end
    end
end

local function addHoldable(roomName)
    if not configs.ghost.showHoldables then
        return
    end

    for _, state in ipairs(getHoldableStates(roomName)) do
        local sprite = createHoldableSprite(state)

        if sprite then
            batch:addFromDrawable(sprite)
        end
    end
end

local function addHitboxes(room)
    if not configs.ghost.showHitboxes then
        return
    end

    local spinnerMeta = getSilhouetteMeta(SPINNER_HITBOX_TEXTURE)

    for _, entity in ipairs(room.entities) do
        local name = entity._name
        local sprite

        if name == "spinner" or name == "FrostHelper/IceSpinner" then
            if spinnerMeta then
                sprite = drawableSprite.fromMeta(spinnerMeta, {
                    x = entity.x or 0,
                    y = entity.y or 0,
                    color = {1, 1, 1, 1},
                    justificationX = 0.5,
                    justificationY = 0,
                    depth = 0
                })

                -- The source plugin still applies the centre-origin correction after setting
                -- justificationY = 0, otherwise the spinner hitbox sits too low
                sprite.y = sprite.y - spinnerMeta.height / 2
            end

        elseif name and name:match("[Ss]pikes?") then
            local x = entity.x or 0
            local y = entity.y or 0
            local width = entity.width or 3
            local height = entity.height or 3

            -- Mirror the source plugin's per-direction offsets exactly. The spike entity origin is
            -- already at the collision edge for Down/Right, so those directions must not be moved.
            if name:match("Right") then
                x = x
            elseif name:match("Left") then
                x = x - 3
            elseif name:match("Up") then
                y = y - 3
            elseif name:match("Down") then
                y = y
            end

            sprite = drawableRectangle.fromRectangle("line", x, y, width, height, "ff0000")
        end

        if sprite then
            batch:addFromDrawable(sprite)
        end
    end
end

local function rebuild()
    batch:clear()

    local room = loadedState.getSelectedRoom()

    if not room then
        lastRoomName = nil

        return
    end

    lastRoomName = room.name

    addPlayer(room.name)
    addHoldable(room.name)
    addHitboxes(room)
end

function ghost.update(dt)
    heartbeatTime = heartbeatTime + dt

    if heartbeatTime >= HEARTBEAT_INTERVAL then
        heartbeatTime = heartbeatTime - HEARTBEAT_INTERVAL
        touchHeartbeat()
    end

    dataTime = dataTime + dt

    if dataTime >= DATA_INTERVAL then
        dataTime = dataTime - DATA_INTERVAL

        local playerContent = readStateFile("PlayerStatePath.txt")
        local holdableContent = readStateFile("HoldableStatePath.txt")

        if playerContent then
            playerStates = parsePlayerStates(playerContent)
        end

        if holdableContent then
            holdableStates = parseHoldableStates(holdableContent)
        end

        if loadedState.getSelectedRoom() then
            rebuild()
        end
    end

    local room = loadedState.getSelectedRoom()

    if room and room.name ~= lastRoomName then
        rebuild()
    end
end

function ghost.draw()
    if not loadedState.map then
        return
    end

    local room = loadedState.getSelectedRoom()

    if not room then
        return
    end

    viewportHandler.drawRelativeTo(room.x, room.y, function()
        batch:draw()
    end)
end

function ghost.clear()
    playerStates = {}
    holdableStates = {}
    batch:clear()

    local handle = io.open(gamePath("ClearPaths"), "w")

    if handle then
        handle:close()
    end
end

local function saveConfig()
    require("utils.config").writeConfig(configs, true)
end

local function toggle(key)
    configs.ghost[key] = not configs.ghost[key]

    saveConfig()
    rebuild()

    return configs.ghost[key]
end

function ghost.togglePlayer()
    return toggle("showPlayer")
end

function ghost.togglePlayerHitbox()
    return toggle("showPlayerHitbox")
end

function ghost.toggleHoldables()
    return toggle("showHoldables")
end

function ghost.getPlayer()
    return configs.ghost.showPlayer
end

function ghost.getPlayerHitbox()
    return configs.ghost.showPlayerHitbox
end

function ghost.getHoldables()
    return configs.ghost.showHoldables
end

function ghost.toggleHitboxes()
    return toggle("showHitboxes")
end

function ghost.getHitboxes()
    return configs.ghost.showHitboxes
end

return ghost
