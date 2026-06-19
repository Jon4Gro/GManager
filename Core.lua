-- GManager Core
-- Wrath 3.3.5a native guild roster tracking, event log, alts management.

GManager = GManager or {}
local addon = GManager
addon.version = "1.3.1" -- 1.3.1: Stronger WhoFrame suppression for silent auto-invite level checks

local LOG_MAX = 15000        -- cap log size per guild to prevent unbounded growth
local SNAPSHOT_DEBOUNCE = 2 -- seconds; coalesce burst GUILD_ROSTER_UPDATE events

local LEAVE_GRACE_SECONDS = 5 * 60  -- reduced to 5 minutes for faster leave logging

local currentGuildKey      -- realm::guildname for the currently active guild
local lastSnapshot         -- previous snapshot used for diffing
local pendingSnapshot      -- coalescing timer-active flag

-- =========================================================
-- SavedVariables bootstrap
-- =========================================================
local function ensureDB()
    if type(GManagerDB)     ~= "table" then GManagerDB     = {} end
    if type(GManagerCharDB) ~= "table" then GManagerCharDB = {} end
    if type(GManagerCharDB.massPromote) ~= "table" then GManagerCharDB.massPromote = {} end
    if GManagerCharDB.openWithGuild == nil then GManagerCharDB.openWithGuild = true end
    if GManagerCharDB.closeWithGuild == nil then GManagerCharDB.closeWithGuild = true end
    if type(GManagerDB.guilds) ~= "table" then GManagerDB.guilds = {} end
    if type(GManagerDB.macros) ~= "table" then GManagerDB.macros = {} end
    if not GManagerDB.version then GManagerDB.version = 3 end
    if not GManagerDB.batchSize then GManagerDB.batchSize = 2 end 
    if type(GManagerDB.autoInvite) ~= "table" then
        GManagerDB.autoInvite = {
            enabled = false,
            phrase = "",
            groupinv = "",
            replyOn = "Auto-Sending Guild invite ",
            replyOff = "Auto-invites are currently disabled",
            minLvl = 1,
            replyLow = "Your level is too low for auto-invite. Please level up first!"
        }
    else
        if GManagerDB.autoInvite.groupinv == nil then GManagerDB.autoInvite.groupinv = "" end
        if GManagerDB.autoInvite.minLvl == nil then GManagerDB.autoInvite.minLvl = 1 end
        if GManagerDB.autoInvite.replyLow == nil then GManagerDB.autoInvite.replyLow = "" end
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
        local name, rank, rankIndex, level, _, zone, note, officerNote, online, _, classFile = GetGuildRosterInfo(i)
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

    for name in pairs(old) do
        if not new[name] then
            guild.pendingLeaves[name] = guild.pendingLeaves[name] or now
        end
    end

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
-- Helper: Multiple Trigger Words separated by '-'
-- =========================================================
local function containsTriggerWord(msg, triggerString)
    if not triggerString or triggerString == "" then return false end
    local lowerMsg = msg:lower()
    for word in string.gmatch(triggerString, "([^%-]+)") do
        word = word:match("^%s*(.-)%s*$") -- trim whitespace
        if word ~= "" and lowerMsg:find(word:lower(), 1, true) then
            return true
        end
    end
    return false
end

-- =========================================================
-- Pre-invite /who level check
-- =========================================================
function addon:ProcessWhoLevelCheck()
    addon.pendingLevelChecks = addon.pendingLevelChecks or {}
    if next(addon.pendingLevelChecks) == nil then return end

    local num = GetNumWhoResults()
    if num == 0 then return end

    local conf = GManagerDB and GManagerDB.autoInvite
    if not conf then 
        addon.pendingLevelChecks = {}
        return 
    end

    local minL = tonumber(conf.minLvl) or 1

    -- Loop through silent who buffer to match the player who whispered us
    for i = 1, num do
        local whoName, _, whoLevelRaw = GetWhoInfo(i)
        if whoName then
            -- Clean the incoming WhoName (strip cross-realm strings, force lowercase)
            local cleanWhoName = string.lower(strsplit("-", whoName))
            
            -- Check if this matches an item in our lookup checklist
            local originalSender = addon.pendingLevelChecks[cleanWhoName]
            
            if originalSender then
                local whoLevel = tonumber(whoLevelRaw) or 0
                addon.pendingLevelChecks[cleanWhoName] = nil -- Clear entry immediately

                if whoLevel >= minL then
                    if conf.replyOn and conf.replyOn ~= "" then
                        SendChatMessage(conf.replyOn, "WHISPER", nil, originalSender)
                    end
                    GuildInvite(originalSender)
                else
                    if conf.replyLow and conf.replyLow ~= "" then
                        SendChatMessage(conf.replyLow, "WHISPER", nil, originalSender)
                    end
                end
            end
        end
    end

    -- After handling our silent level-check /who, hide the Blizzard Who/FriendsFrame
    -- ONLY if it was not already open before we sent the query.
    -- This is the robust fix for the persistent WhoFrame popup on auto-invite triggers.
    if addon._silentWhoFriendsWasShown == false then
        if FriendsFrame and FriendsFrame:IsShown() then
            FriendsFrame:Hide()
        end
        if WhoFrame and WhoFrame:IsShown() then
            WhoFrame:Hide()
        end
    end
    addon._silentWhoFriendsWasShown = nil
    addon._silentWhoWasShown = nil
end

-- =========================================================
-- Macro Spammer Ticker
-- =========================================================
addon.spamTimer = 0
addon.spamInterval = 5
addon.spamActive = false
addon.spamMacros = addon.spamMacros or {}

local spamUpdater = CreateFrame("Frame")
spamUpdater:SetScript("OnUpdate", function(self, elapsed)
    if addon.spamActive and addon.spamInterval and addon.spamInterval > 0 then
        addon.spamTimer = addon.spamTimer + elapsed
        if addon.spamTimer >= (addon.spamInterval * 60) then
            addon.spamTimer = 0
            if GManagerDB and GManagerDB.macros then
                for i = 1, #GManagerDB.macros do
                    if addon.spamMacros[i] then
                        addon:SendMacro(i)
                    end
                end
            end
        end
    end
end)

-- =========================================================
-- Guild Frame Hook (Open/Close with default UI)
-- =========================================================
local function hookGuildFrame()
    if GuildFrame and not GuildFrame.__GManagerHooked then
        GuildFrame.__GManagerHooked = true
        GuildFrame:HookScript("OnShow", function()
            if GManagerCharDB and GManagerCharDB.openWithGuild then
                if addon.UI and addon.UI.Show then addon.UI:Show() end
            end
        end)
        GuildFrame:HookScript("OnHide", function()
            if GManagerCharDB and GManagerCharDB.closeWithGuild then
                if addon.UI and addon.UI.Hide then addon.UI:Hide() end
            end
        end)
    end
end

-- =========================================================
-- Main Backend Event Listener
-- =========================================================
local backend = CreateFrame("Frame")
backend:RegisterEvent("ADDON_LOADED")
backend:RegisterEvent("PLAYER_LOGIN")
backend:RegisterEvent("GUILD_ROSTER_UPDATE")
backend:RegisterEvent("CHAT_MSG_WHISPER")
backend:RegisterEvent("WHO_LIST_UPDATE") 

backend:SetScript("OnEvent", function(self, event, arg1, arg2, arg3, arg4, arg5, arg6, arg7, arg8, arg9, arg10, arg11, arg12)
    if event == "ADDON_LOADED" then
        if arg1 == "GManager" then
            ensureDB()
        elseif arg1 == "Blizzard_GuildUI" then
            hookGuildFrame() 
        end
    elseif event == "PLAYER_LOGIN" then
        hookGuildFrame() 
        if IsInGuild() then GuildRoster() end
    elseif event == "GUILD_ROSTER_UPDATE" then
        if IsInGuild() then scheduleDiff() end
    elseif event == "WHO_LIST_UPDATE" then
        addon:ProcessWhoLevelCheck() 
    elseif event == "CHAT_MSG_WHISPER" then
        local msg, sender = arg1, arg2

        -- 1. Auto Guild Invite
        if GManagerDB and GManagerDB.autoInvite then
            local conf = GManagerDB.autoInvite
            
            -- Check for trigger phrase FIRST
            if conf.phrase and conf.phrase ~= "" and containsTriggerWord(msg, conf.phrase) then
                if conf.enabled then
                    local cleanSender = strsplit("-", sender)
                    
                    addon.pendingLevelChecks = addon.pendingLevelChecks or {}
                    addon.pendingLevelChecks[cleanSender:lower()] = sender
                    
                    -- Record visibility state BEFORE SendWho.
                    -- We track BOTH FriendsFrame (parent social window) and WhoFrame (the tab)
                    -- because on some 3.3.5a clients SendWho can force the whole FriendsFrame open.
                    addon._silentWhoFriendsWasShown = FriendsFrame and FriendsFrame:IsShown() or false
                    addon._silentWhoWasShown = WhoFrame and WhoFrame:IsShown() or false
                    
                    -- FIXED: Direct /who query results to the UI data table instead of the Chat Frame text line
                    SetWhoToUI(1) 
                    -- FIXED: Wrap in exact matching quotes so /who Alex doesn't return Alexander
                    SendWho('n-"' .. cleanSender .. '"')
                else
                    -- OFF-REPLY logic
                    if conf.replyOff and conf.replyOff ~= "" then
                        SendChatMessage(conf.replyOff, "WHISPER", nil, sender)
                    end
                end
            end
        end

        -- 2. Auto Group Invite
        if addon.groupInviteActive then
            local groupPhrase = GManagerDB and GManagerDB.autoInvite and GManagerDB.autoInvite.groupinv or ""
            if containsTriggerWord(msg, groupPhrase) then
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
