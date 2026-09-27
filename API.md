# Hush module API

Modules are separate addons that load after Hush:

```
## Interface: 16001
## Title: Hush Recruit
## Dependencies: Hush
## SavedVariables: HushRecruitDB   (optional, your own data)
```

Everything goes through the global `Hush` table. Internal files are not part of the contract.
`Hush.apiVersion` is `1`; it is raised on breaking changes.

Call anything at file load. Categories added before saved data is loaded are created at `READY`.
Use the `READY` event for work that needs conversations.

## General

| Function | Description |
|---|---|
| `Hush.GetVersion()` | Hush version string. |
| `Hush.IsReady()` | `true` once saved data is loaded (after `PLAYER_LOGIN`). |
| `Hush.RegisterCallback(event, fn, owner)` | Listen to a Hush event, `fn(event, ...)`. A failing listener never breaks others. |
| `Hush.UnregisterCallback(event, owner)` | Remove your listeners for `event`. |
| `Hush.Theme` | Colors and sizes: `Hush.Theme:Color("text")`, `Hush.Theme:Accent()` → r, g, b. |
| `Hush.Widgets` | Flat widgets used by Hush (`Button`, `EditBox`, `Toggle`, `Border`, `OpenMenu`, `Dialog`...). |

## Window

| Function | Description |
|---|---|
| `Hush.Toggle()` | Open/close the window. |
| `Hush.Open(key, focus)` | Open the window on a conversation; `focus` puts the cursor in the input. |
| `Hush.ReplyLast()` | Open the latest incoming whisper with focus. |
| `Hush.GetOpenConversation()` | Key of the conversation shown, or `nil`. |

## Conversations

Other characters (alts) use read-only keys `@<Name-Realm>|<key>` (e.g. `@Kogosh-Beta|W:Sigrid`); `Hush.GetConversation` reads them, while changes (move, pin, module data) are ignored for them.

Keys: `W:<name>` whisper (name via `Ambiguate(name, "none")`), `B:<BattleTag>` Battle.net,
`G:party:<time>` / `G:raid:<time>` group chat.

| Function | Description |
|---|---|
| `Hush.GetConversation(key)` | The conversation table. **Read-only** – change it with the functions below. |
| `Hush.Conversations()` | Iterator: `for key, conv in Hush.Conversations() do`. |
| `Hush.WhisperKey(name)` | Key for a character name (does not create the conversation). |
| `Hush.MoveConversation(key, categoryId)` | Move (also unpins and accepts a request). |
| `Hush.SetPinned(key, pinned)` / `Hush.MarkRead(key)` | |
| `Hush.SendMessage(key, text)` | Send; split at 255 characters like the input. |
| `Hush.AddRetentionGuard(fn, owner)` | `fn(key, conv) → true` protects a conversation from Settings → Storage cleanup (e.g. active candidates). |
| `Hush.SplitMessage(text)` | Split text into parts of max 255 bytes (word boundaries, links and UTF-8 kept intact). |
| `Hush.GetModuleData(key, module)` | Your saved table on that conversation (created on demand). |
| `Hush.SetModuleData(key, module, field, value)` | Set one field and refresh the UI. |
| `Hush.NotifyChanged(key)` | Refresh list/header after changing module data yourself. |

Conversation fields you may read:

```lua
conv = {
  kind = "whisper" | "bnet" | "group",
  target = "Name-Realm" | "BattleTag#1234",
  display = "Name",
  category = "other", pinned = false, request = false,
  unread = 0, last = time, preview = "...", created = time,
  guid = "Player-...",                       -- whispers, when known
  info = { class = "MAGE", level, guild, zone, online, status, seen },
  msgs = { { n, t, d = "in"|"out"|"sys", m = text, s = sender, c = class, k = kind }, ... }, -- max 200
  mod = { [module] = { ... } },             -- via Get/SetModuleData
}
```

## Categories and routing

| Function | Description |
|---|---|
| `Hush.AddCategory(id, name, owner)` | Add a category once (e.g. `"recruit_trial"`, `"Trials"`). Returns the id. |
| `Hush.GetCategories()` | `{ order = { ids }, byId = { [id] = { name, collapsed, owner } } }`. |
| `Hush.AddRoutingRule(fn, priority, owner)` | `fn(conv, info) → categoryId or nil` for **new** conversations. Higher priority first; the guild rule is `0`. |
| `Hush.RemoveRoutingRules(owner)` | |

Built-in ids: `pinned` (virtual), `guild`, `recruits`, `other`.

## Header

| Function | Description |
|---|---|
| `Hush.AddStatusChip(fn, owner)` | `fn(key, conv) → text [, r, g, b]` or `nil`. The first provider with text wins; default color is the accent. |
| `Hush.AddHeaderButton(def, owner)` | `def = { id, text, tooltip, onClick = fn(key, conv), isShown = fn(key, conv) }`. For protected actions (guild invite) use a chat menu item with `macro` instead. |
| `Hush.AddHeaderInfo(fn, owner)` | `fn(key, conv) → text` shown on an extra line under the info line (thin accent bar, e.g. a note). |
| `Hush.RefreshHeader()` | Re-run chips and `isShown` for the open conversation. |

## Context menu and settings

| Function | Description |
|---|---|
| `Hush.AddChatMenuItems(fn)` | `fn(key, conv) → item or { items }` added to the chat right-click menu. `item = { text, onClick, macro = "/slash command", disabled, danger, checked, submenu = { items }, separator = true }` – `macro` runs a protected action through a secure button (not in combat) |
| `Hush.AddSettingsPage(def)` | `def = { id, label, build = function(page) end }`, a page in the settings menu. |
| `Hush.OpenSettings(id)` | Open the settings, optionally on a page. |
| `Hush.AddTitleButton(def)` | Icon button in the title row. `def = { icon = "person" / "megaphone" / "plus" / "settings" / "more", glyph, tooltip, onClick }` |
| `Hush.AddLauncherMenuItems(fn)` | `fn() → item or { items }` added to the launcher right-click menu. |

## Guild and group

| Function | Description |
|---|---|
| `Hush.IsGuildMember(name)` | From the cached guild roster. |
| `Hush.CanGuildInvite()` / `Hush.GuildInvite(name)` | Guild invites are **protected** on WoW Forever: calling `GuildInvite` from addon code is blocked. Use a chat menu item with `macro = "/ginvite " .. name` instead (Hush already has "Guild invite" in the chat menu). |
| `Hush.InviteToGroup(name)` | |
| `Hush.ShowDialog(opts)` | Confirm or text prompt inside the Hush window. `opts = { title, text, input, okText, danger, onOk = fn(value), maxLetters (default 40), allowEmpty }` |

Page builder (`page` in `build`), rows are stacked top to bottom:

```lua
page:Header("Section")
page:Text("A paragraph.")
page:Toggle(label, desc, getter, setter)
page:Segment(label, desc, { { value = "a", label = "A" }, ... }, getter, setter)
page:Slider(label, desc, min, max, step, formatFn, getter, setter)
page:Button(label, desc, buttonText, style, onClick)      -- style: "default" | "accent" | "danger"
page:Custom(height, function(container) ... return refreshFn end)
```

Getters are called every time the page is shown.

## Events

| Event | Arguments |
|---|---|
| `READY` | – saved data loaded, UI can be built |
| `CONV_CREATED` | `key, conv` |
| `CONV_UPDATED` | `conv` (player info, pin, module data) |
| `CONV_MOVED` | `key, from, to` (`from` may be `"requests"`) |
| `CONV_DELETED` | `key` |
| `CONV_RENAMED` | `oldKey, newKey` – same player, the server's spelling (or merged duplicates) |
| `SAVED_CHANGED` | `convKey` – a message was saved or removed |
| `VIEW_CHANGED` | `view` – `"current"`, `"all"` or a character key (alt) |
| `CHARACTERS_CHANGED` | – a character was forgotten |
| `MESSAGE_CONTEXT` | `key, msg` – right-click on a message in the conversation view |
| `CONV_OPENED` | `key, conv, firstUnread` – shown in the window |
| `MESSAGE_ADDED` | `key, msg, conv` |
| `UNREAD_CHANGED` | – |
| `CATEGORIES_CHANGED` | – |
| `SETTINGS_CHANGED` | `key, value` |
| `WINDOW_SHOWN` / `WINDOW_HIDDEN` | – |
| `TAB_CHANGED` | `tab` (`"whispers"`, `"groups"`, `"requests"`) |
| `SEARCH_CHANGED` | `text` |

## Example

```lua
local M = "Hush_Recruit"
Hush.AddCategory("recruit_trial", "Trials", M)

Hush.AddStatusChip(function(key)
    local d = Hush.GetModuleData(key, M)
    if d and d.status == "trial" then return "Trial" end
end, M)

Hush.AddChatMenuItems(function(key, conv)
    if conv.kind ~= "whisper" then return end
    return { text = "Mark as trial", onClick = function()
        Hush.SetModuleData(key, M, "status", "trial")
        Hush.MoveConversation(key, "recruit_trial")
    end }
end)
```
