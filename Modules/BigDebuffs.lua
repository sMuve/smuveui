local _, S = ...
local M = S:NewModule("BigDebuffs")

-- One big icon filling the player/target portrait: the unit's current crowd control debuff, or
-- (if none) an important harmful debuff (one that isn't CC but is still worth flagging, e.g.
-- Weakened Soul), or (if none) its current "important" buff - a big defensive cooldown, an
-- externally applied defensive, or another important buff (a shield, an immunity...). Same
-- categories, same underlying filters as the enemy nameplates' side icons
-- (Modules\Nameplates.lua), just applied to the player/target frame's own portrait instead of a
-- nameplate.
--
-- Priority (CC, then important harmful debuff, then big defensive, then external defensive, then
-- other important) is done entirely by frame level and full coverage, not by reading which of
-- these mini containers is "empty": an empty AuraContainer is naturally a transparent 1x1
-- (confirmed elsewhere in this addon), so whichever highest-priority one actually has a matching
-- aura just visually covers the others beneath it, and the real portrait shows through on its own
-- when none of them do.

local AF = AuraUtil and AuraUtil.AuraFilters
local CreateFilterString = AuraUtil and AuraUtil.CreateFilterString

local UNITS = { "player", "target" }
local FRAMES = { player = "PlayerFrame", target = "TargetFrame" }
-- Where each frame keeps its portrait texture, and the mask atlas it's already cut to (so our
-- icon fits the exact same circle). maskChild is Blizzard's own existing MaskTexture object
-- already masking the portrait itself (confirmed live via /smuve dump), reused directly by the
-- manual icon below instead of creating a fresh CreateMaskTexture+SetAtlas copy - the same
-- technique mini-auras uses for its own portrait display (its GetPortraitMask).
local PORTRAITS = {
    player = { container = "PlayerFrameContainer", texture = "PlayerPortrait", mask = "UI-HUD-UnitFrame-Player-Portrait-Mask", maskChild = "PlayerPortraitMask" },
    target = { container = "TargetFrameContainer", texture = "Portrait", mask = "CircleMask", maskChild = "PortraitMask" },
}
-- Highest priority first; each one's own frame level is set this many steps above the frame's.
local TIERS = { "cc", "importantDebuff", "bigDefensive", "externalDefensive", "important" }

-- A short, explicit inclusion for buffs Blizzard's own category filter string misses entirely -
-- confirmed via /smuve dump: not in any AuraUtil.AuraFilters category (the full list is
-- BigDefensive, Cancelable, CrowdControl, Dispellable, ExternalDefensive, Harmful, Helpful,
-- Important, IncludeNameplateOnly, Maw, NotCancelable, Player, Raid, RaidInCombat,
-- RaidPlayerDispellable - nothing for "grants movement immunity"), and nothing on the aura data
-- itself works as a generic signal either (dispelName is shared by far too many unrelated
-- buffs). Matched via its own AddAuraGroup + candidateFilters.includeSpellIDs (below, on the
-- "important" tier) - found by reading how BetterBlizzPlates' "forever" build
-- (github.com/Bodify/BetterBlizzPlates, forever/modules/auras.lua) solves the exact same gap for
-- its Personal Resource Display. This only works here because these are HELPFUL auras on an
-- assistable unit (player, or a friendly target) - Blizzard's AuraContainerUtil silently refuses
-- the same trick for HARMFUL auras on an assistable unit (confirmed by reading mini-auras,
-- github.com/Verubato/mini-auras), which is why EXTRA_IMPORTANT_DEBUFFS below needs a different,
-- hand-rolled mechanism instead. Still kept deliberately tiny and explicit, not a real spell
-- database.
local EXTRA_IMPORTANT_SPELLS = {
    [1044] = true,  -- Blessing of Freedom
    [5599] = true,  -- Blessing of Protection (confirmed live: 0 matches across all 4 categories)
    [5573] = true,  -- Divine Protection (same)
    [20600] = true, -- Perception
    [20216] = true, -- Divine Favor
    [1277462] = true, -- Contingency Plan
    [14751] = true, -- Inner Focus
    [6346] = true, -- Fear Ward
}

-- Same idea as EXTRA_IMPORTANT_SPELLS, but for harmful debuffs worth flagging that aren't crowd
-- control and aren't in AF.Important either (e.g. Weakened Soul: not dangerous by itself, but
-- important to know you can't be shielded again).
local EXTRA_IMPORTANT_DEBUFFS = {
    [6788] = true, -- Weakened Soul
}

local hosts = {}     -- unit -> { frame, cc, importantDebuff, bigDefensive, externalDefensive, important, generation }
local generation = 0
M.hosts = hosts -- read by /smuve dump (debug.bigDebuffs)

local function DB()
    return S.db.bigDebuffs
end

local function Supported()
    return AF and CreateFilterString and AuraContainerSortMethod ~= nil
end

-- A plain icon masked to the portrait's own circle, with a duration timer at the bottom; no
-- border or stack count - it's meant to read as "the portrait itself changed", not as another
-- aura icon among others. The duration text, when shown, uses the same "8m" (white number,
-- yellow unit) format as the player's own auras (Modules\Auras.lua), via the formatter the
-- target/focus auras already share from Modules\Nameplates.lua for the same look.
local function InitIcon(button, size, maskAtlas, showDuration, durationSize)
    button:SetSize(size, size)
    if button.SetFlattensRenderLayers then
        button:SetFlattensRenderLayers(true)
    end

    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(button)
    icon:SetTexCoord(0.04, 0.96, 0.04, 0.96)
    button:SetIcon(icon)

    local mask = button:CreateMaskTexture()
    mask:SetAllPoints(icon)
    mask:SetAtlas(maskAtlas, false)
    icon:AddMaskTexture(mask)

    if showDuration then
        -- SetDurationText reads its timer data off the button's duration COOLDOWN object, not
        -- off the aura data directly - without one set, there's nothing for it to pull from and
        -- the text never updates (confirmed live: every other InitButton in this addon, e.g.
        -- Nameplates.lua's, always sets one up first). The swipe/countdown-number visuals that
        -- normally come with it are turned off since they wouldn't match the circular mask.
        local cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
        cooldown:SetAllPoints(button)
        cooldown:SetHideCountdownNumbers(true)
        cooldown:SetDrawSwipe(false)
        cooldown:SetDrawBling(false)
        button:SetDurationCooldown(cooldown)

        local timer = button:CreateFontString(nil, "OVERLAY")
        timer:SetFont(S:GetFont(), durationSize, "OUTLINE")
        timer:SetTextColor(1, 1, 1)
        timer:SetPoint("CENTER", button, "CENTER", 0, 0)
        local formatter = S.modules.Nameplates.GetUnitDurationFormatter and S.modules.Nameplates.GetUnitDurationFormatter()
        button:SetDurationText(timer, formatter and { textFormatter = formatter } or {})
    end

    if button.SetCancelAuraButtons then
        button:SetCancelAuraButtons(nil)
    end
    button:EnableMouse(false)
end

local function CreateIcon(frame, filter, size, maskAtlas, showDuration, durationSize)
    local container = CreateFrame("AuraContainer", nil, frame, "CustomAuraContainerTemplate")
    container:SetEnabled(false)
    container:Hide()
    if container.SetFlattensRenderLayers then
        container:SetFlattensRenderLayers(true)
    end
    container:SetFlowLayoutAnchorPoint("TOPLEFT")
    container:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
    container:AddAuraGroup("Icon", filter, {
        maxFrameCount = 1,
        sortMethod = AuraContainerSortMethod.Default,
        sortDirection = AuraContainerSortDirection.Normal,
        initializeFrame = function(button)
            InitIcon(button, size, maskAtlas, showDuration, durationSize)
        end,
        layout = {
            elementSpacing = 0,
            lineSpacing = 0,
            elementWidth = size,
            elementHeight = size,
            layoutIndex = 1,
        },
    })
    return container
end

-- Manual curated-debuff icon, bypassing AddAuraGroup entirely -------------------------------------
-- Blizzard's AuraContainerUtil silently gates candidateFilters.includeSpellIDs by
-- UnitCanAssist("player", unit): a HARMFUL aura's spell-ID map only applies when the unit is NOT
-- assistable, while a HELPFUL aura's only applies when it IS - confirmed by reading mini-auras'
-- own AuraFilters.lua (github.com/Verubato/mini-auras), which hits the identical wall for its
-- portrait display and gives up on the curated list there (its dropSpellIds option) rather than
-- fight it. "player" (and a friendly "target") is always assistable, so EXTRA_IMPORTANT_DEBUFFS
-- can never be matched through AddAuraGroup there - no filter string tweak fixes this, it's the
-- engine's own identity check. So this polls the unit's real harmful auras directly instead and
-- drives a plain icon by hand, the same technique the test-mode preview below already uses.
--
-- This icon never actually renders round, no matter how it's masked - confirmed live through
-- several approaches (a fresh CreateMaskTexture+SetAtlas copy, reusing Blizzard's own existing
-- portrait mask object directly, every combination of SetFlattensRenderLayers, with and without a
-- Cooldown frame in the mix): every one of them reports perfectly correct state via /smuve dump
-- (mask attached, right atlas, right size, shown) and still renders as a plain square in-game. So
-- rather than a true mask, this leans on a much simpler trick instead, found by testing it live:
-- oversized by MANUAL_ICON_OVERSCALE and centered on the portrait, its square corners end up
-- hidden behind the portrait frame's own decorative border artwork (which draws above it), making
-- it read as round in practice without actually being clipped. Confirmed live that 1.1x still
-- left the corners peeking out past the border; 1.2x fully hides them without the icon reading as
-- oversized. The mask is still applied below anyway (harmless, and free in case some future
-- client update makes it actually take effect).
--
-- SCOPE: this overscale trick is ONLY needed for this one manual icon, used ONLY for curated
-- harmful debuffs (EXTRA_IMPORTANT_DEBUFFS) on the player/target portrait, built outside
-- AddAuraGroup for the identity-gate reason above. It does not apply anywhere else in this
-- addon: every other icon - the rest of BigDebuffs' own tiers (cc/bigDefensive/externalDefensive/
-- important, all via CreateIcon/InitIcon below) included - goes through a real AddAuraGroup-
-- created button and masks round correctly without it. Don't carry this workaround over to
-- Nameplates.lua, PartyFrames.lua, Auras.lua or UnitAuras.lua; none of them build a manual,
-- non-AddAuraGroup icon the way this one does, so none of them hit this masking quirk at all.
local MANUAL_ICON_OVERSCALE = 1.2
local UNIT_COLOR = "|cffffd100"

local function FormatRemaining(seconds)
    if seconds < 60 then
        return math.ceil(seconds) .. UNIT_COLOR .. "s|r"
    elseif seconds < 3600 then
        return math.ceil(seconds / 60) .. UNIT_COLOR .. "m|r"
    elseif seconds < 86400 then
        return math.ceil(seconds / 3600) .. UNIT_COLOR .. "h|r"
    end
    return math.ceil(seconds / 86400) .. UNIT_COLOR .. "d|r"
end

local function CreateManualIcon(frame, size, existingMask, maskAtlas, showDuration, durationSize)
    local icon = CreateFrame("Frame", nil, frame)
    icon:SetSize(size, size)
    icon:Hide()
    -- false (mini-auras' own choice for its portrait icons): true composites only the icon's own
    -- subtree, which breaks a mask living elsewhere in the frame tree, like existingMask below.
    -- Neither setting actually renders this round in practice - see the big comment above.
    if icon.SetFlattensRenderLayers then
        icon:SetFlattensRenderLayers(false)
    end

    local art = icon:CreateTexture(nil, "ARTWORK")
    art:SetAllPoints(icon)
    art:SetTexCoord(0.04, 0.96, 0.04, 0.96)
    if existingMask then
        -- Blizzard's own mask, already masking the portrait correctly - reused directly rather
        -- than a fresh CreateMaskTexture+SetAtlas copy. Kept despite neither one visibly working.
        art:AddMaskTexture(existingMask)
    else
        local mask = icon:CreateMaskTexture()
        mask:SetAllPoints(art)
        mask:SetAtlas(maskAtlas, false)
        art:AddMaskTexture(mask)
    end
    icon.art = art

    -- No Cooldown frame at all: mini-auras needed a specially-built masked swipe texture
    -- (glowStyles:MaskSwipeTexture) just to make a Cooldown's own layers respect a circular
    -- mask applied to a sibling texture - they don't by default, regardless of DrawSwipe/
    -- DrawEdge/DrawBling, which is what was squaring off this icon's silhouette. Since the pie
    -- swipe itself was already fully suppressed by intent (only the text timer below is wanted),
    -- it's simplest to just not create one at all rather than fight its default layers.

    if showDuration then
        local timer = icon:CreateFontString(nil, "OVERLAY")
        timer:SetFont(S:GetFont(), durationSize, "OUTLINE")
        timer:SetTextColor(1, 1, 1)
        timer:SetPoint("CENTER", icon, "CENTER", 0, 0)
        icon.timer = timer
    end

    return icon
end

-- Finds the first active debuff (if any) whose spellId is in the given curated set.
local function FindCuratedDebuff(unit, spellSet)
    local index = 1
    while true do
        local ok, auraData = pcall(C_UnitAuras.GetAuraDataByIndex, unit, index, "HARMFUL")
        if not ok or not auraData then
            return nil
        end
        if spellSet[auraData.spellId] then
            return auraData
        end
        index = index + 1
    end
end

local function UpdateManualIcon(unit, icon)
    local auraData = FindCuratedDebuff(unit, EXTRA_IMPORTANT_DEBUFFS)
    if not auraData then
        if icon.ticker then
            icon.ticker:Cancel()
            icon.ticker = nil
        end
        icon:Hide()
        return
    end
    icon.art:SetTexture(auraData.icon)
    local hasTime = auraData.duration and auraData.duration > 0 and auraData.expirationTime
    if icon.timer then
        if hasTime then
            local function Refresh()
                local remaining = auraData.expirationTime - GetTime()
                icon.timer:SetText(remaining > 0 and FormatRemaining(remaining) or "")
            end
            Refresh()
            if icon.ticker then
                icon.ticker:Cancel()
            end
            icon.ticker = C_Timer.NewTicker(1, Refresh)
        else
            if icon.ticker then
                icon.ticker:Cancel()
                icon.ticker = nil
            end
            icon.timer:SetText("")
        end
    end
    icon:Show()
end

local function DisableHost(host)
    for _, key in ipairs(TIERS) do
        if host[key] then
            if key == "importantDebuff" then
                if host[key].ticker then
                    host[key].ticker:Cancel()
                end
            elseif host[key].SetEnabled then
                host[key]:SetEnabled(false)
            end
            host[key]:Hide()
            host[key] = nil
        end
    end
end

local function Build(unit)
    local frame = _G[FRAMES[unit]]
    local info = PORTRAITS[unit]
    local portraitContainer = frame and info and frame[info.container]
    local portrait = portraitContainer and portraitContainer[info.texture]
    if not frame or not portrait then
        return
    end
    local host = hosts[unit] or {}
    hosts[unit] = host

    if host.generation ~= generation then
        DisableHost(host)
        host.generation = generation
    end

    if not DB()[unit].enabled then
        DisableHost(host)
        return
    end

    -- A plain decorative texture, not a protected one (confirmed by Modules\UnitFrames.lua
    -- already reading/darkening portrait-adjacent textures the same way elsewhere), so its size
    -- is safe to read directly rather than needing a saved default.
    local width, height = portrait:GetWidth(), portrait:GetHeight()
    if not width or width <= 0 or not height or height <= 0 then
        return -- try again once it actually has a size
    end
    local size = math.min(width, height)

    if not host.cc then
        local notBig, notExternal = "!" .. AF.BigDefensive, "!" .. AF.ExternalDefensive
        local showDuration = DB().showDuration
        local durationSize = DB().durationSize
        -- Parented to the portrait's own container (not the top-level unit frame) and leveled
        -- just above it: the level badge lives in a separate sibling frame (TargetFrameContent /
        -- PlayerFrameContent) that already draws above this container in the undisturbed UI, so
        -- a small offset from the container's own level clears the portrait without having to
        -- guess how far above everything else on the frame to go.
        -- AF.IncludeNameplateOnly: despite the name, this isn't about displaying on a nameplate -
        -- it's needed to even match some of these spells at all (confirmed live: missing it is
        -- why Blessing of Protection/Freedom were invisible here while working fine on the
        -- nameplates, Modules\Nameplates.lua, which already includes it in this exact filter).
        host.cc = CreateIcon(portraitContainer, CreateFilterString(AF.Harmful, AF.IncludeNameplateOnly, AF.CrowdControl), size, info.mask, showDuration, durationSize)
        -- Harmful counterpart to the "important" buff tier below: a debuff that isn't CC but is
        -- still worth flagging (e.g. Weakened Soul). Not an AddAuraGroup container at all, unlike
        -- every other tier - see CreateManualIcon above for why includeSpellIDs can never work for
        -- a curated harmful debuff on this unit.
        -- Oversized by MANUAL_ICON_OVERSCALE - see the big comment on CreateManualIcon above for
        -- why (masking it properly round never worked; this hides the square corners behind the
        -- portrait's own border art instead).
        host.importantDebuff = CreateManualIcon(portraitContainer, size * MANUAL_ICON_OVERSCALE, info.maskChild and portraitContainer[info.maskChild], info.mask, showDuration, durationSize)
        host.bigDefensive = CreateIcon(portraitContainer, CreateFilterString(AF.Helpful, AF.IncludeNameplateOnly, AF.BigDefensive), size, info.mask, showDuration, durationSize)
        host.externalDefensive = CreateIcon(portraitContainer, CreateFilterString(AF.Helpful, AF.IncludeNameplateOnly, notBig, AF.ExternalDefensive), size, info.mask, showDuration, durationSize)
        host.important = CreateIcon(portraitContainer, CreateFilterString(AF.Helpful, AF.IncludeNameplateOnly, notBig, notExternal, AF.Important), size, info.mask, showDuration, durationSize)
        -- EXTRA_IMPORTANT_SPELLS needs its OWN aura group, not candidateFilters bolted onto the
        -- "Icon" group above: a group's filterString and its candidateFilters are ANDed together,
        -- not alternatives - includeSpellIDs can only narrow what the filter string already
        -- matches, never add something the filter string excludes (confirmed live: Blessing of
        -- Freedom still never showed up here with SetAuraGroupCandidateFilters("Icon", ...), since
        -- "Icon"'s filter string requires AF.Important membership and these spells have none).
        -- BetterBlizzPlates' own matching group uses a broad HELPFUL filter with no category
        -- requirement at all, not the already-curated one - that's the part that actually makes
        -- includeSpellIDs work.
        host.important:AddAuraGroup("Extra", CreateFilterString(AF.Helpful, AF.IncludeNameplateOnly), {
            maxFrameCount = 1,
            candidateFilters = { includeSpellIDs = EXTRA_IMPORTANT_SPELLS },
            initializeFrame = function(button)
                InitIcon(button, size, info.mask, showDuration, durationSize)
            end,
            layout = {
                elementSpacing = 0,
                lineSpacing = 0,
                elementWidth = size,
                elementHeight = size,
                layoutIndex = 2,
            },
        })
        -- A new frame's strata defaults to MEDIUM regardless of its parent's - it isn't
        -- inherited - so left unset, these could outrank a higher-stratum sibling like the
        -- frame's glow/status texture even with a deliberately low frame level. Pinned to the
        -- unit frame's own stratum so frame level is what actually decides the ordering.
        for index, key in ipairs(TIERS) do
            host[key]:SetFrameStrata(frame:GetFrameStrata())
            host[key]:SetFrameLevel(portraitContainer:GetFrameLevel() + (#TIERS - index) + 1)
        end
    end

    for _, key in ipairs(TIERS) do
        local container = host[key]
        container:ClearAllPoints()
        container:SetPoint("CENTER", portrait, "CENTER", 0, 0)
        if key == "importantDebuff" then
            -- Manual Frame, not an AuraContainer - its own Show()/Hide() is driven by whether a
            -- curated debuff is actually found, not shown unconditionally like the others.
            UpdateManualIcon(unit, container)
        else
            container:SetUnit(unit)
            container:SetEnabled(true)
            container:Show()
            if container.UpdateAllAuras then
                container:UpdateAllAuras()
            end
        end
    end
end

-- SafeBuild below only ever reports its FIRST error for the whole session (M.reported), so any
-- later real error (e.g. inside an AddAuraGroup call added after that first one) goes completely
-- silent - confirmed as a real gap while chasing why Weakened Soul never matches. This gives
-- /smuve dump a way to see the raw pcall result right now, bypassing that suppression.
M.DebugBuild = function(unit)
    return pcall(Build, unit)
end

local function SafeBuild(unit)
    local ok, err = pcall(Build, unit)
    if not ok and not M.reported then
        M.reported = true
        geterrorhandler()(err)
    end
end

function M:BuildAll()
    for _, unit in ipairs(UNITS) do
        SafeBuild(unit)
    end
end

-- Test mode -----------------------------------------------------------------------------------
-- Real containers only show a real CC/important aura, so the test mode draws one stand-in icon
-- over each portrait, regardless of the "Enable" toggle, so sizing can be checked before turning
-- the real thing on - same convention as the nameplates' and target frame's test modes.

local SAMPLE_CC_ICON = 136071 -- Polymorph

local previews = {} -- unit -> icon frame

local function ShowPreview(unit)
    local frame = _G[FRAMES[unit]]
    local info = PORTRAITS[unit]
    local portraitContainer = frame and info and frame[info.container]
    local portrait = portraitContainer and portraitContainer[info.texture]
    if not frame or not portrait then
        return
    end
    local width, height = portrait:GetWidth(), portrait:GetHeight()
    if not width or width <= 0 or not height or height <= 0 then
        return
    end
    local size = math.min(width, height)
    local icon = previews[unit]
    if icon and icon.generation ~= generation then
        if icon.ticker then
            icon.ticker:Cancel()
        end
        icon:Hide()
        icon = nil
        previews[unit] = nil
    end
    if not icon then
        icon = CreateFrame("Frame", nil, portraitContainer)
        icon.generation = generation
        icon:SetFrameStrata(frame:GetFrameStrata())
        icon:SetFrameLevel(portraitContainer:GetFrameLevel() + 10)
        local art = icon:CreateTexture(nil, "ARTWORK")
        art:SetAllPoints(icon)
        art:SetTexture(SAMPLE_CC_ICON)
        art:SetTexCoord(0.04, 0.96, 0.04, 0.96)
        local mask = icon:CreateMaskTexture()
        mask:SetAllPoints(art)
        mask:SetAtlas(info.mask, false)
        art:AddMaskTexture(mask)

        -- There's no real aura behind the sample icon for SetDurationText to read a timer off
        -- of, so the countdown is just faked here: a plain 10s-to-1s-to-10s loop, in the same
        -- centered, white-number-yellow-unit look as the real icon's duration text.
        local timer = icon:CreateFontString(nil, "OVERLAY")
        timer:SetFont(S:GetFont(), DB().durationSize, "OUTLINE")
        timer:SetTextColor(1, 1, 1)
        timer:SetPoint("CENTER", icon, "CENTER", 0, 0)
        icon.timer = timer
        icon.count = 10
        timer:SetText(icon.count .. "|cffffd100s|r")
        icon.ticker = C_Timer.NewTicker(1, function()
            icon.count = icon.count - 1
            if icon.count < 1 then
                icon.count = 10
            end
            icon.timer:SetText(icon.count .. "|cffffd100s|r")
        end)

        previews[unit] = icon
    end
    icon.timer:SetShown(DB().showDuration)
    icon:SetSize(size, size)
    icon:ClearAllPoints()
    icon:SetPoint("CENTER", portrait, "CENTER", 0, 0)
    icon:Show()
end

local function HidePreview(unit)
    local icon = previews[unit]
    if icon then
        icon:Hide()
    end
end

function M:UpdateTestMode()
    for _, unit in ipairs(UNITS) do
        if DB().testMode and not InCombatLockdown() then
            S.SafeCall(ShowPreview, unit)
        else
            HidePreview(unit)
        end
    end
end

-- Module -------------------------------------------------------------------------------------------

function M:Init()
    if not Supported() then
        return
    end
    DB().testMode = false -- always off after a reload
    S:On("PLAYER_TARGET_CHANGED", function()
        local host = hosts.target
        if host and host.cc then
            for _, key in ipairs(TIERS) do
                local container = host[key]
                if key == "importantDebuff" then
                    UpdateManualIcon("target", container)
                else
                    container:SetUnit("target")
                    if container.UpdateAllAuras then
                        container:UpdateAllAuras()
                    end
                end
            end
        end
    end)
    -- The manual icon isn't an AuraContainer, so it doesn't get the client's own internal aura
    -- refresh the other tiers do just from being bound via SetUnit - it needs its own event.
    S:On("UNIT_AURA", function(_, unit)
        local host = hosts[unit]
        if host and host.importantDebuff then
            UpdateManualIcon(unit, host.importantDebuff)
        end
    end)
    S:On("PLAYER_REGEN_DISABLED", function()
        for _, unit in ipairs(UNITS) do
            HidePreview(unit)
        end
    end)
    S:On("PLAYER_REGEN_ENABLED", function()
        if DB().testMode then
            M:UpdateTestMode()
        end
    end)
    -- Safety net, same convention as Modules\Auras.lua's duration-takeover ticker: cheap to repeat
    -- (UpdateManualIcon is a no-op redraw when nothing changed) and covers any aura change that
    -- doesn't fire UNIT_AURA the way expected (e.g. a duration tick without a stack/application
    -- change).
    C_Timer.NewTicker(2, function()
        for unit, host in pairs(hosts) do
            if host.importantDebuff then
                UpdateManualIcon(unit, host.importantDebuff)
            end
        end
    end)
end

function M:Refresh()
    if not Supported() then
        return
    end
    generation = generation + 1
    self:BuildAll()
    self:UpdateTestMode()
end

function M:IsSupported()
    return Supported()
end
