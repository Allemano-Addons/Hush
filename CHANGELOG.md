# Changelog

## 0.1.0 – 2026-09-27

### Step 1 – Skeleton
- Addon skeleton: `Hush.toc` (Interface 16001), namespace, event dispatcher, callback system.
- `HushDB`: account-wide settings and quick replies, per-character conversations and categories, schema migrations.
- `Compat.lua` with feature detection, name normalization (`Ambiguate`), class colors, timers, screen size.
- `Theme.lua` with all colors, sizes, fonts (Barlow, OFL) and pixel-perfect helpers.
- Public module API stub (global `Hush`).
- `/hush`, `/hush debug`, `/hush version`.
- Fonts: WoW Forever refuses font files from new addon folders (even known-good files), so Hush uses `FRIZQT__` for now. Barlow stays in `Media/Fonts` and is picked up automatically if the client starts accepting it.

### Step 2 – Data and whisper capture
- `Data.lua`: conversations per character, max 200 messages (oldest dropped), unread counts with "New" marker, previews, categories, routing rules (guild members -> Guild, others -> Other), pin, move, delete, per-module data.
- `Chat.lua`: captures whispers, Battle.net whispers, AFK/DND replies and "player not found" as system lines.
- Unknown players land in Requests until you reply or move them. Guild members and friends skip Requests.
- Default-chat filter: hides whispers only outside combat, never GM whispers. Active once the conversation view exists (test with `/hush filtertest`).
- Test commands: `/hush dump [name]`, `/hush fake <name> <text>`, `/hush read <name>`, `/hush move <name> <category>`.

### Step 3 – Main window
- `Widgets.lua`: flat building blocks – pixel-perfect lines and borders (re-sized on UI scale change), text, icon buttons drawn from lines, text buttons (default/accent/ghost), edit box with placeholder, unread badge, own tooltip, frame pool. Accent color and text size update live.
- `UI/Main.lua`: 1000×620 window, movable (title row or header), resizable (bottom-right grip), position and size saved on whole pixels. Sidebar with HUSH title, new message + settings buttons, search field, Whispers/Groups/Requests tabs with accent underline and unread badges, "+ New category". Conversation pane with header, close button and empty state.
- ESC closes the window (keyboard is never captured in combat).
- `/hush reset` restores window position and size.

### Step 4 – Chat list
- `UI/List.lua`: virtualized chat list with pooled rows (only visible rows are drawn).
- Whispers tab grouped by category (Pinned, Guild, Recruits, Other + custom), collapsible headers with chevron, chat count and unread badge when collapsed. Collapsed state is saved.
- Groups and Requests tabs as flat lists, newest first.
- Chat row: initial in a square, name and initial in class color, online dot (green/orange/grey), time (24 h, "Yesterday", weekday or day/month), preview, unread badge. Selected row with accent bar.
- Search filters on name and message text; categories without matches are hidden and collapsed ones open while searching.
- Thin scrollbar (mouse wheel, draggable thumb – OnUpdate only while dragging).
- Selecting a chat marks it read and fills the header (name, class, level, guild, zone).
- Test commands: `/hush fakemany [n]`, `/hush clearfake`.

### Step 5 – Conversation view
- `UI/Conversation.lua`: compact message list (name + time on one line, text below, no bubbles), virtualized with pooled rows; wrapped text is measured once and cached outside SavedVariables.
- Messages from the same sender within 5 minutes are grouped. Day dividers ("TODAY", "YESTERDAY", date). Accent "NEW" line at the first unread message; the view opens there if it would be off screen.
- Initials in class-colored squares (portraits setting), 24 h timestamps (timestamps setting).
- System lines (AFK/DND/not found) as discreet rows with a colored dot.
- Item, spell and quest links are clickable (`SetItemRef`) and show tooltips on hover.
- Stays pinned to the bottom when new messages arrive; keeps position when scrolled up. Messages that arrive while the window is hidden are unread until you open it.
- Shared thin scrollbar widget for list and conversation.
- Test command: `/hush fakeconvo [name]`.

### Step 6 – Input
- `UI/Input.lua`: message field + accent Send button; Enter sends and keeps focus. Works for whispers and Battle.net whispers (group chats in step 8).
- Messages over 255 characters are split at word boundaries, never inside a link or a multi-byte character; a counter shows "N messages" while typing.
- Shift-clicked links (bags, spells, quests, links in Hush) are inserted into the Hush field while it has focus.
- Quick replies as buttons above the field (`{name}` = the other player's name): click fills the field, shift-click sends.
- "New message" (+): type a character name in the header to open or start a conversation (reuses an existing one regardless of letter case).
- Default-chat filter is now active: whispers are hidden there outside combat and `/r` still works. `/hush filter` toggles it (saved).
- Auto-open: an incoming whisper opens Hush on that conversation when the window is closed (on by default, schema 2 turns it on for existing installs). Never in combat, never for Requests, never steals keyboard focus, never switches away from an open conversation. Sent whispers can do the same (`autoOpenOut`, off by default).

### Step 7 – Combat and sound
- Entering combat hides the Hush window (setting `hideInCombat`); it reopens after combat if it was open.
- Whispers during combat stay unread in their conversations. After combat a toast shows "N whispers during combat" with the senders; left-click opens Hush on the latest one, right-click dismisses. `UI/Toast.lua` fades with animations and hides on a timer (no OnUpdate).
- Own whisper sound (never in combat, max one per 1.5 s): Ping (default), Whisper, Click, Bell. `/hush sound <name>` chooses and plays it.
- Test command: `/hush toasttest`.

### Step 8 – Groups
- `Groups.lua`: party and raid chat (`PARTY`, `PARTY_LEADER`, `RAID`, `RAID_LEADER`, `RAID_WARNING`) captured into the Groups tab. Never hidden in the default chat, no sound, no auto-open.
- One conversation per group/raid session, named with its start time ("Party · 26/09 20:14"). Created on the first message; a party converted to a raid starts a new one. The session survives `/reload`.
- Sender names in class color, "Leader" / "Raid warning" tags, raid warnings in orange. Party/raid colors in the list.
- Header shows "Active · N members" or "Ended <time>". Sending to an ended group is blocked with a notice.
- Test command: `/hush fakegroup`.

### Step 9 – Categories, drag and drop, context menus
- Categories: "+ New category", rename (all except Pinned), delete (chats move to Other; Pinned and Other can't be deleted), move up/down, collapse/expand.
- Drag and drop in the Whispers tab: a ghost row follows the cursor, the target category is outlined with a dashed accent border, the list auto-scrolls near its edges, and the drop is decided with `MouseIsOver()`. Dropping on Pinned pins; dropping a pinned chat elsewhere unpins it. OnUpdate runs only while dragging.
- Right-click menu on chats: Move to…, Pin/Unpin, Mark as read, Invite to group, Guild invite, Delete chat (with confirmation). Moving a request accepts it. Also on the new "…" button in the header.
- Right-click menu on category headers.
- Own flat widgets: context menu with submenus (no UIDropDownMenu, closes on click outside), in-window dialog for prompts and confirmations, dashed border.
- Fix: drag and drop and the chat menu did nothing on WoW Forever. The global `MouseIsOver()` is missing there, so a failed drop left Hush stuck in drag mode and blocked the chat menu. Now uses `frame:IsMouseOver()` via `Compat.MouseIsOver`, and drag state is reset before anything else on drop.

### Step 10 – Launcher and key bindings
- `UI/Launcher.lua`: small movable launcher (own, no LibDBIcon) with an accent speech-bubble icon and an unread badge (whispers + requests). Left-click toggles Hush, drag moves it (position saved on whole pixels), right-click menu: open/close, reply to last whisper, settings, lock position, hide. `/hush launcher` shows it again, `/hush launcher reset` moves it back.
- `Bindings.xml`: "Open / close Hush" and "Reply to last whisper" (opens Hush on the latest incoming whisper with focus in the input) under Key Bindings → AddOns → Hush.
- Public API: `Hush.Toggle()`, `Hush.Open(key, focus)`, `Hush.ReplyLast()`.
- Online status of guild members and friends updates immediately from "has come online" / "has gone offline" messages.
- "Invite to group" is disabled with "(offline)" when the player is known to be offline (WoW Forever answers such invites with a misleading "Cannot find player" naming another character with the same first name).

### Step 11 – Settings
- `UI/Settings.lua`: own settings panel in the Hush style (movable, position saved, ESC closes). Left menu with General, Appearance, Behavior, Notifications, Quick replies; "Unlock & move" and "Clear all chats" (with confirmation) at the bottom. Opens from the title button, the launcher menu or `/hush settings`.
- General: show/lock launcher, reset window position, about.
- Appearance: accent color swatches (Hush + class colors) and "Use my class color", background opacity, text size S/M/L, message style Compact/Bubbles, portraits, timestamps. Everything updates live.
- Behavior: hide whispers in the default chat, hide in combat, open on incoming/outgoing whisper, dim the window while moving (event-driven, not while typing or hovering).
- Notifications: sound on/off and choice with preview, combat summary with preview.
- Quick replies: 10 editable replies.
- "Unlock & move" shows a draggable sample of the combat notice; its position is saved.
- Bubbles message style: own messages right-aligned in an accent-tinted bubble, others left in a dark bubble, sized to the text.
- New widgets: toggle switch, segmented control, slider, color swatch. Page builder usable by modules (`Settings.AddPage`).
- Fix: tooltip background was never anchored, so tooltips had no background.

### Step 12 – Module API
- Public API (global `Hush`, `apiVersion = 1`), documented in `API.md`:
  - window: `Toggle`, `Open(key, focus)`, `ReplyLast`, `GetOpenConversation`, `ShowDialog`
  - conversations: `GetConversation`, `Conversations`, `WhisperKey`, `MoveConversation`, `SetPinned`, `MarkRead`, `SendMessage`
  - per-conversation module data: `GetModuleData`, `SetModuleData`, `NotifyChanged`
  - categories and routing: `AddCategory` (safe before login), `GetCategories`, `AddRoutingRule`, `RemoveRoutingRules`
  - header: `AddStatusChip` (the "Trial" chip), `AddHeaderButton`, `RefreshHeader`
  - `AddChatMenuItems`, `AddSettingsPage` (with the page builder), `OpenSettings`
  - events: `RegisterCallback` / `UnregisterCallback` for READY, CONV_*, MESSAGE_ADDED, UNREAD_CHANGED, CATEGORIES_CHANGED, SETTINGS_CHANGED, WINDOW_*, TAB_CHANGED, SEARCH_CHANGED
  - `Hush.Theme` and `Hush.Widgets` so modules match the Hush style
- Header renders module status chips and buttons.

### Wrap-up
- Dev mode: test and diagnostic commands (`dump`, `fake`, `fakemany`, `fakeconvo`, `fakegroup`, `clearfake`, `read`, `move`, `toasttest`, `api`) are hidden and blocked unless `/hush dev` is on (saved).
- Scrollbar dragging stops safely even if the mouse button is released outside the game.

## 0.1.1 – 2026-09-27
- Font choice in Settings → Appearance: separate "Text font" and "Heading font" dropdowns. Lists the game fonts plus fonts other addons share through LibSharedMedia (e.g. EllesmereUI's Expressway, Barlow Condensed, Poppins), but only those that actually load on this client; each name is previewed in its own font. Hush does not bundle LibSharedMedia.
- "Automatic" (default): game font for text, Barlow Condensed for headings when another addon provides it.
- New dropdown widget; menus can open below a button and preview fonts. Settings panel is taller (620 px).
- `/hush debug` shows the fonts in use.

## 0.1.2 – 2026-09-27
- Module API (additive, `apiVersion` stays 1): `Hush.AddTitleButton`, `Hush.AddLauncherMenuItems`, `Hush.IsGuildMember`, `Hush.CanGuildInvite`, `Hush.GuildInvite`, `Hush.InviteToGroup`. New icons: `person`, `megaphone`.

## 0.1.3 – 2026-09-27
- Module API: `Hush.SplitMessage(text)`.

## 0.1.4 – 2026-09-27
- Module API: `Hush.AddHeaderInfo(fn, owner)` adds text to the header info line.

## 0.1.5 – 2026-09-27
- Fix: a conversation started with "+" using different letter case ("whissel ljud") and the server's spelling ("Whissel Ljud") became two chats, so sent messages ended up in the other one. Names are now matched ignoring case: the server's spelling wins and case duplicates are merged (messages, category, pin and module data). Existing duplicates are merged at login.
- "+ New message" capitalizes every part of the name (surnames on WoW Forever).
- New event `CONV_RENAMED(oldKey, newKey)`.

## 0.1.6 – 2026-09-27
- Fix: "Guild invite" failed with "Interface action failed because of an addon" – guild invites are protected on WoW Forever. It now runs `/ginvite <name>` through an invisible secure button over the menu item (not available in combat, shown as "(not in combat)").
- Module API: menu items and header buttons accept `macro` for protected actions; header overlays are re-armed when the window opens and after combat.

## 0.1.7 – 2026-09-27
- Option Settings → Behavior → Chat list: **Categories** (grouped, as before) or **Recent** (Pinned on top, then all chats newest first regardless of category). Categories keep working in the background; in Recent, drag and drop only pins/unpins.

## 0.1.8 – 2026-09-27
- Fix: keys stopped working while Hush was open. The secure buttons for guild invites (0.1.6) were anchored to Hush frames, which made them protected and blocked Hush's keyboard handling. Secure buttons are now placed at their button's screen position instead of being anchored (hidden while a window is moved or resized, re-placed afterwards).
- Hush no longer captures the keyboard at all: ESC closes the window and the settings through the game's own `UISpecialFrames`. This needs the window names `HushFrame` and `HushSettingsFrame` (the only new globals).

## 0.1.9 – 2026-09-27
- Fix: secure buttons for header actions (Recruit's Invite) were placed before the header had its new layout, so clicking did nothing. Placement now waits one frame; a pending placement is cancelled if the button hides or moves.
- Unsent text is kept per conversation: switching chats saves the draft and restores it when you come back (for the session).

## 0.1.10 – 2026-09-27
- Removed secure `macro` support for header buttons: it did not work reliably. Protected actions such as guild invites stay in the chat right-click menu (where they work).

## 0.1.11 – 2026-09-27
- Header layout: the info line reads naturally – "Level 10 Priest · <Guild> · Zone" with the class name in its class color. Module info (e.g. a recruit note) gets its own line with a thin accent bar; the header only grows when there is one, and long notes are cut with "...".

## 0.1.12 – 2026-09-27
- Dialogs: `maxLetters` (default 40) and `allowEmpty` options, so notes can be longer and cleared.

## 0.1.13 – 2026-09-27
- Settings → Storage: messages per chat (50/100/200/500), delete group chats after N days (default 14), delete inactive whisper chats after N days (default off), usage stats and "Clean up now". Rules run once at login; pinned chats, unread chats, active groups and chats protected by modules are never removed.
- Module API: `Hush.AddRetentionGuard(fn, owner)`.

## 0.1.14 – 2026-09-27
- Saved messages: right-click a message → **Save message** (or Remove from saved). Saved messages are independent copies in the new **Saved** tab, one entry per person/group, shown like a conversation with dates. They survive deleting the conversation and the storage cleanup. Saved messages are marked with a thin accent bar and "Saved" next to the time.
- Right-click a message → **Copy text** (links as plain "[Name]", ready for Ctrl+C).
- Saved tab: right-click an entry for "Open conversation" and "Delete all saved".
- Events `SAVED_CHANGED`, `MESSAGE_CONTEXT`.

## 0.1.15 – 2026-09-27
- **Mini-popup** for incoming whispers (`UI/Popup.lua`): a 320 px window in a corner with the sender's name in class color, the last 1–3 messages (your replies as "You: …") and a reply field. Click the field to type (it never takes the keyboard by itself), Enter sends and marks the chat read; `/r` in the default chat also updates it. Click the name to open the conversation in Hush. Links are clickable.
- Fades after N seconds; hovering or typing keeps it open, with a short grace period after. Max 3 stacked from the corner (newest nearest), the rest wait in "+N more" (click opens Hush). The same person again updates their popup.
- No popups in combat (the combat summary covers it), for the conversation already open in Hush, or (by default) for group chat. Unknown players (Requests) do get popups by default.
- Settings → Behavior → **On incoming whisper**: Popup (default) / Open Hush / Nothing – replaces auto-open (schema 3 switches existing installs to Popup). Settings → Notifications → Popup: corner, duration (4–20 s), popups for Requests, popups for group chat, preview. "Unlock & move" also moves the popups.

## 0.1.16 – 2026-09-27
- Popup: if the newest line is a system reply (player not found, AFK, DND) it is shown in the popup in the same color as in Hush, so it is clear why a reply did not arrive.

## 0.1.17 – 2026-09-27
- **Alt characters**: a character selector under the title (only when more than one character has Hush data) with your character, **All characters** and each alt in class color.
- Other characters' chats are read-only (keys `@Name-Realm|...`): no input, no module buttons, only "Copy text" on messages. A bar offers **Reply as <you>**, which opens or starts the chat on the character you are playing; the alt's history stays where it is.
- **All characters** lists every chat from all characters, newest first, with a small character tag, and search covers them all – the Saved tab too.
- Storage cleanup now runs over all characters at login, and the usage numbers cover all of them. Settings → Storage → Other characters shows each alt's chats, messages and last login, with **Forget** (deletes that character's Hush history).
- Events `VIEW_CHANGED`, `CHARACTERS_CHANGED`.

## 0.1.18 – 2026-09-27
- Fix: characters sharing a first name (e.g. "Allemano Moo" and "Allemano Mu" – WoW Forever has surnames and first names are not unique) shared one storage bucket, so an alt showed the main's chats and the character selector never appeared. Characters are now stored by full name (first name + surname) and realm.
- The old shared bucket is not deleted or guessed: it shows as "<name> (older data)" in the selector (read-only), and Settings → Storage → Other characters has **Merge here** to move it into the character you are playing (chats, categories, saved messages, recruit data). A reminder is printed at login until it is merged or forgotten.
- Your own name uses the full name everywhere: your party/raid messages count as yours again, and "Reply as" shows the full name.
- Fix: merging conversations no longer errors when neither has a creation time.

## 0.1.19 – 2026-09-27
- **Themes** (Settings → Themes): Hush Original (default, unchanged), Midnight, Graphite, Horde and Alliance. A theme swaps the base palette and suggests an accent color; it is applied once at load, so switching asks for a UI reload and costs nothing while playing. Cards show a palette preview and which theme is active.
- `/hush texturetest` (temporary): checks that the classic Blizzard textures exist on this client, for the upcoming "Blizzard Style" theme.

## 0.1.20 – 2026-09-27
- Fix: "Reload" in the theme dialog did nothing (`ReloadUI()` is blocked for addons on WoW Forever). It now runs `/reload` through a secure button. Dialogs accept a `macro` option for this.

## 0.1.21 – 2026-09-27
- **Blizzard Style** theme: the main window, settings and the Recruit ad panel get the classic dark dialog background with the stone border drawn above the content; popups, notices, menus, tooltips and the launcher get the Blizzard tooltip frame; buttons become the red panel buttons with gold text; titles are gold and headings use Friz Quadrata. Everything is gated by `Theme:IsBlizzard()`, so the other themes are unchanged.
- Widgets: `W.SkinPanel(frame, opts)` and `W.SkinButton(button)` (do nothing unless Blizzard Style is active).

## 0.1.22 – 2026-09-27
- Fix: "Reload" after picking a theme still did nothing. Dialog buttons with a protected action now use the method EllesmereUI uses on WoW Forever: `InsecureActionButtonTemplate`, mouse-up only (`useOnKeyDown = false`), so the dialog closing on the press can no longer swallow the action.
- Visible texts use ">" instead of "→" (Friz Quadrata has no arrow glyph).
- Removed the temporary `/hush texturetest`.

## 0.1.23 – 2026-09-27
- Fix: the theme "Reload" button still did nothing. Like EllesmereUI, the /reload button is now an `InsecureActionButtonTemplate` *inside* the dialog button (it moves and raises with it); before it floated above it, and the settings window raised itself over it on the press.
