-- Data: conversations, messages, unread counts, categories and routing.
-- Everything is stored per character in Hush.char (see Core.lua).
local _, Hush = ...

local Data = {}
Hush.Data = Data

-- Messages kept per conversation (Settings → Storage).
local function maxMessages()
    return (Hush.settings and Hush.settings.maxMessages) or 200
end
local PREVIEW_LEN = 80

-- ---------------------------------------------------------------------------
-- Keys
-- ---------------------------------------------------------------------------

function Data.WhisperKey(name) return "W:" .. name end
function Data.BNetKey(tag) return "B:" .. tag end

function Data.Get(key)
    if not Hush.char then return nil end
    -- Saved-message sources ("S|...") look like conversations to the UI.
    if Hush.Saved and Hush.Saved.IsSavedKey(key) then return Hush.Saved.Get(key) end
    return Hush.char.convs[key]
end

function Data.All()
    return Hush.char and Hush.char.convs or {}
end

-- Which list tab a conversation belongs to: "whispers", "requests" or "groups".
function Data.TabOf(conv)
    if conv.kind == "saved" then return "saved" end
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

Data.Preview = preview

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
    while #msgs > maxMessages() do tremove(msgs, 1) end
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

-- ---------------------------------------------------------------------------
-- Name casing: the server delivers whispers regardless of letter case, so a name
-- typed as "whissel ljud" and the server's "Whissel Ljud" are the same player.
-- The server's spelling wins; conversations that only differ in case are merged.
-- ---------------------------------------------------------------------------

-- Other whisper conversations whose name equals `name` ignoring case.
function Data.CaseVariants(name, exceptKey)
    local lname, found = strlower(name), {}
    for key, conv in pairs(Data.All()) do
        if key ~= exceptKey and conv.kind == "whisper" and conv.target and strlower(conv.target) == lname then
            found[#found + 1] = key
        end
    end
    return found
end

local function mergeInto(dst, src)
    for _, m in ipairs(src.msgs) do dst.msgs[#dst.msgs + 1] = m end
    sort(dst.msgs, function(a, b)
        if a.t == b.t then return (a.n or 0) < (b.n or 0) end
        return a.t < b.t
    end)
    while #dst.msgs > maxMessages() do tremove(dst.msgs, 1) end
    for i, m in ipairs(dst.msgs) do m.n = i end
    dst.seq = #dst.msgs
    dst.unread = dst.unread + src.unread
    dst.firstUnread = dst.unread > 0 and dst.msgs[max(1, #dst.msgs - dst.unread + 1)].n or nil
    if src.last > dst.last then dst.last, dst.preview = src.last, src.preview end
    dst.created = min(dst.created or src.created, src.created or dst.created)
    dst.pinned = dst.pinned or src.pinned
    dst.request = dst.request and src.request
    if dst.category == "other" and src.category ~= "other" then dst.category = src.category end
    dst.guid = dst.guid or src.guid
    for k, v in pairs(src.info or {}) do if dst.info[k] == nil then dst.info[k] = v end end
    for mod, t in pairs(src.mod or {}) do
        local mine = dst.mod[mod]
        if not mine or next(mine) == nil then
            dst.mod[mod] = t
        else
            for k, v in pairs(t) do if mine[k] == nil then mine[k] = v end end
        end
    end
end

-- Move a conversation to newKey (merging if it exists) and use the server's spelling.
function Data.Rekey(oldKey, newKey, name)
    local convs = Hush.char.convs
    local src = convs[oldKey]
    if not src or oldKey == newKey then return end
    local dst = convs[newKey]
    if dst then
        mergeInto(dst, src)
    else
        convs[newKey] = src
        src.target, src.display = name, name
    end
    convs[oldKey] = nil
    if Hush.char.lastWhisper == oldKey then Hush.char.lastWhisper = newKey end
    Hush:Fire("CONV_RENAMED", oldKey, newKey)
    Hush:Fire("UNREAD_CHANGED")
end

-- Merge existing case duplicates (from before this fix). Keeps the one with most messages.
function Data.MergeCaseDuplicates()
    local groups = {}
    for key, conv in pairs(Data.All()) do
        if conv.kind == "whisper" and conv.target then
            local l = strlower(conv.target)
            groups[l] = groups[l] or {}
            tinsert(groups[l], key)
        end
    end
    for _, keys in pairs(groups) do
        if #keys > 1 then
            sort(keys, function(a, b)
                local ca, cb = Data.Get(a), Data.Get(b)
                if #ca.msgs ~= #cb.msgs then return #ca.msgs > #cb.msgs end
                return ca.last > cb.last
            end)
            local keep = keys[1]
            for i = 2, #keys do Data.Rekey(keys[i], keep, Data.Get(keep).target) end
        end
    end
end

-- ---------------------------------------------------------------------------
-- Storage: retention and cleanup (runs once at login, or from the settings)
-- ---------------------------------------------------------------------------

-- fn(key, conv) -> true keeps the conversation (e.g. active recruit candidates).
local guards = {}
function Data.AddRetentionGuard(fn, owner)
    guards[#guards + 1] = { fn = fn, owner = owner }
end

local function guarded(key, conv)
    for _, g in ipairs(guards) do
        local ok, keep = pcall(g.fn, key, conv)
        if not ok then geterrorhandler()(keep) elseif keep then return true end
    end
    return false
end

-- Applies the storage settings. With dryRun nothing changes; returns
-- chatsRemoved, messagesTrimmed.
function Data.Cleanup(dryRun)
    local s = Hush.settings
    local now, limit = time(), maxMessages()
    local remove, trimmed = {}, 0
    for key, conv in pairs(Data.All()) do
        local days = conv.kind == "group" and s.groupRetentionDays or s.whisperRetentionDays
        local old = days and days > 0 and (now - (conv.last or 0)) > days * 86400
        local active = conv.kind == "group" and Hush.Groups and Hush.Groups.IsActive(conv)
        if old and not conv.pinned and conv.unread == 0 and not active and not guarded(key, conv) then
            remove[#remove + 1] = key
        elseif #conv.msgs > limit then
            trimmed = trimmed + (#conv.msgs - limit)
            if not dryRun then
                -- Drop the oldest in one pass.
                local keep = {}
                for i = #conv.msgs - limit + 1, #conv.msgs do keep[#keep + 1] = conv.msgs[i] end
                conv.msgs = keep
                if conv.firstUnread and conv.firstUnread < keep[1].n then conv.firstUnread = keep[1].n end
            end
        end
    end
    if not dryRun then
        for _, key in ipairs(remove) do Data.Delete(key) end
    end
    return #remove, trimmed
end

-- Numbers for Settings → Storage. Size is an estimate of the saved file.
function Data.Stats()
    local chats, msgs = 0, 0
    for _, conv in pairs(Data.All()) do
        chats = chats + 1
        msgs = msgs + #conv.msgs
    end
    local saved = Hush.Saved and Hush.Saved.Count() or 0
    return chats, msgs, saved, (msgs + saved) * 270 + chats * 600
end

-- Deletes every conversation of this character. Categories and settings are kept.
function Data.ClearAll()
    local keys = {}
    for key in pairs(Data.All()) do keys[#keys + 1] = key end
    for _, key in ipairs(keys) do Data.Delete(key) end
    Hush.char.lastWhisper = nil
    if Hush.char.group then Hush.char.group.key = nil end
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
-- Categories
-- ---------------------------------------------------------------------------

function Data.Categories()
    return Hush.char.categories
end

-- Returns the new category id. owner marks module-created categories.
function Data.CreateCategory(name, owner, id)
    local cats = Hush.char.categories
    name = strtrim(name or "")
    if name == "" then return nil end
    if id and cats.byId[id] then return id end
    if not id then
        local n = 1
        repeat
            id = "c" .. n
            n = n + 1
        until not cats.byId[id]
    end
    cats.byId[id] = { name = name, collapsed = false, owner = owner }
    tinsert(cats.order, id)
    Hush:Fire("CATEGORIES_CHANGED")
    return id
end

function Data.RenameCategory(id, name)
    local cat = Hush.char.categories.byId[id]
    name = strtrim(name or "")
    if not cat or id == "pinned" or name == "" then return false end
    cat.name = name
    Hush:Fire("CATEGORIES_CHANGED")
    return true
end

-- Deleting moves its chats to Other.
function Data.DeleteCategory(id)
    local cats = Hush.char.categories
    local cat = cats.byId[id]
    if not cat or cat.locked then return false end
    for _, conv in pairs(Data.All()) do
        if conv.category == id then conv.category = "other" end
    end
    cats.byId[id] = nil
    for i = #cats.order, 1, -1 do
        if cats.order[i] == id then tremove(cats.order, i) end
    end
    Hush:Fire("CATEGORIES_CHANGED")
    return true
end

-- Move a category up (-1) or down (+1). Pinned always stays first.
function Data.MoveCategory(id, delta)
    local order = Hush.char.categories.order
    for i, cid in ipairs(order) do
        if cid == id then
            local j = i + delta
            if j < 1 or j > #order or order[j] == "pinned" or id == "pinned" then return false end
            order[i], order[j] = order[j], order[i]
            Hush:Fire("CATEGORIES_CHANGED")
            return true
        end
    end
    return false
end

function Data.SetCategoryCollapsed(id, collapsed)
    local cat = Hush.char.categories.byId[id]
    if not cat then return end
    cat.collapsed = collapsed and true or false
    Hush:Fire("CATEGORIES_CHANGED")
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
