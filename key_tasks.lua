local mq = require('mq')
local logger = require('utils.logger')
local lua_utils = require('utils.lua_utils')
local mq_utils = require('utils.mq_utils')
local tower = require('tower_travel')

local actions = {}

local set_status_delegate = nil
local function SetStatus(message, ...)
    if (set_status_delegate == nil) then return end

    if (... ~= nil) then
        message = string.format(message, ...)
    end

    set_status_delegate(message)
end

local function DoStep(task, step, action)
    local objective = task.Objective(step)
    if (objective.Status() == "Done" or (objective.CurrentCount() ~= nil and objective.RequiredCount() ~= nil and objective.CurrentCount() >= objective.RequiredCount())) then
        logger.debug('Step %s is done.', step)
        return true
    elseif (objective.Status() == nil) then
        logger.trace('Step %s hasnt been unlocked. Jumping back to top.', step)
        mq.delay(1000)
        return false
    end

    logger.info('\agExecuting step %s.', step)
    local result = action(objective)
    mq.delay(500)
    return result
end

local function DoSteps(task, steps)
    while (task ~= nil) do
        if (task.Step == nil or task.Step() == nil) then
            return true
        end

        local step_index = task.Step.Index()
        local callback = steps[step_index]
        if (callback == nil) then
            logger.error('No callback defined for task step %s', tostring(step_index))
            return false
        end

        local result = DoStep(task, step_index, callback)
        if (result == false) then
            logger.error('Task step %s failed', tostring(step_index))
            return false
        end
    end

    return true
end

local function AcceptRewardSelection()
    for attempt = 1, 20 do
        if (mq.TLO.Window('RewardSelectionWnd').Open() == true) then
            logger.info('Reward window detected, accepting reward (attempt %s)', tostring(attempt))

            mq.cmd('/notify RewardSelectionWnd RewardSelectionChooseButton leftmouseup')

            local closed = mq.delay(2000, function()
                return mq.TLO.Window('RewardSelectionWnd').Open() ~= true
            end)

            mq.delay(300)
            mq_utils.AddCursorItemsToInventory(true)
            mq.delay(300)
            mq_utils.AddCursorItemsToInventory(true)

            if closed then
                return true
            end

            logger.warning('Reward window click was sent but window did not close on attempt %s', tostring(attempt))
        end

        mq.delay(500)
    end

    logger.info('No reward selection window appeared during reward polling window')
    mq_utils.AddCursorItemsToInventory(true)
    mq.delay(300)
    mq_utils.AddCursorItemsToInventory(true)
    return true
end

local function DoCombine(key_task_details)
    local function FindContainer()
        return mq.TLO.FindItem(key_task_details.container_id)
    end

    local function GetPackSlot(container)
        if (container() == nil or container.ID() == nil) then
            return nil, nil
        end

        local item_slot = container.ItemSlot()
        if (item_slot == nil) then
            return nil, nil
        end

        return item_slot, item_slot - 22
    end

    local function EnsurePackWindowOpen(pack)
        local window_name = 'Pack' .. tostring(pack)

        mq_utils.OpenWindow('InventoryWindow', 'Inventory')
        mq.delay(500)

        if (mq.TLO.Window(window_name).Open() == true) then
            logger.info('Combine container window %s already open.', window_name)
            return true
        end

        for attempt = 1, 6 do
            mq_utils.OpenWindow('InventoryWindow', 'Inventory')
            mq.delay(300)

            logger.info('Opening combine container in pack slot %s (attempt %s)', tostring(pack), tostring(attempt))
            mq.cmdf('/itemnotify pack%s rightmouseup', pack)

            mq.delay(200)
            local immediate_state = mq.TLO.Window(window_name).Open()
            logger.info('Immediate %s open state after click: %s', window_name, tostring(immediate_state))

            mq.delay(500)
            local short_state = mq.TLO.Window(window_name).Open()
            logger.info('500ms %s open state after click: %s', window_name, tostring(short_state))

            mq.delay(1000)
            local settle_state = mq.TLO.Window(window_name).Open()
            logger.info('1500ms %s open state after click: %s', window_name, tostring(settle_state))

            if (settle_state == true) then
                return true
            end

            mq.delay(500)
        end

        return false
    end

    mq_utils.AddCursorItemsToInventory(true)
    mq.delay(200)

    local container = FindContainer()
    if (container() == nil or container.ID() == nil) then
        logger.error('Combine failed: container not found')
        return false
    end

    local item_slot, pack = GetPackSlot(container)
    if (item_slot == nil) then
        logger.error('Combine failed: container has no ItemSlot')
        return false
    end

    if (pack < 1 or pack > 10) then
        logger.error('Combine failed: container is not in a top-level inventory slot. ItemSlot=%s Pack=%s', tostring(item_slot), tostring(pack))
        return false
    end

    logger.info(
        'Combine container debug: name=%s id=%s itemslot=%s pack=%s',
        tostring(container.Name()),
        tostring(container.ID()),
        tostring(item_slot),
        tostring(pack)
    )

    if not EnsurePackWindowOpen(pack) then
        logger.error('Combine failed: pack window Pack%s did not open', tostring(pack))
        return false
    end

    mq_utils.AddItemToPack(key_task_details.item1_blade_id, pack, 1)
    mq.delay(300)
    mq_utils.AddItemToPack(key_task_details.item2_bow_id, pack, 2)
    mq.delay(300)
    mq_utils.AddItemToPack(key_task_details.item3_biting_id, pack, 3)
    mq.delay(300)

    if (key_task_details.additional_item_ids ~= nil) then
        local pack_slot = 4
        for _, additional_item_id in ipairs(key_task_details.additional_item_ids) do
            mq_utils.AddItemToPack(additional_item_id, pack, pack_slot)
            mq.delay(300)
            pack_slot = pack_slot + 1
        end
    end

    mq_utils.CombinePack(pack)
    logger.info('Combine completed for pack %s, waiting for reward handling', tostring(pack))
    mq.delay(1000)

    if not AcceptRewardSelection() then
        logger.error('Combine succeeded but reward selection failed')
        return false
    end

    return true
end

local check_and_loot_all = function(items)
    local missing_item = false
    for _, item in pairs(items) do
        if (mq.TLO.FindItemCount(item)() == 0) then
            if (mq_utils.LootItemById(item) == false) then
                missing_item = true
            end
        end
    end
    return missing_item
end

local check_and_loot_all_task_items = function(key_task_details)
    local items = {
        key_task_details.item1_blade_id,
        key_task_details.item2_bow_id,
        key_task_details.item3_biting_id
    }
    return check_and_loot_all(items)
end

local function Task_KeyOfSands(task, level)
    local key_task_details = level.key.task
    local steps = {
        function() mq_utils.MoveToLoc('828, -2284, 44') end,
        function() mq_utils.KillAllBaddiesIfUp("orc oracle", 100) end,
        function() mq_utils.LootItemById(key_task_details.item1_blade_id) end,
        function() mq_utils.MoveToLoc('2034, -508, 97 ') end,
        function() mq_utils.KillAllBaddiesIfUp("sandstorm champion", 100) end,
        function() mq_utils.LootItemById(key_task_details.item2_bow_id) end,
        function() mq_utils.MoveToLoc('3791, -1535, 22 ') end,
        function() mq_utils.KillAllBaddiesIfUp("haunting spectre", 100) end,
        function() mq_utils.LootItemById(key_task_details.item3_biting_id) end,
        function() DoCombine(key_task_details) end,
    }

    return DoSteps(task, steps)
end

local function Task_KeyOfLava(task, level)
    local function GetItem(task_item_details)
        check_and_loot_all_task_items(task_item_details)

        ::find_next::
        mq.cmd('/nav spawn magma rockpile |dist=10')
        while mq.TLO.Navigation.Active() do mq.delay(100) end

        local rockpile = mq.TLO.Spawn('magma rockpile')

        if (rockpile == nil or rockpile.Distance() > 20) then goto find_next end

        mq.cmdf('/target id %s', rockpile.ID())
        while (mq.TLO.Target.ID() ~= rockpile.ID()) do
            mq.delay(100)
        end

        logger.info('Digging into rockpile')
        local shovel = mq.TLO.FindItem('Shaledig Shovel')
        if shovel() then
            mq.cmdf('/useitem "%s"', shovel.Name())

            mq.delay(5000, function() return mq.TLO.SpawnCount('npc magma basilisk scavenger radius 40')() ~= 0 end)
            mq_utils.KillOneMob('magma basilisk scavenger', 40)

            mq.delay(200)

            mq_utils.KillAllOnXtarget()
            check_and_loot_all_task_items(task_item_details)
        end
    end

    local key_task_details = level.key.task
    local steps = {
        function() GetItem(key_task_details) end,
        function() GetItem(key_task_details) end,
        function() GetItem(key_task_details) end,
        function() DoCombine(key_task_details) end,
    }

    return DoSteps(task, steps)
end

local function Task_KeyOfForests(task, level)
    local kill_next = function(o, key_task_details, spawn_name)
        while (mq_utils.ObjectiveComplete(o) == false) do
            check_and_loot_all_task_items(key_task_details)
            if (mq_utils.ObjectiveComplete(o)) then return end

            mq.cmd('/hidecorpse all')
            mq_utils.KillOneMob(spawn_name)
            check_and_loot_all_task_items(key_task_details)
            mq_utils.KillAllOnXtarget()
        end
    end

    local key_task_details = level.key.task
    local steps = {
        function(o) kill_next(o, key_task_details, 'enslaved miner') end,
        function(o) kill_next(o, key_task_details, 'enslaved miner') end,
        function(o) kill_next(o, key_task_details, 'enslaved miner') end,
        function() mq_utils.MoveToLoc('2104, 2041, 0') end,
        function(o) kill_next(o, key_task_details, 'orc slaver') end,
        function() mq_utils.LootItemById() end,
        function() DoCombine(key_task_details) end,
    }

    return DoSteps(task, steps)
end

local function Task_KeyOfFrost(task, level)
    local key_task_details = level.key.task
    local items = {
        162066,
        162067,
        162068,
    }

    local surface_kill_mob = function(spawn_name)
        local spawn = mq.TLO.Spawn('npc ' .. spawn_name)
        if (spawn.ID() == nil) then
            logger.warning('No %s found.', spawn_name)
            return false
        end

        ::nav_closer::
        mq.cmdf('/nav locxy %s %s', spawn.X(), spawn.Y())
        while (mq.TLO.Navigation.Active()) do mq.delay(50) end

        if (spawn.Type() ~= "NPC") then
            logger.warning('%s died before engagement.', spawn_name)
            return false
        end

        mq.cmdf('/target id %d', spawn.ID())
        mq.delay(1000, function() return mq.TLO.Target.ID() == spawn.ID() end)

        mq.cmd('/pet attack')
        while (spawn.Type() == "NPC") do
            mq.delay(100)
        end

        return true
    end

    local frost_kill_fish = function(spawn_name)
        if (mq.TLO.Me.Pet.ID() > 0) then
            surface_kill_mob(spawn_name)
        else
            mq_utils.KillOneMob(spawn_name)
        end
    end

    local swim_into_icehole = function()
        if (mq.TLO.Me.Underwater() == true) then return end
        mq.cmd('/removelev')
        mq_utils.MoveToLoc('1345.12 -4576.71 -101.10')
        mq.cmd('/face heading 350')
        mq.cmd('/keypress pitchdown hold')
        mq.delay(3000)
        mq.cmd('/keypress pitchdown')

        mq.cmd('/keypress forward hold ')
        mq.delay(3000)
        mq.cmd('/keypress forward')
        mq.cmd('/nav spawn frost-covered')
        while mq.TLO.Navigation.Active() do mq.delay(1) end
        mq.cmd('/nav spawn polar')
        while mq.TLO.Navigation.Active() do mq.delay(1) end
        mq.cmd('/nav spawn deepwater')
        while mq.TLO.Navigation.Active() do mq.delay(1) end

        if (mq.TLO.Me.Underwater() == false) then
            SetStatus("Cannot enter the Ice Hole.  Please help...")
            mq.cmd('/beep')
            mq.cmd('/beep')
            while (mq.TLO.Me.Underwater() == false) do
                mq.delay(1000, function() return mq.TLO.Me.Underwater() end)
            end
            SetStatus('')
        end
    end

    local function InIceHole()
        return mq.TLO.Me.Underwater() == true or mq.TLO.Me.Z() <= -106
    end

    local swim_outta_icehole = function()
        if (InIceHole() == false) then return end

        mq_utils.MoveToLocXy('-4608.71 -856.67')

        mq.cmd('/face heading 80')

        mq.cmd('/keypress pitchup hold')
        mq.delay(5000)
        mq.cmd('/keypress pitchup')

        mq.cmd('/keypress forward hold ')
        mq.delay(5000)
        mq.cmd('/keypress forward')

        if (InIceHole() == true) then
            SetStatus("Cannot leave the Ice Hole.  Please help...")
            logger.warning('Cannot leave ice hole.  Please help guide character out.')
            mq.cmd('/beep')
            mq.cmd('/beep')
            while (InIceHole() == true) do
                mq.delay(1000, function() return mq.TLO.Me.Underwater() == false end)
            end
            SetStatus('')
        end
    end

    local do_ice_step = function(spawn_name, objective)
        swim_into_icehole()

        while mq_utils.ObjectiveComplete(objective) == false do
            check_and_loot_all(items)
            frost_kill_fish(spawn_name)
            mq.delay(1000)
            check_and_loot_all(items)
            mq_utils.KillAllOnXtarget()
            mq.delay(250)
        end

        check_and_loot_all(items)
    end

    local steps = {
        function()
            swim_into_icehole()
        end,
        function(objective) do_ice_step("a frost-covered cod", objective) end,
        function(objective) do_ice_step("polar char", objective) end,
        function(objective) do_ice_step("deepwater", objective) end,
        function()
            swim_outta_icehole()
            logger.info('Out of ice.  Continuing')
            mq_utils.MoveToLoc("2831, -981, -48")
        end,
        function() mq_utils.MoveToLoc("2831, -981, -48") end,
        function() mq_utils.KillAllBaddiesIfUp("a hungry polar bear") end,
        function() mq_utils.AddCursorItemsToInventory() end,
        function()
            mq_utils.AddCursorItemsToInventory()
            mq_utils.MoveToLoc("874, 148, -45")
        end,
        function() mq_utils.MoveToLoc("874, 148, -45") end,
        function() mq_utils.KillAllBaddiesIfUp("a hungry polar bear") end,
        function() mq_utils.AddCursorItemsToInventory() end,
        function()
            mq_utils.AddCursorItemsToInventory()
            mq_utils.MoveToLoc("-1388.32 1167.07 -59.47")
        end,
        function() mq_utils.MoveToLoc("-1388.32 1167.07 -59.47") end,
        function() mq_utils.KillAllBaddiesIfUp("a hungry polar bear") end,
        function()
            mq_utils.AddCursorItemsToInventory()
            mq_utils.AddCursorItemsToInventory()
        end,
        function() DoCombine(key_task_details) end,
    }

    return DoSteps(task, steps)
end

local function Task_KeyOfSky(task, level)
    local key_task_details = level.key.task
    local steps = {
        function() mq_utils.MoveToSpawnName('Ro`Ken Redfeather') end,
        function() mq_utils.MoveToAndSay('Ro`Ken Redfeather', 'Water') end,
        function() mq_utils.MoveToLoc('909.90 918.86 -22.33') end,
        function() mq_utils.KillOneMob("gnoll troublemaker", 50) end,
        function() mq_utils.LootItemById(key_task_details.item1_blade_id) end,

        function() mq_utils.MoveToAndSay('Vo`Ken', 'Shiny') end,
        function() mq_utils.MoveToLoc('913.65 -492.34 -24.26') end,
        function() mq_utils.KillOneMob("gnoll troublemaker", 50) end,
        function() mq_utils.LootItemById(key_task_details.item2_bow_id) end,

        function() mq_utils.MoveToAndSay('Go`Ken', 'falling') end,
        function() mq_utils.MoveToLoc('2221.66 913.28 -24.50') end,
        function() mq_utils.MoveToLoc('2313.00 932.25 -28.48') end,
        function() mq_utils.MoveToLoc('2195.00 922 -26.38') end,

        function() mq_utils.KillOneMob("gnoll troublemaker", 50) end,
        function() mq_utils.LootItemById(key_task_details.item3_biting_id) end,

        function() DoCombine(key_task_details) end,
    }

    return DoSteps(task, steps)
end

local function Task_KeyOfSteam(task, level)
    local key_task_details = level.key.task
    local steps = {
        function()
            mq_utils.MoveToLoc('1595.93 1689.28 14.01')
            mq_utils.GetGroundSpawn('Drop12537', 100, true)
        end,
        function()
            mq_utils.MoveToLoc('-320.51 1486.21 4.88')
            mq_utils.GetGroundSpawn('Drop12537', 100, true)
        end,
        function() mq_utils.MoveToLoc('-949, 1474, -69') end,
        function() mq_utils.KillAllBaddiesIfUp("grikbar champion") end,
        function() mq_utils.LootItemById(key_task_details.item3_biting_id) end,
        function() DoCombine(key_task_details) end,
    }

    return DoSteps(task, steps)
end

local function Task_KeyOfJungle(task, level)
    local key_task_details = level.key.task

    local function still_missing_task_items()
        return check_and_loot_all_task_items(key_task_details)
    end

    local function open_chest_and_loot()
        if not still_missing_task_items() then
            logger.info('All Jungle key items already collected.')
            return true
        end

        mq_utils.MoveToAndOpen('a broken chest')
        mq.delay(500)
        mq_utils.AddCursorItemsToInventory(true)
        mq.delay(300)

        if not still_missing_task_items() then
            logger.info('Collected missing Jungle key item(s) after opening chest.')
            return true
        end

        logger.info('Still missing Jungle key item(s); chest attempt did not complete objective.')
        return false
    end

    local steps = {
        function() return open_chest_and_loot() end,
        function() return open_chest_and_loot() end,
        function() return open_chest_and_loot() end,
        function() return DoCombine(key_task_details) end,
    }

    return DoSteps(task, steps)
end

local function Task_KeyOfFire(task, level)
    local key_task_details = level.key.task
    local steps = {
        function() mq_utils.MoveToSpawnName('disturbed_nest02') end,
        function()
            mq_utils.MoveToSpawnName('disturbed_nest02')
            mq_utils.KillOneMob("ravenous devourer", 500)
        end,
        function() mq_utils.MoveToSpawnName('disturbed_nest02') end,
        function(objective)
            mq_utils.MoveToSpawnName('disturbed_nest02')
            while (mq_utils.ObjectiveComplete(objective) == false) do
                mq_utils.KillOneMob("an enraged wyvern")
                mq.delay(100)
            end
        end,
        function() mq_utils.LootItemById(key_task_details.item1_blade_id) end,
        function() mq_utils.MoveToSpawnName('disturbed_nest01') end,
        function()
            mq_utils.MoveToSpawnName('disturbed_nest01')
            mq_utils.KillOneMob("ravenous devourer", 500)
        end,
        function() mq_utils.MoveToSpawnName('disturbed_nest01') end,
        function(objective)
            mq_utils.MoveToSpawnName('disturbed_nest01')
            while (mq_utils.ObjectiveComplete(objective) == false) do
                mq_utils.KillAllBaddiesIfUp("an enraged wyvern")
                mq.delay(100)
            end
        end,
        function() mq_utils.LootItemById(key_task_details.item2_bow_id) end,
        function() mq_utils.MoveToSpawnName('disturbed_nest00') end,
        function()
            mq_utils.MoveToSpawnName('disturbed_nest00')
            mq_utils.KillOneMob("ravenous devourer", 500)
        end,
        function() mq_utils.MoveToSpawnName('disturbed_nest00') end,
        function(objective)
            mq_utils.MoveToSpawnName('disturbed_nest00')
            while (mq_utils.ObjectiveComplete(objective) == false) do
                mq_utils.KillAllBaddiesIfUp("an enraged wyvern")
                mq.delay(100)
            end
        end,
        function() mq_utils.LootItemById(key_task_details.item3_biting_id) end,
        function() DoCombine(key_task_details) end,
    }

    return DoSteps(task, steps)
end

local function Task_KeyOfSwamps(task, level)
    local egg_hunt = function()
        mq_utils.KillAllBaddiesIfUp("swamp leech broodmother", 500)
        mq_utils.AddCursorItemsToInventory()
        mq_utils.KillAllBaddiesIfUp("swamp leech hatchling", 500)
        mq_utils.AddCursorItemsToInventory()

        local egg_spawn = mq_utils.GetClosestSpawn('unhatched swamp leech eggs')
        if (egg_spawn == nil) then return end

        ::move_closer::
        local loc = string.format("%s %s", egg_spawn.X(), egg_spawn.Y())
        mq_utils.MoveToLocXy(loc)
        if (nil ~= egg_spawn.Distance() and egg_spawn.Distance() > 10) then mq.delay(1000) goto move_closer end

        ::target_again::
        egg_spawn.DoTarget()
        if (mq.TLO.Target.ID() ~= egg_spawn.ID()) then mq.delay(100) goto target_again end

        mq.cmd('/face')
        mq.delay(100)
        mq.cmd('/attack on')
        mq.delay(100)

        mq_utils.KillAllBaddiesIfUp("swamp leech broodmother", 500)
        mq_utils.AddCursorItemsToInventory()
        mq_utils.KillAllBaddiesIfUp("swamp leech hatchling", 500)
        mq_utils.AddCursorItemsToInventory()
    end

    local key_task_details = level.key.task
    local steps = {
        function() egg_hunt() end,
        function() egg_hunt() end,
        function() egg_hunt() end,
        function() egg_hunt() end,
        function() DoCombine(key_task_details) end,
    }

    return DoSteps(task, steps)
end

local function Task_KeyOfFear(task, level)
    local spawn_name = 'a thulian tarantula'
    local follow_spider = function(o)
        mq.cmd('/removelev')
        logger.info('Waiting for spawn: \ay %s', spawn_name)
        mq_utils.WaitForSpawn(spawn_name)
        logger.info('\ay Spawn seen: \ay Following')
        mq_utils.FollowSpawn(o, spawn_name, 30)
        logger.info('\ay Spawn: \ay Done following')
    end

    local steps = {
        function() mq_utils.MoveToLocXy('2335 970') end,
        function(o) follow_spider(o) end,
        function(o) follow_spider(o) end,
        function()
            mq_utils.KillAllOnXtarget()
            mq_utils.AddCursorItemsToInventory(true)
        end,
        function(o) follow_spider(o) end,
        function(o) follow_spider(o) end,
        function()
            mq_utils.KillAllOnXtarget()
            mq_utils.AddCursorItemsToInventory(true)
        end,
        function(o) follow_spider(o) end,
        function(o) follow_spider(o) end,
        function()
            mq_utils.KillAllOnXtarget()
            mq_utils.AddCursorItemsToInventory(true)
        end,
        function() DoCombine(level.key.task) end,
    }

    return DoSteps(task, steps)
end

local function Task_KeyOfVoid(task, level)
    local rift_hunt = function(o)
        while (mq_utils.ObjectiveComplete(o) == false) do
            mq_utils.KillOneMob('rift', 5000, true)
            mq_utils.KillAllBaddiesIfUp("a discordant golem", 200)
            mq_utils.KillAllBaddiesIfUp("a discordant dragorn invader", 200)
            mq_utils.KillAllOnXtarget()
            mq_utils.AddCursorItemsToInventory()
        end
    end

    local key_task_details = level.key.task
    local steps = {
        function(o) rift_hunt(o) end,
        function(o) rift_hunt(o) end,
        function(o) rift_hunt(o) end,
        function(o) rift_hunt(o) end,
        function() DoCombine(key_task_details) end,
    }

    return DoSteps(task, steps)
end

local function Task_KeyOfDragons(task, level)
    local inspect_altar = function(altar)
        mq_utils.MoveToSpawnName(altar, true)
        mq.cmdf('/nav spawn %s', altar)
        while mq.TLO.Navigation.Active() do mq.delay(100) end
        mq.cmdf('/squelch /target %s', altar)
        mq.delay(500)
        mq.cmd('/inspect')
        mq.delay(1000)
    end

    local kill_things = function(o)
        while (mq_utils.ObjectiveComplete(o) == false) do
            mq_utils.KillOneMob("an inferno goblin ritualist")
            mq_utils.KillAllOnXtarget()
            mq.delay(100)
        end
    end

    local key_task_details = level.key.task
    local steps = {
        function(_) inspect_altar('smoldering_dragon_altar00') end,
        function(o) kill_things(o) end,
        function(_) inspect_altar('burning_dragon_altar00') end,
        function(o) kill_things(o) end,
        function(_) inspect_altar('searing_dragon_altar00') end,
        function(o) kill_things(o) end,
        function() DoCombine(key_task_details) end,
    }

    return DoSteps(task, steps)
end

local function DestroyInventoryItem(item_id)
    if (mq.TLO.FindItemCount(item_id)() == 0) then return end
    if (mq_utils.PickupInventoryItemById(item_id) == false) then return end

    mq.cmd('/destroy')

    mq.delay(2000, function() return not mq.TLO.Cursor.ID() end)
end

local function HasAllTaskCombineItems(task_details)
    if (mq.TLO.FindItemCount(task_details.item1_blade_id)() == 0) then return false end
    if (mq.TLO.FindItemCount(task_details.item2_bow_id)() == 0) then return false end
    if (mq.TLO.FindItemCount(task_details.item3_biting_id)() == 0) then return false end

    if (task_details.additional_item_ids ~= nil) then
        for _, additional_id in pairs(task_details.additional_item_ids) do
            if (mq.TLO.FindItemCount(additional_id)() == 0) then
                return false
            end
        end
    end

    return true
end

local function CleanupInventory(level)
    if (HasAllTaskCombineItems(level.key.task)) then
        logger.info('Preserving existing combine items for task: %s', level.key.task.name)
        return
    end

    if (level.key.task.additional_item_ids ~= nil) then
        for _, additional_id in pairs(level.key.task.additional_item_ids) do
            DestroyInventoryItem(additional_id)
        end
    end

    DestroyInventoryItem(level.key.task.item1_blade_id)
    DestroyInventoryItem(level.key.task.item2_bow_id)
    DestroyInventoryItem(level.key.task.item3_biting_id)
    DestroyInventoryItem(level.key.task.container_id)
end

local function travel_to_tower()
    local current_zone = mq.TLO.Zone.ShortName()
    if (current_zone == 'anniversarytower') then return end

    if (current_zone == 'northro' or current_zone == 'southro') then goto finish_travel end

    if (Settings.general.UseNroPortClicky) then
        local successful = mq_utils.ActivateClickyItemIfAvailableById(111209, nil, 60)
        if (successful) then
            logger.info('Clicked North Ro clicky... waiting for zone.')
            mq_utils.WaitForZone()
            goto finish_travel
        else
            logger.debug('Cannot activate North Ro Outlook device')
        end

        local zueria = mq.TLO.FindItem('Zueria Slide')

        if (zueria.ID() == nil) then goto finish_travel end

        if (zueria.ID() ~= 146385 and zueria.ItemSlot() < 23) then
            logger.warning('Zueria Slide not set to North Ro.  Cannot change while in keyring. Not using.')
            goto finish_travel
        end

        logger.info('Initiating /relocate nro for Zuria Slide usage.')
        mq.cmd('/relocate nro')
        mq.delay(10000, function() return mq.TLO.Me.CastTimeLeft() > 0 end)
        if (zueria.ID() ~= 146385) then
            zueria = mq.TLO.FindItem(146385)
            if (zueria.ID() ~= 146385) then
                logger.warning('Incorrect Zuria Slide situation.')
                return
            end
        end
        mq.delay(zueria.CastTime() + 100, function() return (mq.TLO.Me.CastTimeLeft() == 0 or zueria.TimerReady() > 0) end)
        logger.info('Clicked Zueria slide... waiting for zone.')
        mq_utils.WaitForZone()
        goto finish_travel
    end

    ::finish_travel::
    logger.info('Running to anniversary tower.')
    mq_utils.TravelTo('anniversarytower')
end

local function travel_to_nontower_zone(zone_name)
    if (zone_name == 'northro' or zone_name == 'southro') then goto finish_travel end

    if (Settings.general.UseGateSpell and mq.TLO.Me.AltAbility(1217)() ~= nil) then
        local gate_aa = mq.TLO.Me.AltAbility(1217)
        while (mq.TLO.Me.AltAbilityReady(1217) == false) do
            mq.delay(100)
        end

        mq.cmdf('/alt act %s', mq.TLO.Me.AltAbility(1217))
        mq.delay(gate_aa.Spell.CastTime() + 1000, function() return (mq.TLO.Me.CastTimeLeft() == 0 or mq.TLO.Me.AltAbilityReady(1217) == false) end)
        mq_utils.WaitForZone()
        goto finish_travel
    end

    if (Settings.general.UseGateSpell and mq.TLO.FindItemCount('Bulwark of Many Portals')() > 0) then
        mq.cmd('/useitem "Bulwark of Many Portals"')
        mq.delay(500)
        mq_utils.WaitForZone()
        goto finish_travel
    end

    ::finish_travel::
    if (mq.TLO.Zone.ShortName() == 'anniversarytower') then
        tower.MoveToLevel(1)
    end

    mq_utils.TravelTo(zone_name)
end

function actions.AcquireTask(level, silent)
    if (silent == nil) then silent = false end
    local current_task = mq.TLO.Task(level.key.task.name)
    if (current_task ~= nil and current_task() ~= nil) then
        if (silent ~= false) then
            logger.info('Already have task: %s', level.key.task.name)
        end
        return current_task
    end

    if (silent ~= false) then
        SetStatus('Acquiring quest-requestor for %s', level.key.task.name)
    end

    CleanupInventory(level)

    local key_task_ground_item = mq.TLO.FindItem(level.key.task.request_item_id)
    if (key_task_ground_item() == nil) then
        logger.info('Traveling to get quest item initiator for \at%s', level.key.task.name)
        travel_to_tower()
        tower.MoveToLevel(level.level)
        mq_utils.GetGroundSpawn('Drop12537', 100, true)

        mq_utils.AddCursorItemsToInventory(true)
        key_task_ground_item = mq.TLO.FindItem(level.key.task.request_item_id)
    end

    mq.cmdf('/shift /itemnotify "%s" rightmouseup', key_task_ground_item.Name())
    mq_utils.AddCursorItemsToInventory(true)

    if level.key.task.name == 'Broken Key of Lava' then
        mq.delay(300)
        local cursor_name = mq.TLO.Cursor.Name()
        if cursor_name ~= nil and string.lower(cursor_name) == 'shaledig shovel' then
            mq.cmd('/autoinv')
            mq.delay(300)
        end
    end

    mq.delay(5000, function() return mq.TLO.Task(level.key.task.name).ID() ~= nil end)
    current_task = mq.TLO.Task(level.key.task.name)
    if (current_task() == nil) then
        logger.error('Unable to acquire task for some reason: %s', level.key.task.name)
    end

    return current_task
end

function actions.RunKeyTask(level, refresh_all_delegate, part_of_set)
    if (level.key.task.task_delegate == nil) then
        logger.error('No Key Task Script Specified for: %s', level.key.task.name)
        return false
    end

    local task = actions.AcquireTask(level)
    if (task == nil) then
        logger.error('Unable to request task for: %s', level.key.task.name)
        SetStatus('Unable to request task for: %s', level.key.task.name)
        return false
    end

    SetStatus('Running %s', level.key.task.name)

    local task_container = mq.TLO.FindItem(level.key.task.container_id)
    if (task_container() == nil or task_container.ID() == nil) then
        logger.error('Expected task container not found: %s', level.key.task.name)
        return false
    end

    local move_item_result, moved_item = mq_utils.MoveItemToTopLevelSlot(task_container)
    if (move_item_result ~= true) then
        logger.error('Failed to move task container to top-level slot: %s', level.key.task.name)
        return false
    end

    mq.delay(1000)
    mq_utils.AddCursorItemsToInventory(true)
    mq.delay(300)

    task_container = mq.TLO.FindItem(level.key.task.container_id)
    if (task_container() == nil or task_container.ID() == nil) then
        logger.error('Task container disappeared after move: %s', level.key.task.name)
        return false
    end

    level.key.task.container_name = task_container.Name()

    mq.cmd('/cleanup')
    mq.delay(200)
    mq.cmd('/cleanup')
    mq_utils.OpenWindow('TaskWnd', 'CMD_TOGGLETASKWIN')
    mq_utils.SelectTask(task)

    if (mq.TLO.Zone.ShortName() ~= level.key.task.zone) then
        travel_to_nontower_zone(level.key.task.zone)
    end

    local ok = level.key.task.task_delegate(task, level)

    local updated_task = mq.TLO.Task(level.key.task.name)
    local task_complete = false

    if ok == true then
        if (updated_task == nil or updated_task() == nil) then
            task_complete = true
        elseif (updated_task.Step == nil or updated_task.Step() == nil) then
            task_complete = true
        end
    end

    if not task_complete then
        logger.error('Task did not complete successfully: %s', level.key.task.name)
        SetStatus('Task failed or did not complete: %s', level.key.task.name)

        if (move_item_result == true and moved_item ~= nil) then
            logger.info('Returning item after failed task: %s', moved_item.Name())
            mq_utils.MoveItemToTopLevelSlot(moved_item)
        end

        return false
    end

    level.key.task.selected = false

    SetStatus('')
    if (refresh_all_delegate ~= nil) then
        refresh_all_delegate()
    end
    if (part_of_set ~= true and Settings.key_tasks.returnToTowerWhenDone) then
        travel_to_tower()
    end

    if (move_item_result == true and moved_item ~= nil) then
        logger.info('Returning item to top-level slot: %s', moved_item.Name())
        mq_utils.MoveItemToTopLevelSlot(moved_item)
    end

    return true
end

function actions.RunSelectedKeyTasks(refresh_all_delegate)
    if (Settings.key_tasks.getAllTasksUpFront) then
        for _, level in lua_utils.spairs(tower.Levels) do
            if (level.is_available ~= nil and level.key.task.selected == true) then
                actions.AcquireTask(level, true)
            end
        end
    end

    for _, level in lua_utils.spairs(tower.Levels) do
        if (level.is_available ~= nil and level.key.task.selected == true) then
            actions.RunKeyTask(level, refresh_all_delegate, true)
        end
    end

    if (Settings.key_tasks.returnToTowerWhenDone) then
        travel_to_tower()
    end
end

function actions.Initialize(set_status_method)
    set_status_delegate = set_status_method

    tower.Levels["02"].key.task.task_delegate = Task_KeyOfSands
    tower.Levels["03"].key.task.task_delegate = Task_KeyOfLava
    tower.Levels["04"].key.task.task_delegate = Task_KeyOfForests
    tower.Levels["05"].key.task.task_delegate = Task_KeyOfFrost
    tower.Levels["06"].key.task.task_delegate = Task_KeyOfSky
    tower.Levels["07"].key.task.task_delegate = Task_KeyOfSteam
    tower.Levels["08"].key.task.task_delegate = Task_KeyOfJungle
    tower.Levels["09"].key.task.task_delegate = Task_KeyOfFire
    tower.Levels["10"].key.task.task_delegate = Task_KeyOfSwamps
    tower.Levels["11"].key.task.task_delegate = Task_KeyOfFear
    tower.Levels["12"].key.task.task_delegate = Task_KeyOfVoid
    tower.Levels["13"].key.task.task_delegate = Task_KeyOfDragons

    for _, level in pairs(tower.Levels) do
        if (level.mission ~= nil) then
            level.key.task.selected = level.is_available and level.key.task.task_delegate ~= nil and mq.TLO.FindItemCount(level.key.id)() == 0
            level.key.task_item = mq.TLO.Task(level.key.task.name)
        end
    end
end

return actions