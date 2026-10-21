-- Player-facing strings in the game's own language. `Assets\lang\en.ini` is always loaded
-- first; the file for the language the game reports (KismetInternationalizationLibrary's
-- GetCurrentLanguage: "en", "ja", "zh-Hans", "pt-BR", "es-MX", ...) overlays it, so a key a
-- translation leaves out falls back to English and a missing file falls back whole. The ini
-- files are generated from tools\lang by build_lang.py; never edit them by hand.
local I18n = {}

I18n.language = "en"

local strings = {}

-- The last resort when no language file can be read at all (a broken install, a package missing
-- its Assets folder): English text rather than a raw key on a menu the player is looking at.
-- tools\lang\build_lang.py fails the build when this table and the English source disagree.
I18n.fallback = {
    -- The right-click action that moves a pal to your Palbox.
    menu_palbox = "Send to Palbox",

    -- The right-click action that sends a pal to the Palbox and straight back to the base.
    menu_resummon = "Resummon",

    -- The right-click action that opens the base's fixed assignment board.
    menu_assign = "Assign",

    -- The tooltip on the Send to Palbox action.
    tip_menu_palbox = "Sends this pal to your Palbox.",

    -- The tooltip on the Resummon action.
    tip_menu_resummon = "Sends this pal to the Palbox and straight back to work.",

    -- The tooltip on the Assign action.
    tip_menu_assign = "Opens this base's fixed assignment board.",

    -- The tooltip on a pal in the grid while a click opens the details screen.
    tip_cell_details = "Opens this pal's details screen, and right-click for quick actions.",

    -- The tooltip on a pal in the grid while a click pins the status row instead.
    tip_cell_pin = "Pins this pal's name and status under the grid, and right-click for quick actions.",

    -- The tooltip on an empty worker slot in the grid.
    tip_cell_empty = "This worker slot is empty.",
}

local LIBRARY_PATH = "/Script/Engine.Default__KismetInternationalizationLibrary"

local function scriptDirectory()
    local source = debug.getinfo(1, "S").source or ""
    source = source:sub(1, 1) == "@" and source:sub(2) or source
    return source:match("^(.*)[/\\][^/\\]+$") or "."
end

local function readFile(path)
    local file = io.open(path, "rb")
    if not file then
        return nil
    end
    local content = file:read("a")
    file:close()
    return content
end

function I18n.languageDirectory()
    local scripts = scriptDirectory()
    local modRoot = scripts:match("^(.*)[/\\][^/\\]+$") or scripts
    return modRoot .. "\\Assets\\lang"
end

-- key=value per line, "#" comments, UTF-8 with or without a BOM; "\n" in a value is a newline.
function I18n.parse(content)
    local out = {}
    if content == nil then
        return out
    end
    if content:sub(1, 3) == "\239\187\191" then
        content = content:sub(4)
    end
    for line in (content .. "\n"):gmatch("(.-)\r?\n") do
        if line ~= "" and line:sub(1, 1) ~= "#" then
            local key, value = line:match("^([^=]+)=(.*)$")
            if key ~= nil then
                out[key:match("^%s*(.-)%s*$")] = (value:match("^%s*(.-)%s*$"):gsub("\\n", "\n"))
            end
        end
    end
    return out
end

-- The files worth trying for a reported code, most specific first: "es-MX" tries es-MX then
-- es; "zh-Hans" has no bare parent file and tries only itself.
function I18n.candidates(code)
    local list = {}
    local seen = {}
    local function add(name)
        if name ~= nil and name ~= "" and not seen[name] then
            seen[name] = true
            list[#list + 1] = name
        end
    end
    code = tostring(code or ""):match("^%s*(.-)%s*$")
    add(code)
    local base = code:match("^([%a]+)[%-_]")
    if base ~= nil and base:lower() ~= "zh" then
        add(base)
    end
    return list
end

-- What the game reports, or "en" when the library is unreachable (an engine that renamed it,
-- or a call made before the game is up).
function I18n.detectLanguage()
    if type(StaticFindObject) ~= "function" then
        return "en"
    end
    local ok, code = pcall(function()
        local library = StaticFindObject(LIBRARY_PATH)
        if library == nil or not library:IsValid() then
            return nil
        end
        return library:GetCurrentLanguage():ToString()
    end)
    if ok and type(code) == "string" and code ~= "" then
        return code
    end
    return "en"
end

-- Loads English, then the overlay for `code`. Returns the code whose file was found ("en"
-- when none of the candidates exists).
function I18n.load(directory, code)
    directory = directory or I18n.languageDirectory()
    strings = I18n.parse(readFile(directory .. "\\en.ini"))
    I18n.language = "en"
    for _, candidate in ipairs(I18n.candidates(code)) do
        if candidate ~= "en" then
            local content = readFile(directory .. "\\" .. candidate .. ".ini")
            if content ~= nil then
                for key, value in pairs(I18n.parse(content)) do
                    strings[key] = value
                end
                I18n.language = candidate
                break
            end
        end
    end
    return I18n.language
end

-- `preferred` is the player's own language setting: anything but nil, "" or "auto" wins over
-- what the game reports, so the mod can be read in one language while the game runs in another.
function I18n.refresh(preferred)
    local code = nil
    if type(preferred) == "string" then
        code = preferred:match("^%s*(.-)%s*$")
    end
    if code == nil or code == "" or code:lower() == "auto" then
        code = I18n.detectLanguage()
    end
    return I18n.load(nil, code)
end

-- The string for `key` with every {name} replaced from `vars`; the key itself when unknown, so
-- a missing entry shows up in the UI instead of blanking a label.
function I18n.t(key, vars)
    local text = strings[key] or I18n.fallback[key] or key
    if vars ~= nil then
        text = text:gsub("{(%w+)}", function(name)
            local value = vars[name]
            return value ~= nil and tostring(value) or ("{" .. name .. "}")
        end)
    end
    return text
end

return I18n
