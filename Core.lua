-- GManager Core
-- Wrath 3.3.5a native guild roster tracking, event log, alts management.

GManager = GManager or {}
local addon = GManager
addon.version = "1.1.4"

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
    if not GManagerDB.version then GManagerDB.version = 3 end
    if type(GManagerDB.autoInvite) ~= "table" then
        GManagerDB.autoInvite = {
            enabled = false,
            phrase = "",
            groupinv = "",
            replyOn = "Auto-Sending Guild invite ",
            replyOff = "Auto-invites are currently disabled",
            minLvl = 1,
            replyLow = ""
        }
    else
        -- Ensure the group invite phrase field exists if the table already exists
        if GManagerDB.autoInvite.groupinv == nil then
            GManagerDB.autoInvite.groupinv = ""
        end
    end
end

-- =========================================================
-- Macros API (account-wide saved messages bound to a channel)
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
-- Alts Management API
-- =========================================================
function addon:GetMainOf(name)
    local g = self:GetCurrentGuild()
    return g and g.alts and g.alts[name] or nil
end

function addon:GetAltsOf(mainName)
    local g = self:GetCurrentGuild()
    local alts = {}
    if g and g.alts then
        for alt, main in pairs(g.alts) do
            if main == mainName then
                table.insert(alts, alt)
            end
        end
    end
    table.sort(alts)
    return alts
end

function addon:SetAlt(altName, mainName)
    local g = self:GetCurrentGuild()
    if not g then return false, "No active guild data." end
    if not altName or altName == "" then return false, "Invalid alt name." end
    if mainName == "" then mainName = nil end
    
    if mainName then
        if altName == mainName then return false, "A player cannot be their own main." end
        g.alts[altName] = mainName
        return true, ("Tagged %s as alt of %s."):format(altName, mainName)
    else
        g.alts[altName] = nil
        return true, ("Removed alt status from %s."):format(altName)
    end
end

function addon:GetMemberRecord(name)
    local g = self:GetCurrentGuild()
    return g and g.members and g.members[name] or nil
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
    local todayStr = date("%b %d %Y", now)

    guild.pendingLeaves = guild.pendingLeaves or {}

    -- Joins
    for name, info in pairs(new) do
        if not old[name] then
            local m = guild.members[name]
            if guild.pendingLeaves[name] then
                guild.pendingLeaves[name] = nil
            else
                pushLog(guild, {
                    t = now, type = "JOIN", who = name,
                    details = ("Lvl %d %s"):format(info.level, info.rank),
                })
                if not m then
                    m = {}
                    guild.members[name] = m
                    m.joinDate = todayStr
                    m.joinDateExact = true
                end

                if CanEditOfficerNote and CanEditOfficerNote() then
                    local currentNote = info.officerNote or ""
                    local dateTag = "[" .. todayStr .. "]"
                    if not string.match(currentNote, "%[%a%a%a %d%d %d%d%d%d%]") then
                        local newNote = currentNote
                        if currentNote == "" then
                            newNote = dateTag
                        elseif string.len(currentNote) + string.len(dateTag) + 1 <= 30 then
                            newNote = currentNote .. " " .. dateTag
                        end
                        if newNote ~= currentNote and info.index then
                            GuildRosterSetOfficerNote(info.index, newNote)
                        end
                    end
                end
            end
        end
    end

    -- Leaves (Deferred)
    for name in pairs(old) do
        if not new[name] then
            guild.pendingLeaves[name] = guild.pendingLeaves[name] or now
        end
    end

    -- Changes
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
        end

        local m = guild.members[name]
        if not m then m = {}; guild.members[name] = m end
        if n.online then m.lastOnline = now end
        m.lastRank  = n.rank
        m.lastLevel = n.level
        m.classFile = n.classFile
    end
end

-- =========================================================
-- Tiny scheduler via OnUpdate
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
            pcall(fn)
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
-- Group Auto-Invite Feature API
-- =========================================================
addon.groupInviteActive = false
addon.groupInvitePermanent = false

function addon:StartGroupInvite(minutes)
    self.groupInviteActive = true
    print("|cFFFFCC00GManager|r: Group Auto-Invite mode enabled.")
    if not self.groupInvitePermanent then
        delayCall(minutes * 60, function()
            if self.groupInviteActive and not self.groupInvitePermanent then
                self:StopGroupInvite()
            end
        end)
    end
end

function addon:StopGroupInvite()
    self.groupInviteActive = false
    print("|cFFFFCC00GManager|r: Group Auto-Invite mode disabled.")
    if addon.UI and addon.UI.RefreshIfShown then addon.UI:RefreshIfShown() end
end

-- =========================================================
-- Roster Request Helpers
-- =========================================================
function addon:RequestRoster()
    if IsInGuild() then GuildRoster() end
end

function addon:RequestRosterAfterAction()
    delayCall(0.5, function()
        if IsInGuild() then GuildRoster() end
    end)
end

-- =========================================================
-- Coalesced "do a diff" trigger
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

        if snapCount == 0 then return end

        local now = time()
        for name in pairs(guild.members) do
            if not snap[name] then
                guild.pendingLeaves[name] = guild.pendingLeaves[name] or now
            end
        end

        for name, absentSince in pairs(guild.pendingLeaves) do
            if now - absentSince >= LEAVE_GRACE_SECONDS then
                local m = guild.members[name]
                pushLog(guild, {
                    t = absentSince, type = "LEAVE", who = name,
                    details = m and ("%s (Lvl %d)"):format(m.lastRank or "", m.lastLevel or 0) or "",
                })
                guild.pendingLeaves[name] = nil
                guild.members[name] = nil
            end
        end

        if lastSnapshot then
            diffSnapshots(lastSnapshot, snap, guild)
        else
            for name, info in pairs(snap) do
                if guild.pendingLeaves[name] then
                    guild.pendingLeaves[name] = nil
                end
                local m = guild.members[name]
                if not m then
                    guild.members[name] = {
                        lastOnline = info.online and now or nil,
                        lastRank = info.rank,
                        lastLevel = info.level,
                        classFile = info.classFile,
                    }
                end
            end
        end

        lastSnapshot = snap
        if addon.UI and addon.UI.RefreshIfShown then addon.UI:RefreshIfShown() end
    end)
end

-- =========================================================
-- Main Backend Event Listener
-- =========================================================
local backend = CreateFrame("Frame")
backend:RegisterEvent("ADDON_LOADED")
backend:RegisterEvent("PLAYER_LOGIN")
backend:RegisterEvent("GUILD_ROSTER_UPDATE")
backend:RegisterEvent("CHAT_MSG_WHISPER")

backend:SetScript("OnEvent", function(self, event, arg1, arg2)
    if event == "ADDON_LOADED" and arg1 == "GManager" then
        ensureDB()
    elseif event == "PLAYER_LOGIN" then
        if IsInGuild() then GuildRoster() end
    elseif event == "GUILD_ROSTER_UPDATE" then
        if IsInGuild() then scheduleDiff() end
    elseif event == "CHAT_MSG_WHISPER" then
        local msg, sender = arg1, arg2
        
        -- 1. Auto Guild Invite
        if GManagerDB and GManagerDB.autoInvite and GManagerDB.autoInvite.enabled then
            local conf = GManagerDB.autoInvite
            local phrase = conf.phrase or ""
            if phrase ~= "" and msg:lower():find(phrase:lower(), 1, true) then
                GuildInvite(sender)
                if conf.replyOn and conf.replyOn ~= "" then
                    SendChatMessage(conf.replyOn, "WHISPER", nil, sender)
                end
            end
        end
        
        -- 2. Auto Group Invite
        if addon.groupInviteActive then
            local groupPhrase = GManagerDB and GManagerDB.autoInvite and GManagerDB.autoInvite.groupinv or ""
            if groupPhrase ~= "" and msg:lower():find(groupPhrase:lower(), 1, true) then
                InviteUnit(sender)
            end
        end
    end
end)

-- Slash commands
SLASH_GMANAGER1 = "/gmanager"
SLASH_GMANAGER2 = "/gm"
SlashCmdList["GMANAGER"] = function()
    if addon.UI and addon.UI.Toggle then addon.UI:Toggle() end
end
