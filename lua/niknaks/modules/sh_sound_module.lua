
NikNaks.Sounds = {}

do
    -- http://soundfile.sapp.org/doc/WaveFormat/

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
                if bitRate == 0 then return 0 end
                return dataSize / bitRate
            else
                -- Check if headerId contains a-z characters. Could be a custom chunk
                if string.match(headerId, "[a-z]") then fil:Seek(endPos) continue end
            end
            break
        end
        -- Fallback to file size
        if bitRate > 0 then
            local result = (fil:Size() - 28) / bitRate
            fil:Close()
            return result
        end
        fil:Close()
        return 0
    end

    -- https://xiph.org/vorbis/doc/framing.html

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
        fil:Close()
        if rate == 0 then return 0 end
        return granulePos / rate
    end

    -- http://www.mp3-tech.org/programmer/frame_header.html
    -- https://id3.org/mp3Frame

    -- MPEG Layer III (MP3) bitrate tables, in kbps, indexed by the 4-bit bitrate
    local MP3_BITRATE_V1_L3 = { 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320 }
    local MP3_BITRATE_V2_L3 = { 8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160 }
    local MP3_SAMPLERATE = {
        [0] = { 11025, 12000, 8000 },
        [2] = { 22050, 24000, 16000 },
        [3] = { 44100, 48000, 32000 },
    }

    ---@param fil File
    ---@return number?
    local function readUInt32BE(fil)
        local b1, b2, b3, b4 = fil:ReadByte(), fil:ReadByte(), fil:ReadByte(), fil:ReadByte()
        if not b4 then return nil end
        return bit.bor(bit.lshift(b1, 24), bit.lshift(b2, 16), bit.lshift(b3, 8), b4)
    end

    -- https://github.com/id3/ID3v2.4/blob/master/id3v2.4.0-frames.txt

    --- Returns the duration of an MP3 file (MPEG-1/2/2.5 Layer III only).
    ---@param fil File
    ---@return number seconds
    local function getMP3Duration(fil)
        fil:Seek(0)
        local fileSize = fil:Size()
        -- Skip a trailing ID3v1 tag if present.
        if fileSize >= 128 then
            fil:Seek(fileSize - 128)
            if fil:Read(3) == "TAG" then
                fileSize = fileSize - 128
            end
        end

        local searchStart = 0
        do
            fil:Seek(0)
            if fil:Read(3) == "ID3" then
                fil:Skip(2)
                local b1, b2, b3, b4 = fil:ReadByte(), fil:ReadByte(), fil:ReadByte(), fil:ReadByte()
                local size = bit.bor(
                    bit.lshift(bit.band(b1, 0x7F), 21), bit.lshift(bit.band(b2, 0x7F), 14),
                    bit.lshift(bit.band(b3, 0x7F), 7), bit.band(b4, 0x7F))
                searchStart = 10 + size
            end
        end

        local frameStart, versionBits, bitrateIndex, samplerateIndex, channelMode
        local maxScan = 65536
        for i = 0, maxScan do
            local pos = searchStart + i
            if pos + 4 > fileSize then break end
            fil:Seek(pos)
            local b1 = fil:ReadByte()
            if b1 == 0xFF then
                local b2 = fil:ReadByte()
                if b2 and bit.band(b2, 0xE0) == 0xE0 then
                    local b3, b4 = fil:ReadByte(), fil:ReadByte()
                    local vBits = bit.band(bit.rshift(b2, 3), 0x3) -- 0=MPEG2.5, 1=reserved, 2=MPEG2, 3=MPEG1
                    local lBits = bit.band(bit.rshift(b2, 1), 0x3) -- 1=Layer III (the only one supported here)
                    local brIndex = bit.rshift(b3, 4)
                    local srIndex = bit.band(bit.rshift(b3, 2), 0x3)
                    if vBits ~= 1 and lBits == 1 and brIndex ~= 0 and brIndex ~= 15 and srIndex ~= 3 then
                        frameStart = pos
                        versionBits = vBits
                        bitrateIndex, samplerateIndex = brIndex, srIndex
                        channelMode = bit.rshift(b4, 6) -- 0=stereo, 1=joint, 2=dual, 3=mono
                        break
                    end
                end
            end
        end
        if not frameStart then fil:Close() return 0 end

        local sampleRate = MP3_SAMPLERATE[versionBits][samplerateIndex + 1]
        local bitrateTable = (versionBits == 3) and MP3_BITRATE_V1_L3 or MP3_BITRATE_V2_L3
        local bitrate = bitrateTable[bitrateIndex] -- indices 1-14, matching field values 1-14
        local samplesPerFrame = (versionBits == 3) and 1152 or 576

        -- Xing/Info VBR header
        local sideInfoSize
        if versionBits == 3 then -- MPEG1
            sideInfoSize = (channelMode == 3) and 17 or 32
        else -- MPEG2 / MPEG2.5
            sideInfoSize = (channelMode == 3) and 9 or 17
        end

        local totalFrames

        fil:Seek(frameStart + 4 + sideInfoSize)
        local tag = fil:Read(4)
        if tag == "Xing" or tag == "Info" then
            local flags = readUInt32BE(fil)
            if flags and bit.band(flags, 0x1) ~= 0 then -- frame count field present
                totalFrames = readUInt32BE(fil)
            end
        else
            fil:Seek(frameStart + 4 + 32)
            if fil:Read(4) == "VBRI" then
                fil:Skip(6) -- version(2) delay(2) quality(2)
                fil:Skip(4) -- total bytes(4)
                totalFrames = readUInt32BE(fil)
            end
        end

        fil:Close()

        if totalFrames and totalFrames > 0 then
            return totalFrames * samplesPerFrame / sampleRate
        end

        -- No VBR header found -- assume CBR and estimate from file size.
        if not bitrate or bitrate <= 0 then return 0 end
        return (fileSize - frameStart) * 8 / (bitrate * 1000)
    end

    --- Returns the duration of a sound file. Supports WAV, OGG and MP3 files.
    ---
    --- **Note**: This only works for OGG files with a Vorbis header, and MP3 files
    --- encoded as MPEG-1/2/2.5 Layer III.
    ---
    --- **⚠Warning**: This isn't cached, so it's best to cache the duration if you're going to use it multiple times.
    ---@param soundPath string # The path to the sound file.
    ---@return number seconds # If unable to read the file, it will return 0
    function NikNaks.Sounds.GetDuration(soundPath)
        local fil = file.Open("sound/" .. soundPath, "rb", "GAME")
        if not fil then return 0 end
        -- Read the start of the header
        local header = fil:Read(4)
        if header == "RIFF" then
            return getWaveFileDuration(fil)
        elseif header == "OggS" then
            return getOGGDuration(fil)
        elseif string.match(header, "^ID3") or string.byte(header, 1) == 0xFF then
            return getMP3Duration(fil)
        end
        fil:Close()
        return 0
    end
end