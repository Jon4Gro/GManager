-- GManager Core
-- Wrath 3.3.5a native guild roster tracking, event log, alts management.

GManager = GManager or {}
local addon = GManager
addon.version = "1.1.3"

local LOG_MAX = 15000        -- cap log size per guild to prevent unbounded growth
local SNAPSHOT_DEBOUNCE = 2 -- seconds; coalesce burst GUILD_ROSTER_UPDATE events

-- This server drops players from the roster after roughly one day offline,
-- so the naive "in old, not in new" check would log a spurious LEAVE every
-- time someone took a break and a matching JOIN when they returned. We
-- buffer "missing" players in guild.pendingLeaves and only promote them to
-- a real LEAVE log entry once they've been absent for this many seconds.
-- A reappearance inside the window silently clears the pending state with
-- neither a LEAVE nor a JOIN logged.
local LEAVE_GRACE_SECONDS = 3 * 24 * 60 * 60  -- 3 days

local currentGuildKey      -- realm::guildname for the currently active guild
local lastSnapshot         -- previous snapshot used for diffing
local pendingSnapshot      -- coalescing timer-active flag

-- =========================================================
-- SavedVariables bootstrap
-- =========================================================
local function ensureDB()
    if type(GManagerDB)     ~= "table" then GManagerDB     = {} end
    if type(GManagerCharDB) ~= "table" then GManagerCharDB = {} end
    if type(GManagerDB.guilds) ~= "table" then GManagerDB.guilds = {} end
    if type(GManagerDB.macros) ~= "table" then GManagerDB.macros = {} end
    if not GManagerDB.version then GManagerDB.version = 1 end
    if type(GManagerDB.autoInvite) ~= "table" then
        GManagerDB.autoInvite = {
            enabled = false,
            phrase = "ginv pls",
            replyOn = "Auto-Sending Guild invite ",
            replyOff = "Auto-invites are currently disabled",
            minLvl = 1,
            replyLow = "Function not implemented yet"
        }
    end
end

-- =========================================================
-- Macros API (account-wide saved messages bound to a channel)
-- macro = { channel = "1".."9" | "SAY" | "GUILD" | "OFFICER" | "PARTY" | "RAID" | "YELL",
--           text    = "..." }
-- =========================================================
function addon:GetMacros()
    if type(GManagerDB) ~= "table" or type(GManagerDB.macros) ~= "table" then
        return {}
    end
    return GManagerDB.macros
end

function addon:AddMacro(channel, text)
    if not channel or channel == "" then return false, "Pick a channel." end
    if not text or text == "" then return false, "Message cannot be empty." end
    GManagerDB.macros = GManagerDB.macros or {}
    table.insert(GManagerDB.macros, { channel = channel, text = text })
    return true
end

function addon:RemoveMacro(index)
    if not GManagerDB.macros then return end
    if type(index) ~= "number" then return end
    if index < 1 or index > #GManagerDB.macros then return end
    table.remove(GManagerDB.macros, index)
end

function addon:SendMacro(index)
    if not GManagerDB.macros then return false, "No macros." end
    local m = GManagerDB.macros[index]
    if not m then return false, "Macro not found." end
    return addon:Broadcast(m.channel, m.text)
end

local NAMED_CHANNELS = {
    SAY = true, YELL = true, GUILD = true, OFFICER = true,
    PARTY = true, RAID = true, RAID_WARNING = true,
}

function addon:Broadcast(channel, text)
    if not channel or channel == "" then return false, "No channel." end
    if not text or text == "" then return false, "Empty message." end
    -- Numeric channel: SendChatMessage(msg, "CHANNEL", nil, slot)
    local num = tonumber(channel)
    if num and num >= 1 and num <= 9 then
        SendChatMessage(text, "CHANNEL", nil, num)
        return true
    end
    local up = channel:upper()
    if NAMED_CHANNELS[up] then
        if up == "RAID_WARNING" then
            SendChatMessage(text, "RAID_WARNING")
        else
            SendChatMessage(text, up)
        end
        return true
    end
    return false, "Unsupported channel: " .. tostring(channel)
end

local function guildKey(realmName, guildName)
    return (realmName or "?") .. "::" .. (guildName or "?")
end

local function ensureGuildEntry(key)
    local g = GManagerDB.guilds[key]
    if not g then
        g = { members = {}, log = {}, alts = {}, whitelist = {}}
        GManagerDB.guilds[key] = g
    end
    if not g.members       then g.members       = {} end
    if not g.log           then g.log           = {} end
    if not g.alts          then g.alts          = {} end
    if not g.pendingLeaves then g.pendingLeaves = {} end
    if not g.whitelist     then g.whitelist     = {} end
    return g
end

function addon:GetCurrentGuild()
    if not currentGuildKey then return nil end
    return GManagerDB and GManagerDB.guilds and GManagerDB.guilds[currentGuildKey]
end

function addon:GetCurrentGuildKey()
    return currentGuildKey
end

-- =========================================================
-- Log
-- =========================================================
local function pushLog(guild, entry)
    table.insert(guild.log, entry)
    while #guild.log > LOG_MAX do
        table.remove(guild.log, 1)
    end
end

function addon:ClearLog()
    local g = self:GetCurrentGuild()
    if g then g.log = {} end
end

-- =========================================================
-- Roster snapshot + diff
-- =========================================================
local function snapshotRoster()
    local snap = {}
    local n = GetNumGuildMembers() or 0
    if n == 0 then return snap end
    for i = 1, n do
        local name, rank, rankIndex, level, _, zone, note, officerNote, online, _, classFile
            = GetGuildRosterInfo(i)
        if name and name ~= "" then
            snap[name] = {
                index       = i,
                rank        = rank or "",
                rankIndex   = rankIndex or 0,
                level       = level or 0,
                zone        = zone or "",
                note        = note or "",
                officerNote = officerNote or "",
                online      = online and true or false,
                classFile   = classFile or "",
            }
        end
    end
    return snap
end

local function diffSnapshots(old, new, guild)
    local now = time()
    local todayStr = date("%b %d %Y", now) -- Format: Month dd yyyy (e.g., Jun 09 2026)

    guild.pendingLeaves = guild.pendingLeaves or {}

    -- Joins (in new, not in old)
    for name, info in pairs(new) do
        if not old[name] then
            local m = guild.members[name]
            if guild.pendingLeaves[name] then
                -- Ghost-rejoin: this player was inside the LEAVE grace window
                -- (server briefly dropped them from the roster). Silently
                -- clear the pending state - no JOIN, no LEAVE logged.
                guild.pendingLeaves[name] = nil
            elseif m and m.joinDateExact then
                -- Real rejoin after their LEAVE was already promoted, and we
                -- previously observed their actual first join. PRESERVE the
                -- original joinDate - it stays the very first observed join.
                pushLog(guild, {
                    t = now, type = "JOIN", who = name,
                    details = ("Lvl %d %s"):format(info.level, info.rank),
                })
            elseif m then
                -- Player was seeded (existed in guild.members before we ever
                -- observed their join, typically because the addon was
                -- installed after them). This re-appearance is NOT their
                -- original join - we don't actually know when they joined -
                -- so log the JOIN but do not fabricate a date. joinDate
                -- stays nil and displays as "?".
                pushLog(guild, {
                    t = now, type = "JOIN", who = name,
                    details = ("Lvl %d %s"):format(info.level, info.rank),
                })
            else
                -- First time we've ever observed this player AND they were
                -- never seeded - this is genuinely their join, stamp it
                -- exact so the UI can display it with confidence.
                pushLog(guild, {
                    t = now, type = "JOIN", who = name,
                    details = ("Lvl %d %s"):format(info.level, info.rank),
                })
                m = {}
                guild.members[name] = m
                m.joinDate = todayStr
                m.joinDateExact = true

                -- Auto-write to Officer Note if we have permissions
                if CanEditOfficerNote and CanEditOfficerNote() then
                    local currentNote = info.officerNote or ""
                    local dateTag = "[" .. todayStr .. "]"

                    -- Only append if the date isn't already in the note
                    if not string.match(currentNote, "%[%a%a%a %d%d %d%d%d%d%]") then
                        local newNote = currentNote

                        if currentNote == "" then
                            newNote = dateTag
                            -- Ensure appending it won't exceed the 30 char limit
                            elseif string.len(currentNote) + string.len(dateTag) + 1 <= 30 then
                                newNote = currentNote .. " " .. dateTag
                                end

                                -- If a change was made safely, save it to the server
                                if newNote ~= currentNote and info.index then
                                    GuildRosterSetOfficerNote(info.index, newNote)
                                end
                        end
                    end
            end
        end
    end

    -- Leaves (in old, not in new): defer behind the grace window. The
    -- timestamp we stamp here is preserved across snapshots so the grace
    -- clock keeps counting from the first observed absence.
    for name in pairs(old) do
        if not new[name] then
            guild.pendingLeaves[name] = guild.pendingLeaves[name] or now
        end
    end

    -- Changes (in both)
    for name, n in pairs(new) do
        local o = old[name]
        if o then
            if o.rank ~= n.rank then
                local kind = ((o.rankIndex or 0) > (n.rankIndex or 0)) and "PROMOTE" or "DEMOTE"
                pushLog(guild, {
                    t = now, type = kind, who = name,
                    details = ("%s -> %s"):format(o.rank, n.rank),
                })
            end
            if o.note ~= n.note then
                pushLog(guild, {
                    t = now, type = "NOTE", who = name,
                    details = ("'%s' -> '%s'"):format(o.note, n.note),
                })
            end
            if o.officerNote ~= n.officerNote then
                pushLog(guild, {
                    t = now, type = "ONOTE", who = name,
                    details = ("'%s' -> '%s'"):format(o.officerNote, n.officerNote),
                })
            end
   --[[         if (n.level or 0) > (o.level or 0) then
                pushLog(guild, {
                    t = now, type = "LEVEL", who = name,
                    details = ("%d -> %d"):format(o.level, n.level),
                })
            end ]]
        end

        -- Track last-online + class info
        local m = guild.members[name]
        if not m then m = {}; guild.members[name] = m end
        if n.online then m.lastOnline = now end
        m.lastRank  = n.rank
        m.lastLevel = n.level
    end
end

-- =========================================================
-- Wrath has no C_Timer.After -- implement a tiny one-shot
-- scheduler via OnUpdate.
-- =========================================================
local scheduler = CreateFrame("Frame")
local queue = {}
scheduler:SetScript("OnUpdate", function(self)
    if #queue == 0 then return end
    local now = GetTime()
    local i = 1
    while i <= #queue do
        if now >= queue[i].when then
            local fn = queue[i].fn
            table.remove(queue, i)
            local ok, err = pcall(fn)
            if not ok and GManagerCharDB and GManagerCharDB.debug then
                DEFAULT_CHAT_FRAME:AddMessage("|cffff5555GManager scheduler err: " .. tostring(err))
            end
        else
            i = i + 1
        end
    end
end)
local function delayCall(secs, fn)
    table.insert(queue, { when = GetTime() + secs, fn = fn })
end

-- =========================================================
-- Whitelist API
-- =========================================================
function addon:ToggleWhitelist(name)
local g = self:GetCurrentGuild()
if not g then return false end
    g.whitelist[name] = not g.whitelist[name]
    return g.whitelist[name]
    end

    function addon:IsWhitelisted(name)
    local g = self:GetCurrentGuild()
    return g and g.whitelist and g.whitelist[name] or false
    end

-- =========================================================
-- Coalesced "do a diff" trigger
-- GUILD_ROSTER_UPDATE can fire many times back-to-back. We
-- wait a couple seconds for the dust to settle before diffing.
-- =========================================================
local function scheduleDiff()
    if pendingSnapshot then return end
    pendingSnapshot = true
    delayCall(SNAPSHOT_DEBOUNCE, function()
        pendingSnapshot = false
        if not IsInGuild() then return end
        local guildName = GetGuildInfo("player")
        if not guildName or guildName == "" then return end
        local realmName = GetRealmName() or "?"
        local key = guildKey(realmName, guildName)
        if key ~= currentGuildKey then
            currentGuildKey = key
            lastSnapshot = nil
        end
        local guild = ensureGuildEntry(currentGuildKey)
        local snap = snapshotRoster()
        local snapCount = 0
        for _ in pairs(snap) do snapCount = snapCount + 1 end

        -- Wrath's GetGuildRosterInfo can briefly return an empty roster
        -- right after a guild context change. Don't seed/diff against
        -- a zero-member snapshot - just wait for the next update.
        if snapCount == 0 then
            return
        end

        -- Pre-diff pass: every known member who isn't in this snapshot
        -- becomes (or stays) a pending-leave candidate. This is more
        -- comprehensive than diffSnapshots' own "in old, not in new" check
        -- because it also catches members who were already absent across a
        -- session boundary - the first snapshot after login has no diff
        -- branch, so without this pass their reappearance would log a
        -- spurious JOIN ("real rejoin") instead of silently clearing.
        guild.pendingLeaves = guild.pendingLeaves or {}
        local nowSec = time()
        for name in pairs(guild.members) do
            if not snap[name] then
                guild.pendingLeaves[name] = guild.pendingLeaves[name] or nowSec
            end
        end

        -- First time we've ever observed this guild? Seed the log with a
        -- synthetic "SEEN" entry for every current member. We deliberately
        -- do NOT stamp joinDate here: WoW 3.3.5a has no API for the real
        -- join date, and writing today's date would be a fabrication. These
        -- members keep joinDate == nil and display as "?" until we observe
        -- a genuine first-time JOIN for someone we've never seen before.
        local firstObservation = (next(guild.members) == nil)
                                and (#guild.log == 0)
                                and (lastSnapshot == nil)
        if firstObservation then
            local now = time()
            for name, info in pairs(snap) do
                guild.members[name] = guild.members[name] or {}
                guild.members[name].lastRank  = info.rank
                guild.members[name].lastLevel = info.level
                guild.members[name].classFile = info.classFile
                if info.online then
                    guild.members[name].lastOnline = now
                end
                table.insert(guild.log, {
                    t = now, type = "SEEN", who = name,
                    details = ("Lvl %d %s"):format(info.level, info.rank),
                })
            end
        elseif lastSnapshot then
            diffSnapshots(lastSnapshot, snap, guild)
        end

        -- Post-diff resolution of pending-leaves. Anyone in the snapshot
        -- has their pending state cleared (covers cross-session ghost
        -- rejoins, where there was no diff branch to consume the pending
        -- entry). Anyone past the grace window finally gets a real LEAVE
        -- log entry, stamped with the original absence timestamp so the
        -- log reads as the date they actually went missing.
        for name, since in pairs(guild.pendingLeaves) do
            if snap[name] then
                guild.pendingLeaves[name] = nil
            elseif (nowSec - since) >= LEAVE_GRACE_SECONDS then
                pushLog(guild, { t = since, type = "LEAVE", who = name })
                guild.pendingLeaves[name] = nil
            end
        end

        -- Always update classFile in member records from the latest snapshot.
        for name, info in pairs(snap) do
            local m = guild.members[name]
            if m then m.classFile = info.classFile end
        end
        lastSnapshot = snap

        if addon.UI and addon.UI.RefreshIfShown then
            addon.UI:RefreshIfShown()
        end
    end)
end

-- =========================================================
-- Roster request helper
-- Always force the server-side "show offline" filter on before asking
-- for data. The Blizzard guild window has its own checkbox for this
-- and toggling it off would otherwise hide offline members from us
-- entirely, breaking last-seen tracking and leave-detection.
-- Our UI's "Show Offline" toggle still controls *display* filtering.
-- =========================================================
function addon:RequestRoster()
    if SetGuildRosterShowOffline then
        SetGuildRosterShowOffline(true)
    end
    GuildRoster()
end

-- Called after a roster-mutating action (kick, promote, demote, note edit).
-- The server needs a moment to process the action before its next
-- GUILD_ROSTER_UPDATE reflects the new state, so we fire one request now
-- (usually returns the pre-action snapshot) and a second one ~1.5s later
-- to pick up the post-action snapshot. The second fetch is what actually
-- removes a kicked player from our UI without requiring a /reload.
function addon:RequestRosterAfterAction()
    self:RequestRoster()
    delayCall(1.5, function()
        if IsInGuild() then
            if SetGuildRosterShowOffline then
                SetGuildRosterShowOffline(true)
            end
            GuildRoster()
        end
    end)
end

-- =========================================================
-- Events
-- =========================================================
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:RegisterEvent("PLAYER_GUILD_UPDATE")
eventFrame:RegisterEvent("GUILD_ROSTER_UPDATE")
eventFrame:RegisterEvent("PLAYER_ENTERING_WORLD")
eventFrame:RegisterEvent("CHAT_MSG_WHISPER")
eventFrame:SetScript("OnEvent", function(self, event, msg, author, ...)
ensureDB()

if event == "CHAT_MSG_WHISPER" then
    local conf = GManagerDB.autoInvite
    if conf and msg and msg:lower() == conf.phrase:lower() then
        -- Handle OFF state
        if not conf.enabled then
            if conf.replyOff and conf.replyOff ~= "" then
                SendChatMessage(conf.replyOff, "WHISPER", nil, author)
                end
                return
                end

                -- Handle ON state (Bypassing strict level check due to API limits)
if conf.replyOn and conf.replyOn ~= "" then
        SendChatMessage(conf.replyOn, "WHISPER", nil, author)
    end
        if author then
            GuildInvite(author)
            end
    end
end

        if event == "PLAYER_LOGIN" or event == "PLAYER_ENTERING_WORLD" then
            if IsInGuild() then
            addon:RequestRoster()
        end
        elseif event == "PLAYER_GUILD_UPDATE" then
            if IsInGuild() then
            addon:RequestRoster()
        else
            currentGuildKey = nil
            lastSnapshot = nil
        end
        elseif event == "GUILD_ROSTER_UPDATE" then
        if IsInGuild() then
        -- Re-assert the show-offline flag in case the user just toggled
        -- the Blizzard checkbox; the resulting GUILD_ROSTER_UPDATE will
        -- have given us a partial list. Force-true and re-fetch.
        if SetGuildRosterShowOffline and not GetGuildRosterShowOffline() then
            SetGuildRosterShowOffline(true)
            GuildRoster()
            return
        end
            scheduleDiff()
            end
        end
end)

-- =========================================================
-- Alts API
-- =========================================================
function addon:SetAlt(altName, mainName)
    local g = self:GetCurrentGuild()
    if not g then return false, "Not in a guild yet." end
    if type(altName) ~= "string" or altName == "" then
        return false, "Need an alt name."
    end
    if mainName == nil or mainName == "" then
        g.alts[altName] = nil
        return true, "Removed alt tag from " .. altName
    end
    g.alts[altName] = mainName
    return true, ("Tagged %s as alt of %s"):format(altName, mainName)
end

function addon:GetMainOf(name)
    local g = self:GetCurrentGuild()
    if not g then return nil end
    return g.alts[name]
end

function addon:GetAltsOf(mainName)
    local out = {}
    local g = self:GetCurrentGuild()
    if not g then return out end
    for alt, main in pairs(g.alts) do
        if main == mainName then table.insert(out, alt) end
    end
    table.sort(out)
    return out
end

function addon:GetMemberRecord(name)
    local g = self:GetCurrentGuild()
    if not g then return nil end
    return g.members[name]
end

-- =========================================================
-- Slash commands
-- =========================================================
SLASH_GManager1 = "/gm"
SLASH_GManager2 = "/GManager"
SlashCmdList["GManager"] = function(msg)
    msg = msg and msg:match("^%s*(.-)%s*$") or ""
    local lower = msg:lower()

    if msg == "" then
        if addon.UI and addon.UI.Toggle then
            addon.UI:Toggle()
        end
        return
    end

    if lower == "help" then
        print("|cFFFFCC00Guild Manager|r commands:")
        print("  |cffffff00/gm|r                 - toggle the log window")
        print("  |cffffff00/gm setalt <alt> <main>|r")
        print("  |cffffff00/gm unalt <name>|r")
        print("  |cffffff00/gm alts|r             - print all alt mappings")
        print("  |cffffff00/gm clear|r            - clear the event log for this guild")
        print("  |cffffff00/gm debug|r            - toggle debug prints")
        return
    end

    local setalt = msg:match("^[Ss][Ee][Tt][Aa][Ll][Tt]%s+(%S+)%s+(%S+)$")
    if setalt then
        local alt, main = msg:match("^[Ss][Ee][Tt][Aa][Ll][Tt]%s+(%S+)%s+(%S+)$")
        local ok, m = addon:SetAlt(alt, main)
        print("|cFFFFCC00Guild Manager|r: " .. tostring(m))
        if addon.UI and addon.UI.RefreshIfShown then addon.UI:RefreshIfShown() end
        return
    end

    local unalt = msg:match("^[Uu][Nn][Aa][Ll][Tt]%s+(%S+)$")
    if unalt then
        local ok, m = addon:SetAlt(unalt, nil)
        print("|cFFFFCC00Guild Manager|r: " .. tostring(m))
        if addon.UI and addon.UI.RefreshIfShown then addon.UI:RefreshIfShown() end
        return
    end

    if lower == "alts" then
        local g = addon:GetCurrentGuild()
        if not g or not next(g.alts) then
            print("|cFFFFCC00Guild Manager|r: no alt mappings recorded.")
            return
        end
        print("|cFFFFCC00Guild Manager|r alt mappings:")
        for alt, main in pairs(g.alts) do
            print(("  %s -> %s"):format(alt, main))
        end
        return
    end

    if lower == "clear" then
        addon:ClearLog()
        print("|cFFFFCC00Guild Manager|r: event log cleared.")
        if addon.UI and addon.UI.RefreshIfShown then addon.UI:RefreshIfShown() end
        return
    end

    if lower == "debug" then
        ensureDB()
        GManagerCharDB.debug = not GManagerCharDB.debug
        print("|cFFFFCC00Guild Manager|r: debug = " .. tostring(GManagerCharDB.debug))
        return
    end

    print("|cFFFFCC00Guild Manager|r: unknown command. Try /gm help")
end

-- Run db setup at file load so other files can read it safely.
ensureDB()
