
-- AnniversaryTower\coth
-- Called by a mage to COTH the group main assist
-- (Currently, assuming that is the script caller.)
-- TODO: Communicate Spawn.ID() across the channel
---------------------------
local Version = "1.0"


local mq = require('mq')
local logger = require('utils.logger')
local args = {...}

logger.info('AnniversaryTower/Coth.  Version (%s)  Character (%s)', Version, args[1])

local function IsGroupMember(spawn_id)
    for index = 0, mq.TLO.Group.GroupSize() do
        local group_member = mq.TLO.Group.Member(index)
        if (group_member ~= nil and group_member.ID() == spawn_id) then return true end
    end

    return false
end

if (mq.TLO.Me.Class.ShortName() ~= 'MAG') then
    logger.error('I am not a Magician. No COTH abilities.  Aborting.')
    return
end

local hero_spawn = nil
if (args[1] ~= nil) then
    hero_spawn = mq.TLO.Spawn(args[1])
    if (hero_spawn == nil) then
        logger.error('Supplied spawn ID is not a valid character. Aborting.')
        return
    end

    if (IsGroupMember(hero_spawn.ID()) == false) then
        logger.error('Supplied spawn ID refers to character NOT in our current group. Aborting.')
        return
    end
end

if (hero_spawn == nil or hero_spawn() == nil) then
    hero_spawn = mq.TLO.Group.MainAssist.Spawn()
    if (hero_spawn == nil) then
        hero_spawn = mq.TLO.Group.Leader.Spawn()
    end

    if (hero_spawn == nil) then
        logger.error('No Group.  Abandoning COTH.')
        return
    end
end

logger.info('Attempting to COTH %s (%s)', hero_spawn.Name(), hero_spawn.ID())

while (mq.TLO.Nav.Active()) do mq.cmd('/nav stop') mq.delay(50) end
while (mq.TLO.Me.Casting()) do mq.delay(50) end

mq.cmdf('/target id %d', hero_spawn.ID())
mq.delay(1000, function() return mq.TLO.Target.ID() == hero_spawn.ID() end)
if (mq.TLO.Target.ID() ~= hero_spawn.ID()) then
    logger.error('Unable to target indended hero.  Aborting.')
    return
end

-- Finally, Call That Hero
mq.cmd('/alt act 7050')

