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

-- The plain bronze portrait ring every target (elite or not) shares - kept at its own baked-in
-- color rather than flattened like the rest of UNIT_FRAME_TEXTURES, since the elite wreath below
-- is layered directly on top of it (TargetFrame.xml) and needs it to not read as a near-black ring
-- showing through the wreath's gaps.
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
        -- keepTextureColor: the gold/bronze ring's own color is the whole point of it, so it's
        -- just dimmed rather than flattened to gray like plain chrome.
        S:Darken(S.Resolve(path), ELITE, nil, true)
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

local BUTTON_BARS = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton", "MultiBarRightButton",
    "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
    "PetActionButton", "StanceButton", "BonusActionButton",
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

    local mainBar = _G.MainActionBar or _G.MainMenuBar
    if mainBar then
        DarkenEdges(mainBar)
        for _, child in ipairs({ mainBar:GetChildren() }) do
            DarkenEdges(child)
        end
        -- The gryphons are either textures themselves or frames holding a .Texture.
        local endCaps = mainBar.EndCaps
        if endCaps then
            for _, cap in ipairs({ endCaps.LeftEndCap or false, endCaps.RightEndCap or false }) do
                if cap then
                    S:Darken(cap, LIGHTER)
                    S:Darken(cap.Texture, LIGHTER)
                end
            end
        end
    end

    -- Classic style main bar art
    for i = 0, 3 do
        S:Darken(_G["MainMenuBarTexture" .. i])
        S:Darken(_G["MainMenuMaxLevelBar" .. i])
        S:Darken(_G["MainMenuXPBarTexture" .. i])
        S:Darken(_G["ReputationWatchBarTexture" .. i])
        S:Darken(_G["ReputationXPBarTexture" .. i])
    end
    S:Darken(_G.MainMenuBarLeftEndCap, LIGHTER)
    S:Darken(_G.MainMenuBarRightEndCap, LIGHTER)

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
local BACKGROUND_PATTERNS = { "%-bg[%s%d]", "%-bg$", "stonebg", "%-background%s", "%-background$", "innertoptile" }

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

local function SkinFrame(frame, depth)
    if depth > 5 or frame:IsForbidden() or IsQuestPanel(frame) then
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
    for _, key in ipairs(TEXTURE_KEYS) do
        S:Darken(frame[key])
    end
    for _, key in ipairs(HIDDEN_KEYS) do
        local texture = frame[key]
        if type(texture) == "table" and texture.IsObjectType and texture:IsObjectType("Texture") then
            S:HideWhenDark(texture)
        end
    end
    -- The streaks strip under the title bar also exists without that key (named differently or
    -- on a sub frame), so it is recognized by its texture too.
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:IsObjectType("Texture") then
            if TextureName(region):find("streak") then
                S:HideWhenDark(region)
            elseif IsPanelBackground(region) then
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
    for _, child in ipairs({ frame:GetChildren() }) do
        if not child:IsForbidden() then
            local objectType = child:GetObjectType()
            if objectType == "Button" and IsTab(child) then
                SkinTab(child)
            -- The NineSlice is done above with its own darker tint; walking into it again would
            -- re-darken its corners and edges at the normal (lighter) value.
            elseif objectType == "Frame" and child ~= nineSlice then
                SkinFrame(child, depth + 1)
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

local skinnedPanels = {}

local function SkinPanel(panel)
    if S:DarkModeActive() then
        SkinFrame(panel, 0)
    end
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
