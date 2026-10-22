local _, S = ...
local M = S:NewModule("LootRoll")

-- Group loot roll frames (GroupLootFrame1-4):
--  * Need / Greed / Pass (and Disenchant / Transmog where present) show how many players chose them,
--    as a small number in the button's bottom right corner.
--  * Hovering a button lists who chose it (with their roll, once rolled).
--  * After you rolled, the frame stays up until everyone has chosen or the roll ends.
-- Who chose what comes from the loot history (C_LootHistory), which this client fills per drop.
-- Skipped while BetterGroupLoot is loaded, since it replaces these frames.

local RollState = (Enum and Enum.EncounterLootDropRollState)
    or { NeedMainSpec = 0, NeedOffSpec = 1, Transmog = 2, Greed = 3, NoRoll = 4, Pass = 5 }

local CHOICE_BY_STATE = {
    [RollState.NeedMainSpec] = "need",
    [RollState.NeedOffSpec] = "need",
    [RollState.Transmog] = "transmog",
    [RollState.Greed] = "greed",
    [RollState.NoRoll] = "undecided",
    [RollState.Pass] = "pass",
}

-- Button keys per choice: parentKey first, then the global name suffix of older clients.
local BUTTON_KEYS = {
    need = { "NeedButton", "RollButton" },
    greed = { "GreedButton" },
    pass = { "PassButton" },
    disenchant = { "DisenchantButton" },
    transmog = { "TransmogButton" },
}

local CHOICE_LABELS = {
    need = NEED or "Need",
    greed = GREED or "Greed",
    pass = PASS or "Pass",
    disenchant = ROLL_DISENCHANT or "Disenchant",
    transmog = TRANSMOGRIFY or "Transmog",
}

local frames = {}        -- the client's roll frames
local intercepted = {}   -- frames whose CANCEL_LOOT_ROLL we handle ourselves
local lingering = {}     -- frame -> rollID, frames kept up after you rolled
local rollEnds = {}      -- rollID -> GetTime() at which the roll times out
local dropByRoll = {}    -- rollID -> { encounterID, lootListKey }
local releasing = false
M.frames = frames -- read by /smuve dump (debug.lootRoll)

local function Enabled()
    return S.db.qol.lootRolls
end

local function GetButton(frame, choice)
    local name = frame:GetName()
    -- On this client the buttons live under frame.LootButtonContainer.NeedButton/etc, not
    -- directly on the frame nor as a flat global - confirmed live via /smuve dump (GetButton was
    -- silently returning nil for every button here, which is why counters, hover tooltips and
    -- the disable-while-lingering feature all did nothing). The older lookups are kept too, for
    -- whatever client build actually does use one of them.
    local container = frame.LootButtonContainer
    for _, key in ipairs(BUTTON_KEYS[choice]) do
        local button = frame[key] or (container and container[key]) or (name and _G[name .. key])
        if button then
            return button
        end
    end
end

local function RollIDOf(frame)
    return lingering[frame] or frame.rollID
end

-- Loot history pairing (rolls know nothing about history drops) ------------------------------------

local function ItemIDOf(link)
    return link and tonumber(link:match("item:(%d+)"))
end

-- The history drop of a roll: the same item link (or at least item ID), preferably one that is
-- still being rolled for and not already paired with another open roll.
local function FindDrop(rollID)
    if not (C_LootHistory and C_LootHistory.GetAllEncounterInfos) then
        return nil
    end
    local link = GetLootRollItemLink(rollID)
    if not link then
        return nil
    end
    local itemID = ItemIDOf(link)

    local claimed = {}
    for otherRollID, ref in pairs(dropByRoll) do
        if otherRollID ~= rollID then
            claimed[ref.encounterID .. ":" .. ref.lootListKey] = true
        end
    end

    local best, bestScore = nil, 0
    for _, encounter in ipairs(C_LootHistory.GetAllEncounterInfos() or {}) do
        local encounterID = encounter.encounterID
        for _, drop in ipairs(C_LootHistory.GetSortedDropsForEncounter(encounterID) or {}) do
            if not claimed[encounterID .. ":" .. drop.lootListKey] then
                local score = 0
                if drop.itemHyperlink == link then
                    score = 2
                elseif itemID and ItemIDOf(drop.itemHyperlink) == itemID then
                    score = 1
                end
                if score > 0 and not drop.winner and not drop.allPassed then
                    score = score + 2
                end
                if score > bestScore then
                    best, bestScore = { encounterID = encounterID, lootListKey = drop.lootListKey }, score
                end
            end
        end
    end
    return best
end

local function GetDrop(rollID)
    if not rollID or not (C_LootHistory and C_LootHistory.GetSortedInfoForDrop) then
        return nil
    end
    local ref = dropByRoll[rollID]
    local drop = ref and C_LootHistory.GetSortedInfoForDrop(ref.encounterID, ref.lootListKey)
    if not drop then
        ref = FindDrop(rollID)
        dropByRoll[rollID] = ref
        drop = ref and C_LootHistory.GetSortedInfoForDrop(ref.encounterID, ref.lootListKey)
    end
    return drop
end

-- choice -> list of { name, class, roll, isSelf }, plus .undecided (count) and .finished.
local function GetChoices(rollID)
    local drop = GetDrop(rollID)
    if not drop then
        return nil
    end
    local choices = { need = {}, greed = {}, pass = {}, disenchant = {}, transmog = {}, undecided = {} }
    for _, info in ipairs(drop.rollInfos or {}) do
        local choice = CHOICE_BY_STATE[info.state]
        if choice then
            table.insert(choices[choice], {
                name = info.playerName,
                class = info.playerClass,
                roll = info.roll,
                isSelf = info.isSelf,
            })
        end
    end
    choices.finished = (drop.winner ~= nil) or drop.allPassed == true
    return choices
end

-- Counters ----------------------------------------------------------------------------------------

local function GetCounter(button)
    if button.smuveCount then
        return button.smuveCount
    end
    local count = button:CreateFontString(nil, "OVERLAY")
    count:SetFont(S:GetFont(), 12, "OUTLINE")
    count:SetPoint("BOTTOMRIGHT", button, "BOTTOMRIGHT", 2, -1)
    count:SetJustifyH("RIGHT")
    button.smuveCount = count
    return count
end

local function ClearFrame(frame)
    for choice in pairs(BUTTON_KEYS) do
        local button = GetButton(frame, choice)
        if button then
            if button.smuveCount then
                button.smuveCount:SetText("")
            end
            if button.UnlockHighlight then
                button:UnlockHighlight()
            end
        end
    end
end

-- Lingering ---------------------------------------------------------------------------------------

local function RemoveFrame(frame, rollID)
    if rollID and StaticPopup_Hide then
        StaticPopup_Hide("CONFIRM_LOOT_ROLL", rollID)
    end
    -- This is the one place every rollID's frame finally goes away (lingering or not), so it's
    -- also where the per-roll caches below are retired - otherwise rollEnds/dropByRoll grow for
    -- the rest of the session, since a roll that never lingers never clears them anywhere else.
    if rollID then
        rollEnds[rollID] = nil
        dropByRoll[rollID] = nil
    end
    releasing = true
    if GroupLootContainer_RemoveFrame and GroupLootContainer then
        GroupLootContainer_RemoveFrame(GroupLootContainer, frame)
    else
        frame:Hide()
    end
    releasing = false
end

-- Buttons that were disabled while lingering (StartLinger) and are waiting for combat to end
-- before they can be re-enabled (SetEnabled on these buttons can throw ADDON_ACTION_BLOCKED in
-- combat, the same restriction the bigger health bar runs into on protected unit frame elements).
local pendingEnable = {} -- frame -> true

-- This client's Need/Greed/Pass buttons have no DisabledTexture of their own (confirmed live via
-- /smuve dump - NormalTexture/HighlightTexture/PushedTexture only), so Disable() alone blocks
-- clicks without changing how the button looks at all. Desaturating the normal texture and
-- dimming the button gives it an actual grayed-out look to go with that.
local function SetButtonGrayed(button, grayed)
    local normal = button.GetNormalTexture and button:GetNormalTexture()
    if normal and normal.SetDesaturated then
        normal:SetDesaturated(grayed)
    end
    button:SetAlpha(grayed and 0.4 or 1)
end

local function RestoreButtons(frame)
    -- The cosmetic part (SetButtonGrayed) isn't a protected call like Disable()/SetEnabled() are,
    -- so it always runs right away - only the actual re-enable waits on combat ending below.
    for choice in pairs(BUTTON_KEYS) do
        local button = GetButton(frame, choice)
        if button and button.smuveGrayed then
            SetButtonGrayed(button, false)
            button.smuveGrayed = nil
        end
    end
    if InCombatLockdown() then
        pendingEnable[frame] = true
        return
    end
    pendingEnable[frame] = nil
    for choice in pairs(BUTTON_KEYS) do
        local button = GetButton(frame, choice)
        if button and button.smuveWasEnabled ~= nil then
            button:SetEnabled(button.smuveWasEnabled)
            button.smuveWasEnabled = nil
        end
    end
end

local function Release(frame)
    local rollID = lingering[frame]
    lingering[frame] = nil
    ClearFrame(frame)
    RestoreButtons(frame)
    if rollID then
        dropByRoll[rollID] = nil
    end
    RemoveFrame(frame, rollID)
end

-- After your own roll the frame stays while others are still choosing.
local function ShouldLinger(rollID)
    if not Enabled() or not S.db.qol.lootRollLinger or not rollID then
        return false
    end
    if rollEnds[rollID] and GetTime() >= rollEnds[rollID] then
        return false
    end
    local choices = GetChoices(rollID)
    return choices ~= nil and not choices.finished and #choices.undecided > 0
end

local function StartLinger(frame, rollID)
    lingering[frame] = rollID
    -- The gray-out (SetButtonGrayed) always applies right away, combat or not - it's plain
    -- texture/alpha calls, not the protected kind. Only the actual Disable() below - this almost
    -- always happens mid-fight (you rolled on a boss drop, others haven't yet) - needs combat to
    -- end first, the same protected-call restriction Modules\UnitFrames.lua's bigger health bar
    -- runs into; left clickable in the meantime, a second click just has nothing left to confirm.
    for choice in pairs(BUTTON_KEYS) do
        local button = GetButton(frame, choice)
        if button then
            SetButtonGrayed(button, true)
            button.smuveGrayed = true
        end
    end
    if InCombatLockdown() then
        return
    end
    for choice in pairs(BUTTON_KEYS) do
        local button = GetButton(frame, choice)
        if button and button.IsEnabled then
            button.smuveWasEnabled = button:IsEnabled()
            button:Disable()
        end
    end
end

-- Update ------------------------------------------------------------------------------------------

local function UpdateFrame(frame)
    local rollID = RollIDOf(frame)
    if not rollID or not frame:IsShown() then
        return
    end
    if not Enabled() then
        ClearFrame(frame)
        return
    end

    local choices = GetChoices(rollID)
    for choice in pairs(BUTTON_KEYS) do
        local button = GetButton(frame, choice)
        if button then
            local list = choices and choices[choice]
            local counter = GetCounter(button)
            counter:SetText(list and #list > 0 and #list or "")
            if lingering[frame] and list then
                local chosen = false
                for _, roller in ipairs(list) do
                    chosen = chosen or roller.isSelf
                end
                if chosen then
                    button:LockHighlight()
                end
            end
        end
    end

    if lingering[frame] then
        local timedOut = rollEnds[rollID] and GetTime() >= rollEnds[rollID]
        if timedOut or not choices or choices.finished or #choices.undecided == 0 then
            Release(frame)
        end
    end
end

function M:UpdateAll()
    for _, frame in ipairs(frames) do
        S.SafeCall(UpdateFrame, frame)
    end
end

-- Tooltip -----------------------------------------------------------------------------------------

local function ColorName(name, class)
    local color = class and (C_ClassColor and C_ClassColor.GetClassColor(class) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]))
    if color and color.WrapTextInColorCode then
        return color:WrapTextInColorCode(name)
    elseif color then
        return string.format("|cff%02x%02x%02x%s|r", color.r * 255, color.g * 255, color.b * 255, name)
    end
    return name
end

local function OnButtonEnter(button)
    if not Enabled() then
        return
    end
    local frame = button.smuveFrame
    local choices = GetChoices(RollIDOf(frame))
    local list = choices and choices[button.smuveChoice]
    if not list or #list == 0 then
        return
    end
    if GameTooltip:GetOwner() ~= button then
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
        GameTooltip:SetText(CHOICE_LABELS[button.smuveChoice])
    end
    GameTooltip:AddLine(" ")
    for _, roller in ipairs(list) do
        local name = ColorName(roller.name or UNKNOWN or "?", roller.class)
        if roller.roll then
            GameTooltip:AddDoubleLine(name, roller.roll, 1, 1, 1, 1, 1, 1)
        else
            GameTooltip:AddLine(name, 1, 1, 1)
        end
    end
    GameTooltip:Show()
end

local function OnButtonLeave(button)
    if GameTooltip:GetOwner() == button then
        GameTooltip:Hide()
    end
end

-- Moving the window ---------------------------------------------------------------------------
-- Edit Mode doesn't offer the loot roll window at all, so this is a plain drag-while-unlocked
-- toggle instead - but GroupLootContainer itself (what every GroupLootFrame is actually anchored
-- to - confirmed live, GroupLootFrame1 is anchored to GroupLootContainer, not to UIParent) sizes
-- to its content, so with no roll active it's zero-sized and has nothing to grab. Same fix as the
-- player buffs bar (Modules\Auras.lua): a small always-there handle frame of our own, anchored to
-- UIParent at the saved position, with GroupLootContainer anchored to IT instead of to UIParent
-- directly - so dragging the handle (visible/grabbable even with no roll showing) moves the real
-- window right along with it.

local DEFAULT_POS = { point = "CENTER", x = 0, y = 150 }
local HANDLE_SIZE = 180 -- wide enough to read the label under it; height is cosmetic only

local handle
local unlockLabel
local unlockBackdrop

local function RestorePosition()
    if not handle then
        return
    end
    local pos = S.db.qol.lootRollPosition or DEFAULT_POS
    handle:ClearAllPoints()
    handle:SetPoint(pos.point, UIParent, pos.point, pos.x, pos.y)
    if GroupLootContainer then
        GroupLootContainer:ClearAllPoints()
        GroupLootContainer:SetPoint(pos.point, handle, pos.point, 0, 0)
    end
end

local function OnDragStart(self)
    self:StartMoving()
end

local function OnDragStop(self)
    self:StopMovingOrSizing()
    local point, _, _, x, y = self:GetPoint(1)
    if point and not S.IsSecret(point) then
        S.db.qol.lootRollPosition = { point = point, x = x, y = y }
    end
    -- The container's own anchor point has to follow the handle's possibly-new point too, not
    -- just its x/y - RestorePosition re-anchors both from the same saved position.
    RestorePosition()
end

local function CreateHandle()
    if handle then
        return
    end
    -- GroupLootContainer inherits BottomManagedFrameTemplate - Blizzard's own alert-frame layout
    -- manager (Blizzard_ManagedFrameSystem) re-adds it to its managed container and re-anchors it
    -- (ManagedFrameContainerMixin:AddManagedFrame, called from the container's own OnShow) every
    -- single time it's shown, silently undoing whatever point RestorePosition just set - confirmed
    -- live, the roll window kept opening at its default spot regardless. AddManagedFrame checks
    -- this flag first and bails out immediately if it's set, which is the documented way to opt a
    -- frame out of that system entirely.
    if GroupLootContainer then
        GroupLootContainer.ignoreFramePositionManager = true
    end
    handle = CreateFrame("Frame", nil, UIParent)
    handle:SetSize(HANDLE_SIZE, HANDLE_SIZE * 0.3)
    handle:SetClampedToScreen(true)
    handle:SetScript("OnDragStart", OnDragStart)
    handle:SetScript("OnDragStop", OnDragStop)
    RestorePosition()
end

function M:ApplyUnlocked()
    if not handle then
        return
    end
    local unlocked = S.db.qol.lootRollUnlocked
    handle:SetMovable(true)
    handle:EnableMouse(unlocked)
    if unlocked then
        handle:RegisterForDrag("LeftButton")
    else
        handle:RegisterForDrag()
    end
    if unlocked then
        if not unlockLabel then
            unlockLabel = handle:CreateFontString(nil, "OVERLAY")
            unlockLabel:SetFont(S:GetFont(), 12, "OUTLINE")
            unlockLabel:SetPoint("BOTTOM", handle, "TOP", 0, 4)
            unlockLabel:SetTextColor(1, 0.82, 0)
            unlockLabel:SetText("Loot roll window - drag to move")
        end
        if not unlockBackdrop then
            -- Otherwise invisible with no roll active - hard to even find to drag.
            unlockBackdrop = handle:CreateTexture(nil, "BACKGROUND")
            unlockBackdrop:SetAllPoints(handle)
            unlockBackdrop:SetColorTexture(0, 0.6, 1, 0.3)
        end
        unlockLabel:Show()
        unlockBackdrop:Show()
    else
        if unlockLabel then
            unlockLabel:Hide()
        end
        if unlockBackdrop then
            unlockBackdrop:Hide()
        end
    end
end

-- Setup -------------------------------------------------------------------------------------------

local function SetupFrame(frame)
    table.insert(frames, frame)

    for choice in pairs(BUTTON_KEYS) do
        local button = GetButton(frame, choice)
        if button then
            button.smuveFrame = frame
            button.smuveChoice = choice
            button:HookScript("OnEnter", OnButtonEnter)
            button:HookScript("OnLeave", OnButtonLeave)
            -- Built now (login, out of combat) instead of on the first roll: CreateFontString on
            -- these buttons is the same kind of protected call combat can block.
            GetCounter(button)
        end
    end

    -- Keeps the timer bar running on the original roll time while the frame lingers.
    local timer = frame.Timer or _G[(frame:GetName() or "") .. "Timer"]
    if timer then
        timer:HookScript("OnUpdate", function(self)
            local rollID = lingering[frame]
            if rollID and rollEnds[rollID] then
                local _, max = self:GetMinMaxValues()
                local left = math.max(0, rollEnds[rollID] - GetTime()) * 1000
                if max and max > 0 and max < 1000 then
                    left = left / 1000 -- the bar runs in seconds on this client
                end
                self:SetValue(left)
            end
        end)
    end

    frame:HookScript("OnShow", function()
        C_Timer.After(0, function() UpdateFrame(frame) end)
    end)
    frame:HookScript("OnHide", function()
        if lingering[frame] then
            lingering[frame] = nil
        end
        ClearFrame(frame)
    end)

    -- The frame normally closes as soon as you rolled; that event is handled here instead so the
    -- frame can stay while the others are still choosing.
    if frame:IsEventRegistered("CANCEL_LOOT_ROLL") then
        frame:UnregisterEvent("CANCEL_LOOT_ROLL")
        intercepted[frame] = true
    end
end

local function OnCancelRoll(_, rollID)
    for _, frame in ipairs(frames) do
        if intercepted[frame] and frame.rollID == rollID and frame:IsShown() and not lingering[frame] then
            if ShouldLinger(rollID) then
                StartLinger(frame, rollID)
                UpdateFrame(frame)
            else
                RemoveFrame(frame, rollID)
            end
        end
    end
end

-- Clients that close the frames from the container instead: put the frame right back.
local function OnContainerRemove(container, frame)
    if releasing or intercepted[frame] or lingering[frame] or not frame.rollID then
        return
    end
    local rollID = frame.rollID
    if ShouldLinger(rollID) and GroupLootContainer_AddFrame then
        StartLinger(frame, rollID)
        GroupLootContainer_AddFrame(container, frame)
        frame:Show()
        UpdateFrame(frame)
    end
end

function M:Init()
    if S.IsAddOnLoaded("BetterGroupLoot") then
        return
    end
    S.db.qol.lootRollUnlocked = false -- always off after a reload

    for i = 1, NUM_GROUP_LOOT_FRAMES or 4 do
        local frame = _G["GroupLootFrame" .. i]
        if frame then
            -- One frame throwing here (e.g. CreateFontString being a protected call at a bad
            -- moment, the same restriction noted on GetCounter above) used to take out every
            -- later frame's setup and all of Init()'s event registrations below with it, since
            -- nothing caught it until S.SafeCall at the very top of the whole module's Init.
            S.SafeCall(SetupFrame, frame)
        end
    end
    if #frames == 0 then
        return
    end

    if GroupLootContainer_RemoveFrame then
        hooksecurefunc("GroupLootContainer_RemoveFrame", OnContainerRemove)
    end

    if GroupLootContainer then
        CreateHandle()
        M:ApplyUnlocked()
    end

    S:On("START_LOOT_ROLL", function(_, rollID, rollTime)
        if rollID and rollTime then
            rollEnds[rollID] = GetTime() + rollTime / 1000
        end
        -- All frames busy with lingering rolls: make room for the new one.
        local free = false
        for _, frame in ipairs(frames) do
            free = free or not frame:IsShown()
        end
        if not free then
            for _, frame in ipairs(frames) do
                if lingering[frame] then
                    Release(frame)
                    if GroupLootContainer_OpenNewFrame then
                        C_Timer.After(0, function()
                            for _, other in ipairs(frames) do
                                if other.rollID == rollID and other:IsShown() then
                                    return
                                end
                            end
                            GroupLootContainer_OpenNewFrame(rollID, rollTime)
                        end)
                    end
                    break
                end
            end
        end
        C_Timer.After(0.1, function() M:UpdateAll() end)
    end)
    S:On("CANCEL_LOOT_ROLL", OnCancelRoll)
    S:On("CANCEL_ALL_LOOT_ROLLS", function()
        for _, frame in ipairs(frames) do
            if lingering[frame] then
                Release(frame)
            end
        end
    end)
    for _, event in ipairs({ "LOOT_HISTORY_UPDATE_DROP", "LOOT_HISTORY_UPDATE_ENCOUNTER", "LOOT_HISTORY_CLEAR_HISTORY" }) do
        pcall(S.On, S, event, function() M:UpdateAll() end)
    end
    S:On("PLAYER_REGEN_ENABLED", function()
        for frame in pairs(pendingEnable) do
            RestoreButtons(frame)
        end
    end)

    -- Rolls already running after a /reload.
    if GetActiveLootRollIDs then
        for _, rollID in ipairs(GetActiveLootRollIDs() or {}) do
            local left = GetLootRollTimeLeft and GetLootRollTimeLeft(rollID)
            if left then
                rollEnds[rollID] = GetTime() + left / 1000
            end
        end
    end

    -- Safety net for timeouts and late history data.
    C_Timer.NewTicker(0.5, function()
        for _, frame in ipairs(frames) do
            if frame:IsShown() then
                S.SafeCall(UpdateFrame, frame)
            end
        end
    end)
end

function M:Refresh()
    self:UpdateAll()
    S.SafeCall(self.ApplyUnlocked, self)
end
