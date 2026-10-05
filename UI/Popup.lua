-- Popup: a small window for an incoming whisper, like a phone notification you can reply
-- in. Never takes the keyboard by itself (click the field to type). Max 3 are stacked from
-- the chosen corner; the rest wait in "+N more". Fades on a timer (no OnUpdate).
local _, Hush = ...

local Theme, W, Data, Compat = Hush.Theme, Hush.Widgets, Hush.Data, Hush.Compat

local Popup = {}
Hush.Popup = Popup

local WIDTH, PAD, GAP = 320, 12, 8
local MAX_VISIBLE, MAX_LINES = 3, 3
local HOVER_GRACE = 3 -- seconds kept after the mouse leaves or the field loses focus
local AFTER_SEND = 3  -- seconds kept after you reply

local CORNERS = {
    TOPLEFT = { x = 30, y = -200 }, TOPRIGHT = { x = -30, y = -200 },
    BOTTOMLEFT = { x = 30, y = 200 }, BOTTOMRIGHT = { x = -30, y = 200 },
}

local anchor          -- invisible frame at the chosen position
local stackDown = true
local active = {}     -- visible popups, index 1 = nearest the corner
local byKey = {}
local overflow = {}   -- keys waiting for a free slot (oldest first)
local pool, more
local moveMode = false

-- ---------------------------------------------------------------------------
-- Position
-- ---------------------------------------------------------------------------

local function placeAnchor()
    local d = Hush.db.popup
    anchor:ClearAllPoints()
    if d.left and d.top then
        -- Custom position (Unlock & move): stack away from the nearest screen edge.
        stackDown = d.top > UIParent:GetHeight() / 2
        if stackDown then
            anchor:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", d.left, d.top)
        else
            anchor:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", d.left, d.bottom or (d.top - 120))
        end
    else
        local corner = Hush.settings.popupCorner or "TOPRIGHT"
        local c = CORNERS[corner] or CORNERS.TOPRIGHT
        stackDown = corner:find("TOP") ~= nil
        anchor:SetPoint(corner, UIParent, corner, c.x, c.y)
    end
end

local function layout()
    local prev
    for _, f in ipairs(active) do
        f:ClearAllPoints()
        if stackDown then
            if prev then f:SetPoint("TOP", prev, "BOTTOM", 0, -GAP) else f:SetPoint("TOP", anchor, "TOP") end
        else
            if prev then f:SetPoint("BOTTOM", prev, "TOP", 0, GAP) else f:SetPoint("BOTTOM", anchor, "BOTTOM") end
        end
        prev = f
    end
    local n = #overflow
    if n > 0 then
        more.text:SetText(("+%d more  ·  open Hush"):format(n))
        more:SetWidth(more.text:GetStringWidth() + 24)
        more:ClearAllPoints()
        if stackDown then
            if prev then more:SetPoint("TOPRIGHT", prev, "BOTTOMRIGHT", 0, -GAP) else more:SetPoint("TOP", anchor, "TOP") end
        else
            if prev then more:SetPoint("BOTTOMRIGHT", prev, "TOPRIGHT", 0, GAP) else more:SetPoint("BOTTOM", anchor, "BOTTOM") end
        end
        more:Show()
    else
        more:Hide()
    end
end

-- ---------------------------------------------------------------------------
-- Links (same behavior as the conversation view)
-- ---------------------------------------------------------------------------

local TOOLTIP_LINKS = { item = true, spell = true, enchant = true, quest = true, talent = true }

local function enableLinks(f)
    f:SetHyperlinksEnabled(true)
    f:SetScript("OnHyperlinkClick", function(_, link, text, button) SetItemRef(link, text, button, DEFAULT_CHAT_FRAME) end)
    f:SetScript("OnHyperlinkEnter", function(self, link)
        local kind = link:match("^(%a+):")
        if kind and TOOLTIP_LINKS[kind] then
            GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
            if pcall(GameTooltip.SetHyperlink, GameTooltip, link) then GameTooltip:Show() else GameTooltip:Hide() end
        end
    end)
    f:SetScript("OnHyperlinkLeave", function() GameTooltip:Hide() end)
end

-- ---------------------------------------------------------------------------
-- Timer: fade when the time is up, unless hovered or typing.
-- ---------------------------------------------------------------------------

local release

local function schedule(f, seconds)
    f.token = (f.token or 0) + 1
    local token = f.token
    Compat.After(seconds, function()
        if token ~= f.token or not f:IsShown() or moveMode then return end
        if f:IsMouseOver() or f.edit:HasFocus() then
            f.busyAt = GetTime()
            schedule(f, 1)
        elseif f.busyAt and GetTime() - f.busyAt < HOVER_GRACE then
            schedule(f, 1)
        else
            f.fadeOut:Play()
        end
    end)
end

-- ---------------------------------------------------------------------------
-- Frames
-- ---------------------------------------------------------------------------

local function send(f)
    local text = strtrim(f.edit:GetText() or "")
    local conv = f.key and Data.Get(f.key)
    if text == "" or not conv then return end
    if conv.kind == "group" and not Hush.Groups.IsActive(conv) then
        Hush:Print("This group has ended.")
        return
    end
    for _, part in ipairs(Data.SplitMessage(text)) do
        if not Compat.Send(conv, part) then
            Hush:Print("Can't reach", conv.display, "right now.")
            return
        end
    end
    f.edit:SetText("")
    f.edit:ClearFocus()
    Data.MarkRead(f.key)
    f.busyAt = nil
    schedule(f, AFTER_SEND)
end

local function create()
    local f = CreateFrame("Frame", nil, anchor)
    f:SetWidth(WIDTH)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:Hide()
    f.bg = W.Fill(f, "field", 0.97)
    f.bg:SetAllPoints()
    f.border = W.Border(f, "line")
    W.SkinPanel(f, { kind = "tooltip", hide = { f.bg }, borders = { f.border } })
    f.bar = f:CreateTexture(nil, "ARTWORK")
    f.bar:SetPoint("TOPLEFT")
    f.bar:SetPoint("BOTTOMLEFT")
    W.PixelSize(f.bar, f, "w", 2)
    W.OnAccent(function(r, g, b) f.bar:SetColorTexture(r, g, b, 1) end)
    if Theme:IsAllemano() then -- inside the rounded corners
        f.bar:ClearAllPoints()
        f.bar:SetPoint("TOPLEFT", 4, -8)
        f.bar:SetPoint("BOTTOMLEFT", 4, 8)
    end
    enableLinks(f)

    -- Name (click opens Hush on the conversation)
    f.nameBtn = CreateFrame("Button", nil, f)
    f.nameBtn:SetPoint("TOPLEFT", PAD, -10)
    f.nameBtn:SetHeight(18)
    f.name = W.Text(f.nameBtn, "semibold", 1)
    f.name:SetPoint("LEFT")
    f.nameBtn:SetScript("OnClick", function()
        if f.key then Popup.OpenInHush(f.key) end
    end)
    f.nameBtn:SetScript("OnEnter", function(self) if f.key then W.ShowTooltip(self, "Open in Hush") end end)
    f.nameBtn:SetScript("OnLeave", function() W.HideTooltip() end)

    f.time = W.Text(f, "regular", -2, "textFaint")
    f.time:SetPoint("LEFT", f.name, "RIGHT", 8, 0)

    f.close = W.IconButton(f, "close", 20, "Dismiss", function()
        if f.key then Popup.Dismiss(f.key) else f:Hide() end
    end, "x")
    f.close:SetPoint("TOPRIGHT", -6, -6)

    f.lines = {}

    f.edit = W.EditBox(f, "Reply...", 26)
    f.edit:SetPoint("BOTTOMLEFT", PAD, PAD)
    f.edit:SetPoint("BOTTOMRIGHT", -PAD, PAD)
    f.edit:SetMaxLetters(2000)
    f.edit:SetScript("OnEnterPressed", function() send(f) end)
    f.edit:HookScript("OnEditFocusLost", function() f.busyAt = GetTime() end)

    -- Fade in; fade out when done.
    f.fadeIn = f:CreateAnimationGroup()
    local a = f.fadeIn:CreateAnimation("Alpha")
    a:SetFromAlpha(0)
    a:SetToAlpha(1)
    a:SetDuration(0.2)
    f.fadeOut = f:CreateAnimationGroup()
    local b = f.fadeOut:CreateAnimation("Alpha")
    b:SetFromAlpha(1)
    b:SetToAlpha(0)
    b:SetDuration(0.4)
    f.fadeOut:SetScript("OnFinished", function()
        if f.key then release(f) else f:Hide() end
    end)
    return f
end

local function line(f, i)
    local fs = f.lines[i]
    if not fs then
        fs = W.Text(f, "regular", 0, "text")
        fs:SetWordWrap(true)
        fs:SetWidth(WIDTH - PAD * 2)
        fs:SetJustifyV("TOP")
        if fs.SetMaxLines then fs:SetMaxLines(3) end
        f.lines[i] = fs
    end
    return fs
end

-- data = { name, r, g, b, time, lines = { { text = ..., out = bool } } }
local function fill(f, data)
    f.name:SetText(data.name)
    f.name:SetTextColor(data.r, data.g, data.b)
    f.nameBtn:SetWidth(f.name:GetStringWidth() + 2)
    f.time:SetText(data.time or "")

    local y = -(10 + 18 + 6)
    for i, l in ipairs(data.lines) do
        local fs = line(f, i)
        fs:ClearAllPoints()
        fs:SetPoint("TOPLEFT", PAD, y)
        if l.sys then
            -- Same colors as the system dots in the conversation view.
            local key = l.sys == "notfound" and "danger" or (l.sys == "afk" or l.sys == "dnd") and "away" or "textFaint"
            fs:SetText(l.text)
            fs:SetTextColor(Theme:Color(key))
        elseif l.out then
            fs:SetText("|cff9aa3adYou:|r " .. l.text)
            fs:SetTextColor(Theme:Color("textDim"))
        else
            fs:SetText(l.text)
            fs:SetTextColor(Theme:Color("text"))
        end
        fs:Show()
        y = y - ceil(fs:GetStringHeight()) - 4
    end
    for i = #data.lines + 1, #f.lines do f.lines[i]:Hide() end
    f:SetHeight(-y + 8 + 26 + PAD)
end

-- The last few messages of a conversation, oldest first.
local function dataFor(key)
    local conv = Data.Get(key)
    if not conv then return nil end
    local lines = {}
    -- The newest line may be a system reply (player not found, AFK, DND): show it, so it is
    -- clear why a reply did not arrive.
    local newest = conv.msgs[#conv.msgs]
    local sysLine = newest and newest.d == "sys" and { text = newest.m, sys = newest.k or "sys", t = newest.t } or nil
    for i = #conv.msgs, 1, -1 do
        local m = conv.msgs[i]
        if m.d ~= "sys" then
            tinsert(lines, 1, { text = m.m, out = m.d == "out", t = m.t })
            if #lines >= MAX_LINES then break end
        end
    end
    if sysLine then
        if #lines >= MAX_LINES then tremove(lines, 1) end
        lines[#lines + 1] = sysLine
    end
    local r, g, b = Hush.List.NameColor(conv)
    local last = lines[#lines]
    return { name = conv.display, r = r, g = g, b = b, time = last and date("%H:%M", last.t) or "", lines = lines }
end

-- ---------------------------------------------------------------------------
-- Show / dismiss
-- ---------------------------------------------------------------------------

local function removeValue(list, value)
    for i = #list, 1, -1 do if list[i] == value then tremove(list, i) end end
end

release = function(f)
    local key = f.key
    f.token = (f.token or 0) + 1
    f.fadeIn:Stop()
    f.fadeOut:Stop()
    f.edit:ClearFocus()
    f:Hide()
    f:SetAlpha(1)
    removeValue(active, f)
    if key then byKey[key] = nil end
    f.key, f.busyAt = nil, nil
    pool[#pool + 1] = f
    -- A free slot: show the next waiting conversation.
    if #overflow > 0 and #active < MAX_VISIBLE then
        local nextKey = tremove(overflow, 1)
        layout()
        Popup.Show(nextKey)
        return
    end
    layout()
end

function Popup.Show(key)
    if not anchor then return end
    local data = dataFor(key)
    if not data then return end
    local f = byKey[key]
    if f then
        -- Same person again: update in place and restart the timer.
        fill(f, data)
        f.fadeOut:Stop()
        f:SetAlpha(1)
        f.busyAt = nil
        schedule(f, Hush.settings.popupDuration or 8)
        return
    end
    if #active >= MAX_VISIBLE then
        removeValue(overflow, key)
        overflow[#overflow + 1] = key
        layout()
        return
    end
    f = tremove(pool) or create()
    f.key = key
    byKey[key] = f
    fill(f, data)
    tinsert(active, 1, f)
    layout()
    f:Show()
    f.fadeIn:Play()
    schedule(f, Hush.settings.popupDuration or 8)
end

function Popup.Dismiss(key)
    local f = byKey[key]
    if f then release(f) end
    removeValue(overflow, key)
    layout()
end

function Popup.DismissAll()
    for i = #active, 1, -1 do
        local f = active[i]
        f.token = (f.token or 0) + 1
        f:Hide()
        f.key = nil
        pool[#pool + 1] = f
    end
    wipe(active)
    wipe(byKey)
    wipe(overflow)
    if more then more:Hide() end
end

function Popup.OpenInHush(key)
    Popup.Dismiss(key)
    Hush.Main.Show()
    if Data.Get(key) then Hush.List.Select(key) end
end

-- Whether an incoming message should pop up.
local function wanted(key, conv)
    local s = Hush.settings
    if s.incomingAction ~= "popup" or Compat.InCombat() then return false end
    if conv.kind == "group" then
        if not s.popupGroups then return false end
    elseif conv.kind ~= "whisper" and conv.kind ~= "bnet" then
        return false
    end
    if conv.request and not s.popupRequests then return false end
    if Hush.Data.IsMuted(conv) then return false end -- muted: no popup
    -- Already reading it in Hush.
    if Hush.Main.IsShown() and Hush.Conversation.Current() == key then return false end
    return true
end

-- ---------------------------------------------------------------------------
-- Preview and move mode (Settings)
-- ---------------------------------------------------------------------------

local sample
local function sampleData()
    local r, g, b = Compat.ClassColor("PRIEST")
    return {
        name = "Sigrid", r = r or 1, g = g or 1, b = b or 1, time = date("%H:%M"),
        lines = {
            { text = "Hey! Saw your post, are you still recruiting?" },
            { text = "I'm a holy priest, 3 raids a week works for me." },
        },
    }
end

function Popup.Preview()
    if not anchor then return end
    if not sample then sample = create() end
    fill(sample, sampleData())
    sample:ClearAllPoints()
    if stackDown then sample:SetPoint("TOP", anchor, "TOP") else sample:SetPoint("BOTTOM", anchor, "BOTTOM") end
    sample:SetAlpha(1)
    sample:Show()
    sample.fadeIn:Play()
    schedule(sample, 5)
end

function Popup.SetMoveMode(on)
    if not anchor then return end
    moveMode = on
    if not sample then sample = create() end
    if on then
        fill(sample, sampleData())
        sample.time:SetText("drag to move")
        sample:ClearAllPoints()
        if stackDown then sample:SetPoint("TOP", anchor, "TOP") else sample:SetPoint("BOTTOM", anchor, "BOTTOM") end
        sample:SetMovable(true)
        sample:RegisterForDrag("LeftButton")
        sample:SetScript("OnDragStart", function(self) self:StartMoving() end)
        sample:SetScript("OnDragStop", function(self)
            self:StopMovingOrSizing()
            local d = Hush.db.popup
            d.left = Theme:Snap(self:GetLeft(), self)
            d.top = Theme:Snap(self:GetTop(), self)
            d.bottom = Theme:Snap(self:GetBottom(), self)
            placeAnchor()
            self:ClearAllPoints()
            if stackDown then self:SetPoint("TOP", anchor, "TOP") else self:SetPoint("BOTTOM", anchor, "BOTTOM") end
            layout()
        end)
        sample:SetAlpha(1)
        sample:Show()
    else
        sample:SetScript("OnDragStart", nil)
        sample:SetScript("OnDragStop", nil)
        sample:Hide()
    end
end

-- Choosing a corner in the settings drops the custom position.
function Popup.SetCorner(corner)
    Hush.db.popup.left, Hush.db.popup.top, Hush.db.popup.bottom = nil, nil, nil
    Hush.settings.popupCorner = corner
    if anchor then
        placeAnchor()
        layout()
    end
end

-- ---------------------------------------------------------------------------
-- Setup and events
-- ---------------------------------------------------------------------------

Hush:RegisterCallback("READY", function()
    anchor = CreateFrame("Frame", nil, UIParent)
    anchor:SetSize(WIDTH, 1)
    anchor:SetFrameStrata("DIALOG")
    pool = {}
    more = CreateFrame("Button", nil, anchor)
    more:SetHeight(24)
    more:SetFrameStrata("DIALOG")
    more.bg = W.Fill(more, "field", 0.97)
    more.bg:SetAllPoints()
    more.border = W.Border(more, "line")
    W.SkinPanel(more, { kind = "tooltip", hide = { more.bg }, borders = { more.border } })
    more.text = W.Text(more, "semibold", -1, "text")
    more.text:SetPoint("CENTER")
    more:SetScript("OnClick", function()
        local key = overflow[#overflow]
        wipe(overflow)
        more:Hide()
        Hush.Main.Show()
        if key and Data.Get(key) then Hush.List.Select(key) end
    end)
    more:Hide()
    placeAnchor()

    -- Shift-clicked links go into a popup field while it has focus.
    Compat.HookInsertLink(function(link)
        for _, f in ipairs(active) do
            if link and f.edit:HasFocus() then f.edit:Insert(link) end
        end
    end)
end, "Popup")

Hush:RegisterCallback("MESSAGE_ADDED", function(_, key, msg, conv)
    if not anchor then return end
    if msg.d == "in" then
        if wanted(key, conv) then Popup.Show(key) end
    elseif byKey[key] then
        -- Your reply (from the popup or /r) or a system line: update the open popup.
        local f = byKey[key]
        local data = dataFor(key)
        if data then fill(f, data) end
    end
end, "Popup")

-- Opening the conversation in Hush, deleting it, or entering combat closes its popup.
Hush:RegisterCallback("CONV_OPENED", function(_, key)
    if anchor and Hush.Main.IsShown() then Popup.Dismiss(key) end
end, "Popup")
Hush:RegisterCallback("CONV_DELETED", function(_, key) if anchor then Popup.Dismiss(key) end end, "Popup")
Hush:RegisterCallback("CONV_RENAMED", function(_, oldKey, newKey)
    local f = byKey[oldKey]
    if f then
        byKey[oldKey], byKey[newKey], f.key = nil, f, newKey
    end
    for i, k in ipairs(overflow) do if k == oldKey then overflow[i] = newKey end end
end, "Popup")
Hush:RegisterEvent("PLAYER_REGEN_DISABLED", function() if anchor then Popup.DismissAll() end end)
