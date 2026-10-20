local _, S = ...
local M = S:NewModule("FastLoot")

-- Faster loot: with auto loot on, every slot is taken the moment the loot window is ready,
-- instead of the client looting one slot after the other.

local lastLoot = 0

function M:Init()
    S:On("LOOT_READY", function()
        if not S.db.qol.fastLoot then
            return
        end
        if GetCVarBool("autoLootDefault") == IsModifiedClick("AUTOLOOTTOGGLE") then
            return
        end
        if GetTime() - lastLoot < 0.3 then
            return
        end
        lastLoot = GetTime()
        for slot = GetNumLootItems(), 1, -1 do
            LootSlot(slot)
        end
    end)
end
