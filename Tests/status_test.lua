-- Offline test of Status.lua (not loaded by the game). Run from the Hush folder:  lua Tests/status_test.lua
strtrim = function(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strlower, time = string.lower, os.time

-- A fake game: AFK/DND toggle like "/afk" and "/dnd"; setting one clears the other.
local game = { AFK = false, DND = false, text = nil, inRaid = false, locked = false, sent = {}, flagSends = 0 }
local events, callbacks, slash, prints = {}, {}, {}, {}
local Hush = {
    settings = { statusAutoCombat = false, statusAutoRaid = false, statusGameFlags = true, statusHushReply = true },
    char = {},
    Main = { Show = function() end },
    Settings = { Open = function() end },
}
function Hush:RegisterEvent(e, fn) events[e] = fn end
function Hush:RegisterCallback(e, fn) callbacks[e] = fn end
function Hush:AddSlashCommand(name, fn) slash[name] = fn end
function Hush:Fire() end
function Hush:Print(...) prints[#prints + 1] = table.concat({ ... }, " ") end
function Hush:RecordError(where, err) error(where .. ": " .. tostring(err)) end
Hush.Compat = {
    SendFlag = function(flag, text)
        game.flagSends = game.flagSends + 1
        game[flag] = not game[flag]
        if game[flag] then
            game.text = text
            game[flag == "AFK" and "DND" or "AFK"] = false
        end
        if events.PLAYER_FLAGS_CHANGED then events.PLAYER_FLAGS_CHANGED("PLAYER_FLAGS_CHANGED", "player") end
    end,
    HasFlag = function(flag) return game[flag] end,
    InRaidInstance = function() return game.inRaid end,
    InCombat = function() return false end,
    ChatLocked = function() return game.locked end,
    Send = function(conv, text) game.sent[#game.sent + 1] = conv.target .. ": " .. text return true end,
}
assert(loadfile("Status.lua"))("Hush", Hush)
local S = Hush.Status

local bad = 0
local function check(ok, what) if ok then print("OK   " .. what) else bad = bad + 1; print("BAD  " .. what) end end
local function whisper(name, text, kind)
    callbacks.MESSAGE_ADDED("MESSAGE_ADDED", "w:" .. name, { d = "in", m = text }, { kind = kind or "whisper", target = name })
end

events.PLAYER_ENTERING_WORLD("PLAYER_ENTERING_WORLD")
check(S.Effective() == "available" and not game.DND and not game.AFK, "starts Available, no flags")

S.Set("busy")
check(game.DND and game.text == "I'm busy right now, I'll get back to you.", "Busy sets the game's DND with the text")
whisper("Anna Berg", "hi")
check(#game.sent == 0, "DND is on: the server answers, Hush stays quiet")

S.Set("raid")
check(game.DND and game.text == "I'm raiding right now, I'll answer after the fight.", "Busy -> Raid: DND stays on with the new text")

S.Set("away")
check(game.AFK and not game.DND, "Raid -> Away: AFK on, DND off")

S.Set("available")
check(not game.AFK and not game.DND, "Available clears the flag Hush set")

-- A flag you set yourself is left alone.
game.DND = true
S.Set("busy"); S.Set("available")
check(game.DND, "a DND you typed yourself is not switched off by Hush")
game.DND = false

-- You switch the flag off yourself (/dnd): the status follows.
S.Set("busy")
Hush.Compat.SendFlag("DND", "")
check(S.Base() == "available", "typing /dnd yourself puts Hush back on Available")

-- Combat: no game flag, Hush answers once per person.
S.Set("combat")
check(not game.DND and not game.AFK, "Combat sets no game flag")
whisper("Anna Berg", "inv?")
whisper("Anna Berg", "hello??")
whisper("Bo Ek", "hi")
check(#game.sent == 2 and game.sent[1] == "Anna Berg: [Auto-reply] I'm in combat, I'll answer in a moment.", "Hush answers once per person")
whisper("Cia Dahl", "[Auto-reply] I'm away right now")
check(#game.sent == 2, "never answers an automatic answer")
game.locked = true
whisper("Dan Ek", "hi")
check(#game.sent == 2, "no answer while the game locks addon chat")
game.locked = false
S.Set("available")

-- Battle.net whispers get Hush's answer even while DND is on (the server only answers characters).
S.Set("busy")
whisper("Friend#1234", "yo", "bnet")
check(#game.sent == 3, "Battle.net whisper is answered by Hush while Busy")
S.Set("available")

-- Automatic statuses.
Hush.settings.statusAutoCombat = true
events.PLAYER_REGEN_DISABLED("PLAYER_REGEN_DISABLED")
check(S.Effective() == "combat" and S.Base() == "available", "automatic Combat in combat")
events.PLAYER_REGEN_ENABLED("PLAYER_REGEN_ENABLED")
check(S.Effective() == "available", "back to Available after combat")
Hush.settings.statusAutoRaid = true
game.inRaid = true
events.ZONE_CHANGED_NEW_AREA("ZONE_CHANGED_NEW_AREA")
check(S.Effective() == "raid" and game.DND, "automatic Raid inside a raid sets DND")
events.PLAYER_REGEN_DISABLED("PLAYER_REGEN_DISABLED")
check(S.Effective() == "raid", "Raid wins over Combat inside a raid")
events.PLAYER_REGEN_ENABLED("PLAYER_REGEN_ENABLED")
game.inRaid = false
events.ZONE_CHANGED_NEW_AREA("ZONE_CHANGED_NEW_AREA")
check(S.Effective() == "available" and not game.DND, "leaving the raid clears DND")

-- Own text, empty text, flags off.
S.SetText("busy", "In a meeting")
S.Set("busy")
check(game.text == "In a meeting", "your own text is used")
S.Set("available")
S.SetText("busy", "")
S.Set("busy")
check(not game.DND, "an empty answer sets no flag")
whisper("Eva Lind", "hi")
check(#game.sent == 3, "an empty answer sends nothing")
S.Set("available")
S.SetText("busy", "I'm busy right now, I'll get back to you.")
Hush.settings.statusGameFlags = false
S.Set("busy")
check(not game.DND, "with the game's flags off, Busy sets no DND")
whisper("Eva Lind", "hi")
check(#game.sent == 4, "...and Hush answers instead")
S.Set("available")

-- Slash
slash.status("away")
check(S.Base() == "away", "/hush status away")
slash.status("back")
check(S.Base() == "available", "/hush status back")

print(bad == 0 and "ALL OK" or (bad .. " wrong"))
