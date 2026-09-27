-- Chat: captures whisper events into Hush and hides them in the default chat (never in combat).
local _, Hush = ...

local Chat = {}
Hush.Chat = Chat

local Compat, Data = Hush.Compat, Hush.Data

Chat.inCombat = false

-- ---------------------------------------------------------------------------
-- Guild roster cache
-- ---------------------------------------------------------------------------

local roster = {}
local rosterPending = false
local lastRosterRequest = 0

function Chat.IsGuildMember(name)
    return name ~= nil and roster[name] ~= nil
end

local function requestRoster(force)
    local now = GetTime()
    if not force and now - lastRosterRequest < 30 then return end
    lastRosterRequest = now
    Compat.RequestGuildRoster()
end

local function readRoster()
    rosterPending = false
    roster = Compat.ReadGuildRoster()
    local now = time()
    for key, conv in pairs(Data.All()) do
        if conv.kind == "whisper" then
            local info = roster[conv.target]
            if info then
                Data.UpdateInfo(conv, info)
                -- A fresh conversation that was created before the roster knew the player.
                if conv.category == "other" and now - conv.created < 300 then
                    Data.Move(key, "guild")
                end
            end
        end
    end
end

Hush:RegisterEvent("GUILD_ROSTER_UPDATE", function()
    -- Coalesce bursts of roster events into one read.
    if rosterPending or not Hush.char then return end
    rosterPending = true
    Compat.After(1, readRoster)
end)

-- Everything Hush knows about a character right now.
function Chat.LookupInfo(name)
    local info = {}
    local g = roster[name]
    if g then for k, v in pairs(g) do info[k] = v end end
    local f = Compat.FriendInfo(name)
    if f then for k, v in pairs(f) do if info[k] == nil then info[k] = v end end end
    return info
end

-- Known players skip the Requests tab.
local function isKnown(name)
    return roster[name] ~= nil or Compat.FriendInfo(name) ~= nil
end

-- ---------------------------------------------------------------------------
-- Capture
-- ---------------------------------------------------------------------------

local function onWhisper(event, text, sender, _, _, _, flags, _, _, _, _, _, guid)
    local name = Compat.NormalizeName(sender)
    if not name then return end
    local incoming = event == "CHAT_MSG_WHISPER"
    local key = Data.WhisperKey(name)
    -- The server's spelling wins: fold conversations that only differ in letter case into this one.
    for _, other in ipairs(Data.CaseVariants(name, key)) do Data.Rekey(other, key, name) end

    local info = Chat.LookupInfo(name)
    info.class = info.class or Compat.ClassFromGUID(guid)

    local conv, created = Data.Ensure(key, {
        kind = "whisper", target = name, display = name, info = info,
        request = incoming and not isKnown(name) and flags ~= "GM",
    })
    -- Unique id of the character: first names are not unique on WoW Forever (surnames).
    if guid and guid ~= "" then conv.guid = guid end
    if not created then Data.UpdateInfo(conv, info) end

    Data.AddMessage(key, {
        d = incoming and "in" or "out",
        m = text,
        s = incoming and name or nil,
        k = flags == "GM" and "gm" or nil,
    })
    if incoming then
        Hush.char.lastWhisper = key
        -- Keep /r in the default chat working even when the whisper was hidden there.
        Compat.SetLastTellTarget(name, "WHISPER")
        if not roster[name] then requestRoster() end
    end
end

local function onBNWhisper(event, text, _, _, _, _, _, _, _, _, _, _, _, bnID)
    local bn = Compat.BNInfo(bnID) or {}
    local tag = bn.tag or ("id" .. tostring(bnID))
    local key = Data.BNetKey(tag)
    local incoming = event == "CHAT_MSG_BN_WHISPER"

    local info = { class = bn.class, level = bn.level, zone = bn.zone, online = bn.online,
                   status = bn.status, character = bn.character }
    local conv, created = Data.Ensure(key, {
        kind = "bnet", target = tag, display = tag:match("^[^#]+") or tag, info = info,
    })
    if not created then Data.UpdateInfo(conv, info) end
    conv.bnID = bnID -- session-local, refreshed on every message

    Data.AddMessage(key, { d = incoming and "in" or "out", m = text, s = incoming and conv.display or nil })
    if incoming then
        Hush.char.lastWhisper = key
        if bn.name then Compat.SetLastTellTarget(bn.name, "BN_WHISPER") end
    end
end

-- AFK/DND auto-replies and "player not found" become discreet system lines.
local function addSystemLine(name, kind, text)
    local key = Data.WhisperKey(name)
    local conv = Data.Get(key)
    if not conv then return false end
    -- Auto-replies repeat on every whisper; skip an identical one within 5 minutes.
    local last = conv.msgs[#conv.msgs]
    if last and last.d == "sys" and last.k == kind and last.m == text and time() - last.t < 300 then
        return true
    end
    Data.AddMessage(key, { d = "sys", k = kind, m = text })
    return true
end

local function onAutoReply(event, text, sender)
    local name = Compat.NormalizeName(sender)
    if not name then return end
    local kind = event == "CHAT_MSG_AFK" and "afk" or "dnd"
    local label = kind == "afk" and "is AFK" or "is busy (DND)"
    addSystemLine(name, kind, (text and text ~= "") and (label .. ": " .. text) or label)
end

local function onSystem(_, text)
    text = text or ""
    local who = Compat.MatchPlayerNotFound(text)
    if who then
        local name = Compat.NormalizeName(who)
        if name then addSystemLine(name, "notfound", "Player not found (offline or wrong name).") end
        return
    end
    -- Keep online dots current for guild members and friends.
    local who2, online = Compat.MatchOnlineStatus(text)
    local name = who2 and Compat.NormalizeName(who2)
    local conv = name and Data.Get(Data.WhisperKey(name))
    if conv then Data.UpdateInfo(conv, { online = online }) end
end

-- ---------------------------------------------------------------------------
-- Default chat filter
-- ---------------------------------------------------------------------------

-- Hide only when enabled, when Hush can show messages, and never in combat.
local function shouldHide()
    local s = Hush.settings
    return s ~= nil and s.hideWhispers and Hush.canDisplay == true and not Compat.InCombat()
end
Chat.ShouldHide = shouldHide

local function whisperFilter(_, _, _, _, _, _, _, flags)
    if flags == "GM" then return false end
    return shouldHide()
end

local function autoReplyFilter(_, _, _, sender)
    local name = Compat.NormalizeName(sender)
    return name ~= nil and Data.Get(Data.WhisperKey(name)) ~= nil and shouldHide()
end

local function systemFilter(_, _, text)
    local who = Compat.MatchPlayerNotFound(text or "")
    if not who then return false end
    local name = Compat.NormalizeName(who)
    return name ~= nil and Data.Get(Data.WhisperKey(name)) ~= nil and shouldHide()
end

-- ---------------------------------------------------------------------------
-- Setup
-- ---------------------------------------------------------------------------

Hush:RegisterEvent("PLAYER_LOGIN", function()
    Chat.inCombat = Compat.InCombat()

    Hush:RegisterEvent("CHAT_MSG_WHISPER", onWhisper)
    Hush:RegisterEvent("CHAT_MSG_WHISPER_INFORM", onWhisper)
    Hush:RegisterEvent("CHAT_MSG_BN_WHISPER", onBNWhisper)
    Hush:RegisterEvent("CHAT_MSG_BN_WHISPER_INFORM", onBNWhisper)
    Hush:RegisterEvent("CHAT_MSG_AFK", onAutoReply)
    Hush:RegisterEvent("CHAT_MSG_DND", onAutoReply)
    Hush:RegisterEvent("CHAT_MSG_SYSTEM", onSystem)

    if Compat.features.ChatFilter then
        for _, e in ipairs({ "CHAT_MSG_WHISPER", "CHAT_MSG_WHISPER_INFORM", "CHAT_MSG_BN_WHISPER", "CHAT_MSG_BN_WHISPER_INFORM" }) do
            ChatFrame_AddMessageEventFilter(e, whisperFilter)
        end
        ChatFrame_AddMessageEventFilter("CHAT_MSG_AFK", autoReplyFilter)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_DND", autoReplyFilter)
        ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", systemFilter)
    end

    Compat.After(3, function() requestRoster(true) end)
end)

Hush:RegisterEvent("PLAYER_REGEN_DISABLED", function() Chat.inCombat = true end)
Hush:RegisterEvent("PLAYER_REGEN_ENABLED", function() Chat.inCombat = false end)

-- ---------------------------------------------------------------------------
-- Test commands (until the window exists)
-- ---------------------------------------------------------------------------

local function findConv(query)
    query = strlower(query)
    for key, conv in pairs(Data.All()) do
        if strlower(conv.display) == query or strlower(key) == query then return key, conv end
    end
    for key, conv in pairs(Data.All()) do
        if strlower(conv.display):find(query, 1, true) then return key, conv end
    end
end

local function fmtTime(t) return date("%H:%M", t) end

Hush:AddSlashCommand("dump", function(arg)
    if arg ~= "" then
        local key, conv = findConv(arg)
        if not conv then Hush:Print("No conversation matching", arg) return end
        Hush:Print(("%s  [%s/%s] class=%s lvl=%s zone=%s guild=%s online=%s"):format(key, Data.TabOf(conv),
            conv.category, tostring(conv.info.class), tostring(conv.info.level), tostring(conv.info.zone),
            tostring(conv.info.guild), tostring(conv.info.online)))
        for i = max(1, #conv.msgs - 9), #conv.msgs do
            local m = conv.msgs[i]
            local who = m.d == "out" and "You" or m.d == "sys" and "*" .. (m.k or "sys") or (m.s or "?")
            local newMark = conv.firstUnread and m.n == conv.firstUnread and " |cff3fc7eb--- New ---|r" or ""
            Hush:Print(("  #%d %s %s: %s%s"):format(m.n, fmtTime(m.t), who, m.m, newMark))
        end
        return
    end

    local list = {}
    for key, conv in pairs(Data.All()) do list[#list + 1] = { key = key, conv = conv } end
    sort(list, function(a, b) return a.conv.last > b.conv.last end)
    local total, byTab = Data.UnreadTotals()
    Hush:Print(("%d conversations, unread %d (whispers %d, requests %d, groups %d)"):format(
        #list, total, byTab.whispers, byTab.requests, byTab.groups))
    for _, e in ipairs(list) do
        local c = e.conv
        Hush:Print(("  %s [%s/%s%s] unread %d, %d msgs, %s: %s"):format(e.key, Data.TabOf(c), c.category,
            c.pinned and ", pinned" or "", c.unread, #c.msgs, fmtTime(c.last), c.preview))
    end
end, "list conversations, or /hush dump <name> for messages")

Hush:AddSlashCommand("fake", function(arg)
    local name, text = arg:match("^(%S+)%s*(.*)$")
    name = name or "Testplayer"
    if not text or text == "" then text = "Hello from " .. name .. "! |cff1eff00|Hitem:2589::::::::1:::::::|h[Linen Cloth]|h|r" end
    onWhisper("CHAT_MSG_WHISPER", text, name, "", "", "", "", 0, 0, "", 0, 0, "")
    local conv = Data.Get(Data.WhisperKey(Compat.NormalizeName(name)))
    if conv then conv.fake = true end
    Hush:Print("Fake whisper from", name)
end, "simulate an incoming whisper: /hush fake <name> <text>")

Hush:AddSlashCommand("read", function(arg)
    local key = findConv(arg)
    if key then Data.MarkRead(key) Hush:Print("Marked read:", key) end
end, "mark a conversation read: /hush read <name>")

Hush:AddSlashCommand("move", function(arg)
    local name, cat = arg:match("^(%S+)%s+(%S+)$")
    local key = name and findConv(name)
    if key and Data.Move(key, strlower(cat)) then Hush:Print("Moved", key, "to", cat) else Hush:Print("Usage: /hush move <name> <guild|recruits|other>") end
end, "move a conversation: /hush move <name> <category>")

Hush:AddSlashCommand("filter", function()
    Hush.settings.hideWhispers = not Hush.settings.hideWhispers
    Hush:Print("Hide whispers in the default chat:", Hush.settings.hideWhispers and "ON (never in combat)" or "OFF")
    Hush:Fire("SETTINGS_CHANGED", "hideWhispers")
end, "toggle hiding whispers in the default chat")

local FAKE_NAMES = { "Aldric", "Brynja", "Cedwyn", "Dagny", "Eirik", "Freja", "Gunnar", "Hilda", "Ivar", "Jorunn",
    "Kettil", "Liv", "Magnus", "Nanna", "Orm", "Pernilla", "Ragnar", "Sigrid", "Torvald", "Ulla", "Vidar", "Ylva",
    "Åsa", "Östen", "Ärling" }
local FAKE_CLASSES = { "WARRIOR", "MAGE", "PRIEST", "ROGUE", "DRUID", "HUNTER", "WARLOCK", "PALADIN", "SHAMAN" }
local FAKE_TEXTS = { "lf healer for SM?", "Hey, still recruiting?", "thanks for the invite!", "wanna trade?",
    "Can you craft this for me?", "brb", "Where do I find the quest giver in Ironforge?", "gg" }

Hush:AddSlashCommand("fakemany", function(arg)
    local n = tonumber(arg) or 20
    local cats = { "other", "other", "guild", "recruits" }
    for i = 1, n do
        local name = FAKE_NAMES[(i - 1) % #FAKE_NAMES + 1] .. (i > #FAKE_NAMES and tostring(i) or "")
        local key = Data.WhisperKey(name)
        local online = ({ true, false, nil })[i % 3 + 1]
        local conv = Data.Ensure(key, { kind = "whisper", target = name, display = name, request = i % 7 == 0,
            info = { class = FAKE_CLASSES[i % #FAKE_CLASSES + 1], level = 10 + i % 51, zone = "Elwynn Forest",
                     online = online, status = (i % 5 == 0 and online) and "away" or nil } })
        conv.fake = true
        conv.category = cats[i % #cats + 1]
        conv.pinned = i == 3
        Data.AddMessage(key, { d = "in", m = FAKE_TEXTS[i % #FAKE_TEXTS + 1], s = name, t = time() - i * 3600 * 5 })
        if i % 2 == 0 then Data.MarkRead(key) end
    end
    Hush:Print("Created", n, "fake conversations. Remove with /hush clearfake")
end, "create test conversations: /hush fakemany [n]")

Hush:AddSlashCommand("clearfake", function()
    local n = 0
    for key, conv in pairs(Data.All()) do
        if conv.fake then Data.Delete(key) n = n + 1 end
    end
    Hush:Print("Removed", n, "fake conversations.")
end, "remove test conversations")

Hush:AddSlashCommand("fakeconvo", function(arg)
    local name = arg ~= "" and arg or "Sigrid"
    local key = Data.WhisperKey(name)
    local conv = Data.Ensure(key, { kind = "whisper", target = name, display = name,
        info = { class = "PRIEST", level = 42, zone = "Stranglethorn Vale", guild = "Slakthuset", online = true } })
    conv.fake = true
    local now = time()
    local day = 86400
    local script = {
        { -2 * day - 3000, "in", "Hey! Saw your post about the guild, are you still recruiting?" },
        { -2 * day - 2940, "in", "I'm a priest, mostly holy, lvl 42 right now" },
        { -2 * day - 2800, "out", "Hi! Yes we are :) What's your raid experience?" },
        { -2 * day - 2700, "in", "Did MC and Onyxia back in the day. I can show you my gear: |cff0070dd|Hitem:10041::::::::60:::::::|h[Dragon Finger]|h|r" },
        { -day - 500, "sys", "is AFK: Away from keyboard", "afk" },
        { -day - 400, "out", "Ping me when you're back!" },
        { -3600, "in", "Back now, sorry! This is a longer message to test word wrapping in the conversation view, it should wrap nicely across several lines without breaking the layout or overlapping the next message." },
        { -3500, "in", "Also, do you have a guild bank?" },
        { -600, "in", "Hello?" },
        { -300, "in", "Guess you're busy, talk later! |cff71d5ff|Hspell:2061|h[Flash Heal]|h|r" },
    }
    for i, s in ipairs(script) do
        local d = s[2]
        Data.AddMessage(key, { d = d, m = s[3], s = d == "in" and name or nil, k = s[4], t = now + s[1] })
        -- Everything before the last three incoming messages counts as read.
        if i == 8 then Data.MarkRead(key) end
    end
    Hush:Print("Created a test conversation with", name, "- open /hush and select it.")
end, "create a test conversation: /hush fakeconvo [name]")

-- Hush can show whispers from now on, so the default-chat filter may hide them.
Hush:RegisterCallback("READY", function() Hush.canDisplay = true end, "Chat")

-- Merge conversations that only differ in letter case (created before names were matched case-insensitively).
Hush:RegisterCallback("READY", function()
    Data.MergeCaseDuplicates()
    -- Older data from before surnames were part of the character key.
    for _, c in ipairs(Data.Characters()) do
        if c.char.legacy then
            Hush:Print("Chats from before the surname fix are under \"" .. (c.char.name or c.key)
                .. " (older data)\". Merge them into the right character in Settings > Storage.")
            break
        end
    end
    -- Storage rules run once per login (cheap: one pass over the conversations).
    local removed = Data.Cleanup()
    if removed > 0 then Hush:Print(("Removed %d old chat%s (Settings > Storage)."):format(removed, removed == 1 and "" or "s")) end
end, "Chat")
