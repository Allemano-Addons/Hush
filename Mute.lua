-- Mute: make a conversation quiet without blocking the person. A muted chat still arrives and is kept, but it plays no
-- sound, shows no popup or combat toast, sends no auto-reply and adds nothing to the unread badge. For a while ("Mute
-- for 10 minutes") or until you unmute. Not the game's /ignore. The data side is in Data.lua (Data.SetMute).
local _, Hush = ...

local Data, W = Hush.Data, Hush.Widgets

local Mute = {}
Hush.Mute = Mute

Mute.DURATIONS = {
    { label = "10 minutes", seconds = 600 },
    { label = "30 minutes", seconds = 1800 },
    { label = "1 hour", seconds = 3600 },
    { label = "8 hours", seconds = 28800 },
    { label = "Until I unmute", seconds = true },
}

-- "9 min", "1 h 5 min", "20 s".
function Mute.Format(seconds)
    seconds = math.max(0, math.floor(seconds or 0))
    if seconds < 60 then return seconds .. " s" end
    local minutes = math.floor((seconds + 30) / 60)
    if minutes < 60 then return minutes .. " min" end
    local hours, rest = math.floor(minutes / 60), minutes % 60
    return rest == 0 and (hours .. " h") or (hours .. " h " .. rest .. " min")
end

-- What the chip in the header says for a muted conversation: "Muted 9 min" or "Muted".
function Mute.ChipText(conv)
    if not Data.IsMuted(conv) then return nil end
    local left = Data.MuteLeft(conv)
    return left and ("Muted " .. Mute.Format(left)) or "Muted"
end

-- The menu: the durations, and Unmute when it is muted now.
function Mute.Items(key)
    local conv = Data.Get(key)
    if not conv then return {} end
    local items = {}
    if Data.IsMuted(conv) then
        local left = Data.MuteLeft(conv)
        items[#items + 1] = {
            text = left and ("Unmute (" .. Mute.Format(left) .. " left)") or "Unmute",
            onClick = function() Data.SetMute(key, nil) end,
        }
        items[#items + 1] = { separator = true }
    end
    for _, d in ipairs(Mute.DURATIONS) do
        items[#items + 1] = { text = "Mute: " .. d.label, onClick = function() Data.SetMute(key, d.seconds) end }
    end
    return items
end

function Mute.Open(key)
    local items = Mute.Items(key)
    if #items > 0 then W.OpenMenu(items) end
end

-- Finds a conversation by what the player typed (case does not matter).
local function findByName(text)
    local lower = strlower(strtrim(text or ""))
    if lower == "" then return nil end
    for key, conv in pairs(Data.All()) do
        if (conv.kind == "whisper" or conv.kind == "bnet")
            and (strlower(conv.display or "") == lower or strlower(conv.target or "") == lower) then
            return key, conv
        end
    end
end

-- ---------------------------------------------------------------------------
-- Where it shows: the chat menu, the header (a button and a chip), and slash commands
-- ---------------------------------------------------------------------------

Hush.API.AddChatMenuItems(function(key, conv)
    if conv.kind ~= "whisper" and conv.kind ~= "bnet" then return nil end
    if Data.IsMuted(conv) then
        local left = Data.MuteLeft(conv)
        return { text = left and ("Unmute (" .. Mute.Format(left) .. " left)") or "Unmute", onClick = function() Data.SetMute(key, nil) end }
    end
    local sub = {}
    for _, d in ipairs(Mute.DURATIONS) do
        sub[#sub + 1] = { text = d.label, onClick = function() Data.SetMute(key, d.seconds) end }
    end
    return { text = "Mute", submenu = sub }
end)

-- The first button next to the "..." in the header (the buttons that follow are placed to its left).
Hush.API.AddHeaderButton({
    id = "mute", text = "Mute",
    tooltip = "Make this chat quiet: no sound, popup or badge. It is not blocked and nothing is lost.",
    onClick = function(key) Mute.Open(key) end,
    isShown = function(_, conv) return conv.kind == "whisper" or conv.kind == "bnet" end,
}, "Mute")

Hush.API.AddStatusChip(function(_, conv)
    local text = Mute.ChipText(conv)
    if text then return text, 0.62, 0.65, 0.70 end
end, "Mute")

-- The chip counts down, so the header is drawn again now and then while a timed mute is open.
local ticker = 0
local tickFrame = CreateFrame("Frame")
tickFrame:SetScript("OnUpdate", function(_, elapsed)
    ticker = ticker + elapsed
    if ticker < 15 then return end
    ticker = 0
    local key = Hush.List and Hush.List.selected
    local conv = key and Data.Get(key)
    if conv and type(conv.mute) == "number" and Hush.Main.IsShown() then Hush.API.RefreshHeader() end
end)

Hush:RegisterCallback("CONV_UPDATED", function(_, conv)
    local key = Hush.List and Hush.List.selected
    if key and Data.Get(key) == conv then Hush.API.RefreshHeader() end
end, "Mute")

Hush:AddSlashCommand("mute", function(arg)
    local name, minutes = string.match(arg or "", "^(.-)%s+(%d+)$")
    name = name or arg
    local key, conv = findByName(name)
    if not key then
        Hush:Print("Usage: /hush mute <name> [minutes]. No chat with that name.")
        return
    end
    if minutes then
        Data.SetMute(key, tonumber(minutes) * 60)
        Hush:Print(conv.display .. " is muted for " .. minutes .. " min.")
    else
        Data.SetMute(key, true)
        Hush:Print(conv.display .. " is muted until you unmute.")
    end
end, "mute a chat without blocking it: /hush mute <name> [minutes]")

Hush:AddSlashCommand("unmute", function(arg)
    local key, conv = findByName(arg)
    if not key then
        Hush:Print("Usage: /hush unmute <name>.")
        return
    end
    Data.SetMute(key, nil)
    Hush:Print(conv.display .. " is not muted.")
end, "unmute a chat: /hush unmute <name>")

-- Timed mutes that ended while the game was closed are cleared at login, the rest get their timer.
Hush:RegisterCallback("READY", function()
    Data.ExpireMutes()
    for _, conv in pairs(Data.All()) do
        local left = Data.MuteLeft(conv)
        if left then Hush.Compat.After(left + 1, Data.ExpireMutes) end
    end
end, "Mute")
