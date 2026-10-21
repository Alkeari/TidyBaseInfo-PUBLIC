local config = require("config")
local log = require("logger")
local grid = require("grid")
local livecfg = require("livecfg")

local MOD_VERSION = "1.4.0"

local CANVAS_CLASS_PATH = "/Script/Pal.PalUIInsideBaseCampCanvas"
local SET_PAL_SLOTS_PATH = "/Game/Pal/Blueprint/UI/UserInterface/IngameMenu/Task/"
        .. "WBP_IngameMenu_Task_Simple.WBP_IngameMenu_Task_Simple_C:Set Pal Slots"

log.info("loading Tidy Base Info v" .. MOD_VERSION)

grid.init(config, log)

local slotsHookRegistered = false

local function extractSlots(slotsParam)
    local arrayOk, array = pcall(function()
        return slotsParam:get()
    end)
    if not arrayOk or array == nil then
        return nil
    end

    local slots = {}
    local forEachOk = pcall(function()
        array:ForEach(function(_, element)
            local elementOk, slot = pcall(function()
                return element:get()
            end)
            if elementOk and slot ~= nil then
                slots[#slots + 1] = slot
            end
        end)
    end)
    if forEachOk then
        return slots
    end

    -- Fallback for a TArray wrapper without ForEach: plain index access.
    slots = {}
    local indexOk = pcall(function()
        for index = 1, #array do
            local slot = array[index]
            if slot ~= nil then
                slots[#slots + 1] = slot
            end
        end
    end)
    if indexOk then
        return slots
    end
    return nil
end

local function registerSlotsHook()
    if slotsHookRegistered then
        return
    end
    local ok, hookError = pcall(function()
        -- A single-callback RegisterHook on a Blueprint-path function fires
        -- after the function body, so the vanilla population has already run
        -- and cannot stomp what the grid changes here.
        RegisterHook(SET_PAL_SLOTS_PATH, function(context, slotsParam)
            local taskOk, task = pcall(function()
                return context:get()
            end)
            if not taskOk or task == nil then
                return
            end
            local slots = extractSlots(slotsParam)
            if slots == nil then
                grid.disable("the Slots argument of Set Pal Slots could not be read")
                return
            end
            pcall(function()
                grid.onPalSlots(task, slots)
            end)
        end)
    end)
    if ok then
        slotsHookRegistered = true
        log.info("Set Pal Slots hook registered")
    else
        grid.disable("Set Pal Slots could not be hooked: " .. tostring(hookError))
    end
end

local notifyOk, notifyError = pcall(
        NotifyOnNewObject,
        CANVAS_CLASS_PATH,
        function(canvas)
            ExecuteInGameThread(function()
                pcall(function()
                    registerSlotsHook()
                    grid.onCanvasConstructed(canvas)
                end)
            end)
        end)
if not notifyOk then
    grid.disable("the Base Info canvas observer could not be registered: "
            .. tostring(notifyError))
    return
end

-- The Monitoring Stand's concrete model, collected for the Assign action's
-- cold-start path. A 2026-08-28 companion ProcessEvent capture of a real
-- "[C] Fixed assignment management" press showed the native flow calling
-- OnTriggerInteract on THIS class (not PalMapObjectBaseCampWorkerDirectorModel)
-- through ProcessEvent, with the board built inside the call.
local standNotifyOk = pcall(
        NotifyOnNewObject,
        "/Script/Pal.PalMapObjectBaseCampPassiveWorkHardModel",
        function(model)
            pcall(function()
                grid.onStandModelConstructed(model)
            end)
        end)
if not standNotifyOk then
    log.warn("the Monitoring Stand model observer could not be registered; "
            .. "Assign needs one stand board visit per base per session")
end

-- Scroll and inspect run from keybinds because normal gameplay has no free
-- mouse cursor; inspect frees one so hover detail becomes reachable.
local KEYBINDS = {
    {name = "scrollDown", setting = "scrollDownKey", label = "scroll down",
        run = function()
            grid.scrollBy(config.scrollStepPx)
        end},
    {name = "scrollUp", setting = "scrollUpKey", label = "scroll up",
        run = function()
            grid.scrollBy(-config.scrollStepPx)
        end},
    {name = "inspect", setting = "inspectKey", label = "inspect toggle",
        run = function()
            grid.toggleInspect()
        end},
}

-- The player's chosen modifier, or nil for a bare keybind. "CTRL" is the name the settings file
-- and every mod-options screen use; the loader's own enum spells it CONTROL.
local MODIFIER_NAMES = {ALT = "ALT", CTRL = "CONTROL", CONTROL = "CONTROL", SHIFT = "SHIFT"}

-- RegisterKeyBind on a mouse button wedges UE4SS's engine-tick Lua for the whole session, so a
-- mouse name in the settings is refused rather than registered (category pitfall).
local MOUSE_KEYS = {LEFT_MOUSE_BUTTON = true, RIGHT_MOUSE_BUTTON = true,
    MIDDLE_MOUSE_BUTTON = true, XBUTTON_ONE = true, XBUTTON_TWO = true}

local function chosenModifier()
    local name = tostring(config.keybindModifier or "ALT"):upper()
    if name == "" or name == "NONE" then
        return nil, ""
    end
    local enumName = MODIFIER_NAMES[name]
    local value = enumName ~= nil and ModifierKey[enumName] or nil
    if value == nil then
        log.warn("keybindModifier is '" .. tostring(config.keybindModifier)
                .. "', which is not one of NONE, CTRL, SHIFT or ALT; using ALT")
        return ModifierKey.ALT, "Alt+"
    end
    return value, name:sub(1, 1) .. name:sub(2):lower() .. "+"
end

-- The key combination each action answers to right now, and every combination handed to
-- RegisterKeyBind this session. UE4SS has no way to take a keybind back, so a settings change
-- registers the new combination and the old registration turns inert: every callback checks
-- that the settings still name its own combination before it acts.
local activeBind = {}
local registeredBind = {}
local activeModifierLabel = ""

local function hotkeyLabel(keyName, modifierLabel)
    if keyName == nil or keyName == "" then
        return "off"
    end
    return (modifierLabel or "") .. keyName
end

local function registerBind(entry, signature, keyValue, modifierValue)
    if registeredBind[signature] then
        return true
    end
    local callback = function()
        if activeBind[entry.name] == signature then
            entry.run()
        end
    end
    local ok
    if modifierValue == nil then
        ok = pcall(RegisterKeyBind, keyValue, callback)
    else
        ok = pcall(RegisterKeyBind, keyValue, {modifierValue}, callback)
    end
    if ok then
        registeredBind[signature] = true
    end
    return ok
end

-- Applies the keybind settings as they read right now. Called at boot and again after every
-- live settings change; a combination that is already registered is left alone.
local function refreshKeybinds(firstRun)
    local modifierValue, modifierLabel = chosenModifier()
    activeModifierLabel = modifierLabel
    for _, entry in ipairs(KEYBINDS) do
        local keyName = config[entry.setting]
        keyName = type(keyName) == "string" and keyName or ""
        local previous = activeBind[entry.name]
        local signature = nil
        if keyName == "" then
            if previous ~= nil or firstRun then
                log.info(entry.label .. " keybind is turned off in the settings")
            end
        elseif MOUSE_KEYS[keyName:upper()] then
            log.warn(entry.label .. " keybind names a mouse button ('" .. keyName
                    .. "'), which cannot be bound; it is turned off")
        elseif Key[keyName] == nil then
            log.warn(entry.label .. " keybind names an unknown key ('" .. keyName .. "')")
        else
            signature = hotkeyLabel(keyName, modifierLabel)
            if not registerBind(entry, signature, Key[keyName], modifierValue) then
                log.warn(entry.label .. " keybind could not be registered (" .. signature .. ")")
                signature = nil
            end
        end
        activeBind[entry.name] = signature
        if signature ~= nil and signature ~= previous and previous ~= nil then
            log.info(entry.label .. " keybind is now " .. signature)
        end
    end
end

refreshKeybinds(true)

-- The settings file is watched from here on: an edit made in a text editor, or by any in-game
-- settings editor that writes the file, is merged into the table every module already holds,
-- the keybinds are re-read, and the panel is rebuilt around the new values. Nothing in this mod
-- knows or cares which editor wrote the file.
livecfg.start(config, log, function()
    refreshKeybinds(false)
    grid.applyConfig()
end)

-- Right-click detection lives in grid.lua as RegisterHook on the slot-button
-- base class's click internals, fired by concrete catcher widgets in each
-- cell. NOT a keybind (RegisterKeyBind on a mouse button wedges UE4SS's
-- engine-tick queue) and NOT an IsInputKeyDown poll (PlayerInput cannot see
-- mouse buttons over UI); both failure modes observed in-game 2026-08-28.

local bootModifierLabel = activeModifierLabel

log.info("Tidy Base Info ready: grid bounded to " .. config.maxGridHeight
        .. "px; hold " .. (config.inspectHoldKey ~= "" and config.inspectHoldKey or "off")
        .. " to free the cursor for hover and wheel scroll, "
        .. hotkeyLabel(config.scrollDownKey, bootModifierLabel) .. "/"
        .. hotkeyLabel(config.scrollUpKey, bootModifierLabel)
        .. " scrolls from the keyboard, "
        .. hotkeyLabel(config.inspectKey, bootModifierLabel)
        .. " toggles inspect mode persistently")
