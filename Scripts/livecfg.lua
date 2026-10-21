-- Live settings. `Scripts\config.lua` is re-read from disk on a timer, so an edit made in a
-- text editor, or by any in-game settings editor that writes the file, takes effect without
-- relaunching the game. The settings table handed to `start` is updated in place and never
-- replaced, because every other module holds the table it was given at boot.
local Livecfg = {}

local config = nil
local log = nil

-- The loop wakes on a short fixed beat instead of on the player's interval because LoopAsync's
-- period is fixed when it is registered; `liveReloadSeconds` then decides how often a beat
-- actually reads the file, which is what lets that setting change live along with the rest.
local BASE_TICK_MS = 500

local DEFAULT_SECONDS = 2
local MAX_SECONDS = 60

local defaults = nil
local watchPath = nil
local lastText = nil
local lastReadAt = 0
local pendingConfig = nil
local pendingWarning = nil
local lastWarning = nil
local onApply = nil

local function scriptDirectory()
    local source = debug.getinfo(1, "S").source or ""
    source = source:sub(1, 1) == "@" and source:sub(2) or source
    return source:match("^(.*)[/\\][^/\\]+$") or "."
end

-- The settings file next to this one, so nothing depends on where the mod is installed.
function Livecfg.configPath()
    return scriptDirectory() .. "\\config.lua"
end

function Livecfg.readFile(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local ok, content = pcall(function()
        return file:read("a")
    end)
    file:close()
    if not ok then
        return nil
    end
    return content
end

-- A number of seconds the loop can act on: anything that is not a number falls back to the
-- shipped default, and the range is the one documented above the setting.
function Livecfg.seconds(value)
    if type(value) ~= "number" or value ~= value then
        return DEFAULT_SECONDS
    end
    if value < 0 then
        return 0
    end
    if value > MAX_SECONDS then
        return MAX_SECONDS
    end
    return value
end

-- The settings file is data, so it is run in an empty environment: a chunk that reaches for a
-- global gets nil rather than the mod's own state, and only a returned table is accepted.
function Livecfg.parse(text)
    if type(text) ~= "string" then
        return nil, "the file could not be read"
    end
    local chunk, compileError = load(text, "@config.lua", "t", {})
    if chunk == nil then
        return nil, tostring(compileError)
    end
    local ok, result = pcall(chunk)
    if not ok then
        return nil, tostring(result)
    end
    if type(result) ~= "table" then
        return nil, "the file did not return a settings table"
    end
    return result, nil
end

-- Copies `source` over the live table. A setting the file dropped returns to its boot value; a
-- setting whose type changed keeps the value already in force, because the rest of the mod
-- reads these as plain scalars of a known type. Returns the names that changed and how many
-- were refused.
function Livecfg.merge(target, base, source)
    local changed = {}
    local refused = 0
    for key, bootValue in pairs(base) do
        local value = source[key]
        if value == nil then
            value = bootValue
        elseif type(value) ~= type(bootValue) then
            refused = refused + 1
            value = target[key]
        end
        if target[key] ~= value then
            changed[#changed + 1] = key
            target[key] = value
        end
    end
    table.sort(changed)
    return changed, refused
end

-- Runs on UE4SS's worker thread: file reading and plain Lua only, never a UObject and never a
-- game call. Anything it finds is left for the game thread to act on.
function Livecfg.poll(now)
    now = now or os.clock()
    local interval = Livecfg.seconds(config and config.liveReloadSeconds)
    if interval <= 0 or now - lastReadAt < interval then
        return false
    end
    lastReadAt = now
    local text = Livecfg.readFile(watchPath)
    if text == nil or text == "" then
        -- A file caught mid-write reads as missing or empty; the settings in force stay.
        pendingWarning = "the settings file could not be read; the settings already in force "
                .. "stay as they are"
        return true
    end
    if text == lastText then
        return false
    end
    local parsed, reason = Livecfg.parse(text)
    if parsed == nil then
        pendingWarning = "the settings file could not be read: " .. tostring(reason)
                .. "; the settings already in force stay as they are"
        return true
    end
    -- Only text that parsed becomes the baseline, so a half-written file is read again on the
    -- next beat instead of being swallowed.
    lastText = text
    pendingConfig = parsed
    return true
end

-- Runs on the game thread. Applies whatever the poll left behind; safe to call at any time.
function Livecfg.pump()
    local warning = pendingWarning
    pendingWarning = nil
    if warning ~= nil and warning ~= lastWarning then
        lastWarning = warning
        log.warn(warning)
    end
    local parsed = pendingConfig
    pendingConfig = nil
    if parsed == nil then
        return false
    end
    lastWarning = nil
    local changed, refused = Livecfg.merge(config, defaults, parsed)
    if #changed == 0 and refused == 0 then
        return false
    end
    log.info(string.format("settings reloaded: %d changed (%s)%s", #changed,
            table.concat(changed, ", "),
            refused > 0 and string.format("; %d ignored for a changed value type", refused)
                    or ""))
    if onApply ~= nil and #changed > 0 then
        pcall(onApply, changed)
    end
    return true
end

-- Starts watching. `path` defaults to the mod's own settings file. Returns whether the watch
-- is running: it is off when the player set the interval to 0, and unavailable outside the
-- game, where there is no loop to run it on.
function Livecfg.start(effectiveConfig, logger, applyCallback, path)
    config = effectiveConfig
    log = logger
    onApply = applyCallback
    watchPath = path or Livecfg.configPath()
    defaults = {}
    for key, value in pairs(config) do
        defaults[key] = value
    end
    lastText = Livecfg.readFile(watchPath)
    lastReadAt = os.clock()
    pendingConfig = nil
    pendingWarning = nil
    lastWarning = nil

    -- Nothing reads the file while the interval is 0, which is why switching it back on only
    -- takes effect at the next launch: there is no reader left to notice.
    if Livecfg.seconds(config.liveReloadSeconds) <= 0 then
        log.info("the settings file is not watched (liveReloadSeconds is 0); a change needs a "
                .. "relaunch until it is set back above 0")
        return false
    end
    if type(LoopAsync) ~= "function" then
        log.warn("the settings file cannot be watched: LoopAsync is unavailable")
        return false
    end
    local ok = pcall(LoopAsync, BASE_TICK_MS, function()
        -- One ExecuteInGameThread per edit the player actually makes. The mod's ban on
        -- LoopAsync plus ExecuteInGameThread covers RECURRING cross-thread work;
        -- this is the same rare, user-triggered shape as a keybind press, and the beat itself
        -- queues nothing when the file has not changed.
        local pollOk, queued = pcall(Livecfg.poll, os.clock())
        if pollOk and queued == true and type(ExecuteInGameThread) == "function" then
            pcall(ExecuteInGameThread, function()
                pcall(Livecfg.pump)
            end)
        end
    end)
    if not ok then
        log.warn("the settings file cannot be watched: the reload loop could not be started")
        return false
    end
    log.info(string.format("watching the settings file every %s second(s) for live changes",
            tostring(Livecfg.seconds(config.liveReloadSeconds))))
    return true
end

return Livecfg
