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
