--[[
    Sonaran CAD Plugins

    Plugin Name: dispatchnotify
    Creator: dispatchnotify
    Description: Describe your plugin here

    Put all server-side logic in this file.
]]

local pluginConfig = Config.GetPluginConfig("dispatchnotify")

if pluginConfig.enabled then

    local DISPATCH_TYPE = {"CALL_NEW", "CALL_EDIT", "CALL_CLOSE", "CALL_NOTE", "CALL_SELF_CLEAR"}
    local ORIGIN = {"CALLER", "RADIO_DISPATCH", "OBSERVED", "WALK_UP"}
    local STATUS = {"PENDING", "ACTIVE", "CLOSED"}

    local Active_Calls = {}
    local Incoming_Calls = {}
    local Active_Units = {}

    local PlayerMapping = {}

    local CallList = { 
        activeCalls = nil,
        pendingCalls = nil,
        closedCalls = nil
    }

    registerApiType("GET_CALLS", "emergency")
    local function GetCalls()
        local payload = { serverId = Config.serverId}
        performApiRequest({payload}, "GET_CALLS", function(allcalls)
            local calls = json.decode(allcalls)
            CallList.activeCalls = calls.activeCalls
            CallList.pendingCalls = calls.emergencyCalls
            CallList.closedCalls = calls.closedCalls
        end)
    end

    local function getPlayerSource(identifier)
        local activePlayers = GetPlayers()
        for i,player in pairs(activePlayers) do
            local identifiers = GetIdentifiers(player)
            local primary = identifiers[Config.primaryIdentifier]
            debugLog(("Check %s has identifier %s = %s"):format(player, primary, identifier))
            if primary == identifier then
                return player
            end
        end
        return nil
    end

    local function getPlayerApiId(player)
        local identifiers = GetIdentifiers(player)
        local primary = identifiers[Config.primaryIdentifier]
        return primary
    end

    local function getCallIndex(callId, type)
        for k, v in pairs(CallList[type]) do
            debugLog(("getCallIndex(%s,%s): %s == %s?"):format(callId, type, v.callId, callId))
            if tostring(v.callId) == tostring(callId) then
                return k
            end
        end
        return nil
    end

    local function getUnitByApiId(call, apiId)
        if call.units == nil then
            return nil
        end
        for k, v in pairs(call.units) do
            if v.data.apiId1 == apiId or v.data.apiId2 == apiId then
                return v
            end
        end
        return nil
    end

    local function getAssignedCalls(player)
        local calls = {}
        for k, v in pairs(CallList.activeCalls) do
            if v.units then
                for _, unit in pairs(v.units) do
                    if unit.apiId1 == PlayerMapping[player] or unit.apiId2 == PlayerMapping[player] then
                        table.insert(calls, v)
                    end
                end
            end
        end
        return calls
    end

    local CallerCache = {}
    
    local Caller = {
        playerId = nil,
        caller = nil,
        location = nil,
        description = nil,
        emergency = nil
    }

    function Caller.Create(playerId, caller, location, description, emergency)
        local self = shallowcopy(Caller)
        self.playerId = playerId
        self.caller = caller
        self.location = location
        self.description = description
        self.emergency = emergency
        return self
    end

    function Caller:IsMatch(description, location)
        debugLog(("Check: %s = %s - %s - %s"):format(self.description, description, self.location, location))
        return (self.description == description and location == self.location)
    end

    local function findCaller(description, location)
        for k, v in pairs(CallerCache) do
            if v:IsMatch(description, location) then
                return v, k
            end
        end
        return nil
    end

    -- Attach to /911 call to store potential caller information
    AddEventHandler("SonoranCAD::callcommands:SendCallApi", function(emergency, caller, location, description, source)
        local c = Caller.Create(source, caller, location, description, emergency)
        table.insert(CallerCache, c)
        debugLog(("Cached caller %s as player %s"):format(caller, source))
    end)

    RegisterServerEvent("SonoranCAD::pushevents:DispatchEvent")
    AddEventHandler("SonoranCAD::pushevents:DispatchEvent", function(data)
        local dispatchType = data.dispatch_type
        if dispatchType ~= tostring(dispatchType) then
            -- hmm, expected a string, got a number
            dispatchType = DISPATCH_TYPE[data.dispatch_type+1]
        end
        local switch = {
            ["CALL_NEW"] = function()
                table.insert(CallList.activeCalls, data.dispatch) 
                TriggerEvent("SonoranCAD::dispatchnotify:NewCall", data.dispatch)
            end,
            ["CALL_EDIT"] = function() 
                local call = getCallIndex(data.dispatch.callId, "activeCalls")
                local callId = data.dispatch.callId
                if CallList.activeCalls[call] ~= nil then
                    if CallList.activeCalls[call].callId ~= callId then
                        errorLog("FATAL: mismatched call ID")
                        assert(false)
                    end
                    CallList.activeCalls[call] = data.dispatch
                    debugLog(("CALL_EDIT: %s"):format(json.encode(data.dispatch)))
                    for playerId, apiId in pairs(PlayerMapping) do
                        local unit = getUnitByApiId(CallList.activeCalls[call], apiId)
                        if unit ~= nil then
                            TriggerEvent("SonoranCAD::dispatchnotify:UpdateCall", playerId, CallList.activeCalls[call], unit)
                            TriggerClientEvent("SonoranCAD::dispatchnotify:UpdateCall", playerId, CallList.activeCalls[call], unit)
                            debugLog(("Call updated - ID %s - API ID: %s - Player ID: %s"):format(callId, apiId, playerId))
                        end
                    end
                else
                    print("Ignore call edit with no call")
                end
            end,
            ["CALL_CLOSE"] = function() 
                local call = getCallIndex(data.dispatch.callId, "activeCalls")
                local callId = data.dispatch.callId
                if call ~= nil then
                    if #CallList.closedCalls == pluginConfig.closedCount then
                        CallList.closedCalls[1] = CallList.activeCalls[call]
                    else
                        table.insert(CallList.closedCalls, CallList.activeCalls[call])
                    end
                    CallList.activeCalls[call] = nil
                    debugPrint(("Incoming call %s removed due to close"):format(callId))
                end
            end,
            ["CALL_NOTE"] = function() 
                local call = getCallIndex(data.dispatch.callId, "activeCalls")
                if CallList.activeCalls[call] ~= nil then
                    CallList.activeCalls[call].notes = data.dispatch.notes
                    TriggerEvent("SonoranCAD::dispatchnotify::UpdateCallNotes", call, data.dispatch.notes)
                end
            end,
            ["CALL_SELF_CLEAR"] = function() end
        }
        if switch[dispatchType] then
            switch[dispatchType]()
        else
            print("no")
        end
    end)

    AddEventHandler("SonoranCAD::pushevents:IncomingCadCall", function(data)
        table.insert(CallList.pendingCalls, data)
        local callId = data.callId
        for i=0, GetNumPlayerIndices()-1 do
            local player = GetPlayerFromIndex(i)
            debugLog("PLAYER: "..tostring(player))
            local location = data.location
            local description = data.description
            local caller = data.caller
            local callId = data.callId
            if IsPlayerOnDuty(player) then
                if pluginConfig.notifyMethod == "pnotify" then
                    TriggerClientEvent("pNotify:SendNotification", player, {
                        text = pluginConfig.incomingCallMessage:gsub("{location}", location):gsub("{description}", description):gsub("{caller}", caller):gsub("{callId}", callId),
                        type = "error",
                        layout = "bottomcenter",
                        timeout = "10000"
                    })
                elseif pluginConfig.notifyMethod == "chat" then
                    TriggerClientEvent("chat:addMessage", player, {args = {"^0[ ^1911 ^0] ", pluginConfig.incomingCallMessage:gsub("{location}", location):gsub("{description}", description):gsub("{caller}", caller):gsub("{callId}", callId)}})
                end
                TriggerEvent("SonoranCAD::dispatchnotify:incomingCallForUnit", player, location, description, caller)
            else
                warnLog(("Player %s is not on duty"):format(player))
            end
        end
    end)

    registerApiType("NEW_DISPATCH", "emergency")
    registerApiType("ATTACH_UNIT", "emergency")
    RegisterCommand("r911", function(source, args, rawCommand)
        local source = source
        local callId = args[1]
        if not IsPlayerOnDuty(source) then
            TriggerClientEvent("chat:addMessage", source, {args = {"^0[ ^1Error ^0] ", "You need to be on duty to use this command."}})
            print("not on duty")
            return
        end
        --Get the unit's primary identifier for the API call
        local identifier = getPlayerApiId(source)
        if identifier == nil then
            print("no identifier")
            TriggerClientEvent("chat:addMessage", source, {args = {"^0[ ^1Error ^0] ", "Identifier not configured. Failed."}})
            return
        end
        --Check if there's a call already
        local idx = getCallIndex(callId, "activeCalls")
        if idx ~= nil then
            --Active call already, attach instead
            debugLog("Found Call. Attaching!")
            local data = {callId = callId, units = {identifier}}
            performApiRequest({data}, "ATTACH_UNIT", function(res)
                debugLog("Attach OK: "..tostring(res))
                TriggerClientEvent("chat:addMessage", source, {args = {"^0[ ^2Dispatch ^0] ", "You have been attached to the call."}})
                callInfo = CallList.activeCalls[idx]
                if pluginConfig.waypointType == "postal" then
                    if not IsPluginLoaded("postals") then
                        warnLog("Incorrect configuration: dispatchnotify requires postals plugin when set to postal waypoint mode. Ignoring GPS request.")
                    end
                    if callInfo.postal ~= nil and IsPluginLoaded("postals") then
                        --TriggerClientEvent("SonoranCAD::dispatchnotify:SetGps", playerId, ...)
                    else
                        TriggerClientEvent("chat:addMessage", source, {args = {"^0[ ^2Dispatch ^0] ", ("Caller's location: %s"):format(callInfo.location)}})
                    end
                elseif pluginConfig.waypointType == "exact" then
                    --TriggerClientEvent("SonoranCAD::dispatchnotify:GetLocation", playerId, ...)
                elseif pluginConfig.waypointType == "off" then
                    TriggerClientEvent("chat:addMessage", source, {args = {"^0[ ^2Dispatch ^0] ", ("Caller's location: %s"):format(callInfo.location)}})
                end
            end)
        else
            debugLog("Creating new call...")
            local pIdx = getCallIndex(callId, "pendingCalls")
            if pIdx == nil then
                TriggerClientEvent("chat:addMessage", source, {args = {"^0[ ^1Error ^0] ", "Call not found."}})
                return
            end
            local callInfo = CallList.pendingCalls[pIdx]
            local postal = ""

            local payload = {   serverId = Config.serverId,
                                origin = 0, 
                                status = 1, 
                                priority = 2,
                                block = "",
                                code = "",
                                postal = postal,
                                address = callInfo.location, 
                                title = "OFFICER RESPONSE - "..callInfo.callId, 
                                description = callInfo.description, 
                                isEmergency = callInfo.isEmergency,
                                notes = "Officer responding",
                                metaData = { callerApiId = nil, creatorApiId = identifier },
                                units = { identifier }
            }
            performApiRequest({payload}, "NEW_DISPATCH", function(resp)
                debugLog("Call creation OK")
            end)
        end

    end)

    RegisterServerEvent("SonoranCAD::dispatchnotify:NewCall")
    AddEventHandler("SonoranCAD::dispatchnotify:NewCall", function(data)
        if #data.units > 0 then
            -- new call with units, see who's there
            for i, unit in pairs(data.units) do
                local player = nil
                if unit.data.apiId1 ~= nil then
                    player = getPlayerSource(unit.data.apiId1)
                    if player == nil and unit.data.apiId2 ~= nil then
                        player = getPlayerSource(unit.data.apiId2)
                    end
                end
                if player ~= nil then
                    TriggerClientEvent("SonoranCAD::dispatchnotify:CallAttach", player, data, unit)
                    local caller = findCaller(data.description, data.address)
                    if caller then
                        TriggerClientEvent("SonoranCAD::dispatchnotify:CallResponse", caller.playerId, unit.data.name)
                    else
                        debugLog("Unable to find a caller for call ID "..tostring(data.callId))
                    end
                else
                    warnLog("New call detected, but attached unit is not online.")
                end
            end
        end
    end)

    -- Unit Tracking

    RegisterServerEvent('SonoranCAD::pushevents:UnitListUpdate')
    AddEventHandler('SonoranCAD::pushevents:UnitListUpdate', function(unit)
        local unit = unit
        CheckIdentifiers(unit.data.apiId1, unit.data.apiId2, function(apiId)
            -- grab the unit's ID
            local player = getPlayerSource(apiId)
            debugLog(("Unit update: %s - %s"):format(player, apiId))
            if player ~= nil then
                if unit.type == "EVENT_UNIT_LOGIN" then
                    debugLog(("Unit %s is active, API ID %s"):format(player, apiId))
                    Active_Units[apiId] = player
                    TriggerClientEvent("SonoranCAD::dispatchnotify:UnitLogin", player, apiId)
                    TriggerEvent("SonoranCAD::dispatchnotify:UnitLogin", player, apiId)
                elseif unit.type == "EVENT_UNIT_LOGOUT" then
                    Active_Units[apiId] = player
                    debugLog(("Unit %s is inactive, API ID %s"):format(player, apiId))
                    TriggerClientEvent("SonoranCAD::dispatchnotify:UnitLogout", player, apiId)
                    TriggerEvent("SonoranCAD::dispatchnotify:UnitLogout", player, apiId)
                end
            else
                debugLog(("Couldn't find a match for API ID %s"):format(apiId))
            end
        end)
    end)

    AddEventHandler("playerDropped", function(reason)
        local source = source
        for k, v in pairs(Active_Units) do
            if v == source then
                debugLog(("Dropping %s from Active Units"):format(source))
                Active_Units[k] = nil
                return
            end
        end
    end)

    function IsPlayerOnDuty(player)
        for k, v in pairs(Active_Units) do
            if tostring(v) == tostring(player) then
                return true
            end
        end
        return false
    end

    registerApiType("GET_ACTIVE_UNITS", "emergency")
    CreateThread(function()
        Wait(1000)
        local payload = { serverId = Config.serverId}
        performApiRequest({payload}, "GET_ACTIVE_UNITS", function(runits)
            local allUnits = json.decode(runits)
            for k, v in pairs(allUnits) do
                CheckIdentifiers(v.data.apiId1, v.data.apiId2, function(apiId)
                    if not apiId then
                        return
                    end
                    local playerId = getPlayerSource(apiId)
                    Active_Units[apiId] = playerId
                end)
            end
        end)
        GetCalls()
    end)
   
    RegisterCommand("cc", function(source, args, rawCommand)
        TriggerClientEvent("chat:clear", source)
    end)
    
end