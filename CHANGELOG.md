# Changelog

All notable changes to this addon are documented here.

## 0.9.0 - 2026-11-13
- New: a "what's new" popup shows once after SmuveUI updates, listing what changed since you last saw it. Can be turned off from its own checkbox, or from a new control at the bottom of the Options window (not tucked under any category).
- The Options window's title now shows the installed version number next to "SmuveUI".

## 0.8.0 - 2026-11-12
- New: Auto-open clams. Opens any clam sitting in your bags on its own, the moment it shows up, without touching anything else in your bags. Off by default (Options -> QoL -> Loot & Vendors).
- New: your debuffs bar can now be moved independently of your buffs bar, with its own "Reset position" button. Buffs and debuffs no longer have to stay anchored to each other.
- New: the custom player buffs/debuffs display can be turned off entirely from Options -> Appearance -> Player, reverting to the default client display (needs a reload).
- Fixed: a weapon imbue icon wasn't resizing with the "Buffs scale" slider, and could block dragging the buffs bar while repositioning it.
- Weapon imbue borders are now color-coded: green for a Rogue's poison, purple for every other imbue.

## 0.7.2 - 2026-11-12
- Fixed the player and target frame's rage/energy/other power bar sometimes rendering in Mana's blue color instead of the correct color, when using the default bar texture.
- Fixed sharing chat window layout between characters sometimes silently failing to apply on the receiving character.
- Dark Mode now also covers the escape menu's red action buttons (Continue, Options, Logout, Exit Game, ...), which previously stayed bright and undarkened.

## 0.7.1 - 2026-11-11
- Dark Mode now also covers windows that previously stayed in their default, undarkened look: the Legacy Tree, the Friends/Guild/Who window, NPC dialogue and quest windows, the combined bags window, the character sheet's equipment slots, and the party/raid control window.
- Fixed the enemy nameplate cast bar resetting to its default height every time a new cast started, and enlarged its spell icon.
- Fixed class coloring not applying to the target-of-target frame, a friendly nameplate's name, or a raid frame member in one specific situation: when the chain of targets passed through an NPC rather than another player.
- Fixed unit frame health bars (most noticeable on the target-of-target frame) briefly flashing back to their default color before the correct class/reaction color reasserted itself.

## 0.7.0 - 2026-11-10
- New: Raid/party frame buffs, debuffs, and defensive cooldowns, shown directly on each party/raid member's frame.
- New: a global Bar Texture picker (Options -> Appearance -> Bar Texture) for health and resource bars on the player, target, party, raid, and nameplate frames, plus the personal resource display. Comes with four bundled textures, shared with other addons that support LibSharedMedia.
- New: options to grow the cast bar's height and increase its spell-name/timer text size on enemy nameplates (Options -> Nameplates -> Cast Bar).
- New: the enemy nameplate cast bar's spell icon now has the same black border as every other icon, including a "can't be interrupted" shield badge.
- New: the personal resource display's health bar (the bar above your own character) is now class colored, matching the player and target frames.
- Fixed the target-of-target health bar never getting class colored.
- Fixed the target/focus frame's mana value text occasionally landing in the wrong position during combat.
- Fixed custom bar textures turning solid black on bars that use the client's own atlas art (e.g. the personal resource display), not showing the correct color on resource bars, and the target frame falling out of sync with the chosen texture after a reload.
- Consolidated the QoL options page into sub-categories to fit the settings sidebar.

## 0.6.0 - 2026-11-09
- New: Easy Fishing. With a fishing rod in your main hand, assign one key (Options -> QoL -> Fishing) to cast your line and reel in the catch once it's ready - no need to click the bobber, and the game's own bobber-ready icon shows automatically. The bite splash also plays louder while your line is out, with an adjustable boost slider (up to 5x). Off by default.

## 0.5.0 - 2026-11-06
- New: Battle.net friends in your friends list are now tinted blue for Alliance or red for Horde, based on the faction of the character they're currently playing. Toggle in Options -> QoL -> Social.
- New: SmuveUI's bundled Rajdhani font is now shared with other addons that support LibSharedMedia (WeakAuras, ForeverAuras, and similar), so it shows up as a pickable font there too.
- Fixed friendly players' names on nameplates sometimes staying plain white instead of their class color, when "Class colored" friendly nameplate names is enabled.
- Fixed the "Hide pets/totems" friendly nameplate option (added in 0.4.2) not actually hiding anything. It now also hides friendly guardians and minions (e.g. a mage's Mirror Image, a druid's treant), not just pets and totems.

## 0.4.2 - 2026-11-05
- New: an optional nameplate setting to hide friendly players' pets and totems (Options -> Nameplates -> Friendly Nameplates -> "Hide pets/totems").
- Fixed your own debuffs bar not lining up with the right edge of your buffs bar.
- Removed the custom buff display on the default party frames. Recent changes to how this client resolves party members' aura data made it unreliable (missing icon borders, duplicated icons), so it's been removed rather than left half-working - party frames now show just health and name, same as before this feature existed.

## 0.4.1 - 2026-11-05
- Fixed the default quest tracker briefly flashing back into view every time a tracked objective updated while "hide the default quest tracker" was enabled, instead of staying hidden.

## 0.4.0 - 2026-11-05
- New: a reskin for RestedXP (RXPGuides) that matches SmuveUI's own dark look and font. Enable it from inside RestedXP itself: Settings -> Appearance -> Theme -> "SmuveUI".
- New: Dark Mode can now tint the UI with your class color instead of gray/black. Options -> Appearance -> Color mode, with its own separate intensity slider.

## 0.3.2 - 2026-11-05
- "Name only mode" on nameplates now also applies to friendly NPCs (not just friendly players): their health bar, cast bar, buffs/debuffs and level badge hide correctly, and their name is colored the same way the health bar already was instead of staying plain white.
- Fixed a rare case where a nameplate's health bar could get stuck permanently invisible, most noticeably right as combat started.
- Fixed enemy nameplates occasionally showing both the custom and the game's own default buff/debuff icons at the same time.
- Fixed your own buffs staying visible on the party frame after leaving a party, or after opening and closing Edit Mode, even though the party frame itself was gone.
- Restored Dark Mode styling on the main action bar's own frame art and its gryphon end caps, and fixed it not applying to the target/focus frame's portrait ring on regular (non-elite) targets.
- Fixed a rare issue where the target and focus frame's buffs/debuffs could trigger "secret value" errors.
- Fixed the focus frame's in-combat glow rendering on the target frame instead of the focus frame when both a target and a focus were set.

## 0.3.1 - 2026-11-05
- Fixed a group of rare "secret value"/"action blocked" errors that could interrupt Edit Mode, action bar layout, or party frames, caused by several of the addon's own update hooks running too deep inside the game's own protected UI code.
- Removed the Pet Bar's custom show/hide/mouseover option, since Blizzard's own native pet-bar behavior was the direct cause of one recurring version of the error above; the game's own default behavior (hidden with no pet) now applies to it instead.

## 0.3.0 - 2026-10-25
- New: an optional QoL setting to always show the glowing loot sparkle on quest items, instead of
  only with the right graphics option or the interact key held (Options -> QoL -> Quests).

## 0.2.5 - 2026-10-23
- New: an optional sound when you receive a whisper (Options -> QoL -> Chat), off by default,
  with a choice of several built-in sounds plus a bundled custom one.
- Fixed the options dropdown control running past its column's edge on pages with two columns.

## 0.2.4 - 2026-10-23
- Fixed nameplates: the level badge's own target-selection border now darkens along with the
  health bar's, instead of staying at full brightness.

## 0.2.3 - 2026-10-23
- New: an optional QoL setting to skip typing "DELETE" when destroying a rare quality item or
  better - a plain click on Confirm is enough.
- Dark mode now also darkens the border on confirmation popups (item deletion, ready checks,
  resurrect prompts, and similar), which it was missing before.
- Fixed nameplates: the level badge next to the health bar, including the skull icon for a target
  far above your level, no longer turns gray in dark mode.
- Fixed the equipped item level note briefly showing on empty bag slots for a second or two after
  a reload or login.

## 0.2.2 - 2026-10-23
- New: an optional +COMBAT/-COMBAT flash in the center of the screen when you enter or leave
  combat (Options -> QoL -> Combat).
- Fixed the elite/boss portrait wreath on the target and focus frame turning gray in dark mode.
- The loot roll window can now be repositioned even while no roll is active.
- Need/Greed/Pass buttons now visibly gray out once you've voted on a roll.
- "Keep the roll window open until everyone's chosen" is now its own toggle, separate from the
  roll tracker.

## 0.2.1 - 2026-10-22
- Weapon imbues (shaman imbues, rogue poisons/whetstones) now show on your buffs bar, the same
  way the default UI shows them.
- Your debuffs now keep a minimum distance below your buffs, so a handful of buffs no longer
  leaves debuffs crowded right underneath them.

## 0.2.0 - 2026-10-22
- Vendors: optional auto repair and auto sell junk, each with a chat message reporting the cost
  or revenue.
- Friendly nameplates: new "Name only" (hides the health bar, cast bar and auras) and
  "Class colored" options for player names.
- Nameplates: the health bar of a target tapped by someone else, dead, or offline is correctly
  gray again, instead of being overridden by class/reaction color.
- Your own buffs/debuffs rebuilt from scratch: correctly formatted remaining time, borders
  colored by dispel type, and tooltips. Both bars can now be moved freely (their own unlock
  option) and scaled and resized (icons per row) independently; the debuff bar always stays
  anchored below the buff bar, even when it wraps to another row.
- The experience/reputation bar is resizable again and, like the action
  bars, can be shown on mouseover.
- Dark mode: spell icons on cast bars no longer show their baked-in light border, and the
  target/focus cast bar's background and non-interruptible shield are darkened too.
- Fixed a bug where a buff from the curated list of important spells (e.g. Blessing of
  Protection) could also match its own natural category and render twice on party frames and
  enemy nameplates.
- Fixed a bug where repositioning the target-of-target frame during a mid-combat target change
  could throw an error.
- Raised the default debuff icon size above the health bar on nameplates from 22 to 24.
