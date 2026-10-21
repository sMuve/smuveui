local _, S = ...
local M = S:NewModule("UnitFrames")

-- Player, target, focus and target-of-target frames:
--   * class colored health bars and names (players only; NPCs keep the client's colors),
--   * the own-name fix (the client leaves your own name empty),
--   * mana values on target / focus lined up with the health values.
--
-- None of this hooks the client's unit frame update functions: hooks run in the middle of its
-- updates (name, health, auras), and on this client anything an addon does there can leave the
-- rest of the update unfinished. Colors are applied right after the client's update instead (one
-- frame after a unit change) and kept on by a light timer. Only single widgets are hooked (a name's
-- SetText), to put our values back after the client changed them.
-- The bars' current color is never read (it can be a protected value on this client).

local FRAMES = {
    player = { "PlayerFrame" },
    target = { "TargetFrame" },
    focus = { "FocusFrame" },
    targettarget = { "TargetFrameToT", "TargetFrame.totFrame" },
    focustarget = { "FocusFrameToT", "FocusFrame.totFrame" },
}

local REFRESH_INTERVAL = 0.2

local bars = {}      -- health bar -> unit
local colored = {}   -- health bar -> true while we colored it

local function Enabled()
    return S.db.appearance.classColors or S.db.appearance.reactionColors
end

local function FindBar(paths)
    for _, path in ipairs(paths) do
        local frame = S.Resolve(path)
        local bar = frame and (frame.healthbar or frame.HealthBar
            or S.Resolve(path .. ".PlayerFrameContent.PlayerFrameContentMain.HealthBarsContainer.HealthBar")
            or S.Resolve(path .. ".TargetFrameContent.TargetFrameContentMain.HealthBarsContainer.HealthBar"))
        if bar and bar.SetStatusBarColor then
            return bar
        end
    end
end

local function ClassColor(unit)
    local exists = UnitExists(unit)
    if S.IsSecret(exists) or not exists then
        return nil
    end
    local isPlayer = UnitIsPlayer(unit)
    if S.IsSecret(isPlayer) or not isPlayer then
        return nil
    end
    local _, class = UnitClass(unit)
    if not class or S.IsSecret(class) then
        return nil
    end
    return (C_ClassColor and C_ClassColor.GetClassColor(class)) or (RAID_CLASS_COLORS and RAID_CLASS_COLORS[class])
end

-- The client's own bar color (e.g. red for hostile NPCs on the target frame), as it last set it.
-- Only recorded, never acted on in the client's call; it is what the bar goes back to when the
-- unit is no player any more.
local clientColor = setmetatable({}, { __mode = "k" })     -- bar -> { r, g, b } or false (unreadable)
local clientDesaturated = setmetatable({}, { __mode = "k" }) -- bar -> boolean
local painting = false

local function TrackClientColor(bar)
    hooksecurefunc(bar, "SetStatusBarColor", function(self, r, g, b)
        if painting then
            return
        end
        if S.IsSecret(r) or S.IsSecret(g) or S.IsSecret(b) or type(r) ~= "number" then
            clientColor[self] = false
        else
            clientColor[self] = { r, g, b }
        end
    end)
    if bar.SetStatusBarDesaturated then
        hooksecurefunc(bar, "SetStatusBarDesaturated", function(self, desaturated)
            if not painting and not S.IsSecret(desaturated) then
                clientDesaturated[self] = desaturated and true or false
            end
        end)
    end
end

-- Reaction colors for units that aren't players (or players while class colors are off):
-- the client's standard ones, red (hostile) to yellow (neutral) to green (friendly).
local REACTION_FALLBACK = {
    [1] = { r = 0.8, g = 0.13, b = 0.13 }, [2] = { r = 0.8, g = 0.13, b = 0.13 }, [3] = { r = 0.75, g = 0.27, b = 0 },
    [4] = { r = 0.9, g = 0.7, b = 0 }, [5] = { r = 0, g = 0.6, b = 0.1 }, [6] = { r = 0, g = 0.6, b = 0.1 },
    [7] = { r = 0, g = 0.6, b = 0.1 }, [8] = { r = 0, g = 0.6, b = 0.1 },
}

local function ReactionColor(unit)
    local exists = UnitExists(unit)
    if S.IsSecret(exists) or not exists then
        return nil
    end
    local reaction = UnitReaction(unit, "player")
    if not reaction or S.IsSecret(reaction) then
        return nil
    end
    return (FACTION_BAR_COLORS and FACTION_BAR_COLORS[reaction]) or REACTION_FALLBACK[reaction]
end

-- Class color first (players), then the reaction color.
local function BarColor(unit)
    local db = S.db.appearance
    return (db.classColors and ClassColor(unit)) or (db.reactionColors and ReactionColor(unit)) or nil
end

local function Paint(bar, unit)
    local color = BarColor(unit)
    painting = true
    if color then
        if bar.SetStatusBarDesaturated then
            bar:SetStatusBarDesaturated(true)
        end
        bar:SetStatusBarColor(color.r, color.g, color.b)
        colored[bar] = true
    elseif colored[bar] then
        -- Back to the client's own look: the color it gave the bar last (red for a hostile NPC),
        -- or, if it never set one, the bar texture's own color.
        colored[bar] = nil
        local own = clientColor[bar]
        if bar.SetStatusBarDesaturated then
            bar:SetStatusBarDesaturated(clientDesaturated[bar] or false)
        end
        if own then
            bar:SetStatusBarColor(own[1], own[2], own[3])
        elseif own == nil then
            bar:SetStatusBarColor(1, 1, 1)
        end
        -- own == false: the client's color can't be read; it stays until the client sets it again.
    end
    painting = false
end

-- Own name fix ------------------------------------------------------------------------------------
-- The client leaves your own name empty on the player frame, and keeps the previous name on the
-- target / focus / target-of-target frame when that unit is you. Whenever a frame shows you, its
-- name is filled in. Other units are never touched.

local NAME_STRINGS = {
    player = { "PlayerName", "PlayerFrame.name" },
    target = { "TargetFrame.TargetFrameContent.TargetFrameContentMain.Name", "TargetFrame.name" },
    focus = { "FocusFrame.TargetFrameContent.TargetFrameContentMain.Name", "FocusFrame.name" },
    targettarget = { "TargetFrameToT.Name", "TargetFrameToT.name" },
    focustarget = { "FocusFrameToT.Name", "FocusFrameToT.name" },
}

local nameStrings = {}   -- font string -> unit
local fixingName = false

local function FixName(fontString, unit)
    local isSelf = UnitIsUnit(unit, "player")
    if S.IsSecret(isSelf) or not isSelf then
        return
    end
    local name = GetUnitName("player")
    if not name or S.IsSecret(name) then
        return
    end
    local current = fontString:GetText()
    if S.IsSecret(current) or current == name then
        return
    end
    fixingName = true
    fontString:SetText(name)
    fixingName = false
end

local function SafeFixName(fontString)
    if fixingName then
        return
    end
    local unit = nameStrings[fontString]
    if unit and not pcall(FixName, fontString, unit) then
        fixingName = false
    end
end

local function SetupNames()
    for unit, paths in pairs(NAME_STRINGS) do
        for _, path in ipairs(paths) do
            local fontString = S.Resolve(path)
            if type(fontString) == "table" and fontString.SetText and not nameStrings[fontString] then
                nameStrings[fontString] = unit
                -- The client writing an (empty or old) name is corrected right after.
                hooksecurefunc(fontString, "SetText", SafeFixName)
                break
            end
        end
    end
end

local ColorNameByClass -- below, with the class colored names

function M:UpdateNames()
    for fontString, unit in pairs(nameStrings) do
        SafeFixName(fontString)
        pcall(ColorNameByClass, fontString, unit)
    end
end

-- Mana text alignment -------------------------------------------------------------------------------
-- On the target and focus frames the mana bar is wider than the health bar (it runs under the
-- portrait border), so its left/right values sit further out than the health values above them.
-- They are moved in to line up with the health bar's values.

local TEXT_INSET = 2 -- the client's distance between a bar's edge and its value text
-- This never actually got applied until the HealthBarsContainer.LeftText/RightText lookup below
-- was fixed (it was looking one level too deep, at the health BAR instead of its container, so
-- this whole branch silently never ran before). +2 confirmed too high, -2 confirmed too low;
-- splitting the difference.
local MANA_TEXT_RAISE = 0

local function Number(value)
    if value == nil or S.IsSecret(value) then
        return nil
    end
    return value
end

local function AlignManaText(frameName)
    local main = S.Resolve(frameName .. ".TargetFrameContent.TargetFrameContentMain")
    local mana = main and main.ManaBar
    -- LeftText/RightText live on HealthBarsContainer itself, not nested under its HealthBar child
    -- (confirmed via /smuve dump) - the health bar is still needed separately, for GetCenter().
    local healthContainer = main and main.HealthBarsContainer
    local health = healthContainer and healthContainer.HealthBar
    if not mana or not health or not healthContainer then
        return
    end
    -- Best: line up with the health values themselves, at the height of the mana bar's middle.
    -- (Blizzard's own default already anchors the mana values to these same health text objects;
    -- this only adds the vertical correction below, on the same relationship.)
    local _, manaY = mana:GetCenter()
    local _, healthY = health:GetCenter()
    if Number(manaY) and Number(healthY) and healthContainer.LeftText and healthContainer.RightText then
        -- The offset is taken from the health value's own height (the bar's box is taller than its
        -- visible part), so the mana values end up centered in the mana bar like on the player frame.
        -- The target mana bar's visible part sits higher than the middle of its box (its mask is
        -- shifted up), so the values are raised by that difference to look centered.
        local _, textY = healthContainer.RightText:GetCenter()
        local offsetY = (Number(textY) and (manaY - textY) or (manaY - healthY)) + MANA_TEXT_RAISE
        if mana.LeftText then
            mana.LeftText:ClearAllPoints()
            mana.LeftText:SetPoint("LEFT", healthContainer.LeftText, "LEFT", 0, offsetY)
        end
        if mana.RightText then
            mana.RightText:ClearAllPoints()
            mana.RightText:SetPoint("RIGHT", healthContainer.RightText, "RIGHT", 0, offsetY)
        end
        return
    end

    -- Fallback: move the values in by the mana bar's overhang.
    local leftOverhang = (Number(health:GetLeft()) and Number(mana:GetLeft())) and (health:GetLeft() - mana:GetLeft())
    local rightOverhang = (Number(health:GetRight()) and Number(mana:GetRight())) and (mana:GetRight() - health:GetRight())
    if not leftOverhang or not rightOverhang then
        -- Not laid out yet: from the bar widths, the overhang is the same on both sides.
        local difference = ((Number(mana:GetWidth()) or 0) - (Number(health:GetWidth()) or 0)) / 2
        leftOverhang, rightOverhang = difference, difference
    end
    if mana.LeftText then
        mana.LeftText:ClearAllPoints()
        mana.LeftText:SetPoint("LEFT", mana, "LEFT", leftOverhang + TEXT_INSET, MANA_TEXT_RAISE)
    end
    if mana.RightText then
        mana.RightText:ClearAllPoints()
        mana.RightText:SetPoint("RIGHT", mana, "RIGHT", -(rightOverhang + TEXT_INSET), MANA_TEXT_RAISE)
    end
end

function M:AlignManaTexts()
    for _, frameName in ipairs({ "TargetFrame", "FocusFrame" }) do
        pcall(AlignManaText, frameName)
    end
end

-- Name glow -----------------------------------------------------------------------------------------
-- The reaction colored band behind the name on the target and focus frames (ReputationColor):
-- optionally hidden, kept off by re-hiding it whenever the client shows it again.

local NAME_GLOW = {
    "TargetFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor",
    "FocusFrame.TargetFrameContent.TargetFrameContentMain.ReputationColor",
}
local nameGlowHooked = {}

local function NameGlowEnabled()
    return S.db.appearance.hideNameGlow
end

function M:ApplyNameGlow()
    local hide = NameGlowEnabled()
    for _, path in ipairs(NAME_GLOW) do
        local glow = S.Resolve(path)
        if glow then
            if not nameGlowHooked[glow] then
                nameGlowHooked[glow] = true
                hooksecurefunc(glow, "Show", function(self)
                    if NameGlowEnabled() then
                        self:Hide()
                    end
                end)
            end
            glow:SetShown(not hide)
        end
    end
end

-- Target-of-target position -------------------------------------------------------------------------
-- Pulled closer to the target frame's own portrait (10px right, 10px up from the client's own
-- anchor), to free up the space between them for the target's buffs/debuffs. Captured once (like
-- the cast bar's original anchor in Modules\UnitAuras.lua) and kept on by re-applying whenever the
-- client re-anchors it; relativeTo is always whatever Blizzard anchored it to (TargetFrame, a
-- Blizzard-owned frame), never something of ours, so this never risks the kind of anchor
-- restriction the cast bar hit when it pointed at one of SmuveUI's own frames.

local TOT_OFFSET_X, TOT_OFFSET_Y = 20, 10
local totOriginal
local totPositioning = false

function M:ApplyTotPosition()
    local frame = TargetFrameToT
    if not frame then
        return
    end
    -- A target change during combat taints this C_Timer.After callback, and SetPoint/
    -- ClearAllPoints on the target-of-target frame become protected under that taint - deferred
    -- to PLAYER_REGEN_ENABLED the same way Modules\Nameplates.lua defers ApplyWidth.
    if InCombatLockdown() then
        self.totPending = true
        return
    end
    if not totOriginal then
        if frame:GetNumPoints() == 0 then
            return
        end
        local point, relativeTo, relativePoint, x, y = frame:GetPoint(1)
        if S.IsSecret(point) or S.IsSecret(relativePoint) or S.IsSecret(x) or S.IsSecret(y) then
            return
        end
        totOriginal = { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y }
        hooksecurefunc(frame, "SetPoint", function()
            if not totPositioning then
                M:ApplyTotPosition()
            end
        end)
    end
    self.totPending = false
    totPositioning = true
    frame:ClearAllPoints()
    frame:SetPoint(totOriginal.point, totOriginal.relativeTo, totOriginal.relativePoint,
        totOriginal.x + TOT_OFFSET_X, totOriginal.y + TOT_OFFSET_Y)
    totPositioning = false
end

-- Class colored names ----------------------------------------------------------------------------
-- Player names on the player, target, focus and target-of-target frames in their class color;
-- other units keep the client's yellow.

local classNamed = {}    -- font string -> true while we colored it
local DEFAULT_NAME_COLOR = { 1, 0.82, 0 }

ColorNameByClass = function(fontString, unit)
    local color = S.db.appearance.classColorNames and ClassColor(unit)
    if color then
        fontString:SetTextColor(color.r, color.g, color.b)
        classNamed[fontString] = true
    elseif classNamed[fontString] then
        classNamed[fontString] = nil
        fontString:SetTextColor(DEFAULT_NAME_COLOR[1], DEFAULT_NAME_COLOR[2], DEFAULT_NAME_COLOR[3])
    end
end

function M:UpdateAll()
    for bar, unit in pairs(bars) do
        if not pcall(Paint, bar, unit) then
            painting = false
        end
    end
    self:UpdateNames()
end

-- One frame later: after the client finished its own update of the frame. The target/focus mana
-- values are realigned at the same time, since the same events (target changed, entering world)
-- are what can move the health bar they line up with.
local function UpdateSoon()
    C_Timer.After(0, function()
        M:UpdateAll()
        M:AlignManaTexts()
        M:ApplyNameGlow()
        M:ApplyTotPosition()
    end)
end

function M:Init()
    for unit, paths in pairs(FRAMES) do
        local bar = FindBar(paths)
        if bar then
            bars[bar] = unit
            TrackClientColor(bar)
        end
    end
    SetupNames()
    self:ApplyNameGlow()
    self:ApplyTotPosition()
    S:On("UNIT_NAME_UPDATE", UpdateSoon)

    for _, event in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_TARGET_CHANGED", "PLAYER_FOCUS_CHANGED" }) do
        S:On(event, UpdateSoon)
    end
    S:On("UNIT_TARGET", function(_, unit)
        if unit == "target" or unit == "focus" then
            UpdateSoon()
        end
    end)
    S:On("PLAYER_REGEN_ENABLED", function()
        if M.totPending then
            M:ApplyTotPosition()
        end
    end)

    C_Timer.NewTicker(REFRESH_INTERVAL, function()
        if Enabled() or next(colored) then
            M:UpdateAll()
        else
            M:UpdateNames()
        end
    end)
end

function M:Refresh()
    self:UpdateAll()
    self:ApplyNameGlow()
end
