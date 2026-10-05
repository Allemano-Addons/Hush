-- Offline test of the mute data (Data.IsMuted, SetMute, ExpireMutes, UnreadTotals) and Mute.Format.
-- Run from the Hush folder:  lua Tests/mute_test.lua
strlower, strtrim, time = string.lower, function(s) return s end, os.time
sort, tinsert, tremove, min, max = table.sort, table.insert, table.remove, math.min, math.max
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local now = 1000000
function time() return now end
local fired, timers = {}, {}
local Hush = { settings = { maxMessages = 200 }, char = { convs = {} }, db = { chars = {} } }
function Hush:Fire(event) fired[#fired + 1] = event end
function Hush:RegisterCallback() end
Hush.Compat = { After = function(seconds, fn) timers[#timers + 1] = { seconds = seconds, fn = fn } end }
assert(loadfile("Data.lua"))("Hush", Hush)
local Data = Hush.Data

local bad = 0
local function check(ok, what) if ok then print("OK   " .. what) else bad = bad + 1; print("BAD  " .. what) end end

local aKey, bKey, cKey = Data.WhisperKey("Anna Berg"), Data.WhisperKey("Bo Ek"), Data.WhisperKey("Cia Lund")
for _, k in ipairs({ aKey, bKey, cKey }) do Data.Ensure(k, { kind = "whisper", target = k:sub(3), display = k:sub(3) }) end
Data.Get(aKey).unread, Data.Get(bKey).unread, Data.Get(cKey).unread = 2, 3, 1

check(not Data.IsMuted(Data.Get(aKey)), "nobody is muted at first")
check(select(1, Data.UnreadTotals()) == 6, "all unread count")

-- Mute for ten minutes
check(Data.SetMute(aKey, 600) == true, "mute for ten minutes")
local a = Data.Get(aKey)
check(Data.IsMuted(a) and a.mute == now + 600 and Data.MuteLeft(a) == 600, "it is muted and has 600 seconds left")
check(select(1, Data.UnreadTotals()) == 4, "a muted chat is left out of the unread badge")
check(timers[1] and timers[1].seconds == 601, "a timer is set for the end")
check(fired[#fired] == "UNREAD_CHANGED", "the windows are told")

-- Until unmuted
Data.SetMute(bKey, true)
check(Data.IsMuted(Data.Get(bKey)) and Data.MuteLeft(Data.Get(bKey)) == nil, "muted until unmuted has no time left")
check(select(1, Data.UnreadTotals()) == 1, "both are left out")

-- Time passes
now = now + 599
check(Data.IsMuted(a) and Data.MuteLeft(a) == 1, "one second before the end it is still muted")
now = now + 2
check(not Data.IsMuted(a) and Data.MuteLeft(a) == nil, "after the end it is not muted")
check(select(1, Data.UnreadTotals()) == 3, "and it counts again, even before the mute is cleaned up")
check(Data.ExpireMutes() == 1 and a.mute == nil, "expiring clears it")
check(Data.IsMuted(Data.Get(bKey)) and Data.ExpireMutes() == 0, "a mute until unmuted is never expired")

-- Unmute
Data.SetMute(bKey, nil)
check(not Data.IsMuted(Data.Get(bKey)) and select(1, Data.UnreadTotals()) == 6, "unmuting brings the unread back")
check(Data.SetMute("W:Nobody", 60) == false, "a chat that does not exist cannot be muted")

-- The text
local Mute
Hush.API = { AddChatMenuItems = function() end, AddHeaderButton = function() end, AddStatusChip = function() end, RefreshHeader = function() end }
Hush.Widgets = {}
Hush.Main = { IsShown = function() return false end }
function Hush:AddSlashCommand() end
_G.CreateFrame = function() return { SetScript = function() end } end
assert(loadfile("Mute.lua"))("Hush", Hush)
Mute = Hush.Mute
check(Mute.Format(20) == "20 s" and Mute.Format(540) == "9 min" and Mute.Format(3900) == "1 h 5 min" and Mute.Format(7200) == "2 h", "durations read well")
check(Mute.ChipText(Data.Get(cKey)) == nil, "no chip when not muted")
Data.SetMute(cKey, 600)
check(Mute.ChipText(Data.Get(cKey)) == "Muted 10 min", "the chip says how long")
Data.SetMute(cKey, true)
check(Mute.ChipText(Data.Get(cKey)) == "Muted", "or just Muted")
local items = Mute.Items(cKey)
check(items[1].text == "Unmute" and #items == 7, "the menu offers Unmute and the five durations")
Data.SetMute(cKey, nil)
check(#Mute.Items(cKey) == 5 and Mute.Items(cKey)[1].text == "Mute: 10 minutes", "an unmuted chat only offers the durations")

if bad > 0 then os.exit(1) end
print("mute_test: all passed")
