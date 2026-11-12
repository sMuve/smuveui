local _, S = ...
local M = S:NewModule("AutoOpenClams")

-- Auto-opens any item recognized as a clam the moment it's sitting in the player's bags, leaving
-- every other container (lockboxes, wrapped gifts, quest items, ...) completely untouched.

-- Same compat helper shape as Modules\AutoVendor.lua's own copy - duplicated locally per module,
-- not shared (see its own comment for why).
local function GetContainerItemCompat(bagID, slotID)
    if C_Container and C_Container.GetContainerItemInfo then
        return C_Container.GetContainerItemInfo(bagID, slotID)
    end
    if GetContainerItemInfo then
        local icon, stackCount, locked, quality, readable, lootable, link, isFiltered, noValue, itemID = GetContainerItemInfo(bagID, slotID)
        if link then
            return { hyperlink = link, quality = quality, itemID = itemID, hasNoValue = noValue }
        end
    end
    return nil
end

local function UseContainerItemCompat(bagID, slotID)
    if C_Container and C_Container.UseContainerItem then
        C_Container.UseContainerItem(bagID, slotID)
    elseif UseContainerItem then
        UseContainerItem(bagID, slotID)
    end
end

-- Exact item IDs only, never a name substring match - the feature's own starting premise ("every
-- openable clam has 'clam' in its name") was never relied on; matching by ID sidesteps it
-- entirely. Sourced from Wowhead (not a live /smuve dump - the user couldn't get in-game access
-- when this was filled in); worth a live cross-check with debug.bagClamCandidates
-- (Debug.lua) if any of these turn out wrong or more clam items surface later.
local CLAM_ITEM_IDS = {
    [7973] = "Big-mouth Clam",
    [5524] = "Thick-shelled Clam",
    [5523] = "Small Barnacled Clam",
    [15874] = "Soft-shelled Clam",
}

local function IsClam(info)
    return info ~= nil and info.itemID ~= nil and CLAM_ITEM_IDS[info.itemID] ~= nil
end

local function ScanBagsForClams()
    local matches = {}
    for bagID = 0, NUM_BAG_SLOTS do
        local slots = C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bagID)
            or (GetContainerNumSlots and GetContainerNumSlots(bagID)) or 0
        for slotID = slots, 1, -1 do
            local info = GetContainerItemCompat(bagID, slotID)
            if IsClam(info) then
                table.insert(matches, { bagID = bagID, slotID = slotID })
            end
        end
    end
    return matches
end

-- Pacing (FR-007): one open per tick, same shape as Modules\FastLoot.lua's own lastLoot guard. A
-- skipped slot isn't queued or retried here - using an item removes it from the bag, which fires
-- BAG_UPDATE_DELAYED again on its own, naturally re-scanning and catching anything skipped this
-- pass without needing a queue.
local lastOpen = 0
local OPEN_INTERVAL = 0.3

-- Deferred while in combat (Constitution III); a single flag is enough since PLAYER_REGEN_ENABLED
-- just re-runs the same scan from scratch rather than tracking specific slots.
local pendingOpen = false

local function TryOpen(bagID, slotID)
    if InCombatLockdown() then
        pendingOpen = true
        return
    end
    if GetTime() - lastOpen < OPEN_INTERVAL then
        return
    end
    lastOpen = GetTime()
    UseContainerItemCompat(bagID, slotID)
end

local function OpenClams()
    if not S.db.qol.autoOpenClams then
        return
    end
    for _, slot in ipairs(ScanBagsForClams()) do
        TryOpen(slot.bagID, slot.slotID)
    end
end

function M:Init()
    -- Deliberately BAG_UPDATE_DELAYED, not raw BAG_UPDATE - confirmed on this client (see
    -- Modules\Character.lua) that BAG_UPDATE fires mid-batch while bag contents are still
    -- settling; BAG_UPDATE_DELAYED is the client's own "settled" signal.
    S:On("BAG_UPDATE_DELAYED", OpenClams)
    S:On("PLAYER_REGEN_ENABLED", function()
        if pendingOpen then
            pendingOpen = false
            OpenClams()
        end
    end)
end
