-- API: the public entry point for modules (global "Hush"). See API.md.
-- Modules are separate addons with "## Dependencies: Hush". Everything a module needs
-- goes through this table; internal files are not part of the contract.
local _, Hush = ...

local API = {}
Hush.API = API

API.apiVersion = 1

local function data() return Hush.Data end

-- ---------------------------------------------------------------------------
-- General
-- ---------------------------------------------------------------------------

function API.GetVersion()
    return Hush.version
end

-- true after PLAYER_LOGIN, once saved data is loaded. Use the READY event to wait for it.
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

-- Colors and widgets, so module UI matches Hush.
API.Theme = Hush.Theme
API.Widgets = Hush.Widgets

-- ---------------------------------------------------------------------------
-- Window
-- ---------------------------------------------------------------------------

-- Open/close the window (key binding HUSH_TOGGLE).
function API.Toggle()
    Hush.Main.Toggle()
end

-- Open a conversation by key and optionally focus the input.
function API.Open(key, focus)
    Hush.Main.Show()
    if key and data().Get(key) then
        Hush.List.Select(key)
        -- Next frame, so the key that triggered a binding is not typed into the field.
        if focus then Hush.Compat.After(0, Hush.Input.Focus) end
    end
end

-- Open Hush on the latest incoming whisper with focus in the input (key binding HUSH_REPLY).
function API.ReplyLast()
    local key = Hush.char and Hush.char.lastWhisper
    if key and data().Get(key) then
        API.Open(key, true)
    else
        Hush.Main.Show()
        Hush:Print("No whisper to reply to yet.")
    end
end

-- Key of the conversation shown in the window, or nil.
function API.GetOpenConversation()
    return Hush.Conversation and Hush.Conversation.Current()
end

-- ---------------------------------------------------------------------------
-- Conversations
-- ---------------------------------------------------------------------------

-- The conversation table (treat as read-only; use the functions below to change it).
function API.GetConversation(key)
    return data().Get(key)
end

-- Iterate all conversations of this character: for key, conv in Hush.Conversations() do ... end
function API.Conversations()
    return pairs(data().All())
end

-- Key for a whisper conversation with a character (not created).
function API.WhisperKey(name)
    local n = Hush.Compat.NormalizeName(name)
    return n and data().WhisperKey(n)
end

function API.MoveConversation(key, categoryId)
    local conv = data().Get(key)
    if conv and conv.pinned then data().SetPinned(key, false) end
    return data().Move(key, categoryId)
end

function API.SetPinned(key, pinned) data().SetPinned(key, pinned) end
function API.MarkRead(key) data().MarkRead(key) end

-- Send text to a conversation (split at 255 characters like the input field).
function API.SendMessage(key, text)
    local conv = data().Get(key)
    if not conv then return false end
    for _, part in ipairs(data().SplitMessage(text)) do
        if not Hush.Compat.Send(conv, part) then return false end
    end
    return true
end

-- Per-module data stored with the conversation (saved). Returns a table you may write to.
function API.GetModuleData(key, module)
    assert(type(module) == "string", "Hush.GetModuleData: module name required")
    return data().ModData(key, module)
end

-- Set one field and refresh the UI (list, header, chip).
function API.SetModuleData(key, module, field, value)
    local t = data().ModData(key, module)
    if not t then return false end
    t[field] = value
    API.NotifyChanged(key)
    return true
end

-- Tell Hush a conversation changed (e.g. after writing module data) so the UI refreshes.
function API.NotifyChanged(key)
    local conv = data().Get(key)
    if conv then Hush:Fire("CONV_UPDATED", conv) end
end

-- ---------------------------------------------------------------------------
-- Categories and routing
-- ---------------------------------------------------------------------------

-- Categories added before saved data is loaded are created at READY.
local pendingCategories = {}

-- Add a category (once; returns the existing one if the id is taken). Returns the id.
-- Safe to call while your module file loads.
function API.AddCategory(id, name, owner)
    assert(type(id) == "string" and type(name) == "string", "Hush.AddCategory: id and name required")
    if not Hush.char then
        pendingCategories[#pendingCategories + 1] = { id = id, name = name, owner = owner }
        return id
    end
    return data().CreateCategory(name, owner, id)
end

Hush:RegisterCallback("READY", function()
    for _, c in ipairs(pendingCategories) do data().CreateCategory(c.name, c.owner, c.id) end
    wipe(pendingCategories)
end, "API")

-- { order = { ids }, byId = { [id] = { name, collapsed, owner, builtin, locked } } }
function API.GetCategories()
    return data().Categories()
end

-- Decide the category of NEW conversations. fn(conv, info) -> categoryId or nil.
-- Higher priority runs first; the built-in guild rule has priority 0.
function API.AddRoutingRule(fn, priority, owner)
    assert(type(fn) == "function", "Hush.AddRoutingRule: fn required")
    data().AddRoutingRule(fn, priority, owner)
end

function API.RemoveRoutingRules(owner)
    data().RemoveRoutingRules(owner)
end

-- ---------------------------------------------------------------------------
-- Header: status chip and buttons
-- ---------------------------------------------------------------------------

-- fn(key, conv) -> text [, r, g, b] or nil. The first provider that returns text wins.
function API.AddStatusChip(fn, owner)
    assert(type(fn) == "function", "Hush.AddStatusChip: fn required")
    tinsert(Hush.Main.chipProviders, { fn = fn, owner = owner })
    API.RefreshHeader()
end

-- def = { id, text, tooltip, onClick = fn(key, conv), isShown = fn(key, conv) (optional) }
function API.AddHeaderButton(def, owner)
    assert(type(def) == "table" and def.text and def.onClick, "Hush.AddHeaderButton: text and onClick required")
    tinsert(Hush.Main.headerButtons, { def = def, owner = owner })
    API.RefreshHeader()
end

function API.RefreshHeader()
    if Hush.List and Hush.Main.UpdateHeader then Hush.Main.UpdateHeader(Hush.List.selected) end
end

-- ---------------------------------------------------------------------------
-- Context menu and settings
-- ---------------------------------------------------------------------------

-- fn(key, conv) -> one item or a list of items for the chat right-click menu.
-- item = { text, onClick, disabled, danger, checked, submenu = {items}, separator = true }
function API.AddChatMenuItems(fn)
    assert(type(fn) == "function", "Hush.AddChatMenuItems: fn required")
    tinsert(Hush.Menus.extraChatItems, fn)
end

-- def = { id, label, build = function(page) ... end }. See API.md for the page builder.
function API.AddSettingsPage(def)
    Hush.Settings.AddPage(def)
end

-- Confirm or text prompt inside the Hush window (above it when the window is closed).
-- opts = { title, text, input = default text or nil, okText, danger, onOk = fn(value) }
function API.ShowDialog(opts)
    Hush.Main.Show()
    return Hush.Widgets.Dialog(Hush.Main.frame, opts)
end

-- A small icon button in the title row, left of "New message".
-- def = { icon = "person" | "megaphone" | "plus" | "settings" | "more", glyph = fallback text, tooltip, onClick }
function API.AddTitleButton(def)
    assert(type(def) == "table" and def.onClick, "Hush.AddTitleButton: onClick required")
    tinsert(Hush.Main.titleButtons, { def = def })
    Hush.Main.LayoutTitleButtons()
end

-- fn() -> item or { items } added to the launcher right-click menu.
function API.AddLauncherMenuItems(fn)
    assert(type(fn) == "function", "Hush.AddLauncherMenuItems: fn required")
    tinsert(Hush.Launcher.extraItems, fn)
end

-- Guild and group helpers (WoW Forever differences are handled inside Hush).
function API.IsGuildMember(name) return Hush.Chat.IsGuildMember(Hush.Compat.NormalizeName(name)) end
function API.CanGuildInvite() return Hush.Compat.CanGuildInvite() end
function API.GuildInvite(name) Hush.Compat.GuildInvite(name) end
function API.InviteToGroup(name) Hush.Compat.InviteToGroup(name) end

-- Open the settings, optionally on a page id.
function API.OpenSettings(id)
    Hush.Settings.Open(id)
end

-- ---------------------------------------------------------------------------
-- Globals required by Bindings.xml
-- ---------------------------------------------------------------------------

BINDING_HEADER_HUSH = "Hush"
BINDING_NAME_HUSH_TOGGLE = "Open / close Hush"
BINDING_NAME_HUSH_REPLY = "Reply to last whisper"

_G.Hush = API
