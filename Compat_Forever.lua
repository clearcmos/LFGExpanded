local _, addon = ...
local Compat = {}
addon.Compat = Compat

local raw = {
    info = C_LFGList.GetSearchResultInfo,
    player = C_LFGList.GetSearchResultPlayerInfo,
    counts = C_LFGList.GetSearchResultMemberCounts,
    leader = C_LFGList.GetSearchResultLeaderInfo,
}

function Compat.Accessible(value)
    if issecretvalue and issecretvalue(value) then return false end
    if canaccessvalue and not canaccessvalue(value) then return false end
    if type(value) == "table" and canaccesstable and not canaccesstable(value) then return false end
    return true
end

local function CopyFields(value, fields)
    if not Compat.Accessible(value) then Compat.blocked = true; return nil end
    if value == nil then return nil end
    local copy = {}
    for _, key in ipairs(fields) do
        local field = value[key]
        if not Compat.Accessible(field) then Compat.blocked = true; return nil end
        copy[key] = field
    end
    return copy
end

local function ReadPlayer(fn, ...)
    local value = fn(...)
    local copy = CopyFields(value, { "classFilename", "level", "assignedRole", "name" })
    if not copy then return nil end
    local roles = CopyFields(value.lfgRoles, { "tank", "healer", "dps" })
    if Compat.blocked then return nil end
    copy.lfgRoles = roles
    return copy
end

function Compat.GetSearchResultInfo(id)
    return CopyFields(raw.info(id), { "numMembers", "comment", "leaderName" })
end
function Compat.GetSearchResultPlayerInfo(id, index)
    return ReadPlayer(raw.player, id, index)
end
function Compat.GetSearchResultMemberCounts(id)
    return CopyFields(raw.counts(id), { "TANK", "HEALER", "DAMAGER" })
end
function Compat.GetSearchResultLeaderInfo(id)
    return ReadPlayer(raw.leader, id)
end

-- Check before mutating results. Never filter a partly inaccessible result set.
function Compat.PrepareResults(results)
    Compat.blocked = false
    if not Compat.Accessible(results) then return false end
    for _, id in ipairs(results or {}) do
        if not Compat.Accessible(id) then return false end
        local info = Compat.GetSearchResultInfo(id)
        if Compat.blocked then return false end
        if info then
            if type(info.numMembers) ~= "number" then return false end
            for index = 1, info.numMembers do
                if not Compat.GetSearchResultPlayerInfo(id, index) then return false end
            end
            if info.numMembers > 1 and not Compat.GetSearchResultMemberCounts(id) then return false end
        end
    end
    return not Compat.blocked
end

function Compat.GetMaxLevel()
    return GetMaxPlayerLevel()
end

function Compat.IsCategorySupported(category)
    -- Forever category IDs from its VanillaStyle constants, independent of locale.
    return category == 2 or category == 114
end

-------------------------------------------------------------------------------
-- UI: Forever's own group finder art (Blizzard_GroupFinder_VanillaStyle,
-- Mainline family) so the panel reads as part of the native window.
-------------------------------------------------------------------------------

local PANEL_WIDTH = 368
local INSET_TOP = -124        -- below the role buttons and show checkboxes
local BUTTON_BAR_HEIGHT = 61  -- native BarMiddle offset above the bottom edge
local TAB_ICON = "Interface\\ICONS\\Ability_Hunter_SniperShot"
local ROLE_ATLAS = { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" }

-- Native list rows are 52 to 72 px tall; 36 keeps their art from squashing
-- and still fits all nine classes above the button bar.
Compat.CLASS_ROW_HEIGHT = 36

-- Hide class rows no click could fill; rows with an active filter stay.
Compat.HIDE_EMPTY_CLASSES = true

-- A min/max level range in place of the Max level checkbox.
Compat.LEVEL_RANGE = true

-- Keep filters across sessions in LFGExpandedDB (declared by the Forever TOC).
Compat.PERSIST_FILTERS = true

-- The solo-listing checkbox uses the native browser's header for that section.
Compat.SINGLES_LABEL = "Players"

function Compat.CreatePanel(parent)
    local panel = CreateFrame("Frame", "LFGExpandedPanel", parent, "DefaultPanelTemplate")
    panel:SetSize(PANEL_WIDTH, parent:GetHeight())
    -- Sit beside the native side tabs (Create Listing, Browse, Who) rather than over them.
    local tab = parent.ListingTab
    panel:SetPoint("TOPLEFT", parent, "TOPRIGHT", (tab and tab:GetWidth() or 0) + 2, 0)
    panel:EnableMouse(true)

    -- Header: the stone behind the native listing's role buttons.
    local header = panel:CreateTexture(nil, "BACKGROUND", nil, -5)
    header:SetAtlas("groupfinder-roles-background")
    header:SetPoint("TOPLEFT", 2, -21)
    header:SetPoint("BOTTOMRIGHT", panel, "TOPRIGHT", -2, INSET_TOP - 7)

    -- Inset: the same background and inner frame as the native result list.
    local insetBg = panel:CreateTexture(nil, "BACKGROUND", nil, -4)
    insetBg:SetAtlas("groupfinder-background")
    insetBg:SetPoint("TOPLEFT", 7, INSET_TOP - 3)
    insetBg:SetPoint("BOTTOMRIGHT", -7, 6)
    local insetBorder = panel:CreateTexture(nil, "BORDER")
    insetBorder:SetAtlas("common-insideframe")
    insetBorder:SetPoint("TOPLEFT", 4, INSET_TOP + 2)
    insetBorder:SetPoint("BOTTOMRIGHT", -4, 3)

    local bar = panel:CreateTexture(nil, "ARTWORK")
    bar:SetAtlas("groupfinder-ScrollLine", true)
    bar:SetPoint("LEFT", panel, "BOTTOMLEFT", 4, BUTTON_BAR_HEIGHT)
    bar:SetPoint("RIGHT", panel, "BOTTOMRIGHT", -4, BUTTON_BAR_HEIGHT)
    return panel
end

-- Reposition the shared controls to the native frame's anchors.
function Compat.LayoutPanel(panel, parts)
    parts.title:Hide()
    panel:SetTitle("Filters")

    if UIPanelCloseButtonDefaultAnchorsMixin then
        UIPanelCloseButtonDefaultAnchorsMixin.OnLoad(parts.close)
    else
        parts.close:ClearAllPoints()
        parts.close:SetPoint("TOPRIGHT", 0, 3)
    end

    parts.info:ClearAllPoints()
    parts.info:SetPoint("TOPRIGHT", -10, -28)

    -- Same size and offsets as Send Message and Group Invite.
    parts.search:SetSize(111, 28)
    parts.search:ClearAllPoints()
    parts.search:SetPoint("BOTTOMLEFT", 21, 16)
    parts.reset:SetSize(109, 28)
    parts.reset:ClearAllPoints()
    parts.reset:SetPoint("BOTTOMRIGHT", -21, 16)
end

-- The role icons of Forever's Create Listing tab.
function Compat.StyleRoleButton(btn, role)
    local atlas = "UI-LFG-RoleIcon-" .. ROLE_ATLAS[role]
    btn.icon:SetTexCoord(0, 1, 0, 1)
    btn.icon:SetAtlas(atlas)
    btn.bg:SetTexCoord(0, 1, 0, 1)
    btn.bg:SetAtlas(atlas .. "-Background")
    btn.bg:SetSize(60, 60)
end

-- The list-row art, class icons and selection of the native result list.
function Compat.StyleClassRow(row, class)
    row.icon:SetTexCoord(0, 1, 0, 1)
    row.icon:SetAtlas("groupfinder-icon-class-" .. class:lower())
    row.icon:SetSize(22, 22)
    row.bg:SetAtlas("common-button-list-mid2")
    row.hl:SetAtlas("common-button-list-mid2-hover")
    row.hl:SetAlpha(1)
    local selected = row:CreateTexture(nil, "BORDER")
    selected:SetAtlas("common-button-list-mid2-selected")
    selected:SetBlendMode("ADD")
    selected:SetAllPoints(row.bg)
    selected:Hide()
    row.selected = selected
end

-- A fourth side tab under Blizzard's three; it shows as selected while the panel is open.
function Compat.CreateToggle(parent, panel, click)
    local tab = CreateFrame("Frame", "LFGExpandedForeverToggle", parent, "LargeSideTabButtonTemplate")
    tab.tooltipText = "Filters"
    tab.Icon:SetTexture(TAB_ICON)
    tab:SetFillToInterior(true)
    if parent.WhoListingTab then
        tab:SetPoint("TOPLEFT", parent.WhoListingTab, "BOTTOMLEFT", 0, -2)
    else
        tab:SetPoint("TOPLEFT", parent, "TOPRIGHT", 0, -60)
    end
    tab:SetCustomOnMouseUpHandler(function(_, button, upInside)
        if button == "LeftButton" and upInside then click() end
    end)
    local function Sync() tab:SetChecked(panel:IsShown()) end
    panel:HookScript("OnShow", Sync)
    panel:HookScript("OnHide", Sync)
    Sync()
    return tab
end

-------------------------------------------------------------------------------
-- Native listing tooltip: where people are. The API returns each player's zone
-- as LfgSearchResultPlayerInfo.areaName, but Blizzard's tooltip never shows it.
-- A single player gets a Location line between Members and Voice Chat
-- (activities follow Voice Chat); a group gets a zone column on each member row.
-------------------------------------------------------------------------------

-- Subzones show as their zone. SUBZONES (generated at the end of this file from
-- the client's AreaTable) lists area IDs; the names are read in the client's
-- language on first use. A name under two zones (border lakes, passes, seas)
-- and a name that is itself a zone (a dungeon and its entrance) stay as they are.
local SUBZONES
local zoneOfArea

local function AreaName(id)
    local name = C_Map and C_Map.GetAreaInfo and C_Map.GetAreaInfo(id)
    if type(name) == "string" and name ~= "" then return name end
end

local function ZoneOf(area)
    if not zoneOfArea then
        zoneOfArea = {}
        local zones = {}
        for zoneID, ids in pairs(SUBZONES) do
            local zone = AreaName(zoneID)
            if zone then
                zones[zone] = true
                for _, id in ipairs(ids) do
                    local name = AreaName(id)
                    if name then
                        local known = zoneOfArea[name]
                        if known == nil then
                            zoneOfArea[name] = zone
                        elseif known ~= zone then
                            zoneOfArea[name] = false  -- under two zones
                        end
                    end
                end
            end
        end
        for zone in pairs(zones) do zoneOfArea[zone] = nil end
    end
    return zoneOfArea[area] or area
end

local function ReadZone(info)
    if type(info) ~= "table" or not Compat.Accessible(info) then return nil end
    local area = info.areaName
    if not Compat.Accessible(area) or type(area) ~= "string" or area == "" then return nil end
    return ZoneOf(area)
end

local function ReadName(info)
    if type(info) ~= "table" or not Compat.Accessible(info) then return nil end
    local name = info.name
    if not Compat.Accessible(name) or type(name) ~= "string" or name == "" then return nil end
    return name
end

local function ReadMemberCount(resultID)
    local info = raw.info(resultID)
    if type(info) ~= "table" or not Compat.Accessible(info) then return 0 end
    local count = info.numMembers
    if not Compat.Accessible(count) or type(count) ~= "number" then return 0 end
    return count
end

-- Name to zone for every member whose name and zone are readable.
local function ReadMemberZones(resultID)
    local zones = {}
    for index = 1, ReadMemberCount(resultID) do
        local member = raw.player(resultID, index)
        local name, zone = ReadName(member), ReadZone(member)
        if name and zone then zones[name] = zone end
    end
    return zones
end

-------------------------------------------------------------------------------
-- Member lookups. The server sends a zone for the group leader only (seen
-- 2026-11-20), so a left click on a group listing looks up its next unknown
-- member with /who. SendWho needs a click (a hardware event), and the server
-- silently drops a query sent too soon after another, with a limit Blizzard
-- does not publish. So lookups are spaced: after each one the rows count down
-- before the next click sends. On 2026-11-20 every query 5.8 s or more after
-- the previous one answered in 0.3 s, and one sent 100 s after the previous
-- got no answer, so a missing answer is not taken as throttling. An exact-name
-- query answers in chat while the Who list is hidden: one result line and a
-- total, which are parsed and kept out of chat.
-------------------------------------------------------------------------------

local LOOKUP_TTL = 300      -- seconds a looked-up zone is shown before it counts as unknown
local LOOKUP_TIMEOUT = 5    -- seconds without an answer before a query counts as dropped
local LATE_WINDOW = 60      -- seconds a dropped query's answer is still accepted
local SUPPRESS_WINDOW = 1   -- seconds after an answer during which its chat lines stay hidden
local SPACING = 5           -- seconds between queries
local MAX_MEMBER_ROWS = 10  -- Blizzard's tooltip lists members only up to this group size
local lookup = {
    cache = {},             -- name key -> { zone = string or false (not found), time = seconds }
    dropped = {},           -- name key -> time of a query that got no answer
    token = 0,
    sentAt = nil,
    suppressUntil = 0,
    cooldownUntil = 0,      -- no query before this time
    changed = function() end,
}

local function NameKey(name)
    return (name:gsub("%-.*$", "")):lower()  -- drop a realm suffix
end

-- A client format string compiled to an anchored pattern. Each %s or %d
-- captures, and args lists which argument each capture holds: placeholders may
-- be numbered (%2$s, Russian) and so out of order. A declension block
-- (|3-6(%4$s), Russian) captures the declined word; a plural block
-- (|4player:players;) matches either form.
local compiled = {}
local function Compile(format)
    local entry = compiled[format]
    if entry then return entry end
    local parts, args, last, index = { "^" }, {}, 0, 1
    local function Capture(position, kind)
        local arg = tonumber(position) or (#args + 1)
        args[#args + 1] = arg
        if arg > last then last = arg end
        parts[#parts + 1] = kind == "d" and "(%d+)" or "(.-)"
    end
    while index <= #format do
        local position, kind, stop = format:match("^%%(%d+)%$([sd])()", index)
        if not stop then kind, stop = format:match("^%%([sd])()", index) end
        if stop then
            Capture(position, kind)
        else
            position, stop = format:match("^|3%-%d+%(%%(%d+)%$[sd]%)()", index)
            if not stop then stop = format:match("^|3%-%d+%(%%[sd]%)()", index) end
            if stop then
                Capture(position, "s")
            else
                stop = format:match("^|4[^;]*;()", index)
                if stop then
                    parts[#parts + 1] = ".-"
                else
                    local char = format:sub(index, index)
                    parts[#parts + 1] = char:find("^[%(%)%.%+%-%*%?%[%]%^%$%%]") and "%" .. char or char
                    stop = index + 1
                end
            end
        end
        index = stop
    end
    parts[#parts + 1] = "$"
    entry = { pattern = table.concat(parts), args = args, last = last }
    compiled[format] = entry
    return entry
end

-- The arguments a client format string was filled with to produce text, by
-- argument number (with .last, the highest), or nil when text is not that format.
function Compat.MatchFormat(format, text)
    if type(format) ~= "string" then return nil end
    local entry = Compile(format)
    local captures = { text:match(entry.pattern) }
    if #captures == 0 then return nil end
    local values = { last = entry.last }
    for index, arg in ipairs(entry.args) do values[arg] = captures[index] end
    return values
end

-- A who result line: the link name, the shown name and the zone (always the last argument).
local function MatchResult(text)
    local values = Compat.MatchFormat(WHO_LIST_GUILD_FORMAT, text) or Compat.MatchFormat(WHO_LIST_FORMAT, text)
    if values and values.last >= 3 and values[1] and values[2] and values[values.last] then
        return values[1], values[2], values[values.last]
    end
end

local function IsName(key, linkName, shownName)
    return key ~= nil and (NameKey(linkName) == key or NameKey(shownName) == key)
end

-- The key of a recently dropped query this result answers, if any.
local function DroppedKey(linkName, shownName)
    for key, at in pairs(lookup.dropped) do
        if GetTime() - at <= LATE_WINDOW and IsName(key, linkName, shownName) then return key end
    end
end

local function IsTotal(text)
    return Compat.MatchFormat(WHO_NUM_RESULTS, text) ~= nil
end

-- Seconds the server asks to wait, or nil when the text is no cooldown message.
local function MatchCooldown(text)
    local values = Compat.MatchFormat(WHO_COOLDOWN, text)
    if values then return tonumber(values[1]) or 1 end
    if Compat.MatchFormat(WHO_COOLDOWN_SHORT, text) then return 1 end
end

-- A cached zone, false for not found, nil when unknown or expired.
local function CachedZone(name)
    local entry = lookup.cache[NameKey(name)]
    if entry and GetTime() - entry.time < LOOKUP_TTL then return entry.zone end
    return nil
end

-- What the row of the member the next click looks up shows.
local function LookupStatus(name)
    if NameKey(name) == lookup.pending then return "Looking up..." end
    local wait = lookup.cooldownUntil - GetTime()
    if wait > 0 then return string.format("Wait %ds", math.ceil(wait)) end
    if lookup.dropped[NameKey(name)] then return "No answer, click to retry" end
    return "Click to look up"
end

-- Redraws the rows once a second until the next query may be sent.
local function Countdown()
    lookup.changed()
    local remaining = lookup.cooldownUntil - GetTime()
    if remaining > 0 then
        C_Timer.After(math.min(1, remaining), Countdown)
    else
        lookup.counting = false
    end
end

local function WaitUntil(deadline)
    lookup.cooldownUntil = math.max(lookup.cooldownUntil, deadline)
    if not lookup.counting and lookup.cooldownUntil > GetTime() then
        lookup.counting = true
        C_Timer.After(math.min(1, lookup.cooldownUntil - GetTime()), Countdown)
    end
end

-- zone: a string, false for not found, or nil when the query got no zone.
local function FinishLookup(zone)
    if not lookup.pending then return end
    if zone ~= nil then lookup.cache[lookup.pending] = { zone = zone, time = GetTime() } end
    lookup.pending = nil
    lookup.token = lookup.token + 1
    lookup.changed()
end

local function OnSystemMessage(_, event, text)
    if event ~= "CHAT_MSG_SYSTEM" then return end
    if not Compat.Accessible(text) or type(text) ~= "string" then return end
    local linkName, shownName, zone = MatchResult(text)
    if linkName then
        if IsName(lookup.pending, linkName, shownName) then
            lookup.suppressUntil = GetTime() + SUPPRESS_WINDOW
            lookup.answered = lookup.pending
            FinishLookup(ZoneOf(zone))
        else
            local key = DroppedKey(linkName, shownName)
            if key then  -- the answer to a query that timed out
                lookup.suppressUntil = GetTime() + SUPPRESS_WINDOW
                lookup.answered = key
                lookup.cache[key] = { zone = ZoneOf(zone), time = GetTime() }
                lookup.dropped[key] = nil
                lookup.changed()
            end
        end
    elseif lookup.pending and IsTotal(text) then
        lookup.suppressUntil = GetTime() + SUPPRESS_WINDOW
        lookup.answered = nil
        FinishLookup(false)
    elseif lookup.pending then
        local wait = MatchCooldown(text)
        if wait then  -- the message stays in chat; the rows count down
            WaitUntil(GetTime() + wait)
            FinishLookup(nil)
        end
    end
end

-- Hides this addon's who lines: the answer to the pending query, to one just
-- consumed (this runs once per chat frame, before or after OnSystemMessage), or
-- to a dropped query still inside its late window. The player's own /who shows.
local function ChatFilter(_, _, text)
    local recent = GetTime() <= lookup.suppressUntil
    if not lookup.pending and not recent and not next(lookup.dropped) then return false end
    if not Compat.Accessible(text) or type(text) ~= "string" then return false end
    local linkName, shownName = MatchResult(text)
    if linkName then
        return IsName(lookup.pending, linkName, shownName)
            or (recent and IsName(lookup.answered, linkName, shownName))
            or DroppedKey(linkName, shownName) ~= nil
    end
    return (lookup.pending ~= nil or recent) and IsTotal(text)
end

-- The member the next click looks up: the first one without a zone that has
-- not been tried, then the one whose unanswered query is oldest, so a member
-- who never answers does not hold up the rest. Blizzard's tooltip lists no
-- members for a group above MAX_MEMBER_ROWS, so those get no lookups.
local function NextUnknownMember(resultID)
    local count = ReadMemberCount(resultID)
    if count < 2 or count > MAX_MEMBER_ROWS then return nil end
    local retry, retryAt
    for index = 1, count do
        local member = raw.player(resultID, index)
        local name = ReadName(member)
        if name and not ReadZone(member) and CachedZone(name) == nil then
            local key = NameKey(name)
            local droppedAt = key ~= lookup.pending and lookup.dropped[key]
            if not droppedAt then return name end
            if not retryAt or droppedAt < retryAt then retry, retryAt = name, droppedAt end
        end
    end
    return retry
end

-- A member row without a zone in the listing: a lookup result, or the lookup
-- status for the one member the next click looks up. Other rows wait their turn.
local function RowStatus(name, nextName)
    local zone = CachedZone(name)
    if zone then return zone end
    if zone == false then return "Not found" end
    if nextName and NameKey(name) == NameKey(nextName) then return LookupStatus(name) end
    if lookup.dropped[NameKey(name)] then return "No answer" end
end

local function WhoListShown()
    return (LFGWhoListFrame and LFGWhoListFrame:IsVisible()) or (WhoFrame and WhoFrame:IsVisible())
end

local function StartLookup(resultID)
    if lookup.pending or not (C_FriendList and C_FriendList.SendWho) then return end
    if GetTime() < lookup.cooldownUntil then return end  -- the rows show the countdown
    local name = NextUnknownMember(resultID)
    if not name then return end
    -- Results sent to the UI would raise Blizzard's Who tab over the browser.
    if not WhoListShown() and C_FriendList.SetWhoToUi then C_FriendList.SetWhoToUi(false) end
    local query = name
    if C_NameUtil and C_NameUtil.ReplaceSurnameSeparatorWithLinkSeparator then
        query = C_NameUtil.ReplaceSurnameSeparatorWithLinkSeparator(name)
    end
    local key = NameKey(name)
    lookup.pending, lookup.last = key, key
    lookup.dropped[key] = nil
    lookup.sentAt = GetTime()
    lookup.token = lookup.token + 1
    local token = lookup.token
    lookup.events:RegisterEvent("CHAT_MSG_SYSTEM")  -- stays registered for late answers
    C_FriendList.SendWho((WHO_TAG_EXACT or "") .. query, Enum.SocialWhoOrigin and Enum.SocialWhoOrigin.Social)
    WaitUntil(lookup.sentAt + SPACING)
    C_Timer.After(LOOKUP_TIMEOUT, function()
        if token ~= lookup.token then return end
        lookup.dropped[lookup.pending] = lookup.sentAt  -- its answer may still come
        FinishLookup(nil)
    end)
    lookup.changed()
end

-- Left clicks on result rows; Blizzard's own click (selection) still runs first.
local function HookResultRows()
    local box = LFGBrowseFrame and LFGBrowseFrame.ScrollBox
    if not (box and box.RegisterCallback and box.ForEachFrame and ScrollBoxListMixin) then return end
    local hooked = setmetatable({}, { __mode = "k" })
    local function OnClick(row, button)
        local id = row.resultID
        if button == "LeftButton" and id and Compat.Accessible(id) then StartLookup(id) end
    end
    local function Hook(row)
        if hooked[row] or not (row.HasScript and row:HasScript("OnClick")) then return end
        hooked[row] = true
        row:HookScript("OnClick", OnClick)
    end
    box:RegisterCallback(ScrollBoxListMixin.Event.OnAcquiredFrame, function(_, row) Hook(row) end, lookup)
    box:ForEachFrame(function(row) Hook(row) end)
end

-- Where a row's role icons end, measured as Blizzard sizes the tooltip.
local function RowContentWidth(row)
    local width = row.Name:GetWidth() + 4 + row.Level:GetWidth() + 4
    for _, icon in ipairs(row.Roles or {}) do
        if icon:IsShown() then width = width + icon:GetWidth() end
    end
    return width
end

function Compat.HookEntryTooltip()
    local tooltip = LFGBrowseSearchEntryTooltip
    if not (tooltip and tooltip.MemberCount and tooltip.VoiceChat and tooltip.Leader and tooltip.LeaderIcon
        and tooltip.memberPool and LFGBrowseSearchEntryTooltip_UpdateAndShow) then return end
    -- Kept in upvalues, not fields: no addon keys on Blizzard's frames.
    local line = tooltip:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    line:SetJustifyH("LEFT")
    line:SetPoint("TOPLEFT", tooltip.MemberCount, "BOTTOMLEFT", 0, -8)
    line:Hide()
    local rowZones = setmetatable({}, { __mode = "k" })  -- member row -> zone font string
    local shownResult

    local function ShowSingle(resultID)
        local area = ReadZone(raw.leader(resultID))
        -- Blizzard anchors Voice Chat to Members and never resets it, so restore it every time.
        tooltip.VoiceChat:SetPoint("TOPLEFT", area and line or tooltip.MemberCount, "BOTTOMLEFT", 0, -8)
        if not area then return end
        line:SetText("Location: |cffffffff" .. area .. "|r")
        line:Show()
        tooltip:SetWidth(math.max(tooltip:GetWidth(), line:GetStringWidth() + 22))
        tooltip:SetHeight(tooltip:GetHeight() + line:GetHeight() + 8)
    end

    local function ShowGroup(resultID)
        tooltip.VoiceChat:SetPoint("TOPLEFT", tooltip.MemberCount, "BOTTOMLEFT", 0, -8)
        local rows = {}
        if tooltip.Leader:IsShown() then rows[1] = tooltip.Leader end
        for row in tooltip.memberPool:EnumerateActive() do rows[#rows + 1] = row end
        local zones = ReadMemberZones(resultID)
        local nextName = NextUnknownMember(resultID)
        -- Rows share a left edge, so one offset lines the zones up as a column.
        local column, widest = 0, 0
        for _, row in ipairs(rows) do column = math.max(column, RowContentWidth(row)) end
        column = column + 8
        for _, row in ipairs(rows) do
            local name = row.Name:GetText()
            local value = Compat.Accessible(name) and type(name) == "string" and name ~= ""
                and (zones[name] or RowStatus(name, nextName))
            if value then
                local text = rowZones[row]
                if not text then
                    text = row:CreateFontString(nil, "ARTWORK", "GameFontDisableSmallLeft")
                    rowZones[row] = text
                end
                text:SetPoint("LEFT", row, "LEFT", column, -1)  -- the Level text's baseline
                text:SetText(value)
                text:Show()
                widest = math.max(widest, text:GetStringWidth())
            end
        end
        if widest > 0 then
            tooltip:SetWidth(math.max(tooltip:GetWidth(), tooltip.LeaderIcon:GetWidth() + column + widest + 22))
        end
    end

    local function Update(resultID)
        shownResult = resultID
        line:Hide()
        for _, text in pairs(rowZones) do text:Hide() end  -- pooled rows are reused
        -- Blizzard shows the leader crown only for groups.
        if tooltip.LeaderIcon:IsShown() then ShowGroup(resultID) else ShowSingle(resultID) end
    end

    hooksecurefunc("LFGBrowseSearchEntryTooltip_UpdateAndShow", function(self, resultID)
        if self == tooltip then Update(resultID) end
    end)

    -- A lookup that starts or ends redraws the zone column of a group tooltip still on screen.
    lookup.changed = function()
        if shownResult and tooltip:IsShown() and tooltip.LeaderIcon:IsShown() then Update(shownResult) end
    end
    lookup.events = CreateFrame("Frame")
    lookup.events:SetScript("OnEvent", OnSystemMessage)
    if ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter then
        ChatFrameUtil.AddMessageEventFilter("CHAT_MSG_SYSTEM", ChatFilter)
    end
    HookResultRows()
end

-------------------------------------------------------------------------------
-- Data: regenerate with tools/zones.py after a client patch.
-------------------------------------------------------------------------------
-- BEGIN GENERATED SUBZONES (tools/zones.py)
-- Client 1.60.1.70959: every top-level zone ID -> its subzone IDs, nested ones included.
SUBZONES = {
    [1] = { 77, 131, 132, 133, 134, 135, 136, 137, 138, 189, 211, 212, 716, 800, 801, 802, 803, 804, 805, 806, 807, 808, 809, 2102, 16741 },
    [3] = { 337, 338, 339, 340, 341, 342, 343, 344, 345, 346, 347, 1517, 1877, 1878, 1879, 1897, 1898 },
    [4] = { 72, 73, 1437, 1438, 1439, 1440, 1441, 1457, 2517 },
    [8] = { 74, 75, 76, 116, 300, 657, 1777, 1778, 1779, 1780, 1797, 1798, 1817, 1978, 2403 },
    [10] = { 13, 32, 42, 93, 94, 121, 241, 242, 243, 244, 245, 492, 536, 576, 799, 856, 1097, 1098, 2098, 2161 },
    [11] = { 118, 150, 205, 298, 299, 309, 836, 881, 1016, 1017, 1018, 1020, 1021, 1022, 1023, 1024, 1025, 1036, 1037, 1038, 1039, 2103, 2104, 2365, 2402, 17716, 17732, 17738 },
    [12] = { 9, 18, 23, 24, 34, 53, 54, 55, 56, 57, 59, 60, 61, 62, 63, 64, 80, 86, 87, 88, 89, 91, 92, 120, 797, 798 },
    [14] = { 362, 363, 364, 365, 366, 367, 368, 369, 370, 371, 372, 373, 374, 375, 393, 407, 410, 638, 639, 640, 814, 816, 817, 1296, 1297, 2320, 2337, 2979 },
    [15] = { 403, 496, 497, 498, 499, 500, 501, 502, 503, 504, 505, 506, 507, 508, 509, 510, 511, 512, 513, 514, 515, 516, 517, 518, 2079, 2158, 2302, 2318 },
    [16] = { 878, 1216, 1217, 1218, 1219, 1220, 1221, 1222, 1223, 1224, 1225, 1226, 1227, 1228, 1229, 1230, 1231, 1232, 1233, 1234, 1235, 1236, 1237, 1256, 2321, 2497, 3137, 3138, 3140, 16234, 16577 },
    [17] = { 359, 378, 379, 380, 381, 382, 383, 384, 385, 386, 387, 388, 390, 391, 392, 401, 458, 720, 815, 877, 1156, 1157, 1316, 1597, 1598, 1599, 1600, 1601, 1602, 1603, 1697, 1698, 1699, 1700, 1701, 1702, 1703, 1704, 1717, 1718, 2138, 2157, 2319, 2757 },
    [21] = {},
    [22] = { 49, 81, 82, 83, 84, 2877 },
    [25] = {},
    [28] = { 190, 192, 193, 195, 196, 197, 198, 199, 200, 201, 202, 203, 813, 2297, 2298, 2620, 3197 },
    [30] = {},
    [33] = { 7, 19, 35, 37, 43, 99, 100, 101, 102, 103, 104, 105, 106, 117, 122, 123, 125, 126, 127, 128, 129, 297, 301, 302, 303, 310, 311, 312, 477, 1577, 1578, 1737, 1738, 1739, 1740, 1741, 1742, 1757, 1758, 1759, 1760, 2177, 2338, 2339, 3357, 17853 },
    [36] = { 277, 278, 279, 280, 281, 282, 283, 284, 1339, 1357, 1677, 1678, 1679, 1680, 1681, 1682, 1683, 1684, 2839, 3486, 17707, 17824 },
    [38] = { 142, 143, 144, 145, 146, 147, 149, 556, 837, 838, 839, 923, 924, 925, 936, 2101 },
    [40] = { 2, 20, 26, 107, 108, 109, 111, 113, 115, 219, 916, 917, 918, 919, 920, 921, 922, 1518, 2364 },
    [41] = { 2558, 2559, 2560, 2561, 2562, 2563, 2697, 2837, 2937, 2938 },
    [44] = { 68, 69, 70, 71, 95, 96, 97, 98, 996, 997, 998, 999, 1000, 1001, 1002, 2099 },
    [45] = { 313, 314, 315, 316, 317, 318, 320, 321, 322, 323, 324, 325, 326, 327, 328, 333, 334, 335, 336, 880, 1837, 1857, 1858, 2401 },
    [46] = { 249, 250, 251, 252, 253, 254, 255, 2417, 2418, 2419, 2420, 2421, 16739 },
    [47] = { 307, 348, 349, 350, 351, 352, 353, 354, 355, 356, 1880, 1881, 1882, 1883, 1884, 1885, 1886, 1887, 1917, 2400, 3317, 16740 },
    [51] = { 246, 247, 1442, 1443, 1444, 1445, 1446, 1957, 1958, 1959, 2838, 15159 },
    [65] = {},
    [66] = {},
    [67] = {},
    [85] = { 152, 153, 154, 155, 156, 157, 158, 159, 160, 161, 162, 163, 164, 165, 166, 167, 168, 169, 173, 459, 810, 811, 812, 2117, 2118, 2119, 2399, 16602, 16616, 16881 },
    [130] = { 172, 204, 213, 226, 227, 228, 229, 230, 231, 232, 233, 235, 236, 237, 238, 239, 240, 305, 306, 926, 927, 928, 1338, 2398 },
    [139] = { 1019, 2258, 2259, 2260, 2261, 2262, 2263, 2264, 2265, 2266, 2267, 2268, 2269, 2270, 2271, 2272, 2273, 2274, 2275, 2276, 2277, 2278, 2279, 2299, 2619, 2621, 2622, 2623, 2624, 2625, 2626, 2627, 16335, 16361 },
    [141] = { 186, 187, 188, 256, 257, 258, 259, 260, 261, 262, 263, 264, 265, 266, 478, 696, 697, 698, 699, 700, 701, 702, 736, 2322 },
    [148] = { 442, 443, 444, 445, 446, 447, 448, 449, 450, 452, 453, 454, 455, 456, 2077, 2078, 2326 },
    [151] = {},
    [170] = {},
    [206] = {},
    [207] = {},
    [208] = {},
    [209] = {},
    [210] = {},
    [214] = {},
    [215] = { 220, 221, 222, 223, 224, 225, 358, 360, 396, 397, 398, 399, 404, 470, 471, 472, 473, 474, 475, 476, 637, 818, 819, 820, 821, 2137, 17044, 17045, 17223 },
    [267] = { 271, 272, 275, 285, 286, 287, 288, 289, 290, 294, 295, 896, 1056, 1057, 2397, 2777 },
    [268] = {},
    [269] = {},
    [276] = {},
    [293] = {},
    [296] = {},
    [308] = {},
    [330] = {},
    [331] = { 411, 412, 413, 414, 415, 416, 417, 418, 419, 420, 421, 422, 424, 425, 426, 427, 428, 429, 430, 431, 432, 433, 434, 435, 436, 437, 438, 441, 879, 1276, 2301, 2325, 2357, 2358, 2359, 2360, 2457, 2637, 2797, 2897, 3177, 3319 },
    [332] = {},
    [357] = { 489, 1099, 1100, 1101, 1102, 1103, 1104, 1105, 1106, 1107, 1108, 1109, 1110, 1111, 1112, 1113, 1114, 1115, 1116, 1117, 1118, 1119, 1120, 1121, 1136, 1137, 2323, 2518, 2519, 2520, 2521, 2522, 2577, 3117, 3217 },
    [361] = { 1761, 1762, 1763, 1764, 1765, 1766, 1767, 1768, 1769, 1770, 1771, 1997, 1998, 2478, 2479, 2480, 2481, 2618 },
    [377] = {},
    [394] = { 395 },
    [400] = { 439, 479, 480, 481, 482, 483, 484, 485, 486, 487, 488, 1557, 2097, 2237, 2238, 2239, 2240, 2303, 3037, 3038, 3039, 17052 },
    [405] = { 596, 597, 598, 599, 600, 602, 603, 604, 606, 607, 608, 609, 2198, 2217, 2324, 2404, 2405, 2406, 2407, 2408, 2617 },
    [406] = { 460, 461, 463, 464, 465, 466, 467, 468, 469, 636, 1076, 1277, 2160, 2537, 2538, 2539, 2540, 2541, 3157 },
    [408] = {},
    [409] = {},
    [440] = { 976, 977, 978, 979, 980, 981, 982, 983, 984, 985, 986, 987, 988, 989, 990, 991, 992, 1336, 1937, 1938, 1939, 1940, 2300, 2317, 2857 },
    [457] = {},
    [490] = { 537, 538, 539, 540, 541, 542, 543, 1942, 1943, 16637, 16985, 16986 },
    [491] = {},
    [493] = { 656, 2361, 2362, 2363, 16916 },
    [495] = {},
    [616] = { 16848, 16849, 16853, 16866, 16867, 16868, 17050, 17144, 17145 },
    [618] = { 2241, 2242, 2243, 2244, 2245, 2246, 2247, 2248, 2249, 2250, 2251, 2252, 2253, 2254, 2255, 2256, 3139, 16005 },
    [676] = {},
    [717] = {},
    [718] = {},
    [719] = {},
    [721] = {},
    [722] = {},
    [796] = {},
    [876] = {},
    [956] = {},
    [1176] = {},
    [1196] = {},
    [1337] = {},
    [1377] = { 2477, 2737, 2738, 2739, 2740, 2741, 2742, 2743, 2744, 3077, 3097, 3098, 3099, 3100, 3257, 3425, 3426, 3427, 3446, 3447, 3454 },
    [1397] = {},
    [1417] = {},
    [1477] = {},
    [1497] = {},
    [1519] = { 1617, 17203 },
    [1537] = {},
    [1579] = { 1580 },
    [1581] = { 1582 },
    [1583] = {},
    [1584] = {},
    [1637] = {},
    [1638] = { 1639, 1640, 1641, 2197 },
    [1657] = { 1658, 1659, 1660, 1661, 1662 },
    [1941] = {},
    [1977] = { 3377, 3378, 3379, 3380, 3381, 3382, 3383, 3384, 3397, 3398, 3419 },
    [2017] = {},
    [2037] = {},
    [2057] = {},
    [2100] = {},
    [2159] = {},
    [2257] = {},
    [2280] = {},
    [2366] = {},
    [2367] = {},
    [2437] = {},
    [2557] = { 3237 },
    [2597] = { 2957, 2958, 2959, 2960, 2961, 2962, 2963, 2964, 2977, 2978, 3017, 3057, 3058, 3297, 3298, 3299, 3300, 3301, 3302, 3303, 3304, 3305, 3306, 3318, 3337, 3338 },
    [2677] = {},
    [2717] = {},
    [2817] = {},
    [2917] = {},
    [2918] = {},
    [3277] = {},
    [3358] = { 3417, 3418, 3420, 3421, 3422, 3423, 3424 },
    [3428] = {},
    [3429] = { 3448, 3449, 3450, 3451, 3452, 3453 },
    [3456] = {},
    [3459] = {},
    [3478] = {},
    [13649] = {},
    [15475] = { 15540 },
    [15531] = {},
    [15532] = {},
    [15793] = {},
    [15809] = {},
    [15825] = {},
    [15828] = {},
    [15938] = {},
    [16003] = {},
    [16004] = {},
    [16017] = {},
    [16018] = {},
    [16028] = {},
    [16029] = {},
    [16074] = {},
    [16076] = {},
    [16113] = {},
    [16114] = {},
    [16115] = {},
    [16116] = {},
    [16117] = {},
    [16118] = {},
    [16119] = {},
    [16144] = {},
    [16147] = {},
    [16148] = {},
    [16149] = {},
    [16169] = {},
    [16236] = { 16369, 16372, 16373, 16374 },
    [16295] = {},
    [16362] = {},
    [16394] = {},
    [16508] = {},
    [16509] = {},
    [16510] = { 16537 },
    [16532] = { 16650 },
    [16544] = { 16559 },
    [16550] = { 17038, 17039, 17040, 17041, 17042, 17043, 17046 },
    [16554] = {},
    [16560] = {},
    [16562] = {},
    [16591] = { 16685, 16723, 16724, 16725, 16726, 16727, 16728, 16729, 16731, 16734, 16735, 16736, 16737, 16743, 16744, 16820, 17780, 17808, 17809, 17847 },
    [16593] = { 16622, 16623, 16624, 16625, 16626, 16628, 16629, 16630, 16631, 16635, 16636, 16638, 16663, 16672, 16673, 16674, 16679, 16720, 16833, 16988, 17221, 17674, 17675, 17676, 17677, 17678, 17684 },
    [16603] = { 16604, 16605 },
    [16606] = { 16607, 16608, 16609, 16610 },
    [16611] = { 16612, 16614, 16615, 16617 },
    [16632] = {},
    [16651] = { 2657, 16675, 16676, 16677, 16678, 16742 },
    [16653] = { 16655, 16656, 16657, 16658, 16659, 16660, 16661 },
    [16662] = {},
    [16667] = {},
    [16732] = { 16877, 16878, 16879, 16880 },
    [16756] = { 16757, 16758, 16759, 16760, 16761, 16762, 16763, 16764, 16765 },
    [16772] = {},
    [16842] = {},
    [16876] = {},
    [16919] = {},
    [16941] = {},
    [17065] = {},
    [17066] = {},
    [17191] = {},
    [17803] = {},
    [17804] = {},
    [17852] = {},
}
-- END GENERATED SUBZONES
