local _, S = ...
local M = S:NewModule("RestedXPSkin")

-- RestedXP (the RXPGuides addon folder, see Modules\ObjectiveTracker.lua for how this addon
-- already detects it) ships its own third-party theming API (its Themes.lua,
-- addon:RegisterTheme()) - used here instead of reaching into its frames with texture hooks, the
-- unsupported approach that caused this addon's own taint headaches on Blizzard's protected UI
-- all session. No new art: this reuses RestedXP's own existing "DarkMode" built-in theme's
-- border/banner textures (Textures\DarkMode\rxp-banner.blp, rxp-borders.blp - nothing created by
-- SmuveUI), overriding only its colors (to match SmuveUI's own near-black dark mode shade) and
-- its font (S:GetFont(), the same font every other SmuveUI-drawn piece of text uses).
--
-- Timing: RXPGuides loads alphabetically before SmuveUI, so its own OnInitialize - and the
-- one-time _G.RXPGuides_Themes import it does there - can run before any of SmuveUI's files even
-- load. That documented global-table mechanism can't be relied on here. RegisterTheme() itself has
-- no such requirement (it only inserts into live tables RestedXP's options UI reads on demand), so
-- this waits for RXPGuides to exist via AceAddon-3.0's own registry instead, at SmuveUI's usual
-- module Init time (PLAYER_LOGIN) - by then RXPGuides, if installed, has always finished loading.
--
-- This only ever registers the theme as an available option - RestedXP never auto-switches a
-- user's active theme out from under them, so picking "SmuveUI" in RestedXP's own theme settings
-- (Settings -> Appearance -> Theme) is a one-time step left to the user.

local function BuildTheme()
    return {
        name = "SmuveUI",
        displayName = "SmuveUI",
        author = "SmuveUI",
        -- Same guard RestedXP's own alternate themes use: hidden while Gold Assistant mode (its
        -- own dedicated gold theme) is active, never user-relevant at the same time as this one.
        applicable = function() return not (RXPCData and RXPCData.GA) end,
        background = { 25 / 255, 25 / 255, 25 / 255, 1 },
        bottomFrameBG = { 13 / 255, 13 / 255, 13 / 255, 1 },
        bottomFrameHighlight = { 45 / 255, 45 / 255, 45 / 255, 1 },
        mapPins = { 0.85, 0.85, 0.85, 1 },
        tooltip = "|cFFD9D9D9",
        texturePath = "Interface/AddOns/RXPGuides/Textures/DarkMode/",
        headerTexture = "rxp-banner",
        font = S:GetFont(),
        textColor = { 1, 1, 1 },
    }
end

function M:Init()
    local AceAddon = LibStub and LibStub("AceAddon-3.0", true)
    local RXP = AceAddon and AceAddon:GetAddon("RXPGuides", true)
    if not RXP or type(RXP.RegisterTheme) ~= "function" then
        return
    end
    RXP:RegisterTheme(BuildTheme())

    -- RestedXP's own AceAddon-3.0 initializes it on ITS OWN ADDON_LOADED, which fires as soon as
    -- its files finish loading - well before SmuveUI's files even start (RXPGuides < SmuveUI
    -- alphabetically), and definitely before this module's own Init() (SmuveUI's usual module
    -- timing, PLAYER_LOGIN) runs. So RestedXP's very first "apply my saved theme" pass always runs
    -- before "SmuveUI" even exists in its registry, silently falls back to its own default theme -
    -- confirmed live as the skin resetting on every reload even after being explicitly selected
    -- once. If SmuveUI IS the user's saved choice, this forces the same refresh RestedXP's own
    -- ReloadTheme() does (fonts included, not just LoadActiveTheme()'s color/backdrop pass - fonts
    -- are baked into each text object's SetFont call at creation time, so the font never actually
    -- took on anything RestedXP had already built before our theme existed) now that the theme is
    -- actually there to find - deliberately bypassing ReloadTheme()'s own enableThemeLiveReload
    -- gate, since that guards an expensive LIVE mid-session theme switch, not this one-time,
    -- necessary login-time correction.
    local profile = RXP.settings and RXP.settings.profile
    if profile and profile.activeTheme == "SmuveUI" then
        pcall(RXP.LoadActiveTheme, RXP)
        pcall(RXP.RenderFrame, RXP, "themeReload")
        if RXP.v2 then
            pcall(RXP.v2.ConvertThemes, RXP.v2)
            pcall(RXP.SetupArrow, RXP)
            if RXP.v2.IsGuideWindowEnabled and RXP.v2:IsGuideWindowEnabled() then
                pcall(RXP.v2.UpdateGuideWindow, RXP.v2)
                local ok, window = pcall(RXP.v2.GetGuideWindow, RXP.v2)
                if ok and window and window.UpdateTheme then
                    pcall(window.UpdateTheme, window, {})
                end
                pcall(RXP.v2.UpdateActiveStepTheme, RXP.v2)
            end
        end
    end
end
