--[[
    Sonaran CAD Plugins

    Plugin Name: dispatchnotify
    Creator: template
    Description: Describe your plugin here

    Put all client-side logic in this file.
]]

local pluginConfig = Config.GetPluginConfig("dispatchnotify")

if pluginConfig.enabled then

    local currentCall = nil
    local lastCallDescription = nil

    RegisterNetEvent("SonoranCAD::dispatchnotify:NewCall")
    AddEventHandler("SonoranCAD::dispatchnotify:NewCall", function(data)
        currentCall = data
        if #data.dispatch.units > 0 then
            local officer = data.dispatch.units[1].data.name
            TriggerEvent("chat:addMessage", {args = {"^0^5^*[SonoranCAD]^r ", ("^7%s is responding to your call!"):format(officer)}})
        end
    end)

    RegisterNetEvent("SonoranCAD::dispatchnotify:UpdateCall")
    AddEventHandler("SonoranCAD::dispatchnotify:UpdateCall", function(call, unit)
        if currentCall ~= nil then
            debugLog(json.encode(unit))
            local officer = unit.data.name
            for k, unit in pairs(call.units) do
                for k, v in pairs(currentCall.units) do
                    if v.data.name == officer then
                        return
                    end
                end
            end
        end
        currentCall = call
        TriggerEvent("chat:addMessage", {args = {"^0^5^*[SonoranCAD]^r ", ("^7%s is responding to your call!"):format(officer)}})
    end)

    RegisterNetEvent("SonoranCAD::dispatchnotify:CallResponse")
    AddEventHandler("SonoranCAD::dispatchnotify:CallResponse", function(unitName)
        TriggerEvent("chat:addMessage", {args = {"^0[ ^1911 ^0] ", pluginConfig.notifyMessage:gsub("{officer}", unitName)}})
    end)

    RegisterNetEvent("SonoranCAD::dispatchnotify:CallOk")
    AddEventHandler("SonoranCAD::dispatchnotify:CallOk", function(description)
        lastCallDescription = description
    end)

    CreateThread(function()
        while not NetworkIsPlayerActive(PlayerId()) do
            Wait(10)
        end
        TriggerServerEvent("SonoranCAD::dispatchnotify:UserJoined")
    end)

end