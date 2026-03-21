--- @type Mq
local mq = require('mq')
local ImGui = require('ImGui')

-- local settings = require('settings')
local uiutils = require('utils.ui_utils')
local icons = require('mq.Icons')
local logger = require('utils.logger')
local engine = require('engine')
local lua_utils = require('utils.lua_utils')
local tower = require('tower_travel')

--- @type boolean
Open, ShowUI = true, true
--- @type boolean
MyShowUi = true

local TEXT_BASE_HEIGHT = ImGui.GetTextLineHeightWithSpacing()
local in_tower_zone = false

local actions = {}

local PART1_SCRIPT = 'anniversarytower/PocketFullOfKeys1'
local PART2_SCRIPT = 'anniversarytower/PocketFullOfKeys2'

local PART1_ACHIEVEMENT_ID = 200168
local PART2_ACHIEVEMENT_ID = 200169

local PART1_KEYS = {
    'Repaired Key of Sand',
    'Repaired Key of Lava',
    'Repaired Key of Forests',
    'Repaired Key of Frost',
    'Repaired Key of Sky',
    'Repaired Key of Steam',
}

local PART2_KEYS = {
    'Repaired Key of the Jungle',
    'Repaired Key of Fire',
    'Repaired Key of Swamps',
    'Repaired Key of Fear',
    'Repaired Key of the Void',
    'Repaired Key of Dragons',
}

local function getShortScriptName(scriptName)
    return scriptName:match("([^/]+)$") or scriptName
end

local function getPocketKeyCount(itemName)
    local count = mq.TLO.FindItemCount('=' .. itemName)()
    if count == nil then
        return 0
    end
    return count
end

local function getPocketKeyStatus(keyList)
    local result = {
        total = #keyList,
        have = 0,
        missing = 0,
        items = {},
    }

    for _, itemName in ipairs(keyList) do
        local count = getPocketKeyCount(itemName)
        local present = count > 0

        if present then
            result.have = result.have + 1
        else
            result.missing = result.missing + 1
        end

        table.insert(result.items, {
            name = itemName,
            count = count,
            present = present,
        })
    end

    return result
end

local function allPocketKeysPresent(keyList)
    for _, itemName in ipairs(keyList) do
        if getPocketKeyCount(itemName) <= 0 then
            return false
        end
    end
    return true
end

local function anyPocketKeysPresent(keyList)
    for _, itemName in ipairs(keyList) do
        if getPocketKeyCount(itemName) > 0 then
            return true
        end
    end
    return false
end

local function pocketAchievementsReady()
    local achievementTLO = mq.TLO.Achievement
    return achievementTLO ~= nil and achievementTLO.Ready() == true
end

local function isPocketAchievementComplete(achievementID)
    if not pocketAchievementsReady() then
        return false
    end

    local achievement = mq.TLO.Achievement(achievementID)
    if achievement == nil then
        return false
    end

    local id = achievement.ID()
    if id == nil or id == 0 then
        return false
    end

    return achievement.Completed() == true
end

local function getPocketPartState(keyList, achievementID)
    local status = getPocketKeyStatus(keyList)
    local ready = allPocketKeysPresent(keyList)
    local hasAny = anyPocketKeysPresent(keyList)
    local completed = isPocketAchievementComplete(achievementID)

    return {
        status = status,
        ready = ready,
        hasAny = hasAny,
        completed = completed,
        canHandIn = hasAny and not completed,
    }
end

local function isPocketScriptRunning(scriptName)
    local script = mq.TLO.Lua.Script(scriptName)
    if script() ~= nil and script.Status() == 'RUNNING' then
        return true
    end

    local shortName = getShortScriptName(scriptName)
    script = mq.TLO.Lua.Script(shortName)
    return script() ~= nil and script.Status() == 'RUNNING'
end

local function runPocketScript(scriptName)
    if not scriptName or scriptName == '' then
        logger.warning('Pocket Full of Keys script name is empty.')
        return
    end

    mq.cmd('/lua run ' .. scriptName)
end

local function stopPocketScript(scriptName)
    if not scriptName or scriptName == '' then
        logger.warning('Pocket Full of Keys script name is empty.')
        return
    end

    mq.cmdf('/lua stop %s', scriptName)
end

function actions.InitializeUi(showUi)
    mq.imgui.init('AnniversaryTowerMissions', DrawMainWindow)
    MyShowUi = showUi
end

local anniversaryZoneIds = {
    [869] = true, -- anniversarytower
}

function DrawMainWindow()
    if MyShowUi == false then os.exit() return end

    MyShowUi, ShowUI = ImGui.Begin('Anniversary Tower', Open)

    if ShowUI then
        in_tower_zone = anniversaryZoneIds[mq.TLO.Zone.ID()] == true
        ImGui.Text('State: ')
        ImGui.SameLine()
        if (in_tower_zone == false) then
            uiutils.text_colored(TextStyle.Error, "Not in tower")
        elseif (engine.CurrentProcessName == "Idle") then
            uiutils.text_colored(TextStyle.ItemValue, "Idle")
        elseif (engine.Aborting) then
            uiutils.text_colored(TextStyle.ItemValue, "Canceling")
        else
            uiutils.text_colored(TextStyle.ProcessName, engine.CurrentProcessName)
        end

        if (engine.StatusMessage ~= '') then
            ImGui.Text('Status: ')
            ImGui.SameLine()
            uiutils.text_colored(TextStyle.Error, engine.StatusMessage)
        end

        RenderTabBar()
    end

    ImGui.End()
end

local log_levels = { "Off", "Error", "Warning", "Normal", "Debug", "Trace" }

function RenderSettingsTab()
    local changed

    if ImGui.BeginTabItem('Settings') then
        Settings.general.UseOptimizedNavigation, changed = uiutils.add_setting_checkbox(
            "Use Optimized Navigation",
            Settings.general.UseOptimizedNavigation,
            'When enabled, will use teleporters to dramatically speed up tower travel.'
        )
        if (changed) then engine.SaveSettings() end

        Settings.general.UseMageCoth, changed = uiutils.add_setting_checkbox(
            "Use Mage COTH",
            Settings.general.UseMageCoth,
            'NOTE: Only valid if UseOptimizedNavigation above is false.\r\nIf Magician in group, will attempt to use COTH to bring task requestor up to mission door.'
        )
        if (changed) then engine.SaveSettings() end

        ImGui.Separator()
        uiutils.text_colored(TextStyle.SubSectionTitle, "Zone Travel")
        ImGui.Separator()

        Settings.general.UseNroPortClicky, changed = uiutils.add_setting_checkbox(
            "Use North Ro Port Clicky When Useful",
            Settings.general.UseNroPortClicky,
            'When traveling to tower (not from North/South Ro), will use Northern Desert Outlook Device or Zueria Slide if available'
        )
        if (changed) then engine.SaveSettings() end

        Settings.general.UseGateSpell, changed = uiutils.add_setting_checkbox(
            "Use Gate Spell/AA For First Key Quest",
            Settings.general.UseGateSpell,
            'When running to a key quest, will first gate to potentially dramatically reduce travel times.'
        )
        if (changed) then engine.SaveSettings() end

        Settings.general.UsePoKPortClicky, changed = uiutils.add_setting_checkbox(
            "Use PoK or GH Port Clicky/AA Where Useful",
            Settings.general.UsePoKPortClicky,
            'When travling away from tower (not to North/South Ro) will try to use a PoK clicky if available.'
        )
        if (changed) then engine.SaveSettings() end

        ImGui.Separator()
        uiutils.text_colored(TextStyle.SubSectionTitle, "Quest Running")
        ImGui.Separator()

        ImGui.PushItemWidth(200)
        local name, changedName = ImGui.InputText("Quest Requestor", Settings.general.QuestRequestor, ImGuiInputTextFlags.EnterReturnsTrue)
        ImGui.PopItemWidth()
        if (changedName) then
            Settings.general.QuestRequestor = name
            engine.SaveSettings()
        end

        ImGui.Separator()
        uiutils.text_colored(TextStyle.SubSectionTitle, "Automation Methods")
        ImGui.Separator()

        ImGui.PushStyleColor(ImGuiCol.Text, 1.0, 0.6, 0.6, 1)
        Settings.automation.boxr, changed = uiutils.add_setting_checkbox("Boxr", Settings.automation.boxr, 'Issues Boxr commands to other group members when necessary.')
        ImGui.PopStyleColor(1)
        if (changed) then engine.SaveSettings() end

        Settings.automation.cwtn, changed = uiutils.add_setting_checkbox("CWTN", Settings.automation.cwtn, 'Issues CWTN commands to other group members when necessary.')
        if (changed) then engine.SaveSettings() end

        Settings.automation.kissassist, changed = uiutils.add_setting_checkbox("KissAssist", Settings.automation.kissassist, 'Issues KissAssist commands to other group members when necessary.')
        if (changed) then engine.SaveSettings() end

        Settings.automation.rgmercs, changed = uiutils.add_setting_checkbox("RG Mercs", Settings.automation.rgmercs, 'Issues RGMerc commands to other group members when necessary.')
        if (changed) then engine.SaveSettings() end

        ImGui.Separator()
        uiutils.text_colored(TextStyle.SubSectionTitle, "Logging")
        ImGui.Separator()

        ImGui.PushItemWidth(200)
        local logLevel, changedLog = ImGui.Combo("Log Level", Settings.general.LogLevel, log_levels, #log_levels)
        ImGui.PopItemWidth()
        ImGui.SameLine()
        ImGui.Text("'%s'", log_levels[Settings.general.LogLevel])
        if (changedLog) then engine.set_log_level(logLevel) end

        ImGui.Separator()
        uiutils.text_colored(TextStyle.SubSectionTitle, "Test Settings")
        ImGui.Separator()

        engine.TestMode_NotRequestingMissions, changed = uiutils.add_setting_checkbox(
            "Do Not Request Mission",
            engine.TestMode_NotRequestingMissions,
            'When checked, runs all processes but not actual mission request. Helps see/troubleshoot running-around patterns.'
        )

        ImGui.Separator()
        ImGui.EndTabItem()
    end
end

function RenderMissionKeysTab()
    if not ImGui.BeginTabItem("Keys") then return end

    uiutils.add_icon_action_button(icons.MD_CACHED, 'Refresh', 'refresh', 'Refresh')
    ImGui.SameLine()
    uiutils.add_icon_action_button(icons.MD_PLAY_CIRCLE_FILLED, 'Run Selected', 'run_selected_key_tasks', 'Run Selected')
    ImGui.SameLine()
    uiutils.add_icon_action_button(icons.FA_PLUS_CIRCLE, 'Select All', 'select_all_key_tasks', 'Select All')
    ImGui.SameLine()
    uiutils.add_icon_action_button(icons.FA_MINUS_CIRCLE, 'Select None', 'deselect_all_key_tasks', 'Select None')

    if (engine.GetLastTravelToZoneName() ~= nil) then
        ImGui.SameLine()
        local display = string.format('%s %s', icons.MD_PLAY_CIRCLE_FILLED, 'TravelTo ' .. engine.GetLastTravelToZoneName())
        if ImGui.Button(display) then
            mq.cmd("/travelto " .. engine.GetLastTravelToZoneName())
        end
        uiutils.add_tooltip('Re-initiate travelto last /travelto target')
    end

    local flags = bit32.bor(ImGuiTableFlags.Resizable, ImGuiTableFlags.RowBg, ImGuiTableFlags.BordersOuter)
    if ImGui.BeginTable('##tableKeys', 6, flags, 0, TEXT_BASE_HEIGHT, 0.0) then
        ImGui.TableSetupColumn('Selected', bit32.bor(ImGuiTableColumnFlags.NoSort, ImGuiTableColumnFlags.WidthStretch), -1.0, 0)
        ImGui.TableSetupColumn('Action', bit32.bor(ImGuiTableColumnFlags.NoSort, ImGuiTableColumnFlags.WidthStretch), -1.0, 0)
        ImGui.TableSetupColumn('Ordinal', bit32.bor(ImGuiTableColumnFlags.PreferSortAscending, ImGuiTableColumnFlags.WidthStretch), -1.0, 1)
        ImGui.TableSetupColumn('Key', bit32.bor(ImGuiTableColumnFlags.NoSort, ImGuiTableColumnFlags.WidthStretch), -1.0, 1)
        ImGui.TableSetupColumn('AccessType', bit32.bor(ImGuiTableColumnFlags.NoSort, ImGuiTableColumnFlags.WidthStretch), -1.0, 1)
        ImGui.TableSetupColumn('Key', bit32.bor(ImGuiTableColumnFlags.NoSort, ImGuiTableColumnFlags.WidthStretch), -1.0, 1)

        ImGui.TableNextRow()
        ImGui.TableNextColumn()
        uiutils.text_colored(TextStyle.TableColHeader, 'Selected')
        ImGui.TableNextColumn()
        uiutils.text_colored(TextStyle.TableColHeader, 'Actions')
        ImGui.TableNextColumn()
        uiutils.text_colored(TextStyle.TableColHeader, 'Level')
        ImGui.TableNextColumn()
        uiutils.text_colored(TextStyle.TableColHeader, 'Key')
        ImGui.TableNextColumn()
        uiutils.text_colored(TextStyle.TableColHeader, 'Access Type')
        ImGui.TableNextColumn()
        uiutils.text_colored(TextStyle.TableColHeader, 'Key')

        if (tower.Levels ~= nil) then
            for index, level in lua_utils.spairs(tower.Levels) do
                if (level.key ~= nil and level.is_available ~= false) then
                    level.key.task.request_item = mq.TLO.FindItem(level.key.id)
                    level.key.task.key_task = mq.TLO.Task(level.key.task.task_name)
                    local can_run = level.key.task.task_delegate ~= nil

                    ImGui.TableNextRow()
                    ImGui.TableNextColumn()
                    if (can_run) then
                        level.key.task.selected = uiutils.add_setting_checkbox('##key_select' .. index, level.key.task.selected)
                    end

                    ImGui.TableNextColumn()
                    if (can_run) then
                        uiutils.add_action_button('Run##' .. index, 'run_specific_key_task', 'Run Task', level)
                        ImGui.SameLine()
                    else
                        ImGui.Text('           ')
                        ImGui.SameLine()
                    end

                    uiutils.add_action_button('Go##' .. index, 'goto_level_group', 'Runs group to level ' .. level.level, level.level)
                    ImGui.SameLine()
                    uiutils.add_action_button('Req.##' .. index, 'request_key_task', 'Request Task', level)

                    ImGui.TableNextColumn()
                    uiutils.text_colored(TextStyle.ItemValueDetail, index)
                    ImGui.TableNextColumn()
                    uiutils.text_colored(TextStyle.ItemValueDetail, level.key.name)
                    ImGui.TableNextColumn()
                    if (level.mission.access_type == nil) then
                        uiutils.text_colored(TextStyle.Error, 'None')
                    else
                        uiutils.text_colored(TextStyle.Green, level.mission.access_type)
                    end
                    ImGui.TableNextColumn()
                    if (level.mission.key_status == 'banked') then
                        uiutils.text_colored(TextStyle.ItemLabelHint, 'In Bank')
                    elseif (level.mission.key_status == 'missing') then
                        if (level.mission.access_type == 'Artificer') then
                            uiutils.text_colored(TextStyle.ItemLabelHint, '-')
                        else
                            uiutils.text_colored(TextStyle.Error, 'Missing')
                            if (in_tower_zone) then
                                ImGui.SameLine()
                                uiutils.add_action_button('Go To Level##Keys' .. index, 'goto_level', 'Run this character to level ' .. level.level, level.level)
                            end
                        end
                    else
                        uiutils.text_colored(TextStyle.Green, 'Inventory')
                    end
                end
            end
        end
        ImGui.EndTable()
    end

    ImGui.Separator()
    if ImGui.CollapsingHeader('Key Task Configurations') then
        local changed
        Settings.key_tasks.returnToTowerWhenDone, changed = uiutils.add_setting_checkbox(
            "Return to Tower When Done",
            Settings.key_tasks.returnToTowerWhenDone,
            'If checked, character will return to Anniversary Tower when done with all planned tasks.'
        )
        if (changed) then engine.SaveSettings() end

        Settings.key_tasks.getAllTasksUpFront, changed = uiutils.add_setting_checkbox(
            "Acquire All Task Initially",
            Settings.key_tasks.getAllTasksUpFront,
            'If checked, all tasks will be activated at the start of a run, rather than running back to tower each time.\r\n\r\nNote: Relevant only when running multiple tasks at the same time.'
        )
        if (changed) then engine.SaveSettings() end
    end

    ImGui.EndTabItem()
end

function RenderAllMissionsTab()
    if ImGui.BeginTabItem("Missions") then
        uiutils.add_icon_action_button(icons.MD_CACHED, 'Refresh', 'refresh', 'Refresh')
        if (in_tower_zone) then
            ImGui.SameLine()
            uiutils.add_icon_action_button(icons.MD_PLAY_CIRCLE_FILLED, 'Run Selected', 'run_selected', 'Run Selected')
        end
        ImGui.SameLine()
        uiutils.add_icon_action_button(icons.FA_PLUS_CIRCLE, 'Select All', 'select_all', 'Select All')
        ImGui.SameLine()
        uiutils.add_icon_action_button(icons.FA_MINUS_CIRCLE, 'Select None', 'deselect_all', 'Select None')
        if (in_tower_zone) then
            ImGui.SameLine()
            uiutils.add_icon_action_button(icons.MD_PLAY_CIRCLE_FILLED, 'Go To Level 1', 'goto_level', 'Go To Level 1', 1)
        end

        ImGui.Separator()

        local flags = bit32.bor(ImGuiTableFlags.Resizable, ImGuiTableFlags.RowBg, ImGuiTableFlags.BordersOuter)
        if ImGui.BeginTable('##tableMissions', 7, flags, 0, TEXT_BASE_HEIGHT, 0.0) then
            ImGui.TableSetupColumn('Selected', bit32.bor(ImGuiTableColumnFlags.NoSort, ImGuiTableColumnFlags.WidthStretch), -1.0, 0)
            ImGui.TableSetupColumn('Action', bit32.bor(ImGuiTableColumnFlags.NoSort, ImGuiTableColumnFlags.WidthStretch), -1.0, 0)
            ImGui.TableSetupColumn('Ordinal', bit32.bor(ImGuiTableColumnFlags.PreferSortAscending, ImGuiTableColumnFlags.WidthStretch), -1.0, 1)
            ImGui.TableSetupColumn('Mission', bit32.bor(ImGuiTableColumnFlags.NoSort, ImGuiTableColumnFlags.WidthStretch), -1.0, 1)
            ImGui.TableSetupColumn('Status', bit32.bor(ImGuiTableColumnFlags.NoSort, ImGuiTableColumnFlags.WidthStretch), -1.0, 1)
            ImGui.TableSetupColumn('AccessType', bit32.bor(ImGuiTableColumnFlags.NoSort, ImGuiTableColumnFlags.WidthStretch), -1.0, 1)
            ImGui.TableSetupColumn('Key', bit32.bor(ImGuiTableColumnFlags.NoSort, ImGuiTableColumnFlags.WidthStretch), -1.0, 1)

            ImGui.TableNextRow()
            ImGui.TableNextColumn()
            uiutils.text_colored(TextStyle.TableColHeader, 'Selected')
            ImGui.TableNextColumn()
            uiutils.text_colored(TextStyle.TableColHeader, 'Actions')
            ImGui.TableNextColumn()
            uiutils.text_colored(TextStyle.TableColHeader, 'Level')
            ImGui.TableNextColumn()
            uiutils.text_colored(TextStyle.TableColHeader, 'Mission')
            ImGui.TableNextColumn()
            uiutils.text_colored(TextStyle.TableColHeader, 'Status')
            ImGui.TableNextColumn()
            uiutils.text_colored(TextStyle.TableColHeader, 'Access Type')
            ImGui.TableNextColumn()
            uiutils.text_colored(TextStyle.TableColHeader, 'Key')

            if (tower.Levels ~= nil) then
                for index, level in lua_utils.spairs(tower.Levels) do
                    if (level.mission == nil or level.is_available == false) then goto next_mission_level end

                    level.key.key_item = mq.TLO.FindItem(level.key.id)
                    level.mission.mission_task = mq.TLO.Task(level.mission.name)
                    local can_run = level.is_available ~= false

                    ImGui.TableNextRow()
                    ImGui.TableNextColumn()
                    if (can_run) then
                        level.mission.selected = uiutils.add_setting_checkbox('##Abc' .. index, level.mission.selected, 'Tooltip')
                    end

                    ImGui.TableNextColumn()
                    if (can_run and in_tower_zone) then
                        uiutils.add_action_button('Run##' .. index, 'run_specific_mission', 'Run Mission', level)
                        ImGui.SameLine()
                        uiutils.add_action_button('Go##' .. index, 'goto_level_group', 'Runs group to level ' .. level.level, level.level)
                        ImGui.SameLine()
                        uiutils.add_action_button('Req.##' .. index, 'request_mission', 'Request Mission', level)
                    end

                    ImGui.TableNextColumn()
                    uiutils.text_colored(TextStyle.ItemValueDetail, index)
                    ImGui.TableNextColumn()
                    uiutils.text_colored(TextStyle.ItemValueDetail, level.mission.name)
                    ImGui.TableNextColumn()
                    if (level.mission.mission_task == nil or level.mission.mission_task() == nil) then
                        if (level.mission.status ~= nil and level.mission.status ~= '') then
                            uiutils.text_colored(TextStyle.Yellow, level.mission.status)
                        else
                            ImGui.Text('-')
                        end
                    else
                        uiutils.text_colored(TextStyle.Yellow, 'Active')
                    end
                    ImGui.TableNextColumn()
                    if (level.mission.access_type == nil) then
                        uiutils.text_colored(TextStyle.Error, 'None')
                    else
                        uiutils.text_colored(TextStyle.Green, level.mission.access_type)
                    end
                    ImGui.TableNextColumn()
                    if (level.mission.key_status == 'banked') then
                        uiutils.text_colored(TextStyle.ItemLabelHint, 'In Bank')
                    elseif (level.mission.key_status == 'missing') then
                        if (level.mission.access_type == 'Artificer') then
                            uiutils.text_colored(TextStyle.ItemLabelHint, '-')
                        else
                            uiutils.text_colored(TextStyle.Error, 'Missing')
                            if (in_tower_zone) then
                                ImGui.SameLine()
                                uiutils.add_action_button('Go To Level##' .. index, 'goto_level', 'Run this character to level ' .. level.level, level.level)
                            end
                        end
                    else
                        uiutils.text_colored(TextStyle.Green, 'Inventory')
                    end

                    ::next_mission_level::
                end
            end
            ImGui.EndTable()
        end

        ImGui.Separator()
        if ImGui.CollapsingHeader('Mission Configurations') then
            local changed
            ImGui.Text('Oasis of Jungle')
            ImGui.Indent(20)
            Settings.missions.jungle_KillBarrels, changed = uiutils.add_setting_checkbox(
                "Kill Barrels",
                Settings.missions.jungle_KillBarrels,
                'If checked, group attacks barrels; else sit in corner and wait for them to self-explode (3 minutes).'
            )
            if (changed) then engine.SaveSettings() end
            ImGui.Unindent(20)
        end

        ImGui.EndTabItem()
    end
end

function RenderPocketKeysTab()
    if not ImGui.BeginTabItem("Pocket Full of Keys") then return end

    local function drawPocketKeyList(keyList)
        for _, itemName in ipairs(keyList) do
            local count = getPocketKeyCount(itemName)
            if count > 0 then
                uiutils.text_colored(TextStyle.Green, string.format('%s x%d', itemName, count))
            else
                uiutils.text_colored(TextStyle.Error, itemName)
            end
        end
    end

    local function drawPocketSection(title, keyList, scriptName, achievementID)
        local part = getPocketPartState(keyList, achievementID)
        local status = part.status
        local hasAny = part.hasAny
        local completed = part.completed
        local running = isPocketScriptRunning(scriptName)
        local canHandIn = part.canHandIn

        ImGui.Separator()
        uiutils.text_colored(TextStyle.SubSectionTitle, title)
        ImGui.Separator()

        ImGui.Text(string.format('Keys found: %d / %d', status.have, status.total))
        ImGui.Text(string.format('Ready to hand in: %s', canHandIn and 'Yes' or 'No'))
        ImGui.Text(string.format('Achievement completed: %s', completed and 'Yes' or 'No'))
        ImGui.Text(string.format('Script running: %s', running and 'Yes' or 'No'))

        ImGui.Text('Status: ')
        ImGui.SameLine()
        if completed then
            uiutils.text_colored(TextStyle.Green, 'Completed')
        elseif canHandIn then
            uiutils.text_colored(TextStyle.Yellow, 'Ready')
        elseif hasAny then
            uiutils.text_colored(TextStyle.ItemValueDetail, 'Partial')
        else
            uiutils.text_colored(TextStyle.Error, 'No keys found')
        end

        if not canHandIn or running then
            ImGui.BeginDisabled()
        end
        if ImGui.Button('Run##' .. scriptName) then
            runPocketScript(scriptName)
        end
        if not canHandIn or running then
            ImGui.EndDisabled()
        end

        ImGui.SameLine()

        if ImGui.Button('Stop##' .. scriptName) then
            stopPocketScript(scriptName)
        end

        drawPocketKeyList(keyList)
    end

    uiutils.add_icon_action_button(icons.MD_CACHED, 'Refresh', 'refresh', 'Refresh')

    ImGui.Separator()
    ImGui.TextWrapped('Tracks repaired keys for Pocket Full of Keys Part I and Part II, and launches the hand-in scripts when ready.')

    drawPocketSection('Part I', PART1_KEYS, PART1_SCRIPT, PART1_ACHIEVEMENT_ID)
    drawPocketSection('Part II', PART2_KEYS, PART2_SCRIPT, PART2_ACHIEVEMENT_ID)

    ImGui.EndTabItem()
end

function RenderTabBar()
    ImGui.BeginTabBar("TabBar", ImGuiTabBarFlags.Reorderable)

    RenderAllMissionsTab()
    RenderMissionKeysTab()
    RenderPocketKeysTab()
    RenderSettingsTab()

    ImGui.EndTabBar()
end

return actions