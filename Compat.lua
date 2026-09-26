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

-- Key for per-character storage.
function Compat.PlayerKey()
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

-- ---------------------------------------------------------------------------
-- Misc
-- ---------------------------------------------------------------------------

function Compat.GetAddOnMetadata(addon, field)
    if C_AddOns and C_AddOns.GetAddOnMetadata then
        return C_AddOns.GetAddOnMetadata(addon, field)
    end
    return GetAddOnMetadata(addon, field)
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
