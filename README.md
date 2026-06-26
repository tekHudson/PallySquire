# PallySquire

A clean, **Season of Discovery–native** paladin blessing manager — a from-scratch
reimagining of [PallyPower](https://www.curseforge.com/wow/addons/pally-power).

Pure Lua (no XML), no Ace3, single code path for the Classic Era / SoD client.
Stays **wire-compatible** with PallyPower (`PLPWR` addon-message prefix) so it
works in raids where others still run the original.

## Why it's different from PallyPower

SoD paladins have **no Greater Blessings and no Symbol of Kings** — every
blessing is single-target. The "Enhanced Blessings" book (spell `435984`) just
passively doubles duration and halves mana. PallySquire is built around that:

- **Single-target only.** No greater-blessing layer, no reagent tracking.
- **Per-class assignment + cross-paladin sync** (the feature that makes
  PallyPower worth running) is kept intact.
- Remaining-time is read from the **live aura** on each unit, so Enhanced
  Blessings is handled automatically with no special-casing.

## Design

- **No XML.** Every frame/button is built with `CreateFrame`. Secure
  `SecureActionButtonTemplate` buttons perform the casts; class/auto buttons
  re-arm out of combat, per-player pop-outs (fixed unit) stay castable in combat.
- **No Ace3 / minimal libs.** Saved vars use a tiny defaults-merge; options use
  the Blizzard **Settings API**; comms use a native throttle queue; the minimap
  button is ~30 lines of Lua. Modern APIs: `C_Spell`, `C_UnitAuras`/`AuraUtil`,
  `C_Timer`, `C_AddOns`, `C_ChatInfo`.
- **One file per responsibility** under `Core/` and `UI/`.

## Usage

- `/ps` — open options
- `/ps config` — open the assignment window (left-click a class to cycle its
  blessing, right-click to go back)
- `/ps toggle` — show/hide the bar
- `/ps reset` — recenter the bar
- Right-click the bar or the minimap button — assignment window

## Layout

```
PallySquire.lua      bootstrap: namespace, event dispatch, slash, API shims
Locale/enUS.lua      strings
Core/Data.lua        SoD spell/class tables, runtime name resolution
Core/DB.lua          saved vars + defaults merge + assignment accessors
Core/Comm.lua        PLPWR protocol (PallyPower-compatible) + send throttle
Core/Roster.lua      group/raid scan + per-unit buff state
Core/Buffs.lua       cast eligibility + auto-buff target selection
UI/Frame.lua         main container + minimap + orchestration
UI/Buttons.lua       secure buttons, layout, visual refresh
UI/Config.lua        assignment window
UI/Options.lua       Settings-API options panel
```

## Status

v0.1 — core complete and statically validated. Not yet exercised in-game; see
the verification checklist in the project plan (grid, assignment + sync,
in/out-of-combat casting, auto-buff, auras/seals/RF, options, minimap).

Deferred: non-English locales, skinning, raid/BG auto-assign templates.
