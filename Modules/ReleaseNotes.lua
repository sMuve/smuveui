local addonName, S = ...
local M = S:NewModule("ReleaseNotes")

-- Shown once, as a popup, the first time a player logs in after an update (spec 012). WoW addons
-- can't read arbitrary files - only the .lua files their own .toc lists, plus their own
-- SavedVariables - so CHANGELOG.md's content is hand-copied into this array at release time; see
-- specs/012-release-notes-popup/research.md §1. Newest first, matching CHANGELOG.md's own layout -
-- never reorder independently of a new release (research.md §3 relies on this order).
local ENTRIES = {
    { version = "0.9.5", notes = {
        "Fixed Edit Mode's \"Buffs on Top\" setting having no effect on the target and focus frames' buffs and debuffs.",
    } },
    { version = "0.9.4", notes = {
        "Debuff icon borders colored by dispel type (Magic, Curse, Disease, Poison) are a little darker now, and can be turned off from Options -> Unit Frames if you'd rather keep a plain border.",
        "Reworked the enemy nameplate cast bar: fixed the spell icon staying too small when the bar was made taller, and fixed the bar overlapping the health bar above it when grown.",
        "Fixed a friendly NPC's name sitting off-center in \"name only\" mode.",
        "Fixed the \"What's New\" popup sometimes showing an outdated release's notes instead of the current one's changes.",
        "Fixed the minimap button list in Options stacking on one spot instead of forming two columns.",
        "Fixed some addons showing doubled icons in the minimap button box.",
        "Fixed an error that could occur while changing the custom font setting.",
    } },
    { version = "0.9.3", notes = {
        "New: in \"name only\" mode, a friendly NPC's tooltip description (e.g. \"<General Goods Vendor>\") now shows below its name on its nameplate.",
        "Fixed the target and focus frame occasionally showing a level number and the \"too high to tell\" skull icon overlapping on the same spot.",
    } },
    { version = "0.9.2", notes = {
        "New: party and raid frame member names can now be outlined (Options -> Raid Frames), on by default.",
        "Battle.net whisper conversations are no longer kept in chat history across a reload or relog - doing so could show old messages under the wrong friend's name once you logged back in.",
    } },
    { version = "0.9.1", notes = {
        "Fixed the player and target frame's resource bar showing the wrong color, or an unusually dark one, for non-Mana classes when using the default bar texture.",
        "Fixed the enemy nameplate cast bar's spell icon sometimes rendering smaller than it should.",
        "Fixed the enemy nameplate cast bar occasionally losing its custom look (height, border, spell icon) entirely.",
        "Fixed a curated debuff icon (such as Weakened Soul) disappearing as soon as combat started, if an unrelated debuff on the same unit happened to become unreadable at the same time.",
        "New: arrow keys now move the text cursor and cycle through previously sent chat lines without needing to hold Alt (Options -> Chat & Social -> Chat), on by default.",
    } },
    { version = "0.9.0", notes = {
        "New: a \"what's new\" popup shows once after SmuveUI updates, listing what changed since you last saw it. Can be turned off from its own checkbox, or from a new control at the bottom of the Options window (not tucked under any category).",
        "The Options window's title now shows the installed version number next to \"SmuveUI\".",
    } },
    { version = "0.8.0", notes = {
        "New: Auto-open clams. Opens any clam sitting in your bags the moment it shows up, without touching anything else. Off by default (Options -> QoL -> Loot & Vendors).",
        "New: your debuffs bar can now be moved independently of your buffs bar, with its own \"Reset position\" button.",
        "New: the custom player buffs/debuffs display can be turned off entirely from Options -> Appearance -> Player.",
        "Fixed a weapon imbue icon not resizing with the \"Buffs scale\" slider, and sometimes blocking the buffs bar while repositioning it.",
        "Weapon imbue borders are now color-coded: green for a Rogue's poison, purple for every other imbue.",
    } },
    { version = "0.7.2", notes = {
        "Fixed the player and target frame's power bar sometimes rendering in Mana's blue color instead of the correct color.",
        "Fixed sharing chat window layout between characters sometimes silently failing to apply on the receiving character.",
        "Dark Mode now also covers the escape menu's red action buttons.",
    } },
    { version = "0.7.1", notes = {
        "Dark Mode now also covers several previously undarkened windows: the Legacy Tree, Friends/Guild/Who, NPC dialogue and quest windows, the combined bags window, the character sheet, and the party/raid control window.",
        "Fixed the enemy nameplate cast bar resetting its height every new cast, and enlarged its spell icon.",
        "Fixed class coloring not applying in one specific situation, when a chain of targets passed through an NPC.",
        "Fixed unit frame health bars briefly flashing the wrong color before reasserting the correct one.",
    } },
    { version = "0.7.0", notes = {
        "New: Raid/party frame buffs, debuffs, and defensive cooldowns, shown directly on each party/raid member's frame.",
        "New: a global Bar Texture picker for health and resource bars on the player, target, party, raid, and nameplate frames, plus the personal resource display.",
        "New: options to grow the cast bar's height and increase its spell-name/timer text size on enemy nameplates.",
        "Fixed the target-of-target health bar never getting class colored.",
        "Fixed custom bar textures turning solid black on bars that use the client's own atlas art.",
    } },
}

local function DB()
    return S.db.releaseNotes
end

function M.IsEnabled()
    return DB().enabled
end

function M.SetEnabled(value)
    DB().enabled = value and true or false
end

local function GetCurrentVersion()
    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    return getMetadata(addonName, "Version")
end

-- Every entry newer than lastSeen (array order, newest first). An unknown lastSeen (predates this
-- table, or an old entry was pruned) falls back to just the newest entry, rather than guessing
-- further back (research.md §3).
local function GetNewEntries(lastSeen)
    local idx
    for i, entry in ipairs(ENTRIES) do
        if entry.version == lastSeen then
            idx = i
            break
        end
    end
    if not idx then
        return { ENTRIES[1] }
    end
    local result = {}
    for i = 1, idx - 1 do
        table.insert(result, ENTRIES[i])
    end
    return result
end

-- Popup window --------------------------------------------------------------------------------
-- Same frame-creation recipe Options.lua's own window already uses successfully (PortraitFrameTemplate
-- + InsetFrameTemplate + UIPanelScrollFrameTemplate, UISpecialFrames) - already proven to skin
-- correctly under Dark Mode (Modules\DarkMode.lua's PANELS list), so reused as-is rather than
-- risking a template Dark Mode doesn't know how to walk.

local WIDTH, HEIGHT = 480, 440
local frame, page

local function ClearPage()
    for _, region in ipairs({ page:GetRegions() }) do
        region:Hide()
        region:SetParent(nil)
    end
end

local function FillPage(entries)
    ClearPage()
    local y = -4
    for _, entry in ipairs(entries) do
        local header = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        header:SetPoint("TOPLEFT", 4, y)
        header:SetPoint("RIGHT", page, "RIGHT", -4, 0)
        header:SetJustifyH("LEFT")
        header:SetText("Version " .. entry.version)
        y = y - 22
        for _, line in ipairs(entry.notes) do
            local text = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
            text:SetPoint("TOPLEFT", 14, y)
            text:SetPoint("RIGHT", page, "RIGHT", -4, 0)
            text:SetJustifyH("LEFT")
            text:SetWordWrap(true)
            text:SetText("- " .. line)
            y = y - text:GetStringHeight() - 6
        end
        y = y - 12
    end
    page:SetHeight(math.max(-y + 10, 1))
end

local function CreatePopup()
    frame = CreateFrame("Frame", "SmuveUIReleaseNotesFrame", UIParent, "PortraitFrameTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    -- DIALOG (not Options.lua's own HIGH): this window pops up unasked, on top of anything else
    -- open at login - matches the strata Travelcraft's own confirmed-working "what's new" popup
    -- uses for the same reason.
    frame:SetFrameStrata("DIALOG")
    frame:SetToplevel(true)
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:EnableMouse(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", frame.StartMoving)
    frame:SetScript("OnDragStop", frame.StopMovingOrSizing)
    frame:Hide()
    table.insert(UISpecialFrames, frame:GetName())

    if frame.SetTitle then
        frame:SetTitle("SmuveUI - What's New")
    elseif frame.TitleText then
        frame.TitleText:SetText("SmuveUI - What's New")
    end
    if frame.SetPortraitToAsset then
        frame:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Gear_01")
    elseif frame.PortraitContainer and frame.PortraitContainer.portrait then
        frame.PortraitContainer.portrait:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    end

    local inset = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    inset:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -64)
    inset:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 60)

    local scroll = CreateFrame("ScrollFrame", nil, inset, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 4, -4)
    scroll:SetPoint("BOTTOMRIGHT", -28, 4)
    page = CreateFrame("Frame", nil, scroll)
    page:SetSize(WIDTH - 60, 1)
    scroll:SetScrollChild(page)
    scroll:SetScript("OnSizeChanged", function(_, width)
        page:SetWidth(width)
    end)

    local neverAgain = CreateFrame("CheckButton", nil, frame, "UICheckButtonTemplate")
    neverAgain:SetSize(24, 24)
    neverAgain:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 16, 32)
    local neverAgainLabel = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    neverAgainLabel:SetPoint("LEFT", neverAgain, "RIGHT", 2, 1)
    neverAgainLabel:SetText("Never show release notes again")
    if neverAgain.Text then
        neverAgain.Text:SetText("")
    end
    neverAgain:SetScript("OnClick", function(self)
        M.SetEnabled(not self:GetChecked())
    end)
    frame.neverAgainCheck = neverAgain

    local note = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    note:SetPoint("TOPLEFT", neverAgain, "BOTTOMLEFT", 2, -4)
    note:SetPoint("RIGHT", frame, "RIGHT", -16, 0)
    note:SetJustifyH("LEFT")
    note:SetText("You can turn these back on from /smuveui options.")

    -- PortraitFrameTemplate already brings its own close button (confirmed by Options.lua's
    -- identical window never needing to add one of its own).

    if S.modules.DarkMode.SkinPanels then
        S.modules.DarkMode:SkinPanels()
    end
end

local function ShowPopup(entries)
    if not frame then
        CreatePopup()
    end
    FillPage(entries)
    frame.neverAgainCheck:SetChecked(not DB().enabled)
    frame:Show()
end

-- Version check ---------------------------------------------------------------------------------

local function CheckVersion()
    local db = DB()
    local current = GetCurrentVersion()
    if not current then
        return
    end
    if db.lastSeenVersion == nil then
        -- Fresh install: nothing to report yet, just start tracking from here (FR-005).
        db.lastSeenVersion = current
        return
    end
    if not db.enabled then
        -- Stays silent, and deliberately leaves lastSeenVersion as-is, so turning this back on
        -- later still shows everything missed while it was off (spec's own Assumption).
        return
    end
    if db.lastSeenVersion == current then
        return
    end
    local entries = GetNewEntries(db.lastSeenVersion)
    db.lastSeenVersion = current
    if #entries > 0 then
        ShowPopup(entries)
    end
end

-- Manual escape hatch for live testing: /run SmuveUI.modules.ReleaseNotes.DebugCheckVersion()
M.DebugCheckVersion = CheckVersion

-- A bare pcall swallowed a real login's own failure silently - confirmed live as the actual
-- bug behind a reported "popup doesn't show" report that turned out NOT to be the stale
-- ENTRIES table (already fixed separately): lastSeenVersion correctly advanced to the current
-- version on a clean login (proving CheckVersion's own version-comparison logic ran to
-- completion), yet no popup appeared and no error surfaced anywhere - only possible if
-- ShowPopup/CreatePopup itself threw AFTER that point, caught by this pcall before it ever
-- reached the user's own error-catching addon. Same pattern SafeBind (Modules\Nameplates.lua)
-- already uses for this exact class of problem: report it once via geterrorhandler() instead of
-- swallowing it, so a real failure is actually visible next time instead of a silent no-op.
local reportedError = false
local function SafeCheckVersion()
    local ok, err = pcall(CheckVersion)
    if not ok and not reportedError then
        reportedError = true
        geterrorhandler()(err)
    end
end

function M:Init()
    local ev = CreateFrame("Frame")
    ev:RegisterEvent("PLAYER_ENTERING_WORLD")
    ev:SetScript("OnEvent", function(self)
        self:UnregisterEvent("PLAYER_ENTERING_WORLD")
        -- A few seconds after the loading screen, once the game's own login windows have
        -- settled - this exact delay (and trigger shape) matches Travelcraft's own confirmed-
        -- working "what's new" popup on this same client; shorter delays tried previously here
        -- rendered nothing visible despite the underlying logic running correctly every time.
        if C_Timer then
            C_Timer.After(4, SafeCheckVersion)
        else
            SafeCheckVersion()
        end
    end)
end
