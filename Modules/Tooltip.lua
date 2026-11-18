local _, S = ...
local M = S:NewModule("Tooltip")

-- Tooltips: an optional dark look (near black background, darkened border) and player names in
-- their class color. Both have their own options, independent of the general dark mode.

local TOOLTIPS = {
    "GameTooltip", "ItemRefTooltip", "ShoppingTooltip1", "ShoppingTooltip2", "ItemRefShoppingTooltip1",
    "ItemRefShoppingTooltip2", "EmbeddedItemTooltip", "WorldMapTooltip", "FriendsTooltip",
}

-- A direct NineSlice:SetBorderColor() RGB value (see DarkenBorder below) - 0.25 matches what the
-- old per-texture S:Darken loop this replaced actually produced and had already been confirmed to
-- look right.
local BORDER_COLOR = 0.25

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

-- NineSlice:SetBorderColor(r,g,b,a) - the blessed API (confirmed against muleyoUI's own tooltip
-- skin, Modules/Forever/Tooltips/Style.lua, same client), not per-texture SetVertexColor tinting.
-- NineSlicePanelMixin remembers whatever color this last set and re-applies it itself whenever it
-- redoes its own layout (e.g. SharedTooltip_SetBackdropStyle) - canonical, Blizzard-tracked state,
-- unlike recoloring the raw child textures directly, which Blizzard's own layout-reapply code has
-- no knowledge of and will happily overwrite.
local function DarkenBorder(tooltip)
    local nineSlice = tooltip.NineSlice
    if not nineSlice or tooltip:IsForbidden() then
        return
    end
    if nineSlice.SetBorderColor then
        nineSlice:SetBorderColor(BORDER_COLOR, BORDER_COLOR, BORDER_COLOR, 1)
    else
        -- Fallback for a tooltip whose NineSlice doesn't expose the blessed API for some reason -
        -- the old per-texture tint, better than nothing even though it can't self-heal the same way.
        for key, region in pairs(nineSlice) do
            if key ~= "Center" and type(region) == "table" and region.IsObjectType and region:IsObjectType("Texture") then
                S:Darken(region, 0.15, DarkEnabled)
            end
        end
    end
end

local function RestoreBorder(tooltip)
    local nineSlice = tooltip.NineSlice
    if nineSlice and nineSlice.SetBorderColor then
        nineSlice:SetBorderColor(1, 1, 1, 1)
    end
end

-- A unit frame's own aura tooltip (hovering a buff/debuff icon on the target, party or raid
-- frame) does NOT go through GameTooltip on this client at all - it's a separate Blizzard
-- subsystem, AuraContainerInbound, with its own backdrop entirely (confirmed against muleyoUI's
-- Forever-client theme, Modules/Forever/General/Theme/Tooltips.lua, StyleAuraTooltip()): its own
-- SetTooltipBackdrop() API, a plain old-style backdrop table (edgeFile/bgFile), not NineSlice/atlas
-- pieces - a different rendering path, not a cosmetic variant of DarkenBorder above.
local AURA_TOOLTIP_BACKDROP = {
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = false,
    tileEdge = false,
    tileSize = 16,
    edgeSize = 16,
    insets = { left = 3, right = 3, top = 3, bottom = 3 },
}

local function StyleAuraTooltip()
    if not (AuraContainerInbound and AuraContainerInbound.SetTooltipBackdrop) then
        return
    end
    if DarkEnabled() then
        AuraContainerInbound.SetTooltipBackdrop({
            backdropInfo = AURA_TOOLTIP_BACKDROP,
            centerColor = CreateColor(0, 0, 0, 0.9),
            borderColor = CreateColor(BORDER_COLOR, BORDER_COLOR, BORDER_COLOR, 1),
        })
    else
        AuraContainerInbound.SetTooltipBackdrop({
            backdropInfo = AURA_TOOLTIP_BACKDROP,
            centerColor = CreateColor(1, 1, 1, 1),
            borderColor = CreateColor(1, 1, 1, 1),
        })
    end
end

-- tooltip -> true once its own OnShow hook is installed.
local handled = setmetatable({}, { __mode = "k" })

local function SetupTooltip(tooltip)
    if not tooltip or tooltip:IsForbidden() or not tooltip.NineSlice then
        return
    end
    if not handled[tooltip] then
        handled[tooltip] = true
        -- Still needed for the background: unlike SetBorderColor (see DarkenBorder above),
        -- SetCenterColor isn't bookkept/reapplied by Blizzard on its own relayouts, so this has to
        -- keep reasserting itself on every reshow.
        tooltip:HookScript("OnShow", DarkenBackground)
    end
    if DarkEnabled() then
        DarkenBorder(tooltip)
        DarkenBackground(tooltip)
    else
        RestoreBorder(tooltip)
        RestoreBackground(tooltip)
    end
end

function M:StyleTooltips()
    for _, name in ipairs(TOOLTIPS) do
        SetupTooltip(_G[name])
    end
    StyleAuraTooltip()
    if not self.backdropHooked and SharedTooltip_SetBackdropStyle then
        -- Only the background still needs this - DarkenBorder/SetBorderColor no longer does (see
        -- its own comment above): Blizzard reapplies that color itself on every relayout now.
        -- SetCenterColor isn't bookkept the same way, so this still re-asserts it after whatever
        -- content-driven relayout SharedTooltip_SetBackdropStyle is part of.
        hooksecurefunc("SharedTooltip_SetBackdropStyle", DarkenBackground)
        self.backdropHooked = true
    end
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
