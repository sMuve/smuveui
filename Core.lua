local addonName, S = ...
_G.SmuveUI = S

S.name = addonName
S.modules = {}
S.moduleOrder = {}

-- Defaults ----------------------------------------------------------------------------------------

S.defaults = {
    appearance = {
        colorMode = "dark",     -- "off" | "dark" | "class": mutually exclusive, see Core.lua's Paint()
        darkness = 90,          -- percent; 90 means textures keep 10% of their brightness (Dark mode)
        classColorIntensity = 90, -- same, for Class color mode
        font = "Interface\\AddOns\\SmuveUI\\Media\\Fonts\\Rajdhani-Bold.ttf", -- "DEFAULT" keeps the client's fonts instead
        auraDurationSize = 12,
        auraBuffsPos = nil,     -- { point, x, y }; nil keeps the built-in default position. Debuffs
                                -- anchors to the buffs container instead of having its own position.
        auraBarsUnlocked = false, -- always off after a reload; drag the buffs bar while it's on
        auraBuffsScale = 1,
        auraDebuffsScale = 1,
        auraBuffsPerRow = 10,
        auraDebuffsPerRow = 10,
        classColors = true,     -- class colored health bars on player/target/focus/target of target
        reactionColors = true,  -- other units: red / yellow / green by reaction (class color first)
        classColorNames = false, -- player names on the unit frames in class color
        hideNameGlow = true,    -- the reaction colored band behind the target / focus name
    },
    qol = {
        fastLoot = true,
        chatSync = true,
        chatUrls = true,
        chatHistory = true,
        chatOutline = false,
        whisperSound = false,             -- plays a sound on an incoming whisper
        whisperSoundKit = "TELL_MESSAGE", -- which one (Modules\WhisperSound.lua's SOUNDS list)
        easyFishing = false,    -- one key casts/reels, and the bite cue plays louder, with a fishing rod in hand
        easyFishingKey = nil,   -- the assigned key (a WoW binding string), unbound until the player sets one
        easyFishingBoost = 5,   -- how many times louder Sound Effects play while a bobber is active
        characterInfo = true,
        itemLevel = true,       -- item level on equipped items, colored by rarity
        lootRolls = true,
        lootRollLinger = true,   -- the roll window stays up after you voted until everyone has
        lootRollUnlocked = false, -- always off after a reload; drag the window while it's on
        autoSellJunk = false,     -- sells poor-quality items the moment a vendor window opens
        autoRepair = false,       -- repairs all equipped gear the moment a vendor window opens
        hideObjectiveTracker = false,  -- only acts while RestedXP, Journey or Polestar is loaded
        questSparkle = false,    -- always shows the client's loot-glow outline on quest items
        matchDamageMeterSize = true,   -- a new damage meter window matches the first one's size
        skipDeleteConfirmText = false, -- a plain click deletes rare+ items, no typing "DELETE"
        combatIndicator = false,  -- +COMBAT/-COMBAT flashed center screen entering/leaving combat
        friendFactionColors = true, -- tints Battle.net friend rows blue/red by their character's faction
    },
    actionbars = {
        rangeIndicator = true,
        visibility = {},        -- bar key -> "show" | "mouseover" | "hide" (missing = "show")
        xpScale = 1,
    },
    tooltip = {
        dark = true,
        classColorNames = true,
        classColorClass = true,     -- the class word in the level line
    },
    unitAuras = {               -- target and focus frame auras, each with its own settings
        target = {
            enabled = true,
            testMode = false,  -- always off after a reload
            buffSize = 24,
            buffPerRow = 5,
            buffRows = 3,
            debuffSize = 24,
            debuffPerRow = 5,
            debuffRows = 3,
            showDuration = false,
            durationSize = 10,
            purgeGlow = true,   -- glow on enemy buffs you can purge
        },
        focus = {
            enabled = true,
            buffSize = 24,
            buffPerRow = 5,
            buffRows = 3,
            debuffSize = 24,
            debuffPerRow = 5,
            debuffRows = 3,
            showDuration = false,
            durationSize = 10,
            purgeGlow = true,   -- glow on enemy buffs you can purge
        },
    },
    bigDebuffs = {              -- one big icon over the player/target portrait: crowd control
        testMode = false,       -- first, else an important buff (shield/immunity); always off after a reload
        showDuration = true,
        durationSize = 18,
        player = { enabled = true },
        target = { enabled = true },
    },
    nameplates = {
        enabled = true,
        testMode = false,       -- always off after a reload
        friendlyNameOnly = false, -- hides the health bar and cast bar on friendly nameplates
        friendlyClassColor = false, -- friendly nameplate names in their class color (players only)
        hideFriendlyPets = false, -- hides friendly players' pet/totem nameplates (e.g. a hunter's pet)
        nameX = 0,              -- name above the health bar, offset from its middle
        nameY = 2,
        onlyMyDebuffs = true,
        purgeGlow = true,
        spacing = 3,            -- between all aura icons
        scale = 1,              -- whole nameplate
        width = 200,            -- nameplate width
        barHeight = 15,         -- health bar height
        nameSize = 14,
        levelSize = 14,
        centerAuras = false,    -- debuff / buff rows grow from the center
        debuffSize = 24,
        debuffPerRow = 6,
        debuffRows = 2,
        debuffX = 0,
        debuffY = 24,           -- above the bar, leaving room for the name
        buffSize = 18,
        buffPerRow = 6,
        buffRows = 1,
        importantScale = 1.5,   -- important buffs and crowd control: debuff icon size times this
        importantMax = 2,
        importantX = 0,
        importantY = 0,
        ccScale = 1.5,
        ccMax = 2,
        ccX = 0,
        ccY = 0,
    },
    minimap = {
        hideButtons = true,
        alwaysShown = {},       -- button name -> true: never hidden
    },
    chatLayout = nil,           -- account-wide chat windows, written by Modules\Chat.lua
}

-- Settings earlier versions stored that nothing reads any more; removed from the saved variables.
local OBSOLETE = {
    actionbars = { "xpCustomSize", "xpWidth", "xpHeight" },  -- the XP bar is scaled now
    nameplates = { "nameAbove", "buffGap", "debuffMax", "buffMax", "importantSize", "ccSize", "typeBorders" }, -- always on now
    appearance = { "biggerHealthBar", "playerNameX", "playerNameY", "targetNameX", "targetNameY", "darkMode" }, -- removed
}

local function RemoveObsolete(db)
    for section, keys in pairs(OBSOLETE) do
        if type(db[section]) == "table" then
            for _, key in ipairs(keys) do
                db[section][key] = nil
            end
        end
    end
end

local function MergeDefaults(target, defaults)
    for key, value in pairs(defaults) do
        if type(value) == "table" then
            if type(target[key]) ~= "table" then
                target[key] = {}
            end
            MergeDefaults(target[key], value)
        elseif target[key] == nil then
            target[key] = value
        end
    end
end

-- Helpers -----------------------------------------------------------------------------------------

function S.IsSecret(value)
    return issecretvalue ~= nil and issecretvalue(value)
end

function S.IsAddOnLoaded(name)
    if C_AddOns and C_AddOns.IsAddOnLoaded then
        return C_AddOns.IsAddOnLoaded(name)
    end
    return IsAddOnLoaded and IsAddOnLoaded(name)
end

-- Resolves "PlayerFrame.PlayerFrameContainer.FrameTexture" without erroring on missing links.
function S.Resolve(path)
    local node = _G
    for key in path:gmatch("[^%.]+") do
        if type(node) ~= "table" then
            return nil
        end
        node = node[key]
    end
    return node
end

function S.Print(...)
    print("|cff9d9d9dSmuve|r|cffffffffUI|r:", ...)
end

-- Runs fn and reports errors without stopping the caller (one broken module must not take the rest down).
function S.SafeCall(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then
        geterrorhandler()(err)
    end
    return ok
end

-- Events ------------------------------------------------------------------------------------------

local eventFrame = CreateFrame("Frame")
local handlers = {}

eventFrame:SetScript("OnEvent", function(_, event, ...)
    local list = handlers[event]
    if not list then
        return
    end
    for i = 1, #list do
        S.SafeCall(list[i], event, ...)
    end
end)

function S:On(event, fn)
    if not handlers[event] then
        handlers[event] = {}
        eventFrame:RegisterEvent(event)
    end
    table.insert(handlers[event], fn)
end

-- Modules -----------------------------------------------------------------------------------------

-- A module has optional Init() (once, at PLAYER_LOGIN) and Refresh() (after settings change).
function S:NewModule(name)
    local module = { name = name }
    self.modules[name] = module
    table.insert(self.moduleOrder, module)
    return module
end

function S:Refresh(name)
    local module = self.modules[name]
    if module and module.Refresh and module.initialized then
        S.SafeCall(module.Refresh, module)
    end
end

-- Dark mode texture tinting -----------------------------------------------------------------------
-- Every texture handed to S:Darken() is remembered with its original color, so dark mode can be
-- turned off again without a reload. Blizzard re-coloring a texture is caught by a hook and the
-- dark tint is put back.

local tracked = {}    -- texture -> brightness offset
local originals = {}  -- texture -> { r, g, b, desaturated }
local conditions = {} -- texture -> function deciding whether it is dark (default: dark mode)
local keepColor = {}  -- texture -> true: dim it, but don't flatten its own baked-in color to gray
local painting = false

-- "off": neither mode. "dark": the original flat gray/black tint. "class": the same tint, but
-- colored with the player's own class color instead of gray - mutually exclusive with "dark",
-- picked via one dropdown (Options.lua), not two independent checkboxes.
function S:DarkModeActive()
    return self.db and self.db.appearance.colorMode ~= "off"
end

function S:ClassColorModeActive()
    return self.db and self.db.appearance.colorMode == "class"
end

function S:Shade(offset)
    local base = 1 - (self.db.appearance.darkness or 90) / 100
    return math.max(0, math.min(1, base + (offset or 0)))
end

-- The player's own class color, nil-safe - WoW Forever has the same 9 classes as retail, so
-- RAID_CLASS_COLORS always has an entry once UnitClass resolves.
function S:GetClassColor()
    local _, class = UnitClass("player")
    local color = class and ((C_ClassColor and C_ClassColor.GetClassColor(class)) or RAID_CLASS_COLORS[class])
    return color or { r = 1, g = 1, b = 1 }
end

-- Class color mode's tint: blends from the SAME dark/gray baseline Dark mode uses (Shade, so
-- switching modes doesn't also change how dark everything looks, just whether it's gray or
-- colored) up toward the player's full, true class color - "intensity" is purely that blend
-- weight, never a brightness multiplier. Multiplying the class color's own RGB by a small
-- darkness-style factor (the first version of this did) crushes it toward black exactly like
-- plain gray does - confirmed live as "class color mode looks the same as dark mode" even on a
-- Mage, since 10% of an already not-fully-saturated blue reads as indistinguishable near-black.
function S:ClassTint(offset)
    local gray = S:Shade(offset)
    local intensity = math.max(0, math.min(1, (self.db.appearance.classColorIntensity or 90) / 100))
    local color = S:GetClassColor()
    return gray + (color.r - gray) * intensity, gray + (color.g - gray) * intensity, gray + (color.b - gray) * intensity
end

local function Paint(texture)
    local offset = tracked[texture]
    if offset == nil then
        return
    end
    painting = true
    local condition = conditions[texture]
    local original = originals[texture]
    if (condition and condition()) or (not condition and S:DarkModeActive()) then
        local classMode = S:ClassColorModeActive()
        local value = S:Shade(offset)
        if keepColor[texture] then
            -- Dim the texture's own (possibly dynamic - e.g. a boss/elite atlas Blizzard tints
            -- gold vs. a plain one) color instead of flattening it to gray: OnRecolored below
            -- keeps `original` refreshed with whatever Blizzard itself last set, so this is always
            -- dimming the real current color, never our own previous dimmed output. Unaffected by
            -- Class color mode - this exception is about preserving a texture's OWN hue, which is
            -- orthogonal to what the non-preserved baseline tint color is.
            texture:SetVertexColor(original.r * value, original.g * value, original.b * value)
        else
            if texture.SetDesaturated then
                texture:SetDesaturated(true)
            end
            if classMode then
                texture:SetVertexColor(S:ClassTint(offset))
            else
                texture:SetVertexColor(value, value, value)
            end
        end
    else
        if texture.SetDesaturated then
            texture:SetDesaturated(original.desaturated)
        end
        texture:SetVertexColor(original.r, original.g, original.b)
    end
    painting = false
end

local function OnRecolored(texture)
    if painting then
        return
    end
    if keepColor[texture] then
        -- A genuine (not ours) SetVertexColor call: Blizzard just set the color this texture is
        -- actually supposed to have right now, so that's the new baseline to dim from/restore to.
        local r, g, b = texture:GetVertexColor()
        if not (S.IsSecret(r) or S.IsSecret(g) or S.IsSecret(b)) then
            originals[texture].r, originals[texture].g, originals[texture].b = r, g, b
        end
    end
    local condition = conditions[texture]
    if (condition and condition()) or (not condition and S:DarkModeActive()) then
        Paint(texture)
    end
end

-- condition: optional function; the texture is dark while it returns true (default: dark mode on).
-- keepTextureColor: dim the texture's own baked-in color instead of flattening it to gray - for
-- art whose color is the point (the elite portrait wreath, say), where SetDesaturated(true) plus
-- a gray vertex tint would otherwise erase it rather than just darkening it.
function S:Darken(texture, offset, condition, keepTextureColor)
    if type(texture) ~= "table" or not texture.SetVertexColor or not texture.IsObjectType then
        return
    end
    if texture:IsForbidden() or not texture:IsObjectType("Texture") then
        return
    end
    if tracked[texture] == nil then
        local r, g, b = texture:GetVertexColor()
        -- Protected colors (e.g. on nameplates) can't be kept; those restore to white.
        if S.IsSecret(r) or S.IsSecret(g) or S.IsSecret(b) then
            r, g, b = 1, 1, 1
        end
        local desaturated = texture.IsDesaturated and texture:IsDesaturated()
        if S.IsSecret(desaturated) then
            desaturated = false
        end
        originals[texture] = {
            r = r or 1, g = g or 1, b = b or 1,
            desaturated = desaturated or false,
        }
        hooksecurefunc(texture, "SetVertexColor", OnRecolored)
        if texture.SetDesaturated then
            hooksecurefunc(texture, "SetDesaturated", OnRecolored)
        end
    end
    tracked[texture] = offset or 0
    conditions[texture] = condition
    keepColor[texture] = keepTextureColor or nil
    Paint(texture)
end

-- /smuve dump only: whether S:Darken has ever actually run on this texture.
function S.DarkModeDebugIsTracked(texture)
    return texture ~= nil and tracked[texture] ~= nil
end

local polled = {} -- texture -> true: tracked like S:Darken's, but never hooked (see below)

-- Same bookkeeping and initial paint as S:Darken, but never installs the SetVertexColor/
-- SetDesaturated hooksecurefunc. For art Blizzard itself recolors as one step inside a larger
-- secure sequence (MainActionBar's own hierarchy during vehicle-state transitions, which also
-- hides the pet bar and populates the override bar) - confirmed live that hooking ANYTHING in that
-- hierarchy taints the whole transition, which is why Modules\DarkMode.lua used to leave it
-- undarkened entirely. Never installing the hook removes that vector completely: nothing of ours
-- runs as part of Blizzard's own call chain any more. The tradeoff is this texture no longer
-- self-corrects the instant Blizzard recolors it - RepaintPolled below, on its own ticker (not
-- nested in anything Blizzard calls), is what wins that back a few times a second instead, the
-- same "poll instead of hook" pattern already used for nameplates/action bars/party frames
-- elsewhere in this addon.
function S:DarkenPolled(texture, offset, condition, keepTextureColor)
    if type(texture) ~= "table" or not texture.SetVertexColor or not texture.IsObjectType then
        return
    end
    if texture:IsForbidden() or not texture:IsObjectType("Texture") then
        return
    end
    if tracked[texture] == nil then
        local r, g, b = texture:GetVertexColor()
        if S.IsSecret(r) or S.IsSecret(g) or S.IsSecret(b) then
            r, g, b = 1, 1, 1
        end
        local desaturated = texture.IsDesaturated and texture:IsDesaturated()
        if S.IsSecret(desaturated) then
            desaturated = false
        end
        originals[texture] = {
            r = r or 1, g = g or 1, b = b or 1,
            desaturated = desaturated or false,
        }
    end
    tracked[texture] = offset or 0
    conditions[texture] = condition
    keepColor[texture] = keepTextureColor or nil
    polled[texture] = true
    Paint(texture)
end

function S:RepaintPolled()
    for texture in pairs(polled) do
        Paint(texture)
    end
end

-- Darkens every texture region of a frame (not its children).
function S:DarkenRegions(frame, offset, filter)
    if not frame or not frame.GetRegions or frame:IsForbidden() then
        return
    end
    for _, region in ipairs({ frame:GetRegions() }) do
        if region:IsObjectType("Texture") and (not filter or filter(region)) then
            self:Darken(region, offset)
        end
    end
end

-- Decorations that only look wrong when darkened (light streaks) are hidden in dark mode instead.
local faded = {} -- texture -> original alpha

function S:HideWhenDark(texture)
    if type(texture) ~= "table" or not texture.SetAlpha or not texture.IsObjectType or texture:IsForbidden() then
        return
    end
    if faded[texture] == nil then
        faded[texture] = texture:GetAlpha()
    end
    texture:SetAlpha(self:DarkModeActive() and 0 or faded[texture])
end

function S:RepaintAll()
    for texture in pairs(tracked) do
        Paint(texture)
    end
    for texture, alpha in pairs(faded) do
        texture:SetAlpha(self:DarkModeActive() and 0 or alpha)
    end
end

-- Startup -----------------------------------------------------------------------------------------

S:On("ADDON_LOADED", function(_, loaded)
    if loaded ~= addonName then
        return
    end
    SmuveUIDB = SmuveUIDB or {}
    -- The party frames buff display (Modules\PartyFrames.lua) was removed entirely, so its whole
    -- saved section goes too, not just individual keys - RemoveObsolete below only drops keys
    -- within a section that's still in S.defaults, which this no longer is.
    SmuveUIDB.partyFrames = nil
    -- The old "darkMode" boolean becomes the new "colorMode" string (adds a mutually exclusive
    -- class-color mode alongside it) - a one-time coercion read before RemoveObsolete below drops
    -- the old field, so anyone who had dark mode off keeps it off rather than silently gaining the
    -- new default ("dark").
    if SmuveUIDB.appearance and SmuveUIDB.appearance.colorMode == nil and SmuveUIDB.appearance.darkMode ~= nil then
        SmuveUIDB.appearance.colorMode = SmuveUIDB.appearance.darkMode and "dark" or "off"
    end
    RemoveObsolete(SmuveUIDB)
    -- The old default ("DEFAULT", the client's own fonts) becomes the new one (Rajdhani Bold)
    -- for anyone who never explicitly chose a font - a one-time coercion, not a standing rule,
    -- so deliberately picking "DEFAULT" again afterward sticks.
    if SmuveUIDB.appearance and not SmuveUIDB.appearance.fontDefaultMigrated then
        SmuveUIDB.appearance.fontDefaultMigrated = true
        if SmuveUIDB.appearance.font == "DEFAULT" then
            SmuveUIDB.appearance.font = S.defaults.appearance.font
        end
    end
    MergeDefaults(SmuveUIDB, S.defaults)
    S.db = SmuveUIDB
end)

-- Modules switched off with "/smuve disable <Module>" (for tracking down problems) are not started.
function S:IsModuleDisabled(name)
    return self.db.disabledModules ~= nil and self.db.disabledModules[name] == true
end

S:On("PLAYER_LOGIN", function()
    for _, module in ipairs(S.moduleOrder) do
        -- A disabled module stays uninitialized, so Refresh calls skip it too.
        if not S:IsModuleDisabled(module.name) then
            if module.Init then
                S.SafeCall(module.Init, module)
            end
            module.initialized = true
            if module.Refresh then
                S.SafeCall(module.Refresh, module)
            end
        end
    end
end)

-- Slash command and addon compartment --------------------------------------------------------------

SLASH_SMUVEUI1 = "/smuve"
SLASH_SMUVEUI2 = "/sui"
SLASH_SMUVEUI3 = "/smuveui"
-- /smuve                    options window
-- /smuve dump               diagnostics into the saved variables (see Debug.lua)
-- /smuve cleardump          removes them again
-- /smuve modules            list modules and whether they run
-- /smuve disable <Module>   / enable <Module>: switch a module off/on (after a /reload)
SlashCmdList.SMUVEUI = function(input)
    local command, argument = (input or ""):match("^%s*(%S*)%s*(.-)%s*$")
    command = command:lower()
    if command == "dump" then
        S:Dump()
    elseif command == "cleardump" then
        S.db.debug = nil
        S.Print("Diagnostics removed.")
    elseif command == "modules" then
        for _, module in ipairs(S.moduleOrder) do
            S.Print(module.name .. ": " .. (S:IsModuleDisabled(module.name) and "|cffff4040disabled|r" or "|cff40ff40on|r"))
        end
    elseif command == "disable" or command == "enable" then
        local found
        for _, module in ipairs(S.moduleOrder) do
            if module.name:lower() == argument:lower() then
                found = module.name
            end
        end
        if not found then
            S.Print("Unknown module '" .. argument .. "'. /smuve modules lists them.")
            return
        end
        S.db.disabledModules = S.db.disabledModules or {}
        S.db.disabledModules[found] = command == "disable" or nil
        S.Print(found .. " " .. command .. "d. Type /rl to apply.")
    else
        S:ToggleOptions()
    end
end

-- /rl as a short form of /reload.
SLASH_SMUVEUIRELOAD1 = "/rl"
SlashCmdList.SMUVEUIRELOAD = ReloadUI

function SmuveUI_OnAddonCompartmentClick()
    S:ToggleOptions()
end
