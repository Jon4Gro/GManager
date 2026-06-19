# **GManager (v1.3.2)**

GManager is an all-in-one Guild Management addon natively engineered for **World of Warcraft: Wrath of the Lich King (Patch 3.3.5a)**. Built on the classic frame API (`CreateFrame`, `GuildRosterInfo`, `SetWhoToUI`, `FauxScrollFrame`, `EasyMenu` context menus, etc.) it delivers high-volume guild ops without tainting the default UI. Features include deep event logging, alt-character mapping, channel-bound macros, batch rate-limited promote/kick, smart auto-invite systems with level gating, a minimap button with rotation & distance controls, and 0-minute infinite timers for group invites (matching Macro Spam behavior).

## **⚠️ Known Bug & The GManager Solution**

* **Blizzard GuildFrame Offline Bug**: With GManager loaded the stock `GuildRosterFrame` can get stuck defaulting to "Show Offline Members" after any sort click.  
* **GManager Roster Tab to the Rescue**: Our custom `ROSTER` view (powered by `collectRosterRows`, live `rosterPlayerSearch` / `rosterNoteSearch` / `rosterOfflineDaysSearch` filters, and `ROSTER_COLS` layout) completely replaces the need to fight the default frame. Right-click context menus (`showRosterContextMenu`) give instant whitelist, promote, demote, whisper and group invite actions.

## **What's New in v1.3.2**

* **0 Minutes = Infinite for Auto Group Invite**: The Group Invite minutes input now treats `0` as infinite duration (no auto-stop timer). Matches the Macro Spam total time limit behavior (`0 = Infinite`). Permanent checkbox still works as before; non-permanent with minutes=0 will stay active until manually toggled off.

* **Updated Classic Yellow UI Colors**: All major section headers, tab buttons, and action buttons now consistently use the classic `|cFFFFCC00` yellowish gold (matching the main title) via explicit color codes and `SetTextColor`.

## **What's New in v1.3.1**

* **Fixed InputBox Clipping of Mass Promotion Criteria** (Ranks tab): The `minDays` / `maxOff` EditBoxes and rank name labels inside the "Mass Promote Criteria" right panel were clipping text and suffering from broken/missing backdrop segments (classic `InputBoxTemplate` + tiling issues on 3.3.5a).  
  **Fix**: Custom backdrops on every EditBox, explicit `SetTextInsets(5,5,1,1)`, widened `nameStr` FontString to 95px (handles "Senior Member", "Huggies Helper" etc. without truncation), and tightened row anchors/gaps in `ranksConfigPanel`. Criteria inputs now look crisp and fully visible.

* **Fixed Blizzard WhoFrame pop-up on Auto Guild Invite**: Whisper trigger phrases were causing the full `WhoFrame` to flash open every time an auto-invite candidate whispered.  
  **Fix**: Hardened the `SetWhoToUI(1)` path + exact-name quoting (`SendWho('n-"PlayerName"')`) so `/who` results feed **silently** into the UI data table. `ProcessWhoLevelCheck()` then reads `GetWhoInfo` without ever showing Blizzard's Who window. Zero UI disruption during recruitment spam.

## **What's New in v1.3**

* **Better Leave Logging**: Completely reworked departure tracking in `Core.lua`. Uses a `pendingLeaves` table + `LEAVE_GRACE_SECONDS = 5 * 60` (5 minutes). When a member disappears from `snapshotRoster()`, we record the exact `absentSince` timestamp. On grace expiry the `LEAVE` entry is pushed with `t = absentSince` so the Log tab shows the real moment they left instead of "now". Cleaner audit history for leadership reviews and fewer false-positive leave spam entries during roster floods.

* **Minimum Level System for Auto Guild Invites**: Added full `minLvl` gate (default 1) inside `GManagerDB.autoInvite`. On `CHAT_MSG_WHISPER` trigger match we now do:
  ```lua
  SetWhoToUI(1)
  SendWho('n-"' .. cleanSender .. '"')   -- exact name match with quotes
  ```
  Then `WHO_LIST_UPDATE` → `ProcessWhoLevelCheck()` reads `GetWhoInfo`, compares against `conf.minLvl`, and either `GuildInvite` + `replyOn` or sends the new `replyLow` message. No more inviting level 1 alts or trial accounts by accident.

* **Improved Settings Tab UI**: Major polish pass on the `settingsMode` block in `UI.lua:Refresh()`. 
  - New dedicated **Group Invite** section with its own backdrop (`groupInviteBg`), enable checkbox, phrase `EditBox`, **Minutes** input (supports 0 for infinite), and **Permanent** mode toggle (`groupInvitePermCheck`).
  - Auto Guild Invite controls are now clearly grouped: trigger phrase, `replyOn`/`replyOff`, `minLvl` numeric input, and `replyLow` message.
  - Better `setVis` handling for all the new widgets (`aiMinLvlBg`, `aiReplyLowBg`, etc.).
  - Input focus guards (`HasFocus()`) prevent the periodic refresh from wiping text the user is still typing.
  - Overall tighter layout, consistent label positioning, and smoother batch-size / guild-frame hook toggles.
  - **Minimap Button Controls** (Show button toggle + Rotation/Distance sliders) moved to top-right Settings area (below version header), with Mass Action below it. Background panels updated to properly envelop controls (including group invite check).

## **Core Features**

### **🛡️ Whitelisting**
Protected members (green `[W]` tag in roster rows) are skipped by every mass operation (`ProcessBatch`, mass kick, mass promote). Toggle via right-click context menu or the new whitelist API in `Core.lua`.

### **🥾 Mass Kick List**
Filter the roster (name/note/offline-days), preview the list, then execute in safe configurable batches (`GManagerDB.batchSize`). Double confirmation + whitelist bypass. All kicks go through `GuildUninvite` with post-action `RequestRosterAfterAction` delay.

### **🎖️ Mass Promote List (Ranks Tab)**
Select a baseline rank in the new Ranks view, set min-days-in-guild + max-offline filters, preview candidates (parsed from officer note date tags like `[Jun 09 2026]`), then batch promote. Respects whitelist. Dynamic `GuildControlGetRankName` / `GuildControlGetNumRanks` integration.

### **✉️ Auto Guild & Party Invites (Enhanced in v1.3+ / v1.3.2)**
* **Guild Whisper Triggers**: Custom phrase (supports multiple words separated by `-`). When matched, silent `/who` level check → `minLvl` gate → invite or `replyLow`. Configurable `replyOn` / `replyOff` messages. All handled in the `backend` `OnEvent` for `CHAT_MSG_WHISPER` + `WHO_LIST_UPDATE`. (WhoFrame pop-up fully suppressed in 1.3.1)
* **Party / Group Auto-Invites**: Toggle via Settings → Group Invite section. Minutes field supports **0 for infinite** (no auto-stop timer, matching Macro Spam total limit behavior) or **Permanent** checkbox. Label shows "min (0=inf)". Same multi-word trigger support via `containsTriggerWord`. Uses `InviteUnit`. Checkbox text: "Auto Group On/Off (0=inf): ".
* **Rate & Safety**: `delayCall` scheduler, exact-name `/who` quoting, and focus guards on all EditBoxes.

### **📜 Event Log**
Up to 15 000 entries per guild. Types: `JOIN`, `LEAVE`, `PROMOTE`, `DEMOTE`, `NOTE`, `ONOTE`, `SEEN`, `LEVEL`. Full text search, type filters, line numbers. `fmtDateLong` + `fmtSince` helpers give human readable timestamps and "X days ago" strings. Color coded with `TYPE_COLOR` table.

### **🔗 Alts Mapping**
`SetAlt` / `GetMainOf` / `GetAltsOf` stored per-guild in `GManagerDB.guilds[key].alts`. Displayed in both Roster rows (`<M>` / `(alt)`) and the dedicated Alts tab + Member Detail panel (`Roster.lua`).

### **💬 Account-Wide Macros + Spam**
Save any text bound to a channel (1-9, GUILD, OFFICER, SAY, PARTY, RAID, YELL). Send instantly or add to rotation. `spamUpdater` `OnUpdate` ticker respects `spamInterval` (minutes) + optional **total time limit** (0 = infinite). Spam checkboxes per macro row with live `[SPAM]` tag. Channel buttons, Save button, and per-macro action buttons (Send/Del/Edit/Set) use classic yellowish styling.

## **Interface Tabs (6 total)**

All built with plain Wrath frame API (`UIPanelButtonTemplate`, `InputBoxTemplate`, `OptionsBaseCheckButtonTemplate`, `FauxScrollFrame`, custom `PANEL_BACKDROP` / `BACKDROP` tables). No AceGUI or external libs. Major buttons/headers use classic `|cFFFFCC00` yellowish gold.

1. **Log Tab** – Search + type filter checkboxes + numbered lines + clear button. Right side filter panel.
2. **Roster Tab** – Show offline toggle, player/note search, offline-days threshold, group-alts checkbox, mass-kick button, ONote-empty button. Sortable columns (`rosterSortBy`). Rich right-click menu.
3. **Alts Tab** – Simple list of alt → main mappings with Set / Unset inputs.
4. **Macros Tab** – Channel buttons (highlight active, classic yellow text), message EditBox + Save (yellow), spam interval + total limit (0=inf) + enable checkbox. Per-row Send / Delete / Edit / Set-as-spam buttons (yellow text).
5. **Ranks Tab** – Baseline rank selector, min-days / max-offline filters (now clip-free in 1.3.1), candidate preview table (`collectRanksRows`), mass-promote button (yellow text). Uses live `GuildControlGet*` calls.
6. **Settings Tab (Improved UI)** – 
   - Batch size numeric (yellow header)
   - Open/Close with GuildFrame checkboxes (`GManagerCharDB`)
   - **Group Invite** block: enable, phrase, **Minutes input (0=inf)**, permanent toggle. Background now properly includes the check. Checkbox: "Auto Group On/Off (0=inf): ".
   - **Minimap Button Controls** (Show + Rotation/Distance sliders) positioned top-right below version header; Mass Action below them.
   - **Auto Guild Invite** block: enabled, phrase, replyOn, replyOff, minLvl, replyLow (yellow headers)
   - All inputs guarded against refresh overwrites.
   - Classic yellowish colors applied to headers and relevant buttons throughout.

Access with `/gm` or `/gmanager`. The main frame (`GManagerMainFrame`) is movable, clamped, high-strata, with tab buttons that call `UI:Refresh()` on switch.

## **Slash Commands**

| Command                        | Function |
|--------------------------------|----------|
| `/gm`                          | Toggle main UI window |
| `/gm help`                     | Print command list to chat |
| `/gm setalt <alt> <main>`      | Tag alt relationship (calls `addon:SetAlt`) |
| `/gm unalt <name>`             | Remove alt tag |
| `/gm alts`                     | Dump current alt→main map to chat |
| `/gm clear`                    | Wipe current guild's event log |

## **Technical Information**

* **Interface TOC**: 30300 (WotLK 3.3.5a native)
* **Current Version**: 1.3.2 (see `addon.version` in `Core.lua`)
* **SavedVariables**: `GManagerDB` (account) – guilds, macros, autoInvite config (incl. `groupMinutes`), batchSize, spamTotalMinutes, minimapRotation/Distance, etc.
* **SavedVariablesPerCharacter**: `GManagerCharDB` – open/close with guild, massPromote history
* **Files**: `Core.lua` (backend, events, snapshot diff, leave grace, who level checks, spam ticker with total limit, group invite timer logic), `UI.lua` (6-tab frame, all Refresh logic, context menus, Roster/Ranks/Alts/Macros/Settings widgets, colored buttons/headers, 0-min infinite support, layout moves), `Roster.lua` (Member Detail panel takeover of `GuildMemberDetailFrame`, alt tagging, promote/demote/remove/invite buttons, periodic poll on `GetGuildRosterSelection`)
* **Key Patterns Used**: `scheduleDiff` + `SNAPSHOT_DEBOUNCE`, `ProcessBatch` with 1-second `OnUpdate` pacing, `containsTriggerWord` multi-word split on `-`, `fmtSince` / `lastSeenColor` helpers, `CLASS_COLOR` + `TYPE_COLOR` strings, explicit `|cFFFFCC00` + `SetTextColor` for UI consistency.

## **⚖️ Use at Your Own Discretion**

GManager gives you serious power: batch kicks, mass promotes, auto-invites (with 0=inf minutes or permanent), officer-note date stamping, minimap button positioning, etc. Everything is rate-limited and double-confirmed, but **you** are responsible for the filters you set and for double-checking the green `[W]` whitelist tags before hitting "Mass Kick" or "Mass Promote". The 5-minute leave grace and min-level who-check are there to help, not to replace good judgment. Use responsibly on your realm.

---

*Refined for WotLK 3.3.5a – pure Lua, no external dependencies. v1.3.2 — 0-minute infinite Group Invites + full classic yellow UI polish. Questions or pull requests welcome on the classic addon scene.*
