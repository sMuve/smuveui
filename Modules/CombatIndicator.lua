local _, S = ...
local M = S:NewModule("CombatIndicator")

-- A brief "+COMBAT" / "-COMBAT" flash dead center of the screen on entering/leaving combat.

local HOLD = 2 -- seconds the text stays up before disappearing
local RED = { 0.9, 0.15, 0.15 }
local GREEN = { 0.15, 0.85, 0.15 }

local text
local generation = 0 -- bumped on every flash, so an older pending hide doesn't cut a newer one off

local function EnsureText()
    if text then
        return text
    end
    text = UIParent:CreateFontString(nil, "OVERLAY")
    text:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    text:SetFont(S:GetFont(), 20, "OUTLINE")
    text:Hide()
    return text
end

local function Flash(label, color)
    if not S.db.qol.combatIndicator then
        return
    end
    local t = EnsureText()
    t:SetText(label)
    t:SetTextColor(color[1], color[2], color[3], 1)
    t:Show()
    generation = generation + 1
    local mine = generation
    C_Timer.After(HOLD, function()
        if mine == generation then
            t:Hide()
        end
    end)
end

function M:Init()
    S:On("PLAYER_REGEN_DISABLED", function()
        Flash("+COMBAT", RED)
    end)
    S:On("PLAYER_REGEN_ENABLED", function()
        Flash("-COMBAT", GREEN)
    end)
end
