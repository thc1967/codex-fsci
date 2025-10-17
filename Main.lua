--[[ 
Module: Forge Steel Character Importer
Author: thc1967
Contact: @thc1967 (Dicord)

Description:
  Imports characters from Forge Steel into Codex.

Usage:
  In Codex, Tools -> Import Assets -> Forge Steel Character
  
Dependencies:
  Basic Chat Message module
--]]

Commands.fsci = function(args)
    if args and #args then
        if string.find(args:lower(), "d") then FSCIUtils.ToggleDebugMode() end
        if string.find(args:lower(), "v") then FSCIUtils.ToggleVerboseMode() end
    end
    SendTitledChatMessage(string.format("<color=#00cccc>[d]ebug:</color> %s <color=#00cccc>[v]erbose:</color> %s", FSCIUtils.GetDebugMode(), FSCIUtils.GetVerboseMode()), "fsci", "#e09c9c")
end

local function debugWriteToFile(dto)
    if CTIEUtils.inDebugMode() then
        local jsonString = dto:ToJSON()
        local writePath = "characters/" .. dmhub.gameid
        local exportFilename = string.format("%s.json", dto:GetCharacterName())
        dmhub.WriteTextFile(writePath, exportFilename, jsonString)
    end
end

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
            CTIEUtils.writeLog("!!!! Could not create Forge Steel importer!", CTIEUtils.STATUS.ERROR)
        end
    end
}