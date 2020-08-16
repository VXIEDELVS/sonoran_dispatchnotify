--[[
    Sonoran Plugins

    Plugin Configuration

    Put all needed configuration in this file.

]]
local config = {
    enabled = false,
    configVersion = "1.0",
    pluginName = "dispatchnotify", -- name your plugin here
    pluginAuthor = "SonoranCAD", -- author
    requiresPlugins = {"callcommands", "postals", "pushevents"}, -- required plugins for this plugin to work, separated by commas
    --[[
        notifyMethod: how should the caller be notified?
            none: disable notification
            chat: Sends a message in chat
            pnotify: Uses pNotify to show a notification
            custom: Use the custom event instead (see docs)
    ]]
    notifyMethod = "pnotify",
    --[[
        notifyMessage: Message template to use when sending to the player

        You can use the following replacements:
            {officer} - officer name
            {postal} - postal of call
            {caller} - caller name
    ]]
    notifyMessage = "An officer is responding to your call!",

    -- when true, waypointing to the caller is enabled
    waypointEnabled = true,

    --[[
        waypointType: Type of waypoint to use when officer is attached
            postal: set gps to caller's postal (less accurate, more realistic)
            exact: set gps to caller's position (less realistic)
    ]]
    waypointType = "postal"

}

if config.enabled then
    Config.RegisterPluginConfig(config.pluginName, config)
end