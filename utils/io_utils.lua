--- @type Mq
local mq = require('mq')

local actions = {}

local app_name = 'finalfugue'

function actions.file_exists(name)
	local f = io.open(name, "r")
	if f ~= nil then io.close(f) return true else return false end
end

function actions.create_dir(directoryPath)
    os.execute('mkdir "'..directoryPath:gsub('/','\\')..'" 1>nul: 2>&1')
end

function actions.ensure_config_dir()
	local configDir = actions.get_config_dir()
	if (actions.file_exists(configDir)) then return end
	actions.create_dir(configDir)
end

function actions.get_lua_dir()
    return string.format('%s\\%s', mq.luaDir, app_name):gsub('\\', '/'):lower()
end

function actions.get_lua_file_path(filename)
    return string.format('%s\\%s', actions.get_lua_dir(), filename)
end

function actions.get_config_dir()
    return string.format('%s\\%s', mq.configDir, app_name):gsub('\\', '/'):lower()
end

function actions.get_config_file_path(filename)
    return string.format('%s\\%s', actions.get_config_dir(), filename)
end

function actions.get_root_config_dir()
    return string.format('%s', mq.configDir):gsub('\\', '/'):lower()
end

function actions.get_root_config_file_path(filename)
    return string.format('%s\\%s', actions.get_root_config_dir(), filename)
end

return actions