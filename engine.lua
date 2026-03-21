local mq = require('mq')
local lip = require('lib.LIP')
require('ImGui')
local logger = require('utils.logger')
local lua_utils = require('utils.lua_utils')
local mq_utils = require('utils.mq_utils')
local key_tasks = require('key_tasks')
local tower = require('tower_travel')

---------------------------
--- CHANGE these per your desires
local delay_before_zoning = 20000 -- 20s
---------------------------------

MessagingApps = { "dannet", "bc" }

-- Do not change these. After script run once, actual values stored in
-- config > config/AnniversaryTower/AnniversaryTower_{charname}.ini
Settings = {
    general = {
        MessagingType = "dannet", -- or "bc"
        UseMageCoth = true,
        UnpauseOnMissionEnter = true,
        UseOptimizedNavigation = true,
        LogLevel = 4,
        QuestRequestor = nil,
        UseNroPortClicky = true,
        UsePoKPortClicky = true,
        UseGateSpell = true,
    },
    missions = {
        frost_UseLevitation = false,
        steam_UseLevitation = false,
        jungle_KillBarrels = true,
    },
    key_tasks = {
        returnToTowerWhenDone = true,
        getAllTasksUpFront = true
    },
    automation = {
        boxr = false,
        cwtn = false,
        kissassist = false,
        rgmercs = true,
    }
}
local actions = {}

---@type boolean
actions.InProcess = false
---@type boolean
actions.Aborting = false
---@type string
actions.CurrentProcessName = 'Idle'

actions.TestMode_NotRequestingMissions = false

local key_not_ready = false
local config_path = nil
local lower_level_group_complete
local upper_level_group_complete

local function file_exists(name)
    local f = io.open(name, "r")
    if f ~= nil then
        io.close(f)
        return true
    else
        return false
    end
end

local function ensure_dir(path)
    local normalized = path:gsub('/', '\\')
    os.execute(string.format('if not exist "%s" mkdir "%s"', normalized, normalized))
end

function actions.SaveSettings()
    lip.save(config_path, Settings)
end

function actions.set_log_level(level)
	logger.set_log_level(level)
	Settings.general.LogLevel = level
	actions.SaveSettings()
end

local function IsBoxrLoaded()
	return mq.TLO.Plugin("MQ2Boxr").IsLoaded()
end

local function load_settings()
    local config_root = mq.configDir:gsub('\\', '/')
    local config_subdir = config_root .. '/AnniversaryTower'
    ensure_dir(config_subdir)

    local config_file = string.format('AnniversaryTower_%s.ini', mq.TLO.Me.CleanName())
    config_path = config_subdir .. '/' .. config_file

    if (file_exists(config_path) == false) then
        lip.save(config_path, Settings)
    else
        local saved_settings = lip.load(config_path)

        -- Version updates
        local is_dirty = false

        -- Handle a blank file
        if (saved_settings.general == nil) then
            logger.info('Config file was empty. Updating to default settings.')
            is_dirty = true
        else
            Settings = saved_settings
        end

        local is_boxr_loaded = IsBoxrLoaded()

        if (Settings.general.UseNroPortClicky == nil) then
            Settings.general.UseNroPortClicky = true
            is_dirty = true
        end
        if (Settings.general.UsePoKPortClicky == nil) then
            Settings.general.UsePoKPortClicky = true
            is_dirty = true
        end
        if (Settings.general.UseGateSpell == nil) then
            Settings.general.UseGateSpell = false
            is_dirty = true
        end
        if (Settings.key_tasks == nil) then
            Settings.key_tasks = {
                returnToTowerWhenDone = true,
                getAllTasksUpFront = true,
            }
            is_dirty = true
        end
        if (Settings.missions == nil) then
            Settings.missions = {
                frost_UseLevitation = false,
                steam_UseLevitation = false
            }
            is_dirty = true
        end
        if (Settings.missions.jungle_KillBarrels == nil) then
            Settings.missions.jungle_KillBarrels = true
            is_dirty = true
        end
        if (Settings.general.UseMageCoth == nil) then
            Settings.general.UseMageCoth = true
            is_dirty = true
        end
        if (Settings.general.UnpauseOnMissionEnter == nil) then
            Settings.general.UnpauseOnMissionEnter = true
            is_dirty = true
        end
        if (Settings.automation == nil) then
            Settings.automation = {
                boxr = is_boxr_loaded,
                cwtn = not is_boxr_loaded,
                kissassist = not is_boxr_loaded,
                rgmercs = not is_boxr_loaded,
            }
            is_dirty = true
        end
        if (Settings.automation.boxr == nil) then
            Settings.automation.boxr = is_boxr_loaded
            if (is_boxr_loaded) then
                Settings.automation.cwtn = not is_boxr_loaded
                Settings.automation.kissassist = not is_boxr_loaded
                Settings.automation.rgmercs = not is_boxr_loaded
            end
            is_dirty = true
        end
        if (Settings.general.UseOptimizedNavigation == nil) then
            Settings.general.UseOptimizedNavigation = true
            is_dirty = true
        end
        if (Settings.general.LogLevel == nil) then
            Settings.general.LogLevel = 4
            is_dirty = true
        end
        if (is_dirty) then
            logger.trace('Writing settings to: %s', config_path)
            lip.save(config_path, Settings)
        end
    end

    if (Settings.general.MessagingType ~= 'dannet' and Settings.general.MessagingType ~= 'bc') then
        logger.warning('Messaging Type set to invalid value (%s). Defaulting to "dannet".', Settings.general.MessagingType)
        Settings.general.MessagingType = 'dannet'
    end

    mq_utils.set_messaging_type(Settings.general.MessagingType)
end

local function DoStep(task, step_index, action, display_message)
    local objective = task.Objective(step_index)
    if (objective.Status() == "Done") then
        logger.debug('Step %s is done.', step_index)
        return true
    elseif (objective.Status() == nil) then
        logger.info('Step %s hasnt been unlocked. Jumping back to top.', step_index)
        mq.delay(1000)
        return false
    end

    if (display_message) then
        logger.info('\agExecuting step %s.', step_index)
    end

    local result = action(objective)
    mq.delay(500)
    return result
end

local function SetGroupChaseMode(do_chase)
    if (do_chase) then
        if (Settings.automation.boxr) then
            mq_utils.send_others_message('/boxr chase')
        end
        if (Settings.automation.cwtn) then
            mq_utils.send_others_message_noparse('/docommand /${Me.Class.ShortName} mode 2')
        end
        if (Settings.automation.kissassist) then
            mq_utils.send_others_message('/chase on')
        end
        if (Settings.automation.rgmercs) then
            mq_utils.send_others_message('/rg chaseon')
            mq_utils.send_others_message('/rgl chaseon')
        end
    else
        if (Settings.automation.boxr) then
            mq_utils.send_others_message('/boxr manual')
        end
        if (Settings.automation.cwtn) then
            mq_utils.send_others_message_noparse('/docommand /${Me.Class.ShortName} mode 0')
        end
        if (Settings.automation.kissassist) then
            mq_utils.send_others_message('/chase off')
        end
        if (Settings.automation.rgmercs) then
            mq_utils.send_others_message('/rg chaseoff')
            mq_utils.send_others_message('/rgl chaseoff')
        end
    end
end

local function SetCurrentProcess(processName)
    actions.InProcess = true
    actions.CurrentProcessName = processName
end

actions.StatusMessage = ''
local function SetStatusMessage(message)
    actions.StatusMessage = message
end

local function ClearStatusMessage()
    actions.StatusMessage = ''
end

local function EndCurrentProcess()
    actions.Aborting = false
    actions.InProcess = false
    actions.CurrentProcessName = 'Idle'
end

local function DoSteps(task, steps)
    local last_step_index = 0
    while (task ~= nil) do
        if (task.Step == nil or task.Step() == nil) then return true end
        local callback = steps[task.Step.Index()]
        local is_new_step = last_step_index ~= task.Step.Index()
        DoStep(task, task.Step.Index(), callback, is_new_step)
        last_step_index = task.Step.Index()
    end
end

local function Mission_OasisOfSand(task)
    local step = function(objective)
        if (objective.Instruction() == 'Kill the mummified nomads') then
            mq_utils.KillAllBaddiesIfUp('a forsaken nomad')
            mq_utils.KillAllBaddiesIfUp('a mummified madman')
        elseif (objective.Instruction() == 'Kill the reanimated skeletons') then
            mq_utils.KillAllBaddiesIfUp('a dry bone skeleton')
            mq_utils.KillAllBaddiesIfUp('a sun bleached skeleton')
            mq_utils.KillAllBaddiesIfUp('a dry bone skeleton')
        elseif (objective.Instruction() == 'Kill the ancient crocodiles') then
            mq_utils.KillAllBaddiesIfUp('an ancient croc')
            mq_utils.KillAllBaddiesIfUp('a deepwater crocodile')
        else
            logger.error('MANUAL INTERVENTION NEEDED.  Pausing.  Unknown Quest Step: %s', objective.Instruction())
            --mq.cmd('/boxr pause')
        end
        mq_utils.KillAllOnXtarget()
    end

    local step3 = function()
        mq_utils.KillAllBaddiesIfUp('a withered memory')
    end
    local steps = {
        step,
        step,
        step3,
    }

    return DoSteps(task, steps)
end

local function Mission_OasisOfLava(task)
    local approach_queen = function() mq_utils.KillAllBaddiesIfUp('a molten brood queen') end
    local steps = {
        approach_queen,
        approach_queen
    }
    return DoSteps(task, steps)
end

local function Mission_OasisOfForests(task)
    local step1 = function(objective)
        if (objective.Instruction() == "Gain the orc centurions' attention and kill them") then
            mq_utils.KillAllOnXtarget()
            mq_utils.KillAllBaddiesIfUp('a sylvan bat')
            mq_utils.KillAllBaddiesIfUp('a forest drakeling')
            mq_utils.KillAllBaddiesIfUp('an orc centurion')
        elseif (objective.Instruction() == "Gain the decaying skeletons' attention and kill them") then
            mq_utils.KillAllOnXtarget()
            mq_utils.KillAllBaddiesIfUp('a sylvan bat')
            mq_utils.KillAllBaddiesIfUp('a forest drakeling')
            mq_utils.KillAllBaddiesIfUp('a rotting skeleton')
            mq_utils.KillAllBaddiesIfUp('a decaying skeleton')
        elseif (objective.Instruction() == "Gain the crazed arborean' attention and kill them") then
            mq_utils.KillAllOnXtarget()
            mq_utils.KillAllBaddiesIfUp('a sylvan bat')
            mq_utils.KillAllBaddiesIfUp('a forest drakeling')
            mq_utils.KillAllBaddiesIfUp('a crazed arborean')
        else
            mq_utils.KillAllOnXtarget()
            mq_utils.KillAllBaddiesIfUp('a sylvan bat')
            mq_utils.KillAllBaddiesIfUp('a forest drakeling')
            mq_utils.KillAllBaddiesIfUp('a crazed arborean')
        end
    end
    local step2 = function(objective)
        if (objective.Instruction() == "Kill the orc centurions") then
            mq_utils.KillAllOnXtarget()
            mq_utils.KillAllBaddiesIfUp('a giant wasp drone')
            mq_utils.KillAllBaddiesIfUp('an orc centurion')
        else
            mq_utils.KillAllOnXtarget()
            mq_utils.KillAllBaddiesIfUp('a giant wasp drone')
            mq_utils.KillAllBaddiesIfUp('an orc centurion')
            mq_utils.KillAllBaddiesIfUp('decaying skeleton')
            mq_utils.KillAllBaddiesIfUp('rotting skeleton')
        end
    end
    local step3 = function()
        mq_utils.KillAllBaddiesIfUp('an orc thaumaturgist')
        mq_utils.KillAllBaddiesIfUp('a decaying adventurer')
    end

    local steps = {
        step1,
        step2,
        step3,
    }
    return DoSteps(task, steps)
end

local function Mission_OasisOfFrost(task)
    local wake_mobs_step = function(mob_type)
        if (mq.TLO.Me.XTarget() > 0) then
            return
        end

        if (mq.TLO.FindItemCount(162069)() == 0) then
            logger.info('Grabbing Torch')
            if (mq_utils.GetGroundSpawn('Torch') == false) then
                return false
            end
            mq.cmd('/autoinv')
        end

        local targets = {}
        local mob_count = mq.TLO.SpawnCount(mob_type..' npc')()
        for i=1,mob_count do
            local mob = mq.TLO.NearestSpawn(i, mob_type..' npc')
            if (mob_type == 'undead' and (mob.CleanName() == 'Undead Basil' or mob.CleanName() == 'Undead Paglan' or mob.CleanName() == 'an undead guardian')) then
                goto next_mob
            end

            table.insert(targets, mob)
            ::next_mob::
        end

        for _, mob in pairs(targets) do
            logger.info('Moving to \ag%s\ao (\ag%s\ao)', mob.Name(), mob.ID())
            mq_utils.MoveToId(mob.ID())

            mq.delay(3000, function() return mq.TLO.Me.XTarget() > 0 end)
            if (mq.TLO.Me.XTarget() > 0) then
                return
            end
        end
    end

    local steps = {
        function() wake_mobs_step('undead') end,
        function() mq_utils.KillAllOnXtarget() end,
        function() wake_mobs_step('undead') end,
        function() mq_utils.KillAllOnXtarget() end,
        function() wake_mobs_step('guardian') end,
        function() mq_utils.KillAllOnXtarget() end,
        function()
            mq_utils.KillAllBaddiesIfUp('undead basil')
            mq_utils.KillAllBaddiesIfUp('Undead Paglan')
        end,
    }
    return DoSteps(task, steps)
end

local function Mission_OasisOfSky(task)
    local steps = {
        function() mq_utils.MoveToAndHail('guardian') end,
        function()
            mq_utils.MoveToSpawnNameAndAttack('guardian')
            mq_utils.KillAllOnXtarget()
        end,
        function()
            mq_utils.MoveToSpawnName('gnoll')
            mq_utils.KillAllOnXtarget()
        end,
    }
    return DoSteps(task, steps)
end

local function Mission_OasisOfSteam(task)
    local steps = {
        function() mq_utils.MoveToSpawnName('behemoth') end,
        function() mq_utils.MoveToSpawnName('scrounging') end,
        function() mq_utils.KillAllOnXtarget() end,
        function()
            mq_utils.KillAllOnXtarget()
            mq_utils.LootItemById(162070)
        end,           -- Rusted Gear Pile
        function() mq_utils.MoveToSpawnName('defective') end,
        function() mq_utils.KillAllOnXtarget() end,
        function()
            mq_utils.KillAllOnXtarget()
            mq_utils.LootItemById(162071) -- Rusted Pinion Gear
        end, 
        function() mq_utils.MoveToSpawnName('pool') end,
        function() mq_utils.KillAllOnXtarget() end,
        function()
            mq_utils.KillAllOnXtarget()
            mq_utils.LootItemById(162072) -- Vial of Roiling
        end,
        function() mq_utils.GiveItemsToNpc('behemoth', 162070, 162071, 162072) end,   -- 'Rusted Gear Pile'
        function() mq_utils.GiveItemsToNpc('behemoth', 162071) end,   -- 'Rusted Pinion Gear'
        function() mq_utils.GiveItemsToNpc('behemoth', 162072) end,    -- 'Vial of Roiling'
        function() mq_utils.KillAllBaddiesIfUp('behemoth') end,
        function() mq_utils.KillAllBaddiesIfUp('behemoth') end,
    }
    return DoSteps(task, steps)
end

local function Mission_OasisOfTheJungle(task)
    local function HandleBarrel(barrel_index)
        local barrel_name = 'an_explosive_barrel0'..barrel_index
        if (Settings.missions.jungle_KillBarrels) then
            local barrel_spawn = mq.TLO.Spawn(barrel_name)
            if (barrel_spawn ~= nil) then
                mq_utils.MoveToAndAttackId(barrel_spawn.ID())
                mq.cmd('/pet attack')
                if (mq.TLO.Group() ~= nil) then
                    mq_utils.send_others_message('/target id '..barrel_spawn.ID())
                    mq.delay(250)
                    mq_utils.send_others_message('/attack on')
                    mq_utils.send_others_message('/pet attack')
                end
            end
        elseif (barrel_index == 0) then
            -- Run to east side to avoid first boom-boom
            mq_utils.MoveToLoc('48.90 -24.80 323.12')
            mq_utils.WaitForNoSpawn(barrel_name)
        else
            -- Run to west side to avoid final 2 boom-booms
            mq_utils.MoveToLoc('67.18 153.24 322.94')
            mq_utils.WaitForNoSpawn(barrel_name)
        end
    end

    local steps = {
        function() mq_utils.MoveToSpawnName('gorilla') end,
        function() HandleBarrel(0) end,
        function() HandleBarrel(1) end,
        function() HandleBarrel(2) end,
        function()
            mq_utils.MoveToAndSay('gorilla', 'attack')
            mq_utils.KillOneMob('gorilla')
            mq_utils.KillAllOnXtarget()

            end,
        function()
            mq_utils.KillOneMob('gorilla')
            mq_utils.KillAllOnXtarget()
        end,
    }
    return DoSteps(task, steps)
end

local function Mission_OasisOfFire(task)
    local wake_mobs_step = function(objective, mob_type)
        if (mq.TLO.Me.XTarget() > 0) then
            mq.cmdf('/target id %d', mq.TLO.Me.XTarget(1).ID())
            mq_utils.KillAllOnXtarget()
            return
        end

        ::walk_it_again::
        local targets = {}
        local mob_count = mq.TLO.SpawnCount(mob_type..' npc')()
        logger.info('Attempting to wake \ag%s \aw mobs. Count(\ag%d\aw)', mob_type, mob_count)
        for i=1,mob_count do
            local mob = mq.TLO.NearestSpawn(i, mob_type..' npc')
            table.insert(targets, mob)
        end

        for _, mob in pairs(targets) do
            logger.debug('Moving to mob \ag%s\ao (\ag%s\ao)', mob.Name(), mob.ID())
            mq_utils.MoveToId(mob.ID(), 1)

            mq.delay(3000, function() return mq.TLO.Me.XTarget() > 0 end)
            if (mq.TLO.Me.XTarget() > 0) then
                logger.info('Mob(s) activated. Engaging.')
                mq_utils.KillAllOnXtarget()
                logger.debug('All agro cleared. Ending step.')
                return
            end
        end

        if (mq_utils.ObjectiveComplete(objective) == true) then return end

        logger.info('Objective not complete.  Starting over')
        goto walk_it_again
    end

    local steps = {
        function(o)
            wake_mobs_step(o, 'whirling')
        end,
        function(o)
            mq_utils.KillAllOnXtarget()
            wake_mobs_step(o, 'whirling')
        end,
        function(o)
            mq_utils.KillAllOnXtarget()
            wake_mobs_step(o, 'whirling')
        end,
        function(o)
            mq_utils.KillAllOnXtarget()
            wake_mobs_step(o, 'whirling')
        end,
        function(o)
            mq_utils.KillAllOnXtarget()
            wake_mobs_step(o, 'whirling')
        end,
        function(o)
            mq_utils.KillAllOnXtarget()
            wake_mobs_step(o, 'whirling')
        end,
        function(o)
            mq_utils.KillAllOnXtarget()
            wake_mobs_step(o, 'whirling')
        end,
        function(o)
            mq_utils.KillAllOnXtarget()
            wake_mobs_step(o, 'whirling')
        end,
        function()
            mq_utils.MoveToSpawnNameAndAttack('slumbering wyvern')
            mq_utils.MoveToSpawnNameAndAttack('guardian')
        end,
        function() mq_utils.KillAllOnXtarget() end,
    }
    return DoSteps(task, steps)
end

local function Mission_OasisOfSwamps(task)
    local steps = {
        function() mq_utils.MoveToSpawnName('Amzy the Ravenous') end,
        function() mq_utils.KillAllOnXtarget() end,
        function() mq_utils.MoveToSpawnName('Amzy the Ravenous') end,
        function() mq_utils.KillAllOnXtarget() end,
        function() mq_utils.MoveToSpawnName('Amzy the Ravenous') end,
        function() mq_utils.KillAllOnXtarget() end,
        function() mq_utils.MoveToSpawnName('Amzy the Ravenous') end,
        function() mq_utils.KillAllOnXtarget() end,
        function() mq_utils.MoveToSpawnName('Amzy the Ravenous') end,
        function() mq_utils.KillOneMob('Amzy the Ravenous') end,
    }
    return DoSteps(task, steps)
end

local function Mission_OasisOfFear(task)
    local test_kill_mob = function(spawn_id)
        mq_utils.MoveToAndTargetId(spawn_id)
        mq.delay(1000, function() return mq.TLO.Target.ID() == spawn_id end)
        if (mq.TLO.Target.ID() ~= spawn_id) then return false end

        -- There's a delay in seeing the mobs HP.
        if ( mq.TLO.Target.PctHPs() == 1) then
            mq.delay(1000, function() return mq.TLO.Target.PctHPs() ~= 1 end)
        end

        if (mq.TLO.Me.Combat() == false) then
            mq.cmd('/attack on')
        end

        logger.debug('\ay Testing mob by poking it with sticks.  Current HP: %s', mq.TLO.Target.PctHPs())
        mq.delay(3000, function() return mq.TLO.Target.PctHPs() < 100 end)
        if (mq.TLO.Target.PctHPs() == 100) then return false end

        logger.debug("\ag Target's HP < 100 (%s).  Killing it.", mq.TLO.Target.PctHPs())
        mq_utils.KillOneMob(mq.TLO.Target.Name(), nil, true)
        logger.debug('\ag Mob deaded')
        return true
    end

    local kill_next_egg = function()
        if (mq.TLO.Target.CleanName() == 'a spinechiller egg sac') then
            logger.debug('\at ... finishing current target')
            if (test_kill_mob(mq.TLO.Target.ID()) == true) then
                return true
            end
        end

        logger.debug('\at Walking them all...')

        local targets = {}
        local mob_count = mq.TLO.SpawnCount('npc a spinechiller egg sac')()
        for i=1,mob_count do
            local mob = mq.TLO.NearestSpawn(i, 'npc a spinechiller egg sac')
            table.insert(targets, mob)
        end

        for _, mob in pairs(targets) do
            logger.info('Moving to sac %s (%s)', mob.Name(), mob.ID())
            if (test_kill_mob(mob.ID()) == true) then
                logger.debug('\ag KILLING all on xtarget')
                mq_utils.KillAllOnXtarget()
                logger.debug('\ag ...done KILLING all on xtarget')
                return true
            end
        end

        return false
    end
    
    local function process_random_step(o)
        if (o.Instruction() == "Investigate the spider's nest") then
            logger.debug('\ay Moving to center location')
            mq_utils.KillAllOnXtarget()
            mq_utils.MoveToLoc('129.01 0.30 467.91')
            mq_utils.MoveToLoc('94.25 68.32 465.76')
        elseif (o.Instruction() == 'Kill the attacking desiccated corpses') then
            logger.debug('\ay Killing spawned corpses')
            mq_utils.KillAllOnXtarget()
        elseif (o.Instruction() == 'Destroy the hatching spinechiller egg sacs') then
            logger.debug('\ay Finding and destroying activated egg sacs')
            mq_utils.KillAllOnXtarget()
            kill_next_egg()
        elseif (o.Instruction() == 'Defeat the spinechiller matriarch') then
            logger.debug('\ay Killing boss mama')
            mq_utils.KillAllOnXtarget()
            mq_utils.MoveToAndSay('a spinechiller matriarch', 'attack')
            mq_utils.KillOneMob('a spinechiller matriarch')
        else
            mq_utils.KillAllOnXtarget()

            mq.cmd('/beep')
            logger.warning('\ay Unknown instruction: %s', o.Instruction())
            mq_utils.PauseUntilObjectiveComplete(o)
        end
    end

    local steps = {
        function(o) process_random_step(o) end,
        function(o) process_random_step(o) end,
        function(o) process_random_step(o) end,
        function(o) process_random_step(o) end,
        function(o) process_random_step(o) end,
        function(o) process_random_step(o) end,
        function(o) process_random_step(o) end,
        function(o) process_random_step(o) end,
    }
    return DoSteps(task, steps)
end

local function Mission_OasisOfVoid(task)
    local function process_random_step(objective)
        if (objective.Instruction() == 'Defeat the attacking golems') then
            mq_utils.KillAllOnXtarget()
        elseif (objective.Instruction() == 'Defeat the Mata Muram Effigy') then
            mq_utils.KillOneMob('Mata Muram Effigy')
        end
    end

    local steps = {
        function(o) 
            if (o.Instruction() == 'Approach the Mata Muram Effigy') then
                mq_utils.MoveToSpawnName('Mata Muram Effigy')
                mq_utils.KillAllOnXtarget()
            else
                mq_utils.MoveToSpawnName('rift')
                mq_utils.KillAllOnXtarget()
            end
        end,
        function(o) process_random_step(o) end,
        function(o) process_random_step(o) end,
        function(o) process_random_step(o) end,
        function(o) process_random_step(o) end,
        function(o) process_random_step(o) end,
        function(o) process_random_step(o) end,
        function(o) process_random_step(o) end,
        function(o) process_random_step(o) end,
        function(o) process_random_step(o) end,
    }
    return DoSteps(task, steps)
end

local function Mission_OasisOfDragons(task)
    local move_to_level = function(level, move_into_room)
        local level_details = tower.GetLevelDetails(level)

        ::restart_running::
        logger.debug('\ag Running to door %s', level)
        mq.cmdf("/nav door id %s", level_details.switch_id)
        while(mq.TLO.Navigation.Active()) do
            if (mq.TLO.Me.XTarget(1).ID() > 0) then
                logger.debug('\ay XTarget seen - going to kill')
                mq_utils.KillAllOnXtarget()
                logger.debug('\ag Targets cleared')
                goto restart_running
            end

            mq.delay(50)
        end

        logger.debug('At door, waiting for group to catch up.')
        --mq_utils.WaitForGroupToCatchUp()
        mq_utils.KillAllOnXtarget()
        if (move_into_room) then
            logger.debug('Running into the room')
            mq_utils.MoveToLoc('-110 67 '..mq.TLO.Me.Z())
        end

        logger.info('Moved to level: %s', level)
    end

    local kill = function(level, spawn_name)
        local my_level = tower.GetMyCurrentLevel()
        if (my_level ~= level) then
            tower.MoveToLevel(level)
        end

        mq.cmd('/squelch /target clear')
        --mq_utils.KillAllBaddiesIfUp(spawn_name, nil, nil, nil, nil, 10)
        mq_utils.KillAllBaddiesIfUp(spawn_name, nil, nil, nil, 10)
        mq_utils.KillAllOnXtarget()
        mq.cmd('/say attack')

    end

    local steps = {
        function() move_to_level(4, true) end,
        function() kill(4, 'an orc thaumaturgist') end,
        function() move_to_level(7, true) end,
        function() kill(7, 'an obsolete behemoth') end,
        function() move_to_level(10, true) end,
        function() kill(10, 'Amzy the Ravenous') end,
        function()
            move_to_level(13, false)
            mq_utils.MoveToSpawnName('Echo of Lord Nagafen')
        end,
        function() mq.cmd('/squelch /target clear') mq_utils.KillAllOnXtarget() end,
        function() mq.cmd('/squelch /target clear') mq_utils.KillAllOnXtarget() end,
        function() mq.cmd('/squelch /target clear') mq_utils.KillAllOnXtarget() end,
        function(o) mq_utils.PauseUntilObjectiveComplete(o) end,
    }

    return DoSteps(task, steps)
end


local function GetLevelForDoor(door_id)
    if (door_id <= 2) then
        return door_id
    end

    return door_id - 1
end

local function AcquireTask(level)
    local mission = level.mission
    local key = level.key

    local current_task = mq.TLO.Task(mission.name)
    if (current_task ~= nil and current_task() ~= nil) then
        return current_task
    end

    logger.info('Requesting task: %s', mission.name)

    key_not_ready = false
    local key_item = mq.TLO.FindItem(key.id)
    if (key_item() ~= nil) then
        mq.cmdf('/shift /itemnotify "%s" rightmouseup', key.name)
        mq.delay(key_item.CastTime() + 1000)
        mq.doevents()
        current_task = mq.TLO.Task(mission.name)

        if (key_not_ready == true) then
            if (current_task == nil or current_task() == nil) then
                SetStatusMessage('Key Not Ready')
            end
            key_not_ready = false
        end
    else
        logger.info('No key in inventory. Attempting to request from artificer.')

        SetGroupChaseMode(false)
        mq.delay(100)

        logger.info('Rest of group traveling to \at%s', mission.mission_zone)

        if (Settings.general.UseOptimizedNavigation) then
            mq_utils.send_others_message('/lua run missions_anniversarytower/other_actions runto '..mission.level)
            mq_utils.send_others_message('/tower_o runto '..mission.level)
            tower.MoveToLevel(1)
        else
            mq_utils.send_others_message('/nav door id %s', mission.switch_id)

            -- If we are more than half-way up the tower, go up to the teleporter down
            if (mq.TLO.Me.Z() > 320) then 
                mq_utils.TravelViaTeleporter(19, false)
                mq.delay(200)
            end
        end

        if (actions.TestMode_NotRequestingMissions == true) then
            logger.warning('----- TEST MODE: Not Actually Requesting Mission.')
            mq_utils.MoveToSpawnName('artificer', 10)
        else
            mq_utils.MoveToAndSay('artificer', mission.name)
        end

        current_task = mq_utils.DelayUntilQuestAssigned(5000, mission.name)
    end

    return current_task
end

local task_timers = {}
local function SetMissionStatus(type,mission_name, status)
    if (task_timers[mission_name] == nil) then
        task_timers[mission_name] = {}
    end
    task_timers[mission_name][type] = status

    -- Now report "replay" if exists, else "request"
    if (type == "request") then
        if (task_timers[mission_name].replay ~= nil) then return end
    end

    for _, level in pairs(tower.Levels) do
        if (level.mission ~= nil) then
            if (level.mission.name == mission_name) then
                level.mission.status = status
                if (level.mission.mission_task == nil or level.mission.mission_task() == nil) then
                    level.mission.is_ready = false
                end

                return
            end
        end
    end
end

local function UpdateTaskTimers()
    task_timers = {}
    mq.cmd('/tasktimer')
    mq.doevents()
end

local function RefreshAll(_)
    -- Level 1-6 unlock "Year of Darkpaw Pocket Full of Keys Part I"
    if (lower_level_group_complete ~= true) then
        lower_level_group_complete = mq.TLO.Achievement(200168).Completed()
    end
    if (upper_level_group_complete ~= true) then
        upper_level_group_complete = mq.TLO.Achievement("Year of Darkpaw Pocket Full of Keys Part II").Completed() == true
    end

    for _, level in pairs(tower.Levels) do
        if (level.mission ~= nil) then
            level.mission.is_ready = true

            level.mission.status = '-'
            level.mission.mission_task = mq.TLO.Task(level.mission.name)
            if (level.mission.mission_task ~= nil and level.mission.mission_task() ~= nil) then
                level.mission.status = 'active'
                level.mission.is_ready = true
            end

            level.key.achievement_completed = mq.TLO.Achievement(level.key.achievement).Completed() == true

            level.key.key_item = mq.TLO.FindItem(level.key.id)
            if (level.key.key_item() == nil) then
                level.key.key_item = mq.TLO.FindItemBank(level.key.id)
                if (level.key.key_item() ~= nil) then
                    level.mission.key_status = 'banked'
                else
                    level.mission.key_status = 'missing'
                end

                if ((level.level < 8 and lower_level_group_complete) or (level.level >= 8 and upper_level_group_complete)) then
                    level.mission.access_type = 'Artificer'
                else
                    level.mission.access_type = nil
                end
            else
                level.mission.key_status = 'inventory'

                level.mission.access_type = 'Key'
            end
        end
    end

    UpdateTaskTimers()
end

-- This isn't entirely accurate.  The nil status COULD be question-marks on a not-yet-started task, etc... but it's all we got for now.
local function is_task_complete(task)
    for index = 1,100 do
        local objective = task.Objective(index)
        if (objective.Status() == nil) then return true end
        if (mq_utils.ObjectiveComplete(objective) == false) then return false end
    end
    return true
end

local function RunMission(level)
    local mission = level.mission
    key_not_ready = false
    ClearStatusMessage()

    SetCurrentProcess('Running Mission: ' .. mission.name)
    local current_task = AcquireTask(level)
    local time_since_request = 0
    if (actions.TestMode_NotRequestingMissions == false) then
        if (current_task == nil or current_task() == nil) then
            logger.error('Unable to acquire task. Stopping run.')
            return false
        end

        time_since_request = 21600000 - current_task.Timer()
    end

    --mq.cmd('/dgga /boxr pause')

    mq_utils.SelectTask(current_task)
    local time_to_wait = delay_before_zoning - time_since_request
    logger.debug('TimeSinceReq: \ag%d\ao  TimeToWait: \ag%d\ao', time_since_request, time_to_wait)
    if (time_to_wait > 0) then
        logger.info('\at Waiting for instance generation \aw(\ay%.f second(s)\aw)', time_to_wait / 1000)
        SetStatusMessage(string.format('Waiting for instance generation. (%.f) second(s)', time_to_wait / 1000))

        if (Settings.general.UseOptimizedNavigation == true) then
            mq_utils.send_others_message('/lua run missions_anniversarytower/other_actions zoneto '..mission.level)
            mq_utils.send_others_message('/tower_o zoneto '..mission.level)
            tower.MoveToLevel(mission.level)
        else
            mq_utils.send_group_message('/nav door id %s', mission.switch_id)
            if (Settings.general.UseMageCoth) then
                local mage = mq_utils.GetGroupMemberByClass('MAG')
                if (mage ~= nil) then
                    logger.info('Asking Mage to COTH me.')
                    mq_utils.send_individual_message(mage.Name(), '/lua run missions_anniversarytower/coth '..mq.TLO.Me.ID())
                end
            end
        end

        mq.delay(time_to_wait)
        ClearStatusMessage()
    end

    if (mq.TLO.Zone.ShortName() == mission.mission_zone and mq.TLO.Group.AnyoneMissing() == false) then
    else
        mq_utils.send_others_message('/lua run missions_anniversarytower/other_actions zoneto '..mission.level)
        mq_utils.send_others_message('/tower_o zoneto '..mission.level)
        if (mq.TLO.Zone.ShortName() ~= mission.mission_zone) then
            tower.MoveToLevel(mission.level)
            mq_utils.TravelViaDoor(mission.switch_id, mission.mission_zone, false)
        end
        mq_utils.WaitForGroupToZone()
    end

    SetGroupChaseMode(true)

    mq_utils.SelectTask(current_task)

    --mq.cmd('/dgga /boxr unpause')

    ::recheck_mission::
    if (mission.mission_delegate(current_task) == false) then
        logger.warning('Mission Run Did Not Complete Successfully.  Stopping in Zone for you to sort it out.')
        return false
    end

    -- Check if anyone be deaded
    if (mq_utils.AreGroupCorpsesInZone()) then
        logger.warning('PAUSING: One or more group members dead')
        SetStatusMessage("Group has corpses in zone.  Stalling until they are cleaned up.")
        while (mq_utils.AreGroupCorpsesInZone()) do
            mq.delay(1000)
            mq.doevents()
        end

        logger.info('Dead have been cleared out.')
        ClearStatusMessage()
    end

    -- Double-check that task is fully completed
    if (is_task_complete(current_task) == false) then
        logger.warning('Script appears to have prematurely considered task completed.  Checking again.  If this continues.  Manually complete and re-run script.')
        mq.delay(1000)
        goto recheck_mission
    end

    logger.info('Leaving zone')
    mq_utils.TravelViaDoor(mission.switch_id, 'anniversarytower', true)

    -- If we don't have the achievement, wait up to X seconds for it to actually register
    local achievement = mq.TLO.Achievement(mission.achievement_id)
    if (achievement ~= nil and achievement.Completed() == false) then
        logger.warning('Waiting for achievement to register. Up to 20 seconds.')
        local count_down = 20
        while (count_down > 0 and achievement ~= nil and achievement.Completed() == false) do
            mq.delay(1000)
            count_down = count_down - 1
        end

        achievement = mq.TLO.Achievement(mission.achievement_id)
        if (achievement ~= nil and achievement.Completed() == false) then
            logger.warning("FAILED to acquire achievment. Abandoning script.")
            os.exit()
        end

        logger.info("Achievement detected. Continuing.")
    else
        mq.delay(15000)
    end

    logger.info('Dropping quest')
    mq.cmd('/kickp t')
    mq_utils.click_confirmation_yes()

    mission.selected = false

    RefreshAll()

    return true
end

local function RunToLevel(level)
    tower.MoveToLevel(level)
end

local function RunToLevelGroup(level)
    mq_utils.send_group_message('/lua run missions_anniversarytower/tower_travel '..level)
end

local function RequestMission(level)
    AcquireTask(level)
end

function actions.RunSelectedMissions() actions.SetAction('run_selected') end

local function event_tasktimers_request(_, task_name, time_remaining)
    SetMissionStatus('request', task_name, time_remaining)
end

local function event_tasktimers_replay(_, task_name, time_remaining)
    SetMissionStatus('replay', task_name, time_remaining)
end

local function RunSpecificMission(actionParameter)
    -- TODO: Integrate all checks if this mission is in a state to run
    RunMission(actionParameter)
end

local function RunSelectedMissions(_)
    logger.warning('RunSelectedMissions')

    for _, level in lua_utils.spairs(tower.Levels) do
        if (level.mission ~= nil and level.mission.is_ready == true and level.mission.selected == true) then
            -- TODO: After this, restart spairs and walk list from 1+ again.
            RunMission(level)
        end
    end
end

local function SelectAllMissions(_)
    for _, level in pairs(tower.Levels) do
        if (level.mission ~= nil) then
            level.mission.selected = (level.key.achievement_completed == true and level.is_available == true)
        end
    end
end

local function DeselectAllMissions(_)
    for _, level in pairs(tower.Levels) do
        if (level.mission ~= nil) then
            if (level.mission.selected == true)
            then
                level.mission.selected = false
            end
        end
    end
end

local function SelectAllKeyTasks(_)
    for _, level in pairs(tower.Levels) do
        if (level.key ~= nil) then
            level.key.task.selected = (level.is_available == true and level.key.task.task_delegate ~= nil)
        end
    end
end

local function DeselectAllKeyTasks(_)
    for _, level in pairs(tower.Levels) do
        if (level.mission ~= nil) then
            if (level.key.task.selected == true)
            then
                level.key.task.selected = false
            end
        end
    end
end

local function RunKeyTask(level)
    key_tasks.RunKeyTask(level, RefreshAll)
end

local function RequestKeyTask(level)
    key_tasks.AcquireTask(level)
end

local function RunSelectedKeyTasks()
    key_tasks.RunSelectedKeyTasks(RefreshAll)
end

local function RunTestRoutines()
    mq_utils.MoveItemToTopLevelSlotById(161907)
end

local function event_key_not_ready()
    logger.info('Key Not Ready event detected')
    key_not_ready = true
end

local function output_help()
    logger.info('/tower [command] [floor]')
    logger.info('   Commands: "mission" or "key"')
    logger.info('   floor: either name or numeric floor level')
    logger.info('        : 2-13 or sand, lava, forest, frost, sky, steam, jungle, fire, swamps, fear, void, dragons')
end

local function get_level_data(floor)
    local floor_number = tonumber(floor)
    if (floor_number == true) then
        for _,level in pairs(tower.Levels) do
            if (level.level == floor_number) then
                return level
            end
        end
    else
        for _,level in pairs(tower.Levels) do
            if (level.short_name == floor) then
                return level
            end
        end
    end

    return nil
end

local function bind_command(command, floor)
    local level_data  = get_level_data(floor)

    if (command == 'mission' and level_data ~= nil) then
        actions.SetAction('run_specific_mission', level_data)
    elseif (command == 'key' and level_data ~= nil) then
        actions.SetAction('run_specific_key_task', level_data)
    elseif (command == 'help') then
        output_help()
    else
        logger.warning('Unknown Command: (\at%s\aw), %s', command, floor)
        output_help()
    end
end

local function Initialize()
    load_settings()

    mq.bind('/tower', bind_command)

    if (mq.TLO.Plugin('CWTN') == 'Active') then
        mq.cmdf('/%s mode 7', mq.TLO.Me.Class.ShortName())
    end

    -- Unfortunate hack unless we move all mission methods there as well.  "It's fine"
    tower.Levels["02"].mission.mission_delegate = Mission_OasisOfSand
    tower.Levels["03"].mission.mission_delegate = Mission_OasisOfLava
    tower.Levels["04"].mission.mission_delegate = Mission_OasisOfForests
    tower.Levels["05"].mission.mission_delegate = Mission_OasisOfFrost
    tower.Levels["06"].mission.mission_delegate = Mission_OasisOfSky
    tower.Levels["07"].mission.mission_delegate = Mission_OasisOfSteam
    tower.Levels["08"].mission.mission_delegate = Mission_OasisOfTheJungle
    tower.Levels["09"].mission.mission_delegate = Mission_OasisOfFire
    tower.Levels["10"].mission.mission_delegate = Mission_OasisOfSwamps
    tower.Levels["11"].mission.mission_delegate = Mission_OasisOfFear
    tower.Levels["12"].mission.mission_delegate = Mission_OasisOfVoid
    tower.Levels["13"].mission.mission_delegate = Mission_OasisOfDragons

    tower.Initialize()
    for _, level in pairs(tower.Levels) do
        if (level.mission ~= nil) then
            -- Duplicate the switch and level into the mission to simplify passing that object around
            -- level.mission.switch_id = level.switch_id
            -- level.mission.level = level.level
            level.is_available = level.mission.mission_delegate ~= nil and mq.TLO.Achievement(level.key.achievement).ID() ~= nil
            level.mission.selected = level.is_available
            level.key.achievement_completed = mq.TLO.Achievement(level.key.achievement).Completed() == true
        end
    end

    logger.info('\ao Setting up events')
    mq.event('key_not_ready', "#*#The magic of this key needs more time before the key can perform#*#", event_key_not_ready)
    mq.event('task_timers_request', "#*#'#1#' request timer: #2# remaining.#*#", event_tasktimers_request)
    mq.event('task_timers_replay', "#*#'#1#' replay timer: #2# remaining.#*#", event_tasktimers_replay)
    mq.event('task_timers_received', "#*#You have received a replay timer for '#1#': #2# remaining.#*#", event_tasktimers_request)
end

local next_action = nil
local next_action_parameter = nil

function actions.SetAction(actionName, actionParameter)
    next_action = actionName
    next_action_parameter = actionParameter
end

local last_travelto_zone_name = nil
function actions.GetLastTravelToZoneName()
    return last_travelto_zone_name
end

local function OnTravelToEvent(zoneName)
    last_travelto_zone_name = zoneName
end

local processes = {
    refresh = {
        process_name = 'Refreshing',
        delegate = RefreshAll
    },
    goto_level = {
        process_name = 'Run To Level',
        delegate = RunToLevel
    },
    goto_level_group = {
        process_name = 'Group Run To Level',
        delegate = RunToLevelGroup
    },
    request_mission = {
        process_name = 'Request Mission',
        delegate = RequestMission,
    },
    run_selected = {
        process_name = 'Run Selected Missions',
        delegate = RunSelectedMissions
    },
    run_specific_mission = {
        process_name = 'Run Specific Mission',
        delegate = RunSpecificMission
    },
    select_all = {
        process_name = 'Select All Missions',
        delegate = SelectAllMissions
    },
    deselect_all = {
        process_name = 'Deselect All Missions',
        delegate = DeselectAllMissions
    },
    run_specific_key_task = {
        process_name = 'Run Key Task',
        delegate = RunKeyTask
    },
    request_key_task = {
        process_name = 'Request Key Task',
        delegate = RequestKeyTask
    },
    run_selected_key_tasks = {
        process_name = 'Run Selected Key Tasks',
        delegate = RunSelectedKeyTasks,
    },
    select_all_key_tasks = {
        process_name = 'Select All Key Tasks',
        delegate = SelectAllKeyTasks
    },
    deselect_all_key_tasks = {
        process_name = 'Deselect All Key Tasks',
        delegate = DeselectAllKeyTasks
    },
    run_test_routines = {
        process_name = 'Initiate Test Routines',
        delegate = RunTestRoutines,
    }
}

function actions.Main()
    Initialize()
    RefreshAll()
    key_tasks.Initialize(SetStatusMessage)
    mq_utils.SetTraveltoEvent(OnTravelToEvent)

    next_action = nil
    local action = nil

    while (true) do
        if (next_action == nil) then goto done_with_cycle end

        action = processes[next_action]
        if (action == nil) then
            logger.error('Unknown Action Initiated: %s.  Ignoring', next_action)
            goto done_with_cycle
        end

        SetCurrentProcess(action.process_name)
        action.delegate(next_action_parameter)


        EndCurrentProcess()
        ::done_with_cycle::
        next_action = nil

        mq.delay(1000)
        mq.doevents()
    end
end

return actions
