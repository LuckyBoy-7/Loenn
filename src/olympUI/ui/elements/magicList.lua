local uie = require("ui.elements.main")
local uiu = require("ui.utils")
require("ui.elements.basic")
require("ui.elements.layout")
require("ui.elements.input")


local listCommon = {
    cacheable = false,

    isList = true,
    cbOnItemClick = false,
    grow = true,
    recycledMax = 64,
    style = {
        spacing = 1,
        offscreen = 32,
        elementSize = false
    },

    init = function(self, data, dataToElement, cb)
        -- The pads only reserve scroll space: an explicit transparent background keeps them from
        -- painting a stray block over the list while scrolling
        self._padStart = uie.new({
            id = "padStart",
            cacheable = false,
            style = {bg = {}, border = {}}
        })

        self._padEnd = uie.new({
            id = "padEnd",
            cacheable = false,
            style = {bg = {}, border = {}}
        })

        uie.column.init(self, {self._padStart, self._padEnd})

        self.enabled = true
        self._selectedIndex = 0
        self.data = data
        self.dataToElement = dataToElement or self.dataToElement
        self.cb = cb
        self.currentFirst = 0
        self.currentLast = 0
        self.shrinkOnce = false

        self._rendering = {}
        self._recycled = {}
        self._dummy = false

        self:invalidate()
    end,

    dataToElement = function(self, data, el)
        if not el then
            el = uie.listItem()
        end

        el.text = tostring(data)
        el.data = data

        return el
    end,

    getSelectedData = function(self)
        return self.data[self.selectedIndex]
    end,

    setSelectedData = function(self, value)
        local data = self.data
        for i = 1, #data do
            local d = data[i]

            if d == value then
                self.selectedIndex = i
                return
            end
        end

        self.selectedIndex = 0
    end,

    getSelectedIndex = function(self)
        return self._selectedIndex
    end,

    setSelectedIndex = function(self, value, callCb)
        -- Action buttons and gap rows are not selectable: clicking one must not move the
        -- selection, and a stale selection index must not paint them as selected later.
        local item = self.data and self.data[value]

        if item and (item.isButton or item.isGap) then
            return
        end

        self._selectedIndex = value

        if callCb ~= false --[[ and not nil ]] then
            local cb = self.cb
            if cb then
                cb(self, self.data[value])
            end
        end
    end,

    getIsSelected = function(self, element)
        local item = self.data and self.data[element._magicIndex]

        if item and (item.isButton or item.isGap) then
            return false
        end

        return self.selectedIndex == element._magicIndex
    end,

    setIsSelected = function(self, element, value)
        self.selectedIndex = value and element._magicIndex or 0
    end,

    layoutLateLazy = function(self)
        self:layoutLate()
    end,

    getDummyElement = function(self)
        if #self.children > 2 then
            return self.children[2]
        end

        local el = self._dummy

        if el then
            return el
        end

        el = self.dataToElement(self, self.data[1], nil)
        el.parent = self
        el:reflow()
        el:layoutLazy()
        el:layoutLateLazy()

        self._dummy = el
        return el
    end,


    setElementSize = function(self, value)
        self.style.elementSize = value
    end,

    addChild = function(self, child, index)
        uie.default.addChild(self, child, index)

        if child._magicIndex then
            self._rendering[child._magicIndex] = child
        end
    end,

    removeChild = function(self, child)
        uie.default.removeChild(self, child)

        if child._magicIndex then
            self._rendering[child._magicIndex] = nil

            if #self._recycled < self.recycledMax then
                self._recycled[#self._recycled + 1] = child
            end
        end
    end,

    invalidate = function(self)
        local children = self.children

        while #children > 2 do
            self:removeChild(children[2])
        end

        self.currentFirst = 0
        self.currentLast = 0
        self._offsetData = nil
        self._itemOffsets = nil
        self._itemTotal = 0

        self._padStart.height = self.innerHeight
        self._padEnd.height = 0

        self.shrinkOnce = true

        self:reflow()
    end,

    updateView = function(self)
        local data = self.data
        local children = self.children
        local recycled = self._recycled

        if #data == 0 then
            while #children > 2 do
                self:removeChild(children[2])
            end

            return
        end

        local rendering = self._rendering
        local dataToElement = self.dataToElement

        local visibleFirst, visibleLast = self:getVisibleFirstLast()

        if visibleFirst == 0 and visibleLast == 0 then
            return
        end

        local currentFirst = self.currentFirst
        local currentLast = self.currentLast

        if visibleFirst == currentFirst and visibleLast == currentLast then
            return
        end

        -- print(currentFirst, currentLast, "->", visibleFirst, visibleLast)

        -- Drop rows that left the range.
        for i = currentFirst, currentLast do
            if (i < visibleFirst or i > visibleLast) and rendering[i] then
                self:removeChild(rendering[i])
            end
        end

        -- Add only the missing rows, in index order. Existing rows stay in place, so a small
        -- scroll step does not detach/re-add the whole visible range.
        for i = visibleFirst, visibleLast do
            if not rendering[i] then
                local elRecycled = recycled[#recycled]
                local el = dataToElement(self, data[i], elRecycled)
                el._magicIndex = i

                -- A recycled row was already laid out for its previous item. dataToElement can
                -- reset its height/padding to auto values, so mark it dirty explicitly; otherwise
                -- its next layoutLazy is skipped and it keeps the old (possibly -1) height, which
                -- makes the freshly bound row invisible until something else reflows it.
                el:reflow()

                -- Recycled rows can still have a cached canvas with the previous item's
                -- contents. Invalidate it now; otherwise the new row appears one frame late.
                el:repaint()

                if elRecycled and el == elRecycled then
                    recycled[#recycled] = nil
                end

                local insert = 2

                while insert <= #children - 1 and children[insert]._magicIndex < i do
                    insert = insert + 1
                end

                self:addChild(el, insert)
            end
        end

        self.currentFirst = visibleFirst
        self.currentLast = visibleLast

        self._dummy = false

        -- Apply the new rows in the same update. layoutLazy is required here: it updates the
        -- start/end padding for the new visible range before laying the children out.
        self.reflowing = true
        self:layoutLazy()
        self:layoutLate()
        self:reflow()
    end,

    update = function(self, dt)
        self:updateView()
    end,
}




local function merge(t1, t2)
    for k, v in pairs(t2) do
        if (type(v) == "table") and (type(t1[k] or false) == "table") then
            merge(t1[k], t2[k])
        else
            t1[k] = v
        end
    end
    return t1
end

uie.add("magicList", merge({
    base = "column",

    getElementSize = function(self, el)
        return self.style.elementSize or (el or self.dummyElement).height
    end,

    getItemHeight = function(self, index)
        local item = self.data and self.data[index]

        if item then
            local height = item.height or item._listHeight
                or (item.halfGap and math.max(1, math.floor(self.elementSize * 0.5)))
                or self.elementSize

            return height + (item.marginTop or 0) + (item.marginBottom or 0)
        end

        return self.elementSize
    end,

    getItemOffsets = function(self)
        if self._offsetData == self.data then
            return self._itemOffsets
        end

        local data = self.data or {}
        local spacing = self.style.spacing
        local offsets = {}
        local total = 0
        local hasMargins = false

        for i = 1, #data do
            offsets[i] = total
            total = total + self:getItemHeight(i) + spacing

            if (data[i].marginTop or 0) ~= 0 or (data[i].marginBottom or 0) ~= 0 then
                hasMargins = true
            end
        end

        offsets[#data + 1] = total
        self._offsetData = self.data
        self._itemOffsets = offsets
        self._itemTotal = total
        self._hasItemMargins = hasMargins

        return offsets
    end,

    getItemContentHeight = function(self, index)
        local item = self.data and self.data[index]

        return item and item.height or self.elementSize
    end,

    getVisibleFirstLast = function(self)
        local screenY = self.screenY
        local visibleRect = self.__cached.visibleRect
        local vt = visibleRect[2] - screenY
        local vb = visibleRect[4] - screenY

        -- UpdateView runs before draw, so __cached.visibleRect is one scroll frame behind during
        -- fast scrolling. When the list is directly inside a scrollbox, use the scrollbox's
        -- current rectangle instead so the rebuilt visible rows are already correct.
        local box = self.parent

        if box and box.inner == self then
            -- The list is the scrollbox content. Its y is the current scroll offset; using it
            -- avoids the one-frame lag of the cached visible rectangle.
            vt = -(self.y or 0)
            vb = vt + (box.height or 0)

        elseif box and box.inner and box.screenY and box.height then
            vt = box.screenY - screenY
            vb = box.screenY + box.height - screenY
        end

        local data = self.data or {}
        local count = #data
        local offscreen = self.style.offscreen

        if count == 0 or (vb - vt) <= 0 then
            return 1, math.min(count, offscreen)
        end

        if self.elementSize <= 0 then
            return 0, 0
        end

        local offsets = self:getItemOffsets()

        local function firstAt(value)
            local low, high = 1, count

            while low < high do
                local mid = math.floor((low + high) * 0.5)

                if offsets[mid] + self:getItemHeight(mid) <= value then
                    low = mid + 1
                else
                    high = mid
                end
            end

            return low
        end

        local first = math.max(1, firstAt(vt) - offscreen)
        local last = math.min(count, firstAt(vb) + offscreen)

        return first, last
    end,

    layoutLazy = function(self)
        local padStart = self._padStart
        local padEnd = self._padEnd
        local offsets = self:getItemOffsets()
        local first = self.currentFirst
        local last = self.currentLast

        padStart.height = math.max(0, offsets[first] or 0)

        if last > 0 and last <= #self.data then
            if self._hasItemMargins then
                local contentHeight = 0

                for i = first, last do
                    contentHeight = contentHeight + self:getItemContentHeight(i)
                end

                local desired = math.max(0, (self._itemTotal or 0) - self.style.spacing)
                local spacing = self.style.spacing * math.max(0, last - first + 2)

                padEnd.height = math.max(0, desired - padStart.height - contentHeight - spacing)

            else
                local endOffset = offsets[last] + self:getItemHeight(last)
                padEnd.height = math.max(0, (self._itemTotal or 0) - endOffset - self.style.spacing)
            end
        else
            -- Before the first visible range is calculated, reserve the full content height.
            -- Otherwise the list collapses to zero height and never gets a chance to render.
            padEnd.height = math.max(0, self._itemTotal or 0)
        end

        self:layout()
    end,

    layoutLateChildren = function(self)
        local children = self.children
        if children then
            local width = self.innerWidth

            if self.shrinkOnce then
                for i = 1, #children do
                    local c = children[i]
                    c.parent = self
                    c.width = -1
                    c.autoWidth = -1
                    c.reflowing = true
                    c.reflowingLate = true
                    c:layoutLazy()
                    c:layoutLateLazy()
                    c.reflowingLate = true
                end
                width = 0
                self.shrinkOnce = false
            end

            if self.grow then
                for i = 1, #children do
                    local c = children[i]
                    width = math.max(width, c.width)
                end
            end

            for i = 1, #children do
                local c = children[i]
                c.parent = self
                c.width = width
                c.autoWidth = true
                c:layoutLateLazy()
            end

            local offsets = self:getItemOffsets()

            if self._hasItemMargins then
                for i = 1, #children do
                    local c = children[i]
                    local index = c._magicIndex

                    if index then
                        local item = self.data[index]

                        c.realY = offsets[index] + (item and item.marginTop or 0)
                    end
                end
            end

            if width ~= self.innerWidth then
                self:reflow()
            end
        end
    end,
}, listCommon))


uie.add("magicListH", merge({
    base = "row",

    getElementSize = function(self, el)
        return self.style.elementSize or (el or self.dummyElement).width
    end,

    getVisibleFirstLast = function(self)
        local screenX = self.screenX
        local visibleRect = self.__cached.visibleRect
        local vl = visibleRect[1] - screenX
        local vr = visibleRect[3] - screenX

        local elementSize = self.elementSize

        if (vr - vl) <= 0 or elementSize <= 0 then
            return 0, 0
        end

        local elementSizeSpaced = elementSize + self.style.spacing
        local offscreen = self.style.offscreen

        return math.max(0, math.floor(vl / elementSizeSpaced) - offscreen) + 1, math.min(#self.data, math.ceil(vr / elementSizeSpaced) + offscreen)
    end,

    layoutLazy = function(self)
        local padStart = self._padStart
        local padEnd = self._padEnd

        local elementSize = self.elementSize
        local spacing = self.style.spacing
        local elementSizeSpaced = elementSize + spacing

        padStart.width = (self.currentFirst - 1) * elementSizeSpaced
        padEnd.width = (#self.data - self.currentLast) * elementSizeSpaced - spacing

        self:layout()
    end,

    layoutLateChildren = function(self)
        local children = self.children
        if children then
            local height = self.innerHeight

            if self.shrinkOnce then
                for i = 1, #children do
                    local c = children[i]
                    c.parent = self
                    c.height = -1
                    c.autoHeight = -1
                    c.reflowing = true
                    c.reflowingLate = true
                    c:layoutLazy()
                    c:layoutLateLazy()
                    c.reflowingLate = true
                end
                height = 0
                self.shrinkOnce = false
            end

            if self.grow then
                for i = 1, #children do
                    local c = children[i]
                    height = math.max(height, c.height)
                end
            end

            for i = 1, #children do
                local c = children[i]
                c.parent = self
                c.height = height
                c.autoHeight = true
                c:layoutLateLazy()
            end

            if height ~= self.innerHeight then
                self:reflow()
            end
        end
    end,
}, listCommon))


return uie
