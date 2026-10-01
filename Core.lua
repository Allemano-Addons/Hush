-- Hush: core namespace, event dispatcher, callbacks, SavedVariables and slash command.
local addonName, Hush = ...

Hush.name = addonName
Hush.SCHEMA = 4

-- ---------------------------------------------------------------------------
-- Printing
-- ---------------------------------------------------------------------------

function Hush:Print(...)
    local msg = strjoin(" ", tostringall(...))
    DEFAULT_CHAT_FRAME:AddMessage("|cff3fc7ebHush|r " .. msg)
end

-- ---------------------------------------------------------------------------
-- Errors: recorded (last 10, kept in HushDB for /hush report) and still passed to the
-- normal error display.
-- ---------------------------------------------------------------------------

Hush.errors = {}

function Hush:RecordError(where, err)
    local list = self.errors
    list[#list + 1] = { t = time(), where = tostring(where), msg = tostring(err):sub(1, 400), v = self.version }
    while #list > 10 do tremove(list, 1) end
    geterrorhandler()(err)
end

-- ---------------------------------------------------------------------------
-- Game events: several handlers per event, one shared frame.
-- ---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

-- Returns false if the client does not know the event (WoW Forever lacks some older
-- Classic events); such handlers are simply skipped.
function Hush:RegisterEvent(event, handler)
    local list = eventHandlers[event]
    if not list then
        if not pcall(eventFrame.RegisterEvent, eventFrame, event) then return false end
        list = {}
        eventHandlers[event] = list
    end
    list[#list + 1] = handler
    return true
end

function Hush:UnregisterEvent(event, handler)
    local list = eventHandlers[event]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i] == handler then tremove(list, i) end
    end
    if #list == 0 then
        eventHandlers[event] = nil
        eventFrame:UnregisterEvent(event)
    end
end

-- Each handler runs protected: an error in one part never stops the others (a whisper
-- is always saved even if, say, a UI refresh fails).
eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    if not list then return end
    -- Chat with secret text (see Compat.HasSecret) can't be read: leave it to the default chat.
    if event:sub(1, 9) == "CHAT_MSG_" and Hush.Compat and Hush.Compat.HasSecret(...) then return end
    for i = 1, #list do
        local ok, err = pcall(list[i], event, ...)
        if not ok then Hush:RecordError(event, err) end
    end
end)

-- ---------------------------------------------------------------------------
-- Internal callbacks (Hush events), also exposed to modules via API.lua.
-- A failing listener never stops the others.
-- ---------------------------------------------------------------------------

local callbacks = {}

function Hush:RegisterCallback(name, fn, owner)
    local list = callbacks[name]
    if not list then
        list = {}
        callbacks[name] = list
    end
    list[#list + 1] = { fn = fn, owner = owner }
end

function Hush:UnregisterCallback(name, owner)
    local list = callbacks[name]
    if not list then return end
    for i = #list, 1, -1 do
        if list[i].owner == owner then tremove(list, i) end
    end
end

function Hush:Fire(name, ...)
    local list = callbacks[name]
    if not list then return end
    for i = 1, #list do
        local ok, err = pcall(list[i].fn, name, ...)
        if not ok then Hush:RecordError(name, err) end
    end
end

-- ---------------------------------------------------------------------------
-- SavedVariables
-- ---------------------------------------------------------------------------

local DEFAULT_SETTINGS = {
    accent = "3FD0E0",
    useClassColor = false,
    bgAlpha = 0.95,
    textSize = "M",          -- S / M / L
    msgStyle = "compact",    -- compact / bubbles
    portraits = true,
    listPortraits = true,    -- initials next to each chat in the list
    timestamps = true,
    hideWhispers = true,     -- hide whispers in the default chat (never while in combat)
    hideInCombat = true,     -- hide the Hush window while in combat
    autoOpenIn = true,
    incomingAction = "popup", -- on incoming whisper: "popup" / "open" (Hush) / "none"
    popupCorner = "TOPRIGHT",
    popupDuration = 8,        -- seconds
    popupRequests = true,     -- popups for unknown players
    popupGroups = false,      -- popups for party/raid chat
    autoOpenOut = false,
    fadeWhenMoving = true,
    sound = true,
    soundKey = "ping",
    font = "auto",           -- "auto" or a font name (game font or LibSharedMedia)
    headingFont = "auto",
    listMode = "categories", -- Whispers tab: "categories" (grouped) or "recent" (newest first)
    theme = "allemano",        -- Settings → Themes (needs /reload)
    maxMessages = 200,         -- per conversation, oldest dropped first
    groupRetentionDays = 14,   -- delete group chats older than this (0 = keep)
    whisperRetentionDays = 0,  -- delete inactive whisper chats older than this (0 = keep)
    combatToast = true,
    -- Status (Status.lua). Your own answer texts go in statusTexts[id].
    statusAutoCombat = false,  -- Combat status while in combat
    statusAutoRaid = false,    -- Raid status inside a raid instance
    statusGameFlags = true,    -- Away/Busy/Raid set the game's AFK/DND (the server answers)
    statusHushReply = true,    -- Hush answers itself where the game's flag is not active
}

local DEFAULT_QUICK_REPLIES = {
    "Hi {name}!",
    "Sorry, busy right now. I'll get back to you.",
    "Thanks {name}!",
}

-- Built-in categories. "pinned" is virtual: pinned chats show there regardless of category.
Hush.BUILTIN_CATEGORIES = {
    { id = "pinned",   name = "Pinned",   locked = true },
    { id = "guild",    name = "Guild" },
    { id = "recruits", name = "Recruits" },
    { id = "other",    name = "Other",    locked = true },
}

local function fillDefaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then
            if type(v) == "table" then
                dst[k] = CopyTable(v)
            else
                dst[k] = v
            end
        end
    end
end

-- Schema migrations: MIGRATIONS[n] upgrades a DB from schema n-1 to n.
local MIGRATIONS = {
    -- 2: auto-open on incoming whispers became the default.
    [2] = function(db)
        if db.settings then db.settings.autoOpenIn = true end
    end,
    -- 3: the mini-popup replaces auto-open as the default for incoming whispers.
    [3] = function(db)
        if db.settings then db.settings.incomingAction = "popup" end
    end,
    -- 4: the Allemano theme replaces Hush Original as the default look (other themes kept).
    [4] = function(db)
        local s = db.settings
        if not s then return end
        if s.theme == nil or s.theme == "hush" then s.theme = "allemano" end
        if s.accent == nil or strupper(s.accent) == "3FC7EB" then s.accent = "3FD0E0" end
    end,
}

local function initDB()
    if type(HushDB) ~= "table" then HushDB = {} end
    local db = HushDB
    db.schema = db.schema or Hush.SCHEMA
    for v = db.schema + 1, Hush.SCHEMA do
        if MIGRATIONS[v] then MIGRATIONS[v](db) end
        db.schema = v
    end

    db.settings = db.settings or {}
    fillDefaults(db.settings, DEFAULT_SETTINGS)
    if db.quickReplies == nil then db.quickReplies = CopyTable(DEFAULT_QUICK_REPLIES) end
    db.window = db.window or {}
    fillDefaults(db.window, { w = 1000, h = 620 })
    db.launcher = db.launcher or {}
    db.settingsWindow = db.settingsWindow or {}
    db.toast = db.toast or {}
    db.popup = db.popup or {}
    db.chars = db.chars or {}
    -- Errors from before the saved data was loaded are kept too.
    db.errors = db.errors or {}
    for _, e in ipairs(Hush.errors) do tinsert(db.errors, e) end
    Hush.errors = db.errors
    while #db.errors > 10 do tremove(db.errors, 1) end

    Hush.db = db
    Hush.settings = db.settings
end

local function initCharDB()
    local key = Hush.Compat.PlayerKey()
    local char = Hush.db.chars[key]
    if not char then
        char = { convs = {} }
        Hush.db.chars[key] = char
    end
    char.convs = char.convs or {}
    char.saved = char.saved or {} -- saved messages, see Saved.lua
    -- Who this is, for the character selector (alts).
    char.name = Hush.Compat.PlayerName()
    char.realm = Hush.Compat.PlayerRealm()
    char.class = select(2, UnitClass("player"))
    char.lastLogin = time()
    Hush.charKey = key
    -- Before 0.1.18 characters were stored by first name only, so characters sharing a
    -- first name shared one bucket. That bucket stays readable as "older data" until it is
    -- merged into the right character (Settings → Storage).
    local legacyKey = Hush.Compat.LegacyPlayerKey()
    if legacyKey ~= key and Hush.db.chars[legacyKey] then
        Hush.db.chars[legacyKey].legacy = true
    end

    local cats = char.categories
    if not cats then
        cats = { order = {}, byId = {} }
        char.categories = cats
    end
    for _, c in ipairs(Hush.BUILTIN_CATEGORIES) do
        if not cats.byId[c.id] then
            cats.byId[c.id] = { name = c.name, builtin = true, locked = c.locked, collapsed = false }
            tinsert(cats.order, c.id)
        end
    end

    Hush.char = char
end

-- SavedVariables are read here, never at file load (see WoW Forever SV quirks).
Hush:RegisterEvent("ADDON_LOADED", function(_, name)
    if name ~= addonName then return end
    initDB()
    Hush.Theme:ApplyTheme() -- before any UI exists
    Hush.version = Hush.Compat.GetAddOnMetadata(addonName, "Version") or "?"
end)

Hush:RegisterEvent("PLAYER_LOGIN", function()
    initCharDB()
    Hush.Theme:CheckFonts()
    Hush.ready = true
    Hush:Fire("READY")
end)

-- ---------------------------------------------------------------------------
-- Slash command
-- ---------------------------------------------------------------------------

function Hush:Toggle()
    -- Replaced once the main window exists.
    self:Print("The window arrives in a later step.")
end

local function debugReport()
    local C, T = Hush.Compat, Hush.Theme
    Hush:Print("v" .. tostring(Hush.version), "interface", select(4, GetBuildInfo()), "build", (select(2, GetBuildInfo())))
    Hush:Print("character:", Hush.Compat.PlayerKey(), "schema:", Hush.db and Hush.db.schema)
    local w, h = C.GetPhysicalScreenSize()
    Hush:Print(("screen %dx%d, UI scale %.3f, 1px = %.4f"):format(w, h, UIParent:GetEffectiveScale(), T:Pixel()))
    Hush:Print("fonts:", T.fontStatus)
    Hush:Print("  in use: text", T.fonts.regular, "| heading", T.fonts.heading)
    if T.fontDiag and T.fontStatus ~= "Barlow ok" then
        for key, diag in pairs(T.fontDiag) do Hush:Print(("  %s: %s"):format(key, diag)) end
    end
    local names = {}
    for k in pairs(C.features) do names[#names + 1] = k end
    sort(names)
    for _, k in ipairs(names) do
        Hush:Print(("  %s: %s"):format(k, C.features[k] and "|cff3fc77fyes|r" or "|cffe0564fno|r"))
    end
end

-- Subcommands: other files add their own with Hush:AddSlashCommand.
local slashCommands, slashOrder = {}, {}

-- Test and diagnostic commands: hidden and blocked unless dev mode is on (/hush dev).
local DEV_COMMANDS = {
    api = true, dump = true, fake = true, read = true, move = true, fakemany = true,
    clearfake = true, fakeconvo = true, fakegroup = true, toasttest = true,
    testerror = true,
}

local function devMode() return Hush.db ~= nil and Hush.db.dev == true end

function Hush:AddSlashCommand(name, fn, help)
    if not slashCommands[name] then slashOrder[#slashOrder + 1] = name end
    slashCommands[name] = { fn = fn, help = help, dev = DEV_COMMANDS[name] == true }
end

Hush:AddSlashCommand("debug", debugReport, "client and addon diagnostics")
Hush:AddSlashCommand("version", function() Hush:Print("v" .. tostring(Hush.version)) end, "show version")
Hush:AddSlashCommand("dev", function()
    Hush.db.dev = not devMode()
    Hush:Print("Dev mode", devMode() and "ON: test commands are available (/hush help)." or "OFF.")
end, "toggle dev mode (test commands)")

local function printHelp()
    Hush:Print("/hush - open/close")
    for _, name in ipairs(slashOrder) do
        local c = slashCommands[name]
        if not c.dev or devMode() then
            Hush:Print(("/hush %s - %s%s"):format(name, c.help or "", c.dev and "  |cff7c858f(dev)|r" or ""))
        end
    end
end

SLASH_HUSH1 = "/hush"
SlashCmdList.HUSH = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = strlower(cmd or "")
    local c = slashCommands[cmd]
    if cmd == "" then
        Hush:Toggle()
    elseif c and c.dev and not devMode() then
        Hush:Print("/hush " .. cmd .. " is a dev command. Turn on dev mode with /hush dev")
    elseif c then
        local ok, err = pcall(c.fn, rest)
        if not ok then Hush:RecordError("/hush " .. cmd, err) end
    else
        printHelp()
    end
end

-- Lists the functions in an API table, e.g. /hush api C_PartyInfo invite
Hush:AddSlashCommand("api", function(arg)
    local name, filter = arg:match("^(%S+)%s*(.*)$")
    local t = name and _G[name]
    if type(t) ~= "table" then
        Hush:Print(tostring(name), "does not exist on this client")
        return
    end
    filter = strlower(filter or "")
    local found = {}
    for k, v in pairs(t) do
        if type(v) == "function" and (filter == "" or strlower(k):find(filter, 1, true)) then found[#found + 1] = k end
    end
    sort(found)
    Hush:Print(name .. ":", #found > 0 and table.concat(found, ", ") or "(no matches)")
end, "list API functions: /hush api <table> [filter]")

-- ---------------------------------------------------------------------------
-- /hush report: everything useful for a bug report, ready to copy.
-- ---------------------------------------------------------------------------

function Hush.BuildReport()
    local C, T, D = Hush.Compat, Hush.Theme, Hush.Data
    local s = Hush.settings or {}
    local out = {}
    local function add(fmt, ...) out[#out + 1] = select("#", ...) > 0 and fmt:format(...) or fmt end

    local version, build, buildDate, interface = GetBuildInfo()
    add("Hush report  %s", date("%Y-%m-%d %H:%M"))
    local okR, recruit = pcall(C.GetAddOnMetadata, "Hush_Recruit", "Version")
    if not okR then recruit = nil end
    add("Hush %s%s", tostring(Hush.version), recruit and ("  +  Hush Recruit " .. recruit) or "")
    add("Client %s (%s, %s), interface %s, locale %s", tostring(version), tostring(build), tostring(buildDate),
        tostring(interface), tostring(GetLocale and GetLocale() or "?"))
    add("Character %s, class %s", tostring(Hush.charKey), tostring(C.PlayerClass()))
    local w, h = C.GetPhysicalScreenSize()
    add("Screen %dx%d, UI scale %.3f", w, h, UIParent:GetEffectiveScale())
    add("Fonts: %s | text %s | heading %s", tostring(T.fontStatus), tostring(T.fonts.regular), tostring(T.fonts.heading))
    add("Theme %s, accent %s%s, list %s, incoming %s, hide whispers %s, style %s, text %s",
        tostring(s.theme), tostring(s.accent), s.useClassColor and " (class)" or "", tostring(s.listMode),
        tostring(s.incomingAction), tostring(s.hideWhispers), tostring(s.msgStyle), tostring(s.textSize))
    if Hush.db then
        local chats, msgs, saved, bytes = D.Stats()
        add("Data: %d chats, %d messages, %d saved, %d characters, ~%d KB, schema %s",
            chats, msgs, saved, #D.Characters(), ceil(bytes / 1024), tostring(Hush.db.schema))
    end
    local feats = {}
    for k, v in pairs(C.features) do feats[#feats + 1] = k .. "=" .. (v and "1" or "0") end
    sort(feats)
    add("Features: %s", table.concat(feats, " "))
    add("Secret chat messages skipped this session: %d", C.secretSkipped or 0)
    local addons = C.LoadedAddOns()
    add("Addons loaded (%d): %s", #addons, table.concat(addons, ", "))
    add("")
    add("Recent Hush errors:")
    if #Hush.errors == 0 then
        add("  none")
    else
        for _, e in ipairs(Hush.errors) do
            add("  [%s] %s (v%s): %s", date("%d/%m %H:%M", e.t), e.where, tostring(e.v), e.msg)
        end
    end
    return table.concat(out, "\n")
end

function Hush.OpenReport()
    Hush.Widgets.CopyBox("Hush report", Hush.BuildReport())
end

Hush:AddSlashCommand("report", function(arg)
    if strlower(arg or "") == "clear" then
        wipe(Hush.errors)
        Hush:Print("Error list cleared.")
        return
    end
    Hush.OpenReport()
end, "copy diagnostics for a bug report (/hush report clear empties the error list)")

-- Dev: an intentional error on the next message, to check the safety net and the report.
Hush:AddSlashCommand("testerror", function()
    local fired = false
    Hush:RegisterCallback("MESSAGE_ADDED", function()
        if fired then return end
        fired = true
        error("Intentional test error (/hush testerror)")
    end, "testerror")
    Hush:Print("The next message will raise a test error. The message is still saved; see /hush report.")
end, "raise a test error on the next message")
