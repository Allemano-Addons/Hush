# Hush

**A modern whisper messenger for WoW Forever.** Hush replaces the whisper tabs in your chat frame with a clean, separate messenger window, so private conversations stop getting lost between trade spam and combat text.

> **Alpha.** Hush is new and under active development. Report problems with a screenshot and the text from `/hush report`.

## What it does

### Whispers in their own window
Every conversation gets its own chat in the Hush window, with the unread ones marked. Open the window with `/hush` or the small launcher button at the top of the screen (drag it anywhere).

### A popup for new whispers
When someone whispers you, a small popup shows the message. Click the field to answer right there, or click the name to open the full conversation. The popup never appears in combat, and you can choose the sound.

*Example:* You are farming and a guildmate whispers a question. The popup appears, you type a quick answer in it, and you are back to farming without opening anything.

### Quiet default chat
Outside combat, whispers are hidden in the default chat frame so your general chat stays readable. In combat they show there as usual. `/r` still works, and you can turn the hiding off with `/hush filter`.

### Tools for every conversation
Right-click a chat or a single message for: move, pin, invite to group, guild invite, **save message** and copy text.

- **Mute without blocking:** make a chat quiet for 10 minutes, an hour, 8 hours or until you unmute it. It still arrives and is kept, but plays no sound, shows no popup and adds nothing to the unread badge. Not the game's /ignore.
- **Drafts survive a /reload:** what you typed but did not send is kept for every chat, and the list shows "Draft:" before it.
- **Header buttons:** Invite the player to your group, or tell them about Hush with one click (a short message is put in the input for you to read and send).
- **Saved tab:** messages you saved stay there even if you delete the conversation. Good for addresses, prices and instructions.
- **Quick replies** you can set up in the settings.
- **Alts:** the character selector under the title lets you read your other characters' conversations, or search **all characters** at once.

### Looks the way you want
Themes (including a Blizzard style), fonts, the whisper popup, sounds, quick replies and storage are all in `/hush settings`. Key bindings are under Key Bindings > AddOns > Hush.

## Works with the rest of Allemano Addons
Hush is the base for the other Hush modules, which add buttons and tabs to it:
- **Hush Feed:** sorted channel chat (LFG, Trade, Services) without the spam
- **Hush LFG:** groups and players from chat and the Group Finder in one list
- **Hush Recruit:** guild recruitment ads, apply link and candidate tracking

Other addons can hook in as well (a small API is documented in the source), for example CraftBoard whispers crafters through Hush.

## Commands
- `/hush` open or close, `/hush settings` settings
- `/hush filter` toggle hiding whispers in the default chat
- `/hush launcher` show the launcher button again, `/hush reset` reset window position and size
- `/hush mute <name> [minutes]` and `/hush unmute <name>` quiet a chat without blocking it
- `/hush report` copy diagnostics for a bug report

## Installing manually (WoW Forever)
Hush is made for WoW Forever (interface 16001). If the CurseForge app does not install it into the right folder, download the file from the **Files** tab and unzip it so that the folder is `World of Warcraft\_classic_beta_\Interface\AddOns\Hush`. Restart the game completely the first time.

Pure Lua, no libraries. The Barlow fonts are included under the SIL Open Font License. Source code and issues: https://github.com/Allemano-Addons/Hush
