--[[
    Sonaran CAD Plugins

    Plugin Name: dispatchnotify
    Creator: SonoranCAD
    Description: Show incoming 911 calls and allow units to attach to them.

    Put all server-side logic in this file.
]]

local pluginConfig = Config.GetPluginConfig("dispatchnotify")

if pluginConfig.enabled then

    local DISPATCH_TYPE = {"CALL_NEW", "CALL_EDIT", "CALL_CLOSE", "CALL_NOTE", "CALL_SELF_CLEAR"}
    local ORIGIN = {"CALLER", "RADIO_DISPATCH", "OBSERVED", "WALK_UP"}
    local STATUS = {"PENDING", "ACTIVE", "CLOSED"}

    local CallerMapping = {} -- player, apiId
    local CallMapping = {} -- [911CallId], false/callId

    local LocationCache = {} -- [playerId], coords
    local PlayerCache = {} -- [playerId], identifiers

    local IncomingCallCache = {}
    local CommandCallMapping = {}
    local CallCache = {}

    local UnitCache = {}
    local PostalCache = {}

    local function SendMessage(type, source, message)
        if type == "dispatch" then
            TriggerClientEvent("chat:addMessage", source, {args = {"^0[ ^2Dispatch ^0] ", message}})
        elseif type == pluginConfig.emergencyCallType then
            TriggerClientEvent("chat:addMessage", source, {args = {"^0[ ^1"..type.." ^0] ", message}})
        elseif type == pluginConfig.civilCallType then
            TriggerClientEvent("chat:addMessage", source, {args = {"^0[ ^1"..type.." ^0] ", message}})
        elseif type == pluginConfig.dotCallType then
            TriggerClientEvent("chat:addMessage", source, {args = {"^0[ ^1"..type.." ^0] ", message}})
        elseif type == "error" then
            TriggerClientEvent("chat:addMessage", source, {args = {"^0[ ^1Error ^0] ", message}})
        elseif type == "debug" and Config.debugMode then
            TriggerClientEvent("chat:addMessage", source, {args = {"[ Debug ] ", message}})
        end
    end

    -- player functions
    local function GetPlayerByIdentifier(identifier)
        for k, v in pairs(PlayerCache) do
            for _, id in pairs(v) do
                if id == identifier then
                    return k
                end
            end
        end
        return nil
    end

    local function IsPlayerOnDuty(player)
        if pluginConfig.unitDutyMethod == "incad" then
            if UnitCache[player] ~= nil then
                return true
            else
                return false
            end
        elseif pluginConfig.unitDutyMethod == "permissions" then
            return IsPlayerAceAllowed(player, "sonorancad.dispatchnotify")
        elseif pluginConfig.unitDutyMethod == "esx" and Config.serverType == "esx" then
            assert(false, "ESX mode currently not supported.")
        elseif pluginConfig.unitDutyMethod == "custom" then
            return unitDutyCustom(player)
        end
    end

    local function FindCallMatch(caller, location, description)
        for k, v in pairs(CommandCallMapping) do
            if caller == "incad" then
                local l = 1
                local desc = description
                for line in description:gmatch("([^\n]*)\n?") do
                    if l == 3 then
                        desc = line
                        break
                    else
                        l = l + 1
                    end
                end
                if v.location == location and v.description == desc then
                    return k
                else
                    return nil
                end
            end
            if v.caller == caller and v.location == location and v.description == description then
                return k
            elseif v.caller == caller and (v.location ~= location or v.description ~= description) then
                debugLog(("Ignoring partial match... (caller %s, %s != %s or %s != %s)"):format(v.caller, v.location, location, v.description, description))
            end
        end
        return nil
    end

    local function GetCallerMapping(callId)
        for k, v in pairs(CallerMapping) do
            if tostring(v.iCallId) == tostring(callId) then
                return k
            end
        end
        return nil
    end

    local function GetUnitById(units, unitId)
        for k, v in pairs(units) do
            if v.id == unitId then
                return k
            end
        end
        return nil
    end

    AddEventHandler("SonoranCAD::dispatchnotify:SetDispatchCommandEnabled", function(isEnabled)
        pluginConfig.enableUnitResponse = isEnabled
        debugLog("EnabledUnitResponse toggled "..tostring(isEnabled))
    end)

    RegisterNetEvent("SonoranCAD::dispatchnotify:Joined")
    AddEventHandler("SonoranCAD::dispatchnotify:Joined", function()
        local identifiers = GetIdentifiers(source)
        PlayerCache[source] = identifiers
    end)

    AddEventHandler("playerDropped", function(reason)
        PlayerCache[source] = nil
    end)

    -- Updating location cache (coordinates)
    if pluginConfig.waypointType == "exact" then
        CreateThread(function()
            while true do
                TriggerClientEvent("SonoranCAD::dispatchnotify:GetCoordinates", -1)
                Wait(1000*pluginConfig.locationFrequency)
            end
        end)
    elseif pluginConfig.waypointType == "postal" then
        CreateThread(function()
            while true do
                TriggerClientEvent("SonoranCAD::dispatchnotify:GetPostal", -1)
                Wait(1000*pluginConfig.locationFrequency)
            end
        end)
    end
    RegisterNetEvent("SonoranCAD::dispatchnotify:RecvCoordinates")
    AddEventHandler("SonoranCAD::dispatchnotify:RecvCoordinates", function(coords)
        LocationCache[tostring(source)] = coords
    end)
    RegisterNetEvent("SonoranCAD::dispatchnotify:RecvPostal") 
    AddEventHandler("SonoranCAD::dispatchnotify:RecvPostal", function(postal)
        PostalCache[tostring(source)] = postal
        debugLog(("Saved postal %s from %s, new table %s"):format(postal, source, json.encode(PostalCache)))
    end)

    -- Unit Online/Offline
    RegisterServerEvent('SonoranCAD::pushevents:UnitListUpdate')
    AddEventHandler('SonoranCAD::pushevents:UnitListUpdate', function(unit)
        local playerId = GetPlayerByIdentifier(unit.data.apiId1)
        if playerId == nil and unit.data.apiId2 ~= "" then
            playerId = GetPlayerByIdentifier(unit.data.apiId2)
        end
        if playerId == nil then
            for k, v in pairs(UnitCache) do
                if v.data.apiId1 == unit.data.apiId1 or v.data.apiId2 == unit.data.apiId2 then
                    UnitCache[k] = nil
                end
            end
            return
        end
        if unit.type == "EVENT_UNIT_LOGIN" then
            UnitCache[playerId] = unit
        elseif unit.type == "EVENT_UNIT_LOGOUT" then
            UnitCache[playerId] = nil
        end
    end)

    --EVENT_911 emit('SonoranCAD::pushevents:IncomingCadCall', body.data.call, body.data.apiIds);
    RegisterServerEvent("SonoranCAD::pushevents:IncomingCadCall")
    AddEventHandler("SonoranCAD::pushevents:IncomingCadCall", function(call, apiIds)
        -- incoming call, gather available data
        IncomingCallCache[call.callId] = call
        local callerId = nil
        -- if from in CAD, map the call
        if apiIds ~= nil then
            if apiIds[1] ~= nil then
                local player = GetPlayerByIdentifier(apiIds[1])
                if player ~= nil then
                    table.insert(CallerMapping, {playerId = player, apiId = apiIds[1], iCallId = call.callId, callId = nil})
                    callerId = player
                end
            end
        else
            -- out of cad, check if we have a match from a command plugin
            local match = FindCallMatch(call.caller, call.location, call.description)
            if match ~= nil then
                callerId = CommandCallMapping[match].player
                local callerApiId = GetIdentifiers(callerId)[Config.primaryIdentifier]
                table.insert(CallerMapping, {playerId = player, apiId = callerApiId, iCallId = call.callId, callId = nil})
                debugLog(("Found matching incoming call from %s. Mapped to %s."):format(callerId, call.callId))
                CommandCallMapping[match].iCallId = call.callId
            else
                debugLog(("Could not locate caller source for call ID %s from %s."):format(call.callId, call.caller))
            end
        end

        CallMapping[call.callId] = false
        
        if pluginConfig.enableUnitNotify then
            local type = call.emergency and pluginConfig.civilCallType or pluginConfig.emergencyCallType
            local message = pluginConfig.incomingCallMessage:gsub("{caller}", call.caller):gsub("{location}", call.location):gsub("{description}", call.description):gsub("{callId}", call.callId):gsub("{command}", pluginConfig.respondCommandName)
        
            for k, v in pairs(PlayerCache) do
                if IsPlayerOnDuty(k) then
                    if pluginConfig.unitNotifyMethod == "chat" then
                        SendMessage(type, k, message)
                    elseif pluginConfig.unitNotifyMethod == "pnotify" then
                        TriggerClientEvent("pNotify:SendNotification", k, {
                            text = message,
                            type = "error",
                            layout = "bottomcenter",
                            timeout = "10000"
                        })
                    end
                end
            end
        end

    end)

    --Officer response
    registerApiType("NEW_DISPATCH", "emergency")
    registerApiType("ATTACH_UNIT", "emergency")
    RegisterCommand(pluginConfig.respondCommandName, function(source, args, rawCommand)
        local source = source
        if not pluginConfig.enableUnitResponse then
            SendMessage("error", source, "Self dispatching is disabled.")
            return
        end
        if not IsPlayerOnDuty(source) then
            SendMessage("error", source, "You must be on duty to use this command.")
            return
        end
        if args[1] == nil then
            SendMessage("error", source, "Call ID must be specified.")
            return
        end
        if IncomingCallCache[tonumber(args[1])] == nil then
            SendMessage("error", source, "Call ID was not found!")
            return
        end
        local call = IncomingCallCache[tonumber(args[1])]
        local callerInfo = CallerMapping[GetCallerMapping(call.callId)]
        local identifiers = GetIdentifiers(source)[Config.primaryIdentifier]
        local callerIdentifiers = nil
        
        if callerInfo.playerId == nil then
            callerIdentifiers = GetPlayerByIdentifier(callerInfo.apiId)
            callerInfo.playerId = callerIdentifiers
        else
            callerIdentifiers = GetIdentifiers(callerInfo.playerId)[Config.primaryIdentifier]
        end
        -- Responding to the call
        local currentCall = CallMapping[call.callId] 
        if currentCall == false then
            -- no mapped call, create a new one
            debugLog("Creating new call request...")
            local postal = ""
            if isPluginLoaded("postals") and callerInfo.playerId ~= nil then
                if PostalCache[tostring(callerInfo.playerId)] ~= nil then
                    postal = PostalCache[tostring(callerInfo.playerId)]
                else
                    debugLog("Failed to obtain postal.")
                end
            end
            local payload = {   serverId = Config.serverId,
                                origin = 0, 
                                status = 1, 
                                priority = 2,
                                block = "",
                                code = "",
                                postal = postal,
                                address = call.location, 
                                title = "OFFICER RESPONSE - "..call.callId, 
                                description = call.description, 
                                isEmergency = call.isEmergency,
                                notes = "Officer responding",
                                metaData = { callerApiId = callerIdentifiers, creatorApiId = identifiers, createdFromId = call.callId },
                                units = { identifiers }
            }
            performApiRequest({payload}, "NEW_DISPATCH", function(resp)
                debugLog("Call creation OK")
                SendMessage("debug", source, "You have been attached to the call.")
            end)
        else
            -- Call already exists
            debugLog("Found Call. Attaching!")
            local data = {callId = currentCall.callId, units = {identifiers}}
            performApiRequest({data}, "ATTACH_UNIT", function(res)
                debugLog("Attach OK: "..tostring(res))
                SendMessage("debug", source, "You have been attached to the call.")
            end)
        end
    end)

    --TriggerEvent("SonoranCAD::callcommands:cadIncomingCall", emergency, caller, location, description, source)
    AddEventHandler("SonoranCAD::callcommands:cadIncomingCall", function(emergency, caller, location, description, source)
        -- handle incoming calls from a command, these get handled by EVENT_911
        table.insert(CommandCallMapping, {caller = caller, location = location, description = description, player = source})
        debugLog(("New call detected, inserting %s"):format(json.encode({caller = caller, location = location, description = description, player = source})))
    end)

    local function attachUnitToCall(dispatchData, unit)
        local officerName = unit.data.name
        local playerId = nil
        if dispatchData.metaData ~= nil then 
            playerId = dispatchData.metaData.callerApiId
        else
            local match = FindCallMatch("incad", dispatchData.address, dispatchData.description)
            if match ~= nil then
                playerId = CommandCallMapping[match].player
            end
        end
        local officerApiId = unit.data.apiId1
        local officerId = GetPlayerByIdentifier(unit.data.apiId1)
        if officerId ~= nil  then
            SendMessage("dispatch", officerId, ("You are now attached to call ^4%s^0. Description: ^4%s^0"):format(dispatchData.callId, dispatchData.description))
        end
        if pluginConfig.enableCallerNotify and playerId ~= nil then
            if pluginConfig.callerNotifyMethod == "chat" then
                SendMessage("dispatch", playerId, pluginConfig.notifyMessage:gsub("{officer}", officerName))
            elseif pluginConfig.callerNotifyMethod == "pnotify" then
                TriggerClientEvent("pNotify:SendNotification", playerId, {
                    text = pluginConfig.notifyMessage:gsub("{officer}", officerName),
                    type = "error",
                    layout = "bottomcenter",
                    timeout = "10000"
                })
            elseif pluginConfig.callerNotifyMethod == "custom" then
                TriggerEvent("SonoranCAD::dispatchnotify:UnitAttach", dispatchData.callId, playerId, officerId, officerName)
            end
        else
            debugLog("Could not find player ID.")
        end

        if pluginConfig.waypointType == "postal" then
            if dispatchData.postal ~= nil and dispatchData.postal ~= "" then
                TriggerClientEvent("SonoranCAD::dispatchnotify:SetGps", officerId, dispatchData.postal)
            end
        elseif pluginConfig.waypointType == "exact" then
            if LocationCache[callerId] ~= nil and playerId ~= nil then
                TriggerClientEvent("SonoranCAD::dispatchnotify:SetLocation", officerId, LocationCache[playerId])
            elseif pluginConfig.waypointType == "exact" and pluginConfig.waypointFallbackEnabled then
                if dispatchData.postal ~= nil and dispatchData.postal ~= "" then
                    TriggerClientEvent("SonoranCAD::dispatchnotify:SetGps", officerId, dispatchData.postal)
                end
            end
        end
    end

    RegisterServerEvent("SonoranCAD::pushevents:DispatchEvent")
    AddEventHandler("SonoranCAD::pushevents:DispatchEvent", function(data)
        local dispatchType = data.dispatch_type
        local dispatchData = data.dispatch
        local metaData = data.dispatch.metaData
        if metaData == nil then
            local match = FindCallMatch("incad", dispatchData.address, dispatchData.description)
            if match then
                metaData = {}
                metaData["createdFromId"] = CommandCallMapping[match].player
                debugLog(("Automapping callId %s to match %s"):format(dispatchData.callId, match))
            else
                metaData = {}
            end
        end
        if dispatchType ~= tostring(dispatchType) then
            -- hmm, expected a string, got a number
            dispatchType = DISPATCH_TYPE[data.dispatch_type+1]
        end
        local switch = {
            ["CALL_NEW"] = function()
                debugLog("CALL_NEW fired")
                if CallCache[dispatchData.callId] == nil then
                    CallCache[dispatchData.callId] = dispatchData
                end
                if metaData.createdFromId ~= nil then
                    if CallMapping[metaData.createdFromId] == false then
                        CallMapping[metaData.createdFromId] = dispatchData.callId
                        debugLog(("Found matching 911 call %s, associating %s with it."):format(metaData.createdFromId, dispatchData.callId))
                    end
                else
                    warnLog(("Failed to process incoming call %s, was it processed by the integration? (missing createdFromId)"):format(dispatchData.callId))
                    return
                end
                -- find the caller player
                local mapId = GetCallerMapping(metaData.createdFromId)
                if mapId == nil then
                    -- alternate method, call didn't come from the integration
                    local match = FindCallMatch("incad", dispatchData.address, dispatchData.description)
                    if match ~= nil then
                        mapId = GetCallerMapping(CommandCallMapping[match].iCallId)
                    else
                        assert(false, "Failed to process call as we could not find the caller. Ignored.")
                    end
                end
                local callerId = CallerMapping[mapId].playerId
                CallerMapping[mapId].callId = dispatchData.callId
                -- for every unit we find, alert both caller and unit, if configured
                for k, v in pairs(dispatchData.units) do
                    attachUnitToCall(dispatchData, v)
                end
                debugLog("Finished processing CALL_NEW")
            end,
            ["CALL_EDIT"] = function() 
                -- calls may be edited for a number of reason, fire various events depending on what changed
                if CallCache[dispatchData.callId] == nil then
                    debugLog("CALL_EDIT fired, but we had no cached data. Capture it.")
                    CallCache[dispatchData.callId] = dispatchData
                    return
                end
                local cache = CallCache[dispatchData.callId]
                if cache.postal ~= dispatchData.postal then
                    TriggerEvent("SonoranCAD::dispatchnotify:CallEdit:Postal", dispatchData.callId, dispatchData.postal)
                end
                if cache.address ~= dispatchData.address then
                    TriggerEvent("SonoranCAD::dispatchnotify:CallEdit:Address", dispatchData.callId, dispatchData.address)
                end
                if cache.units == nil and dispatchData.units ~= nil then
                    for k, v in pairs(dispatchData.units) do
                        TriggerEvent("SonoranCAD::dispatchnotify:CallEdit:NewUnit", dispatchData.callId, dispatchData, v)
                    end
                elseif cache.units ~= nil and dispatchData.units == nil then
                    for k, v in pairs(cache.units) do
                        TriggerEvent("SonoranCAD::dispatchnotify:CallEdit:RemoveUnit", dispatchData.callId, v)
                    end
                elseif #cache.units ~= #dispatchData.units then
                    for k, v in pairs(dispatchData.units) do
                        local unit = GetUnitById(cache.units, v.id)
                        if unit == nil then
                            TriggerEvent("SonoranCAD::dispatchnotify:CallEdit:NewUnit", dispatchData.callId, dispatchData, v)
                        end
                    end
                end
                CallCache[dispatchData.callId] = dispatchData
            end,
            ["CALL_CLOSE"] = function() 
                if CallCache[dispatchData.callId] == nil then
                    debugLog("CALL_CLOSE fired, but we had no cached data.")
                    return
                end
                local cache = CallCache[dispatchData.callId]
                if cache.units ~= nil then
                    for k, v in pairs(cache.units) do
                        local officerId = GetPlayerByIdentifier(v.data.apiId1)
                        if officerId ~= nil then
                            TriggerClientEvent("SonoranCAD::dispatchnotify:CallClosed", officerId, cache.callId)
                        end
                    end
                end
                CallCache[dispatchData.callId] = nil
                for callMapId, v in pairs(CallMapping) do
                    if v == dispatchData.callId then
                        CallMapping[callMapId] = nil
                    end
                end
            end,
            ["CALL_NOTE"] = function() 
                TriggerEvent("SonoranCAD::dispatchnotify:CallNote", dispatchData.callId, dispatchData.notes)
            end,
            ["CALL_SELF_CLEAR"] = function() 
                TriggerEvent("SonoranCAD::dispatchnotify:CallSelfClear", dispatchData.units)
            end
        }
        if switch[dispatchType] then
            switch[dispatchType]()
        else
            print("no")
        end
    end)

    -- Location Handling
    AddEventHandler("SonoranCAD::dispatchnotify:StartWaypoint", function(callId, callerId, officerId)
        local call = CallCache[callId]
        infoLog(("Waypoint call ID %s - caller %s - officer %s"):format(callId, callerId, officerId))
        if pluginConfig.waypointType == "postal" then
            if call.postal ~= nil and call.postal ~= "" then
                TriggerClientEvent("SonoranCAD::dispatchnotify:SetGps", officerId, call.postal)
            end
        elseif pluginConfig.waypointType == "exact" then
            if LocationCache[callerId] ~= nil then
                TriggerClientEvent("SonoranCAD::dispatchnotify:SetLocation", officerId, LocationCache[callerId])
            end
        end
    end)
    AddEventHandler("SonoranCAD::dispatchnotify:CallEdit:Postal", function(callId, postal)
        local call = CallCache[callId]
        assert(call ~= nil, "Call not found, failed to process.")
        if call.units == nil then
            return
        end
        for k, unit in pairs(call.units) do
            local officerId = GetPlayerByIdentifier(unit.data.apiId1)
            if officerId ~= nil then
                TriggerClientEvent("SonoranCAD::dispatchnotify:SetGps", officerId, postal, true)
            end
        end
    end)
    AddEventHandler("SonoranCAD::dispatchnotify:CallEdit:NewUnit", function(callId, dispatchData, unit)
        attachUnitToCall(dispatchData, unit)
    end)
    AddEventHandler("SonoranCAD::dispatchnotify:CallEdit:RemoveUnit", function(callId, unit)
    
    end)
    
end