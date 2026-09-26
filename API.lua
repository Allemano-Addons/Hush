-- API: the public entry point for modules (global "Hush"). See API.md.
local _, Hush = ...

local API = {}
Hush.API = API

API.apiVersion = 1

function API.GetVersion()
    return Hush.version
end

function API.IsReady()
    return Hush.ready == true
end

-- Listen to Hush events. owner is any unique value (e.g. your module name) used to unregister.
function API.RegisterCallback(event, fn, owner)
    assert(type(event) == "string", "Hush.RegisterCallback: event must be a string")
    assert(type(fn) == "function", "Hush.RegisterCallback: fn must be a function")
    Hush:RegisterCallback(event, fn, owner)
end

function API.UnregisterCallback(event, owner)
    Hush:UnregisterCallback(event, owner)
end

-- Open/close the window (key binding HUSH_TOGGLE).
function API.Toggle()
    Hush.Main.Toggle()
end

-- Open a conversation by key and optionally focus the input.
function API.Open(key, focus)
    Hush.Main.Show()
    if key and Hush.Data.Get(key) then
        Hush.List.Select(key)
        -- Next frame, so the key that triggered a binding is not typed into the field.
        if focus then Hush.Compat.After(0, Hush.Input.Focus) end
    end
end

-- Open Hush on the latest incoming whisper with focus in the input (key binding HUSH_REPLY).
function API.ReplyLast()
    local key = Hush.char and Hush.char.lastWhisper
    if key and Hush.Data.Get(key) then
        API.Open(key, true)
    else
        Hush.Main.Show()
        Hush:Print("No whisper to reply to yet.")
    end
end

-- Key binding labels.
BINDING_HEADER_HUSH = "Hush"
BINDING_NAME_HUSH_TOGGLE = "Open / close Hush"
BINDING_NAME_HUSH_REPLY = "Reply to last whisper"

_G.Hush = API
