local addonName, S = ...

-- Options window in the client's own style: a portrait frame with a category list on the left
-- and the settings of the selected category on the right. Open with /smuve (or /sui), from the
-- addon compartment, or from Options > AddOns > SmuveUI.

local WIDTH, HEIGHT = 780, 600
local LIST_WIDTH = 180
local ROW_GAP = 8

local frame
local pages = {}
local categoryButtons = {}
local refreshers = {}   -- functions that re-read the DB into the widgets

-- Widgets -----------------------------------------------------------------------------------------

local function AddTooltip(region, title, text)
    if not text then
        return
    end
    region:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(title, 1, 1, 1)
        GameTooltip:AddLine(text, nil, nil, nil, true)
        GameTooltip:Show()
    end)
    region:HookScript("OnLeave", GameTooltip_Hide)
end

-- A page lays its rows out top to bottom. x/width restrict a layout to one column of a
-- multi-column page (Columns below); left out, rows span the page's full content width.
local function NewLayout(page, x, width)
    return { page = page, y = -64, x = x or 20, width = width }
end

local function NextRow(layout, height)
    local row = CreateFrame("Frame", nil, layout.page)
    row:SetPoint("TOPLEFT", layout.page, "TOPLEFT", layout.x, layout.y)
    if layout.width then
        row:SetWidth(layout.width)
    else
        row:SetPoint("RIGHT", layout.page, "RIGHT", -20, 0)
    end
    row:SetHeight(height)
    layout.y = layout.y - height - ROW_GAP
    return row
end

-- Splits the page, from the current row down, into "count" independent side-by-side layouts
-- (each with its own y cursor), for content that doesn't need the full page width. Call
-- JoinColumns once they're built so layout.y reflects whichever column ran longest - the page's
-- own height is set from layout.y once the category's build function returns.
local COLUMN_GAP = 30
local function Columns(layout, count)
    local contentWidth = layout.page:GetWidth() - layout.x - 20
    local columnWidth = (contentWidth - COLUMN_GAP * (count - 1)) / count
    local columns = {}
    for i = 1, count do
        local column = NewLayout(layout.page, layout.x + (i - 1) * (columnWidth + COLUMN_GAP), columnWidth)
        column.y = layout.y
        columns[i] = column
    end
    return columns
end

local function JoinColumns(layout, columns)
    for _, column in ipairs(columns) do
        layout.y = math.min(layout.y, column.y)
    end
end

local function Header(layout, text)
    layout.y = layout.y - 6
    local row = NextRow(layout, 22)
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    label:SetPoint("LEFT")
    label:SetText(text)
    return row
end

local function Note(layout, text)
    local row = NextRow(layout, 28)
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    label:SetPoint("TOPLEFT", 4, 0)
    label:SetPoint("RIGHT")
    label:SetJustifyH("LEFT")
    label:SetText(text)
    return row, label
end

-- A checkbox in a row; x is its distance from the row's left edge.
local function AddCheckbox(row, x, text, tooltip, get, set)
    local check = CreateFrame("CheckButton", nil, row, "UICheckButtonTemplate")
    check:SetSize(26, 26)
    check:SetPoint("LEFT", row, "LEFT", x, 0)
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", check, "RIGHT", 4, 1)
    label:SetText(text)
    -- Blizzard's template brings its own (empty) label; ours is used instead.
    if check.Text then
        check.Text:SetText("")
    end
    check:SetScript("OnClick", function(self)
        PlaySound(self:GetChecked() and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        set(self:GetChecked() and true or false)
    end)
    AddTooltip(check, text, tooltip)
    local function refresh()
        check:SetChecked(get() and true or false)
    end
    refresh()
    table.insert(refreshers, refresh)
    return check, label
end

local function Checkbox(layout, text, tooltip, get, set)
    local row = NextRow(layout, 26)
    row.check, row.label = AddCheckbox(row, 0, text, tooltip, get, set)
    return row
end

-- A second checkbox in the right-hand column of an existing checkbox row.
local SECOND_COLUMN = 290
local function CheckboxRight(row, text, tooltip, get, set)
    row.rightCheck, row.rightLabel = AddCheckbox(row, SECOND_COLUMN, text, tooltip, get, set)
    return row
end

-- Slider with the value to its right; the value can be clicked and typed in.
local function Slider(layout, text, tooltip, min, max, step, get, set, suffix)
    local row = NextRow(layout, 30)
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", 4, 0)
    label:SetWidth(200)
    label:SetJustifyH("LEFT")
    label:SetText(text)

    local slider = CreateFrame("Frame", nil, row, "MinimalSliderWithSteppersTemplate")
    slider:SetPoint("LEFT", label, "RIGHT", 10, 0)
    slider:SetSize(250, 20)

    local input = CreateFrame("EditBox", nil, row, "InputBoxTemplate")
    input:SetSize(46, 20)
    input:SetPoint("LEFT", slider, "RIGHT", 14, 0)
    input:SetAutoFocus(false)
    input:SetJustifyH("CENTER")
    input:SetMaxLetters(5)

    local suffixLabel = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    suffixLabel:SetPoint("LEFT", input, "RIGHT", 4, 0)
    suffixLabel:SetText(suffix or "")

    -- Decimal places of the step (0.05 -> 2), for clean values and display.
    local decimals = step < 1 and math.max(0, math.ceil(-math.log10(step) - 1e-9)) or 0

    local function Snap(value)
        value = math.floor((value - min) / step + 0.5) * step + min
        value = tonumber(string.format("%." .. decimals .. "f", value))
        return math.max(min, math.min(max, value))
    end

    local updating = false
    local function Show(value)
        input:SetText(decimals > 0 and string.format("%." .. decimals .. "f", value) or tostring(value))
        input:SetCursorPosition(0)
    end

    slider:Init(get(), min, max, (max - min) / step, {})
    slider:RegisterCallback(MinimalSliderWithSteppersMixin.Event.OnValueChanged, function(_, value)
        value = Snap(value)
        Show(value)
        if not updating and value ~= get() then
            set(value)
        end
    end, row)

    local function Commit()
        local value = tonumber(input:GetText())
        if value then
            value = Snap(value)
            slider:SetValue(value)
            if value ~= get() then
                set(value)
            end
        end
        Show(get())
        input:ClearFocus()
    end
    input:SetScript("OnEnterPressed", Commit)
    input:SetScript("OnEditFocusLost", Commit)
    input:SetScript("OnEscapePressed", function(self)
        Show(get())
        self:ClearFocus()
    end)

    AddTooltip(slider, text, tooltip)
    local function refresh()
        updating = true
        slider:SetValue(get())
        updating = false
        Show(get())
    end
    refresh()
    table.insert(refreshers, refresh)
    return row
end

-- options: list of { value, text }
local function Dropdown(layout, text, tooltip, getOptions, get, set)
    local row = NextRow(layout, 30)
    local label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    label:SetPoint("LEFT", 4, 0)
    label:SetWidth(200)
    label:SetJustifyH("LEFT")
    label:SetText(text)

    local dropdown = CreateFrame("DropdownButton", nil, row, "WowStyle1DropdownTemplate")
    dropdown:SetPoint("LEFT", label, "RIGHT", 10, 0)
    dropdown:SetWidth(250)
    dropdown:SetupMenu(function(_, root)
        root:SetScrollMode(400)
        for _, option in ipairs(getOptions()) do
            root:CreateRadio(option.text, function() return get() == option.value end, function()
                set(option.value)
            end, option.value)
        end
    end)
    AddTooltip(dropdown, text, tooltip)
    table.insert(refreshers, function()
        dropdown:GenerateMenu()
    end)
    return row
end

local function Button(layout, text, tooltip, onClick)
    local row = NextRow(layout, 26)
    local button = CreateFrame("Button", nil, row, "UIPanelButtonTemplate")
    button:SetText(text)
    local width = math.max(160, button:GetFontString():GetStringWidth() + 30)
    if layout.width then
        width = math.min(width, layout.width - 4)
    end
    button:SetSize(width, 24)
    button:SetPoint("LEFT", 2, 0)
    button:SetScript("OnClick", onClick)
    AddTooltip(button, text, tooltip)
    return row, button
end

-- Setting accessors -------------------------------------------------------------------------------

-- module: a module name, a list of them, or nil to refresh nothing.
local function Setting(section, key, module)
    return function()
        return S.db[section][key]
    end, function(value)
        S.db[section][key] = value
        if type(module) == "table" then
            for _, name in ipairs(module) do
                S:Refresh(name)
            end
        elseif module then
            S:Refresh(module)
        end
    end
end

-- Pages -------------------------------------------------------------------------------------------

local CATEGORIES = {}

StaticPopupDialogs["SMUVEUI_FONT_RELOAD"] = {
    text = "SmuveUI: reload the interface now to apply the font change?",
    button1 = RELOADUI or "Reload",
    button2 = LATER or "Later",
    OnAccept = function()
        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

CATEGORIES[1] = { key = "appearance", title = "Appearance", build = function(layout)
    Header(layout, "Dark Mode")
    Checkbox(layout, "Enable dark mode",
        "Tints the borders and frames of the default UI almost black. Textures stay the client's own.",
        Setting("appearance", "darkMode", "DarkMode"))
    local getDarkness, setDarkness = Setting("appearance", "darkness", "DarkMode")
    Slider(layout, "Darkness", "How dark the tinted textures get. 90% leaves them at a tenth of their brightness.",
        50, 100, 1, getDarkness, setDarkness, "%")

    Header(layout, "Fonts")
    local getFont, setFont = Setting("appearance", "font", "Fonts")
    Dropdown(layout, "Global font", "The font used across the whole interface.", function()
        local options = { { value = "DEFAULT", text = "Default (client font)" } }
        for _, font in ipairs(S.modules.Fonts:GetFontList()) do
            table.insert(options, { value = font.path, text = font.name })
        end
        return options
    end, getFont, function(value)
        setFont(value)
        StaticPopup_Show("SMUVEUI_FONT_RELOAD")
    end)
end }

CATEGORIES[2] = { key = "qol", title = "QoL", build = function(layout)
    local columns = Columns(layout, 2)
    local left, right = columns[1], columns[2]

    Header(left, "Loot")
    Checkbox(left, "Faster loot",
        "With auto loot on, takes every item the moment the loot window opens.",
        Setting("qol", "fastLoot"))
    Checkbox(left, "Loot roll tracker",
        "Need/Greed/Pass show how many players chose them; hover a button to see who. After you rolled, the roll stays up until everyone has chosen.",
        Setting("qol", "lootRolls", "LootRoll"))
    Checkbox(left, "Unlock loot roll window",
        "Edit Mode doesn't offer this window, so it's moved by dragging it directly while this is checked. Always off after a reload.",
        Setting("qol", "lootRollUnlocked", "LootRoll"))
    if S.IsAddOnLoaded("BetterGroupLoot") then
        Note(left, "BetterGroupLoot is loaded and replaces the roll frames, so the tracker is inactive.")
    end

    Header(left, "Quests")
    Checkbox(left, "Hide objective tracker with a quest guide",
        "Completely hides the default objective tracker while RestedXP, Journey or Polestar is loaded. Without one of them the tracker stays.",
        Setting("qol", "hideObjectiveTracker", "ObjectiveTracker"))
    local guide = S.modules.ObjectiveTracker:GetDetected()
    Note(left, guide and ("Detected quest guide: |cffffffff" .. guide .. "|r")
        or "No quest guide detected, so the tracker stays visible.")

    Header(left, "Damage Meter")
    Checkbox(left, "Match window size",
        "A second or third damage meter window (opened from the damage meter's own UI) starts at the same size as the first, instead of the client's default.",
        Setting("qol", "matchDamageMeterSize", "DamageMeter"))

    Header(right, "Character")
    Checkbox(right, "Item rarity borders and enchants",
        "Character frame items get a border in their rarity color and a short note of their enchant, or \"Missing\".",
        Setting("qol", "characterInfo", "Character"))
    Checkbox(right, "Item level on equipped items",
        "Shows each equipped item's level in its bottom corner, in its rarity color.",
        Setting("qol", "itemLevel", "Character"))

    Header(right, "Chat")
    local chatAvailable = S.modules.Chat:IsAvailable()
    local syncRow = Checkbox(right, "Share chat tabs across characters",
        "Chat tabs, their channels, message types, colors and font size are stored for your whole account and set up on every character you log in with.",
        Setting("qol", "chatSync"))
    local urlRow = Checkbox(right, "Copyable links in chat",
        "Web addresses in chat become clickable; clicking one opens a box to copy it from.",
        Setting("qol", "chatUrls"))
    local historyRow = Checkbox(right, "Chat history",
        "The last 200 lines of each chat window (not the combat log) are kept across reloads and relogs, and shown again under a divider.",
        Setting("qol", "chatHistory", "Chat"))
    local outlineRow = Checkbox(right, "Outline",
        "Outlines the text in every chat window.",
        Setting("qol", "chatOutline", "Chat"))
    local _, saveButton = Button(right, "Share this chat now",
        "Stores the current chat tabs as the shared layout right away, instead of at logout.",
        function()
            S.modules.Chat:SaveNow()
            S.Print("Chat layout saved for all characters.")
        end)
    if not chatAvailable then
        syncRow.check:Disable()
        urlRow.check:Disable()
        historyRow.check:Disable()
        outlineRow.check:Disable()
        saveButton:Disable()
        Note(right, "Chattynator is loaded and already shares its tabs and links URLs, so these are inactive.")
    end

    JoinColumns(layout, columns)
end }

CATEGORIES[3] = { key = "actionbars", title = "Action Bars", build = function(layout)
    Header(layout, "Action Bars")
    Checkbox(layout, "Range indicator",
        "Colors the whole button icon: red when out of range, blue when you lack the mana, gray when unusable.",
        Setting("actionbars", "rangeIndicator", "ActionBars"))

    Header(layout, "Experience Bar")
    Slider(layout, "Scale", "Scale of the experience / reputation bar above the action bars (1 = normal size).",
        0.5, 2, 0.05, Setting("actionbars", "xpScale", "StatusBars"))

    Header(layout, "Visibility")
    Note(layout, "Hidden bars are invisible and click-through, but their key bindings still work. All bars show while you drag a spell or are in Edit Mode.")
    local module = S.modules.BarVisibility
    for _, bar in ipairs(module.BARS) do
        Dropdown(layout, bar.label, "Show " .. bar.label:lower() .. " always, only when the mouse is over it, or never.",
            function()
                return module.MODES
            end,
            function()
                return S.db.actionbars.visibility[bar.key] or "show"
            end,
            function(value)
                S.db.actionbars.visibility[bar.key] = value ~= "show" and value or nil
                S:Refresh("BarVisibility")
            end)
    end
end }

-- Aura settings for the target or focus frame (each has its own).
local function AuraSettings(layout, unit, label)
    local function UA(key)
        return function()
            return S.db.unitAuras[unit][key]
        end, function(value)
            S.db.unitAuras[unit][key] = value
            S:Refresh("UnitAuras")
        end
    end
    Header(layout, "Auras")
    if not S.modules.UnitAuras:IsSupported() then
        Note(layout, "This client doesn't offer the aura containers these auras need, so they are inactive.")
    end
    local enableRow = Checkbox(layout, "Enable", "Replaces the auras of the " .. label .. " frame with adjustable ones. Turning it off needs a /reload.", UA("enabled"))
    if unit == "target" then
        CheckboxRight(enableRow, "Test mode", "Shows sample icons below the target frame, to check sizes and offsets. Works even while disabled. Always off after a reload.", UA("testMode"))
    end
    Checkbox(layout, "Show duration", "Shows the remaining time at the bottom of each aura icon, like on your own auras.", UA("showDuration"))
    Checkbox(layout, "Glow on purgeable buffs", "Buffs you can remove (Purge, Dispel Magic, Tranquilizing Shot, ...) on an enemy " .. label .. " get a glowing border.", UA("purgeGlow"))
    Slider(layout, "Aura duration size", "Text size of the remaining time and the stack count (top right).", 6, 20, 1, UA("durationSize"))

    Header(layout, "Buffs (below the frame)")
    Slider(layout, "Icon size", "Size of the buff icons.", 10, 40, 1, UA("buffSize"))
    Slider(layout, "Icons per row", "After this many buffs a new row starts below.", 1, 16, 1, UA("buffPerRow"))
    Slider(layout, "Rows", "How many buff rows there can be.", 1, 6, 1, UA("buffRows"))

    Header(layout, "Debuffs (below the buffs)")
    Slider(layout, "Icon size", "Size of the debuff icons.", 10, 40, 1, UA("debuffSize"))
    Slider(layout, "Icons per row", "After this many debuffs a new row starts below.", 1, 16, 1, UA("debuffPerRow"))
    Slider(layout, "Rows", "How many debuff rows there can be.", 1, 6, 1, UA("debuffRows"))
end

CATEGORIES[4] = { key = "unitframes", title = "Unit Frames", build = function(layout)
    Header(layout, "Unit Frames")
    Checkbox(layout, "Class colored health bars",
        "Player, target, focus, target of target and nameplate health bars use the class color of players. NPCs keep their usual colors.",
        Setting("appearance", "classColors", { "UnitFrames", "Nameplates" }))
    Checkbox(layout, "Reaction colored health bars",
        "Health bars of units that aren't shown in a class color are red (hostile), yellow (neutral) or green (friendly). Class colors come first.",
        Setting("appearance", "reactionColors", { "UnitFrames", "Nameplates" }))
    Checkbox(layout, "Class colored names",
        "Player names on the player, target, focus and target of target frames are shown in their class color.",
        Setting("appearance", "classColorNames", "UnitFrames"))
    Checkbox(layout, "Hide name glow",
        "The reaction colored band behind the name on the target and focus frames is hidden.",
        Setting("appearance", "hideNameGlow", "UnitFrames"))

    Header(layout, "Big Debuffs (Experimental, WIP)")
    if not S.modules.BigDebuffs:IsSupported() then
        Note(layout, "This client doesn't offer the aura containers this needs, so it's inactive.")
    end
    Note(layout, "Experimental and still a work in progress: some important buffs (movement immunities, etc.) are a short, hand-picked list rather than a complete one, and may be missing ones you'd expect.")
    Note(layout, "Shows the unit's current crowd control debuff, or - with none - an important buff (a big defensive, an externally applied one, or another important buff) as one big icon filling its portrait.")
    local enableRow = Checkbox(layout, "Player frame", "Shows the big icon over the player frame's portrait.",
        function() return S.db.bigDebuffs.player.enabled end,
        function(value)
            S.db.bigDebuffs.player.enabled = value
            S:Refresh("BigDebuffs")
        end)
    CheckboxRight(enableRow, "Target frame", "Shows the big icon over the target frame's portrait.",
        function() return S.db.bigDebuffs.target.enabled end,
        function(value)
            S.db.bigDebuffs.target.enabled = value
            S:Refresh("BigDebuffs")
        end)
    local durationRow = Checkbox(layout, "Show duration", "Shows the remaining time centered over the icon, in the same format as your own auras.",
        Setting("bigDebuffs", "showDuration", "BigDebuffs"))
    CheckboxRight(durationRow, "Test mode", "Shows a sample icon over both portraits, to check sizing. Always off after a reload.",
        Setting("bigDebuffs", "testMode", "BigDebuffs"))
    Slider(layout, "Duration size", "Text size of the remaining time.", 6, 30, 1, Setting("bigDebuffs", "durationSize", "BigDebuffs"))
end }

CATEGORIES[5] = { key = "player", title = "Player", indent = true, build = function(layout)
    Header(layout, "Auras")
    Slider(layout, "Aura duration size", "Text size of the remaining time and the stack count (top right) on your buffs and debuffs.",
        6, 20, 1, Setting("appearance", "auraDurationSize", "Auras"))
end }

CATEGORIES[6] = { key = "target", title = "Target", indent = true, build = function(layout)
    AuraSettings(layout, "target", "target")
end }

CATEGORIES[7] = { key = "focus", title = "Focus", indent = true, build = function(layout)
    AuraSettings(layout, "focus", "focus")
end }

CATEGORIES[9] = { key = "tooltip", title = "Tooltip", build = function(layout)
    Header(layout, "Tooltip")
    Checkbox(layout, "Dark tooltips",
        "Tooltips get a near black background and a darkened border.",
        Setting("tooltip", "dark", "Tooltip"))
    Checkbox(layout, "Class colored names",
        "Player names in unit tooltips are shown in their class color.",
        Setting("tooltip", "classColorNames"))
    Checkbox(layout, "Class colored class",
        "The class in a player's level line (e.g. \"Shaman\") is shown in its class color.",
        Setting("tooltip", "classColorClass"))
end }

CATEGORIES[10] = { key = "nameplates", title = "Nameplates", build = function(layout)
    local function NP(key)
        return Setting("nameplates", key, "Nameplates")
    end
    Header(layout, "Enemy Nameplates")
    if not S.modules.Nameplates:IsSupported() then
        Note(layout, "This client doesn't offer the aura containers these nameplates need, so they are inactive.")
    end
    local enableRow = Checkbox(layout, "Enable", "Crowd control right of the bar, important buffs left of it, your debuffs and the remaining buffs in rows above it.", NP("enabled"))
    CheckboxRight(enableRow, "Test mode", "Shows sample icons on every visible nameplate, to check sizes and offsets. Always off after a reload.", NP("testMode"))
    Checkbox(layout, "Only my debuffs", "The debuff row shows only debuffs you applied. Crowd control is always shown.", NP("onlyMyDebuffs"))
    Checkbox(layout, "Glow on purgeable buffs", "Buffs you can remove (Purge, Dispel Magic, Tranquilizing Shot, ...) on enemy nameplates get a glowing border.", NP("purgeGlow"))
    Checkbox(layout, "Align centered", "The debuff and buff rows above the bar grow from the center to both sides, instead of from the left.", NP("centerAuras"))
    Slider(layout, "Aura spacing", "Space between all aura icons.", 0, 12, 1, NP("spacing"))

    Header(layout, "Size (all nameplates)")
    Slider(layout, "Nameplate scale", "Size of every nameplate, its aura icons included.", 0.5, 2, 0.05, NP("scale"))
    Slider(layout, "Nameplate width", "Width of every nameplate and its health bar. Can't change in combat.", 60, 300, 1,
        function() return S.modules.Nameplates:GetWidth() end,
        function(value)
            S.db.nameplates.width = value
            S.modules.Nameplates:ApplyWidth()
        end)
    Slider(layout, "Health bar height", "Height of the health bar on every nameplate.", 4, 40, 1,
        function() return S.modules.Nameplates:GetBarHeight() end,
        function(value)
            S.db.nameplates.barHeight = value
            S:Refresh("Nameplates")
        end)

    Header(layout, "Name & Level")
    Slider(layout, "Name X offset", "Moves the name on enemy nameplates left (negative) or right.", -60, 60, 1, NP("nameX"))
    Slider(layout, "Name Y offset", "Moves the name on enemy nameplates down (negative) or up.", -10, 30, 1, NP("nameY"))
    Slider(layout, "Name size", "Text size of the name on every nameplate.", 6, 24, 1,
        function() return S.modules.Nameplates:GetTextSize("nameSize") end,
        function(value)
            S.db.nameplates.nameSize = value
            S:Refresh("Nameplates")
        end)
    Slider(layout, "Level size", "Text size of the level number on every nameplate.", 6, 24, 1,
        function() return S.modules.Nameplates:GetTextSize("levelSize") end,
        function(value)
            S.db.nameplates.levelSize = value
            S:Refresh("Nameplates")
        end)

    Header(layout, "Debuffs (above the bar)")
    Slider(layout, "Icon size", "Size of the debuff icons.", 12, 40, 1, NP("debuffSize"))
    Slider(layout, "Icons per row", "After this many debuffs a new row starts above.", 1, 12, 1, NP("debuffPerRow"))
    Slider(layout, "Rows", "How many debuff rows there can be.", 1, 4, 1, NP("debuffRows"))
    Slider(layout, "X offset", "Moves the debuff row left (negative) or right.", -60, 60, 1, NP("debuffX"))
    Slider(layout, "Y offset", "Height of the debuff row above the health bar; keep it above the name.", -20, 60, 1, NP("debuffY"))

    Header(layout, "Remaining buffs (above the debuffs)")
    Slider(layout, "Icon size", "Size of the buff icons.", 12, 40, 1, NP("buffSize"))
    Slider(layout, "Icons per row", "After this many buffs a new row starts above.", 1, 12, 1, NP("buffPerRow"))
    Slider(layout, "Rows", "How many buff rows there can be.", 1, 4, 1, NP("buffRows"))

    Header(layout, "Important buffs (left of the bar)")
    Slider(layout, "Scale", "Size of the important buff icons (big and external defensives, important auras), relative to the debuff icons.", 0.5, 3, 0.05, NP("importantScale"))
    Slider(layout, "Maximum", "How many important buffs are shown.", 1, 6, 1, NP("importantMax"))
    Slider(layout, "X offset", "Moves them left (negative) or right.", -60, 60, 1, NP("importantX"))
    Slider(layout, "Y offset", "Moves them down (negative) or up.", -40, 40, 1, NP("importantY"))

    Header(layout, "Crowd control (right of the bar)")
    Slider(layout, "Scale", "Size of the crowd control icons, relative to the debuff icons.", 0.5, 3, 0.05, NP("ccScale"))
    Slider(layout, "Maximum", "How many crowd control effects are shown.", 1, 6, 1, NP("ccMax"))
    Slider(layout, "X offset", "Moves them left (negative) or right.", -60, 60, 1, NP("ccX"))
    Slider(layout, "Y offset", "Moves them down (negative) or up.", -40, 40, 1, NP("ccY"))
end }

CATEGORIES[8] = { key = "partyframes", title = "Party Frames", build = function(layout)
    local function PF(key)
        return Setting("partyFrames", key, "PartyFrames")
    end
    Header(layout, "Party Frames")
    if not S.modules.PartyFrames:IsSupported() then
        Note(layout, "This client doesn't offer the aura containers these need, so they are inactive.")
    end
    Note(layout, "The default (raid-style) party frames don't show buffs on this client, so this draws them itself: each member's own buffs in the top-right corner, and - separately - their current crowd control (first) or an important buff (a big defensive, an externally applied one, or another important buff) centered on the frame.")
    Checkbox(layout, "Enable", "Turns both displays on for every party member frame.", PF("enabled"))
    Header(layout, "Buffs (top-right)")
    Slider(layout, "Icon size", "Size of the unit's own buff icons.", 6, 30, 1, PF("buffSize"))
    Slider(layout, "Maximum", "How many buffs can be shown at once.", 1, 6, 1, PF("buffMax"))
    Header(layout, "Crowd control / important buffs (centered)")
    Slider(layout, "Icon size", "Size of the crowd control / important buff icons.", 6, 30, 1, PF("ccSize"))
    Slider(layout, "Maximum", "How many of these can be shown at once.", 1, 3, 1, PF("ccMax"))
end }

CATEGORIES[11] = { key = "minimap", title = "Map & Minimap", build = function(layout, page)
    Header(layout, "Minimap")
    Checkbox(layout, "Hide addon buttons",
        "Addon buttons around the minimap and the client's addon compartment are hidden; right-click the map to open them all in one box.",
        Setting("minimap", "hideButtons", "Minimap"))
    Note(layout, "Right-click the minimap to open the box with the hidden buttons. It closes on the next right-click or shortly after the mouse leaves.")
    Header(layout, "Buttons in the box (unchecked ones stay on the minimap)")
    page.listStart = layout.y
    page.buttonRows = {}
end }

-- Every module can be switched off completely (the same as /smuve disable <Module>).
local MODULE_NAMES = {
    DarkMode = { "Dark mode", "Dark tint of the default UI's frames, windows, minimap and menus." },
    Fonts = { "Global font", "The font chosen under Appearance." },
    Tooltip = { "Tooltip", "Dark tooltips and class colored names." },
    Auras = { "Player auras", "Your buffs and debuffs: black borders, duration and stacks inside the icon." },
    UnitFrames = { "Unit frames", "Class and reaction colored health bars, class colored names, your own name and the target's mana values." },
    StatusBars = { "Experience bar", "The experience bar's scale." },
    BarVisibility = { "Bar visibility", "Action bars, menu bar and bag bar shown always, on mouseover or hidden." },
    LossOfControl = { "Loss of control", "The loss of control alert in the middle of the screen with a black icon border." },
    Chat = { "Chat", "Chat tabs shared across characters and copyable links." },
    Character = { "Character frame", "Item rarity borders and enchant notes." },
    LootRoll = { "Loot rolls", "Who chose Need, Greed or Pass, and rolls staying until everyone chose." },
    ActionBars = { "Range indicator", "Action button icons colored by range, mana and usability." },
    Minimap = { "Minimap buttons", "Addon buttons hidden, shown in a box on right-click." },
    FastLoot = { "Faster loot", "Loots every item at once." },
    DamageMeter = { "Damage meter", "A new damage meter window matches the first one's size." },
    ObjectiveTracker = { "Objective tracker", "Hides the objective tracker while a quest guide is loaded." },
    Nameplates = { "Nameplates", "Enemy nameplate auras, name, size and test mode." },
    UnitAuras = { "Target & focus auras", "The target and focus frames' own buff and debuff rows." },
    BigDebuffs = { "Big debuffs", "A big crowd control / important buff icon over the player and target portraits." },
    PartyFrames = { "Party frames", "Buffs and crowd control / important icons on the default party frames." },
}

StaticPopupDialogs["SMUVEUI_MODULE_RELOAD"] = {
    text = "SmuveUI: reload the interface now to apply the module change?",
    button1 = RELOADUI or "Reload",
    button2 = LATER or "Later",
    OnAccept = function()
        ReloadUI()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
}

CATEGORIES[12] = { key = "modules", title = "Modules", build = function(layout)
    Header(layout, "Modules")
    Note(layout, "A module that is switched off doesn't run at all. Changes take effect after a reload.")
    for _, module in ipairs(S.moduleOrder) do
        local names = MODULE_NAMES[module.name] or { module.name }
        Checkbox(layout, names[1], names[2], function()
            return not S:IsModuleDisabled(module.name)
        end, function(value)
            S.db.disabledModules = S.db.disabledModules or {}
            S.db.disabledModules[module.name] = (not value) or nil
            StaticPopup_Show("SMUVEUI_MODULE_RELOAD")
        end)
    end
    Button(layout, "Reload UI", "Reloads the interface so module changes take effect.", ReloadUI)
end }

-- The per-button list is rebuilt whenever the minimap module finds new buttons.
function S:OptionsRefreshMinimapList()
    local page = pages.minimap and pages.minimap.content
    if not page or not page.listStart then
        return
    end
    for _, row in ipairs(page.buttonRows) do
        row:Hide()
    end
    local layout = { page = page, y = page.listStart }
    local list = S.modules.Minimap:GetButtons()
    page.buttonRows = {}
    if #list == 0 then
        local row = Note(layout, "No addon buttons found on the minimap.")
        table.insert(page.buttonRows, row)
        page:SetHeight(-layout.y + 10)
        return
    end
    for _, entry in ipairs(list) do
        local row = Checkbox(layout, entry.label, "Unchecked buttons always stay visible.", function()
            return not S.db.minimap.alwaysShown[entry.name]
        end, function(value)
            S.db.minimap.alwaysShown[entry.name] = (not value) or nil
            S:Refresh("Minimap")
        end)
        table.insert(page.buttonRows, row)
    end
    page:SetHeight(-layout.y + 10)
end

-- Window ------------------------------------------------------------------------------------------

local function SelectCategory(key)
    for _, category in ipairs(CATEGORIES) do
        local selected = category.key == key
        pages[category.key]:SetShown(selected)
        local button = categoryButtons[category.key]
        button.selected:SetShown(selected)
        -- Sub-pages are white, so they stand apart from the categories.
        button.label:SetFontObject((selected or category.indent) and "GameFontHighlight" or "GameFontNormal")
    end
    frame.selected = key
end

local function CreateCategoryButton(parent, category, index)
    -- Sub-pages (Player, Target, Focus under Unit Frames) sit indented below their category.
    local indent = category.indent and 14 or 0
    local button = CreateFrame("Button", nil, parent)
    button:SetSize(LIST_WIDTH - 16 - indent, 24)
    button:SetPoint("TOPLEFT", parent, "TOPLEFT", 8 + indent, -8 - (index - 1) * 26)

    local selected = button:CreateTexture(nil, "BACKGROUND")
    selected:SetAtlas("Options_List_Active", false)
    selected:SetAllPoints()
    selected:Hide()
    button.selected = selected

    local highlight = button:CreateTexture(nil, "HIGHLIGHT")
    highlight:SetAtlas("Options_List_Hover", false)
    highlight:SetAllPoints()

    local label = button:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    label:SetPoint("LEFT", 10, 0)
    label:SetText(category.title)
    button.label = label

    button:SetScript("OnClick", function()
        PlaySound(SOUNDKIT.IG_MAINMENU_OPTION)
        SelectCategory(category.key)
    end)
    return button
end

local function CreateOptionsFrame()
    frame = CreateFrame("Frame", "SmuveUIOptionsFrame", UIParent, "PortraitFrameTemplate")
    frame:SetSize(WIDTH, HEIGHT)
    frame:SetPoint("CENTER")
    frame:SetFrameStrata("HIGH")
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
        frame:SetTitle("SmuveUI")
    elseif frame.TitleText then
        frame.TitleText:SetText("SmuveUI")
    end
    if frame.SetPortraitToAsset then
        frame:SetPortraitToAsset("Interface\\Icons\\INV_Misc_Gear_01")
    elseif frame.PortraitContainer and frame.PortraitContainer.portrait then
        frame.PortraitContainer.portrait:SetTexture("Interface\\Icons\\INV_Misc_Gear_01")
    end

    local list = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    list:SetPoint("TOPLEFT", frame, "TOPLEFT", 10, -64)
    list:SetPoint("BOTTOMLEFT", frame, "BOTTOMLEFT", 10, 10)
    list:SetWidth(LIST_WIDTH)

    local content = CreateFrame("Frame", nil, frame, "InsetFrameTemplate")
    content:SetPoint("TOPLEFT", list, "TOPRIGHT", 6, 0)
    content:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -10, 10)

    local version = frame:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    version:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -14, -38)
    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
    version:SetText("v" .. (getMetadata(addonName, "Version") or "?"))

    for index, category in ipairs(CATEGORIES) do
        categoryButtons[category.key] = CreateCategoryButton(list, category, index)

        -- Every page scrolls, so long pages never run out of the window.
        local holder = CreateFrame("Frame", nil, content)
        holder:SetAllPoints()
        holder:Hide()
        local scroll = CreateFrame("ScrollFrame", nil, holder, "UIPanelScrollFrameTemplate")
        scroll:SetPoint("TOPLEFT", 0, -4)
        scroll:SetPoint("BOTTOMRIGHT", -28, 6)
        local page = CreateFrame("Frame", nil, scroll)
        page:SetSize(WIDTH - LIST_WIDTH - 70, 1)
        scroll:SetScrollChild(page)
        scroll:SetScript("OnSizeChanged", function(_, width)
            page:SetWidth(width)
        end)
        holder.content = page

        local title = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
        title:SetPoint("TOPLEFT", 20, -18)
        title:SetText(category.title)

        local divider = page:CreateTexture(nil, "ARTWORK")
        divider:SetAtlas("Options_HorizontalDivider", true)
        divider:SetPoint("TOPLEFT", title, "BOTTOMLEFT", -4, -8)
        divider:SetPoint("RIGHT", page, "RIGHT", -16, 0)

        pages[category.key] = holder
        local layout = NewLayout(page)
        S.SafeCall(category.build, layout, page)
        page:SetHeight(-layout.y + 10)
    end

    frame:HookScript("OnShow", function()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_OPEN)
        for _, refresh in ipairs(refreshers) do
            S.SafeCall(refresh)
        end
    end)
    frame:HookScript("OnHide", function()
        PlaySound(SOUNDKIT.IG_CHARACTER_INFO_CLOSE)
    end)

    S:OptionsRefreshMinimapList()
    SelectCategory(CATEGORIES[1].key)

    if S.modules.DarkMode.SkinPanels then
        S.modules.DarkMode:SkinPanels()
    end
end

function S:ToggleOptions()
    if InCombatLockdown() and not frame then
        S.Print("Options open after combat.")
        return
    end
    if not frame then
        CreateOptionsFrame()
    end
    frame:SetShown(not frame:IsShown())
end

-- Entry in the client's Options > AddOns list ------------------------------------------------------

S:On("PLAYER_LOGIN", function()
    if not (Settings and Settings.RegisterCanvasLayoutCategory) then
        return
    end
    local panel = CreateFrame("Frame")
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightHuge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("SmuveUI")

    local open = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    open:SetSize(200, 26)
    open:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -16)
    open:SetText("Open SmuveUI Options")
    open:SetScript("OnClick", function()
        if SettingsPanel and SettingsPanel:IsShown() then
            HideUIPanel(SettingsPanel)
        end
        if not frame or not frame:IsShown() then
            S:ToggleOptions()
        end
    end)

    local hint = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    hint:SetPoint("TOPLEFT", open, "BOTTOMLEFT", 0, -12)
    hint:SetText("You can also type /smuve or /sui.")

    local category = Settings.RegisterCanvasLayoutCategory(panel, "SmuveUI")
    Settings.RegisterAddOnCategory(category)
end)
