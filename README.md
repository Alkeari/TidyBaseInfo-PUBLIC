# Tidy Base Info

Palworld's Base Info panel, fixed. A compact pal grid with a height limit that scrolls when your base outgrows it, and puts Send to Palbox, Resummon and Assign one right-click away.

> **Works in singleplayer, in co-op, and on dedicated servers.**

---

## Availability

- [Steam Workshop](https://steamcommunity.com/sharedfiles/filedetails/?id=3791929460)
- [Nexus Mods](https://www.nexusmods.com/palworld/mods/5443)

## What It Does

- **Stays out of your HUD** - the grid is capped at a set height, and at the default height it stops short of your hotbar and the Command Pal and Throw Pal Sphere prompts, however many workers you have.
- **Scrolls instead of growing** - once the grid is full it scrolls inside that height. Mouse wheel over the panel, or Alt+Period and Alt+Comma from the keyboard at any time.
- **Frees your cursor two ways** - hold Alt for a quick look, or press Alt+Slash to stay in inspect mode. The quick look survives letting go of Alt while the cursor is on the panel.
- **Leaves your aim alone** - while the cursor is over the panel, aiming, shooting, weapon and pal switching, partner orders and pal throwing are held, so scrolling never swaps your weapon.
- **Hover for live status** - a pal's name, what it is doing right now and its condition icons, in the game's own status row.
- **Left-click for the details screen** - the game's full pal-details page for the pal under the cursor, or pin its status instead.
- **Right-click for three actions** - on the pal under the cursor, without leaving the panel:
  - **Send to Palbox** moves that worker straight to your Palbox.
  - **Resummon** cycles the pal out through the Palbox and back into the base in one action.
  - **Assign** opens the base's fixed-assignment board without the walk to the Monitoring Stand.
- **Speaks your language** - the action menu is the only text the mod writes, and it follows your Palworld language setting in all seventeen the game ships.

---

## Requirements

- Palworld on Steam. The Microsoft Store and Game Pass builds are not supported.

## Installation

On a dedicated server, install the same files on the server as well: Send to Palbox, Resummon and Assign go through the server.

## Configuration

Every setting is in `Scripts\config.lua` inside the mod folder, one plain sentence each with its range or its choices. Save the file and the change takes effect within a couple of seconds while you play, with the panel already on screen rebuilt to match; no restart.

The `liveReloadSeconds` setting sets how often the file is checked, and 0 turns the checking off. An update reinstalls it with defaults, so keep a copy of your edits.

| What you can change | Settings |
|---|---|
| The grid | maximum height and width, where it sits, cell size, the gap between cells |
| Portraits | scale and nudge, the smaller scale for empty slots, whether empty slots show at all |
| Status row | where the hover status line sits |
| Keys | the scroll, inspect and hold keys, and whether the modifier is Alt, Ctrl, Shift or none |
| Scrolling | how far one step moves the grid |
| Action menu | width, placement, padding and spacing |
| Clicking | whether a left-click opens the details screen or pins the status row |
| Your input | whether gameplay input is held while the cursor is over the panel |
| Timing | the Resummon timeout, and how often the mod checks on the panel |
| Language | the language the action menu is written in |
| Update notice | `checkForUpdates`: once per game start, read the newest published version of this mod from `alkeari.com/updates/tidy-base-info.json` and tell you in the game's on-screen log only when a newer one exists. Nothing is sent but that one request |

Every one of them is also on the Mod Configs tab of [Universal Config Manager](https://www.nexusmods.com/palworld/mods/5545) if you run it, so you can change them without leaving the game. It is entirely optional and this mod never requires it.

## Compatibility

- **Client side.** The grid, the hover row, the menu, the cursor modes and every value in `config.lua` change only what you see and how you control it. Your settings apply to you alone.
- **Host side: none.** Send to Palbox, Resummon and Assign go through the same server requests the game's own screens use, so they follow the world's own rules.
- Install it on the server too when you play on a dedicated server. The grid works from the client alone, but the three actions need the server-side install.
- Any other mod that rebuilds the Base Info pal list conflicts with this one. Run one of them.
- On a multiplayer client, pals whose data has not arrived yet are restyled as it lands.
- If a Palworld update renames something the mod depends on, it logs the problem, restores the panel and disables itself instead of breaking your HUD.

## License

License terms are in the [Alkeari License Agreement](https://gist.github.com/Alkeari/2c6ec0cdf3dafee375b1a00b28ca190a).
