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
    bnet      = { hex("82C5FF") },
    party     = { hex("AAABFE") },
    raid      = { hex("FF7F00") },
    warning   = { hex("FF4800") },
}

-- ---------------------------------------------------------------------------
-- Themes. "hush" is the original look and changes nothing. Other themes override the
-- base palette (and suggest an accent). The theme is applied once at load, before any
-- UI is built, so switching needs a /reload and costs nothing while playing.
-- ---------------------------------------------------------------------------

Theme.THEMES = {
    { id = "hush", name = "Hush Original", accent = "3FC7EB" },
    { id = "midnight", name = "Midnight", accent = "7AA2F7", palette = {
        window = "0E1220", sidebar = "0A0E19", field = "141A2B", selected = "1B2338", line = "242D45",
        text = "E4E8F2", textDim = "98A2B8", textFaint = "7A849A" } },
    { id = "graphite", name = "Graphite", accent = "8AB4F8", palette = {
        window = "1A1A1C", sidebar = "141416", field = "222225", selected = "2A2A2E", line = "333338",
        text = "EDEDED", textDim = "A0A0A5", textFaint = "7E7E84" } },
    { id = "horde", name = "Horde", accent = "C8332E", palette = {
        window = "160E0E", sidebar = "110A0A", field = "1F1414", selected = "2A1A1A", line = "3A2222",
        text = "EFE6E4", textDim = "B09A96", textFaint = "8A7672" } },
    { id = "alliance", name = "Alliance", accent = "E0B24A", palette = {
        window = "0D1320", sidebar = "0A0F1A", field = "141C2E", selected = "1B2640", line = "25324F",
        text = "E6ECF5", textDim = "9AA8C0", textFaint = "7784A0" } },
    -- Classic Blizzard frames (dialog backdrop, stone border, red buttons). Only this theme
    -- uses textures; everything it changes is gated by Theme:IsBlizzard().
    { id = "blizzard", name = "Blizzard Style", accent = "FFD100", style = "blizzard", palette = {
        window = "000000", sidebar = "000000", field = "0B0B0B", selected = "2B2416", line = "5A5344",
        text = "FFFFFF", textDim = "CFC6AE", textFaint = "9A9280" } },
}

function Theme:GetTheme(id)
    for _, t in ipairs(self.THEMES) do
        if t.id == id then return t end
    end
    return self.THEMES[1]
end

-- The original palette, kept for previews while another theme is active.
local BASE = {}
for key, c in pairs(Theme.colors) do BASE[key] = { c[1], c[2], c[3] } end

-- Palette of a theme as { key = { r, g, b } } (for previews), falling back to the original.
function Theme:ThemeColor(t, key)
    local h = t.palette and t.palette[key]
    if h then return hex(h) end
    local c = BASE[key]
    return c[1], c[2], c[3]
end

function Theme:IsBlizzard()
    return self.current ~= nil and self.current.style == "blizzard"
end

-- Apply the saved theme (called once, right after SavedVariables load).
function Theme:ApplyTheme()
    local t = self:GetTheme(Hush.settings and Hush.settings.theme)
    self.current = t
    if t.palette then
        for key, h in pairs(t.palette) do self.colors[key] = { hex(h) } end
    end
end

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

-- Hush's own Barlow files (WoW Forever currently refuses them; kept for when it doesn't).
local BUNDLED = {
    regular  = FONT_DIR .. "Barlow-Regular.ttf",
    medium   = FONT_DIR .. "Barlow-Medium.ttf",
    semibold = FONT_DIR .. "Barlow-SemiBold.ttf",
    heading  = FONT_DIR .. "BarlowCondensed-SemiBold.ttf",
}

-- Fonts in use per kind, resolved by Theme:ApplyFontChoice().
Theme.fonts = {
    regular = FALLBACK, medium = FALLBACK, semibold = FALLBACK, heading = FALLBACK,
}
Theme.fontStatus = "not checked"

-- Fonts that ship with the game client.
local BUILTIN_FONTS = {
    { name = "Friz Quadrata", path = "Fonts\\FRIZQT__.TTF" },
    { name = "Arial Narrow",  path = "Fonts\\ARIALN.TTF" },
    { name = "Skurri",        path = "Fonts\\skurri.ttf" },
    { name = "Morpheus",      path = "Fonts\\MORPHEUS.ttf" },
}

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

-- Whether a font file loads on this client (cached per path).
local validCache = {}
local function valid(path)
    if not path then return false end
    if validCache[path] == nil then validCache[path] = fontLoads(path) and true or false end
    return validCache[path]
end

-- LibSharedMedia, if another addon provides it (Hush does not bundle it).
local function lsm()
    return LibStub and LibStub("LibSharedMedia-3.0", true)
end

-- Every font that loads here: game fonts, then fonts other addons registered in
-- LibSharedMedia, sorted by name. Returns { { name, path }, ... }.
function Theme:AvailableFonts()
    local list, seen = {}, {}
    local function add(name, path)
        local key = normalizePath(path)
        if not seen[key] and valid(path) then
            seen[key] = true
            list[#list + 1] = { name = name, path = path }
        end
    end
    for _, f in ipairs(BUILTIN_FONTS) do add(f.name, f.path) end
    local L = lsm()
    if L then
        local shared = {}
        for name, path in pairs(L:HashTable("font") or {}) do shared[#shared + 1] = { name = name, path = path } end
        sort(shared, function(a, b) return a.name < b.name end)
        for _, f in ipairs(shared) do add(f.name, f.path) end
    end
    return list
end

-- Path for a font name from the list above, or nil.
function Theme:FontPath(name)
    for _, f in ipairs(BUILTIN_FONTS) do
        if f.name == name then return f.path end
    end
    local L = lsm()
    return L and L:IsValid("font", name) and L:Fetch("font", name) or nil
end

-- Resolve settings.font / settings.headingFont ("auto" or a font name) into Theme.fonts.
-- Automatic: Hush's Barlow if the client accepts it, otherwise the game font for text and
-- "Barlow Condensed" from LibSharedMedia (if registered by another addon) for headings.
function Theme:ApplyFontChoice()
    local s = Hush.settings or {}
    local text = s.font and s.font ~= "auto" and self:FontPath(s.font)
    if text and not valid(text) then text = nil end
    local head = s.headingFont and s.headingFont ~= "auto" and self:FontPath(s.headingFont)
    if head and not valid(head) then head = nil end

    for _, kind in ipairs({ "regular", "medium", "semibold" }) do
        self.fonts[kind] = text or (valid(BUNDLED[kind]) and BUNDLED[kind]) or FALLBACK
    end
    local sharedCondensed = self:FontPath("Barlow Condensed")
    self.fonts.heading = head
        or (self:IsBlizzard() and FALLBACK) -- Blizzard Style: Friz Quadrata headings
        or (valid(BUNDLED.heading) and BUNDLED.heading)
        or (sharedCondensed and valid(sharedCondensed) and sharedCondensed)
        or FALLBACK
end

function Theme:CheckFonts()
    local missing = {}
    self.fontDiag = {}
    for key, path in pairs(BUNDLED) do
        local loaded, diag = fontLoads(path)
        self.fontDiag[key] = diag
        if not loaded then missing[#missing + 1] = key end
    end
    self.fontStatus = #missing == 0 and "Barlow ok" or ("bundled Barlow refused for " .. table.concat(missing, ", "))
    self:ApplyFontChoice()
end

-- Font changes: resolve before widgets refresh (Theme registers first).
Hush:RegisterCallback("SETTINGS_CHANGED", function(_, key)
    if key == "font" or key == "headingFont" then Theme:ApplyFontChoice() end
end, "Theme")

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

-- ---------------------------------------------------------------------------
-- Temporary: check that the classic Blizzard textures exist on this client before
-- building the "Blizzard Style" theme. Removed once that theme is in place.
-- ---------------------------------------------------------------------------

local TEST_TEXTURES = {
    { "dialog background", "Interface\\DialogFrame\\UI-DialogBox-Background-Dark" },
    { "dialog border", "Interface\\DialogFrame\\UI-DialogBox-Border" },
    { "dialog header", "Interface\\DialogFrame\\UI-DialogBox-Header" },
    { "red button", "Interface\\Buttons\\UI-Panel-Button-Up" },
    { "red button pressed", "Interface\\Buttons\\UI-Panel-Button-Down" },
    { "button highlight", "Interface\\Buttons\\UI-Panel-Button-Highlight" },
    { "close button", "Interface\\Buttons\\UI-Panel-MinimizeButton-Up" },
    { "tooltip border", "Interface\\Tooltips\\UI-Tooltip-Border" },
}

local testFrame
Hush:AddSlashCommand("texturetest", function()
    if testFrame then testFrame:SetShown(not testFrame:IsShown()) return end
    local texProbe = UIParent:CreateTexture(nil, "BACKGROUND")
    for _, t in ipairs(TEST_TEXTURES) do
        local ok = texProbe:SetTexture(t[2])
        Hush:Print(("  %s: %s"):format(t[1], ok == false and "|cffe0564fmissing|r" or "|cff3fc77fok|r"))
    end
    texProbe:Hide()

    local f = CreateFrame("Frame", nil, UIParent, BackdropTemplateMixin and "BackdropTemplate" or nil)
    f:SetSize(300, 190)
    f:SetPoint("CENTER", 0, 80)
    f:SetFrameStrata("DIALOG")
    if f.SetBackdrop then
        f:SetBackdrop({
            bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
            edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
            tile = true, tileSize = 32, edgeSize = 32,
            insets = { left = 11, right = 12, top = 12, bottom = 11 },
        })
    end
    local header = f:CreateTexture(nil, "ARTWORK")
    header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header")
    header:SetSize(256, 64)
    header:SetPoint("TOP", 0, 12)
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", header, "TOP", 0, -14)
    title:SetText("Hush")
    for i, label in ipairs({ "Blizzard Style", "Close test" }) do
        local b = CreateFrame("Button", nil, f)
        b:SetSize(160, 24)
        b:SetPoint("TOP", 0, -40 - (i - 1) * 30)
        b:SetNormalTexture("Interface\\Buttons\\UI-Panel-Button-Up")
        b:SetPushedTexture("Interface\\Buttons\\UI-Panel-Button-Down")
        b:SetHighlightTexture("Interface\\Buttons\\UI-Panel-Button-Highlight", "ADD")
        for _, tex in ipairs({ b:GetNormalTexture(), b:GetPushedTexture(), b:GetHighlightTexture() }) do
            tex:SetTexCoord(0, 0.625, 0, 0.6875)
        end
        local fs = b:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        fs:SetPoint("CENTER")
        fs:SetText(label)
        if i == 2 then b:SetScript("OnClick", function() f:Hide() end) end
    end
    local note = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    note:SetPoint("BOTTOM", 0, 22)
    note:SetText("Texture test – take a screenshot")
    testFrame = f
end, "show a test window with classic Blizzard textures")
