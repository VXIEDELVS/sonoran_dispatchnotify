--[[
    Sonaran CAD Plugins

    Plugin Name: dispatchnotify
    Creator: SonoranCAD
    Description: Show incoming 911 calls and allow units to attach to them.

    Put all client-side logic in this file.
]]

local pluginConfig = Config.GetPluginConfig("dispatchnotify")

if pluginConfig.enabled then

    local gpsLock = true
    local lastGps = nil

    CreateThread(function()
        while not NetworkIsPlayerActive(PlayerId()) do
            Wait(10)
        end
        TriggerServerEvent("SonoranCAD::dispatchnotify:Joined")
    end)

    RegisterNetEvent("SonoranCAD::dispatchnotify:SetGps")
    AddEventHandler("SonoranCAD::dispatchnotify:SetGps", function(postal, isUpdate)
        -- try to set postal via command?
        if gpsLock then
            ExecuteCommand("postal "..tostring(postal))
            if isUpdate then
                TriggerEvent("chat:addMessage", {args = {"^0[ ^2Dispatch ^0] ", ("Call GPS coordinates updated (%s)."):format(postal)}})
            else
                TriggerEvent("chat:addMessage", {args = {"^0[ ^2Dispatch ^0] ", ("GPS coordinates set to caller's last known postal (%s)."):format(postal)}})
            end
        end
    end)

    RegisterNetEvent("SonoranCAD::dispatchnotify:GetCoordinates")
    AddEventHandler("SonoranCAD::dispatchnotify:GetCoordinates", function()
        local coords = GetEntityCoords(GetPlayerPed(-1))
        TriggerServerEvent("SonoranCAD::dispatchnotify:RecvCoordinates", coords)
    end)

    RegisterNetEvent("SonoranCAD::dispatchnotify:GetPostal")
    AddEventHandler("SonoranCAD::dispatchnotify:GetPostal", function()
        local postal = getNearestPostal()
        TriggerServerEvent("SonoranCAD::dispatchnotify:RecvPostal", postal)
    end)

    RegisterNetEvent("SonoranCAD::dispatchnotify:SetLocation")
    AddEventHandler("SonoranCAD::dispatchnotify:SetLocation", function(coords)
        if gpsLock then
            SetNewWaypoint(coords.x, coords.y)
            TriggerEvent("chat:addMessage", {args = {"^0[ ^2Dispatch ^0] ", "GPS coordinates set to caller's last known location."}})
        end
    end)

    RegisterCommand("togglegps", function(source, args, rawCommand)
        gpsLock = not gpsLock
        TriggerEvent("chat:addMessage", {args = {"^0[ ^2GPS ^0] ", ("GPS lock has been %s"):format(gpsLock and "enabled" or "disabled")}})
    end)

end