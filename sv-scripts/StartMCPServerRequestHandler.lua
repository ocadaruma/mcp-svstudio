POLL_INTERVAL = 500
COMMAND_FILE = "/tmp/mcp-svstudio-command.json"
STATE_FILE = "/tmp/mcp-svstudio-state.txt"
RESPONSE_FILE = "/tmp/mcp-svstudio-command-response.json"

-- JSON library --
-- Taken from https://gist.github.com/tylerneylon/59f4bcf316be525b30ab --

local json = {}


-- Internal functions.

local function kind_of(obj)
    if type(obj) ~= 'table' then return type(obj) end
    local i = 1
    for _ in pairs(obj) do
        if obj[i] ~= nil then i = i + 1 else return 'table' end
    end
    if i == 1 then return 'table' else return 'array' end
end

local function escape_str(s)
    local in_char  = {'\\', '"', '/', '\b', '\f', '\n', '\r', '\t'}
    local out_char = {'\\', '"', '/',  'b',  'f',  'n',  'r',  't'}
    for i, c in ipairs(in_char) do
        s = s:gsub(c, '\\' .. out_char[i])
    end
    return s
end

-- Returns pos, did_find; there are two cases:
-- 1. Delimiter found: pos = pos after leading space + delim; did_find = true.
-- 2. Delimiter not found: pos = pos after leading space;     did_find = false.
-- This throws an error if err_if_missing is true and the delim is not found.
local function skip_delim(str, pos, delim, err_if_missing)
    pos = pos + #str:match('^%s*', pos)
    if str:sub(pos, pos) ~= delim then
        if err_if_missing then
            error('Expected ' .. delim .. ' near position ' .. pos)
        end
        return pos, false
    end
    return pos + 1, true
end

-- Expects the given pos to be the first character after the opening quote.
-- Returns val, pos; the returned pos is after the closing quote character.
local function parse_str_val(str, pos, val)
    val = val or ''
    local early_end_error = 'End of input found while parsing string.'
    if pos > #str then error(early_end_error) end
    local c = str:sub(pos, pos)
    if c == '"'  then return val, pos + 1 end
    if c ~= '\\' then return parse_str_val(str, pos + 1, val .. c) end
    -- We must have a \ character.
    local esc_map = {b = '\b', f = '\f', n = '\n', r = '\r', t = '\t'}
    local nextc = str:sub(pos + 1, pos + 1)
    if not nextc then error(early_end_error) end
    return parse_str_val(str, pos + 2, val .. (esc_map[nextc] or nextc))
end

-- Returns val, pos; the returned pos is after the number's final character.
local function parse_num_val(str, pos)
    local num_str = str:match('^-?%d+%.?%d*[eE]?[+-]?%d*', pos)
    local val = tonumber(num_str)
    if not val then error('Error parsing number at position ' .. pos .. '.') end
    return val, pos + #num_str
end


-- Public values and functions.

function json.stringify(obj, as_key)
    local s = {}  -- We'll build the string as an array of strings to be concatenated.
    local kind = kind_of(obj)  -- This is 'array' if it's an array or type(obj) otherwise.
    if kind == 'array' then
        if as_key then error('Can\'t encode array as key.') end
        s[#s + 1] = '['
        for i, val in ipairs(obj) do
            if i > 1 then s[#s + 1] = ', ' end
            s[#s + 1] = json.stringify(val)
        end
        s[#s + 1] = ']'
    elseif kind == 'table' then
        if as_key then error('Can\'t encode table as key.') end
        s[#s + 1] = '{'
        for k, v in pairs(obj) do
            if #s > 1 then s[#s + 1] = ', ' end
            s[#s + 1] = json.stringify(k, true)
            s[#s + 1] = ':'
            s[#s + 1] = json.stringify(v)
        end
        s[#s + 1] = '}'
    elseif kind == 'string' then
        return '"' .. escape_str(obj) .. '"'
    elseif kind == 'number' then
        if as_key then return '"' .. tostring(obj) .. '"' end
        return tostring(obj)
    elseif kind == 'boolean' then
        return tostring(obj)
    elseif kind == 'nil' then
        return 'null'
    else
        error('Unjsonifiable type: ' .. kind .. '.')
    end
    return table.concat(s)
end

json.null = {}  -- This is a one-off table to represent the null value.

function json.parse(str, pos, end_delim)
    pos = pos or 1
    if pos > #str then error('Reached unexpected end of input.') end
    local pos = pos + #str:match('^%s*', pos)  -- Skip whitespace.
    local first = str:sub(pos, pos)
    if first == '{' then  -- Parse an object.
        local obj, key, delim_found = {}, true, true
        pos = pos + 1
        while true do
            key, pos = json.parse(str, pos, '}')
            if key == nil then return obj, pos end
            if not delim_found then error('Comma missing between object items.') end
            pos = skip_delim(str, pos, ':', true)  -- true -> error if missing.
            obj[key], pos = json.parse(str, pos)
            pos, delim_found = skip_delim(str, pos, ',')
        end
    elseif first == '[' then  -- Parse an array.
        local arr, val, delim_found = {}, true, true
        pos = pos + 1
        while true do
            val, pos = json.parse(str, pos, ']')
            if val == nil then return arr, pos end
            if not delim_found then error('Comma missing between array items.') end
            arr[#arr + 1] = val
            pos, delim_found = skip_delim(str, pos, ',')
        end
    elseif first == '"' then  -- Parse a string.
        return parse_str_val(str, pos + 1)
    elseif first == '-' or first:match('%d') then  -- Parse a number.
        return parse_num_val(str, pos)
    elseif first == end_delim then  -- End of an object or array.
        return nil, pos + 1
    else  -- Parse true, false, or null.
        local literals = {['true'] = true, ['false'] = false, ['null'] = json.null}
        for lit_str, lit_val in pairs(literals) do
            local lit_end = pos + #lit_str - 1
            if str:sub(pos, lit_end) == lit_str then return lit_val, lit_end + 1 end
        end
        local pos_info_str = 'position ' .. pos .. ': ' .. str:sub(pos, pos + 10)
        error('Invalid json syntax starting at ' .. pos_info_str)
    end
end

-- ========================= --
-- Synthesizer V script part --
-- ========================= --

function getClientInfo()
    return {
        name = "StartServerRequestHandler",
        author = "Haruki Okada",
        category = "MCP",
        versionNumber = 1,
        minEditorVersion = 65540
    }
end

function fetchState()
    local file = io.open(STATE_FILE, "r")
    if file then
        local state = file:read("*all")
        file:close()
        return state
    else
        -- If the file doesn't exist, create it with initial state
        local file = io.open(STATE_FILE, "w")
        file:write("running")
        file:close()
        return "running"
    end
end

function pollCommandFile()
    SV:setTimeout(POLL_INTERVAL, function()
        -- Check if command file exists
        local file = io.open(COMMAND_FILE, "r")
        if file then
            local command = file:read("*all")
            file:close()

            -- Process the command if it's not empty
            if command and command ~= "" then
                -- Clear the command file immediately to avoid processing the same command multiple times
                local clearFile = io.open(COMMAND_FILE, "w")
                clearFile:close()

                -- Execute the command and write the response
                executeCommand(command)
            end
        end

        -- Check if we should terminate
        if fetchState() == "terminated" then
            SV:finish()
        else
            pollCommandFile()
        end
    end)
end

-- Function to execute commands from the MCP server
function executeCommand(commandJson)
    local command = json.parse(commandJson)

    if command.action == "get_project_info" then
        local project = SV:getProject()
        local timeAxis = project:getTimeAxis()
        local mm = timeAxis:getMeasureMarkAtBlick(0)
        local projectInfo = {
            name = project:getFileName(),
            tempo = timeAxis:getTempoMarkAt(0).bpm,
            timeSignature = mm.numerator .. "/" .. mm.denominator,
            trackCount = project:getNumTracks(),
            ticksPerBeat = SV.QUARTER,
        }
        writeResponse(projectInfo)

    elseif command.action == "list_tracks" then
        local project = SV:getProject()
        local tracks = {}

        for i = 1, project:getNumTracks() do
            local track = project:getTrack(i)
            local count = 0
            for j = 1, track:getNumGroups() do
                local groupRef = track:getGroupReference(j)
                local group = groupRef:getTarget()
                count = count + group:getNumNotes()
            end
            table.insert(tracks, {
                id = i,
                name = track:getName(),
                noteCount = count
            })
        end

        writeResponse(tracks)

    elseif command.action == "get_track_notes" then
        local trackId = tonumber(command.trackId)
        local project = SV:getProject()

        if not trackId or trackId < 1 or trackId > project:getNumTracks() then
            writeResponse({ error = "Invalid track ID" })
            return
        end

        local track = project:getTrack(trackId)
        local notes = {}
        local id = 1
        for i = 1, track:getNumGroups() do
            local groupRef = track:getGroupReference(i)
            local group = groupRef:getTarget()
            for j = 1, group:getNumNotes() do
                local note = group:getNote(j)
                table.insert(notes, {
                    id = id,
                    lyrics = note:getLyrics(),
                    startTime = note:getOnset(),
                    duration = note:getDuration(),
                    pitch = note:getPitch()
                })
                id = id + 1
            end
        end

        writeResponse(notes)

    elseif command.action == "add_notes" then
        local trackId = tonumber(command.trackId)
        local project = SV:getProject()
        local notes = command.notes

        if not trackId or trackId < 1 or trackId > project:getNumTracks() then
            writeResponse({ error = "Invalid track ID" })
            return
        end

        if not notes or type(notes) ~= "table" or #notes == 0 then
            writeResponse({ error = "No notes provided" })
            return
        end

        local track = project:getTrack(trackId)
        if track:getNumGroups() < 2 then
            local group = SV:create("NoteGroup")
            local groupRef = SV:create("NoteGroupReference")
            project:addNoteGroup(group)
            groupRef:setTarget(group)
            track:addGroupReference(groupRef)
        end

        -- Always use first group for simplicity
        local groupRef = track:getGroupReference(2)
        local group = groupRef:getTarget()
        local addedNoteIds = {}

        for i, noteData in ipairs(notes) do
            local note = SV:create("Note")

            note:setLyrics(noteData.lyrics or "")
            note:setOnset(noteData.startTime or 0)
            note:setDuration(noteData.duration or SV.QUARTER)
            note:setPitch(noteData.pitch or 60)

            group:addNote(note)
            table.insert(addedNoteIds, group:getNumNotes())
        end

        local message
        if #addedNoteIds == 1 then
            message = "Note added successfully"
        else
            message = #addedNoteIds .. " notes added successfully"
        end

        writeResponse({
            message = message,
            noteIds = addedNoteIds,
        })
    elseif command.action == "edit_notes" then
        local trackId = tonumber(command.trackId)
        local project = SV:getProject()
        local notes = command.notes

        if not trackId or trackId < 1 or trackId > project:getNumTracks() then
            writeResponse({ error = "Invalid track ID" })
            return
        end

        if not notes or type(notes) ~= "table" or #notes == 0 then
            writeResponse({ error = "No notes provided" })
            return
        end

        local track = project:getTrack(trackId)
        if track:getNumGroups() < 2 then
            local group = SV:create("NoteGroup")
            local groupRef = SV:create("NoteGroupReference")
            project:addNoteGroup(group)
            groupRef:setTarget(group)
            track:addGroupReference(groupRef)
        end

        -- Always use first group for simplicity
        local groupRef = track:getGroupReference(2)
        local group = groupRef:getTarget()
        local editedNoteIds = {}

        for i, noteData in ipairs(notes) do
            local note = group:getNote(noteData.id)

            if noteData.lyrics then
                note:setLyrics(noteData.lyrics)
            end
            if noteData.startTime then
                note:setOnset(noteData.startTime)
            end
            if noteData.duration then
                note:setDuration(noteData.duration)
            end
            if noteData.pitch then
                note:setPitch(noteData.pitch)
            end
            table.insert(editedNoteIds, noteData.id)
        end

        local message
        if #editedNoteIds == 1 then
            message = "Note edited successfully"
        else
            message = #editedNoteIds .. " notes edited successfully"
        end

        writeResponse({
            message = message,
            noteIds = editedNoteIds,
        })
    elseif command.action == "add_track" then
        local project = SV:getProject()
        local trackName = command.name or "New Track"

        -- Create a new track
        local track = SV:create("Track")
        track:setName(trackName)

        -- Add the track to the project
        project:addTrack(track)

        -- Create a default group for the track
        local group = SV:create("NoteGroup")
        local groupRef = SV:create("NoteGroupReference")
        project:addNoteGroup(group)
        groupRef:setTarget(group)
        track:addGroupReference(groupRef)

        -- Get the new track ID (it's the last track in the project)
        local trackId = project:getNumTracks()

        writeResponse({
            message = "Track added successfully",
            trackId = trackId,
            name = trackName
        })
    else
        writeResponse({ error = "Unknown command: " .. command.action })
    end
end

-- Function to write response as JSON
function writeResponse(data)
    local responseFile = io.open(RESPONSE_FILE, "w")
    responseFile:write(json.stringify(data))
    responseFile:close()
end

function main()
    local file = io.open(STATE_FILE, "w")
    file:write("running")
    file:close()
    pollCommandFile()
end
