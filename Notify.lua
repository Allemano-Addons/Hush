-- Notify: combat behavior (hide/reopen window, "X whispers during combat" toast) and sound.
local _, Hush = ...

local Compat = Hush.Compat

local Notify = {}
Hush.Notify = Notify

-- ---------------------------------------------------------------------------
-- Sound
-- ---------------------------------------------------------------------------

-- SOUNDKIT names with numeric fallbacks in case the table differs on this client.
Notify.SOUNDS = {
    { id = "ping",    label = "Ping",    kit = "MAP_PING",                       fallback = 3175 },
    { id = "whisper", label = "Whisper", kit = "TELL_MESSAGE",                   fallback = 3081 },
    { id = "click",   label = "Click",   kit = "IG_MAINMENU_OPTION_CHECKBOX_ON", fallback = 856 },
    { id = "bell",    label = "Bell",    kit = "READY_CHECK",                    fallback = 8960 },
}

function Notify.PlaySound(id)
    local sound = Notify.SOUNDS[1]
    for _, s in ipairs(Notify.SOUNDS) do
        if s.id == id then sound = s break end
    end
    local kit = (SOUNDKIT and SOUNDKIT[sound.kit]) or sound.fallback
    PlaySound(kit, "Master")
end

local lastSound = 0
local function maybePlaySound()
    local s = Hush.settings
    if not s.sound or Compat.InCombat() then return end
    local now = GetTime()
    if now - lastSound < 1.5 then return end -- several whispers at once make one sound
    lastSound = now
    Notify.PlaySound(s.soundKey)
end

-- ---------------------------------------------------------------------------
-- Combat
-- ---------------------------------------------------------------------------

local combat = { count = 0, names = {}, lastKey = nil, wasOpen = false }

local function summary()
    local names = combat.names
    local n = #names
    local text
    if n == 1 then
        text = names[1]
    elseif n == 2 then
        text = names[1] .. " and " .. names[2]
    else
        text = names[1] .. ", " .. names[2] .. " and " .. (n - 2) .. " more"
    end
    return "From " .. text .. "  ·  click to open"
end

Hush:RegisterEvent("PLAYER_REGEN_DISABLED", function()
    combat.count, combat.lastKey = 0, nil
    wipe(combat.names)
    combat.wasOpen = false
    if Hush.settings.hideInCombat and Hush.Main.IsShown() then
        combat.wasOpen = true
        Hush.Main.Hide()
    end
end)

Hush:RegisterEvent("PLAYER_REGEN_ENABLED", function()
    if combat.wasOpen then
        combat.wasOpen = false
        Hush.Main.Show()
    end
    if combat.count > 0 and Hush.settings.combatToast then
        local key = combat.lastKey
        local n = combat.count
        Hush.Toast.Show(n == 1 and "1 whisper during combat" or (n .. " whispers during combat"), summary(), function()
            Hush.Main.Show()
            if key and Hush.Data.Get(key) then Hush.List.Select(key) end
        end)
    end
    combat.count = 0
end)

Hush:RegisterCallback("MESSAGE_ADDED", function(_, key, msg, conv)
    if msg.d ~= "in" or conv.kind == "group" then return end
    if Compat.InCombat() then
        combat.count = combat.count + 1
        combat.lastKey = key
        local seen = false
        for _, name in ipairs(combat.names) do if name == conv.display then seen = true break end end
        if not seen then combat.names[#combat.names + 1] = conv.display end
    else
        maybePlaySound()
    end
end, "Notify")

-- ---------------------------------------------------------------------------
-- Test commands
-- ---------------------------------------------------------------------------

Hush:AddSlashCommand("sound", function(arg)
    local id = arg ~= "" and strlower(arg) or Hush.settings.soundKey
    local known = false
    for _, s in ipairs(Notify.SOUNDS) do if s.id == id then known = true end end
    if not known then
        Hush:Print("Sounds: ping, whisper, click, bell")
        return
    end
    Hush.settings.soundKey = id
    Notify.PlaySound(id)
    Hush:Print("Whisper sound:", id)
end, "choose and play the whisper sound: /hush sound <ping|whisper|click|bell>")

Hush:AddSlashCommand("toasttest", function()
    combat.names = { "Sigrid", "Brynja", "Östen", "Ivar" }
    Hush.Toast.Show("4 whispers during combat", summary(), function() Hush.Main.Show() end)
end, "show the combat toast")
