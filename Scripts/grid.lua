local Palette = require("palette")
local I18n = require("i18n")

local Grid = {}

local config = nil
local log = nil

-- ESlateVisibility, confirmed against /Script/UMG.ESlateVisibility in the object
-- dump (build 24575825): Visible=0, Collapsed=1, Hidden=2, HitTestInvisible=3,
-- SelfHitTestInvisible=4.
local VISIBLE = 0
local COLLAPSED = 1
local HIT_TEST_INVISIBLE = 3
local SELF_HIT_TEST_INVISIBLE = 4

-- EMouseLockMode::DoNotLock, confirmed in the same dump.
local MOUSE_DO_NOT_LOCK = 0

local WIDGET_LIBRARY_PATH = "/Script/UMG.Default__WidgetBlueprintLibrary"
local SIZE_BOX_CLASS_PATH = "/Script/UMG.SizeBox"
local SCROLL_BOX_CLASS_PATH = "/Script/UMG.ScrollBox"
local WRAP_BOX_CLASS_PATH = "/Script/UMG.WrapBox"
local BUTTON_CLASS_PATH = "/Script/UMG.Button"
local VERTICAL_BOX_CLASS_PATH = "/Script/UMG.VerticalBox"
local OVERLAY_CLASS_PATH = "/Script/UMG.Overlay"
local BORDER_CLASS_PATH = "/Script/UMG.Border"

-- The click catcher, take two - the CONCRETE class this time. Round one used
-- the abstract base (WBP_PalCharacterSlotButtonBase_C) whose own widget tree
-- is empty: "My Button" never got registered, BindButtonEvents bound
-- nothing, and both click internals were silently dead. The concrete
-- subclass carries a real tree (its own WBP_PalInvisibleButton, registered
-- as My Button on init), so its inherited Blueprint OnMouseButtonDown sees
-- every mouse button at the Slate layer - the only place right-clicks
-- reliably arrive: the 2026-08-28 diagnostic session proved PlayerInput
-- polling misses presses over UI entirely (two physical right-clicks, one
-- observed down, no observed release). The hooks target the BASE class
-- paths, where the functions are declared; they fire for subclass instances,
-- the game's own Palbox slot buttons included, and recordByCatcher filters
-- to ours.
local CATCHER_CLASS_PATH = "/Game/Pal/Blueprint/UI/Thumbnails/Character/"
        .. "WBP_PalCommonCharacterSlotButton.WBP_PalCommonCharacterSlotButton_C"
local CATCHER_BASE = "/Game/Pal/Blueprint/UI/Thumbnails/Character/Base/"
        .. "WBP_PalCharacterSlotButtonBase.WBP_PalCharacterSlotButtonBase_C"
local CATCHER_LEFT_HOOK = CATCHER_BASE .. ":OnClicked_Internal"
local CATCHER_RIGHT_HOOK = CATCHER_BASE .. ":OnRightClicked_Internal"

-- Visual children of the catcher to collapse: it must catch clicks over our
-- own portrait row, not draw its own portrait, selection frames or effects.
local CATCHER_VISUALS = {"WBP_PalCommonCharacterSlot", "FocusedFrame",
        "Check_0", "Check_1", "Check_2", "PushEff", "Overlay_Select"}
local TEXT_LIBRARY_PATH = "/Script/Engine.Default__KismetTextLibrary"
local UTILITY_PATH = "/Script/Pal.Default__PalUtility"

-- EPalWidgetBlueprintType::MonsterDetail, from the CXXHeaderDump enum
-- definition (build 24575825, read 2026-08-28); also observed live via a
-- ShowCommonUI hook capture when this mod's own click action fired.
local SCREEN_MONSTER_DETAIL = 2

-- EPalWidgetBlueprintType::BaseCampWorkFixedAssignManage.
local SCREEN_FIXED_ASSIGN_MANAGE = 17

-- EPalInteractiveObjectIndicatorType::OpenFixedAssignManageMenu, the exact
-- indicator value the Monitoring Stand's "[C] Fixed assignment management"
-- option carries (Pal_enums.hpp, build 24575825).
local INTERACT_OPEN_FIXED_ASSIGN = 79

local TRANSPARENT = Palette.none()

-- Menu plate colors, all from the palette declaration: a Deep Graphite plate, hairline edges,
-- raised item fills, Soft Champagne labels, and a Forged Gold focus ring on the hovered item as
-- the single accent. The item fill is the raised gray rather than graphite so an item never sits
-- graphite on graphite, and the label is the light end of the scale on every one of those fills.
local MENU_FRAME_EDGE = Palette.color("hairline")
local MENU_FILL = Palette.color("deepGraphite")
local MENU_ITEM_EDGE = Palette.color("hairline")
local MENU_ITEM_FILL = Palette.color("raised")
local MENU_ITEM_FILL_HOVER = Palette.color("raisedHover")
local MENU_LABEL = Palette.color("softChampagne")

-- The focus ring is one widget that is always there and paints only when the item is hovered,
-- so the ring never moves the item it rings. Design system: 2 px, Forged Gold.
local MENU_ITEM_RING = Palette.color("forgedGold", 0.0)
local MENU_ITEM_RING_HOVER = Palette.color("forgedGold")
local MENU_ITEM_RING_PX = 2

-- Hairline width for every edge this mod draws, and the design system's one transition
-- duration, which the frame tick walks the hover fade across.
local HAIRLINE_PX = 1
local TRANSITION_SECONDS = 0.160

local ZERO_GUID = {A = 0, B = 0, C = 0, D = 0}

-- Action ids, never labels: the label is looked up in the player's language when the menu is
-- built, and the id is what the click handler dispatches on.
local MENU_ACTIONS = {"palbox", "resummon", "assign"}

local VANILLA_ROW_PROPERTIES = {
    "WBP_IngameMenu_Task_SimpleList",
    "WBP_IngameMenu_Task_SimpleList_1",
    "WBP_IngameMenu_Task_SimpleList_2",
    "WBP_IngameMenu_Task_SimpleList_3",
    "WBP_IngameMenu_Task_SimpleList_4",
}

local state = {
    disabled = false,
    canvas = nil,
    task = nil,
    slots = nil,
    sizeBox = nil,
    scrollBox = nil,
    wrapBox = nil,
    hoverPanel = nil,
    icons = {},
    hiddenVanilla = {},
    rosterSignature = nil,
    hoveredIndex = nil,
    boundIndex = nil,
    pinnedIndex = nil,
    detailScreenUnavailable = false,
    frameTickRegistered = false,
    lastMaintenanceAt = 0,
    inspectToggled = false,
    cursorMode = nil,
    lastHoverTickAt = nil,
    holdUnavailable = false,
    holdArmed = true,
    hitTestRestore = {},
    widgetLibrary = nil,
    menuBox = nil,
    menuItems = {},
    menuTargetIndex = nil,
    resummonOp = nil,
    panelGuardActive = false,
    stickyMissTicks = 0,
    assignModels = {},
    assignCaptureRegistered = false,
    standModels = {},
    catcherHooksRegistered = false,
}

local function isValid(object)
    if object == nil then
        return false
    end
    local ok, valid = pcall(function()
        return object:IsValid()
    end)
    return ok and valid == true
end

local function safeCall(object, methodName, ...)
    if not isValid(object) then
        return nil
    end
    local args = {...}
    local ok, result = pcall(function()
        return object[methodName](object, table.unpack(args))
    end)
    if ok then
        return result
    end
    return nil
end

local function readProperty(object, propertyName)
    if not isValid(object) then
        return nil
    end
    local ok, value = pcall(function()
        return object[propertyName]
    end)
    if ok then
        return value
    end
    return nil
end

local function sameObject(left, right)
    local leftOk, leftName = pcall(function()
        return left:GetFullName()
    end)
    local rightOk, rightName = pcall(function()
        return right:GetFullName()
    end)
    return leftOk and rightOk and leftName == rightName
end

-- A stable string key for an FGuid struct wrapper.
local function guidKey(guid)
    local key = nil
    pcall(function()
        key = tostring(guid.A) .. "_" .. tostring(guid.B) .. "_"
                .. tostring(guid.C) .. "_" .. tostring(guid.D)
    end)
    return key
end

-- Forward-declared: defined with the resummon plumbing below, needed by
-- restoreVanilla above it so a torn-down panel also lifts the palbox
-- force-sync request an in-flight resummon turned on.
local endResummonOp

-- One action menu entry painted `progress` of the way from its resting state to its hovered
-- one: the raised fill lifts and the Forged Gold focus ring fades in. Called only when the
-- progress actually moved, so a settled menu writes nothing per frame.
local function paintMenuItem(item, progress)
    local eased = Palette.ease(progress)
    safeCall(item.fill, "SetBrushColor",
            Palette.blend(MENU_ITEM_FILL, MENU_ITEM_FILL_HOVER, eased))
    safeCall(item.ring, "SetBrushColor",
            Palette.blend(MENU_ITEM_RING, MENU_ITEM_RING_HOVER, eased))
end

local function closeMenu()
    state.menuTargetIndex = nil
    -- A closed menu forgets its hover, so reopening it never flashes a stale gold ring.
    for _, item in ipairs(state.menuItems) do
        if item.hoverProgress ~= 0 then
            item.hoverProgress = 0
            paintMenuItem(item, 0)
        end
    end
    if isValid(state.menuBox) then
        pcall(function()
            state.menuBox:SetVisibility(COLLAPSED)
        end)
    end
end

-- While the cursor is over the panel, weapon changing, aiming and shooting
-- are disabled on the player's ShooterComponent under this mod's own named
-- flag (flag-keyed disables stack safely with the game's own uses). This is
-- what UIOnlyEx used to provide, scoped to exactly the panel: the hotbar's
-- raw-input wheel cannot swap weapons, a right-click cannot trigger aim's
-- capture steal, and a stray click in a panel gap cannot fire. Lifted the
-- moment the cursor leaves the panel and on every teardown path.
local PANEL_GUARD_FLAG = "TidyBaseInfo"

local function setPanelGuard(active)
    if config.suspendInputOverPanel == false then
        active = false
    end
    if active == state.panelGuardActive then
        return
    end
    local player = safeCall(state.task, "GetOwningPlayer")
    local pawn = readProperty(player, "Pawn")
    local shooter = readProperty(pawn, "ShooterComponent")
    if not isValid(player) or not isValid(shooter) then
        return
    end
    local ok = pcall(function()
        local flag = FName(PANEL_GUARD_FLAG)
        shooter:SetDisableChangeWeaponFlag(flag, active)
        shooter:SetDisableAimFlag(flag, active)
        shooter:SetDisableShootFlag(flag, active)
        -- Controller-level flags: partner instructions IS the right-click
        -- pal-command pointer ("Attack that enemy!", zoomed targeting mode)
        -- that an unconsumed RMB over the panel engaged (observed in-game
        -- 2026-08-28); throw/switch cover the other pal inputs a stray
        -- click or key over the panel could fire.
        player:SetDisablePartnerInstructionsFlag(flag, active)
        player:SetDisableAimInputFlag(flag, active)
        player:SetDisableThrowPalFlag(flag, active)
        player:SetDisableSwitchPalFlag(flag, active)
    end)
    if ok then
        state.panelGuardActive = active
    end
end

-- Applies the cursor state. mode is nil (game input, no cursor) or "hold"
-- (GameAndUIEx: cursor free, hover and clicks on our widgets work, key state
-- stays readable). UIOnlyEx is deliberately NEVER used any more (2026-08-28):
-- it starved IsInputKeyDown, which killed hold-release detection over the
-- panel AND made right-click detection impossible; the only thing it bought
-- was blocking the hotbar's raw-input wheel over the panel, which the
-- keyboard scroll keys already cover. The wheel leak over the panel is the
-- accepted, documented cost of everything else working.
local function applyCursor(mode)
    -- Transition-only: re-applying the input mode every tick resets Slate's
    -- hover and capture state each time, which knocked out panel-hover
    -- detection and wedged input alongside other Alt-hold mods (observed
    -- in-game 2026-08-27). Capture refresh is handled separately, only
    -- off-panel, by refreshHoldCapture.
    if mode == state.cursorMode then
        return
    end
    local player = safeCall(state.task, "GetOwningPlayer")
    local library = state.widgetLibrary
    if not isValid(player) or not isValid(library) then
        return
    end
    if mode == nil then
        closeMenu()
        setPanelGuard(false)
        state.boundIndex = nil
        if isValid(state.hoverPanel) then
            pcall(function()
                state.hoverPanel:SetVisibility(COLLAPSED)
            end)
        end
        pcall(function()
            library:SetInputMode_GameOnly(player, false)
        end)
        pcall(function()
            player.bShowMouseCursor = false
        end)
        state.cursorMode = nil
        return
    end
    -- No focus widget (nil): handing Slate focus to a UI widget takes it off
    -- the game viewport, and PlayerInput then misses the FIRST mouse-button
    -- press over the panel (it gets spent transferring focus back) - observed
    -- in-game 2026-08-28 as right-click needing two presses. With the
    -- viewport keeping focus, IsInputKeyDown sees the first press; hover,
    -- wheel-over-grid and button presses route by hit-test, not focus.
    local ok = pcall(function()
        library:SetInputMode_GameAndUIEx(
                player, nil, MOUSE_DO_NOT_LOCK, false, false)
        player.bShowMouseCursor = true
    end)
    if ok then
        state.cursorMode = mode
    end
end

-- Re-applies the active cursor input mode without a state transition: the
-- game viewport re-grabs mouse capture and hides the cursor on its own world
-- interactions (world left-clicks, and aiming - which an unconsumed
-- right-click over the panel triggers). One re-application releases the
-- capture and restores the cursor.
local function reapplyCursorInputMode()
    local player = safeCall(state.task, "GetOwningPlayer")
    local library = state.widgetLibrary
    if not isValid(player) or not isValid(library) then
        return
    end
    pcall(function()
        library:SetInputMode_GameAndUIEx(
                player, nil, MOUSE_DO_NOT_LOCK, false, false)
        player.bShowMouseCursor = true
    end)
end

-- RegisterKeyBind has no key-release event, so hold-to-inspect is polled from
-- the maintenance loop through the reflected PlayerController:IsInputKeyDown
-- (FKey is a single-FName struct, passable as a table). GameAndUIEx keeps the
-- key state readable at all times, so a release always ends the hold; the
-- holdArmed re-arm (one observed not-down reading before hold is honored)
-- remains as the guard against re-freeing the cursor the instant the inspect
-- toggle turns off while the hold key happens to be down.
local function isHoldKeyDown()
    local holdKey = config.inspectHoldKey
    if state.holdUnavailable or holdKey == nil or holdKey == "" then
        return false
    end
    local player = safeCall(state.task, "GetOwningPlayer")
    if not isValid(player) then
        return false
    end
    local ok, down = pcall(function()
        return player:IsInputKeyDown({KeyName = FName(holdKey)})
    end)
    if not ok then
        state.holdUnavailable = true
        log.warn("hold-to-inspect unavailable: IsInputKeyDown could not be "
                .. "called; the inspect toggle keybind still works")
        return false
    end
    if down ~= true then
        state.holdArmed = true
        return false
    end
    return state.holdArmed
end

local function clearIcons()
    for _, record in ipairs(state.icons) do
        if isValid(record.row) then
            pcall(function()
                record.row:Unbind()
            end)
        end
        if isValid(record.catcher) then
            pcall(function()
                record.catcher:UnbindEvents()
            end)
        end
        for _, widget in ipairs({record.row, record.button, record.catcher,
                record.overlay, record.cell}) do
            if isValid(widget) then
                pcall(function()
                    widget:RemoveFromParent()
                end)
                pcall(function()
                    widget:SetVisibility(COLLAPSED)
                end)
            end
        end
    end
    state.icons = {}
    state.hoveredIndex = nil
    state.boundIndex = nil
    state.pinnedIndex = nil
    state.rosterSignature = nil
    closeMenu()
end

-- Walks from a widget up through every ancestor, crossing UserWidget boundaries
-- (a widget tree's root has no GetParent; its WidgetTree's outer is the owning
-- UserWidget, which sits as a widget in the next tree up).
local function ancestorChain(widget)
    local chain = {}
    local current = widget
    local guard = 0
    while isValid(current) and guard < 40 do
        guard = guard + 1
        chain[#chain + 1] = current
        local parent = safeCall(current, "GetParent")
        if isValid(parent) then
            current = parent
        else
            local treeOk, tree = pcall(function()
                return current:GetOuter()
            end)
            local userWidget = nil
            if treeOk and isValid(tree) then
                local outerOk, outer = pcall(function()
                    return tree:GetOuter()
                end)
                if outerOk and isValid(outer) then
                    userWidget = outer
                end
            end
            if userWidget ~= nil
                    and safeCall(userWidget, "GetVisibility") ~= nil then
                current = userWidget
            else
                break
            end
        end
    end
    return chain
end

-- The Base Info HUD is a passive overlay: some ancestor is HitTestInvisible,
-- which blocks pointer events for its whole subtree, so clicks and wheel input
-- fall through to the game even with a free cursor (wheel keeps scrolling the
-- hotbar, left click attacks). SelfHitTestInvisible keeps the ancestor itself
-- click-through while letting children be hit-testable.
local function unblockHitTesting()
    state.hitTestRestore = {}
    for _, widget in ipairs(ancestorChain(state.sizeBox)) do
        if safeCall(widget, "GetVisibility") == HIT_TEST_INVISIBLE then
            state.hitTestRestore[#state.hitTestRestore + 1] = {widget = widget}
            pcall(function()
                widget:SetVisibility(SELF_HIT_TEST_INVISIBLE)
            end)
        end
    end
    if #state.hitTestRestore > 0 then
        log.info(string.format("hit-testing unblocked on %d ancestor widget(s)",
                #state.hitTestRestore))
    end
end

local function reapplyHitTesting()
    for _, record in ipairs(state.hitTestRestore) do
        if isValid(record.widget)
                and safeCall(record.widget, "GetVisibility") == HIT_TEST_INVISIBLE then
            pcall(function()
                record.widget:SetVisibility(SELF_HIT_TEST_INVISIBLE)
            end)
        end
    end
end

local function restoreHitTesting()
    for _, record in ipairs(state.hitTestRestore) do
        if isValid(record.widget)
                and safeCall(record.widget, "GetVisibility") == SELF_HIT_TEST_INVISIBLE then
            pcall(function()
                record.widget:SetVisibility(HIT_TEST_INVISIBLE)
            end)
        end
    end
    state.hitTestRestore = {}
end

function Grid.restoreVanilla()
    state.inspectToggled = false
    applyCursor(nil)
    restoreHitTesting()
    clearIcons()
    for _, record in ipairs(state.hiddenVanilla) do
        if isValid(record.widget) then
            pcall(function()
                record.widget:SetVisibility(record.visibility)
            end)
        end
    end
    state.hiddenVanilla = {}
    if isValid(state.hoverPanel) then
        pcall(function()
            state.hoverPanel:Unbind()
        end)
    end
    for _, widget in ipairs({state.hoverPanel, state.sizeBox, state.menuBox}) do
        if isValid(widget) then
            pcall(function()
                widget:RemoveFromParent()
            end)
            pcall(function()
                widget:SetVisibility(COLLAPSED)
            end)
        end
    end
    state.sizeBox = nil
    state.scrollBox = nil
    state.wrapBox = nil
    state.hoverPanel = nil
    state.menuBox = nil
    state.menuItems = {}
    state.menuTargetIndex = nil
    if endResummonOp ~= nil then
        endResummonOp()
    end
    state.task = nil
    state.slots = nil
end

-- The category rule: a missing symbol turns the mod off with a readable reason,
-- never a crash. Restores whatever vanilla state was touched.
function Grid.disable(reason)
    if state.disabled then
        return
    end
    state.disabled = true
    log.error("DISABLED: " .. tostring(reason)
            .. ". The game build may have changed; wait for a mod update.")
    Grid.restoreVanilla()
end

local function resolveWidgetLibrary()
    if isValid(state.widgetLibrary) then
        return state.widgetLibrary
    end
    local ok, library = pcall(StaticFindObject, WIDGET_LIBRARY_PATH)
    if ok and isValid(library) then
        state.widgetLibrary = library
        return library
    end
    return nil
end

local function constructWidgetOfClass(widgetClass, outer)
    if not isValid(widgetClass) then
        return nil, "widget class is not loaded"
    end
    local ok, widget = pcall(function()
        return StaticConstructObject(widgetClass, outer, 0, 0, 0, nil, false, false, nil)
    end)
    if not ok or not isValid(widget) then
        return nil, "widget construction failed"
    end
    return widget, nil
end

local function constructNativeWidget(classPath, outer)
    local classOk, widgetClass = pcall(StaticFindObject, classPath)
    if not classOk or not isValid(widgetClass) then
        return nil, classPath .. " is not loaded"
    end
    local widget, constructError = constructWidgetOfClass(widgetClass, outer)
    if widget == nil then
        return nil, classPath .. " " .. constructError
    end
    return widget, nil
end

local function vanillaWidgetsToHide(task)
    local widgets = {}
    for _, propertyName in ipairs(VANILLA_ROW_PROPERTIES) do
        local row = readProperty(task, propertyName)
        if isValid(row) then
            widgets[#widgets + 1] = row
        end
    end
    local counter = readProperty(task, "Text_RemainDIsplayPalNum")
    if isValid(counter) then
        widgets[#widgets + 1] = counter
    end
    return widgets
end

-- Original visibility is captured exactly once per build; the game re-shows
-- these widgets on every roster update, so re-collapsing must never re-capture.
local function hideVanillaWidgets(task, captureOriginals)
    if captureOriginals then
        state.hiddenVanilla = {}
        for _, widget in ipairs(vanillaWidgetsToHide(task)) do
            local visibility = safeCall(widget, "GetVisibility")
            state.hiddenVanilla[#state.hiddenVanilla + 1] = {
                widget = widget,
                visibility = type(visibility) == "number" and visibility or VISIBLE,
            }
        end
    end
    for _, record in ipairs(state.hiddenVanilla) do
        if isValid(record.widget)
                and safeCall(record.widget, "GetVisibility") ~= COLLAPSED then
            pcall(function()
                record.widget:SetVisibility(COLLAPSED)
            end)
        end
    end
end

-- Breadth-first search of a UserWidget's own widget tree by widget object
-- name, bounded, without descending into child UserWidgets' internals beyond
-- panel traversal. Used for row widgets that exist in the tree but are not
-- named class properties (the decoration images).
local function findWidgetNamed(root, name, maxNodes)
    local queue = {root}
    local seen = 0
    while #queue > 0 and seen < (maxNodes or 200) do
        local current = table.remove(queue, 1)
        seen = seen + 1
        if isValid(current) then
            local ok, currentName = pcall(function()
                return current:GetFName():ToString()
            end)
            if ok and currentName == name then
                return current
            end
            local count = safeCall(current, "GetChildrenCount")
            if type(count) == "number" then
                for childIndex = 0, count - 1 do
                    local child = safeCall(current, "GetChildAt", childIndex)
                    if isValid(child) then
                        queue[#queue + 1] = child
                    end
                end
            end
        end
    end
    return nil
end

-- Trims a created vanilla row down to its portrait, the same surgery the
-- installed prior art performs: name and status texts, the three condition
-- widgets, and the row frame's decoration images all collapse; the portrait
-- (with its own built-in work/sleep/meal overlays) stays.
local ROW_DECORATION_PARENT = "HorizontalBox_6"
local ROW_DECORATION_NAMES = {"Image_3", "Image_4", "Image_27", "Image_28", "Image_29"}

local function styleCellRow(row, slotIsEmpty)
    for _, propertyName in ipairs({"Text_PalName", "Text_PalActionInfo",
            "WBP_MainMenu_Pal_State_0", "WBP_MainMenu_Pal_State_1",
            "WBP_MainMenu_Pal_State_2"}) do
        local child = readProperty(row, propertyName)
        if isValid(child) then
            pcall(function()
                child:SetVisibility(COLLAPSED)
            end)
        end
    end
    local rootOk, rootWidget = pcall(function()
        return row.WidgetTree.RootWidget
    end)
    if rootOk and isValid(rootWidget) then
        local strip = findWidgetNamed(rootWidget, ROW_DECORATION_PARENT)
        if isValid(strip) then
            for _, imageName in ipairs(ROW_DECORATION_NAMES) do
                local image = findWidgetNamed(strip, imageName, 40)
                if isValid(image) then
                    pcall(function()
                        image:SetVisibility(COLLAPSED)
                    end)
                end
            end
        end
    end
    -- An empty slot's placeholder circle is authored larger than a pal
    -- portrait, so the occupied fill scale renders it as oversized,
    -- off-center blobs (observed in-game 2026-08-28 at 1.7x); it gets its
    -- own smaller scale instead, tuned so an empty reads about 75% of an
    -- occupied cell's visual size.
    local portrait = readProperty(row, "WBP_PalCommonCharacterSlot")
    if isValid(portrait) then
        local scale = slotIsEmpty == true and config.emptyPortraitScale
                or config.portraitScale
        pcall(function()
            portrait:SetRenderTransformPivot({X = 0.5, Y = 0.5})
            portrait:SetRenderScale({X = scale, Y = scale})
            portrait:SetRenderTranslation(
                    {X = config.portraitOffsetX, Y = config.portraitOffsetY})
        end)
    end
end

local function templateRow(task)
    for _, propertyName in ipairs(VANILLA_ROW_PROPERTIES) do
        local row = readProperty(task, propertyName)
        if isValid(row) then
            return row
        end
    end
    return nil
end

local function buildContainers(task, parentCanvas)
    local outerOk, widgetTree = pcall(function()
        return task.WidgetTree
    end)
    if not outerOk or not isValid(widgetTree) then
        return false, "task WidgetTree is unavailable"
    end

    local sizeBox, sizeBoxError = constructNativeWidget(SIZE_BOX_CLASS_PATH, widgetTree)
    if sizeBox == nil then
        return false, sizeBoxError
    end
    local scrollBox, scrollBoxError = constructNativeWidget(SCROLL_BOX_CLASS_PATH, widgetTree)
    if scrollBox == nil then
        return false, scrollBoxError
    end
    local wrapBox, wrapBoxError = constructNativeWidget(WRAP_BOX_CLASS_PATH, widgetTree)
    if wrapBox == nil then
        return false, wrapBoxError
    end

    safeCall(wrapBox, "SetInnerSlotPadding",
            {X = config.iconPadding, Y = config.iconPadding})
    local scrollSlot = safeCall(scrollBox, "AddChild", wrapBox)
    if scrollSlot == nil then
        return false, "WrapBox could not be attached to ScrollBox"
    end
    local sizeSlot = safeCall(sizeBox, "AddChild", scrollBox)
    if sizeSlot == nil then
        return false, "ScrollBox could not be attached to SizeBox"
    end

    safeCall(sizeBox, "SetWidthOverride", config.gridWidth)
    safeCall(sizeBox, "SetMaxDesiredHeight", config.maxGridHeight)

    local canvasSlot = safeCall(parentCanvas, "AddChildToCanvas", sizeBox)
    if canvasSlot == nil then
        pcall(function()
            sizeBox:RemoveFromParent()
        end)
        return false, "SizeBox could not be attached to CanvasPanel_WorkerInfo"
    end
    pcall(function()
        canvasSlot:SetAutoSize(true)
        canvasSlot:SetPosition({X = config.gridOffsetX, Y = config.gridOffsetY})
    end)

    state.sizeBox = sizeBox
    state.scrollBox = scrollBox
    state.wrapBox = wrapBox
    return true, nil
end

-- The hover/pin detail row is a second instance of the same vanilla row
-- widget each grid cell already renders (WBP_IngameMenu_Task_SimpleList_C:
-- name, status text, condition icons), positioned below the grid and bound
-- via its own Setup(TargetSlot) - the same call and the same widget class
-- proven correct for every grid cell, unlike WBP_PalWorkerInfo (tried
-- 2026-08-28, reverted the same day: even after fixing the call arity it
-- still showed static, wrong, Japanese content in-game, and duplicated the
-- game's own pal-details screen the click action already opens). Unlike a
-- grid cell's row, this one is NOT trimmed by styleCellRow: the point of the
-- hover row is the name and status text a trimmed cell hides.
local function buildHoverPanel(task, parentCanvas)
    local library = resolveWidgetLibrary()
    local template = templateRow(task)
    if library == nil or not isValid(template) then
        return false
    end
    local ok, panel = pcall(function()
        return library:Create(task, template:GetClass(), task:GetOwningPlayer())
    end)
    if not ok or not isValid(panel) then
        return false
    end
    local canvasSlot = safeCall(parentCanvas, "AddChildToCanvas", panel)
    if canvasSlot == nil then
        return false
    end
    pcall(function()
        canvasSlot:SetAutoSize(true)
        canvasSlot:SetPosition({
            X = config.gridOffsetX + config.hoverPanelOffsetX,
            Y = config.gridOffsetY + config.maxGridHeight
                    + config.hoverPanelOffsetY,
        })
    end)
    pcall(function()
        panel:SetVisibility(COLLAPSED)
    end)
    state.hoverPanel = panel
    return true
end

local function slotHandle(record)
    if record == nil then
        return nil
    end
    local ok, handle = pcall(function()
        return record.slot:GetHandle()
    end)
    if ok and isValid(handle) then
        return handle
    end
    return nil
end

local function textFromString(value)
    local libOk, textLibrary = pcall(StaticFindObject, TEXT_LIBRARY_PATH)
    if not libOk or not isValid(textLibrary) then
        return nil
    end
    local ok, text = pcall(function()
        return textLibrary:Conv_StringToText(value)
    end)
    if ok then
        return text
    end
    return nil
end

-- One sentence in the player's language on every element the player can click, the design
-- system's tooltip rule. `/Script/UMG.Widget:SetToolTipText` is reflected (confirmed in
-- `UE4SS_ObjectDump.txt`, build 25094871, 2026-09-08); a build that ever refuses it silently
-- leaves the element with no tooltip rather than failing the panel.
local function setTooltip(widget, key)
    if not isValid(widget) then
        return
    end
    local text = textFromString(I18n.t(key))
    if text ~= nil then
        safeCall(widget, "SetToolTipText", text)
    end
end

-- The context menu: a fixed-width column of native buttons to the LEFT of the
-- grid (the screen edge sits just right of the scrollbar, so rightward
-- placement would clip off-screen). Built lazily once per panel build; clicks
-- are press-edge polled on the same fast loop as the cell buttons.
-- Labels are instances of the game's OWN text-block class (BP_PalTextBlock_C,
-- taken live from the vanilla row's Text_PalName), never a raw
-- /Script/UMG.TextBlock: a raw TextBlock's font object is null, Palworld does
-- not ship the stock engine fonts that null falls back to, and the first paint
-- after the menu first became visible crashed the game with a null-deref
-- access violation (observed 2026-08-28, build 24575825, on the first
-- right-click; the game itself never instantiates a bare TextBlock anywhere,
-- which is corroborating evidence, not proof).
local function buildMenu(task, parentCanvas)
    local widgetTree = readProperty(task, "WidgetTree")
    if not isValid(widgetTree) then
        return false
    end
    local template = templateRow(task)
    local sourceText = readProperty(template, "Text_PalName")
    local textClass = safeCall(sourceText, "GetClass")
    if not isValid(textClass) then
        return false
    end
    -- Visual language borrowed from Palpedia Enhancer's drafted buttons: the
    -- menu is one dark plate (edge Border around fill Border), and each item
    -- is its own plate whose edge turns gold on hover. The transparent native
    -- Button stays outermost per item: it consumes the click and carries the
    -- reflected IsPressed poll; the Borders only paint.
    local menuSize = constructNativeWidget(SIZE_BOX_CLASS_PATH, widgetTree)
    local frameEdge = constructNativeWidget(BORDER_CLASS_PATH, widgetTree)
    local frameFill = constructNativeWidget(BORDER_CLASS_PATH, widgetTree)
    local menuBox = constructNativeWidget(VERTICAL_BOX_CLASS_PATH, widgetTree)
    if not (isValid(menuSize) and isValid(frameEdge) and isValid(frameFill)
            and isValid(menuBox)) then
        return false
    end
    safeCall(menuSize, "SetWidthOverride", config.menuWidth)
    safeCall(frameEdge, "SetBrushColor", MENU_FRAME_EDGE)
    safeCall(frameEdge, "SetPadding", {
        Left = HAIRLINE_PX,
        Top = HAIRLINE_PX,
        Right = HAIRLINE_PX,
        Bottom = HAIRLINE_PX,
    })
    safeCall(frameFill, "SetBrushColor", MENU_FILL)
    safeCall(frameFill, "SetPadding", {Left = 8, Top = 8, Right = 8, Bottom = 8})
    if safeCall(menuSize, "AddChild", frameEdge) == nil
            or safeCall(frameEdge, "AddChild", frameFill) == nil
            or safeCall(frameFill, "AddChild", menuBox) == nil then
        return false
    end

    state.menuItems = {}
    for index, action in ipairs(MENU_ACTIONS) do
        local button = constructNativeWidget(BUTTON_CLASS_PATH, widgetTree)
        local itemRing = constructNativeWidget(BORDER_CLASS_PATH, widgetTree)
        local itemEdge = constructNativeWidget(BORDER_CLASS_PATH, widgetTree)
        local itemFill = constructNativeWidget(BORDER_CLASS_PATH, widgetTree)
        local text = constructWidgetOfClass(textClass, widgetTree)
        local labelText = textFromString(I18n.t("menu_" .. action))
        if isValid(button) and isValid(itemRing) and isValid(itemEdge)
                and isValid(itemFill) and isValid(text) and labelText ~= nil then
            pcall(function()
                text:SetText(labelText)
            end)
            -- Soft Champagne on the raised gray, never the game's own color, and never
            -- wrapped: a label that wraps is a design-system defect, and a translated
            -- action runs half again as long as the English one.
            safeCall(text, "SetColorAndOpacity",
                    {SpecifiedColor = MENU_LABEL, ColorUseRule = 0})
            safeCall(text, "SetAutoWrapText", false)
            setTooltip(button, "tip_menu_" .. action)
            safeCall(button, "SetBackgroundColor", TRANSPARENT)
            safeCall(itemRing, "SetBrushColor", MENU_ITEM_RING)
            safeCall(itemRing, "SetPadding", {
                Left = MENU_ITEM_RING_PX,
                Top = MENU_ITEM_RING_PX,
                Right = MENU_ITEM_RING_PX,
                Bottom = MENU_ITEM_RING_PX,
            })
            safeCall(itemEdge, "SetBrushColor", MENU_ITEM_EDGE)
            safeCall(itemEdge, "SetPadding", {
                Left = HAIRLINE_PX,
                Top = HAIRLINE_PX,
                Right = HAIRLINE_PX,
                Bottom = HAIRLINE_PX,
            })
            safeCall(itemFill, "SetBrushColor", MENU_ITEM_FILL)
            safeCall(itemFill, "SetPadding", {
                Left = config.menuItemPaddingX,
                Top = config.menuItemPaddingY,
                Right = config.menuItemPaddingX,
                Bottom = config.menuItemPaddingY,
            })
            local buttonSlot = safeCall(button, "AddChild", itemRing)
            if buttonSlot ~= nil then
                pcall(function()
                    buttonSlot:SetPadding({Left = 0, Top = 0, Right = 0, Bottom = 0})
                    buttonSlot:SetHorizontalAlignment(0)
                    buttonSlot:SetVerticalAlignment(0)
                end)
            end
            local built = buttonSlot ~= nil
                    and safeCall(itemRing, "AddChild", itemEdge) ~= nil
                    and safeCall(itemEdge, "AddChild", itemFill) ~= nil
                    and safeCall(itemFill, "AddChild", text) ~= nil
            local boxSlot = built and safeCall(menuBox, "AddChild", button) or nil
            if boxSlot ~= nil then
                if index > 1 then
                    pcall(function()
                        boxSlot:SetPadding({
                            Left = 0,
                            Top = config.menuItemGap,
                            Right = 0,
                            Bottom = 0,
                        })
                    end)
                end
                state.menuItems[#state.menuItems + 1] = {
                    button = button,
                    ring = itemRing,
                    edge = itemEdge,
                    fill = itemFill,
                    action = action,
                    wasPressed = false,
                    hoverProgress = 0,
                }
            end
        end
    end
    if #state.menuItems ~= #MENU_ACTIONS then
        state.menuItems = {}
        pcall(function()
            menuSize:RemoveFromParent()
        end)
        return false
    end

    local canvasSlot = safeCall(parentCanvas, "AddChildToCanvas", menuSize)
    if canvasSlot == nil then
        state.menuItems = {}
        return false
    end
    pcall(function()
        canvasSlot:SetAutoSize(true)
        canvasSlot:SetPosition({
            X = config.gridOffsetX - config.menuWidth - config.menuOffsetX,
            Y = config.gridOffsetY + config.menuOffsetY,
        })
    end)
    pcall(function()
        menuSize:SetVisibility(COLLAPSED)
    end)
    state.menuBox = menuSize
    return true
end

local function openMenu(index)
    if not isValid(state.menuBox) then
        return
    end
    state.menuTargetIndex = index
    pcall(function()
        state.menuBox:SetVisibility(VISIBLE)
    end)
end

-- Server-request plumbing for the menu actions, resolved fresh per use (the
-- transmitter and its base camp component are per-player session objects).
-- All symbols from the CXXHeaderDump, build 24575825, 2026-08-28:
-- PalUtility:GetNetworkTransmitterByPlayerCharacter(pawn) ->
-- APalNetworkTransmitter:GetBaseCamp() -> UPalNetworkBaseCampComponent, whose
-- RequestMoveWorkerToPalBox_ToServer / RequestMoveCharacterToWorker_ToServer
-- are the same server requests the vanilla Palbox UI issues. The current base
-- camp id is the canvas's own lastInsideBaseCampID property.
local function networkBaseCamp()
    local player = safeCall(state.task, "GetOwningPlayer")
    local pawn = readProperty(player, "Pawn")
    local utilOk, utility = pcall(StaticFindObject, UTILITY_PATH)
    if not isValid(pawn) or not utilOk or not isValid(utility) then
        return nil
    end
    local ok, transmitter = pcall(function()
        return utility:GetNetworkTransmitterByPlayerCharacter(pawn)
    end)
    if not ok or not isValid(transmitter) then
        return nil
    end
    local component = safeCall(transmitter, "GetBaseCamp")
    if isValid(component) then
        return component
    end
    return readProperty(transmitter, "BaseCamp")
end

local function currentBaseCampId()
    return readProperty(state.canvas, "lastInsideBaseCampID")
end

local function sendToPalbox(record)
    local component = networkBaseCamp()
    local campId = currentBaseCampId()
    local slotId = safeCall(record.slot, "GetSlotId")
    if not isValid(component) or campId == nil or slotId == nil then
        log.warn("Send to Palbox unavailable: base camp request plumbing "
                .. "could not be resolved")
        return false
    end
    local ok, requestError = pcall(function()
        component:RequestMoveWorkerToPalBox_ToServer(campId, slotId, 0, ZERO_GUID)
    end)
    if ok then
        log.info("requested move to Palbox for grid slot " .. record.index)
        return true
    end
    log.warn("Send to Palbox request failed: " .. tostring(requestError))
    return false
end

-- Resummon has no single vanilla call: it is send-to-Palbox followed by a
-- move back into the base's worker container once the server confirms the pal
-- arrived in the box (the maintenance loop polls the player's Palbox
-- container for the saved handle, bounded by resummonTimeoutMs).
-- On a multiplayer client the server syncs palbox slot data on demand only
-- (APalPlayerState:RequestPalBoxSyncPage_ToServer per page while the box UI
-- is open; server-side bIsForceSyncAllSlot), so the step-2 poll's container
-- read is stale for any pal whose slot data never reached this client -
-- observed in co-op 2026-08-29/30 as Resummon working only for pals that had
-- been in the player's own Palbox at some point that session. The op turns
-- RequestForceSyncPalBoxSlot_ToServer on for the wait and off when it ends.
local function setPalboxForceSync(active)
    local player = safeCall(state.task, "GetOwningPlayer")
    local playerState = readProperty(player, "PlayerState")
    if not isValid(playerState) then
        return false
    end
    return (pcall(function()
        playerState:RequestForceSyncPalBoxSlot_ToServer(active)
    end))
end

local function instanceKeyOfHandle(handle)
    local key = nil
    pcall(function()
        local id = handle:GetIndividualID()
        key = guidKey(id.InstanceId)
    end)
    return key
end

endResummonOp = function()
    local op = state.resummonOp
    state.resummonOp = nil
    if op ~= nil and op.forceSyncOn then
        setPalboxForceSync(false)
    end
end

-- FindByHandle first; if it misses, scan the container comparing instance
-- ids, in case the client's replicated box slot carries a different handle
-- OBJECT than the worker slot's handle the op saved (same FPalInstanceID).
local function boxSlotForOp(container, op)
    local slot = safeCall(container, "FindByHandle", op.handle)
    if isValid(slot) then
        return slot
    end
    if op.instanceKey == nil then
        return nil
    end
    local found = nil
    pcall(function()
        container:GetSlots():ForEach(function(_, element)
            if found == nil then
                pcall(function()
                    local candidate = element:get()
                    local candidateHandle = candidate:GetHandle()
                    local id = candidateHandle:GetIndividualID()
                    if guidKey(id.InstanceId) == op.instanceKey then
                        found = candidate
                    end
                end)
            end
        end)
    end)
    return found
end

local function startResummon(record)
    local handle = slotHandle(record)
    local slotId = safeCall(record.slot, "GetSlotId")
    -- GetSlotId returns a STRUCT (FPalCharacterSlotId), not a UObject:
    -- readProperty's IsValid guard always fails on structs (no IsValid
    -- method), so the field is read directly under pcall.
    local workerContainerId = nil
    if slotId ~= nil then
        pcall(function()
            workerContainerId = slotId.ContainerId
        end)
    end
    local campId = currentBaseCampId()
    if handle == nil or workerContainerId == nil or campId == nil then
        log.warn("Resummon unavailable: the pal's container identity could "
                .. "not be read")
        return
    end
    if not sendToPalbox(record) then
        return
    end
    state.resummonOp = {
        handle = handle,
        instanceKey = instanceKeyOfHandle(handle),
        toContainerId = workerContainerId,
        campId = campId,
        deadline = os.clock() + (config.resummonTimeoutMs / 1000),
        forceSyncOn = setPalboxForceSync(true),
    }
    log.info("resummon step 1 sent; waiting for the pal to reach the Palbox")
end

local function resummonTick()
    local op = state.resummonOp
    if op == nil then
        return
    end
    if os.clock() > op.deadline then
        endResummonOp()
        log.warn("resummon timed out waiting for the pal to reach the Palbox; "
                .. "the pal remains in the box")
        return
    end
    local player = safeCall(state.task, "GetOwningPlayer")
    local playerState = readProperty(player, "PlayerState")
    local storage = readProperty(playerState, "PalStorage")
    local container = readProperty(storage, "TargetContainer")
    if not isValid(container) then
        return
    end
    local boxSlot = boxSlotForOp(container, op)
    if not isValid(boxSlot) then
        return
    end
    local boxSlotId = safeCall(boxSlot, "GetSlotId")
    local component = networkBaseCamp()
    if boxSlotId == nil or not isValid(component) then
        return
    end
    endResummonOp()
    local ok, requestError = pcall(function()
        component:RequestMoveCharacterToWorker_ToServer(
                op.campId, boxSlotId, op.toContainerId, ZERO_GUID)
    end)
    if ok then
        log.info("resummon step 2 sent: pal moved back to the base")
    else
        log.warn("resummon step 2 failed (" .. tostring(requestError)
                .. "); the pal remains in the Palbox")
    end
end

-- Captures the natively built, base-linked assignment model the moment the
-- game itself opens the fixed-assignment board (the player using a
-- Monitoring Stand): a post-body hook on the board widget's
-- OnUpdateAssignInfo stashes the model parameter. A Lua-built model can
-- never be base-linked (no reflected setter; two 0-facilities boards proved
-- it in co-op), so the game's own model, captured once per base, is the
-- verified replay source; the cold-start stand call below fills the gap
-- before the first capture.
local function registerAssignCapture()
    if state.assignCaptureRegistered then
        return
    end
    -- The vanilla stand-open path is native-to-native: a session with the
    -- board opened manually produced ZERO type-17 ShowCommonUI hook fires
    -- (2026-08-28), so capture hooks the board WIDGET's own Blueprint
    -- OnUpdateAssignInfo instead, which receives the natively built,
    -- base-linked model as a parameter every time the board's data updates -
    -- guaranteed script-VM traffic whenever the player uses the stand.
    local ok = pcall(RegisterHook,
            "/Game/Pal/Blueprint/UI/BaseCampWorkFixedAssignManage/"
            .. "WBP_BaseCampWorkFixedAssignManage.WBP_BaseCampWorkFixedAssignManage_C"
            .. ":OnUpdateAssignInfo",
            function(_, modelParam)
        pcall(function()
            local model = modelParam:get()
            if not isValid(model) then
                return
            end
            -- Key by the base the model belongs to: its outer is that
            -- base's PalBaseCampModel (learned from the first capture's
            -- outer chain). Only natively built models pass through here
            -- since this mod no longer constructs board models itself.
            local outerCamp = safeCall(model, "GetOuter")
            local campId = safeCall(outerCamp, "GetId")
            local key = campId ~= nil and guidKey(campId) or nil
            if key ~= nil and not (state.assignModels[key] ~= nil
                    and isValid(state.assignModels[key])
                    and sameObject(state.assignModels[key], model)) then
                state.assignModels[key] = model
                log.info("assignment model captured for base " .. key)
            end
        end)
    end)
    state.assignCaptureRegistered = true
    if not ok then
        log.warn("the assignment board could not be hooked; Assign stays "
                .. "unavailable until a model can be captured from it")
    end
end

-- Cold start: open the board through the stand's own interact entry point.
-- The 2026-08-28 companion ProcessEvent capture of a real "[C] Fixed
-- assignment management" press showed the native flow invoking
-- PalMapObjectConcreteModelBase:OnTriggerInteract THROUGH ProcessEvent on
-- the stand's concrete model PalMapObjectBaseCampPassiveWorkHardModel, with
-- the board's widget tree constructing inside that very call - so a Lua
-- call to the same function on the same object with the same arguments is
-- the identical invocation. The earlier "OnTriggerInteract no-ops" finding
-- targeted PalMapObjectBaseCampWorkerDirectorModel, the WRONG concrete
-- model (its handler only knows the battle-type options, 67/68, and
-- silently ignores 79).
local function coldOpenViaStand(campId)
    local player = safeCall(state.task, "GetOwningPlayer")
    local pawn = readProperty(player, "Pawn")
    if not isValid(pawn) then
        return false, "the player pawn could not be resolved"
    end
    local campKey = guidKey(campId)
    for index = #state.standModels, 1, -1 do
        local model = state.standModels[index]
        if not isValid(model) then
            table.remove(state.standModels, index)
        else
            local standCampId = safeCall(model, "GetBaseCampIdBelongTo")
            if standCampId ~= nil and guidKey(standCampId) == campKey then
                local ok, callError = pcall(function()
                    model:OnTriggerInteract(pawn, INTERACT_OPEN_FIXED_ASSIGN)
                end)
                if ok then
                    return true, nil
                end
                return false, "the stand's board-open call failed: "
                        .. tostring(callError)
            end
        end
    end
    return false, "no Monitoring Stand model found for this base"
end

-- Assign reuses the game's OWN board model, captured per base from the
-- board's OnUpdateAssignInfo when the player uses that base's Monitoring
-- Stand or after one successful cold-start open. Building the model from
-- Lua is a proven dead end THREE times over (2026-08-28): bare construction
-- and HUD-service/controller outers gave a blank board, and even the
-- correct native outer (the base's own PalBaseCampModel, learned from a
-- captured model's outer chain) still gave an unlinked board - the native
-- creation initializes internal state reflection cannot reach. Do not try
-- again.
local function openAssignScreen(record)
    local campId = currentBaseCampId()
    if campId == nil then
        return false, "the current base camp id could not be read"
    end
    local key = guidKey(campId)
    local uiModel = key ~= nil and state.assignModels[key] or nil
    if not isValid(uiModel) then
        local coldOk, coldReason = coldOpenViaStand(campId)
        if coldOk then
            log.info("opened the assignment board through the base's "
                    .. "Monitoring Stand (cold start)")
            return true, nil
        end
        return false, "no board model captured for this base yet and the "
                .. "cold-start stand open failed (" .. tostring(coldReason)
                .. "): open its Monitoring Stand assignment board once "
                .. "this session, then Assign works from the grid"
    end
    local utilOk, utility = pcall(StaticFindObject, UTILITY_PATH)
    if not utilOk or not isValid(utility) then
        return false, "PalUtility default object is unavailable"
    end
    local serviceOk, hudService = pcall(function()
        return utility:GetHUDService(state.task)
    end)
    if not serviceOk or not isValid(hudService) then
        return false, "the HUD service could not be resolved"
    end
    local classOk, parameterClass = pcall(StaticFindObject,
            "/Script/Pal.PalHUDDispatchParameter_BaseCampWorkFixedAssignManage")
    if not classOk or not isValid(parameterClass) then
        return false, "the FixedAssignManage dispatch parameter class is not loaded"
    end
    local paramOk, parameter = pcall(function()
        return hudService:CreateDispatchParameterForK2Node(state.task, parameterClass)
    end)
    if not paramOk or not isValid(parameter) then
        return false, "the FixedAssignManage dispatch parameter could not be created"
    end
    local showOk, showError = pcall(function()
        parameter.Model = uiModel
        hudService:ShowCommonUI(SCREEN_FIXED_ASSIGN_MANAGE, parameter)
    end)
    if not showOk then
        return false, "ShowCommonUI failed: " .. tostring(showError)
    end
    return true, nil
end

local function onMenuAction(action, record)
    closeMenu()
    if record == nil then
        return
    end
    if action == "palbox" then
        sendToPalbox(record)
    elseif action == "resummon" then
        startResummon(record)
    elseif action == "assign" then
        -- The assign screen manages its own input mode, same as the details
        -- screen: end the cursor session before opening it.
        state.inspectToggled = false
        state.holdArmed = false
        applyCursor(nil)
        local ok, reason = openAssignScreen(record)
        if ok then
            log.info("opened fixed-assignment screen from grid slot " .. record.index)
        else
            log.warn("fixed-assignment screen unavailable: " .. tostring(reason))
        end
    end
end

local function rosterSignatureOf(slots)
    local parts = {}
    for index, slot in ipairs(slots) do
        local ok, name = pcall(function()
            return slot:GetFullName()
        end)
        -- The empty bit is part of the signature: on a co-op client, slot
        -- data lands via replication after Set Pal Slots first fires, so a
        -- slot can read empty at build time and occupied moments later with
        -- the same object name; the flip must trigger a rebuild.
        local empty = safeCall(slot, "IsEmpty") == true
        parts[#parts + 1] = string.format("%d:%s:%s", index, ok and name or "?",
                empty and "e" or "f")
    end
    return table.concat(parts, "|")
end

-- A hidden empty slot's cell is collapsed, never skipped at build time: a co-op client can read
-- a slot empty when the grid builds and occupied moments later, and the upkeep pass repairs that
-- by restyling and revealing the cell it already made.
local function applyEmptyVisibility(record)
    local hidden = record.isEmpty == true and config.showEmptySlots == false
    if record.hidden == hidden or not isValid(record.cell) then
        return
    end
    pcall(function()
        record.cell:SetVisibility(hidden and COLLAPSED or VISIBLE)
    end)
    record.hidden = hidden
end

local function populateIcons(task, slots)
    clearIcons()
    local template = templateRow(task)
    local library = resolveWidgetLibrary()
    if template == nil or library == nil then
        return false, "row template or WidgetBlueprintLibrary unavailable"
    end
    local rowClass = safeCall(template, "GetClass")
    local owningPlayer = safeCall(task, "GetOwningPlayer")
    if rowClass == nil or owningPlayer == nil then
        return false, "row class or owning player unavailable"
    end
    local treeOk, widgetTree = pcall(function()
        return task.WidgetTree
    end)
    if not treeOk or not isValid(widgetTree) then
        return false, "task WidgetTree is unavailable"
    end

    for index, slot in ipairs(slots) do
        -- Each cell renders a full vanilla row trimmed to its portrait (the
        -- prior art's technique): the portrait keeps its authored geometry
        -- inside its own row, which is what a bare force-stretched icon
        -- widget gets visibly wrong. Cell chain: SizeBox (outermost, its
        -- overrides are the cell's desired size) -> Overlay -> [transparent
        -- Button holding the trimmed row (attack blocking + the IsPressed
        -- left-click fallback poll), catcher on top (Slate-layer left AND
        -- right click source via the hooked base-class internals)].
        local ok, row = pcall(function()
            return library:Create(task, rowClass, owningPlayer)
        end)
        if ok and isValid(row) then
            local setupOk = pcall(function()
                row:Setup(slot)
            end)
            local cell = nil
            local button = nil
            local overlay = nil
            local catcher = nil
            local slotIsEmpty = safeCall(slot, "IsEmpty") == true
            if setupOk then
                styleCellRow(row, slotIsEmpty)
                cell = constructNativeWidget(SIZE_BOX_CLASS_PATH, widgetTree)
                button = constructNativeWidget(BUTTON_CLASS_PATH, widgetTree)
                overlay = constructNativeWidget(OVERLAY_CLASS_PATH, widgetTree)
                local catcherClassOk, catcherClass = pcall(StaticFindObject,
                        CATCHER_CLASS_PATH)
                if catcherClassOk and isValid(catcherClass) then
                    local catcherOk, created = pcall(function()
                        return library:Create(task, catcherClass, owningPlayer)
                    end)
                    if catcherOk then
                        catcher = created
                    end
                end
            end
            if isValid(catcher) then
                pcall(function()
                    catcher.IsEnableDragDrop = false
                    catcher.IsEnableClick = true
                    -- Never focusable: CommonUI hover-focus hid the free
                    -- cursor in catcher round one.
                    catcher.bIsFocusable = false
                end)
                safeCall(catcher, "SetEnable", true)
                local innerButton = readProperty(catcher, "My Button")
                if isValid(innerButton) then
                    pcall(function()
                        innerButton:SetIsFocusable(false)
                    end)
                end
                for _, visualName in ipairs(CATCHER_VISUALS) do
                    local visual = readProperty(catcher, visualName)
                    if isValid(visual) then
                        pcall(function()
                            visual:SetVisibility(COLLAPSED)
                        end)
                    end
                end
                -- Render opacity zero kills EVERYTHING the catcher could ever
                -- draw - including the CommonUI hover/press styling and
                -- animations that showed as an unwanted highlight over the
                -- portrait (observed in-game 2026-08-28) - while Slate
                -- hit-testing, which ignores opacity, keeps working.
                pcall(function()
                    catcher:SetRenderOpacity(0.0)
                end)
            end
            local attached = false
            if isValid(cell) and isValid(button) and isValid(overlay)
                    and isValid(catcher) then
                safeCall(cell, "SetWidthOverride", config.iconSize)
                safeCall(cell, "SetHeightOverride", config.iconSize)
                safeCall(button, "SetBackgroundColor", TRANSPARENT)
                -- One sentence per cell, on both hit-testable layers: the catcher sits over
                -- the button, so a tooltip on the button alone would never be the widget the
                -- cursor is actually on. An empty slot says it is empty rather than
                -- promising an action it has no pal for.
                local tooltipKey = slotIsEmpty and "tip_cell_empty"
                        or (config.openDetailsOnClick == false and "tip_cell_pin"
                                or "tip_cell_details")
                setTooltip(button, tooltipKey)
                setTooltip(catcher, tooltipKey)
                local inButton = safeCall(button, "AddChild", row)
                if inButton ~= nil then
                    safeCall(inButton, "SetPadding",
                            {Left = 0, Top = 0, Right = 0, Bottom = 0})
                    -- The button slot defaults to Center/Center, which lays
                    -- the row out at its own desired size; Fill (0) gives it
                    -- the whole cell.
                    safeCall(inButton, "SetHorizontalAlignment", 0)
                    safeCall(inButton, "SetVerticalAlignment", 0)
                end
                local inOverlayButton = inButton ~= nil
                        and safeCall(overlay, "AddChildToOverlay", button) or nil
                local inOverlayCatcher = inOverlayButton ~= nil
                        and safeCall(overlay, "AddChildToOverlay", catcher) or nil
                for _, overlaySlot in ipairs({inOverlayButton, inOverlayCatcher}) do
                    if overlaySlot ~= nil then
                        safeCall(overlaySlot, "SetHorizontalAlignment", 0)
                        safeCall(overlaySlot, "SetVerticalAlignment", 0)
                    end
                end
                local inCell = inOverlayCatcher ~= nil
                        and safeCall(cell, "AddChild", overlay) or nil
                local inWrap = inCell ~= nil
                        and safeCall(state.wrapBox, "AddChild", cell) or nil
                attached = inWrap ~= nil
            end
            if attached then
                local record = {
                    row = row,
                    cell = cell,
                    button = button,
                    overlay = overlay,
                    catcher = catcher,
                    slot = slot,
                    index = index,
                    isEmpty = slotIsEmpty,
                    hidden = false,
                }
                state.icons[#state.icons + 1] = record
                applyEmptyVisibility(record)
            else
                pcall(function()
                    row:Unbind()
                end)
                if isValid(catcher) then
                    pcall(function()
                        catcher:UnbindEvents()
                    end)
                end
                for _, widget in ipairs({row, button, catcher, overlay, cell}) do
                    if isValid(widget) then
                        pcall(function()
                            widget:RemoveFromParent()
                        end)
                    end
                end
            end
        end
    end

    -- An empty grid over hidden vanilla rows is the worst possible failure
    -- shape; give the player the vanilla panel back instead.
    if #slots > 0 and #state.icons == 0 then
        return false, "no pal icons could be created for a non-empty roster"
    end
    log.info(string.format("grid rebuilt: %d of %d pal icons placed",
            #state.icons, #slots))
    return true, nil
end

local function recordByIndex(index)
    if index == nil then
        return nil
    end
    for _, record in ipairs(state.icons) do
        if record.index == index then
            return record
        end
    end
    return nil
end

-- Hover is polled on the cell button, the top-most hit-testable widget in
-- each cell; the pal widget's own internals may not be hit-testable.
local function hoveredRecord()
    for _, record in ipairs(state.icons) do
        if (isValid(record.catcher) and safeCall(record.catcher, "IsHovered") == true)
                or (isValid(record.cell)
                        and safeCall(record.cell, "IsHovered") == true) then
            return record
        end
    end
    return nil
end

local function updateHoverDetail()
    if state.disabled or not isValid(state.hoverPanel) then
        return
    end
    local hovered = hoveredRecord()
    state.hoveredIndex = hovered ~= nil and hovered.index or nil

    -- The hovered pal wins; with nothing hovered a pinned pal keeps the panel.
    local target = hovered or recordByIndex(state.pinnedIndex)
    -- An empty slot has no status to show: never bind the panel to one.
    -- Fail-open on a reflection error (nil), matching the menu gate.
    if target ~= nil and safeCall(target.slot, "IsEmpty") == true then
        target = nil
    end
    if target == nil then
        if state.boundIndex ~= nil then
            state.boundIndex = nil
            pcall(function()
                state.hoverPanel:SetVisibility(COLLAPSED)
            end)
        end
        return
    end
    if target.index == state.boundIndex then
        return
    end
    state.boundIndex = target.index
    -- The row binds slot events on Setup; unbind the previous pal first, the
    -- same order the game's own rebind flow uses.
    pcall(function()
        state.hoverPanel:Unbind()
    end)
    local ok = pcall(function()
        state.hoverPanel:Setup(target.slot)
    end)
    if ok then
        pcall(function()
            state.hoverPanel:SetVisibility(SELF_HIT_TEST_INVISIBLE)
        end)
    else
        state.boundIndex = nil
    end
end

-- Click action: the game's real pal-details screen via the HUD service (the
-- exact recipe PalCondenserDetails ships), with pin-the-panel as the
-- automatic fallback when the screen path fails.
local function openDetailScreen(record)
    local handle = slotHandle(record)
    if handle == nil then
        return false, "the pal's individual handle could not be read"
    end
    local utilOk, utility = pcall(StaticFindObject, "/Script/Pal.Default__PalUtility")
    if not utilOk or not isValid(utility) then
        return false, "PalUtility default object is unavailable"
    end
    local serviceOk, hudService = pcall(function()
        return utility:GetHUDService(state.task)
    end)
    if not serviceOk or not isValid(hudService) then
        return false, "the HUD service could not be resolved"
    end
    local classOk, parameterClass = pcall(StaticFindObject,
            "/Script/Pal.PalHUDDispatchParameter_MonsterDetail")
    if not classOk or not isValid(parameterClass) then
        return false, "the MonsterDetail dispatch parameter class is not loaded"
    end
    local paramOk, parameter = pcall(function()
        return hudService:CreateDispatchParameterForK2Node(state.task, parameterClass)
    end)
    if not paramOk or not isValid(parameter) then
        return false, "the MonsterDetail dispatch parameter could not be created"
    end
    local showOk, showError = pcall(function()
        parameter.IndividualHandle = handle
        parameter.IsEditable = true
        hudService:ShowCommonUI(SCREEN_MONSTER_DETAIL, parameter)
    end)
    if not showOk then
        return false, "ShowCommonUI failed: " .. tostring(showError)
    end
    return true, nil
end

local function onPalClicked(record)
    -- Two left-click detectors run in parallel (the catcher hook and the
    -- fallback IsPressed poll on the Button beneath it); collapse doubles.
    local now = os.clock()
    if record.lastClickAt ~= nil and now - record.lastClickAt < 0.3 then
        return
    end
    record.lastClickAt = now
    closeMenu()
    -- Clicking an empty slot has nothing to open or pin; same live check and
    -- fail-open behavior as the hover and menu gates.
    if safeCall(record.slot, "IsEmpty") == true then
        return
    end
    if config.openDetailsOnClick ~= false and not state.detailScreenUnavailable then
        -- The details screen manages its own input mode; end our cursor
        -- session first so the maintenance loop does not fight the menu.
        state.inspectToggled = false
        state.holdArmed = false
        applyCursor(nil)
        local ok, reason = openDetailScreen(record)
        if ok then
            log.info("opened pal details for grid slot " .. record.index)
            return
        end
        state.detailScreenUnavailable = true
        log.warn("pal details screen unavailable (" .. tostring(reason)
                .. "); falling back to pinning the status panel")
    end
    if state.pinnedIndex == record.index then
        state.pinnedIndex = nil
    else
        state.pinnedIndex = record.index
    end
    updateHoverDetail()
end

-- Clicks are polled as press edges on the cell and menu buttons, faster than
-- the maintenance cadence so a normal click is not missed: there is no
-- pure-Lua delegate path (native multicast Add needs a C++-backed bridge
-- UFunction). Right-click is a RightMouseButton press edge through the same
-- reflected IsInputKeyDown the hold key uses, targeted at the hovered cell -
-- readable because BOTH cursor modes now run GameAndUIEx (never UIOnlyEx,
-- which starves this poll; see the cursor state machine below).
local function clickTick()
    if state.disabled or state.cursorMode == nil then
        return
    end
    -- How far a hover fade may travel this frame. The first frame of a cursor session has no
    -- previous timestamp to measure from, and a frame after a long stall is clamped to the
    -- whole distance rather than allowed to overshoot.
    local now = os.clock()
    local elapsed = state.lastHoverTickAt ~= nil and (now - state.lastHoverTickAt) or nil
    local step = elapsed ~= nil and math.min(1, elapsed / TRANSITION_SECONDS) or 1
    state.lastHoverTickAt = now
    for _, record in ipairs(state.icons) do
        local pressed = isValid(record.button)
                and safeCall(record.button, "IsPressed") == true
        if pressed and not record.wasPressed then
            pcall(function()
                onPalClicked(record)
            end)
        end
        record.wasPressed = pressed
    end
    for _, item in ipairs(state.menuItems) do
        local pressed = state.menuTargetIndex ~= nil
                and isValid(item.button)
                and safeCall(item.button, "IsPressed") == true
        if pressed and not item.wasPressed then
            pcall(function()
                onMenuAction(item.action, recordByIndex(state.menuTargetIndex))
            end)
        end
        item.wasPressed = pressed
        -- Hover feedback fades over the design system's one transition duration rather
        -- than snapping: the ring and fill are written only while the fade is running, so
        -- a settled item is still read-only per frame.
        local hovered = state.menuTargetIndex ~= nil
                and isValid(item.button)
                and safeCall(item.button, "IsHovered") == true
        local target = hovered and 1 or 0
        local progress = item.hoverProgress or 0
        if progress ~= target then
            if progress < target then
                progress = math.min(target, progress + step)
            else
                progress = math.max(target, progress - step)
            end
            item.hoverProgress = progress
            paintMenuItem(item, progress)
        end
    end
end

local function recordByCatcher(widget)
    if not isValid(widget) then
        return nil
    end
    for _, record in ipairs(state.icons) do
        if isValid(record.catcher) and sameObject(record.catcher, widget) then
            return record
        end
    end
    return nil
end

-- Both clicks arrive from the catcher's hooked base-class internals: the
-- 2026-08-28 diagnostic proved PlayerInput polling cannot see mouse buttons
-- over UI (two physical right-clicks, one observed press, no observed
-- release), so Slate-layer detection through the game's own slot-button
-- widget is the only reliable source. The hooks fire for the game's own
-- Palbox slot buttons too; recordByCatcher filters to this grid's catchers.
local function registerCatcherHooks()
    if state.catcherHooksRegistered then
        return
    end
    local function dispatch(context, label, handler)
        pcall(function()
            local widget = context:get()
            local record = recordByCatcher(widget)
            log.info(label .. " hook fired; ours=" .. tostring(record ~= nil))
            if record ~= nil and state.cursorMode ~= nil then
                handler(record)
            end
        end)
    end
    local leftOk = pcall(RegisterHook, CATCHER_LEFT_HOOK, function(context)
        dispatch(context, "left-click", onPalClicked)
    end)
    local rightOk = pcall(RegisterHook, CATCHER_RIGHT_HOOK, function(context)
        dispatch(context, "right-click", function(record)
            if state.menuTargetIndex == record.index then
                closeMenu()
                return
            end
            -- No menu on an empty worker slot: every action needs a pal.
            -- Fail-open when the reflected call itself errors (nil), so a
            -- symbol change can never silently kill the menu on real pals.
            if safeCall(record.slot, "IsEmpty") == true then
                closeMenu()
                return
            end
            openMenu(record.index)
        end)
    end)
    state.catcherHooksRegistered = true
    if not (leftOk and rightOk) then
        log.warn("slot-button click hooks could not be registered; cell "
                .. "clicks fall back to the left-click poll only")
    end
end

-- Slate hover marks every widget on the path under the cursor, so the SizeBox
-- reads hovered for the whole grid subtree, scrollbar included. The context
-- menu counts as panel too: it sits OUTSIDE the grid SizeBox (to its left),
-- and without it here, mousing from the grid to the menu ended the sticky
-- session and closed the menu the moment the cursor crossed the gap
-- (observed in-game 2026-08-28 as needing to hold Alt all the way to the
-- menu); including it also keeps the weapon/aim/shoot panel guard active
-- over the menu.
local function panelHovered()
    if isValid(state.sizeBox) and safeCall(state.sizeBox, "IsHovered") == true then
        return true
    end
    if isValid(state.hoverPanel)
            and safeCall(state.hoverPanel, "IsHovered") == true then
        return true
    end
    if state.menuTargetIndex ~= nil and isValid(state.menuBox)
            and safeCall(state.menuBox, "IsHovered") == true then
        return true
    end
    return false
end

-- Cursor state machine: one cursor mode ("hold", GameAndUIEx) for both the
-- hold key and the persistent inspect toggle. The old on-panel escalation to
-- UIOnlyEx is gone (see applyCursor); the key state is therefore always
-- readable. An active session also stays alive while the cursor is over the
-- panel even after the hold key releases (the original verified UX: release
-- the hold key while inspecting and keep inspecting; observed missing 2026-08-28);
-- leaving the panel without the key down ends it.
local function desiredCursorMode()
    if state.inspectToggled then
        return "hold"
    end
    if isHoldKeyDown() then
        state.stickyMissTicks = 0
        return "hold"
    end
    if state.cursorMode ~= nil then
        if panelHovered() then
            state.stickyMissTicks = 0
            return "hold"
        end
        -- Grace window: the grid and the context menu are separate widgets
        -- with a gap between them, so crossing from one to the other reads
        -- as not-hovered for a tick or two; a key-released session only ends
        -- after several consecutive off-panel ticks.
        state.stickyMissTicks = state.stickyMissTicks + 1
        if state.stickyMissTicks < config.cursorGraceTicks then
            return "hold"
        end
    end
    state.stickyMissTicks = 0
    return nil
end

-- World clicks make the game viewport re-grab mouse capture, and captured
-- Slate hover goes dead, which silently kills escalation. Re-applying the
-- hold input mode releases the capture, but doing so is only safe while the
-- cursor is OFF the panel: an application resets hover state, and on-panel
-- that would break the very detection escalation needs.
local function refreshHoldCapture()
    if state.cursorMode ~= "hold" or panelHovered() then
        return
    end
    reapplyCursorInputMode()
end

-- NEVER poll-and-repair bShowMouseCursor per tick: PalInsight (installed)
-- also reads and WRITES that flag for its own Alt-hold feature, and a
-- per-tick re-assert here fought it in a cursor tug-of-war that re-applied
-- the input mode every tick - the documented Slate-state-reset storm
-- (observed in-game 2026-08-28: presses died before the click poll saw them,
-- clicks leaked to the game as pal commands, input wedged until Esc). Cursor
-- restoration is event-driven only: the right-click handler's single
-- re-apply, and refreshHoldCapture's slow off-panel cadence.

-- A co-op client's slot data lands via replication after the grid builds, so
-- a cell styled as empty at build time can turn out occupied (build-time
-- IsEmpty read stale-true: rows rendered at vanilla portrait scale, ~55% of
-- the cell, and stayed click-inert). The signature's empty bit catches this
-- when Set Pal Slots re-fires; this slow poll catches it when it does not.
-- Occupied never flips back to empty without a roster change the signature
-- already handles, so only empty-flagged records are polled.
local function refreshEmptyStyling()
    for _, record in ipairs(state.icons) do
        if record.isEmpty and safeCall(record.slot, "IsEmpty") == false then
            record.isEmpty = false
            styleCellRow(record.row, false)
            applyEmptyVisibility(record)
        end
    end
end

local tickCount = 0

local function maintenanceTick()
    if state.disabled or not isValid(state.task) then
        return
    end
    tickCount = tickCount + 1
    hideVanillaWidgets(state.task, false)
    if state.cursorMode == nil and not state.inspectToggled then
        -- Idle: the vanilla-row re-collapse above, one hold-key poll, and two
        -- cheap guards. Hover polling (70+ reflected calls a tick at 35
        -- pals), hit-test reapply and capture refresh matter only with a live
        -- cursor; keeping idle reflected-call volume minimal is deliberate
        -- crash-surface reduction (idle crashes reported 2026-08-28).
        -- The panel guard runs here too: an OS-level cursor (Alt+Tab) hovers
        -- and wheel-scrolls the grid with no cursor session, and without the
        -- guard the hotbar's raw-input wheel read swaps weapons whenever the
        -- ScrollBox sits at a scroll limit (reported 2026-08-30). Safe at
        -- idle: normal play holds mouse capture and captured Slate hover is
        -- dead, so panelHovered() is false the moment the game runs normally.
        setPanelGuard(panelHovered())
        applyCursor(desiredCursorMode())
        if tickCount % 8 == 0 then
            refreshEmptyStyling()
        end
        pcall(resummonTick)
        return
    end
    reapplyHitTesting()
    applyCursor(desiredCursorMode())
    setPanelGuard(panelHovered())
    if tickCount % 4 == 0 then
        refreshHoldCapture()
    end
    if tickCount % 8 == 0 then
        refreshEmptyStyling()
    end
    updateHoverDetail()
    pcall(resummonTick)
end

-- All recurring work runs from a RegisterHook on the always-on HUD root's
-- Blueprint Tick (WBP_PlayerUI_C:Tick): a native game-thread, per-frame
-- callback through the proven Set Pal Slots hook mechanism. LoopAsync +
-- ExecuteInGameThread is BANNED for recurring work in this mod: every
-- ExecuteInGameThread call registers a Lua registry ref from UE4SS's worker
-- thread, racing the game thread's ref consumption; at the click loop's
-- 15ms cadence that race wedged UE4SS's engine-tick queue within seconds
-- ("[Lua::Registry::get_function_ref] Ref was not function", observed
-- in-game 2026-08-28, killing every queued callback for the session), and
-- at the older 40/150ms cadences the same low-probability race is the
-- day's likeliest idle-crash root. Clicks are polled per frame (finer than
-- any loop cadence); the maintenance pass self-throttles on os.clock.
local FRAME_TICK_HOOK = "/Game/Pal/Blueprint/UI/WBP_PlayerUI.WBP_PlayerUI_C:Tick"

local function onFrameTick()
    if state.disabled then
        return
    end
    if state.cursorMode ~= nil and isValid(state.wrapBox) then
        clickTick()
    end
    local now = os.clock()
    if now - state.lastMaintenanceAt >= (config.maintenanceMs / 1000) then
        state.lastMaintenanceAt = now
        maintenanceTick()
    end
end

local function registerFrameTick()
    if state.frameTickRegistered then
        return
    end
    local ok, hookError = pcall(RegisterHook, FRAME_TICK_HOOK, function()
        pcall(onFrameTick)
    end)
    if ok then
        state.frameTickRegistered = true
        return
    end
    Grid.disable("the HUD frame tick could not be hooked: " .. tostring(hookError))
end

local function ensureBuilt(task)
    if isValid(state.task) and isValid(state.wrapBox)
            and sameObject(state.task, task) then
        return true
    end
    Grid.restoreVanilla()

    local parentCanvas = readProperty(task, "CanvasPanel_WorkerInfo")
    if not isValid(parentCanvas) then
        Grid.disable("CanvasPanel_WorkerInfo is missing from the Base Info panel")
        return false
    end
    local built, buildError = buildContainers(task, parentCanvas)
    if not built then
        Grid.disable(buildError)
        return false
    end
    state.task = task
    unblockHitTesting()
    hideVanillaWidgets(task, true)
    if not buildHoverPanel(task, parentCanvas) then
        log.warn("hover detail row could not be created; the grid still works without it")
    end
    if not buildMenu(task, parentCanvas) then
        log.warn("context menu could not be created; the grid still works without it")
    end
    registerFrameTick()
    registerAssignCapture()
    registerCatcherHooks()
    log.info("bounded grid containers attached to the Base Info panel")
    return true
end

-- Canvas construction fires before the Blueprint widget tree fills in its child
-- properties, so nothing is built here beyond remembering the canvas (its
-- lastInsideBaseCampID property is the menu actions' base camp id source, read
-- lazily); the real build happens lazily on the first Set Pal Slots call,
-- whose Context is the fully initialized task widget.
function Grid.onCanvasConstructed(canvas)
    if state.disabled then
        return
    end
    Grid.restoreVanilla()
    -- The language is read here, not at load: the internationalization library is only
    -- reachable once the game is up, and a player who changes the game's language sees the
    -- menu follow it the next time the panel is built.
    pcall(function()
        I18n.refresh(config.language)
    end)
    state.canvas = canvas
end

-- Stand models are stored at construction and read only at click time
-- (matched to the current base by GetBaseCampIdBelongTo); the callback body
-- makes no engine calls, so it is safe on whatever thread fires it.
function Grid.onStandModelConstructed(model)
    if model == nil then
        return
    end
    state.standModels[#state.standModels + 1] = model
end




function Grid.onPalSlots(task, slots)
    if state.disabled or not isValid(task) then
        return
    end
    if not ensureBuilt(task) then
        return
    end
    -- Kept so a settings change can rebuild the panel that is already on screen without
    -- waiting for the game's next delivery.
    state.slots = slots
    local signature = rosterSignatureOf(slots)
    if signature == state.rosterSignature then
        hideVanillaWidgets(task, false)
        return
    end
    local ok, populateError = populateIcons(task, slots)
    if not ok then
        Grid.disable(populateError)
        return
    end
    state.rosterSignature = signature
    -- A roster change means a different base or a changed crew; a scroll
    -- offset kept from the previous roster would show empty space.
    safeCall(state.scrollBox, "ScrollToStart")
    hideVanillaWidgets(task, false)
end

function Grid.scrollBy(pixels)
    if state.disabled or not isValid(state.scrollBox) then
        return
    end
    ExecuteInGameThread(function()
        pcall(function()
            local current = state.scrollBox:GetScrollOffset()
            local target = current + pixels
            if target < 0 then
                target = 0
            end
            state.scrollBox:SetScrollOffset(target)
        end)
    end)
end

-- Persistent inspect toggle: the same GameAndUIEx cursor mode as the hold,
-- just not tied to the key staying down. The UE4SS keybind fires regardless
-- of the game's input mode, so the same key always exits.
function Grid.toggleInspect()
    if state.disabled or not isValid(state.task) then
        return
    end
    ExecuteInGameThread(function()
        pcall(function()
            resolveWidgetLibrary()
            state.inspectToggled = not state.inspectToggled
            if not state.inspectToggled then
                -- If the hold key happens to be down at toggle-off, require
                -- one observed release before hold re-frees the cursor.
                state.holdArmed = false
                applyCursor(nil)
            else
                applyCursor("hold")
            end
            log.info(state.inspectToggled
                    and "inspect mode on: cursor stays free until toggled off"
                    or "inspect mode off")
        end)
    end)
end

-- A settings change lands on the panel already on screen. The containers, the hover row, the
-- cells and the menu all read their geometry and their labels once, while they are built, so
-- the panel is rebuilt from the roster it is already showing rather than left until the game's
-- next delivery. Everything else the settings govern is read where it is used and needs no
-- rebuild. Game thread only.
function Grid.applyConfig()
    if state.disabled then
        return false
    end
    -- The hold key may have been changed away from one IsInputKeyDown refused.
    state.holdUnavailable = false
    pcall(function()
        I18n.refresh(config.language)
    end)
    local task = state.task
    local slots = state.slots
    if not isValid(task) or slots == nil then
        return false
    end
    for _, slot in ipairs(slots) do
        if not isValid(slot) then
            -- A stale roster would rebuild into an empty grid, which turns the mod off; the
            -- game's next delivery rebuilds with the new settings instead.
            state.rosterSignature = nil
            return false
        end
    end
    local inspecting = state.inspectToggled
    Grid.restoreVanilla()
    Grid.onPalSlots(task, slots)
    state.inspectToggled = inspecting
    return true
end

function Grid.init(effectiveConfig, logger)
    config = effectiveConfig
    log = logger
end

return Grid
