Tidy Base Info (Nexus Mods package)
===================================
A compact, scrollable pal grid for the Base Info panel that never overlaps your HUD, with
hover status, click-to-open pal details, and right-click actions (Send to Palbox, Resummon,
Assign).
Requires Palworld on Steam and UE4SS (RE-UE4SS Okaetsu Experimental-Palworld) from Nexus Mods
(https://www.nexusmods.com/palworld/mods/2237), installed the normal UE4SS way (dwmapi.dll plus
the ue4ss folder next to Palworld-Win64-Shipping.exe). Not the page named just "UE4SS": that is
the 3.x release line.

Install
  With Vortex: install and enable like any other mod; Vortex places the files itself.
  By hand:
  1. Install UE4SS (RE-UE4SS Okaetsu Experimental-Palworld) and launch the game once.
  2. Extract this zip into the Palworld install folder (the one containing Palworld.exe and
     Pal\) so that this exists:
       Palworld\Pal\Binaries\Win64\ue4ss\Mods\TidyBaseInfo\Scripts\main.lua
     (the zip already contains the full Pal\Binaries\Win64\ue4ss\Mods\TidyBaseInfo path and
     an enabled.txt).
  3. Launch Palworld and walk into one of your bases.
  To update: replace the folder. To uninstall: delete ue4ss\Mods\TidyBaseInfo.
  UE4SS-settings.ini must keep HookEngineTick = 1 (the default).

  Subscribed to "UE4SS Experimental (Palworld)" on the Steam Workshop instead? Use the Steam
  Workshop version of this mod, which installs itself: search the Palworld Workshop for
  "Tidy Base Info".

Dedicated servers
  Playing on a dedicated server? Install this mod on the SERVER as well as your client,
  using this same zip: the server has the identical Pal\Binaries\Win64\ue4ss layout, so
  extract it into the server's install folder exactly the same way. The Send to Palbox,
  Resummon, and Assign actions need the server-side install; the grid itself works from
  the client alone.

Usage
  Hold Alt to free the mouse cursor over the panel (or press Alt+/ to toggle it on
  persistently). Hover a pal for its status, left-click for its details screen, right-click
  for the action menu. Alt+. and Alt+, scroll the grid from the keyboard. The menu follows
  your Palworld language setting, in all seventeen languages the game ships.

Settings
  Scripts\config.lua: grid height, width and placement, icon size and portrait scale,
  whether empty worker slots are shown, keybinds and the modifier they use, menu size and
  spacing, and the language of the mod's own text, each documented in one sentence with its
  range or its choices. This file is replaced when the mod updates.

Bug reports
  Bugs tab on the Nexus Mods page. Include your UE4SS.log
  (Palworld\Pal\Binaries\Win64\ue4ss\UE4SS.log), the mod version, the Palworld version from
  the title screen, and your other mods.

License
  License terms are in the Alkeari License Agreement:
  https://gist.github.com/Alkeari/2c6ec0cdf3dafee375b1a00b28ca190a
