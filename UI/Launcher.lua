-- Launcher: a small movable button (own, no LibDBIcon) with an unread badge.
local _, Hush = ...

local Theme, W, Data = Hush.Theme, Hush.Widgets, Hush.Data

local Launcher = {}
Hush.Launcher = Launcher

local SIZE = 30
local button

local function db() return Hush.db.launcher end

local function savePosition()
    local d = db()
    d.left = Theme:Snap(button:GetLeft(), button)
    d.top = Theme:Snap(button:GetTop(), button)
end

local function restorePosition()
    local d = db()
    button:ClearAllPoints()
    if d.left and d.top then
        button:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", d.left, d.top)
    else
        -- Top center: free on most UIs (the top-right corner is usually minimap and buffs).
        button:SetPoint("TOP", UIParent, "TOP", 0, -8)
    end
end

-- Whispers and requests; group chat is not counted here (it has its own tab badge).
function Launcher.Update()
    if not button then return end
    local _, byTab = Data.UnreadTotals()
    button.badge:SetCount(byTab.whispers + byTab.requests)
end

local function openMenu()
    local d = db()
    W.OpenMenu({
        { text = Hush.Main.IsShown() and "Close Hush" or "Open Hush", onClick = function() Hush.Main.Toggle() end },
        { text = "Reply to last whisper", onClick = function() Hush.API.ReplyLast() end },
        { text = "Settings", onClick = function() Hush.Main.Show() Hush:Fire("OPEN_SETTINGS") end },
        { separator = true },
        { text = "Lock position", checked = d.locked == true, onClick = function() d.locked = not d.locked end },
        { text = "Hide button", onClick = function() Launcher.SetHidden(true) end },
    })
end

local function build()
    button = CreateFrame("Button", nil, UIParent)
    button:SetSize(SIZE, SIZE)
    button:SetFrameStrata("HIGH")
    button:SetClampedToScreen(true)
    button:SetMovable(true)
    button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    button:RegisterForDrag("LeftButton")

    button.bg = W.Fill(button, "sidebar", 0.95)
    button.bg:SetAllPoints()
    button.border = W.Border(button, "line")

    -- Speech bubble drawn from two rectangles, on whole pixels.
    local bubble = button:CreateTexture(nil, "ARTWORK")
    bubble:SetSize(14, 10)
    bubble:SetPoint("TOPLEFT", 8, -9)
    local tail = button:CreateTexture(nil, "ARTWORK")
    tail:SetSize(4, 4)
    tail:SetPoint("TOPLEFT", bubble, "BOTTOMLEFT", 2, 0)
    W.OnAccent(function(r, g, b)
        bubble:SetColorTexture(r, g, b, 1)
        tail:SetColorTexture(r, g, b, 1)
    end)

    button.badge = W.Badge(button)
    button.badge:SetPoint("CENTER", button, "TOPRIGHT", -2, -2)
    button.badge:SetFrameLevel(button:GetFrameLevel() + 2)

    button:SetScript("OnEnter", function(self)
        self.border:SetColor(Theme:Accent())
        W.ShowTooltip(self, "Hush  |cff7c858fleft-click open, drag to move, right-click menu|r")
    end)
    button:SetScript("OnLeave", function(self)
        self.border:SetColor(Theme:Color("line"))
        W.HideTooltip()
    end)
    button:SetScript("OnClick", function(_, mouseButton)
        if mouseButton == "RightButton" then openMenu() else Hush.Main.Toggle() end
    end)
    button:SetScript("OnDragStart", function(self)
        if db().locked then return end
        W.HideTooltip()
        self:StartMoving()
    end)
    button:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
        restorePosition()
    end)

    restorePosition()
    button:SetShown(not db().hidden)
    Launcher.Update()
end

function Launcher.SetHidden(hidden)
    db().hidden = hidden and true or false
    if button then button:SetShown(not hidden) end
    if hidden then Hush:Print("Launcher hidden. Show it again with /hush launcher") end
end

Hush:RegisterCallback("READY", build, "Launcher")
Hush:RegisterCallback("UNREAD_CHANGED", function() Launcher.Update() end, "Launcher")
Hush:RegisterCallback("CONV_DELETED", function() Launcher.Update() end, "Launcher")

Hush:AddSlashCommand("launcher", function(arg)
    if arg == "reset" then
        db().left, db().top = nil, nil
        if button then restorePosition() end
    end
    Launcher.SetHidden(false)
    Hush:Print("Launcher shown.", arg == "reset" and "Position reset." or "")
end, "show the launcher button (/hush launcher reset to move it back)")
