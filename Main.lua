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

local FSCI_VERBOSE = false
local FSCI_DEBUG = false
local FSCI_DEBUGHEADER = "FSCI::"

local FSCI_STATUS = { -- For logging to the import window via writeLog()
    INFO  = "#aaaaaa",
    ERROR = "#aa0000",
    IMPL  = "#00aaaa",
    GOOD  = "#00aa00",
    WARN  = "#ff8c00"
}

local FSCI_TRANSLATIONS = { -- Translate strings from Forge Steel into Codex values
    -- Ancestries
    ["Elf (high)"]              = "Elf, High",
    ["Elf (wode)"]              = "Elf, Wode",

    -- Ancestry Features
    ["Draconic Pride"]          = "Draconian Pride",
    ["Perseverence"]            = "Perseverance",
    ["Resist the Unnatural"]    = "Resist the Supernatural",

    -- Choice Types
    ["Elementalist Ward"]       = "Ward",

    -- CLasses & Subclasses
    ["Chronokinetic"]           = "Disciple of the Chronokinetic",
    ["Cryokinetic"]             = "Disciple of the Cryokinetic",
    ["Metakinetic"]             = "Disciple of the Metakinetic",

    -- Abilities
    ["Motivate Earth"]          = "Manipulate Earth",               -- Remove when Codex Data is fixed

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

local function writeDebug(s)
    if FSCI_DEBUG then
        print(FSCI_DEBUGHEADER, s)
    end
end

local function formatLogLine(msg, statusColor)
    return string.format("<color=%s>%s</color>", statusColor or FSCI_STATUS.INFO, msg)
end

local indentLevel = 0
local function writeLog(message, status, indent)
    indent = indent or 0
    status = status or FSCI_STATUS.INFO

    if FSCI_VERBOSE or status ~= FSCI_STATUS.INFO then
        if (indent < 0) then indentLevel = math.max(0, indentLevel + indent) end
        local indentedMessage = string.format("%s%s", string.rep(" ", 2 * math.max(0, indentLevel)), message)
        import:Log(formatLogLine(indentedMessage, status))
        if (indent > 0) then indentLevel = math.max(0, indentLevel + indent) end
    end
end

local function translateFStoCodex(fsString)
    return FSCI_TRANSLATIONS[fsString] or fsString
end

local function sanitizedStringsMatch(s1, s2)
    local function sanitize(s)
        s = s or ""
        return s:gsub("[^%w%s;:!@#%$%%^&*()%-+=%?,]", ""):trim()
    end

    local ns1 = string.lower(sanitize(translateFStoCodex(s1)))
    local ns2 = string.lower(sanitize(translateFStoCodex(s2)))

    return ns1 == ns2
end

local function appendToTable(t, k, v)
    t[k] = t[k] or {}
    table.insert(t[k], v)
end

local function minifyJson(jsonString)
    return jsonString:gsub('("[^"]-")|%s+', function(s)
        return s:match('^"') and s or ""  -- Keep quoted strings, remove other whitespace
    end)
end

--- Creates a new language entry in the Codex.
--
-- @param languageName The name of the language to be created.
-- @return The new language object's ID.
local function newLanguage(languageName, languageDescription)
    languageDescription = languageDescription or "Imported via Forge Steel Character Importer"
    writeLog(string.format("Creating new language [%s].", languageName), FSCI_STATUS.IMPL)
    local newLanguage = Language.CreateNew()
    newLanguage.name = languageName
    newLanguage.description = languageDescription
    dmhub.SetAndUploadTableItem(Language.tableName, newLanguage)
    return newLanguage.id
end

--- Retrieves an entry from a Codex table based on a given name.
-- This function searches for a matching entry by name, ensuring it is not hidden.
-- If a match is found, it returns the ID and the full entry object.
--
-- @param (string) tableName The name of the Codex table to search.
-- @param (string) name The name of the item to look up.
-- @return The ID of the found entry, or nil if not found.
-- @return The full entry object if found, or nil otherwise.
local function tableLookupFromName(tableName, name)

    local itemFound =  import:GetExistingItem(tableName, name)
    if itemFound then return itemFound.id, itemFound end

    writeLog(string.format("TLFN fallthrough table [%s]->[%s].", tableName, name), FSCI_STATUS.WARN)

    local t = dmhub.GetTable(tableName) or {}
    for id, row in pairs(t) do
        if not row:try_get("hidden", false) and sanitizedStringsMatch(row.name, name) then
            return id, row
        end
    end

    return nil, nil
end

--- Class representing the Forge Steel Character Importer.
-- This class is responsible for parsing JSON input, mapping it to Codex data,
-- and importing a character into the game system.
--
-- @classmod ThcForgeSteelCharacterImporter
local ThcForgeSteelCharacterImporter = {}
ThcForgeSteelCharacterImporter.__index = ThcForgeSteelCharacterImporter

--- Creates a new instance of the Forge Steel Character Importer.
-- This initializes the importer, parses the JSON input, and prepares
-- internal structures for character creation.
--
-- @constructor
-- @param importer The importer module handling the character import.
-- @param jsonText The raw JSON string representing the character data.
-- @return A new instance of `ThcForgeSteelCharacterImporter`.
function ThcForgeSteelCharacterImporter:new(importer, jsonText)
    local instance = {}
    setmetatable(instance, ThcForgeSteelCharacterImporter)

    instance.importer = importer
    instance.fsJson = jsonText
    instance.fsData = dmhub.FromJson(instance.fsJson).result
    instance.t = nil                    -- The Codex Token
    instance.c = nil                    -- The Codex Character; alias for t.properties
    instance.domainCount = 0

    return instance
end

--- Assigns or appends a value to a level-based choice feature in the character.
-- Searches through the provided features list for a match on type name and adds or replaces a selection.
--
-- @param self The `ThcForgeSteelCharacterImporter` instance.
-- @param typeName (string) The type name of the feature (e.g., `"CharacterSkillChoice"`).
-- @param category (string) The category of the skill; optional
-- @param featuresList (table) A list of level-based feature entries to search through.
-- @param newValue (any) The ID or value to assign as the selected option.
-- @param replace (boolean) Flag indicating whether to replace existing entries (`true`) or append (`false` or nil).
function ThcForgeSteelCharacterImporter:_setLevelChoice(typeName, category, featuresList, newValue, replace)
    category = category or ""
    replace = replace or false
    local foundLevelChoice = false

    writeDebug(string.format("SETLEVELCHOICE:: typeName [%s] category [%s] newValue [%s]", typeName, category, newValue))

    for _, featureInfo in ipairs(featuresList) do
        if featureInfo.typeName == typeName then
            if category == "" or (featureInfo.categories and featureInfo.categories[category:lower()] == true) then
                writeDebug(string.format("SETLEVELCHOICE:: SETTING typeName [%s] category [%s]", typeName, category))
                if replace then
                    self.c:GetLevelChoices()[featureInfo.guid] = newValue
                else
                    appendToTable(self.c:GetLevelChoices(), featureInfo.guid, newValue)
                end
                foundLevelChoice = true
                break
            end
        end
    end

    return foundLevelChoice
end

--- Sets a class-level choice for the character based on the provided type.
-- Iterates through class level details to find and set the specified choice.
--
-- @param typeName (string) The type of choice to set.
-- @param classLevelsFill (table) The data structure containing class-level details.
-- @param newValue (string|number) The value to assign to the specified choice.
-- @param replace (boolean) Optional; indicates if the existing value should be replaced. Default is false.
function ThcForgeSteelCharacterImporter:_setClassLevelChoice(typeName, category, classLevelsFill, newValue, replace)
    replace = replace or false
    local foundLevelChoice = false

    writeDebug(string.format("SETCLASSLEVELCHOICE:: typeName [%s], newValue [%s]", typeName, newValue))

    for _, levelDetails in ipairs(classLevelsFill) do
        if levelDetails ~= nil then
            foundLevelChoice = self:_setLevelChoice(typeName, category, levelDetails.features, newValue, replace)
        end
        if foundLevelChoice then
            break
        end
    end
end

--- Processes and imports languages from provided input data.
-- Looks up each language by name in the Codex, creates a new entry if necessary,
-- and stores each language using the provided storage function.
--
-- @param languages (table) A list of language names to process.
-- @param storageFn (function) A function used to store language IDs after processing.
function ThcForgeSteelCharacterImporter:_processLanguages(languages, storageFn)

    writeDebug("PROCESSLANGUAGES:: " .. json(languages))
    for _, languageName in ipairs(languages) do
        writeLog(string.format("Found Language [%s] in input.", languageName), FSCI_STATUS.INFO)
        local languageId = tableLookupFromName(Language.tableName, languageName)
        if languageId == nil then
            languageId = newLanguage(languageName)
        end
        if languageId ~= nil then
            writeLog(string.format("Adding language [%s] to character.", languageName), FSCI_STATUS.IMPL)
            storageFn(languageId)
        else
            writeLog(string.format("!!!! Language [%s] not found in Codex and can't create.", languageName), FSCI_STATUS.WARN)
        end
    end

end

--- Processes skills from imported data and assigns them to the character.
-- Iterates through each provided skill, looks up its ID in the Codex,
-- and uses a provided function to store the skill choice.
--
-- @param skillNames (table) List of skill names to process.
-- @param codexFill (table) Codex data structure containing skill options.
-- @param storageFn (function) Function to apply the skill choice to the character.
function ThcForgeSteelCharacterImporter:_processSkills(skillNames, codexFill, storageFn, category)
    for _, skillName in pairs(skillNames) do
        writeLog(string.format("Found Skill [%s] in import.", skillName), FSCI_STATUS.INFO, 1)
        local skillId = tableLookupFromName(Skill.tableName, skillName)
        if skillId ~= nil then
            writeLog(string.format("Adding Skill [%s] to character.", skillName), FSCI_STATUS.IMPL)
            storageFn(self, "CharacterSkillChoice", category, codexFill, skillId)
        else
            writeLog(string.format("!!!! Skill [%s] not found in Codex.", skillName), FSCI_STATUS.WARN)
        end
        writeLog(string.format("Skill [%s] complete.", skillName), FSCI_STATUS.INFO, -1)
    end
end

--- Maps imported features and abilities to Codex entries and adds them to the character.
-- Handles abilities, skills, and kits from the import data, matching each item to corresponding entries in the Codex.
--
-- @param importFeatures (table) List of features from imported character data.
-- @param importAbilities (table) List of abilities from imported character data.
-- @param codexFill (table) Codex data structure with potential feature and ability matches.
function ThcForgeSteelCharacterImporter:_processImportListToCodexList(importFeatures, importAbilities, codexFill)
    importFeatures = importFeatures or {}
    importAbilities = importAbilities or {}

    local function processImportAbility(findId)
        for _, ability in pairs(importAbilities) do
            if ability.id == findId then
                writeLog(string.format("Found Ability [%s] in import.", ability.name), FSCI_STATUS.INFO, 1)
                -- We found an Ability Name in the JSON that we now need to find in the level info
                -- It will be in a CharacterFeature within a CharacterFeatureChoice node
                for _, levelDetails in ipairs(codexFill) do
                    if levelDetails ~= nil then
                        for _, featureInfo in ipairs(levelDetails.features) do
                            if featureInfo.typeName == "CharacterFeatureChoice" then
                                for _, characterFeature in pairs(featureInfo.options) do
                                    writeDebug(string.format("IMPORT2CODEX:: [%s] ?= [%s]", characterFeature.name, ability.name))
                                    if sanitizedStringsMatch(characterFeature.name, ability.name) then
                                        writeLog(string.format("Adding Class Ability [%s] to character.", ability.name), FSCI_STATUS.IMPL)
                                        appendToTable(self.c:GetLevelChoices(), featureInfo.guid, characterFeature.guid)
                                        break
                                    end
                                end
                            end
                        end
                    end
                end

                writeLog(string.format("Ability [%s] complete.", ability.name), FSCI_STATUS.INFO, -1)
                break
            end
        end
    end

    local function processImportChoice(importFeature)
        local foundChoice = false
        for _, selectedItem in ipairs(importFeature.data.selected) do
            writeLog(string.format("Found [%s] Choice [%s] in import.", importFeature.name, selectedItem.name))
            for _, levelDetails in ipairs(codexFill) do
                if levelDetails ~= nil then
                    for _, featureInfo in ipairs(levelDetails.features) do
                        if featureInfo.typeName == "CharacterFeatureChoice" and sanitizedStringsMatch(featureInfo.name, importFeature.name) then
                            for _,option in ipairs(featureInfo.options) do
                                if option.typeName == "CharacterFeature" and sanitizedStringsMatch(option.name, selectedItem.name) then
                                    writeLog(string.format("Adding [%s] Choice [%s] to character.", importFeature.name, selectedItem.name), FSCI_STATUS.IMPL)
                                    appendToTable(self.c:GetLevelChoices(), featureInfo.guid, option.guid)
                                    foundChoice = true
                                    break
                                end
                            end
                            if foundChoice then break end
                        end
                    end
                    if foundChoice then break end
                end
            end
            if not foundChoice then
                writeLog(string.format("!!!! [%s] Choice [%s] not found in Codex.", importFeature.name, selectedItem.name), FSCI_STATUS.WARN)
            end
        end
    end

    local function processImportKit(kits)
        local kitCount = 0
        for _, kit in ipairs(kits) do
            if kit ~= nil then
                local kitName = kit.name or ""
                if kitName then
                    writeLog(string.format("Kit [%s] found in import.", kitName), FSCI_STATUS.INFO, 1)
                    local kitId = tableLookupFromName(Kit.tableName, kitName)
                    if kitId ~= nil then
                        kitCount = kitCount + 1
                        if kitCount == 1 then
                            writeLog(string.format("Adding Kit [%s] to character as Kit 1.", kitName), FSCI_STATUS.IMPL)
                            local k = self.c:get_or_add("kitid", kitId)
                            k = kitId
                        elseif kitCount == 2 then
                            writeLog(string.format("Adding Kit [%s] to character as Kit 2.", kitName), FSCI_STATUS.IMPL)
                            local k = self.c:get_or_add("kitid2", kitId)
                            k = kitId
                        else
                            writeLog(string.format("!!!! Found too many kits (%d).", kitCount), FSCI_STATUS.WARN)
                        end
                    end
                    writeLog(string.format("Kit [%s] complete.", kitName), FSCI_STATUS.INFO, -1)
                end
            end
        end
    end

    for _, features in ipairs(importFeatures) do
        for _, feature in ipairs(features.features) do
            if string.lower(feature.type) == "class ability" then
                for _,id in ipairs(feature.data.selectedIDs) do
                    processImportAbility(id)
                end
            elseif string.lower(feature.type) == "skill choice" then
                self:_processSkills(feature.data.selected, codexFill, self._setClassLevelChoice)
            elseif string.lower(feature.type) == "kit" then
                processImportKit(feature.data.selected)
            elseif string.lower(feature.type) == "choice" then
                if feature.data and feature.data.selected and #feature.data.selected > 0 then
                    feature.name = translateFStoCodex(feature.name)
                    writeDebug("CHOICE:: [%s] [%s]", feature.id, feature.name)
                    writeDebug("CHOICE:: [%s] -> [%s]", feature.name, feature.data.selected[1].name)
                    processImportChoice(feature)
                end
            end
        end
    end
end

--- Extracts characteristic attribute values from imported class data.
-- Parses the character's Might, Agility, Reason, Intuition, and Presence values from the imported JSON data.
-- If a characteristic isn't found, it defaults to 0.
--
-- @return (number, number, number, number, number)
--         The extracted values for Might, Agility, Reason, Intuition, and Presence.
function ThcForgeSteelCharacterImporter:_extractCharacteristics()

    if not self.fsData.class or not self.fsData.class.characteristics then
        writeLog("!!!! class.characteristics not found in import.", FSCI_STATUS.WARN)
        return 0, 0, 0, 0, 0, 0
    end

    local charMap = {
        Might = "m",
        Agility = "a",
        Reason = "r",
        Intuition = "i",
        Presence = "p"
    }

    local values = { m = 0, a = 0, r = 0, i = 0, p = 0 }

    for _, entry in ipairs(self.fsData.class.characteristics) do
        local key = charMap[entry.characteristic]
        if key then values[key] = entry.value end
    end

    return values.m, values.a, values.r, values.i, values.p
end

--- Sets the character's attributes based on extracted characteristic values.
-- Retrieves characteristic values from the imported data and applies them to the character's attributes in Codex.
--
-- @see _extractCharacteristics
function ThcForgeSteelCharacterImporter:_setAttributes()
    local attrs = self.c:get_or_add("attributes", {})
    local m, a, r, i, p = self:_extractCharacteristics()
    writeLog(string.format("Setting Attributes M %+d A %+d R %+d I %+d P %+d.", m, a, r, i, p), FSCI_STATUS.IMPL)
    attrs.mgt.baseValue = m
    attrs.agl.baseValue = a
    attrs.rea.baseValue = r
    attrs.inu.baseValue = i
    attrs.prs.baseValue = p
end

--- Processes ancestry (race) features and assigns them to the character.
-- Matches selected ancestry features from imported data to Codex features and applies them to the character's level choices.
--
-- @param raceFill (table) Codex ancestry data containing possible ancestry feature options.
function ThcForgeSteelCharacterImporter:_processAncestryFeatures(raceFill)

    if not self.fsData.ancestry.features then
        writeLog("!!!! Ancestry Features not found in import.", FSCI_STATUS.WARN)
        return
    end

    local function processRaceFeatureChoice(selected)
        -- The logic here is a little different than most.
        -- We need to find the choices within the raceFill
        -- instead of finding them in a table.
        local function mapFSOptionToCodex(choice)
            local s = choice.name or ""
            if string.lower(choice.name) == "damage modifier" then
                s = string.match(choice.description, "^(.*Immunity)")
            else
                s = translateFStoCodex(choice.name)
            end
            return s
        end

        for _, choice in ipairs(selected) do

            local choiceName = mapFSOptionToCodex(choice)

            writeLog(string.format("Found Ancestry Feature [%s]->[%s] in import.", choice.name, choiceName), FSCI_STATUS.INFO, 1)
            writeDebug(string.format("PROCESSRACEFEATURES:: [%s]", choiceName))

            local foundFeature = false
            for _, feature in pairs(raceFill.features) do
                writeDebug(string.format("PROCESSRACEFEATURES:: FEATURE [%s]", feature.name))
                if feature.typeName == "CharacterFeatureChoice" then
                    local levelChoiceGuid = feature.guid
                    for _, option in pairs(feature.options) do
                        writeDebug(string.format("PROCESSRACEFEATURES:: OPTION [%s] VS [%s]: %s", option.name, choiceName, sanitizedStringsMatch(option.name, choiceName)))
                        if sanitizedStringsMatch(option.name, choiceName) then
                            writeLog(string.format("Adding Ancestry Feature [%s] to character.", choiceName), FSCI_STATUS.IMPL)
                            appendToTable(self.c:GetLevelChoices(), levelChoiceGuid, option.guid)
                            foundFeature = true
                            break
                        end
                    end
                    if foundFeature then
                        break
                    end
                end
            end

            writeLog(string.format("Ancestry Feature [%s] complete.", choice.name), FSCI_STATUS.INFO, -1)
        end
    end

    local function processRaceFeaturesList(features)
        for _, feature in ipairs(features) do
            if string.lower(feature.type) == "choice" then
                processRaceFeatureChoice(feature.data.selected)
            elseif string.lower(feature.type) == "skill choice" then
                writeDebug("ANCESTRYFEATURES:: SKILLCHOICE::", json(feature.data.selected))
                self:_processSkills(feature.data.selected, raceFill.features, self._setLevelChoice)
            elseif string.lower(feature.type) == "multiple features" then
                writeDebug("ANCESTRYFEATURES:: MULTIPLEFEATURES")
                processRaceFeaturesList(feature.data.features)
            end
        end
    end

    processRaceFeaturesList(self.fsData.ancestry.features)

end

--- Sets the character's ancestry (race) based on imported data.
-- Looks up the ancestry by name in Codex, applies it to the character,
-- and processes associated ancestry features.
--
-- @see _processAncestryFeatures
function ThcForgeSteelCharacterImporter:_setAncestry()

    if not self.fsData.ancestry then
        writeLog("!!!! Ancestry not found in import.", FSCI_STATUS.WARN)
        return
    end

    local raceInfo = self.fsData.ancestry

    writeLog(string.format("Ancestry [%s] found in import.", raceInfo.name), FSCI_STATUS.INFO, 1)

    local raceId, raceItem = tableLookupFromName(Race.tableName, translateFStoCodex(raceInfo.name))
    if raceId == nil then
        writeLog(string.format("!!!! Ancestry [%s] not found in Codex.", raceInfo.name), FSCI_STATUS.WARN, -1)
        return
    end
    writeLog(string.format("Applying Ancestry [%s] to character.", raceItem.name), FSCI_STATUS.IMPL)
    local r = self.c:get_or_add("raceid", raceId)
    r = raceId

    local raceFill = raceItem:GetClassLevel()
    writeDebug("RACEFILL:: " .. json(raceFill))
    self:_processAncestryFeatures(raceFill)
    writeLog("Ancestry complete.", FSCI_STATUS.INFO, -1)
end

--- Sets the character's cultural details based on imported data.
-- Processes cultural aspects including languages, environment, organization, and upbringing,
-- and applies these choices to the character.
--
-- @see _processLanguages
function ThcForgeSteelCharacterImporter:_setCulture()

    if not self.fsData.culture then
        writeLog("!!!! Culture not found in import.", FSCI_STATUS.WARN)
        return
    end

    -- Culture is a 4-part extract: language list at the root,
    -- environment, organization, and upbringing.

    local culture = self.fsData.culture
    local aspects = self.c:get_or_add("culture", Culture.CreateNew()).aspects
    local caFill

    local function processCultureChoices(inputAspect, caItem)
        caFill = caItem:GetClassLevel()
        writeDebug("CULTUREFILL:: " .. string.upper(inputAspect.name) .. " " .. json(caFill))
        if inputAspect.type == "Skill Choice" then
            self:_processSkills(inputAspect.data.selected, caFill.features, self._setLevelChoice)
        end
    end

    local function processCultureAspect(aspectName)
        writeLog(string.format("Processing Culture Aspect [%s]", aspectName), FSCI_STATUS.INFO, 1)
        local caId, caItem = tableLookupFromName(CultureAspect.tableName, culture[aspectName].name)
        aspects[aspectName] = caId
        processCultureChoices(culture[aspectName], caItem)
        writeLog(string.format("Culture Aspect [%s] complete.", aspectName), FSCI_STATUS.INFO, -1)
    end

    local function storeCultureLanguage(languageId)
        writeDebug(string.format("STORECULTURELANGUAGE:: [%s]", languageId))
        appendToTable(self.c:GetLevelChoices(), "cultureLanguageChoice", languageId)
    end

    writeLog("Processing Culture.", FSCI_STATUS.INFO, 1)

    self:_processLanguages(culture.languages, storeCultureLanguage)
    processCultureAspect("environment")
    processCultureAspect("organization")
    processCultureAspect("upbringing")

    writeLog("Culture complete.", FSCI_STATUS.INFO, -1)
end

--- Processes inciting incidents from imported career data.
-- Finds the selected incident from imported options and adds it as a note to the character.
--
-- @param careerItem (table) The Codex career item containing incident characteristics data.
function ThcForgeSteelCharacterImporter:_processIncitingIncidents(careerItem)

    if not self.fsData.career or not self.fsData.career.incitingIncidents then
        writeLog("!!! Inciting Incidents not found in import.", FSCI_STATUS.WARN)
        return
    end

    local incitingIncidents = self.fsData.career.incitingIncidents

    if incitingIncidents.selectedID == nil then
        writeLog("!!! Selected Inciting Incident not found in import.", FSCI_STATUS.WARN)
        return
    end

    local function incidentNamesMatch(needle, haystack)
        local s = haystack:match("^%*%*:?(.-):?%*%*")
        return sanitizedStringsMatch(needle, s)
    end

    local selectedId = incitingIncidents.selectedID
    for _, option in ipairs(incitingIncidents.options) do
        if string.lower(option.id) == string.lower(selectedId) then
            writeLog(string.format("Found Inciting Incident [%s] in import.", option.name))

            -- Dig the table ID GUID out of the careerItem object
            local foundMatch = false
            for _, characteristic in pairs(careerItem.characteristics) do
                writeDebug(string.format("INCITINGINCIDENT:: CHARACTERISTIC type [%s] table [%s]", characteristic.typeName, characteristic.tableid))
                if characteristic.typeName == "BackgroundCharacteristic" and characteristic.tableid ~= nil then
                    local characteristicsTable = dmhub.GetTable(BackgroundCharacteristic.characteristicsTable)
                    for _, row in pairs(characteristicsTable[characteristic.tableid].rows) do
                        writeDebug(string.format("INCITINGINCIDENT:: row[%s]", row.value.items[1].value))
                        if incidentNamesMatch(option.name, row.value.items[1].value) then
                            writeLog(string.format("Adding Inciting Incident [%s] to character.", option.name), FSCI_STATUS.IMPL)

                            local item = row.value.items[1]
                            local note = {}
                            note.text = item.value
                            note.title = "Inciting Incident"
                            note.rowid = row.id
                            note.tableid = characteristic.tableid

                            local notes = self.c:get_or_add("notes", {})
                            notes[#notes + 1] = note

                            foundMatch = true
                            break
                        end
                    end
                    if foundMatch then break end
                end
            end
            break
        end
    end
end

--- Processes career-related features from imported data and applies them to the character.
-- Handles languages, perks, and skills by matching imported choices to Codex entries.
--
-- @param careerFill (table) Codex career data containing available feature options.
function ThcForgeSteelCharacterImporter:_processCareerFeatures(careerFill)
    if not self.fsData.career or not self.fsData.career.features then
        writeLog("!!!! career features not found in import.", FSCI_STATUS.WARN)
        return
    end

    local careerFeatures = self.fsData.career.features

    local function storeCareerLanguage(languageId)
        self:_setLevelChoice("CharacterLanguageChoice", "", careerFill.features, languageId)
    end

    local function processCareerPerk(perks)
        for _, perk in ipairs(perks) do
            writeLog(string.format("Found Perk [%s] in import.", perk.name))
            local perkId = tableLookupFromName("feats", perk.name)
            if perkId ~= nil then
                writeLog(string.format("Adding Perk [%s] to character.", perk.name), FSCI_STATUS.IMPL)
                self:_setLevelChoice("CharacterFeatChoice", "", careerFill.features, perkId)
            else
                writeLog(string.format("!!!! Perk [%s] not found in Codex.", perk.name), FSCI_STATUS.WARN)
            end
        end
    end

    for _, feature in ipairs(careerFeatures) do
        if string.lower(feature.type) == "language choice" then
            self:_processLanguages(feature.data.selected, storeCareerLanguage)
        elseif string.lower(feature.type) == "perk" then
            processCareerPerk(feature.data.selected)
        elseif string.lower(feature.type) == "skill choice" then
            self:_processSkills(feature.data.selected, careerFill.features, self._setLevelChoice, feature.name:match("^(%S+)"))
        end
    end
end

--- Sets the character's career (background) based on imported data.
-- Finds the matching career entry in the Codex and applies it to the character.
-- Also processes associated inciting incidents and career features.
--
-- @see _processIncitingIncidents
-- @see _processCareerFeatures
function ThcForgeSteelCharacterImporter:_setCareer()
    -- DS Careers use the Background object - holdover from DMHub

    if not self.fsData.career then
        writeLog("!!!! Career not found in import.", FSCI_STATUS.WARN)
        return
    end

    local selectedCareer = self.fsData.career

    writeLog(string.format("Found Career [%s] in import.", selectedCareer.name), FSCI_STATUS.INFO, 1)

    local careerId, careerItem = tableLookupFromName(Background.tableName, selectedCareer.name)
    if careerId == nil then
        writeLog(string.format("!!!! Career [%s] not found in Codex.", selectedCareer.name), FSCI_STATUS.WARN)
        return
    end

    local cid = self.c:get_or_add("backgroundid", careerId)
    cid = careerId

    self:_processIncitingIncidents(careerItem)

    local careerFill = careerItem:GetClassLevel()
    writeDebug("CAREERFILL:: " .. json(careerFill))

    self:_processCareerFeatures(careerFill)

    writeLog("Career complete.", FSCI_STATUS.INFO, -1)
end

--- Adds a subclass to the character based on imported subclass data.
-- Finds the subclass in the Codex, applies it to the character, and processes associated subclass features.
--
-- @param subclassInfo (table) Information about the selected subclass from imported data.
-- @param classLevelsFill (table) Codex data structure containing class-level details.
function ThcForgeSteelCharacterImporter:_addSubclass(subclassInfo, classLevelsFill)

    writeLog(string.format("Found Subclass [%s] in import.", subclassInfo.name))

    -- Find the subclass GUID in the game table
    local subclassId, subclassItem = tableLookupFromName("subclasses", subclassInfo.name)
    if subclassId == nil then
        writeLog(string.format("!!!! Subclass [%s] not found in Codex.", subclassInfo.name), FSCI_STATUS.WARN)
        return
    end

    -- Set the subclass into the character
    writeLog(string.format("Adding Subclass [%s] to character.", subclassInfo.name), FSCI_STATUS.IMPL)
    self:_setClassLevelChoice("CharacterSubclassChoice", "", classLevelsFill, subclassId, false)

    local subclassLevelsFill = {}
    subclassItem:FillLevelsUpTo(self.fsData.class.level, false, "nonprimary", subclassLevelsFill)
    writeDebug("SUBCLASSLEVELSFILL:: " .. json(subclassLevelsFill))

    writeLog("Processing Subclass.", FSCI_STATUS.INFO, 1)
    self:_processImportListToCodexList(subclassInfo.featuresByLevel, self.fsData.class.abilities, subclassLevelsFill)
    writeLog("Processing Subclass complete.", FSCI_STATUS.INFO, -1)
end

--- Adds a domain (subclass specialization) to the character from imported data.
-- Finds the specified domain in the Codex, assigns it to the appropriate character choice, and processes domain features.
--
-- @param domainInfo (table) Information about the selected domain from imported data.
-- @param classLevelsFill (table) Codex data structure containing class-level details.
function ThcForgeSteelCharacterImporter:_addDomain(domainInfo, classLevelsFill)

    writeLog(string.format("Found Domain [%s] in import.", domainInfo.name))

    local domainId, domainItem = tableLookupFromName("subclasses", domainInfo.name)
    if domainId == nil then
        writeLog(string.format("!!!! Domain [%s] not found in Codex.", domainInfo.name), FSCI_STATUS.WARN)
        return
    end

    self.domainCount = self.domainCount + 1
    writeDebug(string.format("ADDDOMAIN:: Adding Domain%d [%s] [%s] to character.", self.domainCount, domainItem.name, domainItem.id))
    writeLog(string.format("Adding Domain%d [%s] to character.", self.domainCount, domainItem.name), FSCI_STATUS.IMPL)

    local searchKey = ""    
    if self.domainCount == 1 then
        searchKey = "First Divine Domain"
    elseif self.domainCount == 2 then
        searchKey = "Second Divine Domain"
    else
        writeLog("Too many domains!", FSCI_STATUS.WARN)
        return
    end

    local foundLevelChoice = false
    for _, levelDetails in ipairs(classLevelsFill) do
        if levelDetails ~= nil then
            for _, featureInfo in ipairs(levelDetails.features) do
                if featureInfo.typeName == "CharacterSubclassChoice" and featureInfo.name == searchKey then
                    -- We found the match in the Codex list
                    appendToTable(self.c:GetLevelChoices(), featureInfo.guid, domainItem.id)

                    local subclassLevelsFill = {}
                    domainItem:FillLevelsUpTo(self.fsData.class.level, false, "nonprimary", subclassLevelsFill)
                    writeDebug("ADDDOMAIN:: SUBCLASSLEVELSFILL " .. json(subclassLevelsFill))

                    writeLog("Processing Domain.", FSCI_STATUS.INFO, 1)
                    self:_processImportListToCodexList(domainInfo.featuresByLevel, self.fsData.class.abilities, subclassLevelsFill)
                    writeLog("Processing Domain complete.", FSCI_STATUS.INFO, -1)

                    foundLevelChoice = true
                    break
                end
            end            
        end
        if foundLevelChoice then break end
    end

end

--- Processes all subclasses and domains selected in the imported class data.
-- Iterates over imported subclass and domain selections, adding each to the character and processing associated features.
--
-- @param classLevelsFill (table) Codex data structure containing class-level details for subclass/domain assignment.
function ThcForgeSteelCharacterImporter:_processSubclasses(classLevelsFill)

    writeLog("Processing Subclasses.", FSCI_STATUS.INFO, 1)

    -- Find the subclasses selected in the JSON
    if self.fsData.class and self.fsData.class.subclasses then 
        local selectedSubclass
        for _, subclassInfo in pairs(self.fsData.class.subclasses) do
            if subclassInfo.selected then
                self:_addSubclass(subclassInfo, classLevelsFill)
            end
        end
    else
        writeLog("!!!! Subclasses not found in import.", FSCI_STATUS.WARN)
    end

    -- Find the domains selected in the JSON
    if self.fsData.class and self.fsData.class.featuresByLevel then
        for _, levelFeature in ipairs(self.fsData.class.featuresByLevel) do
            if levelFeature.features then
                for _, feature in pairs(levelFeature.features) do
                    if string.lower(feature.name) == "domain" then
                        for _, domainInfo in pairs(feature.data.selected) do
                            writeLog(string.format("Domain [%s] found.", domainInfo.name))
                            -- Translate it into the Codex's name
                            domainInfo.name = domainInfo.name .. " Domain"
                            self:_addDomain(domainInfo, classLevelsFill)
                        end
                    end
                end
            end
        end
    end

    writeLog("Processing Subclasses complete.", FSCI_STATUS.INFO, -1)

end

--- Sets the character's class based on imported data.
-- Finds and assigns the class in the Codex, processes subclasses, domains, and related class features.
--
-- @see _processSubclasses
function ThcForgeSteelCharacterImporter:_setClass()

    local className = self.fsData.class.name
    local classLevel = self.fsData.class.level

    writeLog(string.format("Found Class [%s] in import.", className), FSCI_STATUS.INFO, 1)

    local classId, classInfo = tableLookupFromName(Class.tableName, className)
    if classId ~= nil and classInfo ~= nil then
        writeLog(string.format("Adding Class [%s] to character.", className), FSCI_STATUS.IMPL)
        local classes = self.c:get_or_add("classes", {})
        classes[#classes + 1] = {
            classid = classId,
            level = classLevel
        }
    else
        writeLog(string.format("!!!! Class [%s] not found in Codex.", className), FSCI_STATUS.WARN)
        return
    end

    local classLevelsFill = {}
    classInfo:FillLevelsUpTo(classLevel, false, "nonprimary", classLevelsFill)
    writeDebug("CLASSLEVELSFILL:: " .. json(classLevelsFill))

    self:_processSubclasses(classLevelsFill)

    writeLog("Processing Class Features.", FSCI_STATUS.INFO, 1)
    self:_processImportListToCodexList(self.fsData.class.featuresByLevel, self.fsData.class.abilities, classLevelsFill)
    writeLog("Processing Class Features complete.", FSCI_STATUS.INFO, -1)

    writeLog(string.format("Class [%s] complete.", className), FSCI_STATUS.INFO, -1)
end

--- Stores the original imported JSON character data into the character record.
-- Saves the imported character data in minified JSON form for reference or debugging purposes.
function ThcForgeSteelCharacterImporter:_setImport()
    if not FSCI_DEBUG then
        writeLog("Setting Import.", FSCI_STATUS.IMPL)
        local i = self.c:get_or_add("import", {})
        i.type = "mcdm"
        i.data = minifyJson(self.fsJson)
    end
end

--- Initiates the full character import process.
-- Creates a new character instance from imported Forge Steel JSON data,
-- setting attributes, ancestry, culture, career, class, and related features.
-- Finalizes by adding the character to the game system.
--
-- @see _setAttributes
-- @see _setAncestry
-- @see _setCulture
-- @see _setCareer
-- @see _setClass
-- @see _setImport
function ThcForgeSteelCharacterImporter:ImportToon()

    writeLog("Forge Steel Character Import starting.", FSCI_STATUS.INFO, 1)

    self.t = import:CreateCharacter()
    self.t.properties = character.CreateNew {}
    self.t.partyId = GetDefaultPartyID()
    self.t.name = self.fsData.name

    writeLog(string.format("Character Name is [%s].", self.t.name), FSCI_STATUS.IMPL)

    self.c = self.t.properties

    self:_setAttributes()
    self:_setAncestry()
    self:_setCulture()
    self:_setCareer()
    self:_setClass()
    self:_setImport()

    -- Create it in the game
    import:ImportCharacter(self.t)

    writeLog("Forge Steel Character Import complete.", FSCI_STATUS.INFO, -1)

end

Commands.fsci = function(args)
    if args and #args then
        if string.find(args:lower(), "d") then FSCI_DEBUG = not FSCI_DEBUG end
        if string.find(args:lower(), "v") then FSCI_VERBOSE = not FSCI_VERBOSE end
    end
    SendTitledChatMessage(string.format("<color=#00cccc>[d]ebug:</color> %s <color=#00cccc>[v]erbose:</color> %s", FSCI_DEBUG, FSCI_VERBOSE), "fsci", "#e09c9c")
end

import.Register {
    id = "thcfscijson",
    description = "Forge Steel Character (JSON)",
    input = "plaintext",
    priority = 200,

    text = function(importer, text)
        fsci = ThcForgeSteelCharacterImporter:new(importer, text)
        fsci:ImportToon()
    end
}
