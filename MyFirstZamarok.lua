local API = require("api")
local RotationManager = require("MyFirstZamarok.core.rotation_manager")
local PrayerFlicker = require("MyFirstZamarok.core.prayer_flicker")
local Timer = require("MyFirstZamarok.core.timer")
local Utils = require("MyFirstZamarok.MFZ.utils")

local lastStatus = ""
local function logStatusChange(newStatus)
    if newStatus ~= lastStatus then
        Utils.debugLog(string.format("Status Change: %s -> %s", lastStatus, newStatus))
        lastStatus = newStatus
    end
end

-- Mechanic and animation placeholders
Local FlamesOfZamarok_Mechanic = {

}

Local DecimateAndChaosBlast_Mechanic = {

}

Local InfernalTomb_Mechanic = {

}

Local AdrenalineCage_Mechanic = {

}

Local ChaosWitchChannelers_Mechanic = {

}

Local RunesofDestruction_Mechanic = {

}

Local RunesAndHexes_Mechanic = {

}

-- Gearing and swapping at higher enrages
local GEAR_IDS = {
    PowerMelee = {
        HEAD = ,
        BODY = ,
        LEGS = ,
        BOOTS = 
    },
    TANKMelee = {
        HEAD = ,
        BODY = ,
        LEGS = ,
        BOOTS = 
    }
}

-- Helper function to perform improvise using any rotation manager instance
local function performImprovise(rotationInstance, spend, iterations)
    iterations = iterations or 1
    spend = spend or false
    
    for i = 1, iterations do
        -- Get the best ability to use from improvise system
        local bestAbility = rotationInstance:_improvise(spend)
        
        -- Use the ability
        if bestAbility then
            if rotationInstance:_useAbility(bestAbility) then
                Utils.debugLog("Used improvised ability: " .. bestAbility)
                return true
            else
                Utils.debugLog("Failed to use improvised ability: " .. bestAbility)
                return false
            end
        end
    end
    return false
end

Config.Instances, Config.TrackedKills = {}, {}

Config.UserInput = {
    -- essential
    useBankPin = false,
    bankPin = 1234,                 -- use ur own [0000 will spam your console]
    targetCycleKey = 0x09,          -- 0x09 is tab
    -- health and prayer thresholds (settings for player manager)
    healthThreshold = {
        normal = {type = "percent", value = 65},
        critical = {type = "percent", value = 60},
        special = {type = "percent", value = 70}  -- excal threshold
    },
    prayerThreshold = {
        normal = {type = "current", value = 340},
        critical = {type = "percent", value = 10},
        special = {type = "current", value = 600}  -- elven shard threshold
    },
    -- things to check in your inventory before fight
    presetChecks = {
        {id = 48951, amount = 21}, -- 21 x vuln bombs
        {id = 28227, amount = 4},  -- 4  x super sara brews
        {id = 42267, amount = 5},  -- 5  x blue blubbers
		{id = 57164, amount = 1},  -- 1  x ode to deceit
    },
    aura = {
        id = 22294,
        name = "Equilibrium aura",
        buffId = 26098, 
        interfaceSlot = 23
    },
