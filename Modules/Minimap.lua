local _, S = ...
local M = S:NewModule("Minimap")

-- Addon buttons around the minimap are hidden. Right-clicking the map opens a box next to it with
-- the hidden buttons in a grid; it closes on the next right-click or a few seconds after the mouse
-- leaves the minimap and the box. Single buttons can be kept on the minimap from the options
-- ("Map & Minimap"); those stay where their addon put them.

local HIDE_DELAY = 3
local CELL = 34
local PADDING = 8
local MAX_COLUMNS = 6

-- Square shape ---------------------------------------------------------------------------------
-- Only the map's own terrain shape - the round border and buttons stay exactly as they are.
-- Minimap draws its terrain through a mask texture, same as any other masked region
-- (Minimap:SetMaskTexture); 130937/186178 are Blizzard's own stock square/circular masks,
-- confirmed via EllesmereUI's source (EllesmereUIMinimap/EUI_Minimap_Apply.lua, same client) as
-- the exact values it uses for this. GetMinimapShape is a global function several unrelated
-- addons' own map-pin/button placement code calls to ask the map's current shape - overriding it
-- is what keeps their edge-clamping correct once the terrain itself is square; left untouched if
-- another addon already defined it, the same caution EllesmereUI's own source takes.
local SQUARE_MASK = 130937
local ROUND_MASK = 186178
local function SquareShapeFn() return "SQUARE" end

local function ApplySquareShape()
    if not Minimap or not Minimap.SetMaskTexture then
        return
    end
    local square = S.db.minimap.squareMap
    Minimap:SetMaskTexture(square and SQUARE_MASK or ROUND_MASK)
    if Minimap.SetArchBlobRingScalar then
        Minimap:SetArchBlobRingScalar(square and 0 or 1)
    end
    if Minimap.SetQuestBlobRingScalar then
        Minimap:SetQuestBlobRingScalar(square and 0 or 1)
    end
    if GetMinimapShape == nil or GetMinimapShape == SquareShapeFn then
        GetMinimapShape = square and SquareShapeFn or nil
    end
end

-- MinimapCompassTexture (atlas UI-HUD-Minimap-Frame) is the circular ring drawn over the terrain -
-- confirmed via /smuve dump as the only full-size overlay on Minimap itself, and already one of
-- DarkMode.lua's own tracked paths (DarkenMinimap), which only ever tints it, never shows/hides
-- it, so hiding it here doesn't fight that. Squaring the mask without removing this would leave a
-- round ring sitting over square corners.
--
-- In its place: a thin recessed/sunken border (InsetFrameTemplate) - the same one
-- Modules\ReleaseNotes.lua's own inner scroll area and Options.lua's inset panels already use,
-- just not the heavy ornate outer window border (PortraitFrameTemplate) tried first and rejected
-- live as looking wrong at this size - applied directly to a plain proxy frame sized to match
-- Minimap exactly. NineSliceUtil.ApplyLayoutByName works on any frame, not just one built from a
-- bordered template (confirmed via its own source, Blizzard_SharedXML/NineSlice.lua: it creates
-- whatever border pieces the container doesn't already have) - both layout names confirmed real,
-- currently-registered ones (not just CreateFrame template names) via /smuve dump of the client's
-- own NineSliceLayouts table. The proxy is parented to MinimapBackdrop for the same frame-level
-- reason the plain border this replaced was (MinimapBackdrop, level 4, draws above Minimap's own
-- level 3 - see git history for the live-confirmed detail), but sized/positioned to Minimap's own
-- bounds with SetAllPoints so the border traces the actual terrain, not the larger backdrop. Its
-- pieces are darkened the same way as everything else dark mode touches (S:DarkenRegions, which
-- just walks every texture region of a frame - no need to know InsetFrameTemplate's exact piece
-- names for that), requested live since this layout's plain metal look (unlike the ornate one
-- tried first) takes a flat tint fine.
local nineSliceBorder

local function GetNineSliceBorder()
    if nineSliceBorder then
        return nineSliceBorder
    end
    if not (NineSliceUtil and NineSliceUtil.ApplyLayoutByName) then
        return nil
    end
    local host = MinimapBackdrop or Minimap
    nineSliceBorder = CreateFrame("Frame", nil, host)
    nineSliceBorder:SetAllPoints(Minimap)
    nineSliceBorder:SetFrameLevel(host:GetFrameLevel() + 1)
    NineSliceUtil.ApplyLayoutByName(nineSliceBorder, "InsetFrameTemplate")
    return nineSliceBorder
end

-- The round day/night (sun/moon) indicator is a separate client widget, not GameTimeFrame (the
-- calendar button, left alone - see below) and not a Polestar pin (confirmed live: it stayed with
-- every addon disabled, SmuveUI included). /fstack on it pointed at
-- Interface/AddOns/Blizzard_Minimap/.../Dial.lua, and its atlases (UI-HUD-Minimap-DayCycle,
-- UI-HUD-Minimap-Frame-Cycle) confirmed it live in a /smuve dump - anchored at
-- MinimapCluster.MinimapContainer's own (55, 86) offset, matching its on-screen corner position.
-- It has no stable name (generated fresh each session, e.g. "27f4364e7b0"), so it's found by its
-- atlas instead, the same technique IsAddonButton above already uses for addon buttons.
local DAY_CYCLE_ATLAS = "UI-HUD-Minimap-DayCycle"

local function FindDayCycleIndicator()
    local container = MinimapCluster and MinimapCluster.MinimapContainer
    if not container then
        return nil
    end
    for _, child in ipairs({ container:GetChildren() }) do
        if child:IsObjectType("Frame") then
            for _, region in ipairs({ child:GetRegions() }) do
                if region:IsObjectType("Texture") and region.GetAtlas and region:GetAtlas() == DAY_CYCLE_ATLAS then
                    return child
                end
            end
        end
    end
    return nil
end

local function ApplySquareBorder()
    if not Minimap then
        return
    end
    local square = S.db.minimap.squareMap
    if MinimapCompassTexture then
        MinimapCompassTexture:SetShown(not square)
    end
    local dayCycle = FindDayCycleIndicator()
    if dayCycle then
        dayCycle:SetShown(not square)
    end
    -- GameTimeFrame (the actual calendar button) is deliberately left alone: confirmed live that
    -- it's the real calendar icon, unrelated to the sun/moon indicator above.
    local border = GetNineSliceBorder()
    if border then
        border:SetShown(square)
        S:DarkenRegions(border)
    end
end

-- MinimapCluster.MinimapContainer (which just centers Minimap inside itself, 253x253 around a
-- 198x198 map) sits below the zone/time header with a gap - confirmed via /smuve dump as
-- deliberate breathing room for the round shape's curve, but it just reads as dead space once the
-- map is square. Closed by moving the container up so Minimap's own visible top edge (not the
-- padded container's) lands right at the cluster's own top edge, computed from the container's
-- own live size rather than hardcoded, so this keeps working if its dimensions ever change. No
-- longer reserving the header's own height above that: since ApplyHeaderOverlay below moves the
-- header's content onto the terrain itself instead of leaving it in its own bar, there's no
-- separate header row left to leave room for. The container's original anchor is captured once
-- and restored exactly when square mode turns back off, rather than guessing round mode's own
-- numbers.
local originalContainerPoint
local POSITION_GAP = 2

local function ApplySquarePosition()
    local container = MinimapCluster and MinimapCluster.MinimapContainer
    if not container or not Minimap then
        return
    end
    if not originalContainerPoint then
        local point, relativeTo, relativePoint, x, y = container:GetPoint(1)
        if point then
            originalContainerPoint = { point, relativeTo, relativePoint, x, y }
        end
    end
    if S.db.minimap.squareMap then
        -- The container's own top edge needs to sit ABOVE the cluster's top edge by (pad - gap):
        -- it's padded by `pad` above Minimap's own visible top, so it has to move up by more than
        -- just the gap alone to actually close the gap - using just "-gap" here (an earlier version
        -- of this, back when a header height was still subtracted too) moved the container DOWN
        -- instead, confirmed live as making the gap bigger, not smaller.
        local pad = (container:GetHeight() - Minimap:GetHeight()) / 2
        local x = originalContainerPoint and originalContainerPoint[4] or 0
        container:ClearAllPoints()
        container:SetPoint("TOP", MinimapCluster, "TOP", x, pad - POSITION_GAP)
    elseif originalContainerPoint then
        container:ClearAllPoints()
        container:SetPoint(unpack(originalContainerPoint))
    end
end

-- Shared by the coordinates, zone and clock text below, so all three end up at the same size with
-- the same outline instead of each drifting independently - confirmed live they all share the same
-- original size (10) to begin with, so one shared increase keeps them that way.
local MINIMAP_TEXT_SIZE_INCREASE = 2

local function AddOutlineFlag(flags)
    if type(flags) == "string" and flags ~= "" then
        if flags:find("OUTLINE", 1, true) then
            return flags
        end
        return flags .. ",OUTLINE"
    end
    return "OUTLINE"
end

-- Coordinates and clock both sit in the footer strip below the square border, each anchored by its
-- own bottom edge - but PlayerCoords (10px tall) and TimeManagerClockButton (16px tall) aren't the
-- same height, so giving them the identical raw Y offset (tried live) lines up their bottom edges,
-- not their visual centers where the text actually sits - the taller clock frame then floats
-- noticeably higher than the shorter coords frame for the same padding number. This computes each
-- one's own bottom-edge offset from a single shared target center instead, reading each frame's
-- live height rather than hardcoding the half-height difference between them, so the two actually
-- align regardless of which one's size changes later.
local FOOTER_CENTER_Y = -11

local function FooterBottomOffset(frame)
    return FOOTER_CENTER_Y - frame:GetHeight() / 2
end

-- Player coordinates text (MinimapContainer.PlayerCoords/.CoordText) - handled the same deliberate
-- way as the clock below instead of left at whatever its own native anchor happened to be: an
-- earlier version left position/size untouched entirely, confirmed live as looking inconsistent
-- (noticeably smaller, oddly placed) next to the zone text and clock once those got the same
-- treatment. Runs before ApplyClockPosition/ApplyMailPosition below (see the call order where
-- these are invoked) since both of those read this text's current position to line themselves up
-- with it - they need the position this sets, not whatever it was before.
local originalCoordsPoint
local originalCoordFont
local originalCoordTextPoints

local function ApplyCoordsPosition()
    local container = MinimapCluster and MinimapCluster.MinimapContainer
    local coords = container and container.PlayerCoords
    if not coords or not Minimap then
        return
    end
    local coordText = coords.CoordText
    if not originalCoordsPoint then
        local point, relativeTo, relativePoint, x, y = coords:GetPoint(1)
        if point then
            originalCoordsPoint = { point, relativeTo, relativePoint, x, y }
        end
    end
    if coordText and not originalCoordFont then
        local file, size, flags = coordText:GetFont()
        if file then
            originalCoordFont = { file, size, flags }
        end
    end
    -- CoordText itself is anchored TOPLEFT+BOTTOMRIGHT to PlayerCoords, filling that frame's fixed
    -- 90x10 box exactly - confirmed live via /smuve dump (GetHeight stuck at 10 while GetStringHeight
    -- grew to ~11.7 with the bigger font, unlike the zone/clock text, both anchored by a single
    -- point and free to size themselves) as the reason it looked visually smaller/clipped next to
    -- them despite sharing the same font size. Re-anchored to a single CENTER point instead, same
    -- fix as MinimapZoneText's own width constraint above, so it can size itself to the larger font.
    if coordText and not originalCoordTextPoints then
        originalCoordTextPoints = {}
        for i = 1, coordText:GetNumPoints() do
            local point, relativeTo, relativePoint, x, y = coordText:GetPoint(i)
            table.insert(originalCoordTextPoints, { point, relativeTo, relativePoint, x, y })
        end
    end
    if S.db.minimap.squareMap then
        coords:ClearAllPoints()
        coords:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, FooterBottomOffset(coords))
        coords:SetShown(S.db.minimap.showCoords)
        if coordText and originalCoordFont then
            coordText:SetFont(originalCoordFont[1], originalCoordFont[2] + MINIMAP_TEXT_SIZE_INCREASE,
                AddOutlineFlag(originalCoordFont[3]))
            coordText:ClearAllPoints()
            coordText:SetPoint("CENTER", coords, "CENTER", 0, 0)
            coordText:SetWidth(0)
            coordText:SetHeight(0)
        end
    else
        if originalCoordsPoint then
            coords:ClearAllPoints()
            coords:SetPoint(unpack(originalCoordsPoint))
            coords:SetShown(true)
        end
        if coordText and originalCoordFont then
            coordText:SetFont(unpack(originalCoordFont))
        end
        if coordText and originalCoordTextPoints then
            coordText:ClearAllPoints()
            for _, point in ipairs(originalCoordTextPoints) do
                coordText:SetPoint(unpack(point))
            end
        end
    end
end

-- The mail indicator (MinimapCluster.IndicatorFrame, holding MailFrame/MiniMapMailIcon) sits right
-- under the header by default - confirmed live that once the gap above is closed, it overlaps the
-- square map's top-left corner. Moved below the map instead, at the same Y the player-coordinates
-- text (MinimapContainer.PlayerCoords) uses (read live, after ApplyCoordsPosition's own nudge, not
-- hardcoded), minus a further 2px requested live once the first attempt looked slightly off.
local originalIndicatorPoint
local originalIndicatorScale
local MAIL_PADDING = 4
local MAIL_Y_NUDGE = 6
local MAIL_FALLBACK_Y = -18 -- only used if PlayerCoords isn't there to read a real value from
local MAIL_SCALE = 0.8

local function ApplyMailPosition()
    local indicator = MinimapCluster and MinimapCluster.IndicatorFrame
    if not indicator or not Minimap then
        return
    end
    if not originalIndicatorPoint then
        local point, relativeTo, relativePoint, x, y = indicator:GetPoint(1)
        if point then
            originalIndicatorPoint = { point, relativeTo, relativePoint, x, y }
        end
    end
    if not originalIndicatorScale then
        originalIndicatorScale = indicator:GetScale()
    end
    if S.db.minimap.squareMap then
        local coords = MinimapCluster.MinimapContainer and MinimapCluster.MinimapContainer.PlayerCoords
        local _, _, _, _, coordY = coords and coords:GetPoint(1)
        indicator:ClearAllPoints()
        indicator:SetPoint("BOTTOMLEFT", Minimap, "BOTTOMLEFT", MAIL_PADDING, (coordY or MAIL_FALLBACK_Y) - MAIL_Y_NUDGE)
        indicator:SetScale(MAIL_SCALE)
        -- Alpha, not SetShown: confirmed live that Hide()-ing this toggled off, then re-showing it,
        -- left the mail icon itself gone even with mail still pending. IndicatorFrame isn't the
        -- only thing driving the icon's own visibility - the client's own "do I have mail" check
        -- also shows/hides the inner MailFrame directly, independently of our wrapper, and a hidden
        -- parent coming back doesn't un-hide a child that got hidden on its own in the meantime;
        -- nothing re-runs that check just because our own setting toggled, since the real mail
        -- state never changed. Alpha never touches that child's own shown state at all.
        indicator:SetAlpha(S.db.minimap.showMail and 1 or 0)
    else
        if originalIndicatorPoint then
            indicator:ClearAllPoints()
            indicator:SetPoint(unpack(originalIndicatorPoint))
            indicator:SetAlpha(1)
        end
        if originalIndicatorScale then
            indicator:SetScale(originalIndicatorScale)
        end
    end
end

-- Removing the header bar's own background and overlaying its contents (zone name, tracking and
-- calendar - the clock moved out on its own below, see ApplyClockPosition) directly on the square
-- terrain's top edge instead - the user's own creative idea for a cleaner square look, after trying
-- just closing the gap above it. Only ZoneTextButton itself is moved: Tracking and GameTimeFrame
-- are both already anchored relative to IT (confirmed via /smuve dump), so they come along
-- automatically without each needing its own reposition. Centered rather than flush left:
-- ZoneTextButton is 152px wide against Minimap's 198px, and Tracking/GameTimeFrame both hang off
-- its outer edges rather than within its own width, so flush-left risked GameTimeFrame running
-- past the map's right edge - centering splits that margin evenly.
--
-- Frame level still needs individual attention though: these pieces are parented to
-- MinimapCluster, not Minimap/MinimapBackdrop, but level ordering is evidently global within a
-- strata on this client regardless of parent chain (the same lesson the border above is built on,
-- Minimap level 3 vs MinimapBackdrop level 4) - Tracking's own level (2) and GameTimeFrame's (4)
-- both sit at or below MinimapBackdrop's (4), so moved onto the terrain unchanged they'd render
-- underneath it; ZoneTextButton (10) was already high enough.
--
-- Readability against moving terrain is the known tradeoff (same reason Modules\Chat.lua's own
-- outline option exists) - mitigated with an outline on the zone text, same treatment already
-- given the coordinates text.
local HEADER_OVERLAY_INSET = 6
local HEADER_OVERLAY_LEVEL = 20

local originalHeaderBgShown
local originalHeaderPoint
local originalZoneTextFont
local originalZoneTextPoint
local originalZoneTextWidth
local originalZoneTextJustify
local originalTrackingLevel
local originalCalendarLevel

local function CaptureLevel(frame)
    return frame.GetFrameLevel and frame:GetFrameLevel() or nil
end

local function ApplyHeaderOverlay()
    local cluster = MinimapCluster
    local header = cluster and cluster.ZoneTextButton
    if not cluster or not header or not Minimap then
        return
    end
    local square = S.db.minimap.squareMap
    local tracking = cluster.Tracking
    local calendar = GameTimeFrame

    local bg = header.StateTexture
    if bg then
        if originalHeaderBgShown == nil then
            originalHeaderBgShown = bg:IsShown()
        end
        bg:SetShown(not square and originalHeaderBgShown)
    end

    if not originalHeaderPoint then
        local point, relativeTo, relativePoint, x, y = header:GetPoint(1)
        if point then
            originalHeaderPoint = { point, relativeTo, relativePoint, x, y }
        end
    end
    if tracking and not originalTrackingLevel then
        originalTrackingLevel = CaptureLevel(tracking)
    end
    if calendar and not originalCalendarLevel then
        originalCalendarLevel = CaptureLevel(calendar)
    end
    if MinimapZoneText and not originalZoneTextFont then
        local file, size, flags = MinimapZoneText:GetFont()
        if file then
            originalZoneTextFont = { file, size, flags }
        end
    end
    if MinimapZoneText and not originalZoneTextPoint then
        local point, relativeTo, relativePoint, x, y = MinimapZoneText:GetPoint(1)
        if point then
            originalZoneTextPoint = { point, relativeTo, relativePoint, x, y }
        end
        originalZoneTextWidth = MinimapZoneText:GetWidth()
        originalZoneTextJustify = MinimapZoneText:GetJustifyH()
    end

    if square then
        header:ClearAllPoints()
        header:SetPoint("TOP", Minimap, "TOP", 0, -HEADER_OVERLAY_INSET)
        if tracking then
            tracking:SetFrameLevel(HEADER_OVERLAY_LEVEL)
            tracking:SetShown(S.db.minimap.showTracking)
        end
        if calendar then
            calendar:SetFrameLevel(HEADER_OVERLAY_LEVEL)
            calendar:SetShown(S.db.minimap.showCalendar)
        end
        if MinimapZoneText and originalZoneTextFont then
            MinimapZoneText:SetFont(originalZoneTextFont[1], originalZoneTextFont[2] + MINIMAP_TEXT_SIZE_INCREASE,
                AddOutlineFlag(originalZoneTextFont[3]))
        end
        if MinimapZoneText then
            -- Centered on the button (itself centered on the map, see above) instead of left-
            -- anchored, and freed from its original fixed width so it grows symmetrically from
            -- that center instead of truncating a long zone name - confirmed live as a real problem
            -- at the old fixed width ("Tranquil Gardens Cem...").
            MinimapZoneText:ClearAllPoints()
            MinimapZoneText:SetPoint("CENTER", header, "CENTER", 0, 0)
            MinimapZoneText:SetWidth(0)
            MinimapZoneText:SetJustifyH("CENTER")
            MinimapZoneText:SetShown(S.db.minimap.showZoneText)
        end
    else
        if originalHeaderPoint then
            header:ClearAllPoints()
            header:SetPoint(unpack(originalHeaderPoint))
        end
        if tracking and originalTrackingLevel then
            tracking:SetFrameLevel(originalTrackingLevel)
            tracking:SetShown(true)
        end
        if calendar and originalCalendarLevel then
            calendar:SetFrameLevel(originalCalendarLevel)
            calendar:SetShown(true)
        end
        if MinimapZoneText and originalZoneTextFont then
            MinimapZoneText:SetFont(unpack(originalZoneTextFont))
        end
        if MinimapZoneText and originalZoneTextPoint then
            MinimapZoneText:ClearAllPoints()
            MinimapZoneText:SetPoint(unpack(originalZoneTextPoint))
            if originalZoneTextWidth then
                MinimapZoneText:SetWidth(originalZoneTextWidth)
            end
            if originalZoneTextJustify then
                MinimapZoneText:SetJustifyH(originalZoneTextJustify)
            end
            MinimapZoneText:SetShown(true)
        end
    end
end

-- The clock (TimeManagerClockButton/.TimeManagerClockTicker) moved to the bottom-right corner,
-- mirroring the mail icon's bottom-left spot and the coordinates text between them - requested
-- live to declutter the top-right corner, which was sharing space with the calendar button.
-- Detached from the header group above (it no longer rides along with ZoneTextButton) and given
-- its own independent anchor/level/font, the same pattern ApplyMailPosition already uses.
local originalClockPoint
local originalClockLevel
local originalClockFont
local CLOCK_PADDING = 4

local function ApplyClockPosition()
    local clock = TimeManagerClockButton
    local clockText = TimeManagerClockTicker
    if not clock or not Minimap then
        return
    end
    if not originalClockPoint then
        local point, relativeTo, relativePoint, x, y = clock:GetPoint(1)
        if point then
            originalClockPoint = { point, relativeTo, relativePoint, x, y }
        end
    end
    if not originalClockLevel then
        originalClockLevel = CaptureLevel(clock)
    end
    if clockText and not originalClockFont then
        local file, size, flags = clockText:GetFont()
        if file then
            originalClockFont = { file, size, flags }
        end
    end
    if S.db.minimap.squareMap then
        -- Mail and coordinates both sit in the footer strip below the square border, not inside
        -- the terrain's own corner - confirmed live as a real mistake in an earlier version of
        -- this, which anchored the clock with a small Y padding meant to tuck it just inside the
        -- map's bottom-right corner instead, landing it in the wrong area entirely (floating
        -- outside/below everything, not alongside mail and coordinates where it belongs). The Y
        -- itself comes from the shared FooterBottomOffset helper above (same one coordinates use),
        -- not a plain constant of its own: a same-valued plain constant here (tried live) still
        -- left it visually off from the coordinates text, since that doesn't account for the two
        -- frames' different heights - see that helper's own comment.
        clock:ClearAllPoints()
        clock:SetPoint("BOTTOMRIGHT", Minimap, "BOTTOMRIGHT", -CLOCK_PADDING, FooterBottomOffset(clock))
        clock:SetFrameLevel(HEADER_OVERLAY_LEVEL)
        clock:SetShown(S.db.minimap.showClock)
        if clockText and originalClockFont then
            clockText:SetFont(originalClockFont[1], originalClockFont[2] + MINIMAP_TEXT_SIZE_INCREASE,
                AddOutlineFlag(originalClockFont[3]))
        end
    else
        if originalClockPoint then
            clock:ClearAllPoints()
            clock:SetPoint(unpack(originalClockPoint))
            clock:SetShown(true)
        end
        if originalClockLevel then
            clock:SetFrameLevel(originalClockLevel)
        end
        if clockText and originalClockFont then
            clockText:SetFont(unpack(originalClockFont))
        end
    end
end

-- Edit Mode re-applies its own saved layout to the minimap system (size/position included)
-- whenever a layout is saved or Edit Mode closes - confirmed live as the reason resizing the map
-- in Edit Mode brought the header gap and the mail icon's default position back: our own SetPoint
-- calls above are an overlay on top of Edit Mode's layout, not part of it, so Edit Mode has no idea
-- to preserve them. Reapplied on the same two triggers other addons use for this: the
-- EDIT_MODE_LAYOUTS_UPDATED event (fires once a layout change is actually saved) and Edit Mode's
-- own manager frame closing (covers a resize that's previewed live but only saved on exit).
local function ReapplySquareLayout()
    if not S.db.minimap.squareMap then
        return
    end
    ApplySquarePosition()
    ApplyHeaderOverlay()
    ApplyCoordsPosition()
    ApplyClockPosition()
    ApplyMailPosition()
end

-- Client buttons that live on the minimap and must never be treated as addon buttons. A bare "LFG"
-- entry used to be here too, meant for Blizzard's own LFG elements (MiniMapLFG below already
-- covers those) - confirmed live as a real bug instead: the "LFG Forever" addon's own button,
-- LFGForeverMinimapButton, also starts with "LFG", so it silently matched and was never
-- hidden/boxed like every other addon button is.
local BLIZZARD_PREFIXES = {
    "Minimap", "MiniMap", "GameTime", "TimeManager", "QueueStatus", "ExpansionLanding", "GarrisonLanding",
    "HybridMinimap", "MinimapBackdrop", "AddonCompartment", "BattlefieldMinimap", "MiniMapLFG",
    "MiniMapBattlefield", "MiniMapMail", "MiniMapTracking", "MiniMapWorldMap", "FeedbackUI",
    "GuildInstanceDifficulty", "MiniMapInstanceDifficulty", "MiniMapChallengeMode", "DurabilityFrame",
    "SmuveUI",
}

local buttons = {}       -- name -> button
local hiddenByUs = {}    -- button -> true
local boxed = {}         -- button -> { parent, points, dragRegistered }
local revealed = false
local outsideSince
local box

local BUTTON_BORDER = 136430 -- Interface\Minimap\MiniMap-TrackingBorder

local function HasButtonBorder(frame)
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:IsObjectType("Texture") then
            local file = region:GetTexture()
            if file == BUTTON_BORDER or (type(file) == "string" and file:lower():find("trackingborder")) then
                return true
            end
        end
    end
    return false
end

local function IsAddonButton(frame)
    if frame:IsForbidden() or frame:IsProtected() then
        return false
    end
    local name = frame:GetName()
    if type(name) ~= "string" or S.IsSecret(name) then
        return false
    end
    if name:find("^LibDBIcon10_") then
        return true
    end
    for _, prefix in ipairs(BLIZZARD_PREFIXES) do
        if name:find("^" .. prefix) then
            return false
        end
    end
    -- Map pins (quest givers, flight masters, ...) are small named frames on the minimap too, so
    -- only real buttons count: named like one, or wearing the standard minimap button border.
    if not frame:IsObjectType("Button") then
        return false
    end
    local lower = name:lower()
    if lower:find("minimapbutton") or lower:find("minimapicon") or lower:find("minimap_button") then
        return true
    end
    return HasButtonBorder(frame)
end

-- A readable name for the options list.
function M:GetButtonLabel(name)
    return (name:gsub("^LibDBIcon10_", ""):gsub("MinimapButton$", ""):gsub("_", " "))
end

local function IsManaged(name)
    return S.db.minimap.hideButtons and not S.db.minimap.alwaysShown[name]
end

-- The box ------------------------------------------------------------------------------------------

local function GetBox()
    if box then
        return box
    end
    box = CreateFrame("Frame", "SmuveUIMinimapButtonBox", UIParent, "BackdropTemplate")
    box:SetFrameStrata("MEDIUM")
    box:SetClampedToScreen(true)
    box:SetBackdrop({
        bgFile = "Interface\\Buttons\\WHITE8X8",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    box:SetBackdropColor(0.04, 0.04, 0.04, 0.92)
    box:SetBackdropBorderColor(0.3, 0.3, 0.3, 1)
    box:SetPoint("TOPRIGHT", Minimap, "TOPLEFT", -12, 0)
    box:EnableMouse(true)
    box:Hide()
    return box
end

local function PutInBox(button, index, columns)
    if not boxed[button] then
        local points = {}
        for i = 1, button:GetNumPoints() do
            points[i] = { button:GetPoint(i) }
        end
        boxed[button] = { parent = button:GetParent(), points = points, strata = button:GetFrameStrata() }
        -- Minimap button dragging moves them around the map; not while they sit in the box.
        if button.RegisterForDrag and button:GetScript("OnDragStart") then
            boxed[button].drag = true
            button:RegisterForDrag()
        end
    end
    local column = (index - 1) % columns
    local row = math.floor((index - 1) / columns)
    button:SetParent(box)
    button:SetFrameStrata(box:GetFrameStrata())
    button:SetFrameLevel(box:GetFrameLevel() + 2)
    button:ClearAllPoints()
    button:SetPoint("CENTER", box, "TOPLEFT", PADDING + column * CELL + CELL / 2, -(PADDING + row * CELL + CELL / 2))
end

local function TakeOutOfBox(button)
    local saved = boxed[button]
    if not saved then
        return
    end
    boxed[button] = nil
    button:SetParent(saved.parent)
    button:SetFrameStrata(saved.strata)
    button:ClearAllPoints()
    for _, point in ipairs(saved.points) do
        button:SetPoint(unpack(point))
    end
    if saved.drag then
        button:RegisterForDrag("LeftButton")
    end
end

-- Addon compartment ---------------------------------------------------------------------------------
-- The client's addon compartment (the numbered dropdown button) is hidden; every addon listed in it
-- gets a minimap style button in the box instead.

local compartmentButtons = {} -- compartment entry -> button

local function NormalizeForMatch(name)
    if type(name) ~= "string" then
        return nil
    end
    return name:lower():gsub("%s+", ""):gsub("^libdbicon10_", "")
end

-- An addon's AddonCompartmentFrame display title and its LibDBIcon dataobject name are two
-- separate registrations with no required relationship between them - confirmed live via /smuve
-- dump as real duplicates (both a real button and a synthesized one for the same addon): "Nova
-- Instance Tracker" vs. dataobject "NovaInstanceTracker", "DungeonJournal" vs.
-- "ForeverDungeonJournal", and a plain-named (non-LibDBIcon) "PolestarMinimapButton" vs. "Polestar"
-- - the exact "LibDBIcon10_" .. entry.text match this used to require missed all three. A
-- case/space-insensitive substring match against every tracked button's name, not just
-- LibDBIcon-prefixed ones, catches all three instead.
local function HasMatchingButton(entryText)
    local norm = NormalizeForMatch(entryText)
    if not norm or norm == "" then
        return false
    end
    for name in pairs(buttons) do
        local normName = NormalizeForMatch(name)
        if normName and (normName:find(norm, 1, true) or norm:find(normName, 1, true)) then
            return true
        end
    end
    return false
end

local function CompartmentEntries()
    local entries = {}
    local compartment = AddonCompartmentFrame
    for _, entry in ipairs(compartment and compartment.registeredAddons or {}) do
        -- Addons that already have their own minimap/LibDBIcon button may list themselves in the
        -- compartment too; their own button is enough, so skip giving them a second one here.
        if type(entry) == "table" and entry.text and not HasMatchingButton(entry.text) then
            table.insert(entries, entry)
        end
    end
    return entries
end

local function CompartmentButton(entry)
    local button = compartmentButtons[entry]
    if button then
        return button
    end
    button = CreateFrame("Button", nil, GetBox())
    button:SetSize(31, 31)
    button:RegisterForClicks("AnyUp")
    button:SetHighlightTexture(136477) -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight

    local background = button:CreateTexture(nil, "BACKGROUND")
    background:SetTexture(136467) -- Interface\Minimap\UI-Minimap-Background
    background:SetSize(20, 20)
    background:SetPoint("TOPLEFT", 7, -5)
    local icon = button:CreateTexture(nil, "ARTWORK")
    icon:SetSize(17, 17)
    icon:SetPoint("TOPLEFT", 7, -6)
    local border = button:CreateTexture(nil, "OVERLAY")
    border:SetTexture(BUTTON_BORDER)
    border:SetSize(53, 53)
    border:SetPoint("TOPLEFT")
    S:Darken(border)
    button.icon = icon

    -- The compartment calls func(button, { buttonName = mouseButton }, menu).
    button:SetScript("OnClick", function(self, mouseButton)
        if self.entry.func then
            local ok, err = pcall(self.entry.func, self, { buttonName = mouseButton }, self)
            if not ok then
                geterrorhandler()(err)
            end
        end
    end)
    button:SetScript("OnEnter", function(self)
        if self.entry.funcOnEnter then
            pcall(self.entry.funcOnEnter, self, self.entry)
        else
            GameTooltip:SetOwner(self, "ANCHOR_LEFT")
            GameTooltip:SetText(self.entry.text, 1, 1, 1)
            GameTooltip:Show()
        end
    end)
    button:SetScript("OnLeave", function(self)
        if self.entry.funcOnLeave then
            pcall(self.entry.funcOnLeave, self, self.entry)
        end
        GameTooltip_Hide()
    end)

    compartmentButtons[entry] = button
    return button
end

local function UpdateCompartmentFrame()
    local compartment = AddonCompartmentFrame
    if not compartment then
        return
    end
    if S.db.minimap.hideButtons then
        compartment:Hide()
        M.compartmentHidden = true
    elseif M.compartmentHidden then
        M.compartmentHidden = false
        compartment:Show()
    end
end

-- Apply --------------------------------------------------------------------------------------------

local function OnButtonShow(button)
    local name = button:GetName()
    if name and IsManaged(name) and not revealed then
        hiddenByUs[button] = true
        button:Hide()
    end
end

function M:GetSortedNames()
    local names = {}
    for name in pairs(buttons) do
        table.insert(names, name)
    end
    table.sort(names, function(a, b) return self:GetButtonLabel(a):lower() < self:GetButtonLabel(b):lower() end)
    return names
end

function M:Apply()
    local inBox = {}
    for _, name in ipairs(self:GetSortedNames()) do
        local button = buttons[name]
        if IsManaged(name) then
            if revealed then
                -- Buttons their own addon hid stay hidden.
                if button:IsShown() or hiddenByUs[button] then
                    table.insert(inBox, button)
                end
            else
                TakeOutOfBox(button)
                if button:IsShown() then
                    hiddenByUs[button] = true
                    button:Hide()
                end
            end
        else
            TakeOutOfBox(button)
            if hiddenByUs[button] then
                hiddenByUs[button] = nil
                button:Show()
            end
        end
    end

    UpdateCompartmentFrame()
    local entries = (revealed and S.db.minimap.hideButtons) and CompartmentEntries() or {}
    for _, button in pairs(compartmentButtons) do
        button:Hide()
    end

    local total = #inBox + #entries
    if revealed and total > 0 then
        local frame = GetBox()
        local columns = math.min(total, MAX_COLUMNS)
        local rows = math.ceil(total / columns)
        frame:SetSize(PADDING * 2 + columns * CELL, PADDING * 2 + rows * CELL)
        frame:Show()
        for index, button in ipairs(inBox) do
            PutInBox(button, index, columns)
            hiddenByUs[button] = nil
            button:Show()
        end
        for offset, entry in ipairs(entries) do
            local button = CompartmentButton(entry)
            button.entry = entry
            button.icon:SetTexture(entry.icon)
            local index = #inBox + offset
            button:ClearAllPoints()
            button:SetPoint("CENTER", frame, "TOPLEFT",
                PADDING + ((index - 1) % columns) * CELL + CELL / 2,
                -(PADDING + math.floor((index - 1) / columns) * CELL + CELL / 2))
            button:Show()
        end
    elseif box then
        box:Hide()
    end
end

-- Scanning -----------------------------------------------------------------------------------------

function M:Scan()
    local found = false
    for _, parent in ipairs({ Minimap or false, MinimapBackdrop or false, MinimapCluster or false }) do
        if parent then
            for _, child in ipairs({ parent:GetChildren() }) do
                local name = child:GetName()
                if type(name) == "string" and not S.IsSecret(name) and not buttons[name] and IsAddonButton(child) then
                    buttons[name] = child
                    child:HookScript("OnShow", OnButtonShow)
                    found = true
                end
            end
        end
    end
    if found then
        self:Apply()
        if S.OptionsRefreshMinimapList then
            S:OptionsRefreshMinimapList()
        end
    end
end

-- Sorted list of { name, label } for the options panel.
function M:GetButtons()
    local list = {}
    for _, name in ipairs(self:GetSortedNames()) do
        table.insert(list, { name = name, label = self:GetButtonLabel(name) })
    end
    return list
end

local function IsMouseOverButtons()
    if Minimap:IsMouseOver() or (box and box:IsShown() and box:IsMouseOver()) then
        return true
    end
    for _, button in pairs(buttons) do
        if button:IsShown() and button:IsMouseOver() then
            return true
        end
    end
    return false
end

function M:SetRevealed(value)
    revealed = value
    outsideSince = nil
    self:Apply()
end

function M:Init()
    if not Minimap then
        return
    end

    ApplySquareShape()
    ApplySquareBorder()
    ApplySquarePosition()
    ApplyHeaderOverlay()
    ApplyCoordsPosition()
    ApplyClockPosition()
    ApplyMailPosition()

    S:On("EDIT_MODE_LAYOUTS_UPDATED", ReapplySquareLayout)
    if EditModeManagerFrame then
        EditModeManagerFrame:HookScript("OnHide", ReapplySquareLayout)
    end

    local compartment = AddonCompartmentFrame
    if compartment then
        compartment:HookScript("OnShow", function(self)
            if S.db.minimap.hideButtons then
                self:Hide()
            end
        end)
        if type(compartment.RegisterAddon) == "function" then
            hooksecurefunc(compartment, "RegisterAddon", function()
                if revealed then
                    M:Apply()
                end
            end)
        end
    end

    -- Right-click opens the box; Shift + right-click does what right-click did before (the ping).
    -- The client's click handler is wrapped so a plain right-click doesn't reach it.
    local originalClick = Minimap:GetScript("OnMouseUp")
    Minimap:SetScript("OnMouseUp", function(self, button, ...)
        if button == "RightButton" and S.db.minimap.hideButtons and not IsShiftKeyDown() then
            M:SetRevealed(not revealed)
            return
        end
        if originalClick then
            return originalClick(self, button, ...)
        end
    end)
    local originalDown = Minimap:GetScript("OnMouseDown")
    if originalDown then
        Minimap:SetScript("OnMouseDown", function(self, button, ...)
            if button == "RightButton" and S.db.minimap.hideButtons and not IsShiftKeyDown() then
                return
            end
            return originalDown(self, button, ...)
        end)
    end

    -- Close the box once the mouse has been away for a moment.
    local watcher = CreateFrame("Frame")
    local elapsedTotal = 0
    watcher:SetScript("OnUpdate", function(_, elapsed)
        elapsedTotal = elapsedTotal + elapsed
        if elapsedTotal < 0.25 then
            return
        end
        elapsedTotal = 0
        if not revealed then
            return
        end
        if IsMouseOverButtons() then
            outsideSince = nil
        elseif not outsideSince then
            outsideSince = GetTime()
        elseif GetTime() - outsideSince >= HIDE_DELAY then
            M:SetRevealed(false)
        end
    end)

    -- Addons create their buttons at different times.
    S:On("PLAYER_ENTERING_WORLD", function()
        M:Scan()
        C_Timer.After(2, function() M:Scan() end)
        C_Timer.After(8, function() M:Scan() end)
    end)
    S:On("ADDON_LOADED", function()
        C_Timer.After(0.5, function() M:Scan() end)
    end)
    local LDBIcon = LibStub and LibStub("LibDBIcon-1.0", true)
    if LDBIcon and LDBIcon.RegisterCallback then
        LDBIcon.RegisterCallback(M, "LibDBIcon_IconCreated", function()
            M:Scan()
        end)
    end
end

function M:Refresh()
    if not S.db.minimap.hideButtons then
        revealed = false
    end
    ApplySquareShape()
    ApplySquareBorder()
    ApplySquarePosition()
    ApplyHeaderOverlay()
    ApplyCoordsPosition()
    ApplyClockPosition()
    ApplyMailPosition()
    self:Scan()
    self:Apply()
end

-- Debug (/smuve dump): chasing a report that some icons show doubled in the box. Prime suspect is
-- CompartmentEntries()'s de-dup check - it only skips creating a synthesized compartment button
-- when buttons["LibDBIcon10_" .. entry.text] already exists, which assumes an addon's
-- AddonCompartmentFrame display title (entry.text) is identical to the dataobject name LibDBIcon
-- used to build its button's name. Those are two separate registrations an addon can give
-- different strings to - if they don't match, both a real LibDBIcon button and a synthesized
-- compartment button end up in the grid for the same addon, overlapping since nothing else
-- distinguishes them from a genuinely different addon.
function M:DebugLines()
    local lines = {}
    table.insert(lines, "== buttons (name -> real minimap/LibDBIcon button)")
    for name in pairs(buttons) do
        table.insert(lines, "  " .. tostring(name) .. " boxed=" .. tostring(boxed[buttons[name]] ~= nil))
    end
    table.insert(lines, "== AddonCompartmentFrame.registeredAddons")
    local compartment = AddonCompartmentFrame
    for _, entry in ipairs(compartment and compartment.registeredAddons or {}) do
        if type(entry) == "table" then
            table.insert(lines, "  text=" .. tostring(entry.text) ..
                " hasMatchingButton=" .. tostring(entry.text and HasMatchingButton(entry.text)) ..
                " gotSynthesizedButton=" .. tostring(compartmentButtons[entry] ~= nil))
        end
    end
    return lines
end
