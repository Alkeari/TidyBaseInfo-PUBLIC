# Changelog

## v1.4.0 - 2026-10-20

Added: once per game start the mod looks up its newest published version and tells you in the game's on-screen log, in your game's language, only when a newer one exists; checkForUpdates in config.lua turns this off.

## v1.3.1 - 2026-10-17

Fixed: the Korean Send to Palbox menu entry spelled Palbox as "fan box"; it now matches the game's own spelling.
Fixed: the load line in the log names the version that is installed.

## v1.3.0 - 2026-09-05

Added: an edit to config.lua applies within seconds while you play, with no restart, and the panel already on screen is rebuilt with the new values.
Added: a liveReloadSeconds setting choosing how often the file is checked, where 0 turns the checking off.
Fixed: a keybind naming a mouse button is refused with a log line instead of being registered, which would have frozen the mod's input for the rest of the session.

## v1.2.0 - 2026-09-04

- Added: The right-click actions are shown in the game's own language, in all seventeen languages Palworld ships.
- Added: A Language setting pins the mod's text to one language instead of following the game.
- Added: A setting for the modifier the scroll and inspect keybinds use: Alt, Ctrl, Shift, or none at all.
- Added: A setting to hide empty worker slots, for a grid of your pals only.
- Added: A setting to leave weapon switching, aiming and pal commands alone while the cursor is over the panel.
- Added: A setting to pin a pal's name and status on click instead of opening the pal details screen.
- Added: Settings for the space beside an action menu label and for the gap between menu entries.
- Fixed: The action menu padding setting changed only the space above and below a label; the space beside it was fixed at twelve pixels.
- Fixed: Leaving a scroll or inspect key empty now turns that keybind off instead of leaving it unregistered.
- Changed: The action menu is wider by default so a translated label is not cut off.
- Changed: Every setting is documented in one plain sentence with its range or its list of choices.

## v1.1.0 - 2026-09-04

- Changed: The base menu plate, its edges and the item rows follow the Alkeari colors.
- Changed: Gold is now the only highlight color in the menu.

## v1.0.1 - 2026-08-30

- Fixed: on multiplayer clients, pals whose data had not finished replicating when the grid first built rendered at roughly half size and ignored clicks; the grid now restyles them as their data arrives.
- Fixed: with a Windows cursor over the panel (for example after Alt+Tab), scrolling past the grid's top or bottom no longer switches the equipped weapon.
- Fixed: on multiplayer clients, Resummon now works on any pal, including ones another guild member placed; previously such a pal reached the Palbox but never returned to the base.
- Changed: empty worker slots now render at about three quarters of an occupied cell's size instead of roughly half, tunable via emptyPortraitScale in Scripts/config.lua.

## v1.0.0 - 2026-08-29

- Added: the Base Info panel's pal list is now a compact icon grid capped at a fixed height, scrolling within itself instead of growing over the hotbar or action prompts.
- Added: hold Alt (or toggle with Alt+/) to free the mouse cursor over the panel; Alt+. and Alt+, scroll from the keyboard, and the wheel scrolls while the cursor is free.
- Added: hovering a pal's icon shows its name and live status in the game's own status row below the grid.
- Added: left-clicking a pal's icon opens the game's full pal-details screen for that pal.
- Added: right-clicking a pal's icon opens a quick-action menu: Send to Palbox, Resummon, and Assign (the Monitoring Stand's fixed-assignment board, opened from the HUD).
- Added: while the cursor is over the panel, weapon switching, aiming, and shooting are suspended so scrolling and clicking never leak into gameplay.
- Added: every tunable (grid size and placement, icon and portrait scale, keybinds, menu placement) lives in Scripts/config.lua, documented in place.
