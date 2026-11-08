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

-- Cached file lists of the Preview tool, keyed by asset folder
local previewToolFileCache = {}

-- Checkerboard shown when an entry has no usable image
local previewToolPlaceholder

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
        local lhsPriority = options.sourcePriority and options.sourcePriority(lhs.sourceKey) or nil
        local rhsPriority = options.sourcePriority and options.sourcePriority(rhs.sourceKey) or nil

        if lhsPriority and rhsPriority and lhsPriority ~= rhsPriority then
            return lhsPriority < rhsPriority
        end

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
-- Forward declarations: the tile list is built further down, but the row code above uses these
local getTilesetThumbnail
local thumbnailCanvasSize = 40
local thumbnailSize = 22
local thumbnailInset = thumbnailSize + 2
local thumbnailPadding = 2

local function materialDataToElement(list, data, element)
    if not element then
        element = uiElements.listItem()
    end

    if data then
        -- Button rows are actions, not materials: they only run their onPress and never take a
        -- selection or a thumbnail. Rows are recycled, so everything a material row may have left
        -- behind (thumbnail, spacer, extra height, favorite icon) is reset here.
        if data.isButton then
            if element._thumbnailBasePadding == nil then
                element._thumbnailBasePadding = element.style.padding or 4
            end

            if element._thumbnailSpacer then
                element._thumbnailSpacer:removeSelf()
                element._thumbnailSpacer = nil
            end

            element._thumbnailCanvas = nil
            element.isButton = true
            element.itemFavorited = false

            -- Button rows still take part in the hierarchy: keep the indentation below a header
            local indent = data.indent or 0
            local text = data.text or ""

            if indent > 0 and not text:find(decalPathIndent, 1, true) then
                text = string.rep(decalPathIndent, indent) .. text
            end

            element.text = text
            element.data = data
            element.tooltipText = data.tooltip
            element.itemData = data
            element.interactive = 1

            -- Tile rows are taller because of their thumbnail; every other list keeps the stock
            -- row height, otherwise the mixed heights make scrolling twitch
            local tileList = tiles.tileLayers[toolHandler.getLayer() or ""] ~= nil

            if tileList then
                element.minHeight = thumbnailSize + thumbnailPadding * 2
                element.style.padding = thumbnailPadding
                element.style.spacing = 6

            else
                element.minHeight = -1
                element.style.padding = element._thumbnailBasePadding or 4
                element.style.spacing = 4
            end

            element.style.normalBG = {0.13, 0.13, 0.13, 0.9}
            element.style.disabledBG = {0.05, 0.05, 0.05, 0.7}

            -- Rows are recycled: a header may have left the bold flag behind
            if element.label then
                element.label._bold = false
            end

            listItemUtils.clearIcon(element)

            if not element._buttonHooked then
                element._buttonHooked = true

                element:hook({
                    -- Vertical centering only: rows are laid out left aligned, so a horizontal
                    -- centering would shift the text by half of its own width and the two buttons
                    -- would end up with different left margins
                    layoutLate = function(orig, self, ...)
                        orig(self, ...)

                        local label = self.label
                        local isButton = self.itemData and self.itemData.isButton

                        if isButton and label and label.height and (self.height or 0) > 0 then
                            label.realY = math.floor((self.height - label.height) * 0.5)
                        end
                    end,

                    onPress = function(orig, self, x, y, button, ...)
                        if button == 1 and self.itemData and self.itemData.onPress then
                            self.itemData.onPress()

                            return true
                        end

                        return orig(self, x, y, button, ...)
                    end
                })
            end

            return element
        end

        element.isButton = nil
        local tileList = tiles.tileLayers[toolHandler.getLayer() or ""] ~= nil
        local indent = data.indent or 0
        local text = data.text or ""

        -- Tile lists are flat: the thumbnail already sits where the indent would be, so the
        -- text starts right after it
        if indent > 0 and not tileList then
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
        if not thumbnail and not data.isHeader and tiles.tileLayers[data.currentLayer or ""] and data.data then
            thumbnail = getTilesetThumbnail(data.currentLayer, data.data)
        end

        -- Only rows of the tile lists get the thumbnail treatment. Everything else (decals,
        -- entities, triggers, tools) keeps the stock row style and height.
        if element._thumbnailBasePadding == nil then
            element._thumbnailBasePadding = element.style.padding or 4
        end

        if tileList then
            element._thumbnailCanvas = thumbnail and thumbnail.canvas or nil
            element.style.padding = thumbnailPadding
            element.style.spacing = 6

            -- Fixed height: the magic list scrolls by a fixed element size, so every row of the
            -- tile list has to have the exact same height
            element.minHeight = thumbnailSize + thumbnailPadding * 2

        else
            element._thumbnailCanvas = nil
            element.style.padding = element._thumbnailBasePadding
            element.style.spacing = 4
            element.minHeight = -1
        end

        -- Favorited materials show up in the favorites section of the list, so the rows
        -- themselves do not draw a star any more. The icon is still cleared: rows are recycled
        -- and may have carried one before.
        listItemUtils.clearIcon(element)

        -- A fixed size spacer reserves the thumbnail space in the row flow. Every row of a tile
        -- list gets one, so rows keep the same height while they are recycled
        if element._thumbnailSpacer then
            element._thumbnailSpacer:removeSelf()
            element._thumbnailSpacer = nil
        end

        if tileList and thumbnail then
            local spacer = uiElements.new({width = thumbnailInset + 4, height = thumbnailSize})

            spacer.interactive = 0
            element:addChild(spacer, 1)
            element._thumbnailSpacer = spacer
        end

        if not element._thumbnailHooked then
            element._thumbnailHooked = true

            element:hook({
                -- The label is a row child and would sit at the top of the taller row: center it
                layoutLate = function(orig, self, ...)
                    orig(self, ...)

                    local label = self.label

                    if label and label.height and self.height then
                        label.realY = math.floor((self.height - label.height) * 0.5)
                    end
                end,

                draw = function(orig, self, ...)
                    orig(self, ...)

                    local canvas = self._thumbnailCanvas
                    local height = self.height or 0

                    -- Rows that are not laid out yet must not be drawn: a negative or zero scale
                    -- paints garbage over the list while it scrolls
                    if canvas and height > thumbnailSize then
                        local size = thumbnailSize
                        local x = self.screenX + (self._thumbnailBasePadding or 4)
                        local y = self.screenY + math.floor((height - size) * 0.5)

                        -- Restore the color: leaving it white leaks into whatever the list draws
                        -- next (scroll bar, labels), which showed up as white rows
                        local r, g, b, a = love.graphics.getColor()

                        love.graphics.setColor(1, 1, 1, 1)
                        love.graphics.draw(canvas, x, y, 0, size / thumbnailCanvasSize, size / thumbnailCanvasSize)
                        love.graphics.setColor(r, g, b, a)
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

-- Images of the Preview tool, loaded directly from the asset file and cached per path
local previewToolImages = {}
local previewToolImageOrder = {}
local previewToolImageQueued = {}
local previewToolImageQueue = {}
local previewToolPinned = {}
local previewToolImageQueueScheduled = false
local previewUrgentFile
local previewMouseX, previewMouseY
local previewMouseMovedAt = 0
local previewHoverList
local previewHoverItem
local currentPreviewItems

local updateHoverPreview

local MAX_PREVIEW_TOOL_IMAGES = 300
local MAX_CURRENT_MOD_PRELOAD = 64

-- Draws a checkerboard behind the image, so transparent or empty files still show a preview
-- frame instead of nothing
local function createPreviewCanvas(image)
    local width, height

    if image then
        width, height = image:getDimensions()
    else
        -- Big enough for the "loading..." label, otherwise the centred text is clipped
        width, height = 200, 64
    end

    local maxSize = 512
    local scale = math.min(1, maxSize / math.max(width, height))

    width = math.max(1, math.floor(width * scale))
    height = math.max(1, math.floor(height * scale))

    local canvas = love.graphics.newCanvas(width, height)

    canvas:renderTo(function()
        local cell = 8

        love.graphics.clear(0.15, 0.15, 0.15, 1)
        love.graphics.setColor(0.22, 0.22, 0.22, 1)

        for y = 0, height - 1, cell do
            for x = 0, width - 1, cell do
                if (math.floor(x / cell) + math.floor(y / cell)) % 2 == 0 then
                    love.graphics.rectangle("fill", x, y, math.min(cell, width - x), math.min(cell, height - y))
                end
            end
        end

        if image then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(image, 0, 0, 0, scale, scale)
        end
    end)

    return canvas
end

local function loadPreviewToolImage(filename)
    local cached = previewToolImages[filename]

    if cached ~= nil then
        return cached or nil
    end

    local image
    local success, result = pcall(love.graphics.newImage, filename)

    if success then
        image = result
    end

    if not image then
        -- Fallback: read the bytes and build the image from them. This can fail on paths the
        -- filesystem can not chdir into, so it must not take the whole editor down.
        local readSuccess, bytes = pcall(function()
            if filename:sub(1, 1) == "$" then
                return utils.readAll(filename, "rb", true)
            end

            -- Absolute path inside the Celeste content folder: read it with plain io, the editor
            -- filesystem changes the working directory for external files and chokes on some of
            -- these paths
            local file = io.open(filename, "rb")

            if file then
                local contents = file:read("*a")

                file:close()

                return contents
            end

            return utils.readAll(filename, "rb", false)
        end)

        if readSuccess and bytes then
            local ok, fallback = pcall(function()
                return love.graphics.newImage(love.filesystem.newFileData(bytes, "preview_tool.png"))
            end)

            if ok then
                image = fallback
            end
        end
    end

    previewToolImages[filename] = image or false
    table.insert(previewToolImageOrder, filename)

    -- Hovering and prefetching must not keep every preview image in memory forever. Pinned images
    -- (the current map mod) are always kept.
    while #previewToolImageOrder > MAX_PREVIEW_TOOL_IMAGES do
        local removed

        for index, candidate in ipairs(previewToolImageOrder) do
            if not previewToolPinned[candidate] then
                table.remove(previewToolImageOrder, index)

                if candidate ~= filename then
                    previewToolImages[candidate] = nil
                end

                removed = true

                break
            end
        end

        if not removed then
            break
        end
    end

    return image
end

local schedulePreviewToolImages

-- Decoding a large PNG on the main thread can drop a frame. Only decode while the pointer is
-- resting, so moving across the list never competes with image loading.
local function previewCursorIsIdle()
    local x, y = love.mouse.getPosition()
    local now = love.timer.getTime()

    if x ~= previewMouseX or y ~= previewMouseY then
        previewMouseX, previewMouseY = x, y
        previewMouseMovedAt = now

        return false
    end

    return now - previewMouseMovedAt >= 0.15
end

local function processPreviewToolImages()
    previewToolImageQueueScheduled = false

    -- The image under the pointer is urgent: show it as soon as possible. Everything else waits
    -- until the pointer rests, so background decoding can not cause stutter while moving.
    local nextFile = previewToolImageQueue[1]

    if nextFile ~= previewUrgentFile and not previewCursorIsIdle() then
        schedulePreviewToolImages()

        return
    end

    local filename = table.remove(previewToolImageQueue, 1)

    if filename and filename == previewUrgentFile then
        previewUrgentFile = nil
    end

    if filename then
        previewToolImageQueued[filename] = nil

        if previewToolImages[filename] == nil then
            loadPreviewToolImage(filename)
        end

        -- If the pointer is still on the same row, swap the placeholder for the real image
        if previewHoverList and previewHoverItem then
            updateHoverPreview(previewHoverList)
        end
    end

    if #previewToolImageQueue > 0 then
        schedulePreviewToolImages()
    end
end

schedulePreviewToolImages = function()
    if previewToolImageQueueScheduled or #previewToolImageQueue == 0 then
        return
    end

    previewToolImageQueueScheduled = true

    ui.runLate(processPreviewToolImages)
end

local function enqueuePreviewToolImage(filename, front)
    if not filename then
        return
    end

    if previewToolImages[filename] ~= nil then
        return
    end

    if previewToolImageQueued[filename] then
        if front then
            for index, queued in ipairs(previewToolImageQueue) do
                if queued == filename then
                    table.remove(previewToolImageQueue, index)

                    break
                end
            end

            table.insert(previewToolImageQueue, 1, filename)
            previewUrgentFile = filename
            schedulePreviewToolImages()
        end

        return
    end

    previewToolImageQueued[filename] = true

    if front then
        table.insert(previewToolImageQueue, 1, filename)
        previewUrgentFile = filename

    else
        table.insert(previewToolImageQueue, filename)
    end

    schedulePreviewToolImages()
end

local function getPreviewToolImage(filename, front)
    local cached = previewToolImages[filename]

    if cached ~= nil then
        return cached or nil
    end

    enqueuePreviewToolImage(filename, front)

    return nil
end

local function getPreviewToolPlaceholder()
    if not previewToolPlaceholder then
        -- Plain checkerboard: an empty or unloadable image still shows a preview frame
        previewToolPlaceholder = createPreviewCanvas(nil)
    end

    return previewToolPlaceholder
end

-- Applies the hovered color grading texture to the left sample window (ColorGrading layer only)
local function updateColorGradingHover(entry)
    if toolHandler.currentToolName ~= "preview" or toolHandler.getLayer() ~= "colorGrading" then
        return
    end

    require("ui.windows.colorgrading_preview").setGrade(entry and entry.file or nil)
end

updateHoverPreview = function(list)
    -- The debug list has no placements to preview
    if toolHandler.currentToolName == "debug" then
        hoverPreview.hide()
        previewHoverList = nil
        previewHoverItem = nil

        return
    end
    local hovered = ui.hovering

    while hovered and hovered ~= list and not hovered.itemData do
        hovered = hovered.parent
    end

    if not hovered or hovered == list or not hovered.itemData then
        hoverPreview.hide()
        updateColorGradingHover(nil)
        previewHoverList = nil
        previewHoverItem = nil

        return
    end

    local item = hovered.itemData

    previewHoverList = list
    previewHoverItem = item
    local material = item.data
    local content

    -- Preview tool: load the image of the hovered row directly, showing a checkerboard placeholder
    -- when it is empty or can not be loaded
    if toolHandler.currentToolName == "preview" then
        local entry = item.previewEntry

        updateColorGradingHover(entry)

        -- Rows that are not Preview entries (tool/layer rows, headers) have no preview at all
        if not entry then
            hoverPreview.hide()
            previewHoverList = nil
            previewHoverItem = nil

            return
        end

        -- Queue the hovered row first, then its neighbours: moving the pointer down the list
        -- then finds their images already loaded. Color grading LUTs are tiny, so load those
        -- directly and the preview is visible on the same hover frame as the grading result.
        local image

        if not entry.sprite and entry.file then
            if toolHandler.getLayer() == "colorGrading" then
                local cached = previewToolImages[entry.file]

                if cached == nil then
                    cached = loadPreviewToolImage(entry.file)
                end

                image = cached
            else
                image = getPreviewToolImage(entry.file, true)
            end
        end

        if not entry.sprite and currentPreviewItems and item.previewIndex then
            for offset = 1, 8 do
                for _, index in ipairs({item.previewIndex - offset, item.previewIndex + offset}) do
                    local other = currentPreviewItems[index]
                    local otherEntry = other and other.previewEntry

                    if otherEntry and otherEntry.file and not otherEntry.sprite then
                        enqueuePreviewToolImage(otherEntry.file)
                    end
                end
            end
        end

        local key = "preview:" .. tostring(item.data)
        local sprite = entry and entry.sprite

        -- Entries backed by a real file are decoded by the background queue. Only fall back to
        -- the runtime atlas for atlas-only resources, otherwise the first hover would load a
        -- whole atlas page on the main thread
        if not sprite and not entry.file and item.data then
            sprite = atlases.getResource(item.data, "Gameplay")
        end

        if sprite then
            hoverPreview.show(hovered.screenX, hovered.screenY, hovered.height, {
                key = key,
                image = sprite.image,
                quad = sprite.quad,
                layer = sprite.layer,
                width = sprite.width,
                height = sprite.height
            })

        else
            local placeholder = getPreviewToolPlaceholder()

            if not image then
                image = placeholder
            end

            hoverPreview.show(hovered.screenX, hovered.screenY, hovered.height, {
                -- Loading the image changes the key, so a placeholder is replaced by the real
                -- image as soon as the background queue has decoded it
                key = key .. (image == placeholder and ":placeholder" or ":image"),
                image = image,
                width = image:getWidth(),
                height = image:getHeight()
            })
        end

        return
    end

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
            width = thumbnailCanvasSize,
            height = thumbnailCanvasSize,
            -- A 5x5 block stays small on purpose: it is only meant as a hint next to the list
            area = thumbnailCanvasSize * thumbnailCanvasSize * 22
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

-- 5x5 tile thumbnail of a tileset, cached per layer/id
local tilesetThumbnails = {}

-- Sprites and rules changed on disk, so the cached thumbnails are stale
local function resetTilesetThumbnails()
    tilesetThumbnails = {}
end

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
        -- Air (and any tileset without an image) still gets an empty thumbnail, so its row is
        -- the same height as the others
        if id == "0" or not path then
            local emptyCanvas = love.graphics.newCanvas(thumbnailCanvasSize, thumbnailCanvasSize)

            -- Canvas contents are undefined until first rendered, which showed up as a white
            -- block while scrolling
            emptyCanvas:renderTo(function()
                love.graphics.clear(0, 0, 0, 0)
            end)

            local emptyThumbnail = {canvas = emptyCanvas}

            tilesetThumbnails[key] = emptyThumbnail

            return emptyThumbnail
        end

        tilesetThumbnails[key] = false

        return nil
    end

    local image = sprite.image

    -- Fake tile matrix: a 5x5 block surrounded by air, so the autotiler picks the corner, edge and
    -- filled center quads for it instead of one repeated tile
    local blockMatrix = {
        get = function(_, x, y)
            if x >= 0 and x <= 4 and y >= 0 and y <= 4 then
                return id
            end

            return "0"
        end
    }

    local fg = layer ~= "tilesBg"
    local canvas = love.graphics.newCanvas(thumbnailCanvasSize, thumbnailCanvasSize)

    canvas:renderTo(function()
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.setColor(1, 1, 1, 1)

        for y = 0, 4 do
            for x = 0, 4 do
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
-- Marker material of the "Add Defaults" entry in the tile list
local addDefaultsMaterial = "__loenn_add_defaults"
local onlyKeepUsedMaterial = "__loenn_only_keep_used"

-- Source groups of the tilesets that Add Defaults wrote: the rule file keeps them as comments,
-- which is the only place that information still exists (no displayName is written)
local function getRulesSourceGroups(currentLayer)
    local meta = loadedState.side and loadedState.side.meta

    if not meta then
        return {}, {}
    end

    local key = currentLayer == "tilesBg" and "BackgroundTiles" or "ForegroundTiles"
    local configured = meta[key]

    if type(configured) ~= "string" then
        return {}, {}
    end

    configured = string.gsub(configured, "%z", "")

    if configured == "" then
        return {}, {}
    end

    local filename = modHandler.commonModContent .. "/" .. utils.convertToUnixPath(configured)
    local text = utils.readAll(filename, "rb", true)

    if not text then
        return {}, {}
    end

    local groups = {}
    local source

    for line in string.gmatch(text, "[^\n]+") do
        local comment = string.match(line, "<!%-%-%s*Loenn Add Defaults:%s*(.-)%s*%-%->")

        if comment then
            source = comment
        end

        -- The path has to be read before the source is reset below: the comment sits on the line
        -- before its tileset, so the association is valid for this line
        local tilesetPath = string.match(line, '<Tileset[^>]-path%s*=%s*"([^"]*)"')

        if tilesetPath and source then
            -- The comment stores the readable mod name: keep it as the group label
            local group = string.match(source, "^(.-)%s*%(") or source
            group = string.match(group, "^%s*(.-)%s*$") or group

            if group == "" then
                group = "Celeste/Vanilla"
            end

            groups[tilesetPath] = group
        end

        -- A tileset line without a preceding comment starts the authors own tilesets
        if not comment and string.match(line, "^%s*<Tileset") then
            source = nil
        end
    end

    return groups
end

local function getTilesetItems(materials, currentTool, currentLayer, favoritesLookup, language, withActions)
    local entries = {}
    local thumbnails = {}
    local sourceGroups = getRulesSourceGroups(currentLayer)
    local tilerMeta = brushHelper.getTilerMeta(currentLayer) or {}

    -- Distinguish the three kinds of tilesets: the vanilla ones, the ones this feature imported
    -- and the ones the map author made
    local vanillaMeta = currentLayer == "tilesBg" and celesteRender.tilesMetaBgVanilla or celesteRender.tilesMetaFgVanilla
    -- The list formatter already wraps the source in brackets, so the labels themselves must not
    -- contain any
    local vanillaLabel = "Celeste/Vanilla"
    local ownLabel = "This Mod"

    -- Grouping is done by the image path, not by the id: ids are just single characters and can be
    -- reused, while the path tells where the tileset really comes from
    local vanillaPaths = {}

    for _, tileset in pairs(vanillaMeta or {}) do
        if tileset.path then
            vanillaPaths[string.gsub(tileset.path, "^tilesets/", "")] = true
        end
    end

    for _, material in ipairs(materials or {}) do
        local id = type(material) == "table" and material.name or material
        local displayName = type(material) == "table" and material.displayName or tostring(material)

        if id then
            local tileset = tilerMeta[id]
            local tilesetPath = tileset and tileset.path

            -- Tileset meta paths are prefixed with "tilesets/", the rule file paths are not
            local rulePath = tilesetPath and string.gsub(tilesetPath, "^tilesets/", "")
            local modName

            -- Grouping by path: vanilla path = vanilla tileset, a path recorded by Add Defaults
            -- belongs to that source, everything else was made by the map author
            if not rulePath or vanillaPaths[rulePath] then
                modName = vanillaLabel

            else
                modName = sourceGroups[rulePath]

                if not modName then
                    modName = string.match(displayName, "^([^/]+)/") or ownLabel
                end
            end

            table.insert(entries, {
                name = id,
                associatedMods = {modName},
                displayNameNoMods = displayName,
                tooltipText = displayName
            })

            local thumbnail = getTilesetThumbnail(currentLayer, id)

            if thumbnail then
                thumbnails[id] = thumbnail
            end
        end
    end

    -- Vanilla first, this mod second, then the preferred material packs and everything else
    local groupPriority = {
        ["celeste/vanilla"] = 0,
        ["this mod"] = 1,
        spoooky = 2,
        underdragon = 3
    }

    local function entryGroup(entry)
        local group = entry.associatedMods and entry.associatedMods[1] or ""

        return string.lower(group)
    end

    table.sort(entries, function(lhs, rhs)
        local lhsGroup = entryGroup(lhs)
        local rhsGroup = entryGroup(rhs)
        local lhsPriority = groupPriority[lhsGroup] or 100
        local rhsPriority = groupPriority[rhsGroup] or 100

        if lhsPriority ~= rhsPriority then
            return lhsPriority < rhsPriority
        end

        if lhsGroup ~= rhsGroup then
            return lhsGroup < rhsGroup
        end

        return tostring(lhs.displayNameNoMods) < tostring(rhs.displayNameNoMods)
    end)

    local items = getPathTreeItems(entries, currentTool, currentLayer, favoritesLookup, language, {
        flat = true,
        -- Vanilla first, then the tilesets of this mod, then every other source alphabetically
        sourcePriority = function(sourceKey)
            local lower = string.lower(sourceKey or "")

            if lower == "" or lower == "celeste/vanilla" then
                return 0
            end

            if lower == "this mod" then
                return 1
            end

            return 100
        end,
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

    if not withActions then
        return items
    end

    -- Button rows: they run an action on click and are never selected
    local function refreshAfterAction(layer)
        resetTilesetThumbnails()
        toolWindow.materialList:updateItems(getMaterialItems(layer))
    end

    local addDefaultsItem = {
        text = tostring(language.ui.tools_window.add_defaults),
        textNoMods = "",
        data = addDefaultsMaterial,
        indent = 0,
        tooltip = tostring(language.ui.tools_window.add_defaults_description),
        isButton = true,
        sortIndex = 0,
        ancestors = {},
        onPress = function()
            local layer = toolHandler.getLayer()

            require("tileset_defaults").addDefaults(layer, function()
                refreshAfterAction(layer)
            end)
        end
    }

    table.insert(items, 1, addDefaultsItem)

    -- Entry which removes every tileset the map does not use
    local onlyKeepUsedItem = {
        text = tostring(language.ui.tools_window.only_keep_used),
        textNoMods = "",
        data = onlyKeepUsedMaterial,
        indent = 0,
        tooltip = tostring(language.ui.tools_window.only_keep_used_description),
        isButton = true,
        sortIndex = 0.5,
        ancestors = {},
        onPress = function()
            local layer = toolHandler.getLayer()

            require("tileset_defaults").keepUsed(layer, function()
                refreshAfterAction(layer)
            end)
        end
    }

    table.insert(items, 2, onlyKeepUsedItem)

    return items
end

-- Building the stylegrounds entries resolves display names and source mods, which is expensive:
-- keep them around so list rebuilds stay cheap
local stylegroundsMaterialsCache
local stylegroundsWindowModule

-- Files of every Preview tool folder, keyed by the copied path prefix. Building one of these lists
-- is expensive (each installed mod is walked), so it is cached and warmed up in the background.
local previewFolders = {
    bg = {path = "Graphics/Atlases/Gameplay/bgs", prefix = "bgs"},
    collectables = {path = "Graphics/Atlases/Gameplay/collectables", prefix = "collectables"},
    danger = {path = "Graphics/Atlases/Gameplay/danger", prefix = "danger"},
    objects = {path = "Graphics/Atlases/Gameplay/objects", prefix = "objects"},
    -- Color grading files are copied by their path below Graphics/ColorGrading
    colorGrading = {path = "Graphics/ColorGrading", prefix = ""}
}

local function yieldIfPossible(counter)
    if coroutine.isyieldable() and counter % 2000 == 0 then
        coroutine.yield()
    end
end

local function ensurePreviewFiles(copyPrefix, folderPath, deferLoading)
    local files = previewToolFileCache[copyPrefix]

    if files then
        return files
    end

    files = {}

    local vanillaResources = (atlases.gameplay and atlases.gameplay.__vanillaResources) or {}
    local seenFiles = {}
    local prefix = folderPath .. "/"

    local function addFile(filename, relative, source, folderName)
        local key = source .. "|" .. relative
        local resource = copyPrefix ~= "" and (copyPrefix .. "/" .. string.gsub(relative, "%.png$", "")) or nil

        -- Provided by the game itself: handled by the vanilla pass below
        if resource and vanillaResources[resource] then
            return
        end

        if relative ~= "" and not seenFiles[key] then
            seenFiles[key] = true

            table.insert(files, {
                relative = relative,
                file = filename,
                source = source,
                folder = folderName,
                copyPath = (copyPrefix ~= "" and (copyPrefix .. "/") or "")
                    .. string.gsub(relative, "%.png$", "")
            })
        end
    end

    local modFolderNames = {}

    for modFolderName in pairs(modHandler.loadedMods or {}) do
        table.insert(modFolderNames, modFolderName)
    end

    table.sort(modFolderNames)

    for index, modFolderName in ipairs(modFolderNames) do
        local modFilenames = modHandler.findModFiletype(folderPath, "png", {modFolderName})

        if #modFilenames > 0 then
            -- Zip mods are mounted under their file name (Foo_zip): the real name comes from the
            -- mod metadata of one of its files
            local source
            local metadata = modHandler.getModMetadataFromPath(modFilenames[1])
            local modNames = metadata and modHandler.getModNamesFromMetadata(metadata)

            if modNames and modNames[1] then
                source = modNames[1]
            end

            local modInfo = modHandler.loadedMods[modFolderName]
            source = source or (modInfo and modInfo.name) or modFolderName

            for _, filename in ipairs(modFilenames) do
                local startIndex = string.find(filename, prefix, 1, true)

                if startIndex then
                    addFile(filename, filename:sub(startIndex + #prefix), source, modFolderName)
                end
            end
        end

        yieldIfPossible(index)
    end

    -- Vanilla images are part of the game content instead of a mod, so they are scanned from the
    -- Celeste directory as well
    local success, fileLocations = pcall(require, "file_locations")
    local hasLfs, lfs = pcall(require, "lib.lfs_ffi")

    if success and hasLfs then
        local vanillaFolder = utils.convertToUnixPath(utils.joinpath(fileLocations.getCelesteDir(), "Content", folderPath))

        if lfs.attributes(vanillaFolder, "mode") == "directory" then
            local vanillaPrefix = vanillaFolder .. "/"

            local function scanVanilla(directory)
                for entry in lfs.dir(directory) do
                    if entry ~= "." and entry ~= ".." then
                        local target = directory .. "/" .. entry
                        local mode = lfs.attributes(target, "mode")

                        if mode == "directory" then
                            scanVanilla(target)

                        elseif mode == "file" and utils.fileExtension(entry) == "png" then
                            addFile(target, target:sub(#vanillaPrefix + 1), "Celeste")
                        end
                    end
                end
            end

            scanVanilla(vanillaFolder)
        end
    end

    -- Vanilla resources come from the atlas snapshot: they are always listed as Celeste, even
    -- when a mod ships a file with the same path
    local covered = {}
    local resourcePrefix = copyPrefix ~= "" and (copyPrefix .. "/") or nil

    for _, entry in ipairs(files) do
        covered[string.gsub(entry.relative, "%.png$", "")] = true
    end

    if resourcePrefix then
        local counter = 0

        for resource, sprite in pairs(vanillaResources) do
            if utils.startsWith(resource, resourcePrefix) then
                local relative = resource:sub(#resourcePrefix + 1)

                if relative ~= "" and not covered[relative] then
                    covered[relative] = true

                    table.insert(files, {
                        relative = relative .. ".png",
                        sprite = sprite,
                        source = "Celeste",
                        copyPath = copyPrefix .. "/" .. relative
                    })
                end
            end

            counter = counter + 1
            yieldIfPossible(counter)
        end

        -- Everything else in the atlas that no file provided (e.g. resources only reachable
        -- through a zip mount)
        for resource, sprite in pairs(atlases.gameplay) do
            if type(sprite) == "table" and sprite.image and utils.startsWith(resource, resourcePrefix) then
                local relative = resource:sub(#resourcePrefix + 1)

                if relative ~= "" and not covered[relative] then
                    covered[relative] = true

                    local owner = getDecalOwnerModName(resource)

                    table.insert(files, {
                        relative = relative .. ".png",
                        sprite = sprite,
                        source = (owner and owner ~= "") and owner or "Celeste",
                        copyPath = copyPrefix .. "/" .. relative
                    })
                end
            end

            counter = counter + 1
            yieldIfPossible(counter)
        end
    end

    table.sort(files, function(lhs, rhs)
        if lhs.source ~= rhs.source then
            return lhs.source < rhs.source
        end

        return lhs.relative < rhs.relative
    end)

    previewToolFileCache[copyPrefix] = files

    return files
end

getMaterialItems = function(layer)
    -- A rebuilt list invalidates whatever row was hovered before
    hoverPreview.hide()
    previewHoverList = nil
    previewHoverItem = nil
    currentPreviewItems = nil

    -- Do not keep decoding preview images after switching away from the Preview tool
    if not toolHandler.currentTool or toolHandler.currentTool.name ~= "preview" then
        previewToolImageQueue = {}
        previewToolImageQueued = {}
    end

    entityPreviewCache = {}

    local currentTool = toolHandler.currentTool
    local currentLayer = layer or toolHandler.getLayer(currentTool)
    local materials = toolHandler.getMaterials(nil, layer or currentLayer)
    local materialItems = {}
    local favorites = toolUtils.getPersistenceFavorites(currentTool, currentLayer) or {}
    local favoritesLookup = table.flip(favorites)
    local language = languageRegistry.getLanguage()

    -- Stylegrounds: one entry per style kind (Parallax, Group and every registered effect), grouped
    -- by the mod they come from exactly like the trigger list.
    if currentTool and currentTool.name == "stylegrounds" then
        local effects = require("effects")
        local modHandler = require("mods")

        if not stylegroundsWindowModule then
            stylegroundsWindowModule = require("ui.windows.stylegrounds_window")
        end

        if not stylegroundsMaterialsCache then
            local materials = {}

            -- effects.associatedMods returns a list for some handlers but a plain mod name string
            -- for others; getPathTreeItems expects a list
            local function normalizeMods(mods)
                if type(mods) == "string" then
                    return {mods}
                end

                if type(mods) == "table" and #mods > 0 then
                    return mods
                end
            end

            table.insert(materials, {
                name = "parallax",
                displayNameNoMods = "Parallax"
            })

            local effectNames = {}

            for effectName in pairs(effects.registeredEffects or {}) do
                table.insert(effectNames, effectName)
            end

            table.sort(effectNames)

            for _, effectName in ipairs(effectNames) do
                local style = {_name = effectName}
                local handler = effects.registeredEffects[effectName]
                local mods = normalizeMods(effects.associatedMods(style))

                -- Handlers whose metadata could not be resolved still know the file they were
                -- loaded from: "$<mod folder>$/Loenn/effects/..."
                if not mods and handler and handler._loadedFrom then
                    local folderName = string.match(handler._loadedFrom, "^%$([^%$]+)%$")

                    if folderName then
                        local modInfo = modHandler.loadedMods and modHandler.loadedMods[folderName]

                        mods = {modInfo and modInfo.name or folderName}
                    end
                end

                local displayName = tostring(effects.displayName(language, style))
                local modsString = modHandler.formatAssociatedMods(language, mods)

                -- The source is shown by the header, so strip it from the entry text
                if modsString and modsString ~= "" then
                    local literal = string.gsub(modsString, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")

                    displayName = string.gsub(displayName, "%s*" .. literal .. "%s*$", "")
                end

                table.insert(materials, {
                    name = "effect:" .. effectName,
                    effectName = effectName,
                    displayNameNoMods = displayName,
                    associatedMods = mods
                })
            end

            stylegroundsMaterialsCache = materials
        end

        local items = getPathTreeItems(stylegroundsMaterialsCache, currentTool, currentLayer,
            favoritesLookup, language, {
                flat = true,
                leafText = function(entry)
                    return entry.displayName
                end,
                searchText = function(entry)
                    return entry.displayName
                end,
                favoritesText = function(entry)
                    return entry.displayName
                end
            })

        -- Rows stay action buttons: clicking adds a style instead of selecting the row
        for _, item in ipairs(items) do
            if not item.isSource and not item.isFavoritesHeader and item.data then
                local key = tostring(item.data)
                local effectName = string.match(key, "^effect:(.+)$")
                local kind = effectName and "effect" or key

                item.isButton = true
                item.onPress = function()
                    stylegroundsWindowModule.addStyleOfType(kind, effectName)
                end
            end
        end

        currentPreviewItems = items

        -- Current map mod first: those previews are ready by the time the list is browsed,
        -- everything else is queued while hovering
        if currentModKey then
            local preloaded = 0

            for _, item in ipairs(items) do
                local entry = item.previewEntry

                if entry and entry.file and not entry.sprite and entry.source
                    and string.lower(entry.source) == currentModKey then
                    previewToolPinned[entry.file] = true

                    enqueuePreviewToolImage(entry.file)

                    preloaded = preloaded + 1

                    if preloaded >= MAX_CURRENT_MOD_PRELOAD then
                        break
                    end
                end
            end
        end

        -- Everything else warms up slowly while the pointer is idle; hovered rows are promoted
        -- to the front of the queue
        for _, item in ipairs(items) do
            local entry = item.previewEntry

            if entry and entry.file and not entry.sprite then
                enqueuePreviewToolImage(entry.file)
            end
        end

        -- No fixed row height here: this list mixes source headers and normal rows. A leftover
        -- elementSize from the tile list makes the scroll position twitch.
        if toolWindow.materialList then
            toolWindow.materialList.style.elementSize = false
        end

        return items
    end

    -- Scripts tool: one row per registered script. Scripts run on the selected scope, or open a
    -- configuration panel first when they define fields
    if currentTool and currentTool.name == "scripts" then
        local registry = require("scripts.registry")
        local items = {}

        for _, script in ipairs(registry.getScripts()) do
            table.insert(items, {
                text = script.title,
                textNoMods = script.title,
                data = script.name,
                tooltip = script.description
            })
        end

        if toolWindow.materialList then
            toolWindow.materialList.style.elementSize = false
        end

        return items
    end

    -- Preview tool: every image of the selected asset folder, grouped by sub folder. Rows are
    -- action buttons that copy the path relative to the folder (without the file extension).
    if currentTool and currentTool.name == "preview" then
        -- A new folder/layer invalidates the old warmup queue
        previewToolImageQueue = {}
        previewToolImageQueued = {}
        previewToolPinned = {}

        -- path: folder that is scanned, prefix: what the copied path starts with (the folder is
        -- relative to Graphics/Atlases/Gameplay)
        local folders = {
            bg = {path = "Graphics/Atlases/Gameplay/bgs", prefix = "bgs"},
            collectables = {path = "Graphics/Atlases/Gameplay/collectables", prefix = "collectables"},
            danger = {path = "Graphics/Atlases/Gameplay/danger", prefix = "danger"},
            objects = {path = "Graphics/Atlases/Gameplay/objects", prefix = "objects"},
            -- Color grading files are copied by their path below Graphics/ColorGrading
            colorGrading = {path = "Graphics/ColorGrading", prefix = ""}
        }

        local folderInfo = folders[currentLayer] or folders.bg
        local copyPrefix = folderInfo.prefix

        -- Resources the game itself provides. A mod that ships the same path must not make
        -- vanilla assets look like they come from that mod.
        local vanillaResources = (atlases.gameplay and atlases.gameplay.__vanillaResources) or {}

        -- Walk every loaded mod on its own: that way the source of a file is known from the
        -- folder being scanned instead of being guessed from a shared mount point
        local files = previewToolFileCache[copyPrefix]

        if not files then
            files = {}

            local seenFiles = {}
            local prefix = folderInfo.path .. "/"

            local function addFile(filename, relative, source, folderName)
                local key = source .. "|" .. relative
                local resource = copyPrefix ~= "" and (copyPrefix .. "/" .. string.gsub(relative, "%.png$", "")) or nil

                -- Provided by the game itself: handled by the vanilla pass below
                if resource and vanillaResources[resource] then
                    return
                end

                if relative ~= "" and not seenFiles[key] then
                    seenFiles[key] = true

                    table.insert(files, {
                        relative = relative,
                        file = filename,
                        source = source,
                        folder = folderName,
                        copyPath = (copyPrefix ~= "" and (copyPrefix .. "/") or "")
                            .. string.gsub(relative, "%.png$", "")
                    })
                end
            end

            local modFolderNames = {}

            for modFolderName in pairs(modHandler.loadedMods or {}) do
                table.insert(modFolderNames, modFolderName)
            end

            table.sort(modFolderNames)

            for _, modFolderName in ipairs(modFolderNames) do
                local modFilenames = modHandler.findModFiletype(folderInfo.path, "png", {modFolderName})

                if #modFilenames > 0 then
                    -- Zip mods are mounted under their file name (Foo_zip): the real name comes
                    -- from the mod metadata of one of its files
                    local source
                    local metadata = modHandler.getModMetadataFromPath(modFilenames[1])
                    local modNames = metadata and modHandler.getModNamesFromMetadata(metadata)

                    if modNames and modNames[1] then
                        source = modNames[1]
                    end

                    local modInfo = modHandler.loadedMods[modFolderName]
                    source = source or (modInfo and modInfo.name) or modFolderName

                    for _, filename in ipairs(modFilenames) do
                        local startIndex = string.find(filename, prefix, 1, true)

                        if startIndex then
                            addFile(filename, filename:sub(startIndex + #prefix), source, modFolderName)
                        end
                    end
                end
            end

            -- Vanilla images are part of the game content instead of a mod, so they are scanned
            -- from the Celeste directory as well
            local success, fileLocations = pcall(require, "file_locations")
            local hasLfs, lfs = pcall(require, "lib.lfs_ffi")

            if success and hasLfs then
                local vanillaFolder = utils.convertToUnixPath(utils.joinpath(fileLocations.getCelesteDir(), "Content", folderInfo.path))

                if lfs.attributes(vanillaFolder, "mode") == "directory" then
                    local vanillaPrefix = vanillaFolder .. "/"

                    local function scanVanilla(directory)
                        for entry in lfs.dir(directory) do
                            if entry ~= "." and entry ~= ".." then
                                local target = directory .. "/" .. entry
                                local mode = lfs.attributes(target, "mode")

                                if mode == "directory" then
                                    scanVanilla(target)

                                elseif mode == "file" and utils.fileExtension(entry) == "png" then
                                    addFile(target, target:sub(#vanillaPrefix + 1), "Celeste")
                                end
                            end
                        end
                    end

                    scanVanilla(vanillaFolder)
                end
            end

            -- Vanilla resources come from the atlas snapshot: they are always listed as Celeste,
            -- even when a mod ships a file with the same path
            local covered = {}
            local resourcePrefix = copyPrefix ~= "" and (copyPrefix .. "/") or nil

            for _, entry in ipairs(files) do
                covered[string.gsub(entry.relative, "%.png$", "")] = true
            end

            if resourcePrefix then
                for resource, sprite in pairs(vanillaResources) do
                    if utils.startsWith(resource, resourcePrefix) then
                        local relative = resource:sub(#resourcePrefix + 1)

                        if relative ~= "" and not covered[relative] then
                            covered[relative] = true

                            table.insert(files, {
                                relative = relative .. ".png",
                                sprite = sprite,
                                source = "Celeste",
                                copyPath = copyPrefix .. "/" .. relative
                            })
                        end
                    end
                end

                -- Everything else in the atlas that no file provided (e.g. resources only
                -- reachable through a zip mount)
                for resource, sprite in pairs(atlases.gameplay) do
                    if type(sprite) == "table" and sprite.image and utils.startsWith(resource, resourcePrefix) then
                        local relative = resource:sub(#resourcePrefix + 1)

                        if relative ~= "" and not covered[relative] then
                            covered[relative] = true

                            local owner = getDecalOwnerModName(resource)

                            table.insert(files, {
                                relative = relative .. ".png",
                                sprite = sprite,
                                source = (owner and owner ~= "") and owner or "Celeste",
                                copyPath = copyPrefix .. "/" .. relative
                            })
                        end
                    end
                end
            end

            table.sort(files, function(lhs, rhs)
                if lhs.source ~= rhs.source then
                    return lhs.source < rhs.source
                end

                return lhs.relative < rhs.relative
            end)

            previewToolFileCache[copyPrefix] = files
        end

        -- Images are loaded on hover (see updateHoverPreview), nothing has to be prepared here

        -- Animation frames (test00.png, test01.png, ...) are only listed by their first frame
        local keptFrames = {}
        local frameKeys = {}

        for _, entry in ipairs(files) do
            local stem = string.gsub(entry.relative, "%.png$", "")
            local prefix, number = string.match(stem, "^(.-)(%d%d+)$")
            local baseName = string.match(stem, "([^/]*)$")

            if baseName and baseName:match("^%d+$") then
                -- File names that are only numbers are animation frame exports (00.png, 00000011.png,
                -- ...). They are not useful on their own, so they are not listed.

            elseif prefix and number and baseName ~= "" then
                -- test00 / test01 ... only the first frame is listed, per source
                local key = entry.source .. "|" .. prefix .. "#" .. #number
                local frame = tonumber(number)
                local existing = frameKeys[key]

                if not existing or frame < existing.frame then
                    frameKeys[key] = {
                        frame = frame,
                        entry = entry
                    }
                end

            else
                table.insert(keptFrames, entry)
            end
        end

        for _, frameEntry in pairs(frameKeys) do
            table.insert(keptFrames, frameEntry.entry)
        end

        table.sort(keptFrames, function(lhs, rhs)
            return lhs.relative < rhs.relative
        end)

        -- Exactly like the decal list: build materials and let getPathTreeItems group them by
        -- source mod and folder hierarchy
        local previewMaterials = {}
        local previewFiles = {}

        for _, entry in ipairs(keptFrames) do
            local copyPath = entry.copyPath
                or ((copyPrefix ~= "" and (copyPrefix .. "/") or "") .. string.gsub(entry.relative, "%.png$", ""))
            local displayName = string.match(entry.relative, "[^/]+$") or entry.relative

            displayName = string.gsub(displayName, "%.png$", "")

            -- Vanilla files have no mod, leave associatedMods empty so they show up as Celeste
            local associatedMods = entry.source ~= "Celeste" and {entry.source} or nil

            table.insert(previewMaterials, {
                name = copyPath,
                displayNameNoMods = displayName,
                associatedMods = associatedMods
            })

            if previewFiles[copyPath] == nil or entry.source == "Celeste" then
                previewFiles[copyPath] = entry
            end
        end

        -- The mod that owns the current map is listed right after vanilla
        local currentModName

        if loadedState.filename then
            local metadata = modHandler.getModMetadataFromPath(loadedState.filename)
            local names = metadata and modHandler.getModNamesFromMetadata(metadata)

            currentModName = names and names[1]

            if not currentModName then
                local folder = string.match(loadedState.filename, "^%$([^%$]+)%$")
                local info = folder and modHandler.loadedMods and modHandler.loadedMods[folder]

                currentModName = (info and info.name) or folder
            end
        end

        local currentModKey = currentModName and string.lower(currentModName)

        local previewItems = getPathTreeItems(previewMaterials, currentTool, currentLayer, favoritesLookup, language, {
            pathOf = function(name)
                if copyPrefix == "" then
                    return name
                end

                return name:sub(#copyPrefix + 2)
            end,
            leafText = function(entry)
                return entry.displayName
            end,
            -- Vanilla first, then the mod that owns the current map, then everything else
            sourcePriority = function(sourceKey)
                if sourceKey == "" then
                    return 1
                end

                if currentModKey and string.lower(sourceKey) == currentModKey then
                    return 2
                end

                return 3
            end
        })

        local items = previewItems

        -- Rows stay action buttons: clicking copies the path instead of selecting a material
        for index, item in ipairs(items) do
            if not item.isSource and not item.isHeader and not item.isFavoritesHeader and item.data then
                local entry = previewFiles[item.data]

                item.isButton = true
                item.tooltip = item.data
                item.previewEntry = entry
                item.previewIndex = index

                local copyPath = item.data

                item.onPress = function()
                    -- Vanilla resources are always reachable: only the path matters there
                    local isModFile = entry and entry.file and entry.file:sub(1, 1) == "$"

                    if not isModFile then
                        love.system.setClipboardText(copyPath)
                        notifications.notify(string.format(tostring(language.ui.notifications.previewPathCopied), copyPath))

                        return
                    end

                    -- Copying files needs the map to live in an unpacked mod folder
                    local tilesetDefaults = require("tileset_defaults")

                    if not tilesetDefaults.getMapModFolder() then
                        love.system.setClipboardText(copyPath)
                        notifications.notify(string.format(
                            tostring(language.ui.notifications.previewCopyInvalidMod), copyPath))

                        return
                    end

                    require("ui.windows.preview_copy_window").open({
                        copyPath = copyPath,
                        layer = currentLayer,
                        sourceFile = entry.file
                    })
                end
            end
        end

        if toolWindow.materialList then
            toolWindow.materialList.style.elementSize = false
        end

        return items
    end

    if layersWithDecalPaths[currentLayer] then
        return getPathTreeItems(materials, currentTool, currentLayer, favoritesLookup, language, {
            pathOf = function(name)
                return string.match(name, "^decals/(.*)$") or name
            end,
            resolveOwner = true
        })
    end

    -- The debug tool lists whatever is used in the map. This has to come before the tile branch:
    -- the debug tile layers must not get thumbnails, Add Defaults or Only Keep Used entries
    if currentTool and currentTool.name == "debug" then
        local isDecalLayer = currentLayer == "decalsFg" or currentLayer == "decalsBg"

        -- Decals use exactly the same tree as the placement decal list: the source mod on top,
        -- then the folder structure below "decals/". Only the leaf text carries the usage count.
        if isDecalLayer then
            return getPathTreeItems(materials, currentTool, currentLayer, favoritesLookup, language, {
                pathOf = function(name)
                    return string.match(name, "^decals/(.*)$") or name
                end,
                resolveOwner = true,
                leafText = function(entry)
                    return entry.displayName or entry.segments[#entry.segments]
                end
            })
        end

        local sourceGroups = getRulesSourceGroups(currentLayer)
        local tilerMeta = brushHelper.getTilerMeta(currentLayer) or {}
        local debugMaterials = {}

        for _, material in ipairs(materials or {}) do
            local name = type(material) == "table" and material.name or material
            local displayName = type(material) == "table" and material.displayNameNoMods or tostring(material)
            local modName = nil

            if tiles.tileLayers[currentLayer] and name then
                local tileset = tilerMeta[name]

                if tileset and tileset.path then
                    modName = sourceGroups[string.gsub(tileset.path, "^tilesets/", "")]
                end

            elseif name then
                modName = string.match(name, "^([^/]+)/")
            end

            table.insert(debugMaterials, {
                name = name,
                associatedMods = modName and {modName} or nil,
                displayNameNoMods = displayName
            })
        end

        return getPathTreeItems(debugMaterials, currentTool, currentLayer, favoritesLookup, language, {
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

    -- Tile tools list their tilesets grouped by source, with a thumbnail per entry. The special
    -- entries (Add Defaults / Only Keep Used) only make sense for the tools that actually place
    -- tiles, not for the selection tool which also works on tile layers.
    if tiles.tileLayers[currentLayer] then
        local toolName = currentTool and currentTool.name or ""
        local tilePlacingTools = {
            brush = true,
            rectangle = true,
            line = true,
            ellipse = true,
            circle = true,
            bucket = true
        }

        return getTilesetItems(materials, currentTool, currentLayer, favoritesLookup, language,
            tilePlacingTools[toolName] == true)
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
            associatedMods = material.associatedMods,
            -- Button rows run an action on click and never become the selection
            isButton = materialType == "table" and material.isButton or nil,
            onPress = materialType == "table" and material.onPress or nil
        }

        table.insert(materialItems, item)
    end

    -- The magic list scrolls by a fixed element size. Tile lists have taller rows (thumbnail),
    -- every other list keeps the stock row height.
    if toolWindow.materialList then
        toolWindow.materialList.style.elementSize = tiles.tileLayers[currentLayer]
            and (thumbnailSize + thumbnailPadding * 2)
            or false
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
    local tool = toolHandler.tools[toolName]

    -- Tools which manage their own lists (room, stylegrounds) do not list layers below the entry
    if tool and tool.hideLayers then
        return {}
    end

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

-- Tools can share the selected material between their layers (e.g. scripts: Current Room and
-- All Rooms are the same script list, switching the scope should not change the script)
local function getLayerTargetMaterial(tool, layer)
    local handler = type(tool) == "table" and tool
        or toolHandler.tools[tool or toolHandler.currentToolName]

    if handler and handler.sharedMaterialAcrossLayers then
        return toolHandler.getMaterial(handler.name)
    end

    return toolUtils.getPersistenceMaterial(tool, layer)
end

local function layerCallback(list, layerName)
    local layer, subLayer = subLayers.parseLayerName(layerName)

    local sameTool = toolWindow.eventStates.tool == toolHandler.currentToolName
    local sameLayer = toolWindow.eventStates.layer == layer
    local sameSubLayer = not sameLayer and toolWindow.eventStates.subLayer == subLayer

    if not sameLayer or not sameTool or not sameSubLayer then
        local targetMaterial = getLayerTargetMaterial(toolHandler.currentTool, layer)

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
        targetMaterial = getLayerTargetMaterial(tool, layer)
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
    stylegrounds = true,
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

    -- The magic list scrolls by a fixed element size, which getMaterialItems keeps in sync with
    -- the current layer
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
