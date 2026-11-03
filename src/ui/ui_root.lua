local ui = require("ui")
local uiElements = require("ui.elements")
local uiUtils = require("ui.utils")

local menubar = require("ui.menubar")
local notifications = require("ui.notification")
local tooltips = require("ui.tooltip")
local contextMenus = require("ui.context_menu")
local hoverPreviews = require("ui.hover_preview")

local uiRoot = {}

local rootElement
local mainColumn
local windowGroup

function uiRoot.updateWindows(windows)
    if not windowGroup then
        windowGroup = uiElements.group(
            windows
        ):with(uiUtils.fillWidth):with(uiUtils.fillHeight(true))

    else
        windowGroup.children = windows

        windowGroup:reflow()
    end

    if not mainColumn then
        mainColumn = uiElements.column({
            menubar.getMenubar(),
            windowGroup
        }):with({
            style = {
                bg = {},
                padding = 0,
                spacing = 0,
                radius = 0
            }
        }):with(uiUtils.fill)

    else
        mainColumn.children = {
            menubar.getMenubar(),
            windowGroup
        }

        mainColumn:reflow()
    end

    if not rootElement then
        rootElement = uiElements.group({
            mainColumn,
            notifications.getPopupWindow(),
            contextMenus.getContextMenu(),
            tooltips.getTooltipWindow(),
            hoverPreviews.getWindow()
        }):with({
            style = {
                bg = {},
                padding = 0,
                spacing = 0,
                radius = 0
            }
        })

        rootElement._menubar = menubar
        rootElement._windowGroup = windowGroup

    else
        rootElement.children[1] = mainColumn

        rootElement:reflow()
    end
end

-- Group holding every currently loaded window. Used to figure out which parts of the
-- screen are taken up by pinned panels, so overlays can stay inside the workspace.
function uiRoot.getWindowGroup()
    return windowGroup
end

function uiRoot.getRootElement(windows)
    uiRoot.updateWindows(windows)

    return rootElement
end

return uiRoot