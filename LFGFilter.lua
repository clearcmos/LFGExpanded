local addonName, addon = ...

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

local ROLE_ICON_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-PORTRAITROLES"
local CLASS_ICON_TEXTURE = "Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes"

local ROLE_TCOORDS = {
    TANK    = { 0, 19/64, 22/64, 41/64 },
    HEALER  = { 20/64, 39/64, 1/64, 20/64 },
    DAMAGER = { 20/64, 39/64, 22/64, 41/64 },
}

local ROLE_ORDER = { "TANK", "HEALER", "DAMAGER" }
local ROLE_LABELS = { TANK = "Tank", HEALER = "Healer", DAMAGER = "DPS" }

local CLASS_ORDER = {
    "DRUID", "HUNTER", "MAGE", "PALADIN", "PRIEST",
    "ROGUE", "SHAMAN", "WARLOCK", "WARRIOR",
}

local CLASS_LABELS = {
    DRUID = "Druid", HUNTER = "Hunter", MAGE = "Mage",
    PALADIN = "Paladin", PRIEST = "Priest", ROGUE = "Rogue",
    SHAMAN = "Shaman", WARLOCK = "Warlock", WARRIOR = "Warrior",
}

local ICON_SIZE = 28
local ICON_GAP = 3
local COLUMN_WIDTH = 200
local COLUMN_GAP = 16
local PANEL_PADDING = 14
local SECTION_GAP = 10
local CLASS_ROW_HEIGHT = 20
local CLASS_ICON_SMALL = 16
local PANEL_WIDTH = 2 * COLUMN_WIDTH + COLUMN_GAP + 2 * PANEL_PADDING

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local groupFilters = { roles = {}, excludeRoles = {}, classes = {}, excludeClasses = {}, hidden = false }
local singleFilters = { roles = {}, excludeRoles = {}, classes = {}, hidden = false }

local sidePanel
local groupWidgets = {}
local singleWidgets = {}

-------------------------------------------------------------------------------
-- Filter Logic
-------------------------------------------------------------------------------

local function HasActiveSection(f)
    return next(f.roles) ~= nil or next(f.classes) ~= nil
        or (f.excludeRoles and next(f.excludeRoles) ~= nil)
        or (f.excludeClasses and next(f.excludeClasses) ~= nil)
end

local function HasActiveFilters()
    return HasActiveSection(groupFilters) or HasActiveSection(singleFilters)
        or groupFilters.hidden or singleFilters.hidden
end

local ROLE_TO_LFGROLE = { TANK = "tank", HEALER = "healer", DAMAGER = "dps" }

local function PassesRoleCheck(f, resultID, numMembers)
    -- For singles, use lfgRoles from player info (member counts are unreliable)
    if numMembers == 1 then
        local hasInclude = next(f.roles) ~= nil
        local hasExclude = f.excludeRoles and next(f.excludeRoles) ~= nil
        if not hasInclude and not hasExclude then return true end

        local memberInfo = C_LFGList.GetSearchResultPlayerInfo(resultID, 1)
        if not memberInfo or not memberInfo.lfgRoles then return false end
        local lfg = memberInfo.lfgRoles

        -- Exclusion: reject if ALL of the player's listed roles are excluded
        -- (a player listing healer+dps passes a healer exclusion because dps isn't excluded)
        if hasExclude then
            local hasNonExcludedRole = false
            for filterRole, lfgKey in pairs(ROLE_TO_LFGROLE) do
                if lfg[lfgKey] and not f.excludeRoles[filterRole] then
                    hasNonExcludedRole = true
                    break
                end
            end
            if not hasNonExcludedRole then return false end
        end

        if not hasInclude then return true end

        for role in pairs(f.roles) do
            local key = ROLE_TO_LFGROLE[role]
            if key and lfg[key] then return true end
        end
        return false
    end

    -- For groups, member counts are fine
    local hasInclude = next(f.roles) ~= nil
    local hasExclude = f.excludeRoles and next(f.excludeRoles) ~= nil
    if not hasInclude and not hasExclude then return true end

    local mc = C_LFGList.GetSearchResultMemberCounts(resultID)
    if not mc then return false end

    -- Excluded roles must NOT be present
    if hasExclude then
        for role in pairs(f.excludeRoles) do
            if mc[role] and mc[role] > 0 then return false end
        end
    end

    -- If no include filters, exclusion-only is enough
    if not hasInclude then return true end

    -- At least one included role must be present
    for role in pairs(f.roles) do
        if mc[role] and mc[role] > 0 then return true end
    end
    return false
end

local function PassesClassCheck(f, resultID, numMembers)
    local hasInclude = next(f.classes) ~= nil
    local hasExclude = f.excludeClasses and next(f.excludeClasses) ~= nil
    if not hasInclude and not hasExclude then return true end

    local found = {}
    for i = 1, numMembers do
        local info = C_LFGList.GetSearchResultPlayerInfo(resultID, i)
        if info and info.classFilename then found[info.classFilename] = true end
    end

    -- Excluded classes must NOT be present
    if hasExclude then
        for class in pairs(f.excludeClasses) do
            if found[class] then return false end
        end
    end

    if not hasInclude then return true end

    for class in pairs(f.classes) do
        if found[class] then return true end
    end
    return false
end

local function ShouldShowResult(resultID)
    local info = C_LFGList.GetSearchResultInfo(resultID)
    if not info then return false end
    local n = info.numMembers or 0
    if n > 1 then
        if groupFilters.hidden then return false end
        if not HasActiveSection(groupFilters) then return true end
        return PassesRoleCheck(groupFilters, resultID, n)
            and PassesClassCheck(groupFilters, resultID, n)
    else
        if singleFilters.hidden then return false end
        if not HasActiveSection(singleFilters) then return true end
        return PassesRoleCheck(singleFilters, resultID, n)
            and PassesClassCheck(singleFilters, resultID, n)
    end
end

local function GetResultSortClass(resultID)
    local memberInfo = C_LFGList.GetSearchResultPlayerInfo(resultID, 1)
    if memberInfo and memberInfo.classFilename then
        return memberInfo.classFilename
    end
    return "ZZZZ"
end

local function FilterResults(browseFrame)
    local results = browseFrame.results
    if not results then return end
    for i = #results, 1, -1 do
        if not ShouldShowResult(results[i]) then
            table.remove(results, i)
        end
    end

    if HasActiveFilters() then
        local classCache = {}
        local memberCountCache = {}
        for _, id in ipairs(results) do
            local info = C_LFGList.GetSearchResultInfo(id)
            local n = info and info.numMembers or 0
            memberCountCache[id] = n
            if n == 1 then
                classCache[id] = GetResultSortClass(id)
            end
        end

        table.sort(results, function(a, b)
            local aIsGroup = memberCountCache[a] > 1
            local bIsGroup = memberCountCache[b] > 1
            if aIsGroup ~= bIsGroup then return aIsGroup end
            if not aIsGroup then
                local classA = classCache[a] or "ZZZZ"
                local classB = classCache[b] or "ZZZZ"
                if classA ~= classB then return classA < classB end
            end
            return false
        end)
    end
end

-------------------------------------------------------------------------------
-- UI Helpers
-------------------------------------------------------------------------------

-- state: "off", "require", "exclude"
local function UpdateRoleButtonVisual(btn, state)
    if state == "require" then
        btn.icon:SetDesaturated(false)
        btn.icon:SetVertexColor(1, 1, 1)
        btn.icon:SetAlpha(1.0)
        btn.selectedBorder:SetVertexColor(1, 0.82, 0)
        btn.selectedBorder:Show()
        if btn.excludeX then btn.excludeX:Hide() end
    elseif state == "exclude" then
        btn.icon:SetDesaturated(false)
        btn.icon:SetVertexColor(1, 0.3, 0.3)
        btn.icon:SetAlpha(1.0)
        btn.selectedBorder:SetVertexColor(1, 0.2, 0.2)
        btn.selectedBorder:Show()
        if btn.excludeX then btn.excludeX:Show() end
    else
        btn.icon:SetDesaturated(true)
        btn.icon:SetVertexColor(1, 1, 1)
        btn.icon:SetAlpha(0.4)
        btn.selectedBorder:Hide()
        if btn.excludeX then btn.excludeX:Hide() end
    end
end

-- state: "off", "require", "exclude"
local function UpdateClassRowVisual(row, state)
    if state == "require" then
        row.icon:SetDesaturated(false)
        row.icon:SetVertexColor(1, 1, 1)
        row.icon:SetAlpha(1.0)
        row.label:SetAlpha(1.0)
        local color = RAID_CLASS_COLORS[row.filterKey]
        if color then row.label:SetTextColor(color.r, color.g, color.b) end
        row.check:Show()
        if row.excludeX then row.excludeX:Hide() end
    elseif state == "exclude" then
        row.icon:SetDesaturated(false)
        row.icon:SetVertexColor(1, 0.3, 0.3)
        row.icon:SetAlpha(1.0)
        row.label:SetAlpha(1.0)
        row.label:SetTextColor(1, 0.3, 0.3)
        row.check:Hide()
        if row.excludeX then row.excludeX:Show() end
    else
        row.icon:SetDesaturated(true)
        row.icon:SetVertexColor(1, 1, 1)
        row.icon:SetAlpha(0.4)
        row.label:SetAlpha(0.4)
        local color = RAID_CLASS_COLORS[row.filterKey]
        if color then row.label:SetTextColor(color.r, color.g, color.b) end
        row.check:Hide()
        if row.excludeX then row.excludeX:Hide() end
    end
end

local function SetSectionDimmed(widgets, dimmed)
    local alpha = dimmed and 0.3 or 1.0
    if widgets.contentFrame then
        widgets.contentFrame:SetAlpha(alpha)
    end
end

local function RefreshSection(widgets, f)
    for _, btn in ipairs(widgets.roleButtons) do
        local state = "off"
        if f.roles[btn.filterKey] then
            state = "require"
        elseif f.excludeRoles and f.excludeRoles[btn.filterKey] then
            state = "exclude"
        end
        UpdateRoleButtonVisual(btn, state)
    end
    for _, row in ipairs(widgets.classRows) do
        local state = "off"
        if f.classes[row.filterKey] then
            state = "require"
        elseif f.excludeClasses and f.excludeClasses[row.filterKey] then
            state = "exclude"
        end
        UpdateClassRowVisual(row, state)
    end
    SetSectionDimmed(widgets, f.hidden)
end

local function TriggerRefilter()
    if LFGBrowseFrame then
        LFGBrowseFrame:UpdateResultList()
    end
end

-------------------------------------------------------------------------------
-- Role Icon Button
-------------------------------------------------------------------------------

local function CreateRoleButton(parent, role, filterTable, excludeTable, refreshFn)
    local btn = CreateFrame("Button", nil, parent)
    btn:SetSize(ICON_SIZE, ICON_SIZE)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn.filterKey = role

    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetPoint("TOPLEFT", 2, -2)
    icon:SetPoint("BOTTOMRIGHT", -2, 2)
    icon:SetTexture(ROLE_ICON_TEXTURE)
    icon:SetTexCoord(unpack(ROLE_TCOORDS[role]))
    btn.icon = icon

    local sel = btn:CreateTexture(nil, "OVERLAY")
    sel:SetPoint("TOPLEFT", -4, 4)
    sel:SetPoint("BOTTOMRIGHT", 4, -4)
    sel:SetTexture("Interface\\Buttons\\UI-ActionButton-Border")
    sel:SetBlendMode("ADD")
    sel:SetAlpha(0.7)
    sel:Hide()
    btn.selectedBorder = sel

    -- Red X overlay for exclude state
    if excludeTable then
        local exX = btn:CreateTexture(nil, "OVERLAY", nil, 2)
        exX:SetSize(ICON_SIZE - 4, ICON_SIZE - 4)
        exX:SetPoint("CENTER")
        exX:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
        exX:Hide()
        btn.excludeX = exX
    end

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.3)

    btn:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" and excludeTable then
            -- Right-click: toggle exclude (clear require)
            filterTable[self.filterKey] = nil
            if excludeTable[self.filterKey] then
                excludeTable[self.filterKey] = nil
            else
                excludeTable[self.filterKey] = true
            end
        else
            -- Left-click: toggle require (clear exclude)
            if excludeTable then excludeTable[self.filterKey] = nil end
            if filterTable[self.filterKey] then
                filterTable[self.filterKey] = nil
            else
                filterTable[self.filterKey] = true
            end
        end
        refreshFn()
        TriggerRefilter()
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(ROLE_LABELS[role], 1, 1, 1)
        if excludeTable then
            GameTooltip:AddLine("Left-click: must have", 0.5, 1, 0.5)
            GameTooltip:AddLine("Right-click: must NOT have", 1, 0.4, 0.4)
        end
        GameTooltip:Show()
    end)
    btn:SetScript("OnLeave", GameTooltip_Hide)

    UpdateRoleButtonVisual(btn, "off")
    return btn
end

-------------------------------------------------------------------------------
-- Class Row
-------------------------------------------------------------------------------

local function CreateClassRow(parent, class, filterTable, excludeTable, refreshFn)
    local row = CreateFrame("Button", nil, parent)
    row:SetSize(COLUMN_WIDTH, CLASS_ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.filterKey = class

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(CLASS_ICON_SMALL, CLASS_ICON_SMALL)
    icon:SetPoint("LEFT", row, "LEFT", 2, 0)
    icon:SetTexture(CLASS_ICON_TEXTURE)
    local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if tc then icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
    row.icon = icon

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", icon, "RIGHT", 6, 0)
    local color = RAID_CLASS_COLORS[class]
    if color then label:SetTextColor(color.r, color.g, color.b) end
    label:SetText(CLASS_LABELS[class])
    row.label = label

    local check = row:CreateTexture(nil, "OVERLAY")
    check:SetSize(14, 14)
    check:SetPoint("RIGHT", row, "RIGHT", -2, 0)
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check:Hide()
    row.check = check

    -- Red X for exclude state
    if excludeTable then
        local exX = row:CreateTexture(nil, "OVERLAY")
        exX:SetSize(12, 12)
        exX:SetPoint("RIGHT", row, "RIGHT", -3, 0)
        exX:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
        exX:Hide()
        row.excludeX = exX
    end

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight")
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.3)

    row:SetScript("OnClick", function(self, mouseButton)
        if mouseButton == "RightButton" and excludeTable then
            filterTable[self.filterKey] = nil
            if excludeTable[self.filterKey] then
                excludeTable[self.filterKey] = nil
            else
                excludeTable[self.filterKey] = true
            end
        else
            if excludeTable then excludeTable[self.filterKey] = nil end
            if filterTable[self.filterKey] then
                filterTable[self.filterKey] = nil
            else
                filterTable[self.filterKey] = true
            end
        end
        refreshFn()
        TriggerRefilter()
    end)

    UpdateClassRowVisual(row, "off")
    return row
end

-------------------------------------------------------------------------------
-- Section Builder (builds into a column anchored at xAnchor)
-------------------------------------------------------------------------------

local function BuildFilterSection(parent, xAnchor, yStart, label, f, widgets)
    local yOff = yStart

    -- "Show" checkbox + header — checked = visible, unchecked = hidden
    local showBtn = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
    showBtn:SetSize(22, 22)
    showBtn:SetPoint("TOPLEFT", parent, "TOPLEFT", xAnchor, yOff + 2)
    showBtn:SetChecked(true)  -- shown by default
    widgets.showCheckbox = showBtn

    local header = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    header:SetPoint("LEFT", showBtn, "RIGHT", 2, 0)
    header:SetText(label)
    header:SetTextColor(1, 0.82, 0)

    showBtn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        if self:GetChecked() then
            GameTooltip:SetText("Showing " .. label:lower(), 0.5, 1, 0.5)
            GameTooltip:AddLine("Uncheck to hide all " .. label:lower(), 0.7, 0.7, 0.7, true)
        else
            GameTooltip:SetText("Hiding " .. label:lower(), 1, 0.3, 0.3)
            GameTooltip:AddLine("Check to show " .. label:lower(), 0.7, 0.7, 0.7, true)
        end
        GameTooltip:Show()
    end)
    showBtn:SetScript("OnLeave", GameTooltip_Hide)

    yOff = yOff - math.max(header:GetStringHeight(), 22) - 4

    -- Content frame (everything below header, gets dimmed when hidden)
    local content = CreateFrame("Frame", nil, parent)
    content:SetPoint("TOPLEFT", parent, "TOPLEFT", xAnchor, yOff)
    content:SetSize(COLUMN_WIDTH, 1)  -- height doesn't matter for anchoring children
    widgets.contentFrame = content

    local cYOff = 0

    local refreshFn = function() RefreshSection(widgets, f) end

    showBtn:SetScript("OnClick", function(self)
        f.hidden = not self:GetChecked()
        refreshFn()
        TriggerRefilter()
    end)

    -- Roles label
    local rolesLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    rolesLabel:SetPoint("TOP", content, "TOPLEFT", COLUMN_WIDTH / 2, cYOff)
    rolesLabel:SetText("Roles")
    rolesLabel:SetTextColor(0.7, 0.7, 0.7)
    cYOff = cYOff - rolesLabel:GetStringHeight() - 4

    local roleRowWidth = 3 * ICON_SIZE + 2 * ICON_GAP
    local roleStartX = (COLUMN_WIDTH - roleRowWidth) / 2
    widgets.roleButtons = {}
    for i, role in ipairs(ROLE_ORDER) do
        local btn = CreateRoleButton(content, role, f.roles, f.excludeRoles, refreshFn)
        local xOff = roleStartX + (i - 1) * (ICON_SIZE + ICON_GAP)
        btn:SetPoint("TOPLEFT", content, "TOPLEFT", xOff, cYOff)
        widgets.roleButtons[#widgets.roleButtons + 1] = btn
    end
    cYOff = cYOff - ICON_SIZE - 8

    -- Classes label
    local classesLabel = content:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    classesLabel:SetPoint("TOP", content, "TOPLEFT", COLUMN_WIDTH / 2, cYOff)
    classesLabel:SetText("Classes")
    classesLabel:SetTextColor(0.7, 0.7, 0.7)
    cYOff = cYOff - classesLabel:GetStringHeight() - 3

    widgets.classRows = {}
    for _, class in ipairs(CLASS_ORDER) do
        local row = CreateClassRow(content, class, f.classes, f.excludeClasses, refreshFn)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, cYOff)
        widgets.classRows[#widgets.classRows + 1] = row
        cYOff = cYOff - CLASS_ROW_HEIGHT
    end

    return yOff + cYOff
end

-------------------------------------------------------------------------------
-- Side Panel
-------------------------------------------------------------------------------

local function CreateSidePanel()
    if sidePanel then return sidePanel end

    sidePanel = CreateFrame("Frame", "LFGFilterPanel", LFGParentFrame)
    sidePanel:SetWidth(PANEL_WIDTH)
    sidePanel:SetPoint("TOPLEFT", LFGParentFrame, "TOPRIGHT", -1, 0)
    sidePanel:SetFrameStrata("DIALOG")

    -- Solid black background
    local bg = sidePanel:CreateTexture(nil, "BACKGROUND")
    bg:SetAllPoints()
    bg:SetColorTexture(0, 0, 0, 1)

    -- Border
    local border = CreateFrame("Frame", nil, sidePanel, "BackdropTemplate")
    border:SetAllPoints()
    border:SetBackdrop({
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })

    local yOff = -PANEL_PADDING

    -- Title
    local title = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOP", sidePanel, "TOP", 0, yOff)
    title:SetText("LFG Filter")
    yOff = yOff - title:GetStringHeight() - 6

    -- Separator under title
    local sep = sidePanel:CreateTexture(nil, "ARTWORK")
    sep:SetHeight(1)
    sep:SetPoint("LEFT", PANEL_PADDING, 0)
    sep:SetPoint("RIGHT", -PANEL_PADDING, 0)
    sep:SetPoint("TOP", sidePanel, "TOP", 0, yOff)
    sep:SetColorTexture(0.4, 0.4, 0.4, 0.6)
    yOff = yOff - SECTION_GAP

    -- Two columns side by side
    local leftX = PANEL_PADDING
    local rightX = PANEL_PADDING + COLUMN_WIDTH + COLUMN_GAP

    local leftBottom = BuildFilterSection(sidePanel, leftX, yOff, "Groups (2+)", groupFilters, groupWidgets)
    local rightBottom = BuildFilterSection(sidePanel, rightX, yOff, "Singles (1)", singleFilters, singleWidgets)

    local contentBottom = math.min(leftBottom, rightBottom)

    -- Help legend at bottom
    local legendY = contentBottom - SECTION_GAP

    local legendSep = sidePanel:CreateTexture(nil, "ARTWORK")
    legendSep:SetHeight(1)
    legendSep:SetPoint("LEFT", PANEL_PADDING, 0)
    legendSep:SetPoint("RIGHT", -PANEL_PADDING, 0)
    legendSep:SetPoint("TOP", sidePanel, "TOP", 0, legendY)
    legendSep:SetColorTexture(0.4, 0.4, 0.4, 0.4)
    legendY = legendY - 8

    local includeLine = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    includeLine:SetPoint("TOPLEFT", sidePanel, "TOPLEFT", PANEL_PADDING + 2, legendY)
    includeLine:SetText("|cff80ff80Left-click|r  Include role or class")
    includeLine:SetTextColor(0.6, 0.6, 0.6)
    legendY = legendY - includeLine:GetStringHeight() - 4

    local excludeLine = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    excludeLine:SetPoint("TOPLEFT", sidePanel, "TOPLEFT", PANEL_PADDING + 2, legendY)
    excludeLine:SetText("|cffff6666Right-click|r  Exclude role or class")
    excludeLine:SetTextColor(0.6, 0.6, 0.6)
    legendY = legendY - excludeLine:GetStringHeight() - 4

    local bottomY = legendY - PANEL_PADDING
    sidePanel:SetHeight(-bottomY)

    -- Vertical separator between columns (above legend only)
    local vsep = sidePanel:CreateTexture(nil, "ARTWORK")
    vsep:SetWidth(1)
    vsep:SetPoint("TOP", sidePanel, "TOP", 0, yOff)
    vsep:SetPoint("BOTTOM", sidePanel, "TOP", 0, contentBottom)
    vsep:SetPoint("LEFT", sidePanel, "LEFT", PANEL_PADDING + COLUMN_WIDTH + COLUMN_GAP / 2, 0)
    vsep:SetColorTexture(0.4, 0.4, 0.4, 0.6)

    -- Resize grip at bottom-right corner
    local grip = CreateFrame("Button", nil, sidePanel)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", -2, 2)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")

    grip:SetScript("OnMouseDown", function(self, button)
        if button ~= "LeftButton" then return end
        self.startX, self.startY = GetCursorPosition()
        self.startScale = sidePanel:GetScale()
        self.stdWidth = sidePanel:GetWidth() * sidePanel:GetEffectiveScale()
        self.stdHeight = sidePanel:GetHeight() * sidePanel:GetEffectiveScale()
        self:SetScript("OnUpdate", function(self)
            local curX, curY = GetCursorPosition()
            local ratioX = (self.stdWidth + (curX - self.startX)) / self.stdWidth
            local ratioY = (self.stdHeight + (self.startY - curY)) / self.stdHeight
            local ratio = math.max(ratioX, ratioY)
            local newScale = math.max(0.5, math.min(2.0, self.startScale * ratio))
            sidePanel:SetScale(newScale)
        end)
    end)
    grip:SetScript("OnMouseUp", function(self)
        self:SetScript("OnUpdate", nil)
    end)

    return sidePanel
end

-------------------------------------------------------------------------------
-- Hook & Init
-------------------------------------------------------------------------------

local initialized = false

local function Initialize()
    if initialized then return end
    if not LFGBrowseFrame or not LFGParentFrame then return end
    initialized = true

    CreateSidePanel()
    sidePanel:Hide()

    LFGBrowseFrame:HookScript("OnShow", function()
        if sidePanel then sidePanel:Show() end
    end)
    LFGBrowseFrame:HookScript("OnHide", function()
        if sidePanel then sidePanel:Hide() end
    end)

    if LFGBrowseFrame:IsShown() then
        sidePanel:Show()
    end

    local function SaveScroll()
        local sb = LFGBrowseFrame.ScrollBox
        if sb and sb.GetScrollPercentage then
            return sb:GetScrollPercentage()
        end
        return nil
    end

    local function RestoreScroll(pct)
        if pct then
            local sb = LFGBrowseFrame.ScrollBox
            if sb and sb.SetScrollPercentage then
                sb:SetScrollPercentage(pct)
            end
        end
    end

    hooksecurefunc(LFGBrowseFrame, "UpdateResultList", function(self)
        if not HasActiveFilters() then return end
        local pct = SaveScroll()
        FilterResults(self)
        self:UpdateResults()
        RestoreScroll(pct)
    end)

    -- Auto-remove delisted entries in real-time
    local delistFrame = CreateFrame("Frame")
    delistFrame:RegisterEvent("LFG_LIST_SEARCH_RESULT_UPDATED")
    delistFrame:SetScript("OnEvent", function(_, event, resultID)
        if not LFGBrowseFrame:IsShown() then return end
        local results = LFGBrowseFrame.results
        if not results then return end

        local info = C_LFGList.GetSearchResultInfo(resultID)
        if info and info.isDelisted then
            for i = #results, 1, -1 do
                if results[i] == resultID then
                    table.remove(results, i)
                    local pct = SaveScroll()
                    LFGBrowseFrame:UpdateResults()
                    RestoreScroll(pct)
                    return
                end
            end
        end
    end)
end

local frame = CreateFrame("Frame")
frame:RegisterEvent("ADDON_LOADED")
frame:SetScript("OnEvent", function(self, event, loadedAddon)
    if event == "ADDON_LOADED" and loadedAddon == "Blizzard_GroupFinder_VanillaStyle" then
        C_Timer.After(0, Initialize)
    end
end)

if LFGBrowseFrame then
    C_Timer.After(0, Initialize)
end
