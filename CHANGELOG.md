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
