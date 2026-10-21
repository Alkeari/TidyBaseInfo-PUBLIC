-- Tidy Base Info settings. Every value here changes only your own game, and a change takes
-- effect within seconds of saving this file, with no relaunch: the mod watches the file and
-- rebuilds the panel around the new values.

return {
    -- Language for this mod's own labels, where "auto" follows the game's language setting.
    -- Options: auto | en | de | es | es-MX | fr | id | it | ja | ko | pl | pt-BR | ru | th | tr | vi | zh-Hans | zh-Hant
    language = "auto",

    -- The tallest the pal grid may grow before it scrolls inside itself, in pixels.
    -- Range 120 to 900
    maxGridHeight = 320,

    -- Width of the pal grid, in pixels, which decides how many portraits fit per row.
    -- Range 120 to 900
    gridWidth = 368,

    -- Moves the pal grid right, or left with a negative value, in pixels.
    -- Range -400 to 400
    gridOffsetX = 0,

    -- Moves the pal grid down, or up with a negative value, in pixels.
    -- Range -400 to 400
    gridOffsetY = 0,

    -- Side length of one pal cell in the grid, in pixels.
    -- Range 32 to 200
    iconSize = 80,

    -- Gap left between pal cells, in pixels, on both axes.
    -- Range 0 to 40
    iconPadding = 4,

    -- How large a pal portrait is drawn inside its cell, where 1.0 is the size the game draws.
    -- Range 0.5 to 3.0
    portraitScale = 1.7,

    -- Nudges every pal portrait right, or left with a negative value, inside its cell.
    -- Range -40 to 40
    portraitOffsetX = 0,

    -- Nudges every pal portrait down, or up with a negative value, inside its cell.
    -- Range -40 to 40
    portraitOffsetY = 0,

    -- Shows an empty worker slot in the grid as a placeholder circle. Turn it off for a grid of
    -- your pals only.
    showEmptySlots = true,

    -- How large the placeholder circle in an empty worker slot is drawn.
    -- Range 0.5 to 3.0
    emptyPortraitScale = 1.5,

    -- Nudges the hover status row right, or left with a negative value, in pixels.
    -- Range -400 to 400
    hoverPanelOffsetX = 0,

    -- Gap between the bottom of the pal grid and the hover status row below it, in pixels.
    -- Range 0 to 200
    hoverPanelOffsetY = 12,

    -- Modifier key held together with the scroll and inspect keys below.
    -- Options: NONE | CTRL | SHIFT | ALT
    keybindModifier = "ALT",

    -- Key that scrolls the pal grid down one step. Leave it empty to turn this keybind off.
    scrollDownKey = "OEM_PERIOD",

    -- Key that scrolls the pal grid up one step. Leave it empty to turn this keybind off.
    scrollUpKey = "OEM_COMMA",

    -- Key that turns the free mouse cursor over the panel on and off, and keeps it on until you
    -- press the key again. Leave it empty to turn this keybind off.
    inspectKey = "OEM_TWO",

    -- How far one keyboard scroll step moves the pal grid, in pixels.
    -- Range 10 to 400
    scrollStepPx = 84,

    -- Key held for a quick look, which frees the mouse cursor over the panel until you let go.
    -- This one is a raw key name and takes no modifier. Leave it empty to turn holding off.
    inspectHoldKey = "LeftAlt",

    -- How many upkeep passes the free cursor survives after you move off the panel, so crossing
    -- the gap between the grid and the menu does not end it.
    -- Range 1 to 40
    cursorGraceTicks = 4,

    -- Suspends weapon switching, aiming, shooting and pal commands while your cursor is over
    -- the panel, so scrolling and clicking the grid never leak into the world.
    suspendInputOverPanel = true,

    -- Opens the game's full pal details screen when you click a pal. Turn it off to pin that
    -- pal's name and status in the row under the grid instead.
    openDetailsOnClick = true,

    -- Width of the right-click action menu, in pixels, wide enough for the longest label in any
    -- of the mod's languages. Raise it if a label is ever cut off.
    -- Range 120 to 600
    menuWidth = 340,

    -- Gap between the pal grid and the right-click action menu that opens beside it, in pixels.
    -- Range 0 to 200
    menuOffsetX = 8,

    -- Moves the right-click action menu down, or up with a negative value, in pixels.
    -- Range -400 to 400
    menuOffsetY = 0,

    -- Space to the left and right of each label in the right-click action menu, in pixels.
    -- Range 0 to 60
    menuItemPaddingX = 12,

    -- Space above and below each label in the right-click action menu, in pixels.
    -- Range 0 to 60
    menuItemPaddingY = 8,

    -- Gap between the entries of the right-click action menu, in pixels.
    -- Range 0 to 40
    menuItemGap = 4,

    -- How long Resummon waits for a pal to reach the Palbox before giving up and safely leaving
    -- it there, in milliseconds.
    -- Range 1000 to 30000
    resummonTimeoutMs = 6000,

    -- How often the mod checks on the panel, in milliseconds. A smaller number reacts faster and
    -- costs a little more performance.
    -- Range 50 to 1000
    maintenanceMs = 150,

    -- Once per game start the mod asks alkeari.com for its newest published version and, only
    -- when a newer one exists, says so in the game's on-screen log. Nothing is sent but that
    -- request. Turning it on takes effect the next time you launch the game.
    checkForUpdates = true,

    -- How often the mod re-reads this file so an edit lands without a relaunch, in seconds.
    -- Set it to 0 to stop watching the file; turning watching back on takes effect the next
    -- time you launch the game.
    -- Range 0 to 60
    liveReloadSeconds = 2,
}
