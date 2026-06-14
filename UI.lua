-- GManager UI
-- Five tabs: Log, Roster, Alts, Macros, Ranks. Plain Wrath 3.3.5a frame API.
-- No OnKeyDown on Frames, no post-Wrath templates.
-- Added "Refresh List" functionality for the Ranks tab.
-- Added "ONote Empty Newbies" to insert Today Date into OfficerNote if completly Empty

GManager = GManager or {}
GManager.UI = {}
local UI    = GManager.UI
local addon = GManager
local rosterOfflineDaysSearch = ""
-- =========================================================
-- Constants
-- =========================================================
local ROW_HEIGHT = 15
local ROW_COUNT  = 18

-- Per-column widths used by the Roster view (header + each row cell).
-- All values are pixels. The order here MUST match the header build order.
local COL_DEFS = {
    { key = "lvl",    label = "Lvl",         sort = "level",    width = 18  },
    { key = "name",   label = "Name",        sort = "name",     width = 94 },
    { key = "online", label = "Last Online", sort = "online",   width = 71 },
    { key = "join",   label = "Join Date",   sort = "joinDate", width = 71  },
    { key = "rank",   label = "Rank",        sort = "rank",     width = 80 },
    { key = "note",   label = "Note",        sort = "note",     width = 154 },
    { key = "onote",  label = "Officer Note",sort = "onote",    width = 154 },
}
local COL_GAP = 4

local BACKDROP = {
    bgFile   = "Interface\\DialogFrame\\UI-DialogBox-Background",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true, tileSize = 32, edgeSize = 32,
    insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

local PANEL_BACKDROP = {
    bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true, tileSize = 16, edgeSize = 12,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local TYPE_COLOR = {
    SEEN    = "|cffaaaaaa",
    JOIN    = "|cff44ff44",
    LEAVE   = "|cffff5555",
    PROMOTE = "|cffaaff66",
    DEMOTE  = "|cffff8800",
    NOTE    = "|cffff77ff",
    ONOTE   = "|cffcc88ff",
    LEVEL   = "|cff66ccff",
}

local TYPE_LABEL = {
    SEEN    = "Initial",
    JOIN    = "Joined",
    LEAVE   = "Left",
    PROMOTE = "Promoted",
    DEMOTE  = "Demoted",
    NOTE    = "Public Note",
    ONOTE   = "Officer Note",
    LEVEL   = "Leveled",
}

local TYPE_ORDER = { "JOIN", "LEAVE", "PROMOTE", "DEMOTE", "NOTE", "ONOTE", "SEEN" }

local CLASS_COLOR = {
    DEATHKNIGHT = "|cffc41f3b",
    DRUID       = "|cffff7d0a",
    HUNTER      = "|cffabd473",
    MAGE        = "|cff69ccf0",
    PALADIN     = "|cfff58cba",
    PRIEST      = "|cffffffff",
    ROGUE       = "|cfffff569",
    SHAMAN      = "|cff0070de",
    WARLOCK     = "|cff9482c9",
    WARRIOR     = "|cffc79c6e",
}

-- =========================================================
-- UI state
-- =========================================================
local activeView   = "LOG"   -- "LOG", "ROSTER", "ALTS", "MACROS", "RANKS"

-- Macros tab state
local CHANNEL_OPTIONS = { "1","2","3","4","5","6","7","8","9",
                         "GUILD","OFFICER","SAY","PARTY","RAID","YELL" }
local macroSelectedChannel = "GUILD"

-- Log view
local typeFilters = {
    SEEN = true, JOIN = true, LEAVE = true,
    PROMOTE = true, DEMOTE = true,
    NOTE = true, ONOTE = true, LEVEL = false,
}
local logSearchText = ""
local showLineNumbers = true

-- Roster view
local rosterShowOffline    = true
local rosterPlayerSearch   = ""
local rosterNoteSearch     = ""
local rosterSortBy         = "name"   -- "level" | "name" | "online" | "rank"
local rosterSortReverse    = false
local groupAltsWithMain    = false

-- Ranks (Mass Promote) view
local ranksTargetRankIndex = nil
local ranksMinDays         = ""
local ranksMaxOffline      = ""

local frame  -- main frame, lazy-built

-- =========================================================
-- Right-click context menu (Roster rows)
-- =========================================================
local contextMenuFrame

local function showRosterContextMenu(name)

    if not name or name == "" then return end
    if not contextMenuFrame then
        contextMenuFrame = CreateFrame("Frame", "GManagerRosterContextMenu",
                                       UIParent, "UIDropDownMenuTemplate")
    end

    local isSelf = (name == UnitName("player"))
    local canPromote = CanGuildPromote and CanGuildPromote() and not isSelf
    local canDemote  = CanGuildDemote  and CanGuildDemote()  and not isSelf



    local menu = {
        { text = name, isTitle = true, notCheckable = true },
        {
            text = addon:IsWhitelisted(name) and "Remove from Whitelist" or "Add to Whitelist",
            notCheckable = true,
            func = function()
            addon:ToggleWhitelist(name)
            UI:Refresh()
            end,
        },
        {
            text = "Promote",
            notCheckable = true,
            disabled = not canPromote,
            func = function()
                StaticPopupDialogs["GManager_CONFIRM_PROMOTE"] = {
                    text = "Promote |cffffff00"..name.."|r by one rank?",
                    button1 = "Promote", button2 = "Cancel",
                    OnAccept = function()
                        if GuildPromote then GuildPromote(name) end
                        if addon.RequestRosterAfterAction then addon:RequestRosterAfterAction()
                        elseif addon.RequestRoster then addon:RequestRoster() else GuildRoster() end
                    end,
                    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
                }
                StaticPopup_Show("GManager_CONFIRM_PROMOTE")
            end,
        },

        {
            text = "Demote",
            notCheckable = true,
            disabled = not canDemote,
            func = function()
                StaticPopupDialogs["GManager_CONFIRM_DEMOTE"] = {
                    text = "Demote |cffffff00"..name.."|r by one rank?",
                    button1 = "Demote", button2 = "Cancel",
                    OnAccept = function()
                        if GuildDemote then GuildDemote(name) end
                        if addon.RequestRosterAfterAction then addon:RequestRosterAfterAction()
                        elseif addon.RequestRoster then addon:RequestRoster() else GuildRoster() end
                    end,
                    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
                }
                StaticPopup_Show("GManager_CONFIRM_DEMOTE")
            end,
        },
        {
            text = "Whisper",
            notCheckable = true,
            disabled = isSelf,
            func = function()
                if ChatFrame_OpenChat then
                    ChatFrame_OpenChat("/w "..name.." ", DEFAULT_CHAT_FRAME)
                end
            end,
        },
        {
            text = "Invite to Group",
            notCheckable = true,
            disabled = isSelf,
            func = function() if InviteUnit then InviteUnit(name) end end,
        },
        { text = "Cancel", notCheckable = true, func = function() end },
    }

    EasyMenu(menu, contextMenuFrame, "cursor", 0, 0, "MENU")
end

-- =========================================================
-- Helpers
-- =========================================================
local function colorize(typeKey, text)
    return (TYPE_COLOR[typeKey] or "|cffffffff") .. text .. "|r"
end

local function fmtDateLong(epoch)
    if not epoch then return "?" end
    return date("%d %b '%y %H:%M", epoch)
end

local function fmtSince(epoch)
    if not epoch then return "?" end
    local d = time() - epoch
    if d < 60     then return "online" end
    if d < 3600   then return ("%d min"):format(math.floor(d / 60)) end
    if d < 86400  then return ("%d hrs"):format(math.floor(d / 3600)) end
    if d < 604800 then return ("%d days"):format(math.floor(d / 86400)) end
    if d < 2592000 then
        local weeks = math.floor(d / 604800)
        local days = math.floor((d - weeks * 604800) / 86400)
        if days > 0 then return ("%d wks, %d days"):format(weeks, days) end
        return ("%d wks"):format(weeks)
    end
    if d < 31536000 then
        local months = math.floor(d / 2592000)
        local days = math.floor((d - months * 2592000) / 86400)
        if days > 0 then return ("%d mos, %d days"):format(months, days) end
        return ("%d mos"):format(months)
    end
    local years = math.floor(d / 31536000)
    return ("%d yrs"):format(years)
end

local function lastSeenColor(epoch, online)
    if online then return "|cff44ff44" end
    if not epoch then return "|cff888888" end
    local d = time() - epoch
    if d < 86400   then return "|cff99ff99" end  -- < 1 day
    if d < 604800  then return "|cffffffff" end  -- < 7 days
    if d < 2592000 then return "|cffffff66" end  -- < 30 days
    if d < 7776000 then return "|cffffaa00" end  -- < 90 days
    return "|cffff4444"
end

local function classColor(classFile, name)
    return (CLASS_COLOR[classFile or ""] or "|cffeeeeee") .. (name or "?") .. "|r"
end

local function lowerSafe(s) return (s or ""):lower() end

local function ProcessBatch(actionName, list, actionFunc)
    if not list or #list == 0 then
        print("|cff00ff00GManager:|r No members in selection for " .. actionName)
        return
    end

    local batchSize = 15
    local total = #list
    local currentIdx = 1
    local batchNum = 1
    local totalBatches = math.ceil(total / batchSize)

    local processor = CreateFrame("Frame")
    local timer = 0

    processor:SetScript("OnUpdate", function(self, elapsed)
        timer = timer + elapsed
        -- Trigger immediately on first run, then every 1.0 seconds
        if timer >= 1.0 or currentIdx == 1 then
            timer = 0
            local endIdx = math.min(currentIdx + batchSize - 1, total)

            for i = currentIdx, endIdx do
                if list[i] and list[i].name then
                    actionFunc(list[i].name)
                end
            end

            print("|cff00ff00GManager:|r " .. actionName .. " Batch " .. batchNum .. " of " .. totalBatches .. " Done")

            currentIdx = endIdx + 1
            batchNum = batchNum + 1

            if currentIdx > total then
                self:SetScript("OnUpdate", nil)
                print("|cff00ff00GManager:|r All " .. actionName .. " operations completed.")
                if GManager.RequestRosterAfterAction then GManager:RequestRosterAfterAction()
                elseif GManager.RequestRoster then GManager:RequestRoster() else GuildRoster() end
            end
        end
    end)
end

-- =========================================================
-- Window build (lazy)
-- =========================================================
local function build()
    if frame then return frame end

    local f = CreateFrame("Frame", "GManagerMainFrame", UIParent)
    f:SetSize(900, 480)
    f:SetPoint("CENTER")
    f:SetBackdrop(BACKDROP)
    f:SetBackdropColor(0, 0, 0, 1)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop",  f.StopMovingOrSizing)
    f:Hide()

    -- ===== Header =====
    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", -0, -10)
    title:SetText("|cFFFFCC00GManager|r")
    f.title = title

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("TOPLEFT", 16, -24)
    f.subtitle = subtitle

    local rightHeader = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rightHeader:SetPoint("TOPRIGHT", -34, -22)
    rightHeader:SetJustifyH("RIGHT")
    f.rightHeader = rightHeader

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    -- ===== Tabs =====
    f.tabButtons = {}
    local function makeViewBtn(label, viewKey)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(86, 22)
        b:SetText(label)
        b:SetScript("OnClick", function()
            activeView = viewKey
            UI:Refresh()
        end)
        f.tabButtons[viewKey] = b
        return b
    end
    f.tabLog    = makeViewBtn("Log",    "LOG")
    f.tabRoster = makeViewBtn("Roster", "ROSTER")
    f.tabAlts   = makeViewBtn("Alts",   "ALTS")
    f.tabMacros = makeViewBtn("Macros", "MACROS")
    f.tabRanks  = makeViewBtn("Ranks",  "RANKS")
    
    f.tabLog:SetPoint("TOPLEFT", 16, -44)
    f.tabRoster:SetPoint("TOPLEFT", f.tabLog,    "TOPRIGHT", 4, 0)
    f.tabAlts:SetPoint("TOPLEFT",   f.tabRoster, "TOPRIGHT", 4, 0)
    f.tabMacros:SetPoint("TOPLEFT", f.tabAlts,   "TOPRIGHT", 4, 0)
    f.tabRanks:SetPoint("TOPLEFT",  f.tabMacros, "TOPRIGHT", 4, 0)

    -- ===== Log view controls =====
    local logSearch = CreateFrame("EditBox", "GManagerLogSearch", f, "InputBoxTemplate")
    logSearch:SetSize(220, 20)
    logSearch:SetPoint("TOPLEFT", f.tabLog, "BOTTOMLEFT", 8, -18)
    logSearch:SetAutoFocus(false)
    logSearch:SetScript("OnTextChanged", function(self)
        logSearchText = self:GetText() or ""
        UI:Refresh()
    end)
    logSearch:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    logSearch:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
    f.logSearch = logSearch

    local logSearchLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    logSearchLabel:SetPoint("BOTTOMLEFT", logSearch, "TOPLEFT", -4, 1)
    logSearchLabel:SetText("Search Filter")
    f.logSearchLabel = logSearchLabel

    f.filterPanel = CreateFrame("Frame", nil, f)
    f.filterPanel:SetSize(150, 294)
    f.filterPanel:SetPoint("TOPRIGHT", -18, -130)
    f.filterPanel:SetBackdrop(PANEL_BACKDROP)
    f.filterPanel:SetBackdropColor(0, 0, 0, 0.6)

    local fpTitle = f.filterPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    fpTitle:SetPoint("TOP", 0, -8)
    fpTitle:SetText("Display Changes")

    f.filterChecks = {}
    local cbY = -30
    for _, key in ipairs(TYPE_ORDER) do
        local cb = CreateFrame("CheckButton", "GManagerFC_" .. key, f.filterPanel, "OptionsBaseCheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("TOPLEFT", 10, cbY)
        cb:SetChecked(typeFilters[key])
        local labelKey = key
        cb:SetScript("OnClick", function(self)
            typeFilters[labelKey] = self:GetChecked() and true or false
            UI:Refresh()
        end)
        local lbl = f.filterPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        lbl:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        lbl:SetText(colorize(key, TYPE_LABEL[key] or key))
        f.filterChecks[key] = cb
        cbY = cbY - 22
    end

    local checkAll = CreateFrame("Button", nil, f.filterPanel, "UIPanelButtonTemplate")
    checkAll:SetSize(60, 20)
    checkAll:SetText("All")
    checkAll:SetPoint("BOTTOMLEFT", 10, 10)
    checkAll:SetScript("OnClick", function()
        for _, k in ipairs(TYPE_ORDER) do typeFilters[k] = true end
        for _, cb in pairs(f.filterChecks) do cb:SetChecked(true) end
        UI:Refresh()
    end)
    local clearAll = CreateFrame("Button", nil, f.filterPanel, "UIPanelButtonTemplate")
    clearAll:SetSize(60, 20)
    clearAll:SetText("None")
    clearAll:SetPoint("BOTTOMRIGHT", -10, 10)
    clearAll:SetScript("OnClick", function()
        for _, k in ipairs(TYPE_ORDER) do typeFilters[k] = false end
        for _, cb in pairs(f.filterChecks) do cb:SetChecked(false) end
        UI:Refresh()
    end)

    -- ===== Roster view controls =====
    f.rosterShowOfflineCB = CreateFrame("CheckButton", "GManagerShowOffline", f, "OptionsBaseCheckButtonTemplate")
    f.rosterShowOfflineCB:SetSize(20, 20)
    f.rosterShowOfflineCB:SetPoint("TOPLEFT", f.tabLog, "BOTTOMLEFT", 0, -18)
    f.rosterShowOfflineCB:SetChecked(rosterShowOffline)
    f.rosterShowOfflineCB:SetScript("OnClick", function(self)
        rosterShowOffline = self:GetChecked() and true or false
        UI:Refresh()
    end)
    f.rosterShowOfflineLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.rosterShowOfflineLabel:SetPoint("LEFT", f.rosterShowOfflineCB, "RIGHT", 2, 0)
    f.rosterShowOfflineLabel:SetText("Show Offline")

    local rosterPSearch = CreateFrame("EditBox", "GManagerRosterPSearch", f, "InputBoxTemplate")
    rosterPSearch:SetSize(140, 20)
    rosterPSearch:SetPoint("LEFT", f.rosterShowOfflineLabel, "RIGHT", 100, 0)
    rosterPSearch:SetAutoFocus(false)
    rosterPSearch:SetScript("OnTextChanged", function(self)
        rosterPlayerSearch = self:GetText() or ""
        UI:Refresh()
    end)
    rosterPSearch:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    rosterPSearch:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
    f.rosterPSearch = rosterPSearch

    local rosterPSearchLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rosterPSearchLabel:SetPoint("BOTTOMLEFT", rosterPSearch, "TOPLEFT", -4, 1)
    rosterPSearchLabel:SetText("Player Search")
    f.rosterPSearchLabel = rosterPSearchLabel

    local rosterNSearch = CreateFrame("EditBox", "GManagerRosterNSearch", f, "InputBoxTemplate")
    rosterNSearch:SetSize(140, 20)
    rosterNSearch:SetPoint("LEFT", rosterPSearch, "RIGHT", 80, 0)
    rosterNSearch:SetAutoFocus(false)
    rosterNSearch:SetScript("OnTextChanged", function(self)
        rosterNoteSearch = self:GetText() or ""
        UI:Refresh()
    end)
    rosterNSearch:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    rosterNSearch:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
    f.rosterNSearch = rosterNSearch

    local rosterNSearchLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rosterNSearchLabel:SetPoint("BOTTOMLEFT", rosterNSearch, "TOPLEFT", -4, 1)
    rosterNSearchLabel:SetText("Note Search")
    f.rosterNSearchLabel = rosterNSearchLabel

    local rosterOffDaysInput = CreateFrame("EditBox", "GManagerRosterOffDays", f, "InputBoxTemplate")
    rosterOffDaysInput:SetSize(40, 20)
    rosterOffDaysInput:SetPoint("LEFT", rosterNSearch, "RIGHT", 80, 0)
    rosterOffDaysInput:SetAutoFocus(false)
    rosterOffDaysInput:SetNumeric(true)
    rosterOffDaysInput:SetScript("OnTextChanged", function(self)
        rosterOfflineDaysSearch = self:GetText() or ""
        UI:Refresh()
    end)
    rosterOffDaysInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    rosterOffDaysInput:SetScript("OnEnterPressed",  function(self) self:ClearFocus() end)
    f.rosterOffDaysInput = rosterOffDaysInput

    local rosterOffDaysLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rosterOffDaysLabel:SetPoint("BOTTOMLEFT", rosterOffDaysInput, "TOPLEFT", -4, 1)
    rosterOffDaysLabel:SetText("> Days Offline")
    f.rosterOffDaysLabel = rosterOffDaysLabel

    f.rosterONoteEmptyBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.rosterONoteEmptyBtn:SetSize(140, 22)
    f.rosterONoteEmptyBtn:SetPoint("LEFT", f.rosterOffDaysLabel, "Left", -30, -39)
    f.rosterONoteEmptyBtn:SetText("ONote Empty Newbies")
    f.rosterONoteEmptyBtn:SetScript("OnClick", function()
        local list = {}
        for i = 1, GetNumGuildMembers() do
            local name, _, _, _, _, _, _, onote = GetGuildRosterInfo(i)
            -- Target only members whose Officer Note is strictly empty
            if name and (not onote or onote == "") then
                table.insert(list, {name = name})
            end
        end

        if #list == 0 then
            print("|cff00ff00GManager:|r No members with empty Officer Notes.")
            return
        end

        local todayStr = date("%b %d %Y")
        local dateTag = "[" .. todayStr .. "]"

        StaticPopupDialogs["GManager_CONFIRM_ONOTE_EMPTY"] = {
            text = "Insert today's date " .. dateTag .. " for |cffffff00" .. #list .. "|r members?\n(Max 15 per second)",
            button1 = "Proceed",
            button2 = "Cancel",
            OnAccept = function()
                ProcessBatch("ONote Empty", list, function(name)
                    -- We must find the index again as GuildRosterSetOfficerNote requires index
                    for i = 1, GetNumGuildMembers() do
                        if GetGuildRosterInfo(i) == name then
                            GuildRosterSetOfficerNote(i, dateTag)
                            break
                        end
                    end
                end)
            end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        StaticPopup_Show("GManager_CONFIRM_ONOTE_EMPTY")
    end)

    -- The Mass Kick Button
    f.rosterMassKickBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.rosterMassKickBtn:SetSize(130, 26)
    f.rosterMassKickBtn:SetPoint("LEFT", rosterNSearchLabel, "LEFT", 22, -366)
    f.rosterMassKickBtn:SetText("Mass Kick List")
    f.rosterMassKickBtn:SetScript("OnClick", function()
        local rows = addon.RosterRowsCache or {}
        if #rows == 0 or rosterShowOffline == false then
            if rosterShowOffline == false then
                print("|cff00ff00GManager:|r No Offline Selection on, Action aborted ")
            end
            return
        end

        StaticPopupDialogs["GManager_CONFIRM_MASS_KICK"] = {
            text = "WARNING: Kick |cffffff00" .. #rows .. "|r currently filtered members?\n(Max 15 per second)",
            button1 = "KICK ALL",
            button2 = "Cancel",
            OnAccept = function()
                StaticPopupDialogs["GManager_CONFIRM_MASS_KICK_2"] = {
                    text = "SECOND CONFIRMATION: Are you absolutely sure? This cannot be undone.",
                    button1 = "YES, KICK",
                    button2 = "Cancel",
                    OnAccept = function()
                    ProcessBatch("Mass Kick", rows, function(name)
                    if not addon:IsWhitelisted(name) then -- Whitelist check
                        if GuildUninvite then GuildUninvite(name) end
                            end
                        end)
                    end,
                    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
                }
                StaticPopup_Show("GManager_CONFIRM_MASS_KICK_2")
            end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        StaticPopup_Show("GManager_CONFIRM_MASS_KICK")
    end)

    -- ===== Ranks (Mass Promote) view controls =====
    f.ranksHeaderPanel = CreateFrame("Frame", nil, f)
    f.ranksHeaderPanel:SetSize(860, 44)
    f.ranksHeaderPanel:SetPoint("TOPLEFT", f.tabLog, "BOTTOMLEFT", 0, -10)
    
    f.ranksRankLabel = f.ranksHeaderPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.ranksRankLabel:SetPoint("TOPLEFT", 4, -10)
    f.ranksRankLabel:SetText("Rank to Promote FROM:")
    
    f.ranksRankPrev = CreateFrame("Button", nil, f.ranksHeaderPanel, "UIPanelButtonTemplate")
    f.ranksRankPrev:SetSize(24, 22)
    f.ranksRankPrev:SetText("<")
    f.ranksRankPrev:SetPoint("TOPLEFT", f.ranksRankLabel, "RIGHT", 4, 10)
    
    f.ranksRankDisplay = f.ranksHeaderPanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.ranksRankDisplay:SetPoint("LEFT", f.ranksRankPrev, "RIGHT", 10, 0)
    f.ranksRankDisplay:SetWidth(80)
    f.ranksRankDisplay:SetJustifyH("CENTER")
    f.ranksRankDisplay:SetText("Loading...")
    
    f.ranksRankNext = CreateFrame("Button", nil, f.ranksHeaderPanel, "UIPanelButtonTemplate")
    f.ranksRankNext:SetSize(24, 22)
    f.ranksRankNext:SetText(">")
    f.ranksRankNext:SetPoint("LEFT", f.ranksRankDisplay, "RIGHT", 10, 0)

    local function updateRankDisplay()
        local maxRanks = GuildControlGetNumRanks() or 0
        if maxRanks == 0 then
            f.ranksRankDisplay:SetText("Loading...")
            return
        end
        if not ranksTargetRankIndex then
            ranksTargetRankIndex = maxRanks - 1
        end
        if ranksTargetRankIndex < 1 then ranksTargetRankIndex = 1 end
        if ranksTargetRankIndex > maxRanks - 1 then ranksTargetRankIndex = maxRanks - 1 end
        
        f.ranksRankDisplay:SetText(GuildControlGetRankName(ranksTargetRankIndex + 1) or "?")
    end

    f.ranksRankPrev:SetScript("OnClick", function()
        ranksTargetRankIndex = (ranksTargetRankIndex or 1) - 1
        local maxRanks = GuildControlGetNumRanks() or 0
        if ranksTargetRankIndex < 1 then ranksTargetRankIndex = maxRanks - 1 end
        updateRankDisplay()
        UI:Refresh()
    end)
    
    f.ranksRankNext:SetScript("OnClick", function()
        ranksTargetRankIndex = (ranksTargetRankIndex or 1) + 1
        local maxRanks = GuildControlGetNumRanks() or 0
        if ranksTargetRankIndex > maxRanks - 1 then ranksTargetRankIndex = 1 end
        updateRankDisplay()
        UI:Refresh()
    end)

    f.ranksDaysJoinInput = CreateFrame("EditBox", "GManagerRanksDaysJoin", f.ranksHeaderPanel, "InputBoxTemplate")
    f.ranksDaysJoinInput:SetSize(60, 20)
    f.ranksDaysJoinInput:SetPoint("LEFT", f.ranksRankNext, "RIGHT", 60, 0)
    f.ranksDaysJoinInput:SetAutoFocus(false)
    f.ranksDaysJoinInput:SetNumeric(true)
    f.ranksDaysJoinInput:SetText(ranksMinDays)
    f.ranksDaysJoinInput:SetScript("OnTextChanged", function(self) ranksMinDays = self:GetText(); UI:Refresh() end)
    
    f.ranksDaysJoinLabel = f.ranksHeaderPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.ranksDaysJoinLabel:SetPoint("BOTTOMLEFT", f.ranksDaysJoinInput, "TOPLEFT", -4, 2)
    f.ranksDaysJoinLabel:SetText(" Min Days Joined")
    
    f.ranksMaxOfflineInput = CreateFrame("EditBox", "GManagerRanksMaxOffline", f.ranksHeaderPanel, "InputBoxTemplate")
    f.ranksMaxOfflineInput:SetSize(60, 20)
    f.ranksMaxOfflineInput:SetPoint("LEFT", f.ranksDaysJoinInput, "RIGHT", 60, 0)
    f.ranksMaxOfflineInput:SetAutoFocus(false)
    f.ranksMaxOfflineInput:SetNumeric(true)
    f.ranksMaxOfflineInput:SetText(ranksMaxOffline)
    f.ranksMaxOfflineInput:SetScript("OnTextChanged", function(self) ranksMaxOffline = self:GetText(); UI:Refresh() end)
    
    f.ranksMaxOfflineLabel = f.ranksHeaderPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.ranksMaxOfflineLabel:SetPoint("BOTTOMLEFT", f.ranksMaxOfflineInput, "TOPLEFT", -4, 2)
    f.ranksMaxOfflineLabel:SetText("Max Offline Days (Exclude)")
--[[
    f.ranksRefreshBtn = CreateFrame("Button", nil, f.ranksHeaderPanel, "UIPanelButtonTemplate")
    f.ranksRefreshBtn:SetSize(70, 26)
    f.ranksRefreshBtn:SetPoint("LEFT", f.ranksMaxOfflineInput, "RIGHT", 20, 0)
    f.ranksRefreshBtn:SetText("Refresh")
    f.ranksRefreshBtn:SetScript("OnClick", function() UI:Refresh() end)
]]
    -- FIXED: f.ranksPromoteBtn defined before f.ranksDateUnkBtn anchors to it
    f.ranksPromoteBtn = CreateFrame("Button", nil, f.ranksHeaderPanel, "UIPanelButtonTemplate")
    f.ranksPromoteBtn:SetSize(130, 26)
    f.ranksPromoteBtn:SetPoint("LEFT", f.ranksMaxOfflineInput , "LEFT", -20, -350)
    f.ranksPromoteBtn:SetText("Mass Promote this List")
    f.ranksPromoteBtn:SetScript("OnClick", function()
        local rows = addon.RanksRowsCache or {}
        if #rows == 0 then
            print("|cff00ff00GManager:|r No One to Promote in Selection")
            return
        end

        StaticPopupDialogs["GManager_CONFIRM_MASS_PROMOTE"] = {
            text = "Are you sure you want to promote these |cffffff00" .. #rows .. "|r members?\nThis will process sequentially at 15 per second.",
            button1 = "Promote All",
            button2 = "Cancel",
            OnAccept = function()
            ProcessBatch("Mass Promote", rows, function(name)
            if not addon:IsWhitelisted(name) then -- Whitelist check
                if GuildPromote then GuildPromote(name) end
                    end
                end)
            end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        StaticPopup_Show("GManager_CONFIRM_MASS_PROMOTE")
    end)

    -- Column header strip (Roster & Ranks modes)
    f.colHeader = CreateFrame("Frame", nil, f)
    f.colHeader:SetHeight(20)
    f.colHeader:SetPoint("TOPLEFT", 16, -106)
    f.colHeader:SetPoint("RIGHT", -18, 0)

    local function makeHeader(def)
        local b = CreateFrame("Button", nil, f.colHeader)
        b:SetSize(def.width, 20)
        b:SetNormalFontObject("GameFontNormal")
        b:SetHighlightFontObject("GameFontHighlight")
        b:SetText(def.label)
        b:GetFontString():SetJustifyH("LEFT")
        b:GetFontString():ClearAllPoints()
        b:GetFontString():SetPoint("LEFT", b, "LEFT", 0, 0)
        b:GetFontString():SetWidth(def.width)
        local sortKey = def.sort
        b:SetScript("OnClick", function()
            if rosterSortBy == sortKey then
                rosterSortReverse = not rosterSortReverse
            else
                rosterSortBy = sortKey
                rosterSortReverse = false
            end
            UI:Refresh()
        end)
        return b
    end

    f.colHeaderBtns = {}
    local prev
    for _, def in ipairs(COL_DEFS) do
        local b = makeHeader(def)
        if prev then
            b:SetPoint("LEFT", prev, "RIGHT", COL_GAP, 0)
        else
            b:SetPoint("LEFT", 0, 0)
        end
        f.colHeaderBtns[def.key] = b
        prev = b
    end

    -- ===== List panel + scroll =====
    f.listPanel = CreateFrame("Frame", nil, f)
    f.listPanel:SetPoint("TOPLEFT", 16, -130)
    f.listPanel:SetPoint("BOTTOMRIGHT", -180, 56)
    f.listPanel:SetBackdrop(PANEL_BACKDROP)
    f.listPanel:SetBackdropColor(0, 0, 0, 0.6)

    local scroll = CreateFrame("ScrollFrame", "GManagerListScroll", f.listPanel, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 6, -6)
    scroll:SetPoint("BOTTOMRIGHT", -28, 6)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, ROW_HEIGHT, function() UI:Refresh() end)
    end)
    f.scroll = scroll

    -- Row pool
    f.rows = {}
    f.rowCells = {}
    f.rowMacroBtns = {}
    f.rowClickBtns = {}
    for i = 1, ROW_COUNT do
        local rowY = -((i - 1) * ROW_HEIGHT) - 2

        local row = f.listPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 4, rowY)
        row:SetPoint("RIGHT",   scroll, "RIGHT",  -4, 0)
        row:SetHeight(ROW_HEIGHT)
        row:SetJustifyH("LEFT")
        f.rows[i] = row

        local cells = {}
        local prevCell
        for _, def in ipairs(COL_DEFS) do
            local fs = f.listPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            fs:SetWidth(def.width)
            fs:SetHeight(ROW_HEIGHT)
            fs:SetJustifyH("LEFT")
            fs:SetWordWrap(false)
            if prevCell then
                fs:SetPoint("LEFT", prevCell, "RIGHT", COL_GAP, 0)
            else
                fs:SetPoint("TOPLEFT", scroll, "TOPLEFT", 4, rowY)
            end
            cells[def.key] = fs
            prevCell = fs
        end
        f.rowCells[i] = cells

        local delBtn = CreateFrame("Button", nil, f.listPanel, "UIPanelButtonTemplate")
        delBtn:SetSize(46, ROW_HEIGHT - 1)
        delBtn:SetText("Del")
        delBtn:SetPoint("RIGHT", scroll, "RIGHT", -4, 0)
        delBtn:SetPoint("TOP",   scroll, "TOP",    0, rowY)
        delBtn:Hide()

        local sendBtn = CreateFrame("Button", nil, f.listPanel, "UIPanelButtonTemplate")
        sendBtn:SetSize(50, ROW_HEIGHT - 1)
        sendBtn:SetText("Send")
        sendBtn:SetPoint("RIGHT", delBtn, "LEFT", -3, 0)
        sendBtn:Hide()

        f.rowMacroBtns[i] = { send = sendBtn, del = delBtn }

        local clickBtn = CreateFrame("Button", nil, f.listPanel)
        clickBtn:SetPoint("TOPLEFT",     scroll, "TOPLEFT",  2, rowY)
        clickBtn:SetPoint("TOPRIGHT",    scroll, "TOPRIGHT", -2, rowY)
        clickBtn:SetHeight(ROW_HEIGHT)
        clickBtn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        clickBtn:EnableMouse(true)
        local hl = clickBtn:CreateTexture(nil, "HIGHLIGHT")
        hl:SetTexture("Interface\\Buttons\\WHITE8X8")
        hl:SetVertexColor(1, 1, 1, 0.08)
        hl:SetAllPoints(clickBtn)
        clickBtn:Hide()
        f.rowClickBtns[i] = clickBtn
    end

    -- ===== Alts view inputs =====
    f.altInputAlt  = CreateFrame("EditBox", "GManagerAltInput",  f, "InputBoxTemplate")
    f.altInputMain = CreateFrame("EditBox", "GManagerMainInput", f, "InputBoxTemplate")
    f.altInputAlt:SetSize(120, 20)
    f.altInputMain:SetSize(120, 20)
    f.altInputAlt:SetPoint("BOTTOMLEFT",  24, 22)
    f.altInputMain:SetPoint("LEFT", f.altInputAlt, "RIGHT", 12, 0)
    f.altInputAlt:SetAutoFocus(false)
    f.altInputMain:SetAutoFocus(false)
    f.altInputAlt:SetScript("OnEscapePressed",  f.altInputAlt.ClearFocus)
    f.altInputMain:SetScript("OnEscapePressed", f.altInputMain.ClearFocus)

    f.altInputAltLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.altInputAltLabel:SetPoint("BOTTOMLEFT", f.altInputAlt, "TOPLEFT", 0, 2)
    f.altInputAltLabel:SetText("Alt name")
    f.altInputMainLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.altInputMainLabel:SetPoint("BOTTOMLEFT", f.altInputMain, "TOPLEFT", 0, 2)
    f.altInputMainLabel:SetText("Main name")

    f.altBtnSet = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.altBtnSet:SetSize(60, 22)
    f.altBtnSet:SetText("Set")
    f.altBtnSet:SetPoint("LEFT", f.altInputMain, "RIGHT", 8, 0)
    f.altBtnSet:SetScript("OnClick", function()
        local a = f.altInputAlt:GetText()
        local m = f.altInputMain:GetText()
        if a and a ~= "" and m and m ~= "" then
            local ok, msg = addon:SetAlt(a, m)
            print("|cFFFFCC00GManager|r: " .. tostring(msg))
            f.altInputAlt:SetText("")
            f.altInputMain:SetText("")
            UI:Refresh()
        end
    end)

    f.altBtnUnset = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.altBtnUnset:SetSize(60, 22)
    f.altBtnUnset:SetText("Unset")
    f.altBtnUnset:SetPoint("LEFT", f.altBtnSet, "RIGHT", 4, 0)
    f.altBtnUnset:SetScript("OnClick", function()
        local a = f.altInputAlt:GetText()
        if a and a ~= "" then
            local ok, msg = addon:SetAlt(a, nil)
            print("|cFFFFCC00GManager|r: " .. tostring(msg))
            f.altInputAlt:SetText("")
            UI:Refresh()
        end
    end)

    -- ===== Macros view: compose form =====
    f.macroMsgLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.macroMsgLabel:SetPoint("TOPLEFT", f.tabLog, "BOTTOMLEFT", 0, -6)
    f.macroMsgLabel:SetText("Message  |cff888888(saves account-wide, max ~255 chars)|r")

    f.macroMsgBg = CreateFrame("Frame", nil, f)
    f.macroMsgBg:SetPoint("TOPLEFT",  f.macroMsgLabel, "BOTTOMLEFT", 0, -2)
    f.macroMsgBg:SetSize(560, 44)
    f.macroMsgBg:SetBackdrop(PANEL_BACKDROP)
    f.macroMsgBg:SetBackdropColor(0, 0, 0, 0.7)
    f.macroMsgBg:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    f.macroMsg = CreateFrame("EditBox", "GManagerMacroMsg", f.macroMsgBg)
    f.macroMsg:SetFontObject("ChatFontSmall")
    f.macroMsg:SetAutoFocus(false)
    f.macroMsg:SetMultiLine(true)
    f.macroMsg:SetMaxLetters(255)
    f.macroMsg:SetPoint("TOPLEFT",     6, -4)
    f.macroMsg:SetPoint("BOTTOMRIGHT", -6, 4)
    f.macroMsg:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    f.macroChanLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.macroChanLabel:SetPoint("TOPLEFT", f.macroMsgBg, "BOTTOMLEFT", 0, -6)
    f.macroChanLabel:SetText("Channel:")

    f.macroChanBtns = {}
    local prevChanBtn
    for _, opt in ipairs(CHANNEL_OPTIONS) do
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        local width = #opt > 2 and 56 or 26
        b:SetSize(width, 20)
        b:SetText(opt)
        if prevChanBtn then
            b:SetPoint("LEFT", prevChanBtn, "RIGHT", 2, 0)
        else
            b:SetPoint("LEFT", f.macroChanLabel, "RIGHT", 6, 0)
        end
        local choice = opt
        b:SetScript("OnClick", function()
            macroSelectedChannel = choice
            UI:Refresh()
        end)
        f.macroChanBtns[opt] = b
        prevChanBtn = b
    end

    f.macroSaveBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.macroSaveBtn:SetSize(80, 22)
    f.macroSaveBtn:SetText("Save Macro")
    f.macroSaveBtn:SetPoint("TOPLEFT", f.macroChanLabel, "BOTTOMLEFT", 0, -28)
    f.macroSaveBtn:SetScript("OnClick", function()
        local text = f.macroMsg:GetText() or ""
        local ok, msg = addon:AddMacro(macroSelectedChannel, text)
        if ok then
            print("|cFFFFCC00GManager|r: macro saved.")
            f.macroMsg:SetText("")
            f.macroMsg:ClearFocus()
        else
            print("|cFFFFCC00GManager|r: " .. tostring(msg))
        end
        UI:Refresh()
    end)
    -- ===== Auto-Invite Settings (Bottom of Macros View) =====
    -- Raised from 40 to 115 to give the cascading rows room to breathe
    f.autoInvLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.autoInvLabel:SetPoint("BOTTOMLEFT", 18, 40)
    f.autoInvLabel:SetText("Auto Guild Invite")

    -- Fixed: Anchored to the RIGHT of the label instead of overlapping on the LEFT
    f.autoInvCB = CreateFrame("CheckButton", "GManagerAutoInvCB", f, "OptionsBaseCheckButtonTemplate")
    f.autoInvCB:SetSize(24, 24)
    f.autoInvCB:SetPoint("LEFT", f.autoInvLabel, "BOTTOMLEFT", 0, -13)
    f.autoInvCB:SetScript("OnClick", function(self) GManagerDB.autoInvite.enabled = self:GetChecked(); UI:Refresh() end)

    f.autoInvCBLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.autoInvCBLabel:SetPoint("LEFT", f.autoInvCB, "RIGHT", 2, 1)
    f.autoInvCBLabel:SetText("Enable")

    -- Helper to create EditBoxes (Updated to support flexible relative anchoring points)
    local function makeAutoInvEditBox(name, labelTxt, width, anchorFrame, relPoint, x, y, dbKey)
    local bg = CreateFrame("Frame", nil, f)
    bg:SetPoint("TOPLEFT", anchorFrame, relPoint, x, y)
    bg:SetSize(width, 22)
    bg:SetBackdrop(PANEL_BACKDROP)
    bg:SetBackdropColor(0, 0, 0, 0.7)
    bg:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    local lbl = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    lbl:SetPoint("BOTTOMLEFT", bg, "TOPLEFT", 0, 2)
    lbl:SetText(labelTxt)

    local eb = CreateFrame("EditBox", name, bg)
    eb:SetFontObject("ChatFontSmall")
    eb:SetAutoFocus(false)
    eb:SetPoint("TOPLEFT", 6, -3)
    eb:SetPoint("BOTTOMRIGHT", -4, 3)
    eb:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    eb:SetScript("OnTextChanged", function(self)
    if dbKey then GManagerDB.autoInvite[dbKey] = self:GetText() end
        end)
    return bg, eb, lbl
    end
    -- Phrase -> Auto-Reply -> Reply if OFF
    f.aiPhraseBg, f.aiPhrase, f.aiPhraseLbl = makeAutoInvEditBox("GM_AI_Phrase", " Invite Phrase:", 80, f.autoInvCBLabel, "BOTTOMRIGHT", 36, 16, "/w Inv Phrase")
    f.aiOnBg, f.aiOn, f.aiOnLbl             = makeAutoInvEditBox("GM_AI_On", " Auto-Reply:", 200, f.aiPhraseBg, "TOPRIGHT", 12, 0, "replyOn")
    f.aiOffBg, f.aiOff, f.aiOffLbl          = makeAutoInvEditBox("GM_AI_Off", " Reply if OFF:", 200, f.aiOnBg, "TOPRIGHT", 12, 0, "replyOff")
    f.aiLvlBg, f.aiLvl, f.aiLvlLbl          = makeAutoInvEditBox("GM_AI_Lvl", "Min Lvl:", 40, f.aiOffBg, "TOPRIGHT", 12, 0, "minLvl")
    f.aiLowBg, f.aiLow, f.aiLowLbl          = makeAutoInvEditBox("GM_AI_Low", "Reply If too Low:", 200, f.aiLvlBg, "TOPRIGHT", 12, 0, "replyLow")

    -- ===== Footer (Log mode) =====
    f.numberedCB = CreateFrame("CheckButton", "GManagerNumberedCB", f, "OptionsBaseCheckButtonTemplate")
    f.numberedCB:SetSize(20, 20)
    f.numberedCB:SetPoint("BOTTOMLEFT", 24, 22)
    f.numberedCB:SetChecked(showLineNumbers)
    f.numberedCB:SetScript("OnClick", function(self)
        showLineNumbers = self:GetChecked() and true or false
        UI:Refresh()
    end)
    f.numberedLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.numberedLabel:SetPoint("LEFT", f.numberedCB, "RIGHT", 2, 0)
    f.numberedLabel:SetText("Numbered Lines")

    f.clearLogBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.clearLogBtn:SetSize(90, 22)
    f.clearLogBtn:SetText("Clear Log")
    f.clearLogBtn:SetPoint("BOTTOMRIGHT", f.listPanel, "BOTTOMRIGHT", -4, -28)
    f.clearLogBtn:SetScript("OnClick", function()
        addon:ClearLog()
        UI:Refresh()
    end)

    -- Roster mode footer
    f.groupAltsCB = CreateFrame("CheckButton", "GManagerGroupAltsCB", f, "OptionsBaseCheckButtonTemplate")
    f.groupAltsCB:SetSize(20, 20)
    f.groupAltsCB:SetPoint("BOTTOMLEFT", 24, 22)
    f.groupAltsCB:SetChecked(groupAltsWithMain)
    f.groupAltsCB:SetScript("OnClick", function(self)
        groupAltsWithMain = self:GetChecked() and true or false
        UI:Refresh()
    end)
    f.groupAltsLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.groupAltsLabel:SetPoint("LEFT", f.groupAltsCB, "RIGHT", 2, 0)
    f.groupAltsLabel:SetText("Group Alts With Main")

    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.status:SetPoint("BOTTOMRIGHT", f.listPanel, "TOPRIGHT", 0, 2)

    frame = f
    return f
end


-- =========================================================
-- Ranks Date Parser (Helper)
-- =========================================================
local function parseJoinDateToDays(dateStr)
    if not dateStr then return -1 end
    
    -- Try modern Month DD YYYY format
    local m, d2, y2 = string.match(dateStr:lower(), "^(%S+)%s+(%d%d)%s+(%d%d%d%d)$")
    if m and d2 and y2 then
        local map = {
            jan=1, feb=2, mar=3, apr=4, may=5, jun=6, jul=7, aug=8, sep=9, oct=10, nov=11, dec=12,
            ["mär"]=3, mai=5, okt=10, dez=12
        }
        local monthNum = map[m] or 1
        local ts = time({year=tonumber(y2), month=monthNum, day=tonumber(d2), hour=12, min=0, sec=0})
        if ts then return math.floor((time() - ts) / 86400) end
    end
    
    -- Try legacy YYYY-MM-DD
    local y, mStr, d = string.match(dateStr, "^(%d%d%d%d)%-(%d%d)%-(%d%d)$")
    if y and mStr and d then
        local ts = time({year=tonumber(y), month=tonumber(mStr), day=tonumber(d), hour=12, min=0, sec=0})
        if ts then return math.floor((time() - ts) / 86400) end
    end
    
    return -1
end

-- =========================================================
-- Ranks row collection (Mass Promote list)
-- =========================================================
local function collectRanksRows()
    local guild = addon:GetCurrentGuild()
    local rows = {}
    if not guild then return rows end
    
    local minJoinDays = tonumber(ranksMinDays) or 0
    local maxOffDays = tonumber(ranksMaxOffline)
    
    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, rank, rankIndex, level, _, _, note, officerNote, isOnline, _, classFile = GetGuildRosterInfo(i)
        
        if name and rankIndex == ranksTargetRankIndex then
            local rec = guild.members[name]
            local extractedDate = (officerNote and string.match(officerNote, "%[(%S+ %d%d %d%d%d%d)%]")) or ((rec and rec.joinDateExact) and rec.joinDate) or nil

            -- Fallback for Ranks Tab
            local serverEpoch = nil
            if not isOnline then
                local y, m, d, h = GetGuildRosterLastOnline(i)
                if y or m or d or h then
                    local totalSecs = ((y or 0)*365*24*3600) + ((m or 0)*30*24*3600) + ((d or 0)*24*3600) + ((h or 0)*3600)
                    if totalSecs > 0 then
                        serverEpoch = time() - totalSecs
                    end
                end
            end

            local daysJoined = parseJoinDateToDays(extractedDate)
            local lastSeenTs = isOnline and time() or (rec and rec.lastOnline) or serverEpoch

            local daysOffline = 0
            if not isOnline then
                if lastSeenTs then
                    daysOffline = (time() - lastSeenTs) / 86400
                else
                    daysOffline = 9999 -- Unknown, assume huge
                end
            end
            
            local pass = true
            if daysJoined == -1 then
                -- Unknown join date: fail them if a minimum days requirement is set
                if minJoinDays > 0 then pass = false end
            elseif daysJoined < minJoinDays then
                -- Known join date but hasn't been in the guild long enough
                pass = false
            end

            if maxOffDays and daysOffline > maxOffDays then pass = false end
            
            if pass then
                table.insert(rows, {
                    name        = name,
                    rank        = rank or "",
                    level       = level or 0,
                    online      = isOnline and true or false,
                    note        = note or "",
                    officerNote = officerNote or "",
                    classFile   = classFile or (rec and rec.classFile) or "",
                    joinDate    = extractedDate,
                    lastSeen    = lastSeenTs,
                    main        = guild.alts[name],
                })
            end
        end
    end
    
    table.sort(rows, function(a, b) return a.name:lower() < b.name:lower() end)
    return rows
end


-- =========================================================
-- Roster row collection + sorting
-- =========================================================
local function collectRosterRows()
    local guild = addon:GetCurrentGuild()
    local rows = {}
    if not guild then return rows, 0, 0 end

    local online, total = 0, 0
    local needle = lowerSafe(rosterPlayerSearch)
    local noteNeedle = lowerSafe(rosterNoteSearch)

    local n = GetNumGuildMembers() or 0
    for i = 1, n do
        local name, rank, _, level, _, _, note, officerNote, isOnline, _, classFile
            = GetGuildRosterInfo(i)
        if name and name ~= "" then
            total = total + 1
            if isOnline then online = online + 1 end

            local pass = true
            if not rosterShowOffline and not isOnline then pass = false end
            if pass and needle ~= "" and not lowerSafe(name):find(needle, 1, true) then
                pass = false
            end
            if pass and noteNeedle ~= "" then
                local nMatch = (note    and lowerSafe(note):find(noteNeedle, 1, true))
                            or (officerNote and lowerSafe(officerNote):find(noteNeedle, 1, true))
                if not nMatch then pass = false end
            end
            -- Fallback to server's "Last Online" if addon database lacks the timestamp
            local rec = guild.members[name]
            local serverEpoch = nil
            if not isOnline then
                local y, m, d, h = GetGuildRosterLastOnline(i)
                if y or m or d or h then
                    local totalSecs = ((y or 0)*365*24*3600) + ((m or 0)*30*24*3600) + ((d or 0)*24*3600) + ((h or 0)*3600)
                    if totalSecs > 0 then
                        serverEpoch = time() - totalSecs
                    end
                end
            end

            local hasOffDaysFilter = (rosterOfflineDaysSearch ~= nil and rosterOfflineDaysSearch ~= "")
            if pass and hasOffDaysFilter then
                if isOnline then
                    -- Drop online members immediately if ANY input is in the box
                    pass = false
                else
                    local filterOffDays = tonumber(rosterOfflineDaysSearch) or 0
                    local lastSeenTs = (rec and rec.lastOnline) or serverEpoch

                    if lastSeenTs then
                        local daysOffline = (time() - lastSeenTs) / 86400
                        if daysOffline <= filterOffDays then pass = false end
                    else
                        -- Safe drop: if completely unidentifiable, exclude them
                        pass = false
                    end
                end
            end

            if pass then
                table.insert(rows, {
                    name        = name,
                    rank        = rank or "",
                    level       = level or 0,
                    online      = isOnline and true or false,
                    note        = note or "",
                    officerNote = officerNote or "",
                    classFile   = classFile or (rec and rec.classFile) or "",
                    joinDate    = (officerNote and string.match(officerNote, "%[(%a%a%a %d%d %d%d%d%d)%]")) or ((rec and rec.joinDateExact) and rec.joinDate) or nil,
                    lastSeen    = isOnline and time() or (rec and rec.lastOnline) or serverEpoch,
                    main        = guild.alts[name],
                })
            end
        end -- FIXED: Closed the 'if name and name ~= ""' statement block
    end -- FIXED: Closed the 'for i = 1, n' iterator loop

    -- Sort
    local key = rosterSortBy
    local rev = rosterSortReverse
    table.sort(rows, function(a, b)
        local av, bv
        if     key == "level"  then av, bv = a.level, b.level
        elseif key == "name"   then av, bv = a.name:lower(), b.name:lower()
        elseif key == "online" then
            local at = a.online and math.huge or (a.lastSeen or 0)
            local bt = b.online and math.huge or (b.lastSeen or 0)
            av, bv = at, bt
            if not rev then return at > bt else return at < bt end
        elseif key == "rank"   then av, bv = a.rank:lower(), b.rank:lower()
        elseif key == "joinDate" then
            local at = a.joinDate or "9999-99-99"
            local bt = b.joinDate or "9999-99-99"
            av, bv = at, bt
        elseif key == "note"   then av, bv = a.note:lower(), b.note:lower()
        elseif key == "onote"  then av, bv = a.officerNote:lower(), b.officerNote:lower()
        else av, bv = a.name:lower(), b.name:lower() end
        if av == bv then return a.name:lower() < b.name:lower() end
        if rev then return av > bv else return av < bv end
    end)

    if groupAltsWithMain then
        local byMain = {}
        for _, r in ipairs(rows) do
            if r.main then
                byMain[r.main] = byMain[r.main] or {}
                table.insert(byMain[r.main], r)
            end
        end
        local newRows = {}
        local seen = {}
        for _, r in ipairs(rows) do
            if not seen[r.name] then
                if r.main then
                else
                    table.insert(newRows, r)
                    seen[r.name] = true
                    local kids = byMain[r.name]
                    if kids then
                        for _, alt in ipairs(kids) do
                            if not seen[alt.name] then
                                table.insert(newRows, alt)
                                seen[alt.name] = true
                            end
                        end
                    end
                end
            end
        end
        for _, r in ipairs(rows) do
            if not seen[r.name] then
                table.insert(newRows, r)
                seen[r.name] = true
            end
        end
        rows = newRows
    end

    return rows, online, total
end

-- =========================================================
-- Log row collection
-- =========================================================
local function collectLogRows()
    local guild = addon:GetCurrentGuild()
    local rows = {}
    if not guild then return rows, 0 end

    local needle = lowerSafe(logSearchText)
    local total = #guild.log
    for i = total, 1, -1 do
        local e = guild.log[i]
        if e and typeFilters[e.type] then
            if needle ~= "" then
                local hay = lowerSafe((e.who or "") .. " " .. (e.details or "") .. " " .. (TYPE_LABEL[e.type] or e.type))
                if hay:find(needle, 1, true) then
                    table.insert(rows, { entry = e, n = i })
                end
            else
                table.insert(rows, { entry = e, n = i })
            end
        end
    end
    return rows, total
end

-- =========================================================
-- Macros rows
-- =========================================================
local function collectMacrosRows()
    local rows = {}
    local list = addon:GetMacros()
    for i, m in ipairs(list) do
        table.insert(rows, { index = i, channel = m.channel, text = m.text })
    end
    return rows
end

-- =========================================================
-- Alts rows
-- =========================================================
local function collectAltsRows()
    local guild = addon:GetCurrentGuild()
    local rows = {}
    if not guild then return rows end
    for alt, main in pairs(guild.alts) do
        table.insert(rows, { alt = alt, main = main })
    end
    table.sort(rows, function(a, b)
        if a.main == b.main then return a.alt < b.alt end
        return a.main < b.main
    end)
    return rows
end

-- =========================================================
-- Refresh
-- =========================================================
local function setVis(widget, visible)
    if visible then widget:Show() else widget:Hide() end
end

function UI:Refresh()
    local f = frame
    if not f or not f:IsShown() then return end

    local logMode    = (activeView == "LOG")
    local rosterMode = (activeView == "ROSTER")
    local altsMode   = (activeView == "ALTS")
    local macrosMode = (activeView == "MACROS")
    local ranksMode  = (activeView == "RANKS")

    -- Toggle Log controls
    setVis(f.logSearch,         logMode)
    setVis(f.logSearchLabel,    logMode)
    setVis(f.filterPanel,       logMode)
    setVis(f.numberedCB,        logMode)
    setVis(f.numberedLabel,     logMode)
    setVis(f.clearLogBtn,       logMode)

    -- Toggle Roster controls
    setVis(f.rosterShowOfflineCB,    rosterMode)
    setVis(f.rosterShowOfflineLabel, rosterMode)
    setVis(f.rosterPSearch,          rosterMode)
    setVis(f.rosterPSearchLabel,     rosterMode)
    setVis(f.rosterNSearch,          rosterMode)
    setVis(f.rosterNSearchLabel,     rosterMode)
    setVis(f.groupAltsCB,            rosterMode)
    setVis(f.groupAltsLabel,         rosterMode)
    setVis(f.rosterONoteEmptyBtn,    rosterMode or logMode)
    setVis(f.rosterOffDaysInput,     rosterMode)
    setVis(f.rosterOffDaysLabel,     rosterMode)
    setVis(f.rosterMassKickBtn,      rosterMode)

    -- Toggle Ranks controls
    setVis(f.ranksHeaderPanel, ranksMode)
    if ranksMode then
        local maxRanks = GuildControlGetNumRanks() or 0
        if maxRanks > 0 then
            if not ranksTargetRankIndex or ranksTargetRankIndex < 1 or ranksTargetRankIndex > maxRanks - 1 then
                ranksTargetRankIndex = maxRanks - 1
            end
        end
        f.ranksRankDisplay:SetText(GuildControlGetRankName(ranksTargetRankIndex + 1) or "?")
    end

    -- Toggle Shared Column Headers (Roster & Ranks)
    setVis(f.colHeader, rosterMode or ranksMode)

    -- Toggle Alts controls
    setVis(f.altInputAlt,       altsMode)
    setVis(f.altInputMain,      altsMode)
    setVis(f.altInputAltLabel,  altsMode)
    setVis(f.altInputMainLabel, altsMode)
    setVis(f.altBtnSet,         altsMode)
    setVis(f.altBtnUnset,       altsMode)

    -- Toggle Macros controls
    setVis(f.macroMsgLabel,  macrosMode)
    setVis(f.macroMsgBg,     macrosMode)
    setVis(f.macroChanLabel, macrosMode)
    setVis(f.macroSaveBtn,   macrosMode)
    for _, b in pairs(f.macroChanBtns or {}) do setVis(b, macrosMode) end

        -- Toggle Auto-Invite controls
        setVis(f.autoInvLabel, macrosMode)
        setVis(f.autoInvCB, macrosMode)
        setVis(f.autoInvCBLabel, macrosMode)
        setVis(f.aiPhraseBg, macrosMode); setVis(f.aiPhraseLbl, macrosMode)
        setVis(f.aiOnBg, macrosMode); setVis(f.aiOnLbl, macrosMode)
        setVis(f.aiOffBg, macrosMode); setVis(f.aiOffLbl, macrosMode)
        setVis(f.aiLvlBg, false); setVis(f.aiLvlLbl, false) --hidden until properly implemented
        setVis(f.aiLowBg, false); setVis(f.aiLowLbl, false) --hidden until properly implemented

        -- Populate Auto-Invite fields safely
        if macrosMode and GManagerDB and GManagerDB.autoInvite then
            local conf = GManagerDB.autoInvite
            f.autoInvCB:SetChecked(conf.enabled)
            if not f.aiPhrase:HasFocus() then f.aiPhrase:SetText(conf.phrase or "") end
            if not f.aiOn:HasFocus()     then f.aiOn:SetText(conf.replyOn or "") end
            if not f.aiOff:HasFocus()    then f.aiOff:SetText(conf.replyOff or "") end
            if not f.aiLvl:HasFocus()    then f.aiLvl:SetText(conf.minLvl or "1") end
            if not f.aiLow:HasFocus()    then f.aiLow:SetText(conf.replyLow or "") end
        end


    -- List panel sizing
    f.listPanel:ClearAllPoints()
    if macrosMode then
        f.listPanel:SetPoint("TOPLEFT", 16, -200)
    else
        f.listPanel:SetPoint("TOPLEFT", 16, -130)
    end
    if logMode then
        f.listPanel:SetPoint("BOTTOMRIGHT", -180, 56)
    else
        f.listPanel:SetPoint("BOTTOMRIGHT", -18, 56)
    end

    -- Tab highlight
    for view, b in pairs(f.tabButtons) do
        if view == activeView then b:LockHighlight() else b:UnlockHighlight() end
    end

    -- Subtitle + header text per view
    local key = addon:GetCurrentGuildKey()
    local guildLabel = key and key:gsub("::", " / ") or "(not in a guild)"
    if logMode then
        f.subtitle:SetText("|cFFFFCC00Guild Roster Event Log|r   " .. guildLabel)
    elseif rosterMode then
        f.subtitle:SetText("|cFFFFCC00Guild Roster|r   " .. guildLabel)
    elseif macrosMode then
        f.subtitle:SetText("|cFFFFCC00Saved Macros|r   account-wide")
    elseif ranksMode then
        f.subtitle:SetText("|cFFFFCC00Mass Rank Up Settings|r   " .. guildLabel)
    else
        f.subtitle:SetText("|cFFFFCC00Alts|r   " .. guildLabel)
    end

    -- Body
    local data, total, onlineCount = {}, 0, 0
    if logMode then
        data, total = collectLogRows()
        f.rightHeader:SetText(("Total Entries: |cffffffff%d|r"):format(total))
    elseif rosterMode then
        data, onlineCount, total = collectRosterRows()
        addon.RosterRowsCache = data
        f.rightHeader:SetText(("|cffffffff%d|r / %d Online"):format(onlineCount, total))
    elseif ranksMode then
        data = collectRanksRows()
        addon.RanksRowsCache = data 
        f.rightHeader:SetText(("|cffffffff%d|r Candidates available for mass promotion"):format(#data))
    elseif macrosMode then
        data = collectMacrosRows()
        f.rightHeader:SetText(("|cffffffff%d|r macros  -  channel: |cffffcc00%s|r"):format(#data, macroSelectedChannel))
    else
        data = collectAltsRows()
        f.rightHeader:SetText(("|cffffffff%d|r mappings"):format(#data))
    end

    if macrosMode then
        for opt, b in pairs(f.macroChanBtns) do
            if opt == macroSelectedChannel then b:LockHighlight() else b:UnlockHighlight() end
        end
    end

    local count = #data
    FauxScrollFrame_Update(f.scroll, count, ROW_COUNT, ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(f.scroll)

    if rosterMode or ranksMode then
        local mark = rosterSortReverse and "  v" or "  ^"
        for _, def in ipairs(COL_DEFS) do
            local label = def.label
            if rosterSortBy == def.sort then label = label .. mark end
            f.colHeaderBtns[def.key]:SetText(label)
        end
    end

    local function hideCells(i)
        local cells = f.rowCells[i]
        if cells then for _, c in pairs(cells) do c:SetText(""); c:Hide() end end
    end
    local function hideSingle(i)
        local row = f.rows[i]
        if row then row:SetText(""); row:Hide() end
    end
    local function hideMacroBtns(i)
        local btns = f.rowMacroBtns[i]
        if btns then btns.send:Hide(); btns.del:Hide() end
    end
    local function hideClickBtn(i)
        local b = f.rowClickBtns[i]
        if b then b:Hide(); b:SetScript("OnClick", nil) end
    end

    for i = 1, ROW_COUNT do
        local idx = i + offset
        local item = data[idx]

        if not item then
            hideSingle(i)
            hideCells(i)
            hideMacroBtns(i)
            hideClickBtn(i)
        elseif logMode then
            hideCells(i)
            hideMacroBtns(i)
            hideClickBtn(i)
            local row = f.rows[i]
            row:SetPoint("RIGHT", f.scroll, "RIGHT", -4, 0)
            local e = item.entry
            local n = item.n
            local label = TYPE_LABEL[e.type] or e.type
            local detail = e.details and (" - " .. e.details) or ""
            local prefix = showLineNumbers and ("|cff888888%4d)|r "):format(n) or ""
            row:SetText(("%s|cffaaaaaa%s|r  %s  |cffffffff%s|r%s"):format(
                prefix, fmtDateLong(e.t), colorize(e.type, label), e.who or "?", detail))
            row:Show()
        elseif rosterMode or ranksMode then
            hideSingle(i)
            hideMacroBtns(i)
            local r = item
            local cells = f.rowCells[i]

            local lvlTxt = (r.level and r.level > 0) and tostring(r.level) or "?"
            cells.lvl:SetText("|cffffffff" .. lvlTxt .. "|r")

            local mainTag = ""
            if r.main then
                mainTag = "  |cffaaaaff(alt)|r"
            else
                local g = addon:GetCurrentGuild()
                if g then
                    for _, m in pairs(g.alts) do
                        if m == r.name then mainTag = "  |cffffcc00<M>|r"; break end
                    end
                end
            end
            --cells.name:SetText(classColor(r.classFile, r.name) .. mainTag)
            local whiteTag = addon:IsWhitelisted(r.name) and " |cff00ff00[W]|r" or ""
            cells.name:SetText(classColor(r.classFile, r.name) .. mainTag .. whiteTag)

            local onlineRaw = r.online and "Online" or fmtSince(r.lastSeen)
            cells.online:SetText(lastSeenColor(r.lastSeen, r.online) .. onlineRaw .. "|r")

            if r.joinDate then cells.join:SetText("|cffcccccc" .. r.joinDate .. "|r")
            else cells.join:SetText("|cff666666?|r") end

            cells.rank:SetText(r.rank or "")
            cells.note:SetText(r.note or "")
            cells.onote:SetText(r.officerNote or "")

            for _, c in pairs(cells) do c:Show() end

            local clickBtn = f.rowClickBtns[i]
            if clickBtn then
                local rowName = r.name
                clickBtn:SetScript("OnClick", function(_, button)
                    if button == "RightButton" then
                        showRosterContextMenu(rowName)
                    elseif button == "LeftButton" then
                        if addon.ShowMemberDetail then addon:ShowMemberDetail(rowName) end
                    end
                end)
                clickBtn:Show()
            end
        elseif macrosMode then
            hideCells(i)
            hideClickBtn(i)
            local row = f.rows[i]
            local preview = item.text or ""
            if #preview > 60 then preview = preview:sub(1, 60) .. "..." end
            preview = preview:gsub("\n", " "):gsub("|", "||")
            row:SetText(("|cffffcc00[%s]|r  |cffffffff%s|r"):format(tostring(item.channel), preview))
            row:SetPoint("RIGHT", f.scroll, "RIGHT", -110, 0)
            row:Show()

            local btns = f.rowMacroBtns[i]
            if btns then
                btns.send:Show(); btns.del:Show()
                local idx = item.index
                btns.send:SetScript("OnClick", function()
                    local ok, msg = addon:SendMacro(idx)
                    if not ok then print("|cFFFFCC00GManager|r: " .. tostring(msg)) end
                end)
                btns.del:SetScript("OnClick", function() addon:RemoveMacro(idx); UI:Refresh() end)
            end
        else
            hideCells(i)
            hideMacroBtns(i)
            hideClickBtn(i)
            local row = f.rows[i]
            row:SetPoint("RIGHT", f.scroll, "RIGHT", -4, 0)
            row:SetText(("|cffeeeeee%s|r  |cff888888is alt of|r  |cffffcc00%s|r"):format(item.alt, item.main))
            row:Show()
        end
    end

    f.status:SetText("")
end

function UI:RefreshIfShown()
    if frame and frame:IsShown() then UI:Refresh() end
end

function UI:Toggle()
    local f = build()
    if f:IsShown() then f:Hide() else f:Show(); UI:Refresh() end
end

function UI:Show()
    local f = build()
    f:Show()
    UI:Refresh()
end

function UI:Hide()
    if frame then frame:Hide() end
end
