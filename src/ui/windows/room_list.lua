local ui = require("ui")
local uiElements = require("ui.elements")
local uiUtils = require("ui.utils")

local widgetUtils = require("ui.widgets.utils")
local lists = require("ui.widgets.lists")
local simpleDocks = require("ui.widgets.simple_docks")
local contextMenu = require("ui.context_menu")
local roomEditor = require("ui.room_editor")
local sceneHandler = require("scene_handler")
local languageRegistry = require("language_registry")
local mapItemUtils = require("map_item_utils")
local utils = require("utils")
local configs = require("configs")
local keyboardHelper = require("utils.keyboard")

local state = require("loaded_state")
local viewportHandler = require("viewport_handler")

local roomList = {}

local function cleanRoomName(name)
    -- Remove "lvl_" prefix

    local nameWithoutPrefix = name:match("^lvl_(.*)")

    return nameWithoutPrefix or name
end

local function roomContextEditAction(room)
    roomEditor.editExistingRoom(nil, room)
end

local function roomContextDeleteAction(room)
    -- Prompt user for deletion, unless they are holding the bypass modifier
    local bypassPrompt = keyboardHelper.modifierHeld(configs.ui.hotkeys.bypassDangerousActionWarningModifier)
    local map = state.map

    if bypassPrompt then
        mapItemUtils.deleteItem(map, room)
        state.selectItem(nil)

    else
        sceneHandler.sendEvent("editorRoomDelete", map, room, bypassPrompt)
    end
end

local roomContextActions = {
    edit = roomContextEditAction,
    delete = roomContextDeleteAction
}

local function handleContextListClickHandler(roomName)
    return function(element, action)
        local room = state.getRoomByName(roomName)

        if roomContextActions[action] then
            roomContextActions[action](room)
        end

        element:removeSelf()
    end
end

local function roomListItemContext(listItem)
    local roomName = listItem.data
    local language = languageRegistry.getLanguage()

    return uiElements.list({
        uiElements.listItem({
            text = tostring(language.ui.room_list.action.edit),
            data = "edit"
        }),
        uiElements.listItem({
            text = tostring(language.ui.room_list.action.delete),
            data = "delete"
        })
    }, handleContextListClickHandler(roomName))
end

local function roomDataToElement(list, data, element)
    if not element then
        element = uiElements.listItem()
    end

    if data then
        element.text = data.text
        element.data = data.data
    end

    return element
end

local function getRoomItems()
    local rooms = state.map and state.map.rooms or {}
    local roomItems = {}

    for _, room in ipairs(rooms) do
        local name = cleanRoomName(room.name)
        local roomItem = {
            text = name,
            data = room.name
        }

        table.insert(roomItems, roomItem)
    end

    return roomItems
end

-- Updates the list from the editor state. Never fires the list callback: that one
-- moves the camera, which should only happen when the user clicks a room.
local function updateList(list, target)
    local roomItems = getRoomItems()

    local selectedItem = state.getSelectedItem()

    -- Don't update list if we have multiple selections
    if utils.typeof(selectedItem) == "table" then
        return
    end

    if not target then
        local currentRoom = state.getSelectedRoom()

        if currentRoom then
            target = cleanRoomName(currentRoom.name)
        end
    end

    list:updateItems(roomItems, target, nil, true)
end

-- Following the selection with the camera is only wanted when the user clicks a
-- room in the list. Deleting, adding or renaming a room changes the selection
-- too and must not move the view.
local function selectRoom(roomName, moveViewport)
    local currentRoom = state.getSelectedRoom()
    local sameRoomName = currentRoom and cleanRoomName(currentRoom.name) ~= roomName and currentRoom.name ~= roomName

    if not currentRoom or sameRoomName then
        local newRoom = state.getRoomByName(roomName)

        if newRoom then
            -- TODO - Allow user to specify zoom after room selection in config
            state.selectItem(newRoom)

            if moveViewport == true then
                viewportHandler.moveToPosition(newRoom.x + newRoom.width / 2, newRoom.y + newRoom.height / 2, 1, true)
            end
        end
    end
end

function roomList.roomSelectedCallback(element, roomName)
    -- Reached when the user picks a room in the list, programmatic updates pass
    -- preventCallback and do not get here
    selectRoom(roomName, true)
end

function roomList:editorMapTargetChanged()
    return function(element, target, targetType)
        if targetType == "room" then
            local roomNameCleaned = cleanRoomName(target.name)
            local selected = self:setSelection(roomNameCleaned, true, true)

            if not selected then
                self:setFilterText("")
                self:updateItems(getRoomItems(), roomNameCleaned, nil, true)
            end
        end
    end
end

function roomList:editorMapLoaded()
    return function()
        updateList(self)
    end
end

function roomList:editorMapNew()
    return function()
        updateList(self)
    end
end

function roomList:editorRoomDeleted()
    return function(list, room)
        local viewport = viewportHandler.viewport
        local cameraX, cameraY, cameraScale = viewport.x, viewport.y, viewport.scale

        local firstRoom = state.map.rooms[1]

        if firstRoom then
            selectRoom(firstRoom.name, false)
            updateList(self, firstRoom.name)

        else
            updateList(self)
        end

        -- Deleting a room may move the focus to another one, but it must never
        -- move the view with it
        viewport.x, viewport.y, viewport.scale = cameraX, cameraY, cameraScale
    end
end

function roomList:editorRoomAdded()
    return function(list, room)
        selectRoom(room.name, false)
        updateList(self, room.name)
    end
end

function roomList:editorRoomChanged()
    return function(list, room)
        -- Manually set room so we don't update viewport
        selectRoom(room.name, false)
        mapItemUtils.sortRoomList(state.map)
        updateList(self, room.name)
    end
end

function roomList:editorRoomOrderChanged()
    return function()
        updateList(self)
    end
end

function roomList.getWindow()
    local search = ""

    local roomItems = getRoomItems()
    local listOptions = {
        initialSearch = search,
        searchBarLocation = configs.ui.lists.searchBarLocation,
        dataToElement = roomDataToElement,
        listItemContextMenu = roomListItemContext,
        listItemContextMenuOptions = {
            mode = "focused"
        }
    }
    local column, list = lists.getMagicList(roomList.roomSelectedCallback, roomItems, listOptions)

    local panel = uiElements.panel({column}):with(uiUtils.fillHeight(false))
    local window = uiElements.window(tostring(languageRegistry.getLanguage().ui.room_list.window_title), panel):with(uiUtils.fillHeight(false))

    window:with({
        editorRoomOrderChanged = roomList.editorRoomOrderChanged(list),
        editorMapTargetChanged = roomList.editorMapTargetChanged(list),
        editorMapLoaded = roomList.editorMapLoaded(list),
        editorMapNew = roomList.editorMapNew(list),
        editorRoomDeleted = roomList.editorRoomDeleted(list),
        editorRoomAdded = roomList.editorRoomAdded(list),
        editorRoomChanged = roomList.editorRoomChanged(list),
    })

    window.style.bg = {}
    window.style.border = {}
    window.style.padding = column.style.spacing

    widgetUtils.removeWindowTitlebar(window)

    -- Hide by detaching the window instead of relying on the visible flag: the panel is part of a
    -- cached parent canvas, and a visibility change alone did not remove it from the screen
    function window.setRoomListVisible(visible)
        if visible then
            if not window.parent and window._roomListParent then
                window._roomListParent:addChild(window)
                window._roomListParent:reflow()
            end

            -- While detached the map events could not reach this window: rebuild the list from the
            -- current map state when it becomes visible again
            updateList(list)

        else
            if window.parent then
                window._roomListParent = window.parent
                window.parent:removeChild(window)
                window._roomListParent:reflow()
            end
        end
    end

    -- The rooms tool finds the window through the ui module, which is a stable singleton
    local ui = require("ui")

    ui.roomListWindow = window
    window._roomList = true

    local success, toolHandler = pcall(require, "tools")
    local visible = success and toolHandler.currentToolName == "room"

    if not visible then
        ui.runLate(function()
            window.setRoomListVisible(false)
        end)
    end

    return simpleDocks.pinWidgetToEdge("left", window)
end

return roomList