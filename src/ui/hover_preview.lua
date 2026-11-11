-- Generic hover preview window.
--
-- Shows a floating panel next to whatever element is hovered, with its right edge (and a small
-- pointing arrow) toward that element. It is content agnostic: callers pass an image (optionally
-- with a quad / title) and the preview takes care of scaling and keeping itself inside the window.
-- Other tool panels can reuse it the same way the decal list does.

local uiElements = require("ui.elements")
local uiu = require("ui.utils")

local hoverPreview = {}

local gap = 10
local arrowSize = 11
local bubbleRadius = 3
local edgePadding = 12
local defaultArea = 300 * 400 * 0.6 * 0.64
local defaultMaxWidth = 360 * 0.8
local defaultMaxHeight = 420 * 0.8
local panelPadding = 10

-- Transparency checkerboard
local checkerSize = 16
local checkerLight = { 0.72, 0.72, 0.72 }
local checkerDark = { 0.52, 0.52, 0.52 }

local rootGroup
local panel
local anchorX, anchorY, anchorHeight = 0, 0, 0
local arrowY = 0
local shown = false
local currentKey
local imageAreaWidth, imageAreaHeight = 0, 0

local function ensureWindow()
    if rootGroup then
        return
    end

    panel = uiElements.panel({}):with({
        style = {
            -- The bubble (rounded rectangle + arrow) is drawn as one polygon by the root group,
            -- so the panel itself must not paint its own background or border
            bg = {},
            border = {},
            padding = panelPadding,
            radius = 0,
            patch = false
        },
        interactive = 0,
        visible = false
    })

    rootGroup = uiElements.group({panel})
    rootGroup.interactive = 0

    rootGroup:hook({
        update = function(orig, self)
            orig(self)

            if not shown or not panel.visible then
                return
            end

            local windowWidth, windowHeight = love.graphics.getDimensions()
            local width, height = panel.width, panel.height

            -- Right edge of the preview points at the hovered row, vertically centered on it
            local x = anchorX - width - gap
            local y = anchorY + anchorHeight * 0.5 - height * 0.5

            x = math.max(edgePadding, math.min(x, windowWidth - width - edgePadding))
            y = math.max(edgePadding, math.min(y, windowHeight - height - edgePadding))

            hoverPreview._place(x, y)

            -- Arrow points at the row, but stays on the panel
            local rowCenter = anchorY + anchorHeight * 0.5

            arrowY = math.max(panel.y + arrowSize + 3, math.min(rowCenter, panel.y + height - arrowSize - 3))
        end
    })

    rootGroup:hook({
        draw = function(orig, self)
            if not shown or not panel.visible then
                return
            end

            local points, bubbleArrowY = hoverPreview._bubblePoints()

            local x, y, width, height = panel.screenX, panel.screenY, panel.width, panel.height

            -- Fill first, so the image drawn by the children sits on top of it. Use uiu.setColor:
            -- the UI caches the current color, so a raw love.graphics.setColor here would make
            -- the children believe the color is already right and draw the image nearly black.
            uiu.setColor(0.07, 0.07, 0.07, 1)
            love.graphics.rectangle("fill", x, y, width, height)
            love.graphics.polygon("fill",
                x + width, bubbleArrowY - arrowSize,
                x + width + arrowSize, bubbleArrowY,
                x + width, bubbleArrowY + arrowSize)

            -- Classic transparency checkerboard behind the image. The cell size is fixed, the
            -- cells are clipped to the content area so the grid can never spill over the padding
            -- or the border.
            local contentX, contentY = x + panelPadding, y + panelPadding
            local contentWidth = math.max(0, math.floor(width - panelPadding * 2))
            local contentHeight = math.max(0, math.floor(height - panelPadding * 2))

            -- The grid only covers the image, not the description below it
            contentWidth = math.min(contentWidth, math.ceil(imageAreaWidth))
            contentHeight = math.min(contentHeight, math.ceil(imageAreaHeight))

            if contentWidth > 0 and contentHeight > 0 then
                local columns = math.ceil(contentWidth / checkerSize)
                local rows = math.ceil(contentHeight / checkerSize)

                for row = 0, rows - 1 do
                    local cellY = contentY + row * checkerSize
                    local cellHeight = math.min(checkerSize, contentY + contentHeight - cellY)

                    for column = 0, columns - 1 do
                        local cellX = contentX + column * checkerSize
                        local cellWidth = math.min(checkerSize, contentX + contentWidth - cellX)

                        if (row + column) % 2 == 0 then
                            uiu.setColor(checkerLight[1], checkerLight[2], checkerLight[3], 1)

                        else
                            uiu.setColor(checkerDark[1], checkerDark[2], checkerDark[3], 1)
                        end

                        love.graphics.rectangle("fill", cellX, cellY, cellWidth, cellHeight)
                    end
                end
            end

            orig(self)

            -- One single outline around the whole bubble, arrow included: no seam anywhere
            uiu.setColor(0.85, 0.85, 0.85, 0.9)
            love.graphics.setLineWidth(2)
            love.graphics.line(points)
            love.graphics.line(points[#points - 1], points[#points], points[1], points[2])

            uiu.setColor(1, 1, 1, 1)
        end
    })
end

-- The panel position has to be applied to realX/realY as well: those are what layout and drawing
-- actually use, setting x/y alone leaves the element where the last layout pass put it.
function hoverPreview._place(x, y)
    x = math.floor(x)
    y = math.floor(y)

    panel.x = x
    panel.y = y
    panel.realX = x
    panel.realY = y

    if panel.parent then
        panel.parent:reflow()
    end
end

-- Bubble outline: rounded rectangle with a triangular arrow on its right edge, positioned at
-- arrowY. Returns the flattened vertex list (for the outline) and the clamped arrow position.
function hoverPreview._bubblePoints()
    local x, y = panel.screenX, panel.screenY
    local w, h = panel.width, panel.height
    local r = math.max(0, math.min(bubbleRadius, w * 0.5, h * 0.5))
    local size = arrowSize
    local ay = math.max(y + r + size, math.min(arrowY, y + h - r - size))

    local points = {}

    local function arc(cx, cy, from, to)
        local steps = 3

        for i = 0, steps do
            local angle = from + (to - from) * i / steps

            points[#points + 1] = cx + math.cos(angle) * r
            points[#points + 1] = cy + math.sin(angle) * r
        end
    end

    points[#points + 1] = x + r; points[#points + 1] = y
    points[#points + 1] = x + w - r; points[#points + 1] = y
    arc(x + w - r, y + r, -math.pi * 0.5, 0)

    points[#points + 1] = x + w; points[#points + 1] = ay - size
    points[#points + 1] = x + w + size; points[#points + 1] = ay
    points[#points + 1] = x + w; points[#points + 1] = ay + size

    points[#points + 1] = x + w; points[#points + 1] = y + h - r
    arc(x + w - r, y + h - r, 0, math.pi * 0.5)

    points[#points + 1] = x + r; points[#points + 1] = y + h
    arc(x + r, y + h - r, math.pi * 0.5, math.pi)

    points[#points + 1] = x; points[#points + 1] = y + r
    arc(x + r, y + r, math.pi, math.pi * 1.5)

    return points, ay
end

function hoverPreview.getWindow()
    ensureWindow()

    return rootGroup
end

function hoverPreview.isShown()
    return shown and panel ~= nil and panel.visible == true
end

function hoverPreview.hide()
    if not rootGroup then
        return
    end

    shown = false
    currentKey = nil
    panel.visible = false
end

-- content: {
--   image  = love Image (required),
--   quad   = love Quad (optional),
--   width, height = source size (optional, taken from quad/image),
--   title  = string shown below the preview (optional),
--   area, maxWidth, maxHeight = size limits (optional),
-- }
-- left/top/height describe the hovered row: the preview is placed right next to it, vertically
-- centered on it, then clamped to the window.
function hoverPreview.show(left, top, height, content)
    ensureWindow()

    if not content or not content.image then
        hoverPreview.hide()
        return
    end

    anchorX, anchorY = left or 0, top or 0
    anchorHeight = height or 0

    -- Cheap path: same content as the already shown preview, only the anchors (and therefore
    -- the position) changed, so the children don't have to be rebuilt
    if content.key ~= nil and content.key == currentKey and panel.visible then
        shown = true

        return
    end

    currentKey = content.key

    local area = content.area or defaultArea

    -- Keep the area, but cap the sides: a very long/thin sprite would otherwise become huge in
    -- one dimension just to reach the target area
    local windowWidth, windowHeight = love.graphics.getDimensions()
    local maxWidth = math.min(content.maxWidth or defaultMaxWidth, windowWidth - (edgePadding + gap) * 2)
    local maxHeight = math.min(content.maxHeight or defaultMaxHeight, windowHeight - edgePadding * 2)

    local width, heightSource = content.width, content.height

    -- The quad is what actually gets drawn, so prefer its viewport when there is one
    if content.quad then
        local _, _, quadWidth, quadHeight = content.quad:getViewport()
        width, heightSource = quadWidth, quadHeight

    elseif not width or not heightSource then
        width, heightSource = content.image:getDimensions()
    end

    width = math.max(1, width)
    heightSource = math.max(1, heightSource)

    -- Fixed area, keeping the aspect ratio: every preview covers about the same amount of screen
    -- space, no matter if the sprite is wide, tall or square.
    local scale = math.sqrt(area / (width * heightSource))
    scale = math.min(scale, maxWidth / width, maxHeight / heightSource)

    local imageElement = uiElements.image(content.image, content.quad, content.layer):with({
        scaleX = scale,
        scaleY = scale,
        interactive = -1
    })

    imageAreaWidth = width * scale
    imageAreaHeight = heightSource * scale

    local children = {imageElement}

    if content.title then
        -- Shown under the preview, wrapped to the image width so the bubble does not become a
        -- long thin strip for a descriptive tooltip
        local wrapWidth = math.min(maxWidth, math.max(140, imageAreaWidth))

        local label = uiElements.label(uiu.getWrap(love.graphics.getFont(), tostring(content.title), math.floor(wrapWidth)))
        label.style.color = {0.75, 0.75, 0.75, 1}
        label.interactive = -1

        table.insert(children, label)
    end

    local column = uiElements.column(children)
    column.parent = panel
    column.interactive = -1
    panel.children = {column}

    panel:reflow()

    -- Position right away with the size we just computed, so it is already correct on the first
    -- visible frame. The update hook keeps refining it once the real layout size is known.
    local previewWidth = width * scale + panelPadding * 2
    local previewHeight = heightSource * scale + panelPadding * 2

    local x = anchorX - previewWidth - gap
    local y = anchorY + anchorHeight * 0.5 - previewHeight * 0.5

    x = math.max(edgePadding, math.min(x, windowWidth - previewWidth - edgePadding))
    y = math.max(edgePadding, math.min(y, windowHeight - previewHeight - edgePadding))

    hoverPreview._place(x, y)

    panel.visible = true
    shown = true

    arrowY = anchorY + anchorHeight * 0.5
end

return hoverPreview
