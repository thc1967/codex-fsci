--- FSCIImporter handles importing a Forge Steel character into the Codex.
--- @class FSCIImporter
--- @field fsJson string The raw Forge Steel JSON string
--- @field fsData table The parsed Forge Steel data structure
--- @field token table The Codex token representing the new character
--- @field character table The Codex character object - alias for token.character
FSCIImporter = RegisterGameType("FSCIImporter")
FSCIImporter.__index = FSCIImporter

local tableLookupFromName = FSCIUtils.TableLookupFromName
local writeDebug = FSCIUtils.writeDebug
local writeLog = FSCIUtils.writeLog
local STATUS = FSCIUtils.STATUS

--- Creates a new FSCIImporter instance for importing a Forge Steel character into the Codex.
--- @param jsonText string The JSON string from Forge Steel character export
--- @return FSCIImporter|nil instance The new adapter instance if valid, nil if parsing fails
function FSCIImporter:new(jsonText)
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

    -- We don't need this and it can be big.
    parsedData.picture = nil

    local instance = setmetatable({}, self)
    instance.fsJson = jsonText
    instance.fsData = parsedData
    instance.token = {}
    instance.character = {}
    return instance
end

--- Orchestrates the complete character import process
--- Imports token information, character data, and submits to VTT
function FSCIImporter:Import()
    writeDebug("FSCIIMPORTER:: IMPORT:: START::")
    writeLog("Import starting.")

    self:_importTokenInfo()
    self:_importCharacterInfo()

    import:ImportCharacter(self.token)

    writeLog("Import complete.")
    writeDebug("FSCIIMPORTER:: IMPORT:: COMPLETE::")
end

--- Creates and populates the basic token structure for the new character
--- Initializes token properties and assigns to default party
--- @private
function FSCIImporter:_importTokenInfo()
    writeDebug("FSCIIMPORTER:: IMPORTTOKEN:: START::")
    writeLog("Import Token starting.", STATUS.INFO, 1)

    self.token = import:CreateCharacter()
    self.token.properties = character.CreateNew()
    self.token.partyId = GetDefaultPartyID()
    self.token.name = self.fsData.name
    writeLog(string.format("Character Name is [%s].", self.token.name), STATUS.IMPL)

    writeLog("Import Token complete.", STATUS.INFO, -1)
    writeDebug("FSCIIMPORTER:: IMPORTTOKEN:: COMPLETE::")
end

--- Coordinates all character data imports
--- Processes attributes, ancestry, culture, career, class, and complication
--- @private
function FSCIImporter:_importCharacterInfo()
    writeDebug("IMPORTCHARACTER:: START::")
    writeLog("Import Character starting.", STATUS.INFO, 1)

    self.character = self.token.properties

    self:_importAttributes()
    self:_importAncestry()
    self:_importCulture()
    self:_importCareer()
    self:_importClass()
    self:_importComplication()
    self:_setImport()

    writeLog("Import Character complete.", STATUS.INFO, -1)
    writeDebug("IMPORTCHARACTER:: COMPLETE::")
end

--- Imports character attributes from Forge Steel characteristics
--- Maps Forge Steel characteristic names to Codex attribute short names
--- @private
function FSCIImporter:_importAttributes()
    writeDebug("IMPORTATTRIBUTES:: START::")
    writeLog("Import Attributes starting.", STATUS.INFO, 1)

    if self.fsData and self.fsData.class and self.fsData.class.characteristics then
        local attrs = self.character:get_or_add("attributes", {})

        local attributeMapping = {
            Might = "mgt",
            Agility = "agl",
            Reason = "rea",
            Intuition = "inu",
            Presence = "prs"
        }

        -- Initialize all attributes with default values
        for _, shortName in pairs(attributeMapping) do
            if not attrs[shortName] then
                attrs[shortName] = {
                    baseValue = 0
                }
            end
        end

        -- Set values from characteristics array
        for _, entry in ipairs(self.fsData.class.characteristics) do
            local shortName = attributeMapping[entry.characteristic]
            if shortName then
                attrs[shortName].baseValue = entry.value
            end
        end
        writeLog(string.format("Setting Attributes M %+d A %+d R %+d I %+d P %+d.", attrs.mgt.baseValue, attrs.agl.baseValue, attrs.rea.baseValue, attrs.inu.baseValue, attrs.prs.baseValue), STATUS.IMPL)
    else
        writeLog("!!!! Attributes not found in import.", STATUS.WARN)
    end

    writeLog("Import Attributes complete.", STATUS.INFO, -1)
    writeDebug("IMPORTATTRIBUTES:: COMPLETE::")
end

--- Imports character ancestry and processes ancestry feature choices
--- Maps Forge Steel ancestry to Codex race and imports selected features
--- @private
function FSCIImporter:_importAncestry()
    writeDebug("IMPORTANCESTRY:: START::")
    writeLog("Import Ancestry starting.", STATUS.INFO, 1)

    if self.fsData.ancestry then
        local ancestryName = self.fsData.ancestry.name  
        writeLog(string.format("Ancestry [%s] found in import.", ancestryName))
        local codexRaceId, codexRaceItem = tableLookupFromName(Race.tableName, ancestryName)
        if codexRaceId and codexRaceItem then
            writeLog(string.format("Setting Ancestry to [%s].", codexRaceItem:try_get("name")), STATUS.IMPL)
            local r = self.character:get_or_add("raceid", codexRaceId)
            r = codexRaceId

            if self.fsData.ancestry.features then
                local codexFill = codexRaceItem:GetClassLevel()
                print("FSCI:: RACEFILL::", codexFill)
                writeDebug("RACEFILL:: %s", json(codexFill))
                if codexFill then
                    local choiceImporter = FSCIChoiceImporter:new(codexFill.features)
                    if choiceImporter then
                        local levelChoices = choiceImporter:Process(self.fsData.ancestry.features)
                        writeDebug("RACEFILL:: RESULTS:: %s", json(levelChoices))
                        FSCIUtils.MergeTables(self.character:GetLevelChoices(), levelChoices)
                    end
                end
            else
                writeLog("No ancestry choices to process.", STATUS.INFO)
            end
        else
            writeLog(string.format("!!!! Ancestry [%s] not found in Codex.", ancestryName))
        end
    else
        writeLog("!!!! Ancestry not found in import!", STATUS.WARN)
    end

    writeLog("Import Ancestry complete.", STATUS.INFO, -1)
    writeDebug("IMPORTANCESTRY:: COMPLETE::")
end

--- Imports character career (background) and processes career feature choices
--- Maps Forge Steel career to Codex background and triggers inciting incident import
--- @private
function FSCIImporter:_importCareer()
    writeDebug("IMPORTCAREER:: START::")
    writeLog("Import Career starting.", STATUS.INFO, 1)

    if self.fsData.career then
        local fsCareer = self.fsData.career
        writeLog(string.format("Found Career [%s] in import.", fsCareer.name))
        local careerId, careerItem = tableLookupFromName(Background.tableName, fsCareer.name)
        if careerId and careerItem then
            writeLog(string.format("Setting Career to [%s].", fsCareer.name), STATUS.IMPL)
            local backgroundId = self.character:get_or_add("backgroundid", careerId)
            backgroundId = careerId

            if fsCareer.features then
                local careerFill = careerItem:GetClassLevel()
                writeDebug("CAREERFILL:: %s", json(careerFill))
                if careerFill then
                    local choiceImporter = FSCIChoiceImporter:new(careerFill.features)
                    if choiceImporter then
                        local levelChoices = choiceImporter:Process(fsCareer.features)
                        FSCIUtils.MergeTables(self.character:GetLevelChoices(), levelChoices)
                    end
                end
            else
                writeLog("No Career Features found.")
            end

            self:_importIncitingIncident(careerItem)
        else
            writeLog(string.format("!!!! Career [%s] not found in Codex!", fsCareer.name), STATUS.WARN)
        end
    else
        writeLog("!!!! Career not found in import.", STATUS.WARN)
    end

    writeLog("Import Career complete.", STATUS.INFO, -1)
    writeDebug("IMPORTCAREER:: COMPLETE::")
end

--- Delegates class import to FSCIClassImporter
--- Handles all class-related data including levels, abilities, and kits
--- @private
function FSCIImporter:_importClass()
    if self.fsData.class then
        local classImporter = FSCIClassImporter:new(self.fsData.class, self.character)
        classImporter:Import()
    else
        writeLog("!!!! Class information not found in import!", STATUS.WARN)
    end
end

--- Imports character complication
--- Maps Forge Steel complication to Codex complication
--- @private
function FSCIImporter:_importComplication()
    writeDebug("IMPORTCOMPLICATION:: START::")
    writeDebug("Import Complication starting.", STATUS.INFO, 1)

    if self.fsData.complication and self.fsData.complication.name then
        local complicationId = tableLookupFromName(CharacterComplication.tableName, self.fsData.complication.name)
        if complicationId then
            writeLog(string.format("Adding Complication [%s].", self.fsData.complication.name), STATUS.IMPL)
            local c = self.character:get_or_add("complicationid", complicationId)
            c = complicationId
        end
    end

    writeDebug("Import Complication complete.", STATUS.INFO, -1)
    writeDebug("IMPORTCOMPLICATION:: COMPLETE::")
end

--- Imports character culture including languages and three culture aspects
--- Processes environment, organization, and upbringing aspects with their feature choices
--- @private
function FSCIImporter:_importCulture()
    writeDebug("IMPORTCULTURE:: START::")
    writeLog("Import Culture starting.", STATUS.INFO, 1)

    if self.fsData.culture then
        local fsCulture = self.fsData.culture

        if fsCulture.language then
            fsCulture.languages = fsCulture.language.data.selected
        end
        if fsCulture.languages then
            for _, language in pairs(fsCulture.languages) do
                writeLog(string.format("Found Language [%s] in import.", language))
                local languageId = tableLookupFromName(Language.tableName, language)
                if languageId then
                    writeLog(string.format("Adding language [%s].", language), STATUS.IMPL)
                    FSCIUtils.AppendToTable(self.character:GetLevelChoices(), "cultureLanguageChoice", languageId)
                else
                    writeLog(string.format("!!!! Language [%s] not found in Codex!", language), STATUS.WARN)
                end
            end
        end

        local aspectNames = { "environment", "organization", "upbringing" }
        local codexCulture = self.character:get_or_add("culture", Culture.CreateNew())
        local codexAspects = codexCulture:get_or_add("aspects")

        for _, aspectName in pairs(aspectNames) do
            if fsCulture[aspectName] then
                local fsCultureSelection = fsCulture[aspectName].name
                writeLog(string.format("Culture Aspect [%s]->[%s] starting.", aspectName, fsCultureSelection), STATUS.INFO, 1)
                local caId, caItem = tableLookupFromName(CultureAspect.tableName, fsCultureSelection)
                if caId and caItem then
                    writeLog(string.format("Adding Culture Aspect [%s]->[%s]", aspectName, fsCultureSelection), STATUS.IMPL)
                    codexAspects[aspectName] = caId
                    if fsCulture[aspectName].data and fsCulture[aspectName].data.selected then
                        local caFill = caItem:GetClassLevel()
                        if caFill then
                            local choiceImporter = FSCIChoiceImporter:new(caFill.features)
                            if choiceImporter then
                                local levelChoices = choiceImporter:Process({fsCulture[aspectName]})
                                FSCIUtils.MergeTables(self.character:GetLevelChoices(), levelChoices)
                            end
                        end
                    else
                        writeLog(string.format("!!!! No features for Culture Aspect [%s]->[%s] in import!", aspectName, fsCultureSelection), STATUS.WARN)
                    end
                else
                    writeLog(string.format("!!!! Culture Aspect [%s]->[%s] not found in Codex!", aspectName, fsCultureSelection), STATUS.WARN)
                end
                writeLog(string.format("Culture Aspect [%s] complete.", aspectName), STATUS.INFO, -1)
            else
                writeLog(string.format("!!!! Culture Aspect [%s] not in import!", aspectName), STATUS.WARN)
            end
        end
    else
        writeLog("!!!! Culture not found in import!", STATUS.WARN)
    end

    writeLog("Import Culture complete.", STATUS.INFO, -1)
    writeDebug("IMPORTCULTURE:: COMPLETE::")
end

--- Imports the inciting incident from career data
--- Searches career characteristics table for matching incident and adds as character note
--- @param careerItem table The Codex career (background) item containing characteristics
--- @private
function FSCIImporter:_importIncitingIncident(careerItem)
    writeDebug("IMPORTINCITINGINCIDENT:: START::")

    local function incidentNamesMatch(needle, haystack)
        local s = haystack:match("^%*%*:?(.-):?%*%*")
        return FSCIUtils.SanitizedStringsMatch(needle, s)
    end

    if self.fsData.career and self.fsData.career.incitingIncidents and self.fsData.career.incitingIncidents.selected and self.fsData.career.incitingIncidents.selected.name then
        local incidentName = self.fsData.career.incitingIncidents.selected.name
        writeLog(string.format("Found Inciting Incident [%s] in import.", incidentName))

        local foundMatch = false
        for _, characteristic in pairs(careerItem.characteristics) do
            writeDebug(string.format("IMPORTINCITINGINCIDENT:: CHARACTERISTIC type [%s] table [%s]", characteristic.typeName, characteristic.tableid))
            if characteristic.typeName == "BackgroundCharacteristic" and characteristic.tableid ~= nil then
                local characteristicsTable = dmhub.GetTable(BackgroundCharacteristic.characteristicsTable)
                for _, row in pairs(characteristicsTable[characteristic.tableid].rows) do
                    writeDebug(string.format("IMPORTINCITINGINCIDENT:: row[%s]", row.value.items[1].value))
                    if incidentNamesMatch(incidentName, row.value.items[1].value) then
                        writeLog(string.format("Adding Inciting Incident [%s] to character.", incidentName), STATUS.IMPL)

                        local item = row.value.items[1]
                        local note = {}
                        note.text = item.value
                        note.title = "Inciting Incident"
                        note.rowid = row.id
                        note.tableid = characteristic.tableid

                        local notes = self.character:get_or_add("notes", {})
                        notes[#notes + 1] = note

                        foundMatch = true
                        break
                    end
                end
                if foundMatch then break end
            end
        end
    else
        writeLog("!!!! Inciting Incident not found in import!", STATUS.WARN)
    end

    writeDebug("IMPORTINCITINGINCIDENT:: COMPELTE::")
end

--- Stores the original import JSON in the character for future reference
--- Skipped in debug mode to avoid polluting test data
--- @private
function FSCIImporter:_setImport()
    if not FSCIUtils.inDebugMode() then
        writeLog("Setting Import.", STATUS.IMPL)
        local i = self.character:get_or_add("import", {})
        i.type = "mcdm"
        i.data = self.fsJson
    end
end
