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

-- The enchant data GetWeaponEnchantInfo returns never says WHICH imbue it is, only that it's one
-- (enchantType == Imbue) - but only Rogues apply poisons and only Shamans apply the other kind of
-- weapon imbue (Windfury/Flametongue/Frostbrand/Rockbiter), so the player's own class is a simple,
-- reliable stand-in for "is this specifically a poison" without needing a spell/enchant ID list.
local _, PLAYER_CLASS = UnitClass("player")

local ICON_SIZE = 40
local SPACING = 2
local DEBUFF_GAP = 10 -- between the buffs area's bottom edge and the debuffs below it
local MAX_BUFFS = BUFF_MAX_DISPLAY or 32
local MAX_DEBUFFS = DEBUFF_MAX_DISPLAY or 16
-- Only used below, for debuffs' default starting position: that many empty buff rows' worth of
-- distance, so a fresh install's debuffs bar doesn't start awkwardly close to the buffs bar above
-- it (a typical buffs bar is within this many rows most of the time).
local MIN_BUFF_ROWS = 3

-- Buffs and debuffs each get their own saved/draggable position (mirrors how
-- Modules\UnitAuras.lua already treats the target/focus frames' buff and debuff rows as two
-- independent blocks) - they no longer track each other live, so dragging either bar only ever
-- moves that one; debuffs' default position just starts where it visually used to sit.
local DEFAULT_POS = {
    buffs = { point = "TOPRIGHT", x = -275, y = -20 },
    debuffs = { point = "TOPRIGHT", x = -275, y = -20 - (MIN_BUFF_ROWS * (ICON_SIZE + SPACING) + DEBUFF_GAP) },
}

local function DB()
    return S.db.appearance
end

local function Supported()
    return AF and CreateFilterString and FlowDirection and AuraContainerSortMethod ~= nil
        and S.modules.Nameplates and S.modules.Nameplates.InitAuraButton ~= nil
end

local function Enabled()
    return Supported() and DB().auraEnabled
end

local parents = {}    -- "buffs" | "debuffs" -> our own movable anchor frame
local containers = {} -- "buffs" | "debuffs" -> aura container
M.containers = containers -- read by /smuve dump
local imbueCells = {} -- cell index -> { button, icon, cooldown, stack, timer, dur, binding } - declared
                       -- up here (ApplyUnlocked, below, needs to reach it) rather than down with the
                       -- rest of the imbue-cell code further down this file

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
    -- Weapon imbue cells sit directly on top of the buffs parent's own corner (same screen
    -- position as the first one, leading the bar) and, being Buttons with their own mouse always
    -- on for the tooltip, intercept the click before it ever reaches the parent's own drag
    -- handling - confirmed live, the mover only worked with no imbue active. Turned off for the
    -- same reason the backdrop/label only show while unlocked: nothing worth tooltipping while
    -- actively dragging bars around anyway.
    for _, cell in pairs(imbueCells) do
        cell.button:EnableMouse(not unlocked)
    end
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
                label:SetText(key:sub(1, 1):upper() .. key:sub(2) .. " - drag to move")
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

-- key: "buffs" or "debuffs". Clears the saved position regardless of whether the bar currently
-- exists (so a later re-enable/reload starts from the default too), and repositions it live if it
-- does.
function M:ResetPosition(key)
    DB()["aura" .. key .. "Pos"] = nil
    local parent = parents[key]
    local default = DEFAULT_POS[key]
    if parent and default then
        parent:ClearAllPoints()
        parent:SetPoint(default.point, UIParent, default.point, default.x, default.y)
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

-- anchorTo: that aura's own parent frame (buffs or debuffs - see CreateParent/DEFAULT_POS above).
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
    container:SetPoint("TOPRIGHT", anchorTo, "TOPRIGHT", 0, 0)
    return container
end

-- Weapon imbue cells --------------------------------------------------------------------------

local function Readable(v)
    return v ~= nil and not S.IsSecret(v)
end

local imbueTrack = {}  -- weapon slot -> { id, endTime, total }, to know when a swipe restarts
local shownImbues = {} -- cell index -> { inv, icon, charges, endTime, total }

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
    -- Purple, not the usual black border - tells an imbue cell apart from a regular buff at a
    -- glance - green for a Rogue's poison (same green Nameplates.lua's own TYPE_COLORS.Poison
    -- uses), purple for every other kind (same purple as its own TYPE_COLORS.Curse). Both reused
    -- directly rather than sharing a constant (duplicated per module, as usual).
    local edges = S.modules.Nameplates.AddBlackBorder(overlay, button, S.modules.Nameplates.BORDER_SIZE)
    local r, g, b = 0.60, 0.00, 1.00
    if PLAYER_CLASS == "ROGUE" then
        r, g, b = 0.00, 0.60, 0.00
    end
    for _, edge in ipairs(edges) do
        edge:SetVertexColor(r, g, b)
    end

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

    -- Matches ApplyUnlocked's own EnableMouse toggle for every existing cell - a cell created
    -- later (a weapon swap) while already unlocked must start the same way, not default to on.
    button:EnableMouse(not DB().auraBarsUnlocked)
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
    -- Same scale as the buffs container itself (containers.buffs:SetScale, in CreateAuraContainer)
    -- - SetPoint's own offset is already auto-scaled by the calling frame's effective scale, the
    -- same reason containers.buffs' own anchor shift below never needed to account for scale by
    -- hand either, so step itself stays unscaled.
    local scale = DB().auraBuffsScale or 1
    for i = 1, n do
        local cell = imbueCells[i]
        if not cell then
            cell = CreateImbueCell(anchor)
            imbueCells[i] = cell
        end
        if cell.button:GetParent() ~= anchor then
            cell.button:SetParent(anchor)
        end
        cell.button:SetScale(scale)
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

local generation = 0

local function Build()
    for _, key in ipairs({ "buffs", "debuffs" }) do
        if not parents[key] then
            CreateParent(key)
        end
        local anchorTo = parents[key]
        if containers[key] and containers[key].generation ~= generation then
            containers[key]:SetEnabled(false)
            containers[key]:Hide()
            containers[key] = nil
        end
        if not containers[key] then
            local container = CreateAuraContainer(anchorTo, key == "debuffs")
            container.generation = generation
            containers[key] = container
        end
    end
    LayoutImbues()
    M:ApplyUnlocked()
end

function M:Init()
    if not Enabled() then
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
    Build()
end

-- Settings changed: a new container (slider drags settle first).
function M:Refresh()
    if not Enabled() then
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
