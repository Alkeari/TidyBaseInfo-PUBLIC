local Logger = {}

local PREFIX = "[TidyBaseInfo]"

local function write(level, message)
    print(string.format("%s [%s] %s\n", PREFIX, level, tostring(message)))
end

function Logger.info(message)
    write("INFO", message)
end

function Logger.warn(message)
    write("WARN", message)
end

function Logger.error(message)
    write("ERROR", message)
end

return Logger
