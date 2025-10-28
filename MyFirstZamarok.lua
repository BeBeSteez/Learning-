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
-- PlaceHolder
}

Local DecimateAndChaosBlast_Mechanic = {
-- PlaceHolder
}

Local InfernalTomb_Mechanic = {
-- PlaceHolder
}

Local AdrenalineCage_Mechanic = {
-- PlaceHolder
}

Local ChaosWitchChannelers_Mechanic = {
-- PlaceHolder
}

Local RunesofDestruction_Mechanic = {
-- PlaceHolder
}

Local RunesAndHexes_Mechanic = {
-- PlaceHolder
}

local Zamarok_Id = 
-- Object IDs for mechanic end detection
local MECHANIC_OBJECTS = {
-- PlaceHolder
}

-- Gearing and swapping at higher enrages
local GEAR_IDS = {
    PowerMeleeGear = {
        HEAD = ,
        BODY = ,
        LEGS = ,
        BOOTS = 
    },
    TANKMeleeGear = {
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
        {id = 48951, amount = 34}, -- 21 x vuln bombs
        {id = 28227, amount = 6},  -- 4  x super sara brews
        {id = 42267, amount = 6},  -- 5  x blue blubbers
		{id = 57164, amount = 1},  -- 1  x ode to deceit
    },
    aura = {
        id = 22294,
        name = "Equilibrium aura",
        buffId = 26098, 
        interfaceSlot = 23
    },
	--discord (private method)
    discordNotifications = false,
    webhookUrl = "Webhook_URL",
    mention = false,
    userId = "User_ID"
}	

Config.Variables = {
    -- flags 
    initialCheck = false,
    bossDead = false,
    initialRotationComplete = false,  -- Track if initial rotation is complete
    hasUniqueInChest = false,  -- New flag to track if unique is in chest
    chestChecked = false,  -- Track if chest has been checked this kill
    clickedAqueductPortal = false,  -- New flag to track if we've clicked the aqueduct portal
    -- mechanic tracking
    currentMechanic = "none",
    lastMechanic = "none",
    pendingMechanic = "none",
    mechanicStartTick = 0,
    lastMechanicDetectionTick = 0,  -- Track when last mechanic was detected for cooldown
    mechanicCount = 0,
    mechanicHistory = {},  -- Track the 5 mechanics in order
    -- minion targeting
    targetMinionsActive = false,  -- Flag to control when minion targeting timer is active
    -- attempts
    bankAttempts = 0,
    killCount = 0,
    -- tiles
    adreCrystalTile = {x = 0, y = 0, z = 0},
    adreCrystalBDTile = {x = 0, y = 0, z = 0},
    portalTile = {x = 0, y = 0, z = 0},
    lootTile = {x = 0, y = 0, z = 0},
    startspot = {x = 0, y = 0, range = 0},  -- Initialize startspot
    safeSpot = {x = 0, y = 0, range = 0},
    -- misc
    adrenCrystalSide = "East",
    gateTile = nil,
    inPowerMeleeGear = false,
    mechanicEndTicks = {
    -- Placeholder  
    },
    chestLooted = false,  -- Track if we've looted/continued from chest
    chestContainerOpenTime = 0,  -- Track when chest container first opened
    deathStep = nil,
    deathStepTick = nil,
    deathLootStep = nil,
    deathLootStepTick = nil,
    -- Death loot tracking variables
    diedInBossRoom = false,  -- Track if we died in the boss room
    hadContinuedChallenge = false,  -- Track if we had continued challenge before death
    deathLootAvailable = false,  -- Track if there's loot to collect from death
    everUsedContinueChallenge = false,  -- Track if continue challenge has ever been used this session
    totalSeenInChest = 0,
    totalClaimed = 0,
    killLogged = false,
    enrageDetected = false,
}
