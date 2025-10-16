--- FSCIChoiceImporter handles importing choices made in a Forge Steel character
--- into the complex Codex choices
--- @class FSCIChoiceImporter
--- @field availableFeatures table The features available in the Codex
--- @field levelChoices table The calculated list of selected features formatted for the character
--- @field featureData table The full feature objects keyed by GUID
--- @field filter table Optional filter for feature processing (e.g., { description = "War Domain" })
FSCIChoiceImporter = RegisterGameType("FSCIChoiceImporter")
FSCIChoiceImporter.__index = FSCIChoiceImporter

local sanitizedStringsMatch = FSCIUtils.SanitizedStringsMatch
local tableLookupFromName = FSCIUtils.TableLookupFromName
local writeDebug = FSCIUtils.writeDebug
local writeLog = FSCIUtils.writeLog
local STATUS = FSCIUtils.STATUS

--- Creates a new level choice importer and processes the selected features.
--- @param availableFeatures table The list of available feature definitions
--- @param filter? table Optional filter for feature processing (e.g., { description = "War Domain" })
--- @return FSCIChoiceImporter|nil instance The new importer instance if valid
function FSCIChoiceImporter:new(availableFeatures, filter)

    if availableFeatures then
        if type(availableFeatures) == "table" then
            if next(availableFeatures) then
                local instance = setmetatable({}, self)
                instance.availableFeatures = availableFeatures
                instance.levelChoices = {}
                instance.featureData = {}
                instance.filter = filter or {}
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
--- @return table featureData The full feature objects keyed by GUID
function FSCIChoiceImporter:ProcessFeature(feature)
    writeDebug("FSCICHOICEIMPORTER:: PROCESSFEATURE:: %s", json(feature))

    local featureType = string.lower(feature.type)

    if featureType == "ability" or featureType == "choice" then
        writeDebug("PROCESSFEATURES:: FEATURE::")
        self:_processFeatureChoice(feature)
    elseif featureType == "deity" then
        writeDebug("PROCESSFEATURES:: DEITY::")
        self:_processDeityChoice(feature)
    elseif featureType == "language choice" then
        writeDebug("PROCESSFEATURES:: LANGUAGE::")
        self:_processLanguageChoice(feature)
    elseif featureType == "perk" then
        writeDebug("PROCESSFEATURES:: PERK::")
        self:_processPerkChoice(feature)
    elseif featureType == "skill choice" then
        writeDebug("PROCESSFEATURES:: SKILL::")
        self:_processSkillChoice(feature)
    elseif featureType == "subclass" then
        writeDebug("PROCESSFEATURE:: SUBCLASS::")
        self:_processSubclassChoice(feature)
    elseif featureType == "domain feature" then
        writeDebug("PROCESSFEATURES:: DOMAINFEATURE:: %s", json(feature))
        if feature.data and feature.data.selected then
            writeDebug("PROCESSFEATURES:: RECURSE:: DOMAIN::")
            -- self:Process(feature.data.selected)
        end
    elseif featureType == "multiple features" then
        if feature.data and feature.data.features then
            writeDebug("PROCESSFEATURES:: RECURSE:: MULTIPLE::")
            self:Process(feature.data.features)
        end
    end

    return self.levelChoices, self.featureData
end

--- Updates the featureData table with new data
--- @param newFeatureData table The new feature data table to replace the current one
function FSCIChoiceImporter:UpdateFeatureData(newFeatureData)
    self.featureData = newFeatureData or {}
end

--- Sets the filter for feature processing
--- @param filter? table The filter to apply (e.g., { description = "War Domain" }), or nil to clear
function FSCIChoiceImporter:SetFilter(filter)
    self.filter = filter or {}
end

--- Processes all selected features to build our levelChoices structure
--- @param selectedFeatures table The selected features to import
--- @return table levelChoices The list of selected features, mapped to available features
--- @return table featureData The full feature objects keyed by GUID
function FSCIChoiceImporter:Process(selectedFeatures)
    writeDebug("FSCICHOICEIMPORTER:: PROCESS:: START::")

    for _, selectedFeature in pairs(selectedFeatures) do
        self:ProcessFeature(selectedFeature)
    end

    writeDebug("FSCICHOICEIMPORTER:: PROCESS:: COMPLETE:: %s", json(self.levelChoices))
    return self.levelChoices, self.featureData
end

--- Adds a selection to the level choices table, handling replacement or appending to arrays
--- @param featureGuid string The GUID of the feature being selected
--- @param selectedGuid string The GUID of the selected option
--- @param featureObject? table Optional. The full feature object to store
--- @param replaceCurrent? boolean Optional. When true, replaces any existing value. When false (default), appends to a table
--- @private
function FSCIChoiceImporter:_addLevelChoice(featureGuid, selectedGuid, featureObject, replaceCurrent)
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

    -- Store the full feature object if provided
    if featureObject then
        self.featureData[featureGuid] = featureObject
    end
end

--- Processes a feature choice from the selected features, matching choices to available options
--- @param selectedFeature table The selected feature containing choice data
--- @private
function FSCIChoiceImporter:_processFeatureChoice(selectedFeature)
    writeDebug("PROCESSFEATURES:: FEATURE:: START:: %s", json(selectedFeature))

    local choiceName

    local function onMatch(matchedFeature)
        local processed = false
        for _, option in pairs(matchedFeature.options) do
            writeDebug("PROCESSFEATURES:: FEATURE:: ?MATCH:: [%s] [%s]", choiceName, option.name)
            if sanitizedStringsMatch(choiceName, option.name) then
                writeDebug("PROCESSFEATURES:: FEATURE:: !!MATCH::")
                writeLog(string.format("Adding Feature [%s].", choiceName), STATUS.IMPL)
                self:_addLevelChoice(matchedFeature.guid, option.guid, matchedFeature)
                processed = true
                break
            end
        end
        return processed
    end

    for _, choice in ipairs(selectedFeature.data.selected or {}) do
        choiceName = FSCIUtils.TranslateFeatureChoiceToCodex(choice.name, choice.description)
        writeDebug("PROCESSFEATURES:: FEATURE:: [%s]->[%s]", choice.name, choiceName)
        writeLog(string.format("Found Feature [%s] in import.", choiceName))

        self:_findMatchingFeature("CharacterFeatureChoice", self.availableFeatures, onMatch)
    end

    writeDebug("PROCESSFEATURES:: FEATURE:: COMPLETE::")
end

--- Processes a deity choice from the selected features, looking up deity in the Codex
--- @param selectedFeature table The selected feature containing deity choice data
--- @private
function FSCIChoiceImporter:_processDeityChoice(selectedFeature)
    writeDebug("PROCESSFEATURES:: DEITY:: START:: %s", json(selectedFeature))

    self:_processTableLookupChoice(Deity.tableName, "CharacterDeityChoice", selectedFeature.name)

    writeDebug("PROCESSFEATURES:: DEITY:: COMPLETE::")
end

--- Processes a language choice from the selected features, looking up language in the Codex
--- @param selectedFeature table The selected feature containing deity choice data
--- @private
function FSCIChoiceImporter:_processLanguageChoice(selectedFeature)
    writeDebug("PROCESSFEATURES:: LANGUAGE:: START:: %s", json(selectedFeature))

    for _, languageName in pairs(selectedFeature.data.selected) do
        self:_processTableLookupChoice(Language.tableName, "CharacterLanguageChoice", languageName)
    end

    writeDebug("PROCESSFEATURES:: LANGUAGE:: COMPLETE::")
end

--- Processes a perk choice from the selected features, looking up perks in the Codex
--- @param selectedFeature table The selected feature containing skill choice data
--- @private
function FSCIChoiceImporter:_processPerkChoice(selectedFeature)
    writeDebug("PROCESSFEATURES:: PERK:: START:: %s", json(selectedFeature))

    for _, perk in pairs(selectedFeature.data.selected) do
        self:_processTableLookupChoice(CharacterFeat.tableName, "CharacterFeatChoice", perk.name)
    end

    writeDebug("PROCESSFEATURES:: PERK:: COMPLETE::")
end

--- Processes a skill choice from the selected features, looking up skills in the Codex
--- @param selectedFeature table The selected feature containing skill choice data
--- @private
function FSCIChoiceImporter:_processSkillChoice(selectedFeature)
    writeDebug("PROCESSFEATURES:: SKILL:: START:: %s", json(selectedFeature))

    for _, skillName in pairs(selectedFeature.data.selected) do
        self:_processTableLookupChoice(Skill.tableName, "CharacterSkillChoice", skillName)
    end

    writeDebug("PROCESSFEATURES:: SKILL:: COMPLETE::")
end

--- Processes a subclass choice from the selected features, looking up subclass in the Codex
--- @param selectedFeature table The selected feature containing subclass choice data
--- @private
function FSCIChoiceImporter:_processSubclassChoice(selectedFeature)
    writeDebug("PROCESSFEATURES:: SUBCLASS:: START:: %s", json(selectedFeature))

    self:_processTableLookupChoice("subclasses", "CharacterSubclassChoice", selectedFeature.name)

    writeDebug("PROCESSFEATURES:: SUBCLASS:: COMPLETE::")
end

--- Processes a domain feature from the selected features
--- @param selectedFeature table The selected feature containing choice data
--- @private
function FSCIChoiceImporter:_processDomainFeature(selectedFeature)
    writeDebug("PROCESSFEATURES:: DOMAINFEATURE:: START:: %s", json(selectedFeature))

    writeDebug("PROCESSFEATURES:: DOMAINFEATURE:: END::")
end

--- Processes a table lookup choice by finding the item in a table, matching to a feature, and adding to level choices
--- @param tableName string The table name to look up the item in (e.g., "Language.tableName", "CharacterFeat.tableName")
--- @param choiceType string The choice type to find in available features (e.g., "CharacterLanguageChoice")
--- @param itemName string The name of the item to look up
--- @return boolean success Whether the lookup and addition was successful
--- @private
function FSCIChoiceImporter:_processTableLookupChoice(tableName, choiceType, itemName)
    writeLog(string.format("Found %s [%s] in import.", tableName, itemName))

    local itemId, item = tableLookupFromName(tableName, itemName)
    local processed = false

    local function onMatch(matchedFeature)
        if itemName == "Architecture" or itemName == "Blacksmithing" or itemName == "Ananjali" then
            writeLog(string.format("onMatch [%s] [%s]", itemName, item:try_get("category")))
            writeDebug("ONMATCH:: CATEGORIES:: [%s] [%s]", itemName, json(item:try_get("categories")))
        end
        if self:_categoryMatch(item:try_get("category") or "", matchedFeature:try_get("categories") or {}) then
            writeLog(string.format("Adding %s [%s].", tableName, itemName), STATUS.IMPL)
            self:_addLevelChoice(matchedFeature.guid, itemId, matchedFeature)
            return true
        end
        return false
    end

    if itemId then
        writeLog("Found match in Codex.")
        processed = self:_findMatchingFeature(choiceType, self.availableFeatures, onMatch)
    else
        writeLog(string.format("!!!! %s [%s] not found in Codex.", tableName, itemName), STATUS.WARN)
    end

    return processed
end

--- Checks if an available feature passes the current filter criteria
--- @param availableFeature table The available feature to check against the filter
--- @return boolean match True if the feature matches the filter (or no filter is set), false otherwise
--- @private
function FSCIChoiceImporter:_filterMatch(availableFeature)
    -- If filter is set and has content, check all criteria
    if self.filter and next(self.filter) then
        for key, value in pairs(self.filter) do
            if availableFeature[key] and type(availableFeature[key]) == "string" then
                if not sanitizedStringsMatch(string.sub(availableFeature[key], 1, #value), value) then
                    return false
                end
            else
                return false
            end
        end
    end

    return true  -- No filter OR all criteria passed
end

--- Recursively searches available features to find a feature matching the specified choice type
--- @param choiceType string The type of choice to find (e.g., "CharacterSkillChoice")
--- @param availableFeatures table The list of available features to search
--- @param onMatch function Callback function for each match; return true to stop; false to continue
--- @param filterMatched? boolean Whether we're processing under a node that matched our filter
--- @return boolean processed Whether the callback processed the feature / stop processing
--- @private
function FSCIChoiceImporter:_findMatchingFeature(choiceType, availableFeatures, onMatch, filterMatched)
    filterMatched = filterMatched or false

    writeDebug("FINDMATCHINGFEATURE:: START:: %s %s", choiceType, json(availableFeatures))

    local processed = false

    for _, availableFeature in pairs(availableFeatures) do
        writeLog(string.format("Checking feature type %s name %s", availableFeature.typeName, availableFeature.name), STATUS.INFO, 1)

        local passesFilter = filterMatched or self:_filterMatch(availableFeature)

        if passesFilter and sanitizedStringsMatch(choiceType, availableFeature.typeName) then
            writeLog("Potential match...")
            processed = onMatch(availableFeature)
        end
        if not processed then
            local nestedFeatures = availableFeature:try_get("features")
            if nestedFeatures then
                processed = self:_findMatchingFeature(choiceType, nestedFeatures, onMatch, passesFilter)
            end
        end
        writeLog(string.format("End feature type %s", availableFeature.typeName), STATUS.INFO, -1)
        if processed then break end
    end

    writeDebug("FINDMATCHINGFEATURE:: COMPLETE:: %s", tostring(processed))
    return processed
end

--- Determines whether any of the values by string in selected are in the flag list available
--- @param selected string The category name to match
--- @param available table Flag list of available categories
--- @return boolean foundMatch True if the available list is empty or we found a match
function FSCIChoiceImporter:_categoryMatch(selected, available)
    local foundMatch = true

    if next(available) then
        foundMatch = available[selected]
    end

    return foundMatch
end