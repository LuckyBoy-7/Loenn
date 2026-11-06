-- TODO - Add texture dropdown options
-- Currently too slow both in window creation and when clicking around in the style list

local ui = require("ui")
local uiElements = require("ui.elements")
local uiUtils = require("ui.utils")

local utils = require("utils")
local loadedState = require("loaded_state")
local configs = require("configs")
local persistence = require("persistence")
local keyboardHelper = require("utils.keyboard")
local languageRegistry = require("language_registry")
local stylegroundEditor = require("ui.styleground_editor")
local history = require("history")
local snapshotStruct = require("structs.snapshot")
local listWidgets = require("ui.widgets.lists")
local widgetUtils = require("ui.widgets.utils")
local formHelper = require("ui.forms.form")
local parallax = require("parallax")
local effects = require("effects")
local apply = require("apply")
local applyStruct = require("structs.apply")
local parallaxStruct = require("structs.parallax")
local effectStruct = require("structs.effect")
local formUtils = require("ui.utils.forms")
local atlases = require("atlases")

local form = require("ui.forms.form")
local tabbedWindow = require("ui.widgets.tabbed_window")
local notifications = require("ui.notification")
local dropdowns = require("ui.widgets.dropdown")

local windowPersister = require("ui.window_position_persister")
local windowPersisterName = "stylegrounds_window"

local stylegroundWindow = {}

local parallaxTextureOptions

local stylegroundWindowGroup = uiElements.group({})

-- TODO - Layouting variables that should be more dyanmic
local PREVIEW_MAX_WIDTH = 320 * 3
local PREVIEW_MAX_HEIGHT = 180 * 3
local WINDOW_STATIC_HEIGHT = 640

local function cacheParallaxTextureOptions()
    local options = parallax.getParallaxNames()

    table.sort(options)

    parallaxTextureOptions = options
end

local function addFolderIndent(text)
    return " - " .. text
end

local function applyItemIconClick(listItem, button)
    if button ~= 1 then
        return false
    end

    local interactionData = listItem.parent.interactionData
    local style = listItem.data.style

    style._collapsed = not style._collapsed

    interactionData.rebuildListItems()
end

local function getStylegroundItems(targets, items, foreground, parent)
    local language = languageRegistry.getLanguage()
    local groupIndex = 1

    items = items or {}

    for _, style in ipairs(targets) do
        local styleType = utils.typeof(style)

        if styleType == "parallax" then
            local displayName = parallax.displayName(language, style)

            table.insert(items, {
                text = displayName,
                data = {
                    style = style,
                    parentStyle = parent,
                    foreground = foreground,
                }
            })

        elseif styleType == "effect" then
            local displayName = effects.displayName(language, style)

            table.insert(items, {
                text = displayName,
                data = {
                    style = style,
                    parentStyle = parent,
                    foreground = foreground,
                }
            })

        elseif styleType == "apply" then
            if style.children then
                local childItems = getStylegroundItems(style.children, {}, foreground, style)

                local groupText = apply.displayName(language, style, groupIndex)
                local groupLabel = uiElements.label(groupText)
                local listItemData = {
                    style = style,
                    parentStyle = parent,
                    foreground = foreground,
                }

                local collapsed = style._collapsed
                local iconName = collapsed and "hidden" or "visible"

                table.insert(items, {
                    text = groupLabel,
                    data = listItemData,
                    icon = iconName,
                    iconClicked = applyItemIconClick
                })

                if not collapsed then
                    for _, child in ipairs(childItems) do
                        child.text = addFolderIndent(child.text)

                        table.insert(items, child)
                    end
                end

                groupIndex += 1
            end
        end
    end

    return items
end

-- Refreshes the row texts of the open list, e.g. after a name or texture change. Group names are
-- numbered per parent, mirroring how the rows are built.
local function updateListRowTexts(interactionData)
    local list = interactionData and interactionData.stylegroundListElement

    if not list then
        return
    end

    local language = languageRegistry.getLanguage()
    local groupCounters = {}

    for _, item in ipairs(list.children or {}) do
        local data = item.data
        local style = data and data.style

        if style and item.label then
            local styleType = utils.typeof(style)
            local text

            if styleType == "apply" then
                local key = data.parentStyle or false

                groupCounters[key] = (groupCounters[key] or 0) + 1
                text = tostring(apply.displayName(language, style, groupCounters[key]))

            elseif styleType == "parallax" then
                text = tostring(parallax.displayName(language, style))

            elseif styleType == "effect" then
                text = tostring(effects.displayName(language, style))
            end

            if text then
                -- Rows inside a group are indented, keep that when replacing the text
                if data.parentStyle then
                    text = addFolderIndent(text)
                end

                item.label.text = text
                item.label:repaint()
                item:repaint()
            end
        end
    end
end

local function getHandler(style)
    local styleType = utils.typeof(style)

    if styleType == "parallax" then
        return parallax

    elseif styleType == "effect" then
        return effects

    elseif styleType == "apply" then
        return apply
    end
end

local function getOptions(style)
    local handler = getHandler(style)
    local prepareOptions = {
        namePath = {"attribute"},
        tooltipPath = {"description"}
    }
    local dummyData, fieldInformation, fieldOrder = formUtils.prepareFormData(handler, style, prepareOptions, {style})
    local options = {
        fields = fieldInformation,
        fieldOrder = fieldOrder
    }

    -- Add cached texture options
    if utils.typeof(style) == "parallax" then
        options.fields.texture.options = parallaxTextureOptions
    end

    return options, dummyData
end

function stylegroundWindow.getStylegroundPreview(interactionData)
    local language = languageRegistry.getLanguage()
    local formData = interactionData.formData
    local listTarget = interactionData.listTarget
    local style = listTarget and listTarget.style or {}
    local styleType = utils.typeof(style)

    -- Not ready yet: still show a placeholder, otherwise the preview container has no content at
    -- all and keeps a zero size
    if not formData then
        return uiElements.label(tostring(language.ui.styleground_window.preview.no_preview))
    end

    if styleType == "parallax" then
        local sprite = atlases.getResource(formData.texture)

        if sprite then
            local imageElement = uiElements.image(sprite.image, sprite.quad, sprite.layer)

            -- The container positions and scales it: the sprite is drawn as a child element, so
            -- it follows the normal element transforms instead of raw screen coordinates
            imageElement._previewSprite = sprite
            imageElement._previewColor = formData.color
            imageElement.scaleRoundAuto = false

            return imageElement
        end

        return uiElements.label(tostring(language.ui.styleground_window.preview.unknown_texture))
    end

    return uiElements.label(formData.texture or formData._name or tostring(language.ui.styleground_window.preview.no_preview))
end

-- TODO - Improve in the future
-- We can most likely reuse a previous image or label, but this works for now
function stylegroundWindow.updateStylegroundPreview(interactionData)
    local previewContainer = interactionData.stylegroundPreviewGroup

    if not previewContainer then
        return
    end

    local newPreview = stylegroundWindow.getStylegroundPreview(interactionData)

    if previewContainer.children[1] then
        previewContainer:removeChild(previewContainer.children[1])
    end

    if newPreview then
        previewContainer:addChild(newPreview)
    end

    -- Fill the top right area with a fixed size box and scale the preview into it (aspect
    -- preserved, centered). The preview is a normal child element, so it is positioned relative to
    -- the box and follows the element transforms.
    if not previewContainer._previewHooked then
        previewContainer._previewHooked = true

        previewContainer:hook({
            layoutLate = function(orig, self, ...)
                orig(self, ...)

                local parent = self.parent

                if not parent then
                    return
                end

                local availableWidth = parent.innerWidth or 0
                local availableHeight = parent.innerHeight or 0

                if availableWidth <= 0 or availableHeight <= 0 then
                    return
                end

                local maxWidth = math.floor(math.min(availableWidth, 640))
                local maxHeight = math.max(1, math.floor(availableHeight * 0.5))

                local child = self.children and self.children[1]
                local sprite = child and child._previewSprite

                if not sprite then
                    -- Placeholder text: keep a normal sized box so the layout stays stable
                    if self.width ~= maxWidth or self.height ~= maxHeight then
                        self.width = maxWidth
                        self.height = maxHeight
                    end

                    return
                end

                -- Original (untrimmed) size and the trimmed content size
                local realWidth = sprite.realWidth or sprite.width or 0
                local realHeight = sprite.realHeight or sprite.height or 0

                local contentWidth, contentHeight

                if sprite.quad then
                    local _, _, width, height = sprite.quad:getViewport()
                    contentWidth, contentHeight = width, height

                else
                    contentWidth, contentHeight = sprite.width, sprite.height
                end

                if realWidth <= 0 or realHeight <= 0 or contentWidth <= 0 or contentHeight <= 0 then
                    return
                end

                -- Scale the original rectangle to fit, then the box is exactly that size
                local scale = math.min(maxWidth / realWidth, maxHeight / realHeight)
                scale = math.max(scale, 0.01)

                local drawWidth = math.max(1, math.floor(realWidth * scale))
                local drawHeight = math.max(1, math.floor(realHeight * scale))

                if self.width ~= drawWidth or self.height ~= drawHeight then
                    self.width = drawWidth
                    self.height = drawHeight
                end

                child.scaleX = scale
                child.scaleY = scale

                -- Place the trimmed content inside the original rectangle. The atlas stores the
                -- trim as "position minus offset", so the draw offset is minus the stored value.
                -- Without offset information the trim is assumed to be symmetric.
                local offsetX = sprite.offsetX or 0
                local offsetY = sprite.offsetY or 0

                local childX
                if offsetX ~= 0 then
                    childX = -offsetX * scale

                else
                    childX = (realWidth - contentWidth) / 2 * scale
                end

                local childY
                if offsetY ~= 0 then
                    childY = -offsetY * scale

                else
                    childY = (realHeight - contentHeight) / 2 * scale
                end

                child.x = math.floor(childX)
                child.y = math.floor(childY)

                -- Also set the real position: the element layout may not run again before the
                -- next draw
                child.realX = child.x
                child.realY = child.y

                local color = child._previewColor

                if color then
                    local success, r, g, b, a = utils.parseHexColor(color)

                    if success then
                        child.style.color = {r, g, b, a}
                    end
                end
            end,

            draw = function(orig, self, ...)
                orig(self, ...)

                -- Frame around the preview box, so its bounds are visible
                local previousR, previousG, previousB, previousA = love.graphics.getColor()
                local previousLineWidth = love.graphics.getLineWidth()

                love.graphics.setLineWidth(1)
                love.graphics.setColor(1, 1, 1, 0.3)
                love.graphics.rectangle("line", (self.screenX or 0) + 0.5, (self.screenY or 0) + 0.5,
                    math.max(0, (self.width or 0) - 1), math.max(0, (self.height or 0) - 1))

                love.graphics.setLineWidth(previousLineWidth)
                love.graphics.setColor(previousR, previousG, previousB, previousA)
            end
        })
    end

    -- The container starts out empty: reflow so it picks up the size of the new content
    previewContainer:reflow()
end

local function prepareFormData(interactionData)
    local listTarget = interactionData.listTarget
    local formData = {}

    if not listTarget then
        return formData
    end

    local style = listTarget.style or {}
    local parentStyle = listTarget.parentStyle or {}

    -- Copy in parent style, clear name and type
    for k, v in pairs(parentStyle) do
        formData[k] = v
    end

    formData.__name = nil
    formData._type = nil

    -- Copy style
    for k, v in pairs(style) do
        formData[k] = v
    end

    -- Filter out apply children
    if type(formData.children) == "table" then
        formData.children = nil
    end

    -- Add any missing default values
    local handler = getHandler(style)
    local defaultData = handler.defaultData(style) or {}

    for k, v in pairs(defaultData) do
        if formData[k] == nil then
            formData[k] = v
        end
    end

    return formData
end

local function applyFormChanges(style, newData)
    -- TODO - Handle parent better, ignore for now

    for k, v in pairs(newData) do
        style[k] = v
    end
end

-- Returns values as follows:
-- First is fg/bg styles table from the map
-- Second is the actual parent of the style (styles table or an apply)
-- Third is the index in that parent
-- Fourth is the parent style, if it exists
-- Fifth is the index the target would have in the visual list
local function findStyleInStylegrounds(interactionData, target)
    local listIndex = 0
    local listTarget = interactionData.listTarget
    local style = target

    if not listTarget then
        return
    end

    style = style or interactionData.listTarget.style

    local map = interactionData.map
    local foreground = interactionData.listTarget.foreground
    local styles = foreground and map.stylesFg or map.stylesBg

    for i, s in ipairs(styles) do
        listIndex += 1

        if style == s then
            return styles, styles, i, nil, listIndex
        end

        local styleType = utils.typeof(s)

        if styleType == "apply" then
            for j, c in ipairs(s.children or {}) do
                if not style._collapsed then
                    listIndex += 1
                end

                if style == c then
                    return styles, s.children, j, s, listIndex
                end
            end
        end
    end

    return styles, styles, 1, nil, 1
end

local function findListIndex(interactionData, targetStyle)
    local _, _, _, _, listIndex = findStyleInStylegrounds(interactionData, targetStyle)

    return listIndex
end

local function findListItem(interactionData, targetStyle)
    local listElement = interactionData.stylegroundListElement

    for i, item in ipairs(listElement.children) do
        if item.data.style == targetStyle then
            return item, i
        end
    end
end

local function findCurrentListItem(interactionData)
    local listTarget = interactionData.listTarget

    return findListItem(interactionData, listTarget.style)
end

local function moveIndex(t, before, after)
    local value = table.remove(t, before)

    table.insert(t, after, value)
end

local function canMoveStyle(interactionData, offset)
    local listTarget = interactionData.listTarget

    if not listTarget or listTarget.defaultTarget then
        return false
    end

    local _, parent, index = findStyleInStylegrounds(interactionData)

    if parent and index then
        local newIndex = index + offset

        return index ~= newIndex and newIndex >= 1 and newIndex <= #parent
    end

    return false
end

local function updateMovementButtons(interactionData)
    -- Movement buttons were removed from the form: nothing to keep in sync
end

local function moveStyle(interactionData, offset)
    local styles, parent, index = findStyleInStylegrounds(interactionData)

    if parent and index then
        local newIndex = utils.clamp(index + offset, 1, #parent)

        if index ~= newIndex then
            local listElement = interactionData.stylegroundListElement
            local _, listIndex = findCurrentListItem(interactionData)
            local movingGroup = styles == parent

            moveIndex(parent, index, newIndex)

            if movingGroup then
                local newListIndex = findListIndex(interactionData, style)

                interactionData.rebuildListItems(newListIndex)

            else
                moveIndex(listElement.children, listIndex, listIndex + offset)
            end

            listElement:reflow()

            updateMovementButtons(interactionData)
        end
    end
end

local function createApply()
    local style = applyStruct.decode({})
    local defaultData = apply.defaultData(style) or {}

    -- Used for visuals, not saved to map bin
    style._collapsed = false

    for k, v in pairs(defaultData) do
        style[k] = v
    end

    return style
end

local function createParallax()
    local style = parallaxStruct.decode({})
    local defaultData = parallax.defaultData(style) or {}

    for k, v in pairs(defaultData) do
        style[k] = v
    end

    return style
end

local function createEffect(name)
    local style = effectStruct.decode({__name = name})
    local defaultData = effects.defaultData(style) or {}

    for k, v in pairs(defaultData) do
        style[k] = v
    end

    return style
end

-- For when the list is completely empty
local function getDefaultListTarget()
    return {
        style = createParallax(),
        foreground = true,
        defaultTarget = true
    }
end

-- Restores a whole styleground state: used by the undo entries and by the auto-edit sessions
local function applyStyleState(map, state)
    map.stylesFg = utils.deepcopy(state.fg)
    map.stylesBg = utils.deepcopy(state.bg)

    -- Keep the open window in sync when the change is undone or redone
    if currentInteractionData and currentInteractionData.rebuildListItems then
        currentInteractionData.listTarget = getDefaultListTarget()

        currentInteractionData.rebuildListItems()
        stylegroundWindow.updateStylegroundForm(currentInteractionData)
        stylegroundWindow.updateStylegroundPreview(currentInteractionData)
    end
end

local function snapshotStyleState(map, before, after, title)
    history.addSnapshot(snapshotStruct.create(title or "Stylegrounds", {}, function()
        applyStyleState(map, before)
    end, function()
        applyStyleState(map, after)
    end))
end

-- Wraps a styleground edit into an undoable history entry. The returned commit function has to be
-- called once the mutation is done; it also marks the map as having unsaved changes.
local function beginStyleEdit(map)
    -- A pending auto-edit session (form changes) ends before a structural change happens
    local interactionData = currentInteractionData

    if interactionData then
        stylegroundWindow.endAutoEdit(interactionData)
    end

    local before = {
        fg = utils.deepcopy(map.stylesFg),
        bg = utils.deepcopy(map.stylesBg)
    }

    return function(title)
        local after = {
            fg = utils.deepcopy(map.stylesFg),
            bg = utils.deepcopy(map.stylesBg)
        }

        snapshotStyleState(map, before, after, title)
    end
end

-- Auto edits: form changes are applied immediately, but the undo entry is only created once the
-- user stops typing for a moment. That keeps one undo step per editing session instead of one per
-- keystroke.
local autoEditDelay = 0.5

function stylegroundWindow.beginAutoEdit(interactionData)
    local session = interactionData.autoEdit

    if session and love.timer.getTime() - session.time > autoEditDelay then
        stylegroundWindow.endAutoEdit(interactionData)
        session = nil
    end

    if not session then
        local map = interactionData.map

        interactionData.autoEdit = {
            time = love.timer.getTime(),
            before = {
                fg = utils.deepcopy(map.stylesFg),
                bg = utils.deepcopy(map.stylesBg)
            }
        }

    else
        session.time = love.timer.getTime()
    end
end

function stylegroundWindow.endAutoEdit(interactionData)
    local session = interactionData and interactionData.autoEdit

    if not session then
        return
    end

    interactionData.autoEdit = nil

    local map = interactionData.map
    local after = {
        fg = utils.deepcopy(map.stylesFg),
        bg = utils.deepcopy(map.stylesBg)
    }

    snapshotStyleState(map, session.before, after, "Edit styleground")
end

local function changeStyleForeground(interactionData)
    local listTarget = interactionData.listTarget
    local currentListElement = interactionData.stylegroundListElement
    local otherListElement = interactionData.stylegroundListElementOther

    local foreground = listTarget.foreground

    local movedStyle = listTarget.style
    local map = interactionData.map

    -- Update map style data
    local commit = beginStyleEdit(map)
    local fromStyles = foreground and map.stylesFg or map.stylesBg
    local toStyles = foreground and map.stylesBg or map.stylesFg

    for i, s in ipairs(fromStyles) do
        if movedStyle == s then
            table.remove(fromStyles, i)
            table.insert(toStyles, movedStyle)

            break
        end
    end

    commit("Move styleground")

    interactionData.rebuildListItems(nil, otherListElement)
    interactionData.rebuildListItems(nil, currentListElement)
end

local function addNewStyle(interactionData, formFields)
    local listTarget = interactionData.listTarget

    local newStyle
    local currentStyle = listTarget.style
    local parentStyle = listTarget.parentStyle

    local listElement = interactionData.stylegroundListElement
    local foreground = listElement == interactionData.stylegroundListElementFg
    local map = interactionData.map
    local method = interactionData.addNewMethod.method
    local commit = beginStyleEdit(map)

    if method == "basedOnCurrent" then
        if currentStyle then
            newStyle = utils.deepcopy(currentStyle)

            applyFormChanges(newStyle, form.getFormData(formFields))
        end

    elseif method == "group" then
        newStyle = createApply()

    elseif method == "parallax" then
        newStyle = createParallax()

    elseif method == "effect" then
        local effectName = interactionData.addNewMethod.name

        newStyle = createEffect(effectName)
    end

    if newStyle then
        local _, parentTable, index = findStyleInStylegrounds(interactionData)
        local _, listIndex = findCurrentListItem(interactionData)
        local targetGroup
        local newIsApply = utils.typeof(newStyle) == "apply"
        local currentIsApply = utils.typeof(currentStyle) == "apply"
        local parentIsApply = utils.typeof(parentStyle) == "apply"

        if currentIsApply then
            targetGroup = currentStyle

            -- We are adding as first element of the group
            index = 0

        elseif parentIsApply then
            targetGroup = parentStyle
        end

        local addToGroup = targetGroup and not newIsApply

        -- If we add a apply it should be added after the current group
        if newIsApply and targetGroup then
            parentTable = foreground and map.stylesFg or map.stylesBg
            _, _, index, _, listIndex = findStyleInStylegrounds(interactionData, targetGroup)
            listIndex += #targetGroup.children
        end

        -- Fallback if we don't have any items in the list yet
        if #listElement.children == 0 then
            addToGroup = false
            parentTable = foreground and map.stylesFg or map.stylesBg
            listIndex = 0
            index = 0
        end

        if addToGroup then
            if not targetGroup.children then
                targetGroup.children = {}
            end

            table.insert(targetGroup.children, index + 1, newStyle)

        else
            table.insert(parentTable, index + 1, newStyle)
        end

        -- Update list index after adding group
        if newIsApply and parentIsApply then
            listIndex = findListIndex(interactionData, newStyle) - 1
        end

        commit("Add styleground")
        interactionData.rebuildListItems(listIndex + 1)
    end

    return not not newStyle
end

-- Selects and focuses a style in the active list. Deferred on purpose: list:updateItems()
-- restores the previous selection in a ui.runLate callback, which would overwrite an immediate
-- selection change.
local function selectStyleDeferred(interactionData, style, list)
    list = list or (interactionData and interactionData.stylegroundListElement)

    if not list or not style then
        return
    end

    ui.runLate(function()
        for index, item in ipairs(list.children or {}) do
            if item.data and item.data.style == style then
                list:setSelection(index)

                widgetUtils.focusElement(item)
                listWidgets.scrollSelectionVisible(list)

                return
            end
        end
    end)
end

local function removeStyle(interactionData)
    local list = interactionData.stylegroundListElement
    local startIndex = list and list:getSelectedIndex() or 1
    local targets = interactionData.selectedTargets or {}

    -- Multiple rows selected: remove every one of them in a single undo step
    if #targets > 1 then
        local commit = beginStyleEdit(interactionData.map)

        for _, target in ipairs(targets) do
            local fake = table.shallowcopy(interactionData)
            fake.listTarget = target

            local _, parent, index = findStyleInStylegrounds(fake)

            if parent and index then
                table.remove(parent, index)
            end
        end

        commit("Remove stylegrounds")

        interactionData.listTarget = getDefaultListTarget()
        interactionData.selectedTargets = {}

        local newItems = interactionData.rebuildListItems()

        if #newItems > 0 then
            -- Select the layer above the deleted one
            local selectIndex = math.max(math.min(startIndex - 1, #newItems), 1)
            local item = newItems[selectIndex]

            selectStyleDeferred(interactionData, item and item.data and item.data.style)

        else
            stylegroundWindow.updateStylegroundForm(interactionData)
            stylegroundWindow.updateStylegroundPreview(interactionData)
        end

        return
    end

    local _, parent, index = findStyleInStylegrounds(interactionData)

    if parent and index then
        local _, listIndex = findCurrentListItem(interactionData)
        local commit = beginStyleEdit(interactionData.map)

        table.remove(parent, index)

        commit("Remove styleground")

        local newItems = interactionData.rebuildListItems(listIndex or 1)

        if #newItems > 0 then
            -- Select the layer above the deleted one, or the first one when it was the top layer
            local selectIndex = math.max(math.min((listIndex or 1) - 1, #newItems), 1)
            local item = newItems[selectIndex]

            selectStyleDeferred(interactionData, item and item.data and item.data.style)

            return
        end

        interactionData.listTarget = getDefaultListTarget()

        stylegroundWindow.updateStylegroundForm(interactionData)
        stylegroundWindow.updateStylegroundPreview(interactionData)
    end
end

local function updateStyle(interactionData, style, newData)
    local commit = beginStyleEdit(interactionData.map)
    local targets = interactionData.selectedTargets or {}

    if #targets > 1 then
        -- Multiple rows selected: apply the form to every one of them
        for _, target in ipairs(targets) do
            applyFormChanges(target.style, newData)
        end

    else
        applyFormChanges(style, newData)
    end

    commit("Edit styleground")
    interactionData.rebuildListItems()
end

local function findBestGroupParent(interactionData)
    local listTarget = interactionData.listTarget
    local currentStyle = listTarget.style
    local closestGroup
    local seenCurrent = false

    local styles = findStyleInStylegrounds(interactionData)

    -- Try to find the closest group, prefer inserting into group above
    for _, style in ipairs(styles) do
        if style == currentStyle then
            seenCurrent = true

            if closestGroup then
                return closestGroup
            end
        end

        if utils.typeof(style) == "apply" then
            closestGroup = style

            if seenCurrent then
                return style
            end
        end
    end
end

local function addStyleToGroup(interactionData)
    local listTarget = interactionData.listTarget
    local currentStyle = listTarget.style
    local parentGroup = findBestGroupParent(interactionData)
    local styles, _, index = findStyleInStylegrounds(interactionData)
    local commit = beginStyleEdit(interactionData.map)

    -- If no groups exist create one and insert it there instead
    if not parentGroup then
        parentGroup = createApply()

        table.insert(styles, index + 1, parentGroup)
    end

    table.insert(parentGroup.children, currentStyle)
    table.remove(styles, index)

    commit("Move styleground into group")
    interactionData.rebuildListItems()
end

-- Creates a new, empty group at the current position. Unlike "add to group" this does not move
-- the selected style anywhere.
local function createEmptyGroup(interactionData)
    local styles = findStyleInStylegrounds(interactionData)

    if not styles then
        return
    end

    local _, _, index = findStyleInStylegrounds(interactionData)
    local group = createApply()
    local commit = beginStyleEdit(interactionData.map)

    -- An empty list has no valid index to insert after: clamp so insertion stays in bounds
    local insertIndex = math.min(index or #styles, #styles) + 1

    table.insert(styles, insertIndex, group)

    commit("Create styleground group")
    interactionData.rebuildListItems()
end

local function removeStyleFromGroup(interactionData)
    local listTarget = interactionData.listTarget
    local style = listTarget.style
    local parentStyle = listTarget.parentStyle
    local styles, _, index = findStyleInStylegrounds(interactionData)
    local _, _, parentIndex = findStyleInStylegrounds(interactionData, parentStyle)

    if parentStyle and parentStyle.children and styles and parentIndex then
        local commit = beginStyleEdit(interactionData.map)

        table.remove(parentStyle.children, index)
        table.insert(styles, parentIndex + 1, style)

        commit("Move styleground out of group")
        interactionData.rebuildListItems()
    end
end

local function getNewDropdownOptions(style, foreground, usingDefault, showIncorrect)
    local language = languageRegistry.getLanguage()
    local knownEffects = effects.registeredEffects
    local options = {}

    if style and not usingDefault then
        table.insert(options, {
            text = tostring(language.ui.styleground_window.new_options.based_on_current),
            data = {
                method = "basedOnCurrent"
            }
        })
    end

    table.insert(options, {
        text = tostring(language.ui.styleground_window.new_options.parallax),
        data = {
            method = "parallax"
        }
    })

    table.insert(options, {
        text = tostring(language.ui.styleground_window.new_options.apply),
        data = {
            method = "group"
        }
    })

    -- Find all effects and add them in sorted order (by display name)
    local effectOptions = {}

    for name, _ in pairs(knownEffects) do
        local fakeEffect = {_name = name}
        local displayName = effects.displayName(language, fakeEffect)
        local canForeground = effects.canForeground(fakeEffect)
        local canBackground = effects.canBackground(fakeEffect)
        local correctForegroundValue = foreground and canForeground or not foreground and canBackground

        local option = {
            text = displayName,
            data = {
                method = "effect",
                name = name,
                correctForegroundValue = correctForegroundValue
            }
        }

        -- Remove invalid options that does not match current foreground/background
        if showIncorrect or correctForegroundValue then
            table.insert(effectOptions, option)
        end
    end

    effectOptions = table.sortby(effectOptions, function(option)
        return option.text
    end)()

    for _, option in ipairs(effectOptions) do
        table.insert(options, option)
    end

    return options
end

local function notifyRemoveStyle(language, interactionData)
    notifications.notify(
        function(popup)
            return uiElements.column({
                uiElements.label(tostring(language.ui.stylegrounds_window.delete_style_warning)),
                uiElements.row({
                    uiElements.button(tostring(language.ui.button.yes), function()
                        removeStyle(interactionData)
                        popup:close()
                    end),
                    uiElements.button(tostring(language.ui.button.no), function()
                        popup:close()
                    end),
                })
            })
        end,
        -1,
        {clearSameTag = true, tag = "stylegroundDelete"}
    )
end

local function getStylegroundFormButtons(interactionData, formFields, formOptions)
    local listTarget = interactionData.listTarget or {}
    local listHasElements = false

    if interactionData.stylegroundListElement then
        listHasElements = #interactionData.stylegroundListElement.children > 0
    end

    local language = languageRegistry.getLanguage()
    local style = listTarget.style
    local foreground = interactionData.stylegroundListElement == interactionData.stylegroundListElementFg
    local isDefaultTarget = listTarget.defaultTarget
    local inGroup = not not listTarget.parentStyle
    local isGroup = utils.typeof(style) == "apply"

    local handler = getHandler(style)

    local canForeground = handler and handler.canForeground(style)
    local canBackground = handler and handler.canBackground(style)
    local canChangeForeground = canForeground and canBackground and not inGroup

    local moveToForegroundText = tostring(language.ui.styleground_window.form.move_to_foreground)
    local moveToBackgroundText = tostring(language.ui.styleground_window.form.move_to_background)

    local movementButtonElements = {}

    local changeForegroundButton = {
        text = foreground and moveToBackgroundText or moveToForegroundText,
        callback = function()
            changeStyleForeground(interactionData)
        end
    }
    local addToGroupButton = {
        text = tostring(language.ui.styleground_window.form.create_group or "Create Group"),
        callback = function()
            createEmptyGroup(interactionData)
        end
    }
    local removeFromGroupButton = {
        text = tostring(language.ui.styleground_window.form.remove_from_group),
        callback = function()
            removeStyleFromGroup(interactionData)
        end
    }

    interactionData.movementButtonElements = movementButtonElements

    local buttons = {
        {
            text = tostring(language.ui.styleground_window.form.remove),
            enabled = listHasElements,
            callback = function()
                -- Delete right away: the removal is undoable, so no confirmation is needed
                removeStyle(interactionData)
            end
        },
    }

    if canChangeForeground and listHasElements then
        table.insert(buttons, changeForegroundButton)
    end

    if not isGroup then
        if inGroup then
            table.insert(buttons, removeFromGroupButton)

        else
            table.insert(buttons, addToGroupButton)
        end
    end

    local buttonRow = formHelper.getFormButtonRow(buttons, formFields, formOptions)

    -- The "New" dropdown is gone: the right side of the tools window lists what can be added.
    -- "New" therefore creates a plain parallax style, groups come from the Create Group button.
    interactionData.addNewMethod = {method = "parallax"}

    return buttonRow
end

function stylegroundWindow.getStylegroundForm(interactionData)
    local formData = prepareFormData(interactionData)
    local formOptions, dummyData = getOptions(formData)

    -- TODO - Add to config file?
    -- 3 field pairs per row: each pair uses two grid columns (label and input)
    formOptions.columns = 6
    -- Tighter spacing: the label column already includes its own padding
    formOptions.gridColumnSpacing = 8
    formOptions.gridRowSpacing = 4
    -- Keep every label directly next to its input: the settings labels got long, which pushed
    -- short labels far away from their inputs in the shared grid columns
    formOptions.pairFieldElements = true

    -- With more than one row selected only the fields every selection has in common are shown;
    -- "Update" then applies the form to all of them
    local selectedTargets = interactionData.selectedTargets or {}

    if #selectedTargets > 1 then
        local commonFields = {}

        for _, key in ipairs(formOptions.fieldOrder) do
            local common = true

            for i = 2, #selectedTargets do
                local otherData = prepareFormData({listTarget = selectedTargets[i]})

                if otherData[key] == nil then
                    common = false

                    break
                end
            end

            if common then
                table.insert(commonFields, key)
            end
        end

        formOptions.fieldOrder = commonFields
        -- Fields that are not in the field order come from the first selection only, so they must
        -- not be offered for a multi selection
        formOptions.hideUnordered = true
    end
    formOptions.formFieldChanged = function(formFields, changedField)
        local newData = form.getFormData(formFields)

        interactionData.formData = newData

        -- Auto update: only the field the user actually changed is applied to the selected styles.
        -- Applying the whole form would overwrite every other property of the other selections.
        local targets = interactionData.selectedTargets or {}

        if changedField and changedField.name and #targets > 0 then
            stylegroundWindow.beginAutoEdit(interactionData)

            local parts = form.getNameParts(changedField.name, formOptions)
            local value = utils.getPath(newData, parts)

            for _, target in ipairs(targets) do
                utils.setPath(target.style, parts, utils.deepcopy(value), true)
            end

            history.madeChanges = true

            -- Refresh the row texts: display names depend on fields like the texture or the group
            -- name
            updateListRowTexts(interactionData)
        end

        stylegroundWindow.updateStylegroundPreview(interactionData)
    end

    local formBody, formFields = formHelper.getFormBody(dummyData, formOptions)
    local buttonRow = getStylegroundFormButtons(interactionData, formFields, formOptions)

    -- Finish all fade effects
    for _, field in ipairs(formFields) do
        for _, element in ipairs(field.elements) do
            widgetUtils.finishElementFade(element)
        end
    end

    for _, button in ipairs(buttonRow.children) do
        widgetUtils.finishElementFade(button)
    end

    return uiElements.column({formBody, buttonRow})
end

function stylegroundWindow.updateStylegroundForm(interactionData)
    local formContainer = interactionData.formContainerGroup
    local newForm = stylegroundWindow.getStylegroundForm(interactionData)
    local children = formContainer.children or {}

    while #children > 0 do
        children[1]:removeSelf()
    end

    formContainer:addChild(newForm)
end

-- Check if movement is allowed and return prepared offset and interactionData
local function listItemDragAllowed(interactionData, fromList, fromListItem, _, _, fromIndex, toIndex)
    local offset = toIndex - fromIndex

    if toIndex > fromIndex then
        offset -= 1
    end

    if offset ~= 0 then
        local fakeInteractionData = table.shallowcopy(interactionData)

        fakeInteractionData.listTarget = fromListItem.data
        fakeInteractionData.stylegroundListElement = fromList

        return canMoveStyle(fakeInteractionData, offset), offset, fakeInteractionData
    end

    return false, offset, nil
end

-- True when the drag crosses a group boundary, which is a structural move instead of a reorder
local function isCrossParentDrag(fromListItem, toListItem)
    local from = fromListItem and fromListItem.data
    local to = toListItem and toListItem.data

    return from ~= nil and to ~= nil and from.style ~= nil and to.style ~= nil
        and from.parentStyle ~= to.parentStyle
end

-- Resolves the group a drop belongs to. Dropping on the upper half of a group row targets that
-- row, dropping on its lower half inserts right after the row, so the row above the insertion
-- index has to be checked as well.
local function getGroupDropData(toList, toListItem, toIndex, fromListItem)
    local toData = toListItem and toListItem.data

    if toData and toData.style and utils.typeof(toData.style) == "apply" then
        return toData
    end

    local children = toList and toList.children

    if children and toIndex then
        local previous = children[toIndex - 1]

        if previous and previous ~= fromListItem and previous.data
            and previous.data.style and utils.typeof(previous.data.style) == "apply" then
            return previous.data
        end
    end
end

-- Moves a style into or out of a group. Returns true when the drag was a structural move.
local function moveStyleBetweenParents(interactionData, fromData, toData)
    local map = interactionData.map
    local fromStyle = fromData.style
    local toStyle = toData.style

    if not fromStyle or not toStyle or fromStyle == toStyle then
        return false
    end

    -- A group cannot be moved into another group
    if utils.typeof(fromStyle) == "apply" and toData.parentStyle then
        return false
    end

    local fake = table.shallowcopy(interactionData)
    fake.listTarget = fromData

    local _, sourceParent, sourceIndex = findStyleInStylegrounds(fake)

    if not sourceParent or not sourceIndex then
        return false
    end

    local targetParent

    if toData.parentStyle then
        targetParent = toData.parentStyle.children

    else
        targetParent = toData.foreground and map.stylesFg or map.stylesBg
    end

    if not targetParent or targetParent == sourceParent then
        return false
    end

    local commit = beginStyleEdit(map)

    table.remove(sourceParent, sourceIndex)

    -- Recompute the target index: removing the dragged item can shift it
    local targetIndex

    for i, s in ipairs(targetParent) do
        if s == toStyle then
            targetIndex = i

            break
        end
    end

    if not targetIndex then
        commit("Move styleground")

        return false
    end

    table.insert(targetParent, targetIndex, fromStyle)

    commit("Move styleground between groups")
    interactionData.rebuildListItems()

    return true
end

-- Drops a style onto a group row: it becomes a child of that group
local function moveStyleIntoGroup(interactionData, fromData, group)
    if not group or utils.typeof(fromData.style) == "apply" then
        return false
    end

    local map = interactionData.map
    local fake = table.shallowcopy(interactionData)
    fake.listTarget = fromData

    local _, sourceParent, sourceIndex = findStyleInStylegrounds(fake)

    if not sourceParent or not sourceIndex then
        return false
    end

    if group.children and sourceParent == group.children then
        return false
    end

    local commit = beginStyleEdit(map)

    table.remove(sourceParent, sourceIndex)

    group.children = group.children or {}
    table.insert(group.children, fromData.style)

    -- Expand the group so the moved style is visible right away
    group._collapsed = false

    commit("Move styleground into group")
    interactionData.rebuildListItems()

    return true
end

local function listItemDraggedHandler(interactionData)
    return function(fromList, fromListItem, toList, toListItem, fromIndex, toIndex)
        local fromData = fromListItem and fromListItem.data
        local groupData = getGroupDropData(toList, toListItem, toIndex, fromListItem)

        if groupData and fromData then
            -- Dropping onto a group row puts the style into that group (both halves of the row)
            moveStyleIntoGroup(interactionData, fromData, groupData.style)

        elseif isCrossParentDrag(fromListItem, toListItem) then
            moveStyleBetweenParents(interactionData, fromListItem.data, toListItem.data)

        else
            local allowed, offset, fakeInteraction = listItemDragAllowed(interactionData, fromList, fromListItem, toList, toListItem, fromIndex, toIndex)

            if allowed then
                moveStyle(fakeInteraction, offset)

                -- Force update movement buttons with the real data
                -- We might have moved in a way that should disable/enable some buttons
                updateMovementButtons(interactionData)
            end
        end

        -- Manually update the list
        return false
    end
end

local function listItemCanInsertHandler(interactionData)
    return function(fromList, fromListItem, toList, toListItem, fromIndex, toIndex)
        local from = fromListItem and fromListItem.data
        local groupData = getGroupDropData(toList, toListItem, toIndex, fromListItem)

        -- Dropping onto a group row moves the style into that group, which is not a plain
        -- reorder and has to be accepted here as well. The insert line would be misleading, so it
        -- is hidden for this case.
        if from and groupData and from.style ~= groupData.style
            and utils.typeof(from.style) ~= "apply" then
            return true, true
        end

        -- Dropping into or out of a group is allowed even though it is not a plain reorder
        if isCrossParentDrag(fromListItem, toListItem) then
            return true
        end

        -- Only the first return value is the "allowed" flag: the helper also returns the offset
        -- and a fake interaction data, which must not end up as the hide-insert-line flag
        local allowed = listItemDragAllowed(interactionData, fromList, fromListItem, toList, toListItem, fromIndex, toIndex)

        return allowed
    end
end

local function listItemDoubleClickedHandler(interactionData)
    return function(_, button)
        if button ~= 1 then
            return
        end

        local listTarget = interactionData.listTarget
        local style = listTarget.style
        local isGroup = utils.typeof(style) == "apply"

        if isGroup then
            style._collapsed = not style._collapsed

            interactionData.rebuildListItems()
        end
    end
end

function stylegroundWindow.getStylegroundListItems(map, fg)
    local styles = fg and map.stylesFg or map.stylesBg

    return getStylegroundItems(styles or {}, {}, fg)
end

-- The styles selected in a list: either the multi selection or the single list selection
local function getSelectedTargets(interactionData, list)
    local targets = {}

    for _, item in ipairs(list.children or {}) do
        if item.data and list:getIsSelected(item) then
            table.insert(targets, item.data)
        end
    end

    if #targets == 0 and list.selected and list.selected.data then
        table.insert(targets, list.selected.data)
    end

    return targets
end

local function getItemRange(list, fromItem, toItem)
    local fromIndex, toIndex

    for i, item in ipairs(list.children or {}) do
        if item == fromItem then
            fromIndex = i
        end

        if item == toItem then
            toIndex = i
        end
    end

    if not fromIndex or not toIndex then
        return nil
    end

    if fromIndex > toIndex then
        fromIndex, toIndex = toIndex, fromIndex
    end

    return fromIndex, toIndex
end

local function ctrlHeld()
    return love.keyboard.isDown("lctrl", "rctrl")
end

local function shiftHeld()
    return love.keyboard.isDown("lshift", "rshift")
end

-- True while a text input owns the keyboard. Clipboard and delete keys must not reach the list
-- in that case: Ctrl+X inside a form field has to edit the text, not cut a styleground.
local function textInputFocused()
    local focusing = ui.focusing

    while focusing do
        if focusing.getCursorIndex or focusing.setCursorIndex or focusing.__type == "field" then
            return true
        end

        focusing = focusing.parent
    end

    return false
end

function stylegroundWindow.getStylegroundList(map, interactionData, fg)
    local items = stylegroundWindow.getStylegroundListItems(map, fg)

    local listOptions = {
        initialItem = 1,
        draggable = true,
        listItemDragged = listItemDraggedHandler(interactionData),
        listItemCanInsert = listItemCanInsertHandler(interactionData),
        listItemDoubleClicked = listItemDoubleClickedHandler(interactionData),
    }

    local column, list = listWidgets.getList(function(element, listItem)
        -- Selecting something else ends a pending form edit session (one undo step per session)
        stylegroundWindow.endAutoEdit(interactionData)

        interactionData.listTarget = listItem
        interactionData.selectedTargets = getSelectedTargets(interactionData, element)
        interactionData.formData = prepareFormData(interactionData)

        stylegroundWindow.updateStylegroundForm(interactionData)
        stylegroundWindow.updateStylegroundPreview(interactionData)
    end, items, listOptions)

    list:layout()

    -- Multi selection, like a file list: shift extends a range, ctrl toggles single rows. The
    -- selection is kept by style, so it survives the list being rebuilt.
    local selectionStyles = {}
    local anchorStyle

    local function clearSelection()
        for k in pairs(selectionStyles) do
            selectionStyles[k] = nil
        end

        anchorStyle = nil
    end

    list.getIsSelected = function(self, item)
        local style = item.data and item.data.style

        if style and next(selectionStyles) then
            return selectionStyles[style] == true
        end

        return self.selected == item
    end

    list.setIsSelected = function(self, item, value)
        local style = item.data and item.data.style

        if not value or not style then
            clearSelection()
            self.selected = false

            return
        end

        if ctrlHeld() then
            if selectionStyles[style] then
                selectionStyles[style] = nil
                anchorStyle = nil

                -- Keep the plain selection in sync, otherwise the item would look selected again
                -- through the single selection fallback once nothing is left in the multi set
                self.selected = next(selectionStyles) and item or false

            else
                selectionStyles[style] = true
                anchorStyle = style
                self.selected = item
            end

            return
        end

        if shiftHeld() and anchorStyle then
            local anchorItem

            for _, c in ipairs(self.children or {}) do
                if c.data and c.data.style == anchorStyle then
                    anchorItem = c

                    break
                end
            end

            if anchorItem and anchorItem.parent == item.parent then
                local fromIndex, toIndex = getItemRange(self, anchorItem, item)

                if fromIndex then
                    clearSelection()
                    anchorStyle = style

                    for i = fromIndex, toIndex do
                        local other = self.children[i]

                        if other and other.data and other.data.style then
                            selectionStyles[other.data.style] = true
                        end
                    end

                    self.selected = item

                    return
                end
            end
        end

        clearSelection()

        selectionStyles[style] = true
        anchorStyle = style
        self.selected = item
    end

    return column, list, items
end

-- The window is a singleton while the stylegrounds tool is active
local currentWindow
local currentInteractionData
local addingStyle = false

-- Which list a new style goes to: the one currently shown in the window, foreground by default
local function getActiveForeground(interactionData)
    local activeList = interactionData and interactionData.stylegroundListElement

    if not activeList then
        return true
    end

    return activeList == interactionData.stylegroundListElementFg
end

-- Adds one style to the foreground or background list of the map and refreshes an open window
function stylegroundWindow.addStyle(name, foreground)
    local map = (currentInteractionData and currentInteractionData.map) or loadedState.map

    if not map or not name or addingStyle then
        return false
    end

    addingStyle = true

    if foreground == nil then
        foreground = getActiveForeground(currentInteractionData)
    end

    local styles = foreground and map.stylesFg or map.stylesBg
    local style = parallaxStruct.decode({})

    style.texture = name

    table.insert(styles, style)

    if currentInteractionData and currentInteractionData.rebuildListItems then
        currentInteractionData.rebuildListItems(nil, currentInteractionData.stylegroundListElement)
    end

    addingStyle = false

    return true
end

function stylegroundWindow.isOpen()
    return currentWindow ~= nil and currentWindow.parent ~= nil
end

function stylegroundWindow.closeForTool()
    if currentWindow and currentWindow.parent then
        currentWindow.parent:removeChild(currentWindow)
    end

    currentWindow = nil
    currentInteractionData = nil
end

-- Adds one style of a given kind to the foreground or background list: "parallax" (empty
-- texture), "group" or "effect" with the effect name
function stylegroundWindow.addStyleOfType(kind, effectName, foreground)
    -- Prefer the map the open window works on: after a reload loadedState.map may be a new object
    local map = (currentInteractionData and currentInteractionData.map) or loadedState.map

    if not map or addingStyle then
        return false
    end

    addingStyle = true

    if foreground == nil then
        foreground = getActiveForeground(currentInteractionData)
    end

    local styles = foreground and map.stylesFg or map.stylesBg
    local style

    if kind == "group" then
        style = createApply()

    elseif kind == "effect" and effectName then
        style = createEffect(effectName)

    else
        style = parallaxStruct.decode({})
        -- New parallax layers start with a valid texture, so the preview and the row name work
        -- right away instead of showing "Parallax - nil"
        style.texture = "bgs/00/bg0"
    end

    table.insert(styles, style)

    history.addSnapshot(snapshotStruct.create("Add styleground", {}, function()
        for i, s in ipairs(styles) do
            if s == style then
                table.remove(styles, i)

                break
            end
        end

        if currentInteractionData and currentInteractionData.rebuildListItems then
            currentInteractionData.rebuildListItems(nil, currentInteractionData.stylegroundListElement)
        end
    end, function()
        table.insert(styles, style)

        if currentInteractionData and currentInteractionData.rebuildListItems then
            currentInteractionData.rebuildListItems(nil, currentInteractionData.stylegroundListElement)
        end
    end))

    if currentInteractionData and currentInteractionData.rebuildListItems then
        local list = currentInteractionData.stylegroundListElement

        currentInteractionData.rebuildListItems(nil, list)
        selectStyleDeferred(currentInteractionData, style, list)
    end

    addingStyle = false

    return true
end

-- Same list the texture dropdown of the window uses, so the tools window can show the very same
-- backgrounds as buttons
function stylegroundWindow.getParallaxOptions()
    if parallaxTextureOptions then
        return parallaxTextureOptions
    end

    local names = parallax.getParallaxNames() or {}

    table.sort(names)

    return names
end

-- Styles copied with Ctrl+C. Only kept while a window is open, like the room clipboard.
local stylegroundClipboard

function stylegroundWindow.copySelection(interactionData)
    local targets = interactionData.selectedTargets or {}

    if #targets == 0 then
        return
    end

    stylegroundClipboard = {
        foreground = targets[1].foreground,
        styles = {}
    }

    for _, target in ipairs(targets) do
        table.insert(stylegroundClipboard.styles, utils.deepcopy(target.style))
    end
end

function stylegroundWindow.cutSelection(interactionData)
    stylegroundWindow.copySelection(interactionData)
    removeStyle(interactionData)
end

function stylegroundWindow.pasteSelection(interactionData)
    if not stylegroundClipboard or #stylegroundClipboard.styles == 0 then
        return
    end

    local map = interactionData.map

    -- Paste into the list that is currently shown, not into the side the styles were copied from
    local activeList = interactionData.stylegroundListElement
    local foreground = not activeList or activeList == interactionData.stylegroundListElementFg
    local styles = foreground and map.stylesFg or map.stylesBg
    local targets = interactionData.selectedTargets or {}

    -- Only the actual selection may act as the anchor. listTarget can be stale (for example after
    -- the list was rebuilt), which would insert the pasted styles somewhere in the middle.
    local anchor = targets[#targets]

    if anchor and anchor.foreground ~= foreground then
        anchor = nil
    end

    local parent = styles
    local index = #styles

    if anchor and anchor.parentStyle and anchor.parentStyle.children then
        parent = anchor.parentStyle.children
        index = #parent
    end

    if anchor then
        local found = false

        for i, s in ipairs(parent) do
            if s == anchor.style then
                index = i
                found = true

                break
            end
        end

        -- Anchor is not part of this list any more: append at the end
        if not found then
            index = #parent
        end
    end

    local commit = beginStyleEdit(map)

    for _, style in ipairs(stylegroundClipboard.styles) do
        table.insert(parent, index + 1, utils.deepcopy(style))
        index = index + 1
    end

    commit("Paste stylegrounds")

    if interactionData.rebuildListItems then
        local list = interactionData.stylegroundListElement

        interactionData.rebuildListItems(nil, list)
    end
end

function stylegroundWindow.getWindowContent(map)
    local interactionData = {}
    local language = languageRegistry.getLanguage()

    -- See TODO at top of file
    --cacheParallaxTextureOptions()

    interactionData.map = map

    -- Kept around so the tool can refresh the list when a style is added from the tools window
    currentInteractionData = interactionData
    interactionData.listTarget = getDefaultListTarget()
    interactionData.selectedTargets = {}

    local stylegroundFormGroup = uiElements.group({}):with(uiUtils.bottombound)
    -- Filled by updateStylegroundPreview: images are drawn by the container itself, so there is no
    -- child element to create here. Caching is disabled because a cached element draws with a
    -- translated coordinate system, which would move the sprite out of its box.
    local stylegroundPreview = uiElements.group({}):with({
        cacheable = false
    })

    local listColumnForeground, listForeground = stylegroundWindow.getStylegroundList(map, interactionData, true)
    local listColumnBackground, listBackground = stylegroundWindow.getStylegroundList(map, interactionData, false)

    listForeground.interactionData = interactionData
    listBackground.interactionData = interactionData

    interactionData.formContainerGroup = stylegroundFormGroup
    interactionData.stylegroundPreviewGroup = stylegroundPreview
    interactionData.stylegroundListElementFg = listForeground
    interactionData.stylegroundListElementBg = listBackground

    function interactionData.rebuildListItems(listTarget, list)
        if not list then
            list = interactionData.stylegroundListElement
        end

        local fg = list == interactionData.stylegroundListElementFg
        local newItems = stylegroundWindow.getStylegroundListItems(map, fg)

        -- Use current target if none specified
        if not listTarget then
            listTarget = list:getSelectedIndex()
        end

        list:updateItems(newItems, listTarget)

        return newItems
    end

    local function tabCallbackHandler(fg)
        return function()
            local currentList = fg and listForeground or listBackground
            local otherList = fg and listBackground or listForeground

            persistence.stylegroundWindowPreviousTab = fg and "foreground" or "background"
            interactionData.stylegroundListElement = currentList
            interactionData.stylegroundListElementOther = otherList

            ui.runLate(function()
                if #currentList.children > 0 then
                    widgetUtils.focusElement(currentList.children[1])
                    currentList:setSelection(currentList:getSelectedData(), false, false)

                else
                    interactionData.listTarget = getDefaultListTarget()

                    stylegroundWindow.updateStylegroundForm(interactionData)
                    stylegroundWindow.updateStylegroundPreview(interactionData)
                end
            end)
        end
    end

    local tabs = {
        {
            title = tostring(language.ui.styleground_window.tab_foreground),
            content = listColumnForeground,
            callback = tabCallbackHandler(true)
        },
        {
            title = tostring(language.ui.styleground_window.tab_background),
            content = listColumnBackground,
            callback = tabCallbackHandler(false)
        },
    }
    local initialTab = persistence.stylegroundWindowPreviousTab == "background" and 2 or 1

    -- The left column is as wide as the longest item text, or as wide as the two tab buttons when
    -- both lists are empty
    local measureLabel = uiElements.label("")
    local measureFont = measureLabel.style.font
    local listTextWidth = 0

    for _, list in ipairs({listForeground, listBackground}) do
        for _, item in ipairs(list.children or {}) do
            local text = item.label and item.label.text or ""

            if type(text) == "string" then
                listTextWidth = math.max(listTextWidth, measureFont:getWidth(text))
            end
        end
    end

    local tabsWidth = 32

    for index, tab in ipairs(tabs) do
        if index > 1 then
            tabsWidth = tabsWidth + 8
        end

        tabsWidth = tabsWidth + measureFont:getWidth(tab.title)
    end

    local tabbedWindowOptions = {
        respectSiblings = false,
        initialTab = initialTab,
        minWidth = math.ceil(math.max(listTextWidth + 40, tabsWidth))
    }
    local _, tabbedContent = tabbedWindow.createWindow("", tabs, tabbedWindowOptions)

    stylegroundWindow.updateStylegroundForm(interactionData)
    stylegroundWindow.updateStylegroundPreview(interactionData)

    -- Left: the foreground/background tabs, the tab content already fills the window height.
    -- Right: preview on top, options and buttons at the bottom.
    local rightSpacer = uiElements.new({}):with(uiUtils.fillHeight(true))

    local rightColumn = uiElements.column({
        stylegroundPreview,
        rightSpacer,
        stylegroundFormGroup
    }):with(uiUtils.fillHeight(false))

    local layout = uiElements.row({
        tabbedContent,
        rightColumn
    }):with(uiUtils.fillHeight(true))

    return layout, interactionData
end

function stylegroundWindow.editStylegrounds(map)
    if not map then
        return
    end

    -- Repeated clicks only ever open one window
    if stylegroundWindow.isOpen() then
        return currentWindow
    end

    local window
    local layout = stylegroundWindow.getWindowContent(map)

    local language = languageRegistry.getLanguage()
    local windowTitle = tostring(language.ui.styleground_window.window_title)

    -- Figure out some smart sizing things here, this is too hardcoded
    -- Still doesn't fit all the elements, good enough for now
    window = uiElements.window(windowTitle, layout):with({
        height = WINDOW_STATIC_HEIGHT
    })

    local windowCloseCallback = windowPersister.getWindowCloseCallback(windowPersisterName)

    local function onClose(w)
        -- Commit a pending form edit session so it stays undoable after the window is gone
        if currentInteractionData then
            stylegroundWindow.endAutoEdit(currentInteractionData)
        end

        currentWindow = nil
        currentInteractionData = nil

        -- The styleground clipboard lives only as long as the window
        stylegroundClipboard = nil

        -- Leaving the tool open would keep an empty list around: fall back to the selection tool
        local toolHandler = require("tools")

        if toolHandler.currentToolName == "stylegrounds" then
            toolHandler.selectTool("selection")
        end

        return windowCloseCallback(w)
    end

    -- The window group is only attached once the UI root is ready: fall back to the window group
    -- of the root, so opening the window from the tool does not depend on the load order
    local parentGroup = stylegroundWindowGroup.parent

    if not parentGroup then
        local ok, uiRoot = pcall(require, "ui.ui_root")

        parentGroup = ok and uiRoot.getWindowGroup() or nil
    end

    -- The close button is part of the titlebar, so it has to be added before the layout is forced
    widgetUtils.addWindowCloseButton(window, onClose)

    -- This window is deliberately not position-persisted: it always opens centered. Layout is
    -- forced first so the size used for centering is final.
    if parentGroup then
        parentGroup:addChild(window)

        window:layout()
        window:layoutLate()

        widgetUtils.centerWindow(window, parentGroup)
    end

    widgetUtils.preventOutOfBoundsMovement(window)
    widgetUtils.consumeKeyboardEvents(window)

    -- Install after consumeKeyboardEvents, so this hook is the outer one and sees the keys first.
    -- While a form field is focused its own handling wins: the list shortcuts are isolated.
    window:hook({
        onKeyPress = function(orig, self, key, scancode, isrepeat)
            if currentInteractionData and not textInputFocused() then
                if ctrlHeld() then
                    if key == "c" then
                        stylegroundWindow.copySelection(currentInteractionData)

                        return true

                    elseif key == "x" then
                        stylegroundWindow.cutSelection(currentInteractionData)

                        return true

                    elseif key == "v" then
                        stylegroundWindow.pasteSelection(currentInteractionData)

                        return true
                    end

                elseif key == "delete" then
                    removeStyle(currentInteractionData)

                    return true
                end
            end

            if orig then
                return orig(self, key, scancode, isrepeat)
            end

            return false
        end
    })

    currentWindow = window

    return window
end

-- Group to get access to the main group and sanely inject windows in it
function stylegroundWindow.getWindow()
    stylegroundEditor.stylegroundWindow = stylegroundWindow

    return stylegroundWindowGroup
end

return stylegroundWindow