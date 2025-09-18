--- FSCILeveledChoiceImporter handles importing choices made in a Forge Steel character
--- into the complex Codex choices - when the available features are arrayed by level
--- @class FSCILeveledChoiceImporter
--- @field selectedFeatures table The feeatures selected in the FS character
--- @field availableFeatures table The features available in the Codex
--- @field levelChoices table The calculated list of selected features formatted for the character
FSCILeveledChoiceImporter = RegisterGameType("FSCILeveledChoiceImporter")
FSCILeveledChoiceImporter.__index = FSCILeveledChoiceImporter

local writeDebug = FSCIUtils.writeDebug
local writeLog = FSCIUtils.writeLog
local STATUS = FSCIUtils.STATUS

--- Creates a new level choice importer and processes the selected features.
--- @param selectedFeatures table The selected features to import
--- @param availableFeatures table The list of available feature definitions
--- @return FSCILeveledChoiceImporter|nil instance The new importer instance if valid
function FSCILeveledChoiceImporter:new(selectedFeatures, availableFeatures)

    if selectedFeatures and availableFeatures then
        if type(selectedFeatures) == "table" and type(availableFeatures) == "table" then
            if next(selectedFeatures) and next(availableFeatures) then
                local instance = setmetatable({}, self)
                instance.selectedFeatures = selectedFeatures
                instance.availableFeatures = availableFeatures
                instance.levelChoices = {}
                return instance
            end
        end
    end

    writeLog("No features to process.", STATUS.INFO)
    writeDebug("FSCILEVELEDCHOICEIMPORTER:: NEW:: Nothing to process.")
    return nil
end

--- Processes all selected features to build our levelChoices structure
--- @return table levelChoices The list of selected features, mapped to available features
function FSCILeveledChoiceImporter:Process()
    writeDebug("FSCILEVELEDCHOICEIMPORTER:: PROCESS:: START::")
    
    self:_processFeatures(self.selectedFeatures)
    writeDebug("FSCILEVELEDCHOICEIMPORTER:: PROCESS:: COMPLETE:: %s", json(self.levelChoices))
    return self.levelChoices
end

