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

-- Client buttons that live on the minimap and must never be treated as addon buttons.
local BLIZZARD_PREFIXES = {
    "Minimap", "MiniMap", "GameTime", "TimeManager", "QueueStatus", "ExpansionLanding", "GarrisonLanding",
    "HybridMinimap", "MinimapBackdrop", "AddonCompartment", "BattlefieldMinimap", "LFG", "MiniMapLFG",
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

local function CompartmentEntries()
    local entries = {}
    local compartment = AddonCompartmentFrame
    for _, entry in ipairs(compartment and compartment.registeredAddons or {}) do
        -- LibDBIcon addons may list themselves in the compartment as well; their own button is enough.
        if type(entry) == "table" and entry.text and not buttons["LibDBIcon10_" .. entry.text] then
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
    self:Scan()
    self:Apply()
end
