local _, S = ...
local M = S:NewModule("Auras")

-- Player buffs and debuffs, built from our own AuraContainer the same way Modules\UnitAuras.lua
-- already does for target/focus (same InitAuraButton style.playerLook=true look: black border,
-- debuff-type colored border, white-number/yellow-unit duration, tooltips), instead of reskinning
-- Blizzard's own BuffFrame/DebuffFrame buttons in place. Confirmed live via /smuve dump that those
-- native buttons never carry SetDurationText or AddDispelTypeTexture (SetDurationText=nil on
-- every one of them, every time) - only buttons an AddAuraGroup call creates itself get those -
-- so the old reskin approach could only ever touch font/size/position, never the duration text's
-- actual content/color or a debuff border's dispel-type color. The "8m" vs "8 m" switching the
-- user saw was always the client's own native text underneath, not anything this addon controlled.
--
-- Not anchored to BuffFrame/DebuffFrame at all, and Edit Mode is never consulted - confirmed live
-- through several rounds of this addon's own trial and error (GetPoint on anything parented to
-- BuffFrame/DebuffFrame is permanently secret, SetSize on either silently does nothing, an
-- UpdateSystemSetting-driven layout still rendered visibly offset with no way to read back and
-- correct it) that this client's BuffFrame/DebuffFrame and Edit Mode integration can't be
-- depended on from addon code. EllesmereUI (this client's own popular UI addon, confirmed by
-- reading its EllesmereUIUnitFrames/EUI_PlayerAuraBars_Bars.lua) independently arrived at the
-- same conclusion: its player aura bars are plain UIParent-anchored frames with their own saved
-- position and their own drag-to-move, Blizzard's BuffFrame/DebuffFrame hidden outright ("so
-- auras aren't shown twice"). This follows that same proven approach, reusing the plain
-- drag-while-unlocked pattern already in Modules\LootRoll.lua for its window (Edit Mode doesn't
-- offer that one either).

local AF = AuraUtil and AuraUtil.AuraFilters
local CreateFilterString = AuraUtil and AuraUtil.CreateFilterString
local FlowDirection = AnchorUtil and AnchorUtil.FlowDirection

-- Weapon imbues (shaman imbues at any rank, confirmed the same way for rogue poisons/whetstones)
-- are a WoW Forever-only enchant type (Enum.ItemEnchantType.Imbue) separate from the plain
-- temporary enchant type (oils, stones) that C_PaperDollInfo.GetTemporaryEnchantmentInfo exposes -
-- confirmed live that AddItemEnchantment (which reads that same API under the hood, like the
-- client's own native BuffFrame.AuraContainer weapon-enchant cells) never sees an imbue at all,
-- regardless of rank or weapon. EllesmereUI (EllesmereUIUnitFrames\EUI_UnitFrames_ForeverImbues.lua)
-- reads C_Item.GetWeaponEnchantInfo(slot) instead - a different, non-deprecated API that lists
-- every enchant per weapon slot with its own enchantType - and draws imbues as its own icons
-- beside its aura container rather than through AddItemEnchantment. This does the same.
local EnchantType = Enum.ItemEnchantType
local WeaponSlot = Enum.WeaponSlot
local ImbuesSupported = EnchantType and EnchantType.Imbue and WeaponSlot and C_Item
    and C_Item.GetWeaponEnchantInfo and GetInventoryItemTexture
-- Reverse slot order: the cells are laid out leading (before) the buffs, growing away from the
-- bar one slot at a time, so main hand ends up the one touching the bar - same as the client's
-- own native weapon-enchant cells.
local IMBUE_SLOTS = ImbuesSupported and { WeaponSlot.Ranged, WeaponSlot.OffHand, WeaponSlot.MainHand } or {}
local IMBUE_INV_SLOT = ImbuesSupported and {
    [WeaponSlot.MainHand] = INVSLOT_MAINHAND or 16,
    [WeaponSlot.OffHand] = INVSLOT_OFFHAND or 17,
    [WeaponSlot.Ranged] = INVSLOT_RANGED or 18,
} or {}

local ICON_SIZE = 40
local SPACING = 2
local DEBUFF_GAP = 10 -- between the buffs area's bottom edge and the debuffs below it
local MAX_BUFFS = BUFF_MAX_DISPLAY or 32
local MAX_DEBUFFS = DEBUFF_MAX_DISPLAY or 16
-- Debuffs keeps at least this many empty buff rows' worth of distance from the buffs' top edge,
-- even with only one or two buffs up - so debuffs doesn't jump up right under them, and only
-- creeps back down (RepositionDebuffs, below) once buffs actually grows past this many rows.
local MIN_BUFF_ROWS = 3

-- Only buffs gets a saved/draggable position; debuffs is anchored to its container below instead
-- (see CreateAuraContainer/RepositionDebuffs) so a bigger buffs scale, or buffs simply wrapping to
-- another row, carries debuffs down with it live rather than needing a second position to keep in
-- sync.
local DEFAULT_POS = {
    buffs = { point = "TOPRIGHT", x = -275, y = -20 },
}

local function DB()
    return S.db.appearance
end

local function Supported()
    return AF and CreateFilterString and FlowDirection and AuraContainerSortMethod ~= nil
        and S.modules.Nameplates and S.modules.Nameplates.InitAuraButton ~= nil
end

local parents = {}    -- "buffs" | "debuffs" -> our own movable anchor frame
local containers = {} -- "buffs" | "debuffs" -> aura container
M.containers = containers -- read by /smuve dump

-- Hiding Blizzard's own BuffFrame/DebuffFrame -------------------------------------------------

-- The client re-shows these on its own later (confirmed live for the collapse/expand button
-- earlier, same reasoning applies here) - Show and SetShown are both hooked, plus a cheap
-- low-frequency ticker as a backstop regardless of mechanism.
local hiddenForever = setmetatable({}, { __mode = "k" })
local hideHooked = setmetatable({}, { __mode = "k" })

local function HideForever(frame)
    if not frame then
        return
    end
    hiddenForever[frame] = true
    frame:Hide()
    if not hideHooked[frame] then
        hideHooked[frame] = true
        hooksecurefunc(frame, "Show", function(self) self:Hide() end)
        if frame.SetShown then
            hooksecurefunc(frame, "SetShown", function(self, shown)
                if shown then
                    self:Hide()
                end
            end)
        end
    end
end

local hideTicker

local function StartHideTicker()
    if hideTicker then
        return
    end
    hideTicker = C_Timer.NewTicker(0.5, function()
        for frame in pairs(hiddenForever) do
            if frame:IsShown() then
                frame:Hide()
            end
        end
    end)
end

-- Our own frames --------------------------------------------------------------------------------

local function OnDragStart(self)
    self:StartMoving()
end

local function OnDragStop(self, key)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint(1)
    if point and not S.IsSecret(point) then
        DB()["aura" .. key .. "Pos"] = { point = point, x = x, y = y }
    end
end

local unlockLabels = {}
local unlockBackdrops = {}

function M:ApplyUnlocked()
    local unlocked = DB().auraBarsUnlocked
    for key, parent in pairs(parents) do
        parent:SetMovable(true)
        parent:EnableMouse(unlocked)
        if unlocked then
            parent:RegisterForDrag("LeftButton")
        else
            parent:RegisterForDrag()
        end
        local label = unlockLabels[key]
        local backdrop = unlockBackdrops[key]
        if unlocked then
            if not label then
                label = parent:CreateFontString(nil, "OVERLAY")
                label:SetFont(S:GetFont(), 12, "OUTLINE")
                label:SetPoint("BOTTOM", parent, "TOP", 0, 4)
                label:SetTextColor(1, 0.82, 0)
                label:SetText("Buffs - drag to move")
                unlockLabels[key] = label
            end
            if not backdrop then
                -- Otherwise invisible with nothing active on it - hard to even find to drag.
                backdrop = parent:CreateTexture(nil, "BACKGROUND")
                backdrop:SetAllPoints(parent)
                backdrop:SetColorTexture(0, 0.6, 1, 0.3)
                unlockBackdrops[key] = backdrop
            end
            label:Show()
            backdrop:Show()
        else
            if label then
                label:Hide()
            end
            if backdrop then
                backdrop:Hide()
            end
        end
    end
end

local function CreateParent(key)
    local parent = CreateFrame("Frame", nil, UIParent)
    -- A minimum clickable size, so the drag handle is grabbable even with nothing active on it.
    parent:SetSize(ICON_SIZE + SPACING, ICON_SIZE + SPACING)
    local saved = DB()["aura" .. key .. "Pos"] or DEFAULT_POS[key]
    parent:SetPoint(saved.point, UIParent, saved.point, saved.x, saved.y)
    parent:SetClampedToScreen(true)
    parent:SetScript("OnDragStart", OnDragStart)
    parent:SetScript("OnDragStop", function(self) OnDragStop(self, key) end)
    parents[key] = parent
    return parent
end

-- Containers ---------------------------------------------------------------------------------------

-- anchorTo: the buffs parent frame for buffs, the buffs container itself for debuffs (anchored to
-- its bottom edge instead of to a parent of its own - see the comment on DEFAULT_POS above).
local function CreateAuraContainer(anchorTo, isDebuff)
    local container = CreateFrame("AuraContainer", nil, UIParent, "CustomAuraContainerTemplate")
    container:SetUnit("player")
    if container.SetFlattensRenderLayers then
        container:SetFlattensRenderLayers(true)
    end
    local prefix = isDebuff and "auraDebuffs" or "auraBuffs"
    container:SetScale(DB()[prefix .. "Scale"] or 1)
    local perRow = DB()[prefix .. "PerRow"] or 10
    container:SetFlowLayoutAnchorPoint("TOPRIGHT")
    container:SetFlowLayoutGrowthDirection(FlowDirection.Left, FlowDirection.Down)
    container:SetFlowLayoutMaximumLineSize(perRow * (ICON_SIZE + SPACING))

    local style = {
        typeBorders = true, -- debuff borders in their dispel type's color, always on
        purgeGlow = false,
        showDuration = true,
        durationSize = DB().auraDurationSize,
        playerLook = true, -- duration and stacks positioned/formatted like this style was built for
        mouse = true,      -- tooltips on hover, like the client's own buff/debuff icons
    }
    -- AF.IncludeNameplateOnly: despite the name, this isn't about displaying on a nameplate - a
    -- plain Helpful/Harmful filter string misses some spells entirely without it (confirmed
    -- elsewhere in this addon for Blessing of Protection/Freedom - Modules\Nameplates.lua,
    -- Modules\BigDebuffs.lua, Modules\PartyFrames.lua).
    container:AddAuraGroup(isDebuff and "Debuffs" or "Buffs",
        CreateFilterString(isDebuff and AF.Harmful or AF.Helpful, AF.IncludeNameplateOnly), {
        maxFrameCount = isDebuff and MAX_DEBUFFS or MAX_BUFFS,
        sortMethod = AuraContainerSortMethod.Default,
        sortDirection = AuraContainerSortDirection.Normal,
        initializeFrame = function(button)
            S.modules.Nameplates.InitAuraButton(button, ICON_SIZE, not isDebuff, style)
            -- Right click to cancel, like the client's own buff icons; debuffs can't be canceled.
            if not isDebuff and button.SetCancelAuraButtons then
                button:SetCancelAuraButtons("RightButtonUp")
            end
        end,
        layout = {
            elementSpacing = SPACING,
            lineSpacing = SPACING,
            elementWidth = ICON_SIZE,
            elementHeight = ICON_SIZE,
            layoutIndex = 1,
        },
    })
    -- Weapon imbues (shaman imbues, rogue poisons, whetstones) are NOT added here via
    -- AddItemEnchantment - confirmed live that its initializeFrame never even fires for one on an
    -- addon-created container, the same way the plain temporary-enchant APIs never see one either
    -- (see the EnchantType/ImbuesSupported comment near the top of this file). They're drawn as
    -- their own cells instead, leading the buffs container - see LayoutImbues, below Build().
    container:SetEnabled(true)
    container:ClearAllPoints()
    if isDebuff then
        -- Just a provisional anchor so the frame is never pointless between creation and the
        -- RepositionDebuffs call Build() makes right after - that one (below) is what actually
        -- keeps it in place, live, off the buffs area's real height with its minimum-rows floor.
        container:SetPoint("TOPRIGHT", anchorTo, "BOTTOMRIGHT", 0, -DEBUFF_GAP)
    else
        container:SetPoint("TOPRIGHT", anchorTo, "TOPRIGHT", 0, 0)
    end
    return container
end

-- Weapon imbue cells --------------------------------------------------------------------------

local function Readable(v)
    return v ~= nil and not S.IsSecret(v)
end

local imbueTrack = {}  -- weapon slot -> { id, endTime, total }, to know when a swipe restarts
local shownImbues = {} -- cell index -> { inv, icon, charges, endTime, total }
local imbueCells = {}  -- cell index -> { button, icon, cooldown, stack, timer, dur, binding }

-- Equipment data, read on the weapon events and at each layout only.
local function ScanImbues()
    local n, now = 0, GetTime()
    for _, slot in ipairs(IMBUE_SLOTS) do
        local list = C_Item.GetWeaponEnchantInfo(slot)
        local found
        if type(list) == "table" then
            for _, enchant in ipairs(list) do
                if Readable(enchant.hasEnchant) and enchant.hasEnchant and Readable(enchant.enchantType)
                    and enchant.enchantType == EnchantType.Imbue and Readable(enchant.timeLeft)
                    and enchant.timeLeft > 0 then
                    found = enchant
                    break
                end
            end
        end
        if found then
            local left = found.timeLeft / 1000
            local endTime = now + left
            local tracked = imbueTrack[slot]
            if not tracked then
                tracked = {}
                imbueTrack[slot] = tracked
            end
            -- A new imbue, or the same one refreshed (its end moved out): restart the swipe from
            -- what's actually left now, rather than carrying over a stale total.
            if tracked.id ~= found.enchantID or endTime > (tracked.endTime or 0) + 1 then
                tracked.total = left
            end
            tracked.id, tracked.endTime = found.enchantID, endTime
            n = n + 1
            local shown = shownImbues[n]
            if not shown then
                shown = {}
                shownImbues[n] = shown
            end
            shown.inv = IMBUE_INV_SLOT[slot]
            local icon = found.enchantIconID
            if not (Readable(icon) and icon ~= 0) then
                icon = GetInventoryItemTexture("player", shown.inv) or 134400
            end
            shown.icon = icon
            shown.charges = Readable(found.charges) and found.charges or 0
            shown.endTime, shown.total = endTime, tracked.total
        else
            imbueTrack[slot] = nil
        end
    end
    return n
end

local function ImbueCellOnEnter(self)
    local inv = self.imbueInv
    if not inv then
        return
    end
    GameTooltip:SetOwner(self, "ANCHOR_BOTTOMLEFT")
    GameTooltip:SetInventoryItem("player", inv)
    GameTooltip:Show()
end

local function ImbueCellOnLeave()
    GameTooltip:Hide()
end

-- A plain button, not a client aura button - AddItemEnchantment-created buttons support methods
-- like SetDurationText/SetIcon that a manually created frame simply doesn't have, so this is
-- built by hand instead, the same pieces InitButton (Modules\Nameplates.lua) uses: a texture, a
-- CooldownFrameTemplate, a black border, and a duration text bound live through C_DurationUtil.
local function CreateImbueCell(parent)
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(ICON_SIZE, ICON_SIZE)
    if button.SetFlattensRenderLayers then
        button:SetFlattensRenderLayers(true)
    end

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
    cooldown:SetAllPoints(button)
    cooldown:SetReverse(true)
    cooldown:SetDrawBling(false)
    cooldown:SetHideCountdownNumbers(true)

    local overlay = CreateFrame("Frame", nil, button)
    overlay:SetAllPoints(button)
    overlay:SetFrameLevel(cooldown:GetFrameLevel() + 1)
    S.modules.Nameplates.AddBlackBorder(overlay, button, S.modules.Nameplates.BORDER_SIZE)

    local stack = overlay:CreateFontString(nil, "OVERLAY")
    stack:SetFont(S:GetFont(), DB().auraDurationSize, "OUTLINE")
    stack:SetPoint("TOPRIGHT", button, "TOPRIGHT", -1, -1)
    stack:SetTextColor(1, 1, 1)

    local timer = overlay:CreateFontString(nil, "OVERLAY")
    timer:SetFont(S:GetFont(), DB().auraDurationSize, "OUTLINE")
    timer:SetTextColor(1, 1, 1)
    timer:SetPoint("BOTTOM", button, "BOTTOM", 1, 1)

    local dur, binding
    if C_DurationUtil and C_DurationUtil.CreateDuration and C_DurationUtil.CreateDurationTextBinding then
        dur = C_DurationUtil.CreateDuration()
        binding = C_DurationUtil.CreateDurationTextBinding()
        binding:SetFontString(timer)
        binding:SetDuration(dur)
        local formatter = S.modules.Nameplates.GetUnitDurationFormatter()
        if formatter then
            binding:SetFormatter(formatter)
        end
    end

    button:EnableMouse(true)
    button:SetScript("OnEnter", ImbueCellOnEnter)
    button:SetScript("OnLeave", ImbueCellOnLeave)

    return { button = button, icon = icon, cooldown = cooldown, stack = stack, timer = timer, dur = dur, binding = binding }
end

local function PaintImbueCell(cell, shown)
    cell.button.imbueInv = shown.inv
    cell.icon:SetTexture(shown.icon)
    cell.stack:SetText(shown.charges > 0 and tostring(shown.charges) or "")
    cell.cooldown:SetCooldown(shown.endTime - shown.total, shown.total)
    if cell.binding then
        cell.dur:SetTimeFromEnd(shown.endTime, shown.total)
        cell.binding:SetEnabled(true)
    end
end

local function HideImbueCellsFrom(first)
    for i = first, #imbueCells do
        imbueCells[i].button:Hide()
        if imbueCells[i].binding then
            imbueCells[i].binding:SetEnabled(false)
        end
    end
end

local lastImbueCount = 0 -- imbue cells LayoutImbues last placed, for RepositionDebuffs' x-shift

-- Debuffs anchors off the buffs PARENT (the fixed drag anchor), not the buffs container itself,
-- with its own live height floored at MIN_BUFF_ROWS rows - so a handful of buffs don't pull
-- debuffs up right underneath them, while a buffs area that actually grows past that floor still
-- pushes debuffs down further rather than overlapping it. Cancels out the same imbue-cell x-shift
-- LayoutImbues applies to the buffs container, so debuffs' right edge stays put regardless of how
-- many imbues are showing. Called after every LayoutImbues pass, and off a low-frequency ticker
-- (StartDebuffsTicker, below) to also catch a plain buff count/row change with no weapon event
-- behind it.
local function RepositionDebuffs()
    if not (containers.buffs and containers.debuffs and parents.buffs) then
        return
    end
    local actual = containers.buffs:GetHeight()
    if not (actual and not S.IsSecret(actual)) then
        actual = 0
    end
    local minHeight = MIN_BUFF_ROWS * (ICON_SIZE + SPACING) * (DB().auraBuffsScale or 1)
    local height = math.max(actual, minHeight)
    local step = ICON_SIZE + SPACING
    containers.debuffs:ClearAllPoints()
    containers.debuffs:SetPoint("TOPRIGHT", parents.buffs, "TOPRIGHT", lastImbueCount * step, -(height + DEBUFF_GAP))
end

-- Lays out active imbues leading the buffs container (same side the client's own weapon-enchant
-- cells lead BuffFrame from), then shifts the container's own anchor out of the way by as many
-- steps - its line width is shortened to match, same as everything else anchored off it.
local function LayoutImbues()
    if not (ImbuesSupported and containers.buffs and parents.buffs) then
        return
    end
    local anchor = parents.buffs
    local n = math.min(ScanImbues(), #IMBUE_SLOTS)
    local step = ICON_SIZE + SPACING
    for i = 1, n do
        local cell = imbueCells[i]
        if not cell then
            cell = CreateImbueCell(anchor)
            imbueCells[i] = cell
        end
        if cell.button:GetParent() ~= anchor then
            cell.button:SetParent(anchor)
        end
        cell.button:ClearAllPoints()
        cell.button:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -(i - 1) * step, 0)
        PaintImbueCell(cell, shownImbues[i])
        cell.button:Show()
    end
    HideImbueCellsFrom(n + 1)
    containers.buffs:ClearAllPoints()
    containers.buffs:SetPoint("TOPRIGHT", anchor, "TOPRIGHT", -n * step, 0)
    local perRow = DB().auraBuffsPerRow or 10
    containers.buffs:SetFlowLayoutMaximumLineSize(math.max(step, perRow * step - n * step))
    lastImbueCount = n
    RepositionDebuffs()
    return n
end

local imbueEvents

local function StartImbueEvents()
    if imbueEvents or not ImbuesSupported then
        return
    end
    imbueEvents = CreateFrame("Frame")
    imbueEvents:SetScript("OnEvent", function() M:RefreshImbues() end)
    imbueEvents:RegisterEvent("WEAPON_ENCHANT_CHANGED")
    imbueEvents:RegisterEvent("WEAPON_SLOT_CHANGED")
    imbueEvents:RegisterEvent("PLAYER_ENTERING_WORLD")
end

-- A weapon event: rescans and re-lays out immediately, rather than through the debounced
-- M:Refresh below - unlike a settings change, this can't be waiting on a slider to settle.
function M:RefreshImbues()
    LayoutImbues()
end

local debuffsTicker

-- RepositionDebuffs needs to track the buffs area's live height regardless of weapon imbues (it's
-- not an imbue feature), so this runs it on its own low-frequency ticker rather than only
-- piggybacking on LayoutImbues/the weapon events above - ImbuesSupported clients still get it hit
-- twice (LayoutImbues calls it too) which is harmless, unsupported clients still get it at all.
local function StartDebuffsTicker()
    if debuffsTicker then
        return
    end
    debuffsTicker = C_Timer.NewTicker(0.3, RepositionDebuffs)
end

local generation = 0

local function Build()
    if not parents.buffs then
        CreateParent("buffs")
    end
    -- Buffs first: debuffs anchors to its container below, so it must already exist.
    for _, key in ipairs({ "buffs", "debuffs" }) do
        local anchorTo = key == "debuffs" and containers.buffs or parents.buffs
        if containers[key] and (containers[key].generation ~= generation or not anchorTo) then
            containers[key]:SetEnabled(false)
            containers[key]:Hide()
            containers[key] = nil
        end
        if not containers[key] and anchorTo then
            local container = CreateAuraContainer(anchorTo, key == "debuffs")
            container.generation = generation
            containers[key] = container
        end
    end
    LayoutImbues()
    RepositionDebuffs()
    M:ApplyUnlocked()
end

function M:Init()
    if not Supported() then
        return
    end
    DB().auraBarsUnlocked = false -- always off after a reload
    -- Superseded outright, the same way EllesmereUI does it - nothing here depends on them being
    -- shown, sized, or anchored to any more.
    for _, frameName in ipairs({ "BuffFrame", "DebuffFrame" }) do
        local frame = _G[frameName]
        if frame then
            HideForever(frame)
        end
    end
    StartHideTicker()
    StartImbueEvents()
    StartDebuffsTicker()
    Build()
end

-- Settings changed: a new container (slider drags settle first).
function M:Refresh()
    if not Supported() then
        return
    end
    S.SafeCall(self.ApplyUnlocked, self)
    if self.rebuildPending then
        return
    end
    self.rebuildPending = true
    C_Timer.After(0.3, function()
        M.rebuildPending = false
        generation = generation + 1
        Build()
    end)
end

function M:IsSupported()
    return Supported()
end
