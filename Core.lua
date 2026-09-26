-- Hush: core namespace, event dispatcher, callbacks, SavedVariables and slash command.
local addonName, Hush = ...

Hush.name = addonName
Hush.SCHEMA = 2

-- ---------------------------------------------------------------------------
-- Printing
-- ---------------------------------------------------------------------------

function Hush:Print(...)
    local msg = strjoin(" ", tostringall(...))
    DEFAULT_CHAT_FRAME:AddMessage("|cff3fc7ebHush|r " .. msg)
end

-- ---------------------------------------------------------------------------
-- Game events: several handlers per event, one shared frame.
-- ---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local eventHandlers = {}

function Hush:RegisterEvent(event, handler)
    local list = eventHandlers[event]
    if not list then
        list = {}
        eventHandlers[event] = list
        eventFrame:RegisterEvent(event)
    end
    list[#list + 1] = handler
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

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = eventHandlers[event]
    if not list then return end
    for i = 1, #list do
        list[i](event, ...)
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
        if not ok then geterrorhandler()(err) end
    end
end

-- ---------------------------------------------------------------------------
-- SavedVariables
-- ---------------------------------------------------------------------------

local DEFAULT_SETTINGS = {
    accent = "3FC7EB",
    useClassColor = false,
    bgAlpha = 0.95,
    textSize = "M",          -- S / M / L
    msgStyle = "compact",    -- compact / bubbles
    portraits = true,
    timestamps = true,
    hideWhispers = true,     -- hide whispers in the default chat (never while in combat)
    hideInCombat = true,     -- hide the Hush window while in combat
    autoOpenIn = true,
    autoOpenOut = false,
    fadeWhenMoving = true,
    sound = true,
    soundKey = "ping",
    combatToast = true,
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
    db.chars = db.chars or {}

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

function Hush:AddSlashCommand(name, fn, help)
    if not slashCommands[name] then slashOrder[#slashOrder + 1] = name end
    slashCommands[name] = { fn = fn, help = help }
end

Hush:AddSlashCommand("debug", debugReport, "client and addon diagnostics")
Hush:AddSlashCommand("version", function() Hush:Print("v" .. tostring(Hush.version)) end, "show version")

SLASH_HUSH1 = "/hush"
SlashCmdList.HUSH = function(msg)
    msg = strtrim(msg or "")
    local cmd, rest = msg:match("^(%S*)%s*(.-)$")
    cmd = strlower(cmd or "")
    if cmd == "" then
        Hush:Toggle()
    elseif slashCommands[cmd] then
        slashCommands[cmd].fn(rest)
    else
        Hush:Print("/hush - open/close")
        for _, name in ipairs(slashOrder) do
            Hush:Print(("/hush %s - %s"):format(name, slashCommands[name].help or ""))
        end
    end
end
