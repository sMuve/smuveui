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

local ICON_SIZE = 30
local SPACING = 2
local DEBUFF_GAP = 10 -- between the buffs container's bottom edge and the debuffs below it
local MAX_BUFFS = BUFF_MAX_DISPLAY or 32
local MAX_DEBUFFS = DEBUFF_MAX_DISPLAY or 16

-- Only buffs gets a saved/draggable position; debuffs is anchored to its container below instead
-- (see CreateAuraContainer) so a bigger buffs scale, or buffs simply wrapping to another row,
-- carries debuffs down with it live rather than needing a second position to keep in sync.
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
    container:AddAuraGroup(isDebuff and "Debuffs" or "Buffs", CreateFilterString(isDebuff and AF.Harmful or AF.Helpful), {
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
    -- Temporary weapon enchants show alongside buffs, same as the client's own BuffFrame.
    if not isDebuff and AuraContainerItemEnchantmentSlot then
        for _, slot in ipairs({ AuraContainerItemEnchantmentSlot.MainHand, AuraContainerItemEnchantmentSlot.OffHand,
            AuraContainerItemEnchantmentSlot.Ranged }) do
            container:AddItemEnchantment(slot, {
                initializeFrame = function(button)
                    S.modules.Nameplates.InitAuraButton(button, ICON_SIZE, true, style)
                end,
            })
        end
    end
    container:SetEnabled(true)
    container:ClearAllPoints()
    if isDebuff then
        -- Below the buffs container's actual bottom edge, a live anchor rather than a one-time
        -- measurement - carries debuffs down automatically when buffs grows (a bigger scale, or
        -- just wrapping to another row once there are enough of them), instead of needing a
        -- second saved position to keep in sync with the first by hand.
        container:SetPoint("TOPRIGHT", anchorTo, "BOTTOMRIGHT", 0, -DEBUFF_GAP)
    else
        container:SetPoint("TOPRIGHT", anchorTo, "TOPRIGHT", 0, 0)
    end
    return container
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
