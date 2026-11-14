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
    -- UnitClassBase, not UnitClass, and no issecretvalue gate on its result before using it -
    -- confirmed via BetterBlizzFrames' own forever-build class-color helper that
    -- C_ClassColor.GetClassColor tolerates a secret class token and still hands back a usable
    -- color table. A plain Lua "not class"/"IsSecret(class)" branch on it (the old code here) is
    -- exactly what silently produced the default/white fallback whenever "targettarget" resolved
    -- through an NPC's own target - confirmed live: wrong only in that case, never through a
    -- player-owned target chain. The (C_ClassColor...) or (RAID_CLASS_COLORS...) fallback below
    -- stays safe even with a secret class: "or" only evaluates the RAID_CLASS_COLORS index if
    -- GetClassColor's result is falsy, so a secret class is never used to index that table directly.
    local class = UnitClassBase(unit)
    if class == nil then
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
local Paint -- forward declared: TrackClientColor's hooks below call it, but it's defined further down

-- Whenever the client repaints a bar we're currently overriding (colored[bar] true), it does so on
-- its own schedule (a health/target update), not ours - waiting for the next REFRESH_INTERVAL tick
-- to put our color back left a brief flash of the client's own color/desaturation on screen first
-- (confirmed live, most noticeable on the target-of-target frame, whose health bar the client
-- repaints more often than it does target/focus). hooksecurefunc fires synchronously right after
-- the client's own call, so reasserting here instead closes that window immediately.
local function RepaintIfOverridden(bar)
    local unit = bars[bar]
    if unit and colored[bar] then
        Paint(bar, unit)
    end
end

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
        RepaintIfOverridden(self)
    end)
    if bar.SetStatusBarDesaturated then
        hooksecurefunc(bar, "SetStatusBarDesaturated", function(self, desaturated)
            if painting then
                return
            end
            if not S.IsSecret(desaturated) then
                clientDesaturated[self] = desaturated and true or false
            end
            RepaintIfOverridden(self)
        end)
    end
end

local boundUnits = {} -- unit -> true once its bar is in `bars`

-- Target-of-target's health bar isn't guaranteed to exist yet at Init, unlike Target/Focus's own
-- bars (there from login) - TargetFrameToT/FocusFrameToT only get populated once the game has
-- actually shown a target-of-target at least once. A single resolve attempt in Init() then
-- permanently gave up on them, so their health bars never got registered in `bars` and never got
-- class/reaction colored even once a real target-of-target later showed up. Retried here instead,
-- from the ticker, until each unit's bar actually resolves.
local function EnsureBars()
    for unit, paths in pairs(FRAMES) do
        if not boundUnits[unit] then
            local bar = FindBar(paths)
            if bar then
                boundUnits[unit] = true
                bars[bar] = unit
                TrackClientColor(bar)
            end
        end
    end
    -- The personal resource display is its own frame (not part of FRAMES/FindBar's shape, and
    -- always shows "player"), so it's bound separately here rather than through the FRAMES loop
    -- above - a second, distinct bar mapped to the same "player" unit, reusing the same
    -- bars/Paint/TrackClientColor machinery. Confirmed via /smuve dump that nothing colored this
    -- bar before: it showed the client's own plain health-percent green, never class color.
    if not boundUnits.playerPersonalResource then
        local frame = PersonalResourceDisplayFrame
        local container = frame and frame.HealthBarsContainer
        local bar = container and container.healthBar
        if bar and bar.SetStatusBarColor then
            boundUnits.playerPersonalResource = true
            bars[bar] = "player"
            TrackClientColor(bar)
        end
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

Paint = function(bar, unit)
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

-- This never actually got applied until the HealthBarsContainer.LeftText/RightText lookup below
-- was fixed (it was looking one level too deep, at the health BAR instead of its container, so
-- this whole branch silently never ran before). +2 confirmed too high, -2 confirmed too low;
-- splitting the difference.
local MANA_TEXT_RAISE = 0
local ALIGN_RETRY_ATTEMPTS = 5
local ALIGN_RETRY_DELAY = 0.2 -- combat-protected reads clear almost immediately; a short retry covers it

local function Number(value)
    if value == nil or S.IsSecret(value) then
        return nil
    end
    return value
end

local AlignManaText -- forward-declared, retries itself

-- A fallback that re-derives the overhang from GetLeft()/GetRight()/GetWidth() used to run here
-- whenever GetCenter() was secret (combat). It could sign-flip: those getters go secret together
-- with GetCenter() on this client, so it silently defaulted both widths to 0, sometimes landing
-- leftOverhang/rightOverhang at zero or briefly negative mid target-change - which put the text
-- past center, looking like it swapped sides, and the result stuck until the next target/focus
-- change (this only re-runs on those events, not continuously). Retrying instead of guessing never
-- renders a wrong position - worst case the text keeps whatever position it already had.
local function RetryAlignManaText(frameName, attempt)
    if attempt > ALIGN_RETRY_ATTEMPTS then
        return
    end
    C_Timer.After(ALIGN_RETRY_DELAY, function()
        pcall(AlignManaText, frameName, attempt + 1)
    end)
end

AlignManaText = function(frameName, attempt)
    local main = S.Resolve(frameName .. ".TargetFrameContent.TargetFrameContentMain")
    local mana = main and main.ManaBar
    -- LeftText/RightText live on HealthBarsContainer itself, not nested under its HealthBar child
    -- (confirmed via /smuve dump) - the health bar is still needed separately, for GetCenter().
    local healthContainer = main and main.HealthBarsContainer
    local health = healthContainer and healthContainer.HealthBar
    if not mana or not health or not healthContainer then
        return
    end
    -- Line up with the health values themselves, at the height of the mana bar's middle.
    -- (Blizzard's own default already anchors the mana values to these same health text objects;
    -- this only adds the vertical correction below, on the same relationship.)
    local _, manaY = mana:GetCenter()
    local _, healthY = health:GetCenter()
    if not (Number(manaY) and Number(healthY) and healthContainer.LeftText and healthContainer.RightText) then
        -- Secret (combat-protected) read: leave the existing anchors alone rather than guess, and
        -- try again shortly once the values are readable.
        RetryAlignManaText(frameName, attempt or 1)
        return
    end
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
end

function M:AlignManaTexts()
    for _, frameName in ipairs({ "TargetFrame", "FocusFrame" }) do
        pcall(AlignManaText, frameName)
    end
end

-- PlayerFrame's own mana-bar text sits a few px too high - unlike Target/Focus above, this isn't
-- a box/mask mismatch (confirmed live: reusing AlignManaText's own calculation for PlayerFrame
-- computed essentially no correction, and the drift persisted regardless). The actual anchor data
-- involved (GetPoint() on these FontStrings) is secret/combat-protected and unreadable on this
-- client, so the real mechanism was never pinned down - confirmed via BetterBlizzFrames' own
-- source, which hand-repositions this exact text with a manually-tuned pixel offset rather than a
-- computed one, same as here. AdjustPointsOffset (not ClearAllPoints+SetPoint) shifts whatever
-- Blizzard's own anchor already is by this relative amount, leaving the horizontal position -
-- never reported as wrong - untouched, and sidesteps needing to read the secret anchor at all.
-- Guarded to run once per login/reload only: calling it again would compound the offset further.
local PLAYER_MANA_TEXT_NUDGE_Y = 2 -- a few px down; confirmed live as the right direction/amount (was 3 - too close to the bar's own border, nudged back up 1px)
local playerManaTextNudged = false

local function NudgePlayerManaText()
    if playerManaTextNudged then
        return
    end
    local playerMain = S.Resolve("PlayerFrame.PlayerFrameContent.PlayerFrameContentMain")
    local manaArea = playerMain and playerMain.ManaBarArea
    local mana = (manaArea and manaArea.ManaBar) or (playerMain and playerMain.ManaBar)
    if not mana or not mana.LeftText or not mana.RightText then
        return
    end
    if mana.LeftText.AdjustPointsOffset then
        mana.LeftText:AdjustPointsOffset(0, -PLAYER_MANA_TEXT_NUDGE_Y)
    end
    if mana.RightText.AdjustPointsOffset then
        mana.RightText:AdjustPointsOffset(0, -PLAYER_MANA_TEXT_NUDGE_Y)
    end
    playerManaTextNudged = true
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
        NudgePlayerManaText()
        M:ApplyNameGlow()
        M:ApplyTotPosition()
    end)
end

-- The target/focus (and boss) frame's level number and its "skull" (too-high-to-tell) icon are
-- supposed to be mutually exclusive, but confirmed live via /smuve dump that this client's own
-- level-display code sometimes shows both at once: LevelText showing a plain number while
-- HighLevelTexture was also shown, both anchored to the same center point on
-- LevelBackgroundCircle. Confirmed via BetterBlizzFrames' own source (forever/BetterBlizzFrames.lua,
-- FixSkullLevelText) as a named, dedicated bugfix for this exact client behavior - not something
-- either addon causes. Hooks CheckLevel, the native method responsible for this decision, and
-- clears the number's text whenever the skull is shown, right when the client itself just updated
-- it, rather than polling for the mismatch afterward.
local function ClearSkullLevelText(frame)
    local content = frame.TargetFrameContent
    local highLevelTexture = content and content.TargetFrameContentContextual and content.TargetFrameContentContextual.HighLevelTexture
    if highLevelTexture and highLevelTexture:IsShown() then
        local levelText = content.TargetFrameContentMain and content.TargetFrameContentMain.LevelText
        if levelText then
            levelText:SetText("")
        end
    end
end

local skullLevelHooked = {}

local function FixSkullLevelText()
    for _, name in ipairs({ "TargetFrame", "FocusFrame", "Boss1TargetFrame", "Boss2TargetFrame",
        "Boss3TargetFrame", "Boss4TargetFrame", "Boss5TargetFrame" }) do
        local frame = _G[name]
        if frame and frame.CheckLevel and frame.TargetFrameContent and not skullLevelHooked[frame] then
            skullLevelHooked[frame] = true
            hooksecurefunc(frame, "CheckLevel", ClearSkullLevelText)
        end
    end
end

function M:Init()
    FixSkullLevelText()
    EnsureBars()
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
        EnsureBars()
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

-- Debug (/smuve dump): every tracked health bar this module colors, its remembered client color
-- (captured via the SetStatusBarColor hook in TrackClientColor), and its current live color - to
-- tell apart "we never touched this bar" from "we colored it and it's wrong" from "the client's
-- own hook fired with an unexpected value" when a bar's color looks wrong.
function M:DebugLines()
    local lines = {}
    for bar, unit in pairs(bars) do
        local okColor, r, g, b = pcall(bar.GetStatusBarColor, bar)
        local own = clientColor[bar]
        table.insert(lines, string.format(
            "unit=%s colored=%s clientColor=%s live=%s desaturated(client)=%s",
            tostring(unit), tostring(colored[bar]),
            own == false and "<unreadable>" or (own and string.format("%.2f,%.2f,%.2f", own[1], own[2], own[3]) or "nil"),
            okColor and string.format("%.2f,%.2f,%.2f", r, g, b) or ("error:" .. tostring(r)),
            tostring(clientDesaturated[bar])))
    end
    return lines
end
