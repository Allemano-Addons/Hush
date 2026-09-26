-- Theme: all colors, sizes and fonts live here.
local addonName, Hush = ...

local Theme = {}
Hush.Theme = Theme

local function hex(s)
    return tonumber(s:sub(1, 2), 16) / 255, tonumber(s:sub(3, 4), 16) / 255, tonumber(s:sub(5, 6), 16) / 255
end
Theme.Hex = hex

Theme.colors = {
    window    = { hex("111418") },
    sidebar   = { hex("0D1013") },
    field     = { hex("15191E") },
    selected  = { hex("1A1F26") },
    line      = { hex("22272E") },
    text      = { hex("E6E8EB") },
    textDim   = { hex("9AA3AD") },
    textFaint = { hex("7C858F") },
    online    = { hex("3FC77F") },
    away      = { hex("E8A33D") },
    offline   = { hex("5A626B") },
    danger    = { hex("E0564F") },
}

-- r, g, b for a named color.
function Theme:Color(key)
    local c = self.colors[key]
    return c[1], c[2], c[3]
end

-- Accent: class color if chosen, otherwise the saved hex.
function Theme:Accent()
    local s = Hush.settings
    if s and s.useClassColor then
        local r, g, b = Hush.Compat.ClassColor(Hush.Compat.PlayerClass())
        if r then return r, g, b end
    end
    return hex(s and s.accent or "3FC7EB")
end

Theme.size = {
    windowW = 1000,
    windowH = 620,
    windowMinW = 720,
    windowMinH = 420,
    sidebarW = 300,
    titleH = 40,
    searchH = 28,
    tabH = 30,
    categoryH = 24,
    chatRowH = 52,
    headerH = 64,
    inputH = 34,
    quickReplyH = 22,
    padding = 12,
    gap = 8,
}

Theme.textSizes = { S = 11, M = 12, L = 14 }

function Theme:TextSize(delta)
    local s = Hush.settings and Hush.settings.textSize or "M"
    return (self.textSizes[s] or 12) + (delta or 0)
end

-- ---------------------------------------------------------------------------
-- Fonts: Barlow if the files load, otherwise the default Blizzard font.
-- ---------------------------------------------------------------------------

local FONT_DIR = "Interface\\AddOns\\" .. addonName .. "\\Media\\Fonts\\"
local FALLBACK = "Fonts\\FRIZQT__.TTF"

Theme.fonts = {
    regular  = FONT_DIR .. "Barlow-Regular.ttf",
    medium   = FONT_DIR .. "Barlow-Medium.ttf",
    semibold = FONT_DIR .. "Barlow-SemiBold.ttf",
    heading  = FONT_DIR .. "BarlowCondensed-SemiBold.ttf",
}
Theme.fontStatus = "not checked"

local function normalizePath(p)
    return p and strlower((p:gsub("/", "\\"))) or ""
end

local probe
-- Returns loaded (bool) and a short diagnostic string.
local function fontLoads(path)
    probe = probe or UIParent:CreateFontString(nil, "BACKGROUND")
    probe:SetFont(FALLBACK, 12, "")
    local ok = probe:SetFont(path, 12, "")
    local current = probe:GetFont()
    local diag = ("SetFont=%s GetFont=%s"):format(tostring(ok), tostring(current))
    -- Newer clients report success directly; older ones return nil, so compare paths.
    if ok == true then return true, diag end
    if ok == false then return false, diag end
    return normalizePath(current) == normalizePath(path), diag
end

function Theme:CheckFonts()
    local missing = {}
    self.fontDiag = {}
    for key, path in pairs(self.fonts) do
        local loaded, diag = fontLoads(path)
        self.fontDiag[key] = diag
        if not loaded then
            self.fonts[key] = FALLBACK
            missing[#missing + 1] = key
        end
    end
    self.fontStatus = #missing == 0 and "Barlow ok" or ("fallback for " .. table.concat(missing, ", "))
end

-- Apply a font to a FontString. kind: regular/medium/semibold/heading.
function Theme:SetFont(fs, kind, delta)
    fs:SetFont(self.fonts[kind or "regular"] or FALLBACK, self:TextSize(delta), "")
    fs:SetShadowOffset(0, 0)
end

-- ---------------------------------------------------------------------------
-- Pixel-perfect sizing
-- ---------------------------------------------------------------------------

-- Size of one physical pixel in the frame's coordinate space.
function Theme:Pixel(frame)
    local _, physH = Hush.Compat.GetPhysicalScreenSize()
    local scale = (frame or UIParent):GetEffectiveScale()
    return 768 / physH / scale
end

-- Round a size to whole physical pixels.
function Theme:Snap(value, frame)
    local px = self:Pixel(frame)
    return floor(value / px + 0.5) * px
end
