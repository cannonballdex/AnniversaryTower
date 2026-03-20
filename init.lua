-- AnniversaryTower
---------------------------
local Version = "1.29"

local mq = require('mq')
local lip = require('lib.LIP')
require('ImGui')
local main_ui = require('anniversarytower_ui')
local engine = require('engine')

local ffi = require('ffi')

ffi.cdef[[
typedef unsigned long DWORD;
typedef int BOOL;
DWORD GetFileAttributesW(const wchar_t* lpFileName);
BOOL CreateDirectoryW(const wchar_t* lpPathName, void* lpSecurityAttributes);
]]

local kernel32 = ffi.load('kernel32')
local INVALID_FILE_ATTRIBUTES = 0xFFFFFFFF

local function to_wide(str)
    local buf = ffi.new('wchar_t[?]', #str + 1)
    for i = 1, #str do
        buf[i - 1] = str:byte(i)
    end
    buf[#str] = 0
    return buf
end

local function dir_exists(path)
    local attrs = kernel32.GetFileAttributesW(to_wide(path))
    return attrs ~= INVALID_FILE_ATTRIBUTES
end

local function ensure_config_dir()
    local config_root = mq.configDir:gsub('/', '\\')
    local dir = config_root .. '\\AnniversaryTower'

    if not dir_exists(dir) then
        local ok = kernel32.CreateDirectoryW(to_wide(dir), nil)
        if ok == 0 and not dir_exists(dir) then
            error('Failed to create config directory: ' .. dir)
        end
    end
end

---------------------------
--- CHANGE these per your desires
local DebugOutput = false
---------------------------------

printf('AnniversaryTower.  Version (%s)', Version)

ensure_config_dir()

main_ui.InitializeUi(true)
engine.Main()

while Open do
    mq.delay(500)
    mq.doevents()
end