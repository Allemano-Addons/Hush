-- Conversation view: compact message list with day dividers, "New" marker, system lines
-- and clickable links. Virtualized: messages are measured once, only visible ones are drawn.
local _, Hush = ...

local Theme, W, Data, Compat = Hush.Theme, Hush.Widgets, Hush.Data, Hush.Compat

local Conv = {}
Hush.Conversation = Conv

local body            -- Main.body (clipping area)
local items = {}
local contentH = 0
local offset = 0
local scrollbar
local msgPool, dayPool, newPool, sysPool
local measure         -- hidden FontString used to measure wrapped text
local current         -- key of the open conversation
local newMarker       -- msg.n of the first unread message when the conversation was opened

-- Measured heights, weak-keyed by message table so nothing ends up in SavedVariables.
local heights = setmetatable({}, { __mode = "k" })

local PAD_X = 20
local PAD_RIGHT = 28       -- room for the scrollbar
local PORTRAIT = 30
local GROUP_WINDOW = 300   -- messages from the same sender within 5 min are grouped
local DAY_H, NEW_H = 34, 22
local BPX, BPY = 10, 6          -- bubble padding
local BUBBLE_MAX = 0.72        -- bubble max width, share of the text area

-- ---------------------------------------------------------------------------
-- Layout helpers
-- ---------------------------------------------------------------------------

local function showPortraits() return Hush.settings.portraits ~= false end
local function showTimes() return Hush.settings.timestamps ~= false end
local function bubbles() return Hush.settings.msgStyle == "bubbles" end

local function textLeft()
    return PAD_X + (showPortraits() and (PORTRAIT + 12) or 0)
end

local function textWidth()
    return max(80, body:GetWidth() - textLeft() - PAD_RIGHT)
end

local function measureText(msg, width, delta)
    local size = Theme:TextSize(delta)
    local font = Theme.fonts.regular
    local c = heights[msg]
    if c and c.w == width and c.size == size and c.font == font then return c.h end
    Theme:SetFont(measure, "regular", delta)
    measure:SetWidth(width)
    measure:SetText(msg.m ~= "" and msg.m or " ")
    local h = ceil(measure:GetStringHeight())
    heights[msg] = { w = width, size = size, font = font, h = h }
    return h
end

local function dayLabel(t)
    local d = date("*t", t)
    local now = date("*t")
    if d.year == now.year and d.yday == now.yday then return "Today" end
    local y = date("*t", time() - 86400)
    if d.year == y.year and d.yday == y.yday then return "Yesterday" end
    return date("%A %d %B", t)
end

-- Sender name and color for a message.
local function senderOf(conv, m)
    if m.d == "out" then
        local r, g, b = Compat.ClassColor(Compat.PlayerClass())
        if not r then r, g, b = Theme:Color("text") end
        return Compat.PlayerName(), r, g, b
    end
    local name = m.s or conv.display
    local r, g, b = Compat.ClassColor(m.c)
    if not r then r, g, b = Hush.List.NameColor(conv) end
    return name, r, g, b
end

-- ---------------------------------------------------------------------------
-- Build item list
-- ---------------------------------------------------------------------------

local function build()
    wipe(items)
    contentH = 0
    local conv = current and Data.Get(current)
    if not conv then return end

    local width = textWidth()
    local headerH = Theme:TextSize(0) + 4
    local y = 8
    local lastDay, lastSender, lastT

    for _, m in ipairs(conv.msgs) do
        local day = date("%Y%j", m.t)
        if day ~= lastDay then
            items[#items + 1] = { kind = "day", y = y, h = DAY_H, label = dayLabel(m.t) }
            y = y + DAY_H
            lastDay, lastSender = day, nil
        end
        if newMarker and m.n == newMarker then
            items[#items + 1] = { kind = "new", y = y, h = NEW_H }
            y = y + NEW_H
            lastSender = nil
        end

        if m.d == "sys" then
            local h = measureText(m, width, -1) + 8
            items[#items + 1] = { kind = "sys", y = y, h = h, msg = m }
            y = y + h
            lastSender = nil
        else
            local sender = m.d == "out" and "\1me" or (m.s or conv.display)
            local grouped = sender == lastSender and lastT and (m.t - lastT) < GROUP_WINDOW
            local bubble = bubbles()
            local w = bubble and (floor(width * BUBBLE_MAX) - 2 * BPX) or width
            local textH = measureText(m, w, 0)
            local pad = bubble and (2 * BPY + 2) or 0
            local h = grouped and (textH + 4 + pad) or (10 + headerH + 2 + textH + 4 + pad)
            if not grouped and showPortraits() and not (bubble and m.d == "out") then h = max(h, 10 + PORTRAIT + 4) end
            items[#items + 1] = { kind = "msg", y = y, h = h, msg = m, conv = conv, grouped = grouped,
                                  textH = textH, textW = w, bubble = bubble }
            y = y + h
            lastSender, lastT = sender, m.t
        end
    end
    contentH = y + 12
end

-- ---------------------------------------------------------------------------
-- Row types
-- ---------------------------------------------------------------------------

local HYPERLINK_TOOLTIP = { item = true, spell = true, enchant = true, quest = true, talent = true, achievement = true }

local function onHyperlinkClick(_, link, text, button)
    SetItemRef(link, text, button, DEFAULT_CHAT_FRAME)
end

local function onHyperlinkEnter(self, link)
    local kind = link:match("^(%a+):")
    if kind and HYPERLINK_TOOLTIP[kind] then
        GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
        if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then
            GameTooltip:Show()
        else
            GameTooltip:Hide()
        end
    end
end

local function onHyperlinkLeave() GameTooltip:Hide() end

local function onMessageMouseUp(self, button)
    if button == "RightButton" and self.msg then
        Hush:Fire("MESSAGE_CONTEXT", current, self.msg)
    end
end

local function enableLinks(f)
    f:SetHyperlinksEnabled(true)
    -- Right-click a message: save, copy (see Menus.lua).
    f:EnableMouse(true)
    f:SetScript("OnMouseUp", onMessageMouseUp)
    f:SetScript("OnHyperlinkClick", onHyperlinkClick)
    f:SetScript("OnHyperlinkEnter", onHyperlinkEnter)
    f:SetScript("OnHyperlinkLeave", onHyperlinkLeave)
end

local function createMsg()
    local f = CreateFrame("Frame", nil, body)
    enableLinks(f)

    f.box = CreateFrame("Frame", nil, f)
    f.box:SetSize(PORTRAIT, PORTRAIT)
    f.box:SetPoint("TOPLEFT", PAD_X, -10)
    f.box.bg = W.Fill(f.box, "field", 1)
    f.box.bg:SetAllPoints()
    W.Round(f.box.bg, Theme.radius.small)
    W.RoundBorder(W.Border(f.box, "line"), Theme.radius.small)
    f.initial = W.Text(f.box, "semibold", 1)
    f.initial:SetPoint("CENTER")

    f.name = W.Text(f, "semibold", 0)
    f.time = W.Text(f, "regular", -2, "textFaint")
    f.bubble = f:CreateTexture(nil, "BACKGROUND")
    W.Round(f.bubble, 8)
    f.savedBar = f:CreateTexture(nil, "ARTWORK") -- thin accent bar on saved messages
    f.savedBar:SetWidth(2)
    f.savedBar:Hide()

    f.text = W.Text(f, "regular", 0, "text")
    f.text:SetWordWrap(true)
    if f.text.SetNonSpaceWrap then f.text:SetNonSpaceWrap(true) end
    f.text:SetJustifyV("TOP")
    return f
end

local function fillMsg(f, it)
    local m = it.msg
    f.msg = m
    local left = textLeft()
    local name, r, g, b = senderOf(it.conv, m)
    local mine = it.bubble and m.d == "out"   -- own bubbles sit on the right, without name/portrait
    local headerH = Theme:TextSize(0) + 4

    f.box:SetShown(not it.grouped and showPortraits() and not mine)
    f.name:SetShown(not it.grouped and not mine)
    f.time:SetShown(not it.grouped and showTimes())

    -- Header: name + time (compact and incoming bubbles), or only time on the right (own bubbles).
    f.time:ClearAllPoints()
    if not it.grouped then
        f.initial:SetText(strupper((name or "?"):match("^[%z\1-\127\194-\244][\128-\191]*") or "?"))
        f.initial:SetTextColor(r, g, b)
        f.name:ClearAllPoints()
        f.name:SetPoint("TOPLEFT", left, -10)
        f.name:SetText(name)
        f.name:SetTextColor(r, g, b)
        local tag = m.k == "leader" and "  ·  Leader" or m.k == "warning" and "  ·  Raid warning" or ""
        if m.saved then
            local ar, ag, ab = Theme:Accent()
            tag = tag .. ("  ·  |cff%02x%02x%02xSaved|r"):format(floor(ar * 255), floor(ag * 255), floor(ab * 255))
        end
        f.time:SetText(date("%H:%M", m.t) .. tag)
        if mine then
            f.time:SetPoint("TOPRIGHT", -PAD_RIGHT, -10)
        else
            f.time:SetPoint("LEFT", f.name, "RIGHT", 8, 0)
        end
    end

    f.savedBar:ClearAllPoints()
    f.savedBar:SetPoint("TOPRIGHT", f.text, "TOPLEFT", it.bubble and -(BPX + 4) or -8, 0)
    f.savedBar:SetPoint("BOTTOMRIGHT", f.text, "BOTTOMLEFT", it.bubble and -(BPX + 4) or -8, 0)
    f.savedBar:SetColorTexture(Theme:Accent())
    f.savedBar:SetShown(m.saved == true)

    f.text:ClearAllPoints()
    f.text:SetWidth(it.textW)
    f.text:SetHeight(it.textH)
    f.text:SetText(m.m)
    f.text:SetTextColor(Theme:Color(m.k == "gm" and "bnet" or m.k == "warning" and "warning" or "text"))

    if not it.bubble then
        f.bubble:Hide()
        if it.grouped then
            f.text:SetPoint("TOPLEFT", left, -2)
        else
            f.text:SetPoint("TOPLEFT", f.name, "BOTTOMLEFT", 0, -2)
        end
        return
    end

    -- Bubble: shrink to the text (GetStringWidth is the unwrapped width, capped at the max).
    local w = min(it.textW, ceil(f.text:GetStringWidth()) + 1)
    f.text:SetWidth(w)
    local top = it.grouped and -(2 + BPY) or -(10 + headerH + 2 + BPY)
    if mine then
        f.text:SetPoint("TOPRIGHT", -PAD_RIGHT - BPX, top)
        f.bubble:SetColorTexture(Theme:Accent())
        f.bubble:SetAlpha(0.22)
    else
        f.text:SetPoint("TOPLEFT", left + BPX, top)
        f.bubble:SetColorTexture(Theme:Color("field"))
        f.bubble:SetAlpha(1)
    end
    f.bubble:ClearAllPoints()
    f.bubble:SetPoint("TOPLEFT", f.text, "TOPLEFT", -BPX, BPY)
    f.bubble:SetPoint("BOTTOMRIGHT", f.text, "BOTTOMRIGHT", BPX, -BPY)
    f.bubble:Show()
end

local function createDay()
    local f = CreateFrame("Frame", nil, body)
    f.label = W.Text(f, "heading", -2, "textFaint")
    f.label:SetPoint("CENTER", 0, -2)
    f.left = W.Fill(f, "line", 1, "ARTWORK")
    f.left:SetPoint("LEFT", PAD_X, -2)
    f.left:SetPoint("RIGHT", f.label, "LEFT", -12, 0)
    W.PixelSize(f.left, f, "h")
    f.right = W.Fill(f, "line", 1, "ARTWORK")
    f.right:SetPoint("LEFT", f.label, "RIGHT", 12, 0)
    f.right:SetPoint("RIGHT", -PAD_RIGHT, -2)
    W.PixelSize(f.right, f, "h")
    return f
end

local function createNew()
    local f = CreateFrame("Frame", nil, body)
    f.label = W.Text(f, "heading", -2)
    f.label:SetPoint("RIGHT", -PAD_RIGHT, 0)
    f.label:SetText("NEW")
    f.line = f:CreateTexture(nil, "ARTWORK")
    f.line:SetPoint("LEFT", PAD_X, 0)
    f.line:SetPoint("RIGHT", f.label, "LEFT", -8, 0)
    W.PixelSize(f.line, f, "h")
    W.OnAccent(function(r, g, b)
        f.line:SetColorTexture(r, g, b, 1)
        f.label:SetTextColor(r, g, b)
    end)
    return f
end

local SYS_COLORS = { notfound = "danger", afk = "away", dnd = "away" }

local function createSys()
    local f = CreateFrame("Frame", nil, body)
    enableLinks(f)
    f.dot = f:CreateTexture(nil, "ARTWORK")
    f.dot:SetSize(4, 4)
    f.text = W.Text(f, "regular", -1, "textFaint")
    f.text:SetWordWrap(true)
    f.text:SetJustifyV("TOP")
    f.text:SetPoint("TOPLEFT", 0, -4)
    f.dot:SetPoint("RIGHT", f.text, "TOPLEFT", -8, -6)
    return f
end

local function fillSys(f, it)
    f.msg = it.msg
    f.text:ClearAllPoints()
    f.text:SetPoint("TOPLEFT", textLeft(), -4)
    f.text:SetWidth(textWidth())
    f.text:SetText(it.msg.m)
    f.dot:SetColorTexture(Theme:Color(SYS_COLORS[it.msg.k] or "textFaint"))
end

-- ---------------------------------------------------------------------------
-- Rendering and scrolling
-- ---------------------------------------------------------------------------

local function maxOffset()
    return max(0, contentH - body:GetHeight())
end

local function render()
    msgPool:ReleaseAll()
    dayPool:ReleaseAll()
    newPool:ReleaseAll()
    sysPool:ReleaseAll()
    local viewH = body:GetHeight()
    for _, it in ipairs(items) do
        local top = it.y - offset
        if top + it.h > 0 and top < viewH then
            local f
            if it.kind == "msg" then
                f = msgPool:Acquire()
                fillMsg(f, it)
            elseif it.kind == "day" then
                f = dayPool:Acquire()
                f.label:SetText(strupper(it.label))
            elseif it.kind == "new" then
                f = newPool:Acquire()
            else
                f = sysPool:Acquire()
                fillSys(f, it)
            end
            f:SetHeight(it.h)
            f:SetPoint("TOPLEFT", body, "TOPLEFT", 0, -top)
            f:SetPoint("TOPRIGHT", body, "TOPRIGHT", 0, -top)
        end
    end
    scrollbar:Update(offset, contentH, viewH)
end

function Conv.SetOffset(value)
    offset = min(max(0, value), maxOffset())
    render()
end

local function atBottom()
    if not body then return true end -- window not built yet
    return offset >= maxOffset() - 4
end

function Conv.ScrollToBottom()
    offset = maxOffset()
    render()
end

-- Rebuild after data or size changes. keepBottom: stay pinned to the newest message.
function Conv.Refresh(keepBottom)
    if not body or not current then return end
    build()
    if keepBottom then offset = maxOffset() else offset = min(offset, maxOffset()) end
    render()
end

-- ---------------------------------------------------------------------------
-- Open / close
-- ---------------------------------------------------------------------------

function Conv.Open(key, firstUnread)
    current = key
    newMarker = firstUnread
    body.empty:Hide()
    body.emptySub:Hide()
    build()
    offset = maxOffset()
    -- Start at the "New" marker if it would be scrolled out of view.
    if newMarker then
        for _, it in ipairs(items) do
            if it.kind == "new" then
                offset = min(offset, max(0, it.y - 24))
                break
            end
        end
    end
    render()
end

function Conv.Close()
    current, newMarker = nil, nil
    wipe(items)
    contentH, offset = 0, 0
    if body then
        render()
        body.empty:Show()
        body.emptySub:Show()
    end
end

function Conv.Current() return current end

-- Hush treats a conversation as read while it is visible.
function Hush.IsViewing(key)
    return current == key and Hush.Main.IsShown()
end

-- ---------------------------------------------------------------------------
-- Setup and events
-- ---------------------------------------------------------------------------

Hush:RegisterCallback("WINDOW_BUILT", function()
    body = Hush.Main.body
    body:SetClipsChildren(true)
    body:EnableMouseWheel(true)
    body:SetScript("OnMouseWheel", function(_, delta)
        Conv.SetOffset(offset - delta * 3 * (Theme:TextSize(0) + 6))
    end)
    body:SetScript("OnSizeChanged", function()
        if current then Conv.Refresh(atBottom()) end
    end)

    measure = body:CreateFontString(nil, "BACKGROUND")
    measure:SetWordWrap(true)
    if measure.SetNonSpaceWrap then measure:SetNonSpaceWrap(true) end
    measure:SetAlpha(0)
    measure:SetPoint("TOPLEFT", body, "TOPLEFT", -10000, 0)

    msgPool = W.Pool(createMsg)
    dayPool = W.Pool(createDay)
    newPool = W.Pool(createNew)
    sysPool = W.Pool(createSys)
    scrollbar = W.Scrollbar(body, Conv.SetOffset)
end, "Conversation")

Hush:RegisterCallback("CONV_OPENED", function(_, key, _, firstUnread) Conv.Open(key, firstUnread) end, "Conversation")

Hush:RegisterCallback("MESSAGE_ADDED", function(_, key, msg)
    if key ~= current or not Hush.Main.IsShown() then return end
    Conv.Refresh(atBottom() or msg.d == "out")
end, "Conversation")

Hush:RegisterCallback("CONV_DELETED", function(_, key)
    if key == current then Conv.Close() end
end, "Conversation")

Hush:RegisterCallback("WINDOW_SHOWN", function()
    if not current then return end
    local conv = Data.Get(current)
    if conv and conv.unread > 0 then
        -- Messages arrived while hidden: reopen so the "New" marker is placed and they are marked read.
        Hush.List.Select(current)
    else
        Conv.Refresh(atBottom())
    end
end, "Conversation")

Hush:RegisterCallback("SETTINGS_CHANGED", function(_, key)
    if key == "textSize" or key == "timestamps" or key == "portraits" or key == "msgStyle" or key == "accent"
        or key == "useClassColor" or key == "font" or key == "headingFont" then
        Conv.Refresh(atBottom())
    end
end, "Conversation")
Hush:RegisterCallback("FONTS_CHANGED", function() Conv.Refresh(atBottom()) end, "Conversation")
Hush:RegisterCallback("CONV_RENAMED", function(_, oldKey, newKey)
    if current == oldKey then
        current = newKey
        Conv.Refresh(true)
        Hush.Main.UpdateHeader(newKey)
    end
end, "Conversation")
-- A message was saved or removed: update the markers (and the saved view itself).
Hush:RegisterCallback("SAVED_CHANGED", function() if current then Conv.Refresh(atBottom()) end end, "Conversation")
