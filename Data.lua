-- Data: conversations, messages, unread counts, categories and routing.
-- Everything is stored per character in Hush.char (see Core.lua).
local _, Hush = ...

local Data = {}
Hush.Data = Data

local MAX_MESSAGES = 200
local PREVIEW_LEN = 80

-- ---------------------------------------------------------------------------
-- Keys
-- ---------------------------------------------------------------------------

function Data.WhisperKey(name) return "W:" .. name end
function Data.BNetKey(tag) return "B:" .. tag end

function Data.Get(key)
    return Hush.char and Hush.char.convs[key]
end

function Data.All()
    return Hush.char and Hush.char.convs or {}
end

-- Which list tab a conversation belongs to: "whispers", "requests" or "groups".
function Data.TabOf(conv)
    if conv.kind == "group" then return "groups" end
    if conv.request then return "requests" end
    return "whispers"
end

-- ---------------------------------------------------------------------------
-- Routing: which category a new conversation lands in.
-- Rules are tried from highest priority; the first non-nil category id wins.
-- ---------------------------------------------------------------------------

local rules = {}

-- fn(conv, info) -> categoryId or nil
function Data.AddRoutingRule(fn, priority, owner)
    rules[#rules + 1] = { fn = fn, priority = priority or 0, owner = owner }
    sort(rules, function(a, b) return a.priority > b.priority end)
end

function Data.RemoveRoutingRules(owner)
    for i = #rules, 1, -1 do
        if rules[i].owner == owner then tremove(rules, i) end
    end
end

local function categoryExists(id)
    return id and Hush.char.categories.byId[id] ~= nil and id ~= "pinned"
end

function Data.Route(conv, info)
    for _, rule in ipairs(rules) do
        local ok, id = pcall(rule.fn, conv, info)
        if not ok then
            geterrorhandler()(id)
        elseif categoryExists(id) then
            return id
        end
    end
    return "other"
end

-- Built-in rule: guild members go to Guild.
Data.AddRoutingRule(function(conv)
    if conv.kind == "whisper" and Hush.Chat and Hush.Chat.IsGuildMember(conv.target) then
        return "guild"
    end
end, 0, "Hush")

-- ---------------------------------------------------------------------------
-- Conversations
-- ---------------------------------------------------------------------------

-- Returns the conversation, creating it if needed. fields: kind, target, display, info, request.
function Data.Ensure(key, fields)
    local convs = Hush.char.convs
    local conv = convs[key]
    if conv then return conv, false end

    conv = {
        kind = fields.kind or "whisper",
        target = fields.target,
        display = fields.display or fields.target or key,
        category = "other",
        pinned = false,
        request = fields.request or false,
        unread = 0,
        seq = 0,
        created = time(),
        last = time(),
        preview = "",
        info = {},
        msgs = {},
        mod = {},
    }
    if fields.info then Data.UpdateInfo(conv, fields.info, true) end
    convs[key] = conv
    conv.category = Data.Route(conv, fields.info)
    Hush:Fire("CONV_CREATED", key, conv)
    return conv, true
end

-- Merge known player info (class, level, guild, zone, online, status). Nil fields are kept.
function Data.UpdateInfo(conv, info, silent)
    if not info then return end
    local ci = conv.info
    local changed = false
    for k, v in pairs(info) do
        if v ~= nil and v ~= "" and ci[k] ~= v then
            ci[k] = v
            changed = true
        end
    end
    ci.seen = time()
    if changed and not silent then Hush:Fire("CONV_UPDATED", conv) end
end

local function preview(text)
    -- Strip color codes and hyperlinks down to their visible text.
    local p = text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", "")
    if #p > PREVIEW_LEN then
        local cut = PREVIEW_LEN - 3
        -- Don't split a multi-byte UTF-8 character (å, ä, ö...).
        while cut > 1 and p:byte(cut + 1) and p:byte(cut + 1) >= 0x80 and p:byte(cut + 1) < 0xC0 do cut = cut - 1 end
        p = p:sub(1, cut) .. "..."
    end
    return p
end

-- Is the player currently looking at this conversation? Set by the UI.
function Data.IsViewing(key)
    return Hush.IsViewing ~= nil and Hush.IsViewing(key) or false
end

-- msg: { d = "in"|"out"|"sys", m = text, s = sender, c = classFile, k = subkind }
function Data.AddMessage(key, msg)
    local conv = Data.Get(key)
    if not conv then return end

    conv.seq = conv.seq + 1
    msg.n = conv.seq
    msg.t = msg.t or time()
    local msgs = conv.msgs
    msgs[#msgs + 1] = msg
    while #msgs > MAX_MESSAGES do tremove(msgs, 1) end
    -- Keep the "New" marker on a message that still exists.
    if conv.firstUnread and conv.firstUnread < msgs[1].n then conv.firstUnread = msgs[1].n end

    if msg.d ~= "sys" then
        conv.last = msg.t
        conv.preview = (msg.d == "out" and "You: " or "") .. preview(msg.m)
    end

    if msg.d == "in" and not Data.IsViewing(key) then
        conv.unread = conv.unread + 1
        conv.firstUnread = conv.firstUnread or msg.n
        if Hush.Chat and Hush.Chat.inCombat then conv.combatUnread = (conv.combatUnread or 0) + 1 end
    elseif msg.d == "out" then
        -- Replying accepts a request and counts as reading.
        if conv.request then
            conv.request = false
            Hush:Fire("CONV_MOVED", key, "requests", conv.category)
        end
        Data.MarkRead(key)
    end

    Hush:Fire("MESSAGE_ADDED", key, msg, conv)
    if msg.d == "in" then Hush:Fire("UNREAD_CHANGED") end
end

function Data.MarkRead(key, silent)
    local conv = Data.Get(key)
    if not conv or (conv.unread == 0 and not conv.firstUnread) then return end
    conv.unread = 0
    conv.firstUnread = nil
    conv.combatUnread = nil
    if not silent then Hush:Fire("UNREAD_CHANGED") end
end

-- Move to a category. Also accepts a request.
function Data.Move(key, categoryId)
    local conv = Data.Get(key)
    if not conv or not categoryExists(categoryId) then return false end
    local from = conv.request and "requests" or conv.category
    conv.category = categoryId
    conv.request = false
    Hush:Fire("CONV_MOVED", key, from, categoryId)
    return true
end

function Data.SetPinned(key, pinned)
    local conv = Data.Get(key)
    if not conv then return end
    conv.pinned = pinned and true or false
    Hush:Fire("CONV_UPDATED", conv)
end

function Data.Delete(key)
    local conv = Data.Get(key)
    if not conv then return end
    Hush.char.convs[key] = nil
    Hush:Fire("CONV_DELETED", key)
    Hush:Fire("UNREAD_CHANGED")
end

-- Module data per conversation: Data.ModData(key, "Hush_Recruit") -> table (created on demand).
function Data.ModData(key, module)
    local conv = Data.Get(key)
    if not conv then return nil end
    conv.mod = conv.mod or {}
    conv.mod[module] = conv.mod[module] or {}
    return conv.mod[module]
end

-- ---------------------------------------------------------------------------
-- Splitting long messages (chat limit is 255 bytes)
-- ---------------------------------------------------------------------------

local LIMIT = 255

-- Byte spans of hyperlinks, which must never be split.
local function linkSpans(text)
    local spans = {}
    local pos = 1
    while true do
        local s, e = text:find("|c%x%x%x%x%x%x%x%x|H.-|h.-|h|r", pos)
        if not s then s, e = text:find("|H.-|h.-|h", pos) end
        if not s then break end
        spans[#spans + 1] = { s, e }
        pos = e + 1
    end
    return spans
end

local function insideSpan(spans, i)
    for _, sp in ipairs(spans) do
        if i > sp[1] and i <= sp[2] then return sp end
    end
end

-- Returns a list of parts, each <= 255 bytes, split at spaces where possible.
function Data.SplitMessage(text)
    text = strtrim(text or "")
    local parts = {}
    while #text > LIMIT do
        local spans = linkSpans(text)
        local cut
        -- Last space within the limit that is not inside a link.
        for i = LIMIT + 1, 2, -1 do
            if text:sub(i, i) == " " and not insideSpan(spans, i) then
                cut = i
                break
            end
        end
        local nextStart
        if cut then
            nextStart = cut + 1
            cut = cut - 1
        else
            -- No usable space: hard cut, but not inside a link or a UTF-8 character.
            cut = LIMIT
            local sp = insideSpan(spans, cut + 1)
            if sp and sp[1] > 1 then cut = sp[1] - 1 end
            while cut > 1 and text:byte(cut + 1) and text:byte(cut + 1) >= 0x80 and text:byte(cut + 1) < 0xC0 do
                cut = cut - 1
            end
            nextStart = cut + 1
        end
        parts[#parts + 1] = strtrim(text:sub(1, cut))
        text = strtrim(text:sub(nextStart))
    end
    if text ~= "" then parts[#parts + 1] = text end
    return parts
end

-- ---------------------------------------------------------------------------
-- Unread totals
-- ---------------------------------------------------------------------------

-- Returns total, { whispers = n, requests = n, groups = n }
function Data.UnreadTotals()
    local byTab = { whispers = 0, requests = 0, groups = 0 }
    local total = 0
    for _, conv in pairs(Data.All()) do
        if conv.unread > 0 then
            local tab = Data.TabOf(conv)
            byTab[tab] = byTab[tab] + conv.unread
            total = total + conv.unread
        end
    end
    return total, byTab
end
