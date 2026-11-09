local _, S = ...
local M = S:NewModule("EasyFishing")

-- One assigned key casts Fishing when idle and reels in the catch when the bobber can be
-- interacted with, without ever clicking the bobber - both only while a fishing pole is in the
-- main hand. The reel trick: WoW's own soft-target system can be made to pick up the bobber
-- (GameObject 35591) by widening SoftTargetInteract*, and the stock INTERACTTARGET binding action
-- is what actually reels it in - so the key is rebound to that action for the whole channel (not
-- just once the bobber is confirmed caught: that soft-target event flickers, and a gap where the
-- key falls back to its normal binding can interrupt the channel outright). With nothing to
-- interact with, INTERACTTARGET itself safely does nothing, so this doubles as "ignore an early
-- press." There's no API to boost one sound cue in isolation, so the "louder splash" is a Sound
-- Effects channel boost, with Master (and, if Master had to move, everything under it)
-- compensated so nothing else sounds different.
local BUTTON_NAME = "SmuveUIEasyFishingCastButton"
local BOBBER_ID = 35591
-- The last two turn on the client's own built-in soft-target icon above the bobber once it's in
-- reach - the same reticle the game already shows over herbs/quest items, not a custom texture.
local REEL_CVARS = {
    SoftTargetInteract = "3", SoftTargetInteractRange = "30", SoftTargetInteractArc = "2", SoftTargetInteractRangeIsHard = "0",
    SoftTargetIconGameObject = "1", SoftTargetIconInteract = "1",
}
local SFX, MASTER = "Sound_SFXVolume", "Sound_MasterVolume"
local OTHER_VOLUMES = { "Sound_MusicVolume", "Sound_AmbienceVolume", "Sound_DialogVolume" }
local FISHING_SPELLS = { 18248, 7732, 7731, 7620 }
local WEAPON_CLASS = Enum.ItemClass and Enum.ItemClass.Weapon
local FISHING_POLE = Enum.ItemWeaponSubclass and Enum.ItemWeaponSubclass.Fishingpole

local castButton
local fishingID, fishingName
local channeling = false   -- the player's own Fishing channel is running
local softBobber = false   -- the soft-interact target is the player's own bobber
local heldCVars             -- cvar -> { old, set }, only while this session holds it

local function Key()
    return S.db.qol.easyFishingKey
end

local function Active()
    return S.db.qol.easyFishing and Key() ~= nil
end

local function RodEquipped()
    if not (WEAPON_CLASS and FISHING_POLE and C_Item and C_Item.GetItemInfoInstant) then
        return false
    end
    local id = GetInventoryItemID("player", INVSLOT_MAINHAND)
    if not id then
        return false
    end
    local _, _, _, _, _, classID, subclassID = C_Item.GetItemInfoInstant(id)
    return classID == WEAPON_CLASS and subclassID == FISHING_POLE
end

local function ResolveFishing()
    fishingID, fishingName = nil, nil
    for _, id in ipairs(FISHING_SPELLS) do
        if IsPlayerSpell(id) then
            fishingID, fishingName = id, C_Spell.GetSpellName(id)
            return
        end
    end
end

-- Held CVars -----------------------------------------------------------------------------------

local function HoldCVar(cvar, value)
    heldCVars = heldCVars or {}
    if heldCVars[cvar] then
        return
    end
    local old = GetCVar(cvar)
    if old == nil or old == value then
        return
    end
    SetCVar(cvar, value)
    heldCVars[cvar] = { old = old, set = value }
end

-- Only puts back a CVar if it still holds what this session set - a value the player changed by
-- hand mid-session is theirs, not ours to overwrite.
local function ReleaseCVars()
    if not heldCVars then
        return
    end
    for cvar, saved in pairs(heldCVars) do
        if GetCVar(cvar) == saved.set then
            SetCVar(cvar, saved.old)
        end
    end
    heldCVars = nil
end

local function Round(v)
    return math.floor(v * 10000 + 0.5) / 10000
end

-- Sound Effects take the boost first; past 100% Master makes up the rest (also capped at 100%),
-- and everything under Master comes down by that same factor, so it plays exactly as loud as
-- before even though the raw CVar moved.
local function BeginSoundBoost()
    local sfx = tonumber(GetCVar(SFX))
    if not sfx or sfx <= 0 then
        return -- Sound Effects muted: no boost
    end
    local want = sfx * (tonumber(S.db.qol.easyFishingBoost) or 5)
    local sfxNew = math.min(1, Round(want))
    if sfxNew ~= sfx then
        HoldCVar(SFX, tostring(sfxNew))
    end
    if want <= sfxNew then
        return
    end
    local master = tonumber(GetCVar(MASTER))
    if not master or master <= 0 or master >= 1 then
        return -- no headroom to borrow from Master
    end
    local masterNew = math.min(1, Round(master * want / sfxNew))
    if masterNew == master then
        return
    end
    HoldCVar(MASTER, tostring(masterNew))
    local factor = masterNew / master
    for _, cvar in ipairs(OTHER_VOLUMES) do
        local v = tonumber(GetCVar(cvar))
        if v and v > 0 then
            HoldCVar(cvar, tostring(Round(v / factor)))
        end
    end
end

local function BeginSession()
    BeginSoundBoost()
    for cvar, value in pairs(REEL_CVARS) do
        HoldCVar(cvar, value)
    end
end

local function EndSession()
    ReleaseCVars()
end

-- The key and its cast button --------------------------------------------------------------------

local function EnsureCastButton()
    if castButton then
        return
    end
    castButton = CreateFrame("Button", BUTTON_NAME, nil, "SecureActionButtonTemplate")
    castButton:RegisterForClicks("AnyDown")
    castButton:SetAttribute("useOnKeyDown", true)
    castButton:SetAttribute("type", "spell")
end

local pendingApply = false
local RefreshDebugState -- forward declaration; defined below, used at the end of Apply()

-- Out of combat only: override bindings and secure attributes can't change otherwise.
local function Apply()
    if InCombatLockdown() then
        pendingApply = true
        RefreshDebugState()
        return
    end
    pendingApply = false
    if castButton then
        ClearOverrideBindings(castButton)
    end
    if not (Active() and RodEquipped()) then
        EndSession()
        RefreshDebugState()
        return
    end
    EnsureCastButton()
    castButton:SetAttribute("spell", fishingID)
    local key = Key()
    if channeling then
        -- Bound the whole channel, not just once the soft-target event says the bobber is caught:
        -- that event flickers (acquired/lost/acquired as the bobber bobs), and leaving the key
        -- unbound in between let a press fall through to the player's own regular binding for it,
        -- which could interrupt the channel outright. With nothing to interact with, INTERACTTARGET
        -- itself safely does nothing, which is exactly "ignored" for an early press.
        SetOverrideBinding(castButton, true, key, "INTERACTTARGET")
    else
        SetOverrideBindingClick(castButton, true, key, BUTTON_NAME)
    end
    RefreshDebugState()
end

-- Events ------------------------------------------------------------------------------------------

local function OnChannelStart(_, unit, _, spellID)
    if unit ~= "player" or not Active() then
        return
    end
    local ok, name = pcall(C_Spell.GetSpellName, spellID)
    if not ok or S.IsSecret(name) or name ~= fishingName then
        return
    end
    channeling, softBobber = true, false
    BeginSession()
    Apply()
end

local function OnChannelStop(_, unit)
    if unit ~= "player" then
        return
    end
    channeling, softBobber = false, false
    EndSession()
    Apply()
end

-- softBobber is tracked for the debug dump only now - the key stays bound to INTERACTTARGET for
-- the whole channel (see Apply()), so this no longer needs to drive a rebind.
local function OnSoftInteractChanged(_, _, newTarget)
    if not (Active() and channeling) then
        return
    end
    local isBobber = false
    if newTarget and not S.IsSecret(newTarget) then
        local kind, _, _, _, _, id = strsplit("-", newTarget)
        isBobber = kind == "GameObject" and tonumber(id) == BOBBER_ID
    end
    softBobber = isBobber
    RefreshDebugState()
end

local function OnEquipmentChanged(_, slot)
    if slot ~= INVSLOT_MAINHAND then
        return
    end
    if not RodEquipped() then
        EndSession()
    end
    Apply()
end

local function OnRegenEnabled()
    if pendingApply then
        Apply()
    end
end

function M:Init()
    S:On("UNIT_SPELLCAST_CHANNEL_START", OnChannelStart)
    S:On("UNIT_SPELLCAST_CHANNEL_STOP", OnChannelStop)
    S:On("PLAYER_SOFT_INTERACT_CHANGED", OnSoftInteractChanged)
    S:On("PLAYER_EQUIPMENT_CHANGED", OnEquipmentChanged)
    S:On("PLAYER_REGEN_ENABLED", OnRegenEnabled)
    S:On("SPELLS_CHANGED", ResolveFishing)
    ResolveFishing()
end

function M:Refresh()
    Apply()
end

-- For Debug.lua's /smuve dump: this module's runtime state isn't visible anywhere else.
M.debugState = {}
function RefreshDebugState()
    local held = {}
    if heldCVars then
        for cvar in pairs(heldCVars) do
            table.insert(held, cvar)
        end
    end
    M.debugState.active = Active()
    M.debugState.rodEquipped = RodEquipped()
    M.debugState.key = Key()
    M.debugState.fishingID = fishingID
    M.debugState.fishingName = fishingName
    M.debugState.channeling = channeling
    M.debugState.softBobber = softBobber
    M.debugState.castButton = castButton ~= nil
    M.debugState.pendingApply = pendingApply
    M.debugState.heldCVars = next(held) and table.concat(held, ",") or "none"
end
M.RefreshDebugState = RefreshDebugState
