--[[
    Created by Cannonballdex
    PocketFullOfKeys1lua - Hands in all 6 repaired keys to the clockwork artificer for the quest "Pocket Full of Keys Part I"
--]]
local mq = require('mq')
local mq_utils = require('utils.mq_utils')

local ZONE_NAME = 'anniversarytower'
local NPC_NAME = 'a clockwork artificer'
local REQUEST_PHRASE = 'first six keys'   -- change to "active set" if needed
local WAIT_TIME = 1000
local ZONE_WAIT = 60000
local waitFor = mq_utils.waitFor

local KEYS = {
    'Repaired Key of Sand',
    'Repaired Key of Lava',
    'Repaired Key of Forests',
    'Repaired Key of Frost',
    'Repaired Key of Sky',
    'Repaired Key of Steam',
}

local function log(msg, ...)
    printf('[HandKeys] ' .. msg, ...)
    if mq.TLO.Lua.Script('overseer').Status() == "RUNNING" then
        mq.cmd('/rgl pause')
    end
end

local function inZone(zoneName)
    return mq.TLO.Zone.ShortName() == zoneName
end

local function haveTarget()
    local id = mq.TLO.Target.ID()
    return id ~= nil and id > 0
end

local function cursorHasItem()
    local id = mq.TLO.Cursor.ID()
    return id ~= nil and id > 0
end

local function cursorEmpty()
    local id = mq.TLO.Cursor.ID()
    return id == nil or id == 0
end

local function openInventory()
    if not mq.TLO.Window('InventoryWindow').Open() then
        mq.TLO.Window('InventoryWindow').DoOpen()
        mq.delay(1000)
    end
end

local function travelToZone(zoneName)
    if inZone(zoneName) then
        return true
    end

    log('Traveling to %s', zoneName)
    mq_utils.TravelTo(zoneName)

    local ok = waitFor(ZONE_WAIT, function()
        return inZone(zoneName)
    end)

    if not ok then
        log('Failed to reach zone: %s', zoneName)
    end

    return ok
end

local function targetNPC()
    mq.cmd('/target npc "' .. NPC_NAME .. '"')
    if mq.TLO.Target.Distance() > 25 then
        log('NPC is too far away')
        mq.cmdf('/nav spawn %s', NPC_NAME)
    end
    while mq.TLO.Target.Distance() > 25 do
        mq.delay(5000)
    end
    mq.delay(2000, haveTarget)

    if not haveTarget() then
        log('Could not target NPC')
        return false
    end

    mq.cmd('/face')
    return true
end

local function activateTask()
    log('Sending phrase: %s', REQUEST_PHRASE)
    mq.cmd('/say ' .. REQUEST_PHRASE)

    -- give NPC time to respond / enable trade
    mq.delay(2000)
end

local function haveItem(itemName)
    local count = mq.TLO.FindItemCount('=' .. itemName)()
    return count ~= nil and count > 0
end

local function pickUpOne(itemName)
    local item = mq.TLO.FindItem('=' .. itemName)

    local slot1 = item.ItemSlot() - 22
    local slot2 = item.ItemSlot2() + 1

    mq.cmd('/itemnotify in pack' .. slot1 .. ' ' .. slot2 .. ' leftmouseup')
    mq.delay(WAIT_TIME)

    if mq.TLO.Window('QuantityWnd').Open() then
        while mq.TLO.Window('QuantityWnd').Child('QTYW_SliderInput').Text() ~= '1' do
            mq.TLO.Window('QuantityWnd').Child('QTYW_SliderInput').SetText('1')
            mq.delay(50)
        end

        while mq.TLO.Window('QuantityWnd').Open() do
            mq.cmd('/notify QuantityWnd QTYW_Accept_Button leftmouseup')
            mq.delay(100)
        end
    end

    mq.delay(WAIT_TIME, cursorHasItem)
end

local function giveItem()
    mq.cmd('/click left target')
    mq.delay(WAIT_TIME, cursorEmpty)
end

local function clickTrade()
    mq.delay(500)

    for _ = 1, 5 do
        mq.cmd('/notify TradeWnd TRDW_Trade_Button leftmouseup')
        mq.delay(300)
    end
end

local function autoinv()
    if cursorHasItem() then
        mq.cmd('/autoinv')
        mq.delay(500)
    end
end

local function handIn(itemName)
    if not haveItem(itemName) then
        log('Skipping missing key: %s', itemName)
        return true
    end

    log('Giving: %s', itemName)

    pickUpOne(itemName)
    giveItem()

    mq.delay(1000)
    clickTrade()
    mq.delay(2000)

    autoinv()

    return true
end

local function run()
    if not travelToZone(ZONE_NAME) then
        return
    end
    openInventory()

    if not targetNPC() then return end

    activateTask()

    for _, key in ipairs(KEYS) do
        if not handIn(key) then
            log('Stopped on %s', key)
            return
        end
    end

    log('All keys handed in successfully')
    if mq.TLO.Lua.Script('overseer').Status() == "RUNNING" then
        mq.cmd('/rgl unpause')
    end
end

run()