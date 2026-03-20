
-- others_actions
-- Called to initiate actions on individual characters
---------------------------
local Version = "1.0"

local mq = require('mq')
local logger = require('utils.logger')
local mq_utils = require('utils.mq_utils')
local tower = require('tower_travel')


local args = {...}

local function ZoneIntoMission(level)
    local level_details = tower.GetLevelDetails(level)
    logger.info('\awRunning to level \ag%s\aw and zoning into mission \at%s', level, level_details.mission.name)
    tower.MoveToLevel(level)
    mq_utils.TravelViaDoor(level_details.mission.switch_id, level_details.mission.mission_zone, false)
end

local function process(command, arg1)
    if (command == 'zoneto') then
        tower.Initialize()
        local target_level = tonumber(arg1)
        if (target_level ~= nil) then
            ZoneIntoMission(target_level)
        end
    elseif (command == 'runto') then
        tower.MoveToLevel(arg1)
    end
end


local function bind_command(command, floor)
    process(command, floor)
end

mq.bind('/tower_o', bind_command)

local command = string.lower(args[1])
local arg = tonumber(args[2])
process(command, arg)
