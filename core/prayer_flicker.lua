---@version 1.0.3
--[[
    File: prayer_flicker.lua
    Description: This class is designed for dynamic prayer switching based on various threat types
    Author: Sonson
]]
---@class PrayerFlicker
---@field config PrayerFlickerConfig
---@field state PrayerFlickerState
local PrayerFlicker = {}
PrayerFlicker.__index = PrayerFlicker

--#region example config
--[[
    an example config could look something like this
    local config = {
        prayers = {
            PrayerFlicker.PRAYERS.SOUL_SPLIT,           -- [1]
            PrayerFlicker.PRAYERS.DEFLECT_MELEE,        -- [2]
            PrayerFlicker.PRAYERS.DEFLECT_MAGIC,        -- [3]
            PrayerFlicker.PRAYERS.DEFLECT_RANGED,       -- [4]
        },
        defaultPrayer = config.prayers[1],
        projectiles = {
            {
                id = 7714,
                prayer = config.prayers[4],
                bypassCondition = function() return Utils.isDivertActive() end,
                priority = 2,
                activationDelay = 1,
                duration = 1
            },
            {
                id = 7718,
                prayer = config.prayers[3],
                bypassCondition = function() return Utils.isDivertActive() or Utils.isEdictAnimationActive() end,
                priority = 1,
                activationDelay = 1,
                duration = 1
            }
        },
        npcs = {
            {
                id = Constants.NPCS.ZAMORAK.ID,
                animations = {
                    {
                        animId = Constants.NPCS.ZAMORAK.ANIMATIONS.MELEE_ATTACK,
                        prayer = config.prayers[2],
                        activationDelay = 2,
                        duration = 4,
                        priority = 100
                    }
                }
            },
            {
                id = Constants.NPCS.CHAOS_WITCH.ID,
                animations = {
                    {
                        animId = Constants.NPCS.CHAOS_WITCH.ANIMATIONS.MAGIC_ATTACK,
                        prayer = config.prayers[3],
                        activationDelay = 0,
                        duration = 2,
                        priority = 1
                    }
                }
            }
        },
        conditionals = {
            {
                condition = function() return isNearChaosTrap(5) end,
                prayer = config.prayers[3],
                priority = 10,
                duration = 3
            }
        }
    }
]]
--#endregion

--#region luaCATS annotation
---@class Prayer
---@field name string
---@field buffId number

---@class PrayerFlickerConfig
---@field defaultPrayer Prayer | nil
---@field prayers Prayer[]
---@field projectiles Projectile[] | nil
---@field npcs PrayerFlickerNPC[] | nil
---@field conditionals Conditional[] | nil

---projectile threat data
---@class Projectile
---@field id projectileId
---@field prayer Prayer
---@field bypassCondition nil | fun(): boolean
---@field priority number
---@field activationDelay number
---@field duration number

---npc animation data
---@class PrayerFlickerNPC
---@field id npcId
---@field animations Animation[]

---animation threat data
---@class Animation
---@field animId animationId
---@field prayer Prayer
---@field activationDelay number
---@field bypassCondition nil | fun(): boolean
---@field duration number
---@field priority number
---@field overrideAnim animationId | nil

---conditional threat data
---@class Conditional
---@field condition fun(): boolean
---@field bypassCondition nil | fun(): boolean
---@field prayer Prayer
---@field priority number
---@field duration number

---@class PrayerFlickerState
---@field activePrayer Prayer
---@field lastPrayerTick number
---@field pendingActions Threat[]

---@class Threat
---@field type threatType
---@field projId projectileId
---@field animId animationId
---@field npcId npcId
---@field condition fun(): boolean
---@field prayer Prayer
---@field priority number
---@field activateTick gameTick
---@field expireTick gameTick
---@field overrideAnim animationId | nil

---@alias threatType
---| "projectile"
---| "animation"
---| "conditional"

---@alias gameTick number
---@alias projectileId number
---@alias npcId number
---@alias animationId number
--#endregion

local API = require("api")

local debug = false

---debug logging function
---@param message string
local function debugLog(message)
    if debug then
        print("[PRAYER_FLICKER]: " .. message)
    end
end

---creates a new PrayerFlicker instance
---@param config PrayerFlickerConfig
---@return PrayerFlicker
function PrayerFlicker.new(config)
    local self = setmetatable({}, PrayerFlicker)
    -- terminate if no config
    if not config then
        print("[PRAYER_FLICKER]: You need to provide a configuration list when initializing.")
        print("[PRAYER_FLICKER]: Terminating your session.")
        API.Write_LoopyLoop(false)
    end

    debugLog("Initializing PrayerFlicker with config")

    self.config = {
        prayers = config.prayers,
        defaultPrayer = config.defaultPrayer or {},
        projectiles = config.projectiles or {},
        npcs = config.npcs or {},
        conditionals = config.conditionals or {}
    }

    self:_checkPrayersOnAbilityBars()

    self.state = {
        ---@diagnostic disable-next-line
        activePrayer = {},
        lastPrayerTick = 0,
        lastUpdateTick = 0,
        pendingActions = {},
        lastAttemptedPrayer = {},  -- NEW: Track last prayer we tried to click
        lastAttemptedTick = 0,     -- NEW: When we last attempted a prayer click
        -- Debug state tracking to prevent spam
        lastPendingCount = 0,
        lastRequiredPrayer = "",
        lastActivePrayer = ""
    }

    return self
end


---@type table<any, Prayer>
---@enum prayers list of prayers to choose from
PrayerFlicker.PRAYERS = {
    SOUL_SPLIT          = { name = "Soul Split",     buffId = 26033 },
    DEFLECT_MELEE       = { name = "Deflect Melee",  buffId = 26040 },
    DEFLECT_MAGIC       = { name = "Deflect Magic",  buffId = 26041 },
    DEFLECT_RANGED      = { name = "Deflect Ranged", buffId = 26044 },
    DEFLECT_NECROMANCY  = { name = "Deflect Necromancy", buffId = 30745 }
}

---checks to see if the listed prayers exist on available ability bars
---@private
function PrayerFlicker:_checkPrayersOnAbilityBars()
    local missingPrayers = {}

    for _, prayer in pairs(self.config.prayers) do
        if #API.GetABs_names({prayer.name}) < 1 then
            table.insert(missingPrayers, prayer.name)
        end
    end

    if #missingPrayers >= 1 then
        print("[PRAYER FLICKER]: Missing prayers!")
        print("[PRAYER FLICKER]: Please make sure to add the following prayers to your ability bars.")
        print("[PRAYER FLICKER]: " .. table.concat(missingPrayers, ", "))
        print("[PRAYER FLICKER]: Terminating your session.")

        API.Write_LoopyLoop(false)
    else
        debugLog("All required prayers found on ability bars")
    end
end

---gets the active prayer
---@return Prayer
function PrayerFlicker:_getCurrentPrayer()
    debugLog("=== CHECKING CURRENT PRAYER ===")
    
    -- Check all configured prayers
    for i, prayer in ipairs(self.config.prayers) do
        local buffStatus = API.Buffbar_GetIDstatus(prayer.buffId, false)
        debugLog(string.format("Prayer %d: %s (ID: %d) - Found: %s", 
            i, prayer.name, prayer.buffId, tostring(buffStatus.found)))
        
        if buffStatus.found then
            debugLog(string.format("FOUND ACTIVE PRAYER: %s", prayer.name))
            debugLog("=== END PRAYER CHECK ===")
            return prayer
        end
    end
    
    -- If we get here, no configured prayers are active
    debugLog("NO CONFIGURED PRAYERS FOUND ACTIVE")
    
    -- Debug: Check what prayers ARE active
    local allActiveBuffs = API.Buffbar_GetAllIDs(false)
    debugLog("All active prayer buffs:")
    for _, buff in ipairs(allActiveBuffs) do
        if buff.id >= 26000 and buff.id <= 27000 then -- Prayer buff ID range
            debugLog(string.format("  Active prayer buff ID: %d", buff.id))
        end
    end
    
    debugLog("=== END PRAYER CHECK ===")
    return {}
end

--#region threat checks
---checks if the projectile threat still exists
---@private
---@param projectileId projectileId
---@return boolean
function PrayerFlicker:_projectileExists(projectileId)
    local projectiles = API.GetAllObjArray1({ projectileId }, 60, { 5 })
    local exists = #projectiles > 0
    if exists then
        debugLog("Projectile " .. projectileId .. " detected (" .. #projectiles .. " found)")
    end
    return exists
end

---checks if the animation threat still exists
---@private
---@param npcId npcId
---@param animId animationId
---@param overrideAnim animationId | nil
---@return boolean
function PrayerFlicker:_animationExists(npcId, animId, overrideAnim)
    local npcs = API.GetAllObjArray1({ npcId }, 60, { 1 })
    for _, npc in ipairs(npcs) do
        if npc.Id then
            -- Check for original animation
            if npc.Anim == animId then 
                debugLog("Animation threat detected - NPC " .. npcId .. " with animation " .. animId)
                return true 
            end
            -- Check for override animation if specified
            if overrideAnim and npc.Anim == overrideAnim then
                debugLog("Override animation threat detected - NPC " .. npcId .. " with override animation " .. overrideAnim .. " (original: " .. animId .. ")")
                return true
            end
        end
    end
    return false
end

---checks if the conditional threat still exists
---@private
---@param condFn fun(): boolean
---@return boolean
function PrayerFlicker:_conditionalThreatExists(condFn)
    local exists = condFn()
    if exists then
        debugLog("Conditional threat is active")
    end
    return exists
end

--#endregion

--#region threat scans
---checks for projectile threats and adds them to self.state.pendingActions
---@private
---@param currentTick gameTick
function PrayerFlicker:_scanProjectiles(currentTick)
    for _, proj in ipairs(self.config.projectiles) do
        if not (proj.bypassCondition and proj.bypassCondition()) then
            if self:_projectileExists(proj.id) then
                -- Check if this threat already exists
                local alreadyExists = false
                for _, existingAction in ipairs(self.state.pendingActions) do
                    if existingAction.type == "projectile" and existingAction.projId == proj.id then
                        alreadyExists = true
                        break
                    end
                end
                
                if not alreadyExists then
                    debugLog("Adding projectile threat: " .. proj.id .. " -> " .. proj.prayer.name .. " (priority: " .. (proj.priority or 0) .. ")")
                table.insert(self.state.pendingActions, {
                    type = "projectile",
                    projId = proj.id,
                    prayer = proj.prayer,
                    priority = proj.priority or 0,
                    activateTick = currentTick + (proj.activationDelay or 0),
                    expireTick = currentTick + (proj.activationDelay or 0) + (proj.duration or 1)
                })
            end
            end
        else
            debugLog("Projectile " .. proj.id .. " bypassed by condition")
        end
    end
end

---checks for npcs and animations and adds them to self.state.pendingActions
---@private
---@param currentTick gameTick
function PrayerFlicker:_scanAnimations(currentTick)
    for _, npc in ipairs(self.config.npcs) do
        local npcs = API.GetAllObjArray1({ npc.id }, 60, { 1 })
        for _, npcObj in ipairs(npcs) do
            if npcObj.Id then
                for _, anim in ipairs(npc.animations) do
                    if not (anim.bypassCondition and anim.bypassCondition()) then
                        if npcObj.Anim == anim.animId then
                            -- Check if this threat already exists
                            local alreadyExists = false
                            for _, existingAction in ipairs(self.state.pendingActions) do
                                if existingAction.type == "animation" and 
                                   existingAction.npcId == npc.id and 
                                   existingAction.animId == anim.animId then
                                    alreadyExists = true
                                    break
                                end
                            end
                            
                            if not alreadyExists then
                                debugLog("Adding animation threat: NPC " .. npc.id .. " anim " .. anim.animId .. " -> " .. anim.prayer.name .. " (priority: " .. (anim.priority or 0) .. ")")
                            table.insert(self.state.pendingActions, {
                                type = "animation",
                                npcId = npc.id,
                                animId = anim.animId,
                                prayer = anim.prayer,
                                priority = anim.priority or 0,
                                activateTick = currentTick + (anim.activationDelay or 0),
                                expireTick = currentTick + (anim.activationDelay or 0) + (anim.duration or 1),
                                overrideAnim = anim.overrideAnim
                            })
                        end
                        end
                    else
                        debugLog("Animation " .. anim.animId .. " on NPC " .. npc.id .. " bypassed by condition")
                    end
                end
            end
        end
    end
end

---checks for conditional threats and adds them to self.state.pendingActions
---@private
---@param currentTick gameTick
function PrayerFlicker:_scanConditionals(currentTick)
    for _, cond in ipairs(self.config.conditionals) do
        if not(cond.bypassCondition and cond.bypassCondition()) then
            if cond.condition() then
                debugLog("Adding conditional threat -> " .. cond.prayer.name .. " (priority: " .. cond.priority .. ")")
                table.insert(self.state.pendingActions, {
                    type = "conditional",
                    condition = cond.condition,
                    prayer = cond.prayer,
                    priority = cond.priority,
                    activateTick = currentTick,
                    expireTick = currentTick + cond.duration
                })
            end
        else
            debugLog("Conditional threat bypassed by condition")
        end
    end
end

--#endregion

---cleans up self.state.pendingActions, keeping only active threats
---@private
---@param currentTick gameTick
function PrayerFlicker:_cleanupPendingActions(currentTick)
    for i = #self.state.pendingActions, 1, -1 do
        local action = self.state.pendingActions[i]

        -- only remove if expired
        if action.expireTick <= currentTick then
            debugLog("Removing expired threat: " .. action.type .. " -> " .. action.prayer.name)
            table.remove(self.state.pendingActions, i)

            -- remove if threat no longer exists and not active
        elseif action.activateTick > currentTick then
            if action.type == "projectile" and not self:_projectileExists(action.projId) then
                debugLog("Removing inactive projectile threat: " .. action.projId .. " -> " .. action.prayer.name)
                table.remove(self.state.pendingActions, i)
            elseif action.type == "animation" and not self:_animationExists(action.npcId, action.animId, action.overrideAnim) then
                debugLog("Removing inactive animation threat: NPC " .. action.npcId .. " anim " .. action.animId .. " -> " .. action.prayer.name)
                table.remove(self.state.pendingActions, i)
            elseif action.type == "condition" and not self:_conditionalThreatExists(action.condition) then
                debugLog("Removing inactive conditional threat -> " .. action.prayer.name)
                table.remove(self.state.pendingActions, i)
            end
        -- Also remove if threat no longer exists even if it's supposed to be active
        elseif action.type == "animation" and not self:_animationExists(action.npcId, action.animId, action.overrideAnim) then
            debugLog("Removing ended animation threat: NPC " .. action.npcId .. " anim " .. action.animId .. " -> " .. action.prayer.name)
            table.remove(self.state.pendingActions, i)
        elseif action.type == "projectile" and not self:_projectileExists(action.projId) then
            debugLog("Removing ended projectile threat: " .. action.projId .. " -> " .. action.prayer.name)
            table.remove(self.state.pendingActions, i)
        end
    end
end

---determines the prayer to use based on threat priorities
---@private
---@param currentTick gameTick
---@return Prayer
function PrayerFlicker:_determineActivePrayer(currentTick)
    -- sort threats by priority (highest first)
    table.sort(self.state.pendingActions, function(a, b)
        return (a.priority or 0) > (b.priority or 0)
    end)

    for _, action in ipairs(self.state.pendingActions) do
        if action.activateTick <= currentTick and action.expireTick > currentTick then
            debugLog("Active threat found: " .. action.type .. " -> " .. action.prayer.name .. " (priority: " .. (action.priority or 0) .. ")")
            return action.prayer
        end
    end

    return self.config.defaultPrayer
end

---@private
---@param prayer Prayer
---@return boolean
-- Updated _switchPrayer function:
function PrayerFlicker:_switchPrayer(prayer)
    if not prayer then 
        debugLog("No prayer provided to switch to")
        return false 
    end
    
    if not prayer.name then
        debugLog("Prayer has no name, skipping switch")
        return false
    end
    
    local currentTick = API.Get_tick()
    local currentPrayer = self:_getCurrentPrayer()

    -- ORIGINAL CHECK: prayer actually detected as active
    if (self.state.activePrayer.buffId == prayer.buffId and self.state.lastPrayerTick + 4 > currentTick) or (currentPrayer.buffId == prayer.buffId) then
        debugLog("Prayer " .. prayer.name .. " is already active, skipping switch")
        return false
    end
    
    -- NEW CHECK: prevent clicking same prayer we just attempted
    if self.state.lastAttemptedPrayer.buffId == prayer.buffId and (currentTick - self.state.lastAttemptedTick) <= 6 then
        debugLog(string.format("Already attempted %s %d ticks ago, skipping duplicate click", 
            prayer.name, currentTick - self.state.lastAttemptedTick))
        return false
    end

    debugLog("Attempting to switch to prayer: " .. prayer.name)

    -- flick prayer
    local success = API.DoAction_Ability(
        prayer.name,
        1,
        API.OFF_ACT_GeneralInterface_route,
        true
    )

    if success then
        self.state.lastPrayerTick = currentTick
        self.state.activePrayer = prayer
        self.state.lastAttemptedPrayer = prayer    -- NEW: Track what we just attempted
        self.state.lastAttemptedTick = currentTick -- NEW: Track when we attempted it
        debugLog("Successfully switched to prayer: " .. prayer.name)
    else
        -- Even if click failed, still track the attempt to prevent spam
        self.state.lastAttemptedPrayer = prayer
        self.state.lastAttemptedTick = currentTick
        debugLog("Failed to switch to prayer: " .. prayer.name)
    end

    return success
end

---disables active prayer or selected prayer
---@param prayer? Prayer optional if you want to turn off a specific prayer
---@return boolean
function PrayerFlicker:deactivatePrayer(prayer)
    local currentTick = API.Get_tick()
    prayer = prayer or self:_getCurrentPrayer()
    if not prayer.name or ((currentTick - self.state.lastPrayerTick < 1) and not self.state.activePrayer.name) then return false end

    local success = API.DoAction_Ability(
        prayer.name,
        1,
        API.OFF_ACT_GeneralInterface_route,
        true
    )

    if success then
        self.state.lastPrayerTick = API.Get_tick()
        debugLog("Successfully deactivated prayer: " .. (prayer.name or "unknown"))
        ---@diagnostic disable-next-line
        self.state.activePrayer = {}
    else
        debugLog("Failed to deactivate prayer: " .. (prayer.name or "unknown"))
    end

    return success
end

---updates PrayerFlicker instance
---@return boolean
-- Fix the update() function to handle prayer transition periods:

    function PrayerFlicker:update()
        local currentTick = API.Get_tick()
        
        -- Prevent multiple updates in the same tick
        if self.state.lastUpdateTick == currentTick then
            return false
        end
        self.state.lastUpdateTick = currentTick
        
        local pendingCountBefore = #self.state.pendingActions
        local showDetailedDebug = false
        
        -- Only show detailed debug if pending actions count changed
        if pendingCountBefore ~= self.state.lastPendingCount then
            showDetailedDebug = true
            debugLog("=== PrayerFlicker Update (Tick: " .. currentTick .. ") ===")
            debugLog("Pending actions before scan: " .. pendingCountBefore)
        end
    
        if self.config.projectiles and #self.config.projectiles > 0 then
            self:_scanProjectiles(currentTick)
        end
        if self.config.npcs and #self.config.npcs > 0 then
            self:_scanAnimations(currentTick)
        end
        if self.config.conditionals and #self.config.conditionals > 0 then
            self:_scanConditionals(currentTick)
        end
        
        local pendingCountAfterScan = #self.state.pendingActions
        if showDetailedDebug or pendingCountAfterScan ~= pendingCountBefore then
            if not showDetailedDebug then
                debugLog("=== PrayerFlicker Update (Tick: " .. currentTick .. ") ===")
                debugLog("Pending actions before scan: " .. pendingCountBefore)
            end
            debugLog("Pending actions after scan: " .. pendingCountAfterScan)
            showDetailedDebug = true
        end
        
        self:_cleanupPendingActions(currentTick)
        local pendingCountAfterCleanup = #self.state.pendingActions
        
        if showDetailedDebug or pendingCountAfterCleanup ~= pendingCountAfterScan then
            if not showDetailedDebug then
                debugLog("=== PrayerFlicker Update (Tick: " .. currentTick .. ") ===")
                debugLog("Pending actions before scan: " .. pendingCountBefore)
                debugLog("Pending actions after scan: " .. pendingCountAfterScan)
            end
            debugLog("Pending actions after cleanup: " .. pendingCountAfterCleanup)
            showDetailedDebug = true
        end
        
        local requiredPrayer = self:_determineActivePrayer(currentTick)
        local requiredPrayerName = requiredPrayer and requiredPrayer.name or "None"
        local currentPrayer = self:_getCurrentPrayer()
        local currentPrayerName = currentPrayer and currentPrayer.name or "None"
        
        -- TRANSITION PERIOD PROTECTION: Don't update state tracking if we just switched prayers
        local recentlySwapped = (currentTick - self.state.lastPrayerTick) <= 3
        local inTransition = recentlySwapped and currentPrayerName == "None" and self.state.activePrayer and self.state.activePrayer.name
        
        if inTransition then
            -- Use the last known active prayer instead of "None" during transition
            currentPrayerName = self.state.activePrayer.name
            debugLog(string.format("TRANSITION PERIOD: Using last known prayer (%s) instead of 'None'", currentPrayerName))
        end
        
        -- Check if prayer state changed (but ignore transitions to "None")
        if requiredPrayerName ~= self.state.lastRequiredPrayer or (currentPrayerName ~= self.state.lastActivePrayer and not inTransition) then
            if not showDetailedDebug then
                debugLog("=== PrayerFlicker Update (Tick: " .. currentTick .. ") ===")
            end
            if requiredPrayerName ~= self.state.lastRequiredPrayer then
                debugLog("Required prayer changed: " .. self.state.lastRequiredPrayer .. " -> " .. requiredPrayerName)
            end
            if currentPrayerName ~= self.state.lastActivePrayer and not inTransition then
                debugLog("Active prayer changed: " .. self.state.lastActivePrayer .. " -> " .. currentPrayerName)
            end
            showDetailedDebug = true
        end
        
        local result = self:_switchPrayer(requiredPrayer)
        
        if showDetailedDebug then
            debugLog("=== End PrayerFlicker Update ===")
        end
        
        -- Update state tracking (but don't overwrite with "None" during transitions)
        self.state.lastPendingCount = pendingCountAfterCleanup
        self.state.lastRequiredPrayer = requiredPrayerName
        if not inTransition then
            self.state.lastActivePrayer = currentPrayerName
        end
        
        return result
    end

---can use with API.DrawTable(PrayerFlicker:tracking()) to check metrics
---@return table
function PrayerFlicker:tracking()
    local currentPrayer = self:_getCurrentPrayer()
    local requiredPrayer = self:_determineActivePrayer(API.Get_tick())
    
    local metrics = {
        { "Prayer Flicker:", "" },
        { "-- Active",       currentPrayer and currentPrayer.name or "None" },
        { "-- Last Used",    self.state.activePrayer and self.state.activePrayer.name or "None" },
        { "-- Required",     requiredPrayer and requiredPrayer.name or "None" },
        { "-- Pending Actions", tostring(#self.state.pendingActions) },
        { "-- Debug Mode", debug and "Enabled" or "Disabled" },
    }
    return metrics
end

return PrayerFlicker

--[[
Changelog:
    - v1.0.4:
        - Checks for prayers on ability bars when initializing
            - Terminates script if prayers are not found & outputs missing prayers
        - Added prayerFlicker.PRAYERS as enum for users to choose prayers from
            - Currently only has data for curses
        - Improved fail safes

    - v1.0.3:
        - Added bypass condition to NPCs and Conditional threats
        - Fixed bypass condition luaCATS annotation

    - v1.0.2 :
        - Fixes and improvements to conditional threat detection

    - v1.0.1:
        - Added PrayerFlicker:deactivatePrayer()
        - update() and & _switchPrayer() now return true when prayer is switched

    - v1.0.0:
        -Initial release
]]
