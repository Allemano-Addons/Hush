-- Compat: everything that may differ on WoW Forever (a Classic+ beta whose API can change).
-- Other files must go through here instead of calling version-sensitive APIs directly.
local _, Hush = ...

local Compat = {}
Hush.Compat = Compat

-- Feature detection, shown by /hush debug.
Compat.features = {
    Ambiguate = type(Ambiguate) == "function",
    BackdropTemplate = BackdropTemplateMixin ~= nil,
    BNet = type(BNGetFriendInfoByID) == "function" or (C_BattleNet and C_BattleNet.GetAccountInfoByID) ~= nil,
    C_AddOns = C_AddOns ~= nil,
    C_ChatInfo = C_ChatInfo ~= nil and C_ChatInfo.SendAddonMessage ~= nil,
    C_FriendList = C_FriendList ~= nil,
    C_Timer = C_Timer ~= nil,
    ChatFilter = type(ChatFrame_AddMessageEventFilter) == "function",
    PhysicalScreenSize = type(GetPhysicalScreenSize) == "function",
    MouseIsOverGlobal = type(MouseIsOver) == "function",
}

-- ---------------------------------------------------------------------------
-- Names
-- ---------------------------------------------------------------------------

-- Same player -> same key: "Name" on own realm, "Name-Realm" for others.
function Compat.NormalizeName(name)
    if not name or name == "" then return nil end
    if Compat.features.Ambiguate then
        return Ambiguate(name, "none")
    end
    local realm = Compat.PlayerRealm()
    local short, r = strsplit("-", name, 2)
    if r and r ~= realm then return name end
    return short
end

function Compat.PlayerRealm()
    local realm = GetNormalizedRealmName and GetNormalizedRealmName()
    if not realm or realm == "" then
        realm = (GetRealmName() or ""):gsub("[%s%-]", "")
    end
    return realm
end

-- Your full character name. On WoW Forever UnitName returns the first name and the
-- SURNAME separately, and first names are not unique ("Allemano Moo" and "Allemano Mu"
-- are different characters), so the surname is part of the name. Chat events use the
-- same "First Last" form.
function Compat.PlayerName()
    local name, second = UnitName("player")
    name = name or "Unknown"
    if type(second) == "string" and second ~= "" then
        local sep = Constants and Constants.CharacterNameSeparatorConsts
            and Constants.CharacterNameSeparatorConsts.CHARACTERNAME_SURNAME_SEPARATOR or " "
        return name .. sep .. second
    end
    return name
end

-- Key for per-character storage: full name + realm.
function Compat.PlayerKey()
    return Compat.PlayerName() .. "-" .. Compat.PlayerRealm()
end

-- The key Hush used before 0.1.18 (first name only), for the "older data" bucket.
function Compat.LegacyPlayerKey()
    return (UnitName("player") or "Unknown") .. "-" .. Compat.PlayerRealm()
end

-- ---------------------------------------------------------------------------
-- Classes
-- ---------------------------------------------------------------------------

-- Returns classFile (e.g. "MAGE") for a GUID, or nil.
function Compat.ClassFromGUID(guid)
    if not guid or guid == "" or type(GetPlayerInfoByGUID) ~= "function" then return nil end
    local ok, _, classFile = pcall(GetPlayerInfoByGUID, guid)
    if ok then return classFile end
end

-- r, g, b for a classFile, or nil.
function Compat.ClassColor(classFile)
    if not classFile then return nil end
    local colors = CUSTOM_CLASS_COLORS or RAID_CLASS_COLORS
    local c = colors and colors[classFile]
    if c then return c.r, c.g, c.b end
end

function Compat.PlayerClass()
    local _, classFile = UnitClass("player")
    return classFile
end

-- Localized class name ("Mage", "Magier") -> classFile ("MAGE").
local localizedToFile
function Compat.ClassFileFromLocalized(name)
    if not name then return nil end
    if not localizedToFile then
        localizedToFile = {}
        for file, loc in pairs(LOCALIZED_CLASS_NAMES_MALE or {}) do localizedToFile[loc] = file end
        for file, loc in pairs(LOCALIZED_CLASS_NAMES_FEMALE or {}) do localizedToFile[loc] = file end
    end
    return localizedToFile[name] or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[strupper(name)] and strupper(name))
end

-- ---------------------------------------------------------------------------
-- Guild and friends
-- ---------------------------------------------------------------------------

function Compat.RequestGuildRoster()
    if not IsInGuild() then return end
    if C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    elseif GuildRoster then
        GuildRoster()
    end
end

function Compat.PlayerGuildName()
    return IsInGuild() and GetGuildInfo("player") or nil
end

-- Returns { [normalizedName] = info } for the whole guild roster.
function Compat.ReadGuildRoster()
    local roster = {}
    if not IsInGuild() then return roster end
    local guild = Compat.PlayerGuildName()
    for i = 1, GetNumGuildMembers() do
        local name, _, _, level, _, zone, _, _, online, status, classFile = GetGuildRosterInfo(i)
        local key = Compat.NormalizeName(name)
        if key then
            roster[key] = {
                class = classFile, level = level, zone = zone, guild = guild,
                online = online and true or false,
                status = (status == 1 or status == "<AFK>") and "away" or (status == 2 or status == "<DND>") and "busy" or nil,
            }
        end
    end
    return roster
end

-- Friend-list info for a character name, or nil.
function Compat.FriendInfo(name)
    if not (C_FriendList and C_FriendList.GetFriendInfo) then return nil end
    local f = C_FriendList.GetFriendInfo(name)
    if not f then return nil end
    return {
        class = Compat.ClassFileFromLocalized(f.className),
        level = f.level, zone = f.area,
        online = f.connected and true or false,
        status = f.afk and "away" or f.dnd and "busy" or nil,
    }
end

-- ---------------------------------------------------------------------------
-- Battle.net
-- ---------------------------------------------------------------------------

-- Info about a Battle.net account from a bnSenderID (session-local id), or nil.
-- tag is the stable key (BattleTag); name may be a protected |K string for display only.
function Compat.BNInfo(bnID)
    if not bnID or bnID == 0 then return nil end
    if C_BattleNet and C_BattleNet.GetAccountInfoByID then
        local a = C_BattleNet.GetAccountInfoByID(bnID)
        if a then
            local g = a.gameAccountInfo or {}
            return {
                tag = a.battleTag, name = a.accountName,
                character = g.characterName, realm = g.realmName,
                class = Compat.ClassFileFromLocalized(g.className),
                level = g.characterLevel, zone = g.areaName,
                online = g.isOnline and true or false,
                status = a.isAFK and "away" or a.isDND and "busy" or nil,
            }
        end
    end
    if BNGetFriendInfoByID then
        local _, accountName, battleTag, _, charName, _, _, isOnline, _, isAFK, isDND = BNGetFriendInfoByID(bnID)
        if battleTag or accountName then
            return {
                tag = battleTag, name = accountName, character = charName,
                online = isOnline and true or false,
                status = isAFK and "away" or isDND and "busy" or nil,
            }
        end
    end
end

-- Current session id (bnetAccountID) for a BattleTag, or nil if not a friend / offline list.
function Compat.BNIDFromTag(tag)
    if not tag or not BNGetNumFriends then return nil end
    for i = 1, BNGetNumFriends() do
        if C_BattleNet and C_BattleNet.GetFriendAccountInfo then
            local a = C_BattleNet.GetFriendAccountInfo(i)
            if a and a.battleTag == tag then return a.bnetAccountID end
        elseif BNGetFriendInfo then
            local id, _, battleTag = BNGetFriendInfo(i)
            if battleTag == tag then return id end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Sending
-- ---------------------------------------------------------------------------

local function sendChat(text, chatType, target)
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        C_ChatInfo.SendChatMessage(text, chatType, nil, target)
    else
        SendChatMessage(text, chatType, nil, target)
    end
end

-- Send one part (<= 255 bytes) to a conversation. Returns false if it can't be delivered.
function Compat.Send(conv, text)
    if conv.kind == "whisper" then
        sendChat(text, "WHISPER", conv.target)
        return true
    elseif conv.kind == "bnet" then
        local id = Compat.BNIDFromTag(conv.target) or conv.bnID
        if not id then return false end
        if C_BattleNet and C_BattleNet.SendWhisper then
            C_BattleNet.SendWhisper(id, text)
        else
            BNSendWhisper(id, text)
        end
        return true
    elseif conv.kind == "group" then
        sendChat(text, conv.channel or "PARTY")
        return true
    end
    return false
end

function Compat.InviteToGroup(name)
    if C_PartyInfo and C_PartyInfo.InviteUnit then
        C_PartyInfo.InviteUnit(name)
    elseif InviteUnit then
        InviteUnit(name)
    end
end

function Compat.CanGuildInvite()
    return IsInGuild() and CanGuildInvite ~= nil and CanGuildInvite() and true or false
end

function Compat.GuildInvite(name)
    if C_GuildInfo and C_GuildInfo.Invite then
        C_GuildInfo.Invite(name)
    elseif GuildInvite then
        GuildInvite(name)
    end
end

-- Call fn(link) whenever the game inserts a link (shift-click on items, spells, quests...).
function Compat.HookInsertLink(fn)
    if ChatFrameUtil and ChatFrameUtil.InsertLink then
        hooksecurefunc(ChatFrameUtil, "InsertLink", fn)
    elseif ChatEdit_InsertLink then
        hooksecurefunc("ChatEdit_InsertLink", fn)
    end
end

-- Let /r in the default chat reply to a whisper that Hush hid.
function Compat.SetLastTellTarget(name, chatType)
    if ChatEdit_SetLastTellTarget then
        ChatEdit_SetLastTellTarget(name, chatType)
    end
end

-- ---------------------------------------------------------------------------
-- System messages
-- ---------------------------------------------------------------------------

-- Turns a Blizzard format string ("No player named '%s' is currently playing.") into a Lua pattern.
local function formatToPattern(fmt)
    local p = fmt:gsub("([%%%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
    p = p:gsub("%%%%s", "(.+)"):gsub("%%%%d", "(%%d+)")
    return "^" .. p .. "$"
end

local onlinePattern, offlinePattern
-- "X has come online." / "X has gone offline." (guild members and friends).
-- Returns name, isOnline or nil.
function Compat.MatchOnlineStatus(msg)
    if ERR_FRIEND_ONLINE_SS then
        onlinePattern = onlinePattern or formatToPattern(ERR_FRIEND_ONLINE_SS)
        local name = msg:match(onlinePattern)
        if name then return name, true end
    end
    if ERR_FRIEND_OFFLINE_S then
        offlinePattern = offlinePattern or formatToPattern(ERR_FRIEND_OFFLINE_S)
        local name = msg:match(offlinePattern)
        if name then return name, false end
    end
end

local notFoundPattern
-- Returns the player name if msg is "player not found", else nil.
function Compat.MatchPlayerNotFound(msg)
    if not ERR_CHAT_PLAYER_NOT_FOUND_S then return nil end
    notFoundPattern = notFoundPattern or formatToPattern(ERR_CHAT_PLAYER_NOT_FOUND_S)
    return msg:match(notFoundPattern)
end

-- ---------------------------------------------------------------------------
-- Misc
-- ---------------------------------------------------------------------------

function Compat.GetAddOnMetadata(addon, field)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(addon, field)
    end
    return GetAddOnMetadata(addon, field)
end

-- Is the mouse over a frame/region? The global MouseIsOver() is missing on WoW Forever,
-- the IsMouseOver method is what exists there.
function Compat.MouseIsOver(region)
    if not region or not region:IsVisible() then return false end
    if region.IsMouseOver then return region:IsMouseOver() end
    if MouseIsOver then return MouseIsOver(region) end
    return false
end

function Compat.InCombat()
    return InCombatLockdown() or UnitAffectingCombat("player") and true or false
end

local timerFrame
function Compat.After(seconds, fn)
    if C_Timer and C_Timer.After then
        return C_Timer.After(seconds, fn)
    end
    -- Fallback: tiny OnUpdate that only runs while timers are pending.
    if not timerFrame then
        timerFrame = CreateFrame("Frame")
        timerFrame.pending = {}
        timerFrame:SetScript("OnUpdate", function(self)
            local now = GetTime()
            for i = #self.pending, 1, -1 do
                local t = self.pending[i]
                if now >= t.at then
                    tremove(self.pending, i)
                    t.fn()
                end
            end
            if #self.pending == 0 then self:Hide() end
        end)
    end
    tinsert(timerFrame.pending, { at = GetTime() + seconds, fn = fn })
    timerFrame:Show()
end

-- Physical resolution, used for pixel-perfect borders.
function Compat.GetPhysicalScreenSize()
    if Compat.features.PhysicalScreenSize then
        local w, h = GetPhysicalScreenSize()
        if w and h and h > 0 then return w, h end
    end
    if GetScreenResolutions and GetCurrentResolution then
        local res = select(GetCurrentResolution(), GetScreenResolutions())
        if res then
            local w, h = res:match("(%d+)x(%d+)")
            if w then return tonumber(w), tonumber(h) end
        end
    end
    return 1920, 1080
end
