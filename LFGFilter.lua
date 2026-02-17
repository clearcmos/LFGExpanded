local addonName, addon = ...

-------------------------------------------------------------------------------
-- Constants
-------------------------------------------------------------------------------

local ROLE_ICON_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICON-ROLES"
local ROLE_BG_TEXTURE = "Interface\\LFGFrame\\UI-LFG-ICONS-ROLEBACKGROUNDS"
local CLASS_ICON_TEXTURE = "Interface\\GLUES\\CHARACTERCREATE\\UI-CharacterCreate-Classes"

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

local ROLE_BUTTON_SIZE = 48
local ROLE_BG_SIZE = 80
local ROLE_BUTTON_GAP = 25
local SECTION_GAP = 10
local CLASS_ROW_HEIGHT = 31
local CLASS_ICON_SMALL = 18
local PANEL_WIDTH = 384
local PANEL_HEIGHT = 512
local CONTENT_LEFT = 22
local CONTENT_TOP = -50
local CONTENT_WIDTH = 324
local CONTENT_HEIGHT = 347

-------------------------------------------------------------------------------
-- State
-------------------------------------------------------------------------------

local filters = { roles = {}, excludeRoles = {}, classes = {}, excludeClasses = {} }
local showGroups = true
local showSingles = true
local show70Only = false

local sidePanel
local filterTab
local filterWidgets = {}

local classCounts = {}
local classRoleCounts = {}  -- classRoleCounts["DRUID"] = { TANK=0, HEALER=0, DAMAGER=0 }
local classNotes = {}

-------------------------------------------------------------------------------
-- Filter Logic
-------------------------------------------------------------------------------

local function HasActiveSection(f)
    return next(f.roles) ~= nil or next(f.classes) ~= nil
        or (f.excludeRoles and next(f.excludeRoles) ~= nil)
        or (f.excludeClasses and next(f.excludeClasses) ~= nil)
end

local function HasActiveFilters()
    return HasActiveSection(filters) or not showGroups or not showSingles or show70Only
end

local function HasActivitySelected()
    local cat = LFGBrowseFrame and LFGBrowseFrame.CategoryDropdown
    local act = LFGBrowseFrame and LFGBrowseFrame.ActivityDropdown
    if not cat or not act then return false end
    local categoryID = cat.selectedCategoryID
    if not categoryID or categoryID == 0 then return false end
    local selected = act.selectedValues
    if not selected or #selected == 0 then return false end
    return true
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
        if not showGroups then return false end
    else
        if not showSingles then return false end
    end

    if show70Only then
        for i = 1, n do
            local mi = C_LFGList.GetSearchResultPlayerInfo(resultID, i)
            if mi and mi.level and mi.level < 70 then return false end
        end
    end

    if not HasActiveSection(filters) then return true end

    return PassesRoleCheck(filters, resultID, n)
        and PassesClassCheck(filters, resultID, n)
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

local LFGROLE_TO_FILTERROLE = { tank = "TANK", healer = "HEALER", dps = "DAMAGER" }

local function ComputeClassData(results)
    wipe(classCounts)
    wipe(classRoleCounts)
    wipe(classNotes)
    if not results then return end

    for _, resultID in ipairs(results) do
        local info = C_LFGList.GetSearchResultInfo(resultID)
        if info then
            local numMembers = info.numMembers or 0
            local seenClasses = {}

            -- Collect per-class data: which classes appear, and which roles per class (per listing)
            local classRolesInListing = {}  -- classRolesInListing["HUNTER"] = { TANK=true, DAMAGER=true }
            for i = 1, numMembers do
                local memberInfo = C_LFGList.GetSearchResultPlayerInfo(resultID, i)
                if memberInfo and memberInfo.classFilename then
                    local class = memberInfo.classFilename
                    if not seenClasses[class] then
                        seenClasses[class] = true
                        classCounts[class] = (classCounts[class] or 0) + 1
                        classRolesInListing[class] = {}
                    end
                    local hasRole = false
                    if memberInfo.lfgRoles then
                        for lfgKey, filterRole in pairs(LFGROLE_TO_FILTERROLE) do
                            if memberInfo.lfgRoles[lfgKey] then
                                classRolesInListing[class][filterRole] = true
                                hasRole = true
                            end
                        end
                    end
                    -- Fallback to assignedRole for group members without lfgRoles
                    if not hasRole and memberInfo.assignedRole and memberInfo.assignedRole ~= "" and memberInfo.assignedRole ~= "NONE" then
                        classRolesInListing[class][memberInfo.assignedRole] = true
                    end
                end
            end
            -- Tally roles per class (once per listing, not per member)
            for class, roles in pairs(classRolesInListing) do
                if not classRoleCounts[class] then
                    classRoleCounts[class] = { TANK = 0, HEALER = 0, DAMAGER = 0 }
                end
                for filterRole in pairs(roles) do
                    classRoleCounts[class][filterRole] = classRoleCounts[class][filterRole] + 1
                end
            end

            local comment = info.comment
            if comment and comment ~= "" then
                local leaderInfo = C_LFGList.GetSearchResultPlayerInfo(resultID, 1)
                local leaderClass = leaderInfo and leaderInfo.classFilename
                if leaderClass then
                    if not classNotes[leaderClass] then
                        classNotes[leaderClass] = {}
                    end
                    classNotes[leaderClass][#classNotes[leaderClass] + 1] = { resultID = resultID, comment = comment }
                end
            end
        end
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
        if btn.bg then btn.bg:SetAlpha(0.6); btn.bg:SetVertexColor(1, 1, 1) end
        if btn.includeCheck then btn.includeCheck:Show() end
        if btn.excludeX then btn.excludeX:Hide() end
    elseif state == "exclude" then
        btn.icon:SetDesaturated(false)
        btn.icon:SetVertexColor(1, 0.3, 0.3)
        btn.icon:SetAlpha(1.0)
        if btn.bg then btn.bg:SetAlpha(0.4); btn.bg:SetVertexColor(1, 0.3, 0.3) end
        if btn.includeCheck then btn.includeCheck:Hide() end
        if btn.excludeX then btn.excludeX:Show() end
    else
        btn.icon:SetDesaturated(true)
        btn.icon:SetVertexColor(1, 1, 1)
        btn.icon:SetAlpha(0.4)
        if btn.bg then btn.bg:SetAlpha(0.15); btn.bg:SetVertexColor(1, 1, 1) end
        if btn.includeCheck then btn.includeCheck:Hide() end
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
end

local function UpdateClassCounts()
    if not filterWidgets.classRows then return end
    for _, row in ipairs(filterWidgets.classRows) do
        local cls = row.filterKey
        local count = classCounts[cls] or 0
        row.countLabel:SetText(count)
        if count > 0 then
            row.countLabel:SetAlpha(1.0)
            row.infoBtn:SetAlpha(0.8)
        else
            row.countLabel:SetAlpha(0.3)
            row.infoBtn:SetAlpha(0.3)
        end
        -- Update role breakdown
        local rc = classRoleCounts[cls]
        for _, role in ipairs(ROLE_ORDER) do
            local rw = row.roleWidgets[role]
            local n = rc and rc[role] or 0
            rw.count:SetText(n)
            if n > 0 then
                rw.icon:SetDesaturated(false)
                rw.icon:SetAlpha(0.9)
                rw.count:SetAlpha(0.9)
            else
                rw.icon:SetDesaturated(true)
                rw.icon:SetAlpha(0.3)
                rw.count:SetAlpha(0.3)
            end
        end
    end
end

local function UpdateContentVisibility(show)
    if not filterWidgets.classRows then return end
    if show then
        if filterWidgets.warningText then filterWidgets.warningText:Hide() end
        for _, row in ipairs(filterWidgets.classRows) do
            row:Show()
        end
        if filterWidgets.resetBtn then
            if HasActiveFilters() then
                filterWidgets.resetBtn:Enable()
            else
                filterWidgets.resetBtn:Disable()
            end
        end
    else
        if filterWidgets.warningText then filterWidgets.warningText:Show() end
        for _, row in ipairs(filterWidgets.classRows) do
            row:Hide()
        end
        if filterWidgets.resetBtn then filterWidgets.resetBtn:Disable() end
    end
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
    btn:SetSize(ROLE_BUTTON_SIZE, ROLE_BUTTON_SIZE)
    btn:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    btn.filterKey = role

    -- Colored background ring (80x80, centered behind 48x48 button)
    local bg = btn:CreateTexture(nil, "BACKGROUND")
    bg:SetSize(ROLE_BG_SIZE, ROLE_BG_SIZE)
    bg:SetPoint("CENTER")
    bg:SetTexture(ROLE_BG_TEXTURE)
    bg:SetTexCoord(GetBackgroundTexCoordsForRole(role))
    bg:SetAlpha(0.15)
    btn.bg = bg

    -- Role icon (full button size, uses big role icon atlas)
    local icon = btn:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(ROLE_ICON_TEXTURE)
    icon:SetTexCoord(GetTexCoordsForRole(role))
    btn.icon = icon

    -- Green checkmark overlay (for include state)
    local chk = btn:CreateTexture(nil, "OVERLAY", nil, 2)
    chk:SetSize(ROLE_BUTTON_SIZE * 0.6, ROLE_BUTTON_SIZE * 0.6)
    chk:SetPoint("CENTER")
    chk:SetTexture("Interface\\RaidFrame\\ReadyCheck-Ready")
    chk:Hide()
    btn.includeCheck = chk

    -- Red X overlay (for exclude state)
    local exX = btn:CreateTexture(nil, "OVERLAY", nil, 2)
    exX:SetSize(ROLE_BUTTON_SIZE * 0.6, ROLE_BUTTON_SIZE * 0.6)
    exX:SetPoint("CENTER")
    exX:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
    exX:Hide()
    btn.excludeX = exX

    -- Highlight on hover
    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetSize(ROLE_BG_SIZE, ROLE_BG_SIZE)
    hl:SetPoint("CENTER")
    hl:SetTexture("Interface\\Buttons\\UI-Common-MouseHilight")
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.3)

    -- Left-click: toggle off/include; Right-click: toggle off/exclude
    btn:SetScript("OnClick", function(self, mouseButton)
        local key = self.filterKey
        if mouseButton == "RightButton" then
            filterTable[key] = nil
            if excludeTable[key] then
                excludeTable[key] = nil
            else
                excludeTable[key] = true
            end
        else
            excludeTable[key] = nil
            if filterTable[key] then
                filterTable[key] = nil
            else
                filterTable[key] = true
            end
        end
        refreshFn()
        TriggerRefilter()
    end)
    btn:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(ROLE_LABELS[role], 1, 1, 1)
        GameTooltip:AddLine("Left-click: require | Right-click: exclude", 0.7, 0.7, 0.7)
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
    row:SetSize(CONTENT_WIDTH, CLASS_ROW_HEIGHT)
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row.filterKey = class

    -- Row background (matches native LFG browse entry style)
    local bg = row:CreateTexture(nil, "BACKGROUND")
    bg:SetPoint("TOPLEFT", 3, -2)
    bg:SetPoint("BOTTOMRIGHT", -3, 0)
    bg:SetColorTexture(1, 1, 1, 0.04)

    local icon = row:CreateTexture(nil, "ARTWORK")
    icon:SetSize(CLASS_ICON_SMALL, CLASS_ICON_SMALL)
    icon:SetPoint("LEFT", row, "LEFT", 8, 0)
    icon:SetTexture(CLASS_ICON_TEXTURE)
    local tc = CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
    if tc then icon:SetTexCoord(tc[1], tc[2], tc[3], tc[4]) end
    row.icon = icon

    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    label:SetPoint("LEFT", icon, "RIGHT", 8, 0)
    local color = RAID_CLASS_COLORS[class]
    if color then label:SetTextColor(color.r, color.g, color.b) end
    label:SetText(CLASS_LABELS[class])
    row.label = label

    -- Role breakdown icons (native large atlas, 18x18, same as Group Browser)
    local LARGE_ROLE_ATLAS = {
        TANK = "groupfinder-icon-role-large-tank",
        HEALER = "groupfinder-icon-role-large-heal",
        DAMAGER = "groupfinder-icon-role-large-dps",
    }
    local ROLE_START_X = 120
    local ROLE_SPACING = 36
    local roleWidgets = {}
    for idx, role in ipairs(ROLE_ORDER) do
        local ri = row:CreateTexture(nil, "ARTWORK")
        ri:SetSize(18, 18)
        ri:SetAtlas(LARGE_ROLE_ATLAS[role], false)
        ri:SetDesaturated(true)
        ri:SetAlpha(0.3)
        ri:SetPoint("LEFT", row, "LEFT", ROLE_START_X + (idx - 1) * ROLE_SPACING, 0)

        local rc = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
        rc:SetText("0")
        rc:SetTextColor(0.7, 0.7, 0.7)
        rc:SetAlpha(0.3)
        rc:SetPoint("LEFT", ri, "RIGHT", 2, 0)

        roleWidgets[role] = { icon = ri, count = rc }
    end
    row.roleWidgets = roleWidgets

    -- Count label (number of listings with this class)
    local countLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    countLabel:SetPoint("RIGHT", row, "RIGHT", -55, 0)
    countLabel:SetJustifyH("RIGHT")
    countLabel:SetText("0")
    countLabel:SetTextColor(0.7, 0.7, 0.7)
    countLabel:SetAlpha(0.3)
    row.countLabel = countLabel

    -- Info button (hover shows notes from listings of this class)
    local infoFrame = CreateFrame("Frame", nil, row)
    infoFrame:SetSize(24, 24)
    infoFrame:SetPoint("LEFT", countLabel, "RIGHT", 4, 0)
    infoFrame:EnableMouse(true)

    local infoIcon = infoFrame:CreateTexture(nil, "ARTWORK")
    infoIcon:SetAllPoints()
    infoIcon:SetTexture("Interface\\common\\help-i")
    infoIcon:SetAlpha(0.8)

    infoFrame:SetScript("OnEnter", function(self)
        local cls = row.filterKey
        local notes = classNotes[cls]
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(CLASS_LABELS[cls] .. " Notes", 1, 1, 1)
        if notes and #notes > 0 then
            local sorted = {}
            for i, entry in ipairs(notes) do
                local rid = entry.resultID
                local name
                local ri = C_LFGList.GetSearchResultInfo(rid)
                if ri then name = ri.leaderName end
                if not name then
                    local mi = C_LFGList.GetSearchResultPlayerInfo(rid, 1)
                    name = mi and mi.name
                end
                if not name then
                    local li = C_LFGList.GetSearchResultLeaderInfo(rid)
                    name = li and li.name
                end
                sorted[#sorted + 1] = { name = name or "Unknown", comment = entry.comment }
            end
            table.sort(sorted, function(a, b)
                return a.name:lower() < b.name:lower()
            end)
            for i, entry in ipairs(sorted) do
                if i > 20 then
                    GameTooltip:AddLine("... and " .. (#sorted - 20) .. " more", 0.5, 0.5, 0.5)
                    break
                end
                if i > 1 then
                    GameTooltip:AddLine(" ", 1, 1, 1)
                end
                local clr2 = RAID_CLASS_COLORS[cls]
                if clr2 then
                    GameTooltip:AddLine(entry.name, clr2.r, clr2.g, clr2.b)
                else
                    GameTooltip:AddLine(entry.name, 0.6, 0.8, 1)
                end
                GameTooltip:AddLine(entry.comment, 1, 0.82, 0, true)
            end
        else
            GameTooltip:AddLine("No notes in current listings", 0.5, 0.5, 0.5)
        end
        GameTooltip:Show()
    end)
    infoFrame:SetScript("OnLeave", GameTooltip_Hide)
    row.infoBtn = infoFrame

    local check = row:CreateTexture(nil, "OVERLAY")
    check:SetSize(16, 16)
    check:SetPoint("RIGHT", row, "RIGHT", -8, 0)
    check:SetTexture("Interface\\Buttons\\UI-CheckBox-Check")
    check:Hide()
    row.check = check

    -- Red X for exclude state
    if excludeTable then
        local exX = row:CreateTexture(nil, "OVERLAY")
        exX:SetSize(14, 14)
        exX:SetPoint("RIGHT", row, "RIGHT", -8, 0)
        exX:SetTexture("Interface\\RaidFrame\\ReadyCheck-NotReady")
        exX:Hide()
        row.excludeX = exX
    end

    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetPoint("TOPLEFT", 3, -2)
    hl:SetPoint("BOTTOMRIGHT", -3, 0)
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
-- Section Builder (single column)
-------------------------------------------------------------------------------

local function BuildFilterSection(parent, f, widgets)
    local content = CreateFrame("Frame", nil, parent)
    content:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, 0)
    content:SetSize(CONTENT_WIDTH, 1)
    widgets.contentFrame = content

    local refreshFn = function() RefreshSection(widgets, f) end

    -- Role icon zone matches native LFG proportions (68px: icons at -60, content at -128)
    local separatorOff = -68
    local iconCenterY = -((math.abs(separatorOff) - ROLE_BUTTON_SIZE) / 2)
    local cYOff = iconCenterY

    local numButtons = 3
    local totalWidth = numButtons * ROLE_BUTTON_SIZE + (numButtons - 1) * ROLE_BUTTON_GAP
    local roleStartX = (CONTENT_WIDTH - totalWidth) / 2
    widgets.roleButtons = {}
    for i, role in ipairs(ROLE_ORDER) do
        local btn = CreateRoleButton(content, role, f.roles, f.excludeRoles, refreshFn)
        local xOff = roleStartX + (i - 1) * (ROLE_BUTTON_SIZE + ROLE_BUTTON_GAP)
        btn:SetPoint("TOPLEFT", content, "TOPLEFT", xOff, cYOff)
        widgets.roleButtons[#widgets.roleButtons + 1] = btn
    end

    -- No manual separator needed — the baked-in ornate bar in UI-LFG-FRAME
    -- at y=-128 is revealed by positioning bgArt to start just below it
    cYOff = separatorOff - 12

    widgets.classRows = {}
    for _, class in ipairs(CLASS_ORDER) do
        local row = CreateClassRow(content, class, f.classes, f.excludeClasses, refreshFn)
        row:SetPoint("TOPLEFT", content, "TOPLEFT", 0, cYOff)
        widgets.classRows[#widgets.classRows + 1] = row
        row:Hide()
        cYOff = cYOff - CLASS_ROW_HEIGHT
    end

    -- Warning text shown until a search is performed
    local warning = content:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    warning:SetPoint("CENTER", content, "TOPLEFT", CONTENT_WIDTH / 2, -200)
    warning:SetWidth(CONTENT_WIDTH - 40)
    warning:SetJustifyH("CENTER")
    warning:SetText("Select at least one dungeon or raid in Group Browser and click Search Again to continue")
    warning:SetTextColor(0.6, 0.6, 0.6)
    widgets.warningText = warning

    return cYOff
end

-------------------------------------------------------------------------------
-- Side Panel (native LFG frame design)
-------------------------------------------------------------------------------

local function SetFilterTabHighlight(active)
    if not filterTab then return end
    if active then
        filterTab:SetNormalFontObject(GameFontHighlightSmall)
    else
        filterTab:SetNormalFontObject(GameFontNormalSmall)
    end
end

local function CreateSidePanel()
    if sidePanel then return sidePanel end

    sidePanel = CreateFrame("Frame", "LFGFilterPanel", LFGParentFrame, "PortraitFrameTemplate")
    sidePanel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)
    sidePanel:SetPoint("TOPLEFT", LFGParentFrame, "TOPRIGHT", -1, 0)
    sidePanel:SetFrameStrata("DIALOG")

    ---------------------------------------------------------------------------
    -- Hide PortraitFrameTemplate chrome (we only use it for the portrait)
    ---------------------------------------------------------------------------

    sidePanel.Bg:Hide()
    sidePanel.TitleBg:Hide()
    sidePanel.TopBorder:Hide()
    sidePanel.TopRightCorner:Hide()
    sidePanel.BotLeftCorner:Hide()
    sidePanel.BotRightCorner:Hide()
    sidePanel.BottomBorder:Hide()
    sidePanel.LeftBorder:Hide()
    sidePanel.RightBorder:Hide()
    sidePanel.TopTileStreaks:Hide()
    sidePanel.PortraitFrame:Hide()
    sidePanel.TitleText:Hide()
    sidePanel.CloseButton:Hide()
    if sidePanel.NineSlice then sidePanel.NineSlice:Hide() end
    -- Hide the unmasked portrait duplicate from PortraitFrameTemplateNoCloseButton
    if sidePanel.portrait then sidePanel.portrait:Hide() end

    ---------------------------------------------------------------------------
    -- Portrait (circle-masked, from PortraitFrameTemplate's PortraitContainer)
    ---------------------------------------------------------------------------

    -- Reposition PortraitContainer so the portrait centers within the LFG ring
    -- Ring center = TOPLEFT(12,-5) + half of 64x64 = (44,-37)
    -- Portrait is 62x62 at (-5,7) within container, so container goes at (18,-13)
    sidePanel.PortraitContainer:ClearAllPoints()
    sidePanel.PortraitContainer:SetPoint("TOPLEFT", sidePanel, "TOPLEFT", 18, -13)
    SetPortraitToTexture(sidePanel.PortraitContainer.portrait, "Interface\\FriendsFrame\\FriendsFrameScrollIcon")

    -- LFG-style gold portrait ring (over the template's masked portrait)
    local portraitBorder = sidePanel:CreateTexture(nil, "OVERLAY")
    portraitBorder:SetSize(64, 64)
    portraitBorder:SetPoint("TOPLEFT", 12, -5)
    portraitBorder:SetTexture("Interface\\LFGFrame\\UI-LFG-PORTRAIT")

    ---------------------------------------------------------------------------
    -- Background textures (LFG-style, 2-piece)
    ---------------------------------------------------------------------------

    local bgTop = sidePanel:CreateTexture(nil, "BACKGROUND", nil, -1)
    bgTop:SetSize(512, 256)
    bgTop:SetPoint("TOPLEFT", 0, 0)
    bgTop:SetTexture("Interface\\LFGFrame\\UI-LFG-FRAME")
    bgTop:SetTexCoord(0, 1.0, 0, 0.5)

    local bgBot = sidePanel:CreateTexture(nil, "BACKGROUND", nil, 1)
    bgBot:SetSize(512, 256)
    bgBot:SetPoint("TOPLEFT", 0, -256)
    bgBot:SetTexture("Interface\\LFGFrame\\UI-LFG-FRAME")
    bgBot:SetTexCoord(0, 1.0, 0.5, 1.0)

    -- Content area background: matches native LFG exactly (y=-128, 282px tall)
    -- This reveals the ornate separator bars baked into UI-LFG-FRAME at both
    -- the top (between roles and content) and bottom (above button wells)
    local bgArt = sidePanel:CreateTexture(nil, "BACKGROUND", nil, 2)
    bgArt:SetSize(CONTENT_WIDTH, 282)
    bgArt:SetPoint("TOPLEFT", CONTENT_LEFT, -128)
    bgArt:SetAtlas("groupfinder-background-classic")

    ---------------------------------------------------------------------------
    -- Title
    ---------------------------------------------------------------------------

    local title = sidePanel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    title:SetPoint("TOP", 0, -18)
    title:SetText("Filters")

    ---------------------------------------------------------------------------
    -- Close button
    ---------------------------------------------------------------------------

    local closeBtn = CreateFrame("Button", nil, sidePanel, "UIPanelCloseButton")
    closeBtn:SetPoint("TOPRIGHT", -26, -8)
    closeBtn:SetScript("OnClick", function()
        sidePanel:Hide()
        SetFilterTabHighlight(false)
    end)

    ---------------------------------------------------------------------------
    -- Info button (hover tooltip explains controls)
    ---------------------------------------------------------------------------

    local infoBtn = CreateFrame("Button", nil, sidePanel)
    infoBtn:SetSize(24, 24)
    infoBtn:SetPoint("TOPRIGHT", -40, -44)

    local infoIcon = infoBtn:CreateTexture(nil, "ARTWORK")
    infoIcon:SetAllPoints()
    infoIcon:SetTexture("Interface\\common\\help-i")
    infoIcon:SetAlpha(0.8)

    infoBtn:SetScript("OnEnter", function(self)
        infoIcon:SetAlpha(1.0)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Filter Controls", 1, 1, 1)
        GameTooltip:AddLine("|cff80ff80Left-click|r  Include role or class", 0.8, 0.8, 0.8)
        GameTooltip:AddLine("|cffff6666Right-click|r  Exclude role or class", 0.8, 0.8, 0.8)
        GameTooltip:Show()
    end)
    infoBtn:SetScript("OnLeave", function()
        infoIcon:SetAlpha(0.8)
        GameTooltip:Hide()
    end)

    ---------------------------------------------------------------------------
    -- Gear button (native DropdownButton with SetupMenu, same as LFG gear)
    ---------------------------------------------------------------------------

    local gearBtn = CreateFrame("DropdownButton", nil, sidePanel, "LFGOptionsButton")
    gearBtn:SetPoint("RIGHT", infoBtn, "LEFT", -4, 0)
    gearBtn:SetupMenu(function(dropdown, rootDescription)
        rootDescription:SetTag("MENU_LFG_FILTER_OPTIONS")

        rootDescription:CreateCheckbox("Show Groups (2+)",
            function() return showGroups end,
            function()
                showGroups = not showGroups
                TriggerRefilter()
            end
        )

        rootDescription:CreateCheckbox("Show Singles (1)",
            function() return showSingles end,
            function()
                showSingles = not showSingles
                TriggerRefilter()
            end
        )

        rootDescription:CreateCheckbox("Show 70 Only",
            function() return show70Only end,
            function()
                show70Only = not show70Only
                TriggerRefilter()
            end
        )
    end)

    ---------------------------------------------------------------------------
    -- Filter content area (single column, centered)
    ---------------------------------------------------------------------------

    local contentContainer = CreateFrame("Frame", nil, sidePanel)
    contentContainer:SetPoint("TOPLEFT", sidePanel, "TOPLEFT", CONTENT_LEFT, CONTENT_TOP)
    contentContainer:SetSize(CONTENT_WIDTH, CONTENT_HEIGHT)

    BuildFilterSection(contentContainer, filters, filterWidgets)

    ---------------------------------------------------------------------------
    -- Search Again button (bottom center, same style as Send Message button)
    ---------------------------------------------------------------------------

    local searchBtn = CreateFrame("Button", nil, sidePanel, "UIPanelButtonTemplate")
    searchBtn:SetSize(140, 22)
    searchBtn:SetPoint("BOTTOMLEFT", sidePanel, "BOTTOMLEFT", 19, 79)
    searchBtn:SetText("Search Again")
    searchBtn:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        LFGBrowse_DoSearch()
    end)

    local resetBtn = CreateFrame("Button", nil, sidePanel, "UIPanelButtonTemplate")
    resetBtn:SetSize(140, 22)
    resetBtn:SetPoint("BOTTOMRIGHT", sidePanel, "BOTTOMRIGHT", -40, 79)
    resetBtn:SetText("Reset Filters")
    resetBtn:Disable()
    filterWidgets.resetBtn = resetBtn
    resetBtn:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON)
        wipe(filters.roles)
        wipe(filters.excludeRoles)
        wipe(filters.classes)
        wipe(filters.excludeClasses)
        showGroups = true
        showSingles = true
        show70Only = false
        RefreshSection(filterWidgets, filters)
        TriggerRefilter()
    end)

    return sidePanel
end

-------------------------------------------------------------------------------
-- Filter Tab
-------------------------------------------------------------------------------

local function CreateFilterTab()
    filterTab = CreateFrame("Button", "LFGParentFrameTab3", LFGParentFrame, "CharacterFrameTabButtonTemplate")
    filterTab:SetID(3)
    filterTab:SetText("Filters")
    LowerFrameLevel(filterTab)

    -- Prevent the template's DISPLAY_SIZE_CHANGED handler from shifting the tab
    filterTab:UnregisterAllEvents()

    -- Always keep deselected visual state (active textures bleed 4px upward)
    PanelTemplates_DeselectTab(filterTab)

    -- Immediate fallback anchor (works before tab widths are known)
    filterTab:SetPoint("LEFT", LFGParentFrame.Tab2, "RIGHT", -14, 0)
    PanelTemplates_TabResize(filterTab, 0)

    -- Reposition to a fixed BOTTOMLEFT anchor on the parent frame.
    -- This avoids Blizzard's Browse OnShow hack that shifts Tab2 down 2px.
    local function RepositionFilterTab()
        local tab1W = LFGParentFrame.Tab1:GetWidth()
        local tab2W = LFGParentFrame.Tab2:GetWidth()
        if tab1W <= 10 or tab2W <= 10 then return end  -- tabs not laid out yet
        PanelTemplates_TabResize(filterTab, nil, tab2W)
        filterTab:ClearAllPoints()
        filterTab:SetPoint("BOTTOMLEFT", LFGParentFrame, "BOTTOMLEFT", 16 + tab1W - 14 + tab2W - 14, 45)
    end

    -- Defer initial positioning until tab widths are final
    C_Timer.After(0, RepositionFilterTab)

    -- Re-anchor on every tab switch (Blizzard shifts Tab2 in Browse OnShow)
    hooksecurefunc(LFGBrowseFrame, "OnShow", RepositionFilterTab)
    LFGListingFrame:HookScript("OnShow", RepositionFilterTab)

    -- Recompute when Tab1 text changes (Create Listing <-> Edit Listing)
    hooksecurefunc(LFGParentFrame.Tab1, "SetText", function()
        C_Timer.After(0, RepositionFilterTab)
    end)

    filterTab:SetScript("OnClick", function(self)
        if sidePanel:IsShown() then
            sidePanel:Hide()
            SetFilterTabHighlight(false)
        else
            sidePanel:Show()
            SetFilterTabHighlight(true)
        end
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_TAB)
    end)

    filterTab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Filter search results by role and class", 1, 1, 1)
        GameTooltip:Show()
    end)
    filterTab:SetScript("OnLeave", function()
        GameTooltip:Hide()
    end)
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

    CreateFilterTab()

    -- Hide filter panel when LFG parent frame closes
    LFGParentFrame:HookScript("OnHide", function()
        if sidePanel and sidePanel:IsShown() then
            sidePanel:Hide()
            SetFilterTabHighlight(false)
        end
    end)

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
        local show = HasActivitySelected()
        if show then
            ComputeClassData(self.results)
            UpdateClassCounts()
        end
        if show and HasActiveFilters() then
            local pct = SaveScroll()
            FilterResults(self)
            self:UpdateResults()
            RestoreScroll(pct)
        end
        UpdateContentVisibility(show)
    end)

    -- Check if activity already selected (e.g., after /reload)
    if HasActivitySelected() then
        ComputeClassData(LFGBrowseFrame.results)
        UpdateClassCounts()
        UpdateContentVisibility(true)
    end

    -- Also check on panel show, in case activity was selected while panel was hidden
    sidePanel:HookScript("OnShow", function()
        local show = HasActivitySelected()
        if show and LFGBrowseFrame.results then
            ComputeClassData(LFGBrowseFrame.results)
            UpdateClassCounts()
        end
        UpdateContentVisibility(show)
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
