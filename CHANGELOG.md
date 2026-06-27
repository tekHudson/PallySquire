# Changelog

All notable changes to PallySquire are documented here.
This project follows [Keep a Changelog](https://keepachangelog.com) and
[Semantic Versioning](https://semver.org).

## [Unreleased]

## [0.1.2] - 2026-06-26
### Added
- Righteous Fury button for tanking (opt-in via options). Left-click casts it;
  the border shows on/off (green = active, red = missing).
- Missing buffs now tint the whole icon red, not just the border — applies to
  aura, seal, Righteous Fury, and class buttons.

## [0.1.1] - 2026-06-26
### Fixed
- Paladin-only: the addon now disables itself entirely on non-paladin
  characters (no bar, minimap, comms, events, or options) instead of loading.

## [0.1.0] - 2026-06-25
### Added
- Initial release: a clean, Season of Discovery–native paladin blessing
  manager — a from-scratch, pure-Lua (no XML), no-Ace3 reimagining of
  PallyPower.
- Single-target blessing model (SoD has no Greater Blessings / Symbol of
  Kings); remaining time is read from the live aura so Enhanced Blessings is
  handled automatically.
- Cross-paladin assignment sync, wire-compatible with PallyPower via the
  `PLPWR` addon-message prefix (works in mixed raids).
- Compact action bar: square class/control buttons with colored need-state
  borders, assigned-blessing glyphs, and outlined remaining-time text.
  Left-click a class button to cast the next-needed member; right-click to
  toggle per-player pop-out buttons (castable in combat).
- Assignments window: columnar layout (one column per class, 5 + 4 across two
  rows) with aura/seal pickers and per-class blessing icon flyouts. Toggle a
  per-character override for any member; overrides sync and the casting logic
  honors them.
- Native minimap button, Settings-API options panel (categorized), and a
  Demo mode that previews a full raid solo.
