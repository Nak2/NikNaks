
NikNaks.Sounds = {}

do
    ---Returns the duration of a wave file
    ---@param fil File
    ---@return number seconds # If unable to read the file, it will return 0
    local function getWaveFileDuration(fil)
        fil:Skip(4)
        if fil:Read(4) ~= "WAVE" then fil:Close() return 0 end -- Make sure it's a WAVE file
        local bitRate = 0
        -- Handle headers
        while true do
            local headerId = string.lower(fil:Read(4))
            local dataSize = fil:ReadLong()
            local endPos = fil:Tell() + dataSize
            if headerId == "fmt " then
                fil:Skip(8) -- Format, Channels, sampleRate
                bitRate = fil:ReadLong()
                fil:Seek(endPos)
                continue
            elseif headerId == "data" then
                fil:Close()
                return dataSize / bitRate
            else
                -- Check if headerId contains a-z characters. Could be a custom chunk
                if string.match(headerId, "[a-z]") then fil:Seek(endPos) continue end
            end
            break
        end
        -- Fallback to file size
        if bitRate > 0 then
            return (fil:Size() - 28) / bitRate
        end
        fil:Close()
        return 0
    end

    --- Returns the duration of an OGG file
    ---
    --- *Note: This only works for OGG files with a Vorbis header*.
    ---@param fil File
    ---@return integer
    local function getOGGDuration(fil)
        -- Locate the last page header
        local size = fil:Size() - 6
        for i = size, 0, -1 do
            fil:Seek(i)
            if fil:Read(4) == "OggS" then
                if fil:ReadByte() == 0 then break end -- Version have to be 0
            end
        end
        if fil:ReadByte() ~= 0x04 then fil:Close() return 0 end -- Ensure EOS flag is set
        local granulePos = fil:ReadLong()
        -- Locate first Voribs header. This should be somewhere after 28 bytes from the start.
        -- Limit this to 1000 bytes to prevent lag for non-vorbis ogg files
        local found = false
        for i = 28, 1000, 1 do
            fil:Seek(i)
            if fil:Read(6) == "vorbis" then
                found = true
                break
            end
        end
        if not found then fil:Close() return 0 end

        fil:Skip(5)
        local rate = fil:ReadLong()
        return granulePos / rate
    end

    /*
    --- Returns the duration of an MP3 file
    ---@param soundPath string
    ---@return integer
    local function getMP3Duration(soundPath)
        local buff = NikNaks.BitBuffer.OpenFile( soundPath, "GAME" )
        if not buff then return 0 end
        -- check for ID3v2 tag
        local tag = buff:Read(3)
        if tag == "ID3" then
            local majorVersion = buff:ReadByte()
            local minorVersion = buff:ReadByte()
            local flags = buff:ReadByte()
            local size = buff:ReadLong()
            if bit.band(flags, 0x10) ~= 0 then
                -- Extended header
                local extSize = buff:ReadLong()
                buff:Skip(extSize - 6)
            end
            buff:Skip(size - 10)

            -- Check for another ID3v2 tag
            tag = buff:Read(3)
            if tag == "ID3" then
                majorVersion = buff:ReadByte()
                minorVersion = buff:ReadByte()
                flags = buff:ReadByte()
                size = buff:ReadLong()
                if bit.band(flags, 0x10) ~= 0 then
                    -- Extended header
                    local extSize = buff:ReadLong()
                    buff:Skip(extSize - 6)
                end
                buff:Skip(size - 10)
            end

            -- Check for a MPEG header
            local header = buff:Read(3)
            if header == "TAG" then
                
                return -4
            end


        else

        end

        return duration
    end*/

    --- Returns the duration of a sound file. Supports WAV and OGG files, regardless of OS.
    ---
    --- **Note**: This only works for OGG files with a Vorbis header
    --- 
    --- **⚠Warning**: This isn't cached, so it's best to cache the duration if you're going to use it multiple times.
    ---@param soundPath string # The path to the sound file.
    ---@return number seconds # If unable to read the file, it will return 0
    function NikNaks.Sounds.GetDuration(soundPath)
        local fil = file.Open("sound/" .. soundPath, "rb", "GAME")
        if not fil then return 0 end
        -- Read the start of the header
        local header = fil:Read(4)
        print(string.byte(header, 1, 4))
        if header == "RIFF" then
            return getWaveFileDuration(fil)
        elseif header == "OggS" then
            return getOGGDuration(fil)
        elseif string.match(header, "ID3") then
            fil:Close()
        end
        return 0
    end
end