
NikNaks.DataPackage = {}

local NET = "NikNak_Data"

local NET_HEADER = 0
local NET_DATA = 1

local conMaxSize = CreateConVar( "niknaks_datapackage_maxsize", "63", FCVAR_ARCHIVE + FCVAR_REPLICATED, "The max size of a data packages in kb." , 1, 63 )

-- Net messages can max be 64kb in size. And a roughly 128kb/s limit. Max 1 package pr second.

---@class DataPackage
---@field _id string # The package id.
---@field _data number[] # 32bit data
---@field _size number # The bigbuffer size.
---@field _nsize number # The size of the data.
---@field _nid number # The current index of the data.
---@field _players Player[] # The players that should receive this package.


--- Returns the max size of a data package in longs.
---@return number
local function getMaxConSize()
    return math.floor( conMaxSize:GetInt() * 256 )
end


if SERVER then
    util.AddNetworkString( NET )
    ---@type DataPackage[]
    local dataToSend = {}
    DEBUGDATASEND = dataToSend

    local nextSend = 0
    local function onThink()
        -- Once pr second
        if nextSend >= CurTime() then return end
        nextSend = CurTime() + 1

        if #dataToSend == 0 then
            hook.Remove( "Think", "NikNaks.DataPackage" )
            return
        end
        local package = dataToSend[1]

        if #package._data == package._nid then
            -- We're done with this package.
            table.remove( dataToSend, 1 )
            hook.Run( NikNaks.Hooks.DataPackageDone, package._id )
            return
        end
        
        net.Start(NET)
            net.WriteUInt( NET_DATA, 1 )
            for i = 1, getMaxConSize() do
                if not package._data[package._nid + 1] then break end
                package._nid = package._nid + 1
                net.WriteUInt( package._data[package._nid], 32 )
            end
        net.Send( package._players )
    end

    --- Sends a data package to the specified players.
    --- @param id string # The package id.
    --- @param bitBuffer BitBuffer # The data to send.
    --- @param players Player[] # The players to send the data to.
    ---
	--- *Server*: 
    function NikNaks.DataPackage.Send( id, bitBuffer, players )
        ---@type DataPackage
        local package = {
            _id = id,
            _data = bitBuffer._data,
            _size = bitBuffer:Size(),
            _nsize = #bitBuffer._data,
            _players = players,
            _nid = 0
        }

        hook.Run( NikNaks.Hooks.DataPackageStart, package._id )

        net.Start(NET)
            net.WriteUInt( NET_HEADER, 1 )
            net.WriteString( id )
            net.WriteUInt( package._size, 32 )
            net.WriteUInt( package._nsize, 32 )
        net.Send( players )

        table.insert( dataToSend, package )
        hook.Add( "Think", "NikNaks.DataPackage", onThink )
    end

    --- Returns true if the package is in the queue to be sent.
    --- @param id string
    --- @return boolean
    --- 
    --- @server
    function NikNaks.DataPackage.IsInQueue( id )
        for i = 1, #dataToSend do
            if dataToSend[i]._id == id then return true end
        end
        return false
    end

    --- Returns true if the package id is being sent.
    --- @param id string
    --- @return boolean
    --- 
    --- @server
    function NikNaks.DataPackage.IsSending( id )
        return dataToSend[1] and dataToSend[1]._id == id or false
    end

    --- Returns the current percent of the package being sent.
    ---@return number # The current percent. 0-1
    function NikNaks.DataPackage.CurrentPercent()
        local currentPackage = dataToSend[1]
        if not currentPackage then return 0 end
        return currentPackage._nid / currentPackage._nsize
    end
else
    ---@type DataPackage?
    local packageBuilder

    ---Returns true if the package id is being received.
    ---@param id string
    ---@return boolean
    ---
    ---@client
    function NikNaks.DataPackage.IsReciving( id )
        return packageBuilder and packageBuilder._id == id or false
    end

    net.Receive( NET, function()
        local header = net.ReadUInt( 1 )
        if header == NET_HEADER then
            local id = net.ReadString()
            local size = net.ReadUInt( 32 )
            local nsize = net.ReadUInt( 32 )

            packageBuilder = {
                _id = id,
                _data = {},
                _size = size,
                _nsize = nsize,
                _players = {},
                _nid = 0
            }

        elseif header == NET_DATA then
            if not packageBuilder then return end
            for i = 1, getMaxConSize() do
                if #packageBuilder._data == packageBuilder._nsize then
                    -- Done
                    local BitBuffer = NikNaks.BitBuffer.Create( packageBuilder._data )
                    BitBuffer._len = packageBuilder._size
                    hook.Run( NikNaks.Hooks.DataPackageDone, packageBuilder._id, BitBuffer )
                    packageBuilder = nil
                    return
                end
                table.insert( packageBuilder._data, net.ReadUInt( 32 ) )
                packageBuilder._nid = packageBuilder._nid + 1
            end
        end
    end)

    --- Returns the current percent of the package being sent.
    ---@return number # The current percent. 0-1
    function NikNaks.DataPackage.CurrentPercent()
        if not packageBuilder then return 0 end
        return packageBuilder._nid / packageBuilder._nsize
    end
end