local _, S = ...
local M = S:NewModule("QuestSparkle")

-- Quest loot sparkle: the client only shows its loot-glow/outline effect on interactable items
-- (quest items among them) while the "Interactive Highlight" graphics option is set to show it,
-- or while holding the interact-highlight key. These CVars force it to always show instead -
-- confirmed live via /dump GetCVar(...), same as Modules\Nameplates.lua's FRIENDLY_CVARS.
local CVARS = {
    "outlineModeShowLootEffectWhenDisabled",
    "graphicsOutlineMode",
    "OutlineEngineMode",
    "raidGraphicsOutlineMode",
    "RAIDOutlineEngineMode",
}

local function Apply()
    local on = S.db.qol.questSparkle
    for _, cvar in ipairs(CVARS) do
        SetCVar(cvar, on and "1" or "0")
    end
end

function M:Init()
    Apply()
end

function M:Refresh()
    Apply()
end
