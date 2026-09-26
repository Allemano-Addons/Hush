-- Toast: a small discreet notice (e.g. "3 whispers during combat"). Left-click runs the
-- action, right-click dismisses. Fades with animations and hides on a timer (no OnUpdate).
local _, Hush = ...

local Theme, W, Compat = Hush.Theme, Hush.Widgets, Hush.Compat

local Toast = {}
Hush.Toast = Toast

local frame
local token = 0
local DURATION = 12

local function build()
    frame = CreateFrame("Button", nil, UIParent)
    frame:SetSize(320, 56)
    frame:SetPoint("TOP", UIParent, "TOP", 0, -140)
    frame:SetFrameStrata("DIALOG")
    frame:SetClampedToScreen(true)
    frame:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    frame:Hide()

    frame.bg = W.Fill(frame, "field", 0.97)
    frame.bg:SetAllPoints()
    frame.border = W.Border(frame, "line")
    frame.bar = frame:CreateTexture(nil, "ARTWORK")
    frame.bar:SetPoint("TOPLEFT")
    frame.bar:SetPoint("BOTTOMLEFT")
    W.PixelSize(frame.bar, frame, "w", 3)
    W.OnAccent(function(r, g, b) frame.bar:SetColorTexture(r, g, b, 1) end)

    frame.title = W.Text(frame, "semibold", 1, "text")
    frame.title:SetPoint("TOPLEFT", 16, -11)
    frame.title:SetWidth(292)
    frame.sub = W.Text(frame, "regular", -1, "textDim")
    frame.sub:SetPoint("TOPLEFT", frame.title, "BOTTOMLEFT", 0, -5)
    frame.sub:SetWidth(292)

    frame.fadeIn = frame:CreateAnimationGroup()
    local a = frame.fadeIn:CreateAnimation("Alpha")
    a:SetFromAlpha(0)
    a:SetToAlpha(1)
    a:SetDuration(0.2)
    frame.fadeIn:SetScript("OnPlay", function() frame:SetAlpha(1) end)

    frame.fadeOut = frame:CreateAnimationGroup()
    local b = frame.fadeOut:CreateAnimation("Alpha")
    b:SetFromAlpha(1)
    b:SetToAlpha(0)
    b:SetDuration(0.4)
    frame.fadeOut:SetScript("OnFinished", function() frame:Hide() end)

    frame:SetScript("OnEnter", function(self) self.bg:SetColorTexture(Theme:Color("selected")) end)
    frame:SetScript("OnLeave", function(self) self.bg:SetColorTexture(Theme:Color("field")) end)
    frame:SetScript("OnClick", function(self, button)
        Toast.Hide()
        if button == "LeftButton" and self.onClick then self.onClick() end
    end)
end

function Toast.Show(title, sub, onClick)
    if not frame then build() end
    frame.title:SetText(title)
    frame.sub:SetText(sub or "")
    frame.onClick = onClick
    frame.fadeOut:Stop()
    frame:Show()
    frame.fadeIn:Play()

    token = token + 1
    local mine = token
    Compat.After(DURATION, function()
        -- Only the newest toast hides itself; keep it while the mouse is over it.
        if mine ~= token or not frame:IsShown() then return end
        if frame:IsMouseOver() then
            Compat.After(3, function() if mine == token and frame:IsShown() then frame.fadeOut:Play() end end)
        else
            frame.fadeOut:Play()
        end
    end)
end

function Toast.Hide()
    if frame then
        token = token + 1
        frame.fadeIn:Stop()
        frame.fadeOut:Stop()
        frame:Hide()
    end
end
