std = "lua51"
max_line_length = false
self = false
exclude_files = { "Media/**" }

-- The only globals Hush may write.
globals = {
    "HushDB",
    "Hush",
    "SLASH_HUSH1",
    "SlashCmdList",
    "BINDING_HEADER_HUSH",
    "BINDING_NAME_HUSH_TOGGLE",
    "BINDING_NAME_HUSH_REPLY",
}

-- WoW API used by Hush (read-only). Extend as new APIs are used.
read_globals = {
    -- Lua extensions in WoW
    "strjoin", "strsplit", "strtrim", "strlower", "strupper", "strlen", "strsub", "strfind",
    "tostringall", "tinsert", "tremove", "wipe", "sort", "floor", "ceil", "min", "max", "abs",
    "format", "date", "time", "CopyTable", "geterrorhandler", "securecall",

    -- Frames and UI
    "CreateFrame", "UIParent", "DEFAULT_CHAT_FRAME", "BackdropTemplateMixin",
    "GetCursorPosition", "MouseIsOver", "PlaySound", "PlaySoundFile", "SOUNDKIT",
    "GameTooltip", "SetItemRef", "ChatEdit_InsertLink", "ChatFrame_AddMessageEventFilter",
    "ChatFrame_RemoveMessageEventFilter", "ChatFrame_SendTell",

    -- Game info
    "GetBuildInfo", "GetTime", "GetAddOnMetadata", "C_AddOns", "C_Timer", "C_ChatInfo",
    "C_FriendList", "C_BattleNet", "C_GuildInfo",
    "GetPhysicalScreenSize", "GetScreenResolutions", "GetCurrentResolution",
    "UnitName", "UnitClass", "UnitAffectingCombat", "InCombatLockdown",
    "GetRealmName", "GetNormalizedRealmName", "GetPlayerInfoByGUID",
    "Ambiguate", "BNGetFriendInfoByID", "RAID_CLASS_COLORS", "CUSTOM_CLASS_COLORS",
    "LOCALIZED_CLASS_NAMES_MALE", "LOCALIZED_CLASS_NAMES_FEMALE",
    "IsInGuild", "GetGuildInfo", "GetNumGuildMembers", "GetGuildRosterInfo", "GuildRoster",
    "ERR_CHAT_PLAYER_NOT_FOUND_S",
}
