--- FSCIChoiceImporter handles importing choices made in a Forge Steel character
--- into the complex Codex choices
--- @class FSCIChoiceImporter
--- @field availableFeatures table The features available in the Codex
--- @field levelChoices table The calculated list of selected features formatted for the character
FSCIChoiceImporter = RegisterGameType("FSCIChoiceImporter")
FSCIChoiceImporter.__index = FSCIChoiceImporter

local sanitizedStringsMatch = FSCIUtils.SanitizedStringsMatch
local tableLookupFromName = FSCIUtils.TableLookupFromName
local writeDebug = FSCIUtils.writeDebug
local writeLog = FSCIUtils.writeLog
local STATUS = FSCIUtils.STATUS

--- Creates a new level choice importer and processes the selected features.
--- @param selectedFeatures table The selected features to import
--- @param availableFeatures table The list of available feature definitions
--- @return FSCIChoiceImporter|nil instance The new importer instance if valid
function FSCIChoiceImporter:new(availableFeatures)

    if availableFeatures then
        if type(availableFeatures) == "table" then
            if next(availableFeatures) then
                local instance = setmetatable({}, self)
                instance.availableFeatures = availableFeatures
                instance.levelChoices = {}
                return instance
            end
        end
    end

    writeLog("No features to process.", STATUS.INFO)
    writeDebug("FSCICHOICEIMPORTER:: NEW:: Nothing to process.")
    return nil
end

--- Processes a single selected feature to build our levelChoices structure
--- @param feature table The selected feature to import
--- @return table levelChoices The list of selected features, apped to available features
function FSCIChoiceImporter:ProcessFeature(feature)
    local featureType = string.lower(feature.type)
    if featureType == "choice" then
        self:_processFeatureChoice(feature)
    elseif featureType == "language choice" then
        writeDebug("PROCESSFEATURES:: LANGUAGE::")
        self:_processLanguageChoice(feature)
    elseif featureType == "perk" then
        writeDebug("PROCESSFEATURES:: PERK::")
        self:_processPerkChoice(feature)
    elseif featureType == "skill choice" then
        writeDebug("PROCESSFEATURES:: SKILL::")
        self:_processSkillChoice(feature)
    elseif featureType == "multiple features" then
        if feature.data and feature.data.features then
            writeDebug("PROCESSFEATURES:: RECURSE::")
            self:Process(feature.data.features)
        end
    end
    return self.levelChoices
end

--- Processes all selected features to build our levelChoices structure
--- @param selectedFeatures table The selected features to import
--- @return table levelChoices The list of selected features, mapped to available features
function FSCIChoiceImporter:Process(selectedFeatures)
    writeDebug("FSCICHOICEIMPORTER:: PROCESS:: START::")

    for _, selectedFeature in pairs(selectedFeatures) do
        self:ProcessFeature(selectedFeature)
    end

    writeDebug("FSCICHOICEIMPORTER:: PROCESS:: COMPLETE:: %s", json(self.levelChoices))
    return self.levelChoices
end

--- Adds a selection to the level choices table, handling replacement or appending to arrays
--- @param featureGuid string The GUID of the feature being selected
--- @param selectedGuid string The GUID of the selected option
--- @param replaceCurrent boolean Optional. When true, replaces any existing value. When false (default), appends to a table
--- @private
function FSCIChoiceImporter:_addLevelChoice(featureGuid, selectedGuid, replaceCurrent)
    replaceCurrent = replaceCurrent or false

    if replaceCurrent then
        self.levelChoices[featureGuid] = selectedGuid
    else
        if self.levelChoices[featureGuid] == nil then
            self.levelChoices[featureGuid] = { selectedGuid }
        else
            if type(self.levelChoices[featureGuid]) ~= "table" then
                local existingValue = self.levelChoices[featureGuid]
                self.levelChoices[featureGuid] = { existingValue, selectedGuid }
            else
                table.insert(self.levelChoices[featureGuid], selectedGuid)
            end
        end
    end
end

--- Processes a feature choice from the selected features, matching choices to available options
--- @param selectedFeature table The selected feature containing choice data
--- @private
function FSCIChoiceImporter:_processFeatureChoice(selectedFeature)
    writeDebug("PROCESSFEATURES:: FEATURE:: START:: %s", json(selectedFeature))

    for _, choice in ipairs(selectedFeature.data.selected) do
        local choiceName = FSCIUtils.TranslateFeatureChoiceToCodex(choice.name, choice.description)
        writeDebug(string.format("PROCESSRACEFEATURES:: FEATURE:: [%s]->[%s]", choice.name, choiceName))
        writeLog(string.format("Found Feature [%s] in import.", choiceName))

        local matchedFeature = self:_findMatchingFeature("CharacterFeatureChoice", self.availableFeatures)
        if matchedFeature then
            for _, option in pairs(matchedFeature.options) do
                if sanitizedStringsMatch(choiceName, option.name) then
                    writeLog(string.format("Adding Feature [%s].", choiceName), STATUS.IMPL)
                    self:_addLevelChoice(matchedFeature.guid, option.guid)
                    break
                end
            end
        else
            writeLog("!!!! Matching Feature not found!", STATUS.WARN)
        end
    end

    writeDebug("PROCESSFEATURES:: FEATURE:: COMPLETE::")
end

--- Processes a language choice from the selected features, looking up languages in the Codex
--- @param selectedFeature table The selected feature containing skill choice data
--- @private
function FSCIChoiceImporter:_processLanguageChoice(selectedFeature)
    writeDebug("PROCESSFEATURES:: LANGUAGE:: START:: %s", json(selectedFeature))

    for _, languageName in pairs(selectedFeature.data.selected) do
        writeLog(string.format("Found Language [%s] in import.", languageName))
        local languageId = tableLookupFromName(Language.tableName, languageName)
        if languageId then
            writeLog("Found match in Codex.")
            local matchedFeature = self:_findMatchingFeature("CharacterLanguageChoice", self.availableFeatures)
            if matchedFeature then
                writeLog(string.format("Adding Language [%s].", languageName), STATUS.IMPL)
                self:_addLevelChoice(matchedFeature.guid, languageId)
            else
                writeLog("!!!! Matching feature not found!", STATUS.WARN)
            end
        else
            writeLog(string.format("!!!! Language [%s] not found in Codex.", languageName), STATUS.WARN)
        end
    end

    writeDebug("PROCESSFEATURES:: LANGUAGE:: COMPLETE::")
end

--- Processes a perk choice from the selected features, looking up perks in the Codex
--- @param selectedFeature table The selected feature containing skill choice data
--- @private
function FSCIChoiceImporter:_processPerkChoice(selectedFeature)
    writeDebug("PROCESSFEATURES:: PERK:: START:: %s", json(selectedFeature))

    for _, perk in pairs(selectedFeature.data.selected) do
        writeLog(string.format("Found Perk [%s] in import.", perk.name))
        local perkId = tableLookupFromName(CharacterFeat.tableName, perk.name)
        if perkId then
            writeLog("Found match in Codex.")
            local matchedFeature = self:_findMatchingFeature("CharacterFeatChoice", self.availableFeatures)
            if matchedFeature then
                writeLog(string.format("Adding Perk [%s].", perk.name), STATUS.IMPL)
                self:_addLevelChoice(matchedFeature.guid, perkId)
            else
                writeLog("!!!! Matching feature not found!", STATUS.WARN)
            end
        else
            writeLog(string.format("!!!! Perk [%s] not found in Codex!", perk.name), STATUS.WARN)
        end
    end

    writeDebug("PROCESSFEATURES:: PERK:: COMPLETE::")
end

--- Processes a skill choice from the selected features, looking up skills in the Codex
--- @param selectedFeature table The selected feature containing skill choice data
--- @private
function FSCIChoiceImporter:_processSkillChoice(selectedFeature)
    writeDebug("PROCESSFEATURES:: SKILL:: START:: %s", json(selectedFeature))

    for _, skillName in pairs(selectedFeature.data.selected) do
        writeLog(string.format("Found Skill [%s] in import.", skillName))
        local skillId = tableLookupFromName(Skill.tableName, skillName)
        if skillId then
            writeLog("Found match in Codex.")
            local matchedFeature = self:_findMatchingFeature("CharacterSkillChoice", self.availableFeatures)
            if matchedFeature then
                writeLog(string.format("Adding Skill [%s].", skillName), STATUS.IMPL)
                self:_addLevelChoice(matchedFeature.guid, skillId)
            else
                writeLog("!!!! Matching feature not found!", STATUS.WARN)
            end
        else
            writeLog(string.format("!!!! Skill [%s] not found in Codex.", skillName), STATUS.WARN)
        end
    end

    writeDebug("PROCESSFEATURES:: SKILL:: COMPLETE::")
end

--- Recursively searches available features to find a feature matching the specified choice type
--- @param choiceType string The type of choice to find (e.g., "CharacterSkillChoice")
--- @param availableFeatures table The list of available features to search
--- @return table|nil matchedFeature The matching feature if found, nil otherwise
--- @private
function FSCIChoiceImporter:_findMatchingFeature(choiceType, availableFeatures)
    writeDebug("FINDMATCHINGFEATURE:: START:: %s %s", choiceType, json(availableFeatures))

    local matchedFeature = nil

    for _, availableFeature in pairs(availableFeatures) do
        if sanitizedStringsMatch(choiceType, availableFeature.typeName) then
            matchedFeature = availableFeature
        else
            local nestedFeatures = availableFeature:try_get("features")
            if nestedFeatures then
                matchedFeature = self:_findMatchingFeature(choiceType, nestedFeatures)
            end
        end
        if matchedFeature then break end
    end

    writeDebug("FINDMATCHINGFEATURE:: COMPLETE:: %s", json(matchedFeature))
    return matchedFeature
end