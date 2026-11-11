local _, S = ...
local M = S:NewModule("DarkMode")

-- Brightness offsets on top of the dark base, so some art stays readable (e.g. the gryphons).
local LIGHTER = 0.15
local ELITE = 0.25

-- Unit frames, cast bars, class resources --------------------------------------------------------

local UNIT_FRAME_TEXTURES = {
    -- Modern player/target/focus frames
    "PlayerFrame.PlayerFrameContainer.FrameTexture",
    "PlayerFrame.PlayerFrameContainer.AlternatePowerFrameTexture",
    "PlayerFrame.PlayerFrameContainer.VehicleFrameTexture",
    "PlayerFrame.PlayerFrameContent.PlayerFrameContentContextual.PlayerPortraitCornerIcon",
    "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.LevelBackgroundCircle",
    "PlayerFrame.PlayerFrameContent.PlayerFrameContentMain.PvpBackgroundCircle",
    -- TargetFrame.TargetFrameContainer.FrameTexture/FocusFrame's own are NOT here - see
    -- ELITE_TEXTURES below, they share this same bronze ring with the elite portrait overlay.
    "TargetFrame.TargetFrameContent.TargetFrameContentMain.LevelBackgroundCircle",
    "TargetFrame.totFrame.FrameTexture",
    "FocusFrame.TargetFrameContent.TargetFrameContentMain.LevelBackgroundCircle",
    "FocusFrame.totFrame.FrameTexture",
    "TargetFrameToT.FrameTexture",
    "FocusFrameToT.FrameTexture",
    "PetFrameTexture",
    "PetFrame.FrameTexture",
    "PlayerFrameGroupIndicatorLeft",
    "PlayerFrameGroupIndicatorRight",
    "PlayerFrameGroupIndicatorMiddle",
    -- Classic style unit frames (in case the client uses them)
    "PlayerFrameTexture",
    "TargetFrameTextureFrameTexture",
    "TargetFrameToTTextureFrameTexture",
    "FocusFrameTextureFrameTexture",
    "FocusFrameToTTextureFrameTexture",
    -- Cast bars and timers
    "PlayerCastingBarFrame.Border",
    "PlayerCastingBarFrame.TextBorder",
    "TargetFrame.spellbar.Border",
    "TargetFrame.spellbar.TextBorder",
    "FocusFrame.spellbar.Border",
    "FocusFrame.spellbar.TextBorder",
    "PetCastingBarFrame.Border",
    "CastingBarFrame.Border",
    "TargetFrameSpellBar.Border",
    -- The parchment backing behind the cast icon/text (confirmed live at full brightness while
    -- .Border/.TextBorder right next to it were already dark) - a piece Target/Focus's cast bar
    -- template has that Player/Pet's simpler one doesn't.
    "TargetFrameSpellBar.Background",
    "FocusFrameSpellBar.Background",
    -- The non-interruptible-cast shield overlay, same template piece, same issue.
    "TargetFrameSpellBar.BorderShield",
    "FocusFrameSpellBar.BorderShield",
    -- Class resources
    "AlternatePowerBar.Border",
    "AlternatePowerBar.LeftBorder",
    "AlternatePowerBar.RightBorder",
    "PlayerFrameAlternateManaBarBorder",
    "PlayerFrameAlternateManaBarLeftBorder",
    "PlayerFrameAlternateManaBarRightBorder",
    "PaladinPowerBarFrame.Background",
    "PaladinPowerBarFrame.ActiveTexture",
}

-- The plain bronze portrait ring every target (elite or not) shares - named ELITE_TEXTURES for
-- historical reasons (it used to be dimmed-but-color-preserved specifically for the elite wreath
-- layered on top of it, see DarkenUnitFrames below for why that was dropped); flattened like the
-- rest of UNIT_FRAME_TEXTURES now, just kept separate since it goes through DarkenPolled instead
-- of Darken.
local ELITE_TEXTURES = {
    "TargetFrame.TargetFrameContainer.FrameTexture",
    "FocusFrame.TargetFrameContainer.FrameTexture",
}

-- The elite/boss portrait wreath itself (BossPortraitFrameTexture) is deliberately NOT darkened
-- at all - confirmed live that even dimmed-but-color-preserved (S:Darken's keepTextureColor) was
-- still too washed out next to its actual bright gold/bronze art, and there's no brightness offset
-- between "flattened gray" and "untouched" that reads as "dark-mode-appropriate gold" rather than
-- either too gray or too bright. It's a small, infrequently-seen accent (elite/boss targets only),
-- not worth chasing further - left at its native, undarkened color instead.

-- The border on a cast bar's spell icon isn't a separate texture to darken - confirmed live
-- (/dump found Icon but no IconBorder) - it's baked into the edges of the icon art itself, the
-- same way every spell/item icon in the game is. The rest of this addon already crops that same
-- edge on its own icons (Modules\Nameplates.lua's InitButton); this does the same here.
local CAST_ICONS = {
    "PlayerCastingBarFrame.Icon",
    "TargetFrame.spellbar.Icon",
    "TargetFrameSpellBar.Icon",
    "FocusFrame.spellbar.Icon",
    "FocusFrameSpellBar.Icon",
    "PetCastingBarFrame.Icon",
    "CastingBarFrame.Icon",
}

local function CropCastIcons()
    for _, path in ipairs(CAST_ICONS) do
        local icon = S.Resolve(path)
        if icon and icon.SetTexCoord then
            icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        end
    end
end

local function DarkenUnitFrames()
    CropCastIcons()
    for _, path in ipairs(UNIT_FRAME_TEXTURES) do
        S:Darken(S.Resolve(path))
    end
    for _, path in ipairs(ELITE_TEXTURES) do
        -- Flattened like PlayerFrame's own ring now (no keepTextureColor, no ELITE offset) -
        -- confirmed live the gold-preserving dim still reads as clearly undarkened next to
        -- everything else for the vast majority of targets, which aren't elite/boss and so never
        -- show the wreath this was originally preserved for in the first place (that wreath,
        -- BossPortraitFrameTexture, is handled entirely separately below and left alone). A flat
        -- ring mismatching the elite wreath on the rare elite/boss target is a smaller cost than
        -- an undarkened ring on every normal one. DarkenPolled, not Darken: confirmed live
        -- Blizzard recolors this ring itself on every target switch (elite vs. normal get
        -- different base tints), the same "Blizzard recolors this dynamically, a permanent hook
        -- can't reliably win that race" case as MainActionBar's own art above, just per-target
        -- instead of per-vehicle-transition. The ticker in Init below (S:RepaintPolled) already
        -- covers this too, no separate ticker needed.
        S:DarkenPolled(S.Resolve(path))
    end

    for i = 1, 4 do
        S:Darken(S.Resolve("PartyFrame.MemberFrame" .. i .. ".Texture"))
        S:Darken(S.Resolve("PartyFrame.MemberFrame" .. i .. ".PetFrame.Texture"))
        S:Darken(_G["PartyMemberFrame" .. i .. "Texture"])
    end
    for i = 1, 5 do
        local boss = _G["Boss" .. i .. "TargetFrame"]
        if boss then
            S:Darken(S.Resolve("Boss" .. i .. "TargetFrame.TargetFrameContainer.FrameTexture"))
            S:Darken(S.Resolve("Boss" .. i .. "TargetFrame.spellbar.Border"))
        end
    end

    -- Raid / party frame borders
    for _, name in ipairs({ "CompactPartyFrameBorderFrame", "CompactRaidFrameContainerBorderFrame" }) do
        S:DarkenRegions(_G[name])
    end
    for group = 1, 8 do
        S:DarkenRegions(_G["CompactRaidGroup" .. group .. "BorderFrame"])
    end

    -- Mirror timers (breath, fatigue)
    local container = MirrorTimerContainer
    if container and container.mirrorTimers then
        for _, timer in ipairs(container.mirrorTimers) do
            S:Darken(timer.Border)
            S:Darken(timer.TextBorder)
        end
    end
    for i = 1, 3 do
        S:Darken(_G["MirrorTimer" .. i .. "Border"])
    end

    -- Class resource bars that are built from children
    for _, name in ipairs({ "RogueComboPointBarFrame", "DruidComboPointBarFrame", "WarlockPowerFrame", "MageArcaneChargesFrame" }) do
        local bar = _G[name]
        if bar then
            for _, child in ipairs({ bar:GetChildren() }) do
                S:Darken(child.BGInactive, LIGHTER)
                S:Darken(child.BG_Inactive, LIGHTER)
                S:Darken(child.Background, LIGHTER)
                S:Darken(child.ArcaneBG, LIGHTER)
            end
        end
    end
    if TotemFrame then
        for _, child in ipairs({ TotemFrame:GetChildren() }) do
            S:Darken(child.Border)
        end
    end
end

-- Action bars, micro menu, bags, XP/rep bars -----------------------------------------------------

-- PetActionButton/StanceButton/BonusActionButton deliberately excluded - same reasoning
-- Modules\ActionBars.lua's own BARS list already uses. S:Darken installs a permanent
-- hooksecurefunc(texture, "SetVertexColor"/"SetDesaturated", ...) on every texture it touches
-- (Core.lua), so darkening these buttons' art means that hook fires every time the client
-- recolors/desaturates them for its own reasons - which for the pet bar specifically happens as
-- part of its own per-button Update(), the same call that can go on to Hide() the bar (no pet) and
-- have Edit Mode reflow MainActionBar under it. Confirmed live as the same ADDON_ACTION_BLOCKED on
-- MainActionBar:SetPointBase() that Modules\ActionBars.lua's and Modules\BarVisibility.lua's own
-- pet-bar hooks were already fixed for - this was the one actually still causing it.
local BUTTON_BARS = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
}

local MICRO_BUTTONS = {
    "CharacterMicroButton", "ProfessionMicroButton", "SpellbookMicroButton", "TalentMicroButton",
    "LegacyMicroButton", "QuestLogMicroButton", "GuildMicroButton", "SocialsMicroButton", "LFDMicroButton",
    "LFGMicroButton", "CollectionsMicroButton", "EJMicroButton", "HelpMicroButton", "StoreMicroButton",
    "MainMenuMicroButton", "WorldMapMicroButton", "PVPMicroButton", "AchievementMicroButton",
}

local function DarkenEdges(frame)
    if not frame then
        return
    end
    S:Darken(frame.TopEdge)
    S:Darken(frame.BottomEdge)
    S:Darken(frame.Center)
    S:Darken(frame.BorderArt)
end

-- Same as DarkenEdges, but for art inside MainActionBar's own hierarchy - see DarkenActionBars
-- below for why this goes through S:DarkenPolled instead.
local function DarkenEdgesPolled(frame)
    if not frame then
        return
    end
    S:DarkenPolled(frame.TopEdge)
    S:DarkenPolled(frame.BottomEdge)
    S:DarkenPolled(frame.Center)
    S:DarkenPolled(frame.BorderArt)
end

local function DarkenButtonArt(button, name)
    if not button then
        return
    end
    if button.GetNormalTexture then
        S:Darken(button:GetNormalTexture())
    end
    S:Darken(button.NormalTexture)
    S:Darken(button.Background)
    S:Darken(button.PushedBackground)
    S:Darken(button.RightDivider)
    if name then
        S:Darken(_G[name .. "NormalTexture"])
    end
end

local function DarkenActionBars()
    for _, prefix in ipairs(BUTTON_BARS) do
        for i = 1, 12 do
            local name = prefix .. i
            DarkenButtonArt(_G[name], name)
        end
    end

    -- MainActionBar itself (its edges, every child via GetChildren, end caps) and the classic-
    -- style bar's own end caps go through S:DarkenPolled, not S:Darken - Blizzard recolors this
    -- whole hierarchy's art as part of vehicle-state transitions (which also hide the pet bar and
    -- populate the override bar), and a permanent SetVertexColor/SetDesaturated hook anywhere in
    -- it taints that entire transition, confirmed live as the pet-bar MainActionBar reflow block
    -- and the override bar's secret-cooldown block showing up together, every time, from this one
    -- source. DarkenPolled never installs that hook, so there's nothing left for it to taint; the
    -- ticker in Init below is what keeps it dark instead of a self-correcting hook.
    local mainBar = _G.MainActionBar or _G.MainMenuBar
    if mainBar then
        DarkenEdgesPolled(mainBar)
        for _, child in ipairs({ mainBar:GetChildren() }) do
            DarkenEdgesPolled(child)
        end
        -- The gryphons are either textures themselves or frames holding a .Texture.
        local endCaps = mainBar.EndCaps
        if endCaps then
            for _, cap in ipairs({ endCaps.LeftEndCap or false, endCaps.RightEndCap or false }) do
                if cap then
                    S:DarkenPolled(cap, LIGHTER)
                    S:DarkenPolled(cap.Texture, LIGHTER)
                end
            end
        end
    end

    -- Classic style main bar art. MainMenuBarTexture/XP/Reputation bar textures are a separate,
    -- non-action-bar hierarchy (StatusTrackingBarManager's) and keep using the normal hooked
    -- S:Darken - Blizzard doesn't recolor those as part of a vehicle transition.
    for i = 0, 3 do
        S:DarkenPolled(_G["MainMenuBarTexture" .. i])
        S:Darken(_G["MainMenuMaxLevelBar" .. i])
        S:Darken(_G["MainMenuXPBarTexture" .. i])
        S:Darken(_G["ReputationWatchBarTexture" .. i])
        S:Darken(_G["ReputationXPBarTexture" .. i])
    end
    S:DarkenPolled(_G.MainMenuBarLeftEndCap, LIGHTER)
    S:DarkenPolled(_G.MainMenuBarRightEndCap, LIGHTER)

    if StatusTrackingBarManager then
        S:Darken(S.Resolve("StatusTrackingBarManager.MainStatusTrackingBarContainer.BarFrameTexture"))
        S:Darken(S.Resolve("StatusTrackingBarManager.SecondaryStatusTrackingBarContainer.BarFrameTexture"))
    end

    -- Swing timer bars: background and frame art darkened, like the XP bar above; the fill stays
    -- (it's the progress indicator, same reason health bar fills are never darkened either).
    for _, name in ipairs({ "SwingTimerMainHandFrame", "SwingTimerOffHandFrame", "SwingTimerRangedFrame" }) do
        local bar = _G[name]
        if bar then
            S:Darken(bar.Background)
            S:Darken(bar.Border)
        end
    end

    if MicroMenu then
        S:Darken(MicroMenu.BorderArt)
    end
    for _, name in ipairs(MICRO_BUTTONS) do
        local button = _G[name]
        if button then
            S:Darken(button.Background)
            S:Darken(button.PushedBackground)
        end
    end

    if BagsBar then
        DarkenEdges(BagsBar)
        for _, child in ipairs({ BagsBar:GetChildren() }) do
            DarkenEdges(child)
        end
    end
    for _, name in ipairs({ "MainMenuBarBackpackButton", "CharacterReagentBag0Slot", "KeyRingButton",
        "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot", "CharacterBag3Slot" }) do
        DarkenButtonArt(_G[name], name)
    end
end

-- Minimap -----------------------------------------------------------------------------------------

local TRACKING_BORDER = 136430 -- Interface\Minimap\MiniMap-TrackingBorder, used by most minimap buttons

local function DarkenTrackingBorders(frame, depth)
    if not frame or depth > 2 or frame:IsForbidden() then
        return
    end
    S:DarkenRegions(frame, nil, function(region)
        local file = region:GetTexture()
        return file == TRACKING_BORDER or (type(file) == "string" and file:lower():find("trackingborder"))
    end)
    for _, child in ipairs({ frame:GetChildren() }) do
        DarkenTrackingBorders(child, depth + 1)
    end
end

local function TextureName(region)
    local atlas = region.GetAtlas and region:GetAtlas()
    local file = region:GetTexture()
    return ((atlas or "") .. " " .. (type(file) == "string" and file or "")):lower()
end

-- Every texture in a frame and its sub frames (buttons included), optionally filtered.
local function DarkenTree(frame, depth, filter, offset)
    if not frame or depth > 4 or frame:IsForbidden() then
        return
    end
    S:DarkenRegions(frame, offset, filter)
    for _, child in ipairs({ frame:GetChildren() }) do
        DarkenTree(child, depth + 1, filter, offset)
    end
end

-- Frame art only: borders, rings, bars, backgrounds; never icons.
local function IsFrameArt(region)
    local name = TextureName(region)
    return name:find("border") or name:find("frame") or name:find("ring") or name:find("edge")
        or name:find("header") or name:find("bar") or name:find("bg") or name:find("background")
end

local BUTTON_ICON_OFFSET = 0.25

function M:DarkenMinimapHeader()
    local cluster = MinimapCluster
    if not cluster then
        return
    end
    -- The zone title bar on top of the minimap (all of it is frame art).
    S:Darken(cluster.BorderTop)
    if type(cluster.BorderTop) == "table" and cluster.BorderTop.GetChildren then
        DarkenTree(cluster.BorderTop, 0)
    end
    DarkenTree(cluster.ZoneTextButton, 0, IsFrameArt)
    -- Tracking (magnifier) button and the day/night indicator: only their frames, not the icons.
    DarkenTree(cluster.Tracking, 0, IsFrameArt)
    S:Darken(cluster.Tracking and cluster.Tracking.Background)
    DarkenTree(cluster.DielFrame, 0, function(region)
        local name = TextureName(region)
        return name:find("frame") or name:find("border") or name:find("ring")
    end)
    -- Header regions that sit directly on the cluster.
    S:DarkenRegions(cluster, nil, IsFrameArt)

    -- The calendar and tracking buttons are icon and frame in one texture; they are darkened as a
    -- whole, a little lighter than frames so the icon stays recognizable. Highlights stay bright.
    local notHighlight = function(region)
        return region:GetDrawLayer() ~= "HIGHLIGHT"
    end
    DarkenTree(GameTimeFrame, 0, notHighlight, BUTTON_ICON_OFFSET)
    DarkenTree(cluster.Tracking and cluster.Tracking.Button, 0, notHighlight, BUTTON_ICON_OFFSET)
end

function M:DarkenMinimap()
    S.SafeCall(self.DarkenMinimapHeader, self)
    for _, path in ipairs({
        "MinimapCompassTexture", "MinimapBorder", "MinimapBorderTop", "MinimapCluster.BorderTop",
        "MinimapCluster.Tracking.Background", "MiniMapTrackingBorder", "MiniMapTrackingButtonBorder",
        "MiniMapMailBorder", "MiniMapWorldMapButton.Border",
    }) do
        S:Darken(S.Resolve(path))
    end
    S:DarkenRegions(S.Resolve("MinimapCluster.BorderTop"))
    for _, path in ipairs({ "Minimap.ZoomIn", "Minimap.ZoomOut", "MinimapZoomIn", "MinimapZoomOut", "TimeManagerClockButton" }) do
        S:DarkenRegions(S.Resolve(path))
    end
    DarkenTrackingBorders(Minimap, 0)
end

-- Chat tabs and edit boxes ------------------------------------------------------------------------

local TAB_KEYS = {
    "Left", "Middle", "Right", "ActiveLeft", "ActiveMiddle", "ActiveRight",
    "leftSelectedTexture", "middleSelectedTexture", "rightSelectedTexture",
    "leftTexture", "middleTexture", "rightTexture",
}
local EDITBOX_KEYS = { "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }

function M:DarkenChatFrame(chatFrame)
    if not chatFrame then
        return
    end
    local name = chatFrame:GetName()
    local tab = _G[name .. "Tab"]
    if tab then
        for _, key in ipairs(TAB_KEYS) do
            S:Darken(tab[key])
            S:Darken(_G[name .. "Tab" .. key])
        end
    end
    local editBox = chatFrame.editBox or _G[name .. "EditBox"]
    if editBox then
        for _, key in ipairs(EDITBOX_KEYS) do
            S:Darken(editBox[key])
            S:Darken(_G[name .. "EditBox" .. key])
        end
    end
    S:DarkenRegions(_G[name .. "ButtonFrame"])
end

function M:DarkenChat()
    local count = (Constants and Constants.ChatFrameConstants and Constants.ChatFrameConstants.MaxChatWindows) or NUM_CHAT_WINDOWS or 10
    for i = 1, count do
        self:DarkenChatFrame(_G["ChatFrame" .. i])
    end
    for _, name in ipairs(CHAT_FRAMES or {}) do
        self:DarkenChatFrame(_G[name])
    end
end

-- Panels (character, spellbook, bags, menus, ...) -------------------------------------------------
-- Walks a window's frame tree (frames only, never buttons or scroll frames, so item icons and map
-- pins stay untouched) and darkens its borders, title bars, backgrounds and tabs.

-- Quest/dialogue frames (QuestFrame, QuestLog*, GossipFrame, ItemTextFrame) are deliberately left
-- out: their parchment background is part of the quest art, not a stone/metal panel, and
-- darkening it just turns it black. SkinFrame's IsQuestPanel check below catches the same content
-- nested inside a window that does get skinned (the world map's embedded quest details).
local PANELS = {
    "CharacterFrame", "SpellBookFrame", "PlayerSpellsFrame", "ProfessionsBookFrame",
    "MerchantFrame", "MailFrame", "OpenMailFrame",
    "BankFrame", "TradeFrame", "LootFrame", "FriendsFrame", "PVEFrame", "WorldMapFrame", "GameMenuFrame",
    "SettingsPanel", "AddonList", "TaxiFrame", "FlightMapFrame", "DressUpFrame",
    "TabardFrame", "GuildRegistrarFrame", "PetitionFrame", "ReadyCheckFrame", "ReadyCheckListenerFrame",
    "LFGDungeonReadyDialog", "HelpFrame", "ChannelFrame", "ContainerFrameCombinedBags", "MacroFrame",
    "ClassTrainerFrame", "TalentFrame", "PlayerTalentFrame", "InspectFrame", "AuctionHouseFrame",
    "AuctionFrame", "CommunitiesFrame", "KeyBindingFrame", "CraftFrame", "TradeSkillFrame",
    "EncounterJournal", "CollectionsJournal", "AchievementFrame", "CalendarFrame", "TimeManagerFrame",
    "GuildBankFrame", "ItemSocketingFrame", "PetStableFrame", "StableFrame",
    "ProfessionsFrame", "WhoFrame", "RaidParentFrame", "GuildFrame", "LFGParentFrame", "BattlefieldFrame",
    "PVPFrame", "HonorFrame", "SmuveUIOptionsFrame", "ColorPickerFrame", "StaticPopup1", "StaticPopup2",
    "StaticPopup3", "StaticPopup4", "CinematicFrameCloseDialog",
    "BarberShopFrame", "GroupLootHistoryFrame", "LootHistoryFrame", "ArenaFrame", "ProfessionsCustomerOrdersFrame",
    -- LegacySystemFrame (the "Legacy Tree" talent-style window) and SocialUIFrame (the unified
    -- Friends/Guild/Who window that replaced FriendsFrame on this build) - confirmed via /fstack
    -- live as the actual frame names; neither was in this list at all, so they never got skinned.
    "LegacySystemFrame", "SocialUIFrame",
    -- GossipFrame (NPC dialogue options) and QuestFrame (the quest offer/detail/reward window) -
    -- both confirmed live to have the exact same NineSlice border as every other panel here, just
    -- were never in this list at all (a screenshot of QuestFrame specifically - accepting a quest,
    -- not just talking to an NPC - showed the exact same untouched look GossipFrame had before it
    -- was added). SkinFrame's own IsQuestPanel check still keeps their parchment untouched (see
    -- SkinFrame's own comment) - it matches both of these names already.
    "GossipFrame", "QuestFrame",
    -- CompactRaidFrameManager (the Party/Raid control window - layout, pings, leave party) -
    -- confirmed via /fstack as the actual frame name; never in this list at all.
    "CompactRaidFrameManager",
    -- EditModeManagerFrame is deliberately NOT listed here: walking its frame tree with
    -- SkinFrame caused a reproducible Lua stack overflow (confirmed live), and it's Blizzard's
    -- own layout tool rather than a panel worth reskinning.
}
for i = 1, 13 do
    table.insert(PANELS, "ContainerFrame" .. i)
end
-- The built-in damage meter's windows.
for i = 1, 3 do
    table.insert(PANELS, "DamageMeterSessionWindow" .. i)
end

-- Light decorations hidden in dark mode (darkened they show as a gray band).
local HIDDEN_KEYS = { "TopTileStreaks" }

local TEXTURE_KEYS = {
    "Bg", "TitleBg", "Header", "TopLeftCorner", "TopRightCorner", "BotLeftCorner", "BotRightCorner",
    "BottomLeftCorner", "BottomRightCorner", "TopBorder", "BottomBorder", "LeftBorder", "RightBorder",
    "TopEdge", "BottomEdge", "LeftEdge", "RightEdge", "LeftBG", "CenterBG", "RightBG", "BorderTop",
    "BorderBottom", "BorderLeft", "BorderRight", "BorderTopLeft", "BorderTopRight", "BorderBottomLeft",
    "BorderBottomRight", "Background", "TopBackgroundStrip", "TopBackgroundStripBottomEdge",
}

-- Panel backgrounds recognized by their texture, for windows built from client specific parts
-- (the character window's pane backgrounds, stone strips, ...). Race / model art is left alone.
-- TextureName gives "<atlas> <file>", so a name can end in a space.
-- "uiframemetal" added after GossipFrame's own portrait ring (atlas
-- "gamepad-uiframemetal-largeportrait-focus" - this client reuses gamepad/console UI atlases for
-- plain keyboard-and-mouse windows too, confirmed live via /smuve dump) stayed undarkened next to
-- an otherwise fully dark window; this is a name-based pattern so it applies anywhere that family
-- of metal-portrait-ring art turns up, not just on GossipFrame.
local BACKGROUND_PATTERNS = {
    "%-bg[%s%d]", "%-bg$", "stonebg", "%-background%s", "%-background$", "innertoptile", "uiframemetal",
}

local function IsPanelBackground(region)
    local name = TextureName(region)
    if name:find("race") or name:find("model") then
        return false
    end
    for _, pattern in ipairs(BACKGROUND_PATTERNS) do
        if name:find(pattern) then
            return true
        end
    end
    return false
end

local FRAME_KEYS_ALL_TEXTURES = { "Border", "Header", "TitleContainer" }

local TAB_TEXTURE_KEYS = {
    "Left", "Middle", "Right", "LeftActive", "MiddleActive", "RightActive",
    "LeftDisabled", "MiddleDisabled", "RightDisabled",
}

local function IsTab(button)
    if button.LeftActive or button.MiddleActive then
        return true
    end
    -- A name can be a protected value (no string functions on it); those are no tabs here.
    local name = button:GetName()
    return type(name) == "string" and not S.IsSecret(name) and name:find("Tab%d+$") ~= nil and button.Left ~= nil
end

local function SkinTab(button)
    local name = button:GetName()
    if type(name) ~= "string" or S.IsSecret(name) then
        name = nil
    end
    for _, key in ipairs(TAB_TEXTURE_KEYS) do
        S:Darken(button[key])
        if name then
            S:Darken(_G[name .. key])
        end
    end
end

-- Window borders (NineSlice) are bright metal; at the normal darkness their title band still
-- reads as gray, so they go darker than the rest.
local NINESLICE_OFFSET = -0.08

-- Quest/dialogue content keeps its parchment background entirely, wherever it turns up: the
-- gossip window, item text "books", and the quest log's own reading pane, which also appears
-- nested inside other windows that do get skinned (the world map's embedded quest details).
-- Matched loosely by name since Blizzard nests the sub-frame differently depending on context.
local function IsQuestPanel(frame)
    local name = frame.GetName and frame:GetName()
    if type(name) ~= "string" or S.IsSecret(name) then
        return false
    end
    local lower = name:lower()
    return lower:find("quest") ~= nil or lower == "gossipframe" or lower == "itemtextframe"
end

local function SkinFrame(frame, depth, topQuestPanel)
    if depth > 5 or frame:IsForbidden() then
        return
    end
    -- topQuestPanel is computed ONCE, from the top-level panel this walk actually started from (the
    -- PANELS entry - GossipFrame/QuestFrame/ItemTextFrame), then inherited unchanged through every
    -- recursive call below - NOT recomputed fresh per nested frame. Recomputing it per-frame was the
    -- actual bug behind QuestFrame's two undarkened strips: almost every one of its own legitimate
    -- sub-frames (QuestFrameInset, QuestFrameProgressPanel, ...) is ALSO named with "quest" in it, so
    -- the old per-frame check wrongly treated them as "nested foreign quest content" and bailed out
    -- of them ENTIRELY (border included) - including QuestFrameProgressPanel, two levels down, whose
    -- own "Material" pieces are exactly what the strips turned out to be (see further below).
    if depth == 0 then
        topQuestPanel = IsQuestPanel(frame)
    end
    -- A quest/dialogue window encountered NESTED inside some UNRELATED panel's frame tree (e.g. the
    -- world map's embedded quest log pane) is never one of this addon's own panels, just along for
    -- the ride while walking someone else's frame tree - left alone entirely, border included. Only
    -- fires when the panel we started walking from ISN'T itself one of our own quest-style panels
    -- (topQuestPanel false) - otherwise every nested piece of GossipFrame/QuestFrame's own subtree
    -- gets skinned like normal below, parchment protection included.
    if not topQuestPanel and depth > 0 and IsQuestPanel(frame) then
        return
    end
    local nineSlice = frame.NineSlice
    if type(nineSlice) == "table" and nineSlice.GetObjectType and nineSlice:GetObjectType() == "Frame" then
        S:DarkenRegions(nineSlice, NINESLICE_OFFSET)
    end
    -- StaticPopup/GameDialog-based windows (confirm popups, ready checks, ...) carry their actual
    -- border/background art as BG.Top/BG.Bottom (GameDialogBaseMixin:OnLoad, SetAtlas directly -
    -- not one of TEXTURE_KEYS' named pieces, and not caught by the region-name scan below either,
    -- confirmed live the delete-item confirmation's bronze border never got touched by either).
    local bg = frame.BG
    if type(bg) == "table" and bg.GetObjectType and bg:GetObjectType() == "Frame" then
        S:Darken(bg.Top)
        S:Darken(bg.Bottom)
    end
    -- Newer Blizzard panels (the combined bags frame confirmed live, via /smuve dump) carry their
    -- actual background as a "Bg" sub-FRAME, not a texture - a stretchy set of regions (a center
    -- fill plus "uiframebackground-nineslice-corner..." atlas corners) whose field names (if any)
    -- don't match TEXTURE_KEYS, and whose center fill has no atlas/file name at all for the
    -- IsPanelBackground name-scan below to catch either. DarkenRegions catches all of it regardless
    -- of name, the same way the window border NineSlice above does for its own regions.
    local bgFrame = frame.Bg
    if not topQuestPanel and type(bgFrame) == "table" and bgFrame.GetObjectType and bgFrame:GetObjectType() == "Frame" then
        S:DarkenRegions(bgFrame)
    end
    -- Reverted to the blanket topQuestPanel skip (not a per-texture "parchment" name check) - confirmed
    -- live that one of GossipFrame's Bg/Background fields darkened this way turned out to be a
    -- shading layer drawn OVER the parchment itself (not named with "parchment" at all), so tinting
    -- it visibly darkened the parchment text underneath even though the real "questbg-parchment"
    -- texture was correctly left alone. Blanket-protecting both was wrong in a different way (left
    -- two decorative strips undarkened), but darkening the parchment is the worse mistake of the two.
    if not topQuestPanel then
        for _, key in ipairs(TEXTURE_KEYS) do
            S:Darken(frame[key])
        end
    end
    for _, key in ipairs(HIDDEN_KEYS) do
        local texture = frame[key]
        if type(texture) == "table" and texture.IsObjectType and texture:IsObjectType("Texture") then
            S:HideWhenDark(texture)
        end
    end
    -- The streaks strip under the title bar also exists without that key (named differently or
    -- on a sub frame), so it is recognized by its texture too.
    local regions = { frame:GetRegions() }
    -- A window's NPC/player portrait (the actual face render, atlas "rtportrait*" - confirmed live
    -- via /smuve dump on GossipFrame) always sits in its own small frame alongside its ring/border
    -- art, as one or more sibling textures that match neither a TEXTURE_KEYS field name nor
    -- IsPanelBackground's naming patterns, so they fell through every check here untouched (visible
    -- live as GossipFrame's portrait ring staying undarkened next to an otherwise fully dark window).
    -- The face itself is left alone; everything else sharing its frame is darkened like any other
    -- panel art, the same fix benefiting any other panel with this same portrait-frame shape.
    -- TextureName joins atlas and file path with a space (empty atlas leaves a leading space), so
    -- this is a plain substring search, not an anchored "^rtportrait" - the portrait face here is a
    -- plain file path ("rtportrait1"), not an atlas, confirmed live via /smuve dump.
    local isPortraitFrame = false
    for _, region in ipairs(regions) do
        if region:IsObjectType("Texture") and TextureName(region):find("rtportrait", 1, true) then
            isPortraitFrame = true
            break
        end
    end
    for _, region in ipairs(regions) do
        if region:IsObjectType("Texture") then
            local name = TextureName(region)
            if name:find("streak") then
                S:HideWhenDark(region)
            elseif not topQuestPanel and not name:find("rtportrait", 1, true) and (IsPanelBackground(region) or isPortraitFrame) then
                S:Darken(region)
            end
        end
    end
    for _, key in ipairs(FRAME_KEYS_ALL_TEXTURES) do
        local holder = frame[key]
        if type(holder) == "table" and holder.GetObjectType and holder:GetObjectType() == "Frame" then
            S:DarkenRegions(holder)
        end
    end
    -- GossipFrame.GreetingPanel.ScrollBox.Shadows - the top/bottom scroll-fade gradient over the
    -- parchment reading pane, confirmed live via /fstack as the topmost (highest frame level) thing
    -- at that screen position. Didn't fix the strips on its own though - confirmed live (a second
    -- /fstack at the same spot) that this frame has no visible texture of its own there (it's a
    -- mouse-level-only hit, not what's actually painting the pixel); the two GLOBAL names also
    -- listed at that same position, GossipFrameBg and GossipFrameMaterialBotLeft, are the actual
    -- candidates - neither ever turned up in the recursive tree walk/dump (likely nested past its
    -- depth cap, or not a true child of GossipFrame at all), so they're resolved directly by their
    -- exact global name instead of relying on recursion to find them.
    local shadows = frame.GreetingPanel and frame.GreetingPanel.ScrollBox and frame.GreetingPanel.ScrollBox.Shadows
    if type(shadows) == "table" and shadows.GetObjectType then
        if shadows:GetObjectType() == "Frame" then
            S:DarkenRegions(shadows)
        elseif shadows:IsObjectType("Texture") then
            S:Darken(shadows)
        end
    end
    if frame == GossipFrame then
        for _, globalName in ipairs({ "GossipFrameBg", "GossipFrameMaterialBotLeft" }) do
            local object = _G[globalName]
            if type(object) == "table" and object.GetObjectType then
                local objType = object:GetObjectType()
                if objType == "Frame" then
                    S:DarkenRegions(object)
                elseif objType == "Texture" then
                    S:Darken(object)
                end
            end
        end
    end
    -- QuestFrame/QuestFrameInset: confirmed live via /fstack that the remaining top/bottom strips on
    -- QuestFrame are its own direct regions - QuestFrameBg among them, the same "separate Bg global"
    -- pattern as GossipFrameBg. Unlike GossipFrame though, QuestFrame's actual parchment lives in a
    -- separate nested child frame (QuestFrameDetailPanel/GreetingPanel/...), never a direct region of
    -- QuestFrame or QuestFrameInset themselves - confirmed by mirroring mUI's own approach exactly
    -- (mUI:Skin(QuestFrame) / mUI:Skin(QuestFrameInset), a blanket darken of direct regions with no
    -- name filtering at all, which is what their screenshot showed working correctly) - so a blanket
    -- DarkenRegions on these two specifically, unlike the TEXTURE_KEYS/region-scan blanket skip
    -- everywhere else in this subtree, can't accidentally reach the parchment.
    if frame == QuestFrame or frame == QuestFrameInset then
        S:DarkenRegions(frame)
    end
    -- QuestFrameProgressPanel.MaterialTopLeft/.SealMaterialBG - confirmed live via /fstack as the
    -- decorative edge pieces behind QuestFrame's own parchment pane (the same two strips GossipFrame
    -- had, just a field path here instead of a separate global). Matched generically by field name
    -- rather than frame identity - this template name doesn't turn up anywhere else in the addon.
    -- MaterialTopRight/MaterialBotRight added after a side-by-side screenshot against mUI showed a
    -- strip still remaining at the top of QuestFrameDetailPanel specifically - mUI's own Blacklist.lua
    -- names all four corners (ItemTextMaterialTopLeft/TopRight/BotLeft/BotRight) for this same style
    -- of panel; only 2 of the 4 were in this list, confirmed live as the actual gap.
    for _, key in ipairs({ "MaterialTopLeft", "MaterialTopRight", "MaterialBotLeft", "MaterialBotRight", "SealMaterialBG" }) do
        local material = frame[key]
        if type(material) == "table" and material.GetObjectType then
            local objType = material:GetObjectType()
            if objType == "Frame" then
                S:DarkenRegions(material)
            elseif objType == "Texture" then
                S:Darken(material)
            end
        end
    end
    for _, child in ipairs({ frame:GetChildren() }) do
        if not child:IsForbidden() then
            local objectType = child:GetObjectType()
            if objectType == "Button" and IsTab(child) then
                SkinTab(child)
            -- The NineSlice is done above with its own darker tint; walking into it again would
            -- re-darken its corners and edges at the normal (lighter) value.
            elseif objectType == "Frame" and child ~= nineSlice then
                SkinFrame(child, depth + 1, topQuestPanel)
            end
        end
    end
end

-- Named panel art the frame walk doesn't reach (borders around the character model).
local PANEL_TEXTURES = {
    "PaperDollInnerBorderTop", "PaperDollInnerBorderBottom", "PaperDollInnerBorderBottom2",
    "PaperDollInnerBorderLeft", "PaperDollInnerBorderRight", "PaperDollInnerBorderTopLeft",
    "PaperDollInnerBorderTopRight", "PaperDollInnerBorderBottomLeft", "PaperDollInnerBorderBottomRight",
}

-- Equipment slot buttons on the paper doll: Buttons, which SkinFrame's own frame walk deliberately
-- never reaches (see its header comment - this is what keeps item icons everywhere else untouched).
-- Their own NormalTexture turned out to be a blank, fileless placeholder (confirmed live via
-- /smuve dump: darkening it made no visible difference, since there was no image there to tint).
-- The actual visible tan slot-background art is a "ui-character-info-gearslot" atlas texture
-- nested one level deeper, in an unnamed child frame the button walk below has to find by name
-- instead - same for "character-emptysocket" (the empty gem-socket backgrounds on the same slots).
local SLOT_BG_ATLASES = { "ui-character-info-gearslot", "character-emptysocket" }

local function DarkenSlotBackground(button)
    -- The button's own NormalTexture (GetNormalTexture()) - confirmed live via /fstack
    -- (fsobj = CharacterSecondaryHandSlotNormalTexture, hit directly on the visible border line) that
    -- this IS rendering real, visible border art, contrary to an earlier, wrong conclusion: that
    -- conclusion came from this file's own TextureName() helper reporting it as blank/nameless, which
    -- only reads STRING file paths - a numeric fileID-based texture (this one) reports exactly the
    -- same "blank" way despite showing a real image, so "blank name" was never actually proof of "no
    -- visible content." NINESLICE_OFFSET for the same reason as below: its own bevel/highlight detail
    -- needs to go darker than flat panel fill to read as fully dark next to a flat-black icon.
    local normalTexture = button.GetNormalTexture and button:GetNormalTexture()
    if normalTexture then
        S:Darken(normalTexture, NINESLICE_OFFSET)
    end
    -- NINESLICE_OFFSET (not the default 0): confirmed live that the gearslot art's own baked-in
    -- bevel/highlight detail still reads as a visible lighter outline around the icon even at the
    -- normal darkness level, next to an icon dimmed flat black - the same "bright metal border needs
    -- to go darker than flat panel fill" case NINESLICE_OFFSET exists for elsewhere in this file.
    local borderFrame = button.BorderFrame
    if type(borderFrame) == "table" and borderFrame.GetObjectType and borderFrame:GetObjectType() == "Frame" then
        S:DarkenRegions(borderFrame, NINESLICE_OFFSET)
    end
    for _, region in ipairs({ button:GetRegions() }) do
        if region:IsObjectType("Texture") then
            -- TextureName joins atlas/file with a space (plain substring match, not an exact key
            -- lookup - the joined string always carries a leading or trailing space alongside it).
            local name = TextureName(region)
            for _, atlas in ipairs(SLOT_BG_ATLASES) do
                if name:find(atlas, 1, true) then
                    -- forceOpaque: the same semi-transparent-by-design issue as the combined bags
                    -- frame's own Bg (see its comment above) - a color tint alone leaves a
                    -- translucent slot tray still showing the 3D character model through it.
                    S:Darken(region, NINESLICE_OFFSET, nil, false, true)
                    break
                end
            end
        end
    end
    for _, child in ipairs({ button:GetChildren() }) do
        if not child:IsForbidden() and child:GetObjectType() == "Frame" then
            DarkenSlotBackground(child)
        end
    end
end

local SLOT_BUTTONS = {
    "CharacterHeadSlot", "CharacterNeckSlot", "CharacterShoulderSlot", "CharacterBackSlot",
    "CharacterChestSlot", "CharacterShirtSlot", "CharacterTabardSlot", "CharacterWristSlot",
    "CharacterHandsSlot", "CharacterWaistSlot", "CharacterLegsSlot", "CharacterFeetSlot",
    "CharacterFinger0Slot", "CharacterFinger1Slot", "CharacterTrinket0Slot", "CharacterTrinket1Slot",
    "CharacterMainHandSlot", "CharacterSecondaryHandSlot", "CharacterRangedSlot",
}

local skinnedPanels = {}

local function SkinPanel(panel)
    if S:DarkModeActive() then
        SkinFrame(panel, 0)
    end
end

-- The combined bags frame's own .Bg (and each individual ContainerFrame's, when combine-bags is
-- off) is a sub-FRAME, not a texture (see SkinFrame's own Bg-as-frame handling above) - confirmed
-- live via /smuve dump that two of its own regions (the rounded bottom corners) sit at alpha=0.8,
-- not 1, which a color tint alone can't fix (SetVertexColor only ever multiplies RGB, never alpha).
-- Forced fully opaque here instead, on top of (not instead of) the normal color darkening
-- DarkenRegions already did on them.
local BAG_BG_FRAMES = { "ContainerFrameCombinedBags" }
for i = 1, 13 do
    table.insert(BAG_BG_FRAMES, "ContainerFrame" .. i)
end

function M:SkinPanels()
    for _, name in ipairs(PANELS) do
        local panel = _G[name]
        if type(panel) == "table" and panel.GetObjectType and not panel:IsForbidden() then
            if not skinnedPanels[panel] then
                skinnedPanels[panel] = true
                -- Panels build parts of themselves lazily, so they are walked again whenever they open.
                panel:HookScript("OnShow", SkinPanel)
            end
            SkinPanel(panel)
        end
    end
    for _, name in ipairs(PANEL_TEXTURES) do
        S:Darken(_G[name])
    end
    for _, name in ipairs(SLOT_BUTTONS) do
        local button = _G[name]
        if button then
            DarkenSlotBackground(button)
        end
    end
    for _, name in ipairs(BAG_BG_FRAMES) do
        local panel = _G[name]
        local bgFrame = panel and panel.Bg
        if type(bgFrame) == "table" and bgFrame.GetRegions then
            for _, region in ipairs({ bgFrame:GetRegions() }) do
                if region:IsObjectType("Texture") then
                    S:Darken(region, 0, nil, false, true)
                end
            end
        end
    end
end

-- Debug (/smuve dump): whether a handful of panels - mostly ones reported as never getting
-- darkened - actually exist yet, were ever walked by SkinFrame, and what pieces SkinFrame's
-- texture-key/NineSlice checks actually found on them. CharacterFrame is included for contrast -
-- a panel confirmed working, to tell "this frame's own structure doesn't match what SkinFrame
-- looks for" apart from "SkinFrame isn't reaching this frame at all."
local DEBUG_PANELS = {
    "CharacterFrame", "GossipFrame",
}

function M:DebugLines()
    local lines = { "DarkModeActive=" .. tostring(S:DarkModeActive()) }
    for _, name in ipairs(DEBUG_PANELS) do
        local frame = _G[name]
        if not frame then
            table.insert(lines, name .. ": <does not exist yet>")
        else
            local nineSlice = frame.NineSlice
            local hasNineSlice = type(nineSlice) == "table" and nineSlice.GetObjectType and nineSlice:GetObjectType() == "Frame"
            local keys = {}
            for _, key in ipairs(TEXTURE_KEYS) do
                if frame[key] then
                    table.insert(keys, key)
                end
            end
            local frameKeys = {}
            for _, key in ipairs(FRAME_KEYS_ALL_TEXTURES) do
                local holder = frame[key]
                if type(holder) == "table" and holder.GetObjectType and holder:GetObjectType() == "Frame" then
                    table.insert(frameKeys, key)
                end
            end
            table.insert(lines, string.format(
                "%s: skinned=%s nineSlice=%s textureKeys=[%s] frameKeys=[%s] BG=%s children=%d frameAlpha=%s",
                name, tostring(skinnedPanels[frame] or false), tostring(hasNineSlice),
                table.concat(keys, ","), table.concat(frameKeys, ","),
                tostring(type(frame.BG)), select("#", frame:GetChildren()),
                tostring(frame.GetAlpha and frame:GetAlpha())))
            if frame.Background then
                local bgType2 = frame.Background.GetObjectType and frame.Background:GetObjectType()
                table.insert(lines, "  Background objectType=" .. tostring(bgType2)
                    .. (bgType2 == "Texture" and (" name=" .. TextureName(frame.Background)) or "")
                    .. " sameAsBg=" .. tostring(frame.Background == frame.Bg))
                if bgType2 == "Texture" then
                    table.insert(lines, "  Background: " .. S.DarkModeDebugInfo(frame.Background))
                end
            end
            if frame.Bg then
                local bgType = frame.Bg.GetObjectType and frame.Bg:GetObjectType()
                table.insert(lines, "  Bg objectType=" .. tostring(bgType)
                    .. (bgType == "Texture" and (" name=" .. TextureName(frame.Bg)) or ""))
                if bgType == "Texture" then
                    table.insert(lines, "  Bg: " .. S.DarkModeDebugInfo(frame.Bg))
                elseif bgType == "Frame" then
                    -- Bg is itself a sub-frame (a stretchable 3-slice background, say) - list what's
                    -- actually inside it, since that's what would need darkening instead.
                    for _, region in ipairs({ frame.Bg:GetRegions() }) do
                        if region:IsObjectType("Texture") then
                            local regionName = region.GetName and region:GetName()
                            table.insert(lines, "  Bg region " .. tostring(type(regionName) == "string" and regionName or region)
                                .. " name=" .. TextureName(region) .. " isPanelBg=" .. tostring(IsPanelBackground(region))
                                .. " " .. S.DarkModeDebugInfo(region))
                        end
                    end
                    for _, child in ipairs({ frame.Bg:GetChildren() }) do
                        table.insert(lines, "  Bg child: " .. tostring(child:GetObjectType()))
                    end
                end
            end
            if hasNineSlice then
                local pieces = {}
                for _, child in ipairs({ nineSlice:GetRegions() }) do
                    local objType = child.GetObjectType and child:GetObjectType()
                    if objType == "Texture" then
                        local key
                        for _, k in ipairs(TEXTURE_KEYS) do
                            if nineSlice[k] == child then
                                key = k
                                break
                            end
                        end
                        table.insert(pieces, (key or "?") .. ":" .. S.DarkModeDebugInfo(child))
                    end
                end
                table.insert(lines, "  NineSlice regions: " .. table.concat(pieces, " | "))
            end
            if frame.GetBackdropColor then
                local okBackdrop, r, g, b, a = pcall(frame.GetBackdropColor, frame)
                table.insert(lines, "  Backdrop color: " .. (okBackdrop and string.format("%.2f,%.2f,%.2f,%.2f", r, g, b, a) or "n/a"))
            end
        end
    end

    -- Full tree dump: every Texture region's name/color/tracked state, plus every Frame/Button
    -- child, bounded to a few levels deep. Used below for two things the targeted checks above
    -- didn't explain: (1) CharacterHeadSlot's NormalTexture turned out to already be a blank, file-
    -- less white texture (darkening a texture with no image draws no visible change), so whatever
    -- the user actually sees behind the icon must be a different region this walk will surface;
    -- (2) GossipFrame's header/portrait area still reads undarkened after the NineSlice/TEXTURE_KEYS
    -- fix, the same partial-coverage issue CharacterFrame itself needed extra handling for early on.
    local function DumpTree(obj, out, prefix, depth)
        if depth > 2 or #out > 400 or not obj or obj:IsForbidden() then
            return
        end
        local okRegions, regions = pcall(function() return { obj:GetRegions() } end)
        if okRegions then
            for _, region in ipairs(regions) do
                if region:IsObjectType("Texture") then
                    table.insert(out, prefix .. "Texture " .. TextureName(region) .. " " .. S.DarkModeDebugInfo(region))
                end
            end
        end
        local okChildren, children = pcall(function() return { obj:GetChildren() } end)
        if okChildren then
            for i, child in ipairs(children) do
                if i > 20 then
                    table.insert(out, prefix .. "... (" .. (#children - 20) .. " more children)")
                    break
                end
                if not child:IsForbidden() then
                    local objType = child:GetObjectType()
                    local childName = child.GetName and child:GetName()
                    table.insert(out, prefix .. objType .. " " .. tostring(type(childName) == "string" and childName or "<unnamed>"))
                    if objType == "Frame" or objType == "Button" or objType == "StatusBar" then
                        DumpTree(child, out, prefix .. "  ", depth + 1)
                    end
                end
            end
        end
    end

    local slotButton = _G["CharacterHeadSlot"]
    if slotButton then
        table.insert(lines, "CharacterHeadSlot tree:")
        DumpTree(slotButton, lines, "  ", 0)
    else
        table.insert(lines, "CharacterHeadSlot: <does not exist yet - open the character panel first>")
    end

    -- An EMPTY slot (no item equipped) showing a persistent white/gray border, confirmed by the user
    -- to happen with no item in it - ruling out the quality-colored IconBorder (Character.lua hides
    -- that one entirely when there's no item: GetInventoryItemQuality returns nil). Likeliest
    -- remaining candidate: the icon texture's own built-in "empty slot" placeholder art, which this
    -- addon's own code deliberately never touches (to avoid recoloring a real equipped item's icon)
    -- - checked explicitly here since that exclusion would be the wrong call specifically while a
    -- slot is empty (no real item art to protect).
    local secondaryHand = _G["CharacterSecondaryHandSlot"]
    if secondaryHand then
        table.insert(lines, "CharacterSecondaryHandSlot tree:")
        DumpTree(secondaryHand, lines, "  ", 0)
        local icon = secondaryHand.icon or _G["CharacterSecondaryHandSlotIconTexture"]
        if icon then
            table.insert(lines, "CharacterSecondaryHandSlot icon name=" .. TextureName(icon) .. " " .. S.DarkModeDebugInfo(icon))
        end
        local borderFrame = secondaryHand.BorderFrame
        table.insert(lines, "CharacterSecondaryHandSlot.BorderFrame=" .. tostring(borderFrame)
            .. " objectType=" .. tostring(type(borderFrame) == "table" and borderFrame.GetObjectType and borderFrame:GetObjectType()))
        if type(borderFrame) == "table" and borderFrame.GetObjectType and borderFrame:GetObjectType() == "Frame" then
            table.insert(lines, "CharacterSecondaryHandSlot.BorderFrame tree:")
            DumpTree(borderFrame, lines, "  ", 0)
        end
    end

    local gossipFrame = _G["GossipFrame"]
    if gossipFrame then
        table.insert(lines, "GossipFrame tree:")
        DumpTree(gossipFrame, lines, "  ", 0)
        -- Explicit named-field lookups instead of relying on the tree walk finding them by luck -
        -- the user pointed at two horizontal strips (above and below the parchment) that are still
        -- untouched; TitleContainer (confirmed present via frameKeys above) and a separate
        -- "Background" field (distinct from "Bg", also in textureKeys above) are the two likeliest
        -- places for exactly that kind of strip art to live.
        if gossipFrame.TitleContainer then
            table.insert(lines, "GossipFrame.TitleContainer tree:")
            DumpTree(gossipFrame.TitleContainer, lines, "  ", 0)
        end
        if gossipFrame.Background then
            local bgType = gossipFrame.Background.GetObjectType and gossipFrame.Background:GetObjectType()
            table.insert(lines, "GossipFrame.Background objectType=" .. tostring(bgType))
            if bgType == "Texture" then
                table.insert(lines, "  " .. S.DarkModeDebugInfo(gossipFrame.Background))
            elseif bgType == "Frame" then
                DumpTree(gossipFrame.Background, lines, "  ", 0)
            end
        end
    end

    -- QuestFrameGreetingPanel (the quest-list style dialogue, distinct from GossipFrame and from
    -- QuestFrameDetailPanel/QuestFrameProgressPanel) still showed the same two strips after those
    -- other two panels' own "Material*" fields got fixed - /fstack at that exact screen position hit
    -- QuestFrameProgressPanel instead (same screen rect, higher frame level, not what's actually
    -- rendering there), so its real structure is dumped directly here instead of guessed from fstack.
    local questFrame = _G["QuestFrame"]
    if questFrame and questFrame.GreetingPanel then
        table.insert(lines, "QuestFrame.GreetingPanel tree:")
        DumpTree(questFrame.GreetingPanel, lines, "  ", 0)
    end
    return lines
end

-- Calendar ---------------------------------------------------------------------------------------
-- The frame, month header, weekday bars and buttons are darkened; the day cells (parchment, holiday
-- pictures and their decorations) keep their look entirely (DarkenCalendarTree skips them).
-- Outside the day cells a few textures stay as they are too: today's marker, highlights, the close
-- button. Many calendar textures only report a file ID, so their own name and the path they were
-- set from are checked as well.
local CALENDAR_KEEP = { "holiday", "event", "today", "currentday", "highlight", "close", "glow", "invite" }

local function CalendarName(region)
    local path = region.GetTextureFilePath and region:GetTextureFilePath()
    local debugName = region.GetDebugName and region:GetDebugName()
    return (TextureName(region) .. " " .. (type(path) == "string" and path or "") .. " "
        .. (type(debugName) == "string" and not S.IsSecret(debugName) and debugName or "")):lower()
end

local function IsCalendarArt(region)
    if region:GetDrawLayer() == "HIGHLIGHT" then
        return false
    end
    local name = CalendarName(region)
    for _, word in ipairs(CALENDAR_KEEP) do
        if name:find(word, 1, true) then
            return false
        end
    end
    return true
end

-- The day cells (parchment, holiday pictures, their decorations) keep their look entirely;
-- everything around them is darkened.
local function DarkenCalendarTree(frame, depth)
    if not frame or depth > 4 or frame:IsForbidden() then
        return
    end
    local name = frame.GetDebugName and frame:GetDebugName()
    if type(name) == "string" and not S.IsSecret(name) and name:find("DayButton", 1, true) then
        return
    end
    S:DarkenRegions(frame, nil, IsCalendarArt)
    for _, child in ipairs({ frame:GetChildren() }) do
        DarkenCalendarTree(child, depth + 1)
    end
end

function M:DarkenCalendar()
    if not CalendarFrame or CalendarFrame:IsForbidden() then
        return
    end
    if not self.calendarHooked then
        self.calendarHooked = true
        -- Day buttons get new textures as months change; they are walked again on every open.
        CalendarFrame:HookScript("OnShow", function()
            if S:DarkModeActive() then
                DarkenCalendarTree(CalendarFrame, 0)
            end
        end)
    end
    DarkenCalendarTree(CalendarFrame, 0)
end

-- Dropdown and context menus -------------------------------------------------------------------
-- The client's menus draw their background in a style frame made by MenuStyle*Mixin:Generate.
-- Hooking those mixins before menus exist darkens every menu built from them.

-- Registered either way; the tint follows dark mode being on or off.
local function DarkenMenuStyle(styleFrame)
    S:DarkenRegions(styleFrame)
end

function M:HookMenus()
    if self.menusHooked then
        return
    end
    self.menusHooked = true
    for _, name in ipairs({ "MenuStyle1Mixin", "MenuStyle2Mixin", "WowStyle1MenuMixin", "WowStyle2MenuMixin" }) do
        local mixin = _G[name]
        if type(mixin) == "table" and type(mixin.Generate) == "function" then
            hooksecurefunc(mixin, "Generate", DarkenMenuStyle)
        end
    end
end

-- Module ------------------------------------------------------------------------------------------

function M:ApplyAll()
    S.SafeCall(DarkenUnitFrames)
    S.SafeCall(DarkenActionBars)
    S.SafeCall(self.DarkenMinimap, self)
    S.SafeCall(self.DarkenChat, self)
    S.SafeCall(self.SkinPanels, self)
    S.SafeCall(self.DarkenCalendar, self)
end

function M:Init()
    self:HookMenus()
    -- Wins back MainActionBar's own art (edges, gryphons, classic-style end caps) from Blizzard's
    -- own vehicle-transition recolors a few times a second - the trade S:DarkenPolled makes for
    -- never hooking SetVertexColor/SetDesaturated on that hierarchy (Core.lua). Cheap: a handful
    -- of textures, not the whole tracked set S:RepaintAll() would redo.
    C_Timer.NewTicker(0.3, function()
        if S:DarkModeActive() then
            S:RepaintPolled()
        end
    end)
    -- Damage meter windows are created when they are first opened; new ones are picked up here.
    C_Timer.NewTicker(1, function()
        if not S:DarkModeActive() then
            return
        end
        for i = 1, 3 do
            local window = _G["DamageMeterSessionWindow" .. i]
            if window and not skinnedPanels[window] then
                M:SkinPanels()
                return
            end
        end
    end)
    -- Each paper doll slot rebuilds its own background art on update (confirmed live via /smuve
    -- dump + screenshot: some slots kept the one-time SkinPanels() darkening, others - evidently
    -- re-created or re-colored by this same update - had reverted back to the plain tan look),
    -- so it's reasserted here every time instead of relying on a single pass at login.
    if PaperDollItemSlotButton_Update then
        hooksecurefunc("PaperDollItemSlotButton_Update", function(button)
            if S:DarkModeActive() and button then
                DarkenSlotBackground(button)
            end
        end)
    end
    -- QuestFrame's own sub-panels (GreetingPanel/DetailPanel/ProgressPanel/RewardPanel) are swapped
    -- in and out of the SAME, continuously-visible QuestFrame window - switching between them never
    -- fires QuestFrame's own OnShow again, so a sub-panel that's lazily created the first time THAT
    -- specific panel is needed this session, after the one-time SkinPanels() OnShow pass already ran,
    -- never got caught (confirmed live: QuestFrameGreetingPanel's strips stayed undarkened even after
    -- QuestFrameDetailPanel's identical pieces got fixed, simply because Detail happened to exist
    -- first). Re-skinning QuestFrame on each of these events - the same ones Blizzard itself uses to
    -- switch between its sub-panels - keeps catching whichever one just appeared.
    for _, event in ipairs({ "QUEST_GREETING", "QUEST_DETAIL", "QUEST_PROGRESS", "QUEST_COMPLETE" }) do
        S:On(event, function()
            if S:DarkModeActive() and QuestFrame then
                -- One frame later: the sub-panel this event is about may not be fully built/shown
                -- yet at the moment the event itself fires.
                C_Timer.After(0, function()
                    if S:DarkModeActive() and QuestFrame then
                        SkinFrame(QuestFrame, 0)
                    end
                end)
            end
        end)
    end
    -- Load-on-demand Blizzard windows (talents, auction house, ...) appear later.
    S:On("ADDON_LOADED", function()
        if S:DarkModeActive() then
            C_Timer.After(0, function()
                M:SkinPanels()
                S.SafeCall(M.DarkenCalendar, M)
            end)
        end
    end)
    S:On("PLAYER_ENTERING_WORLD", function()
        if S:DarkModeActive() then
            M:ApplyAll()
            -- Some minimap and bar parts are built a moment after entering the world.
            C_Timer.After(2, function()
                if S:DarkModeActive() then
                    M:ApplyAll()
                end
            end)
        end
    end)
    -- Party/raid frames and pet/whisper windows are created on demand.
    S:On("GROUP_ROSTER_UPDATE", function()
        if S:DarkModeActive() then
            S.SafeCall(DarkenUnitFrames)
        end
    end)
    -- Target/focus frame art (TargetFrameContainer.FrameTexture, the level badge, the cast bar
    -- border, ...) only ever resolves to a real texture once you've actually had a target/focus
    -- at least once - DarkenUnitFrames running once at login, before that's happened, leaves
    -- S.Resolve() finding nothing there yet to darken, and nothing re-ran it afterward.
    S:On("PLAYER_TARGET_CHANGED", function()
        if S:DarkModeActive() then
            S.SafeCall(DarkenUnitFrames)
        end
    end)
    S:On("PLAYER_FOCUS_CHANGED", function()
        if S:DarkModeActive() then
            S.SafeCall(DarkenUnitFrames)
        end
    end)
    if FCF_OpenTemporaryWindow then
        hooksecurefunc("FCF_OpenTemporaryWindow", function()
            if S:DarkModeActive() then
                M:DarkenChat()
            end
        end)
    end
end

function M:Refresh()
    if S:DarkModeActive() then
        self:ApplyAll()
    end
    -- Re-tints everything already known: picks up a new darkness value or restores the original
    -- colors when dark mode was switched off.
    S:RepaintAll()
end
