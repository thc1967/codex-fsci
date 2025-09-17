--- FSCIAdapter handles the conversion of Forge Steel character data to CTIE format.
--- This class parses Forge Steel JSON exports, translates the data using existing FSCI logic,
--- and populates a complete CTIECodexDTO object for import through the CTIE pipeline.
--- @class FSCIAdapter
--- @field fsJson string The raw Forge Steel JSON string
--- @field fsData table The parsed Forge Steel data structure
--- @field codexDTO CTIECodexDTO The CTIE Codex DTO object being populated
FSCIAdapter = RegisterGameType("FSCIAdapter")
FSCIAdapter.__index = FSCIAdapter

local writeDebug = CTIEUtils.writeDebug
local writeLog = CTIEUtils.writeLog
local STATUS = CTIEUtils.STATUS

--- Translate strings from Forge Steel names to Codex names.
local FSCI_TRANSLATIONS = {
    -- Ancestries
    ["Elf (high)"]              = "Elf, High",
    ["Elf (wode)"]              = "Elf, Wode",

    -- Ancestry Features
    ["Draconic Pride"]          = "Draconian Pride",
    ["Perseverence"]            = "Perseverance",
    ["Resist the Unnatural"]    = "Resist the Supernatural",

    -- Choice Types
    ["Elementalist Ward"]       = "Ward",

    -- Classes & Subclasses
    ["Chronokinetic"]           = "Disciple of the Chronokinetic",
    ["Cryokinetic"]             = "Disciple of the Cryokinetic",
    ["Metakinetic"]             = "Disciple of the Metakinetic",

    -- Abilities
    ["Motivate Earth"]          = "Manipulate Earth",               -- Remove when Codex Data is fixed
    ["Halt, Miscreant!"]        = "Halt Miscreant!",

    -- Feats
    ["I've Got You"]            = "I've Got You!",
    ["Teamwork"]                = "Team Backbone",                  -- Remove when Codex Data is fixed

    ["Prayer"]                  = "Prayers",

    -- Inciting Incidents
    ["Near-Death Experience"]   = "Near Death Experience",

    -- Kits
    ["Rapid Fire"]              = "Rapid-Fire",
    
    -- Languages
    ["Anjali"]                  = "Anjal",                          -- Remove when Codex Data is fixed
    ["Yllric"]                  = "Yllyric",

    -- Psionic Augmentations & Wards
    ["Battle Augmentation"]     = "Battle Augmentation ",
    ["Steel Ward"]              = "Steel Ward ",
    ["Talent Ward"]             = "Ward",

    -- Skills
    ["Perform"]                 = "Performance",
}

--- Performs fuzzy string matching between sanitized, translated strings.
--- Normalizes strings by removing special characters, trimming whitespace, applying translations, and doing case-insensitive comparison.
--- @param s1 string First string to compare
--- @param s2 string Second string to compare
--- @return boolean match True if strings match after sanitization and translation
local function sanitizedStringsMatch(s1, s2)
    local function sanitize(s)
        s = s or ""
        return s:gsub("[^%w%s;:!@#%$%%^&*()%-+=%?,]", ""):trim()
    end

    local function translateFStoCodex(fsString)
        return FSCI_TRANSLATIONS[fsString] or fsString
    end

    local ns1 = string.lower(sanitize(translateFStoCodex(s1)))
    local ns2 = string.lower(sanitize(translateFStoCodex(s2)))

    return ns1 == ns2
end

--- Translates Forge Steel strings to Codex equivalents using FSCI_TRANSLATIONS.
--- @param fsString string The Forge Steel string to translate
--- @return string The translated string or original if no translation exists
local function translateFStoCodex(fsString)
    return FSCI_TRANSLATIONS[fsString] or fsString
end

--- Creates a new FSCIAdapter instance for converting Forge Steel character data to CTIE format.
--- Parses and validates the provided JSON text from Forge Steel exports and initializes
--- an empty CTIECodexDTO object for population during conversion.
--- @param jsonText string The JSON string from Forge Steel character export
--- @return FSCIAdapter|nil instance The new adapter instance if valid, nil if parsing fails
function FSCIAdapter:new(jsonText)
    if not jsonText or #jsonText == 0 then
        writeLog("!!!! Empty Forge Steel import file.", STATUS.WARN)
        return nil
    end

    local parsedData = dmhub.FromJson(jsonText).result
    if not parsedData then
        writeLog("!!!! Invalid Forge Steel JSON format.", STATUS.WARN)
        return nil
    end

    -- Basic validation - ensure it's Forge Steel format
    if not parsedData.name or not parsedData.class then
        writeLog("!!!! Not a valid Forge Steel character file.", STATUS.WARN)
        return nil
    end

    local instance = setmetatable({}, self)
    instance.fsJson = jsonText
    instance.fsData = parsedData
    instance.codexDTO = CTIECodexDTO:new()
    return instance
end

--- Converts Forge Steel character data to CTIE format for import.
--- Orchestrates the translation process by calling specialized conversion methods for each data category.
--- Processes ancestry, culture, career, class, and attribute data from Forge Steel format into
--- the CTIECodexDTO structure for seamless import through the CTIE pipeline.
--- @return CTIECodexDTO codexDTO The populated Codex DTO object ready for CTIE import
function FSCIAdapter:Convert()
    writeDebug("FSCIADAPTER:: START::")
    writeLog("Forge Steel character conversion start.", STATUS.INFO, 1)

    -- Set character name in token
    self.codexDTO:Token():SetName(self.fsData.name)
    writeLog(string.format("Character Name is [%s].", self.fsData.name), STATUS.IMPL)

    -- Convert all character data
    self:_convertAttributes()
    self:_convertAncestry()
    self:_convertCulture()
    self:_convertCareer()
    self:_convertClass()
    self:_convertKits()

    writeLog("Forge Steel character conversion complete.", STATUS.INFO, -1)
    return self.codexDTO
end

--- Creates a lookup record for database-backed objects with fuzzy matching.
--- Uses existing game data to resolve names to GUIDs when possible.
--- @private
--- @param tableName string The table name to search in
--- @param name string The name to look up
--- @return CTIELookupTableDTO lookupRecord The populated lookup record
function FSCIAdapter:_createLookupRecord(tableName, name)
    local translatedName = translateFStoCodex(name)
    local lookupRecord = CTIELookupTableDTO:new()
    lookupRecord:SetTableName(tableName)
    lookupRecord:SetName(translatedName)
    
    -- Try to find GUID using fuzzy matching
    local itemFound = import:GetExistingItem(tableName, translatedName)
    if itemFound then
        lookupRecord:SetID(itemFound.id)
        writeDebug("LOOKUP:: FOUND GUID [%s] for [%s] in [%s]", itemFound.id, translatedName, tableName)
        return lookupRecord
    end
    
    -- Fallback to fuzzy search in table
    local t = dmhub.GetTable(tableName) or {}
    for id, row in pairs(t) do
        if not row:try_get("hidden", false) and sanitizedStringsMatch(row.name, translatedName) then
            lookupRecord:SetID(id)
            writeDebug("LOOKUP:: FUZZY FOUND GUID [%s] for [%s] in [%s]", id, translatedName, tableName)
            return lookupRecord
        end
    end
    
    writeLog(string.format("!!!! Unable to resolve [%s] in table [%s].", translatedName, tableName), STATUS.WARN)
    lookupRecord:SetID("") -- Empty GUID for later resolution
    return lookupRecord
end

--- Maps table names back to choice types using the reverse of CHOICE_TYPE_TO_TABLE_NAME_MAP.
--- @private
--- @param tableName string The table name to look up
--- @return string choiceType The corresponding choice type or "CharacterFeatureChoice" as fallback
function FSCIAdapter:_getChoiceTypeFromTableName(tableName)
    local tableToChoiceMap = {
        [Deity.tableName] = "CharacterDeityChoice",
        [CharacterFeat.tableName] = "CharacterFeatChoice", 
        ["feats"] = "CharacterFeatChoice", -- Handle the "feats" alias used for perks
        [CTIEUtils.FEATURE_TABLE_MARKER] = "CharacterFeatureChoice",
        [Language.tableName] = "CharacterLanguageChoice",
        [Skill.tableName] = "CharacterSkillChoice",
        ["subclasses"] = "CharacterSubclassChoice"
    }
    
    return tableToChoiceMap[tableName] or "CharacterFeatureChoice"
end

--- Creates a selected feature DTO for choice-based features.
--- @private
--- @param selectedOptions table Array of selected option GUIDs or lookup records
--- @return CTIESelectedFeatureDTO|nil selectedFeature The populated selected feature DTO, or nil if no valid selections
function FSCIAdapter:_createSelectedFeature(selectedOptions)
    -- Validate that we have actual selections to prevent CTIELevelChoiceImporter crashes
    if not selectedOptions or #selectedOptions == 0 then
        writeLog("!!!! Attempted to create selectedFeature with no selections, continuing", STATUS.WARN)
        return nil
    end

    local selectedFeature = CTIESelectedFeatureDTO:new()
    -- Leave choiceId blank for CTIE system to resolve

    for _, option in ipairs(selectedOptions) do
        selectedFeature:AddSelection(option) -- Add lookup record or GUID
    end

    -- Set choiceType based on the first option's table name
    if selectedOptions[1].GetTableName then
        local tableName = selectedOptions[1]:GetTableName()
        local choiceType = self:_getChoiceTypeFromTableName(tableName)
        selectedFeature:SetChoiceType(choiceType)
        writeDebug("SELECTEDFEATURE:: SET CHOICETYPE [%s] for table [%s]", choiceType, tableName)
    end

    return selectedFeature
end

--- Converts Forge Steel attribute data to CTIE format.
--- Extracts characteristic values from Forge Steel class data and sets them in the attributes DTO.
--- @private
function FSCIAdapter:_convertAttributes()
    writeLog("Parsing Attributes.", STATUS.INFO, 1)

    if not (self.fsData.class and self.fsData.class.characteristics) then
        writeLog("!!!! class.characteristics not found in import.", STATUS.WARN, -1)
        return
    end

    local attributesDTO = self.codexDTO:Character():Attributes()
    local charMap = {
        Might = "mgt",
        Agility = "agl", 
        Reason = "rea",
        Intuition = "inu",
        Presence = "prs"
    }

    for _, entry in ipairs(self.fsData.class.characteristics) do
        local key = charMap[entry.characteristic]
        if key then
            writeDebug("CONVERTATTRIBUTES:: SET:: %s => %+d", key, entry.value)
            writeLog(string.format("Setting Attribute %s to %+d.", key, entry.value), STATUS.INFO)
            
            -- Set attribute value using appropriate method
            if key == "mgt" then
                attributesDTO:SetMgt(entry.value)
            elseif key == "agl" then
                attributesDTO:SetAgl(entry.value)
            elseif key == "rea" then
                attributesDTO:SetRea(entry.value)
            elseif key == "inu" then
                attributesDTO:SetInu(entry.value)
            elseif key == "prs" then
                attributesDTO:SetPrs(entry.value)
            end
        else
            writeLog(string.format("!!!! Unknown characteristic [%s] in import.", entry.characteristic), STATUS.WARN)
        end
    end

    writeLog("Attributes complete.", STATUS.INFO, -1)
end

--- Converts Forge Steel ancestry data to CTIE format.
--- Sets the race lookup record and processes selected ancestry features.
--- @private
function FSCIAdapter:_convertAncestry()
    writeDebug("CONVERTANCESTRY:: START::")
    writeLog("Parsing Ancestry.", STATUS.INFO, 1)

    if not self.fsData.ancestry then
        writeLog("!!!! Ancestry not found in import.", STATUS.WARN, -1)
        return
    end

    local raceInfo = self.fsData.ancestry
    writeLog(string.format("Ancestry [%s] found in import.", raceInfo.name), STATUS.INFO)

    local ancestryDTO = self.codexDTO:Character():Ancestry()
    
    -- Set race lookup record
    local raceLookup = self:_createLookupRecord(Race.tableName, raceInfo.name)
    ancestryDTO:GuidLookup():SetTableName(raceLookup:GetTableName())
    ancestryDTO:GuidLookup():SetName(raceLookup:GetName())
    ancestryDTO:GuidLookup():SetID(raceLookup:GetID())
    
    -- Process ancestry features
    if raceInfo.features then
        self:_convertAncestryFeatures(raceInfo.features, ancestryDTO:SelectedFeatures())
    end

    writeLog("Ancestry complete.", STATUS.INFO, -1)
    writeDebug("CONVERTANCESTRY:: COMPLETE:: %s", json(ancestryDTO))
end

--- Maps Forge Steel feature option names to Codex equivalents.
--- Handles special cases like damage modifier extraction from descriptions.
--- @private
--- @param choice table The Forge Steel choice object with name and description
--- @return string The mapped Codex name
local function mapFSOptionToCodex(choice)
    local s = choice.name or ""
    if string.lower(s) == "damage modifier" then
        s = string.match(choice.description or "", "^(.*Immunity)") or s
    else
        s = translateFStoCodex(s)
    end
    return s
end

--- Converts Forge Steel ancestry features to CTIE selected features format.
--- Processes choice-based features, skill choices, and nested multiple features recursively.
--- @private
--- @param features table Array of Forge Steel ancestry features to convert
--- @param selectedFeaturesDTO CTIESelectedFeaturesDTO The DTO to populate with converted features
function FSCIAdapter:_convertAncestryFeatures(features, selectedFeaturesDTO)
    if not features then
        writeLog("!!!! Ancestry Features not found in import.", STATUS.WARN)
        return
    end

    for _, feature in ipairs(features) do
        local featureType = string.lower(feature.type or "")
        
        if "choice" == featureType and feature.data and feature.data.selected then
            -- Handle choice-based features - group all selections from the same choice
            local lookupRecords = {}
            for _, choice in ipairs(feature.data.selected) do
                local choiceName = mapFSOptionToCodex(choice)
                writeLog(string.format("Found Ancestry Feature [%s]->[%s] in import.", choice.name or "?", choiceName), STATUS.INFO)
                
                -- Create a feature lookup record - these are special markers for later resolution
                local lookupRecord = CTIELookupTableDTO:new()
                lookupRecord:SetTableName(CTIEUtils.FEATURE_TABLE_MARKER)
                lookupRecord:SetName(choiceName)
                lookupRecord:SetID("") -- Empty GUID for features
                
                table.insert(lookupRecords, lookupRecord)
            end
            
            -- Create a single selected feature with all selections grouped together
            if #lookupRecords > 0 then
                local selectedFeature = self:_createSelectedFeature(lookupRecords)
                selectedFeaturesDTO:AddFeature(selectedFeature)
            end
            
        elseif "skill choice" == featureType and feature.data and feature.data.selected then
            -- Handle skill choices - group all selections from the same choice
            local lookupRecords = {}
            for _, skillName in ipairs(feature.data.selected) do
                writeLog(string.format("Found Ancestry Skill [%s] in import.", skillName), STATUS.INFO)
                local skillLookup = self:_createLookupRecord(Skill.tableName, skillName)
                table.insert(lookupRecords, skillLookup)
            end
            
            -- Create a single selected feature with all selections grouped together
            if #lookupRecords > 0 then
                local selectedFeature = self:_createSelectedFeature(lookupRecords)
                selectedFeaturesDTO:AddFeature(selectedFeature)
            end
            
        elseif "perk" == featureType and feature.data and feature.data.selected then
            -- Handle perk choices - group all selections from the same choice
            local lookupRecords = {}
            for _, perk in ipairs(feature.data.selected) do
                writeLog(string.format("Found Ancestry Perk [%s] in import.", perk.name or "?"), STATUS.INFO)
                local perkLookup = self:_createLookupRecord("feats", perk.name)
                table.insert(lookupRecords, perkLookup)
            end
            
            -- Create a single selected feature with all selections grouped together
            if #lookupRecords > 0 then
                local selectedFeature = self:_createSelectedFeature(lookupRecords)
                selectedFeaturesDTO:AddFeature(selectedFeature)
            end
            
        elseif "multiple features" == featureType and feature.data and feature.data.features then
            -- Handle nested features recursively
            writeDebug("CONVERTANCESTRYFEATURES:: MULTIPLEFEATURES::")
            self:_convertAncestryFeatures(feature.data.features, selectedFeaturesDTO)
        end
    end
end

--- Converts Forge Steel culture data to CTIE format.
--- Sets culture language and processes the three culture aspects (environment, organization, upbringing).
--- @private
function FSCIAdapter:_convertCulture()
    writeDebug("CONVERTCULTURE:: START::")
    writeLog("Parsing Culture.", STATUS.INFO, 1)

    if not self.fsData.culture then
        writeLog("!!!! Culture not found in import.", STATUS.WARN, -1)
        return
    end

    local culture = self.fsData.culture
    local cultureDTO = self.codexDTO:Character():Culture()
    
    -- Process culture languages (Forge Steel has multiple, CTIE expects one primary)
    if culture.languages and #culture.languages > 0 then
        local primaryLanguage = culture.languages[1] -- Take first language as primary
        writeLog(string.format("Setting primary culture language [%s].", primaryLanguage), STATUS.INFO)
        local languageLookup = self:_createLookupRecord(Language.tableName, primaryLanguage)
        cultureDTO:Language():SetTableName(languageLookup:GetTableName())
        cultureDTO:Language():SetName(languageLookup:GetName())
        cultureDTO:Language():SetID(languageLookup:GetID())
    end
    
    -- Process culture aspects
    self:_convertCultureAspects(culture, cultureDTO)

    writeLog("Culture complete.", STATUS.INFO, -1)
    writeDebug("CONVERTCULTURE:: COMPLETE:: %s", json(cultureDTO))
end

--- Converts Forge Steel culture aspects to CTIE format.
--- Processes environment, organization, and upbringing aspects with their selected features.
--- @private
--- @param culture table The Forge Steel culture data
--- @param cultureDTO CTIECultureDTO The CTIE culture DTO to populate
function FSCIAdapter:_convertCultureAspects(culture, cultureDTO)
    local aspectNames = {"environment", "organization", "upbringing"}
    
    for _, aspectName in ipairs(aspectNames) do
        if culture[aspectName] then
            self:_convertCultureAspect(aspectName, culture[aspectName], cultureDTO)
        else
            writeLog(string.format("!!! Culture Aspect [%s] not found in import!", aspectName), STATUS.WARN)
        end
    end
end

--- Converts a single culture aspect to CTIE format.
--- @private
--- @param aspectName string The aspect name ("environment", "organization", "upbringing")
--- @param aspect table The Forge Steel aspect data
--- @param cultureDTO CTIECultureDTO The CTIE culture DTO to populate
function FSCIAdapter:_convertCultureAspect(aspectName, aspect, cultureDTO)
    writeLog(string.format("Processing Culture Aspect [%s] [%s]", aspectName, aspect.name or "?"), STATUS.INFO, 1)

    local aspectDTO
    if aspectName == "environment" then
        aspectDTO = cultureDTO:Environment()
    elseif aspectName == "organization" then
        aspectDTO = cultureDTO:Organization()
    elseif aspectName == "upbringing" then
        aspectDTO = cultureDTO:Upbringing()
    else
        writeLog(string.format("!!!! Unknown culture aspect [%s]", aspectName), STATUS.WARN, -1)
        return
    end
    
    -- Set aspect lookup record
    local aspectLookup = self:_createLookupRecord(CultureAspect.tableName, aspect.name)
    aspectDTO:GuidLookup():SetTableName(aspectLookup:GetTableName())
    aspectDTO:GuidLookup():SetName(aspectLookup:GetName())
    aspectDTO:GuidLookup():SetID(aspectLookup:GetID())
    
    -- Process aspect features (typically skill choices)
    if aspect.type and aspect.type:lower() == "skill choice" and aspect.data and aspect.data.selected then
        -- Handle skill choices - group all selections from the same choice
        local lookupRecords = {}
        for _, skillName in ipairs(aspect.data.selected) do
            writeLog(string.format("Found Culture Aspect Skill [%s] in import.", skillName), STATUS.INFO)
            local skillLookup = self:_createLookupRecord(Skill.tableName, skillName)
            table.insert(lookupRecords, skillLookup)
        end
        
        -- Create a single selected feature with all selections grouped together
        if #lookupRecords > 0 then
            local selectedFeature = self:_createSelectedFeature(lookupRecords)
            aspectDTO:SelectedFeatures():AddFeature(selectedFeature)
        end
    end

    writeLog(string.format("Culture Aspect [%s] complete.", aspectName), STATUS.INFO, -1)
end

--- Converts Forge Steel career data to CTIE format.
--- Sets career background lookup and processes career features and inciting incidents.
--- @private
function FSCIAdapter:_convertCareer()
    writeDebug("CONVERTCAREER:: START::")
    writeLog("Parsing Career.", STATUS.INFO, 1)
    
    if not self.fsData.career then
        writeLog("!!!! Career not found in import.", STATUS.WARN, -1)
        return
    end

    local careerInfo = self.fsData.career
    writeLog(string.format("Found Career [%s] in import.", careerInfo.name), STATUS.INFO)

    local careerDTO = self.codexDTO:Character():Career()
    
    -- Set background lookup record
    local backgroundLookup = self:_createLookupRecord(Background.tableName, careerInfo.name)
    careerDTO:GuidLookup():SetTableName(backgroundLookup:GetTableName())
    careerDTO:GuidLookup():SetName(backgroundLookup:GetName())
    careerDTO:GuidLookup():SetID(backgroundLookup:GetID())
    
    -- Process career features (languages, perks, skills, etc.)
    if careerInfo.features then
        self:_convertCareerFeatures(careerInfo.features, careerDTO:SelectedFeatures())
    end

    -- Process inciting incident
    if careerInfo.incitingIncidents and careerInfo.incitingIncidents.selectedID then
        self:_convertIncitingIncident(careerInfo.incitingIncidents, careerDTO)
    end

    writeLog("Career complete.", STATUS.INFO, -1)
    writeDebug("CONVERTCAREER:: COMPLETE:: %s", json(careerDTO))
end

--- Processes inciting incident from career data.
--- @private
--- @param incitingIncidents table The inciting incidents data from Forge Steel
--- @param careerDTO CTIECareerDTO The career DTO to populate
function FSCIAdapter:_convertIncitingIncident(incitingIncidents, careerDTO)
    if not incitingIncidents.selectedID then
        writeLog("!!!! No inciting incident selected.", STATUS.WARN)
        return
    end
    
    for _, option in ipairs(incitingIncidents.options or {}) do
        if string.lower(option.id) == string.lower(incitingIncidents.selectedID) then
            writeLog(string.format("Found Inciting Incident [%s] in import.", option.name), STATUS.INFO)
            -- For now, we'll create a placeholder - this would need special handling for notes
            local incidentLookup = CTIELookupTableDTO:new()
            incidentLookup:SetTableName("IncitingIncident")
            incidentLookup:SetName(translateFStoCodex(option.name))
            incidentLookup:SetID("")
            
            careerDTO:IncitingIncident():SetTableName(incidentLookup:GetTableName())
            careerDTO:IncitingIncident():SetName(incidentLookup:GetName()) 
            careerDTO:IncitingIncident():SetID(incidentLookup:GetID())
            break
        end
    end
end

--- Processes career features (languages, perks, skills).
--- @private
--- @param features table Array of career features
--- @param selectedFeaturesDTO CTIESelectedFeaturesDTO The selected features DTO to populate
function FSCIAdapter:_convertCareerFeatures(features, selectedFeaturesDTO)
    for _, feature in ipairs(features) do
        local featureType = string.lower(feature.type or "")
        
        if "language choice" == featureType and feature.data and feature.data.selected then
            -- Handle language choices - group all selections from the same choice
            local lookupRecords = {}
            for _, languageName in ipairs(feature.data.selected) do
                writeLog(string.format("Found Career Language [%s] in import.", languageName), STATUS.INFO)
                local languageLookup = self:_createLookupRecord(Language.tableName, languageName)
                table.insert(lookupRecords, languageLookup)
            end
            
            -- Create a single selected feature with all selections grouped together
            if #lookupRecords > 0 then
                local selectedFeature = self:_createSelectedFeature(lookupRecords)
                selectedFeaturesDTO:AddFeature(selectedFeature)
            end
            
        elseif "perk" == featureType and feature.data and feature.data.selected then
            -- Handle perk choices - group all selections from the same choice
            local lookupRecords = {}
            for _, perk in ipairs(feature.data.selected) do
                writeLog(string.format("Found Career Perk [%s] in import.", perk.name or "?"), STATUS.INFO)
                local perkLookup = self:_createLookupRecord("feats", perk.name)
                table.insert(lookupRecords, perkLookup)
            end
            
            -- Create a single selected feature with all selections grouped together
            if #lookupRecords > 0 then
                local selectedFeature = self:_createSelectedFeature(lookupRecords)
                selectedFeaturesDTO:AddFeature(selectedFeature)
            end
            
        elseif "skill choice" == featureType and feature.data and feature.data.selected then
            -- Handle skill choices - group all selections from the same choice
            local lookupRecords = {}
            for _, skillName in ipairs(feature.data.selected) do
                writeLog(string.format("Found Career Skill [%s] in import.", skillName), STATUS.INFO)
                local skillLookup = self:_createLookupRecord(Skill.tableName, skillName)
                table.insert(lookupRecords, skillLookup)
            end
            
            -- Create a single selected feature with all selections grouped together
            if #lookupRecords > 0 then
                local selectedFeature = self:_createSelectedFeature(lookupRecords)
                selectedFeaturesDTO:AddFeature(selectedFeature)
            end
        end
    end
end

--- Converts Forge Steel class data to CTIE format.
--- Sets class lookup record, level, and processes class features including subclasses and domains.
--- @private
function FSCIAdapter:_convertClass()
    writeDebug("CONVERTCLASS:: START::")
    writeLog("Parsing Class.", STATUS.INFO, 1)
    
    if not self.fsData.class then
        writeLog("!!!! Class not found in import.", STATUS.WARN, -1)
        return
    end

    local classInfo = self.fsData.class
    writeLog(string.format("Found Class [%s] Level [%d] in import.", classInfo.name, classInfo.level or 1), STATUS.INFO)

    local classDTO = self.codexDTO:Character():Class()
    
    -- Set class lookup record
    local classLookup = self:_createLookupRecord(Class.tableName, classInfo.name)
    classDTO:GuidLookup():SetTableName(classLookup:GetTableName())
    classDTO:GuidLookup():SetName(classLookup:GetName())
    classDTO:GuidLookup():SetID(classLookup:GetID())
    
    -- Set class level
    classDTO:SetLevel(classInfo.level or 1)
    
    -- Process class features
    if classInfo.featuresByLevel then
        self:_convertClassFeatures(classInfo.featuresByLevel, classInfo.abilities, classDTO:SelectedFeatures())
    end
    
    -- Process subclasses
    if classInfo.subclasses then
        self:_convertSubclasses(classInfo.subclasses, classDTO:SelectedFeatures())
    end

    writeLog("Class complete.", STATUS.INFO, -1)
    writeDebug("CONVERTCLASS:: COMPLETE:: %s", json(classDTO))
end

--- Processes class features from featuresByLevel array.
--- @private
--- @param featuresByLevel table Array of level-based features
--- @param abilities table Array of class abilities
--- @param selectedFeaturesDTO CTIESelectedFeaturesDTO The selected features DTO to populate
function FSCIAdapter:_convertClassFeatures(featuresByLevel, abilities, selectedFeaturesDTO)
    for _, levelFeature in ipairs(featuresByLevel) do
        if levelFeature.features then
            for _, feature in ipairs(levelFeature.features) do
                local featureType = string.lower(feature.type or "")
                
                if "class ability" == featureType and feature.data and feature.data.selectedIDs then
                    -- Map ability IDs to ability names, then find in Codex - group all selections from the same choice
                    local lookupRecords = {}
                    for _, abilityId in ipairs(feature.data.selectedIDs) do
                        for _, ability in ipairs(abilities or {}) do
                            if ability.id == abilityId then
                                writeLog(string.format("Found Class Ability [%s] in import.", ability.name), STATUS.INFO)
                                local abilityLookup = CTIELookupTableDTO:new()
                                abilityLookup:SetTableName(CTIEUtils.FEATURE_TABLE_MARKER)
                                abilityLookup:SetName(translateFStoCodex(ability.name))
                                abilityLookup:SetID("")
                                
                                table.insert(lookupRecords, abilityLookup)
                                break
                            end
                        end
                    end
                    
                    -- Create a single selected feature with all abilities grouped together
                    if #lookupRecords > 0 then
                        local selectedFeature = self:_createSelectedFeature(lookupRecords)
                        selectedFeaturesDTO:AddFeature(selectedFeature)
                    end
                    
                elseif "choice" == featureType and feature.data and feature.data.selected then
                    -- Handle choice-based features - group all selections from the same choice
                    local lookupRecords = {}
                    for _, choice in ipairs(feature.data.selected) do
                        writeLog(string.format("Found Class Choice [%s] in import.", choice.name or "?"), STATUS.INFO)
                        local choiceLookup = CTIELookupTableDTO:new()
                        choiceLookup:SetTableName(CTIEUtils.FEATURE_TABLE_MARKER)
                        choiceLookup:SetName(translateFStoCodex(choice.name or ""))
                        choiceLookup:SetID("")
                        
                        table.insert(lookupRecords, choiceLookup)
                    end
                    
                    -- Create a single selected feature with all selections grouped together
                    if #lookupRecords > 0 then
                        local selectedFeature = self:_createSelectedFeature(lookupRecords)
                        selectedFeaturesDTO:AddFeature(selectedFeature)
                    end
                    
                elseif "perk" == featureType and feature.data and feature.data.selected then
                    -- Handle perk choices - group all selections from the same choice
                    local lookupRecords = {}
                    for _, perk in ipairs(feature.data.selected) do
                        writeLog(string.format("Found Class Perk [%s] in import.", perk.name or "?"), STATUS.INFO)
                        local perkLookup = self:_createLookupRecord("feats", perk.name)
                        table.insert(lookupRecords, perkLookup)
                    end
                    
                    -- Create a single selected feature with all selections grouped together
                    if #lookupRecords > 0 then
                        local selectedFeature = self:_createSelectedFeature(lookupRecords)
                        selectedFeaturesDTO:AddFeature(selectedFeature)
                    end
                    
                elseif "skill choice" == featureType and feature.data then
                    -- Handle class skill choices with real GUID lookup
                    writeDebug("PROCESSCLASS:: Found skill choice feature [%s] with selected skills: %s", feature.name or "unnamed", json(feature.data.selected or {}))
                    self:_convertClassSkillChoice(feature, selectedFeaturesDTO)

                elseif "domain" == featureType and feature.data and feature.data.selected then
                    -- Handle domain choices - create domain selections and default deity
                    self:_convertDomains(feature.data.selected, selectedFeaturesDTO)

                elseif "domain feature" == featureType and feature.data and feature.data.selected then
                    -- Handle domain feature choices - process selected domain features which may contain skill choices
                    writeDebug("PROCESSCLASS:: Found domain feature choice with %d selected features", #(feature.data.selected or {}))
                    for _, selectedDomainFeature in ipairs(feature.data.selected) do
                        writeDebug("PROCESSCLASS:: Processing domain feature [%s] of type [%s]", selectedDomainFeature.name or "unnamed", selectedDomainFeature.type or "unknown")

                        -- Extract domain name from the selectedDomainFeature ID or name
                        local domainName = self:_extractDomainNameFromFeature(selectedDomainFeature)
                        writeDebug("PROCESSCLASS:: Extracted domain name: [%s]", domainName or "unknown")

                        if selectedDomainFeature.type and string.lower(selectedDomainFeature.type) == "multiple features" and
                           selectedDomainFeature.data and selectedDomainFeature.data.features then
                            -- Process the nested features within the selected domain feature with domain context
                            self:_processNestedDomainFeatures(selectedDomainFeature.data.features, domainName, selectedFeaturesDTO)
                        end
                    end
                end
            end
        end
    end
end

--- Extracts domain name from a selected domain feature.
--- @private
--- @param selectedDomainFeature table The selected domain feature object
--- @return string|nil domainName The domain name extracted from the feature
function FSCIAdapter:_extractDomainNameFromFeature(selectedDomainFeature)
    -- The domain name should be extractable from the feature ID
    -- Feature IDs are like "domain-war-1" where "war" is the domain name
    if selectedDomainFeature.id then
        local domainMatch = selectedDomainFeature.id:match("^domain%-([^%-]+)")
        if domainMatch then
            -- Capitalize first letter to match domain names like "War"
            return domainMatch:gsub("^%l", string.upper)
        end
    end

    -- Fallback: try to extract from name if ID extraction fails
    writeDebug("EXTRACTDOMAIN:: Could not extract domain from ID [%s], trying name [%s]",
              selectedDomainFeature.id or "nil", selectedDomainFeature.name or "nil")
    return nil
end

--- Processes nested domain features (skill choices within domain features).
--- @private
--- @param features table Array of nested features to process
--- @param domainName string The domain name these features belong to
--- @param selectedFeaturesDTO CTIESelectedFeaturesDTO The selected features DTO to populate
function FSCIAdapter:_processNestedDomainFeatures(features, domainName, selectedFeaturesDTO)
    writeDebug("PROCESSNESTEDOMAIN:: Processing [%d] nested features for domain [%s]", #features, domainName or "unknown")

    for i, feature in ipairs(features) do
        local featureType = string.lower(feature.type or "")
        writeDebug("PROCESSNESTEDOMAIN:: Feature [%d/%d]: id=[%s] name=[%s] type=[%s] in domain [%s]",
                  i, #features, feature.id or "nil", feature.name or "unnamed", featureType, domainName or "unknown")

        if "skill choice" == featureType and feature.data then
            -- Handle nested skill choices as domain skill choices with domain context
            local skillNames = feature.data.selected or {}
            local listOptions = feature.data.listOptions or {}
            writeDebug("PROCESSNESTEDOMAIN:: SKILL CHOICE found: feature=[%s] skills=[%s] listOptions=[%s] domain=[%s]",
                      feature.name or "unnamed", table.concat(skillNames, ", "), table.concat(listOptions, ", "), domainName or "unknown")

            -- Validate domain name before processing
            if not domainName or domainName == "" then
                writeLog(string.format("!!!! Missing domain name for skill choice [%s], skills: %s", feature.name or "unnamed", table.concat(skillNames, ", ")), STATUS.WARN)
                return
            end

            self:_convertDomainSkillChoiceWithContext(feature, domainName, selectedFeaturesDTO)

        elseif "multiple features" == featureType and feature.data and feature.data.features then
            -- Recursively process further nested features
            writeDebug("PROCESSNESTEDOMAIN:: Recursing into [%d] nested features in domain [%s]",
                      #(feature.data.features or {}), domainName or "unknown")
            self:_processNestedDomainFeatures(feature.data.features, domainName, selectedFeaturesDTO)

        else
            writeDebug("PROCESSNESTEDOMAIN:: Skipping feature [%s] of type [%s] (not skill choice or multiple features)",
                      feature.name or "unnamed", featureType)
        end
    end

    writeDebug("PROCESSNESTEDOMAIN:: Completed processing nested features for domain [%s]", domainName or "unknown")
end

--- Processes nested class features (like those found in domain feature choices).
--- @private
--- @param features table Array of nested features to process
--- @param selectedFeaturesDTO CTIESelectedFeaturesDTO The selected features DTO to populate
function FSCIAdapter:_processNestedClassFeatures(features, selectedFeaturesDTO)
    for _, feature in ipairs(features) do
        local featureType = string.lower(feature.type or "")
        writeDebug("PROCESSNESTEDCLASS:: Processing nested feature [%s] of type [%s]", feature.name or "unnamed", featureType)

        if "skill choice" == featureType and feature.data then
            -- Handle nested skill choices as class skill choices
            local skillNames = feature.data.selected or {}
            writeDebug("PROCESSNESTEDCLASS:: Found skill choice feature [%s] with selected skills: %s", feature.name or "unnamed", table.concat(skillNames, ", "))
            self:_convertClassSkillChoice(feature, selectedFeaturesDTO)

        elseif "multiple features" == featureType and feature.data and feature.data.features then
            -- Recursively process further nested features
            self:_processNestedClassFeatures(feature.data.features, selectedFeaturesDTO)
        end
    end
end

--- Processes domain selections from class features.
--- Creates domain entries with choiceType "CharacterDeityDomainChoice" and adds default deity entry.
--- @private
--- @param selectedDomains table Array of selected domain objects from Forge Steel
--- @param selectedFeaturesDTO CTIESelectedFeaturesDTO The selected features DTO to populate
function FSCIAdapter:_convertDomains(selectedDomains, selectedFeaturesDTO)
    if not selectedDomains or #selectedDomains == 0 then
        return
    end

    -- Add default deity entry first and get its reference
    local deitySelectedFeature = self:_addDefaultDeity(selectedFeaturesDTO)

    -- Find the real deity choice feature GUID from the class definition
    local className = self.fsData.class.name
    local deityChoiceGuid = self:_findDeityChoiceFeatureGuid(className)
    local domainChoiceId

    if deityChoiceGuid then
        -- Use the real deity choice GUID + "-domains"
        domainChoiceId = deityChoiceGuid .. "-domains"
        writeLog(string.format("Using real deity choice GUID [%s] for domains.", deityChoiceGuid), STATUS.INFO)
    else
        -- Fall back to synthetic ID if real GUID cannot be found
        local syntheticDeityId = "forge-steel-deity-" .. tostring(os.time())
        domainChoiceId = syntheticDeityId .. "-domains"
        writeLog(string.format("!!!! Could not find deity choice GUID, using synthetic ID [%s].", syntheticDeityId), STATUS.WARN)
    end

    -- Create domain lookup records
    local domainLookupRecords = {}
    for _, domain in ipairs(selectedDomains) do
        if domain and domain.name then
            writeLog(string.format("Found Domain [%s] in import.", domain.name), STATUS.INFO)
            local domainLookup = CTIELookupTableDTO:new()
            domainLookup:SetTableName("DeityDomains")
            domainLookup:SetName(translateFStoCodex(domain.name))
            domainLookup:SetID("") -- No GUID available from Forge Steel
            table.insert(domainLookupRecords, domainLookup)
        end
    end

    -- Create domain selected feature
    if #domainLookupRecords > 0 then
        local domainSelectedFeature = CTIESelectedFeatureDTO:new()
        domainSelectedFeature:SetChoiceType("CharacterDeityDomainChoice")
        domainSelectedFeature:SetChoiceId(domainChoiceId) -- Set the choiceId (real or synthetic)

        for _, lookupRecord in ipairs(domainLookupRecords) do
            domainSelectedFeature:AddSelection(lookupRecord)
        end

        selectedFeaturesDTO:AddFeature(domainSelectedFeature)

        writeLog(string.format("Created domain feature with choiceId [%s].", domainChoiceId), STATUS.INFO)
    end

    -- Process domain skills (nested within domain features)
    self:_convertDomainSkills(selectedDomains, selectedFeaturesDTO)
end

--- Processes domain skills nested within domain features.
--- @private
--- @param selectedDomains table Array of selected domain objects from Forge Steel
--- @param selectedFeaturesDTO CTIESelectedFeaturesDTO The selected features DTO to populate
function FSCIAdapter:_convertDomainSkills(selectedDomains, selectedFeaturesDTO)
    for _, domain in ipairs(selectedDomains) do
        if domain and domain.name and domain.featuresByLevel then
            writeLog(string.format("Processing skills for domain [%s].", domain.name), STATUS.INFO, 1)

            -- Get domain definition features to search through (like class skills)
            local domainFeatures = self:_getDomainFeatures(domain.name)

            -- Search through domain featuresByLevel for skill choices
            for _, levelFeature in ipairs(domain.featuresByLevel) do
                if levelFeature.features then
                    self:_processDomainLevelFeatures(levelFeature.features, domainFeatures, selectedFeaturesDTO)
                end
            end

            writeLog(string.format("Domain [%s] skills complete.", domain.name), STATUS.INFO, -1)
        end
    end
end

--- Recursively processes domain level features looking for skill choices.
--- @private
--- @param features table Array of features to process
--- @param domainFeatures table Domain definition features to search for matching choiceIds
--- @param selectedFeaturesDTO CTIESelectedFeaturesDTO The selected features DTO to populate
function FSCIAdapter:_processDomainLevelFeatures(features, domainFeatures, selectedFeaturesDTO)
    for _, feature in ipairs(features) do
        local featureType = string.lower(feature.type or "")

        if "skill choice" == featureType and feature.data then
            -- Handle domain skill choices using direct search like class skills
            writeDebug("PROCESSDOMAIN:: Found skill choice feature [%s] with selected skills: %s", feature.name or "unnamed", json(feature.data.selected or {}))
            self:_convertDomainSkillChoice(feature, domainFeatures, selectedFeaturesDTO)

        elseif "multiple features" == featureType and feature.data and feature.data.features then
            -- Recursively process nested features
            self:_processDomainLevelFeatures(feature.data.features, domainFeatures, selectedFeaturesDTO)
        end
    end
end

--- Gets domain definition features like class features.
--- @private
--- @param domainName string The name of the domain
--- @return table domainFeatures The domain feature definition table or empty table on error
function FSCIAdapter:_getDomainFeatures(domainName)
    writeDebug("GETDOMAINFEATURES:: Getting features for domain [%s] from class definition", domainName)

    -- First, validate that the domain exists in DeityDomains table
    local domainGuid, domainItem = CTIEUtils.TableLookupFromName(DeityDomain.tableName, domainName)
    writeDebug("GETDOMAINFEATURES:: Domain validation for [%s]: GUID [%s]", domainName, domainGuid or "nil")

    if not domainGuid or not domainItem then
        writeLog(string.format("!!!! Could not resolve domain GUID for [%s], continuing with empty features", domainName), STATUS.WARN)
        return {}
    end

    -- Get the class definition (domain features are part of class, not domain)
    local className = self.fsData.class.name
    writeDebug("GETDOMAINFEATURES:: Getting class [%s] definition for domain [%s] features", className, domainName)

    local classGuid = CTIEUtils.ResolveLookupRecord(Class.tableName, className, "")
    if not classGuid or #classGuid == 0 then
        writeLog(string.format("!!!! Could not resolve class GUID for [%s], continuing with empty features", className), STATUS.WARN)
        return {}
    end

    local classTable = dmhub.GetTable(Class.tableName)
    if not classTable or not classTable[classGuid] then
        writeLog(string.format("!!!! Could not find class definition for GUID [%s], continuing with empty features", classGuid), STATUS.WARN)
        return {}
    end

    local classDefinition = classTable[classGuid]
    writeDebug("GETDOMAINFEATURES:: Found class definition for [%s]", className)

    -- Get class levels and search for domain-specific features
    local classLevels = {}
    classDefinition:FillLevelsUpTo(10, false, "nonprimary", classLevels)
    writeDebug("CONVERTDOMAINWITHCONTEXT:: GETDOMAINFEATURES:: FILL:: %s", json(classLevels))

    -- Filter class features to find domain-specific ones for the requested domain
    local domainFeatures = {}
    for levelNum, levelData in pairs(classLevels) do
        if levelData.features then
            writeDebug("CONVERTDOMAINWITHCONTEXT:: GETDOMAINFEATURES:: Searching class level [%d] with [%d] features for domain [%s]", levelNum, #levelData.features, domainName)

            local domainLevelFeatures = {}
            for i, feature in ipairs(levelData.features) do
                -- Look for features with names ending in "Domain Feature"
                local featureName = feature.name or ""
                writeDebug("CONVERTDOMAINWITHCONTEXT:: GETDOMAINFEATURES:: Checking feature [%s] for 'Domain Feature' pattern", featureName)

                if string.match(featureName, "Domain Feature$") then
                    writeDebug("CONVERTDOMAINWITHCONTEXT:: GETDOMAINFEATURES:: Found domain feature: [%s] at level [%d]", featureName, levelNum)

                    -- Look for nested features within this domain feature
                    if feature.features then
                        writeDebug("CONVERTDOMAINWITHCONTEXT:: GETDOMAINFEATURES:: Searching [%d] nested features in [%s] for domain [%s]", #feature.features, featureName, domainName)

                        for j, nestedFeature in ipairs(feature.features) do
                            local nestedFeatureName = nestedFeature.name or ""
                            local expectedDomainFeatureName = domainName .. " Domain"

                            writeDebug("CONVERTDOMAINWITHCONTEXT:: GETDOMAINFEATURES:: Checking nested feature [%s] against expected [%s]", nestedFeatureName, expectedDomainFeatureName)

                            -- Look for features named "[DomainName] Domain" (e.g., "War Domain")
                            if nestedFeatureName == expectedDomainFeatureName then
                                writeDebug("CONVERTDOMAINWITHCONTEXT:: GETDOMAINFEATURES:: MATCH! Found [%s] domain feature", domainName)

                                -- Process the features under this matching domain
                                if nestedFeature.features then
                                    writeDebug("CONVERTDOMAINWITHCONTEXT:: GETDOMAINFEATURES:: Processing [%d] features under [%s]", #nestedFeature.features, expectedDomainFeatureName)

                                    for k, domainSpecificFeature in ipairs(nestedFeature.features) do
                                        table.insert(domainLevelFeatures, domainSpecificFeature)
                                        writeDebug("CONVERTDOMAINWITHCONTEXT:: GETDOMAINFEATURES:: Added domain-specific feature: type=[%s] guid=[%s] name=[%s]",
                                                  domainSpecificFeature.typeName or "nil", domainSpecificFeature.guid or "nil", domainSpecificFeature.name or "nil")

                                        -- Log skill choice features specifically with their categories
                                        if domainSpecificFeature.typeName == "CharacterSkillChoice" then
                                            local categories = {}
                                            if domainSpecificFeature.categories then
                                                for cat, enabled in pairs(domainSpecificFeature.categories) do
                                                    if enabled and cat ~= "_luaTable" then
                                                        table.insert(categories, cat)
                                                    end
                                                end
                                            end
                                            writeDebug("CONVERTDOMAINWITHCONTEXT:: GETDOMAINFEATURES:: DOMAIN SKILLCHOICE L%d: guid=[%s] categories=[%s] for domain [%s]",
                                                      levelNum, domainSpecificFeature.guid, table.concat(categories, ","), domainName)
                                        end
                                    end
                                else
                                    writeDebug("CONVERTDOMAINWITHCONTEXT:: GETDOMAINFEATURES:: No features found under [%s]", expectedDomainFeatureName)
                                end
                            end
                        end
                    else
                        writeDebug("CONVERTDOMAINWITHCONTEXT:: GETDOMAINFEATURES:: No nested features found in domain feature [%s]", featureName)
                    end
                end
            end

            if #domainLevelFeatures > 0 then
                table.insert(domainFeatures, { level = levelNum, features = domainLevelFeatures })
                writeDebug("CONVERTDOMAINWITHCONTEXT:: GETDOMAINFEATURES:: Level [%d] has [%d] domain features, total levels with features: [%d]", levelNum, #domainLevelFeatures, #domainFeatures)
            end
        end
    end

    writeDebug("CONVERTDOMAINWITHCONTEXT:: GETDOMAINFEATURES:: LOADED:: [%d] [%s] [%s] %s", #domainFeatures, domainName, className, json(domainFeatures))
    return domainFeatures
end

--- Finds skill choice features in a domain definition (DEPRECATED - replaced by direct search).
--- @private
--- @param domainName string The name of the domain to search
--- @return table skillChoiceMap A mapping of category keys to feature GUIDs
function FSCIAdapter:_findDomainSkillChoiceFeatures(domainName)
    writeDebug("FINDDOMAINSKILLCHOICES:: Searching for skill choice features in domain [%s]", domainName)

    local skillChoiceMap = {}

    -- First, resolve the domain GUID (domains are stored as subclasses)
    local domainGuid = CTIEUtils.ResolveLookupRecord("subclasses", domainName, "")
    if not domainGuid or #domainGuid == 0 then
        writeLog(string.format("!!!! Could not resolve domain GUID for [%s], continuing with fallback", domainName), STATUS.WARN)
        return skillChoiceMap
    end

    -- Get the domain definition
    local subclassTable = dmhub.GetTable("subclasses")
    if not subclassTable or not subclassTable[domainGuid] then
        writeLog(string.format("!!!! Could not find domain definition for GUID [%s], continuing with fallback", domainGuid), STATUS.WARN)
        return skillChoiceMap
    end

    local domainDefinition = subclassTable[domainGuid]
    writeDebug("FINDDOMAINSKILLCHOICES:: Found domain definition for [%s]", domainName)

    -- Search through domain levels for skill choice features
    local domainLevels = {}
    domainDefinition:FillLevelsUpTo(10, false, "nonprimary", domainLevels)
    writeDebug("FINDDOMAINSKILLCHOICES:: FILL:: %s", json(domainLevels))

    for levelNum, levelData in pairs(domainLevels) do
        if levelData.features then
            for _, feature in pairs(levelData.features) do
                if feature.typeName == "CharacterSkillChoice" then
                    local categoryKey = self:_createCategoryKey(feature.categories)
                    skillChoiceMap[categoryKey] = feature.guid
                    writeDebug("FINDDOMAINSKILLCHOICES:: Found skill choice feature [%s] with categories [%s] at level [%d]", feature.guid, categoryKey, levelNum)
                end

                -- Also search nested features
                local nestedSkillChoices = self:_searchNestedSkillChoices(feature)
                for catKey, guid in pairs(nestedSkillChoices) do
                    skillChoiceMap[catKey] = guid
                end
            end
        end
    end

    local count = 0
    for _ in pairs(skillChoiceMap) do count = count + 1 end
    writeLog(string.format("Found %d skill choice features for domain [%s]", count, domainName), STATUS.INFO)
    return skillChoiceMap
end

--- Converts a domain skill choice with specific domain context.
--- @private
--- @param feature table The skill choice feature from Forge Steel
--- @param domainName string The specific domain name (e.g., "War", "Life")
--- @param selectedFeaturesDTO CTIESelectedFeaturesDTO The selected features DTO to populate
function FSCIAdapter:_convertDomainSkillChoiceWithContext(feature, domainName, selectedFeaturesDTO)
    if not feature.data or not domainName then
        writeDebug("CONVERTDOMAINWITHCONTEXT:: Missing feature data or domain name")
        return
    end

    local skillNames = feature.data.selected or {}
    writeDebug("CONVERTDOMAINWITHCONTEXT:: Processing skill choice [%s] with %d selected skills: %s in domain [%s]",
              feature.name or "unnamed", #skillNames, table.concat(skillNames, ", "), domainName)

    for _, skillName in ipairs(skillNames) do
        writeDebug("CONVERTDOMAINWITHCONTEXT:: Processing individual skill: [%s] in domain [%s]", skillName, domainName)
    end

    -- Get domain-specific features for the character's selected domain
    local domainFeatures = self:_getDomainFeatures(domainName)
    if not domainFeatures or #domainFeatures == 0 then
        writeDebug("CONVERTDOMAINWITHCONTEXT:: NODOMAINFEATURES:: %s", domainName)
        writeLog(string.format("!!!! Could not get domain features for [%s] (empty or nil result), discarding skill choice for skills: %s",
                              domainName, table.concat(skillNames, ", ")), STATUS.WARN)
        return
    end

    writeDebug("CONVERTDOMAINWITHCONTEXT:: Successfully retrieved [%d] domain levels for [%s]", #domainFeatures, domainName)

    -- Output each skill name with the levelFill JSON for debugging
    for _, skillName in ipairs(skillNames) do
        writeDebug("CONVERTDOMAINWITHCONTEXT:: %s %s", skillName, json(domainFeatures))
    end

    -- Convert Forge Steel listOptions to categories for matching
    local listOptions = feature.data.listOptions or {}
    local categories = self:_convertListOptionsToCategories(listOptions)

    -- Find matching domain skill choice feature GUID using domain-specific level fill search
    local choiceId = self:_findDomainSkillChoiceGuid(domainFeatures, listOptions, skillNames)
    writeDebug("CONVERTDOMAINWITHCONTEXT:: choiceId lookup result: [%s] for listOptions: %s and skills: %s in domain [%s]",
              tostring(choiceId), json(listOptions), table.concat(skillNames, ", "), domainName)

    if not choiceId then
        writeLog(string.format("!!!! Could not find domain skill choice feature for categories [%s] in domain [%s], discarding skill choice", categories, domainName), STATUS.WARN)
        return -- Discard this skill choice completely
    end

    -- Create skill lookup records
    local lookupRecords = {}
    for _, skillName in ipairs(feature.data.selected or {}) do
        writeDebug("CONVERTDOMAINWITHCONTEXT:: Creating lookup record for skill: [%s] in domain [%s]", skillName, domainName)
        writeLog(string.format("Found Domain Skill [%s] in import for domain [%s].", skillName, domainName), STATUS.INFO)
        local skillLookup = self:_createLookupRecord(Skill.tableName, skillName)
        table.insert(lookupRecords, skillLookup)
        writeDebug("CONVERTDOMAINWITHCONTEXT:: Added lookup record for skill [%s] to list (now %d records)", skillName, #lookupRecords)
    end

    -- Create selected feature with proper choiceId and categories
    writeDebug("CONVERTDOMAINWITHCONTEXT:: About to create DTO with %d lookupRecords for skills: %s in domain [%s]",
              #lookupRecords, table.concat(skillNames, ", "), domainName)
    if #lookupRecords > 0 then
        writeDebug("CONVERTDOMAINWITHCONTEXT:: Creating selectedFeature DTO with choiceId [%s] for skills: %s in domain [%s]",
                  choiceId, table.concat(skillNames, ", "), domainName)
        local selectedFeature = CTIESelectedFeatureDTO:new()
        selectedFeature:SetChoiceType("CharacterSkillChoice")
        selectedFeature:SetChoiceId(choiceId) -- Set the domain-specific GUID

        -- Set categories from listOptions
        local categories = self:_createCategoriesObject(listOptions)
        selectedFeature:SetCategories(categories)
        writeDebug("CONVERTDOMAINWITHCONTEXT:: Set categories: %s", json(categories))

        -- Add skill selections
        for _, lookupRecord in ipairs(lookupRecords) do
            selectedFeature:AddSelection(lookupRecord)
            writeDebug("CONVERTDOMAINWITHCONTEXT:: Added selection: table=[%s] name=[%s] id=[%s]",
                      lookupRecord:GetTableName(), lookupRecord:GetName(), lookupRecord:GetID())
        end

        selectedFeaturesDTO:AddFeature(selectedFeature)
        writeDebug("CONVERTDOMAINWITHCONTEXT:: Successfully added selectedFeature to DTO for skills: %s in domain [%s]",
                  table.concat(skillNames, ", "), domainName)

        writeLog(string.format("Created domain skill feature with choiceId [%s] and categories [%s] for skills: %s in domain [%s].",
                              choiceId, table.concat(listOptions, ","), table.concat(skillNames, ", "), domainName), STATUS.INFO)
    else
        writeLog(string.format("Skipping domain skill feature with no selections for categories [%s] in domain [%s].",
                              table.concat(listOptions, ","), domainName), STATUS.INFO)
    end
end

--- Converts a domain skill choice using direct feature search (like class skills).
--- @private
--- @param feature table The skill choice feature from Forge Steel
--- @param domainFeatures table Domain definition features to search for matching choiceIds
--- @param selectedFeaturesDTO CTIESelectedFeaturesDTO The selected features DTO to populate
function FSCIAdapter:_convertDomainSkillChoice(feature, domainFeatures, selectedFeaturesDTO)
    if not feature.data then
        return
    end

    writeDebug("CONVERTDOMAINSKILL:: Processing skill choice [%s] with %d selected skills", feature.name or "unnamed", #(feature.data.selected or {}))
    for _, skillName in ipairs(feature.data.selected or {}) do
        writeDebug("CONVERTDOMAINSKILL:: Selected skill: [%s]", skillName)
    end

    -- Convert Forge Steel listOptions to categories for matching
    local listOptions = feature.data.listOptions or {}
    local categories = self:_convertListOptionsToCategories(listOptions)

    -- Find matching domain skill choice feature GUID using direct search (like class skills)
    local choiceId = self:_findSkillChoiceInFeatures(domainFeatures, listOptions)
    if not choiceId then
        writeLog(string.format("!!!! Could not find domain skill choice feature for categories [%s], discarding skill choice", categories), STATUS.WARN)
        return -- Discard this skill choice completely
    end

    -- Create skill lookup records
    local lookupRecords = {}
    for _, skillName in ipairs(feature.data.selected or {}) do
        writeLog(string.format("Found Domain Skill [%s] in import.", skillName), STATUS.INFO)
        local skillLookup = self:_createLookupRecord(Skill.tableName, skillName)
        table.insert(lookupRecords, skillLookup)
    end

    -- Create selected feature with proper choiceId and categories
    if #lookupRecords > 0 or #listOptions > 0 then -- Include even if no selections but has categories
        local selectedFeature = CTIESelectedFeatureDTO:new()
        selectedFeature:SetChoiceType("CharacterSkillChoice")
        selectedFeature:SetChoiceId(choiceId) -- Set the real domain GUID

        -- Set categories from listOptions
        local categories = self:_createCategoriesObject(listOptions)
        selectedFeature:SetCategories(categories)

        -- Add skill selections
        for _, lookupRecord in ipairs(lookupRecords) do
            selectedFeature:AddSelection(lookupRecord)
        end

        selectedFeaturesDTO:AddFeature(selectedFeature)

        writeLog(string.format("Created domain skill feature with choiceId [%s] and categories [%s].", choiceId, categories), STATUS.INFO)
    end
end

--- Finds the deity choice feature GUID from the Codex class definition.
--- Searches through the class features to locate the CharacterDeityChoice feature.
--- Always returns a result (GUID or nil) and never stops processing.
--- @private
--- @param className string The name of the class to search
--- @return string|nil deityChoiceGuid The GUID of the deity choice feature, or nil if not found
function FSCIAdapter:_findDeityChoiceFeatureGuid(className)
    writeDebug("FINDDEITYFEATURE:: Searching for deity choice in class [%s]", className)

    -- First, resolve the class GUID
    local classGuid = CTIEUtils.ResolveLookupRecord(Class.tableName, className, "")
    if not classGuid or #classGuid == 0 then
        writeLog(string.format("!!!! Could not resolve class GUID for [%s], continuing with fallback", className), STATUS.WARN)
        return nil
    end

    -- Get the class definition
    local classTable = dmhub.GetTable(Class.tableName)
    if not classTable or not classTable[classGuid] then
        writeLog(string.format("!!!! Could not find class definition for GUID [%s], continuing with fallback", classGuid), STATUS.WARN)
        return nil
    end

    local classDefinition = classTable[classGuid]
    writeDebug("FINDDEITYFEATURE:: Found class definition for [%s]", className)

    -- Search through class levels for deity choice feature
    local classLevels = {}
    classDefinition:FillLevelsUpTo(10, false, "nonprimary", classLevels) -- Search up to level 10
    writeDebug("FINDDEITYFEATURE:: LEVELSFILL:: %s", json(classLevels))

    for levelNum, levelData in pairs(classLevels) do
        writeDebug("FINDDEITYFEATURE:: Checking level [%d]", levelNum)
        if levelData.features then
            for _, feature in pairs(levelData.features) do
                writeDebug("FINDDEITYFEATURE:: Checking feature [%s]", feature.typeName or "nil")
                if feature.typeName == "CharacterDeityChoice" then
                    writeDebug("FINDDEITYFEATURE:: Found deity choice feature [%s] at level [%d]", feature.guid, levelNum)
                    writeLog(string.format("Found deity choice feature for class [%s]", className), STATUS.INFO)
                    return feature.guid
                end

                -- Also search nested features recursively
                local nestedGuid = self:_searchNestedFeatures(feature, "CharacterDeityChoice")
                if nestedGuid then
                    writeDebug("FINDDEITYFEATURE:: Found nested deity choice feature [%s]", nestedGuid)
                    return nestedGuid
                end
            end
        end
    end

    writeLog(string.format("!!!! No deity choice feature found in class [%s], continuing with fallback", className), STATUS.WARN)
    return nil
end

--- Recursively searches nested features for a specific typeName.
--- Always returns safely and never stops processing.
--- @private
--- @param feature table The feature to search
--- @param targetTypeName string The typeName to look for
--- @return string|nil The GUID if found, nil otherwise
function FSCIAdapter:_searchNestedFeatures(feature, targetTypeName)
    writeDebug("FINDDEITYFEATURE:: SEARCHNESTEDFEATURES:: START::")
    if feature and feature.typeName == targetTypeName then
        writeDebug("FINDDEITYFEATURE:: SEARCHNESTEDFEATURES:: RETURN:: %s", feature.guid)
        return feature.guid
    end
    writeDebug("FINDDEITYFEATURE:: SEARCHNESTEDFEATURES:: STEP_2::")

    if feature and feature:try_get("features") then
        writeDebug("FINDDEITYFEATURE:: SEARCHNESTEDFEATURES:: STEP_3::")
        for _, nestedFeature in pairs(feature.features) do
            local nestedResult = self:_searchNestedFeatures(nestedFeature, targetTypeName)
            if nestedResult then
                return nestedResult
            end
        end
    else
        writeDebug("FINDDEITYFEATURE:: SEARCHNESTEDFEATURES:: No nested features.")
    end

    return nil
end

--- Finds skill choice features in the Codex class definition.
--- Searches for CharacterSkillChoice features and maps categories to GUIDs.
--- Always returns safely and never stops processing.
--- @private
--- @param className string The name of the class to search
--- @return table skillChoiceMap A mapping of category keys to feature GUIDs
function FSCIAdapter:_findSkillChoiceFeatures(className)
    writeDebug("FINDSKILLCHOICES:: Searching for skill choice features in class [%s]", className)

    local skillChoiceMap = {}

    -- First, resolve the class GUID
    local classGuid = CTIEUtils.ResolveLookupRecord(Class.tableName, className, "")
    if not classGuid or #classGuid == 0 then
        writeLog(string.format("!!!! Could not resolve class GUID for [%s], continuing with fallback", className), STATUS.WARN)
        return skillChoiceMap
    end

    -- Get the class definition
    local classTable = dmhub.GetTable(Class.tableName)
    if not classTable or not classTable[classGuid] then
        writeLog(string.format("!!!! Could not find class definition for GUID [%s], continuing with fallback", classGuid), STATUS.WARN)
        return skillChoiceMap
    end

    local classDefinition = classTable[classGuid]
    writeDebug("FINDSKILLCHOICES:: Found class definition for [%s]", className)

    -- Search through class levels for skill choice features
    local classLevels = {}
    classDefinition:FillLevelsUpTo(10, false, "nonprimary", classLevels) -- Search up to level 10

    for levelNum, levelData in pairs(classLevels) do
        if levelData.features then
            for _, feature in pairs(levelData.features) do
                if feature.typeName == "CharacterSkillChoice" then
                    -- Create category key from feature categories
                    local categoryKey = self:_createCategoryKey(feature.categories)
                    skillChoiceMap[categoryKey] = feature.guid
                    writeDebug("FINDSKILLCHOICES:: Found skill choice feature [%s] with categories [%s] at level [%d]", feature.guid, categoryKey, levelNum)
                end

                -- Also search nested features recursively
                local nestedSkillChoices = self:_searchNestedSkillChoices(feature)
                for catKey, guid in pairs(nestedSkillChoices) do
                    skillChoiceMap[catKey] = guid
                end
            end
        end
    end

    local count = 0
    for _ in pairs(skillChoiceMap) do count = count + 1 end
    writeLog(string.format("Found %d skill choice features for class [%s]", count, className), STATUS.INFO)
    return skillChoiceMap
end

--- Creates a category key from a Codex feature's categories table.
--- @private
--- @param categories table The categories table from a Codex feature
--- @return string categoryKey A sorted, comma-separated string of category names
function FSCIAdapter:_createCategoryKey(categories)
    if not categories then
        return ""
    end

    local categoryList = {}
    for category, isTrue in pairs(categories) do
        if isTrue and category ~= "_luaTable" then
            table.insert(categoryList, string.lower(category))
        end
    end

    table.sort(categoryList)
    return table.concat(categoryList, ",")
end

--- Recursively searches nested features for skill choice features.
--- @private
--- @param feature table The feature to search
--- @return table skillChoiceMap A mapping of category keys to feature GUIDs
function FSCIAdapter:_searchNestedSkillChoices(feature)
    local skillChoiceMap = {}

    if feature and feature.typeName == "CharacterSkillChoice" then
        local categoryKey = self:_createCategoryKey(feature.categories)
        skillChoiceMap[categoryKey] = feature.guid
    end

    if feature and feature.features then
        for _, nestedFeature in pairs(feature.features) do
            local nestedSkillChoices = self:_searchNestedSkillChoices(nestedFeature)
            for catKey, guid in pairs(nestedSkillChoices) do
                skillChoiceMap[catKey] = guid
            end
        end
    end

    return skillChoiceMap
end

--- Converts Forge Steel listOptions to a category key for matching.
--- @private
--- @param listOptions table Array of category names from Forge Steel
--- @return string categoryKey A sorted, comma-separated string of category names
function FSCIAdapter:_convertListOptionsToCategories(listOptions)
    if not listOptions then
        return ""
    end

    local categoryList = {}
    for _, option in ipairs(listOptions) do
        table.insert(categoryList, string.lower(option))
    end

    table.sort(categoryList)
    return table.concat(categoryList, ",")
end

--- Creates a categories object from Forge Steel listOptions.
--- @private
--- @param listOptions table Array of category names from Forge Steel
--- @return table categories A categories object like {interpersonal: true, lore: true}
function FSCIAdapter:_createCategoriesObject(listOptions)
    local categories = {}
    if listOptions then
        for _, option in ipairs(listOptions) do
            categories[string.lower(option)] = true
        end
    end
    return categories
end

--- Converts a class skill choice using Main.lua's direct feature search approach.
--- @private
--- @param feature table The skill choice feature from Forge Steel
--- @param selectedFeaturesDTO CTIESelectedFeaturesDTO The selected features DTO to populate
function FSCIAdapter:_convertClassSkillChoice(feature, selectedFeaturesDTO)
    if not feature.data then
        return
    end

    local skillNames = feature.data.selected or {}
    writeDebug("CONVERTCLASSSKILL:: Processing skill choice [%s] with %d selected skills: %s", feature.name or "unnamed", #skillNames, table.concat(skillNames, ", "))
    for _, skillName in ipairs(skillNames) do
        writeDebug("CONVERTCLASSSKILL:: Processing individual skill: [%s]", skillName)
    end

    -- Get class features the same way Main.lua does
    local className = self.fsData.class.name
    local classLevelsFill = self:_getClassFeatures(className)
    if not classLevelsFill then
        writeLog(string.format("!!!! Could not get class features for [%s], using fallback", className), STATUS.WARN)
        self:_convertSkillChoiceFallback(feature, selectedFeaturesDTO)
        return
    end

    -- Convert Forge Steel listOptions to categories for matching
    local listOptions = feature.data.listOptions or {}

    -- Find matching skill choice feature using Main.lua's approach
    local choiceId = self:_findSkillChoiceInFeatures(classLevelsFill, listOptions)
    writeDebug("CONVERTCLASSSKILL:: choiceId lookup result: [%s] for listOptions: %s and skills: %s", tostring(choiceId), json(listOptions), table.concat(skillNames, ", "))
    if not choiceId then
        writeLog(string.format("!!!! Could not find skill choice feature for categories [%s], discarding skill choice", table.concat(listOptions, ",")), STATUS.WARN)
        return -- Discard this skill choice completely
    end

    -- Create skill lookup records
    local lookupRecords = {}
    for _, skillName in ipairs(feature.data.selected or {}) do
        writeDebug("CONVERTCLASSSKILL:: Creating lookup record for skill: [%s]", skillName)
        writeLog(string.format("Found Class Skill [%s] in import.", skillName), STATUS.INFO)
        local skillLookup = self:_createLookupRecord(Skill.tableName, skillName)
        table.insert(lookupRecords, skillLookup)
        writeDebug("CONVERTCLASSSKILL:: Added lookup record for skill [%s] to list (now %d records)", skillName, #lookupRecords)
    end

    -- Create selected feature with proper choiceId and categories - ONLY if we have actual selections
    writeDebug("CONVERTCLASSSKILL:: About to create DTO with %d lookupRecords for skills: %s", #lookupRecords, table.concat(skillNames, ", "))
    if #lookupRecords > 0 then
        writeDebug("CONVERTCLASSSKILL:: Creating selectedFeature DTO with choiceId [%s] for skills: %s", choiceId, table.concat(skillNames, ", "))
        local selectedFeature = CTIESelectedFeatureDTO:new()
        selectedFeature:SetChoiceType("CharacterSkillChoice")
        selectedFeature:SetChoiceId(choiceId) -- Set the real GUID

        -- Set categories from listOptions
        local categories = self:_createCategoriesObject(listOptions)
        selectedFeature:SetCategories(categories)
        writeDebug("CONVERTCLASSSKILL:: Set categories: %s", json(categories))

        -- Add skill selections
        for _, lookupRecord in ipairs(lookupRecords) do
            selectedFeature:AddSelection(lookupRecord)
            writeDebug("CONVERTCLASSSKILL:: Added selection: table=[%s] name=[%s] id=[%s]",
                      lookupRecord:GetTableName(), lookupRecord:GetName(), lookupRecord:GetID())
        end

        selectedFeaturesDTO:AddFeature(selectedFeature)
        writeDebug("CONVERTCLASSSKILL:: Successfully added selectedFeature to DTO for skills: %s", table.concat(skillNames, ", "))

        writeLog(string.format("Created class skill feature with choiceId [%s] and categories [%s] for skills: %s.", choiceId, table.concat(listOptions, ","), table.concat(skillNames, ", ")), STATUS.INFO)
    else
        writeLog(string.format("Skipping class skill feature with no selections for categories [%s].", table.concat(listOptions, ",")), STATUS.INFO)
    end
end

--- Gets class features the same way Main.lua does.
--- @private
--- @param className string The name of the class
--- @return table|nil classLevelsFill The class features structure
function FSCIAdapter:_getClassFeatures(className)
    -- Resolve class GUID and get class info
    local classGuid = CTIEUtils.ResolveLookupRecord(Class.tableName, className, "")
    if not classGuid or #classGuid == 0 then
        return nil
    end

    local classTable = dmhub.GetTable(Class.tableName)
    if not classTable or not classTable[classGuid] then
        return nil
    end

    local classInfo = classTable[classGuid]
    local classLevel = self.fsData.class.level or 1

    -- Use the same call as Main.lua
    local classLevelsFill = {}
    classInfo:FillLevelsUpTo(classLevel, false, "nonprimary", classLevelsFill)

    return classLevelsFill
end

--- Recursively searches through nested features for skill choice features.
--- @private
--- @param features table Array of features to search through
--- @param listOptions table Array of category names from Forge Steel
--- @param searchPath string Debug path showing nesting level
--- @return string|nil choiceId The GUID of the matching skill choice feature
function FSCIAdapter:_searchNestedSkillChoices(features, listOptions, searchPath)
    for _, featureInfo in ipairs(features) do
        local currentPath = searchPath .. " -> " .. (featureInfo.name or featureInfo.guid or "unnamed")
        writeDebug("SEARCHNESTED:: Checking feature at path: %s, type: %s", currentPath, featureInfo.typeName or "no-type")

        if featureInfo.typeName == "CharacterSkillChoice" then
            writeDebug("SEARCHNESTED:: Found CharacterSkillChoice at path: %s with categories: %s", currentPath, json(featureInfo.categories))

            -- Check if categories match
            local matchesCategory = false
            if not listOptions or #listOptions == 0 then
                matchesCategory = true
            else
                for _, option in ipairs(listOptions) do
                    local categoryName = string.lower(option)
                    if featureInfo.categories and featureInfo.categories[categoryName] == true then
                        writeDebug("SEARCHNESTED:: MATCH FOUND for category [%s] at path: %s", categoryName, currentPath)
                        matchesCategory = true
                        break
                    end
                end
            end

            if matchesCategory then
                writeDebug("SEARCHNESTED:: Returning matching feature [%s] at path: %s", featureInfo.guid, currentPath)
                return featureInfo.guid
            end
        end

        -- Recursively search nested features
        local nestedFeatures = featureInfo:try_get("features")
        if nestedFeatures then
            writeDebug("SEARCHNESTED:: Recursing into nested features at path: %s", currentPath)
            local nestedResult = self:_searchNestedSkillChoices(nestedFeatures, listOptions, currentPath)
            if nestedResult then
                return nestedResult
            end
        end
    end

    return nil
end

--- Finds a domain skill choice GUID by searching through domain level fill structure.
--- @private
--- @param domainLevels table The domain level fill structure from FillLevelsUpTo
--- @param listOptions table Array of category names from Forge Steel
--- @param skillNames table Array of skill names being processed
--- @return string|nil choiceId The GUID of the matching domain skill choice feature
function FSCIAdapter:_findDomainSkillChoiceGuid(domainLevels, listOptions, skillNames)
    skillNames = skillNames or {}
    writeDebug("FINDDOMAINGUID:: Searching domain levels for skill choice with listOptions: %s", json(listOptions))

    for _, levelData in ipairs(domainLevels) do
        local levelNum = levelData.level
        -- Output the specific levelData being processed with skill names
        for _, skillName in ipairs(skillNames) do
            writeDebug("FINDDOMAINGUID:: %s %s", skillName, json(levelData))
        end

        if levelData.features then
            writeDebug("FINDDOMAINGUID:: Checking level %d with %d features", levelNum, #levelData.features)
            for _, feature in pairs(levelData.features) do
                if feature.typeName == "CharacterSkillChoice" then
                    writeDebug("FINDDOMAINGUID:: Found CharacterSkillChoice feature [%s] at level %d with categories: %s",
                              feature.guid or "no-guid", levelNum, json(feature.categories))

                    -- Check if categories match
                    local matchesCategory = false
                    if not listOptions or #listOptions == 0 then
                        matchesCategory = true
                    else
                        for _, option in ipairs(listOptions) do
                            local categoryName = string.lower(option)
                            writeDebug("FINDDOMAINGUID:: Checking if category [%s] matches feature categories", categoryName)
                            if feature.categories then
                                -- Handle both array format [exploration] and boolean table format {exploration: true}
                                local categoryMatch = false

                                -- Check if categories is an array
                                if type(feature.categories) == "table" and #feature.categories > 0 then
                                    for _, cat in ipairs(feature.categories) do
                                        if string.lower(cat) == categoryName then
                                            categoryMatch = true
                                            break
                                        end
                                    end
                                end

                                -- Also check boolean table format for backward compatibility
                                if not categoryMatch and feature.categories[categoryName] == true then
                                    categoryMatch = true
                                end

                                if categoryMatch then
                                    writeDebug("FINDDOMAINGUID:: MATCH FOUND for category [%s] in domain level %d", categoryName, levelNum)
                                    matchesCategory = true
                                    break
                                end
                            end
                        end
                    end

                    if matchesCategory then
                        writeDebug("FINDDOMAINGUID:: Returning matching domain feature [%s] for categories [%s]", feature.guid, table.concat(listOptions, ","))
                        return feature.guid
                    else
                        writeDebug("FINDDOMAINGUID:: No category match for domain feature [%s]", feature.guid or "no-guid")
                    end
                end

                -- Also search nested features recursively in domain features
                local nestedFeatures = feature:try_get("features")
                if nestedFeatures then
                    writeDebug("FINDDOMAINGUID:: Searching nested features for domain level %d feature [%s]", levelNum, feature.guid or "no-guid")
                    local nestedResult = self:_searchNestedSkillChoices(nestedFeatures, listOptions, string.format("DomainLevel%d", levelNum))
                    if nestedResult then
                        return nestedResult
                    end
                end
            end
        end
    end

    writeDebug("FINDDOMAINGUID:: NO MATCHING DOMAIN SKILL CHOICE FOUND for listOptions: %s", json(listOptions))
    return nil
end

--- Finds a skill choice feature in the feature list using Main.lua's logic with recursive search.
--- @private
--- @param classLevelsFill table The class features structure
--- @param listOptions table Array of category names from Forge Steel
--- @return string|nil choiceId The GUID of the matching skill choice feature
function FSCIAdapter:_findSkillChoiceInFeatures(classLevelsFill, listOptions)
    writeDebug("FINDSKILLCHOICE:: Searching for skill choice with listOptions: %s", json(listOptions))

    -- Mirror Main.lua's _setLevelChoice logic
    for levelNum, levelData in ipairs(classLevelsFill) do
        if levelData.features then
            for _, featureInfo in ipairs(levelData.features) do
                if featureInfo.typeName == "CharacterSkillChoice" then
                    writeDebug("FINDSKILLCHOICE:: Found CharacterSkillChoice feature [%s] at level %d with categories: %s",
                              featureInfo.guid or "no-guid", levelNum, json(featureInfo.categories))

                    -- Check if categories match - Main.lua checks each category individually
                    local matchesCategory = false
                    if not listOptions or #listOptions == 0 then
                        -- No specific categories required
                        matchesCategory = true
                    else
                        -- Check if any of the listOptions match the feature's categories
                        for _, option in ipairs(listOptions) do
                            local categoryName = string.lower(option)
                            writeDebug("FINDSKILLCHOICE:: Checking if category [%s] matches feature categories", categoryName)
                            if featureInfo.categories and featureInfo.categories[categoryName] == true then
                                writeDebug("FINDSKILLCHOICE:: MATCH FOUND for category [%s]", categoryName)
                                matchesCategory = true
                                break
                            end
                        end
                    end

                    if matchesCategory then
                        writeDebug("FINDSKILLCHOICE:: Found matching feature [%s] for categories [%s]", featureInfo.guid, table.concat(listOptions, ","))
                        return featureInfo.guid
                    else
                        writeDebug("FINDSKILLCHOICE:: No category match for feature [%s]", featureInfo.guid or "no-guid")
                    end
                end

                -- Search nested features recursively for ANY feature type
                local nestedFeatures = featureInfo:try_get("features")
                if nestedFeatures then
                    writeDebug("FINDSKILLCHOICE:: Searching nested features for level %d feature [%s]", levelNum, featureInfo.guid or "no-guid")
                    local nestedResult = self:_searchNestedSkillChoices(nestedFeatures, listOptions, string.format("Level%d", levelNum))
                    if nestedResult then
                        return nestedResult
                    end
                end
            end
        end
    end

    writeDebug("FINDSKILLCHOICE:: NO MATCHING SKILL CHOICE FOUND for listOptions: %s", json(listOptions))
    return nil
end


--- Adds a default deity entry when domains are selected.
--- @private
--- @param selectedFeaturesDTO CTIESelectedFeaturesDTO The selected features DTO to populate
--- @return CTIESelectedFeatureDTO deitySelectedFeature The created deity selected feature
function FSCIAdapter:_addDefaultDeity(selectedFeaturesDTO)
    local deitySelectedFeature = CTIESelectedFeatureDTO:new()
    deitySelectedFeature:SetChoiceType("CharacterDeityChoice")

    local deityLookup = CTIELookupTableDTO:new()
    deityLookup:SetTableName(Deity.tableName)
    deityLookup:SetName("All Domains")
    deityLookup:SetID("") -- No GUID available

    deitySelectedFeature:AddSelection(deityLookup)
    selectedFeaturesDTO:AddFeature(deitySelectedFeature)

    writeLog("Added default deity [All Domains] for domain selection.", STATUS.INFO)
    return deitySelectedFeature
end

--- Processes subclasses from class data.
--- @private
--- @param subclasses table The subclasses data
--- @param selectedFeaturesDTO CTIESelectedFeaturesDTO The selected features DTO to populate
function FSCIAdapter:_convertSubclasses(subclasses, selectedFeaturesDTO)
    for _, subclass in pairs(subclasses) do
        if subclass.selected then
            writeLog(string.format("Found selected Subclass [%s] in import.", subclass.name), STATUS.INFO)
            local subclassLookup = self:_createLookupRecord("subclasses", subclass.name)
            local selectedFeature = self:_createSelectedFeature({subclassLookup})
            if selectedFeature then
                selectedFeaturesDTO:AddFeature(selectedFeature)
            end
            
            -- Process subclass features from featuresByLevel
            if subclass.featuresByLevel then
                writeLog(string.format("Processing features for Subclass [%s].", subclass.name), STATUS.INFO, 1)
                self:_convertSubclassFeatures(subclass, selectedFeaturesDTO)
                writeLog(string.format("Subclass [%s] features complete.", subclass.name), STATUS.INFO, -1)
            end
        end
    end
end

--- Processes subclass features including skills with subclass-specific GUID lookup.
--- @private
--- @param subclass table The subclass data from Forge Steel
--- @param selectedFeaturesDTO CTIESelectedFeaturesDTO The selected features DTO to populate
function FSCIAdapter:_convertSubclassFeatures(subclass, selectedFeaturesDTO)
    if not subclass.featuresByLevel then
        return
    end

    -- Get subclass skill choice features
    local subclassSkillChoices = self:_findSubclassSkillChoiceFeatures(subclass.name)

    for _, levelFeature in ipairs(subclass.featuresByLevel) do
        if levelFeature.features then
            for _, feature in ipairs(levelFeature.features) do
                local featureType = string.lower(feature.type or "")

                if "skill choice" == featureType and feature.data then
                    -- Handle subclass skill choices with subclass-specific GUID lookup
                    self:_convertSubclassSkillChoice(feature, subclassSkillChoices, selectedFeaturesDTO)

                elseif "class ability" == featureType and feature.data and feature.data.selectedIDs then
                    -- Handle subclass abilities with selectedIDs
                    local lookupRecords = {}
                    for _, abilityId in ipairs(feature.data.selectedIDs) do
                        writeLog(string.format("Found Subclass Ability [%s] in import.", abilityId), STATUS.INFO)
                        local abilityLookup = CTIELookupTableDTO:new()
                        abilityLookup:SetTableName(CTIEUtils.FEATURE_TABLE_MARKER)
                        abilityLookup:SetName(abilityId) -- Using ID as name for now
                        abilityLookup:SetID("")
                        table.insert(lookupRecords, abilityLookup)
                    end

                    if #lookupRecords > 0 then
                        local selectedFeature = self:_createSelectedFeature(lookupRecords)
                        selectedFeaturesDTO:AddFeature(selectedFeature)
                    end

                elseif "choice" == featureType and feature.data and feature.data.selected then
                    -- Handle subclass choice features (like "Sentenced")
                    local lookupRecords = {}
                    for _, choice in ipairs(feature.data.selected) do
                        writeLog(string.format("Found Subclass Choice [%s] in import.", choice.name or "?"), STATUS.INFO)
                        local choiceLookup = CTIELookupTableDTO:new()
                        choiceLookup:SetTableName(CTIEUtils.FEATURE_TABLE_MARKER)
                        choiceLookup:SetName(translateFStoCodex(choice.name or ""))
                        choiceLookup:SetID("")
                        table.insert(lookupRecords, choiceLookup)
                    end

                    if #lookupRecords > 0 then
                        local selectedFeature = self:_createSelectedFeature(lookupRecords)
                        selectedFeaturesDTO:AddFeature(selectedFeature)
                    end
                end
            end
        end
    end
end

--- Finds skill choice features in a subclass definition.
--- @private
--- @param subclassName string The name of the subclass to search
--- @return table skillChoiceMap A mapping of category keys to feature GUIDs
function FSCIAdapter:_findSubclassSkillChoiceFeatures(subclassName)
    writeDebug("FINDSUBCLASSSKILLCHOICES:: Searching for skill choice features in subclass [%s]", subclassName)

    local skillChoiceMap = {}

    -- First, resolve the subclass GUID
    local subclassGuid = CTIEUtils.ResolveLookupRecord("subclasses", subclassName, "")
    if not subclassGuid or #subclassGuid == 0 then
        writeLog(string.format("!!!! Could not resolve subclass GUID for [%s], continuing with fallback", subclassName), STATUS.WARN)
        return skillChoiceMap
    end

    -- Get the subclass definition
    local subclassTable = dmhub.GetTable("subclasses")
    if not subclassTable or not subclassTable[subclassGuid] then
        writeLog(string.format("!!!! Could not find subclass definition for GUID [%s], continuing with fallback", subclassGuid), STATUS.WARN)
        return skillChoiceMap
    end

    local subclassDefinition = subclassTable[subclassGuid]
    writeDebug("FINDSUBCLASSSKILLCHOICES:: Found subclass definition for [%s]", subclassName)

    -- Search through subclass levels for skill choice features
    local subclassLevels = {}
    subclassDefinition:FillLevelsUpTo(10, false, "nonprimary", subclassLevels)

    for levelNum, levelData in pairs(subclassLevels) do
        if levelData.features then
            for _, feature in pairs(levelData.features) do
                if feature.typeName == "CharacterSkillChoice" then
                    local categoryKey = self:_createCategoryKey(feature.categories)
                    skillChoiceMap[categoryKey] = feature.guid
                    writeDebug("FINDSUBCLASSSKILLCHOICES:: Found skill choice feature [%s] with categories [%s] at level [%d]", feature.guid, categoryKey, levelNum)
                end

                -- Also search nested features
                local nestedFeatures = feature:try_get("features")
                if nestedFeatures then
                    local nestedSkillChoices = self:_searchNestedSkillChoices(nestedFeatures)
                    for catKey, guid in pairs(nestedSkillChoices) do
                        skillChoiceMap[catKey] = guid
                    end
                end
            end
        end
    end

    local count = 0
    for _ in pairs(skillChoiceMap) do count = count + 1 end
    writeLog(string.format("Found %d skill choice features for subclass [%s]", count, subclassName), STATUS.INFO)
    return skillChoiceMap
end

--- Converts a subclass skill choice using subclass-specific GUID lookup.
--- @private
--- @param feature table The skill choice feature from Forge Steel
--- @param subclassSkillChoices table The subclass skill choice features mapping
--- @param selectedFeaturesDTO CTIESelectedFeaturesDTO The selected features DTO to populate
function FSCIAdapter:_convertSubclassSkillChoice(feature, subclassSkillChoices, selectedFeaturesDTO)
    if not feature.data then
        return
    end

    -- Convert Forge Steel listOptions to category key for matching
    local listOptions = feature.data.listOptions or {}
    local categoryKey = self:_convertListOptionsToCategories(listOptions)

    -- Find matching subclass skill choice feature GUID
    local choiceId = subclassSkillChoices[categoryKey]
    if not choiceId then
        writeLog(string.format("!!!! Could not find subclass skill choice feature for categories [%s], discarding skill choice", categoryKey), STATUS.WARN)
        return -- Discard this skill choice completely
    end

    -- Create skill lookup records
    local lookupRecords = {}
    for _, skillName in ipairs(feature.data.selected or {}) do
        writeLog(string.format("Found Subclass Skill [%s] in import.", skillName), STATUS.INFO)
        local skillLookup = self:_createLookupRecord(Skill.tableName, skillName)
        table.insert(lookupRecords, skillLookup)
    end

    -- Create selected feature with proper choiceId and categories
    if #lookupRecords > 0 or #listOptions > 0 then
        local selectedFeature = CTIESelectedFeatureDTO:new()
        selectedFeature:SetChoiceType("CharacterSkillChoice")
        selectedFeature:SetChoiceId(choiceId) -- Set the real subclass GUID

        -- Set categories from listOptions
        local categories = self:_createCategoriesObject(listOptions)
        selectedFeature:SetCategories(categories)

        -- Add skill selections
        for _, lookupRecord in ipairs(lookupRecords) do
            selectedFeature:AddSelection(lookupRecord)
        end

        selectedFeaturesDTO:AddFeature(selectedFeature)

        writeLog(string.format("Created subclass skill feature with choiceId [%s] and categories [%s].", choiceId, categoryKey), STATUS.INFO)
    end
end

--- Converts Forge Steel kit data to CTIE format.
--- Extracts kit selections from class features and sets them in the kit DTO.
--- @private
function FSCIAdapter:_convertKits()
    writeDebug("CONVERTKITS:: START::")
    writeLog("Parsing Kits.", STATUS.INFO, 1)
    
    local kitDTO = self.codexDTO:Character():Kit()
    local kitCount = 0
    
    -- Look for kits in class features
    if self.fsData.class and self.fsData.class.featuresByLevel then
        for _, levelFeature in ipairs(self.fsData.class.featuresByLevel) do
            if levelFeature.features then
                for _, feature in ipairs(levelFeature.features) do
                    if string.lower(feature.type or "") == "kit" and feature.data and feature.data.selected then
                        for _, kit in ipairs(feature.data.selected) do
                            if kit and kit.name then
                                kitCount = kitCount + 1
                                writeLog(string.format("Found Kit [%s] in import.", kit.name), STATUS.INFO)
                                
                                local kitLookup = self:_createLookupRecord(Kit.tableName, kit.name)
                                
                                if kitCount == 1 then
                                    kitDTO:Kit1():SetTableName(kitLookup:GetTableName())
                                    kitDTO:Kit1():SetName(kitLookup:GetName())
                                    kitDTO:Kit1():SetID(kitLookup:GetID())
                                    writeLog(string.format("Set Kit 1 [%s].", kit.name), STATUS.IMPL)
                                elseif kitCount == 2 then
                                    kitDTO:Kit2():SetTableName(kitLookup:GetTableName())
                                    kitDTO:Kit2():SetName(kitLookup:GetName())
                                    kitDTO:Kit2():SetID(kitLookup:GetID())
                                    writeLog(string.format("Set Kit 2 [%s].", kit.name), STATUS.IMPL)
                                else
                                    writeLog(string.format("!!!! Too many kits (%d). Only 2 supported.", kitCount), STATUS.WARN)
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    
    if kitCount == 0 then
        writeLog("No kits found in import.", STATUS.INFO)
    end
    
    writeLog("Kits complete.", STATUS.INFO, -1)
    writeDebug("CONVERTKITS:: COMPLETE:: kit1=%s kit2=%s", kitDTO:Kit1():GetName() or "nil", kitDTO:Kit2():GetName() or "nil")
end