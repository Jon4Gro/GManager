# **GManager (v1.2)**

GManager is an all-in-one Guild Management addon natively engineered for **World of Warcraft: Wrath of the Lich King (Patch 3.3.5a)**. Engineered to streamline high-volume guild operations, this tool offers unparalleled administration utilities including deep core logging, robust alt-character mapping, localized channel macros, and automated batch processing systems.

## **⚠️ Known Bug & The GManager Solution**

Like any powerful interface overhaul, GManager has one minor administrative quirk you should be aware of regarding the default user interface:

* **The Blizzard GuildFrame Bug**: Keeping this addon active will cause the original Blizzard GuildFrame to get visually stuck to show Offline Members. Specifically, whenever you click to sort the default roster, it will default to always showing offline members.  
* **The Silver Lining**: While this default UI glitch can be annoying, GManager's dedicated **Roster Tab** completely compensates for it by offering a vastly superior overview. Instead of fighting with the default frame, GManager provides a cleaner directory equipped with live text filtering by character name or note strings, dynamic thresholds for minimum days offline, and powerful right-click context menus to handle invites, whispers, and rank shifts instantly.

## **What's New in v1.2**

* **🎖️ Improved Mass Promote System**: Enhanced ranking logic, better filtering UI in the new **Ranks Tab**, and more precise membership duration calculations based on officer note date parsing.
* **🛠️ Major UI Improvements**: Cleaner layout, better responsiveness, refined column widths, and polished visual feedback across all tabs.
* **⚙️ New Settings Tab**: Centralized configuration for:
  * Batch size control for mass operations
  * Auto-open / Auto-close behavior tied to the default Guild Frame
  * Full Auto Guild Invite & Auto Group Invite configuration (keywords, replies, level filters, etc.)
* **General Polish**: Various bug fixes, performance tweaks, and improved roster handling.

## **Core Features**

### **🛡️ Whitelisting**

* **Protection Shield**: Protect specific characters from any mass automated administrative actions.  
* **Visual Indicators**: Whitelisted members are clearly labeled with a green  
  $$W$$  
  tag right in your guild roster view.  
* **Easy Management**: Toggle a member's whitelist status effortlessly using the right-click roster context menu.

### **🥾 Mass Kick List**

* **Clean House Safely**: Seamlessly kick inactive, low-level, or unwanted characters based on your active roster filters.  
* **Smart Whitelist Bypass**: The system checks every target and guarantees whitelisted members will never be removed during a sweep.  
* **Rate-Limited Performance**: Actions are executed sequentially in safe batches (configurable size) to protect server stability.  
* **Double Confirmation Guardrails**: Employs a rigorous 2-step safety prompt window to prevent accidental mass removals.

### **🎖️ Mass Promote List (Improved)**

* **Automated Rank Ups**: Evaluate and mass promote roster members from a specific rank up to the next tier sequentially.  
* **Granular Criteria Filters**: Filter your promotion pool by minimum days spent in the guild and maximum allowed offline days.  
* **Safety First**: Respects the roster whitelist entirely by skipping protected members.  
* **Server-Friendly Execution**: Configurable batch processing with clear progress feedback.

### **✉️ Auto Guild & Party Invites**

* **Guild Whisper Triggers**: Automatically invites guildless players to the guild when they whisper you a customizable keyword phrase. Includes automated replies, level filter safety blocks, and dynamic out-of-service alerts.  
* **Party / Group Auto-Invites**: Turn your character into an automated group recruitment hub. Instantly accepts whisper trigger keywords to auto-invite characters to your party or raid group.  
* **Group Window Scheduler**: Built-in temporal safety parameters allow you to open recruitment bursts for limited time or lock into permanent mode.

## **Interface Tabs Breakdown**

GManager features a clean, plain-frame UI accessible via **/gm** with 6 specialized tabs:

### **1. Log Tab**

* **Ghost-Leave Filtering**: Features a smart 3-day grace window buffer for missing characters.  
* **Comprehensive Audit Trail**: Tracks joins, leaves, note edits, rank changes, and more.  
* **Scannable Utilities**: Full text search, line numbering, and support for up to 15,000 entries.

### **2. Roster Tab**

* **Enhanced Context Menus**: Right-click any member for whitelisting, promote/demote, whisper, or invite.  
* **Advanced Search Filters**: Filter by name, note, or offline days.  
* **ONote Empty Newbies**: One-click batch tagging of new members with today's date in officer notes.

### **3. Ranks Tab (New/Improved)**

* **Mass Promotion Dashboard**: Select baseline rank and preview eligible candidates with powerful filtering.  
* **Dynamic Time Parsing**: Reads membership dates from officer notes for accurate longevity calculations.

### **4. Alts Tab**

* **Alt-to-Main Indexing**: Alphabetical map of secondary characters linked to their mains.

### **5. Macros Tab**

* **Account-Wide Macros**: Save and broadcast messages to any channel (GUILD, OFFICER, SAY, PARTY, etc.).  
* **Spam Rotation**: Optional timed broadcasting of selected macros.

### **6. Settings Tab (New!)**

* Configure batch sizes, Guild Frame integration, and all Auto-Invite settings in one place.

## **Slash Commands**

You can control the addon directly via standard chat slash commands using **/gm** or **/GManager**:

| Command             | Function |
| :----               | :---- |
| /gm                 | Toggles the primary GManager user interface window. |
| /gm help            | Prints an index of available command options inside the chat log. |
| /gm setalt \<altName\> \<mainName\> | Tags a specific character as an alternate version of a primary main character. |
| /gm unalt \<name\>  | Removes any existing alternate-character association tag from the target. |
| /gm alts            | Prints a structured breakdown of all currently mapped alt-to-main relationships in chat. |
| /gm clear           | Instantly purges the event history log for your current active guild. |

## **Technical Information**

* **Interface TOC ID**: 30300 (Wrath of the Lich King Native Patch 3.3.5a).  
* **Current Version**: 1.2.  
* **Saved Variables (Account-Wide)**: GManagerDB.  
* **Saved Variables (Character-Specific)**: GManagerCharDB.  
* **Component Architecture**: Core.lua, UI.lua, Roster.lua.

## **⚖️ Use at Your Own Discretion**

**Important Notice**: Because GManager introduces automated, high-speed batch execution tools—such as the Mass Kick List, Mass Promote List, and Officer Note population tools—it gives you immense power over your Guild.  
While the addon is engineered with server-friendly rate limits and multi-step verification confirmation prompts to prevent accidents, automated tools are only as precise as the filters you set.  
**Please utilize this software responsibly and at your own discretion.** Always double-check your active roster filters and verify your green

$$W$$  
whitelist tags before pulling the trigger on any mass administrative actions.
