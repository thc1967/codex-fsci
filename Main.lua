--[[ 
Module: Forge Steel Character Importer
Author: thc1967
Contact: @thc1967 (Dicord)

Description:
  Imports characters from Forge Steel into Codex.

Usage:
  In Codex, Codex -> Import Assets -> Forge Steel Character
  
Dependencies:
  Basic Chat Message module
--]]

--- Chat command to toggle debug and verbose logging modes
--- Usage: /fsci [d] [v] - toggles debug mode with 'd', verbose mode with 'v'
--- Displays current state of both modes in chat
--- @param args string Command arguments ('d' for debug, 'v' for verbose)
Commands.fsci = function(args)
    if args and #args then
        if string.find(args:lower(), "d") then FSCIUtils.ToggleDebugMode() end
        if string.find(args:lower(), "v") then FSCIUtils.ToggleVerboseMode() end
    end
    SendTitledChatMessage(string.format("<color=#00cccc>[d]ebug:</color> %s <color=#00cccc>[v]erbose:</color> %s", FSCIUtils.inDebugMode(), FSCIUtils.inVerboseMode()), "fsci", "#e09c9c")
end

--- Registers the Forge Steel JSON importer with Codex's import system
--- Parses JSON text and creates a new character in the VTT
import.Register {
    id = "thcfscijson",
    description = "Forge Steel Character (JSON)",
    input = "plaintext",
    priority = 200,

    text = function(importer, text)
        local importer = FSCIImporter:new(text)
        if importer then
            importer:Import()
        else
            FSCIUtils.writeLog("!!!! Could not create Forge Steel importer!", FSCIUtils.STATUS.ERROR)
        end
    end
}