-- Widgets: flat building blocks in the Hush style. No Blizzard textures or templates.
local _, Hush = ...

local Theme, Compat = Hush.Theme, Hush.Compat

local W = {}
Hush.Widgets = W

-- ---------------------------------------------------------------------------
-- Pixel-sized textures: re-sized when the UI scale changes.
-- ---------------------------------------------------------------------------

local pixelItems = {}

local function applyPixel(item)
    local px = Theme:Pixel(item.frame)
    if item.axis == "h" then
        item.tex:SetHeight(px * item.n)
    else
        item.tex:SetWidth(px * item.n)
    end
end

-- Keep tex exactly n physical pixels high ("h") or wide ("w").
function W.PixelSize(tex, frame, axis, n)
    local item = { tex = tex, frame = frame, axis = axis, n = n or 1 }
    pixelItems[#pixelItems + 1] = item
    applyPixel(item)
end

function W.RefreshPixels()
    for i = 1, #pixelItems do applyPixel(pixelItems[i]) end
end

Hush:RegisterEvent("UI_SCALE_CHANGED", function() W.RefreshPixels() end)
Hush:RegisterEvent("DISPLAY_SIZE_CHANGED", function() W.RefreshPixels() end)

-- A solid color texture.
function W.Fill(frame, colorKey, alpha, layer)
    local t = frame:CreateTexture(nil, layer or "BACKGROUND")
    local r, g, b = Theme:Color(colorKey)
    t:SetColorTexture(r, g, b, alpha or 1)
    return t
end

-- A 1 px line along one side of frame ("top", "bottom", "left", "right").
function W.Line(frame, side, colorKey, layer)
    local t = W.Fill(frame, colorKey or "line", 1, layer or "BORDER")
    if side == "top" or side == "bottom" then
        local p = side == "top" and "TOP" or "BOTTOM"
        t:SetPoint(p .. "LEFT")
        t:SetPoint(p .. "RIGHT")
        W.PixelSize(t, frame, "h")
    else
        local p = side == "left" and "LEFT" or "RIGHT"
        t:SetPoint("TOP" .. p)
        t:SetPoint("BOTTOM" .. p)
        W.PixelSize(t, frame, "w")
    end
    return t
end

-- 1 px border on all sides. Returns a table with the four lines and :SetColor.
local borderMethods = {}
function borderMethods:SetColor(r, g, b, a)
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
        self[side]:SetColorTexture(r, g, b, a or 1)
    end
end

function W.Border(frame, colorKey)
    local b = setmetatable({}, { __index = borderMethods })
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do
        b[side] = W.Line(frame, side, colorKey)
    end
    return b
end

-- ---------------------------------------------------------------------------
-- Accent color: everything registered here is recolored when the accent changes.
-- ---------------------------------------------------------------------------

local accentFns = {}

-- fn(r, g, b) is called now and on every accent change.
function W.OnAccent(fn)
    accentFns[#accentFns + 1] = fn
    fn(Theme:Accent())
end

function W.ApplyAccent()
    local r, g, b = Theme:Accent()
    for i = 1, #accentFns do accentFns[i](r, g, b) end
end

-- ---------------------------------------------------------------------------
-- Text
-- ---------------------------------------------------------------------------

local fontItems = {}

function W.Text(parent, kind, delta, colorKey, layer)
    local fs = parent:CreateFontString(nil, layer or "OVERLAY")
    Theme:SetFont(fs, kind, delta)
    fs:SetTextColor(Theme:Color(colorKey or "text"))
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    fontItems[#fontItems + 1] = { fs = fs, kind = kind, delta = delta }
    return fs
end

function W.RefreshFonts()
    for i = 1, #fontItems do
        local f = fontItems[i]
        Theme:SetFont(f.fs, f.kind, f.delta)
    end
end

Hush:RegisterCallback("SETTINGS_CHANGED", function(_, key)
    if key == "accent" or key == "useClassColor" then
        W.ApplyAccent()
    elseif key == "textSize" or key == "font" or key == "headingFont" then
        W.RefreshFonts()
    end
end, "Widgets")

-- Other addons may register LibSharedMedia fonts late during login: resolve again shortly after.
Hush:RegisterCallback("READY", function()
    Compat.After(1, function()
        Theme:ApplyFontChoice()
        W.RefreshFonts()
        Hush:Fire("FONTS_CHANGED")
    end)
end, "Widgets")

-- ---------------------------------------------------------------------------
-- Tooltip (own, flat)
-- ---------------------------------------------------------------------------

local tip
function W.ShowTooltip(owner, text)
    if not tip then
        tip = CreateFrame("Frame", nil, UIParent)
        tip:SetFrameStrata("TOOLTIP")
        tip:SetClampedToScreen(true)
        tip.bg = W.Fill(tip, "field", 0.98)
        tip.bg:SetAllPoints()
        W.Border(tip, "line")
        tip.text = W.Text(tip, "regular", -1, "text")
        tip.text:SetPoint("CENTER")
    end
    tip.text:SetText(text)
    tip:SetSize(tip.text:GetStringWidth() + 16, tip.text:GetStringHeight() + 10)
    tip:ClearAllPoints()
    -- Below the owner (keeps it inside the window near the title row); above near the screen bottom.
    if (owner:GetBottom() or 100) * owner:GetEffectiveScale() < 80 then
        tip:SetPoint("BOTTOM", owner, "TOP", 0, 4)
    else
        tip:SetPoint("TOP", owner, "BOTTOM", 0, -4)
    end
    tip:Show()
end

function W.HideTooltip()
    if tip then tip:Hide() end
end

-- ---------------------------------------------------------------------------
-- Icons drawn from lines (no texture files needed).
-- ---------------------------------------------------------------------------

-- Rectangles are placed from the icon box's top-left on whole pixels, so they stay crisp.
local function rect(box, x, y, w, h)
    local t = box:CreateTexture(nil, "ARTWORK")
    t:SetPoint("TOPLEFT", box, "TOPLEFT", x, -y)
    t:SetSize(w, h)
    return t
end

local function line(frame, x1, y1, x2, y2, thickness)
    if not frame.CreateLine then return nil end
    local l = frame:CreateLine(nil, "ARTWORK")
    l:SetThickness(thickness)
    l:SetStartPoint("CENTER", frame, x1, y1)
    l:SetEndPoint("CENTER", frame, x2, y2)
    return l
end

-- Returns a list of textures/lines forming the icon, centered in frame.
local ICONS = {
    plus = function(f, s)
        local m = s / 2 - 1
        return { rect(f, 0, m, s, 2), rect(f, m, 0, 2, s) }
    end,
    close = function(f, s)
        local h = s / 2
        local a, b = line(f, -h, -h, h, h, 1.5), line(f, -h, h, h, -h, 1.5)
        if a then return { a, b } end
        return nil
    end,
    settings = function(f, s) -- three sliders with knobs
        local parts = {}
        local rows = { { y = 1, knob = 2 }, { y = s / 2, knob = s - 4 }, { y = s - 1, knob = 4 } }
        for _, row in ipairs(rows) do
            parts[#parts + 1] = rect(f, 0, row.y, s, 1)
            parts[#parts + 1] = rect(f, row.knob - 1, row.y - 2, 2, 5)
        end
        return parts
    end,
    chevronDown = function(f, s)
        local q = s / 4
        local a, b = line(f, -q * 1.5, q * 0.75, 0, -q * 0.75, 1.5), line(f, 0, -q * 0.75, q * 1.5, q * 0.75, 1.5)
        if a then return { a, b } end
    end,
    chevronRight = function(f, s)
        local q = s / 4
        local a, b = line(f, -q * 0.75, q * 1.5, q * 0.75, 0, 1.5), line(f, q * 0.75, 0, -q * 0.75, -q * 1.5, 1.5)
        if a then return { a, b } end
    end,
    person = function(f, s) -- head and shoulders
        return { rect(f, s / 2 - 2, 0, 4, 4), rect(f, 1, s - 4, s - 2, 4) }
    end,
    megaphone = function(f, s) -- small box + widening horn
        return { rect(f, 0, s / 2 - 2, 3, 4), rect(f, 3, s / 2 - 3, 2, 6), rect(f, 5, s / 2 - 4, 2, 8), rect(f, 7, 0, 2, s) }
    end,
    more = function(f, s) -- three dots
        local m = s / 2 - 1
        return { rect(f, 0, m, 2, 2), rect(f, m, m, 2, 2), rect(f, s - 2, m, 2, 2) }
    end,
    grip = function(f, s)
        local parts = {}
        for i = 1, 3 do
            local o = i * s / 3
            local l = line(f, s / 2 - o, -s / 2, s / 2, -s / 2 + o, 1)
            if l then parts[#parts + 1] = l end
        end
        return parts
    end,
}

-- Draw an icon; falls back to a text glyph if lines are not supported.
function W.Icon(frame, name, size, fallbackGlyph)
    -- An even-sized box centered in the (even-sized) button keeps whole-pixel positions.
    size = size - size % 2
    local box = CreateFrame("Frame", nil, frame)
    box:SetSize(size, size)
    box:SetPoint("CENTER")
    local parts = ICONS[name] and ICONS[name](box, size)
    if parts and #parts > 0 then
        local icon = { parts = parts, box = box }
        function icon:SetColor(r, g, b, a)
            for _, p in ipairs(self.parts) do p:SetColorTexture(r, g, b, a or 1) end
        end
        function icon:SetShown(shown) self.box:SetShown(shown) end
        return icon
    end
    local fs = W.Text(box, "semibold", 2)
    fs:SetPoint("CENTER")
    fs:SetText(fallbackGlyph or "?")
    return {
        box = box,
        SetColor = function(_, r, g, b, a) fs:SetTextColor(r, g, b, a or 1) end,
        SetShown = function(self, shown) self.box:SetShown(shown) end,
    }
end

-- ---------------------------------------------------------------------------
-- Buttons
-- ---------------------------------------------------------------------------

-- Small square icon button. onClick(self, mouseButton).
function W.IconButton(parent, iconName, size, tooltip, onClick, fallbackGlyph)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(size or 24, size or 24)
    b.bg = W.Fill(b, "selected", 1)
    b.bg:SetAllPoints()
    b.bg:Hide()
    b.icon = W.Icon(b, iconName, 10, fallbackGlyph)
    b.icon:SetColor(Theme:Color("textDim"))
    b:SetScript("OnEnter", function(self)
        self.bg:Show()
        self.icon:SetColor(Theme:Color("text"))
        if tooltip then W.ShowTooltip(self, tooltip) end
    end)
    b:SetScript("OnLeave", function(self)
        self.bg:Hide()
        self.icon:SetColor(Theme:Color("textDim"))
        W.HideTooltip()
    end)
    b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- Flat text button. style: "default", "accent" or "ghost" (text only).
function W.Button(parent, label, style, onClick)
    style = style or "default"
    local b = CreateFrame("Button", nil, parent)
    b:SetHeight(Theme.size.inputH - 6)
    b.text = W.Text(b, "semibold", 0, style == "ghost" and "textDim" or "text")
    b.text:SetPoint("CENTER")
    b.text:SetText(label)
    b:SetWidth(b.text:GetStringWidth() + 24)

    if style ~= "ghost" then
        b.bg = W.Fill(b, "field", 1)
        b.bg:SetAllPoints()
        b.border = W.Border(b, "line")
    end

    if style == "accent" then
        b.text:SetTextColor(Theme:Color("sidebar"))
        W.OnAccent(function(r, g, bl)
            b.bg:SetColorTexture(r, g, bl, 1)
            b.border:SetColor(r, g, bl, 1)
        end)
        b:SetScript("OnEnter", function(self) self.bg:SetAlpha(0.85) end)
        b:SetScript("OnLeave", function(self) self.bg:SetAlpha(1) end)
    elseif style == "danger" then
        b.bg:SetColorTexture(Theme:Color("danger"))
        b.border:SetColor(Theme:Color("danger"))
        b.text:SetTextColor(Theme:Color("text"))
        b:SetScript("OnEnter", function(self) self.bg:SetAlpha(0.85) end)
        b:SetScript("OnLeave", function(self) self.bg:SetAlpha(1) end)
    elseif style == "ghost" then
        b:SetScript("OnEnter", function(self) self.text:SetTextColor(Theme:Color("text")) end)
        b:SetScript("OnLeave", function(self) self.text:SetTextColor(Theme:Color("textDim")) end)
    else
        b:SetScript("OnEnter", function(self) self.bg:SetColorTexture(Theme:Color("selected")) end)
        b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(Theme:Color("field")) end)
    end
    if onClick then b:SetScript("OnClick", onClick) end
    return b
end

-- ---------------------------------------------------------------------------
-- Edit box
-- ---------------------------------------------------------------------------

function W.EditBox(parent, placeholder, height)
    local e = CreateFrame("EditBox", nil, parent)
    e:SetHeight(height or Theme.size.searchH)
    e:SetAutoFocus(false)
    Theme:SetFont(e, "regular", 0)
    fontItems[#fontItems + 1] = { fs = e, kind = "regular", delta = 0 }
    e:SetTextColor(Theme:Color("text"))
    e:SetTextInsets(10, 10, 0, 0)

    e.bg = W.Fill(e, "field", 1)
    e.bg:SetAllPoints()
    e.border = W.Border(e, "line")

    e.placeholder = W.Text(e, "regular", 0, "textFaint")
    e.placeholder:SetPoint("LEFT", 10, 0)
    e.placeholder:SetText(placeholder or "")

    local function update(self)
        self.placeholder:SetShown(self:GetText() == "" and not self:HasFocus())
    end
    e:SetScript("OnEditFocusGained", function(self)
        self.border:SetColor(Theme:Accent())
        update(self)
    end)
    e:SetScript("OnEditFocusLost", function(self)
        self.border:SetColor(Theme:Color("line"))
        update(self)
    end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:HookScript("OnTextChanged", update)
    return e
end

-- ---------------------------------------------------------------------------
-- Badge (unread counter)
-- ---------------------------------------------------------------------------

function W.Badge(parent)
    local b = CreateFrame("Frame", nil, parent)
    b:SetHeight(16)
    b.bg = b:CreateTexture(nil, "ARTWORK")
    b.bg:SetAllPoints()
    W.OnAccent(function(r, g, bl) b.bg:SetColorTexture(r, g, bl, 1) end)
    b.text = W.Text(b, "semibold", -2, "sidebar")
    b.text:SetPoint("CENTER", 0, 0)
    function b:SetCount(n)
        if not n or n <= 0 then self:Hide() return end
        self.text:SetText(n > 99 and "99+" or tostring(n))
        self:SetWidth(max(16, self.text:GetStringWidth() + 8))
        self:Show()
    end
    b:Hide()
    return b
end

-- ---------------------------------------------------------------------------
-- Frame pool (reused rows)
-- ---------------------------------------------------------------------------

function W.Pool(create, reset)
    local pool = { free = {}, active = {} }
    function pool:Acquire()
        local obj = tremove(self.free) or create()
        self.active[#self.active + 1] = obj
        obj:Show()
        return obj
    end
    function pool:ReleaseAll()
        for i = #self.active, 1, -1 do
            local obj = self.active[i]
            obj:Hide()
            obj:ClearAllPoints()
            if reset then reset(obj) end
            self.free[#self.free + 1] = obj
            self.active[i] = nil
        end
    end
    return pool
end

-- ---------------------------------------------------------------------------
-- Thin scrollbar for virtualized lists.
-- onScroll(newOffset) is called while dragging; call :Update(offset, contentH, viewH) after rendering.
-- ---------------------------------------------------------------------------

function W.Scrollbar(parent, onScroll)
    local bar = CreateFrame("Frame", nil, parent)
    bar:SetPoint("TOPRIGHT", -2, -2)
    bar:SetPoint("BOTTOMRIGHT", -2, 2)
    bar:SetWidth(4)
    bar:SetFrameLevel(parent:GetFrameLevel() + 10)
    local thumb = CreateFrame("Frame", nil, bar)
    thumb:SetWidth(4)
    thumb.tex = W.Fill(thumb, "line", 1, "OVERLAY")
    thumb.tex:SetAllPoints()
    thumb:EnableMouse(true)
    bar.thumb = thumb
    bar.offset, bar.maxOffset = 0, 0

    -- OnUpdate only while the mouse button is held.
    thumb:SetScript("OnMouseDown", function(self)
        local _, cy = GetCursorPosition()
        self.startY = cy / self:GetEffectiveScale()
        self.startOffset = bar.offset
        self.tex:SetColorTexture(Theme:Color("textFaint"))
        self:SetScript("OnUpdate", function(s)
            -- Safety: stop if the button was released outside the game frame.
            if not IsMouseButtonDown("LeftButton") then
                s:SetScript("OnUpdate", nil)
                s.tex:SetColorTexture(Theme:Color("line"))
                return
            end
            local _, y = GetCursorPosition()
            y = y / s:GetEffectiveScale()
            local trackH = bar:GetHeight() - s:GetHeight()
            if trackH > 0 then
                onScroll(s.startOffset + (s.startY - y) / trackH * bar.maxOffset)
            end
        end)
    end)
    thumb:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
        self.tex:SetColorTexture(Theme:Color("line"))
    end)

    function bar:Update(offset, contentH, viewH)
        self.offset = offset
        self.maxOffset = max(0, contentH - viewH)
        if contentH <= viewH or viewH <= 0 then
            self:Hide()
            return
        end
        self:Show()
        local trackH = self:GetHeight()
        local thumbH = max(24, trackH * viewH / contentH)
        local pos = (trackH - thumbH) * (offset / self.maxOffset)
        thumb:SetHeight(thumbH)
        thumb:ClearAllPoints()
        thumb:SetPoint("TOPRIGHT", self, "TOPRIGHT", 0, -pos)
    end

    bar:Hide()
    return bar
end

-- ---------------------------------------------------------------------------
-- Dashed accent border (drop target highlight). Call :Layout() after resizing.
-- ---------------------------------------------------------------------------

function W.DashedBorder(frame, dash, gap)
    dash, gap = dash or 6, gap or 4
    local d = { frame = frame, textures = {} }
    function d:Layout()
        local w, h = frame:GetWidth(), frame:GetHeight()
        local px = Theme:Pixel(frame)
        local r, g, b = Theme:Accent()
        local n = 0
        local function seg(point, x, y, sw, sh)
            n = n + 1
            local t = self.textures[n]
            if not t then
                t = frame:CreateTexture(nil, "OVERLAY")
                self.textures[n] = t
            end
            t:ClearAllPoints()
            t:SetPoint(point, frame, point, x, y)
            t:SetSize(sw, sh)
            t:SetColorTexture(r, g, b, 1)
            t:Show()
        end
        for x = 0, w - 1, dash + gap do
            local len = min(dash, w - x)
            seg("TOPLEFT", x, 0, len, px)
            seg("BOTTOMLEFT", x, 0, len, px)
        end
        for y = 0, h - 1, dash + gap do
            local len = min(dash, h - y)
            seg("TOPLEFT", 0, -y, px, len)
            seg("TOPRIGHT", 0, -y, px, len)
        end
        for i = n + 1, #self.textures do self.textures[i]:Hide() end
    end
    return d
end

-- ---------------------------------------------------------------------------
-- Secure macro overlay: an invisible SecureActionButton over a Hush button that runs a
-- slash command when clicked (e.g. "/ginvite Name"). Needed for protected actions such as
-- guild invites, which addon code may not call directly. Only armed out of combat.
-- ---------------------------------------------------------------------------

-- IMPORTANT: the overlay is never anchored to Hush frames. Anchoring a secure frame to a
-- frame makes that frame "protected", which blocked keyboard handling and showing/hiding
-- Hush in combat. Instead it is placed at the target's screen position when armed.

local overlays = {}

local function placeOver(o, target)
    local left, bottom = target:GetLeft(), target:GetBottom()
    if not left or not bottom then return false end
    local ratio = target:GetEffectiveScale() / UIParent:GetEffectiveScale()
    o:ClearAllPoints()
    o:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", left * ratio, bottom * ratio)
    o:SetSize(target:GetWidth() * ratio, target:GetHeight() * ratio)
    return true
end

function W.SecureMacroOverlay(target, postClick)
    local o = CreateFrame("Button", nil, UIParent, "SecureActionButtonTemplate")
    o:RegisterForClicks("AnyUp", "AnyDown") -- the template acts once, per the key-down setting
    o:SetAttribute("type", "macro")
    o:Hide()
    -- Keep the Hush button's hover look.
    o:SetScript("OnEnter", function() local f = target:GetScript("OnEnter") if f then f(target) end end)
    o:SetScript("OnLeave", function() local f = target:GetScript("OnLeave") if f then f(target) end end)
    if postClick then o:SetScript("PostClick", postClick) end
    target:HookScript("OnHide", function() o:Disarm() end)

    -- Returns false in combat (secure attributes can't change then).
    -- Placement waits one frame: a button that was just re-anchored reports its new
    -- screen position only after the next layout pass.
    function o:Arm(macrotext)
        if InCombatLockdown() then return false end
        self:Hide()
        self.token = (self.token or 0) + 1
        local token = self.token
        Compat.After(0, function()
            if token ~= self.token or InCombatLockdown() then return end
            if not target:IsVisible() or not placeOver(self, target) then return end
            self:SetFrameStrata(target:GetFrameStrata())
            self:SetFrameLevel(target:GetFrameLevel() + 1) -- just above its button, not above other windows
            self:SetAttribute("macrotext", macrotext)
            self:Show()
        end)
        return true
    end
    function o:Disarm()
        self.token = (self.token or 0) + 1 -- cancel a pending arm
        if not InCombatLockdown() then self:Hide() end
    end
    overlays[#overlays + 1] = o
    return o
end

-- Hide every overlay (entering combat, or while a window is being moved so no invisible
-- button is left at the old position).
function W.HideSecureOverlays()
    if InCombatLockdown() then return end
    for _, o in ipairs(overlays) do o:Disarm() end
end

-- Entering combat: hide all overlays while that is still allowed.
Hush:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    for _, o in ipairs(overlays) do o:Hide() end
end)

-- ---------------------------------------------------------------------------
-- Context menu (own, flat). No UIDropDownMenu, so no taint.
-- items: { text, onClick, disabled, danger, checked, submenu = {items}, separator = true }
-- ---------------------------------------------------------------------------

local MENU_ITEM_H = 24
local menus = {}

local function hideMenu(level)
    for l = level, #menus do menus[l]:Hide() end
end

function W.CloseMenus()
    hideMenu(1)
end

function W.IsMenuOpen()
    return menus[1] ~= nil and menus[1]:IsShown()
end

local showMenu

local function menuButton(m, i)
    local b = m.buttons[i]
    if b then return b end
    b = CreateFrame("Button", nil, m)
    b:SetHeight(MENU_ITEM_H)
    b.hover = W.Fill(b, "selected", 1)
    b.hover:SetAllPoints()
    b.hover:Hide()
    b.check = b:CreateTexture(nil, "ARTWORK")
    b.check:SetSize(6, 6)
    b.check:SetPoint("LEFT", 10, 0)
    W.OnAccent(function(r, g, bl) b.check:SetColorTexture(r, g, bl, 1) end)
    b.text = W.Text(b, "regular", 0, "text")
    b.text:SetPoint("LEFT", 24, 0)
    b.arrow = W.Icon(b, "chevronRight", 8, ">")
    b.arrow.box:ClearAllPoints()
    b.arrow.box:SetPoint("RIGHT", -8, 0)
    b.arrow:SetColor(Theme:Color("textDim"))
    b.line = W.Fill(b, "line", 1, "ARTWORK")
    b.line:SetPoint("LEFT", 8, 0)
    b.line:SetPoint("RIGHT", -8, 0)
    W.PixelSize(b.line, b, "h")

    b:SetScript("OnEnter", function(self)
        if self.item.separator then return end
        if not self.item.disabled then self.hover:Show() end
        if self.item.submenu and not self.item.disabled then
            showMenu(m.level + 1, self.item.submenu, self)
        else
            hideMenu(m.level + 1)
        end
    end)
    b:SetScript("OnLeave", function(self) self.hover:Hide() end)
    b:SetScript("OnClick", function(self)
        local item = self.item
        if item.separator or item.disabled or item.submenu then return end
        W.CloseMenus()
        if item.onClick then item.onClick() end
    end)
    m.buttons[i] = b
    return b
end

local function getMenu(level)
    local m = menus[level]
    if m then return m end
    m = CreateFrame("Frame", nil, UIParent)
    m.level = level
    m:SetFrameStrata("FULLSCREEN_DIALOG")
    m:SetFrameLevel(10 + level * 10)
    m:SetClampedToScreen(true)
    m:EnableMouse(true)
    m.bg = W.Fill(m, "field", 0.98)
    m.bg:SetAllPoints()
    m.border = W.Border(m, "line")
    m.buttons = {}
    m:Hide()
    menus[level] = m
    return m
end

-- anchor: a frame (submenu opens to its right) or nil (at the cursor).
showMenu = function(level, items, anchor)
    hideMenu(level)
    local m = getMenu(level)
    local toArm = {}
    local width, y = (level == 1 and anchor and anchor:GetWidth()) or 160, 4
    for i, item in ipairs(items) do
        local b = menuButton(m, i)
        b.item = item
        b:ClearAllPoints()
        b:SetPoint("TOPLEFT", 0, -y)
        b:SetPoint("TOPRIGHT", 0, -y)
        local sep = item.separator
        b:SetHeight(sep and 9 or MENU_ITEM_H)
        b.line:SetShown(sep == true)
        b.text:SetShown(not sep)
        b.check:SetShown(item.checked == true)
        b.arrow:SetShown(item.submenu ~= nil)
        -- Protected actions (guild invite) run through a secure overlay; not possible in combat.
        local blocked = false
        if item.macro and not sep then
            b.secure = b.secure or W.SecureMacroOverlay(b, function() W.CloseMenus() end)
            blocked = InCombatLockdown()
            toArm[#toArm + 1] = b -- armed after the menu is shown (needs its screen position)
        elseif b.secure then
            b.secure:Disarm()
        end
        if not sep then
            -- Optional font preview (font picker); otherwise the normal menu font.
            if item.font then
                b.text:SetFont(item.font, Theme:TextSize(1), "")
            else
                Theme:SetFont(b.text, "regular", 0)
            end
            b.text:SetText(blocked and (item.text .. " (not in combat)") or item.text)
            local color = (item.disabled or blocked) and "textFaint" or item.danger and "danger" or "text"
            b.text:SetTextColor(Theme:Color(color))
            width = max(width, b.text:GetStringWidth() + 24 + 28)
        end
        b:Show()
        y = y + b:GetHeight()
    end
    for i = #items + 1, #m.buttons do m.buttons[i]:Hide() end
    m:SetSize(width, y + 4)
    m:ClearAllPoints()
    if anchor and level == 1 then
        m:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2) -- dropdown below its button
    elseif anchor then
        m:SetPoint("TOPLEFT", anchor, "TOPRIGHT", 2, 4)
    else
        local x, cy = GetCursorPosition()
        local scale = UIParent:GetEffectiveScale()
        m:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / scale, cy / scale)
    end
    m:Show()
    for _, b in ipairs(toArm) do b.secure:Arm(b.item.macro) end
end

-- anchor (optional): open below that frame, like a dropdown. Otherwise at the cursor.
function W.OpenMenu(items, anchor)
    W.HideTooltip()
    showMenu(1, items, anchor)
end

-- Close menus when clicking anywhere else.
do
    local watcher = CreateFrame("Frame")
    local ok = pcall(watcher.RegisterEvent, watcher, "GLOBAL_MOUSE_DOWN")
    if ok then
        watcher:SetScript("OnEvent", function()
            if not W.IsMenuOpen() then return end
            for _, m in ipairs(menus) do
                if m:IsShown() and m:IsMouseOver() then return end
            end
            W.CloseMenus()
        end)
    else
        -- Fallback: an invisible full-screen catcher below the menus.
        local catcher = CreateFrame("Button", nil, UIParent)
        catcher:SetAllPoints(UIParent)
        catcher:SetFrameStrata("FULLSCREEN_DIALOG")
        catcher:SetFrameLevel(1)
        catcher:RegisterForClicks("AnyUp")
        catcher:SetScript("OnClick", function() W.CloseMenus() end)
        catcher:Hide()
        hooksecurefunc(W, "OpenMenu", function() catcher:Show() end)
        hooksecurefunc(W, "CloseMenus", function() catcher:Hide() end)
    end
end

-- ---------------------------------------------------------------------------
-- Dialog inside a parent frame: confirm or text prompt.
-- opts: { title, text, input = default text or nil, okText, danger, onOk(value),
--         maxLetters (default 40), allowEmpty (input may be saved empty) }
-- ---------------------------------------------------------------------------

local dialogs = {}

function W.Dialog(parent, opts)
    local d = dialogs[parent]
    if not d then
        d = CreateFrame("Frame", nil, parent)
        d:SetAllPoints()
        d:SetFrameLevel(parent:GetFrameLevel() + 50)
        d:EnableMouse(true)
        d.dim = d:CreateTexture(nil, "BACKGROUND")
        d.dim:SetAllPoints()
        d.dim:SetColorTexture(0, 0, 0, 0.55)

        local box = CreateFrame("Frame", nil, d)
        box:SetSize(340, 150)
        box:SetPoint("CENTER")
        box.bg = W.Fill(box, "window", 1)
        box.bg:SetAllPoints()
        W.Border(box, "line")
        d.box = box

        d.title = W.Text(box, "heading", 2, "text")
        d.title:SetPoint("TOPLEFT", 16, -16)
        d.text = W.Text(box, "regular", 0, "textDim")
        d.text:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -8)
        d.text:SetWidth(308)
        d.text:SetWordWrap(true)

        d.edit = W.EditBox(box, "", 30)
        d.edit:SetWidth(308)
        d.edit:SetMaxLetters(40)

        d.cancel = W.Button(box, "Cancel", "ghost", function() d:Hide() end)
        d.cancel:SetPoint("BOTTOMRIGHT", -16, 14)
        d.okButtons = {}

        local function ok()
            local value = d.opts.input and strtrim(d.edit:GetText() or "") or true
            if d.opts.input and value == "" and not d.opts.allowEmpty then return end
            d:Hide()
            if d.opts.onOk then d.opts.onOk(value) end
        end
        d.ok = ok
        d.edit:SetScript("OnEnterPressed", ok)
        d.edit:SetScript("OnEscapePressed", function() d:Hide() end)
        d:SetScript("OnHide", function() d.edit:ClearFocus() end)
        dialogs[parent] = d
    end

    d.opts = opts
    d.title:SetText(strupper(opts.title or ""))
    d.text:SetText(opts.text or "")
    local style = opts.danger and "danger" or "accent"
    if not d.okButtons[style] then
        d.okButtons[style] = W.Button(d.box, "", style, function() d.ok() end)
        d.okButtons[style]:SetPoint("RIGHT", d.cancel, "LEFT", -8, 0)
    end
    for s, b in pairs(d.okButtons) do b:SetShown(s == style) end
    local okBtn = d.okButtons[style]
    okBtn.text:SetText(opts.okText or "OK")
    okBtn:SetWidth(okBtn.text:GetStringWidth() + 28)

    local textH = (opts.text and opts.text ~= "") and (d.text:GetStringHeight() + 8) or 0
    if opts.input then
        d.edit:ClearAllPoints()
        d.edit:SetPoint("TOPLEFT", d.title, "BOTTOMLEFT", 0, -(12 + textH))
        d.edit:SetMaxLetters(opts.maxLetters or 40)
        d.edit:SetText(opts.input)
        d.edit:Show()
        d.box:SetHeight(16 + 20 + 12 + textH + 30 + 16 + 28 + 14)
    else
        d.edit:Hide()
        d.box:SetHeight(16 + 20 + textH + 16 + 28 + 14)
    end
    d:Show()
    if opts.input then
        d.edit:SetFocus()
        d.edit:HighlightText()
    end
    return d
end

-- ---------------------------------------------------------------------------
-- Settings controls: toggle switch, segmented choice, slider, color swatch.
-- Each has :Set(value) (no callback) and calls onChange(value) on user input.
-- ---------------------------------------------------------------------------

function W.Toggle(parent, onChange)
    local t = CreateFrame("Button", nil, parent)
    t:SetSize(32, 16)
    t.track = t:CreateTexture(nil, "BACKGROUND")
    t.track:SetAllPoints()
    t.knob = t:CreateTexture(nil, "ARTWORK")
    t.knob:SetSize(12, 12)
    function t:Set(on)
        self.value = on and true or false
        self.knob:ClearAllPoints()
        if self.value then
            self.track:SetColorTexture(Theme:Accent())
            self.knob:SetColorTexture(Theme:Color("sidebar"))
            self.knob:SetPoint("RIGHT", -2, 0)
        else
            self.track:SetColorTexture(Theme:Color("line"))
            self.knob:SetColorTexture(Theme:Color("textDim"))
            self.knob:SetPoint("LEFT", 2, 0)
        end
    end
    W.OnAccent(function() if t.value ~= nil then t:Set(t.value) end end)
    t:SetScript("OnClick", function(self)
        self:Set(not self.value)
        if onChange then onChange(self.value) end
    end)
    t:Set(false)
    return t
end

-- options: { { value = "S", label = "S" }, ... }
function W.Segment(parent, options, onChange)
    local s = CreateFrame("Frame", nil, parent)
    s:SetHeight(24)
    s.buttons = {}
    local x = 0
    for i, opt in ipairs(options) do
        local b = CreateFrame("Button", nil, s)
        b.value = opt.value
        b.bg = W.Fill(b, "field", 1)
        b.bg:SetAllPoints()
        b.text = W.Text(b, "semibold", -1, "textDim")
        b.text:SetPoint("CENTER")
        b.text:SetText(opt.label)
        local w = max(36, b.text:GetStringWidth() + 20)
        b:SetSize(w, 24)
        b:SetPoint("LEFT", x, 0)
        x = x + w + 2
        b:SetScript("OnClick", function(self)
            s:Set(self.value)
            if onChange then onChange(self.value) end
        end)
        b:SetScript("OnEnter", function(self) if self.value ~= s.value then self.text:SetTextColor(Theme:Color("text")) end end)
        b:SetScript("OnLeave", function() s:Set(s.value) end)
        s.buttons[i] = b
    end
    s:SetWidth(x - 2)
    W.Border(s, "line")
    function s:Set(value)
        self.value = value
        local r, g, bl = Theme:Accent()
        for _, b in ipairs(self.buttons) do
            if b.value == value then
                b.bg:SetColorTexture(r, g, bl, 1)
                b.text:SetTextColor(Theme:Color("sidebar"))
            else
                b.bg:SetColorTexture(Theme:Color("field"))
                b.text:SetTextColor(Theme:Color("textDim"))
            end
        end
    end
    W.OnAccent(function() if s.value ~= nil then s:Set(s.value) end end)
    return s
end

-- Horizontal slider. format(value) -> label text.
function W.Slider(parent, minV, maxV, step, width, format, onChange)
    local s = CreateFrame("Slider", nil, parent)
    s:SetOrientation("HORIZONTAL")
    s:SetSize(width or 200, 16)
    s:SetMinMaxValues(minV, maxV)
    s:SetValueStep(step)
    if s.SetObeyStepOnDrag then s:SetObeyStepOnDrag(true) end
    s.track = W.Fill(s, "line", 1, "BACKGROUND")
    s.track:SetPoint("LEFT")
    s.track:SetPoint("RIGHT")
    s.track:SetHeight(2)
    local thumb = s:CreateTexture(nil, "OVERLAY")
    thumb:SetSize(10, 16)
    s:SetThumbTexture(thumb)
    W.OnAccent(function(r, g, b) thumb:SetColorTexture(r, g, b, 1) end)
    s.label = W.Text(s, "regular", -1, "textDim")
    s.label:SetPoint("LEFT", s, "RIGHT", 10, 0)
    s.silent = false
    s:SetScript("OnValueChanged", function(self, value)
        value = floor(value / step + 0.5) * step
        self.label:SetText(format and format(value) or tostring(value))
        if not self.silent and onChange then onChange(value) end
    end)
    s:EnableMouseWheel(false)
    function s:Set(value)
        self.silent = true
        self:SetValue(value)
        self.label:SetText(format and format(value) or tostring(value))
        self.silent = false
    end
    return s
end

-- Dropdown: a field-styled button that opens a menu below itself.
-- getOptions() -> { { value, label, font = path (optional preview) }, ... }
function W.Dropdown(parent, width, getOptions, onChange)
    local d = CreateFrame("Button", nil, parent)
    d:SetSize(width or 200, 26)
    d.bg = W.Fill(d, "field", 1)
    d.bg:SetAllPoints()
    d.border = W.Border(d, "line")
    d.text = W.Text(d, "regular", 0, "text")
    d.text:SetPoint("LEFT", 10, 0)
    d.text:SetWidth((width or 200) - 36)
    d.arrow = W.Icon(d, "chevronDown", 8, "v")
    d.arrow.box:ClearAllPoints()
    d.arrow.box:SetPoint("RIGHT", -10, 0)
    d.arrow:SetColor(Theme:Color("textDim"))

    function d:Set(value)
        self.value = value
        local label = tostring(value)
        for _, opt in ipairs(getOptions()) do
            if opt.value == value then label = opt.label break end
        end
        self.text:SetText(label)
    end

    d:SetScript("OnEnter", function(self) self.border:SetColor(Theme:Color("textFaint")) end)
    d:SetScript("OnLeave", function(self) self.border:SetColor(Theme:Color("line")) end)
    d:SetScript("OnClick", function(self)
        if W.IsMenuOpen() then W.CloseMenus() return end
        local items = {}
        for _, opt in ipairs(getOptions()) do
            items[#items + 1] = {
                text = opt.label,
                font = opt.font,
                checked = opt.value == self.value,
                onClick = function()
                    self:Set(opt.value)
                    if onChange then onChange(opt.value) end
                end,
            }
        end
        W.OpenMenu(items, self)
    end)
    return d
end

-- Square color swatch with a selection ring.
function W.Swatch(parent, r, g, b, tooltip, onClick)
    local s = CreateFrame("Button", nil, parent)
    s:SetSize(22, 22)
    s.ring = W.Border(s, "line")
    s.fill = s:CreateTexture(nil, "ARTWORK")
    s.fill:SetPoint("TOPLEFT", 3, -3)
    s.fill:SetPoint("BOTTOMRIGHT", -3, 3)
    s.fill:SetColorTexture(r, g, b, 1)
    function s:SetSelected(on)
        if on then self.ring:SetColor(Theme:Color("text")) else self.ring:SetColor(Theme:Color("line")) end
    end
    s:SetScript("OnEnter", function(self) if tooltip then W.ShowTooltip(self, tooltip) end end)
    s:SetScript("OnLeave", function() W.HideTooltip() end)
    s:SetScript("OnClick", function() if onClick then onClick() end end)
    return s
end

-- Resize bounds differ between client generations.
function W.SetResizeBounds(frame, minW, minH, maxW, maxH)
    if frame.SetResizeBounds then
        frame:SetResizeBounds(minW, minH, maxW, maxH)
    else
        if frame.SetMinResize then frame:SetMinResize(minW, minH) end
        if frame.SetMaxResize and maxW then frame:SetMaxResize(maxW, maxH) end
    end
end

Compat.features.CreateLine = UIParent.CreateLine ~= nil
