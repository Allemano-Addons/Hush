std = "lua51"
max_line_length = false
self = false
exclude_files = { "Media/**", "Tests/**" }

-- The only globals Hush may write.
globals = {
    "HushDB",
    "Hush",
    "SLASH_HUSH1",
    "SlashCmdList",
    "BINDING_HEADER_HUSH",
    "BINDING_NAME_HUSH_TOGGLE",
    "BINDING_NAME_HUSH_REPLY",
    -- Window names, only so ESC closes them via UISpecialFrames.
    "HushFrame", "HushSettingsFrame",
}

-- WoW API used by Hush (read-only). Extend as new APIs are used.
read_globals = {
    "issecretvalue",
    "UISpecialFrames",
    -- Lua extensions in WoW
    "strjoin", "strsplit", "strtrim", "strlower", "strupper", "strlen", "strsub", "strfind",
    "tostringall", "tinsert", "tremove", "wipe", "sort", "floor", "ceil", "min", "max", "abs",
    "format", "date", "time", "CopyTable", "geterrorhandler", "securecall",

    -- Frames and UI
    "CreateFrame", "UIParent", "DEFAULT_CHAT_FRAME", "BackdropTemplateMixin",
    "GetCursorPosition", "PlaySound", "PlaySoundFile", "SOUNDKIT",
    "GameTooltip", "SetItemRef", "ChatEdit_InsertLink", "ChatFrame_AddMessageEventFilter",
    "ChatFrame_RemoveMessageEventFilter", "ChatFrame_SendTell",

    -- Game info
    "GetBuildInfo", "GetTime", "GetAddOnMetadata", "C_AddOns", "C_Timer", "C_ChatInfo",
    "C_FriendList", "C_BattleNet", "C_GuildInfo",
    "GetPhysicalScreenSize", "GetScreenResolutions", "GetCurrentResolution",
    "UnitName", "UnitClass", "UnitAffectingCombat", "InCombatLockdown", "UnitIsAFK", "UnitIsDND", "IsInInstance",
    "GetRealmName", "GetNormalizedRealmName", "GetPlayerInfoByGUID",
    "Ambiguate", "BNGetFriendInfoByID", "RAID_CLASS_COLORS", "CUSTOM_CLASS_COLORS",
    "LOCALIZED_CLASS_NAMES_MALE", "LOCALIZED_CLASS_NAMES_FEMALE",
    "IsInGuild", "GetGuildInfo", "GetNumGuildMembers", "GetGuildRosterInfo", "GuildRoster",
    "LibStub", "ERR_CHAT_PLAYER_NOT_FOUND_S", "ERR_FRIEND_ONLINE_SS", "ERR_FRIEND_OFFLINE_S",
    "SendChatMessage", "BNSendWhisper", "BNGetNumFriends", "BNGetFriendInfo",
    "ChatFrameUtil", "ChatEdit_SetLastTellTarget", "ChatEdit_SendText", "ChatEdit_DeactivateChat", "ChatFrame1EditBox", "hooksecurefunc", "IsShiftKeyDown",
    "Constants", "MouseIsOver", "MouseIsOver", "IsMouseButtonDown", "InviteUnit", "GuildInvite", "CanGuildInvite", "C_PartyInfo",
    "GetLocale", "GetNumAddOns", "GetAddOnInfo", "IsAddOnLoaded", "IsInRaid", "IsInGroup", "GetNumRaidMembers", "GetNumPartyMembers", "GetNumGroupMembers",
}
