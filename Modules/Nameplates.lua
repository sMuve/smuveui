local _, S = ...
local M = S:NewModule("Nameplates")

-- Simplified enemy nameplates:
--   * crowd control debuffs to the right of the health bar,
--   * important enemy buffs (big / external defensives, important auras) to its left,
--   * your debuffs in a row above the bar (high enough to keep the name readable),
--   * the remaining buffs in a row above the debuffs,
--   * the name above the health bar instead of inside it,
--   * buffs you can purge get a glowing border.
--
-- Enemy auras are protected values in combat, so no addon code can read them. The client's own
-- aura containers (CreateFrame("AuraContainer")) pick, sort and show the auras from filter strings,
-- and draw icon, timer, stacks and the purge marking in buttons that are styled once, when the
-- client creates them. Everything here goes through those containers.

local AF = AuraUtil and AuraUtil.AuraFilters
local CreateFilterString = AuraUtil and AuraUtil.CreateFilterString
local FlowDirection = AnchorUtil and AnchorUtil.FlowDirection

-- A short, explicit inclusion for buffs Blizzard's own category filter string misses entirely -
-- same list, same reasoning as Modules\BigDebuffs.lua and Modules\PartyFrames.lua (confirmed live
-- that none of these show up as an enemy nameplate's important buff either, e.g. Blessing of
-- Freedom in a duel). Needs its OWN aura group (see "Extra" below), not candidateFilters bolted
-- onto "Important": a group's filterString and its candidateFilters are ANDed together, not
-- alternatives, and "Important"'s filter string requires AF.Important membership, which these
-- spells don't have.
local EXTRA_IMPORTANT_SPELLS = {
    [1044] = true,  -- Blessing of Freedom
    [5599] = true,  -- Blessing of Protection
    [5573] = true,  -- Divine Protection
    [20600] = true, -- Perception
    [20216] = true, -- Divine Favor
    [1277462] = true, -- Contingency Plan
    [14751] = true, -- Inner Focus
    [6346] = true, -- Fear Ward
}

local PURGE_ATLAS = "newplayertutorial-drag-slotblue"
-- Space between icons, and the size of the side icons (crowd control, important buffs): the debuff
-- icon size times their scale.
local function Spacing()
    return S.db.nameplates.spacing
end

-- Width of a line that holds exactly "count" icons.
local function LineSize(count, size)
    return count * size + (count - 1) * S.db.nameplates.spacing
end

local function SideSize(scale)
    return math.floor(S.db.nameplates.debuffSize * (scale or 1) + 0.5)
end
local ROW_GAP = 3      -- between the debuff rows and the buff rows above them
local SIDE_GAP = 4     -- between the health bar (or level badge) and the side icons
local HIDE_TIMER_FROM = 61

-- Offensive dispels of this client: buffs of these types can be removed by you.
local PURGE_SPELLS = {
    { types = { "Magic" }, spells = { 370, 8012 } },                        -- Purge (Shaman)
    { types = { "Magic" }, spells = { 527, 988 } },                         -- Dispel Magic (Priest)
    { types = { "Magic" }, spells = { 30449 } },                            -- Spellsteal (Mage)
    { types = { "Magic" }, spells = { 19505, 19731, 19734, 19736 }, pet = true }, -- Devour Magic (Felhunter)
    { types = { "Magic", "Enrage" }, spells = { 19801 } },                  -- Tranquilizing Shot (Hunter)
    { types = { "Enrage" }, spells = { 2908, 8955, 9901 } },                -- Soothe Animal (Druid)
}

local PlaceRows          -- defined with the layout below; the test mode uses it too
local sets = {}          -- unit token -> { frame, containers, preview }
local hookedNames = setmetatable({}, { __mode = "k" }) -- plate name font strings already hooked
local enemyFrames = setmetatable({}, { __mode = "k" }) -- plate unit frame -> true while styled as enemy
local generation = 0     -- raised when the settings change; older sets are rebuilt
local purgeAssets = {}   -- dispel type -> { asset = atlas }, for the types you can purge
local durationFormatter

local function DB()
    return S.db.nameplates
end

local function Supported()
    return AF and CreateFilterString and FlowDirection and AuraContainerSortMethod ~= nil
end

-- Helpers ------------------------------------------------------------------------------------------

local function Accessible(region)
    if not region then
        return false
    end
    local forbidden = region:IsForbidden()
    if S.IsSecret(forbidden) or forbidden then
        return false
    end
    if region.CanBeAccessedInContext then
        local ok, allowed = pcall(region.CanBeAccessedInContext, region)
        if not ok or S.IsSecret(allowed) or not allowed then
            return false
        end
    end
    return true
end

local function IsEnemy(unit)
    local canAttack = UnitCanAttack("player", unit)
    if S.IsSecret(canAttack) then
        return false
    end
    return canAttack and true or false
end

local function KnowsSpell(spellID, isPet)
    if IsSpellKnownOrOverridesKnown then
        return IsSpellKnownOrOverridesKnown(spellID, isPet)
    end
    return IsSpellKnown and IsSpellKnown(spellID, isPet)
end

function M:RefreshPurgeTypes()
    wipe(purgeAssets)
    for _, entry in ipairs(PURGE_SPELLS) do
        for _, spellID in ipairs(entry.spells) do
            if KnowsSpell(spellID, entry.pet) then
                for _, dispelType in ipairs(entry.types) do
                    purgeAssets[dispelType] = { asset = PURGE_ATLAS }
                end
                break
            end
        end
    end
end

-- A stable, sorted signature of purgeAssets' keys, to detect whether RefreshPurgeTypes actually
-- changed anything (pairs() order isn't guaranteed, so the keys are sorted before joining).
local function PurgeSignature()
    local keys = {}
    for dispelType in pairs(purgeAssets) do
        table.insert(keys, dispelType)
    end
    table.sort(keys)
    return table.concat(keys, ",")
end

local function GetDurationFormatter()
    if durationFormatter or not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then
        return durationFormatter
    end
    durationFormatter = C_StringUtil.CreateNumericRuleFormatter()
    durationFormatter:SetBreakpoints({
        { threshold = 0, format = "%d", step = 1, rounding = Enum.NumericRuleFormatRounding.Up },
        { threshold = HIDE_TIMER_FROM, format = " " }, -- long auras show no timer
    })
    return durationFormatter
end

-- Like the player's own auras: "45s", "8m", "2h" with a white number and the unit in the
-- client's yellow, rounded up as the client does. The client fills the text itself (the time can
-- be a protected value), so the format is set up through its number formatter.
local UNIT_COLOR = "|cffffd100"
local unitFormatter

local function GetUnitDurationFormatter()
    if unitFormatter or not (C_StringUtil and C_StringUtil.CreateNumericRuleFormatter) then
        return unitFormatter
    end
    local up = Enum.NumericRuleFormatRounding.Up
    local formatter = C_StringUtil.CreateNumericRuleFormatter()
    local ok = pcall(formatter.SetBreakpoints, formatter, {
        { threshold = 0, format = "%d" .. UNIT_COLOR .. "s|r", step = 1, rounding = up },
        { threshold = 60, format = "%d" .. UNIT_COLOR .. "m|r", step = 1, rounding = up, components = { { div = 60 } } },
        { threshold = 3600, format = "%d" .. UNIT_COLOR .. "h|r", step = 1, rounding = up, components = { { div = 3600 } } },
        { threshold = 86400, format = "%d" .. UNIT_COLOR .. "d|r", step = 1, rounding = up, components = { { div = 86400 } } },
    })
    unitFormatter = ok and formatter or nil
    return unitFormatter
end

-- Shared with Modules\BigDebuffs.lua, for a duration text in the same "8m" (white number,
-- yellow unit) format as the player's own auras.
M.GetUnitDurationFormatter = GetUnitDurationFormatter

-- Aura buttons -------------------------------------------------------------------------------------

-- Returns the four edge textures. thickness is in screen pixels.
local function AddBlackBorder(host, anchor, thickness)
    thickness = thickness or 1
    local edges = {}
    for _, side in ipairs({ "TOP", "BOTTOM", "LEFT", "RIGHT" }) do
        local edge = host:CreateTexture(nil, "OVERLAY", nil, 4)
        edge:SetColorTexture(1, 1, 1, 1)
        edge:SetVertexColor(0, 0, 0, 1)
        if side == "TOP" or side == "BOTTOM" then
            edge:SetPoint(side .. "LEFT", anchor, side .. "LEFT", 0, 0)
            edge:SetPoint(side .. "RIGHT", anchor, side .. "RIGHT", 0, 0)
            PixelUtil.SetHeight(edge, thickness)
        else
            edge:SetPoint("TOP" .. side, anchor, "TOP" .. side, 0, 0)
            edge:SetPoint("BOTTOM" .. side, anchor, "BOTTOM" .. side, 0, 0)
            PixelUtil.SetWidth(edge, thickness)
        end
        table.insert(edges, edge)
    end
    return edges
end

-- Debuff border colors by dispel type (physical debuffs: "None").
-- Debuffs without a type ("None", physical) get a red border.
local BORDER_SIZE = 2 -- pixels, like the player's own auras

-- Shared with Modules\Auras.lua, for the weapon-imbue cells it draws itself (see there) - the
-- same black border as every other aura icon, on a plain frame rather than a client aura button.
M.AddBlackBorder = AddBlackBorder
M.BORDER_SIZE = BORDER_SIZE

local DISPEL_TYPES = { "None", "Magic", "Curse", "Disease", "Poison", "Bleed", "Enrage" }
local TYPE_COLORS = {
    None = { 0.80, 0.00, 0.00 },
    Magic = { 0.20, 0.60, 1.00 },
    Curse = { 0.60, 0.00, 1.00 },
    Disease = { 0.60, 0.40, 0.00 },
    Poison = { 0.00, 0.60, 0.00 },
    Bleed = { 0.80, 0.00, 0.00 },
}

local typeColorMap
local function TypeColorMap()
    if not typeColorMap and CreateColor then
        typeColorMap = {}
        for dispelType, color in pairs(TYPE_COLORS) do
            typeColorMap[dispelType] = CreateColor(color[1], color[2], color[3], 1)
        end
    end
    return typeColorMap
end

-- Buff borders are black; on buffs you can purge the glow replaces them. The client decides by
-- the buff's dispel type itself, so this works with protected values too.
local function HideEdgesWhenPurgeable(button, edges)
    if not CreateColor or not Enum.CustomAuraButtonDispelTypeTextureStyle then
        return
    end
    local colors = {}
    for _, dispelType in ipairs(DISPEL_TYPES) do
        colors[dispelType] = CreateColor(0, 0, 0, purgeAssets[dispelType] and 0 or 1)
    end
    for _, edge in ipairs(edges) do
        button:AddDispelTypeTexture(edge, {
            style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
            showWhenHarmful = false,
            showWhenHelpful = true,
            showWithoutDispelType = true,
            customDispelColorMap = colors,
        })
    end
end

-- The client colors the edges by the debuff's type itself (the type can be a protected value).
local function ColorEdgesByType(button, edges)
    local colors = TypeColorMap()
    if not colors or not Enum.CustomAuraButtonDispelTypeTextureStyle then
        return
    end
    for _, edge in ipairs(edges) do
        button:AddDispelTypeTexture(edge, {
            style = Enum.CustomAuraButtonDispelTypeTextureStyle.PreserveAsset,
            showWhenHarmful = true,
            showWhenHelpful = false,
            showWithoutDispelType = true,
            customDispelColorMap = colors,
        })
    end
end

-- A glowing frame around the icon; it pulses softly.
local function CreatePurgeGlow(host, button, size)
    local glow = host:CreateTexture(nil, "OVERLAY", nil, 7)
    glow:SetAtlas(PURGE_ATLAS)
    glow:SetPoint("TOPLEFT", button, "TOPLEFT", -size * 0.47, size * 0.46)
    glow:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", size * 0.47, -size * 0.46)
    local pulse = glow:CreateAnimationGroup()
    pulse:SetLooping("BOUNCE")
    local fade = pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.45)
    fade:SetDuration(0.7)
    pulse:Play()
    return glow
end

-- Called by the client for every button a container creates; the look is fixed from here on.
-- style (optional, for other aura displays): typeBorders, purgeGlow, showDuration, durationSize,
-- mouse (tooltips), playerLook (texts placed and formatted like the player's own auras).
-- Without it the nameplate settings apply.
local function InitButton(button, size, helpful, style)
    style = style or {
        typeBorders = true, -- debuff borders in their dispel type's color, always on
        purgeGlow = DB().purgeGlow,
        showDuration = true,
        durationSize = math.max(8, math.floor(size * 0.45)),
    }
    button:SetSize(size, size)
    if button.SetFlattensRenderLayers then
        button:SetFlattensRenderLayers(true)
    end

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    button:SetIcon(icon)

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(button)
    cooldown:SetReverse(true)
    cooldown:SetDrawBling(false)
    cooldown:SetHideCountdownNumbers(true)
    button:SetDurationCooldown(cooldown)

    local overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints(button)
    overlay:SetFrameLevel(cooldown:GetFrameLevel() + 1)
    -- Every icon has a black border; debuffs take their type's color, purgeable buffs the glow.
    local edges = AddBlackBorder(overlay, button, BORDER_SIZE)
    local purgeGlow = helpful and style.purgeGlow and next(purgeAssets) ~= nil
    if not helpful and style.typeBorders then
        ColorEdgesByType(button, edges)
    elseif purgeGlow then
        HideEdgesWhenPurgeable(button, edges)
    end

    -- playerLook: stacks in the top right and the duration at the bottom, both inside the icon in
    -- the duration font, like the player's own auras.
    local count
    if style.playerLook then
        count = overlay:CreateFontString(nil, "OVERLAY")
        count:SetFont(S:GetFont(), style.durationSize, "OUTLINE")
        count:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
    else
        count = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormalSmall")
        count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -1)
    end
    count:SetTextColor(1, 1, 1)
    button:SetApplicationCount(count)

    if style.showDuration then
        local timer = overlay:CreateFontString(nil, "OVERLAY")
        timer:SetFont(S:GetFont(), style.durationSize, "OUTLINE")
        timer:SetTextColor(1, 1, 1)
        local formatter
        if style.playerLook then
            timer:SetPoint("BOTTOM", button, "BOTTOM", 1, 1)
            formatter = GetUnitDurationFormatter()
        else
            timer:SetPoint("CENTER", button, "CENTER", 0, 0)
            formatter = GetDurationFormatter()
        end
        button:SetDurationText(timer, formatter and { textFormatter = formatter } or {})
    end

    if purgeGlow and Enum.CustomAuraButtonDispelTypeTextureStyle then
        local glow = CreatePurgeGlow(overlay, button, size)
        button:AddDispelTypeTexture(glow, {
            style = Enum.CustomAuraButtonDispelTypeTextureStyle.CustomAsset,
            showWhenHarmful = false,
            showWhenHelpful = true,
            showWithoutDispelType = false,
            customDispelAssetMap = purgeAssets,
        })
    end

    if button.SetCancelAuraButtons then
        button:SetCancelAuraButtons(nil)
    end
    if style.mouse then
        -- Tooltips on hover, like the client's own aura icons.
        if button.SetTooltipAnchorPoint then
            button:SetTooltipAnchorPoint("ANCHOR_BOTTOMRIGHT", 0, 0)
        end
        return
    end
    -- No tooltips: the icons must not catch the clicks meant for the nameplate.
    if button.SetHideTooltipInCombat then
        button:SetHideTooltipInCombat(true)
    end
    button:EnableMouse(false)
end

-- Shared with the target / focus auras (Modules\UnitAuras.lua).
M.InitAuraButton = InitButton

-- Containers ---------------------------------------------------------------------------------------

-- groups: list of { key, filter, max, candidateFilters }
local function CreateContainer(groups, size, helpful, flowPoint, horizontal, vertical, lineSize)
    local container = CreateFrame("AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    container:SetEnabled(false)
    container:Hide()
    if container.SetFlattensRenderLayers then
        container:SetFlattensRenderLayers(true)
    end
    container:SetFlowLayoutAnchorPoint(flowPoint)
    container:SetFlowLayoutGrowthDirection(horizontal, vertical)
    if lineSize then
        container:SetFlowLayoutMaximumLineSize(lineSize)
    end
    for index, group in ipairs(groups) do
        container:AddAuraGroup(group.key, group.filter, {
            maxFrameCount = group.max,
            sortMethod = AuraContainerSortMethod.Default,
            sortDirection = AuraContainerSortDirection.Normal,
            candidateFilters = group.candidateFilters,
            initializeFrame = function(button)
                InitButton(button, size, helpful)
            end,
            layout = {
                elementSpacing = Spacing(),
                lineSpacing = Spacing(),
                elementWidth = size,
                elementHeight = size,
                layoutIndex = index,
            },
        })
    end
    return container
end

local function BuildContainers()
    local db = DB()
    local mine = db.onlyMyDebuffs and AF.Player or nil
    local function Filter(...)
        local parts = {}
        for i = 1, select("#", ...) do
            local part = select(i, ...)
            if part then
                table.insert(parts, part)
            end
        end
        return CreateFilterString(unpack(parts))
    end
    local notCC = "!" .. AF.CrowdControl
    local notBig, notExternal, notImportant = "!" .. AF.BigDefensive, "!" .. AF.ExternalDefensive, "!" .. AF.Important

    local containers = {}
    -- Crowd control: right of the bar, in one line growing right.
    local ccSize = SideSize(db.ccScale)
    containers.cc = CreateContainer({
        { key = "CC", filter = Filter(AF.Harmful, AF.IncludeNameplateOnly, AF.CrowdControl), max = db.ccMax },
    }, ccSize, false, "TOPLEFT", FlowDirection.Right, FlowDirection.Down, LineSize(db.ccMax, ccSize))
    -- Important buffs: left of the bar, in one line growing left; big defensives first, then
    -- external defensives, then other important buffs.
    local importantSize = SideSize(db.importantScale)
    containers.important = CreateContainer({
        { key = "DefBig", filter = Filter(AF.Helpful, AF.IncludeNameplateOnly, AF.BigDefensive), max = db.importantMax },
        { key = "DefExt", filter = Filter(AF.Helpful, AF.IncludeNameplateOnly, notBig, AF.ExternalDefensive), max = db.importantMax },
        { key = "Important", filter = Filter(AF.Helpful, AF.IncludeNameplateOnly, notBig, notExternal, AF.Important), max = db.importantMax },
        -- Excludes the same three categories the other groups above already claim - without that,
        -- a spell on this explicit list that Blizzard also tags BigDefensive/ExternalDefensive/
        -- Important (e.g. Blessing of Protection, both here and ExternalDefensive) matched two
        -- groups at once and rendered twice (confirmed live on Modules\PartyFrames.lua's identical
        -- setup).
        { key = "Extra", filter = Filter(AF.Helpful, AF.IncludeNameplateOnly, notBig, notExternal, notImportant), max = db.importantMax,
            candidateFilters = { includeSpellIDs = EXTRA_IMPORTANT_SPELLS } },
    }, importantSize, true, "TOPRIGHT", FlowDirection.Left, FlowDirection.Down, LineSize(db.importantMax, importantSize))
    -- Debuffs: rows above the bar; a new row starts after "per row" icons and goes on top.
    containers.debuffs = CreateContainer({
        { key = "Debuffs", filter = Filter(AF.Harmful, AF.IncludeNameplateOnly, mine, notCC), max = db.debuffPerRow * db.debuffRows },
    }, db.debuffSize, false, "BOTTOMLEFT", FlowDirection.Right, FlowDirection.Up, LineSize(db.debuffPerRow, db.debuffSize))
    -- Remaining buffs: rows above the debuffs.
    containers.buffs = CreateContainer({
        { key = "Buffs", filter = Filter(AF.Helpful, AF.IncludeNameplateOnly, notBig, notExternal, notImportant), max = db.buffPerRow * db.buffRows },
    }, db.buffSize, true, "BOTTOMLEFT", FlowDirection.Right, FlowDirection.Up, LineSize(db.buffPerRow, db.buffSize))
    return containers
end

-- The level badge sits right of the bar; crowd control goes right of it.
local function RightAnchor(frame, unit)
    local level = frame.PlayerLevelDiffFrame
    if level and Accessible(level) and level:IsShown() and (not level.ShouldDisplay or level:ShouldDisplay(unit)) then
        return level
    end
    return frame.HealthBarsContainer
end

-- The debuff row above the bar and the buff row above it, from the left or centered.
PlaceRows = function(debuffs, buffs, bar)
    local db = DB()
    debuffs:ClearAllPoints()
    buffs:ClearAllPoints()
    if db.centerAuras then
        debuffs:SetPoint("BOTTOM", bar, "TOP", db.debuffX, db.debuffY)
        buffs:SetPoint("BOTTOM", debuffs, "TOP", 0, ROW_GAP)
    else
        debuffs:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", db.debuffX, db.debuffY)
        buffs:SetPoint("BOTTOMLEFT", debuffs, "TOPLEFT", 0, ROW_GAP)
    end
end

local function PlaceContainers(set, frame, unit)
    local db = DB()
    local bar = frame.HealthBarsContainer
    local containers = set.containers

    local cc = containers.cc
    cc:ClearAllPoints()
    cc:SetPoint("TOPLEFT", RightAnchor(frame, unit), "RIGHT", SIDE_GAP + db.ccX, SideSize(db.ccScale) / 2 + db.ccY)

    local important = containers.important
    important:ClearAllPoints()
    important:SetPoint("TOPRIGHT", bar, "LEFT", -SIDE_GAP + db.importantX, SideSize(db.importantScale) / 2 + db.importantY)

    -- An empty container is one pixel tall, so the buffs drop down when there are no debuffs.
    -- Centered: a container is as wide as its icons, so anchoring its middle centers the rows.
    PlaceRows(containers.debuffs, containers.buffs, bar)
end

-- Name ---------------------------------------------------------------------------------------------

local placingName = false

local function PlaceName(frame)
    local name = frame.name
    if not name or not Accessible(name) or placingName then
        return
    end
    placingName = true
    name:ClearAllPoints()
    name:SetPoint("BOTTOM", frame.HealthBarsContainer, "TOP", DB().nameX, DB().nameY)
    placingName = false
end

local function HookName(frame)
    local name = frame.name
    if not name or hookedNames[name] or not Accessible(name) then
        return
    end
    hookedNames[name] = true
    -- The client re-anchors the name when it updates the plate; ours goes back on.
    hooksecurefunc(name, "SetPoint", function()
        if placingName or not enemyFrames[frame] then
            return
        end
        local db = DB()
        if db.enabled then
            pcall(PlaceName, frame)
        end
    end)
end

-- The client's own nameplate auras are hidden while ours are shown.
local function SetDefaultAurasShown(frame, shown)
    local auras = frame.AurasFrame
    if auras and Accessible(auras) then
        auras:SetAlpha(shown and 1 or 0)
    end
end

-- Test mode ----------------------------------------------------------------------------------------
-- Real containers only show real auras, so the test mode draws stand-in icons in the same places.

local SAMPLE_ICONS = {
    debuffs = { 136207, 136139, 132204 },        -- Shadow Word: Pain (Magic), Curse of Agony (Curse), Serpent Sting (Poison)
    buffs = { 135987, 132333 },                  -- Power Word: Fortitude (Magic), Battle Shout (no type)
    important = { 135896, 135964 },              -- Divine Shield (can't be purged), Blessing of Protection (Magic)
    cc = { 136071, 132114 },                     -- Polymorph (Magic), Bash (no type)
}
-- Which sample buffs can be purged (they show the purge glow).
local SAMPLE_PURGEABLE = {
    buffs = { true, false },
    important = { false, true },
}
-- Dispel types of the sample debuffs (for their colored borders).
local SAMPLE_TYPES = {
    debuffs = { "Magic", "Curse", "Poison" },
    cc = { "Magic", "None" },
}

local function PreviewIcon(holder, size, texture, purgeable, dispelType)
    local icon = CreateFrame("Frame", nil, holder)
    icon:SetSize(size, size)
    local art = icon:CreateTexture(nil, "ARTWORK")
    art:SetAllPoints()
    art:SetTexture(texture)
    art:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    local edges = AddBlackBorder(icon, icon, BORDER_SIZE)
    local color = dispelType and TYPE_COLORS[dispelType]
    for _, edge in ipairs(edges) do
        if purgeable then
            edge:SetVertexColor(0, 0, 0, 0)
        elseif color then
            edge:SetVertexColor(color[1], color[2], color[3], 1)
        end
    end
    local timer = icon:CreateFontString(nil, "OVERLAY")
    timer:SetFont(S:GetFont(), math.max(8, math.floor(size * 0.45)), "OUTLINE")
    timer:SetPoint("CENTER")
    timer:SetText(math.random(3, 25))
    if purgeable then
        CreatePurgeGlow(icon, icon, size)
    end
    return icon
end

-- Shared with the target / focus auras' own test mode (Modules\UnitAuras.lua).
M.PreviewIcon = PreviewIcon

-- A block of stand-in icons laid out like the matching container: "count" icons, "perRow" per
-- line, new lines above (growUp) or below; lines grow to the left with growLeft. The sample
-- textures, types and purgeable flags repeat.
local function PreviewBlock(holder, sample, types, size, count, perRow, growLeft, growUp, purgeable)
    local spacing = Spacing()
    local lines = math.ceil(count / perRow)
    local block = CreateFrame("Frame", nil, holder)
    block:SetSize(math.max(1, LineSize(math.min(count, perRow), size)), math.max(1, lines * size + (lines - 1) * spacing))
    for index = 1, count do
        local which = (index - 1) % #sample + 1
        local icon = PreviewIcon(block, size, sample[which], purgeable and purgeable[which], types and types[which])
        local x = ((index - 1) % perRow) * (size + spacing)
        local y = math.floor((index - 1) / perRow) * (size + spacing)
        if growUp then
            icon:SetPoint("BOTTOMLEFT", block, "BOTTOMLEFT", x, y)
        elseif growLeft then
            icon:SetPoint("TOPRIGHT", block, "TOPRIGHT", -x, -y)
        else
            icon:SetPoint("TOPLEFT", block, "TOPLEFT", x, -y)
        end
    end
    return block
end

local function ShowPreview(set, frame, unit)
    local db = DB()
    if set.preview and set.preview.generation ~= generation then
        set.preview:Hide()
        set.preview = nil
    end
    if not set.preview then
        local holder = CreateFrame("Frame", nil, frame)
        holder:SetAllPoints(frame)
        holder:SetFrameLevel(frame:GetFrameLevel() + 20)
        holder.generation = generation
        holder.cc = PreviewBlock(holder, SAMPLE_ICONS.cc, SAMPLE_TYPES.cc, SideSize(db.ccScale), db.ccMax, db.ccMax)
        holder.important = PreviewBlock(holder, SAMPLE_ICONS.important, nil, SideSize(db.importantScale),
            db.importantMax, db.importantMax, true, false, db.purgeGlow and SAMPLE_PURGEABLE.important)
        holder.debuffs = PreviewBlock(holder, SAMPLE_ICONS.debuffs, SAMPLE_TYPES.debuffs, db.debuffSize,
            db.debuffPerRow * db.debuffRows, db.debuffPerRow, false, true)
        holder.buffs = PreviewBlock(holder, SAMPLE_ICONS.buffs, nil, db.buffSize,
            db.buffPerRow * db.buffRows, db.buffPerRow, false, true, db.purgeGlow and SAMPLE_PURGEABLE.buffs)
        set.preview = holder
    end
    local holder, bar = set.preview, frame.HealthBarsContainer
    holder.cc:ClearAllPoints()
    holder.cc:SetPoint("TOPLEFT", RightAnchor(frame, unit), "RIGHT", SIDE_GAP + db.ccX, SideSize(db.ccScale) / 2 + db.ccY)
    holder.important:ClearAllPoints()
    holder.important:SetPoint("TOPRIGHT", bar, "LEFT", -SIDE_GAP + db.importantX, SideSize(db.importantScale) / 2 + db.importantY)
    PlaceRows(holder.debuffs, holder.buffs, bar)
    holder:Show()
end

-- Size and border ----------------------------------------------------------------------------------

-- Width: the client's nameplate size, shared by all plates (the health bar spans it). The client
-- sets its own size again when its nameplate options change, so ours goes back on after that.
local applyingWidth = false

function M:GetWidth()
    local width = DB().width
    if width then
        return width
    end
    local current = C_NamePlate.GetNamePlateSize and C_NamePlate.GetNamePlateSize()
    return (current and not S.IsSecret(current)) and math.floor(current + 0.5) or 150
end

function M:ApplyWidth()
    local width = DB().width
    if not width or not (C_NamePlate.SetNamePlateSize and C_NamePlate.GetNamePlateSize) then
        return
    end
    if InCombatLockdown() then
        self.widthPending = true
        return
    end
    self.widthPending = false
    local currentWidth, currentHeight = C_NamePlate.GetNamePlateSize()
    if S.IsSecret(currentWidth) or S.IsSecret(currentHeight) then
        return
    end
    if not currentWidth or math.abs(currentWidth - width) > 0.5 then
        applyingWidth = true
        pcall(C_NamePlate.SetNamePlateSize, width, currentHeight or 45)
        applyingWidth = false
    end
end

-- Height: each plate's health bar; the client sets it again on updates, ours goes back on.
local barHeightHooked = setmetatable({}, { __mode = "k" })
local settingHeight = false

function M:GetBarHeight()
    return DB().barHeight or 15
end

local function ApplyBarHeight(frame)
    local height = DB().barHeight
    local bars = frame.HealthBarsContainer
    if not height or not bars or not Accessible(bars) or settingHeight then
        return
    end
    if not barHeightHooked[bars] then
        barHeightHooked[bars] = true
        hooksecurefunc(bars, "SetHeight", function(self)
            if not settingHeight and DB().barHeight then
                pcall(ApplyBarHeight, frame)
            end
        end)
    end
    settingHeight = true
    bars:SetHeight(height)
    settingHeight = false
end

-- Dark mode: on this client the plate's border is the health bar's background texture (it
-- reaches out around the bar). The target highlight is darkened less, so the target stays
-- visible. The level badge's ring (playerLevelDiffIcon) keeps its own color dimmed rather than
-- flattened to gray - confirmed live that flattening it made both the level number AND the skull
-- icon a way-higher-level target shows in its place unreadable/wrong-colored. Same treatment as
-- the elite portrait ring on the target/focus frame (Modules\DarkMode.lua).
local TARGET_HIGHLIGHT_OFFSET = 0.5
local LEVEL_DIFF_OFFSET = 0.2

local function DarkenBorder(frame)
    local healthBar = frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar
    if healthBar and Accessible(healthBar) then
        S:Darken(healthBar.bgTexture)
        S:Darken(healthBar.selectedBorder, TARGET_HIGHLIGHT_OFFSET)
    end
    local level = frame.PlayerLevelDiffFrame
    if level and Accessible(level) and level.playerLevelDiffIcon then
        S:Darken(level.playerLevelDiffIcon, LEVEL_DIFF_OFFSET, nil, true)
    end
end

-- Health bar color -----------------------------------------------------------------------------
-- Same class-color-first-then-reaction priority as the player/target/focus frames (Modules\
-- UnitFrames.lua, not shared from there since every other module here duplicates this small a
-- bit of class color lookup too, e.g. LootRoll.lua, Tooltip.lua). Blizzard's own nameplate color
-- doesn't always reflect class color (a PvP-flagged enemy player's bar can come back a plain
-- reaction color instead), so it's applied here too and kept on by re-coloring whenever the
-- client changes the bar's color back.

local REACTION_FALLBACK = {
    [1] = { r = 0.8, g = 0.13, b = 0.13 }, [2] = { r = 0.8, g = 0.13, b = 0.13 }, [3] = { r = 0.75, g = 0.27, b = 0 },
    [4] = { r = 0.9, g = 0.7, b = 0 }, [5] = { r = 0, g = 0.6, b = 0.1 }, [6] = { r = 0, g = 0.6, b = 0.1 },
    [7] = { r = 0, g = 0.6, b = 0.1 }, [8] = { r = 0, g = 0.6, b = 0.1 },
}

local function PlateClassColor(unit)
    local exists = UnitExists(unit)
    if S.IsSecret(exists) or not exists then
        return nil
    end
    local isPlayer = UnitIsPlayer(unit)
    if S.IsSecret(isPlayer) or not isPlayer then
        return nil
    end
    local _, class = UnitClass(unit)
    if not class or S.IsSecret(class) then
        return nil
    end
    return (C_ClassColor and C_ClassColor.GetClassColor(class)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
end

local function PlateReactionColor(unit)
    local exists = UnitExists(unit)
    if S.IsSecret(exists) or not exists then
        return nil
    end
    local reaction = UnitReaction(unit, "player")
    if not reaction or S.IsSecret(reaction) then
        return nil
    end
    return (FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]) or REACTION_FALLBACK[reaction]
end

local function PlateBarColor(unit)
    local appearance = S.db.appearance
    return (appearance.classColors and PlateClassColor(unit)) or (appearance.reactionColors and PlateReactionColor(unit)) or nil
end

-- Tapped by another player (you can't loot/get credit), dead, or disconnected: the client grays
-- the health bar itself (CompactUnitFrame_UpdateHealthColor: 0.9,0.9,0.9 tapped, 0.5,0.5,0.5
-- dead/offline) before our own color below would otherwise overwrite it. UnitIsTapDenied can't
-- be read here to detect that directly - a secret value in combat, same class of problem as
-- Modules\ActionBars.lua's range check - so instead this reads the color the client just set and
-- leaves it alone when it already matches one of those two grays.
local SPECIAL_GRAYS = { { 0.9, 0.9, 0.9 }, { 0.5, 0.5, 0.5 } }

local function MatchesSpecialGray(r, g, b)
    if S.IsSecret(r) or S.IsSecret(g) or S.IsSecret(b) then
        return false
    end
    for _, gray in ipairs(SPECIAL_GRAYS) do
        if math.abs(r - gray[1]) < 0.01 and math.abs(g - gray[2]) < 0.01 and math.abs(b - gray[3]) < 0.01 then
            return true
        end
    end
    return false
end

local barPainting = false
local barColorHooked = setmetatable({}, { __mode = "k" }) -- health bar -> true
local barUnit = setmetatable({}, { __mode = "k" })         -- health bar -> its current unit token

local function PaintBarColor(healthBar)
    local unit = barUnit[healthBar]
    if not unit then
        return
    end
    local r, g, b = healthBar:GetStatusBarColor()
    if MatchesSpecialGray(r, g, b) then
        return
    end
    local color = PlateBarColor(unit)
    if not color then
        return
    end
    barPainting = true
    healthBar:SetStatusBarColor(color.r, color.g, color.b)
    barPainting = false
end

local function ApplyBarColor(frame, unit)
    local healthBar = frame.HealthBarsContainer and frame.HealthBarsContainer.healthBar
    if not healthBar or not Accessible(healthBar) then
        return
    end
    -- The health bar object is pooled and reused for a different unit later, so the callback
    -- below looks this up fresh each time rather than closing over the unit from here.
    barUnit[healthBar] = unit
    if not barColorHooked[healthBar] then
        barColorHooked[healthBar] = true
        hooksecurefunc(healthBar, "SetStatusBarColor", function(self)
            if not barPainting then
                pcall(PaintBarColor, self)
            end
        end)
    end
    pcall(PaintBarColor, healthBar)
end

-- Friendly nameplates --------------------------------------------------------------------------
-- Both the "name only" simplification (health bar, cast bar, level badge and native buffs/
-- debuffs all hidden) and the class colored name are native client behavior on this build,
-- confirmed live via /dump GetCVar(...): fighting the client's own frames with hooks (an earlier
-- version of this code did - health bar/cast bar alpha, SetTextColor, all reset by the client's
-- own update passes in ways that kept racing whatever we tried) isn't needed when it already has
-- CVars for exactly this.
local FRIENDLY_CVARS = {
    friendlyNameOnly = "nameplateShowOnlyNameForFriendlyPlayerUnits",
    friendlyClassColor = "nameplateUseClassColorForFriendlyPlayerUnitNames",
}

local function ApplyFriendlyCVars()
    local db = DB()
    for key, cvar in pairs(FRIENDLY_CVARS) do
        SetCVar(cvar, db[key] and "1" or "0")
    end
end

-- Name and level text size (nil: the client's size).
local resizing = false
local fontHooked = setmetatable({}, { __mode = "k" })

local function SetFontSize(fontString, size)
    if not size or not fontString or not Accessible(fontString) then
        return
    end
    local file, current, flags = fontString:GetFont()
    if not file or S.IsSecret(file) or S.IsSecret(current) or current == size then
        return
    end
    resizing = true
    fontString:SetFont(file, size, flags or "")
    resizing = false
end

-- Font strings under a frame (the level badge keeps its number in a sub frame).
local function EachFontString(frame, callback, depth)
    if not frame or depth > 2 or not Accessible(frame) then
        return
    end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:IsObjectType("FontString") then
            callback(region)
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        EachFontString(child, callback, depth + 1)
    end
end

local function ApplyTextSizes(frame)
    local db = DB()
    local name = frame.name
    if name and db.nameSize then
        if not fontHooked[name] and Accessible(name) then
            fontHooked[name] = true
            -- The client sets the name's font again on updates; our size goes back on.
            for _, method in ipairs({ "SetFont", "SetFontObject" }) do
                hooksecurefunc(name, method, function(self)
                    if not resizing and DB().nameSize then
                        pcall(SetFontSize, self, DB().nameSize)
                    end
                end)
            end
        end
        SetFontSize(name, db.nameSize)
    end
    if db.levelSize then
        EachFontString(frame.PlayerLevelDiffFrame, function(text)
            SetFontSize(text, db.levelSize)
        end, 0)
    end
end

-- The sizes the sliders start from: the first visible plate's, or the usual ones.
function M:GetTextSize(key)
    local db = DB()
    if db[key] then
        return db[key]
    end
    for _, set in pairs(sets) do
        local frame = set.frame
        if frame then
            local text = key == "nameSize" and frame.name
            if key == "levelSize" then
                EachFontString(frame.PlayerLevelDiffFrame, function(region) text = text or region end, 0)
            end
            if text and Accessible(text) then
                local _, size = text:GetFont()
                if size and not S.IsSecret(size) then
                    return math.floor(size + 0.5)
                end
            end
        end
    end
    return 12
end

-- Binding ------------------------------------------------------------------------------------------

local function DisableContainers(set)
    for _, container in pairs(set.containers or {}) do
        container:SetEnabled(false)
        container:Hide()
        container:ClearAllPoints()
        container:SetParent(UIParent)
    end
end

function M:Unbind(unit)
    local set = sets[unit]
    if not set then
        return
    end
    DisableContainers(set)
    if set.preview then
        set.preview:Hide()
    end
    if set.frame then
        enemyFrames[set.frame] = nil
        SetDefaultAurasShown(set.frame, true)
    end
    set.frame = nil
end

function M:Bind(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit, issecure and issecure())
    local frame = plate and plate.UnitFrame
    if not frame or not Accessible(frame) or not frame.HealthBarsContainer then
        return
    end
    local db = DB()
    local enemy = IsEnemy(unit)
    local set = sets[unit] or {}
    sets[unit] = set

    -- Settings changed since this set was built: start over with new containers.
    if set.generation ~= generation then
        DisableContainers(set)
        set.containers = nil
        set.generation = generation
    end
    set.frame = frame
    pcall(ApplyBarHeight, frame)
    pcall(DarkenBorder, frame)
    pcall(ApplyBarColor, frame, unit)
    pcall(ApplyTextSizes, frame)
    -- Whole nameplate scale (every plate; the aura icons on it scale along).
    local scale = db.scale or 1
    if math.abs(frame:GetScale() - scale) > 0.001 then
        frame:SetScale(scale)
    end
    enemyFrames[frame] = (enemy and db.enabled) or nil

    -- The test mode pauses in combat: the samples hide and come back when it ends.
    if db.testMode and not InCombatLockdown() then
        ShowPreview(set, frame, unit)
    elseif set.preview then
        set.preview:Hide()
    end

    if not (db.enabled and enemy) then
        DisableContainers(set)
        SetDefaultAurasShown(frame, true)
        return
    end

    HookName(frame)
    PlaceName(frame)

    if not set.containers then
        set.containers = BuildContainers()
    end
    local level = frame:GetFrameLevel() + 10
    for _, container in pairs(set.containers) do
        container:SetParent(frame)
        container:SetFrameStrata(frame:GetFrameStrata())
        container:SetFrameLevel(level)
    end
    PlaceContainers(set, frame, unit)
    for _, container in pairs(set.containers) do
        container:SetUnit(unit)
        container:SetEnabled(true)
        container:Show()
    end
    SetDefaultAurasShown(frame, false)
end

local function SafeBind(unit)
    local ok, err = pcall(M.Bind, M, unit)
    if not ok and not M.reported then
        M.reported = true
        geterrorhandler()(err)
    end
end

function M:BindAll()
    for _, plate in ipairs(C_NamePlate.GetNamePlates() or {}) do
        local unit = plate.namePlateUnitToken or (plate.UnitFrame and plate.UnitFrame.unit)
        if type(unit) == "string" and not S.IsSecret(unit) then
            SafeBind(unit)
        end
    end
end

-- Module -------------------------------------------------------------------------------------------

function M:Init()
    if not Supported() then
        return
    end
    local db = DB()
    db.testMode = false
    -- The first version's default debuff height (16) becomes the new default (24).
    if not db.layoutVersion then
        if db.debuffY == 16 then
            db.debuffY = 24
        end
        db.layoutVersion = 2
    end
    self:RefreshPurgeTypes()
    ApplyFriendlyCVars()

    S:On("PLAYER_REGEN_ENABLED", function()
        if M.widthPending then
            M:ApplyWidth()
        end
        if DB().testMode then
            M:BindAll()
        end
    end)
    S:On("PLAYER_REGEN_DISABLED", function()
        for _, set in pairs(sets) do
            if set.preview then
                set.preview:Hide()
            end
        end
    end)
    if C_NamePlate.SetNamePlateSize then
        hooksecurefunc(C_NamePlate, "SetNamePlateSize", function()
            if not applyingWidth and DB().width then
                C_Timer.After(0, function() M:ApplyWidth() end)
            end
        end)
    end
    S:On("NAME_PLATE_UNIT_ADDED", function(_, unit)
        SafeBind(unit)
    end)
    S:On("NAME_PLATE_UNIT_REMOVED", function(_, unit)
        pcall(M.Unbind, M, unit)
    end)
    S:On("UNIT_FACTION", function(_, unit)
        if type(unit) == "string" and not S.IsSecret(unit) and sets[unit] then
            SafeBind(unit)
        end
    end)
    -- New spells (a purge learned) change which buffs glow: buttons are rebuilt.
    for _, event in ipairs({ "SPELLS_CHANGED", "UNIT_PET" }) do
        S:On(event, function()
            local before = PurgeSignature()
            M:RefreshPurgeTypes()
            local after = PurgeSignature()
            if before ~= after and not InCombatLockdown() then
                M:Rebuild()
            end
        end)
    end
end

-- Settings changed: new containers on every plate (button looks are fixed once created).
-- Slider drags come in many small steps, so this waits until they settle.
function M:Rebuild()
    if self.rebuildPending then
        return
    end
    self.rebuildPending = true
    C_Timer.After(0.3, function()
        M.rebuildPending = false
        generation = generation + 1
        M:BindAll()
    end)
end

function M:Refresh()
    if not Supported() then
        return
    end
    ApplyFriendlyCVars()
    self:ApplyWidth()
    self:Rebuild()
end

function M:IsSupported()
    return Supported()
end
