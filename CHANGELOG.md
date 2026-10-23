# Changelog

All notable changes to this addon are documented here.

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
