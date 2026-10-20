local _, S = ...
local M = S:NewModule("DamageMeter")

-- The built-in damage meter's first window lives inside "DamageMeter", the Edit Mode managed
-- anchor frame (resize it there like an action bar); any further window you open from its own
-- UI is a separate, freely floating frame that always starts at the client's default size
-- (400x200) instead of matching the first one. This copies "DamageMeter"'s real size onto each
-- new extra window the first time it appears - not kept in sync afterwards, so resizing one
-- later doesn't fight a drag you did yourself.
-- Confirmed non-secret and freely resizable by /smuve dump: these are ordinary addon-manipulable
-- panels (they have their own resize buttons, and Modules\DarkMode.lua already skins them),
-- nothing like the protected unit frames elsewhere in this addon.

local synced = setmetatable({}, { __mode = "k" }) -- window -> true, once matched

local function Enabled()
    return S.db.qol.matchDamageMeterSize
end

local function MatchSize(window)
    local source = _G.DamageMeter
    if not source then
        return
    end
    local width, height = source:GetWidth(), source:GetHeight()
    if not width or width <= 0 or not height or height <= 0 then
        return
    end
    window:SetSize(width, height)
end

local function CheckWindows()
    if not Enabled() then
        return
    end
    for i = 2, 3 do
        local window = _G["DamageMeterSessionWindow" .. i]
        if window and not synced[window] then
            synced[window] = true
            pcall(MatchSize, window)
        end
    end
end

-- Row background/border -----------------------------------------------------------------------
-- Each row (the highlighted LocalPlayerEntry, and every generic one pooled under
-- MinimizeContainer.ScrollBox.ScrollTarget as the list fills) has its own StatusBar.Background
-- and .BackgroundEdge, confirmed by /smuve dump; the fill itself is left alone, the same reason
-- health bar fills, the XP bar's fill and the swing timer's fill are never darkened either.
-- Rows are created/reused by the client's own scroll list with no event to hook, so this is
-- scanned on the same ticker as the size match above, registering any new one found with
-- S:Darken (safe to call regardless of the current dark mode state - it only visibly darkens
-- when dark mode is on, and RepaintAll keeps it correct if that's toggled later).

local darkenedRows = setmetatable({}, { __mode = "k" }) -- StatusBar -> true

local function DarkenRow(statusBar)
    if not statusBar or darkenedRows[statusBar] then
        return
    end
    darkenedRows[statusBar] = true
    S:Darken(statusBar.Background)
    S:Darken(statusBar.BackgroundEdge)
end

local function CheckRows(window)
    local container = window and window.MinimizeContainer
    if not container then
        return
    end
    if container.LocalPlayerEntry then
        DarkenRow(container.LocalPlayerEntry.StatusBar)
    end
    local scrollTarget = container.ScrollBox and container.ScrollBox.ScrollTarget
    if scrollTarget then
        for _, row in ipairs({ scrollTarget:GetChildren() }) do
            DarkenRow(row.StatusBar)
        end
    end
end

local function CheckAll()
    for i = 1, 3 do
        local window = _G["DamageMeterSessionWindow" .. i]
        if window then
            pcall(CheckRows, window)
        end
    end
    CheckWindows()
end

function M:Init()
    C_Timer.NewTicker(1, CheckAll)
end
