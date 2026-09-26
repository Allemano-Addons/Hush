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

_G.Hush = API
