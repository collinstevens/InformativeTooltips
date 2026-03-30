local ADDON_NAME, ns = ...

---------------------------------------------------------------------------
-- Edge cases: talents that buff a spell but don't mention it by name
---------------------------------------------------------------------------

local talentsMissingName = {
    ----Preservation Evoker
    --Living Flame
    [361469] = {
        --Lifeforce Mender
        [376179] = true,
    },
    --Chronoflame
    [431443] = {
        --Lifeforce Mender
        [376179] = true,
    },
    --Fire Breath
    [357208] = {
        --Lifeforce Mender
        [376179] = true,
    },
}

---------------------------------------------------------------------------
-- Edge cases: spells that replace other spells
---------------------------------------------------------------------------

local replacedSpells = {
    ----Preservation Evoker
    --Chronoflame replaces Living Flame
    [431443] = 361469,
    ----Mistweaver Monk
    --Rushing Wind Kick replaces Rising Sun Kick
    [467307] = 107428,
    ----Farseer Shaman
    --Ancestral Swiftness replaces Natures Swiftness
    [443454] = 378081,
    ----Subtlety Rogue
    --Gloomblade replaces Backstab
    [200758] = 53,
    ----Affliction Warlock
    --Drain Soul replaces Shadow Bolt
    [388667] = 686,
}

---------------------------------------------------------------------------
-- Edge cases: talents that mention a spell without meaningfully buffing it
---------------------------------------------------------------------------

local blacklistedTalents = {
    ----Monk
    --Enveloping Mist
    [124682] = {
        --Thunder Focus Tea
        [116680] = true,
        --Secret Infusion
        [388491] = true,
    },
    --Renewing Mist
    [115151] = {
        --Thunder Focus Tea
        [116680] = true,
        --Secret Infusion
        [388491] = true,
    },
    --Vivify
    [116670] = {
        --Thunder Focus Tea
        [116680] = true,
        --Secret Infusion
        [388491] = true,
    },
    --Rising Sun Kick
    [107428] = {
        --Thunder Focus Tea
        [116680] = true,
        --Secret Infusion
        [388491] = true,
    },
    --Expel Harm
    [322101] = {
        --Thunder Focus Tea
        [116680] = true,
        --Secret Infusion
        [388491] = true,
    },
    ----Druid
    --Rejuvenation
    [774] = {
        --Incarnation: Tree of Life
        [33891] = true,
    },
    --Wild Growth
    [48438] = {
        --Incarnation: Tree of Life
        [33891] = true,
    },
    --Regrowth
    [8936] = {
        --Incarnation: Tree of Life
        [33891] = true,
    },
    --Wrath
    [5176] = {
        --Incarnation: Tree of Life
        [33891] = true,
    },
    --Entangling Roots
    [339] = {
        --Incarnation: Tree of Life
        [33891] = true,
    },
    --Grove Guardians
    [102693] = {
        --Cenarius' Guidance
        [393371] = true,
    },
    ----Shaman
    --Flame Shock
    [188389] = {
        --Surge of Power
        [262303] = true,
        --Deeply Rooted Elements
        [378270] = true,
        --Ascendance
        [114050] = true,
    },
    --Chain Lightning
    [188443] = {
        --Surge of Power
        [262303] = true,
    },
    --Lightning Bolt
    [188196] = {
        --Surge of Power
        [262303] = true,
    },
    --Frost Shock
    [196840] = {
        --Surge of Power
        [262303] = true,
    },
    --Lava Burst
    [51505] = {
        --Surge of Power
        [262303] = true,
    },
}

---------------------------------------------------------------------------
-- Talent cache
---------------------------------------------------------------------------

local talentCache = {}

local function UpdateTalentCache()
    table.wipe(talentCache)

    local configID = C_ClassTalents.GetActiveConfigID()
    if not configID then return end

    local configInfo = C_Traits.GetConfigInfo(configID)
    if not configInfo then return end

    -- Build currency-to-source mapping: currency[1] = "Class", currency[2] = spec name
    local specIndex = GetSpecialization()
    local specName = specIndex and select(2, GetSpecializationInfo(specIndex)) or "Spec"
    local currencyToSource = {}
    for _, treeID in ipairs(configInfo.treeIDs) do
        local treeCurrencyInfo = C_Traits.GetTreeCurrencyInfo(configID, treeID, false)
        if treeCurrencyInfo then
            if treeCurrencyInfo[1] then
                currencyToSource[treeCurrencyInfo[1].traitCurrencyID] = "Class"
            end
            if treeCurrencyInfo[2] then
                currencyToSource[treeCurrencyInfo[2].traitCurrencyID] = specName
            end
        end
    end

    -- Cache hero subtree names
    local subTreeNames = {}

    for _, treeID in ipairs(configInfo.treeIDs) do
        local nodes = C_Traits.GetTreeNodes(treeID)
        for _, nodeID in ipairs(nodes) do
            local nodeInfo = C_Traits.GetNodeInfo(configID, nodeID)

            -- Determine source: hero subtree name, or class/spec from node cost currency
            local source
            if nodeInfo.subTreeID then
                if not subTreeNames[nodeInfo.subTreeID] then
                    local subTreeInfo = C_Traits.GetSubTreeInfo(configID, nodeInfo.subTreeID)
                    subTreeNames[nodeInfo.subTreeID] = subTreeInfo and subTreeInfo.name or "Hero"
                end
                source = subTreeNames[nodeInfo.subTreeID]
            else
                local costs = C_Traits.GetNodeCost(configID, nodeID)
                if costs and #costs > 0 then
                    source = currencyToSource[costs[1].ID] or "Class"
                else
                    source = "Class"
                end
            end

            local activeEntryID = nodeInfo.activeEntry and nodeInfo.activeEntry.entryID
            for _, entryID in ipairs(nodeInfo.entryIDs) do
                local entryInfo = C_Traits.GetEntryInfo(configID, entryID)
                if entryInfo and entryInfo.definitionID then
                    local definitionInfo = C_Traits.GetDefinitionInfo(entryInfo.definitionID)
                    if definitionInfo.spellID then
                        local talentSpellID = definitionInfo.spellID
                        local selected = nodeInfo.currentRank > 0 and entryID == activeEntryID
                        local talent = Spell:CreateFromSpellID(talentSpellID)
                        talent:ContinueOnSpellLoad(function()
                            talentCache[talentSpellID] = {
                                name = talent:GetSpellName(),
                                desc = talent:GetSpellDescription(),
                                source = source,
                                selected = selected,
                            }
                        end)
                    end
                end
            end
        end
    end
end

---------------------------------------------------------------------------
-- Saved variables
---------------------------------------------------------------------------

local db
local settingsCategory

---------------------------------------------------------------------------
-- Tooltip enhancement
---------------------------------------------------------------------------

local function EnhanceTooltip(spellID, tooltip)
    if db and db.modifier and not IsShiftKeyDown() then return end

    local spellInfo = C_Spell.GetSpellInfo(spellID)
    if not spellInfo then return end

    local spellName = spellInfo.name
    local replacedName = nil
    if replacedSpells[spellID] then
        local replacedInfo = C_Spell.GetSpellInfo(replacedSpells[spellID])
        if replacedInfo then
            replacedName = replacedInfo.name
        end
    end

    local matches = {}
    for talentSpellID, talentInfo in pairs(talentCache) do
        local isBlacklisted = blacklistedTalents[spellID] and blacklistedTalents[spellID][talentSpellID]
        local isMissingName = talentsMissingName[spellID] and talentsMissingName[spellID][talentSpellID]

        if isMissingName or (not isBlacklisted and talentInfo.name ~= spellName and talentInfo.desc and (string.find(talentInfo.desc, spellName, 1, true) or (replacedName and string.find(talentInfo.desc, replacedName, 1, true)))) then
            matches[#matches + 1] = talentInfo
        end
    end

    if #matches == 0 then return end

    if #matches >= 4 then
        tooltip:SetMinimumWidth(400)
    end

    for _, talentInfo in ipairs(matches) do
        local header = talentInfo.name
        if talentInfo.source then
            header = header .. " - " .. talentInfo.source
        end
        if talentInfo.selected then
            tooltip:AddLine("\n|cffffffff" .. header .. ":|r " .. talentInfo.desc .. "\n", 1.0, 0.82, 0.0, true)
        else
            tooltip:AddLine("\n|cffffffff" .. header .. ":|r " .. talentInfo.desc .. "\n", 0.5, 0.5, 0.5, true)
        end
    end

    tooltip:AddLine(" ")
    tooltip:Show()
end

---------------------------------------------------------------------------
-- Tooltip hook
---------------------------------------------------------------------------

if TooltipDataProcessor then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tooltip, data)
        if not data or not data.id or issecretvalue(data.id) then return end
        if C_SpellBook.IsSpellInSpellBook(data.id) then
            EnhanceTooltip(data.id, tooltip)
        end
    end)

    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Macro, function(tooltip, data)
        if not data or not data.lines or not data.lines[1] then return end
        local tooltipID = data.lines[1].tooltipID
        if not tooltipID or issecretvalue(tooltipID) then return end
        if C_SpellBook.IsSpellInSpellBook(tooltipID) then
            EnhanceTooltip(tooltipID, tooltip)
        end
    end)

    TooltipDataProcessor.AddLinePreCall(TooltipDataProcessor.AllTypes, function(tooltip, lineData)
        if db and db.hideGlyphs and lineData.leftText and not issecretvalue(lineData.leftText) and string.find(lineData.leftText, "Glyph", 1, true) then
            return true
        end
    end)
end

---------------------------------------------------------------------------
-- Settings panel (Options > AddOns)
---------------------------------------------------------------------------

local function CreateSettingsPanel()
    local panel = CreateFrame("Frame")

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Informative Tooltips")

    local desc = panel:CreateFontString(nil, "ARTWORK", "GameFontHighlightSmall")
    desc:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
    desc:SetText("Displays talent information related to an ability in its tooltip.")

    -- Hide glyphs checkbox
    local glyphCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    glyphCheck:SetPoint("TOPLEFT", desc, "BOTTOMLEFT", 0, -16)
    glyphCheck.text:SetText("Hide glyph modifiers in tooltips")
    glyphCheck:SetChecked(db.hideGlyphs == true)
    glyphCheck:SetScript("OnClick", function(self)
        db.hideGlyphs = self:GetChecked()
    end)

    -- Shift modifier checkbox
    local modifierCheck = CreateFrame("CheckButton", nil, panel, "UICheckButtonTemplate")
    modifierCheck:SetPoint("TOPLEFT", glyphCheck, "BOTTOMLEFT", 0, -8)
    modifierCheck.text:SetText("Require Shift key to show talent information")
    modifierCheck:SetChecked(db.modifier == true)
    modifierCheck:SetScript("OnClick", function(self)
        db.modifier = self:GetChecked()
    end)

    settingsCategory = Settings.RegisterCanvasLayoutCategory(panel, "Informative Tooltips")
    Settings.RegisterAddOnCategory(settingsCategory)
end

local function OpenSettings()
    if settingsCategory then
        Settings.OpenToCategory(settingsCategory:GetID())
    end
end

---------------------------------------------------------------------------
-- Event handling
---------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("TRAIT_CONFIG_UPDATED")
eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON_NAME then
        self:UnregisterEvent("ADDON_LOADED")

        InformativeTooltipsDB = InformativeTooltipsDB or {}
        db = InformativeTooltipsDB
        if db.hideGlyphs == nil then db.hideGlyphs = true end

        CreateSettingsPanel()
        C_Timer.After(1, UpdateTalentCache)
    elseif event == "TRAIT_CONFIG_UPDATED" then
        C_Timer.After(1, UpdateTalentCache)
    end
end)

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------

SLASH_INFORMATIVETOOLTIPS1 = "/informativetooltips"
SLASH_INFORMATIVETOOLTIPS2 = "/it"
SlashCmdList["INFORMATIVETOOLTIPS"] = function(msg)
    msg = strtrim(msg):lower()
    if msg == "settings" or msg == "config" or msg == "options" then
        OpenSettings()
    else
        print("|cnNORMAL_FONT_COLOR:Informative Tooltips:|r Commands:")
        print("  /it settings - Open settings panel")
    end
end
