local _, S = ...
local M = S:NewModule("UnitAuras")

-- Target and focus auras with adjustable icon size, icons per row and rows, and an optional
-- duration text. Blizzard's aura container on these frames is switched off and replaced by the
-- client's own aura containers (CreateFrame("AuraContainer")), like on the nameplates: buffs in
-- rows below the frame, debuffs in rows below the buffs. The icons look like the nameplate ones
-- (black border, debuff type colors, purge glow) and show tooltips.

local START_X = 5       -- from the frame art's bottom left corner
local START_Y = 9
local TYPE_GAP = 4      -- between the buff rows and the debuff rows
local SPACING = 2       -- between icons

local FRAMES = { target = "TargetFrame", focus = "FocusFrame" }
local SPELLBAR_FRAMES = { target = "TargetFrameSpellBar", focus = "FocusFrameSpellBar" }
local SPELLBAR_GAP = 6  -- below whichever aura row is lowest

local hosts = {}        -- unit -> { frame, buffs, debuffs, generation }
local generation = 0
local suppressed = {}    -- unit -> true once the client's auras on its frame are off
local spellbarOriginal = {} -- unit -> { point, relativeTo, relativePoint, x, y }, captured once
local spellbarQueued = {}
local spellbarWaiting = {}

-- Each frame has its own settings: S.db.unitAuras.target / .focus.
local function DB(unit)
    return S.db.unitAuras[unit]
end

local function Supported()
    return AuraUtil and AuraUtil.AuraFilters and AuraUtil.CreateFilterString and AnchorUtil
        and AnchorUtil.FlowDirection and AuraContainerSortMethod ~= nil
        and S.modules.Nameplates and S.modules.Nameplates.InitAuraButton ~= nil
end

local function LineSize(count, size)
    return count * size + (count - 1) * SPACING
end

-- Height of a block of "rows" rows at "size" each (an empty block is one pixel tall, matching
-- the real containers below). From our own saved settings and a plain aura count, never read off
-- a live frame, so nothing here can come back as a secret value (see ApplySpellBar below).
local function BlockHeight(size, perRow, maxRows, count)
    if count <= 0 then
        return 1
    end
    local rows = math.min(math.ceil(count / perRow), maxRows)
    return rows * size + (rows - 1) * SPACING
end

-- How many of the unit's current auras match (helpful/buffs or harmful/debuffs): plain aura data
-- by classic enumeration, not read off any aura container's rendered geometry, so - unlike that
-- geometry - this isn't a protected value.
local function CountAuras(unit, helpful)
    local filter = helpful and "HELPFUL" or "HARMFUL"
    local count = 0
    while C_UnitAuras.GetAuraDataByIndex(unit, count + 1, filter) do
        count = count + 1
    end
    return count
end

-- Blizzard's own auras ------------------------------------------------------------------------------

local function SuppressBlizzardAuras(frame)
    local container = frame.GetAuraContainer and frame:GetAuraContainer()
    if not container then
        return
    end
    container:SetMaxBuffs(0)
    container:SetMaxDebuffs(0)
    container:SetEnabled(false)
end

local function SuppressAll()
    for unit, name in pairs(FRAMES) do
        local frame = _G[name]
        if frame and frame.GetAuraContainer and DB(unit).enabled and not suppressed[unit] then
            suppressed[unit] = true
            SuppressBlizzardAuras(frame)
            -- The client configures its container again on changes; it stays off.
            if type(frame.ConfigureAuraContainer) == "function" then
                hooksecurefunc(frame, "ConfigureAuraContainer", function(self)
                    if DB(unit).enabled then
                        SuppressBlizzardAuras(self)
                    end
                end)
            end
            frame:GetAuraContainer():SetUnit("none")
        end
    end
end

-- Containers ---------------------------------------------------------------------------------------

local function CreateBlock(parent, helpful, size, perRow, rows, db, purgeGlow, unit)
    local AF = AuraUtil.AuraFilters
    local container = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
    container:SetEnabled(false)
    if container.SetFlattensRenderLayers then
        container:SetFlattensRenderLayers(true)
    end
    container:SetFlowLayoutAnchorPoint("TOPLEFT")
    container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
    container:SetFlowLayoutMaximumLineSize(LineSize(perRow, size))

    local style = {
        typeBorders = true, -- debuff borders in their dispel type's color, always on
        purgeGlow = purgeGlow,
        showDuration = db.showDuration,
        durationSize = db.durationSize,
        playerLook = true,    -- duration and stacks like the player's own auras
        mouse = true,
    }
    container:AddAuraGroup(helpful and "Buffs" or "Debuffs", AuraUtil.CreateFilterString(helpful and AF.Helpful or AF.Harmful), {
        maxFrameCount = perRow * rows,
        sortMethod = AuraContainerSortMethod.Default,
        sortDirection = AuraContainerSortDirection.Normal,
        initializeFrame = function(button)
            S.modules.Nameplates.InitAuraButton(button, size, helpful, style)
        end,
        layout = {
            elementSpacing = SPACING,
            lineSpacing = SPACING,
            elementWidth = size,
            elementHeight = size,
            layoutIndex = 1,
        },
    })
    -- The container auto-sizes to the auras it holds; whenever that changes, the cast bar below
    -- may need to move down (or back up) with it.
    container:SetScript("OnSizeChanged", function()
        M:QueueSpellBar(unit)
    end)
    return container
end

-- Test mode (target frame only - the focus frame's version was removed: with no real focus,
-- FocusFrame is never shown or laid out by the client, and nothing short of a real click on a
-- secure, attribute-driven button can set the focus from addon code to fix that, which wasn't
-- worth the complexity here) ------------------------------------------------------------------
-- Real containers only show real auras, so the test mode draws stand-in icons in the same spot,
-- like the nameplates' test mode (Modules\Nameplates.lua) - reusing its icon look (PreviewIcon)
-- rather than duplicating the border/purge-glow drawing.

local SAMPLE_BUFFS = { 135987, 132333 }           -- Power Word: Fortitude (Magic), Battle Shout (no type)
local SAMPLE_DEBUFFS = { 136207, 136139, 132204 } -- Shadow Word: Pain (Magic), Curse of Agony (Curse), Serpent Sting (Poison)
local SAMPLE_DEBUFF_TYPES = { "Magic", "Curse", "Poison" }

local previews = {} -- unit -> holder frame

-- Rows grow downward from the grid's TOPLEFT (like the real containers' FlowDirection.Down from
-- a TOPLEFT anchor point) - that needs a NEGATIVE y offset per row, since positive y is up in
-- WoW's coordinate space; using a positive offset here (confirmed live) stacked every row after
-- the first above the grid instead, overlapping the frame's portrait/name.
local function PreviewGrid(holder, sample, types, size, perRow, rows)
    local PreviewIcon = S.modules.Nameplates.PreviewIcon
    local count = perRow * rows
    local grid = CreateFrame("Frame", nil, holder)
    grid:SetSize(math.max(1, LineSize(math.min(count, perRow), size)), math.max(1, rows * size + (rows - 1) * SPACING))
    for index = 1, count do
        local which = (index - 1) % #sample + 1
        local icon = PreviewIcon(grid, size, sample[which], nil, types and types[which])
        local x = ((index - 1) % perRow) * (size + SPACING)
        local y = math.floor((index - 1) / perRow) * (size + SPACING)
        icon:SetPoint("TOPLEFT", grid, "TOPLEFT", x, -y)
    end
    return grid
end

local function ShowPreview(unit)
    local frame = _G[FRAMES[unit]]
    if not frame then
        return
    end
    local db = DB(unit)
    local holder = previews[unit]
    if holder and holder.generation ~= generation then
        holder:Hide()
        holder = nil
        previews[unit] = nil
    end
    if not holder then
        holder = CreateFrame("Frame", nil, frame)
        holder:SetFrameLevel(frame:GetFrameLevel() + 20)
        holder.generation = generation
        holder.buffs = PreviewGrid(holder, SAMPLE_BUFFS, nil, db.buffSize, db.buffPerRow, db.buffRows)
        holder.debuffs = PreviewGrid(holder, SAMPLE_DEBUFFS, SAMPLE_DEBUFF_TYPES, db.debuffSize, db.debuffPerRow, db.debuffRows)
        previews[unit] = holder
    end
    local anchorTo = (frame.TargetFrameContainer and frame.TargetFrameContainer.FrameTexture) or frame
    holder.buffs:ClearAllPoints()
    holder.buffs:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", START_X, START_Y)
    holder.debuffs:ClearAllPoints()
    holder.debuffs:SetPoint("TOPLEFT", holder.buffs, "BOTTOMLEFT", 0, -TYPE_GAP)
    holder:Show()
end

local function HidePreview(unit)
    local holder = previews[unit]
    if holder then
        holder:Hide()
    end
end

local function Build(unit)
    local frame = _G[FRAMES[unit]]
    if not frame then
        return
    end
    local db = DB(unit)
    local host = hosts[unit] or {}
    hosts[unit] = host
    M:CaptureSpellBarOriginal(unit)

    -- Settings changed: the old containers retire and new ones are built (button looks are fixed).
    if host.generation ~= generation then
        for _, key in ipairs({ "buffsEnemy", "buffsFriendly", "debuffs" }) do
            if host[key] then
                host[key]:SetEnabled(false)
                host[key]:Hide()
                host[key] = nil
            end
        end
        host.generation = generation
    end

    -- Shown regardless of "Enable", like the nameplates' test mode, so sizes can be checked
    -- before turning the real auras on. Paused in combat: the samples hide and come back after.
    if db.testMode and not InCombatLockdown() then
        pcall(ShowPreview, unit)
    else
        HidePreview(unit)
    end

    if not db.enabled then
        -- No aura rows of ours below the frame any more: the cast bar goes back where it was.
        M:QueueSpellBar(unit)
        return
    end

    -- Buffs come in two blocks: with the purge glow for enemies, without it for friendly units
    -- (their buffs can't be purged). The one matching the unit is shown (UpdateHostility).
    if not host.buffsEnemy then
        local glow = db.purgeGlow
        host.buffsEnemy = CreateBlock(frame, true, db.buffSize, db.buffPerRow, db.buffRows, db, glow, unit)
        host.buffsFriendly = CreateBlock(frame, true, db.buffSize, db.buffPerRow, db.buffRows, db, false, unit)
        host.debuffs = CreateBlock(frame, false, db.debuffSize, db.debuffPerRow, db.debuffRows, db, false, unit)
    end

    -- Below the frame art; an empty block is one pixel tall, so the debuffs move up without buffs.
    local anchorTo = (frame.TargetFrameContainer and frame.TargetFrameContainer.FrameTexture) or frame
    for _, key in ipairs({ "buffsEnemy", "buffsFriendly" }) do
        host[key]:ClearAllPoints()
        host[key]:SetPoint("TOPLEFT", anchorTo, "BOTTOMLEFT", START_X, START_Y)
    end
    for _, key in ipairs({ "buffsEnemy", "buffsFriendly", "debuffs" }) do
        host[key]:SetFrameLevel(frame:GetFrameLevel() + 5)
    end
    M:UpdateHostility(unit)
end

-- Shows the buff block matching the unit (enemy or friendly) and hangs the debuffs below it.
function M:UpdateHostility(unit)
    local host = hosts[unit]
    if not host or not host.buffsEnemy then
        return
    end
    local enemy = UnitExists(unit) and UnitCanAttack("player", unit)
    if S.IsSecret(enemy) then
        enemy = false
    end
    local active = enemy and host.buffsEnemy or host.buffsFriendly
    local inactive = enemy and host.buffsFriendly or host.buffsEnemy
    inactive:SetEnabled(false)
    inactive:Hide()
    host.debuffs:ClearAllPoints()
    host.debuffs:SetPoint("TOPLEFT", active, "BOTTOMLEFT", 0, -TYPE_GAP)
    for _, container in ipairs({ active, host.debuffs }) do
        container:SetUnit(unit)
        container:SetEnabled(true)
        container:Show()
        if container.UpdateAllAuras then
            container:UpdateAllAuras()
        end
    end
    M:QueueSpellBar(unit)
end

-- Blizzard's cast bar (TargetFrameSpellBar / FocusFrameSpellBar) is normally anchored assuming
-- the frame's own (now suppressed) aura rows; with ours below the frame instead, it lands on top
-- of them. Setting its anchor once doesn't stick, though: something in the client's own code
-- re-anchors it again afterward regardless of what we set (muleyoUI's Forever-specific castbar
-- modules hit the same thing on this build and gave up fighting it with a one-shot SetPoint).
-- Their fix, reused here: don't out-guess whatever re-anchors it, just hook the bar's own
-- SetPoint and re-apply our anchor right after any OTHER call lands, skipping only the ones that
-- are our own (mUI's Theme:AnchorSpellbarToContainer does the same thing).

local watchdogInstalled = {} -- bar -> true

-- Live counters read by /smuve dump (debug.unitAuras), since the last two attempts at this
-- didn't work and guessing a third time blind isn't worth another round trip.
M.spellBarDebug = {}

local function Debug(unit, event)
    local d = M.spellBarDebug[unit]
    if not d then
        d = { watchdogHits = 0, applies = 0 }
        M.spellBarDebug[unit] = d
    end
    d.last = event
    if event == "watchdog" then
        d.watchdogHits = d.watchdogHits + 1
    elseif event == "applied" or event == "restored" then
        d.applies = d.applies + 1
    end
end

local function InstallWatchdog(unit, bar)
    if watchdogInstalled[bar] then
        return
    end
    watchdogInstalled[bar] = true
    Debug(unit, "watchdog-installed")
    hooksecurefunc(bar, "SetPoint", function(self)
        if not self.smuveReanchoring then
            Debug(unit, "watchdog")
            M:QueueSpellBar(unit)
        end
    end)
end

function M:CaptureSpellBarOriginal(unit)
    local bar = _G[SPELLBAR_FRAMES[unit]]
    if not bar then
        Debug(unit, "no-bar-at-capture")
        return
    end
    InstallWatchdog(unit, bar)
    if spellbarOriginal[unit] then
        return
    end
    -- GetNumPoints()/GetPoint() on this bar can come back secret (confirmed live: a /smuve dump
    -- taken mid-cast crashed with "'for' limit must be a number" on exactly this call), so this
    -- is best-effort and quietly gives up rather than risk throwing mid-Build().
    local count = bar:GetNumPoints()
    if S.IsSecret(count) or count == 0 then
        return
    end
    local point, relativeTo, relativePoint, x, y = bar:GetPoint(1)
    if S.IsSecret(point) or S.IsSecret(x) or S.IsSecret(y) then
        return
    end
    spellbarOriginal[unit] = { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y }
end

-- Two hard platform limits, both confirmed live by /smuve dump rather than guessed:
--  1. Anchoring this protected bar's relativeTo to host.debuffs (our own, addon-created frame)
--     is flatly refused: "Anchoring disallowed as dependent object would inherit forbidden
--     aspects: UntrustedLayoutScriptExecution". Not a bug to route around - a protected frame
--     cannot be pointed at an addon-created one at all, however it's called.
--  2. GetHeight()/GetBottom()/IsShown() on an AuraContainer are themselves secret values on this
--     client, even for one SmuveUI created - "attempt to perform arithmetic on local
--     'buffHeight' (a secret number value...)" - so the actual rendered height can't be read
--     either, to compute an offset from.
-- So relativeTo is always a Blizzard-owned frame (allowed), and the offset is computed from the
-- unit's actual current buff/debuff counts (CountAuras, plain aura data) against our own row/size
-- settings (BlockHeight) - never from reading any live frame's geometry, so nothing in it can
-- come back secret. A worst-case (always the configured max rows) was tried first and worked,
-- but left a large, often-empty gap below the bar; this tracks the real row count instead.
local function ApplySpellBar(unit)
    local bar = _G[SPELLBAR_FRAMES[unit]]
    local frame = _G[FRAMES[unit]]
    local host = hosts[unit]
    local db = DB(unit)
    local original = spellbarOriginal[unit]
    if not bar or not frame then
        Debug(unit, "no-bar-at-apply")
        return
    end
    bar.smuveReanchoring = true
    local ok, err = pcall(function()
        if not db.enabled or not host or not host.debuffs then
            if original then
                bar:ClearAllPoints()
                bar:SetPoint(original.point, original.relativeTo, original.relativePoint, original.x, original.y)
                Debug(unit, "restored")
            else
                Debug(unit, "skip-no-usable-original")
            end
            return
        end
        local buffHeight = BlockHeight(db.buffSize, db.buffPerRow, db.buffRows, CountAuras(unit, true))
        local debuffHeight = BlockHeight(db.debuffSize, db.debuffPerRow, db.debuffRows, CountAuras(unit, false))
        local extra = START_Y + buffHeight + TYPE_GAP + debuffHeight
        local anchorTo = (frame.TargetFrameContainer and frame.TargetFrameContainer.FrameTexture) or frame
        bar:ClearAllPoints()
        bar:SetPoint("TOP", anchorTo, "BOTTOM", 0, -(SPELLBAR_GAP + extra))
        Debug(unit, "applied")
    end)
    -- Always cleared, success or not: left stuck at true, the watchdog hook above would ignore
    -- every future SetPoint on this bar for the rest of the session.
    bar.smuveReanchoring = false
    if not ok then
        Debug(unit, "error")
        local d = M.spellBarDebug[unit]
        if d then
            d.error = tostring(err)
        end
    end
end

-- Applied a frame later (the containers need a layout pass to report their real size), out of
-- combat only: SetPoint on this bar follows the same rules as the rest of the secure unit frames.
function M:QueueSpellBar(unit)
    if spellbarQueued[unit] then
        return
    end
    spellbarQueued[unit] = true
    C_Timer.After(0, function()
        spellbarQueued[unit] = nil
        if InCombatLockdown() then
            spellbarWaiting[unit] = true
            Debug(unit, "combat-lockdown")
            return
        end
        local ok, err = pcall(ApplySpellBar, unit)
        if not ok then
            local d = M.spellBarDebug[unit] or {}
            M.spellBarDebug[unit] = d
            d.error = tostring(err)
        end
    end)
end

local function SafeBuild(unit)
    local ok, err = pcall(Build, unit)
    if not ok and not M.reported then
        M.reported = true
        geterrorhandler()(err)
    end
end

function M:BuildAll()
    for unit in pairs(FRAMES) do
        SafeBuild(unit)
    end
end

-- Module -------------------------------------------------------------------------------------------

function M:Init()
    -- Earlier versions had one set of settings for both frames: it is copied to each.
    local all = S.db.unitAuras
    local KEYS = { "enabled", "buffSize", "buffPerRow", "buffRows", "debuffSize", "debuffPerRow", "debuffRows", "showDuration", "durationSize" }
    if all.buffSize ~= nil then
        -- The first defaults (20 / 6 / 2, durations on) count as the newer ones (24 / 5 / 3, off).
        local first = { buffSize = 20, buffPerRow = 6, buffRows = 2, debuffSize = 20, debuffPerRow = 6, debuffRows = 2, showDuration = true }
        for _, unit in ipairs({ "target", "focus" }) do
            for _, key in ipairs(KEYS) do
                if all[key] ~= nil and not (not all.defaultsVersion and first[key] == all[key]) then
                    all[unit][key] = all[key]
                end
            end
        end
        for _, key in ipairs(KEYS) do
            all[key] = nil
        end
        all.defaultsVersion = nil
    end
    if not Supported() then
        return
    end
    -- Always off after a reload, like the nameplates' test mode. Target only - the focus frame
    -- version of this was removed (see the comment above the "Test mode" section).
    DB("target").testMode = false
    S.db.unitAuras.focus.testMode = nil
    -- A new target or focus: the containers read the unit's auras again.
    local function Update(unit)
        if hosts[unit] then
            pcall(M.UpdateHostility, M, unit)
        end
    end
    S:On("PLAYER_TARGET_CHANGED", function() Update("target") end)
    S:On("PLAYER_FOCUS_CHANGED", function() Update("focus") end)
    -- A unit can turn hostile or friendly (duels, PvP flags).
    S:On("UNIT_FACTION", function(_, unit)
        if unit == "target" or unit == "focus" then
            Update(unit)
        end
    end)
    S:On("PLAYER_REGEN_DISABLED", function()
        for unit in pairs(previews) do
            HidePreview(unit)
        end
    end)
    S:On("PLAYER_REGEN_ENABLED", function()
        for unit in pairs(spellbarWaiting) do
            spellbarWaiting[unit] = nil
            M:QueueSpellBar(unit)
        end
        if DB("target").testMode then
            SafeBuild("target")
        end
    end)
end

-- Settings changed: new containers (slider drags settle first).
function M:Refresh()
    if not Supported() then
        return
    end
    if DB("target").enabled or DB("focus").enabled then
        SuppressAll()
    end
    if self.rebuildPending then
        return
    end
    self.rebuildPending = true
    C_Timer.After(0.3, function()
        M.rebuildPending = false
        generation = generation + 1
        M:BuildAll()
    end)
end

function M:IsSupported()
    return Supported()
end
