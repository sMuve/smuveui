local _, S = ...
local M = S:NewModule("WhisperSound")

-- Plays a sound whenever you get a whisper (tell or Battle.net whisper), off by default. The
-- choice of sound is a curated handful of the client's own built-in ones (SOUNDKIT has hundreds of
-- entries, most obscure/internal) rather than every single one, the same way Options.lua picks
-- which fonts to list rather than every font on disk, plus this addon's own bundled one(s) under
-- Media\Sounds - those use `file` (played with PlaySoundFile) instead of `kit` (PlaySound).
M.SOUNDS = {
    { value = "TELL_MESSAGE", text = "Whisper (default)", kit = "TELL_MESSAGE" },
    { value = "READY_CHECK", text = "Ready Check", kit = "READY_CHECK" },
    { value = "RAID_WARNING", text = "Raid Warning", kit = "RAID_WARNING" },
    { value = "RAID_BOSS_EMOTE_WARNING", text = "Raid Boss Warning", kit = "RAID_BOSS_EMOTE_WARNING" },
    { value = "AUCTION_WINDOW_OPEN", text = "Auction Window", kit = "AUCTION_WINDOW_OPEN" },
    { value = "PVP_THROUGH_QUEUE", text = "PvP Queue Pop", kit = "PVP_THROUGH_QUEUE" },
    { value = "MAP_PING", text = "Map Ping", kit = "MAP_PING" },
    { value = "ALARM_CLOCK_WARNING_2", text = "Alarm Clock", kit = "ALARM_CLOCK_WARNING_2" },
    { value = "IG_PLAYER_INVITE", text = "Player Invite", kit = "IG_PLAYER_INVITE" },
    { value = "ACHIEVEMENT_MENU_OPEN", text = "Achievement", kit = "ACHIEVEMENT_MENU_OPEN" },
    { value = "SMUVE_SWEEP", text = "Smuve Sweep", file = "Interface\\AddOns\\SmuveUI\\Media\\Sounds\\arcade_sweep.ogg" },
}

local byValue = {}
for _, sound in ipairs(M.SOUNDS) do
    byValue[sound.value] = sound
end

local function OnWhisper()
    if not S.db.qol.whisperSound then
        return
    end
    local sound = byValue[S.db.qol.whisperSoundKit or "TELL_MESSAGE"] or byValue.TELL_MESSAGE
    if sound.file then
        PlaySoundFile(sound.file)
    elseif sound.kit and SOUNDKIT then
        local id = SOUNDKIT[sound.kit]
        if id then
            PlaySound(id)
        end
    end
end

function M:Init()
    S:On("CHAT_MSG_WHISPER", OnWhisper)
    S:On("CHAT_MSG_BN_WHISPER", OnWhisper)
end
