# RepSync - Development Guide

## Project Overview

**RepSync** is a WoW Classic Anniversary addon that automatically switches the player's watched reputation bar when entering dungeons and raids associated with specific factions.

### Key Files
- `RepSync.lua` - Main addon code (all logic in single file)
- `RepSync.toc` - Addon manifest
- `README.md` - Documentation (also used for CurseForge description)
- Deployed to: `/mnt/data/games/World of Warcraft/_anniversary_/Interface/AddOns/RepSync/`

### Features
- Auto-detects instance entry via `GetInstanceInfo()`
- Maps instances to their associated reputation faction
- Handles faction-specific reps (Honor Hold vs Thrallmar) via `UnitFactionGroup()`
- Saves and restores previously watched reputation on instance exit
- Expand/collapse-safe faction index lookup (expands headers, finds faction, re-collapses)
- Debounce logic to avoid redundant switches
- GUI options panel (`/rs`) with two toggle checkboxes
- SavedVariables: `RepSyncDB` (per-character)

### Architecture
- Single Lua file with no XML dependencies
- Event-driven: PLAYER_ENTERING_WORLD, ZONE_CHANGED_NEW_AREA
- `FindAndWatchFactionByID()` handles the expand-all → find → set → re-collapse dance
- `INSTANCE_FACTION_MAP` flat table keyed by instanceID (8th return of `GetInstanceInfo()`)
- `C_Reputation.GetWatchedFactionData()` to check current watched faction

### Slash Commands
- `/rs` - Toggle GUI options window
- `/rs clear` - Clear saved previous faction
- `/rs list` - List all mapped instances in chat
- `/rs help` - Show commands

### Development Workflow

See the `/wow-addon` skill for the standard development workflow (test, version, commit, deploy).

## WoW API Reference

For WoW Classic Anniversary API documentation, patterns, and development workflow, use the `/wow-addon` skill:
```
/wow-addon
```
This loads the shared TBC API reference, common patterns, and gotchas.
