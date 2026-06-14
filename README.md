# **GManager v1.1.3**

GManager is an all-in-one Guild Management addon natively engineered for **World of Warcraft: Wrath of the Lich King (Patch 3.3.5a)**. Originally developed to streamline guild operations, this version has been refined to offer unparalleled administration tools. It provides deep logging, robust alt-character tracking, channel macros, and automated batch administration features.

## **⚠️ Known Bug & The GManager Solution**

Like any powerful interface overhaul, GManager has one minor administrative quirk you should be aware of regarding the default user interface:

* **The Blizzard GuildFrame Bug**: Keeping this addon active will cause the original Blizzard GuildFrame to get visually stuck to show Offline Members. Specifically, whenever you click to sort the default roster, it will default to always showing offline members.  
* **The Silver Lining**: While this default UI glitch can be annoying, GManager's dedicated **Roster Tab** completely compensates for it by offering a vastly superior overview. Instead of fighting with the default frame, GManager provides a cleaner directory equipped with live text filtering by character name or note strings, dynamic thresholds for minimum days offline, and powerful right-click context menus to handle invites, whispers, and rank shifts instantly.

## **Core Features**

### **🛡️ Whitelisting (New\!)**

* **Protection Shield**: Protect specific characters from any mass automated administrative actions.  
* **Visual Indicators**: Whitelisted members are clearly labeled with a green **\[W\]** tag right in your guild roster view.  
* **Easy Management**: Toggle a member's whitelist status effortlessly using the right-click roster context menu.

### **🥾 Mass Kick List (New\!)**

* **Clean House Safely**: Seamlessly kick inactive, low-level, or unwanted characters based on your active roster filters.  
* **Smart Whitelist Bypass**: The system checks every target and guarantees whitelisted members will never be removed during a sweep.  
* **Rate-Limited Performance**: Actions are executed sequentially in safe batches of 15 players per second to protect server stability and prevent client freezes.  
* **Double Confirmation Guardrails**: Employs a rigorous 2-step safety prompt window to prevent accidental mass removals.

### **🎖️ Mass Promote List (New\!)**

* **Automated Rank Ups**: Evaluate and mass promote roster members from a specific rank up to the next tier sequentially.  
* **Granular Criteria Filters**: Filter your promotion pool by minimum days spent in the guild and maximum allowed offline days.  
* **Safety First**: Respects the roster whitelist entirely by skipping protected members.  
* **Server-Friendly Execution**: Runs safely at a rate of 15 operations per second.

### **✉️ Auto Guild Invites (New\!)**

* **Whisper Triggers**: Automatically invites guildless players to the guild when they whisper you a customizable keyword phrase.  
* **Modular Reply Templates**: Configure automated whisper responses for every scenario, including a message sent alongside successful invites, an optional reply when the function is turned off, a minimum level filter, and an automatic notification text if a candidate's level is too low.

## **Interface Tabs Breakdown**

GManager features a clean, plain-frame UI accessible with 5 specialized tabs:

### **1\. Log Tab**

* **Ghost-Leave Filtering**: Features a smart 3-day grace window buffer for missing characters. This prevents temporary database synchronization hiccups from cluttering your logs with fake leave/join messages.  
* **Comprehensive Audit Trail**: Tracks and logs all instances of character joins, departures, public note edits, officer note changes, rank promotions, and rank demotions.  
* **Scannable Utilities**: Offers full text search filtering, line numbering options, and a structural layout capable of sorting up to 9,000 recorded lines per guild.

### **2\. Roster Tab**

* **Enhanced Context Menus**: Right-clicking any member provides quick-access buttons to toggle whitelisting, initiate safe rank-ups or rank-downs, open whispers, or send a group invite.  
* **Advanced Search Filters**: Filter your live directory seamlessly by character name, note string, or specify a threshold for minimum days offline.  
* **ONote Empty Newbies**: Features a dedicated button to identify members with blank officer notes and batch-write today's exact date tag (e.g., \[Jun 13 2026\]) directly to the server.

### **3\. Ranks Tab**

* **Mass Promotion Dashboard**: Select a specific baseline guild rank using structural arrow selectors to preview all eligible promotion candidates.  
* **Dynamic Time Parsing**: Automatically extracts and parses structured dates directly from server-side officer notes to calculate exact membership longevity.

### **4\. Alts Tab**

* **Alt-to-Main Indexing**: Displays an alphabetical, structured map of secondary characters linked back to their main characters.

### **5\. Macros & Auto-Invite Tab**

* **Account-Wide Macros**: Save and broadcast custom text strings instantly across explicit system channels like SAY, GUILD, OFFICER, PARTY, RAID, or specific numerical channels 1-9.  
* **Auto Guild Invite Hub**: Located conveniently at the bottom of the tab, this interface contains clear setup inputs to manage your automated recruitment phrases, active status toggles, and whisper responses.

## **Slash Commands**

You can control the addon directly via standard chat slash commands using **/gm** or **/GManager**:

| Command           | Function |
| :----             | :---- |
| /gm               | Toggles the primary GManager user interface window. |
| /gm help          | Prints an index of available command options inside the chat log. |
| /gm setalt \<altName\> \<mainName\> | Tags a specific character as an alternate version of a primary main character. |
| /gm unalt \<name\> | Removes any existing alternate-character association tag from the target. |
| /gm alts          | Prints a structured breakdown of all currently mapped alt-to-main relationships in chat. |
| /gm clear         | Instantly purges the event history log for your current active guild. |
| /gm debug         | Toggles basic administrative debug print alerts. |

## 

## **Technical Information**

* **Interface TOC ID**: 30300 (Wrath of the Lich King Native).  
* **Current Version**: 1.1.2.  
* **Saved Variables (Account-Wide)**: GManagerDB.  
* **Saved Variables (Character-Specific)**: GManagerCharDB.

## **⚖️ Use at Your Own Discretion**

**Important Notice**: Because GManager v1.1.2 introduces automated, high-speed batch execution tools—such as the Mass Kick List and Mass Promote List \- it gives you immense 2-Click power over your Guild.

While the addon is engineered with server-friendly rate limits (15 operations/Member-Changes per second) and a 2-step verification confirmation prompt to prevent accidents, automated tools are only as precise as the filters you set. A single misplaced criteria filter or an un-updated whitelist could result in unintended rank shifts or member removals.

**Please utilize this software responsibly and at your own discretion.** Always double-check your active roster filters and verify your green **\[W\]** whitelist tags before pulling the trigger on any mass administrative actions.

