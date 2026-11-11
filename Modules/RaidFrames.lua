local _, S = ...
local M = S:NewModule("RaidFrames")

-- Reliable buffs/debuffs/defensive-cooldown display, plus independent styling and behavior
-- tweaks, on the default CompactPartyFrame/CompactRaidFrame member frames. A first attempt at
-- the aura part of this (Modules\PartyFrames.lua, removed) broke because trusting AddAuraGroup's
-- own candidateFilters alone to decide what shows isn't reliable for party/raid units on this
-- client (duplicated icons, missing borders) - Blizzard's real visibility rule for raid-frame
-- buffs touches protected caches addon code can't call at all. The fix here, confirmed working
-- in the reference addon for this same client: replicate that rule ourselves from live aura data
-- and exclude by spell ID, so a buff is only ever assigned to one display category.

local function DB()
    return S.db.raidFrames
end

-- ============================================================================
-- Capability check
-- ============================================================================

local function Supported()
    return CreateFrame and AuraUtil and AuraUtil.AuraFilters and AuraUtil.CreateFilterString and
        AnchorUtil and AnchorUtil.FlowDirection and EditModeManagerFrame and
        EditModeManagerFrame.GetRaidFrameWidth and EditModeManagerFrame.GetRaidFrameHeight and
        S.modules.Nameplates and S.modules.Nameplates.InitAuraButton ~= nil
end

function M:IsSupported()
    return Supported()
end

-- ============================================================================
-- Member-frame registry
-- ============================================================================
-- CompactPartyFrameMember1-5 are static; CompactRaidFrame1-40 are created/destroyed as the raid's
-- size changes, so they can't be enumerated once at login - CompactUnitFrame_SetUnit fires for
-- any of them the moment it's assigned a unit (new frame or a roster change alike), so hooking it
-- is both the discovery mechanism and the roster-change refresh in one place.

local trackedFrames = {}  -- frame -> true
local frameState = {}     -- frame -> { unit, buffContainer, debuffContainer, defensiveContainer, ... }
local InstallMouseoverHighlight -- forward-declared: defined with the rest of the styling code below, called from M:RefreshFrame above it

local function IsMemberFrameName(name)
    return name ~= nil and (name:find("^CompactPartyFrameMember") ~= nil or name:find("^CompactRaidFrame") ~= nil)
end

local function IsPartyFrame(frame)
    local name = frame:GetName()
    return name ~= nil and name:find("^CompactPartyFrameMember") ~= nil
end

local function TrackFrame(frame)
    trackedFrames[frame] = true
end

M.trackedFrames = trackedFrames -- read by Debug.lua

-- ============================================================================
-- Curated spell lists
-- ============================================================================
-- Starting point ported from the reference addon's own shipped, confirmed-working lists for this
-- client - expected to need occasional updates as new abilities are introduced (see spec
-- Assumptions); not exposed in the options window.

local IMPORTANT_BUFFS = {
    [10060] = true,   -- Power Infusion
    [1044] = true,    -- Blessing of Freedom
    [210256] = true,  -- Blessing of Sanctuary
    [106898] = true,  -- Stampeding Roar (No Form)
    [77764] = true,   -- Stampeding Roar (Cat)
    [77761] = true,   -- Stampeding Roar (Bear)
    [116841] = true,  -- Tiger's Lust
    [53563] = true,   -- Beacon of Light
    [156910] = true,  -- Beacon of Faith
    [200025] = true,  -- Beacon of Virtue
    [1244893] = true, -- Beacon of the Survivor
    [974] = true,     -- Earth Shield
    [383648] = true,  -- Earth Shield
    [57934] = true,   -- Tricks of the Trade
    [1224098] = true, -- Tricks of the Trade
    [59628] = true,   -- Tricks of the Trade
}

local DEFENSIVE_COOLDOWNS = {
    [498] = true,     -- Divine Protection
    [403876] = true,  -- Divine Protection
    [33206] = true,   -- Pain Suppression
    [228050] = true,  -- Guardian of the Forgotten Queen
    [31821] = true,   -- Aura Mastery
    [363534] = true,  -- Rewind
    [370960] = true,  -- Emerald Communion
    [378441] = true,  -- Time Stop
    [325174] = true,  -- Spirit Link Totem
    [409293] = true,  -- Burrow
    [353319] = true,  -- Revival
    [108416] = true,  -- Dark Pact
    [200183] = true,  -- Apotheosis
    [215769] = true,  -- Spirit of the Redeemer
    [421453] = true,  -- Ultimate Penitence
    [374227] = true,  -- Zephyr
    [15286] = true,   -- Vampiric Embrace
    [102558] = true,  -- Incarnation (Guardian)
    [125174] = true,  -- Touch of Karma
    [386208] = true,  -- Defensive Stance
    [97463] = true,   -- Rallying Cry
    [5277] = true,    -- Evasion
    [187827] = true,  -- Metamorphosis
    [145629] = true,  -- Anti-Magic Zone
    [410358] = true,  -- Spellwarden (AMS)
    [49039] = true,   -- Lichborne
    [81256] = true,   -- Dancing Rune Weapon
    [216331] = true,  -- Avenging Crusader
    [389539] = true,  -- Sentinel
    [1261872] = true, -- Heart of the Wild (Bear)
    [5487] = true,    -- Bear Form
    [1966] = true,    -- Feint
    [586] = true,     -- Fade
    [23920] = true,   -- Spell Reflect
}

local EXCLUDED_NOISE_AURAS = {
    [57723] = true,   -- Exhaustion (Heroism)
    [57724] = true,   -- Sated (Bloodlust)
    [80354] = true,   -- Temporal Displacement (Time Warp)
    [95809] = true,   -- Insanity (Hunter pet Ancient Hysteria)
    [264689] = true,  -- Fatigued (Drums of Fury / Primal Rage)
    [390435] = true,  -- Exhaustion (Evoker Fury of the Aspects)
    [308312] = true,  -- Time Trial Practice
    [1254550] = true, -- Arcane Empowerment
    [26013] = true,   -- Deserter
    [71041] = true,   -- Deserter
    [405692] = true,  -- Deserter
}

-- Excluded from the native "big defensive" group too, so a spell curated into DEFENSIVE_COOLDOWNS
-- or IMPORTANT_BUFFS never also slips through via the native BIG_DEFENSIVE filter.
local CURATED_EXCLUDE = {}
for id in pairs(IMPORTANT_BUFFS) do
    CURATED_EXCLUDE[id] = true
end
for id in pairs(DEFENSIVE_COOLDOWNS) do
    CURATED_EXCLUDE[id] = true
end

-- ============================================================================
-- Raid-buff visibility classifier
-- ============================================================================
-- Blizzard's own rule for whether a buff belongs on a raid frame (AuraUtil.ShouldDisplayBuff)
-- reads caches tainted code can't access. Reimplemented here from each unit's own live aura data
-- and kept in a shared, spell-ID-keyed exclude table consulted by every tracked frame's "Buffs"
-- group - exclusion by ID, not overlapping candidateFilters, is what keeps a buff from ever
-- rendering in more than one category.

local raidBuffHidden = { [true] = {}, [false] = {} } -- combat state -> spellId -> true (hidden)
local raidBuffExclude = {}                            -- spellId -> true, fed into the "Buffs" group

local function RebuildRaidBuffExclude()
    wipe(raidBuffExclude)
    for id in pairs(CURATED_EXCLUDE) do
        raidBuffExclude[id] = true
    end
    for id in pairs(raidBuffHidden[UnitAffectingCombat("player") and true or false]) do
        raidBuffExclude[id] = true
    end
end
RebuildRaidBuffExclude()

local function ShouldDisplayRaidBuff(sourceUnit, spellId, canApplyAura)
    local visibilityType = UnitAffectingCombat("player") and Enum.SpellAuraVisibilityType.RaidInCombat or
        Enum.SpellAuraVisibilityType.RaidOutOfCombat
    local hasCustom, alwaysShowMine, showForMySpec = C_Spell.GetVisibilityInfo(spellId, visibilityType)
    local isMine = sourceUnit == "player" or sourceUnit == "pet" or sourceUnit == "vehicle"

    if hasCustom then
        return showForMySpec or (alwaysShowMine and isMine)
    elseif isMine and canApplyAura then
        return not C_Spell.IsSelfBuff(spellId)
    end
    return false
end

-- Returns true when the hidden-spell set actually changed (so callers only re-apply the exclude
-- table to live aura groups when it's worth it).
local function ClassifyRaidBuff(aura)
    if S.IsSecret(aura) then
        return false
    end
    local spellId = aura.spellId
    local sourceUnit = aura.sourceUnit
    if not spellId or S.IsSecret(spellId) or S.IsSecret(sourceUnit) or S.IsSecret(aura.canApplyAura) then
        return false
    end

    local hidden = raidBuffHidden[UnitAffectingCombat("player") and true or false]
    local shown = ShouldDisplayRaidBuff(sourceUnit, spellId, aura.canApplyAura) and true or false
    if shown == (hidden[spellId] == nil) then
        return false
    end
    hidden[spellId] = (not shown) or nil
    return true
end

local function ScanRaidBuffs(unit)
    local ok, auras = pcall(C_UnitAuras.GetUnitAuras, unit, "HELPFUL|PLAYER")
    if not ok or S.IsSecret(auras) or type(auras) ~= "table" then
        return false
    end
    local changed = false
    for _, aura in ipairs(auras) do
        changed = ClassifyRaidBuff(aura) or changed
    end
    return changed
end

local function UpdateRaidBuffExclusions()
    RebuildRaidBuffExclude()
    for frame in pairs(trackedFrames) do
        local state = frameState[frame]
        if state and state.buffContainer and not frame:IsForbidden() then
            state.buffsFilters.excludeSpellIDs = raidBuffExclude
            state.buffContainer:SetAuraGroupCandidateFilters("Buffs", state.buffsFilters)
        end
    end
end

-- ============================================================================
-- Aura icon look (shared with nameplates / target & focus auras)
-- ============================================================================

local function InitAuraButton(auraFrame, size, helpful)
    S.modules.Nameplates.InitAuraButton(auraFrame, size, helpful, {
        typeBorders = true,
        purgeGlow = false,
        showDuration = true,
        durationSize = math.max(6, math.floor(size * 0.4)),
        mouse = true,
    })
end

-- ============================================================================
-- Frame size (percentage-of-height sizing, so Edit Mode resizing is followed live)
-- ============================================================================
-- GetWidth()/GetHeight() on these frames come back protected on this client; the Edit Mode
-- manager's own accessors are the supported path to the same number.

local DEFAULT_FRAME_HEIGHT = 36

local function FrameHeight(frame)
    local systemIndex = IsPartyFrame(frame) and Enum.EditModeUnitFrameSystemIndices.Party or
        Enum.EditModeUnitFrameSystemIndices.Raid
    local ok, height = pcall(EditModeManagerFrame.GetRaidFrameHeight, EditModeManagerFrame, systemIndex,
        DEFAULT_FRAME_HEIGHT)
    if ok and type(height) == "number" and not S.IsSecret(height) and height > 0 then
        return height
    end
    return DEFAULT_FRAME_HEIGHT
end

local function CategorySizes(frame)
    local db = DB()
    local height = FrameHeight(frame)
    local buffSize = math.floor(height * (db.buffSizePercent or 33) / 100 + 0.5)
    local debuffSize = math.floor(height * (db.debuffSizePercent or 33) / 100 + 0.5)
    local bossDebuffSize = math.floor(debuffSize * (db.bossDebuffScale or 1.3) + 0.5)
    local defensiveSize = math.floor(height * (db.defensiveSizePercent or 55) / 100 + 0.5)
    return math.max(buffSize, 1), math.max(debuffSize, 1), math.max(bossDebuffSize, 1), math.max(defensiveSize, 1)
end

-- ============================================================================
-- Aura containers
-- ============================================================================

local RAID_MAX_BUFFS = 6
local RAID_MAX_DEBUFFS = 5
local RAID_MAX_BIG_DEBUFFS = 2
local RAID_MAX_DEFENSIVE = 3
local ICON_GAP = 1

local function RaidFilter(...)
    return AuraUtil.CreateFilterString(...)
end

local function EnsureAuraContainers(frame)
    local state = frameState[frame]
    if state then
        return state
    end

    state = {}
    frameState[frame] = state

    local buffSize, debuffSize, bossDebuffSize, defensiveSize = CategorySizes(frame)
    state.buffBaseSize, state.debuffBaseSize, state.bossDebuffBaseSize, state.defensiveBaseSize =
        buffSize, debuffSize, bossDebuffSize, defensiveSize

    -- 1x1 anchor frames in the frame's two bottom corners, so the "which side" setting can swap
    -- what anchors to which corner without recomputing anchor math every time.
    local buffAnchor = CreateFrame("Frame", nil, frame)
    buffAnchor:SetSize(1, 1)
    state.buffAnchor = buffAnchor
    local debuffAnchor = CreateFrame("Frame", nil, frame)
    debuffAnchor:SetSize(1, 1)
    state.debuffAnchor = debuffAnchor

    -- Buffs (player-sourced only - this is about tracking what YOU'RE providing a member, not
    -- showing every buff from every source, matching the reference addon's own scope).
    local buffContainer = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
    state.buffsFilters = { excludeSpellIDs = raidBuffExclude, isFriendly = true }
    buffContainer:AddAuraGroup("Buffs", RaidFilter("HELPFUL", "PLAYER", "!BIG_DEFENSIVE", "!EXTERNAL_DEFENSIVE"), {
        maxFrameCount = RAID_MAX_BUFFS,
        candidateFilters = state.buffsFilters,
        initializeFrame = function(auraFrame)
            InitAuraButton(auraFrame, buffSize, true)
        end,
        layout = { elementSpacing = ICON_GAP, lineSpacing = ICON_GAP },
    })
    buffContainer:AddAuraGroup("BuffsImportant", RaidFilter("HELPFUL", "PLAYER"), {
        maxFrameCount = RAID_MAX_BUFFS,
        candidateFilters = { includeSpellIDs = IMPORTANT_BUFFS, isFriendly = true },
        initializeFrame = function(auraFrame)
            InitAuraButton(auraFrame, buffSize, true)
        end,
        layout = { elementSpacing = ICON_GAP, lineSpacing = ICON_GAP },
    })
    buffContainer:SetEnabled(false)
    state.buffContainer = buffContainer

    -- Debuffs (every source - a debuff matters regardless of who applied it).
    local debuffContainer = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
    debuffContainer:SetFrameLevel(buffContainer:GetFrameLevel() + 10)
    debuffContainer:AddAuraGroup("DebuffsBig", RaidFilter("HARMFUL"), {
        maxFrameCount = RAID_MAX_BIG_DEBUFFS,
        candidateFilters = { isBossOrRoleAura = true, excludeSpellIDs = EXCLUDED_NOISE_AURAS, isFriendly = true },
        initializeFrame = function(auraFrame)
            InitAuraButton(auraFrame, bossDebuffSize, false)
        end,
        layout = { elementSpacing = ICON_GAP, lineSpacing = ICON_GAP },
    })
    debuffContainer:AddAuraGroup("DebuffsNormal", RaidFilter("HARMFUL"), {
        maxFrameCount = RAID_MAX_DEBUFFS,
        candidateFilters = { isBossOrRoleAura = false, excludeSpellIDs = EXCLUDED_NOISE_AURAS, isFriendly = true },
        initializeFrame = function(auraFrame)
            InitAuraButton(auraFrame, debuffSize, false)
        end,
        layout = { elementSpacing = ICON_GAP, lineSpacing = ICON_GAP },
    })
    debuffContainer:SetEnabled(false)
    state.debuffContainer = debuffContainer

    -- Defensive cooldowns - native big-defensive filter, plus the curated list it misses, plus an
    -- optional fallback to the generic "important" filter.
    local defensiveContainer = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
    defensiveContainer:SetFrameLevel(debuffContainer:GetFrameLevel() + 10)
    defensiveContainer:AddAuraGroup("BigDefensives", RaidFilter("HELPFUL", "BIG_DEFENSIVE"), {
        maxFrameCount = RAID_MAX_DEFENSIVE,
        candidateFilters = { excludeSpellIDs = CURATED_EXCLUDE, isFriendly = true },
        initializeFrame = function(auraFrame)
            InitAuraButton(auraFrame, defensiveSize, true)
        end,
        layout = { elementSpacing = ICON_GAP, lineSpacing = ICON_GAP },
    })
    defensiveContainer:AddAuraGroup("AdditionalDefensives", RaidFilter("HELPFUL"), {
        maxFrameCount = RAID_MAX_DEFENSIVE,
        candidateFilters = { includeSpellIDs = DEFENSIVE_COOLDOWNS, isFriendly = true },
        initializeFrame = function(auraFrame)
            InitAuraButton(auraFrame, defensiveSize, true)
        end,
        layout = { elementSpacing = ICON_GAP, lineSpacing = ICON_GAP },
    })
    defensiveContainer:AddAuraGroup("DefensivesImportant",
        RaidFilter("HELPFUL", "IMPORTANT", "!BIG_DEFENSIVE", "!EXTERNAL_DEFENSIVE"), {
            maxFrameCount = DB().defensiveShowImportant and RAID_MAX_DEFENSIVE or 0,
            candidateFilters = { excludeSpellIDs = CURATED_EXCLUDE, isFriendly = true },
            initializeFrame = function(auraFrame)
                InitAuraButton(auraFrame, defensiveSize, true)
            end,
            layout = { elementSpacing = ICON_GAP, lineSpacing = ICON_GAP },
        })
    defensiveContainer:SetEnabled(false)
    state.defensiveContainer = defensiveContainer

    TrackFrame(frame)
    return state
end

-- Buff/debuff side + defensive position/offset ------------------------------------------------

local function ApplySides(frame, state)
    local db = DB()
    local debuffsRight = db.debuffSide == "RIGHT"
    local debuffAnchor = debuffsRight and state.buffAnchor or state.debuffAnchor
    local buffAnchor = debuffsRight and state.debuffAnchor or state.buffAnchor
    local debuffPoint = debuffsRight and "BOTTOMRIGHT" or "BOTTOMLEFT"
    local buffPoint = debuffsRight and "BOTTOMLEFT" or "BOTTOMRIGHT"
    local debuffGrowth = debuffsRight and AnchorUtil.FlowDirection.Left or AnchorUtil.FlowDirection.Right
    local buffGrowth = debuffsRight and AnchorUtil.FlowDirection.Right or AnchorUtil.FlowDirection.Left

    state.debuffContainer:ClearAllPoints()
    state.debuffContainer:SetPoint(debuffPoint, debuffAnchor, debuffPoint, 0, 0)
    state.debuffContainer:SetFlowLayoutAnchorPoint(debuffPoint)
    state.debuffContainer:SetFlowLayoutGrowthDirection(debuffGrowth, AnchorUtil.FlowDirection.Up)

    state.buffContainer:ClearAllPoints()
    state.buffContainer:SetPoint(buffPoint, buffAnchor, buffPoint, 0, 0)
    state.buffContainer:SetFlowLayoutAnchorPoint(buffPoint)
    state.buffContainer:SetFlowLayoutGrowthDirection(buffGrowth, AnchorUtil.FlowDirection.Up)

    local point = (db.defensivePosition == "LEFT" or db.defensivePosition == "RIGHT") and db.defensivePosition or
        "CENTER"
    state.defensiveContainer:ClearAllPoints()
    if point == "RIGHT" then
        state.defensiveContainer:SetFlowLayoutAnchorPoint("RIGHT")
        state.defensiveContainer:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Left, AnchorUtil.FlowDirection.Down)
        state.defensiveContainer:SetPoint("RIGHT", frame, "RIGHT", db.defensiveOffsetX or 0, db.defensiveOffsetY or 0)
    elseif point == "LEFT" then
        state.defensiveContainer:SetFlowLayoutAnchorPoint("LEFT")
        state.defensiveContainer:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
        state.defensiveContainer:SetPoint("LEFT", frame, "LEFT", db.defensiveOffsetX or 0, db.defensiveOffsetY or 0)
    else
        state.defensiveContainer:SetFlowLayoutAnchorPoint("LEFT")
        state.defensiveContainer:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
        state.defensiveContainer:SetPoint("CENTER", frame, "CENTER", db.defensiveOffsetX or 0, db.defensiveOffsetY or 0)
    end
end

local function ApplyAnchors(frame, state)
    local powerBar = frame.powerBar
    local hasPower = powerBar and powerBar:IsShown()
    local refFrame = hasPower and powerBar or frame
    local rightRef = hasPower and "TOPRIGHT" or "BOTTOMRIGHT"
    local leftRef = hasPower and "TOPLEFT" or "BOTTOMLEFT"
    local yOffset = hasPower and 1 or 2

    state.buffAnchor:ClearAllPoints()
    state.buffAnchor:SetPoint("BOTTOMRIGHT", refFrame, rightRef, -2, yOffset)
    state.debuffAnchor:ClearAllPoints()
    state.debuffAnchor:SetPoint("BOTTOMLEFT", refFrame, leftRef, 2, yOffset)
end

-- Live rescale (never rebuilds the icons - just scales the whole container against the size it
-- was created at).
local function ApplySizing(frame, state)
    local buffSize, debuffSize, bossDebuffSize, defensiveSize = CategorySizes(frame)
    local buffMax = math.max(buffSize, 1)
    state.buffContainer:SetFlowLayoutMaximumLineSize(3 * (buffMax + ICON_GAP))
    if state.buffBaseSize > 0 then
        state.buffContainer:SetScale(buffMax / state.buffBaseSize)
    end

    local debuffLine = RAID_MAX_BIG_DEBUFFS * (bossDebuffSize + ICON_GAP) + RAID_MAX_DEBUFFS * (debuffSize + ICON_GAP)
    state.debuffContainer:SetFlowLayoutMaximumLineSize(debuffLine)
    if state.debuffBaseSize > 0 then
        state.debuffContainer:SetScale(debuffSize / state.debuffBaseSize)
    end

    state.defensiveContainer:SetFlowLayoutMaximumLineSize(RAID_MAX_DEFENSIVE * (defensiveSize + ICON_GAP))
    if state.defensiveBaseSize > 0 then
        state.defensiveContainer:SetScale(defensiveSize / state.defensiveBaseSize)
    end
end

-- Unreachable / not-assistable handling ----------------------------------------------------------

local function HideContainers(state, ...)
    for _, container in ipairs({ ... }) do
        if container.mUIUnit ~= nil then
            container:SetEnabled(false)
            container.mUIUnit = nil
            container:Hide()
        end
    end
end

local function ShowContainer(container, unit)
    if container.mUIUnit ~= unit then
        container:SetUnit(unit)
        container:SetEnabled(true)
        container.mUIUnit = unit
        container:Show()
    end
    container:UpdateAllAuras()
end

local function RefreshAuras(frame)
    local state = frameState[frame]
    if not state then
        return
    end

    local unit = frame.displayedUnit or frame.unit
    if not unit or unit:match("target") then
        HideContainers(state, state.buffContainer, state.debuffContainer, state.defensiveContainer)
        return
    end

    local unreachable = (UnitPhaseReason and UnitPhaseReason(unit) ~= nil) or
        (UnitIsVisible and not UnitIsVisible(unit))
    if unreachable then
        HideContainers(state, state.buffContainer, state.debuffContainer, state.defensiveContainer)
        return
    end

    if ScanRaidBuffs(unit) then
        UpdateRaidBuffExclusions()
    end

    ApplySides(frame, state)
    ApplyAnchors(frame, state)

    local notAssistable = UnitCanAssist and not UnitCanAssist("player", unit)
    if notAssistable then
        HideContainers(state, state.defensiveContainer)
    else
        ShowContainer(state.defensiveContainer, unit)
    end

    ShowContainer(state.buffContainer, unit)
    ShowContainer(state.debuffContainer, unit)
end

local function TeardownFrame(frame)
    local state = frameState[frame]
    if not state then
        return
    end
    HideContainers(state, state.buffContainer, state.debuffContainer, state.defensiveContainer)
end

function M:RefreshFrame(frame)
    if not frame or frame:IsForbidden() then
        return
    end
    InstallMouseoverHighlight(frame)
    if not DB().enabled then
        TeardownFrame(frame)
        return
    end
    local state = EnsureAuraContainers(frame)
    local db = DB()
    state.defensiveContainer:SetAuraGroupMaxFrameCount("DefensivesImportant",
        db.defensiveShowImportant and RAID_MAX_DEFENSIVE or 0)
    ApplySizing(frame, state)
    RefreshAuras(frame)
end

-- ============================================================================
-- Frame registry hook (discovery + roster-change rebinding)
-- ============================================================================

local setUnitHooked = false

local function OnSetUnit(frame)
    if S.IsSecret(frame) or frame:IsForbidden() then
        return
    end
    local name = frame.GetName and frame:GetName()
    if not IsMemberFrameName(name) then
        return
    end
    TrackFrame(frame)
    M:RefreshFrame(frame)
end

local function InstallSetUnitHook()
    if setUnitHooked or type(CompactUnitFrame_SetUnit) ~= "function" then
        return
    end
    setUnitHooked = true
    hooksecurefunc("CompactUnitFrame_SetUnit", OnSetUnit)
end

-- Not every state change that matters fires a convenient event (phase, range, combat-dependent
-- raid-buff visibility) - a low-frequency ticker covers the rest, same as the reference addon.
local refreshTicker

local function TickAllFrames()
    for frame in pairs(trackedFrames) do
        if not frame:IsForbidden() then
            M:RefreshFrame(frame)
        end
    end
end

-- ============================================================================
-- Frame styling (health text, names, role icon, mouseover highlight)
-- ============================================================================

-- Same proven order as Modules\UnitFrames.lua's own ClassColor. UnitClassBase, not UnitClass, and
-- no issecretvalue gate on its result before using it - confirmed via BetterBlizzFrames' own
-- forever-build class-color helper that C_ClassColor.GetClassColor tolerates a secret class token
-- and still hands back a usable color table; a plain Lua "not class"/"IsSecret(class)" branch on
-- it is what caused a target-of-target coloring bug in UnitFrames.lua, fixed the same way here.
local function ClassColorFor(unit)
    local exists = UnitExists(unit)
    if S.IsSecret(exists) or not exists then
        return nil
    end
    local isPlayer = UnitIsPlayer(unit)
    if S.IsSecret(isPlayer) or not isPlayer then
        return nil
    end
    local class = UnitClassBase(unit)
    if class == nil then
        return nil
    end
    return (C_ClassColor and C_ClassColor.GetClassColor(class)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
end

local function ApplyHealthText(frame)
    local unit = frame.displayedUnit or frame.unit
    local statusText = frame.statusText
    if not unit or not statusText then
        return
    end
    local db = DB()
    if db.healthTextMode == "CLASS" then
        local color = ClassColorFor(unit)
        if color then
            statusText:SetTextColor(color.r, color.g, color.b)
        end
    elseif db.healthTextMode == "CUSTOM" and db.healthTextCustomColor then
        local c = db.healthTextCustomColor
        statusText:SetTextColor(c.r, c.g, c.b)
    end
end

local function ApplyName(frame)
    local unit = frame.displayedUnit or frame.unit
    local name = frame.name
    if not unit or not name then
        return
    end
    local db = DB()
    if db.nameHidden then
        name:SetAlpha(0)
        return
    end
    name:SetAlpha(1)

    if db.nameClassColor then
        local color = ClassColorFor(unit)
        if color then
            name:SetTextColor(color.r, color.g, color.b)
        end
    end

    if db.nameCentered and IsPartyFrame(frame) then
        name:ClearAllPoints()
        name:SetPoint("CENTER", frame, "CENTER", 0, 0)
    end
end

local function ApplyRoleIcon(frame)
    local icon = frame.roleIcon
    if not icon then
        return
    end
    icon:SetAlpha(DB().roleIconHidden and 0 or 1)
end

function M:ApplyStyling(frame)
    if not frame or frame:IsForbidden() then
        return
    end
    pcall(ApplyHealthText, frame)
    pcall(ApplyName, frame)
    pcall(ApplyRoleIcon, frame)
end

local stylingHooked = false

local function InstallStylingHooks()
    if stylingHooked then
        return
    end
    stylingHooked = true
    if type(CompactUnitFrame_UpdateStatusText) == "function" then
        hooksecurefunc("CompactUnitFrame_UpdateStatusText", function(frame)
            M:ApplyStyling(frame)
        end)
    end
    if type(CompactUnitFrame_UpdateName) == "function" then
        hooksecurefunc("CompactUnitFrame_UpdateName", function(frame)
            M:ApplyStyling(frame)
        end)
    end
    if type(CompactUnitFrame_UpdateRoleIcon) == "function" then
        hooksecurefunc("CompactUnitFrame_UpdateRoleIcon", function(frame)
            M:ApplyStyling(frame)
        end)
    end
end

-- Mouseover highlight ------------------------------------------------------------------------------

local MOUSEOVER_ALPHA = 0.3
local mouseoverHooked = {} -- frame -> true

function InstallMouseoverHighlight(frame)
    if mouseoverHooked[frame] then
        return
    end
    mouseoverHooked[frame] = true

    local highlight = frame:CreateTexture(nil, "OVERLAY")
    highlight:SetAllPoints(frame)
    highlight:SetColorTexture(1, 1, 1, MOUSEOVER_ALPHA)
    highlight:Hide()
    frame.smuveMouseoverHighlight = highlight

    frame:HookScript("OnEnter", function(self)
        if DB().mouseoverHighlight then
            self.smuveMouseoverHighlight:Show()
        end
    end)
    frame:HookScript("OnLeave", function(self)
        self.smuveMouseoverHighlight:Hide()
    end)
end

-- ============================================================================
-- Frame behavior: always-show-while-solo, mouse button 4/5 forwarding
-- ============================================================================

local soloVisibilityHooked = false
local soloVisibilityPending = false

local function ApplySoloVisibility()
    if InCombatLockdown() then
        soloVisibilityPending = true
        return
    end
    soloVisibilityPending = false
    if not CompactPartyFrame then
        return
    end
    if DB().soloVisible and not IsInGroup() then
        CompactPartyFrame:Show()
    elseif not IsInGroup() and not DB().soloVisible then
        if CompactPartyFrame.UpdateVisibility then
            CompactPartyFrame:UpdateVisibility()
        end
    end
    if CompactPartyFrame.UpdatePaddingAndLayout then
        pcall(CompactPartyFrame.UpdatePaddingAndLayout, CompactPartyFrame)
    end
end

local function InstallSoloVisibilityHook()
    if soloVisibilityHooked or not CompactPartyFrame or not CompactPartyFrame.UpdateVisibility then
        return
    end
    soloVisibilityHooked = true
    hooksecurefunc(CompactPartyFrame, "UpdateVisibility", function()
        if DB().soloVisible and not IsInGroup() and not InCombatLockdown() then
            CompactPartyFrame:Show()
        end
    end)
end

-- Blizzard's secure compact frames absorb BUTTON4/5 clicks instead of forwarding them, so a
-- mouseover macro/multibar bound to those buttons never fires while hovering one. Fixed by
-- resolving the current keybind to a concrete click target and mirroring it onto the frame's own
-- secure click attributes - only the base (no-modifier) binding is handled; a full
-- modifier-combination matrix was judged not worth the added complexity for this feature.
--
-- GetBindingAction returns a binding COMMAND name (e.g. "ACTIONBUTTON3"), which is not the same
-- string as the button frame's own global name - only the common bar families are mapped here.
local BINDING_FRAME_PREFIXES = {
    ACTIONBUTTON = "ActionButton",
    MULTIACTIONBAR1BUTTON = "MultiBarBottomLeftButton",
    MULTIACTIONBAR2BUTTON = "MultiBarBottomRightButton",
    MULTIACTIONBAR3BUTTON = "MultiBarRightButton",
    MULTIACTIONBAR4BUTTON = "MultiBarLeftButton",
}

local function ResolveButtonTarget(binding)
    local action = GetBindingAction(binding)
    if not action or action == "" then
        return nil
    end
    if action:match("^CLICK ") then
        return action:match("^CLICK ([^:]+)")
    end
    for prefix, frameBase in pairs(BINDING_FRAME_PREFIXES) do
        local index = action:match("^" .. prefix .. "(%d+)$")
        if index then
            local frameName = frameBase .. index
            if _G[frameName] then
                return frameName
            end
        end
    end
    return nil
end

local mouseButtonForwardingApplied = {} -- frame -> true

local function ApplyMouseButtonForwarding(frame)
    if InCombatLockdown() then
        return false
    end
    local wantForwarding = DB().mouseButtonForwarding
    if not wantForwarding then
        if mouseButtonForwardingApplied[frame] then
            frame:SetAttribute("type4", nil)
            frame:SetAttribute("clickbutton4", nil)
            frame:SetAttribute("type5", nil)
            frame:SetAttribute("clickbutton5", nil)
            mouseButtonForwardingApplied[frame] = nil
        end
        return true
    end

    local target4, target5 = ResolveButtonTarget("BUTTON4"), ResolveButtonTarget("BUTTON5")
    frame:SetAttribute("type4", target4 and "click" or nil)
    frame:SetAttribute("clickbutton4", target4)
    frame:SetAttribute("type5", target5 and "click" or nil)
    frame:SetAttribute("clickbutton5", target5)
    -- RegisterForClicks replaces the frame's whole click set, so the compact frame's own
    -- left-click-to-target/right-click-menu registration is named explicitly here rather than
    -- risking a blanket "AnyUp"/"AnyDown" interfering with behavior this feature isn't meant to
    -- touch at all.
    if frame.RegisterForClicks and not mouseButtonForwardingApplied[frame] then
        frame:RegisterForClicks("LeftButtonUp", "RightButtonUp", "Button4Down", "Button5Down")
    end
    mouseButtonForwardingApplied[frame] = true
    return true
end

local mouseButtonForwardingPending = false

local function ApplyMouseButtonForwardingToAll()
    local allOk = true
    for frame in pairs(trackedFrames) do
        if not frame:IsForbidden() and not ApplyMouseButtonForwarding(frame) then
            allOk = false
        end
    end
    mouseButtonForwardingPending = not allOk
end

-- ============================================================================
-- Debug readback (consumed by Debug.lua's /smuve dump)
-- ============================================================================

M.debugState = {}

local function RefreshDebugState()
    local lines = {}
    local count = 0
    for frame in pairs(trackedFrames) do
        count = count + 1
        local state = frameState[frame]
        local unit = frame.unit or (state and state.buffContainer and state.buffContainer.mUIUnit)
        table.insert(lines, (frame.GetName and frame:GetName() or "?") .. " unit=" .. tostring(unit))
    end
    M.debugState.trackedCount = count
    M.debugState.frames = lines
    local excludeCount = 0
    for _ in pairs(raidBuffExclude) do
        excludeCount = excludeCount + 1
    end
    M.debugState.raidBuffExcludeCount = excludeCount
end
M.RefreshDebugState = RefreshDebugState

-- ============================================================================
-- Module lifecycle
-- ============================================================================

local function OnUnitAura(_, unit)
    if S.IsSecret(unit) or not (unit == "player" or unit:find("^party") or unit:find("^raid")) then
        return
    end
    if ScanRaidBuffs(unit) then
        UpdateRaidBuffExclusions()
    end
end

local function OnCombatStateChanged()
    for frame in pairs(trackedFrames) do
        local unit = not frame:IsForbidden() and (frame.displayedUnit or frame.unit)
        if unit then
            ScanRaidBuffs(unit)
        end
    end
    UpdateRaidBuffExclusions()
    if soloVisibilityPending then
        ApplySoloVisibility()
    end
    if mouseButtonForwardingPending then
        ApplyMouseButtonForwardingToAll()
    end
end

function M:Init()
    InstallSetUnitHook()
    InstallStylingHooks()
    InstallSoloVisibilityHook()

    S:On("UNIT_AURA", OnUnitAura)
    S:On("PLAYER_REGEN_DISABLED", OnCombatStateChanged)
    S:On("PLAYER_REGEN_ENABLED", OnCombatStateChanged)

    refreshTicker = refreshTicker or C_Timer.NewTicker(1, TickAllFrames)

    for frame in pairs(trackedFrames) do
        M:RefreshFrame(frame)
        M:ApplyStyling(frame)
    end
    ApplySoloVisibility()
    ApplyMouseButtonForwardingToAll()
end

function M:Refresh()
    for frame in pairs(trackedFrames) do
        M:RefreshFrame(frame)
        M:ApplyStyling(frame)
    end
    ApplySoloVisibility()
    ApplyMouseButtonForwardingToAll()
    RefreshDebugState()
end
