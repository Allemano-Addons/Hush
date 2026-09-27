-- Groups: party and raid chat as their own conversations, one per group/raid session.
-- Group chat is never hidden in the default chat.
local _, Hush = ...

local Compat, Data = Hush.Compat, Hush.Data

local Groups = {}
Hush.Groups = Groups

local LABEL = { PARTY = "Party", RAID = "Raid" }

-- "PARTY", "RAID" or nil.
function Groups.CurrentType()
    if IsInRaid and IsInRaid() then return "RAID" end
    if IsInGroup and IsInGroup() then return "PARTY" end
    if GetNumRaidMembers and GetNumRaidMembers() > 0 then return "RAID" end
    if GetNumPartyMembers and GetNumPartyMembers() > 0 then return "PARTY" end
    return nil
end

function Groups.MemberCount()
    if GetNumGroupMembers then return GetNumGroupMembers() end
    return 0
end

-- The active session is saved per character so /reload continues the same conversation.
local function session() return Hush.char.group end

local function endSession()
    local s = session()
    if not s then return end
    local conv = s.key and Data.Get(s.key)
    if conv then
        conv.ended = time()
        Data.UpdateInfo(conv, { online = false })
    end
    Hush.char.group = nil
end

-- Called on login and roster changes: start/end sessions as the group changes.
function Groups.Check()
    if not Hush.char then return end
    local t = Groups.CurrentType()
    local s = session()
    if not t then
        endSession()
    elseif not s or s.type ~= t then
        -- New group, or party converted to raid: a new conversation.
        endSession()
        Hush.char.group = { type = t, started = time() }
    end
    -- Keep the header (member count) current.
    local cur = session()
    local conv = cur and cur.key and Data.Get(cur.key)
    if conv then Hush:Fire("CONV_UPDATED", conv) end
end

-- Conversation for the current session, created on the first message.
local function sessionConv()
    local s = session()
    if not s then
        Groups.Check()
        s = session()
        if not s then return nil end
    end
    if s.key and Data.Get(s.key) then return s.key, Data.Get(s.key) end
    local key = "G:" .. strlower(s.type) .. ":" .. s.started
    local conv = Data.Ensure(key, {
        kind = "group",
        display = LABEL[s.type] .. "  ·  " .. date("%d/%m %H:%M", s.started),
        info = { online = true },
    })
    conv.channel = s.type
    s.key = key
    return key, conv
end

function Groups.IsActive(conv)
    local s = session()
    return conv.kind == "group" and s ~= nil and s.key ~= nil and Data.Get(s.key) == conv
end

-- ---------------------------------------------------------------------------
-- Capture
-- ---------------------------------------------------------------------------

local KINDS = {
    CHAT_MSG_PARTY_LEADER = "leader",
    CHAT_MSG_RAID_LEADER = "leader",
    CHAT_MSG_RAID_WARNING = "warning",
}

local function onGroupMessage(event, text, sender, _, _, _, _, _, _, _, _, _, guid)
    local key = sessionConv()
    if not key then return end
    local name = Compat.NormalizeName(sender) or sender
    local me = Compat.PlayerName()
    Data.AddMessage(key, {
        d = (name == me) and "out" or "in",
        m = text,
        s = name,
        c = Compat.ClassFromGUID(guid),
        k = KINDS[event],
    })
end

Hush:RegisterEvent("PLAYER_LOGIN", function()
    for _, e in ipairs({ "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_RAID",
                         "CHAT_MSG_RAID_LEADER", "CHAT_MSG_RAID_WARNING" }) do
        Hush:RegisterEvent(e, onGroupMessage)
    end
    Hush:RegisterEvent("GROUP_ROSTER_UPDATE", Groups.Check)
    -- Some clients fire the older roster events instead.
    Hush:RegisterEvent("PARTY_MEMBERS_CHANGED", Groups.Check)
    Hush:RegisterEvent("RAID_ROSTER_UPDATE", Groups.Check)
    Compat.After(2, Groups.Check)
end)

-- ---------------------------------------------------------------------------
-- Test command
-- ---------------------------------------------------------------------------

Hush:AddSlashCommand("fakegroup", function()
    local started = time() - 1800
    local key = "G:party:" .. started
    local conv = Data.Ensure(key, {
        kind = "group", display = "Party  ·  " .. date("%d/%m %H:%M", started), info = { online = false },
    })
    conv.channel, conv.ended, conv.fake = "PARTY", time() - 60, true
    local lines = {
        { "Ragnar", "WARRIOR", "leader", "ok everyone, pull after buffs" },
        { "Sigrid", "PRIEST", nil, "oom, 10 sec" },
        { "Ivar", "MAGE", nil, "want water? |cffffffff|Hitem:8079::::::::60:::::::|h[Conjured Crystal Water]|h|r" },
        { Compat.PlayerName(), Compat.PlayerClass(), nil, "ready!" },
        { "Ragnar", "WARRIOR", "warning", "DON'T PULL THE PATROL" },
    }
    for i, l in ipairs(lines) do
        Data.AddMessage(key, { d = l[1] == Compat.PlayerName() and "out" or "in", m = l[4], s = l[1], c = l[2], k = l[3],
                               t = started + i * 120 })
    end
    Hush:Print("Created a test group chat (ended). Open the Groups tab.")
end, "create a test party conversation")
