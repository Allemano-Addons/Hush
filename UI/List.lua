-- Chat list: categories and chat rows in the sidebar, virtualized with pooled rows.
local _, Hush = ...

local Theme, W, Data, Compat = Hush.Theme, Hush.Widgets, Hush.Data, Hush.Compat
local S = Theme.size

local List = {}
Hush.List = List

local area            -- Main.listArea
local items = {}      -- flat list: { kind = "cat"|"conv", y, h, id/key, ... }
local contentH = 0
local offset = 0
local rowPool, catPool
local scrollbar

local TOP_PAD = 6
local EMPTY_TEXT = {
    whispers = "No conversations yet",
    groups = "No group chats yet",
    requests = "No requests",
}

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------

-- First visible character, UTF-8 safe.
local function initial(name)
    local c = (name or "?"):match("^[%z\1-\127\194-\244][\128-\191]*") or "?"
    return strupper(c)
end

-- 24 h clock today, "Yesterday", weekday within a week, otherwise day/month.
function List.FormatTime(t)
    local now = time()
    local today = date("*t", now)
    today.hour, today.min, today.sec = 0, 0, 0
    local midnight = time(today)
    if t >= midnight then return date("%H:%M", t) end
    if t >= midnight - 86400 then return "Yesterday" end
    if t >= midnight - 6 * 86400 then return date("%a", t) end
    return date("%d/%m", t)
end

-- Name color: class color if known, otherwise normal text.
function List.NameColor(conv)
    local r, g, b = Compat.ClassColor(conv.info and conv.info.class)
    if r then return r, g, b end
    if conv.kind == "bnet" then return Theme:Color("bnet") end
    if conv.kind == "group" then return Theme:Color(conv.channel == "RAID" and "raid" or "party") end
    return Theme:Color("text")
end

-- Online dot color, or nil when unknown.
function List.StatusColor(conv)
    local info = conv.info
    if not info or info.online == nil then return nil end
    if not info.online then return Theme:Color("offline") end
    if info.status then return Theme:Color("away") end
    return Theme:Color("online")
end

local function matches(conv, query)
    if query == "" then return true end
    if strlower(conv.display):find(query, 1, true) then return true end
    for i = #conv.msgs, 1, -1 do
        local m = conv.msgs[i].m
        if m and strlower(m):find(query, 1, true) then return true end
    end
    return false
end

local function byLast(a, b) return a.last > b.last end

-- ---------------------------------------------------------------------------
-- Build the flat item list for the active tab
-- ---------------------------------------------------------------------------

local function collect()
    wipe(items)
    local tab = Hush.Main.activeTab
    local query = strlower(Hush.Main.search or "")
    local searching = query ~= ""
    local y = TOP_PAD

    local function addConv(key, conv, catId)
        items[#items + 1] = { kind = "conv", key = key, conv = conv, catId = catId, y = y, h = S.chatRowH }
        y = y + S.chatRowH
    end

    if tab == "whispers" then
        local cats = Hush.char.categories
        local byCat = {}
        for _, id in ipairs(cats.order) do byCat[id] = {} end
        for key, conv in pairs(Data.All()) do
            if Data.TabOf(conv) == "whispers" and matches(conv, query) then
                local id = conv.pinned and "pinned" or conv.category
                if not byCat[id] then id = "other" end
                local list = byCat[id]
                list[#list + 1] = { key = key, conv = conv, last = conv.last }
            end
        end
        for _, id in ipairs(cats.order) do
            local list = byCat[id]
            local cat = cats.byId[id]
            local hide = (#list == 0) and (id == "pinned" or searching)
            if not hide then
                sort(list, byLast)
                local unread = 0
                for _, e in ipairs(list) do unread = unread + e.conv.unread end
                items[#items + 1] = { kind = "cat", id = id, cat = cat, count = #list, unread = unread, y = y, h = S.categoryH }
                y = y + S.categoryH
                if not cat.collapsed or searching then
                    for _, e in ipairs(list) do addConv(e.key, e.conv, id) end
                end
            end
        end
    else
        local list = {}
        for key, conv in pairs(Data.All()) do
            if Data.TabOf(conv) == tab and matches(conv, query) then
                list[#list + 1] = { key = key, conv = conv, last = conv.last }
            end
        end
        sort(list, byLast)
        for _, e in ipairs(list) do addConv(e.key, e.conv) end
    end

    contentH = y + TOP_PAD
    local hasConvs = false
    for _, it in ipairs(items) do if it.kind == "conv" then hasConvs = true break end end
    area.empty:SetText(searching and "No matches" or EMPTY_TEXT[tab])
    area.empty:SetShown(not hasConvs)
end

-- ---------------------------------------------------------------------------
-- Rows
-- ---------------------------------------------------------------------------

local function createRow()
    local r = CreateFrame("Button", nil, area)
    r:SetHeight(S.chatRowH)
    r:RegisterForClicks("LeftButtonUp", "RightButtonUp")

    r.hover = W.Fill(r, "selected", 0.5)
    r.hover:SetAllPoints()
    r.hover:Hide()
    r.sel = W.Fill(r, "selected", 1)
    r.sel:SetAllPoints()
    r.sel:Hide()
    r.bar = r:CreateTexture(nil, "ARTWORK")
    r.bar:SetPoint("TOPLEFT")
    r.bar:SetPoint("BOTTOMLEFT")
    W.PixelSize(r.bar, r, "w", 2)
    W.OnAccent(function(cr, cg, cb) r.bar:SetColorTexture(cr, cg, cb, 1) end)

    -- Initial in a square
    r.box = CreateFrame("Frame", nil, r)
    r.box:SetSize(30, 30)
    r.box:SetPoint("LEFT", S.padding, 0)
    r.box.bg = W.Fill(r.box, "field", 1)
    r.box.bg:SetAllPoints()
    W.Border(r.box, "line")
    r.initial = W.Text(r.box, "semibold", 2)
    r.initial:SetPoint("CENTER", 0, 0)
    r.initial:SetJustifyH("CENTER")

    r.dot = r.box:CreateTexture(nil, "OVERLAY")
    r.dot:SetSize(8, 8)
    r.dot:SetPoint("BOTTOMRIGHT", 2, -2)
    r.dotRing = r.box:CreateTexture(nil, "ARTWORK", nil, 7)
    r.dotRing:SetSize(10, 10)
    r.dotRing:SetPoint("CENTER", r.dot, "CENTER")
    r.dotRing:SetColorTexture(Theme:Color("sidebar"))

    r.name = W.Text(r, "semibold", 0)
    r.name:SetPoint("TOPLEFT", r.box, "TOPRIGHT", 10, -1)

    r.time = W.Text(r, "regular", -2, "textFaint")
    r.time:SetPoint("TOPRIGHT", -S.padding, -12)
    r.time:SetJustifyH("RIGHT")
    r.name:SetPoint("TOPRIGHT", r, "TOPRIGHT", -(S.padding + 64), -12)

    r.badge = W.Badge(r)
    r.badge:SetPoint("BOTTOMRIGHT", -S.padding, 10)

    r.preview = W.Text(r, "regular", -1, "textDim")
    r.preview:SetPoint("BOTTOMLEFT", r.box, "BOTTOMRIGHT", 10, 1)
    r.preview:SetPoint("BOTTOMRIGHT", r, "BOTTOMRIGHT", -(S.padding + 36), 12)

    r:SetScript("OnEnter", function(self) self.hover:Show() end)
    r:SetScript("OnLeave", function(self) self.hover:Hide() end)
    r:RegisterForDrag("LeftButton")
    r:SetScript("OnDragStart", function(self) List.StartDrag(self.key) end)
    r:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            Hush:Fire("CONV_CONTEXT", self.key, self)
        else
            List.Select(self.key)
        end
    end)
    return r
end

local function fillRow(r, it)
    local conv = it.conv
    r.key = it.key
    r.catId = it.catId
    local selected = it.key == List.selected
    r.sel:SetShown(selected)
    r.bar:SetShown(selected)

    local nr, ng, nb = List.NameColor(conv)
    r.initial:SetText(initial(conv.display))
    r.initial:SetTextColor(nr, ng, nb)
    r.name:SetText(conv.display)
    r.name:SetTextColor(nr, ng, nb)

    local dr, dg, db = List.StatusColor(conv)
    if dr then
        r.dot:SetColorTexture(dr, dg, db, 1)
        r.dotRing:SetColorTexture(Theme:Color(selected and "selected" or "sidebar"))
    end
    r.dot:SetShown(dr ~= nil)
    r.dotRing:SetShown(dr ~= nil)

    r.time:SetText(List.FormatTime(conv.last))
    r.preview:SetText(conv.preview ~= "" and conv.preview or " ")
    r.badge:SetCount(conv.unread)
    -- Unread chats: brighter preview.
    r.preview:SetTextColor(Theme:Color(conv.unread > 0 and "text" or "textDim"))
end

local function createCat()
    local c = CreateFrame("Button", nil, area)
    c:SetHeight(S.categoryH)
    c:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    c.down = W.Icon(c, "chevronDown", 8, "-")
    c.right = W.Icon(c, "chevronRight", 8, "+")
    for _, ic in ipairs({ c.down, c.right }) do
        ic.box:ClearAllPoints()
        ic.box:SetPoint("LEFT", S.padding + 1, 0)
        ic:SetColor(Theme:Color("textFaint"))
    end
    c.label = W.Text(c, "heading", -1, "textFaint")
    c.label:SetPoint("LEFT", S.padding + 16, 0)
    c.count = W.Text(c, "regular", -2, "textFaint")
    c.count:SetPoint("LEFT", c.label, "RIGHT", 6, 0)
    c.badge = W.Badge(c)
    c.badge:SetPoint("RIGHT", -S.padding, 0)

    c:SetScript("OnEnter", function(self) self.label:SetTextColor(Theme:Color("text")) end)
    c:SetScript("OnLeave", function(self) self.label:SetTextColor(Theme:Color("textFaint")) end)
    c:SetScript("OnClick", function(self, button)
        if button == "RightButton" then
            Hush:Fire("CATEGORY_CONTEXT", self.id, self)
        else
            local cat = Hush.char.categories.byId[self.id]
            Data.SetCategoryCollapsed(self.id, not cat.collapsed)
        end
    end)
    return c
end

local function fillCat(c, it)
    c.id = it.id
    local collapsed = it.cat.collapsed and (Hush.Main.search or "") == ""
    c.down:SetShown(not collapsed)
    c.right:SetShown(collapsed)
    c.label:SetText(strupper(it.cat.name))
    c.count:SetText(it.count > 0 and tostring(it.count) or "")
    -- Collapsed categories still show their unread total.
    c.badge:SetCount(collapsed and it.unread or 0)
end

-- ---------------------------------------------------------------------------
-- Rendering and scrolling
-- ---------------------------------------------------------------------------

local function maxOffset()
    return max(0, contentH - area:GetHeight())
end

local function render()
    rowPool:ReleaseAll()
    catPool:ReleaseAll()
    local viewH = area:GetHeight()
    for _, it in ipairs(items) do
        local top = it.y - offset
        if top + it.h > 0 and top < viewH then
            local f
            if it.kind == "conv" then
                f = rowPool:Acquire()
                fillRow(f, it)
            else
                f = catPool:Acquire()
                fillCat(f, it)
            end
            f:SetPoint("TOPLEFT", area, "TOPLEFT", 0, -top)
            f:SetPoint("TOPRIGHT", area, "TOPRIGHT", 0, -top)
        end
    end
    scrollbar:Update(offset, contentH, viewH)
end

function List.SetOffset(value)
    offset = min(max(0, value), maxOffset())
    render()
end

-- Rebuild items and render. Coalesced: many events in one frame cause one refresh.
function List.Refresh()
    if not area or not Hush.Main.IsShown() then
        return
    end
    collect()
    offset = min(offset, maxOffset())
    render()
end

local pending = false
local function queueRefresh()
    if pending then return end
    pending = true
    Compat.After(0, function()
        pending = false
        List.Refresh()
    end)
end
List.QueueRefresh = queueRefresh

-- ---------------------------------------------------------------------------
-- Drag and drop between categories (Whispers tab)
-- ---------------------------------------------------------------------------

local ghost, dropHL
local drag -- { key, target }

local function buildDragFrames()
    ghost = CreateFrame("Frame", nil, UIParent)
    ghost:SetFrameStrata("TOOLTIP")
    ghost:SetSize(220, 38)
    ghost.bg = W.Fill(ghost, "selected", 0.95)
    ghost.bg:SetAllPoints()
    ghost.border = W.Border(ghost, "line")
    W.OnAccent(function(r, g, b) ghost.border:SetColor(r, g, b, 1) end)
    ghost.initial = W.Text(ghost, "semibold", 1)
    ghost.initial:SetPoint("LEFT", 12, 0)
    ghost.name = W.Text(ghost, "semibold", 0)
    ghost.name:SetPoint("LEFT", 32, 0)
    ghost:Hide()

    dropHL = CreateFrame("Frame", nil, area)
    dropHL:SetFrameLevel(area:GetFrameLevel() + 8)
    dropHL.bg = dropHL:CreateTexture(nil, "BACKGROUND")
    dropHL.bg:SetAllPoints()
    W.OnAccent(function(r, g, b) dropHL.bg:SetColorTexture(r, g, b, 0.06) end)
    dropHL.dash = W.DashedBorder(dropHL)
    dropHL:SetScript("OnSizeChanged", function(self) self.dash:Layout() end)
    dropHL:Hide()
end

-- Highlight the whole block of a category: header plus its rows.
local function highlight(catId)
    if not catId then dropHL:Hide() return end
    local top, bottom
    for _, it in ipairs(items) do
        local id = it.kind == "cat" and it.id or it.catId
        if id == catId then
            top = top or it.y
            bottom = it.y + it.h
        end
    end
    if not top then dropHL:Hide() return end
    dropHL:ClearAllPoints()
    dropHL:SetPoint("TOPLEFT", area, "TOPLEFT", 4, -(top - offset))
    dropHL:SetPoint("TOPRIGHT", area, "TOPRIGHT", -8, -(top - offset))
    dropHL:SetHeight(bottom - top)
    dropHL:Show()
end

-- Which category is under the mouse (MouseIsOver on the visible pooled frames).
local function targetUnderMouse()
    if not Compat.MouseIsOver(area) then return nil end
    for _, c in ipairs(catPool.active) do
        if Compat.MouseIsOver(c) then return c.id end
    end
    for _, r in ipairs(rowPool.active) do
        if Compat.MouseIsOver(r) then return r.catId end
    end
    return nil
end

local function finishDrag()
    if not drag then return end
    -- Reset first so an error below can never leave Hush stuck in drag mode.
    local key = drag.key
    drag = nil
    ghost:SetScript("OnUpdate", nil)
    ghost:Hide()
    dropHL:Hide()
    local target = targetUnderMouse()
    local conv = Data.Get(key)
    if not conv or not target then return end
    if target == "pinned" then
        if not conv.pinned then Data.SetPinned(key, true) end
    else
        if conv.pinned then Data.SetPinned(key, false) end
        if conv.category ~= target then Data.Move(key, target) end
    end
    List.Refresh()
end

function List.StartDrag(key)
    if Hush.Main.activeTab ~= "whispers" or (Hush.Main.search or "") ~= "" then return end
    local conv = Data.Get(key)
    if not conv then return end
    if not ghost then buildDragFrames() end
    drag = { key = key }
    W.HideTooltip()

    local r, g, b = List.NameColor(conv)
    ghost.initial:SetText(initial(conv.display))
    ghost.initial:SetTextColor(r, g, b)
    ghost.name:SetText(conv.display)
    ghost.name:SetTextColor(r, g, b)
    ghost:Show()

    -- OnUpdate only while dragging: follow the cursor, find the target, auto-scroll.
    ghost:SetScript("OnUpdate", function(self)
        if not IsMouseButtonDown("LeftButton") then
            finishDrag()
            return
        end
        local x, y = GetCursorPosition()
        local scale = self:GetEffectiveScale()
        self:ClearAllPoints()
        self:SetPoint("LEFT", UIParent, "BOTTOMLEFT", x / scale + 12, y / scale)

        local ay = y / area:GetEffectiveScale()
        if Compat.MouseIsOver(area) then
            if ay > area:GetTop() - 24 then
                List.SetOffset(offset - 8)
            elseif ay < area:GetBottom() + 24 then
                List.SetOffset(offset + 8)
            end
        end

        local target = targetUnderMouse()
        drag.target = target
        highlight(target) -- also follows auto-scrolling
    end)
end

function List.IsDragging() return drag ~= nil and ghost ~= nil and ghost:IsShown() end

-- ---------------------------------------------------------------------------
-- Selection
-- ---------------------------------------------------------------------------

function List.Select(key)
    local conv = key and Data.Get(key)
    if not conv then return end
    -- Jump to the tab the conversation lives in.
    local tab = Data.TabOf(conv)
    if Hush.Main.activeTab ~= tab then Hush.Main.SetTab(tab) end
    List.selected = key
    -- Remember where the unread messages start before marking them read.
    local firstUnread = conv.firstUnread
    Data.MarkRead(key)
    Hush:Fire("CONV_OPENED", key, conv, firstUnread)
    List.Refresh()
end

-- ---------------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------------

Hush:RegisterCallback("WINDOW_BUILT", function()
    area = Hush.Main.listArea
    area:SetClipsChildren(true)
    area:EnableMouseWheel(true)
    area:SetScript("OnMouseWheel", function(_, delta)
        List.SetOffset(offset - delta * S.chatRowH)
    end)
    area:SetScript("OnSizeChanged", function() if Hush.Main.IsShown() then List.Refresh() end end)
    rowPool = W.Pool(createRow, function(r) r.key = nil; r.hover:Hide() end)
    catPool = W.Pool(createCat)
    scrollbar = W.Scrollbar(area, List.SetOffset)
end, "List")

Hush:RegisterCallback("WINDOW_SHOWN", function() List.Refresh() end, "List")
Hush:RegisterCallback("TAB_CHANGED", function() offset = 0; List.Refresh() end, "List")
Hush:RegisterCallback("SEARCH_CHANGED", function() offset = 0; List.Refresh() end, "List")
for _, e in ipairs({ "MESSAGE_ADDED", "CONV_CREATED", "CONV_UPDATED", "CONV_MOVED", "CONV_DELETED", "UNREAD_CHANGED", "CATEGORIES_CHANGED" }) do
    Hush:RegisterCallback(e, queueRefresh, "List")
end
Hush:RegisterCallback("CONV_DELETED", function(_, key)
    if List.selected == key then List.selected = nil end
end, "List")
