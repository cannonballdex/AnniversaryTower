--- @type Mq
local mq = require('mq')
local logger = require('utils.logger')
local string_utils = require('utils.string_utils')

local actions = {}

local event_cannot_enter_seen = false
local DEFAULT_DISTANCE = 5

-----------------------------------------
-- Item Management
-----------------------------------------
function actions.BlockUntilItemCastingCompleted(item, delay_for_casting_begin)
    if (delay_for_casting_begin == nil) then delay_for_casting_begin = 2000 end

    logger.trace('Waiting for casting to begin')
    mq.delay(delay_for_casting_begin, function() return mq.TLO.Me.CastTimeLeft() > 0 end)

    logger.trace('Waiting for cast to be completed: %s - %s - %s', item.CastTime(), mq.TLO.Me.CastTimeLeft(), item.TimerReady())
    mq.delay(item.CastTime()+100, function() return (mq.TLO.Me.CastTimeLeft() == 0 or item.TimerReady() > 0) end)
end

-- Activates the specified item if it is in inventory and doesn't have a cool-down timer
-- delay_until_completed.  Defaults to true.  If true, method doesn't return until casting has completed or interrupted.
-- allowed_time_window.  Defaults to 0. If pending cast is < that number of seconds, will wait
-- Returns true if casting was able to begin; otherwise false.
function actions.ActivateClickyItemIfAvailable(item, delay_until_completed, allowed_time_window_in_seconds)
    if (delay_until_completed == nil) then delay_until_completed = true end
    if (allowed_time_window_in_seconds == nil) then allowed_time_window_in_seconds = 0 end

    if (item.ID() == nil) then
        logger.info('Item called for activation that is not owned: %s', item.Name())
        return false
    end

    if (item.Clicky() == nil) then
        logger.info('Item called for activation that has no clicky effect: \at %s', item.Name())
        return false
    end

    ::try_again::
    if (item.TimerReady() > allowed_time_window_in_seconds) then
        logger.info('\ag%s \ao is not available for %s seconds.', item.Name(), item.TimerReady())
        return false
    end

    if (item.TimerReady() > 0) then
        mq.delay(allowed_time_window_in_seconds)
        goto try_again
    end

    logger.info('Activating (\at%s\aw) CastTime: \ag %s', item.Name(), item.CastTime())

    mq.cmdf('/useitem "%s"', item.Name())

    if (delay_until_completed == false or item.CastTime() < 150) then
        return true
    end

    actions.BlockUntilItemCastingCompleted(item, 5000)

    return true
end

function actions.ActivateClickyItemIfAvailableById(item_id, delay_until_completed, allowed_time_window)
    local item = mq.TLO.FindItem(item_id)
    if (item.ID() == nil) then return end
    return actions.ActivateClickyItemIfAvailable(item, delay_until_completed, allowed_time_window)
end

function actions.ActivateClickyItemIfAvailableByName(item_name, delay_until_completed, allowed_time_window)
    local item = mq.TLO.FindItem(item_name)
    if (item.ID() == nil) then return end
    return actions.ActivateClickyItemIfAvailable(item, delay_until_completed, allowed_time_window)
end

local function ClickConfirmation(button)
	-- TODO: Another place where the condition on mq.delay doesn't seem to be honored
	-- mq.delay(10000, mq.TLO.Window('ConfirmationDialogBox').Open())
	-- Look Into:         mq.delay(5000, function() return validatemenu(clicky) end)
	mq.parse('/delay 10s ${Window[ConfirmationDialogBox].Open}')
	mq.delay(250)
	mq.cmd.notify('ConfirmationDialogBox '..button..' leftmouseup')
	mq.doevents()
	::ConfirmWait::
	mq.delay(5)
	if (mq.TLO.Window('ConfirmationDialogBox').Open()) then
		goto ConfirmWait
	end
end

function actions.click_confirmation_ok()
    ClickConfirmation('CD_OK_Button')
end

function actions.click_confirmation_yes()
	actions.WaitForWindow('ConfirmationDialogBox')
	mq.delay(200)
	mq.cmd('/yes')
end

function actions.close_bag(pack, slot)
	if (pack == nil or slot == nil) then return end

	if (mq.TLO.Window('pack' .. pack).Open() ~= nil) then
		mq.delay(500)
		mq.cmdf('/nomodkey /itemnotify %s rightmouseup', slot)
	end
end

function actions.open_item_bag(item_name)
    local item = mq.TLO.FindItem(item_name)
    if (item == nil) then
        return nil, nil
    end

    local slot1 = item.ItemSlot()
    local slot2 = item.ItemSlot2() + 1
    if (slot2 ~= 0) then
         local pack = item.ItemSlot() - 22
         if mq.TLO.Window('pack' .. pack).Open() == nil then
            mq.cmdf('/nomodkey /itemnotify %s rightmouseup', slot1)
            mq.delay(500)

			return pack, slot1
        end
	end

	return nil, nil
end

function actions.DelayUntilQuestAssigned(delay_value, quest_name)
    mq.delay(delay_value, function() return mq.TLO.Task(quest_name)() ~= nil end)
    return mq.TLO.Task(quest_name)
end

local messaging_type = 'dannet' -- or 'bc'
function actions.set_messaging_type(type)
    messaging_type = type
end

function actions.get_messsaging_type()
    return messaging_type
end

function actions.send_message(do_noparse, scope, command, ...)
    local full_command = string.format(command, ...)
    local noparse = ''
    if (do_noparse) then noparse = '/noparse ' end
    local preslash = ''
    if (messaging_type == 'bc') then preslash = '/' end

    full_command = string.format('%s/%s %s%s', noparse, scope, preslash, full_command)
    mq.cmd(full_command)
end

function actions.send_individual_message(char_name, command, ...)
    if (messaging_type == 'dannet') then
        actions.send_message(false, 'dex '..char_name, command, ...)
    else
        actions.send_message(false, 'bct '..char_name, command, ...)
    end
end

function actions.send_group_message(command, ...)
    -- If we aren't in a group, then just do the command ourselves
    if (mq.TLO.Group() == nil) then
        mq.cmd(command)
    elseif (messaging_type == 'dannet') then
        actions.send_message(false, 'dgga', command, ...)
    else
        actions.send_message(false, 'bcga', command, ...)
    end
end

function actions.send_others_message(command, ...)
    if (mq.TLO.Group() == nil) then return end
    if (messaging_type == 'dannet') then
        actions.send_message(false, 'dgge', command, ...)
    else
        actions.send_message(false, 'bcg', command, ...)
    end
end

function actions.send_others_message_noparse(command, ...)
    if (messaging_type == 'dannet') then
        actions.send_message(true, 'dgge', command, ...)
    else
        actions.send_message(true, 'bcg', command, ...)
    end
end


function actions.is_up(spawn_name)
    return mq.TLO.Spawn(spawn_name).ID() > 0
end

-- Delays until the requested zone has been entered and game is in proper state
-- returns TRUE if this occurred in the expected time; otherwise false
function actions.WaitForZone(zone_name, duration)
    if (duration == nil) then duration = 10000 end

    mq.delay(duration, function() return mq.TLO.Zone.ShortName() == zone_name end)
end

function actions.IsGroupInZone()
    if (mq.TLO.Group.GroupSize() == nil) then return true end

    return mq.TLO.Group.AnyoneMissing() == false
end

function actions.WaitForGroupToZone(delay)
    if (mq.TLO.Group.GroupSize() == nil) then return end

    delay = delay or 1000

    local displayed_message = false
    while(true) do
        if (mq.TLO.Group.AnyoneMissing() == false) then
            mq.delay(delay)
            return
        end

        if (displayed_message == false) then
            logger.info('In zone. Waiting for group to catch up.')
            displayed_message = true
        end

        mq.delay(1000)
        mq.doevents()
    end
end

function actions.TravelViaTeleporter(doorId, whole_group)
    if (whole_group == true) then
        actions.send_group_message('/nav door id %s click', doorId)
    else
        mq.cmdf('/nav door id %s click', doorId)
    end

    while mq.TLO.Navigation.Active() == true do
        mq.delay(100)
        mq.doevents()
    end
end

-- retry_duration_ms is amount of time to wait for door-click to work before clicking again
function actions.TravelViaDoor(doorId, target_zoneName, whole_group, retry_duration_ms)
    event_cannot_enter_seen = false

    if (mq.TLO.Zone.ShortName() == target_zoneName and (whole_group == false or mq.TLO.Group.AnyoneMissing() == false)) then
        return
    end

    if (retry_duration_ms == nil) then retry_duration_ms = 10000 end

    ::try_door_again::
    if mq.TLO.Zone.ShortName() ~= target_zoneName then
        if (whole_group == true) then
            logger.info('Whole group traveling to \at%s', target_zoneName)
            actions.send_group_message('/nav door id %s click', doorId)
        else
            logger.info('Traveling to %s', target_zoneName)
            mq.cmdf('/nav door id %s click', doorId)
        end
    end

    while mq.TLO.Zone.ShortName() ~= target_zoneName do
        mq.delay(500)
        mq.doevents()

        if (event_cannot_enter_seen == true) then
            logger.info('\ar Zone Not Ready.\aw Waiting %s ms and trying to enter again.', retry_duration_ms);
            mq.delay(retry_duration_ms)
            goto try_door_again
        end
    end

    if (whole_group) then
        actions.WaitForGroupToZone()
    end
end

function actions.TravelToGroup(zoneName)
    actions.send_group_message('/travelto %s', zoneName)

    while(true) do
        if (mq.TLO.Zone.ShortName() ~= zoneName) then goto keep_waiting end

        if (mq.TLO.Group.AnyoneMissing() == false) then
            return
        end

        ::keep_waiting::
        mq.delay(1000)
    end
end

local travel_to_event = nil
function actions.SetTraveltoEvent(travel_to_delegate)
    travel_to_event = travel_to_delegate
end

function actions.TravelTo(zoneName, whole_group)
    if (travel_to_event ~= nil) then travel_to_event(zoneName) end

    if (whole_group == true) then actions.TravelToGroup(zoneName) return end

    if mq.TLO.Zone.ShortName() == zoneName then return end

    logger.info('Traveling to %s', zoneName)
    mq.cmdf('/travelto %s', zoneName)

    while mq.TLO.Zone.ShortName() ~= zoneName do
        mq.delay(500)
    end
end

function actions.MoveToSpawnName(spawn_name, distance, non_npc)
    local spawn_query = spawn_name

    if (non_npc ~= true) then
        spawn_query = 'npc '..spawn_name
    end

    if (mq.TLO.SpawnCount(spawn_query)() <= 0) then return false end

    if (distance == nil) then distance = DEFAULT_DISTANCE end

    local spawn = mq.TLO.Spawn(spawn_query)
    if (spawn.Distance() < distance) then return true end

    mq.cmdf('/squelch /nav id "%s" npc |dist=%s', spawn.ID(), distance)
    while mq.TLO.Navigation.Active() do mq.delay(1) end
    mq.delay(500)
    return true
end

function actions.MoveToLoc(locXyz)
    mq.cmdf('/nav loc %s', locXyz)
    while mq.TLO.Navigation.Active() do mq.delay(1) end
    mq.delay(500)
    return true
end

function actions.MoveToLocXy(locXy)
    mq.cmdf('/nav locxy %s', locXy)
    while mq.TLO.Navigation.Active() do mq.delay(1) end
    mq.delay(500)
    return true
end

function actions.MoveToId(id, distance)
    if (distance == nil) then distance = DEFAULT_DISTANCE end
    mq.cmdf('/squelch /nav id %s |dist=%s', id, distance)
    while mq.TLO.Navigation.Active() do mq.delay(1) end
    mq.delay(500)
    return true
end

function actions.MoveToSpawnNameAndAttack(spawn_name)
    if actions.MoveToSpawnName(spawn_name) == false then return false end
    mq.cmdf('/squelch /target npc %s', spawn_name)
    mq.delay(250)
    if (mq.TLO.Me.Combat() == false) then
        mq.cmd('/attack on')
        if (mq.TLO.Pet.ID() ~= 0) then
            mq.cmd('/pet attack')
        end
    end
    return true
end

function actions.MoveToAndAttackId(id, distance)
    actions.MoveToAndTargetId(id, distance)
    mq.delay(250)
    if (mq.TLO.Me.Combat() == false) then
        mq.cmd('/attack on')
        if (mq.TLO.Pet.ID() ~= 0) then
            mq.cmd('/pet attack')
        end
    end
    return true
end

function actions.MoveToSpawnNameAndTarget(spawn_name, distance)
    if actions.MoveToSpawnName(spawn_name, distance) == false then return false end
    mq.cmdf('/squelch /target npc %s', spawn_name)
    mq.delay(250)
    return true
end

function actions.MoveToAndTargetId(id, distance)
    if actions.MoveToId(id, distance) == false then return false end
    mq.cmdf('/squelch /target id %s', id)
    mq.delay(250)
    return true
end

function actions.MoveToSpawnNameAndAct(spawn_name,cmd)
    if actions.MoveToSpawnNameAndTarget(spawn_name) == false then return false end
    mq.cmd(cmd)
    mq.cmd('/squelch /target clear')
    return true
end

function actions.CorpseTargetCheck()
    if (mq.TLO.Target.Type() == "Corpse") then
        mq.cmd('/squelch /target clear')
        mq.delay(500)
    end
end

function actions.MoveToAndHail(spawn_name) return actions.MoveToSpawnNameAndAct(spawn_name, '/hail') end
function actions.MoveToAndSay(spawn_name,say) return actions.MoveToSpawnNameAndAct(spawn_name, string.format('/say %s', say)) end
function actions.MoveToAndOpen(spawn_name) return actions.MoveToSpawnNameAndAct(spawn_name, '/open') end

function actions.KillAllOnXtarget()
    while mq.TLO.Me.XTarget(1).ID() > 0
    do
        if (mq.TLO.Target() == nil) then
            actions.MoveToAndAttackId(mq.TLO.Me.XTarget(1).ID())
        else
            actions.CorpseTargetCheck()
        end
    end
end

function actions.WaitForSpawn(spawn_name, distance)
    if (spawn_name == nil) then
        logger.warning('Wait for spawn, no name specified')
        return false
    end

    local search_string = 'npc '..spawn_name

    if (distance ~= nil) then
        search_string = string.format(' radius %s', distance)
    end

    while(mq.TLO.SpawnCount(search_string)() == 0) do
        mq.delay(100)
    end

    return true
end

function actions.WaitForNoSpawn(spawn_name, distance)
    local search_string = 'npc '..spawn_name

    if (distance ~= nil) then
        search_string = string.format(' radius %s', distance)
    end

    while(mq.TLO.SpawnCount(search_string)() > 0) do
        mq.delay(500)
    end
end

function actions.FollowSpawn(objective, spawn_name, follow_distance)
    if (spawn_name == nil) then
        logger.warning('Follow spawn name not specified')
        return false
    end

    local spawn = mq.TLO.Spawn('npc '..spawn_name)
    if (spawn.ID() == 0) then
        logger.warning('Follow Spawn not found: %s', spawn_name)
        return false
    end

    if (follow_distance == nil) then follow_distance = 50 end
    while(spawn.ID() > 0 and actions.ObjectiveComplete(objective) == false) do
        if (spawn.Distance() > follow_distance) then
            actions.MoveToId(spawn.ID())
        end

        mq.delay(100)
    end

    return true
end

function actions.KillAllBaddiesIfUp2(spawn, distance, forceGroup)
    local logged = false

    local spawn_search = 'npc '..spawn
    if (distance ~= nil) then
        spawn_search = string.format(' radius %s', distance)
    end

    while(mq.TLO.SpawnCount(spawn_search)() > 0) do
        if (logged == false) then
            logger.info('Killing \at%s', spawn)
            logged = true
        end

        if (actions.MoveToSpawnNameAndAttack(spawn) == false) then logger.debug('Move/Attack for (%s) failed', spawn) return end
        actions.CorpseTargetCheck()
    end

    actions.KillAllOnXtarget()
end

local function CwtnResetCamp()
    if (mq.TLO.CWTN == nil) then return end

    logger.info('\ay Resetting CWTN camp')
    mq.cmdf('/%s resetcamp', mq.TLO.CWTN.Command())
end

function actions.KillOneMob(spawn_name, distance, force_group)
    local spawn_name_lowercase = string.lower(spawn_name)

    -- If we have a target and it's our desired mob, then wait a bit...
    if (mq.TLO.Target.ID() > 0 and string.find(string.lower(mq.TLO.Target.CleanName()), spawn_name_lowercase) ~= nil) then
        if (mq.TLO.Target.Distance() > DEFAULT_DISTANCE) then
            actions.MoveToAndAttackId(mq.TLO.Target.ID(), DEFAULT_DISTANCE)
        end
        mq.delay(250)
    else
        local spawn_search = string.format('"%s"', spawn_name)
        if (distance ~= nil) then
            spawn_search = spawn_search..' radius '..distance
        end

        local actual_spawn = mq.TLO.NearestSpawn('npc '..spawn_search)
        if (actual_spawn.ID() == nil) then
            logger.debug('No spawn found: (\at%s\ao)', spawn_search)
            return false
        end

        logger.info('\aoKilling \at%s\ao (id:\at%s\ao)', spawn_name, actual_spawn.ID())

        if (actions.MoveToAndAttackId(actual_spawn.ID()) == false) then
            logger.debug('Move/Attack for (%s) failed', spawn_name)
            return
        end

        if (force_group == true) then
            actions.send_others_message('/target id %d', actual_spawn.ID())
            mq.delay(250)
            actions.send_others_message('/attack on')
        end

        while(actual_spawn.ID() ~= nil and actual_spawn.ID() ~= 0 and actual_spawn.Type() ~= 'Corpse') do
            mq.delay(100)
            mq.doevents()
            if (mq.TLO.Target.Distance() ~= nil and mq.TLO.Target.Distance() > DEFAULT_DISTANCE) then
                actions.MoveToAndAttackId(mq.TLO.Target.ID(), DEFAULT_DISTANCE)
            end
        end

        return
    end
end

-- Runs the supplied delegate against each group_member
-- If all return true, return true; else return false
local function are_all_group_members(delegate, include_myself)
    if (include_myself == nil) then include_myself = false end
    if (mq.TLO.Group.GroupSize() == nil) then
        return delegate(mq.TLO.Me)
    else
        for index = 0, mq.TLO.Group.Members() do
            local group_member = mq.TLO.Group.Member(index)
            if (include_myself == true or group_member.ID() ~= mq.TLO.Me.ID()) then
                if (delegate(group_member) == false) then return false end
            end
        end
    end

    return true
end

--- Runs the supplied delegate against each group_member
--- If any return true, return true; else return false
--- @param delegate function Signature of name(mq.TLO.Group[Member])
local function are_any_group_members(delegate, include_myself)
    include_myself = include_myself or false
    if (mq.TLO.Group.GroupSize() == nil) then
        return delegate(mq.TLO.Me)
    else
        for index = 0, mq.TLO.Group.Members() do
            local group_member = mq.TLO.Group.Member(index)
            if (include_myself == true or group_member.ID() ~= mq.TLO.Me.ID()) then
                if (delegate(group_member) == true) then return true end
            end
        end
    end
    return false
end

--- Returns true if all group members are either in range or moving
--- Returns false if any group member is out of range AND not moving
local function are_group_members_arriving(distance)
    distance = distance or GroupAcceptableRange

    -- Are all group members in range or running?
    return are_all_group_members(function(group_member)
        return group_member.Spawn.Distance() <= distance or group_member.Spawn.Moving() == true
    end, false)
end


GroupAcceptableRange = 30
function actions.AreGroupMembersInRange(distance)
    distance = distance or GroupAcceptableRange

    return are_any_group_members(function(group_member)
        return group_member.Spawn.ID() == 0 or group_member.Spawn.Distance() > distance
    end) == false
end

--- Pauses until group moves closer.  Optionally, after a certain time, a "Come To Me" call will be made
-- --- @param duration integer Identifies how long to wait
-- --- @param distance integer Indicates distance to be considered "in range"
function actions.WaitForGroupToCatchUp(spec, duration, distance)
    if (spec ~= nil and spec.mission_details ~= nil and actions.AmIDriver(spec.mission_details) == false) then return false end

    duration = duration or 10000
    distance = distance or GroupAcceptableRange

    if (actions.AreGroupMembersInRange(distance)) then return true end

    -- TODO: Is this a valid step to bail on?
    if (mq.TLO.Me.Moving() == true) then return false end

    -- If any are out of range and not moving... do something about that
    if (are_group_members_arriving(distance) == false) then
        -- TODO: Optimize to just telling the lagging person
        actions.send_others_message('/nav id %s', mq.TLO.Me.ID())
    end

    logger.info('Waiting for group to catch up (range: %s)', distance)
    mq.delay(duration, function() return actions.AreGroupMembersInRange() end)

    if (actions.AreGroupMembersInRange() == false) then
        logger.warning('Group Members Not In Range. Need to do sumpn about that.')
        return false
    end

    return true
end

function actions.ObjectiveComplete(objective)
    return (objective ~= nil and objective.Status() == "Done")
end

function actions.PauseUntilObjectiveComplete(objective, description)
    mq.cmd('/beep')
    mq.cmd('/beep')
    if (description == nil) then
        description = "Waiting until objective is \atmanually\aw completed."
    end

    logger.warning(description)

    while( actions.ObjectiveComplete(objective) == false) do
        mq.doevents()
        mq.delay(500)
    end
end

function actions.KillAllBaddiesIfUpForTask(spawn_name, task_objective)
    return actions.KillAllBaddiesIfUp(spawn_name, nil, false, false, task_objective)
end

function actions.KillAllBaddiesIfUp(spawn_name, distance, forceGroup, resetCamp, task_objective, zdistance)
    local last_actual_spawn = nil
    local is_new_target = false
    local spawn_name_lowercase = string.lower(spawn_name)
    if (resetCamp == nil) then resetCamp = false end

    while(true) do
        if (task_objective ~= nil and task_objective.Status() == "Done") then return end

        -- If we have a target and it's our desired mob, then wait a bit...
        if (mq.TLO.Target.ID() > 0 and string.find(string.lower(mq.TLO.Target.CleanName()), spawn_name_lowercase) ~= nil) then
            if (mq.TLO.Target.Distance() > DEFAULT_DISTANCE) then
                actions.MoveToId(mq.TLO.Target.ID(), DEFAULT_DISTANCE)
            end
            mq.delay(250)
        else
            local spawn_search = ''
            if (spawn_name ~= '') then 
                spawn_search = string.format('"%s"', spawn_name)
            end

            if (distance ~= nil) then
                spawn_search = spawn_search..' radius '..distance
            end
            if (zdistance ~= nil) then
                spawn_search = spawn_search..' zradius '..zdistance
            end

            local actual_spawn = mq.TLO.NearestSpawn('npc '..spawn_search)
            if (actual_spawn.ID() == nil) then
                logger.debug('No spawn found: (\at%s\ao)', spawn_search)
                return false
            end

            if (last_actual_spawn == nil or last_actual_spawn.ID() ~= actual_spawn.ID()) then
                last_actual_spawn = actual_spawn
                is_new_target = true
            else
                is_new_target = false
            end

            if (is_new_target == true) then
                logger.info('\aoKilling \at%s\ao (id:\at%s\ao)', spawn_name, actual_spawn.ID())
            end

            if (actions.MoveToAndAttackId(actual_spawn.ID(), distance) == false) then logger.debug('Move/Attack for (%s) failed', spawn_name) return end

            if (resetCamp == true) then
                CwtnResetCamp()
                resetCamp = false
            end

            if (forceGroup == true and is_new_target) then
                actions.send_others_message('/target id %d', actual_spawn.ID())
                mq.delay(250)
                actions.send_others_message('/attack on')
            end
        end

        actions.CorpseTargetCheck()
    end
end

function actions.KillAllBaddiesIfUpAndAnotherDown(spawn, previous_spawn, distance)
    if (actions.is_up(previous_spawn)) then
        logger.debug('Not killing \ay%s\aw as \ag%s\aw is up', spawn, previous_spawn)
        return false
    end
    return actions.KillAllBaddiesIfUp(spawn, distance)
end

function actions.ActivateItem(item_name)
    mq.cmdf('/shift /itemnotify "%s" rightmouseup', item_name)
    mq.delay(1500)
end

function actions.OpenContainer(container_name)
    actions.ActivateItem(container_name)
end

function actions.AddItemToPack(item_id, pack, slot)
    actions.PickupInventoryItemById(item_id)
    mq.delay(1000)
    mq.cmdf('/itemnotify in pack%d %d leftmouseup', pack, slot)
    mq.delay(1000)
end

function actions.CombinePack(pack)
    mq.cmdf('/combine pack%d', pack)
    actions.AddCursorItemsToInventory(true)
end

-- Puts any items on cursor into inventory
-- Parameter: wait_for_cursor_item. If TRUE, waits for an item to appear on the cursor before acting
function actions.AddCursorItemsToInventory(wait_for_cursor_item)
    if (wait_for_cursor_item == nil) then wait_for_cursor_item = false end

    if (wait_for_cursor_item == false and mq.TLO.Cursor.ID() == nil) then return end

    if (wait_for_cursor_item == true) then
        mq.delay(2000, function() return mq.TLO.Cursor.ID() ~= nil end)
    end

    ::auto_inv_again::
    mq.cmd.autoinv()
    mq.delay(1000, function() return mq.TLO.Cursor.ID() == nil end)
    if (mq.TLO.Cursor.ID() ~= nil) then goto auto_inv_again end
end

function actions.GetClosestSpawn(spawn_name)
    if (spawn_name == nil) then return nil end
    local mob_count = mq.TLO.SpawnCount('npc '..spawn_name)()
    for i=1,mob_count do
        local mob = mq.TLO.NearestSpawn(i, 'npc '..spawn_name)
        local can_reach = mq.TLO.Navigation.PathExists( string.format("locyxz %s", mob.LocYXZ()))()
        if (can_reach == true) then return mob end
    end

    return nil
end

function actions.GetGroundSpawn(item_name, distance, wait_for_respawn)
    local logged_search_already = false

    ::search_again::

    local ground_item = mq.TLO.Ground.Search(item_name)
    if (not wait_for_respawn and ground_item() == nil) then
        logger.warning('No expected groundspawn: %s', item_name)
        return false
    end

    if (distance ~= nil) then
        if (ground_item.Distance() > distance) then
            if (not wait_for_respawn) then
                logger.warning('No expected groundspawn in range: %s', item_name)
                return false
            else
                if (logged_search_already == false) then
                    logger.info('Waiting for ground item respawn: %s', item_name)
                    logged_search_already = true
                end
                mq.delay(1000)
                goto search_again
            end
        end
    end

    if (mq.TLO.Navigation.PathExists(string.format("item %s", item_name))() == false) then
        logger.error('\arCould not find a path to the ground spawn.\ao  Move closer or acquire manually.  Exiting Script.')
        return false
    end

    mq.cmd("/squelch /target clear")
    mq.delay(100)
    mq.cmdf('/itemtarget "${Ground.Search[%s]}"', item_name)
    mq.delay(100)

    if (string_utils.starts_with(mq.TLO.ItemTarget(), item_name)) then
        logger.debug('ITEM TARGETED: %s - %s', item_name, mq.TLO.ItemTarget())
        mq.cmd("/nav item |dist=10")
        while mq.TLO.Navigation.Active() do
            mq.delay(100)
        end
        mq.delay(100)
    else
        logger.error('Unable to target item: %s - %s', item_name, mq.TLO.ItemTarget())
        return error
    end

    mq.TLO.Ground.Search(item_name).Grab()
    actions.AddCursorItemsToInventory(true)

    if mq.TLO.Cursor.ID() then
        mq.cmd('/autoinventory')
    end
    mq.delay(1000)
    if mq.TLO.Cursor.ID() then
        mq.cmd('/autoinventory')
    end

    return true
end

function actions.PickupInventoryItemById(item_id)
    mq.delay(1)

    local l_id = item_id

    if mq.TLO.FindItemCount(l_id)() < 1 or mq.TLO.FindItem(l_id)() == nil then
        print("Nothing found to grab")
        return false
    end

    mq.delay(1)

    local l_count = 1

    local slot2 = mq.TLO.FindItem(l_id).ItemSlot2() + 1

    if slot2 == 0 then

        -- Workaround for UI interference
        if GLOBAL_STANDARD_UI == 1 then mq.delay(2000) end

        -- Not in bag
        local slot1 = mq.TLO.FindItem(l_id).ItemSlot()

        if l_count == 1 then
            mq.cmd('/ctrl /itemnotify ' .. slot1 .. ' leftmouseup')
            mq.delay(200)
        end

    else
        mq.delay(1)
        local pack = mq.TLO.FindItem(l_id).ItemSlot() - 22
        -- Workaround for UI interference
        if GLOBAL_STANDARD_UI == 1 then mq.delay(2000) end

        mq.delay(1)

        if l_count == 1 then

            mq.delay(1)

            mq.cmd('/ctrl /itemnotify in pack' .. pack .. ' ' .. slot2 ..' leftmouseup')
            mq.delay(200)
        end

    end

    if mq.TLO.Cursor.Name == nil or mq.TLO.Cursor.Name == "NULL" then
        logger.error('Unable to pick up item from inventory: %s', item_id)
        return false
    end

    return true
end

local function GiveItemToTarget(item_id)
    if (item_id == nil) then return end

    if (actions.PickupInventoryItemById(item_id) == true) then
        mq.cmd('/click left target')
        mq.delay(1000)
    end
end

function actions.GiveItemsToNpc(target_name, item_id1, item_id2, item_id3, item_id4)
    if (mq.TLO.SpawnCount('npc '..target_name)() < 1) then
        logger.warning('No target found for GiveItems: %s', target_name)
        return false
    end

    actions.MoveToSpawnNameAndTarget(target_name, 10)

    GiveItemToTarget(item_id1)
    GiveItemToTarget(item_id2)
    GiveItemToTarget(item_id3)
    GiveItemToTarget(item_id4)

    if mq.TLO.Window('GiveWnd').Open() then
        mq.cmd('/notify GiveWnd GVW_Give_Button leftmouseup')
    end

    return true
end

---Delays until loot is no longer in progress
---@param delay_ms number? (Default: 3000) specifies amount of time in ms to wait for looting to free up
---@return boolean true if successfully freed up looting, else false
local function delay_while_loot_in_progress(delay_ms)
    if (delay_ms == nil) then delay_ms = 3000 end

    if (mq.TLO.AdvLoot.LootInProgress()) then
        logger.info('....waiting for flags to clear...')
        mq.delay(delay_ms, function() return mq.TLO.AdvLoot.LootInProgress() == false end)
        if (mq.TLO.AdvLoot.LootInProgress()) then
            printf('Unable to loot for 3+ seconds. Aborting')
            return false
        end
    end

    return true
end

function actions.LootItemById(item_id)
    local current_inventory_count = mq.TLO.FindItemCount(item_id)()
    ::check_personal::

    if (delay_while_loot_in_progress() == false) then
        return false
    end

    if (mq.TLO.AdvLoot.PCount() > 0) then
        for index = 1, mq.TLO.AdvLoot.PCount() do
            if (mq.TLO.AdvLoot.PList(index).ID() == item_id) then
                logger.info('\ay Attempting to loot item ID:\at %d', item_id)
                mq.cmdf('/advloot personal %d loot', index)

                mq.delay(3000, function() return mq.TLO.FindItemCount(item_id)() > current_inventory_count end)
                if ( mq.TLO.FindItemCount(item_id)() > current_inventory_count) then
                    logger.info('\ay Looted item:\at%d', item_id)
                    return true
                end

                logger.info('\at Unable to loot item:\ag%s', item_id)
                return false
            end
        end
    end

    if (mq.TLO.AdvLoot.SCount() > 0) then
        for index = 1, mq.TLO.AdvLoot.SCount() do
            if (mq.TLO.AdvLoot.SList(index).ID() == item_id) then
                logger.info('\ay Assigning shared loot item ID:\at %d \ay to \at %s', item_id, mq.TLO.Me.Name())
                mq.cmdf('/advloot shared %d giveto %s 1', index, mq.TLO.Me.Name())
                goto check_personal
            end
        end
    end

    return false
end

function actions.AreGroupCorpsesInZone()
    if (mq.TLO.Group.GroupSize() == nil) then return false end
    
    for index = 0, mq.TLO.Group.GroupSize() - 1 do
        local group_member = mq.TLO.Group.Member(index)
        if (group_member ~= nil) then
            logger.debug('\ay Checking next group member: %s \at%s', index, group_member.Name())
            local spawn_count = mq.TLO.SpawnCount('corpse ' .. group_member.Name())()
            if (spawn_count > 0) then
                logger.warning('\ao %d corpses seen for (%s)', spawn_count, group_member.Name())
                return true
            end
        end
    end

    return false
end

function actions.GetGroupMemberByClass(class_short_name)
    for index = 0, mq.TLO.Group.GroupSize() do
        local group_member = mq.TLO.Group.Member(index)
        if (group_member ~= nil and group_member.Class.ShortName() == class_short_name) then
            return group_member
        end
    end

    return nil
end

function actions.IsItemInTopLevelSlot(item)
    return item.ItemSlot2() < 0
end

function actions.GetFirstEmptyTopLevelSlot()
    for slot = 23, 32 do
        if (mq.TLO.Me.Inventory(slot).ID() == nil) then
            return slot
        end
    end
    return nil
end

-- Returns the first non-container in a top-level slot
-- Or if none found, the first empty container in a top-level slot
function actions.GetFirstTopLevelItemThatCanBeMovedIntoABag()
    local empty_container_item = nil
    for slot = 23, 32 do
        local item = mq.TLO.Me.Inventory(slot)
        if (item ~= nil) then
            -- Is non-container?
            if (item.Container() == 0) then
                return item
            end

            if (empty_container_item == nil and item.Container() > 0 and item.Items() == 0) then
                empty_container_item = item
            end
        end
    end

    return empty_container_item
end

function actions.GetFirstTopLevelSlotWithNonContainer()
    for slot = 23, 32 do
        local item = mq.TLO.Me.Inventory(slot)
        if (item ~= nil and item.Container() > 0) then
            return item
        end
    end

    return nil
end

function actions.GetFirstEmptyContainerInTopLevelSlot()
    for slot = 23, 32 do
        local item = mq.TLO.Me.Inventory(slot)
        if (item ~= nil and item.Container() > 0 and item.Items() == 0) then
            return item
        end
    end

    return nil
end

-- Item_size == 1 SMALL, 2 MEDIUM, 3 LARGE, 4 GIANT
-- Defaults to 1 if not specified (nil)
-- container_to_exclude_id == optional ID if it's the item being moved.  Don't wanna "move into myself"
function actions.GetFirstOpenContainerInventorySlot(item_size, container_to_exclude)
    if (item_size == nil) then item_size = 1 end
    item_size = tonumber(item_size)

    for slot = 23, 32 do
        if (container_to_exclude ~= nil and container_to_exclude.ItemSlot() == slot) then goto next_item end

        local item = mq.TLO.Me.Inventory(slot)
        -- If we have an item, it's a container, slots available, and big enough to fit our item
        if (item ~= nil and item.Container() > 0 and item.Items() < item.Container() and item.SizeCapacity() >= item_size) then
            if (item.Items() == 0) then
                return slot - 22, 1
            end

            for bucket = 1, item.Items() do
                if (item.Item(bucket).ID() == nil) then
                    return slot - 22, bucket
                end
            end
        end

        ::next_item::
    end

    return nil, nil
end

-- Moves specified item to top-level slot, if not already
-- If item already in top-level slot, return (true, nil)
-- If no free top-level slots open, make room and return (true, item) moved to do so
-- If unable to make room, return (false,nil)
function actions.MoveItemToTopLevelSlot(item)
        if (item.ID() == nil) then return true, nil end

    if (actions.IsItemInTopLevelSlot(item)) then return true, nil end

    -- If we don't have a top-level slot open, then make room
    local top_level_slot = actions.GetFirstEmptyTopLevelSlot()
    local item_to_move = nil
    if (top_level_slot == nil) then
        item_to_move = actions.GetFirstTopLevelItemThatCanBeMovedIntoABag()
        if (item_to_move == nil) then
            return false, nil
        end

        logger.info('Moving item from top-level slot: \at%s\ao (\aw%s\ao)', item_to_move.Name(), item_to_move.ID())
        top_level_slot = item_to_move.ItemSlot()

        local pack, slot = actions.GetFirstOpenContainerInventorySlot(item_to_move.Size(), item_to_move)
        if (pack == nil) then
            logger.warning('Unable to free up a top level inventory slot')
            return false, nil
        end

        logger.info('Moving Item \at%s\ao to \atpack %s\ao, \atslot %s', item_to_move.Name(), pack, slot)
        actions.PickupInventoryItemById(item_to_move.ID())
        mq.cmdf('/ctrl /itemnotify in pack%s %s leftmouseup', pack, slot)
    end

    -- Debug.Assert()
    if (actions.GetFirstEmptyTopLevelSlot() == nil) then
        logger.error("We thought we made a top-level slot but we was wrong")
        return
    end

    -- Move relevant container to top level slot
    actions.PickupInventoryItemById(item.ID())
    mq.cmd('/autoinv')
    if (actions.IsItemInTopLevelSlot(item) == false) then
        logger.error('\at Failed to put item in top-level slot: %s', item.Name())
        return
    end

    return true, item_to_move
end

function actions.MoveItemToTopLevelSlotById(item_id)
    local item = mq.TLO.FindItem(item_id)
    if (item() == nil) then
        logger.error('Specified item not found: %s', item_id)
        return false, nil
    end

    return actions.MoveItemToTopLevelSlot(item)
end

function actions.WaitForWindow(window_name, delay_time)
	if (delay_time == nil) then delay_time = 5000 end
	mq.delay(delay_time, function() return mq.TLO.Window(window_name).Open() end)
end

function actions.OpenWindow(window_name, command, delay_time)
    if (mq.TLO.Window(window_name).Open() == true) then return end

    mq.cmd('/keypress '..command)
    actions.WaitForWindow('TaskWnd', delay_time)
end

function actions.SelectTask(task)
    mq.cmdf('/notify TaskWnd Task_TaskList listselect %s leftmouseup', task.WindowIndex())
end

function actions.GroupHasClass(class_short_name)
    return actions.GetGroupMemberByClass(class_short_name) ~= nil
end

function actions.GroupHasMage()
    return actions.GetGroupMemberByClass('MAG') ~= nil
end

function actions.GroupMageCothMe()
    local mage = actions.GetGroupMemberByClass('MAG')
    if (mage == nil) then return false end
    actions.send_individual_message(mage.Name(), '/targ id '..mq.TLO.Me.ID())
    mq.delay(100)
    actions.send_individual_message(mage.Name(), '/alt act 7050')
end

local function event_cannot_enter()
    logger.debug('\ar Zone Not Ready notice seen.');
    event_cannot_enter_seen = true
end

mq.event('cannot_enter', "#*#A strange magical presence prevents you from entering.  It's too dangerous to enter at the moment.#*#", event_cannot_enter)

return actions