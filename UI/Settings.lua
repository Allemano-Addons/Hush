-- Settings: own panel in the Hush style. Left menu with pages, "Unlock & move" and
-- "Clear all chats" at the bottom. Modules can add pages with Settings.AddPage.
local _, Hush = ...

local Theme, W, Data = Hush.Theme, Hush.Widgets, Hush.Data
local S = Theme.size

local Settings = {}
Hush.Settings = Settings

local WIDTH, HEIGHT, MENU_W = 760, 620, 190
local PAD = 28

local frame
local pages = {}      -- { id, label, build, frame }
local current
local moveMode = false

-- Change a setting and tell everyone.
function Settings.Set(key, value)
    Hush.settings[key] = value
    Hush:Fire("SETTINGS_CHANGED", key, value)
end

local function get(key) return function() return Hush.settings[key] end end
local function set(key) return function(v) Settings.Set(key, v) end end

-- ---------------------------------------------------------------------------
-- Page builder
-- ---------------------------------------------------------------------------

local Page = {}
Page.__index = Page

local function newPage(parent, label)
    local f = CreateFrame("Frame", nil, parent)
    f:SetAllPoints()
    f:Hide()
    local p = setmetatable({ frame = f, y = -24, refreshers = {} }, Page)
    local title = W.Text(f, "heading", 5, "text")
    title:SetPoint("TOPLEFT", PAD, p.y)
    title:SetText(strupper(label))
    p.y = p.y - 40
    return p
end

function Page:Header(text)
    self.y = self.y - 8
    local fs = W.Text(self.frame, "heading", -1, "textFaint")
    fs:SetPoint("TOPLEFT", PAD, self.y)
    fs:SetText(strupper(text))
    self.y = self.y - 22
end

function Page:Text(text)
    local fs = W.Text(self.frame, "regular", -1, "textDim")
    fs:SetPoint("TOPLEFT", PAD, self.y)
    fs:SetWidth(WIDTH - MENU_W - PAD * 2)
    fs:SetWordWrap(true)
    fs:SetText(text)
    self.y = self.y - fs:GetStringHeight() - 12
    return fs
end

-- A labeled row with a control on the right.
function Page:Row(label, desc, control)
    local top = self.y
    local fs = W.Text(self.frame, "semibold", 0, "text")
    fs:SetPoint("TOPLEFT", PAD, top - 4)
    fs:SetText(label)
    local h = 30
    if desc then
        local d = W.Text(self.frame, "regular", -2, "textFaint")
        d:SetPoint("TOPLEFT", fs, "BOTTOMLEFT", 0, -4)
        d:SetText(desc)
        h = 44
    end
    control:SetParent(self.frame)
    control:ClearAllPoints()
    control:SetPoint("TOPRIGHT", self.frame, "TOPRIGHT", -PAD - (control.rightPad or 0), top - 4)
    local line = W.Fill(self.frame, "line", 1, "BORDER")
    line:SetPoint("TOPLEFT", PAD, top - h - 4)
    line:SetPoint("TOPRIGHT", -PAD, top - h - 4)
    W.PixelSize(line, self.frame, "h")
    self.y = top - h - 12
end

function Page:Toggle(label, desc, getter, setter)
    local t = W.Toggle(self.frame, setter)
    self:Row(label, desc, t)
    self.refreshers[#self.refreshers + 1] = function() t:Set(getter()) end
    return t
end

function Page:Segment(label, desc, options, getter, setter)
    local s = W.Segment(self.frame, options, setter)
    self:Row(label, desc, s)
    self.refreshers[#self.refreshers + 1] = function() s:Set(getter()) end
    return s
end

-- getOptions() -> { { value, label, font = path (optional preview) }, ... }
function Page:Dropdown(label, desc, getOptions, getter, setter)
    local d = W.Dropdown(self.frame, 220, getOptions, setter)
    self:Row(label, desc, d)
    self.refreshers[#self.refreshers + 1] = function() d:Set(getter()) end
    return d
end

function Page:Slider(label, desc, minV, maxV, step, fmt, getter, setter)
    local s = W.Slider(self.frame, minV, maxV, step, 180, fmt, setter)
    s.rightPad = 44 -- room for the value label
    self:Row(label, desc, s)
    self.refreshers[#self.refreshers + 1] = function() s:Set(getter()) end
    return s
end

function Page:Button(label, desc, buttonText, style, onClick)
    local b = W.Button(self.frame, buttonText, style or "default", onClick)
    self:Row(label, desc, b)
    return b
end

-- Free-form block: fn(container) builds inside a frame of the given height.
function Page:Custom(height, fn)
    local c = CreateFrame("Frame", nil, self.frame)
    c:SetPoint("TOPLEFT", PAD, self.y)
    c:SetPoint("TOPRIGHT", -PAD, self.y)
    c:SetHeight(height)
    local refresh = fn(c)
    if refresh then self.refreshers[#self.refreshers + 1] = refresh end
    self.y = self.y - height - 12
    return c
end

function Page:Refresh()
    for _, r in ipairs(self.refreshers) do r() end
end

-- ---------------------------------------------------------------------------
-- Built-in pages
-- ---------------------------------------------------------------------------

local CLASS_ORDER = { "WARRIOR", "PALADIN", "HUNTER", "ROGUE", "PRIEST", "SHAMAN", "MAGE", "WARLOCK", "DRUID" }

local function buildGeneral(p)
    p:Header("Launcher")
    p:Toggle("Show launcher button", "The small Hush button with the unread badge.",
        function() return not Hush.db.launcher.hidden end,
        function(v) Hush.Launcher.SetHidden(not v) end)
    p:Toggle("Lock launcher position", nil,
        function() return Hush.db.launcher.locked == true end,
        function(v) Hush.db.launcher.locked = v end)
    p:Header("Window")
    p:Button("Window position and size", "Move the Hush window back to the center at 1000×620.", "Reset", "default",
        function() Hush.Main.ResetPosition() end)
    p:Header("About")
    p:Text("Hush " .. tostring(Hush.version) .. " for WoW Forever.  /hush opens and closes the window, /hush help lists all commands. "
        .. "Key bindings: Key Bindings → AddOns → Hush.")
end

local function buildAppearance(p)
    p:Header("Accent color")
    p:Custom(26, function(c)
        local swatches = {}
        local function select()
            local s = Hush.settings
            for _, sw in ipairs(swatches) do
                sw:SetSelected(not s.useClassColor and strupper(s.accent) == sw.hex)
            end
        end
        local function add(hexStr, tooltip)
            local r, g, b = Theme.Hex(hexStr)
            local sw = W.Swatch(c, r, g, b, tooltip, function()
                Settings.Set("useClassColor", false)
                Settings.Set("accent", hexStr)
                select()
                p:Refresh()
            end)
            sw.hex = hexStr
            sw:SetPoint("LEFT", (#swatches) * 28, 0)
            swatches[#swatches + 1] = sw
        end
        add("3FC7EB", "Hush")
        for _, class in ipairs(CLASS_ORDER) do
            local color = RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
            if color then
                local hexStr = ("%02X%02X%02X"):format(floor(color.r * 255 + 0.5), floor(color.g * 255 + 0.5), floor(color.b * 255 + 0.5))
                local name = LOCALIZED_CLASS_NAMES_MALE and LOCALIZED_CLASS_NAMES_MALE[class] or class
                add(hexStr, name)
            end
        end
        return select
    end)
    p:Toggle("Use my class color", "Follows the class of the character you are playing.",
        get("useClassColor"), set("useClassColor"))
    p:Slider("Background opacity", nil, 50, 100, 5,
        function(v) return v .. "%" end,
        function() return floor((Hush.settings.bgAlpha or 0.95) * 100 + 0.5) end,
        function(v) Settings.Set("bgAlpha", v / 100) end)
    -- Only fonts that load on this client are listed; each is shown in its own font.
    local function fontOptions(autoLabel)
        local opts = { { value = "auto", label = autoLabel } }
        for _, f in ipairs(Theme:AvailableFonts()) do
            opts[#opts + 1] = { value = f.name, label = f.name, font = f.path }
        end
        return opts
    end
    p:Header("Fonts")
    p:Dropdown("Text font", "Game fonts and fonts shared by other addons (LibSharedMedia).",
        function() return fontOptions("Automatic (game font)") end, get("font"), set("font"))
    p:Dropdown("Heading font", "Titles, categories and dividers.",
        function() return fontOptions("Automatic (Barlow Condensed if available)") end, get("headingFont"), set("headingFont"))
    p:Header("Layout")
    p:Segment("Text size", nil,
        { { value = "S", label = "S" }, { value = "M", label = "M" }, { value = "L", label = "L" } },
        get("textSize"), set("textSize"))
    p:Segment("Message style", nil,
        { { value = "compact", label = "Compact" }, { value = "bubbles", label = "Bubbles" } },
        get("msgStyle"), set("msgStyle"))
    p:Toggle("Show portraits", "Initials in class color next to messages.", get("portraits"), set("portraits"))
    p:Toggle("Show timestamps", "24-hour time next to each sender.", get("timestamps"), set("timestamps"))
end

local function buildThemes(p)
    p:Text("A theme changes the colors of Hush. Switching needs a UI reload; your settings, chats and "
        .. "features stay the same. Picking a theme also sets its accent color, which you can still change under Appearance.")
    local themes = Theme.THEMES
    p:Custom(#themes * 52, function(c)
        local cards = {}
        for i, t in ipairs(themes) do
            local card = CreateFrame("Button", nil, c)
            card:SetPoint("TOPLEFT", 0, -(i - 1) * 52)
            card:SetPoint("TOPRIGHT", 0, -(i - 1) * 52)
            card:SetHeight(44)
            card.bg = W.Fill(card, "field", 1)
            card.bg:SetAllPoints()
            card.border = W.Border(card, "line")

            -- Palette preview: window, sidebar, field, line, text, accent.
            local x = 12
            for _, key in ipairs({ "window", "sidebar", "field", "line", "text" }) do
                local sw = card:CreateTexture(nil, "ARTWORK")
                sw:SetSize(16, 16)
                sw:SetPoint("LEFT", x, 0)
                sw:SetColorTexture(Theme:ThemeColor(t, key))
                x = x + 18
            end
            local acc = card:CreateTexture(nil, "ARTWORK")
            acc:SetSize(16, 16)
            acc:SetPoint("LEFT", x + 4, 0)
            acc:SetColorTexture(Theme.Hex(t.accent))

            card.name = W.Text(card, "semibold", 1, "text")
            card.name:SetPoint("LEFT", x + 34, 0)
            card.name:SetText(t.name)
            card.tag = W.Text(card, "regular", -1, "textFaint")
            card.tag:SetPoint("RIGHT", -12, 0)

            card:SetScript("OnEnter", function(self) self.bg:SetColorTexture(Theme:Color("selected")) end)
            card:SetScript("OnLeave", function(self) self.bg:SetColorTexture(Theme:Color("field")) end)
            card:SetScript("OnClick", function()
                if (Hush.settings.theme or "hush") == t.id then return end
                Hush.settings.theme = t.id
                Hush.settings.accent = t.accent
                p:Refresh()
                W.Dialog(frame, {
                    title = "Reload UI",
                    text = "\"" .. t.name .. "\" is applied after a UI reload. Reload now?",
                    okText = "Reload",
                    macro = "/reload", -- ReloadUI() is blocked for addons on WoW Forever
                })
            end)
            card.theme = t
            cards[i] = card
        end
        return function()
            local chosen = Hush.settings.theme or "hush"
            local applied = Theme.current and Theme.current.id or "hush"
            for _, card in ipairs(cards) do
                local id = card.theme.id
                if id == applied and id == chosen then
                    card.tag:SetText("Active")
                    card.border:SetColor(Theme:Accent())
                elseif id == chosen then
                    card.tag:SetText("Selected – reload to apply")
                    card.border:SetColor(Theme:Accent())
                else
                    card.tag:SetText("")
                    card.border:SetColor(Theme:Color("line"))
                end
            end
        end
    end)
end

local function buildBehavior(p)
    p:Segment("Chat list", "Categories groups chats. Recent shows the newest first (pinned stay on top).",
        { { value = "categories", label = "Categories" }, { value = "recent", label = "Recent" } },
        get("listMode"), set("listMode"))
    p:Toggle("Hide whispers in the default chat", "Never while in combat. Everything is always saved in Hush.",
        get("hideWhispers"), set("hideWhispers"))
    p:Toggle("Hide Hush in combat", "Opens again after combat if it was open.", get("hideInCombat"), set("hideInCombat"))
    p:Segment("On incoming whisper", "Never in combat, never takes keyboard focus.",
        { { value = "popup", label = "Popup" }, { value = "open", label = "Open Hush" }, { value = "none", label = "Nothing" } },
        get("incomingAction"), set("incomingAction"))
    p:Toggle("Open on outgoing whisper", "When you whisper someone from the default chat.",
        get("autoOpenOut"), set("autoOpenOut"))
    p:Toggle("Dim the window while moving", "Fades Hush while your character runs, unless you are typing in it.",
        get("fadeWhenMoving"), set("fadeWhenMoving"))
end

local function buildNotifications(p)
    p:Toggle("Sound on new whisper", "Never in combat.", get("sound"), set("sound"))
    local options = {}
    for _, s in ipairs(Hush.Notify.SOUNDS) do options[#options + 1] = { value = s.id, label = s.label } end
    p:Segment("Sound", "Plays when you pick it.", options, get("soundKey"), function(v)
        Settings.Set("soundKey", v)
        Hush.Notify.PlaySound(v)
    end)
    p:Toggle("Combat summary", "\"3 whispers during combat\" after combat, click to open.",
        get("combatToast"), set("combatToast"))
    p:Button("Preview", nil, "Show", "default", function()
        Hush.Toast.Show("2 whispers during combat", "From Sigrid and Ivar  ·  click to open")
    end)

    p:Header("Popup")
    p:Segment("Corner", "Or drag it: Unlock & move.",
        { { value = "TOPLEFT", label = "Top L" }, { value = "TOPRIGHT", label = "Top R" },
          { value = "BOTTOMLEFT", label = "Bottom L" }, { value = "BOTTOMRIGHT", label = "Bottom R" } },
        function() return not Hush.db.popup.left and Hush.settings.popupCorner or nil end,
        function(v) Hush.Popup.SetCorner(v) end)
    p:Slider("Show for", "Hovering or typing keeps it open.", 4, 20, 1, function(v) return v .. " s" end,
        get("popupDuration"), set("popupDuration"))
    p:Toggle("Popups for unknown players", "Whispers that land in Requests.", get("popupRequests"), set("popupRequests"))
    p:Toggle("Popups for group chat", "Party and raid messages (they always show in the default chat).",
        get("popupGroups"), set("popupGroups"))
    p:Button("Preview", nil, "Show", "default", function() Hush.Popup.Preview() end)
end

local function buildQuickReplies(p)
    p:Text("Up to 10 replies, shown as buttons above the message field. {name} is replaced with the "
        .. "other player's name. Click fills the field, shift-click sends.")
    p:Custom(10 * 34, function(c)
        local boxes = {}
        local function save()
            local list = {}
            for i, box in ipairs(boxes) do list[i] = strtrim(box:GetText() or "") end
            Hush.db.quickReplies = list
            Hush:Fire("QUICK_REPLIES_CHANGED")
        end
        for i = 1, 10 do
            local e = W.EditBox(c, "Reply " .. i, 28)
            e:SetPoint("TOPLEFT", 0, -(i - 1) * 34)
            e:SetPoint("TOPRIGHT", 0, -(i - 1) * 34)
            e:SetMaxLetters(200)
            e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
            e:HookScript("OnEditFocusLost", save)
            e:SetScript("OnTabPressed", function() if boxes[i + 1] then boxes[i + 1]:SetFocus() end end)
            boxes[i] = e
        end
        return function()
            for i, box in ipairs(boxes) do box:SetText(Hush.db.quickReplies[i] or "") end
        end
    end)
end

local function buildStorage(p)
    p:Text("Everything Hush keeps is loaded at login, so less history means shorter loading screens. "
        .. "The rules below run once per login. Saved messages are never removed.")
    p:Segment("Messages per chat", "Oldest messages are dropped first.",
        { { value = 50, label = "50" }, { value = 100, label = "100" }, { value = 200, label = "200" }, { value = 500, label = "500" } },
        get("maxMessages"), set("maxMessages"))
    p:Segment("Delete group chats after", "Party and raid chats with no messages for this long.",
        { { value = 0, label = "Off" }, { value = 3, label = "3d" }, { value = 7, label = "7d" }, { value = 14, label = "14d" }, { value = 30, label = "30d" } },
        get("groupRetentionDays"), set("groupRetentionDays"))
    p:Segment("Delete inactive whispers after", "Never pinned chats, unread chats or active recruits.",
        { { value = 0, label = "Off" }, { value = 30, label = "30d" }, { value = 60, label = "60d" }, { value = 90, label = "90d" }, { value = 180, label = "180d" } },
        get("whisperRetentionDays"), set("whisperRetentionDays"))

    p:Header("Usage")
    p:Custom(20, function(c)
        local fs = W.Text(c, "regular", 0, "textDim")
        fs:SetPoint("TOPLEFT")
        return function()
            local chats, msgs, saved, bytes = Data.Stats()
            local size = bytes >= 1048576 and ("%.1f MB"):format(bytes / 1048576) or ("%d KB"):format(ceil(bytes / 1024))
            fs:SetText(("%d chats  ·  %d messages  ·  %d saved  ·  about %s on disk (all characters)"):format(chats, msgs, saved, size))
        end
    end)
    p:Button("Clean up now", "Apply the rules above right away.", "Clean up", "default", function()
        local chats, trimmed = Data.Cleanup(true)
        if chats == 0 and trimmed == 0 then
            Hush:Print("Nothing to clean up.")
            return
        end
        W.Dialog(frame, {
            title = "Clean up",
            text = ("Remove %d chat%s and %d old message%s?"):format(chats, chats == 1 and "" or "s", trimmed, trimmed == 1 and "" or "s"),
            okText = "Clean up",
            danger = true,
            onOk = function()
                Data.Cleanup()
                p:Refresh()
            end,
        })
    end)
    -- Other characters' history (alts): size and "Forget".
    local others = {}
    for _, c in ipairs(Data.Characters()) do
        if not c.current then others[#others + 1] = c end
    end
    if #others > 0 then
        p:Header("Other characters")
        local shown = min(#others, 6)
        p:Custom(shown * 30, function(c)
            local rows = {}
            for i = 1, shown do
                local info = others[i]
                local row = CreateFrame("Frame", nil, c)
                row:SetPoint("TOPLEFT", 0, -(i - 1) * 30)
                row:SetPoint("TOPRIGHT", 0, -(i - 1) * 30)
                row:SetHeight(28)
                row.label = W.Text(row, "semibold", 0, "text")
                row.label:SetPoint("LEFT")
                row.stats = W.Text(row, "regular", -1, "textFaint")
                row.stats:SetPoint("LEFT", row.label, "RIGHT", 10, 0)
                row.forget = W.Button(row, "Forget", "ghost", function()
                    W.Dialog(frame, {
                        title = "Forget character",
                        text = "Delete all Hush history (chats, categories, saved messages) of "
                            .. (info.char.name or info.key) .. "? This cannot be undone.",
                        okText = "Forget",
                        danger = true,
                        onOk = function()
                            Data.ForgetCharacter(info.key)
                            row:Hide()
                            p:Refresh()
                        end,
                    })
                end)
                row.forget:SetPoint("RIGHT")
                -- The shared bucket from before 0.1.18: move it into the character you play.
                if info.char.legacy then
                    row.merge = W.Button(row, "Merge here", "accent", function()
                        W.Dialog(frame, {
                            title = "Merge older data",
                            text = "Move these chats, categories and saved messages into "
                                .. Hush.Compat.PlayerName() .. "? Do this on the character they belong to.",
                            okText = "Merge",
                            onOk = function()
                                Data.MergeCharacter(info.key)
                                row:Hide()
                                p:Refresh()
                                Hush:Print("Older data merged into " .. Hush.Compat.PlayerName() .. ".")
                            end,
                        })
                    end)
                    row.merge:SetHeight(24)
                    row.merge:SetPoint("RIGHT", row.forget, "LEFT", -6, 0)
                end
                row.forget.text:SetTextColor(Theme:Color("danger"))
                row.forget:SetScript("OnLeave", function(self) self.text:SetTextColor(Theme:Color("danger")) end)
                row.info = info
                rows[i] = row
            end
            return function()
                for _, row in ipairs(rows) do
                    local char = Hush.db.chars[row.info.key]
                    if char then
                        local chats, msgs = 0, 0
                        for _, conv in pairs(char.convs or {}) do chats = chats + 1; msgs = msgs + #conv.msgs end
                        row.label:SetText(Hush.Main.CharLabel(row.info.key, char))
                        local seen = char.lastLogin and ("last played " .. date("%d/%m/%Y", char.lastLogin)) or ""
                        row.stats:SetText(("%d chats · %d messages · %s"):format(chats, msgs, seen))
                    end
                end
            end
        end)
    end
end

-- ---------------------------------------------------------------------------
-- Frame
-- ---------------------------------------------------------------------------

local function savePosition()
    local d = Hush.db.settingsWindow
    d.left = Theme:Snap(frame:GetLeft(), frame)
    d.top = Theme:Snap(frame:GetTop(), frame)
end

local function restorePosition()
    local d = Hush.db.settingsWindow
    frame:ClearAllPoints()
    if d.left and d.top then
        frame:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", d.left, d.top)
    else
        frame:SetPoint("CENTER", 0, 20)
    end
end

local function updateMenu()
    for _, pg in ipairs(pages) do
        local b = pg.menuButton
        local active = pg == current
        b.sel:SetShown(active)
        b.bar:SetShown(active)
        b.text:SetTextColor(Theme:Color(active and "text" or "textDim"))
    end
end

function Settings.ShowPage(id)
    for _, pg in ipairs(pages) do
        if pg.id == id then
            if not pg.page then
                pg.page = newPage(frame.content, pg.label)
                local ok, err = pcall(pg.build, pg.page)
                if not ok then geterrorhandler()(err) end
            end
            if current and current.page then current.page.frame:Hide() end
            current = pg
            pg.page:Refresh()
            pg.page.frame:Show()
            updateMenu()
            return
        end
    end
end

local function addMenuButton(pg)
    local b = CreateFrame("Button", nil, frame.menu)
    b:SetHeight(32)
    b.sel = W.Fill(b, "selected", 1)
    b.sel:SetAllPoints()
    b.sel:Hide()
    b.bar = b:CreateTexture(nil, "ARTWORK")
    b.bar:SetPoint("TOPLEFT")
    b.bar:SetPoint("BOTTOMLEFT")
    W.PixelSize(b.bar, b, "w", 2)
    W.OnAccent(function(r, g, bl) b.bar:SetColorTexture(r, g, bl, 1) end)
    b.bar:Hide()
    b.text = W.Text(b, "semibold", 0, "textDim")
    b.text:SetPoint("LEFT", S.padding + 4, 0)
    b.text:SetText(pg.label)
    b:SetScript("OnClick", function() Settings.ShowPage(pg.id) end)
    b:SetScript("OnEnter", function(self) if pg ~= current then self.text:SetTextColor(Theme:Color("text")) end end)
    b:SetScript("OnLeave", function() updateMenu() end)
    pg.menuButton = b
end

local function layoutMenu()
    for i, pg in ipairs(pages) do
        if not pg.menuButton then addMenuButton(pg) end
        pg.menuButton:ClearAllPoints()
        pg.menuButton:SetPoint("TOPLEFT", 0, -S.titleH - 8 - (i - 1) * 32)
        pg.menuButton:SetPoint("TOPRIGHT", 0, -S.titleH - 8 - (i - 1) * 32)
    end
end

local function setMoveMode(on)
    moveMode = on
    Hush.Toast.SetMoveMode(on)
    Hush.Popup.SetMoveMode(on)
    frame.moveButton.text:SetText(on and "Lock" or "Unlock & move")
end

local function build()
    -- Named only so ESC closes it through UISpecialFrames (no keyboard capture).
    frame = CreateFrame("Frame", "HushSettingsFrame", UIParent)
    tinsert(UISpecialFrames, "HushSettingsFrame")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetFrameStrata("HIGH")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:Hide()
    frame.bg = W.Fill(frame, "window", 0.98)
    frame.bg:SetAllPoints()

    local menu = CreateFrame("Frame", nil, frame)
    menu:SetPoint("TOPLEFT")
    menu:SetPoint("BOTTOMLEFT")
    menu:SetWidth(MENU_W)
    menu.bg = W.Fill(menu, "sidebar", 1)
    menu.bg:SetAllPoints()
    W.Line(menu, "right", "line")
    frame.menu = menu

    -- Title row (drag to move)
    local title = CreateFrame("Frame", nil, menu)
    title:SetPoint("TOPLEFT")
    title:SetPoint("TOPRIGHT")
    title:SetHeight(S.titleH)
    title:EnableMouse(true)
    title:RegisterForDrag("LeftButton")
    title:SetScript("OnDragStart", function() frame:StartMoving() end)
    title:SetScript("OnDragStop", function()
        frame:StopMovingOrSizing()
        savePosition()
        restorePosition()
    end)
    local square = title:CreateTexture(nil, "ARTWORK")
    square:SetSize(10, 10)
    square:SetPoint("LEFT", S.padding, 0)
    W.OnAccent(function(r, g, b) square:SetColorTexture(r, g, b, 1) end)
    local name = W.Text(title, "heading", 3, "text")
    name:SetPoint("LEFT", square, "RIGHT", 8, 0)
    name:SetText("SETTINGS")

    -- Bottom buttons
    local clear = W.Button(menu, "Clear all chats", "ghost", function()
        W.Dialog(frame, {
            title = "Clear all chats",
            text = "Delete every conversation and its history for this character? Categories and settings are kept.",
            okText = "Clear all",
            danger = true,
            onOk = function() Data.ClearAll() end,
        })
    end)
    clear:SetPoint("BOTTOMLEFT", S.padding - 8, 12)
    clear.text:SetTextColor(Theme:Color("danger"))
    clear:SetScript("OnLeave", function(self) self.text:SetTextColor(Theme:Color("danger")) end)

    local move = W.Button(menu, "Unlock & move", "default", function() setMoveMode(not moveMode) end)
    move:SetPoint("BOTTOMLEFT", S.padding, 48)
    move:SetPoint("BOTTOMRIGHT", -S.padding, 48)
    frame.moveButton = move
    local moveHint = W.Text(menu, "regular", -2, "textFaint")
    moveHint:SetPoint("BOTTOMLEFT", move, "TOPLEFT", 0, 6)
    moveHint:SetText("Move the combat notice and popups")

    -- Content area
    local content = CreateFrame("Frame", nil, frame)
    content:SetPoint("TOPLEFT", menu, "TOPRIGHT")
    content:SetPoint("BOTTOMRIGHT")
    frame.content = content

    local close = W.IconButton(frame, "close", 24, "Close", function() frame:Hide() end, "x")
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetFrameLevel(content:GetFrameLevel() + 20)

    frame.border = W.Border(frame, "line")
    for _, side in ipairs({ "top", "bottom", "left", "right" }) do frame.border[side]:SetDrawLayer("OVERLAY", 7) end

    frame:SetScript("OnHide", function()
        if moveMode then setMoveMode(false) end
        W.CloseMenus()
    end)

    restorePosition()
    layoutMenu()
end

-- def: { id, label, build = function(page) ... end }
function Settings.AddPage(def)
    assert(type(def) == "table" and def.id and def.label and def.build, "Settings.AddPage: id, label and build are required")
    for _, pg in ipairs(pages) do
        if pg.id == def.id then return end
    end
    pages[#pages + 1] = { id = def.id, label = def.label, build = def.build }
    if frame then layoutMenu() end
end

function Settings.Open(id)
    if not Hush.ready then return end
    if not frame then build() end
    frame:Show()
    Settings.ShowPage(id or (current and current.id) or pages[1].id)
end

function Settings.Toggle()
    if frame and frame:IsShown() then frame:Hide() else Settings.Open() end
end

Settings.AddPage({ id = "general", label = "General", build = buildGeneral })
Settings.AddPage({ id = "appearance", label = "Appearance", build = buildAppearance })
Settings.AddPage({ id = "themes", label = "Themes", build = buildThemes })
Settings.AddPage({ id = "behavior", label = "Behavior", build = buildBehavior })
Settings.AddPage({ id = "notifications", label = "Notifications", build = buildNotifications })
Settings.AddPage({ id = "quickreplies", label = "Quick replies", build = buildQuickReplies })
Settings.AddPage({ id = "storage", label = "Storage", build = buildStorage })

Hush:RegisterCallback("OPEN_SETTINGS", function() Settings.Toggle() end, "Settings")
Hush:AddSlashCommand("settings", function(arg) Settings.Open(arg ~= "" and arg or nil) end, "open the settings")

-- Keep the "Show launcher" toggle etc. in sync when changed elsewhere.
Hush:RegisterCallback("SETTINGS_CHANGED", function()
    if frame and frame:IsShown() and current and current.page then current.page:Refresh() end
end, "Settings")
