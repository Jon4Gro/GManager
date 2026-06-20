-- GManager UI
-- Six tabs: Log, Roster, Alts, Macros, Ranks, Settings. Plain Wrath 3.3.5a frame API.

GManager = GManager or {}
GManager.UI = {}
local UI    = GManager.UI
local addon = GManager
local rosterOfflineDaysSearch = ""

-- =========================================================
-- Constants
-- =========================================================
local ROW_HEIGHT = 14
local ROW_COUNT  = 20

local COL_DEFS = {
    { key = "lvl",    label = "Lvl",         sort = "level",    width = 18  },
    { key = "name",   label = "Name",        sort = "name",     width = 90  },
    { key = "online", label = "Last Online", sort = "online",   width = 80  },
    { key = "join",   label = "Join Date",   sort = "joinDate", width = 80  },
    { key = "rank",   label = "Rank",        sort = "rank",     width = 80  },
    { key = "note",   label = "Note",        sort = "note",     width = 154 },
    { key = "onote",  label = "Officer Note",sort = "onote",    width = 154 },
}
local COL_GAP = 4

local ROSTER_COLS = {
    { key = "lvl",    width = 18  },
    { key = "name",   width = 94  },
    { key = "online", width = 71  },
    { key = "join",   width = 71  },
    { key = "rank",   width = 80  },
    { key = "note",   width = 210 },
    { key = "onote",  width = 210 },
}

local RANKS_COLS = {
    { key = "name",   width = 100 },
    { key = "rank",   width = 70  },
    { key = "online", width = 70  },
    { key = "note",   width = 100 },
    { key = "onote",  width = 160 },
}

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
local activeView   = "LOG"

local CHANNEL_OPTIONS = { "1","2","3","4","5","6","7","8","9",
                         "GUILD","OFFICER","SAY","PARTY","RAID","YELL" }
local macroSelectedChannel = "GUILD"

local typeFilters = {
    SEEN = true, JOIN = true, LEAVE = true,
    PROMOTE = true, DEMOTE = true,
    NOTE = true, ONOTE = true, LEVEL = false,
}
local logSearchText = ""
local showLineNumbers = true

local rosterShowOffline    = true
local rosterPlayerSearch   = ""
local rosterNoteSearch     = ""
local rosterSortBy         = "name"
local rosterSortReverse    = false
local groupAltsWithMain    = false

local frame

-- =========================================================
-- Right-click context menu (Roster rows)
-- =========================================================
local contextMenuFrame

local function showRosterContextMenu(name)
    if not name or name == "" then return end
    if not contextMenuFrame then
        contextMenuFrame = CreateFrame("Frame", "GManagerRosterContextMenu", UIParent, "UIDropDownMenuTemplate")
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
                        else GuildRoster() end
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
                        else GuildRoster() end
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
    if d < 86400   then return "|cff99ff99" end
    if d < 604800  then return "|cffffffff" end
    if d < 2592000 then return "|cffffff66" end
    if d < 7776000 then return "|cffffaa00" end
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

    local rawSize = (GManagerDB and GManagerDB.batchSize) or 2
    local bSize = math.max(1, tonumber(rawSize) or 2)
    local total = #list
    local currentIdx = 1
    local batchNum = 1
    local totalBatches = math.ceil(total / bSize)

    local processor = CreateFrame("Frame")
    local timer = 0

    processor:SetScript("OnUpdate", function(self, elapsed)
        timer = timer + elapsed
        if timer >= 1.0 or currentIdx == 1 then
            timer = 0
            local endIdx = math.min(currentIdx + bSize - 1, total)

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
                self:Hide()
                print("|cff00ff00GManager:|r All " .. actionName .. " operations completed.")
                if GManager.RequestRosterAfterAction then GManager:RequestRosterAfterAction()
                else GuildRoster() end
            end
        end
    end)
end

-- =========================================================
-- Window build
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
    title:SetPoint("TOPLEFT", 18, -18)
    title:SetText("|cFFFFCC00GManager|r")
    f.title = title

    local subtitle = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    subtitle:SetPoint("RIGHT", f.title ,"RIGHT",330, 0)
    f.subtitle = subtitle

    local rightHeader = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rightHeader:SetPoint("TOPRIGHT", -34, -22)
    rightHeader:SetJustifyH("RIGHT")
    f.rightHeader = rightHeader

    local rrightHeader = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    rrightHeader:SetPoint("TOPRIGHT", -34, -34)
    rrightHeader:SetJustifyH("RIGHT")
    f.rrightHeader = rrightHeader

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    -- ===== Tabs =====
    f.tabButtons = {}
    local function makeViewBtn(label, viewKey)
        local b = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
        b:SetSize(86, 22)
        b:SetText("|cFFFFCC00" .. label .. "|r")
        local fs = b:GetFontString()
        if fs then fs:SetTextColor(1, 0.8, 0) end
        b:SetScript("OnClick", function(self)
            activeView = viewKey
            for _, btn in pairs(f.tabButtons) do
                btn:UnlockHighlight()
                local fs = btn:GetFontString()
                if fs then fs:SetTextColor(1, 0.8, 0) end
            end
            self:LockHighlight()
            local fs = self:GetFontString()
            if fs then fs:SetTextColor(1, 0.8, 0) end
            UI:Refresh()
        end)
        f.tabButtons[viewKey] = b
        return b
    end
    f.tabLog      = makeViewBtn("Log",      "LOG")
    f.tabRoster   = makeViewBtn("Roster",   "ROSTER")
    f.tabAlts     = makeViewBtn("Alts",     "ALTS")
    f.tabMacros   = makeViewBtn("Macros",   "MACROS")
    f.tabRanks    = makeViewBtn("Ranks",    "RANKS")
    f.tabSettings = makeViewBtn("Settings", "SETTINGS")

    f.tabLog:SetPoint("TOPLEFT", 16, -38)
    f.tabRoster:SetPoint("TOPLEFT", f.tabLog,      "TOPRIGHT", 4, 0)
    f.tabAlts:SetPoint("TOPLEFT",   f.tabRoster,   "TOPRIGHT", 4, 0)
    f.tabMacros:SetPoint("TOPLEFT", f.tabAlts,     "TOPRIGHT", 4, 0)
    f.tabRanks:SetPoint("TOPLEFT",  f.tabMacros,   "TOPRIGHT", 4, 0)
    f.tabSettings:SetPoint("TOPLEFT", f.tabRanks,  "TOPRIGHT", 4, 0)

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
    fpTitle:SetText("|cFFFFCC00Display Changes|r")
    fpTitle:SetTextColor(1, 0.8, 0)

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
    rosterPSearch:SetPoint("LEFT", f.rosterShowOfflineLabel, "RIGHT", 70, 0)
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
    rosterNSearch:SetPoint("LEFT", rosterPSearch, "RIGHT", 36, 0)
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
    rosterOffDaysInput:SetPoint("LEFT", rosterNSearch, "RIGHT", 36, 0)
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
    f.rosterONoteEmptyBtn:SetSize(150, 24)
    f.rosterONoteEmptyBtn:SetPoint( "TOPRIGHT", -18, -102)
    f.rosterONoteEmptyBtn:SetText("|cFFFFCC00ONote Empty Newbies|r")
    local fs = f.rosterONoteEmptyBtn:GetFontString()
    if fs then fs:SetTextColor(1, 0.8, 0) end
    f.rosterONoteEmptyBtn:SetScript("OnClick", function()
        local list = {}
        for i = 1, GetNumGuildMembers() do
            local name, _, _, _, _, _, _, onote = GetGuildRosterInfo(i)
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
        local bSize = (GManagerDB and GManagerDB.batchSize) or 2

        StaticPopupDialogs["GManager_CONFIRM_ONOTE_EMPTY"] = {
            text = "Insert today's date " .. dateTag .. " for |cffffff00" .. #list .. "|r members?\n(Max " .. bSize .. " per second)",
            button1 = "Proceed", button2 = "Cancel",
            OnAccept = function()
                ProcessBatch("ONote Empty", list, function(name)
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

    f.rosterMassKickBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.rosterMassKickBtn:SetSize(150, 24)
    f.rosterMassKickBtn:SetPoint("BOTTOMRIGHT", -18, 18)
    f.rosterMassKickBtn:SetText("Mass Kick List")
    f.rosterMassKickBtn:SetScript("OnClick", function()
        local rows = addon.RosterRowsCache or {}
        if #rows == 0 or rosterShowOffline == false then
            if rosterShowOffline == false then
                print("|cff00ff00GManager:|r No Offline Selection on, Action aborted ")
            end
            return
        end
        local bSize = (GManagerDB and GManagerDB.batchSize) or 2

        StaticPopupDialogs["GManager_CONFIRM_MASS_KICK"] = {
            text = "WARNING: Kick |cffffff00" .. #rows .. "|r currently filtered members?\n(Max " .. bSize .. " per second)",
            button1 = "KICK ALL", button2 = "Cancel",
            OnAccept = function()
                StaticPopupDialogs["GManager_CONFIRM_MASS_KICK_2"] = {
                    text = "SECOND CONFIRMATION: Are you absolutely sure? This cannot be undone.",
                    button1 = "YES, KICK", button2 = "Cancel",
                    OnAccept = function()
                        ProcessBatch("Mass Kick", rows, function(name)
                            if not addon:IsWhitelisted(name) then
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

    -- ===== Ranks Config Right Panel =====
    f.ranksConfigPanel = CreateFrame("Frame", nil, f)
    f.ranksConfigPanel:SetPoint("TOPRIGHT", -13, -60)
    f.ranksConfigPanel:SetSize(300, 410)
    f.ranksConfigPanel:SetBackdrop(PANEL_BACKDROP)
    f.ranksConfigPanel:SetBackdropColor(0, 0, 0, 0.6)

    f.rankConfigLabel = f.ranksConfigPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.rankConfigLabel:SetPoint("TOP", 0, -10)
    f.rankConfigLabel:SetText("|cFFFFCC00Mass Promote Criteria|r")
    f.rankConfigLabel:SetTextColor(1, 0.8, 0)

    f.rankRows = {}
    for i = 2, 10 do
        local row = CreateFrame("Frame", nil, f.ranksConfigPanel)
        row:SetSize(280, 24)
        local offset = i - 1
        row:SetPoint("TOPLEFT", 10, -20 - (offset * 26))

        local cb = CreateFrame("CheckButton", nil, row, "OptionsBaseCheckButtonTemplate")
        cb:SetSize(20, 20)
        cb:SetPoint("LEFT", 0, 0)

        local nameStr = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        nameStr:SetPoint("LEFT", cb, "RIGHT", 4, 0)
        nameStr:SetWidth(95)                 -- wider so "Huggies Helper" / "Senior Member" don't truncate
        nameStr:SetJustifyH("LEFT")

        -- Min Days editbox (custom backdrop = no more missing middle)
        local minDays = CreateFrame("EditBox", nil, row)
        minDays:SetSize(48, 20)
        minDays:SetPoint("LEFT", nameStr, "RIGHT", 12, 0)
        minDays:SetAutoFocus(false)
        minDays:SetNumeric(true)
        minDays:SetFontObject("ChatFontSmall")
        minDays:SetBackdrop({
            bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 8,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        minDays:SetBackdropColor(0, 0, 0, 0.85)
        minDays:SetTextInsets(5, 5, 1, 1)
        minDays:SetTextColor(1, 1, 1, 1)

        -- Max Off editbox
        local maxOff = CreateFrame("EditBox", nil, row)
        maxOff:SetSize(48, 20)
        maxOff:SetPoint("LEFT", minDays, "RIGHT", 18, 0)
        maxOff:SetAutoFocus(false)
        maxOff:SetNumeric(true)
        maxOff:SetFontObject("ChatFontSmall")
        maxOff:SetBackdrop({
            bgFile   = "Interface\\ChatFrame\\ChatFrameBackground",
            edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
            tile = true, tileSize = 16, edgeSize = 8,
            insets = { left = 3, right = 3, top = 3, bottom = 3 },
        })
        maxOff:SetBackdropColor(0, 0, 0, 0.85)
        maxOff:SetTextInsets(5, 5, 1, 1)
        maxOff:SetTextColor(1, 1, 1, 1)

        local saved = GManagerCharDB and GManagerCharDB.massPromote and GManagerCharDB.massPromote[i] or {}
        cb:SetChecked(saved.checked or false)
        minDays:SetText(saved.minDays or "")
        maxOff:SetText(saved.maxOff or "")

        cb:SetScript("OnClick", function(self)
            if GManagerCharDB then
                GManagerCharDB.massPromote[i] = GManagerCharDB.massPromote[i] or {}
                GManagerCharDB.massPromote[i].checked = self:GetChecked() and true or false
            end
            UI:Refresh()
        end)
        minDays:SetScript("OnTextChanged", function(self)
            if GManagerCharDB then
                GManagerCharDB.massPromote[i] = GManagerCharDB.massPromote[i] or {}
                GManagerCharDB.massPromote[i].minDays = self:GetText()
            end
            UI:Refresh()
        end)
        maxOff:SetScript("OnTextChanged", function(self)
            if GManagerCharDB then
                GManagerCharDB.massPromote[i] = GManagerCharDB.massPromote[i] or {}
                GManagerCharDB.massPromote[i].maxOff = self:GetText()
            end
            UI:Refresh()
        end)

        f.rankRows[i] = { frame = row, cb = cb, nameStr = nameStr, minDays = minDays, maxOff = maxOff }
    end
    
    local minDaysLbl = f.ranksConfigPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    minDaysLbl:SetPoint("BOTTOM", f.rankRows[2].minDays, "TOP", 0, 2)
    minDaysLbl:SetText("Min Days")

    local maxOffLbl = f.ranksConfigPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    maxOffLbl:SetPoint("BOTTOM", f.rankRows[2].maxOff, "TOP", 0, 2)
    maxOffLbl:SetText("Max Off")

    f.ranksMultiPromoteBtn = CreateFrame("Button", nil, f.ranksConfigPanel, "UIPanelButtonTemplate")
    f.ranksMultiPromoteBtn:SetSize(180, 26)
    f.ranksMultiPromoteBtn:SetPoint("BOTTOM", 0, 15)
    f.ranksMultiPromoteBtn:SetText("|cFFFFCC00Mass Promote Selected|r")
    local fs = f.ranksMultiPromoteBtn:GetFontString()
    if fs then fs:SetTextColor(1, 0.8, 0) end
    f.ranksMultiPromoteBtn:SetScript("OnClick", function()
        local rows = addon.RanksRowsCache or {}
        if #rows == 0 then
            print("|cff00ff00GManager:|r No members match the selected conditions.")
            return
        end

        local bSize = tonumber(GManagerDB and GManagerDB.batchSize) or 2
        StaticPopupDialogs["GManager_CONFIRM_MULTI_PROMOTE"] = {
            text = "Are you sure you want to promote these |cffffff00" .. #rows .. "|r members?\nThis will process sequentially at " .. bSize .. " per second.",
            button1 = "Promote All", button2 = "Cancel",
            OnAccept = function()
                ProcessBatch("Mass Promote", rows, function(name)
                    if not addon:IsWhitelisted(name) then
                        if GuildPromote then GuildPromote(name) end
                    end
                end)
            end,
            timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
        }
        StaticPopup_Show("GManager_CONFIRM_MULTI_PROMOTE")
    end)

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
        local fs = b:GetFontString()
        if fs then fs:SetTextColor(1, 0.8, 0) end
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
    f.listPanel:SetPoint("TOPLEFT", 16, -160)
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
        delBtn:SetSize(36, ROW_HEIGHT - 1)
        delBtn:SetText("|cFFFFCC00Del|r")
        local fs = delBtn:GetFontString()
        if fs then fs:SetTextColor(1, 0.8, 0) end
        delBtn:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -4, rowY)
        delBtn:Hide()

        local sendBtn = CreateFrame("Button", nil, f.listPanel, "UIPanelButtonTemplate")
        sendBtn:SetSize(40, ROW_HEIGHT - 1)
        sendBtn:SetText("|cFFFFCC00Send|r")
        fs = sendBtn:GetFontString()
        if fs then fs:SetTextColor(1, 0.8, 0) end
        sendBtn:SetPoint("RIGHT", delBtn, "LEFT", -2, 0)
        sendBtn:Hide()

        local setBtn = CreateFrame("Button", nil, f.listPanel, "UIPanelButtonTemplate")
        setBtn:SetSize(36, ROW_HEIGHT - 1)
        setBtn:SetText("|cFFFFCC00Set|r")
        fs = setBtn:GetFontString()
        if fs then fs:SetTextColor(1, 0.8, 0) end
        setBtn:SetPoint("RIGHT", sendBtn, "LEFT", -2, 0)
        setBtn:Hide()

        local editBtn = CreateFrame("Button", nil, f.listPanel, "UIPanelButtonTemplate")
        editBtn:SetSize(40, ROW_HEIGHT - 1)
        editBtn:SetText("|cFFFFCC00Edit|r")
        fs = editBtn:GetFontString()
        if fs then fs:SetTextColor(1, 0.8, 0) end
        editBtn:SetPoint("RIGHT", setBtn, "LEFT", -2, 0)
        editBtn:Hide()

        f.rowMacroBtns[i] = { send = sendBtn, del = delBtn, edit = editBtn, set = setBtn }

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
    f.altBtnSet:SetText("|cFFFFCC00Set|r")
    local fs = f.altBtnSet:GetFontString()
    if fs then fs:SetTextColor(1, 0.8, 0) end
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
    f.altBtnUnset:SetText("|cFFFFCC00Unset|r")
    local fs = f.altBtnUnset:GetFontString()
    if fs then fs:SetTextColor(1, 0.8, 0) end
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
    f.macroMsgBg:SetSize(760, 44)
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
        b:SetText("|cFFFFCC00" .. opt .. "|r")
        local fs = b:GetFontString()
        if fs then fs:SetTextColor(1, 0.8, 0) end
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
    f.macroSaveBtn:SetText("|cFFFFCC00Save Macro|r")
    local fs = f.macroSaveBtn:GetFontString()
    if fs then fs:SetTextColor(1, 0.8, 0) end
    f.macroSaveBtn:SetPoint("TOPLEFT", f.macroChanLabel, "BOTTOMLEFT", 0, -28)

    -- MISSING FRAME CREATION ADDED HERE
    f.macroSpamCB = CreateFrame("CheckButton", "GManagerMacroSpamCB", f, "OptionsBaseCheckButtonTemplate")
    f.macroSpamCB:SetSize(20, 20)
    f.macroSpamCB:SetPoint( "BOTTOMLEFT", 18, 24)
    f.macroSpamCB:SetScript("OnClick", function(self)
        addon.spamActive = self:GetChecked()
        addon.spamInterval = tonumber(f.macroSpamInterval:GetText()) or 5
        addon.spamTotalLimit = tonumber(f.macroSpamTotal and f.macroSpamTotal:GetText()) or 0
        if GManagerDB then GManagerDB.spamTotalMinutes = addon.spamTotalLimit end
        addon.spamTotalElapsed = 0  -- reset total timer on (re)start

        local hasActive = false
        if addon.spamMacros then
            for k, v in pairs(addon.spamMacros) do
                if v then hasActive = true; break end
            end
        end

        if addon.spamActive and not hasActive then
            print("|cFFFFCC00GManager|r: Please 'Set' at least one macro first.")
            self:SetChecked(false)
            addon.spamActive = false
            addon.spamTotalElapsed = 0
        end
        addon.spamTimer = 0 -- Reset timer
    end)

    f.macroSpamLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.macroSpamLabel:SetPoint("LEFT", f.macroSpamCB, "RIGHT", 6, 1)
    f.macroSpamLabel:SetText("Spam selected Macro every:")

    f.macroSpamInterval = CreateFrame("EditBox", "GManagerMacroSpamInterval", f, "InputBoxTemplate")
    f.macroSpamInterval:SetSize(36, 24)
    f.macroSpamInterval:SetPoint("LEFT", f.macroSpamLabel, "RIGHT", 13, 0)
    f.macroSpamInterval:SetNumeric(true)
    f.macroSpamInterval:SetAutoFocus(false)
    f.macroSpamInterval:EnableMouse(true)
    f.macroSpamInterval:SetText("5")
    f.macroSpamInterval:SetScript("OnTextChanged", function(self)
        addon.spamInterval = tonumber(self:GetText()) or 5
    end)
    f.macroSpamInterval:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.macroSpamInterval:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    
    f.macroSpamMinLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.macroSpamMinLabel:SetPoint("LEFT", f.macroSpamInterval, "RIGHT", 4, 0)
    f.macroSpamMinLabel:SetText("minutes")

    -- Second minutes field: total time limit for spam
    f.macroSpamTotalLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.macroSpamTotalLabel:SetPoint("LEFT", f.macroSpamMinLabel, "RIGHT", 8, 0)
    f.macroSpamTotalLabel:SetText("for the next: ")
    f.macroSpamTotal = CreateFrame("EditBox", "GManagerMacroSpamTotal", f, "InputBoxTemplate")
    f.macroSpamTotal:SetSize(30, 24)
    f.macroSpamTotal:SetPoint("LEFT", f.macroSpamTotalLabel, "RIGHT", 4, 0)
    f.macroSpamTotal:SetNumeric(true)
    f.macroSpamTotal:SetAutoFocus(false)
    f.macroSpamTotal:SetText("0")
    f.macroSpamTotal:SetScript("OnTextChanged", function(self)
        addon.spamTotalLimit = tonumber(self:GetText()) or 0
        if GManagerDB then GManagerDB.spamTotalMinutes = addon.spamTotalLimit end
    end)
    f.macroSpamTotal:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.macroSpamTotal:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    f.macroSpamTotalMinLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.macroSpamTotalMinLabel:SetPoint("LEFT", f.macroSpamTotal, "RIGHT", 2, 0)
    f.macroSpamTotalMinLabel:SetText("minutes ( 0 = Infinite)")

    if GManagerDB then
        local tval = GManagerDB.spamTotalMinutes or 0
        f.macroSpamTotal:SetText(tostring(tval))
        addon.spamTotalLimit = tval
    end

    f.macroSaveBtn:SetScript("OnClick", function()
        local text = f.macroMsg:GetText() or ""
        if text == "" then return end

        if addon.editingMacroIndex then
            StaticPopupDialogs["GManager_CONFIRM_MACRO_OVERWRITE"] = {
                text = "Overwrite existing macro?",
                button1 = "Yes", button2 = "No",
                OnAccept = function()
                    GManagerDB.macros[addon.editingMacroIndex] = { channel = macroSelectedChannel, text = text }
                    addon.editingMacroIndex = nil
                    f.macroMsg:SetText("")
                    f.macroMsg:ClearFocus()
                    UI:Refresh()
                end,
                timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
            }
            StaticPopup_Show("GManager_CONFIRM_MACRO_OVERWRITE")
        else
            local ok, msg = addon:AddMacro(macroSelectedChannel, text)
            if ok then
                print("|cFFFFCC00GManager|r: macro saved.")
                f.macroMsg:SetText("")
                f.macroMsg:ClearFocus()
            else
                print("|cFFFFCC00GManager|r: " .. tostring(msg))
            end
            UI:Refresh()
        end
    end)


    -- ===== Settings View Components =====
    f.batchSizeLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.batchSizeLabel:SetPoint( "TOPRIGHT", -84, -230)
    f.batchSizeLabel:SetText("|cFFFFCC00Mass Action Batch Size (per sec):|r")
    f.batchSizeLabel:SetTextColor(1, 0.8, 0)

    f.batchSizeInput = CreateFrame("EditBox", "GManagerBatchSize", f, "InputBoxTemplate")
    f.batchSizeInput:SetSize(26, 20)
    f.batchSizeInput:SetPoint("LEFT", f.batchSizeLabel, "RIGHT", 13, 0)
    f.batchSizeInput:SetAutoFocus(false)
    f.batchSizeInput:SetNumeric(true)
    f.batchSizeInput:SetScript("OnTextChanged", function(self)
        if GManagerDB then GManagerDB.batchSize = tonumber(self:GetText()) or 2 end
    end)

    f.openWithGuildCB = CreateFrame("CheckButton", "GManagerOpenWithGuildCB", f, "OptionsBaseCheckButtonTemplate")
    f.openWithGuildCB:SetSize(20, 20)
    f.openWithGuildCB:SetPoint("TOPLEFT", f.batchSizeLabel, "BOTTOMLEFT", 0, -12)
    f.openWithGuildCB:SetScript("OnClick", function(self)
        if GManagerCharDB then GManagerCharDB.openWithGuild = self:GetChecked() and true or false end
    end)
    f.openWithGuildLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.openWithGuildLabel:SetPoint("LEFT", f.openWithGuildCB, "RIGHT", 4, 0)
    f.openWithGuildLabel:SetText("Open GManager with Guild Frame")

    f.closeWithGuildCB = CreateFrame("CheckButton", "GManagerCloseWithGuildCB", f, "OptionsBaseCheckButtonTemplate")
    f.closeWithGuildCB:SetSize(20, 20)
    f.closeWithGuildCB:SetPoint("TOPLEFT", f.openWithGuildCB, "BOTTOMLEFT", 0, -6)
    f.closeWithGuildCB:SetScript("OnClick", function(self)
        if GManagerCharDB then GManagerCharDB.closeWithGuild = self:GetChecked() and true or false end
    end)
    f.closeWithGuildLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.closeWithGuildLabel:SetPoint("LEFT", f.closeWithGuildCB, "RIGHT", 4, 0)
    f.closeWithGuildLabel:SetText("Close GManager with Guild Frame")

    -- Minimap Button in Settings
    f.showMinimapCB = CreateFrame("CheckButton", "GManagerShowMinimapCB", f, "OptionsBaseCheckButtonTemplate")
    f.showMinimapCB:SetSize(20, 20)
    f.showMinimapCB:SetPoint("TOPRIGHT", -120, -90)
    f.showMinimapCB:SetScript("OnClick", function(self)
        if GManagerDB then
            GManagerDB.showMinimapButton = self:GetChecked() and true or false
            if addon.UpdateMinimapButton then addon:UpdateMinimapButton() end
        end
    end)
    f.showMinimapLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.showMinimapLabel:SetPoint("RIGHT", f.showMinimapCB, "LEFT", -4, 0)
    f.showMinimapLabel:SetText("Show Minimap Button")

    f.minimapCtrlLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.minimapCtrlLabel:SetPoint("TOPRIGHT",f.showMinimapCB, -10, -24)
    f.minimapCtrlLabel:SetText("|cFFFFCC00Minimap Button Position|r")
    f.minimapCtrlLabel:SetTextColor(1, 0.8, 0)

    -- Rotation slider
    f.minimapRotLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.minimapRotLabel:SetPoint("TOPLEFT", f.minimapCtrlLabel, "BOTTOMLEFT", 0, -8)
    f.minimapRotLabel:SetText("|cFFFFCC00Rotation|r")
    f.minimapRotLabel:SetTextColor(1, 0.8, 0)

    f.minimapRotSlider = CreateFrame("Slider", nil, f)
    f.minimapRotSlider:SetOrientation("HORIZONTAL")
    f.minimapRotSlider:SetSize(150, 16)
    f.minimapRotSlider:SetPoint("LEFT", f.minimapRotLabel, "RIGHT", 6, 0)
    f.minimapRotSlider:SetMinMaxValues(0, 360)
    f.minimapRotSlider:SetValueStep(5)
    f.minimapRotSlider:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 }
    })
    f.minimapRotSlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local rotThumb = f.minimapRotSlider:GetThumbTexture()
    if rotThumb then rotThumb:SetSize(14, 20) end
    f.minimapRotLow = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.minimapRotLow:SetPoint("TOPLEFT", f.minimapRotSlider, "BOTTOMLEFT", 2, 0)
    f.minimapRotLow:SetText("0")
    f.minimapRotHigh = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.minimapRotHigh:SetPoint("TOPRIGHT", f.minimapRotSlider, "BOTTOMRIGHT", -2, 0)
    f.minimapRotHigh:SetText("360")
    f.minimapRotVal = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.minimapRotVal:SetPoint("LEFT", f.minimapRotSlider, "RIGHT", 6, 0)
    f.minimapRotSlider:SetScript("OnValueChanged", function(self, val)
        local v = math.floor(val / 5 + 0.5) * 5
        if v < 0 then v = 0 end
        if v > 360 then v = 360 end
        if GManagerDB then GManagerDB.minimapRotation = v end
        if f.minimapRotVal then f.minimapRotVal:SetText(tostring(v)) end
        if addon.UpdateMinimapPos then addon.UpdateMinimapPos() end
    end)

    -- Distance slider
    f.minimapDistLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.minimapDistLabel:SetPoint("TOPLEFT", f.minimapRotLabel, "BOTTOMLEFT", 0, -16)
    f.minimapDistLabel:SetText("|cFFFFCC00Distance|r")
    f.minimapDistLabel:SetTextColor(1, 0.8, 0)

    f.minimapDistSlider = CreateFrame("Slider", nil, f)
    f.minimapDistSlider:SetOrientation("HORIZONTAL")
    f.minimapDistSlider:SetSize(150, 16)
    f.minimapDistSlider:SetPoint("LEFT", f.minimapDistLabel, "RIGHT", 6, 0)
    f.minimapDistSlider:SetMinMaxValues(20, 240)
    f.minimapDistSlider:SetValueStep(2)
    f.minimapDistSlider:SetBackdrop({
        bgFile = "Interface\\Buttons\\UI-SliderBar-Background",
        edgeFile = "Interface\\Buttons\\UI-SliderBar-Border",
        tile = true, tileSize = 8, edgeSize = 8,
        insets = { left = 3, right = 3, top = 6, bottom = 6 }
    })
    f.minimapDistSlider:SetThumbTexture("Interface\\Buttons\\UI-SliderBar-Button-Horizontal")
    local distThumb = f.minimapDistSlider:GetThumbTexture()
    if distThumb then distThumb:SetSize(14, 20) end
    f.minimapDistLow = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.minimapDistLow:SetPoint("TOPLEFT", f.minimapDistSlider, "BOTTOMLEFT", 2, 0)
    f.minimapDistLow:SetText("20")
    f.minimapDistHigh = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    f.minimapDistHigh:SetPoint("TOPRIGHT", f.minimapDistSlider, "BOTTOMRIGHT", -2, 0)
    f.minimapDistHigh:SetText("240")
    f.minimapDistVal = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.minimapDistVal:SetPoint("LEFT", f.minimapDistSlider, "RIGHT", 6, 0)
    f.minimapDistSlider:SetScript("OnValueChanged", function(self, val)
        local v = math.floor(val / 2 + 0.5) * 2
        if v < 20 then v = 20 end
        if v > 240 then v = 240 end
        if GManagerDB then GManagerDB.minimapDistance = v end
        if f.minimapDistVal then f.minimapDistVal:SetText(tostring(v)) end
        if addon.UpdateMinimapPos then addon.UpdateMinimapPos() end
    end)

    -- init slider thumbs from current DB values at build time
    if GManagerDB then
        local ir = GManagerDB.minimapRotation or 0
        f.minimapRotSlider:SetValue(ir)
        if f.minimapRotVal then f.minimapRotVal:SetText(tostring(ir)) end
        local id = math.max(20, math.min(240, GManagerDB.minimapDistance or 80))
        if GManagerDB then GManagerDB.minimapDistance = id end
        f.minimapDistSlider:SetValue(id)
        if f.minimapDistVal then f.minimapDistVal:SetText(tostring(id)) end
    end

    f.autoInvLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.autoInvLabel:SetPoint("BOTTOMLEFT", 24, 120)
    f.autoInvLabel:SetText("|cFFFFCC00Auto Guild  Invite|r")
    f.autoInvLabel:SetTextColor(1, 0.8, 0)

    f.autoInvCB = CreateFrame("CheckButton", "GManagerAutoInvCB", f, "OptionsBaseCheckButtonTemplate")
    f.autoInvCB:SetSize(24, 24)
    f.autoInvCB:SetPoint("TOPLEFT", f.autoInvLabel, "BOTTOMLEFT", 0, -20)
    f.autoInvCB:SetScript("OnClick", function(self) GManagerDB.autoInvite.enabled = self:GetChecked(); UI:Refresh() end)

    f.autoInvCBLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.autoInvCBLabel:SetPoint("LEFT", f.autoInvCB, "RIGHT", 2, 1)
    f.autoInvCBLabel:SetText("Enable")

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
            if dbKey and GManagerDB and GManagerDB.autoInvite then GManagerDB.autoInvite[dbKey] = self:GetText() end
        end)
        return bg, eb, lbl
    end

    f.aiPhraseBg, f.aiPhrase, f.aiPhraseLbl = makeAutoInvEditBox("GM_AI_Phrase", " Trigger Words (can be multiple seperate with - ):", 380, f.autoInvCB, "BOTTOM", -13, -32, "phrase")
    f.aiOnBg, f.aiOn, f.aiOnLbl             = makeAutoInvEditBox("GM_AI_On", " Auto-Reply:", 300, f.autoInvCBLabel, "TOPRIGHT", 14, -5, "replyOn")
    f.aiOffBg, f.aiOff, f.aiOffLbl          = makeAutoInvEditBox("GM_AI_Off", " Reply if OFF:", 300, f.aiOnBg, "TOPRIGHT", 10, 0, "replyOff")

    -- Re-introduced level check controls for Guild Auto Invite (right of Reply if OFF)
    f.aiMinLvlBg, f.aiMinLvl, f.aiMinLvlLbl = makeAutoInvEditBox("GM_AI_MinLvl", " Min Lvl:", 50, f.aiPhrase, "RIGHT", 10, 11, "minLvl")
    f.aiReplyLowBg, f.aiReplyLow, f.aiReplyLowLbl = makeAutoInvEditBox("GM_AI_ReplyLow", " Reply if too Low:", 240, f.aiMinLvlBg, "RIGHT", 10, 11, "replyLow")
    f.aiMinLvl:SetNumeric(true)  -- numeric input for level

    f.autoInvBg = CreateFrame("Frame", nil, f)
    f.autoInvBg:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })
    f.autoInvBg:SetBackdropColor(0.05, 0.05, 0.05, 0.6)
    f.autoInvBg:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    f.autoInvBg:SetPoint("TOPLEFT", f.autoInvLabel, "TOPLEFT", -6, -18)
    f.autoInvBg:SetPoint("BOTTOMRIGHT", f.aiReplyLow, "RIGHT", 10, -18)
    f.autoInvBg:SetFrameLevel(math.max(0, f.autoInvCB:GetFrameLevel() - 1))

    f.groupInviteLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    f.groupInviteLabel:SetPoint("BOTTOMLEFT", f.autoInvCB, "BOTTOMLEFT", 0, 170)
    f.groupInviteLabel:SetText("|cFFFFCC00Auto Group Invite|r")
    f.groupInviteLabel:SetTextColor(1, 0.8, 0)

    f.groupInviteCheck = CreateFrame("CheckButton", "GManagerGroupInviteCheck", f, "InterfaceOptionsCheckButtonTemplate")
    f.groupInviteCheck:SetPoint("TOPLEFT", f.groupInviteLabel, "BOTTOMLEFT", 0, -13)
    GManagerGroupInviteCheckText:SetText("Auto Group On/Off: ")

    f.groupInviteEditBoxLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.groupInviteEditBoxLabel:SetPoint("BOTTOMLEFT", f.groupInviteCheck , "RIGHT", -19, -34)
    f.groupInviteEditBoxLabel:SetText("Trigger Words (seperate with -): ")

    f.groupInviteEditBox = CreateFrame("EditBox", "GManagerGroupInviteEditBox", f, "InputBoxTemplate")
    f.groupInviteEditBox:SetSize(490, 20)
    f.groupInviteEditBox:SetPoint("BOTTOMLEFT",  f.groupInviteCheck , "RIGHT", -18, -60)
    f.groupInviteEditBox:SetAutoFocus(false)
    f.groupInviteEditBox:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.groupInviteEditBox:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    f.groupInviteEditBox:SetScript("OnTextChanged", function(self)
        if GManagerDB and GManagerDB.autoInvite then
            GManagerDB.autoInvite.groupinv = self:GetText() or ""
        end
    end)

    f.groupInvitePermCheck = CreateFrame("CheckButton", "GManagerGroupInvitePermCheck", f, "InterfaceOptionsCheckButtonTemplate")
    f.groupInvitePermCheck:SetPoint("LEFT", f.groupInviteMinutes, "RIGHT", 30, -1)
    GManagerGroupInvitePermCheckText:SetText("Permanent")

    -- Minutes value for temporary duration (used when Permanent is off, default 15; 0 = infinite like Macro Spam)
    f.groupInviteMinutes = CreateFrame("EditBox", "GManagerGroupInviteMinutes", f, "InputBoxTemplate")
    f.groupInviteMinutes:SetSize(28, 20)
    f.groupInviteMinutes:SetPoint("LEFT", GManagerGroupInviteCheckText, "RIGHT", 8, 0)
    f.groupInviteMinutes:SetNumeric(true)
    f.groupInviteMinutes:SetAutoFocus(false)
    f.groupInviteMinutes:SetText("15")
    f.groupInviteMinutes:SetScript("OnTextChanged", function(self)
        if GManagerDB and GManagerDB.autoInvite then
            local v = tonumber(self:GetText())
            GManagerDB.autoInvite.groupMinutes = (v ~= nil) and v or 15
        end
    end)
    f.groupInviteMinutes:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    f.groupInviteMinutes:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)

    if GManagerDB and GManagerDB.autoInvite and GManagerDB.autoInvite.groupMinutes then
        f.groupInviteMinutes:SetText(tostring(GManagerDB.autoInvite.groupMinutes))
    end

    f.groupInviteCheck:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        if checked then
            addon.groupInvitePermanent = f.groupInvitePermCheck:GetChecked()
            local mins = tonumber(f.groupInviteMinutes and f.groupInviteMinutes:GetText()) or 15
            addon:StartGroupInvite(mins)
        else
            addon:StopGroupInvite()
        end
    end)

    f.groupInvitePermCheck:SetScript("OnClick", function(self)
        local checked = self:GetChecked()
        addon.groupInvitePermanent = checked
        if f.groupInviteCheck:GetChecked() then
            if checked then
                print("|cFFFFCC00Guild Manager|r: Group Auto-Invite mode set to permanent.")
            else
                local mins = tonumber(f.groupInviteMinutes and f.groupInviteMinutes:GetText()) or 15
                addon:StartGroupInvite(mins)
            end
        end
    end)

    f:HookScript("OnShow", function()
        if f.groupInviteCheck then f.groupInviteCheck:SetChecked(addon.groupInviteActive) end
        if f.groupInvitePermCheck then f.groupInvitePermCheck:SetChecked(addon.groupInvitePermanent) end
        if GManagerDB and GManagerDB.autoInvite then
            if f.groupInviteEditBox then
                f.groupInviteEditBox:SetText(GManagerDB.autoInvite.groupinv or "")
            end
            if f.groupInviteMinutes then
                local m = GManagerDB.autoInvite.groupMinutes or 15
                f.groupInviteMinutes:SetText(tostring(m))
            end
        end
    end)

    f.groupInviteBg = CreateFrame("Frame", nil, f)
    f.groupInviteBg:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Buttons\\WHITE8X8",
        edgeSize = 1,
        insets = { left = 0, right = 0, top = 0, bottom = 0 }
    })

    f.groupInviteMinLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.groupInviteMinLabel:SetPoint("LEFT", f.groupInviteMinutes, "RIGHT", 4, 0)
    f.groupInviteMinLabel:SetText("Minutes (0 = Infinite)")

    f.groupInviteBg:SetBackdropColor(0.05, 0.05, 0.05, 0.6)
    f.groupInviteBg:SetBackdropBorderColor(0.3, 0.3, 0.3, 0.8)
    f.groupInviteBg:SetPoint("TOPLEFT", f.groupInviteCheck, "TOPLEFT", -6, 5)
    f.groupInviteBg:SetPoint("BOTTOMRIGHT", f.groupInviteEditBox, "BOTTOMRIGHT", 6, -13)
    f.groupInviteBg:SetFrameLevel(math.max(0, f.groupInviteCheck:GetFrameLevel() - 1))

    -- Blacklist button (bottom-right corner of Settings view only)
    f.blacklistBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    f.blacklistBtn:SetSize(130, 24)
    f.blacklistBtn:SetPoint("BOTTOMRIGHT", -18, 18)
    f.blacklistBtn:SetText("|cFFFFCC00Blacklist...|r")
    local fs = f.blacklistBtn:GetFontString()
    if fs then fs:SetTextColor(1, 0.8, 0) end
    f.blacklistBtn:SetScript("OnClick", function()
        UI:ToggleBlacklistWindow()
    end)
    f.blacklistBtn:Hide()

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
    f.clearLogBtn:SetSize(150, 24)
    f.clearLogBtn:SetText("|cFFFFCC00Clear Log|r")
    local fs = f.clearLogBtn:GetFontString()
    if fs then fs:SetTextColor(1, 0.8, 0) end
    f.clearLogBtn:SetPoint("BOTTOMRIGHT", -18, 18)
    f.clearLogBtn:SetScript("OnClick", function()
        addon:ClearLog()
        UI:Refresh()
    end)

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

    f.status = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.status:SetPoint("BOTTOMLEFT", 16, 14)

    _G["GManagerMainFrame"] = f
    table.insert(UISpecialFrames, "GManagerMainFrame")

    if GuildFrame then
        GuildFrame:HookScript("OnShow", function()
            if GManagerCharDB and GManagerCharDB.openWithGuild then
                if not f:IsShown() then UI:Show() end
            end
        end)
        GuildFrame:HookScript("OnHide", function()
            if GManagerCharDB and GManagerCharDB.closeWithGuild then
                if f:IsShown() then UI:Hide() end
            end
        end)
    end
    frame = f
    return f
end

-- =========================================================
-- Ranks Date Parser (Helper)
-- =========================================================
local function parseJoinDateToDays(dateStr)
    if not dateStr then return -1 end

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
    if not guild or not frame or not frame.rankRows then return rows end

    local n = GetNumGuildMembers() or 0
    for j = 1, n do
        local name, rank, rankIndex, level, _, _, note, officerNote, isOnline, _, classFile = GetGuildRosterInfo(j)
        if name then
            local rowUI = frame.rankRows[rankIndex + 1]
            if rowUI and rowUI.frame:IsShown() and rowUI.cb:GetChecked() then
                local minDays = tonumber(rowUI.minDays:GetText()) or 0
                local maxOff = tonumber(rowUI.maxOff:GetText())

                local rec = guild.members[name]
                local extractedDate = (officerNote and string.match(officerNote, "%[(%S+ %d%d %d%d%d%d)%]")) or ((rec and rec.joinDateExact) and rec.joinDate) or nil

                local serverEpoch = nil
                if not isOnline then
                    local yy, mm, dd, hh = GetGuildRosterLastOnline(j)
                    if yy or mm or dd or hh then
                        local totalSecs = ((yy or 0)*365*24*3600) + ((mm or 0)*30*24*3600) + ((dd or 0)*24*3600) + ((hh or 0)*3600)
                        if totalSecs > 0 then serverEpoch = time() - totalSecs end
                    end
                end

                local daysJoined = parseJoinDateToDays(extractedDate)
                local lastSeenTs = isOnline and time() or (rec and rec.lastOnline) or serverEpoch

                local daysOffline = 0
                if not isOnline then
                    if lastSeenTs then daysOffline = (time() - lastSeenTs) / 86400 else daysOffline = 9999 end
                end

                local pass = true
                if daysJoined == -1 then
                    if minDays > 0 then pass = false end
                elseif daysJoined < minDays then
                    pass = false
                end

                if maxOff and daysOffline > maxOff then pass = false end

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
    end
    
    local key = rosterSortBy
    local rev = rosterSortReverse
    table.sort(rows, function(a, b)
        local av, bv
        if     key == "name"   then av, bv = a.name:lower(), b.name:lower()
        elseif key == "online" then
            local at = a.online and math.huge or (a.lastSeen or 0)
            local bt = b.online and math.huge or (b.lastSeen or 0)
            if not rev then return at > bt else return at < bt end
        elseif key == "note"   then av, bv = a.note:lower(), b.note:lower()
        elseif key == "onote"  then av, bv = a.officerNote:lower(), b.officerNote:lower()
        else av, bv = a.name:lower(), b.name:lower() end
        if av == bv then return a.name:lower() < b.name:lower() end
        if rev then return av > bv else return av < bv end
    end)
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
        local name, rank, _, level, _, _, note, officerNote, isOnline, _, classFile = GetGuildRosterInfo(i)
        if name and name ~= "" then
            total = total + 1
            if isOnline then online = online + 1 end

            local pass = true
            if not rosterShowOffline and not isOnline then pass = false end
            if pass and needle ~= "" and not lowerSafe(name):find(needle, 1, true) then pass = false end
            if pass and noteNeedle ~= "" then
                local nMatch = (note and lowerSafe(note):find(noteNeedle, 1, true)) or (officerNote and lowerSafe(officerNote):find(noteNeedle, 1, true))
                if not nMatch then pass = false end
            end

            local rec = guild.members[name]
            local serverEpoch = nil
            if not isOnline then
                local y, m, d, h = GetGuildRosterLastOnline(i)
                if y or m or d or h then
                    local totalSecs = ((y or 0)*365*24*3600) + ((m or 0)*30*24*3600) + ((d or 0)*24*3600) + ((h or 0)*3600)
                    if totalSecs > 0 then serverEpoch = time() - totalSecs end
                end
            end

            local hasOffDaysFilter = (rosterOfflineDaysSearch ~= nil and rosterOfflineDaysSearch ~= "")
            if pass and hasOffDaysFilter then
                if isOnline then
                    pass = false
                else
                    local filterOffDays = tonumber(rosterOfflineDaysSearch) or 0
                    local lastSeenTs = (rec and rec.lastOnline) or serverEpoch
                    if lastSeenTs then
                        local daysOffline = (time() - lastSeenTs) / 86400
                        if daysOffline <= filterOffDays then pass = false end
                    else
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
        end
    end

    local key = rosterSortBy
    local rev = rosterSortReverse
    table.sort(rows, function(a, b)
        local av, bv
        if     key == "level"  then av, bv = a.level, b.level
        elseif key == "name"   then av, bv = a.name:lower(), b.name:lower()
        elseif key == "online" then
            local at = a.online and math.huge or (a.lastSeen or 0)
            local bt = b.online and math.huge or (b.lastSeen or 0)
            if not rev then return at > bt else return at < bt end
        elseif key == "rank"   then av, bv = a.rank:lower(), b.rank:lower()
        elseif key == "joinDate" then av, bv = (a.joinDate or "9999-99-99"), (b.joinDate or "9999-99-99")
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
                if not r.main then
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
-- Log map collection
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
                if hay:find(needle, 1, true) then table.insert(rows, { entry = e, n = i }) end
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
    for alt, main in pairs(guild.alts) do table.insert(rows, { alt = alt, main = main }) end
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
    if not widget then return end
    if visible then widget:Show() else widget:Hide() end
end

function UI:Refresh()
    local f = frame
    if not f or not f:IsShown() then return end

    local logMode      = (activeView == "LOG")
    local rosterMode   = (activeView == "ROSTER")
    local altsMode     = (activeView == "ALTS")
    local macrosMode   = (activeView == "MACROS")
    local ranksMode    = (activeView == "RANKS")
    local settingsMode = (activeView == "SETTINGS")

    setVis(f.colHeader, rosterMode or ranksMode)

    for _, def in ipairs(COL_DEFS) do
        f.colHeaderBtns[def.key]:Hide()
        for i = 1, ROW_COUNT do
            f.rowCells[i][def.key]:Hide()
        end
    end

    local activeCols = rosterMode and ROSTER_COLS or (ranksMode and RANKS_COLS or nil)
    if activeCols then
        local prevHeader = nil
        for _, col in ipairs(activeCols) do
            local btn = f.colHeaderBtns[col.key]
            btn:SetWidth(col.width)
            btn:GetFontString():SetWidth(col.width)
            btn:ClearAllPoints()
            if prevHeader then
                btn:SetPoint("LEFT", prevHeader, "RIGHT", COL_GAP, 0)
            else
                btn:SetPoint("LEFT", f.colHeader, "LEFT", 0, 0)
            end
            btn:Show()
            prevHeader = btn
        end

        for i = 1, ROW_COUNT do
            local prevCell = nil
            for _, col in ipairs(activeCols) do
                local cell = f.rowCells[i][col.key]
                cell:SetWidth(col.width)
                cell:ClearAllPoints()
                if prevCell then
                    cell:SetPoint("LEFT", prevCell, "RIGHT", COL_GAP, 0)
                else
                    cell:SetPoint("TOPLEFT", f.scroll, "TOPLEFT", 4, -((i - 1) * ROW_HEIGHT) - 2)
                end
                prevCell = cell
            end
        end
    end

    if settingsMode then
        f.listPanel:Hide()
    else
        f.listPanel:Show()
        f.listPanel:ClearAllPoints()
        if macrosMode then 
            f.listPanel:SetPoint("TOPLEFT", 16, -200) 
        else 
            f.listPanel:SetPoint("TOPLEFT", 16, -130) 
        end
        
        if logMode then f.listPanel:SetPoint("BOTTOMRIGHT", -180, 56)
        elseif ranksMode then f.listPanel:SetPoint("BOTTOMRIGHT", -330, 56) 
        else f.listPanel:SetPoint("BOTTOMRIGHT", -18, 56) end
    end

    setVis(f.logSearch,         logMode)
    setVis(f.logSearchLabel,    logMode)
    setVis(f.filterPanel,       logMode)
    setVis(f.numberedCB,        logMode)
    setVis(f.numberedLabel,     logMode)
    setVis(f.clearLogBtn,       logMode)

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

    setVis(f.altInputAlt,       altsMode)
    setVis(f.altInputMain,      altsMode)
    setVis(f.altInputAltLabel,  altsMode)
    setVis(f.altInputMainLabel, altsMode)
    setVis(f.altBtnSet,         altsMode)
    setVis(f.altBtnUnset,       altsMode)

    setVis(f.macroMsgLabel,  macrosMode)
    setVis(f.macroMsgBg,     macrosMode)
    setVis(f.macroChanLabel, macrosMode)
    setVis(f.macroSaveBtn,   macrosMode)
    for _, b in pairs(f.macroChanBtns or {}) do setVis(b, macrosMode) end
    setVis(f.macroSpamCB, macrosMode)
    setVis(f.macroSpamLabel, macrosMode)
    setVis(f.macroSpamInterval, macrosMode)
    setVis(f.macroSpamMinLabel, macrosMode)
    setVis(f.macroSpamTotalLabel, macrosMode)
    setVis(f.macroSpamTotal, macrosMode)
    setVis(f.macroSpamTotalMinLabel, macrosMode)

    setVis(f.ranksConfigPanel, ranksMode)
    if ranksMode then
        local numRanks = GuildControlGetNumRanks() or 0
        for i = 1, 10 do
            local r = f.rankRows[i]
            if r then
                if i <= numRanks and i > 1 then
                    r.frame:Show()
                    r.nameStr:SetText(GuildControlGetRankName(i))
                else
                    r.frame:Hide()
                end
            end
        end
    end

    setVis(f.batchSizeLabel, settingsMode)
    setVis(f.batchSizeInput, settingsMode)
    setVis(f.openWithGuildCB, settingsMode)
    setVis(f.openWithGuildLabel, settingsMode)
    setVis(f.closeWithGuildCB, settingsMode)
    setVis(f.closeWithGuildLabel, settingsMode)
    setVis(f.showMinimapCB, settingsMode)
    setVis(f.showMinimapLabel, settingsMode)
    setVis(f.minimapCtrlLabel, settingsMode)
    setVis(f.minimapRotSlider, settingsMode)
    setVis(f.minimapRotLabel, settingsMode)
    setVis(f.minimapRotVal, settingsMode)
    setVis(f.minimapRotLow, settingsMode)
    setVis(f.minimapRotHigh, settingsMode)
    setVis(f.minimapDistSlider, settingsMode)
    setVis(f.minimapDistLabel, settingsMode)
    setVis(f.minimapDistVal, settingsMode)
    setVis(f.minimapDistLow, settingsMode)
    setVis(f.minimapDistHigh, settingsMode)
    setVis(f.autoInvLabel, settingsMode)
    setVis(f.autoInvCB, settingsMode)
    setVis(f.autoInvCBLabel, settingsMode)
    setVis(f.autoInvBg, settingsMode)
    setVis(f.aiPhraseBg, settingsMode); setVis(f.aiPhraseLbl, settingsMode)
    setVis(f.aiOnBg, settingsMode); setVis(f.aiOnLbl, settingsMode)
    setVis(f.aiOffBg, settingsMode); setVis(f.aiOffLbl, settingsMode)
    setVis(f.aiMinLvlBg, settingsMode); setVis(f.aiMinLvlLbl, settingsMode)
    setVis(f.aiReplyLowBg, settingsMode); setVis(f.aiReplyLowLbl, settingsMode)
    
    setVis(f.groupInviteLabel, settingsMode)
    local groupInviteMode = settingsMode
    if f.groupInviteCheck then setVis(f.groupInviteCheck, groupInviteMode) end
    if f.groupInviteEditBox then setVis(f.groupInviteEditBox, groupInviteMode); setVis(f.groupInviteEditBoxLabel, groupInviteMode) end
    if f.groupInvitePermCheck then setVis(f.groupInvitePermCheck, groupInviteMode) end
    if f.groupInviteMinLabel then setVis(f.groupInviteMinLabel, groupInviteMode) end
    if f.groupInviteMinutes then setVis(f.groupInviteMinutes, groupInviteMode) end
    if f.groupInviteBg then setVis(f.groupInviteBg, groupInviteMode) end
    setVis(f.blacklistBtn, settingsMode)

    if settingsMode and GManagerDB then
        if not f.batchSizeInput:HasFocus() then
            f.batchSizeInput:SetText(tostring(GManagerDB.batchSize or 2))
        end
        if GManagerDB.autoInvite then
            local conf = GManagerDB.autoInvite
            f.autoInvCB:SetChecked(conf.enabled)
            if not f.aiPhrase:HasFocus() then f.aiPhrase:SetText(conf.phrase or "") end
            if not f.aiOn:HasFocus()     then f.aiOn:SetText(conf.replyOn or "") end
            if not f.aiOff:HasFocus()    then f.aiOff:SetText(conf.replyOff or "") end
            if not f.aiMinLvl:HasFocus() then f.aiMinLvl:SetText(tostring(conf.minLvl or 1)) end
            if not f.aiReplyLow:HasFocus() then f.aiReplyLow:SetText(conf.replyLow or "") end
            if f.groupInviteMinutes and not f.groupInviteMinutes:HasFocus() then
                f.groupInviteMinutes:SetText(tostring(conf.groupMinutes or 15))
            end
        end
    end

    if macrosMode then
        if f.macroSpamCB then f.macroSpamCB:SetChecked(addon.spamActive) end
        if f.macroSpamInterval and not f.macroSpamInterval:HasFocus() then
            f.macroSpamInterval:SetText(tostring(addon.spamInterval or 5))
        end
        if f.macroSpamTotal and not f.macroSpamTotal:HasFocus() then
            local t = (GManagerDB and GManagerDB.spamTotalMinutes) or addon.spamTotalLimit or 0
            f.macroSpamTotal:SetText(tostring(t))
            addon.spamTotalLimit = t
        end
    end

    for view, b in pairs(f.tabButtons) do
        if view == activeView then b:LockHighlight() else b:UnlockHighlight() end
    end

    local key = addon:GetCurrentGuildKey()
    local guildLabel = key and key:gsub("::", " / ") or "(not in a guild)"
    if logMode then f.subtitle:SetText("|cFFFFCC00Guild Roster Event Log|r   " .. guildLabel)
    elseif rosterMode then f.subtitle:SetText("|cFFFFCC00Guild Roster|r   " .. guildLabel)
    elseif macrosMode then f.subtitle:SetText("|cFFFFCC00Saved Macros|r   Account-wide")
    elseif ranksMode  then f.subtitle:SetText("|cFFFFCC00Rank Up Settings|r   " .. guildLabel)
    elseif settingsMode then f.subtitle:SetText("|cFFFFCC00Auto Settings Guild/Group Invites and more|r")
    else f.subtitle:SetText("|cFFFFCC00Alts|r   " .. guildLabel) end

    local data, total, onlineCount = {}, 0, 0
    if settingsMode then
        f.rightHeader:SetText(("Version |cffffffff%s|r"):format(addon.version or "?"))
        f.rightHeader:Show()
        f.rrightHeader:SetText("")
        f.rrightHeader:Hide()
        if GManagerCharDB then
            f.openWithGuildCB:SetChecked(GManagerCharDB.openWithGuild)
            f.closeWithGuildCB:SetChecked(GManagerCharDB.closeWithGuild)
        end
        if f.showMinimapCB then
            f.showMinimapCB:SetChecked(GManagerDB.showMinimapButton ~= false)
        end
        if f.minimapRotSlider then
            local r = GManagerDB.minimapRotation or 0
            f.minimapRotSlider:SetValue(r)
            if f.minimapRotVal then f.minimapRotVal:SetText(tostring(r)) end
        end
        if f.minimapDistSlider then
            local d = math.max(20, math.min(240, GManagerDB.minimapDistance or 80))
            if GManagerDB then GManagerDB.minimapDistance = d end
            f.minimapDistSlider:SetValue(d)
            if f.minimapDistVal then f.minimapDistVal:SetText(tostring(d)) end
        end
    elseif logMode then
        data, total = collectLogRows()
        f.rightHeader:SetText(("Total Entries: |cffffffff%d|r"):format(total))
    elseif rosterMode then
        data, onlineCount, total = collectRosterRows()
        addon.RosterRowsCache = data
        f.rightHeader:SetText(("|cffffffff%d|r / %d Online"):format(onlineCount, total))
    elseif ranksMode then
        data = collectRanksRows()
        addon.RanksRowsCache = data
        f.rightHeader:SetText(("|cffffffff%d|r Candidates matching criteria"):format(#data))
    elseif macrosMode then
        data = collectMacrosRows()
        local filtered = {}
        for _, m in ipairs(data) do
            if m.channel == macroSelectedChannel then
                table.insert(filtered, m)
            end
        end
        data = filtered
        f.rightHeader:SetText(("|cffffffff%d|r macros  -  channel: |cffffcc00%s|r"):format(#data, macroSelectedChannel))
    else
        data = collectAltsRows()
        f.rightHeader:SetText(("|cffffffff%d|r mappings"):format(#data))
    end

    if macrosMode then
        for opt, b in pairs(f.macroChanBtns) do
            if opt == macroSelectedChannel then b:LockHighlight() else b:UnlockHighlight() end
            local fs = b:GetFontString()
            if fs then fs:SetTextColor(1, 0.8, 0) end
        end
    end

    if not settingsMode then
        local count = #data
        FauxScrollFrame_Update(f.scroll, count, ROW_COUNT, ROW_HEIGHT)
        local offset = FauxScrollFrame_GetOffset(f.scroll)

        if rosterMode or ranksMode then
            local mark = rosterSortReverse and "  v" or "  ^"
            for _, def in ipairs(COL_DEFS) do
                local label = def.label
                if rosterSortBy == def.sort then label = label .. mark end
                f.colHeaderBtns[def.key]:SetText(label)
                local fs = f.colHeaderBtns[def.key]:GetFontString()
                if fs then fs:SetTextColor(1, 0.8, 0) end
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
            if btns then btns.send:Hide(); btns.del:Hide(); btns.edit:Hide(); btns.set:Hide() end
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
                        for _, m in pairs(g.alts) do if m == r.name then mainTag = "  |cffffcc00<M>|r"; break end end
                    end
                end
                local whiteTag = addon:IsWhitelisted(r.name) and " |cff00ff00[W]|r" or ""
                cells.name:SetText(classColor(r.classFile, r.name) .. mainTag .. whiteTag)

                local onlineRaw = r.online and "Online" or fmtSince(r.lastSeen)
                cells.online:SetText(lastSeenColor(r.lastSeen, r.online) .. onlineRaw .. "|r")

                if r.joinDate then cells.join:SetText("|cffcccccc" .. r.joinDate .. "|r") else cells.join:SetText("|cff666666?|r") end

                cells.rank:SetText(r.rank or "")
                cells.note:SetText(r.note or "")
                cells.onote:SetText(r.officerNote or "")

                if activeCols then
                    for _, col in ipairs(activeCols) do
                        cells[col.key]:Show()
                    end
                end

                local clickBtn = f.rowClickBtns[i]
                if clickBtn then
                    local rowName = r.name
                    clickBtn:SetScript("OnClick", function(_, button)
                        if button == "RightButton" then
                            showRosterContextMenu(rowName)
                        elseif button == "LeftButton" then
                            addon:ShowMemberDetail(rowName)
                        end
                    end)
                    clickBtn:Show()
                end
            elseif altsMode then
                hideCells(i)
                hideMacroBtns(i)
                hideClickBtn(i)
                local row = f.rows[i]
                row:SetPoint("RIGHT", f.scroll, "RIGHT", -4, 0)
                row:SetText(("|cffffffff%s|r  |cff888888is alt of|r  |cffffcc00%s|r"):format(item.alt, item.main))
                row:Show()
            elseif macrosMode then
                hideCells(i)
                hideClickBtn(i)
                local row = f.rows[i]
                local btns = f.rowMacroBtns[i]
                row:SetPoint("RIGHT", btns.edit, "LEFT", -6, 0)

                local isSpam = addon.spamMacros and addon.spamMacros[item.index]
                local tag = isSpam and " |cff00ff00[SPAM]|r" or ""
                row:SetText(item.text .. tag)
                row:Show()
                btns.send:Show(); btns.del:Show(); btns.edit:Show(); btns.set:Show()

                btns.set:SetText(isSpam and "|cff00ff00On|r" or "|cFFFFCC00Set|r")
                local fs = btns.set:GetFontString()
                if fs then fs:SetTextColor(1, 0.8, 0) end

                -- force yellow for send/del/edit/set (On stays green)
                for _, btnName in ipairs({"send", "del", "edit"}) do
                    local b = btns[btnName]
                    local bfs = b and b:GetFontString()
                    if bfs then bfs:SetTextColor(1, 0.8, 0) end
                end
                if not isSpam then
                    local b = btns.set
                    local bfs = b and b:GetFontString()
                    if bfs then bfs:SetTextColor(1, 0.8, 0) end
                end

                local idx = item.index
                local txt = item.text
                local chan = item.channel
                btns.send:SetScript("OnClick", function() addon:SendMacro(idx) end)
                btns.del:SetScript("OnClick", function()
                    addon:RemoveMacro(idx)
                    if addon.spamMacros then
                        local newSpam = {}
                        for oldIdx, active in pairs(addon.spamMacros) do
                            if active then
                                if oldIdx < idx then newSpam[oldIdx] = true
                                elseif oldIdx > idx then newSpam[oldIdx - 1] = true end
                            end
                        end
                        addon.spamMacros = newSpam

                        local hasActive = false
                        for k, v in pairs(addon.spamMacros) do if v then hasActive = true; break end end
                        if not hasActive and addon.spamActive then
                            addon.spamActive = false
                            addon.spamTotalElapsed = 0
                            if f.macroSpamCB then f.macroSpamCB:SetChecked(false) end
                        end
                    end
                    UI:Refresh()
                end)
                btns.edit:SetScript("OnClick", function()
                    local currentMsg = f.macroMsg:GetText() or ""
                    if currentMsg == "" then
                        f.macroMsg:SetText(txt)
                        macroSelectedChannel = chan
                        addon.editingMacroIndex = idx
                        UI:Refresh()
                    else
                        print("|cFFFFCC00GManager|r: Clear the message box first to edit.")
                    end
                end)
                btns.set:SetScript("OnClick", function()
                    addon.spamMacros = addon.spamMacros or {}
                    addon.spamMacros[idx] = not addon.spamMacros[idx]

                    if addon.spamMacros[idx] then
                        print("|cFFFFCC00GManager|r: Macro added to spam rotation.")
                    else
                        print("|cFFFFCC00GManager|r: Macro removed from spam rotation.")
                        local hasActive = false
                        for k, v in pairs(addon.spamMacros) do if v then hasActive = true; break end end
                        if not hasActive and addon.spamActive then
                            addon.spamActive = false
                            if f.macroSpamCB then f.macroSpamCB:SetChecked(false) end
                            print("|cFFFFCC00GManager|r: No macros selected, spam disabled.")
                        end
                    end
                    UI:Refresh()
                end)
            end
        end
    end
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
    if blacklistFrame then blacklistFrame:Hide() end
end

-- =========================================================
-- Blacklist Management Window (account-wide, for Auto Group + Guild Invite)
-- =========================================================
local blacklistFrame
local blRows = {}
local BL_ROW_HEIGHT = 18
local MAX_BL_ROWS = 25

local function positionBlacklistWindow(f)
    if frame and frame:IsShown() then
        f:ClearAllPoints()
        f:SetPoint("TOPLEFT", frame, "TOPRIGHT", 6, 0)
        f:SetHeight(frame:GetHeight())
        f:SetWidth(390)
    else
        f:ClearAllPoints()
        f:SetPoint("CENTER", UIParent, "CENTER", 0, 60)
    end
end

local function buildBlacklistWindow()
    if blacklistFrame then return blacklistFrame end

    local f = CreateFrame("Frame", "GManagerBlacklistFrame", UIParent)
    f:SetSize(390, 480)
    f:SetPoint("CENTER", 0, 60)
    f:SetBackdrop(BACKDROP)
    f:SetBackdropColor(0, 0, 0, 1)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:SetClampedToScreen(true)
    f:SetFrameStrata("HIGH")
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("|cFFFFCC00Blacklist|r  |cffaaaaaa(Auto Guild + Group Invite)|r")

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", 2, 2)

    -- Name input
    local nameLabel = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    nameLabel:SetPoint("TOPLEFT", 21, -48)
    nameLabel:SetText("Player Name")

    local nameInput = CreateFrame("EditBox", "GManagerBLNameInput", f, "InputBoxTemplate")
    nameInput:SetSize(180, 20)
    nameInput:SetPoint("TOPLEFT", nameLabel, "BOTTOMLEFT", 2, -2)
    nameInput:SetAutoFocus(false)
    nameInput:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    nameInput:SetScript("OnEnterPressed", function(self)
        local n = self:GetText()
        if n and n ~= "" then
            addon:AddToBlacklist(n)
            self:SetText("")
        end
        self:ClearFocus()
        UI:RefreshBlacklistWindow()
    end)

    local addBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    addBtn:SetSize(60, 22)
    addBtn:SetText("|cFFFFCC00Add|r")
    local fs = addBtn:GetFontString()
    if fs then fs:SetTextColor(1, 0.8, 0) end
    addBtn:SetPoint("LEFT", nameInput, "RIGHT", 8, 0)
    addBtn:SetScript("OnClick", function()
        local n = nameInput:GetText()
        if n and n ~= "" then
            addon:AddToBlacklist(n)
            nameInput:SetText("")
            nameInput:ClearFocus()
            UI:RefreshBlacklistWindow()
        end
    end)

    -- List container
    local listPanel = CreateFrame("Frame", nil, f)
    listPanel:SetPoint("TOPLEFT", 16, -85)
    listPanel:SetPoint("BOTTOMRIGHT", -16, 90)
    listPanel:SetBackdrop(PANEL_BACKDROP)
    listPanel:SetBackdropColor(0, 0, 0, 0.6)

    local scroll = CreateFrame("ScrollFrame", "GManagerBLScroll", listPanel, "FauxScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -26, 4)
    scroll:SetScript("OnVerticalScroll", function(self, offset)
        FauxScrollFrame_OnVerticalScroll(self, offset, BL_ROW_HEIGHT, function() UI:RefreshBlacklistWindow() end)
    end)

    -- Row pool (create more than visible so we can handle taller windows / scrolling)
    for i = 1, MAX_BL_ROWS do
        local rowY = -((i - 1) * BL_ROW_HEIGHT) - 1

        local row = listPanel:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        row:SetPoint("TOPLEFT", scroll, "TOPLEFT", 6, rowY)
        row:SetPoint("RIGHT", scroll, "RIGHT", -58, 0)
        row:SetHeight(BL_ROW_HEIGHT)
        row:SetJustifyH("LEFT")

        local remBtn = CreateFrame("Button", nil, listPanel, "UIPanelButtonTemplate")
        remBtn:SetSize(68, BL_ROW_HEIGHT - 2)
        remBtn:SetText("|cFFFFCC00Rem|r")
        local rfs = remBtn:GetFontString()
        if rfs then rfs:SetTextColor(1, 0.8, 0) end
        remBtn:SetPoint("TOPRIGHT", scroll, "TOPRIGHT", -2, rowY)

        blRows[i] = { label = row, rem = remBtn }
    end

    -- Autoresponse section
    local arLabel = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    arLabel:SetPoint("BOTTOMLEFT", 24, 72)
    arLabel:SetText("|cFFFFCC00Autoresponse (sent to blacklisted players on trigger)|r")
    arLabel:SetTextColor(1, 0.8, 0)

    local arBg = CreateFrame("Frame", nil, f)
    arBg:SetPoint("TOPLEFT", arLabel, "BOTTOMLEFT", -6, -2)
    arBg:SetPoint("BOTTOMRIGHT", -18, 22)
    arBg:SetBackdrop(PANEL_BACKDROP)
    arBg:SetBackdropColor(0, 0, 0, 0.7)
    arBg:SetBackdropBorderColor(0.5, 0.5, 0.5, 1)

    local arEdit = CreateFrame("EditBox", "GManagerBLReplyEdit", arBg)
    arEdit:SetFontObject("ChatFontSmall")
    arEdit:SetAutoFocus(false)
    arEdit:SetMultiLine(true)
    arEdit:SetMaxLetters(255)
    arEdit:SetPoint("TOPLEFT", 6, -4)
    arEdit:SetPoint("BOTTOMRIGHT", -6, 4)
    arEdit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)

    local saveReplyBtn = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
    saveReplyBtn:SetSize(70, 20)
    saveReplyBtn:SetText("|cFFFFCC00Save|r")
    local sfs = saveReplyBtn:GetFontString()
    if sfs then sfs:SetTextColor(1, 0.8, 0) end
    saveReplyBtn:SetPoint("BOTTOMRIGHT", -18, 6)
    saveReplyBtn:SetScript("OnClick", function()
        local txt = arEdit:GetText() or ""
        addon:SetBlacklistReply(txt)
        print("|cFFFFCC00GManager|r: Blacklist autoresponse saved.")
    end)

    f.arEdit = arEdit
    f.scroll = scroll
    f.nameInput = nameInput

    _G["GManagerBlacklistFrame"] = f
    table.insert(UISpecialFrames, "GManagerBlacklistFrame")

    f:HookScript("OnShow", function()
        positionBlacklistWindow(f)
        UI:RefreshBlacklistWindow()
    end)

    blacklistFrame = f
    return f
end

function UI:RefreshBlacklistWindow()
    local f = blacklistFrame
    if not f or not f:IsShown() then return end

    -- populate reply
    if f.arEdit and not f.arEdit:HasFocus() then
        f.arEdit:SetText(addon:GetBlacklistReply() or "")
    end

    local data = addon:GetBlacklist() or {}
    local count = #data

    local scrollH = (f.scroll and f.scroll:GetHeight()) or 290
    local visible = math.max(1, math.floor((scrollH + 2) / BL_ROW_HEIGHT))
    visible = math.min(visible, MAX_BL_ROWS)

    FauxScrollFrame_Update(f.scroll, count, visible, BL_ROW_HEIGHT)
    local offset = FauxScrollFrame_GetOffset(f.scroll)

    for i = 1, MAX_BL_ROWS do
        local row = blRows[i]
        if not row then break end

        if i > visible then
            row.label:Hide()
            row.rem:Hide()
            row.rem:SetScript("OnClick", nil)
        else
            local idx = i + offset
            local item = data[idx]
            if not item then
                row.label:SetText("")
                row.label:Hide()
                row.rem:Hide()
                row.rem:SetScript("OnClick", nil)
            else
                local display = item:sub(1,1):upper() .. item:sub(2)
                row.label:SetText("|cffffffff" .. display .. "|r")
                row.label:Show()

                local nameKey = item
                row.rem:Show()
                row.rem:SetScript("OnClick", function()
                    addon:RemoveFromBlacklist(nameKey)
                    UI:RefreshBlacklistWindow()
                end)
            end
        end
    end
end

function UI:ShowBlacklistWindow()
    local f = buildBlacklistWindow()
    if not f then return end

    positionBlacklistWindow(f)
    f:Show()
    if f.Raise then f:Raise() end
    UI:RefreshBlacklistWindow()
end

function UI:ToggleBlacklistWindow()
    local f = buildBlacklistWindow()
    if not f then return end
    if f:IsShown() then
        f:Hide()
    else
        UI:ShowBlacklistWindow()
    end
end
