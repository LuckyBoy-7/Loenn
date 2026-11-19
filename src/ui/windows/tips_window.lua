-- Small utility window opened from Help > Pick Random Tips. Picks a random tip from the same
-- table used by the loading screen.

local ui = require("ui")
local uiElements = require("ui.elements")
local uiRoot = require("ui.ui_root")
local widgetUtils = require("ui.widgets.utils")
local windowPersister = require("ui.window_position_persister")
local languageRegistry = require("language_registry")
local tipsData = require("assets.loading.tips")
local tipsWindowWrapper = require("ui.tips_window_wrapper")
local fonts = require("fonts")

local tipsWindow = {}

local tipsWindowGroup = uiElements.group({})
local window
local tipLabel
local lastTipIndex

local windowName = "tips_window"
local textWidth = 420

local function getText(key)
    local language = languageRegistry.getLanguage()

    return tostring(language.ui.tips_window[key])
end

local function pickTip()
    local tips = tipsData.tips or {}

    if #tips == 0 then
        return nil
    end

    local index = love.math.random(#tips)

    -- Do not show the same tip twice in a row
    if #tips > 1 and index == lastTipIndex then
        index = index % #tips + 1
    end

    lastTipIndex = index

    return tips[index]
end

local function pickAndShowTip()
    if not tipLabel then
        return
    end

    local tip = pickTip()

    if tip then
        tipLabel:setText(tip)

    else
        tipLabel:setText(getText("empty"))
    end
end

local function getTipFont()
    local baseFont = uiElements.__label
        and uiElements.__label.__default
        and uiElements.__label.__default.style.font
        or love.graphics.getFont()
    local baseHeight = baseFont and baseFont:getHeight(" ") or 14
    local fontSize = math.max(12, math.floor(baseHeight * 1.35 + 0.5))

    return fonts.getScreenFont(fontSize, baseFont)
end

function tipsWindow.show()
    if window and window.parent then
        return
    end

    local language = languageRegistry.getLanguage()
    local pickButton = uiElements.button(tostring(language.ui.tips_window.pick), pickAndShowTip)
    local placeholder = uiElements.label(tostring(language.ui.tips_window.placeholder), getTipFont())

    placeholder.wrap = true
    tipLabel = placeholder

    local leftColumn = uiElements.column({pickButton}):with({
        style = {
            padding = 8
        }
    })
    local rightColumn = uiElements.column({placeholder}):with({
        width = textWidth,
        style = {
            padding = 8
        }
    })
    local content = uiElements.row({leftColumn, rightColumn}):with({
        style = {
            padding = 8,
            spacing = 8
        }
    })

    -- The row itself top-aligns its children; center both columns so the button and the (possibly
    -- wrapped) text block share the same vertical center.
    content:hook({
        layoutChildren = function(original, self)
            original(self)

            local rowHeight = math.max(leftColumn.height, rightColumn.height)
            local paddingTop = 8

            leftColumn.realY = paddingTop + math.floor((rowHeight - leftColumn.height) / 2)
            rightColumn.realY = paddingTop + math.floor((rowHeight - rightColumn.height) / 2)
        end
    })

    window = uiElements.window(tostring(language.ui.tips_window.title), content)

    local parent = uiRoot.getWindowGroup() or ui.root

    content:layout()
    windowPersister.trackWindow(windowName, window)
    parent:addChild(window)
    widgetUtils.addWindowCloseButton(window, windowPersister.getWindowCloseCallback(windowName))
    window:layout()
    window:layoutLate()
    widgetUtils.preventOutOfBoundsMovement(window)
    widgetUtils.consumeKeyboardEvents(window)
end

function tipsWindow.getWindow()
    tipsWindowWrapper.tipsWindow = tipsWindow

    return tipsWindowGroup
end

return tipsWindow
