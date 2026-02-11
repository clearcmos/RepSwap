# RepSwitcher

Automatically switches your watched reputation bar when entering dungeons and raids in WoW Classic Anniversary Edition.

## The Problem

When running TBC and Vanilla dungeons/raids, you want to track the associated faction's reputation. But it's easy to forget to switch, especially when bouncing between different instances.

## The Solution

RepSwitcher detects when you enter a mapped instance and automatically switches your watched reputation to the correct faction. When you leave, it restores your previous reputation.

## Supported Instances

### TBC Dungeons
| Instance | Faction |
|---|---|
| Hellfire Ramparts, Blood Furnace, Shattered Halls | Honor Hold / Thrallmar |
| Slave Pens, Underbog, Steamvault | Cenarion Expedition |
| Mana-Tombs | The Consortium |
| Auchenai Crypts, Sethekk Halls, Shadow Labyrinth | Lower City |
| Mechanar, Botanica, Arcatraz | The Sha'tar |
| Old Hillsbrad Foothills, Black Morass | Keepers of Time |
| Magister's Terrace | Shattered Sun Offensive |

### TBC Raids
| Instance | Faction |
|---|---|
| Karazhan | The Violet Eye |
| Hyjal Summit | Scale of the Sands |
| Black Temple | Ashtongue Deathsworn |

### Vanilla Dungeons
| Instance | Faction |
|---|---|
| Stratholme, Scholomance | Argent Dawn |
| Blackrock Depths | Thorium Brotherhood |
| Dire Maul | Shen'dralar |

### Vanilla Raids
| Instance | Faction |
|---|---|
| Molten Core | Hydraxian Waterlords |
| Ruins of Ahn'Qiraj | Cenarion Circle |
| Temple of Ahn'Qiraj | Brood of Nozdormu |
| Zul'Gurub | Zandalar Tribe |
| Naxxramas | Argent Dawn |

## Commands

- `/rs` - Show current status
- `/rs on` / `/rs off` - Enable or disable
- `/rs restore on` / `/rs restore off` - Toggle automatic restoration of previous rep on exit
- `/rs verbose on` / `/rs verbose off` - Toggle chat notifications
- `/rs check` - Manually trigger a zone check
- `/rs clear` - Clear the saved previous faction
- `/rs list` - Show all mapped instances and their factions
- `/rs help` - Show command help

## How It Works

1. When you enter a mapped instance, RepSwitcher saves your currently watched faction and switches to the instance's associated reputation.
2. For faction-specific reputations (e.g., Hellfire Citadel dungeons), it automatically picks the correct one for your character (Honor Hold for Alliance, Thrallmar for Horde).
3. When you leave the instance, it restores your previously watched faction.

## Installation

1. Download and extract to `Interface/AddOns/RepSwitcher/`
2. Restart WoW or `/reload`
3. That's it - RepSwitcher is enabled by default

## Settings

All settings are per-character and persist across sessions:
- **enabled** - Whether auto-switching is active (default: on)
- **restorePrevious** - Whether to restore previous rep on instance exit (default: on)
- **verbose** - Whether to show chat messages on switch (default: on)
