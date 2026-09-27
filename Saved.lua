-- Saved: individual messages saved from conversations. They are independent copies, so
-- they survive deleting the conversation and the storage cleanup. One "source" per
-- conversation; a source looks like a conversation (kind = "saved") so the list and the
-- conversation view can show it. Keys: "S|" .. conversation key.
local _, Hush = ...

local Saved = {}
Hush.Saved = Saved

local PREFIX = "S|"

local function store() return Hush.char and Hush.char.saved or {} end

function Saved.KeyFor(convKey) return PREFIX .. convKey end
function Saved.IsSavedKey(key) return type(key) == "string" and key:sub(1, 2) == PREFIX end

-- The source table for a saved key ("S|W:Name"), or nil.
function Saved.Get(key)
    if not Saved.IsSavedKey(key) then return nil end
    return store()[key:sub(3)]
end

-- Iterate sources: for convKey, src in Saved.Sources() do ... end
function Saved.Sources() return pairs(store()) end

function Saved.Count()
    local n = 0
    for _, src in pairs(store()) do n = n + #src.msgs end
    return n
end

local function refresh(src)
    sort(src.msgs, function(a, b) return a.t < b.t end)
    for i, m in ipairs(src.msgs) do m.n = i end
    local last = src.msgs[#src.msgs]
    src.last = last and last.t or 0
    src.preview = last and Hush.Data.Preview(last.m) or ""
end

local function sameMessage(a, b)
    return a.t == b.t and a.m == b.m and a.d == b.d
end

function Saved.IsSaved(msg) return msg ~= nil and msg.saved == true end

-- Save a message from a conversation.
function Saved.Add(convKey, msg)
    if Hush.Data.IsForeign(convKey) then return false end -- other characters are read-only
    local conv = Hush.Data.Get(convKey)
    if not conv or not msg or msg.d == "sys" then return false end
    local all = Hush.char.saved
    local src = all[convKey]
    if not src then
        src = {
            kind = "saved", convKey = convKey, sourceKind = conv.kind,
            display = conv.display, target = conv.target,
            info = { class = conv.info and conv.info.class },
            msgs = {}, unread = 0, pinned = false, request = false, category = "saved",
        }
        all[convKey] = src
    end
    for _, m in ipairs(src.msgs) do
        if sameMessage(m, msg) then return false end
    end
    src.msgs[#src.msgs + 1] = { t = msg.t, d = msg.d, m = msg.m, s = msg.s, c = msg.c, k = msg.k, savedAt = time() }
    msg.saved = true
    refresh(src)
    Hush:Fire("SAVED_CHANGED", convKey)
    return true
end

-- Remove one saved message (a copy from src.msgs, or the original conversation message).
function Saved.Remove(convKey, msg)
    if Hush.Data.IsForeign(convKey) then return end
    local src = store()[convKey]
    if not src then return end
    for i = #src.msgs, 1, -1 do
        if sameMessage(src.msgs[i], msg) then tremove(src.msgs, i) end
    end
    -- Clear the marker on the original, if the conversation still exists.
    local conv = Hush.Data.Get(convKey)
    if conv then
        for _, m in ipairs(conv.msgs) do
            if sameMessage(m, msg) then m.saved = nil end
        end
    end
    if #src.msgs == 0 then
        store()[convKey] = nil
        Hush:Fire("CONV_DELETED", Saved.KeyFor(convKey))
    else
        refresh(src)
    end
    Hush:Fire("SAVED_CHANGED", convKey)
end

function Saved.RemoveAll(convKey)
    if Hush.Data.IsForeign(convKey) then return end
    local src = store()[convKey]
    if not src then return end
    local conv = Hush.Data.Get(convKey)
    if conv then
        for _, m in ipairs(conv.msgs) do m.saved = nil end
    end
    store()[convKey] = nil
    Hush:Fire("CONV_DELETED", Saved.KeyFor(convKey))
    Hush:Fire("SAVED_CHANGED", convKey)
end

-- Keep saved messages attached when a conversation changes key (server spelling).
Hush:RegisterCallback("CONV_RENAMED", function(_, oldKey, newKey)
    local all = store()
    local src = all[oldKey]
    if not src then return end
    local existing = all[newKey]
    if existing then
        for _, m in ipairs(src.msgs) do existing.msgs[#existing.msgs + 1] = m end
        refresh(existing)
    else
        all[newKey] = src
        src.convKey = newKey
        local conv = Hush.Data.Get(newKey)
        if conv then src.display, src.target = conv.display, conv.target end
    end
    all[oldKey] = nil
    Hush:Fire("SAVED_CHANGED", newKey)
end, "Saved")
