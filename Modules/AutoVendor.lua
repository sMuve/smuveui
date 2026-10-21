local _, S = ...
local M = S:NewModule("AutoVendor")

-- Auto sell junk and auto repair, both on MERCHANT_SHOW: each setting is read fresh so toggling
-- it off takes effect on the next vendor visit without needing a reload.

-- Same compat helper as Modules\Character.lua's GetContainerItemCompat, duplicated rather than
-- shared - every module here that touches bags/class colors keeps its own small copy of this
-- kind of lookup (see Modules\LootRoll.lua, Modules\Tooltip.lua for the class color version).
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

local POOR_QUALITY = (Enum.ItemQuality and Enum.ItemQuality.Poor) or 0

local function GetItemInfoCompat(link)
    if C_Item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(link)
    end
    return GetItemInfo(link)
end

-- Reverse slot order: selling shifts later slots down, so a forward loop would skip items.
local function SellJunk()
    local revenue = 0
    for bagID = 0, NUM_BAG_SLOTS do
        local slots = C_Container and C_Container.GetContainerNumSlots and C_Container.GetContainerNumSlots(bagID)
            or (GetContainerNumSlots and GetContainerNumSlots(bagID)) or 0
        for slotID = slots, 1, -1 do
            local info = GetContainerItemCompat(bagID, slotID)
            local quality = info and info.quality
            -- not S.IsSecret(quality) must come first: `and` short-circuits left to right, so
            -- quality == POOR_QUALITY never runs on a secret value (would throw outright).
            if info and info.hyperlink and not info.hasNoValue and not S.IsSecret(quality) and quality == POOR_QUALITY then
                local _, _, _, _, _, _, _, _, _, _, vendorPrice = GetItemInfoCompat(info.hyperlink)
                if vendorPrice and vendorPrice > 0 then
                    revenue = revenue + vendorPrice * (info.stackCount or 1)
                end
                if C_Container and C_Container.UseContainerItem then
                    C_Container.UseContainerItem(bagID, slotID)
                elseif UseContainerItem then
                    UseContainerItem(bagID, slotID)
                end
            end
        end
    end
    if revenue > 0 then
        S.Print("Sold junk for " .. GetMoneyString(revenue, true))
    end
end

local function RepairAll()
    if not CanMerchantRepair or not CanMerchantRepair() then
        return
    end
    local cost, canRepair = GetRepairAllCost()
    if not canRepair or not cost or cost <= 0 then
        return
    end
    local useGuildFunds = CanGuildBankRepair and CanGuildBankRepair() and GetGuildBankWithdrawMoney
        and GetGuildBankWithdrawMoney() >= cost
    RepairAllItems(useGuildFunds)
    S.Print("Repaired for " .. GetMoneyString(cost, true))
end

function M:Init()
    S:On("MERCHANT_SHOW", function()
        if S.db.qol.autoSellJunk then
            S.SafeCall(SellJunk)
        end
        if S.db.qol.autoRepair then
            S.SafeCall(RepairAll)
        end
    end)
end
