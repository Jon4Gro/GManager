# **GManager (v1.5)**

GManager is an all-in-one Guild Management addon natively engineered for **World of Warcraft: Wrath of the Lich King (Patch 3.3.5a)**. Built on the classic frame API (`CreateFrame`, `GuildRosterInfo`, `SetWhoToUI`, `FauxScrollFrame`, `EasyMenu` context menus, etc.) it delivers high-volume guild ops without tainting the default UI.

Features include deep event logging, alt-character mapping, channel-bound macros, batch rate-limited promote/kick, smart auto-invite systems with level gating, a minimap button with rotation & distance controls, 0-minute infinite timers, **and a powerful account-wide Blacklist** for both Auto Guild and Auto Group Invites.

## **⚠️ Known Bug & The GManager Solution**

* **Blizzard GuildFrame Offline Bug**: With GManager loaded the stock `GuildRosterFrame` can get stuck defaulting to "Show Offline Members" after any sort click.  
* **GManager Roster Tab to the Rescue**: Our custom `ROSTER` view (powered by `collectRosterRows`, live `rosterPlayerSearch` / `rosterNoteSearch` / `rosterOfflineDaysSearch` filters, and `ROSTER_COLS` layout) completely replaces the need to fight the default frame. Right-click context menus (`showRosterContextMenu`) give instant whitelist, promote, demote, whisper and group invite actions.

## **What's New in v1.5**

* **BlacklistDetail Window**: The main Blacklist window height was reduced. The "Remove" button was moved into a new **BlacklistDetail** panel shown below the list:
  - Displays the selected player's name
  - Remove button on the right
  - Local notes editbox (200 char limit, multiline support)

* **Ban Member Right-Click Option** (Roster context menu):
  - Requires confirmation
  - Kicks the member **and** adds them to the blacklist
  - Automatically writes an officer note in the format: `OfficerName MMM DD YYYY: banned`

* **Auto Ban on Leaving** (Settings checkbox above Blacklist button):
  - Automatically adds players who leave the guild to the blacklist
  - Note format: `MMM DD YYYY: Quit Guild`

* **Share Blacklist to Officer Chat**:
  - New button above "Auto Ban on Leaving"
  - Shares all blacklisted members + their notes via in-game Officer chat
  - Addon listens on Officer chat and automatically **adds/updates** received entries (with notes)

* **Roster View Enhancement**:
  - Matching criteria counter (from Ranks view) now also shown below the right header in Roster view, reflecting current displayed members.

* **Various UI Polish**:
  - Blacklist and detail editboxes limited to 200 characters
  - Improved multiline support and sizing for Autoresponse + Local Notes
  - Height adjustments across Blacklist-related windows

## **What's New in v1.4**

* **Account-Wide Blacklist for Auto Invites**: A single blacklist (saved in `GManagerDB`) now protects **both** Auto Guild Invite and Auto Group Invite. Blacklisted players are silently blocked from triggering invites.

* **Blacklist Management Window**: New **Blacklist...** button in the bottom-right corner of the Settings tab opens a dedicated side window:
  - Docked to the **right side** of the main GManager window
  - Height matches the main window
  - Width set to main width − 30 (390px)
  - Add player names via input box (Enter or Add button supported)
  - Easy removal with **Rem** buttons next to each entry
  - Editable **Autoresponse** — a custom message sent to blacklisted players when they whisper a trigger phrase
  - Fully scrollable list (improved FauxScroll handling)

* **New Slash Commands**:
  - `/gm bladd <name>` — Quickly add a player to the blacklist
  - `/gm bl` (or `/gm blacklist`, `/gm blist`) — Print the current blacklist to chat

* **Toggle Behavior**: Pressing the Blacklist button again while the window is open will close it.

## **Core Features**

### **🛡️ Whitelisting**
Protected members (green `[W]` tag in roster rows) are skipped by every mass operation (`ProcessBatch`, mass kick, mass promote). Toggle via right-click context menu or the whitelist API in `Core.lua`.

### **🛑 Blacklist**
Account-wide list that blocks players from both Auto Guild Invite and Auto Group Invite. 
- Add/remove via the Settings → Blacklist... window (docked to the right)
- Optional autoresponse sent to blacklisted players
- Slash command support: `/gm bladd` and `/gm bl`
- Works even if auto-invite is enabled

### **🥾 Mass Kick List**
Filter the roster (name/note/offline-days), preview the list, then execute in safe configurable batches (`GManagerDB.batchSize`). Double confirmation + whitelist bypass. All kicks go through `GuildUninvite` with post-action `RequestRosterAfterAction` delay.

### **🎖️ Mass Promote List (Ranks Tab)**
Select a baseline rank in the Ranks view, set min-days-in-guild + max-offline filters, preview candidates (parsed from officer note date tags like `[Jun 09 2026]`), then batch promote. Respects whitelist. Dynamic `GuildControlGetRankName` / `GuildControlGetNumRanks` integration.

### **✉️ Auto Guild & Party Invites**
* **Guild Whisper Triggers**: Custom phrase (supports multiple words separated by `-`). When matched, silent `/who` level check → `minLvl` gate → invite or `replyLow`. Configurable `replyOn` / `replyOff` messages. Fully protected by the new Blacklist system.
* **Party / Group Auto-Invites**: Toggle via Settings. Minutes field supports **0 for infinite** (no auto-stop timer) or **Permanent** checkbox. Same trigger phrase support. Blocked by blacklist.
* **Rate & Safety**: `delayCall` scheduler, exact-name `/who` quoting, and focus guards on all EditBoxes.

### **📜 Event Log**
Up to 15 000 entries per guild. Types: `JOIN`, `LEAVE`, `PROMOTE`, `DEMOTE`, `NOTE`, `ONOTE`, `SEEN`, `LEVEL`. Full text search, type filters, line numbers. `fmtDateLong` + `fmtSince` helpers give human readable timestamps and "X days ago" strings. Color coded with `TYPE_COLOR` table.

### **🔗 Alts Mapping**
`SetAlt` / `GetMainOf` / `GetAltsOf` stored per-guild in `GManagerDB.guilds[key].alts`. Displayed in both Roster rows (`<M>` / `(alt)`) and the dedicated Alts tab + Member Detail panel (`Roster.lua`).

### **💬 Account-Wide Macros + Spam**
Save any text bound to a channel (1-9, GUILD, OFFICER, SAY, PARTY, RAID, YELL). Send instantly or add to rotation. `spamUpdater` `OnUpdate` ticker respects `spamInterval` (minutes) + optional **total time limit** (0 = infinite). Spam checkboxes per macro row with live `[SPAM]` tag.

## **Interface Tabs (6 total)**

All built with plain Wrath frame API. Major buttons/headers use classic `|cFFFFCC00` yellowish gold.

1. **Log Tab** – Search + type filter checkboxes + numbered lines + clear button. Right side filter panel.
2. **Roster Tab** – Show offline toggle, player/note search, offline-days threshold, group-alts checkbox, mass-kick button, ONote-empty button. Sortable columns. Rich right-click menu.
3. **Alts Tab** – Simple list of alt → main mappings with Set / Unset inputs.
4. **Macros Tab** – Channel buttons, message EditBox + Save, spam interval + total limit (0=inf) + enable checkbox. Per-row action buttons.
5. **Ranks Tab** – Baseline rank selector, min-days / max-offline filters, candidate preview, mass-promote button.
6. **Settings Tab** – 
   - Batch size, Open/Close with GuildFrame options
   - Minimap Button Controls (Show + Rotation/Distance)
   - **Auto Guild Invite** controls (phrase, replies, min level, reply low)
   - **Auto Group Invite** (phrase, minutes 0=inf, Permanent)
   - **Blacklist...** button (bottom-right) — opens the account-wide blacklist manager docked to the right of the main window

Access with `/gm` or `/gmanager`. The main frame (`GManagerMainFrame`) is movable, clamped, high-strata.

## **Slash Commands**

| Command                        | Function |
|--------------------------------|----------|
| `/gm`                          | Toggle main UI window |
| `/gm help`                     | Print command list to chat |
| `/gm setalt <alt> <main>`      | Tag alt relationship |
| `/gm unalt <name>`             | Remove alt tag |
| `/gm alts`                     | Dump current alt→main map to chat |
| `/gm clear`                    | Wipe current guild's event log |
| `/gm bladd <name>`             | Add player to the blacklist (Auto Guild + Group) |
| `/gm bl` (or `blacklist`/`blist`) | Print current blacklist to chat |

## **Technical Information**

* **Interface TOC**: 30300 (WotLK 3.3.5a native)
* **Current Version**: 1.5 (see `addon.version` in `Core.lua`)
* **SavedVariables**: `GManagerDB` (account) – guilds, macros, autoInvite config, batchSize, spamTotalMinutes, minimap settings, **blacklist**, **blacklistReply**
* **SavedVariablesPerCharacter**: `GManagerCharDB` – open/close with guild, massPromote history
* **Files**: `Core.lua`, `UI.lua`, `Roster.lua`
* **Key Patterns Used**: `scheduleDiff`, `ProcessBatch`, `containsTriggerWord`, dynamic FauxScroll handling, classic frame positioning

## **⚖️ Use at Your Own Discretion**

GManager gives you serious power. The new Blacklist is a powerful tool to protect your auto-invite systems. Everything is rate-limited and double-confirmed where appropriate, but **you** are responsible for the names you add to the blacklist and whitelist. Use responsibly on your realm.

---

*Refined for WotLK 3.3.5a – pure Lua, no external dependencies. v1.5 — BlacklistDetail, Ban Member, Auto Ban on Leave, Officer Chat share/listen sync.*