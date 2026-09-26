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
    elseif key == "textSize" then
        W.RefreshFonts()
    end
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
        W.Fill(tip, "field", 0.98)
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
