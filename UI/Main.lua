-- Main window: sidebar (title, search, tabs, list area) and conversation pane.
local _, Hush = ...

local Theme, W, Data = Hush.Theme, Hush.Widgets, Hush.Data
local S = Theme.size

local Main = {}
Hush.Main = Main

Main.activeTab = "whispers"
Main.search = ""

local frame

-- ---------------------------------------------------------------------------
-- Position and size
-- ---------------------------------------------------------------------------

local function savePosition()
    local db = Hush.db.window
    db.left = Theme:Snap(frame:GetLeft(), frame)
    db.top = Theme:Snap(frame:GetTop(), frame)
    db.w = Theme:Snap(frame:GetWidth(), frame)
    db.h = Theme:Snap(frame:GetHeight(), frame)
end

local function restorePosition()
    local db = Hush.db.window
    frame:ClearAllPoints()
    frame:SetSize(Theme:Snap(db.w or S.windowW, frame), Theme:Snap(db.h or S.windowH, frame))
    if db.left and db.top then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", db.left, db.top)
    else
        frame:SetPoint("CENTER")
    end
end

local function makeDraggable(region)
    region:EnableMouse(true)
    region:RegisterForDrag("LeftButton")
    region:SetScript("OnDragStart", function() frame:StartMoving() end)
    region:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        savePosition()
        restorePosition() -- re-anchor TOPLEFT on whole pixels
    end)
end

function Main.ApplyBackgroundAlpha()
    if not frame then return end
    local a = Hush.settings.bgAlpha or 0.95
    frame.bg:SetAlpha(a)
    frame.sidebar.bg:SetAlpha(a)
end

-- ---------------------------------------------------------------------------
-- Tabs
-- ---------------------------------------------------------------------------

local TABS = {
    { id = "whispers", label = "Whispers" },
    { id = "groups",   label = "Groups" },
    { id = "requests", label = "Requests" },
}

local function updateTabs()
    for _, tab in ipairs(frame.tabs) do
        local active = tab.id == Main.activeTab
        tab.text:SetTextColor(Theme:Color(active and "text" or "textDim"))
        tab.underline:SetShown(active)
    end
end

function Main.SetTab(id)
    if Main.activeTab == id then return end
    Main.activeTab = id
    updateTabs()
    Hush:Fire("TAB_CHANGED", id)
end

function Main.UpdateBadges()
    if not frame then return end
    local _, byTab = Data.UnreadTotals()
    for _, tab in ipairs(frame.tabs) do
        tab.badge:SetCount(byTab[tab.id])
    end
end

local function createTabs(parent)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetHeight(S.tabH)
    W.Line(bar, "bottom", "line")
    frame.tabs = {}

    local count = #TABS
    for i, def in ipairs(TABS) do
        local tab = CreateFrame("Button", nil, bar)
        tab.id = def.id
        tab:SetSize(S.sidebarW / count, S.tabH)
        tab:SetPoint("TOPLEFT", bar, "TOPLEFT", (i - 1) * S.sidebarW / count, 0)

        tab.text = W.Text(tab, "semibold", 0, "textDim")
        tab.text:SetText(def.label)
        tab.badge = W.Badge(tab)

        -- Center label + badge together.
        tab.text:SetPoint("CENTER", tab, "CENTER", 0, 0)
        tab.badge:SetPoint("LEFT", tab.text, "RIGHT", 5, 0)

        tab.underline = tab:CreateTexture(nil, "OVERLAY")
        tab.underline:SetPoint("BOTTOMLEFT", 6, 0)
        tab.underline:SetPoint("BOTTOMRIGHT", -6, 0)
        W.PixelSize(tab.underline, tab, "h", 2)
        W.OnAccent(function(r, g, b) tab.underline:SetColorTexture(r, g, b, 1) end)

        tab:SetScript("OnClick", function(self) Main.SetTab(self.id) end)
        tab:SetScript("OnEnter", function(self)
            if self.id ~= Main.activeTab then self.text:SetTextColor(Theme:Color("text")) end
        end)
        tab:SetScript("OnLeave", function() updateTabs() end)
        frame.tabs[i] = tab
    end

    bar:SetScript("OnSizeChanged", function(self, w)
        local tw = w / count
        for i, tab in ipairs(frame.tabs) do
            tab:ClearAllPoints()
            tab:SetPoint("TOPLEFT", self, "TOPLEFT", (i - 1) * tw, 0)
            tab:SetSize(tw, S.tabH)
        end
    end)
    return bar
end

-- ---------------------------------------------------------------------------
-- Build
-- ---------------------------------------------------------------------------

local function buildSidebar()
    local side = CreateFrame("Frame", nil, frame)
    side:SetPoint("TOPLEFT")
    side:SetPoint("BOTTOMLEFT")
    side:SetWidth(S.sidebarW)
    side.bg = W.Fill(side, "sidebar", 1)
    side.bg:SetAllPoints()
    W.Line(side, "right", "line")
    frame.sidebar = side

    -- Title row
    local title = CreateFrame("Frame", nil, side)
    title:SetPoint("TOPLEFT")
    title:SetPoint("TOPRIGHT")
    title:SetHeight(S.titleH)
    makeDraggable(title)

    local square = title:CreateTexture(nil, "ARTWORK")
    square:SetSize(10, 10)
    square:SetPoint("LEFT", S.padding, 0)
    W.OnAccent(function(r, g, b) square:SetColorTexture(r, g, b, 1) end)

    local name = W.Text(title, "heading", 3, "text")
    name:SetPoint("LEFT", square, "RIGHT", 8, 0)
    name:SetText("HUSH")

    local settingsBtn = W.IconButton(title, "settings", 22, "Settings", function()
        Hush:Fire("OPEN_SETTINGS")
    end, "=")
    settingsBtn:SetPoint("RIGHT", -S.padding, 0)

    local newBtn = W.IconButton(title, "plus", 22, "New message", function()
        Hush:Fire("NEW_MESSAGE")
    end, "+")
    newBtn:SetPoint("RIGHT", settingsBtn, "LEFT", -2, 0)

    -- Search
    local search = W.EditBox(side, "Search", S.searchH)
    search:SetPoint("TOPLEFT", title, "BOTTOMLEFT", S.padding, 0)
    search:SetPoint("TOPRIGHT", title, "BOTTOMRIGHT", -S.padding, 0)
    search:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    search:HookScript("OnTextChanged", function(self)
        local text = strtrim(self:GetText() or "")
        if text ~= Main.search then
            Main.search = text
            Hush:Fire("SEARCH_CHANGED", text)
        end
    end)
    frame.search = search

    -- Tabs
    local tabs = createTabs(side)
    tabs:SetPoint("TOPLEFT", search, "BOTTOMLEFT", -S.padding, -S.gap)
    tabs:SetPoint("TOPRIGHT", search, "BOTTOMRIGHT", S.padding, -S.gap)

    -- Bottom: new category
    local bottom = CreateFrame("Frame", nil, side)
    bottom:SetPoint("BOTTOMLEFT")
    bottom:SetPoint("BOTTOMRIGHT")
    bottom:SetHeight(36)
    W.Line(bottom, "top", "line")
    local newCat = W.Button(bottom, "+ New category", "ghost", function()
        Hush:Fire("NEW_CATEGORY")
    end)
    newCat:SetPoint("LEFT", S.padding - 8, 0)
    frame.newCategory = newCat

    -- List area (filled in by UI/List.lua)
    local list = CreateFrame("Frame", nil, side)
    list:SetPoint("TOPLEFT", tabs, "BOTTOMLEFT", 0, 0)
    list:SetPoint("BOTTOMRIGHT", bottom, "TOPRIGHT", 0, 0)
    list.empty = W.Text(list, "regular", 0, "textFaint")
    list.empty:SetPoint("TOP", 0, -24)
    list.empty:SetText("No conversations yet")
    frame.list = list
    Main.listArea = list
end

local function buildPane()
    local pane = CreateFrame("Frame", nil, frame)
    pane:SetPoint("TOPLEFT", frame.sidebar, "TOPRIGHT")
    pane:SetPoint("BOTTOMRIGHT")
    frame.pane = pane

    -- Header
    local header = CreateFrame("Frame", nil, pane)
    header:SetPoint("TOPLEFT")
    header:SetPoint("TOPRIGHT")
    header:SetHeight(S.headerH)
    W.Line(header, "bottom", "line")
    makeDraggable(header)
    frame.header = header

    local close = W.IconButton(header, "close", 24, "Close", function() Main.Hide() end, "x")
    close:SetPoint("TOPRIGHT", -S.gap, -S.gap)
    header.close = close

    header.title = W.Text(header, "semibold", 4, "text")
    header.title:SetPoint("TOPLEFT", S.padding + 4, -14)
    header.title:SetText("")

    header.meta = W.Text(header, "regular", -1, "textDim")
    header.meta:SetPoint("TOPLEFT", header.title, "BOTTOMLEFT", 0, -6)

    -- Footer (input area, built in a later step)
    local footer = CreateFrame("Frame", nil, pane)
    footer:SetPoint("BOTTOMLEFT")
    footer:SetPoint("BOTTOMRIGHT")
    footer:SetHeight(1)
    frame.footer = footer

    -- Body (messages)
    local body = CreateFrame("Frame", nil, pane)
    body:SetPoint("TOPLEFT", header, "BOTTOMLEFT")
    body:SetPoint("BOTTOMRIGHT", footer, "TOPRIGHT")
    frame.body = body

    body.empty = W.Text(body, "semibold", 2, "textDim")
    body.empty:SetPoint("CENTER", 0, 10)
    body.empty:SetText("Select a conversation")
    body.emptySub = W.Text(body, "regular", -1, "textFaint")
    body.emptySub:SetPoint("TOP", body.empty, "BOTTOM", 0, -6)
    body.emptySub:SetText("Whispers you send and receive show up here.")

    Main.header, Main.body, Main.footer = header, body, footer
end

local function buildGrip()
    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(frame:GetFrameLevel() + 20)
    grip.icon = W.Icon(grip, "grip", 12, "/")
    grip.icon:SetColor(Theme:Color("textFaint"))
    grip:SetScript("OnEnter", function(self) self.icon:SetColor(Theme:Color("text")) end)
    grip:SetScript("OnLeave", function(self) self.icon:SetColor(Theme:Color("textFaint")) end)
    grip:SetScript("OnMouseDown", function() frame:StartSizing("BOTTOMRIGHT") end)
    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()
        savePosition()
        restorePosition()
    end)
end

-- ESC closes the window without a global name (UISpecialFrames would need one).
-- Keyboard input is only enabled while shown and out of combat, and always passes
-- through except for ESC, so it can never swallow keys during a fight.
local function enableKeyboard(on)
    if on and InCombatLockdown() then on = false end
    frame:EnableKeyboard(on)
    if on then frame:SetPropagateKeyboardInput(true) end
end

local function setupEscape()
    frame:SetScript("OnKeyDown", function(self, key)
        if key == "ESCAPE" and not InCombatLockdown() then
            self:SetPropagateKeyboardInput(false)
            Main.Hide()
        end
    end)
    Hush:RegisterEvent("PLAYER_REGEN_DISABLED", function() frame:EnableKeyboard(false) end)
    Hush:RegisterEvent("PLAYER_REGEN_ENABLED", function() if frame:IsShown() then enableKeyboard(true) end end)
end

local function build()
    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:SetResizable(true)
    frame:EnableMouse(true)
    W.SetResizeBounds(frame, S.windowMinW, S.windowMinH, 2400, 1400)
    frame:Hide()

    frame.bg = W.Fill(frame, "window", 1)
    frame.bg:SetAllPoints()

    buildSidebar()
    buildPane()
    buildGrip()
    frame.border = W.Border(frame, "line")
    -- Border above children.
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do frame.border[side]:SetDrawLayer("OVERLAY", 7) end

    setupEscape()
    restorePosition()
    Main.ApplyBackgroundAlpha()
    updateTabs()
    Main.UpdateBadges()

    frame:SetScript("OnShow", function()
        enableKeyboard(true)
        Hush:Fire("WINDOW_SHOWN")
    end)
    frame:SetScript("OnHide", function()
        frame:EnableKeyboard(false)
        W.HideTooltip()
        Hush:Fire("WINDOW_HIDDEN")
    end)

    Main.frame = frame
    Hush:Fire("WINDOW_BUILT", frame)
end

-- ---------------------------------------------------------------------------
-- Public
-- ---------------------------------------------------------------------------

function Main.IsShown()
    return frame ~= nil and frame:IsShown()
end

function Main.Show()
    if not Hush.ready then return end
    if not frame then build() end
    frame:Show()
end

function Main.Hide()
    if frame then frame:Hide() end
end

function Main.Toggle()
    if Main.IsShown() then Main.Hide() else Main.Show() end
end

function Hush:Toggle()
    Main.Toggle()
end

-- Header: name in class color, then "Class · Level 60 · <Guild> · Zone".
function Main.UpdateHeader(key)
    if not frame then return end
    local header = frame.header
    local conv = key and Data.Get(key)
    if not conv then
        header.title:SetText("")
        header.meta:SetText("")
        return
    end
    header.title:SetText(conv.display)
    header.title:SetTextColor(Hush.List.NameColor(conv))

    local info, parts = conv.info or {}, {}
    if conv.kind == "bnet" then
        parts[#parts + 1] = conv.target
        if info.character then parts[#parts + 1] = info.character end
    end
    local className = info.class and LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[info.class]
    if className then parts[#parts + 1] = className end
    if info.level and info.level > 0 then parts[#parts + 1] = "Level " .. info.level end
    if info.guild then parts[#parts + 1] = "<" .. info.guild .. ">" end
    if info.zone then parts[#parts + 1] = info.zone end
    if conv.kind == "whisper" and #parts == 0 then parts[#parts + 1] = "No info yet" end
    if conv.kind == "group" then
        if Hush.Groups.IsActive(conv) then
            parts[#parts + 1] = "Active"
            parts[#parts + 1] = Hush.Groups.MemberCount() .. " members"
        else
            parts[#parts + 1] = "Ended" .. (conv.ended and (" " .. date("%d/%m %H:%M", conv.ended)) or "")
        end
    end
    header.meta:SetText(table.concat(parts, "  ·  "))
end

-- Auto-open: incoming (or sent) whisper opens Hush on that conversation when the window is
-- closed. Never in combat, never for Requests, never steals keyboard focus, never switches
-- away from a conversation that is already open.
Hush:RegisterCallback("MESSAGE_ADDED", function(_, key, msg, conv)
    if conv.kind == "group" or msg.d == "sys" or conv.request then return end
    if Main.IsShown() or Hush.Compat.InCombat() then return end
    local s = Hush.settings
    if (msg.d == "in" and s.autoOpenIn) or (msg.d == "out" and s.autoOpenOut) then
        Main.Show()
        Hush.List.Select(key)
    end
end, "Main")

Hush:RegisterCallback("CONV_OPENED", function(_, key) Main.UpdateHeader(key) end, "Main")
Hush:RegisterCallback("CONV_UPDATED", function(_, conv)
    local key = Hush.List.selected
    if key and Data.Get(key) == conv then Main.UpdateHeader(key) end
end, "Main")
Hush:RegisterCallback("CONV_DELETED", function(_, key)
    if Hush.List.selected == nil or Hush.List.selected == key then Main.UpdateHeader(nil) end
end, "Main")

Hush:RegisterCallback("UNREAD_CHANGED", function() Main.UpdateBadges() end, "Main")
Hush:RegisterCallback("SETTINGS_CHANGED", function(_, key)
    if key == "bgAlpha" then Main.ApplyBackgroundAlpha() end
    if key == "fadeWhenMoving" and frame then frame:SetAlpha(1) end
end, "Main")

function Main.ResetPosition()
    Hush.db.window.left, Hush.db.window.top = nil, nil
    Hush.db.window.w, Hush.db.window.h = S.windowW, S.windowH
    if frame then restorePosition() end
    Hush:Print("Window position and size reset.")
end

Hush:AddSlashCommand("reset", Main.ResetPosition, "reset window position and size")

-- ---------------------------------------------------------------------------
-- Dim while moving: fade the window while the character runs, unless the
-- mouse is over it or the player is typing in it. Event-driven, no OnUpdate.
-- ---------------------------------------------------------------------------

local MOVING_ALPHA = 0.35
local moving = false

local function applyMovingAlpha()
    if not frame then return end
    local typing = Hush.Input and Hush.Input.HasFocus and Hush.Input.HasFocus()
    local fade = moving and Hush.settings.fadeWhenMoving and not typing and not frame:IsMouseOver()
    frame:SetAlpha(fade and MOVING_ALPHA or 1)
end

Hush:RegisterEvent("PLAYER_STARTED_MOVING", function() moving = true applyMovingAlpha() end)
Hush:RegisterEvent("PLAYER_STOPPED_MOVING", function() moving = false applyMovingAlpha() end)
Hush:RegisterCallback("WINDOW_BUILT", function()
    frame:HookScript("OnEnter", function() frame:SetAlpha(1) end)
    frame:HookScript("OnLeave", applyMovingAlpha)
end, "Main")
