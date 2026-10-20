local _, S = ...
local M = S:NewModule("Tooltip")

-- Tooltips: an optional dark look (near black background, darkened border) and player names in
-- their class color. Both have their own options, independent of the general dark mode.

local TOOLTIPS = {
    "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "ItemRefShoppingTooltip1",
    "ItemRefShoppingTooltip2", "EmbeddedItemTooltip", "WorldMapTooltip", "FriendsTooltip",
}

local BORDER_OFFSET = 0.15 -- the border stays a little lighter than the background

local function DarkEnabled()
    return S.db.tooltip.dark
end

-- Dark look ----------------------------------------------------------------------------------------

local function DarkenBackground(tooltip)
    if not DarkEnabled() or not tooltip or tooltip:IsForbidden() then
        return
    end
    local nineSlice = tooltip.NineSlice
    if nineSlice and nineSlice.SetCenterColor then
        nineSlice:SetCenterColor(0, 0, 0, 0.9)
    elseif tooltip.SetBackdropColor then
        tooltip:SetBackdropColor(0, 0, 0, 0.9)
    end
end

local function RestoreBackground(tooltip)
    local nineSlice = tooltip.NineSlice
    if nineSlice and nineSlice.SetCenterColor and TOOLTIP_DEFAULT_BACKGROUND_COLOR then
        local r, g, b = TOOLTIP_DEFAULT_BACKGROUND_COLOR:GetRGB()
        nineSlice:SetCenterColor(r, g, b, 1)
    end
end

function M:StyleTooltips()
    for _, name in ipairs(TOOLTIPS) do
        local tooltip = _G[name]
        if tooltip and tooltip.NineSlice and not tooltip:IsForbidden() then
            for key, region in pairs(tooltip.NineSlice) do
                if key ~= "Center" and type(region) == "table" and region.IsObjectType and region:IsObjectType("Texture") then
                    S:Darken(region, BORDER_OFFSET, DarkEnabled)
                end
            end
            if not self.hooked then
                tooltip:HookScript("OnShow", DarkenBackground)
            end
            if DarkEnabled() then
                DarkenBackground(tooltip)
            else
                RestoreBackground(tooltip)
            end
        end
    end
    if not self.hooked and SharedTooltip_SetBackdropStyle then
        hooksecurefunc("SharedTooltip_SetBackdropStyle", DarkenBackground)
    end
    self.hooked = true
end

-- Class colored names ------------------------------------------------------------------------------

-- The class word in the level line ("Level 28 Dwarf Shaman"), in the class color.
local function ColorClassWord(tooltip, className, color)
    local name = tooltip:GetName()
    if not name or not className or S.IsSecret(className) then
        return
    end
    local hex = string.format("ff%02x%02x%02x", color.r * 255, color.g * 255, color.b * 255)
    for i = 2, tooltip:NumLines() do
        local line = _G[name .. "TextLeft" .. i]
        local text = line and line:GetText()
        if type(text) == "string" and not S.IsSecret(text) then
            local first, last = text:find(className, 1, true)
            -- Lines that are already colored (e.g. by another addon) are left alone.
            if first and not text:find("|c", 1, true) then
                line:SetText(text:sub(1, first - 1) .. "|c" .. hex .. className .. "|r" .. text:sub(last + 1))
                return
            end
        end
    end
end

local function ColorName(tooltip)
    local db = S.db.tooltip
    if not (db.classColorNames or db.classColorClass) or not tooltip or tooltip:IsForbidden() or not tooltip.GetUnit then
        return
    end
    local _, unit = tooltip:GetUnit()
    if not unit or S.IsSecret(unit) then
        return
    end
    local isPlayer = UnitIsPlayer(unit)
    if S.IsSecret(isPlayer) or not isPlayer then
        return
    end
    local className, class = UnitClass(unit)
    if not class or S.IsSecret(class) then
        return
    end
    local color = (C_ClassColor and C_ClassColor.GetClassColor(class)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
    if not color then
        return
    end
    local line = tooltip:GetName() and _G[tooltip:GetName() .. "TextLeft1"]
    if db.classColorNames and line then
        line:SetTextColor(color.r, color.g, color.b)
    end
    if db.classColorClass then
        ColorClassWord(tooltip, className, color)
    end
end

local function SafeColorName(tooltip)
    S.SafeCall(ColorName, tooltip)
end

-- Module -------------------------------------------------------------------------------------------

function M:Init()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, SafeColorName)
    elseif GameTooltip:HasScript("OnTooltipSetUnit") then
        GameTooltip:HookScript("OnTooltipSetUnit", SafeColorName)
    end
    S:On("PLAYER_ENTERING_WORLD", function()
        M:StyleTooltips()
    end)
end

function M:Refresh()
    self:StyleTooltips()
    S:RepaintAll()
end
