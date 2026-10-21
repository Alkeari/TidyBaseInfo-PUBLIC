Tidy Base Info
==============
A compact, scrollable pal grid for the Base Info panel that never overlaps your HUD, with
hover status, click-to-open pal details, and right-click actions (Send to Palbox, Resummon,
Assign).
Requires Palworld on Steam and UE4SS Experimental (Palworld) from the Steam Workshop.

Install (Steam Workshop)
  Subscribe, launch Palworld, enable the mod under Options > Mod Management.

Got this file some other way (not a Steam Workshop subscription)?
  This package is built for the Steam Workshop loader, which installs by item ID, not by
  dropping a folder in by hand. If you are not using Steam Workshop, use the Nexus Mods
  package instead: it installs directly into the Palworld game folder and needs no Steam
  subscription. Search for "Tidy Base Info" on https://www.nexusmods.com/palworld

Usage
  Hold Alt to free the mouse cursor over the panel (or press Alt+/ to toggle it on
  persistently). Hover a pal for its status, left-click for its details screen, right-click
  for the action menu. Alt+. and Alt+, scroll the grid from the keyboard. The menu follows
  your Palworld language setting, in all seventeen languages the game ships.

Dedicated servers
  Playing on a dedicated server? The mod must also be installed on the server (this package
  carries the server install rule, so a Workshop-configured server installs it
  automatically). The Send to Palbox, Resummon, and Assign actions need the server-side
  install; the grid itself works from the client alone.

Settings
  Scripts\config.lua: grid height, width and placement, icon size and portrait scale,
  whether empty worker slots are shown, keybinds and the modifier they use, menu size and
  spacing, and the language of the mod's own text, each documented in one sentence with its
  range or its choices. This file is replaced when the mod updates.

Bug reports
  Steam Workshop page > Discussions > Bug Reports, or the Bugs tab on Nexus Mods. Include
  your UE4SS.log (Mods\NativeMods\UE4SS\UE4SS.log), the mod version, the Palworld version
  from the title screen, and your other mods.

License
  License terms are in the Alkeari License Agreement:
  https://gist.github.com/Alkeari/2c6ec0cdf3dafee375b1a00b28ca190a
