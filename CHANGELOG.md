# Changelog

## 0.1.0 (in progress)

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
