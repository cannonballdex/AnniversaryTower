-- AnniversaryTower\coth
-- Called by a mage to COTH the group main assist
-- (Currently, assuming that is the script caller.)
-- TODO: Communicate Spawn.ID() across the channel
---------------------------
local Version = "1.0"


local mq = require('mq')
local logger = require('utils.logger')
local args = {...}

local actions = {}

actions.Levels = {
    ["01"] = {
        level = 1,
        switch_id = 20,
        teleporter_id = 15,
        short_name = 'base',
    },
    ["02"] = {
        level = 2,
        switch_id = 1,
        teleporter_id = nil,
        closest_teleporter_id = 15,
        closest_teleporter_level = 1,
        short_name = 'sand',
        mission = {
            name = "Oasis of Sand",
            mission_zone = 'anniversarytower_errandone',
            achievement_id = 200144,
        },
        key = {
            name = 'Repaired Key of Sand',
            achievement = 200143,
            id = 161891,
            task = {
                name = 'Broken Key of Sands',
                request_item_id = 161947,
                container_id = 161887,
                item1_blade_id = 161888,
                item2_bow_id = 161889,
                item3_biting_id = 161890,
                zone = 'southro'
            }
        }
    },
    ["03"] = {
        level = 3,
        switch_id = 2,
        teleporter_id = nil,
        closest_teleporter_id = 16,
        closest_teleporter_level = 4,
        short_name = 'lava',
        mission = {
            name = "Oasis of Lava",
            switch = 2,
            mission_zone = 'anniversarytower_errandone',
            achievement_id = 200146,
        },
        key = {
            name = 'Repaired Key of Lava',
            achievement = 200145,
            id = 161896,
            task = {
                name = 'Broken Key of Lava',
                request_item_id = 161948,
                container_id = 161892,
                item1_blade_id = 161893,
                item2_bow_id = 161894,
                item3_biting_id = 161895,
                additional_item_ids = {
                    161959
                },
                zone = 'lavastorm'
            }
        }
    },
    ["04"] = {
        level = 4,
        switch_id = 4,
        teleporter_id = 16,
        short_name = 'forest',
        mission = {
            name = "Oasis of Forests",
            mission_zone = 'anniversarytower_errandone',
            achievement_id = 200148,
        },
        key = {
            name = 'Repaired Key of Forests',
            achievement = 200147,
            id = 161901,
            task = {
                name = 'Broken Key of Forests',
                request_item_id = 161949,
                container_id = 161897,
                item1_blade_id = 161898,
                item2_bow_id = 161899,
                item3_biting_id = 161900,
                zone = 'gfaydark'
            }
        }
    },
    ["05"] = {
        level = 5,
        switch_id = 5,
        teleporter_id = nil,
        closest_teleporter_id = 16,
        closest_teleporter_level = 4,
        short_name = 'frost',
        mission = {
            name = "Oasis of Frost",
            mission_zone = 'anniversarytower_errandtwo',
            achievement_id = 200150,
        },
        key = {
            name = 'Repaired Key of Frost',
            achievement = 200149,
            id = 161921,
            task = {
                name = 'Broken Key of Frost',
                request_item_id = 161953,
                container_id = 161917,
                item1_blade_id = 161918,
                item2_bow_id = 161919,
                item3_biting_id = 161920,
                additional_item_ids = {
                    162066,
                    162067,
                    162068,
                },
                zone = 'everfrost'
            }
        }
    },
    ["06"] = {
        level = 6,
        switch_id = 6,
        teleporter_id = nil,
        closest_teleporter_id = 17,
        closest_teleporter_level = 7,
        short_name = 'sky',
        mission = {
            name = "Oasis of Sky",
            mission_zone = 'anniversarytower_errandone',
            achievement_id = 200152,
        },
        key = {
            name = 'Repaired Key of Sky',
            achievement = 200151,
            id = 161911,
            task = {
                name = 'Broken Key of Sky',
                request_item_id = 161951,
                container_id = 161907,
                item1_blade_id = 161908,
                item2_bow_id = 161909,
                item3_biting_id = 161910,
                zone = 'lakerathe'
            }
        }
    },
    ["07"] = {
        level = 7,
        switch_id = 7,
        teleporter_id = 17,
        short_name = 'steam',
        mission = {
            name = "Oasis of Steam",
            mission_zone = 'anniversarytower_errandone',
            achievement_id = 200154,
        },
        key = {
            name = 'Repaired Key of Steam',
            achievement = 200153,
            id = 161931,
            task = {
                name = 'Broken Key of Steam',
                request_item_id = 161955,
                container_id = 161927,
                item1_blade_id = 161928,
                item2_bow_id = 161929,
                item3_biting_id = 161930,
                zone = 'steamfontmts'
            }
        }
    },
    ["08"] = {
        level = 8,
        switch_id = 8,
        teleporter_id = nil,
        closest_teleporter_id = 17,
        closest_teleporter_level = 7,
        short_name = 'jungle',
        mission = {
            name = "Oasis of the Jungle",
            mission_zone = 'anniversarytower_errandone',
            achievement_id = 200156,
        },
        key = {
            name = 'Repaired Key of the Jungle',
            achievement = 200155,
            id = 161906,
            task = {
                name = 'Broken Key of the Jungle',
                request_item_id = 161950,
                container_id = 161902,
                item1_blade_id = 161903,
                item2_bow_id = 161904,
                item3_biting_id = 161905,
                zone = 'emeraldjungle'
            }
        }
    },
    ["09"] = {
        level = 9,
        switch_id = 9,
        teleporter_id = nil,
        closest_teleporter_id = 18,
        closest_teleporter_level = 10,
        short_name = 'fire',
        mission = {
            name = "Oasis of Fire",
            mission_zone = 'anniversarytower_errandone',
            achievement_id = 200158,
        },
        key = {
            name = 'Repaired Key of Fire',
            achievement = 200157,
            id = 161926,
            task = {
                name = 'Broken Key of Fire',
                request_item_id = 161954, -- Broken Key of Fire
                container_id = 161922,   -- Broken Key of Fire
                item1_blade_id = 161923, -- Broken Key Blade of Fire
                item2_bow_id = 161924,   -- Broken Key Bow of Fire
                item3_biting_id = 161925, -- Broken Key Bitting of Fire
                zone = 'skyfire'
            }
        }
    },
    ["10"] = {
        level = 10,
        switch_id = 10,
        teleporter_id = 18,
        short_name = 'swamps',
        mission = {
            name = "Oasis of Swamps",
            mission_zone = 'anniversarytower_errandone',
            achievement_id = 200160,
        },
        key = {
            name = 'Repaired Key of Swamps',
            achievement = 200159,
            id = 161916,
            task = {
                name = 'Broken Key of Swamps',
                request_item_id = 161952,
                container_id = 161912,
                item1_blade_id = 161913,
                item2_bow_id = 161914,
                item3_biting_id = 161915,
                zone = 'swampofnohope'
            }
        }
    },
    ["11"] = {
        level = 11,
        switch_id = 11,
        teleporter_id = nil,
        closest_teleporter_id = 18,
        closest_teleporter_level = 10,
        short_name = 'fear',
        mission = {
            name = "Oasis of Fear",
            mission_zone = 'anniversarytower_errandone',
            achievement_id = 200162,
        },
        key = {
            name = 'Repaired Key of Fear',
            achievement = 200161,
            id = 161936,
            task = {
                name = 'Broken Key of Fear',
                request_item_id = 161956,
                container_id = 161932,
                item1_blade_id = 161933,
                item2_bow_id = 161934,
                item3_biting_id = 161935,
                zone = 'feerrott'
            }
        }
    },
    ["12"] = {
        level = 12,
        switch_id = 12,
        teleporter_id = nil,
        closest_teleporter_id = 19,
        closest_teleporter_level = 13,
        short_name = 'void',
        mission = {
            name = "Oasis of the Void",
            mission_zone = 'anniversarytower_errandone',
            achievement_id = 200164,
        },
        key = {
            name = 'Repaired Key of the Void',
            achievement = 200163,
            id = 161941,
            task = {
                name = 'Broken Key of the Void',
                request_item_id = 161957,
                container_id = 161937,
                item1_blade_id = 161938,
                item2_bow_id = 161939,
                item3_biting_id = 161940,
                zone = 'fieldofbone'
            }
        }
    },
    ["13"] = {
        level = 13,
        switch_id = 21,
        teleporter_id = nil,
        closest_teleporter_id = 19,
        closest_teleporter_level = 13,
        short_name = 'dragons',
        mission = {
            name = "Oasis of Dragons",
            mission_zone = 'anniversarytower_errandone',
            achievement_id = 200166,
        },
        key = {
            name = 'Repaired Key of Dragons',
            achievement = 200165,
            id = 161946,
            task = {
                name = 'Broken Key of Dragons',
                request_item_id = 161958,
                container_id = 161942,
                item1_blade_id = 161943,
                item2_bow_id = 161944,
                item3_biting_id = 161945,
                zone = 'soldunga'
            }
        }
    },
}

local function to_door(switch_id, click)
    if (not click) then
        mq.cmdf("/nav door id %s", switch_id)
    else
        mq.cmdf("/nav door id %s click", switch_id)
    end
    while(mq.TLO.Navigation.Active()) do mq.delay(50) end
end

local function TravelViaTeleporter(id)
    logger.info('Travel through teleporter %s', id)
    local current_z = mq.TLO.Me.Z()
    to_door(id, true)

    while (math.abs(current_z - mq.TLO.Me.Z()) < 10) do
        mq.delay(50)
    end
    mq.delay(100)
end


function actions.GetLevelDetails(level)
    return actions.Levels[string.format("%02d", level)]
end

local function GetLevelForDoor(door_id)
    if (door_id <= 2) then
        return door_id
    end

    return door_id - 1
end

local function GetDistanceToLevel(level)
    local level_details = actions.GetLevelDetails(level)
    local target_door = level_details.switch_id
    if (target_door == nil) then
        target_door = level_details.teleporter_id
    end

    return mq.TLO.Switch(target_door).Distance3D()
end

-- Returns closest teleporter to my current level
-- TODO: Replace with more efficient algorithm
function actions.GetMyCurrentLevel()
    local last_level = 1
    local last_distance = 9999999
    for i = 1, 13 do
        local distance = GetDistanceToLevel(i)
        if distance == nil then
            logger.warning('GetMyCurrentLevel: distance nil for level %s', i)
            return nil
        end
        if (distance > last_distance) then
            return last_level
        end

        last_level = i
        last_distance = distance
    end

    return last_level
end

local function GetMyCurrentLevelDetails()
    local current_level = actions.GetMyCurrentLevel()

    if not current_level then
        logger.error('Failed to determine current level')
        return nil
    end

    local details = actions.GetLevelDetails(current_level)

    if not details then
        logger.error('No level details found for level %s', current_level)
        return nil
    end

    return details
end

local function MoveToHigherLevel(my_level_details, target_level)
    local target_level_details = actions.GetLevelDetails(target_level)

    ::keep_going::
    local delta = math.abs(target_level - my_level_details.level)

    -- If we are one away, or two away with a teleporter between us (i.e. 3 to 5), then just run there
    if (delta == 1 or
        (delta == 2 and
            my_level_details.closest_teleporter_level ~= nil and my_level_details.closest_teleporter_level > my_level_details.level)) then
        logger.info('Running directly from level %s to level %s', my_level_details.level, target_level)
        to_door(target_level_details.switch_id)
        return
    end

    if (my_level_details.teleporter_id ~= nil) then
        TravelViaTeleporter(my_level_details.teleporter_id)
    else
        TravelViaTeleporter(my_level_details.closest_teleporter_id)
    end

    my_level_details = GetMyCurrentLevelDetails()

    if (my_level_details.level == target_level) then
        logger.info('At target level %s', target_level)
        return
    end

    goto keep_going
end

local function MoveToLowerLevel(my_level_details, target_level)
    local target_level_details = actions.GetLevelDetails(target_level)

    local delta = my_level_details.level - target_level
    if (delta < 2) then

        to_door(target_level_details.switch_id)
        return
    end

    -- Go to roof...
    MoveToHigherLevel(my_level_details, 13)

    -- Zip back down to level 1
    TravelViaTeleporter(19)

    if (target_level == 1) then
        return
    end

    -- And now run up to the zone we wanted
    my_level_details = actions.GetLevelDetails(1)
    MoveToHigherLevel(my_level_details, target_level)
end

function actions.MoveToLevel(target_level)
    if (target_level > 13 or target_level < 1) then
        logger.error('Invalid Level requested: %s', target_level)
        return
    end

    local my_level_details = GetMyCurrentLevelDetails()

    if not my_level_details then
        logger.error('MoveToLevel aborted: could not determine current level')
        return
    end

    -- We're already on the level, just nudge near door, if one.
    if (my_level_details.level == target_level) then
        if (my_level_details.switch_id ~= nil) then
            logger.info('Running directly from level %s to level %s', my_level_details.level, target_level)
            to_door(my_level_details.switch_id)
        end
        return
    end

    if (my_level_details.level < target_level) then
        MoveToHigherLevel(my_level_details, target_level)
    else
        MoveToLowerLevel(my_level_details, target_level)
    end

    -- This move helps us not re-engage the teleporter due to current nav meshes
    if (target_level == 1) then
        logger.debug('Scooting to safe spot on Level 1')
        mq.cmd('/nav loc -40.03 -23.28 -16.02')
        while(mq.TLO.Navigation.Active()) do mq.delay(50) end
    end
end

function actions.GetLevelForDoor(door_id)
    if (door_id <= 2) then
        return door_id
    end

    return door_id - 1
end

function actions.Initialize()
    for _, level in pairs(actions.Levels) do
        if (level.mission ~= nil) then
            -- Duplicate the switch and level into the mission to simplify passing that object around
            level.mission.switch_id = level.switch_id
            level.mission.level = level.level
        end
    end
end

if (args[1] ~= nil) then
    -- If we were run with a NUMERIC argument, run to that floor
    local target_level = tonumber(args[1])
    if (target_level ~= nil) then
        actions.MoveToLevel(tonumber(target_level))
    else
        local target_level_name = string.lower(args[1])
        for _,level in pairs(actions.Levels) do
            if (level.short_name == target_level_name) then
                actions.MoveToLevel(level.level)
                return
            end
        end

        -- logger.warning('Command-line may be a numeric floor # (1-13), the base level ("base") or the name of a mission (i.e. "sand", "void")')
    end
end

return actions