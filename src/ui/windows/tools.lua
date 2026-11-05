-- TODO - Hide material list if no materials?

local ui = require("ui")
local uiElements = require("ui.elements")
local uiUtils = require("ui.utils")

local widgetUtils = require("ui.widgets.utils")
local lists = require("ui.widgets.lists")
local simpleDocks = require("ui.widgets.simple_docks")
local contextMenu = require("ui.context_menu")
local listItemUtils = require("ui.utils.list_item")
local notifications = require("ui.notification")
local hoverPreview = require("ui.hover_preview")

local configs = require("configs")
local languageRegistry = require("language_registry")
local toolHandler = require("tools")
local toolUtils = require("tool_utils")
local persistence = require("persistence")
local modHandler = require("mods")
local textSearching = require("utils.text_search")
local utils = require("utils")
local hotkeyHandler = require("hotkey_handler")
local loadedState = require("loaded_state")
local subLayers = require("sub_layers")
local history = require("history")
local selectionUtils = require("selections")
local celesteRender = require("celeste_render")
local atlases = require("atlases")
local entities = require("entities")
local tiles = require("tiles")
local brushHelper = require("brushes")
local autotiler = require("autotiler")
local selectionItemUtils = require("selection_item_utils")
local placementUtils = require("placement_utils")
local virtualFs = require("virtual_fs")
local utf8 = require("utf8")

local toolWindow = {}

toolWindow.toolList = false
toolWindow.toolPanel = false

toolWindow.layerList = false
toolWindow.layerPanel = false
toolWindow.layerPanelVisible = true

toolWindow.modeList = false
toolWindow.modePanel = false
toolWindow.modePanelVisible = true

toolWindow.materialList = false
toolWindow.materialSearch = false
toolWindow.materialPanel = false

toolWindow.subLayers = {}

toolWindow.eventStates = {}

local layersWithSubLayers = {
    entities = true,
    triggers = true,
    decalsFg = true,
    decalsBg = true,
}

local layersWithBlankIcon = {
    allLayers = true,
}

-- Layers whose materials are decal paths. Those are shown as a path hierarchy instead of a flat
-- list of full paths, which makes a long list of mod decals much easier to navigate.
local layersWithDecalPaths = {
    decalsFg = true,
    decalsBg = true,
}

local decalPathIndent = "    "
local vanillaDecalSource = "[Celeste/Vanilla]"

-- Cached entity previews (name -> preview content or false), rebuilt with the material list
local entityPreviewCache = {}

local function splitDecalPath(path)
    local segments = {}

    for segment in string.gmatch(path, "[^/]+") do
        table.insert(segments, segment)
    end

    return segments
end

local function getDecalSourceLabel(language, associatedMods)
    return modHandler.formatAssociatedMods(language, associatedMods) or vanillaDecalSource
end

-- Some mods ship no usable everest.yaml (or their metadata cannot be looked up), so their decals
-- end up without associated mods and would be filed under vanilla. Fall back to the mod which
-- actually provides the decal file.
local function getDecalOwnerModName(name)
    local owner = virtualFs.getOwner("Graphics/Atlases/Gameplay/" .. name .. ".png")

    if not owner then
        return nil
    end

    local metadata = modHandler.modMetadata and modHandler.modMetadata[owner]

    if metadata then
        local names = modHandler.getModNamesFromMetadata(metadata)

        if names and #names > 0 then
            return names[1]
        end
    end

    return (owner:gsub("_zip$", ""):gsub("_folder$", ""))
end

-- Turns flat material names into a tree of list rows: a source header, one row per path segment
-- and the material itself as the leaf. Used by the decal list and the trigger list, which both
-- have mod/path style names.
--
-- options:
--   pathOf(name)      -> the slash separated path used for the hierarchy
--   leafText(entry)   -> display text of the actual material row
--   searchText(entry) -> text used for searching that row
--   favoritesText(entry) -> display text in the favorites group (defaults to the full path)
--   resolveOwner      -> ask virtual_fs for the mod when the material has no associated mods
local function getPathTreeItems(materials, currentTool, currentLayer, favoritesLookup, language, options)
    options = options or {}

    local function pathOf(name)
        return options.pathOf and options.pathOf(name) or name
    end

    local function leafText(entry)
        return options.leafText and options.leafText(entry) or entry.segments[#entry.segments]
    end

    local function searchText(entry)
        return options.searchText and options.searchText(entry) or table.concat(entry.segments, "/")
    end

    local function favoritesText(entry)
        return options.favoritesText and options.favoritesText(entry) or table.concat(entry.segments, "/")
    end

    local entries = {}

    for _, material in ipairs(materials or {}) do
        local isTable = type(material) == "table"
        local name = isTable and material.name or material

        if name then
            local associatedMods = isTable and material.associatedMods or nil

            if options.resolveOwner and (not associatedMods or #associatedMods == 0) then
                local ownerMod = getDecalOwnerModName(name)

                if ownerMod then
                    associatedMods = {ownerMod}
                end
            end

            local path = pathOf(name)

            -- Also searchable by the mod it comes from: most mod materials do not contain the
            -- mod name in their path at all
            local searchNames = {}

            for _, modName in ipairs(associatedMods or {}) do
                table.insert(searchNames, modName)
            end

            for _, altName in ipairs(isTable and material.alternativeDisplayNames or {}) do
                table.insert(searchNames, altName)
            end

            if #searchNames == 0 then
                table.insert(searchNames, "Celeste")
                table.insert(searchNames, "Vanilla")
            end

            table.insert(entries, {
                name = name,
                material = isTable and material or nil,
                -- Flat lists (triggers, entities) only get a source header, no path hierarchy
                segments = options.flat and {} or splitDecalPath(path),
                displayName = (isTable and material.displayNameNoMods) or name,
                sourceLabel = getDecalSourceLabel(language, associatedMods),
                sourceKey = (associatedMods and associatedMods[1]) or "",
                associatedMods = associatedMods,
                tooltip = isTable and material.tooltipText or nil,
                alternativeNames = searchNames
            })
        end
    end

    table.sort(entries, function(lhs, rhs)
        if lhs.sourceKey ~= rhs.sourceKey then
            -- Vanilla materials first
            if lhs.sourceKey == "" then
                return true
            elseif rhs.sourceKey == "" then
                return false
            end

            return lhs.sourceKey < rhs.sourceKey
        end

        local lhsPath = table.concat(lhs.segments, "/")
        local rhsPath = table.concat(rhs.segments, "/")

        if lhsPath ~= rhsPath then
            return lhsPath < rhsPath
        end

        return lhs.name < rhs.name
    end)

    local items = {}

    local function addItem(item)
        item.currentTool = currentTool
        item.currentToolName = currentTool.name
        item.currentLayer = currentLayer

        table.insert(items, item)
    end

    local previousSource
    local previousSegments = {}
    local chain = {}

    -- Favorites get their own root group on top instead of being sorted to the front of the tree.
    -- They are left out of the tree below: the same entry twice would make selecting it ambiguous.
    local favorites = {}
    local treeEntries = {}

    for _, entry in ipairs(entries) do
        if favoritesLookup[entry.name] then
            table.insert(favorites, entry)

        else
            table.insert(treeEntries, entry)
        end
    end

    if #favorites > 0 then
        addItem({
            text = "[Favorites]",
            textNoMods = "",
            data = false,
            isHeader = true,
            isSource = true,
            isFavoritesHeader = true,
            indent = 0,
            ancestors = {}
        })

        for _, entry in ipairs(favorites) do
            addItem({
                text = favoritesText(entry),
                textNoMods = searchText(entry),
                data = entry.name,
                indent = 0,
                tooltip = entry.tooltip,
                alternativeNames = entry.alternativeNames,
                associatedMods = entry.associatedMods,
                itemFavorited = true,
                isFavoritesGroup = true,
                placement = entry.material,
                ancestors = {}
            })
        end
    end

    for _, entry in ipairs(treeEntries) do
        if entry.sourceLabel ~= previousSource then
            previousSource = entry.sourceLabel
            previousSegments = {}

            local sourceItem = {
                text = entry.sourceLabel,
                textNoMods = "",
                data = false,
                isHeader = true,
                isSource = true,
                indent = 0,
                ancestors = {}
            }

            addItem(sourceItem)

            chain = { sourceItem }
        end

        local segments = entry.segments
        local commonPrefix = 0

        while commonPrefix < #previousSegments and commonPrefix < #segments - 1
            and previousSegments[commonPrefix + 1] == segments[commonPrefix + 1] do
            commonPrefix = commonPrefix + 1
        end

        if #chain > commonPrefix + 1 then
            local shortened = {}

            for i = 1, commonPrefix + 1 do
                shortened[i] = chain[i]
            end

            chain = shortened
        end

        for i = commonPrefix + 1, #segments - 1 do
            local dirItem = {
                text = segments[i],
                textNoMods = "",
                data = false,
                isHeader = true,
                indent = i,
                ancestors = chain
            }

            addItem(dirItem)

            local nextChain = table.shallowcopy(chain)
            nextChain[#nextChain + 1] = dirItem
            chain = nextChain
        end

        addItem({
            text = leafText(entry),
            textNoMods = searchText(entry),
            data = entry.name,
            indent = options.flat and 1 or #segments,
            tooltip = entry.tooltip,
            alternativeNames = entry.alternativeNames,
            associatedMods = entry.associatedMods,
            itemFavorited = not not favoritesLookup[entry.name],
            placement = entry.material,
            ancestors = chain
        })

        previousSegments = segments
    end

    -- Keep the generated tree order and ignore the favorite-first sorting of the material list
    for i, item in ipairs(items) do
        item.sortIndex = i
    end

    return items
end

local function getLanguageOrDefault(languagePath, default)
    if languagePath._exists then
        return tostring(languagePath)
    end

    return default
end

local function updateListItemFavoriteVisuals(listItem)
    local favorite = listItem.itemFavorited

    if favorite then
        listItemUtils.setIcon(listItem, "favorite")

    else
        listItemUtils.clearIcon(listItem)
    end
end

-- Used for layer icon click and double click
local function layerItemToggleVisibilityHandler(listItem, button)
    if button ~= 1 then
        return false
    end

    local layer = listItem.baseLayer
    local subLayer = listItem.subLayer
    local layerName = subLayers.formatLayerName(layer, subLayer)
    local newVisible = not loadedState.getLayerVisible(layerName)

    loadedState.setLayerVisible(layerName, newVisible)
end

local function materialSortFunction(lhs, rhs)
    -- Items which already come in a meaningful order (the decal path tree)
    if lhs.sortIndex and rhs.sortIndex then
        return lhs.sortIndex < rhs.sortIndex
    end

    if lhs.itemFavorited ~= rhs.itemFavorited then
        return lhs.itemFavorited
    end

    if configs.ui.searching.sortByScore then
        if lhs._filterScore and rhs._filterScore and lhs._filterScore ~= rhs._filterScore then
            return lhs._filterScore > rhs._filterScore
        end
    end

    local lhsText = lhs.originalText or lhs.text
    local rhsText = rhs.originalText or rhs.text

    return lhsText < rhsText
end

-- TODO - Config for text vs textNoMods?
-- TODO - Score checks could potentially be cached, for mod names there is a lot of redundant checks
local function getMaterialScore(item, searchParts, caseSensitive, fuzzy)
    -- Always match with empty search
    if #searchParts == 0 then
        return math.huge
    end

    local totalScore = 0

    -- Every term has to match (AND): "crystal flower" only finds entries matching both
    for _, part in ipairs(searchParts) do
        local partScore = nil

        if part.mode == "name" then
            local search = part.text
            local text = item.textNoMods or ""
            partScore = textSearching.searchScore(text, search, caseSensitive, fuzzy)

            if item.alternativeNames then
                for _, altName in ipairs(item.alternativeNames) do
                    local altScore = textSearching.searchScore(altName, search, caseSensitive, fuzzy)

                    if altScore and (not partScore or altScore > partScore) then
                        partScore = altScore
                    end
                end
            end

        elseif part.mode == "modName" then
            -- If we have additional search text it should search for entries within the given mod
            local associatedMods = item.associatedMods
            local searchModName = part.text
            local search = part.additional
            local text = item.textNoMods or ""

            -- Assume that mods with no associatedMods is from Celeste
            if not associatedMods or #associatedMods == 0 then
                associatedMods = {"Celeste", "Vanilla"}
            end

            for _, modName in ipairs(associatedMods) do
                local modScore = textSearching.searchScore(modName, searchModName, caseSensitive, fuzzy)
                local score = textSearching.searchScore(text, search, caseSensitive, fuzzy)

                -- Only include the additional search if it matches
                if modScore and (#search == 0 or score) then
                    partScore = modScore + (score or 0)

                    break
                end
            end
        end

        if not partScore then
            return nil
        end

        totalScore += partScore
    end

    return totalScore
end

local function prepareMaterialSearch(search)
    local parts = {}
    local searchStringParts = search:split("|")()

    for _, searchPart in ipairs(searchStringParts) do
        if utils.startsWith(searchPart, "@") then
            -- First space or the end of the string, used to extract additional search terms
            local spaceIndex = utils.findCharacter(searchPart, " ") or #searchPart + 1
            local modName = string.sub(searchPart, 2, spaceIndex - 1)
            local additional = string.sub(searchPart, spaceIndex + 1)
            local addedTerm = false

            -- Separate words are independent terms (a union), not one long substring
            for word in additional:gmatch("%S+") do
                addedTerm = true

                table.insert(parts, {
                    mode = "modName",
                    text = modName,
                    additional = word
                })
            end

            if not addedTerm then
                table.insert(parts, {
                    mode = "modName",
                    text = modName,
                    additional = ""
                })
            end

        else
            for word in searchPart:gmatch("%S+") do
                table.insert(parts, {
                    mode = "name",
                    text = word
                })
            end
        end
    end

    -- Remove empty entries, just causes issues
    for i = #parts, 1, -1 do
        if #parts[i].text == 0 then
            table.remove(parts, i)
        end
    end

    return parts
end

-- Search filter for the decal path tree: a matching decal keeps the directory rows above it, so
-- the result stays readable instead of being a pile of indented leaves.
local function filterMaterialItems(items, search, options)
    if not search or search == "" then
        -- Keep the scores consistent: a stale mix of numbers and nils makes the sorting
        -- comparator compare a number with nil
        for _, item in ipairs(items) do
            item._filterScore = math.huge
        end

        return items
    end

    local fuzzy = configs.ui.searching.searchFuzzy
    local caseSensitive = configs.ui.searching.searchCaseSensitive

    if caseSensitive == "contextual" then
        caseSensitive = search ~= search:lower()

    elseif type(caseSensitive) == "string" then
        caseSensitive = caseSensitive == "always"
    end

    if utils.startsWith(search, "~") then
        fuzzy = true
        search = string.sub(search, 2)
    end

    local parts = prepareMaterialSearch(search)

    if #parts == 0 then
        return items
    end

    local keep = {}
    local favoritesHeader

    for _, item in ipairs(items) do
        if item.isFavoritesHeader then
            favoritesHeader = item

        elseif not item.isHeader then
            local score = getMaterialScore(item, parts, caseSensitive, fuzzy)

            if score then
                item._filterScore = score
                keep[item] = true

                -- Favorites are not part of the tree, so keep their own root row with them
                if item.isFavoritesGroup and favoritesHeader then
                    keep[favoritesHeader] = true
                end

                for _, ancestor in ipairs(item.ancestors or {}) do
                    keep[ancestor] = true
                end
            end
        end
    end

    local filtered = {}

    for _, item in ipairs(items) do
        if keep[item] then
            table.insert(filtered, item)
        end
    end

    return filtered
end

local getMaterialItems

local function updateFavorite(materialList, itemData, tool, layer, material, favorite)
    if favorite then
        toolUtils.addPersistenceFavorites(tool, layer, material)

    else
        toolUtils.removePersistenceFavorites(tool, layer, material)
    end

    itemData.itemFavorited = favorite

    -- Rebuild the whole list so the favorites root group reflects the change right away
    materialList:updateItems(getMaterialItems(), material)
end

local function materialFavoriteDoubleClickedCallback(self, button)
    if button ~= 1 or not self.data then
        return
    end

    local tool = toolHandler.currentTool
    local layer = toolHandler.getLayer()

    local material = self.data
    local favorited = self.itemFavorited

    updateFavorite(self.parent, self.itemData, tool, layer, material, not favorited)
end

local function addMaterialContextMenu(language, tool, layer, listItem)
    local material = listItem.data
    local itemData = listItem.itemData
    local favorite = itemData.itemFavorited

    local favoriteText = tostring(language.ui.tools_window.favorite)
    local favoriteCheckbox = uiElements.checkbox(favoriteText, favorite, function(checkbox, newFavorite)
        updateFavorite(listItem.parent, itemData, tool, layer, material, newFavorite)
    end)

    listItem._favoriteCheckbox = favoriteCheckbox

    local content = uiElements.row({
        favoriteCheckbox
    })

    return contextMenu.addContextMenu(listItem, content)
end

-- The editor only ships a single (bitmap) font, so bold text is emulated by drawing the label
-- once more with a one pixel offset.
local function installBoldLabelHook(listItem)
    local label = listItem and listItem.label

    if label and not label._boldHooked then
        label._boldHooked = true

        label:hook({
            draw = function(orig, self)
                orig(self)

                if self._bold and self._text then
                    love.graphics.draw(self._text, self.screenX + 1, self.screenY)
                end
            end
        })
    end
end

-- Defined further down, used by the row and preview code above it
local getTilesetThumbnail

local function materialDataToElement(list, data, element)
    if not element then
        element = uiElements.listItem()
    end

    if data then
        local indent = data.indent or 0
        local text = data.text or ""

        if indent > 0 then
            text = string.rep(decalPathIndent, indent) .. text
        end

        element.text = text
        element.data = data.data
        element.tooltipText = data.tooltip
        element.itemFavorited = data.itemFavorited
        element.originalText = data.text
        element.itemData = data

        -- Path tree rows are just labels: no interaction at all (hit testing uses the raw
        -- "interactive" field, not getInteractive)
        if data.isHeader then
            element.interactive = -1

            -- Directory rows get their own background: the topmost is the darkest and every
            -- deeper level gets a little lighter, always staying darker than a decal row.
            -- This has to be normalBG: the list item's update fades style.bg from normalBG every
            -- frame, so writing style.bg directly is simply overwritten.
            local shade = math.min(0.11, 0.06 + (data.indent or 0) * 0.01)

            element.style.normalBG = { shade, shade, shade, 1 }
            element.style.disabledBG = { shade, shade, shade, 1 }

        else
            element.interactive = 1
            element.style.normalBG = { 0.13, 0.13, 0.13, 0.9 }
            element.style.disabledBG = { 0.05, 0.05, 0.05, 0.7 }
        end

        -- The UI only ships one (bitmap) font, so "bold" is emulated by drawing the label twice.
        -- Every path tree row (source and directories) is bold, decals themselves are not. The
        -- label must not be cached, otherwise a recycled label keeps its old (not bold) canvas.
        if element.label then
            element.label.cacheable = false
            installBoldLabelHook(element)
            element.label._bold = data.isHeader or false
        end

        -- Hover preview is driven from the list update (see updateHoverPreview): enter/leave
        -- callbacks are not reliable here, because a row element can be rebound to different
        -- data (scrolling, filtering) without the hover ever leaving it, which showed a stale
        -- preview for a different decal.

        local thumbnail = data.thumbnail

        -- Rows may be rebuilt from plain data, so fall back to looking the tileset up again
        if not thumbnail and tiles.tileLayers[data.currentLayer or ""] and data.data then
            thumbnail = getTilesetThumbnail(data.currentLayer, data.data)
        end

        -- Must come first: it rebuilds the row children for the favorite/icon state
        updateListItemFavoriteVisuals(element)

        -- Then the thumbnail gets added, so the icon reset can not wipe it
        if element._thumbnailElement then
            element._thumbnailElement:removeSelf()
        end

        element._thumbnailElement = nil
        element._thumbnailCanvas = thumbnail and thumbnail.canvas or nil

        if thumbnail then
            local success, thumbnailElement = pcall(uiElements.image, thumbnail.canvas)

            if success and thumbnailElement then
                element:addChild(thumbnailElement, 1)
                element:reflow()

                element._thumbnailElement = thumbnailElement
            end
        end

        -- The image child only reserves the space: the row's own element draw does not seem to
        -- reach it, so the canvas is drawn here, where the row is painted
        if not element._thumbnailHooked then
            element._thumbnailHooked = true

            element:hook({
                draw = function(orig, self, ...)
                    orig(self, ...)

                    local canvas = self._thumbnailCanvas
                    local thumbnailElement = self._thumbnailElement

                    if canvas and thumbnailElement and thumbnailElement.screenX then
                        local size = math.min(thumbnailElement.width or 16, thumbnailElement.height or 16)
                        local offsetX = thumbnailElement.screenX + math.floor((thumbnailElement.width - size) * 0.5)
                        local offsetY = thumbnailElement.screenY + math.floor((thumbnailElement.height - size) * 0.5)

                        love.graphics.setColor(1, 1, 1, 1)
                        love.graphics.draw(canvas, offsetX, offsetY, 0, size / 24, size / 24)
                    end
                end
            })
        end
    end

    return element
end

-- Rows are recycled and rebound to other data while scrolling or filtering (sometimes without
-- an enter/leave event at all), so the hover preview is recomputed every frame from the element
-- currently under the cursor instead of being started from an onEnter callback.

-- Collects every actual sprite (something with an atlas image and a quad) from a drawable,
-- looking through the table wrappers that animation frames / custom drawables use.
local function collectSpriteDrawables(drawable, out, depth)
    if type(drawable) ~= "table" or depth > 3 then
        return
    end

    local meta = drawable.meta

    if meta and meta.image and drawable.quad and drawable.quad.getViewport then
        table.insert(out, drawable)

        return
    end

    for _, value in ipairs(drawable) do
        collectSpriteDrawables(value, out, depth + 1)
    end
end

-- Turns a drawable (single sprite, animation frames, or a table of custom drawables) into
-- preview content. Only real sprites are kept: that filters out the helper drawables used by
-- custom rendering (lines, rectangles, the 1x1 white pixel, ...). Everything else is composited
-- onto a canvas, so entities built out of many sprites (a zip mover and the like) show all of
-- them, positioned relative to each other but without the entity's world offset.
local function spriteToPreview(sprite)
    local meta = sprite.meta

    if not meta or not meta.image or not sprite.quad then
        return nil
    end

    return {
        image = meta.image,
        quad = sprite.quad,
        layer = meta.layer or sprite.layer,
        width = meta.width,
        height = meta.height
    }
end

local function drawableToPreview(drawable)
    local sprites = {}

    collectSpriteDrawables(drawable, sprites, 0)

    if #sprites == 0 then
        return nil
    end

    if #sprites == 1 then
        return spriteToPreview(sprites[1])
    end

    local minX, minY = math.huge, math.huge
    local maxX, maxY = -math.huge, -math.huge

    for _, sprite in ipairs(sprites) do
        local _, _, width, height = sprite.quad:getViewport()
        local x, y = sprite.x or 0, sprite.y or 0

        minX = math.min(minX, x)
        minY = math.min(minY, y)
        maxX = math.max(maxX, x + width)
        maxY = math.max(maxY, y + height)
    end

    local width = math.ceil(maxX - minX)
    local height = math.ceil(maxY - minY)

    -- Too big to be a sane preview (or degenerate): fall back to the biggest single sprite
    if width <= 0 or height <= 0 or width > 512 or height > 512 then
        local best, bestArea = nil, -1

        for _, sprite in ipairs(sprites) do
            local _, _, spriteWidth, spriteHeight = sprite.quad:getViewport()
            local area = spriteWidth * spriteHeight

            if area > bestArea then
                best, bestArea = sprite, area
            end
        end

        return best and spriteToPreview(best)
    end

    local canvas = love.graphics.newCanvas(width, height)
    local previousCanvas = love.graphics.getCanvas()

    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    uiUtils.setColor(1, 1, 1, 1)

    for _, sprite in ipairs(sprites) do
        local meta = sprite.meta
        local layer = meta.layer or sprite.layer
        local x = (sprite.x or 0) - minX
        local y = (sprite.y or 0) - minY

        if layer then
            love.graphics.drawLayer(meta.image, layer, sprite.quad, x, y)

        else
            love.graphics.draw(meta.image, sprite.quad, x, y)
        end
    end

    love.graphics.setCanvas(previousCanvas)
    uiUtils.setColor(1, 1, 1, 1)

    return {
        image = canvas,
        quad = love.graphics.newQuad(0, 0, width, height, width, height),
        width = width,
        height = height
    }
end

-- Renders the drawable the same way the placement ghost does (including custom drawing such as
-- the lines of a zip mover, and the entity nodes) into an offscreen canvas, then crops it to the
-- drawn content.
local function drawableToCanvasPreview(drawable, room, layer, entity)
    local entityX = entity and entity.x or 0
    local entityY = entity and entity.y or 0

    -- The canvas has to cover the nodes as well, which can be far away from the entity
    local extent = 80

    for _, node in ipairs(entity and entity.nodes or {}) do
        extent = math.max(extent,
            math.abs((node.x or 0) - entityX) + 24,
            math.abs((node.y or 0) - entityY) + 24)
    end

    local size = math.min(512, math.max(96, math.ceil(extent * 2)))

    local drawn, canvas = pcall(function()
        local target = love.graphics.newCanvas(size, size)
        local previousCanvas = love.graphics.getCanvas()

        love.graphics.setCanvas(target)
        love.graphics.clear(0, 0, 0, 0)
        uiUtils.setColor(1, 1, 1, 1)

        love.graphics.push()
        love.graphics.translate(size / 2 - entityX, size / 2 - entityY)

        local ok

        if utils.typeof(drawable) == "table" then
            ok = pcall(function()
                for _, part in ipairs(drawable) do
                    if part.draw then
                        part:draw(1)
                    end
                end
            end)

        else
            ok = pcall(function()
                if drawable.draw then
                    drawable:draw(1)
                end
            end)
        end

        -- Node lines and node sprites are drawn by the same code the editor uses for a placed
        -- entity, which is what the placement ghost shows too
        if ok and room and entity then
            pcall(selectionItemUtils.drawSelected, room, layer, entity)
        end

        love.graphics.pop()
        love.graphics.setCanvas(previousCanvas)
        uiUtils.setColor(1, 1, 1, 1)

        if not ok then
            error("drawable failed to draw")
        end

        return target
    end)

    if not drawn or not canvas then
        return nil
    end

    local data = canvas:newImageData()
    local minX, minY = size, size
    local maxX, maxY = -1, -1

    for y = 0, size - 1 do
        for x = 0, size - 1 do
            local _, _, _, alpha = data:getPixel(x, y)

            if alpha > 0.01 then
                minX = math.min(minX, x)
                minY = math.min(minY, y)
                maxX = math.max(maxX, x)
                maxY = math.max(maxY, y)
            end
        end
    end

    data:release()

    if maxX < minX or maxY < minY then
        return nil
    end

    local width, height = maxX - minX + 1, maxY - minY + 1

    return {
        image = canvas,
        quad = love.graphics.newQuad(minX, minY, width, height, size, size),
        width = width,
        height = height
    }
end

-- Entities are drawn from their handler, which needs a room and an entity instance. Both are
-- best effort: if the handler needs something we can't provide, there is simply no preview.
local function getEntityPreview(placement)
    if not placement or not placement.itemTemplate then
        return nil
    end

    local cacheKey = placement.name

    if cacheKey and entityPreviewCache[cacheKey] ~= nil then
        return entityPreviewCache[cacheKey] or nil
    end

    local name = placement.itemTemplate._name
    local handler = name and entities.registeredEntities[name]
    local preview

    if handler then
        local room = loadedState.getSelectedRoom()
        local entity = utils.deepcopy(placement.itemTemplate)

        entity.x = entity.x or 0
        entity.y = entity.y or 0

        -- The placement ghost adds the mandatory nodes to the item before drawing it (see
        -- placement.lua updatePlacementNodes); without them a node based entity would preview
        -- just its main sprite. Mirror that here.
        if room then
            local minimumNodes = placementUtils.nodeLimits(room, "entities", entity)

            if minimumNodes and minimumNodes > 0 then
                entity.nodes = entity.nodes or {}

                while #entity.nodes < minimumNodes do
                    local index = #entity.nodes + 1
                    local widthOffset = (entity.width or 0) * index
                    local nodeOffsetX = index * 16

                    table.insert(entity.nodes, {
                        x = entity.x + widthOffset + nodeOffsetX,
                        y = entity.y
                    })
                end
            end
        end

        local ok, drawable = pcall(entities.getEntityDrawable, name, handler, room, entity, nil)

        if ok and drawable then
            -- Draw it exactly like the placement ghost does (custom rendering, lines, sprite
            -- tables, nodes, ...) into a canvas; only if that produces nothing, fall back to
            -- pulling the sprites out of the drawable
            preview = drawableToCanvasPreview(drawable, room, "entities", entity) or drawableToPreview(drawable)
        end
    end

    if cacheKey then
        entityPreviewCache[cacheKey] = preview or false
    end

    return preview
end

local function updateHoverPreview(list)
    -- The debug list has no placements to preview
    if toolHandler.currentToolName == "debug" then
        hoverPreview.hide()

        return
    end

    local hovered = ui.hovering

    while hovered and hovered ~= list and not hovered.itemData do
        hovered = hovered.parent
    end

    if not hovered or hovered == list or not hovered.itemData then
        hoverPreview.hide()
        return
    end

    local item = hovered.itemData
    local material = item.data
    local content

    if type(material) ~= "string" then
        hoverPreview.hide()
        return
    end

    local thumbnail = item.thumbnail

    if not thumbnail and item.currentLayer and tiles.tileLayers[item.currentLayer] and material then
        thumbnail = getTilesetThumbnail(item.currentLayer, material)
    end

    if thumbnail then
        content = {
            key = "tileset:" .. tostring(material),
            image = thumbnail.canvas,
            width = 24,
            height = 24
        }

    elseif utils.startsWith(material, "decals/") then
        -- getResource returns the atlas sprite. Its quad is on the sprite itself (meta has no
        -- quad), so use the sprite fields: the image is the whole atlas page otherwise.
        local sprite = atlases.getResource(material, "Gameplay")

        if sprite then
            content = {
                key = "decal:" .. material,
                image = sprite.image,
                quad = sprite.quad,
                -- Sprites live in a runtime texture array; without the layer the wrong slice of
                -- the atlas is drawn
                layer = sprite.layer,
                width = sprite.width,
                height = sprite.height
            }
        end

    elseif item.currentLayer == "entities" then
        local preview = getEntityPreview(item.placement)

        if preview then
            preview.key = "entity:" .. material

            content = preview
        end
    end

    if not content then
        hoverPreview.hide()
        return
    end

    -- The description goes under the preview image instead of a separate tooltip
    local tooltip = item.tooltip

    if type(tooltip) == "string" and tooltip ~= "" then
        content.title = tooltip
    end

    hoverPreview.show(hovered.screenX, hovered.screenY, hovered.height, content)
end

-- 3x3 tile thumbnail of a tileset, cached per layer/id
local tilesetThumbnails = {}

getTilesetThumbnail = function(layer, id)
    local key = layer .. ":" .. tostring(id)
    local cached = tilesetThumbnails[key]

    if cached ~= nil then
        return cached or nil
    end

    local meta = brushHelper.getTilerMeta(layer)
    local tileset = meta and meta[id]
    local path = tileset and tileset.path
    local sprite = path and atlases.getResource(path, "Gameplay")

    if not sprite or not sprite.image then
        tilesetThumbnails[key] = false

        return nil
    end

    local image = sprite.image

    -- Fake tile matrix: a 3x3 block surrounded by air, so the autotiler picks the corner, edge
    -- and filled center quads for it instead of one repeated tile
    local blockMatrix = {
        get = function(_, x, y)
            if x >= 0 and x <= 2 and y >= 0 and y <= 2 then
                return id
            end

            return "0"
        end
    }

    local fg = layer ~= "tilesBg"
    local canvas = love.graphics.newCanvas(24, 24)

    canvas:renderTo(function()
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.setColor(1, 1, 1, 1)

        for y = 0, 2 do
            for x = 0, 2 do
                local quads = autotiler.getQuads(x, y, blockMatrix, tileset, "0", " ", "*", {{0, 0}}, nil, autotiler.checkTile)

                if quads and quads[1] then
                    local quad = celesteRender.getOrCacheTileSpriteQuad(celesteRender.tilesSpriteMetaCache, id, tileset.path, quads[1], fg)

                    if sprite.layer then
                        love.graphics.drawLayer(image, sprite.layer, quad, x * 8, y * 8)

                    else
                        love.graphics.draw(image, quad, x * 8, y * 8)
                    end
                end
            end
        end
    end)

    local thumbnail = {canvas = canvas, image = canvas}

    tilesetThumbnails[key] = thumbnail

    return thumbnail
end

-- Tile materials are tilesets: group them by source like the placement list and attach the
-- thumbnail each row shows in front of its name
local function getTilesetItems(materials, currentTool, currentLayer, favoritesLookup, language)
    local entries = {}
    local thumbnails = {}

    for _, material in ipairs(materials or {}) do
        local id = type(material) == "table" and material.name or material
        local displayName = type(material) == "table" and material.displayName or tostring(material)

        if id then
            local modName = string.match(displayName, "^([^/]+)/")

            table.insert(entries, {
                name = id,
                associatedMods = modName and {modName} or nil,
                displayNameNoMods = displayName,
                tooltipText = displayName
            })

            local thumbnail = getTilesetThumbnail(currentLayer, id)

            if thumbnail then
                thumbnails[id] = thumbnail
            end
        end
    end

    local items = getPathTreeItems(entries, currentTool, currentLayer, favoritesLookup, language, {
        flat = true,
        leafText = function(entry)
            return entry.displayName or entry.name
        end,
        searchText = function(entry)
            return entry.displayName or entry.name
        end,
        favoritesText = function(entry)
            return entry.displayName or entry.name
        end
    })

    for _, item in ipairs(items) do
        item.thumbnail = thumbnails[item.data]
    end

    return items
end

getMaterialItems = function(layer)
    -- A rebuilt list invalidates whatever row was hovered before
    hoverPreview.hide()
    entityPreviewCache = {}

    local currentTool = toolHandler.currentTool
    local currentLayer = layer or toolHandler.getLayer(currentTool)
    local materials = toolHandler.getMaterials(nil, layer or currentLayer)
    local materialItems = {}
    local favorites = toolUtils.getPersistenceFavorites(currentTool, currentLayer) or {}
    local favoritesLookup = table.flip(favorites)
    local language = languageRegistry.getLanguage()

    if layersWithDecalPaths[currentLayer] then
        return getPathTreeItems(materials, currentTool, currentLayer, favoritesLookup, language, {
            pathOf = function(name)
                return string.match(name, "^decals/(.*)$") or name
            end,
            resolveOwner = true
        })
    end

    -- Tile tools list their tilesets grouped by source, with a 3x3 tile thumbnail per entry
    if tiles.tileLayers[currentLayer] then
        return getTilesetItems(materials, currentTool, currentLayer, favoritesLookup, language)
    end

    -- The debug tool lists the entities / triggers used in the map, grouped by mod
    if currentTool and currentTool.name == "debug" then
        return getPathTreeItems(materials, currentTool, currentLayer, favoritesLookup, language, {
            flat = true,
            leafText = function(entry)
                return entry.displayName or entry.name
            end,
            searchText = function(entry)
                return entry.displayName or entry.name
            end,
            favoritesText = function(entry)
                return entry.displayName or entry.name
            end
        })
    end

    if currentLayer == "triggers" or currentLayer == "entities" then
        -- Triggers and entities have no meaningful path hierarchy: group them by source mod only
        return getPathTreeItems(materials, currentTool, currentLayer, favoritesLookup, language, {
            flat = true,
            leafText = function(entry)
                return entry.displayName or entry.segments[#entry.segments]
            end,
            searchText = function(entry)
                return entry.displayName or table.concat(entry.segments, "/")
            end,
            favoritesText = function(entry)
                return entry.displayName or table.concat(entry.segments, "/")
            end
        })
    end

    for i, material in ipairs(materials or {}) do
        local materialTooltip
        local materialText = material
        local materialTextNoMods = material
        local materialData = material
        local materialType = type(material)

        if materialType == "table" then
            materialText = material.displayName or material.name
            materialTextNoMods = material.displayNameNoMods or materialText
            materialData = material.name
            materialTooltip = material.tooltipText
        end

        local itemFavorited = not not favoritesLookup[materialData]
        local item = {
            text = materialText,
            textNoMods = materialTextNoMods,
            alternativeNames = material.alternativeDisplayNames,
            data = materialData,
            tooltip = materialTooltip,
            itemFavorited = itemFavorited,
            currentTool = currentTool,
            currentToolName = currentTool.name,
            currentLayer = currentLayer,
            associatedMods = material.associatedMods
        }

        table.insert(materialItems, item)
    end

    return materialItems
end

local function materialCallback(list, material)
    -- Header rows of the decal path tree have no material behind them
    if not material then
        return
    end

    local sameMaterial = material == toolWindow.eventStates.material

    if not sameMaterial then
        toolWindow.eventStates.material = material

        toolHandler.setMaterial(material)
    end
end

local function toolMaterialChangedCallback(self, tool, layer, material)
    toolWindow.eventStates.layer = layer
    toolWindow.eventStates.material = material

    toolWindow.layerList:setSelection(subLayers.formatLayerName(layer, tool.subLayer), true)

    local selectedMaterial = toolWindow.materialList:setSelection(material, true)

    if not selectedMaterial then
        toolWindow.materialList:clearSelection()
    end
end

local function getLayerItemName(language, layer, subLayer, noIndent, forceSubLayer)
    local layersNames = language.layers.name
    local displayName = getLanguageOrDefault(layersNames[layer], layer)
    local defaultSubLayer = not subLayer or subLayer == -1

    if not forceSubLayer and defaultSubLayer then
        return displayName
    end

    local layerDisplayName = subLayers.getLayerName(layer, subLayer)

    if not layerDisplayName or utils.trim(layerDisplayName) == "" then
        subLayer = subLayer or 0
        layerDisplayName = string.format("%s %s", displayName, subLayer + 1)
    end

    if noIndent then
        return layerDisplayName
    end

    return string.format("  %s", layerDisplayName)
end

local function getLayerItems(toolName)
    local language = languageRegistry.getLanguage()
    local layers = toolHandler.getLayers(toolName) or {}
    local layerItems = {}

    local layersDescriptions = language.layers.description

    local allSubLayers = toolWindow.subLayers

    for _, layer in ipairs(layers) do
        local tooltipText = getLanguageOrDefault(layersDescriptions[layer])

        local layerBlank = layersWithBlankIcon[layer]
        local layerVisible = loadedState.getLayerVisible(layer)
        local icon = layerVisible and "visible" or "hidden"

        if layerBlank then
            icon = "blank"
        end

        -- Layer with -1 means all layers
        local baseLayerItem = {
            text = getLayerItemName(language, layer),
            data = subLayers.formatLayerName(layer, -1),
            layerVisible = layerVisible,
            tooltipText = tooltipText,
            baseLayer = layer,
            subLayer = -1,
            icon = icon,
            iconClicked = layerItemToggleVisibilityHandler,
        }

        table.insert(layerItems, baseLayerItem)

        if layersWithSubLayers[layer] then
            -- Convert from lookup table into sorted list
            local subLayerNames = table.keys(allSubLayers[layer] or {})

            table.sort(subLayerNames)

            if #subLayerNames > 0 then
                for _, subLayer in ipairs(subLayerNames) do
                    local layerName = subLayers.formatLayerName(layer, subLayer)
                    local subLayerVisible = loadedState.getLayerVisible(layerName)
                    local subItem = {
                        text = getLayerItemName(language, layer, subLayer),
                        data = layerName,
                        layerVisible = subLayerVisible,
                        tooltipText = tooltipText,
                        baseLayer = layer,
                        subLayer = subLayer,
                        icon = subLayerVisible and "visible" or "hidden",
                        iconClicked = layerItemToggleVisibilityHandler,
                    }

                    table.insert(layerItems, subItem)
                end

                -- Base group and one sub layer, remove the base layer but keep its base text
                if #subLayerNames == 1 then
                    local currentItem = layerItems[#layerItems]

                    currentItem.text = getLayerItemName(language, layer)

                    table.remove(layerItems, #layerItems - 1)
                end
            end
        end
    end

    return layerItems
end

local function deleteSubLayerInfo(layer, subLayer)
    local layerInfo = toolWindow.subLayers[layer]

    if layerInfo and layerInfo[subLayer] then
        layerInfo[subLayer] = nil

        -- Check if we only have a single layer left and notify the user
        local layerCount = utils.countKeys(layerInfo)

        if layerCount == 0 or layerCount == 1 then
            local language = languageRegistry.getLanguage()
            local existingLayerIndex = next(layerInfo)
            local layerName = getLayerItemName(language, layer, existingLayerIndex, true, true)

            notifications.notify(
                string.format(tostring(language.ui.tools_window.remove_last_sub_layer), layerName),
                nil,
                {clickToClose = true}
            )
        end
    end
end

local function deleteSubLayer(layer, subLayer)
    local map = loadedState.map
    local snapshot, relevantRooms = selectionUtils.deleteSubLayer(map, layer, subLayer)

    if snapshot then
        history.addSnapshot(snapshot)

        for _, room in ipairs(relevantRooms) do
            toolUtils.redrawTargetLayer(room, layer)
            celesteRender.invalidateRoomCache(room, {"canvas", "complete"})
        end

        return true
    end
end

local function addSubLayerInfo(layer, subLayer)
    if not layersWithSubLayers[layer] then
        return
    end

    if not toolWindow.subLayers[layer] then
        toolWindow.subLayers[layer] = {}
    end

    local layerInfo = toolWindow.subLayers[layer]
    local layerCount = #layerInfo
    local layerKeysCount = utils.countKeys(layerInfo)
    local shouldNotifyUser = layerKeysCount == 0 or layerKeysCount == 1

    if shouldNotifyUser then
        local language = languageRegistry.getLanguage()
        local existingLayerIndex = next(layerInfo)
        local layerName = getLayerItemName(language, layer, existingLayerIndex, true, true)

        notifications.notify(
            string.format(tostring(language.ui.tools_window.add_first_sub_layer), layerName),
            nil,
            {clickToClose = true}
        )
    end

    -- Special case for when no editor layers are found at all
    if layerCount == 0 then
        layerInfo[0] = 0
        layerInfo[1] = 1

        return 1
    end

    -- Find first empty layer index
    for i = 0, layerCount + 1 do
        if not layerInfo[i] then
            layerInfo[i] = i

            return i
        end
    end
end

local function layerListInlineRename(layer, subLayer, layerListItem)
    -- Remove the label and insert a textfield in its place
    local oldLabel = layerListItem.label
    local icon = layerListItem.children[1]

    local language = languageRegistry.getLanguage()
    local initialText = getLayerItemName(language, layer, subLayer, true)

    local function layout()
        layerListItem:layout()
        layerListItem:layoutLate()
        layerListItem.parent:layout()
        layerListItem.parent:layoutLate()
    end

    local function unfocusCleanup(field)
        -- Remove field and readd the label
        field:removeSelf()
        layerListItem:addChild(oldLabel)

        layout()
    end

    -- Fill width doesn't work, do some rough calculations
    local fieldWidth = layerListItem.width - icon.width - layerListItem.style.spacing * 3
    local field = uiElements.field(initialText, function(_, text)
        oldLabel.text = getLayerItemName(language, layer, subLayer)
        subLayers.setLayerName(layer, subLayer, text)
    end):with({
        style = {
            padding = 0,
            spacing = 0,
        }
    }):hook({
        onKeyRelease = function(orig, self, key, ...)
            if key == "return" or key == "escape" then
                return unfocusCleanup(self)
            end

            return orig(self, key, ...)
        end,
        onUnfocus = function(_, self)
            unfocusCleanup(self)
        end,
    }):with({
        width = fieldWidth
    })

    table.remove(layerListItem.children)
    table.insert(layerListItem.children, field)

    widgetUtils.focusElement(field)
    field.index = utf8.len(initialText)

    layout()
end

local function layerContextMenuClickHandler(layer, subLayer, layerListItem)
    return function(element, action)
        local updateList = false
        local listTarget

        if action == "add" then
            local newSubLayer = addSubLayerInfo(layer, subLayer)

            if newSubLayer then
                listTarget = subLayers.formatLayerName(layer, newSubLayer)
                updateList = true
            end

        elseif action == "delete" then
            deleteSubLayer(layer, subLayer)
            deleteSubLayerInfo(layer, subLayer)

            listTarget = layer
            updateList = true

        elseif action == "rename" then
            layerListInlineRename(layer, subLayer, layerListItem)
        end

        if updateList then
            toolWindow.layerList:updateItems(getLayerItems(), listTarget)
        end

        element.parent.parent:removeSelf()
    end
end

local function layerContextMenu(listItem)
    local layerName = listItem.data

    if not layerName then
        return
    end

    local layer, subLayer = subLayers.parseLayerName(layerName)

    if not layersWithSubLayers[layer] then
        return false
    end

    local language = languageRegistry.getLanguage()
    local listItems = {
        uiElements.listItem({
            text = tostring(language.ui.tools_window.add_sub_layer),
            data = "add"
        })
    }

    if subLayer ~= -1 then
        table.insert(listItems, uiElements.listItem({
            text = tostring(language.ui.tools_window.delete_sub_layer),
            data = "delete"
        }))

        table.insert(listItems, uiElements.listItem({
            text = tostring(language.ui.tools_window.rename_sub_layer),
            data = "rename"
        }))
    end

    local content = uiElements.column({
        uiElements.list(
            listItems,
            layerContextMenuClickHandler(layer, subLayer, listItem)
        )
    })

    return content
end

local function layerDataToElement(list, data, element)
    if not element then
        element = uiElements.listItem()

        element:layout()
    end

    if data then
        element.text = data.text
        element.data = data.data
        element.tooltipText = data.tooltip
        element.layerVisible = data.layerVisible
        element.itemData = data
        element.baseLayer = data.baseLayer
        element.subLayer = data.subLayer
    end

    return element
end

local function layerCallback(list, layerName)
    local layer, subLayer = subLayers.parseLayerName(layerName)

    local sameTool = toolWindow.eventStates.tool == toolHandler.currentToolName
    local sameLayer = toolWindow.eventStates.layer == layer
    local sameSubLayer = not sameLayer and toolWindow.eventStates.subLayer == subLayer

    if not sameLayer or not sameTool or not sameSubLayer then
        local targetMaterial = toolUtils.getPersistenceMaterial(toolHandler.currentTool, layer)

        toolWindow.eventStates.tool = toolHandler.currentToolName
        toolWindow.eventStates.layer = layer
        toolWindow.eventStates.subLayer = subLayer
        toolWindow.eventStates.searchTerm = nil
        toolWindow.eventStates.material = nil

        toolHandler.setLayer(layer, subLayer)

        if not sameLayer then
            toolWindow.materialList:updateItems(getMaterialItems(layer), targetMaterial)
        end
    end
end

local function toolLayerChangedCallback(self, tool, layer, subLayer)
    local searchText = toolUtils.getPersistenceSearch(tool, layer) or ""
    local sameLayer = toolWindow.eventStates.layer == layer
    local sameSubLayer = not sameLayer and toolWindow.eventStates.subLayer == subLayer
    local sameSearch = toolWindow.eventStates.searchTerm == searchText
    local targetMaterial = nil

    if not sameLayer then
        targetMaterial = toolUtils.getPersistenceMaterial(tool, layer)
    end

    if not sameLayer or not sameSubLayer or not sameSearch then
        local targetLayerName = subLayers.formatLayerName(layer, subLayer)

        toolWindow.eventStates.searchTerm = searchText
        toolWindow.eventStates.layer = layer
        toolWindow.eventStates.subLayer = subLayer

        toolWindow.materialList:setFilterText(searchText, true)
        toolWindow.layerList:updateItems(getLayerItems(), targetLayerName, nil, true)

        if not sameLayer then
            toolWindow.materialList:updateItems(getMaterialItems(layer), targetMaterial)
        end
    end
end

local function updateLayerList(toolName, tool, targetLayer, preventCallback)
    if not toolName then
        toolName = toolHandler.currentToolName
    end

    local items = getLayerItems(toolName)

    if toolName and not tool then
        tool = toolHandler.tools[toolName]
    end

    if tool and not targetLayer then
        targetLayer = toolUtils.getPersistenceLayer(tool)
    end

    toolWindow.layerList:updateItems(items, targetLayer, nil, preventCallback)

    local newVisible = #items > 0

    if newVisible ~= toolWindow.layerPanelVisible then
        if newVisible then
            toolWindow.leftColumn:addChild(toolWindow.layerPanel, 2)

        else
            toolWindow.layerPanel:removeSelf()

            -- Always update material list if the layer list is invisible
            -- Layer item callback will never happen and the material list will be stuck
            toolWindow.materialList:updateItems(getMaterialItems("fake_layer_name"))
        end

        toolWindow.layerPanelVisible = newVisible
    end
end

local function layerInformationChangedCallback(window, key, value)
    -- Only update if its a visibility change
    if key ~= "visible" then
        return
    end

    local toolName = toolWindow.eventStates.tool
    local layer = toolWindow.eventStates.layer
    local subLayer = toolWindow.eventStates.subLayer
    local layerName = subLayers.formatLayerName(layer, subLayer)

    updateLayerList(toolName, toolHandler.tools[toolName], layerName, true)
    widgetUtils.updateHoveredTarget()
end

local function layerAddedCallback(_, layer, subLayer)
    if not toolWindow.subLayers[layer] then
        toolWindow.subLayers[layer] = {}
    end

    toolWindow.subLayers[layer][subLayer] = subLayer
end

local function layerDeletedCallback(_, layer, subLayer)
    if toolWindow.subLayers[layer] then
        toolWindow.subLayers[layer][subLayer] = nil
    end
end

local function getModeItems(toolName)
    local language = languageRegistry.getLanguage()
    local modes = toolHandler.getModes(toolName) or {}
    local modeItems = {}

    if not toolName then
        toolName = toolHandler.currentToolName
    end

    for _, mode in pairs(modes) do
        local displayName = getLanguageOrDefault(language.tools[toolName].modes.name[mode], mode)
        local tooltipText = getLanguageOrDefault(language.tools[toolName].modes.description[mode], mode)

        local item = uiElements.listItem({
            text = displayName,
            data = mode
        })

        table.insert(modeItems, item)

        if tooltipText then
            item.tooltipText = tooltipText
        end
    end

    return modeItems
end

local function modeCallback(list, mode)
    local sameMode = mode == toolWindow.eventStates.mode

    if not sameMode then
        toolWindow.eventStates.mode = mode
        toolWindow.eventStates.layer = nil
        toolWindow.eventStates.searchTerm = ""
        toolWindow.eventStates.material = nil

        toolHandler.setMode(mode)
    end
end

local function toolModeChangedCallback(self, tool, mode)
    toolWindow.eventStates.mode = mode

    toolWindow.modeList:setSelection(mode, true)
end

local function updateToolModeList(name)
    local items = getModeItems(name)

    toolWindow.modeList:updateItems(items)

    local newVisible = #items > 0

    if newVisible ~= toolWindow.modePanelVisible then
        if newVisible then
            toolWindow.leftColumn:addChild(toolWindow.modePanel)

        else
            toolWindow.modePanel:removeSelf()
        end

        toolWindow.modePanelVisible = newVisible
    end
end

-- Tools without an explicit order (external ones from mods) sort after the built in ones
local defaultToolOrder = 1000

-- Blank rows separating the groups of tools in the tool list. They are not interactive at all:
-- no hover, no click, no selection and no keyboard navigation.
local toolSeparatorsBefore = {
    selection = true,
    debug = true
}

local function getToolSpacer()
    return uiElements.listItem({
        text = "",
        data = false
    })
end

-- The list rebuilds its rows from the items that are handed to it, so the separator rows can only
-- be made non interactive after the list was created. They look like a normal row but never react
-- to the mouse and can not be selected (click or keyboard).
local function styleToolSeparators(list)
    for _, item in ipairs(list.children or {}) do
        if item.data == false then
            item.interactive = -1
            item._enabled = false
            item.isSeparator = true

            -- Keep the regular row background. Disabled rows would be drawn darker, so the
            -- state styles are all pointed at the normal one
            local normalBG = item.style.normalBG

            item.style.disabledBG = normalBG
            item.style.hoveredBG = normalBG
            item.style.pressedBG = normalBG
            item.style.selectedBG = normalBG
        end
    end
end

local function getToolItems(sortItems)
    local language = languageRegistry.getLanguage()
    local tools = toolHandler.tools
    local toolItems = {}

    local toolNames = language.tools.name
    local toolDescriptions = language.tools.description

    for name, tool in pairs(tools) do
        local displayName = getLanguageOrDefault(toolNames[name], name)
        local tooltipText = getLanguageOrDefault(toolDescriptions[name])

        local item = uiElements.listItem({
            text = displayName,
            data = name
        })

        item.toolName = name
        item.toolOrder = tool.order or defaultToolOrder

        table.insert(toolItems, item)

        if tooltipText then
            item.tooltipText = tooltipText
        end
    end

    if sortItems ~= false then
        table.sort(toolItems, function(lhs, rhs)
            if lhs.toolOrder ~= rhs.toolOrder then
                return lhs.toolOrder < rhs.toolOrder
            end

            local lhsGroup = tools[lhs.data].group or ""
            local rhsGroup = tools[rhs.data].group or ""

            return lhsGroup == rhsGroup and lhs.text < rhs.text or lhsGroup < rhsGroup
        end)

        -- Separators are inserted after sorting, so they never take part in it
        for index = #toolItems, 1, -1 do
            if toolSeparatorsBefore[toolItems[index].toolName] then
                table.insert(toolItems, index, getToolSpacer())
            end
        end
    end

    return toolItems
end

local function toolCallback(list, toolName)
    -- Blank separator rows have no tool behind them
    if not toolName then
        return
    end

    local sameTool = toolName == toolWindow.eventStates.tool

    if not sameTool then
        toolWindow.eventStates.tool = toolName
        toolWindow.eventStates.mode = nil
        toolWindow.eventStates.searchTerm = ""
        toolWindow.eventStates.layer = nil
        toolWindow.eventStates.material = nil

        toolHandler.selectTool(toolName)
        updateLayerList(toolName, toolHandler.tools[toolName])
        updateToolModeList(toolName)
    end
end

local function toolChangedCallback(self, tool)
    toolWindow.toolList:setSelection(tool.name)
end

local function updateLayerAndPlacementsCallback(list, layer, value)
    -- We get the event before the main editor
    -- Placements for example will be out of date if we update now
    ui.runLate(function()
        toolWindow.layerList:updateItems(getLayerItems())

        if layer == toolWindow.eventStates.layer then
            toolWindow.materialList:updateItems(getMaterialItems())
        end
    end)
end

local function mapLoadedCallback(list)
    toolWindow.subLayers = loadedState.subLayers or {}
    updateLayerAndPlacementsCallback(list)
end

local function materialSearchFieldChanged(element, new, old)
    local tool = toolHandler.currentTool
    local layer = toolHandler.getLayer()

    toolUtils.setPersistenceSearch(tool, layer, new)
end

local function focusMaterialSearchHandler()
    if toolWindow.materialSearch then
        widgetUtils.focusElement(toolWindow.materialSearch)
    end
end

function toolWindow.getWindow()
    -- Update known sub layers
    toolWindow.subLayers = loadedState.subLayers or {}

    local toolListOptions = {
        initialItem = toolHandler.currentToolName
    }

    local modeListOptions = {
        initialItem = toolHandler.getMode()
    }

    local currentTool = toolHandler.currentTool
    local currentLayer = toolHandler.getLayer()
    local currentSubLayer = currentTool.subLayer
    local initialLayer = subLayers.formatLayerName(currentLayer, currentSubLayer)
    local layerListOptions = {
        initialItem = initialLayer,
        dataToElement = layerDataToElement,
        listItemDoubleClicked = layerItemToggleVisibilityHandler,
        listItemContextMenu = layerContextMenu,
        listItemContextMenuOptions = {
            mode = "focused"
        }
    }

    local materialListOptions = {
        searchBarLocation = configs.ui.lists.searchBarLocation,
        searchBarCallback = materialSearchFieldChanged,
        initialSearch = toolUtils.getPersistenceSearch(currentTool, currentLayer),
        initialItem = toolHandler.getMaterial(),
        listItemDoubleClicked = materialFavoriteDoubleClickedCallback,
        dataToElement = materialDataToElement,
        sortingFunction = materialSortFunction,
        filterItems = filterMaterialItems,
        searchScore = getMaterialScore,
        searchRawItem = true,
        searchPreprocessor = prepareMaterialSearch,
        sort = true
    }

    local toolItems = getToolItems()
    local scrolledToolList, toolList = lists.getList(toolCallback, toolItems, toolListOptions)

    styleToolSeparators(toolList)

    local modeItems = getModeItems()
    local scrolledModeList, modeList = lists.getList(modeCallback, modeItems, modeListOptions)

    local layerItems = getLayerItems()
    local scrolledLayerList, layerList = lists.getMagicList(layerCallback, layerItems, layerListOptions)

    local materialItems = getMaterialItems()
    local scrolledMaterialList, materialList, materialSearchField = lists.getMagicList(materialCallback, materialItems, materialListOptions)

    hotkeyHandler.addHotkey("global", configs.ui.hotkeys.focusMaterialSearch, focusMaterialSearchHandler)

    -- Make sure lists are visually updated
    -- This does some extra logic to hide the lists if they are empty
    ui.runLate(function()
        updateLayerList()
        updateToolModeList()
    end)

    toolWindow.toolList = toolList
    toolWindow.layerList = layerList
    toolWindow.materialList = materialList

    -- Drive the decal hover preview from the list itself (rows are recycled, so enter/leave
    -- events alone are not reliable)
    materialList:with(uiUtils.hook({
        update = function(orig, self)
            orig(self)
            updateHoverPreview(self)
        end
    }))
    toolWindow.modeList = modeList
    toolWindow.toolPanel = uiElements.panel({toolList})
    toolWindow.layerPanel = uiElements.panel({layerList})
    toolWindow.modePanel = uiElements.panel({modeList})
    toolWindow.leftColumn = uiElements.column({
        toolWindow.toolPanel,
        toolWindow.layerPanel,
        toolWindow.modePanel
    })
    toolWindow.materialSearch = materialSearchField

    local materialPanel = uiElements.panel({scrolledMaterialList}):with(uiUtils.fillHeight(false))

    -- Solid background: while a virtualized list catches up with fast scrolling there can be a
    -- frame without rows, and the window background would otherwise show through as black.
    materialPanel.style.bg = { 0.07, 0.07, 0.07, 1 }
    materialPanel.style.patch = false
    materialPanel.style.radius = 0

    -- The list area changes every frame while scrolling, so its containers must not be drawn
    -- into a cached canvas: a cache invalidated at the wrong moment shows up as a black frame
    -- when dragging the scrollbar quickly.
    materialPanel.cacheable = false
    scrolledMaterialList.cacheable = false

    local row = uiElements.row({
        toolWindow.leftColumn,
        materialPanel
    }):with(uiUtils.fillHeight(true))

    local window = uiElements.window("Tools", row):with(uiUtils.fillHeight(false))

    -- Same reason as the material panel: don't cache the window which contains the live list
    window.cacheable = false

    -- Lets overlays (notifications) know where the actual panel content starts, instead of
    -- anchoring to the window edge: the tool column in front of it is a floating list which
    -- does not reach the bottom, so the free space for overlays starts at the material list.
    window._workspaceRightElement = materialPanel

    window:with({
        editorToolChanged = toolChangedCallback,
        editorToolLayerChanged = toolLayerChangedCallback,
        editorToolMaterialChanged = toolMaterialChangedCallback,
        editorToolModeChanged = toolModeChangedCallback,
        editorMapLoaded = mapLoadedCallback,
        editorMapNew = mapLoadedCallback,
        editorShownDependenciesChanged = updateLayerAndPlacementsCallback,
        editorLayerInformationChanged = layerInformationChangedCallback,
        editorLayerAdded = layerAddedCallback,
        editorLayerDeleted = layerDeletedCallback,

        interactive = 0
    })

    window.style.bg = {}
    window.style.border = {}
    window.style.padding = row.style.spacing

    widgetUtils.removeWindowTitlebar(window)

    return simpleDocks.pinWidgetToEdge("right", window)
end

return toolWindow
