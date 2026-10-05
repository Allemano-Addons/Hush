-- Header: two buttons in the header of a conversation: "Invite" (invite the player to your group) and "Get Hush" (a
-- friendly message that tells the other player about Hush, put in the input as a draft, never sent by itself).
local _, Hush = ...

local Compat = Hush.Compat

local Header = {}
Hush.Header = Header

Header.DEFAULT_INVITE = "Hey! I use Hush for my whispers: every conversation in one window, searchable, and it works with all my characters. "
    .. "You can find it in the CurseForge app (search \"Allemano Hush\") or at https://allemano.org/addons/hush"

-- The text for "Get Hush": the player's own wording from the settings, else the default.
function Header.InviteText()
    local custom = Hush.settings and Hush.settings.hushInviteText
    if type(custom) == "string" and strtrim(custom) ~= "" then return custom end
    return Header.DEFAULT_INVITE
end

-- Added after Mute, so they sit to its left: Invite | Get Hush | Mute | ... | X
Hush.API.AddHeaderButton({
    id = "gethush", text = "Get Hush",
    tooltip = "Puts a short message in the input that tells this player about Hush. You read it and press Send.",
    onClick = function() Hush.Input.PutDraft(Header.InviteText()) end,
    isShown = function(_, conv) return conv.kind == "whisper" or conv.kind == "bnet" end,
}, "Header")

Hush.API.AddHeaderButton({
    id = "invite", text = "Invite",
    tooltip = "Invite this player to your group.",
    onClick = function(_, conv)
        if conv.info and conv.info.online == false then
            Hush:Print(conv.display .. " is offline.")
            return
        end
        Compat.InviteToGroup(conv.target)
    end,
    isShown = function(_, conv) return conv.kind == "whisper" end,
}, "Header")
