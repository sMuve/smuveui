local _, S = ...
local M = S:NewModule("BarVisibility")

-- Action bars, the micro menu and the bag bar can each be shown always, only on mouseover, or
-- hidden. Hidden bars become invisible and click-through, but their key bindings keep working.
-- Only alpha and mouse input change, so this works in combat too (mouse input changes for the
-- action bars wait until combat ends).

M.BARS = {
    { key = "bar1", label = "Action Bar 1", frames = { "MainActionBar", "MainMenuBar" }, buttons = "ActionButton" },
    { key = "bar2", label = "Action Bar 2", frames = { "MultiBarBottomLeft" }, buttons = "MultiBarBottomLeftButton" },
    { key = "bar3", label = "Action Bar 3", frames = { "MultiBarBottomRight" }, buttons = "MultiBarBottomRightButton" },
    { key = "bar4", label = "Action Bar 4", frames = { "MultiBarRight" }, buttons = "MultiBarRightButton" },
    { key = "bar5", label = "Action Bar 5", frames = { "MultiBarLeft" }, buttons = "MultiBarLeftButton" },
    { key = "bar6", label = "Action Bar 6", frames = { "MultiBar5" }, buttons = "MultiBar5Button" },
    { key = "bar7", label = "Action Bar 7", frames = { "MultiBar6" }, buttons = "MultiBar6Button" },
    { key = "bar8", label = "Action Bar 8", frames = { "MultiBar7" }, buttons = "MultiBar7Button" },
    -- No Pet Bar entry: it's the one bar Blizzard itself natively shows/hides live (pet summon/
    -- dismiss), which repeatedly put our own alpha/mouse management of it in the same update pass
    -- as Blizzard's own PetActionBar:Update()/Hide() - confirmed live, after several narrower fixes,
    -- as a recurring (if by then rare) ADDON_ACTION_BLOCKED on MainActionBar:SetPointBase() when
    -- Edit Mode reflowed the bars below it in that same pass. Blizzard's own default pet-bar
    -- visibility (hidden with no pet) stands in for the custom mode this bar used to offer.
    { key = "stance", label = "Stance Bar", frames = { "StanceBar" }, buttons = "StanceButton" },
    { key = "micro", label = "Menu Bar", frames = { "MicroMenuContainer", "MicroMenu" } },
    { key = "bags", label = "Bag Bar", frames = { "BagsBar" } },
    { key = "xp", label = "Experience Bar", frames = { "StatusTrackingBarManager.MainStatusTrackingBarContainer" } },
    { key = "reputation", label = "Reputation Bar", frames = { "StatusTrackingBarManager.SecondaryStatusTrackingBarContainer" } },
}

M.MODES = {
    { value = "show", text = "Always show" },
    { value = "mouseover", text = "Show on mouseover" },
    { value = "hide", text = "Hide" },
}

local FADE_SPEED = 6 -- alpha per second

local function FrameOf(bar)
    for _, name in ipairs(bar.frames) do
        local frame = S.Resolve(name)
        if frame then
            return frame
        end
    end
end

local function ModeOf(bar)
    return S.db.actionbars.visibility[bar.key] or "show"
end

-- Bars always show while placing spells on them or in Edit Mode.
local function ForceShown()
    return (GetCursorInfo() ~= nil) or (EditModeManagerFrame and EditModeManagerFrame:IsShown())
        or (SpellFlyout and SpellFlyout:IsShown())
end

-- Deferred a tick: this runs off our own OnUpdate watcher, not a Blizzard call, but WoW batches
-- every frame's OnUpdate/OnEvent scripts for a given render tick into one execution pass - so an
-- EnableMouse call here can still land in the very same pass as the client's own, e.g. PetActionBar
-- deciding to Hide() itself (pet dismissed) and having Edit Mode reflow MainActionBar under it.
-- Confirmed live: that reflow's SetPoint on MainActionBar then hits ADDON_ACTION_BLOCKED, tainted
-- by this call having landed in the same pass. One tick later is a different pass.
local function ApplyMouse(bar, enabled)
    if bar.buttons then
        for i = 1, 12 do
            local button = _G[bar.buttons .. i]
            if button then
                button:EnableMouse(enabled)
            end
        end
    else
        local frame = FrameOf(bar)
        if frame then
            for _, child in ipairs({ frame:GetChildren() }) do
                if not child:IsForbidden() and child:IsObjectType("Button") then
                    child:EnableMouse(enabled)
                end
            end
        end
    end
end

local function SetMouse(bar, frame, enabled)
    if bar.mouseEnabled == enabled then
        return
    end
    -- Action buttons are secure: their mouse input can only change out of combat.
    if bar.buttons and InCombatLockdown() then
        M.pendingMouse = true
        return
    end
    bar.mouseEnabled = enabled
    C_Timer.After(0, function()
        ApplyMouse(bar, enabled)
    end)
end

-- Cooldown spirals "bling" even on invisible bars; that is switched off while a bar is hidden.
local function SetBling(bar, visible)
    if not bar.buttons or bar.bling == visible then
        return
    end
    bar.bling = visible
    for i = 1, 12 do
        local button = _G[bar.buttons .. i]
        local cooldown = button and (button.cooldown or _G[bar.buttons .. i .. "Cooldown"])
        if cooldown and cooldown.SetDrawBling then
            cooldown:SetDrawBling(visible)
        end
    end
end

local function TargetAlpha(bar, frame)
    local mode = ModeOf(bar)
    if mode == "show" or ForceShown() then
        return 1
    elseif mode == "hide" then
        return 0
    end
    return frame:IsMouseOver(8, -8, -8, 8) and 1 or 0
end

local function Update(elapsed)
    for _, bar in ipairs(M.BARS) do
        local frame = FrameOf(bar)
        if frame and not frame:IsForbidden() then
            local mode = ModeOf(bar)
            local target = TargetAlpha(bar, frame)
            -- Bars set to "Always show" are left to the client once they are fully back.
            if mode ~= "show" or bar.managed then
                local alpha = frame:GetAlpha()
                if alpha ~= target then
                    local step = elapsed * FADE_SPEED
                    alpha = target > alpha and math.min(target, alpha + step) or math.max(target, alpha - step)
                    frame:SetAlpha(alpha)
                end
                SetMouse(bar, frame, mode ~= "hide" or ForceShown())
                SetBling(bar, alpha > 0)
                bar.managed = mode ~= "show" or alpha < 1
            end
        end
    end
end

function M:Init()
    local throttle = 0
    local watcher = CreateFrame("Frame")
    watcher:SetScript("OnUpdate", function(_, elapsed)
        throttle = throttle + elapsed
        if throttle >= 0.05 then
            Update(throttle)
            throttle = 0
        end
    end)
    S:On("PLAYER_REGEN_ENABLED", function()
        if M.pendingMouse then
            M.pendingMouse = false
            for _, bar in ipairs(M.BARS) do
                local frame = FrameOf(bar)
                if frame and bar.buttons then
                    local wanted = ModeOf(bar) ~= "hide" or ForceShown()
                    bar.mouseEnabled = nil
                    SetMouse(bar, frame, wanted)
                end
            end
        end
    end)
end

function M:Refresh()
    Update(1)
end
