# Hush

A modern whisper messenger for **WoW Forever** (Classic+ beta, interface 16001).
Pure Lua, no libraries.

## Install

1. Unzip so the folder is `World of Warcraft\_classic_beta_\Interface\AddOns\Hush` (the `.toc` file directly inside it).
2. Optional: install **Hush_Recruit** the same way for guild recruitment.
3. Restart the game (a full restart the first time, not only `/reload`).

## Using it

- `/hush` opens and closes the window. The small launcher button (top center, drag it anywhere) does the same.
- Incoming whispers show a **popup**: click the field to reply, click the name to open Hush. Never in combat.
- Whispers are hidden in the default chat outside combat (in combat they show there as usual); `/r` still works.
- Right-click a chat or a message for more (move, pin, invite, guild invite, save message, copy text).
- **Saved** tab: messages you saved, kept even if the chat is deleted.
- Character selector under the title: read your alts' chats, or search **All characters**.
- `/hush settings` for everything else: themes (incl. Blizzard Style), fonts, popup, sounds, quick replies, storage.
- Key bindings: Key Bindings > AddOns > Hush.

## Commands

| Command | |
|---|---|
| `/hush` | Open / close |
| `/hush settings` | Settings |
| `/hush filter` | Toggle hiding whispers in the default chat |
| `/hush launcher` | Show the launcher button again |
| `/hush reset` | Reset window position and size |
| `/hush mute <name> [minutes]` | Quiet a chat without blocking it (`/hush unmute <name>` undoes it) |
| `/hush report` | Copy diagnostics for a bug report (also Settings > General) |
| `/hush debug` | Diagnostics in the chat |

## Notes

- WoW Forever is in beta and its API can change. Report problems with a screenshot and the text from `/hush report`.
- Modules can extend Hush, see `API.md`.
- Fonts in `Media/Fonts` are Barlow (SIL Open Font License, `OFL.txt`).
