-- Status: Available / Away / Busy / Raid / Combat. A status can answer whispers for you:
--   * Away, Busy and Raid set the game's own AFK / DND with your text. The server then answers
--     every whisper, also in boss fights where addons can't read chat (secret values).
--   * Where the game's flag is not active (Combat, Battle.net whispers, or the flag option
--     off), Hush sends the answer itself: at most once per person every 5 minutes.
-- Raid and Combat can switch on by themselves (Settings > Status). Notifications are not
-- changed by a status.
local _, Hush = ...

local Compat = Hush.Compat

local Status = {}
Hush.Status = Status

Status.LIST = {
    { id = "available", label = "Available", color = { 0.30, 0.85, 0.45 } },
    { id = "away", label = "Away", flag = "AFK", color = { 0.95, 0.75, 0.25 },
      text = "I'm away right now, I'll answer when I'm back." },
    { id = "busy", label = "Busy", flag = "DND", color = { 0.90, 0.30, 0.30 },
      text = "I'm busy right now, I'll get back to you." },
    { id = "raid", label = "Raid", flag = "DND", color = { 0.75, 0.40, 0.95 },
      text = "I'm raiding right now, I'll answer after the fight." },
    { id = "combat", label = "Combat", color = { 0.95, 0.50, 0.20 },
      text = "I'm in combat, I'll answer in a moment." },
}
local BY_ID = {}
for _, def in ipairs(Status.LIST) do BY_ID[def.id] = def end

local REPLY_PREFIX = "[Auto-reply] "
local REPLY_EVERY = 300 -- seconds between automatic answers to the same person

local inCombat = false
local lastEffective = "available"
local flagSet, flagText, flagSeen -- the AFK/DND flag Hush switched on, its text, and whether the game confirmed it
local replied = {}                -- conversation key -> time of the last automatic answer

-- ---------------------------------------------------------------------------
-- State
-- ---------------------------------------------------------------------------

function Status.Def(id) return BY_ID[id] or BY_ID.available end

-- The status you chose yourself.
function Status.Base()
    local id = Hush.char and Hush.char.status
    return BY_ID[id] and id or "available"
end

-- What applies right now: your own choice, else Raid / Combat when those are automatic.
function Status.Effective()
    local base = Status.Base()
    if base ~= "available" then return base end
    local s = Hush.settings
    if s and s.statusAutoRaid and Compat.InRaidInstance() then return "raid" end
    if s and s.statusAutoCombat and inCombat then return "combat" end
    return "available"
end

-- The answer text of a status ("" = no answer).
function Status.Text(id)
    local texts = Hush.settings and Hush.settings.statusTexts
    local custom = texts and texts[id]
    if custom ~= nil then return custom end
    return Status.Def(id).text or ""
end

function Status.SetText(id, text)
    local s = Hush.settings
    if type(s.statusTexts) ~= "table" then s.statusTexts = {} end
    text = strtrim(text or "")
    -- Back to the built-in text when it is the same (or emptied for a status without one).
    s.statusTexts[id] = (text ~= (Status.Def(id).text or "")) and text or nil
end

-- ---------------------------------------------------------------------------
-- The game's AFK / DND flag
-- ---------------------------------------------------------------------------

local hasFlag = Compat.HasFlag

-- "/afk text" and "/dnd text" toggle: only send when the flag has to change.
local function toggleFlag(flag, text)
    local ok, err = pcall(Compat.SendFlag, flag, text or "")
    if not ok then Hush:RecordError("status flag", err) end
    return ok
end

local function applyFlag(id)
    local def = Status.Def(id)
    local want = Hush.settings.statusGameFlags and def.flag or nil
    local text = Status.Text(id)
    if want and text == "" then want = nil end

    -- Switch off a flag Hush switched on, when it is no longer wanted (or its text changed).
    -- (The bookkeeping changes before the command is sent, so the flag event that follows
    -- is never mistaken for you switching the flag off yourself.)
    if flagSet and (flagSet ~= want or flagText ~= text) then
        local old = flagSet
        flagSet, flagText, flagSeen = nil, nil, nil
        if hasFlag(old) then toggleFlag(old, "") end
    end
    if want and not flagSet then
        if hasFlag(want) then
            -- Already on (you typed /dnd yourself): leave it, and leave it on later.
            return
        end
        flagSet, flagText, flagSeen = want, text, false
        if not toggleFlag(want, text) then flagSet, flagText, flagSeen = nil, nil, nil end
    end
end

-- ---------------------------------------------------------------------------
-- Changing status
-- ---------------------------------------------------------------------------

local function apply(announce)
    if not Hush.settings then return end
    local effective = Status.Effective()
    applyFlag(effective)
    if effective ~= lastEffective then
        lastEffective = effective
        if announce or effective == "raid" then
            Hush:Print("Status: " .. Status.Def(effective).label .. (effective ~= Status.Base() and " (automatic)" or ""))
        end
        Hush:Fire("STATUS_CHANGED", effective)
        return true
    end
    return false
end

function Status.Set(id)
    if not BY_ID[id] or not Hush.char then return end
    Hush.char.status = id ~= "available" and id or nil
    -- Your own choice can change without the effective status changing (Raid chosen while
    -- Raid was automatic): the window still has to update.
    if not apply(true) then Hush:Fire("STATUS_CHANGED", Status.Effective()) end
end

-- Settings changed (texts, options): apply them to the current status.
function Status.Refresh() apply(false) end

-- ---------------------------------------------------------------------------
-- Automatic answers from Hush
-- ---------------------------------------------------------------------------

Hush:RegisterCallback("MESSAGE_ADDED", function(_, key, msg, conv)
    if not msg or msg.d ~= "in" or not conv or msg.k == "gm" then return end
    if conv.kind ~= "whisper" and conv.kind ~= "bnet" then return end
    if Hush.Data and Hush.Data.IsMuted(conv) then return end -- no auto-reply to somebody who is muted
    local s = Hush.settings
    if not s or not s.statusHushReply then return end
    local id = Status.Effective()
    local text = Status.Text(id)
    if id == "available" or text == "" then return end
    -- The server already answers character whispers while the AFK / DND flag is on.
    local def = Status.Def(id)
    if conv.kind == "whisper" and def.flag and hasFlag(def.flag) then return end
    -- Never answer an automatic answer (two players with a status would loop).
    if type(msg.m) == "string" and msg.m:sub(1, #REPLY_PREFIX) == REPLY_PREFIX then return end
    local now = time()
    if replied[key] and now - replied[key] < REPLY_EVERY then return end
    if Compat.ChatLocked() then return end
    replied[key] = now
    local ok, err = pcall(Compat.Send, conv, (REPLY_PREFIX .. text):sub(1, 255))
    if not ok then Hush:RecordError("status reply", err) end
end, "Status")

-- ---------------------------------------------------------------------------
-- Events
-- ---------------------------------------------------------------------------

Hush:RegisterEvent("PLAYER_REGEN_DISABLED", function() inCombat = true; apply(false) end)
Hush:RegisterEvent("PLAYER_REGEN_ENABLED", function() inCombat = false; apply(false) end)
Hush:RegisterEvent("ZONE_CHANGED_NEW_AREA", function() apply(false) end)
Hush:RegisterEvent("PLAYER_ENTERING_WORLD", function()
    inCombat = Compat.InCombat()
    -- After a login the game's flags are gone: a status that relies on one starts over.
    -- After a /reload the flag is still on: it is still the one Hush switched on.
    local def = Status.Def(Status.Base())
    if def.flag and Hush.settings and Hush.settings.statusGameFlags and Hush.char then
        if hasFlag(def.flag) then
            flagSet, flagText, flagSeen = def.flag, Status.Text(def.id), true
        else
            Hush.char.status = nil
        end
    end
    lastEffective = Status.Effective()
    apply(false)
    Hush:Fire("STATUS_CHANGED", lastEffective)
end)

-- You (or the game) switched the flag off: "/afk" again, moving after being away...
Hush:RegisterEvent("PLAYER_FLAGS_CHANGED", function(_, unit)
    if unit ~= "player" or not flagSet then return end
    if hasFlag(flagSet) then
        flagSeen = true
    elseif flagSeen then
        local wasFlag = flagSet
        flagSet, flagText, flagSeen = nil, nil, nil
        if Status.Def(Status.Base()).flag == wasFlag and Hush.char then
            Hush.char.status = nil
            if not apply(true) then Hush:Fire("STATUS_CHANGED", Status.Effective()) end
        end
    end
end)

-- ---------------------------------------------------------------------------
-- Menu, slash commands
-- ---------------------------------------------------------------------------

-- Menu items to pick a status (used by the window's status dot and the launcher menu).
function Status.MenuItems()
    local items = {}
    local base = Status.Base()
    for _, def in ipairs(Status.LIST) do
        items[#items + 1] = { text = def.label, checked = def.id == base, onClick = function() Status.Set(def.id) end }
    end
    items[#items + 1] = { separator = true }
    items[#items + 1] = { text = "Status settings...", onClick = function()
        Hush.Main.Show()
        Hush.Settings.Open("status")
    end }
    return items
end

local function setByName(name)
    name = strlower(strtrim(name or ""))
    if name == "" then
        local e = Status.Effective()
        Hush:Print("Status: " .. Status.Def(e).label .. (e ~= Status.Base() and " (automatic)" or "")
            .. ". /hush status available | away | busy | raid | combat")
        return
    end
    if name == "back" or name == "off" or name == "none" then name = "available" end
    for _, def in ipairs(Status.LIST) do
        if def.id == name or strlower(def.label) == name then Status.Set(def.id) return end
    end
    Hush:Print("Unknown status. Use: available, away, busy, raid, combat")
end

Hush:AddSlashCommand("status", setByName, "show or set your status: /hush status away | busy | raid | combat | available")
