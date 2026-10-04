-- Offline test of Data.LinkBNet: a Battle.net conversation and a character conversation with the same person become one.
-- Run from the Hush folder:  lua Tests/bnet_link_test.lua
strlower, strtrim, time = string.lower, function(s) return s end, os.time
sort, tinsert, tremove, min, max = table.sort, table.insert, table.remove, math.min, math.max
wipe = function(t) for k in pairs(t) do t[k] = nil end return t end

local fired = {}
local Hush = {
    settings = { maxMessages = 200 },
    char = { convs = {} },
    db = { chars = {} },
}
function Hush:Fire(event, ...) fired[#fired + 1] = event end
function Hush:RegisterCallback() end
Hush.Compat = {}
assert(loadfile("Data.lua"))("Hush", Hush)
local Data = Hush.Data

local bad = 0
local function check(ok, what) if ok then print("OK   " .. what) else bad = bad + 1; print("BAD  " .. what) end end

local wKey, bKey = Data.WhisperKey("Quu Ken"), Data.BNetKey("Qken#1234")
Data.Ensure(wKey, { kind = "whisper", target = "Quu Ken", display = "Quu Ken" })
Data.Ensure(bKey, { kind = "bnet", target = "Qken#1234", display = "Qken" })
Data.AddMessage(wKey, { d = "in", m = "hello from the character", t = 100 })
Data.AddMessage(bKey, { d = "in", m = "hello from battle.net", t = 200 })
Data.AddMessage(wKey, { d = "out", m = "and back", t = 300 })

Data.Get(bKey).unread, Data.Get(wKey).unread = 1, 1
Data.LinkBNet(bKey, wKey, "Qken#1234", 77)
local conv = Data.Get(wKey)
check(Data.Get(bKey) == nil, "the Battle.net conversation is gone")
check(#conv.msgs == 3, "all three messages are in the character's conversation")
check(conv.msgs[1].m == "hello from the character" and conv.msgs[2].m == "hello from battle.net" and conv.msgs[3].m == "and back", "in time order")
check(conv.msgs[2].v == "bn" and conv.msgs[1].v == nil, "the Battle.net messages are marked")
check(conv.bnTag == "Qken#1234" and conv.bnID == 77, "it remembers the BattleTag and the id to answer through")
check(conv.unread == 2, "unread counts are added")
check(fired[#fired - 1] == "CONV_RENAMED", "the windows are told the conversation moved")

-- linking again, or a conversation that does not exist, changes nothing
Data.LinkBNet(bKey, wKey, "Qken#1234", 77)
check(#conv.msgs == 3, "linking twice does nothing")
Data.LinkBNet(Data.BNetKey("X#1"), Data.WhisperKey("Nobody"), "X#1", 1)
check(Data.Get(Data.WhisperKey("Nobody")) == nil, "no character conversation, nothing is made")

if bad > 0 then os.exit(1) end
print("bnet_link_test: all passed")
