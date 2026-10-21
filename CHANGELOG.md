# Changelog

All notable changes to this addon are documented here.

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
- The experience/reputation bar above the action bars is resizable again and, like the action
  bars, can be shown on mouseover.
- Dark mode: spell icons on cast bars no longer show their baked-in light border, and the
  target/focus cast bar's background and non-interruptible shield are darkened too.
- Fixed a bug where a buff from the curated list of important spells (e.g. Blessing of
  Protection) could also match its own natural category and render twice on party frames and
  enemy nameplates.
- Fixed a bug where repositioning the target-of-target frame during a mid-combat target change
  could throw an error.
- Raised the default debuff icon size above the health bar on nameplates from 22 to 24.
