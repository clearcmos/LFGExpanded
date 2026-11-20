-- Run from the repository root. Frame stand-ins test integration, not rendering.
local passed = 0
local function test(name, run)
    run(); passed = passed + 1; print("PASS " .. name)
end
local secret = setmetatable({}, { __index = function() error("secret read") end,
    __lt = function() error("secret compare") end })
-- A secret string keeps its type in the client, so a type check alone would let it through.
local secretZone = "Hidden Zone"
issecretvalue = function(value) return rawequal(value, secret) or value == secretZone end
canaccesstable = function(value) return not rawequal(value, secret) end
local fixtures = {
    [1] = { { classFilename = "PRIEST", level = 60, assignedRole = "HEALER", lfgRoles = { healer = true }, areaName = "Undercity" } },
    [2] = { { classFilename = "WARRIOR", level = 60, assignedRole = "TANK", lfgRoles = { tank = true } } },
    [3] = { { classFilename = "MAGE", level = 50, assignedRole = "DAMAGER", lfgRoles = { dps = true }, areaName = secretZone } },
    [4] = { { name = "Bark", classFilename = "DRUID", level = 60, assignedRole = "TANK", lfgRoles = { tank = true }, areaName = "Orgrimmar" },
        { name = "Mend", classFilename = "PRIEST", level = 60, assignedRole = "HEALER", lfgRoles = { healer = true }, areaName = "Stratholme" } },
    [5] = { { classFilename = "SHAMAN", level = 60, lfgRoles = { healer = true, dps = true } } },
}
local restricted, loading = false, false
C_LFGList = {
    GetSearchResultInfo = function(id)
        if not fixtures[id] then return nil end
        return { numMembers = restricted and id == 1 and secret or #fixtures[id], comment = "Notes", leaderName = "Leader" }
    end,
    GetSearchResultPlayerInfo = function(id, index)
        if loading and id == 1 then return nil end
        return fixtures[id] and fixtures[id][index]
    end,
    GetSearchResultMemberCounts = function(id)
        return id == 4 and { TANK = 1, HEALER = 1, DAMAGER = 0 } or { TANK = 0, HEALER = 0, DAMAGER = 0 }
    end,
    GetSearchResultLeaderInfo = function(id) return fixtures[id] and fixtures[id][1] end,
    GetAvailableCategories = function() return { 2, 114 } end,
    GetLfgCategoryInfo = function() return { name = "Donjons" } end,
}
GetMaxPlayerLevel = function() return 60 end
local addon = {}
assert(loadfile("Compat_Forever.lua"))("LFGExpanded", addon)
local Compat = addon.Compat
test("safe listing snapshots preserve class, roles and notes", function()
    assert(Compat.PrepareResults({1, 2, 3, 4, 5}))
    assert(Compat.GetSearchResultInfo(4).numMembers == 2)
    assert(Compat.GetSearchResultPlayerInfo(1, 1).lfgRoles.healer)
end)
test("restriction and incomplete data block filtering before mutation", function()
    restricted = true; assert(not Compat.PrepareResults({1, 2}))
    restricted = false; loading = true; assert(not Compat.PrepareResults({1, 2}))
    loading = false
    assert(not Compat.PrepareResults(secret))
    assert(not Compat.PrepareResults({secret}))
end)
test("category selection is independent of translated names", function()
    assert(Compat.IsCategorySupported(2) and Compat.IsCategorySupported(114))
    assert(not Compat.IsCategorySupported(116))
end)

local objects, methods = {}, {}
local object
-- Template children the adapter touches. The side tab is a Frame, so Button-only
-- methods fail loudly, as they would in the client.
local templates = {
    LargeSideTabButtonTemplate = function(obj)
        obj.Icon = object("Texture")
        obj.SetNormalFontObject = function() error("side tab is not a Button") end
        obj.SetCustomOnMouseUpHandler = function(self, handler) self.mouseUp = handler end
    end,
}
function object(kind, name, _, template)
    if name then assert(_G[name] == nil, "duplicate frame name: " .. name) end
    local obj = setmetatable({ kind = kind, scripts = {}, shown = false }, { __index = methods })
    objects[#objects + 1] = obj
    if name then _G[name] = obj end
    if templates[template] then templates[template](obj) end
    return obj
end
setmetatable(methods, { __index = function(_, key)
    if key:match("^Get") then return function() return 1 end end
    return function() end
end })
function methods:SetScript(event, callback) self.scripts[event] = callback end
function methods:HookScript(event, callback)
    local old = self.scripts[event]
    self.scripts[event] = function(...) if old then old(...) end; callback(...) end
end
function methods:Show()
    local wasShown = self.shown; self.shown = true
    if not wasShown and self.scripts.OnShow then self.scripts.OnShow(self) end
end
function methods:Hide()
    local wasShown = self.shown; self.shown = false
    if wasShown and self.scripts.OnHide then self.scripts.OnHide(self) end
end
function methods:SetShown(value) if value then self:Show() else self:Hide() end end
function methods:IsShown() return self.shown end
function methods:SetText(value) self.textValue = value end
function methods:SetPoint(...) self.point = { ... } end
function methods:SetChecked(value) self.checked = value end
function methods:GetChecked() return self.checked end
function methods:GetText() return self.textValue end
function methods:ClearFocus()
    if self.scripts.OnEditFocusLost then self.scripts.OnEditFocusLost(self) end
end
function methods:HasScript() return true end
function methods:CreateTexture() return object("Texture") end
function methods:CreateFontString() return object("FontString") end
CreateFrame = object
UIParent = object("Frame")
LFGParentFrame = object("Frame")
local whoTab = object("Button")
LFGParentFrame.Tab3 = whoTab
LFGParentFrame.ListingTab = object("Frame")
LFGParentFrame.WhoListingTab = object("Frame")
LFGParentFrameTab3 = whoTab
LFGBrowseFrame = object("Frame")
LFGBrowseFrame.results = {}
LFGBrowseFrame.CategoryDropdown = { selectedCategoryID = 2, SetValue = function(self, id) self.selectedCategoryID = id end }
LFGBrowseFrame.ActivityDropdown = { selectedValues = { 1 } }
-- A result row as the browser's ScrollBox hands it out.
local resultRow = object("Button")
resultRow.resultID = 4
ScrollBoxListMixin = { Event = { OnAcquiredFrame = "OnAcquiredFrame" } }
LFGBrowseFrame.ScrollBox = { GetScrollPercentage = function() return 0.4 end, SetScrollPercentage = function() end,
    RegisterCallback = function() end, ForEachFrame = function(_, callback) callback(resultRow) end }
function LFGBrowseFrame:UpdateResultList() self.results = {1, 2, 3, 4, 5}; self:UpdateResults() end
function LFGBrowseFrame:UpdateResults() end
local originalRenderer = function() end
LFGBrowseSearchEntry_Update = originalRenderer
hooksecurefunc = function(target, key, callback)
    if type(target) == "string" then target, key, callback = _G, target, key end
    local original = target[key]
    target[key] = function(...) original(...); callback(...) end
end
-- The native listing tooltip. Blizzard recomputes its size and leader crown on every
-- show, fills the leader row, and hands member rows out of a pool in no fixed order.
local function memberRow()
    local row = object("Frame")
    row.Name, row.Level, row.Role = object("FontString"), object("FontString"), object("Texture")
    row.Roles = { row.Role }
    row.Role:Show()
    return row
end
local tooltip = object("Frame")
tooltip.MemberCount = object("FontString")
tooltip.VoiceChat = object("FontString")
tooltip.LeaderIcon = object("Texture")
tooltip.Leader = memberRow()
local pooledRows = { memberRow(), memberRow() }
tooltip.memberPool = { active = {}, EnumerateActive = function(self)
    local index = 0
    return function() index = index + 1; return self.active[index] end
end }
function tooltip:GetHeight() return self.height end
function tooltip:SetHeight(value) self.height = value end
LFGBrowseSearchEntryTooltip = tooltip
LFGBrowseSearchEntryTooltip_UpdateAndShow = function(self, id)
    local members = fixtures[id]
    self.height = 100
    self:Show()
    self.LeaderIcon:SetShown(#members > 1)
    self.Leader.Name:SetText(members[1].name)
    self.Leader:Show()
    self.memberPool.active = {}
    for index = 2, #members do
        local row = pooledRows[index - 1]
        row.Name:SetText(members[index].name)
        self.memberPool.active[#self.memberPool.active + 1] = row
    end
end
-- Zero-delay timers run at once (Initialize); others run when advance() reaches them.
local now = 1000
GetTime = function() return now end
local timers = {}
C_Timer = { After = function(delay, callback)
    if delay == 0 then callback() else timers[#timers + 1] = { due = now + delay, run = callback } end
end }
local function advance(seconds)
    local target = now + seconds
    while true do
        local soonest
        for index, timer in ipairs(timers) do
            if timer.due <= target and (not soonest or timer.due < timers[soonest].due) then soonest = index end
        end
        if not soonest then break end
        local timer = table.remove(timers, soonest)
        now = math.max(now, timer.due)
        timer.run()
    end
    now = target
end
local whoQueries, chatFilter = {}, nil
C_FriendList = { SendWho = function(query) whoQueries[#whoQueries + 1] = query end, SetWhoToUi = function() end }
C_NameUtil = { ReplaceSurnameSeparatorWithLinkSeparator = function(name) return name end }
ChatFrameUtil = { AddMessageEventFilter = function(_, filter) chatFilter = filter end }
Enum = { SocialWhoOrigin = { Social = 1 } }
-- Client area names for the IDs the zone tests use (from the 1.60.1 AreaTable).
local areaNames = { [85] = "Tirisfal Glades", [811] = "Nightmare Vale", [28] = "Western Plaguelands",
    [152] = "The Bulwark", [813] = "The Bulwark", [139] = "Eastern Plaguelands", [2279] = "Stratholme",
    [2017] = "Stratholme", [16591] = "Riverglades", [16724] = "Farholde Keep", [616] = "Mount Hyjal",
    [16867] = "Shrine of Aviana" }
C_Map = { GetAreaInfo = function(id) return areaNames[id] end }
WHO_TAG_EXACT = "x-"
WHO_LIST_FORMAT = "|Hplayer:%s|h[%s]|h: Level %d %s %s - %s"
WHO_LIST_GUILD_FORMAT = "|Hplayer:%s|h[%s]|h: Level %d %s %s <%s> - %s"
WHO_NUM_RESULTS = "%d |4player:players; total"
WHO_COOLDOWN = "You must wait %d seconds before using /who again."
WHO_COOLDOWN_SHORT = "You must wait a moment longer before using /who again."
wipe = function(t) for key in pairs(t) do t[key] = nil end end
GetBackgroundTexCoordsForRole = function() return 0, 1, 0, 1 end
GetTexCoordsForRole = GetBackgroundTexCoordsForRole
RAID_CLASS_COLORS = {}
GameTooltip_Hide = function() end
SOUNDKIT = {}
PlaySound = function() end
-- Saved filters from a previous session, with malformed entries mixed in.
LFGExpandedDB = {
    roles = { TANK = true, BOGUS = true }, excludeRoles = { TANK = true, HEALER = "yes" },
    classes = { MAGE = true }, excludeClasses = { MAGE = true, WARLOCK = true },
    levelMin = 0, levelMax = 99.5, showGroups = "no", showSingles = false,
}
test("Forever initialization preserves native Who tab and result renderer", function()
    assert(loadfile("LFGExpanded.lua"))("LFGExpanded", addon)
    assert(LFGParentFrameTab3 == whoTab and LFGParentFrame.Tab3 == whoTab)
    assert(LFGBrowseSearchEntry_Update == originalRenderer)
    assert(LFGExpandedForeverToggle and LFGExpandedPanel)
    LFGBrowseFrame.CategoryDropdown:SetValue(2)
    assert(LFGExpandedPanel:IsShown())
end)
local function zoneText(row)
    for _, obj in ipairs(objects) do
        local point = rawget(obj, "point")
        if obj.kind == "FontString" and point and point[2] == row then return obj end
    end
end
test("listing tooltip shows a single player's zone between Members and Voice Chat", function()
    LFGBrowseSearchEntryTooltip_UpdateAndShow(tooltip, 1)
    local line = tooltip.VoiceChat.point[2]
    assert(line ~= tooltip.MemberCount and line.point[2] == tooltip.MemberCount)
    assert(line.shown and line.textValue == "Location: |cffffffffUndercity|r", line.textValue)
    assert(tooltip.height == 109)
    for _, id in ipairs({ 3, 2 }) do  -- a hidden zone, then none at all
        LFGBrowseSearchEntryTooltip_UpdateAndShow(tooltip, id)
        assert(not line.shown and tooltip.VoiceChat.point[2] == tooltip.MemberCount and tooltip.height == 100)
    end
end)
test("subzones show as their zone; border and dungeon names stay as reported", function()
    local cases = { ["Nightmare Vale"] = "Tirisfal Glades", ["Farholde Keep"] = "Riverglades",
        ["Shrine of Aviana"] = "Mount Hyjal", ["The Bulwark"] = "The Bulwark", ["Stratholme"] = "Stratholme",
        ["Tirisfal Glades"] = "Tirisfal Glades" }
    for area, shown in pairs(cases) do
        fixtures[1][1].areaName = area
        LFGBrowseSearchEntryTooltip_UpdateAndShow(tooltip, 1)
        local line = tooltip.VoiceChat.point[2]
        assert(line.textValue == "Location: |cffffffff" .. shown .. "|r", line.textValue)
    end
    fixtures[1][1].areaName = "Undercity"
end)
test("group tooltip lines each member's zone up in a column", function()
    LFGBrowseSearchEntryTooltip_UpdateAndShow(tooltip, 4)
    local leader, member = zoneText(tooltip.Leader), zoneText(pooledRows[1])
    assert(leader.shown and leader.textValue == "Orgrimmar", leader.textValue)
    assert(member.shown and member.textValue == "Stratholme", member.textValue)
    assert(leader.point[4] == member.point[4] and leader.point[4] > 0)
    assert(tooltip.VoiceChat.point[2] == tooltip.MemberCount and tooltip.height == 100)
    fixtures[4][2].areaName = secretZone
    LFGBrowseSearchEntryTooltip_UpdateAndShow(tooltip, 4)
    assert(leader.textValue == "Orgrimmar" and member.textValue == "Click to look up", member.textValue)
    fixtures[4][2].areaName = "Stratholme"
    LFGBrowseSearchEntryTooltip_UpdateAndShow(tooltip, 1)  -- a single player after a group
    assert(not leader.shown and not member.shown and tooltip.VoiceChat.point[2].shown)
end)
local function systemMessage(text)
    for _, obj in ipairs(objects) do
        if obj.scripts.OnEvent then obj.scripts.OnEvent(obj, "CHAT_MSG_SYSTEM", text) end
    end
end
test("member lookups: one per click, spaced by a live countdown, late answers kept", function()
    fixtures[6] = {  -- the server sends only the leader's zone
        { name = "Ash", classFilename = "WARRIOR", level = 60, assignedRole = "TANK", lfgRoles = { tank = true }, areaName = "Undercity" },
        { name = "Bo", classFilename = "ROGUE", level = 60, assignedRole = "DAMAGER", lfgRoles = { dps = true } },
        { name = "Cy", classFilename = "MAGE", level = 60, assignedRole = "DAMAGER", lfgRoles = { dps = true } },
    }
    resultRow.resultID = 6
    LFGBrowseSearchEntryTooltip_UpdateAndShow(tooltip, 6)
    local bo = zoneText(pooledRows[1])
    local cy = setmetatable({}, { __index = function(_, key)  -- created once Cy has something to show
        local text = zoneText(pooledRows[2])
        if key == "shown" then return text ~= nil and text.shown end
        return text and text[key]
    end })
    local function click() resultRow.scripts.OnClick(resultRow, "LeftButton") end
    local function filtered(text) return chatFilter(nil, "CHAT_MSG_SYSTEM", text) end
    -- Only the member the next click looks up shows a status.
    assert(bo.textValue == "Click to look up" and not cy.shown)
    click()
    assert(whoQueries[#whoQueries] == "x-Bo" and bo.textValue == "Looking up..." and not cy.shown)
    local sent = #whoQueries
    local answer = "|Hplayer:Bo|h[Bo]|h: Level 60 Undead Rogue - Farholde Keep"
    assert(filtered(answer))
    systemMessage(answer)
    assert(bo.textValue == "Riverglades" and filtered("1 player total"))
    assert(cy.shown and cy.textValue == "Wait 5s", cy.textValue)
    click()  -- too soon: nothing is sent
    assert(#whoQueries == sent)
    advance(1)
    assert(cy.textValue == "Wait 4s", cy.textValue)
    advance(4)
    assert(cy.textValue == "Click to look up", cy.textValue)
    assert(not filtered("1 player total"))  -- the player's own /who shows
    click()
    assert(whoQueries[#whoQueries] == "x-Cy")
    systemMessage("Somebody has come online.")  -- an unrelated line changes nothing
    advance(5)  -- no answer
    assert(cy.textValue == "No answer, click to retry", cy.textValue)
    local late = "|Hplayer:Cy|h[Cy]|h: Level 60 Gnome Mage <Guild> - Nightmare Vale"
    assert(filtered(late))
    systemMessage(late)
    assert(cy.textValue == "Tirisfal Glades", cy.textValue)
    advance(300)  -- both expire
    click(); systemMessage("0 players total")
    assert(bo.textValue == "Not found", bo.textValue)
    advance(5)
    click(); systemMessage("You must wait 30 seconds before using /who again.")
    assert(cy.textValue == "Wait 30s", cy.textValue)
    advance(30)
    assert(cy.textValue == "Click to look up", cy.textValue)
    assert(LFGExpandedDB.whoLog == nil)  -- lookups are not logged
    resultRow.resultID = 4
end)
test("an unanswered member goes to the back of the queue; the player's own /who stays visible", function()
    fixtures[7] = {
        { name = "Dee", classFilename = "WARRIOR", level = 60, assignedRole = "TANK", lfgRoles = { tank = true }, areaName = "Durotar" },
        { name = "Eli", classFilename = "ROGUE", level = 60, assignedRole = "DAMAGER", lfgRoles = { dps = true } },
        { name = "Fay", classFilename = "HUNTER", level = 60, assignedRole = "DAMAGER", lfgRoles = { dps = true } },
    }
    resultRow.resultID = 7
    LFGBrowseSearchEntryTooltip_UpdateAndShow(tooltip, 7)
    local eli, fay = zoneText(pooledRows[1]), zoneText(pooledRows[2])
    local function click() resultRow.scripts.OnClick(resultRow, "LeftButton") end
    local function filtered(text) return chatFilter(nil, "CHAT_MSG_SYSTEM", text) end
    local fayLine = "|Hplayer:Fay|h[Fay]|h: Level 60 Orc Hunter - Durotar"
    local eliLine = "|Hplayer:Eli|h[Eli]|h: Level 60 Troll Rogue - Durotar"
    assert(eli.textValue == "Click to look up" and not fay.shown)
    click()
    assert(whoQueries[#whoQueries] == "x-Eli")
    advance(5)  -- no answer: Fay is next, Eli waits for a retry
    assert(eli.textValue == "No answer" and fay.textValue == "Click to look up", eli.textValue)
    click()
    assert(whoQueries[#whoQueries] == "x-Fay")
    systemMessage(fayLine)
    assert(fay.textValue == "Durotar" and eli.textValue == "Wait 5s", eli.textValue)
    advance(5)
    assert(eli.textValue == "No answer, click to retry", eli.textValue)
    advance(60)  -- past the late window: these are the player's own /who now
    assert(not filtered(fayLine) and not filtered(eliLine))
    click()
    assert(whoQueries[#whoQueries] == "x-Eli")
    systemMessage(eliLine)
    assert(eli.textValue == "Durotar", eli.textValue)
    -- A raid listing: Blizzard's tooltip lists no members, so a click sends nothing.
    fixtures[8] = { fixtures[7][1] }
    for index = 2, 11 do
        fixtures[8][index] = { name = "Raider" .. index, classFilename = "MAGE", level = 60, assignedRole = "DAMAGER", lfgRoles = { dps = true } }
    end
    resultRow.resultID = 8
    advance(5)
    local sent = #whoQueries
    click()
    assert(#whoQueries == sent)
    fixtures[7], fixtures[8] = nil, nil
    resultRow.resultID = 4
end)
test("who lines parse in clients with numbered placeholders (Russian)", function()
    local plain = "|Hplayer:%1$s|h[%2$s]|h:  |3-6(%4$s), |3-6(%5$s) %3$d-го уровня – %6$s"
    local guild = "|Hplayer:%1$s|h[%2$s]|h: |3-6(%4$s), |3-6(%5$s) %3$d-го уровня <%6$s> - %7$s"
    local values = Compat.MatchFormat(plain, "|Hplayer:Иван|h[Иван]|h:  орка, воина 60-го уровня – Оргриммар")
    assert(values and values[2] == "Иван" and values[3] == "60" and values[values.last] == "Оргриммар")
    values = Compat.MatchFormat(guild, "|Hplayer:Иван|h[Иван]|h: орка, воина 60-го уровня <Орда> - Оргриммар")
    assert(values and values[1] == "Иван" and values[6] == "Орда" and values[values.last] == "Оргриммар")
    assert(not Compat.MatchFormat(guild, "|Hplayer:Иван|h[Иван]|h:  орка, воина 60-го уровня – Оргриммар"))
    assert(Compat.MatchFormat("Всего игроков: %d", "Всего игроков: 0")[1] == "0")
    assert(Compat.MatchFormat("Подождите %d сек., прежде чем снова использовать команду /кто.",
        "Подождите 4 сек., прежде чем снова использовать команду /кто.")[1] == "4")
    assert(not Compat.MatchFormat(plain, "1 player total"))
end)
local function checkbox(label)
    for index, obj in ipairs(objects) do
        if obj.kind == "CheckButton" and objects[index + 1].textValue == label then return obj end
    end
end
local function control(key)
    for _, obj in ipairs(objects) do
        if obj.kind == "Button" and obj.filterKey == key then return obj end
    end
    error("missing control " .. key)
end
local function click(key, mouse)
    local obj = control(key); obj.scripts.OnClick(obj, mouse or "LeftButton")
end
test("remembered filters are restored and malformed entries ignored", function()
    LFGBrowseFrame:UpdateResultList()
    -- Tank OR Mage, Warlock excluded, groups only: just the druid/priest group.
    assert(#LFGBrowseFrame.results == 1 and LFGBrowseFrame.results[1] == 4)
    local singles = checkbox("Players")
    -- Centered: stand-in text is 1 px wide, so "Groups" ends at 57 and "Level" starts at 244.5.
    assert(singles.point[4] == 139.25, singles.point[4])
    assert(singles.checked == false and checkbox("Groups").checked == true)
    click("TANK"); click("MAGE"); click("WARLOCK", "RightButton")
    singles:SetChecked(true); singles.scripts.OnClick(singles)
    assert(#LFGBrowseFrame.results == 5)
end)
test("Filters side tab toggles the panel and tracks its visibility", function()
    local tab = LFGExpandedForeverToggle
    assert(tab.checked == true)
    tab.mouseUp(tab, "LeftButton", true)
    assert(not LFGExpandedPanel:IsShown() and tab.checked == false)
    tab.mouseUp(tab, "LeftButton", false)
    assert(not LFGExpandedPanel:IsShown())
    tab.mouseUp(tab, "LeftButton", true)
    assert(LFGExpandedPanel:IsShown() and tab.checked == true)
end)
test("include role filters both singles and groups", function()
    click("HEALER")
    assert(#LFGBrowseFrame.results == 3)
    assert(LFGBrowseFrame.results[1] == 4)
end)
test("class and role includes retain OR semantics", function()
    click("WARRIOR")
    assert(#LFGBrowseFrame.results == 4)
    click("WARRIOR"); click("HEALER")
end)
test("role exclusion retains dual-role singles and excludes matching groups", function()
    click("HEALER", "RightButton")
    assert(#LFGBrowseFrame.results == 3)
    for _, id in ipairs(LFGBrowseFrame.results) do assert(id ~= 1 and id ~= 4) end
    click("HEALER", "RightButton")
end)
local function visibleRows()
    local list = {}
    for _, key in ipairs({ "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST", "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR" }) do
        local row = control(key)
        if row:IsShown() then list[#list + 1] = key; row.y = row.point[5] end
    end
    return table.concat(list, " ")
end
test("class rows hide when no click could fill them, and stack without gaps", function()
    LFGBrowseFrame:UpdateResultList()
    assert(visibleRows() == "DRUID MAGE PRIEST SHAMAN WARRIOR", visibleRows())
    assert(control("DRUID").y == -80 and control("MAGE").y == -116 and control("WARRIOR").y == -224)
    click("DAMAGER", "RightButton")  -- the mage lists DPS only; the shaman also heals
    assert(visibleRows() == "DRUID PRIEST SHAMAN WARRIOR", visibleRows())
    click("TANK")  -- OR include: the shaman shows 0 but including it would add it
    assert(visibleRows() == "DRUID PRIEST SHAMAN WARRIOR", visibleRows())
    assert(control("SHAMAN").countLabel.textValue == 0)
    click("WARRIOR", "RightButton")  -- an excluded class keeps its row
    assert(visibleRows() == "DRUID PRIEST SHAMAN WARRIOR", visibleRows())
    click("WARRIOR", "RightButton"); click("TANK"); click("DAMAGER", "RightButton")
    assert(visibleRows() == "DRUID MAGE PRIEST SHAMAN WARRIOR", visibleRows())
end)
local function shownText(fragment)
    for _, obj in ipairs(objects) do
        if obj.kind == "FontString" and obj.shown and type(obj.textValue) == "string"
            and obj.textValue:find(fragment, 1, true) then return true end
    end
    return false
end
test("an empty class list explains itself", function()
    assert(not shownText("No listings"))
    click("TANK", "RightButton"); click("HEALER", "RightButton"); click("DAMAGER", "RightButton")
    assert(visibleRows() == "" and shownText("No listings match these filters"))
    click("TANK", "RightButton"); click("HEALER", "RightButton"); click("DAMAGER", "RightButton")
    assert(visibleRows() ~= "" and not shownText("No listings"))
    local saved = fixtures; fixtures = {}
    LFGBrowseFrame:UpdateResultList()
    assert(shownText("No listings found"))
    fixtures = saved
    LFGBrowseFrame:UpdateResultList()
    assert(not shownText("No listings"))
end)
local function levelBoxes()
    local list = {}
    for _, obj in ipairs(objects) do
        if obj.kind == "EditBox" then list[#list + 1] = obj end
    end
    assert(#list == 2)
    return list[1], list[2]
end
local function setLevels(lo, hi)
    local minBox, maxBox = levelBoxes()
    minBox:SetText(lo); maxBox:SetText(hi); minBox:ClearFocus()
end
test("level range replaces Max level and applies to every member", function()
    assert(not checkbox("Max level"))
    setLevels("55", "")
    assert(#LFGBrowseFrame.results == 4)
    for _, id in ipairs(LFGBrowseFrame.results) do assert(id ~= 3) end
    setLevels("", "55")  -- only the level-50 mage
    assert(#LFGBrowseFrame.results == 1 and LFGBrowseFrame.results[1] == 3)
    setLevels("60", "50")  -- swapped into 50-60
    local minBox, maxBox = levelBoxes()
    assert(minBox.textValue == "50" and maxBox.textValue == "60" and #LFGBrowseFrame.results == 5)
    minBox:SetText("10"); minBox.scripts.OnEscapePressed(minBox)
    assert(minBox.textValue == "50")
    setLevels("", "")
    assert(#LFGBrowseFrame.results == 5)
end)
test("filters are saved at logout", function()
    click("HEALER"); setLevels("55", "")
    for _, obj in ipairs(objects) do
        if obj.scripts.OnEvent then obj.scripts.OnEvent(obj, "PLAYER_LOGOUT") end
    end
    local db = LFGExpandedDB
    assert(db.roles.HEALER == true and next(db.excludeClasses) == nil)
    assert(db.levelMin == 55 and db.levelMax == nil and db.showGroups == true and db.showSingles == true)
    assert(db.whoLog == nil)
    click("HEALER"); setLevels("", "")
end)
test("restricted refresh leaves native results intact and warns", function()
    click("HEALER")
    restricted = true
    LFGBrowseFrame:UpdateResultList()
    assert(#LFGBrowseFrame.results == 5)
    local warned = false
    for _, obj in ipairs(objects) do
        if type(obj.textValue) == "string" and obj.textValue:find("Filters are paused", 1, true) then warned = true end
    end
    assert(warned)
    restricted = false
    LFGBrowseFrame:UpdateResultList()
    assert(#LFGBrowseFrame.results == 3)
end)
print(string.format("%d tests passed", passed))
