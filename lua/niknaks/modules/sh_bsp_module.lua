-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
-- License: https://github.com/Nak2/NikNaks/blob/main/LICENSE

local obj_tostring = "BSP %s [ %s ]"
local format = string.format

--- @class BSPObject
--- @field _isL4D2 boolean # If the map is from L4D2, this will be true.
local meta = NikNaks.__metatables["BSP"]

--- @return File?
local function openFile( self )
	if self._mapfile == nil then return end
	return file.Open( self._mapfile, "rb", "GAME" )
end

--- Reads the lump header.
--- @param self BSPObject
--- @param f BitBuffer|File
local function read_lump_h( self, f )
	-- "How do we stop people loading L4D2 maps in other games?"
	-- "I got it, we scrample the header."

	--- @class BSPLumpHeader
	--- @field fileofs number # Offset of the lump in the file
	--- @field filelen number # Length of the lump
	--- @field version number # Version of the lump
	--- @field fourCC number # FourCC of the lump
	local t = {}
	if self._version ~= 21 or self._isL4D2 == false then
		t.fileofs = f:ReadLong()
		t.filelen = f:ReadLong()
		t.version = f:ReadLong()
		t.fourCC  = f:ReadLong()
	elseif self._isL4D2 == true then
		t.version = f:ReadLong()
		t.fileofs = f:ReadLong()
		t.filelen = f:ReadLong()
		t.fourCC = f:ReadLong()
	elseif NikNaks._Source:find( "niknak" ) then -- Try and figure it out
		local fileofs = f:ReadLong() -- Version
		local filelen = f:ReadLong() -- fileofs
		local version = f:ReadLong() -- filelen
		t.fourCC  = f:ReadLong()
		if fileofs <= 8 then
			self._isL4D2 = true
			t.version = fileofs
			t.fileofs = filelen
			t.filelen = version
		else
			self._isL4D2 = false
			t.fileofs = fileofs
			t.filelen = filelen
			t.version = version
		end
	end

	return t
end

--- Parse LZMA. These are for gamelumps, entities, PAK files and staticprops .. ect from TF2
--- @param str string
--- @return string
local function LZMADecompress( str )
	if str:sub( 0, 4 ) ~= "LZMA" then return str end

	local actualSize = str:sub( 5, 8 )
	local lzmaSize 	= NikNaks.BitBuffer.StringToInt( str:sub( 9, 12 ) )
	if lzmaSize <= 0 then return "" end -- Invalid length

	local t = str:sub( 13, 17 )
	local data = str:sub( 18, 18 + lzmaSize ) -- Why not just read all of it? What data is after this? Tell me your secrets Valve.
	return util.Decompress( t .. actualSize .. "\0\0\0\0" .. data ) or str
end

local thisMap = "maps/" .. game.GetMap() .. ".bsp"
local thisMapObject

--- Reads the BSP file and returns it as an object.
--- @param fileName string? # The file name of the map. If not provided, it will load the current map.
--- @return BSPObject? # Will be nill, if unable to load the map.
--- @return BSP_ERROR? # Error code if unable to load the map.
--- **Note:** The current map will be cached and returned if the same map is loaded twice.
---
--- **Error Codes:**
--- - `NikNaks.BSP_ERROR_FILENOTFOUND` - File not found
--- - `NikNaks.BSP_ERROR_FILECANTOPEN` - Unable to open file
--- - `NikNaks.BSP_ERROR_NOT_BSP` - Not a BSP file
--- - `NikNaks.BSP_ERROR_TOO_NEW` - Map is too new
function NikNaks.Map( fileName )
	-- Handle filename
	if not fileName then
		if thisMapObject then return thisMapObject end -- This is for optimization, so we don't have to load the same map twice.
		fileName = thisMap
	else
		if not string.match( fileName, ".bsp$" ) then fileName = fileName .. ".bsp" end -- Add file header
		if not string.match( fileName, "^maps/" ) and not file.Exists( fileName, "GAME" ) then -- Map doesn't exists and no folder indecated.
			fileName = "maps/" .. fileName	-- Add "maps" folder
		end
	end

	if not file.Exists( fileName, "GAME" ) then
		-- File not found
		return nil, NikNaks.BSP_ERROR_FILENOTFOUND
	end

	local f = file.Open( fileName, "rb", "GAME" )
	if not f then
		-- Unable to open file
		return nil, NikNaks.BSP_ERROR_FILECANTOPEN
	end

	-- Read the header
	if f:Read( 4 ) ~= "VBSP" then
		f:Close()
		return nil, NikNaks.BSP_ERROR_NOT_BSP
	end

	-- Create BSP object
	--- @class BSPObject
	--- @field __map BSPObject
	local BSP = setmetatable( {}, meta )
	BSP._mapfile = fileName
	BSP._size	 = f:Size()
	BSP._mapname = string.GetFileFromFilename( fileName )
	BSP._mapname = string.match( BSP._mapname, "(.+).bsp$" ) or BSP._mapname
	BSP._version = f:ReadLong()
	BSP._fileobj = f

	if BSP._version > 21 then
		f:Close()
		return nil, NikNaks.BSP_ERROR_TOO_NEW
	end

	-- Read Lump Header
	--- @type BSPLumpHeader[]
	BSP._lumpheader = {}
	for i = 0, 63 do
		BSP._lumpheader[i] = read_lump_h( BSP, f )
	end

	--- @type BitBuffer[]
	BSP._lumpstream = {}

	BSP._gamelumps = {}
	f:Close()

	if thisMap == fileName then
		thisMapObject = BSP
	end

	return BSP
end

-- Smaller functions
do
	--- Returns the mapname of the map.
	--- @return string
	function meta:GetMapName()
		return self._mapname or "Unknown"
	end

	--- Returns the filepath of the map.
	--- @return string
	function meta:GetMapFile()
		return self._mapfile or "No file"
	end

	--- Returns the map-version.
	--- @return number
	function meta:GetVersion()
		return self._version
	end

	--- Returns the size of the map in bytes.
	--- @return number # Size in bytes
	function meta:GetSize()
		return self._size
	end
end

-- Lump functions
do
	if SERVER then
		---Returns true if the server has a lumpfile for the given lump. Lumpfiles are used to override the default lump data. They do not exist on the client.
		---@param lump_id number # The lump ID
		---@return boolean
		---@server
		function meta:HasLumpFile( lump_id )
			if self._lumpfile and self._lumpfile[lump_id] ~= nil then
				return self._lumpfile[lump_id]
			end
			self._lumpfile = self._lumpfile or {}
			self._lumpfile[lump_id] = file.Exists("maps/" .. self._mapname .. "_l_" .. lump_id .. ".lmp", "GAME")
			return self._lumpfile[lump_id]
		end
	end

	--- Returns the data lump as a ByteBuffer. This will also be cached onto the BSP object.
	--- @param lump_id number # The lump ID to read. This is a number between 0 and 63.
	--- @return BitBuffer
	function meta:GetLump( lump_id )
		local lumpStream = self._lumpstream[lump_id]
		if lumpStream then
			lumpStream:Seek( 0 ) -- Reset the read position
			return lumpStream
		end

		local lump_h = self._lumpheader[lump_id]
		assert( lump_h, "Tried to read invalid lumpheader!" )

		-- The raw lump data
		local data = ""

		-- Check for LUMPs
		local lumpPath = "maps/" .. self._mapname .. "_l_" .. lump_id .. ".lmp"
		if file.Exists( lumpPath, "GAME" ) then -- L4D has _s_ and _h_ files too. Depending on the gamemode.
			data = file.Read( lumpPath, "GAME" ) or ""
		elseif lump_h.filelen > 0 then
			local f = openFile( self )
			if (f ~= nil) then
				f:Seek( lump_h.fileofs )
				data = f:Read( lump_h.filelen )
				f:Close()
			end
		end

		-- TF2 have some maps that are LZMA compressed.
		data = LZMADecompress( data )

		-- Create bytebuffer object with the data and return it
		self._lumpstream[lump_id] = NikNaks.BitBuffer( data or "" )

		return self._lumpstream[lump_id]
	end

	--- Deletes the lump from the cache. This frees up memory.
	--- @param lump_id number
	function meta:ClearLump( lump_id )
		self._lumpstream[lump_id] = nil
	end

	--- Returns the lump version.
	--- @return number
	function meta:GetLumpVersion( lump_id )
		return self._lumpheader[ lump_id ].version
	end

	--- Reads the lump as a string. This will not be cached or saved, but it is faster than to parse the data into a bytebuffer and useful to read the raw data.
	--- @param lump_id number # The lump ID to read. This is a number between 0 and 63.
	--- @return string # The raw data of the lump.
	function meta:GetLumpString( lump_id )
		local lump_h = self._lumpheader[lump_id]
		assert( lump_h, "Tried to read invalid lumpheader!" )

		-- The raw lump data
		local data = ""
		local lumpPath = "maps/" .. self._mapname .. "_l_" .. lump_id .. ".lmp"
		if file.Exists( lumpPath, "GAME" ) then
			data = file.Read( lumpPath, "GAME" ) or ""
		elseif lump_h.filelen > 0 then
			local f = openFile( self )
			if(f ~= nil) then
				f:Seek( lump_h.fileofs )
				data = f:Read( lump_h.filelen )
				f:Close()
			end
		end

		-- TF2 have some maps that are LZMA compressed.
		data = LZMADecompress( data )
		return data
	end

	--- Returns a list of gamelumps.
	--- @return BSPGameLumpHeader[]
	function meta:GetGameLumpHeaders()
		if self._gamelump then return self._gamelump end
		self._gamelump = {}

		local lump = self:GetLump( 35 )
		for i = 0, math.min( 63, lump:ReadLong() ) do
			--- @class BSPGameLumpHeader
			--- @field id number # ID of the lump
			--- @field flags number # Flags of the lump
			--- @field version number # Version of the lump
			--- @field fileofs number # Offset of the lump in the file
			--- @field filelen number # Length of the lump
			local t = {
				id = lump:ReadLong(),
				flags = lump:ReadUShort(),
				version = lump:ReadUShort(),
				fileofs = lump:ReadLong(),
				filelen = lump:ReadLong()
			}
			self._gamelump[i] = t
		end

		self:ClearLump( 35 )
		return self._gamelump
	end

	--- Returns the gamelump header matching the ID.
	--- @param GameLumpID number
	--- @return BSPGameLumpHeader?
	function meta:FindGameLump( GameLumpID )
		for _, v in pairs( self:GetGameLumpHeaders() ) do
			if v.id == GameLumpID then
				return v
			end
		end
	end

	--- @class BSPGameLump
	--- @field buffer BitBuffer
	--- @field version number
	--- @field flags number

	--- Returns the game lump as a bytebuffer. This will also be cached on the BSP object.
	--- @param gameLumpID any
	---	@return BSPGameLump?
	function meta:GetGameLump( gameLumpID )
		--- @type BSPGameLump?
		local gameLump = self._gamelumps[gameLumpID]
		if gameLump then
			gameLump.buffer:Seek( 0 )
			return gameLump
		end

		-- Locate the gamelump.
		local t = self:FindGameLump( gameLumpID )

		-- No data found, or lump has no data.
		if not t or t.filelen <= 0 then
			-- Create an empty bitbuffer with -1 version and 0 flag

			gameLump = {
				flags = t and t.flags or 0,
				version = t and t.version or -1,
				buffer = NikNaks.BitBuffer.Create(),
			}

			self._gamelumps[gameLumpID] = gameLump
			return gameLump
		else
			local f = openFile( self )
			if f ~= nil then
				f:Seek( t.fileofs )
				gameLump = {
					flags = t.flags,
					version = t.version,
					buffer = NikNaks.BitBuffer.Create( LZMADecompress( f:Read( t.filelen ) ) ),
				}
				self._gamelumps[gameLumpID] = gameLump
				return gameLump
			end
		end
	end
end

-- Word Data
do
	local default = [[detail\detailsprites.vmt]]

	--- Returns the detail-metail the map uses. This is used for the detail sprites like grass and flowers.
	--- @return string
	function meta:GetDetailMaterial()
		local wEnt = self:GetEntities()[0]
		return wEnt and wEnt.detailmaterial or default
	end

	--- Returns true if the map is a cold world. ( Flag set in the BSP ) This was added in Day of Defeat: Source.
	--- @return boolean
	function meta:IsColdWorld()
		local wEnt = self:GetEntity( 0 )
		return wEnt and wEnt.coldworld == 1 or false
	end

	--- Returns the min-positions where brushes are within the map.
	--- @return Vector
	function meta:WorldMin()
		if self._wmin then return self._wmin end

		local wEnt = self:GetEntity( 0 )
		if not wEnt then
			self._wmin = NikNaks.vector_zero
			return self._wmin
		end

		self._wmin = util.StringToType( wEnt.world_mins or "0 0 0", "Vector" ) or NikNaks.vector_zero
		return self._wmin
	end

	--- Returns the max-position where brushes are within the map.
	--- @return Vector
	function meta:WorldMax()
		if self._wmax then return self._wmax end

		local wEnt = self:GetEntity( 0 )
		if not wEnt then
			self._wmax = NikNaks.vector_zero
			return self._wmax
		end

		self._wmax = util.StringToType( wEnt.world_maxs or "0 0 0", "Vector" ) or NikNaks.vector_zero
		return self._wmax
	end

	--- Returns the map-bounds. These are not the size of the map, but the bounds where brushes are within.
	--- @return Vector
	--- @return Vector
	function meta:GetBrushBounds()
		return self:WorldMin(), self:WorldMax()
	end

	--- Returns the skybox position. Returns [0,0,0] if none are found.
	--- @return Vector
	function meta:GetSkyBoxPos()
		if self._skyCamPos then return self._skyCamPos end

		local t = self:FindByClass( "sky_camera" )
		if #t < 1 then
			self._skyCamPos = NikNaks.vector_zero
		else
			self._skyCamPos = t[1].origin
		end

		return self._skyCamPos
	end

	--- Returns the skybox scale. Returns 1 if none are found.
	--- @return number
	function meta:GetSkyBoxScale()
		if self._skyCamScale then return self._skyCamScale end

		local t = self:FindByClass( "sky_camera" )
		if #t < 1 then
			self._skyCamScale = 1
		else
			self._skyCamScale = t[1].scale
		end

		return self._skyCamScale
	end

	--- Returns true if the map has a 3D skybox.
	--- @return boolean
	function meta:HasSkyBox()
		if self._skyCam ~= nil then return self._skyCam end
		self._skyCam = #self:FindByClass( "sky_camera" ) > 0
		return self._skyCam
	end

	--- Returns a position in the skybox that matches the one in the world.
	--- @param vec Vector
	--- @return Vector
	function meta:WorldToSkyBox( vec )
		return vec / self:GetSkyBoxScale() + self:GetSkyBoxPos()
	end

	--- Returns a position in the world that matches the one in the skybox.
	--- @param vec Vector
	--- @return Vector
	function meta:SkyBoxToWorld( vec )
		return ( vec - self:GetSkyBoxPos() ) * self:GetSkyBoxScale()
	end
end

-- Cubemaps
do
	--- @class BSPCubeMap
	--- @field origin Vector
	--- @field size number
	--- @field texture string
	--- @field id number
	local cubemeta = {}
	cubemeta.__index = cubemeta
	cubemeta.__tostring = function( self ) return
		format( obj_tostring, "Cubemap", "Index: " .. self:GetIndex() )
	end

	--- Returns the position of the cubemap.
	--- @return Vector
	function cubemeta:GetPos() return self.origin end

	--- Returns the size of the cubemap.
	--- @return number # Size of the cubemap
	function cubemeta:GetSize() return self.size end

	--- Returns the index of the cubemap.
	--- @return number # Index of the cubemap
	function cubemeta:GetIndex() return self.id or -1 end

	--- Returns the texture of the cubemap.
	--- @return string
	function cubemeta:GetTexture() return self.texture end

	--- Returns the CubeMaps in the map.
	--- @return BSPCubeMap[]
	function meta:GetCubemaps()
		if self._cubemaps then return self._cubemaps end

		local b = self:GetLump( 42 )
		local len = b:Size()

		--- @type BSPCubeMap[]
		self._cubemaps = {}
		for _ = 1, math.min( 1024, len / 128 ) do
			--- @class BSPCubeMap
			local t = setmetatable( {}, cubemeta )
			t.origin = Vector( b:ReadLong(), b:ReadLong(), b:ReadLong() )
			t.size = b:ReadLong()
			t.texture = ""

			local texturePath = "maps/" .. self:GetMapName() .. "/c" .. t.origin.x .. "_" .. t.origin.y .. "_" .. t.origin.z
			t.texturePath = texturePath
			if self:GetVersion() > 19 then
				t.texturePath = texturePath .. ".hdr"
			end

			if t.size == 0 then
				t.size = 32
			end

			t.id = table.insert( self._cubemaps, t ) - 1
		end

		self:ClearLump( 42 )
		return self._cubemaps
	end

	--- Returns the nearest cubemap to the given position.
	--- @param pos Vector # The position to check from
	--- @return BSPCubeMap?
	function meta:FindNearestCubemap( pos )
		local lr, lc
		for _, v in ipairs( self:GetCubemaps() ) do
			local cd = v:GetPos():DistToSqr( pos )

			if not lc then
				lc = v
				lr = cd
			elseif lr > cd then
				lc = v
				lr = cd
			end
		end

		return lc
	end
end

-- Textures and materials
do
	-- local max_data = 256000

	--- Returns the texture data string table. This is an id list of all textures used by the map.
	--- @return number[]
	function meta:GetTexdataStringTable()
		if self._texstab then return self._texstab end

		self._texstab = {}

		local data = self:GetLump( 44 )
		for i = 0, data:Size() / 32 - 1 do
			self._texstab[i] = data:ReadLong()
		end

		self:ClearLump( 44 )
		return self._texstab
	end

	--- Returns the texture data string data. This is a list of all textures used by the map.
	--- @return table
	function meta:GetTexdataStringData()
		if self._texstr then return self._texstr end

		--- @type table
		self._texstr = {}

		--- @type string[]
		self._texstr.id = {}

		local data = self:GetLump( 43 )
		for i = 0, data:Size() / 8 - 1 do
			local _id = data:Tell() / 8
			local str = data:ReadStringNull()
			self._texstr.id[_id] = str

			if #str == 0 then break end

			self._texstr[i] = string.lower( str )
		end

		self:ClearLump( 43 )
		return self._texstr
	end

	--- Returns a list of textures used by the map.
	--- @return string[]
	function meta:GetTextures()
		local c = {}
		local q = self:GetTexdataStringData()
		for i = 1, #q do
			c[i] = q[i]
		end
		return c
	end

	local function getTexByID( self, id )
		id = self:GetTexdataStringTable()[id]
		return self:GetTexdataStringData().id[id]
	end

	--- Returns a list of material-data used by the map.
	--- @return BSPTextureData[]
	function meta:GetTexData()
		if self._tdata then return self._tdata end

		--- @type BSPTextureData[]
		self._tdata = {}

		-- Load TexdataStringTable		
		self:GetTextures()
		local b = self:GetLump( 2 )
		local count = b:Size() / 256 + 1

		for i = 0, count - 1 do
			--- @class BSPTextureData
			--- @field reflectivity Vector
			--- @field nameStringTableID string
			--- @field width number
			--- @field height number
			--- @field view_width number
			--- @field view_height number
			local t = {}
			t.reflectivity = b:ReadVector()
			local n = b:ReadLong()
			t.nameStringTableID = getTexByID( self, n ) or tostring( n )
			t.width = b:ReadLong()
			t.height = b:ReadLong()
			t.view_width = b:ReadLong()
			t.view_height = b:ReadLong()
			self._tdata[i] = t
		end

		self:ClearLump( 2 )
		return self._tdata
	end

	--- Returns a list of material-data used by the map.
	--- @return TextureInfo[]
	function meta:GetTexInfo()
		if self._tinfo then return self._tinfo end

		self._tinfo = {}
		local data = self:GetLump( 6 )

		for i = 0, data:Size() / 576 - 1 do
			--- @class TextureInfo
			--- @field textureVects table<number, number[]>
			--- @field lightmapVecs table<number, number[]>
			--- @field flags number # Surface flags of the texture (SURF_*)
			--- @field texdata number # Index of the texture data
			local t = {}
			t.textureVects	= {}
			t.textureVects[0] = { [0] = data:ReadFloat(), data:ReadFloat(), data:ReadFloat(), data:ReadFloat() }
			t.textureVects[1] = { [0] = data:ReadFloat(), data:ReadFloat(), data:ReadFloat(), data:ReadFloat() }
			t.lightmapVecs	= {}
			t.lightmapVecs[0] = { [0] = data:ReadFloat(), data:ReadFloat(), data:ReadFloat(), data:ReadFloat() }
			t.lightmapVecs[1] = { [0] = data:ReadFloat(), data:ReadFloat(), data:ReadFloat(), data:ReadFloat() }
			t.flags			= data:ReadLong()
			t.texdata 		= data:ReadLong()
			self._tinfo[i] = t
		end

		self:ClearLump( 6 )
		return self._tinfo
	end
end

-- Planes, Vertex and Edges
do
	local dot = Vector().Dot

	--- @class BSPPlane
	--- @field normal Vector # Normal vector
	--- @field dist number # Distance from origin
	--- @field type number # Plane axis identifier
	--- @field back BSPPlane # Back plane
	local planeMeta = {}
	planeMeta.__index = planeMeta
	NikNaks.__metatables["BSP Plane"] = planeMeta

	--- Calculates the plane dist
	--- @param vec Vector
	--- @return number
	function planeMeta:DistTo( vec )
		return dot(self.normal, vec ) - self.dist
	end

	--- Returns a list of all planes
	--- @return BSPPlane[]
	function meta:GetPlanes()
		if self._plane then return self._plane end

		self._plane = {}
		local data = self:GetLump( 1 )
		for i = 0, data:Size() / 160 - 1 do
			--- @class BSPPlane
			local t = {}
			t.normal = data:ReadVector() -- Normal vector
			t.dist = data:ReadFloat() -- Distance from origin
			t.type = data:ReadLong() -- Plane axis identifier
			setmetatable( t, planeMeta )
			self._plane[i] = t
		end

		for i, t in pairs( self._plane ) do
			t.back = self._plane[ bit.bxor( i, 1 ) ] -- Back plane
		end

		self:ClearLump( 1 )
		return self._plane
	end

	local MAX_MAP_VERTEXS = 65536

	--- Returns an array of coordinates of all the vertices (corners) of brushes in the map geometry.
	--- @return Vector[]
	function meta:GetVertex()
		if self._vertex then return self._vertex end

		--- @type Vector[]
		self._vertex = {}
		local data = self:GetLump( 3 )

		for i = 0, math.min( data:Size() / 96, MAX_MAP_VERTEXS ) - 1 do
			self._vertex[i] = data:ReadVector()
		end

		self:ClearLump( 3 )
		return self._vertex
	end

	local MAX_MAP_EDGES = 256000

	--- Returns all edges. An edge is two points forming a line.
	--- Note: First edge seems to be [0 0 0] - [0 0 0]
	--- @return table<number, Vector[]>
	function meta:GetEdges()
		if self._edge then return self._edge end

		-- @type table<number, Vector[]>
		self._edge = {}
		local data = self:GetLump( 12 )

		local v = self:GetVertex()
		for i = 0, math.min( data:Size() / 32, MAX_MAP_EDGES ) -1 do
			self._edge[i] = { v[data:ReadUShort()], v[data:ReadUShort()] }
		end

		self:ClearLump( 12 )
		return self._edge
	end

	local MAX_MAP_SURFEDGES = 512000

	---Returns all surfedges. A surfedge is an index to edges with a direction. If positive First -> Second, if negative Second -> First.
	---@return number[]
	function meta:GetSurfEdges()
		if self._surfedge then return self._surfedge end

		--- @type number[]
		self._surfedge = {}
		local data = self:GetLump( 13 )

		for i = 0, math.min( data:Size() / 32, MAX_MAP_SURFEDGES ) -1 do
			self._surfedge[i] = data:ReadLong()
		end

		self:ClearLump( 13 )
		return self._surfedge
	end

	local abs = math.abs

	--- Returns the two edge-positions using surf index
	--- @param num number
	--- @return Vector, Vector
	function meta:GetSurfEdgesIndex( num )
		local surf = self:GetSurfEdges()[num]
		local edge = self:GetEdges()[abs( surf )]

		if surf >= 0 then
			return edge[1], edge[2]
		else
			return edge[2], edge[1]
		end
	end
end

-- Visibility, leafbrush and leaf functions
do
	--- Returns the visibility data.
	--- @return VisibilityInfo
	function meta:GetVisibility()
		if self._vis then return self._vis end

		local data = self:GetLump( 4 )
		local num_clusters = data:ReadLong()

		-- Check to see if the num_clusters match
		if num_clusters ~= self:GetLeafsNumClusters() then
			error( "Invalid NumClusters!" )
		end

		--- @class VisibilityInfo
		--- @field VisData VisbilityData[] # Visibility data
		--- @field num_clusters number # Number of clusters
		local t = { VisData = {} }
		local visData = t.VisData

		for i = 0, num_clusters - 1 do
			--- @class VisbilityData
			--- @field PVS number
			--- @field PAS number
			local v = {}
			v.PVS = data:ReadULong()
			v.PAS = data:ReadULong()

			visData[i] = v
		end

		data:Seek( 0 )

		local bytebuff = {}
		for i = 0, bit.rshift( data:Size() - data:Tell(), 3 ) - 1 do
			bytebuff[i] = data:ReadByte()
		end

		t._bytebuff = bytebuff
		t.num_clusters = num_clusters
		self._vis = t

		self:ClearLump( 4 )
		return t
	end

	local TEST_EPSILON			= 0.1
	local dot = Vector().Dot

	--- Returns the leaf the point is within. Use 0 If unsure about iNode.
	--- @param iNode number
	--- @param point Vector
	--- @return BSPLeafObject
	function meta:PointInLeaf( iNode, point )
		if iNode < 0 then
			return self:GetLeafs()[-1 -iNode]
		end

		local node = self:GetNodes()[iNode]
		local plane = self:GetPlanes()[node.planenum]
		local dist = dot(point, plane.normal ) - plane.dist

		if dist > TEST_EPSILON then
			return self:PointInLeaf( node.children[1], point )
		elseif dist < -TEST_EPSILON then
			return self:PointInLeaf( node.children[2], point )
		else
			local pTest = self:PointInLeaf( node.children[1], point )
			if pTest.cluster ~= -1 then
				return pTest
			end

			return self:PointInLeaf( node.children[2], point )
		end
	end

	--- Returns the contents of the point.
	--- @param point Vector
	--- @return CONTENTS # Contents of the point
	function meta:PointContents( point )
		local leaf = self:PointInLeaf( 0, point )
		return leaf.contents
	end

	--- Returns the leaf the point is within, but allows caching by feeding the old VisLeaf. 
	--- Will also return a boolean indicating if the leaf is new.
	--- @param iNode number
	--- @param point Vector
	--- @param lastVis BSPLeafObject?
	--- @return BSPLeafObject
	--- @return boolean newLeaf
	function meta:PointInLeafCache( iNode, point, lastVis )
		if not lastVis then return self:PointInLeaf( iNode, point ), true end
		if point:WithinAABox( lastVis.mins, lastVis.maxs ) then return lastVis, false end
		return self:PointInLeaf( iNode, point ), true
	end

	--- Returns the vis-cluster from said point.
	--- @param position Vector
	--- @return number
	function meta:ClusterFromPoint( position )
		return self:PointInLeaf( 0, position ).cluster or -1
	end

	--- Computes the leaf-id the detail is within. -1 for none.
	--- @param position Vector
	--- @return number
	function meta:ComputeDetailLeaf( position )
		local node = 0
		local nodes = self:GetNodes()
		local planes = self:GetPlanes()

		while node > 0 do
			--- @type MapNode
			local n = nodes[node]
			--- @type BSPPlane
			local p = planes[n.planenum]

			if dot(position, p.normal ) < p.dist then
				node = n.children[2]
			else
				node = n.children[1]
			end
		end

		return - node - 1
	end

	local MAX_MAP_LEAFFACES = 65536

	--- Returns the leaf_face array. This is used to return a list of faces from a leaf.
	--- FaceID = LeafFace[ Leaf.firstleafface + [0 -> Leaf.numleaffaces - 1] ]
	--- @return number[]
	function meta:GetLeafFaces()
		if self._leaffaces then return self._leaffaces end

		--- @type number[]
		self._leaffaces = {}
		local data = self:GetLump( 16 )

		for i = 1, math.min( data:Size() / 16, MAX_MAP_LEAFFACES ) do
			self._leaffaces[i] = data:ReadUShort()
		end

		self:ClearLump( 16 )
		return self._leaffaces
	end

	local MAX_MAP_LEAFBRUSHES = 65536

	--- Returns an array of leafbrush-data.
	--- @return BSPBrushObject[]
	function meta:GetLeafBrushes()
		if self._leafbrush then return self._leafbrush end

		--- @type BSPBrushObject[]
		self._leafbrush = {}
		local data = self:GetLump( 17 )
		local brushes = self:GetBrushes()

		for i = 1, math.min( data:Size() / 16, MAX_MAP_LEAFBRUSHES ) do
			self._leafbrush[i] = brushes[data:ReadUShort()]
		end

		self:ClearLump( 17 )
		return self._leafbrush
	end

	--- Returns map-leafs in a table with cluster-IDs as key. Note: -1 is no cluster ID.
	--- @return table<number, BSPLeafObject[]>
	function meta:GetLeafClusters()
		if self._clusters then return self._clusters end

		--- @type table<number, BSPLeafObject[]>
		self._clusters = {}
		local leafs = self:GetLeafs()

		for i = 0, #leafs - 1 do
			local leaf = leafs[i]
			local cluster = leaf.cluster
			if self._clusters[cluster] then
				table.insert( self._clusters[cluster], leaf )
			else
				self._clusters[cluster] = { leaf }
			end
		end

		return self._clusters
	end

end

-- Faces and Displacments
do
	--- Returns the DispVerts data.
	--- @return DispVert[]
	function meta:GetDispVerts()
		if self._dispVert then return self._dispVert end

		--- @type DispVert[]
		self._dispVert = {}
		local data = self:GetLump( 33 )

		for i = 0, data:Size() / 160 - 1 do
			--- @class DispVert
			--- @field vec Vector
			--- @field dist number
			--- @field alpha number
			local t = {
				vec = data:ReadVector(),
				dist = data:ReadFloat(),
				alpha = data:ReadFloat()
			}

			self._dispVert[i] = t
		end

		self:ClearLump( 33 )
		return self._dispVert
	end

	--- Holds flags for the triangle in the displacment mesh.
	--- Returns the DispTris data
	--- @return number[]
	function meta:GetDispTris()
		if self._dispTris then return self._dispTris end

		--- @type number[]
		self._dispTris = {}
		local data = self:GetLump( 48 )

		for i = 0, data:Size() / 16 - 1 do
			self._dispTris[i] = data:ReadUShort()
		end

		self:ClearLump( 48 )
		return self._dispTris
	end

	local m_AllowedVerts = 10
	local m_Ddispinfo_t = 176 * 8

	--- Returns the DispInfo data.
	--- @return DispInfo[] # DispInfo
	--- @return table<number, DispInfo> # DispInfo By face
	function meta:GetDispInfo()
		if self._dispinfo then return self._dispinfo, self._dispinfo_byface end

		--- @type DispInfo[]
		self._dispinfo = {}

		--- @type DispInfo[]
		self._dispinfo_byface = {}

		local data = self:GetLump( 26 )
		local dispInfoCount = data:Size() / m_Ddispinfo_t

		local target = 0
		for i = 0, dispInfoCount - 1 do
			target = i * m_Ddispinfo_t

			if data:Tell() ~= target then
				print( "ERROR: Mismatched tell. Expected:", target, "got:", data:Tell(), "diff:", target - data:Tell() )
			end

			local function verify( expectedBytes )
				local here = data:Tell()
				assert( here == target + ( expectedBytes * 8 ), ( here - target ) / 8 )
			end

			--- @class DispInfo
			--- @field startPosition Vector
			--- @field DispVertStart number
			--- @field DispTriStart number
			--- @field power number
			--- @field minTess number
			--- @field smoothingAngle number
			--- @field contents CONTENTS|MASK # Contents of the displacement. ( MASK is a combination of CONTENTS )
			--- @field MapFace number
			--- @field LightmapAlphaStart number
			--- @field LightmapSamplePositionStart number
			local q = {}

			-- 4 bytes * 3 = 12 bytes
			q.startPosition = data:ReadVector()
			verify( 12 )

			-- 4 bytes
			q.DispVertStart = data:ReadLong()
			verify( 16 )

			-- 4 bytes
			q.DispTriStart = data:ReadLong()
			verify( 20 )

			-- 4 bytes
			q.power = data:ReadLong()
			assert( q.power >= 2, q.power )
			assert( q.power <= 4, q.power )
			verify( 24 )

			-- 2 bytes
			q.flags = data:ReadUShort()
			verify( 26 )

			-- 2 bytes
			q.minTess = data:ReadShort()
			verify( 28 )

			-- 4 bytes
			q.smoothingAngle = data:ReadFloat()
			verify( 32 )

			-- 4 bytes
			q.contents = data:ReadLong()
			verify( 36 )

			-- 2 bytes
			q.MapFace = data:ReadUShort()
			verify( 38 )

			-- 4 bytes 
			q.LightmapAlphaStart = data:ReadLong()
			verify( 42 )

			-- 4 bytes
			q.LightmapSamplePositionStart = data:ReadLong()
			verify( 46 )

			data:Skip( 88 * 8 )
			-- -- 48 bytes
			-- q.EdgeNeighbors = CDispNeighbor( data )
			-- verify( 94 )

			-- -- 40 bytes
			-- q.CornerNeighbors = CDispCornerNeighbors( data )
			verify( 134 )

			-- 4 bytes * 10 = 40 bytes
			q.allowedVerts = {}
			for v = 0, m_AllowedVerts - 1 do
				q.allowedVerts[v] = data:ReadLong()
			end
			assert( table.Count( q.allowedVerts ) == 10, table.Count( q.allowedVerts ) )
			verify( 174 )

			data:Skip( 8 * 2 )

			local offset = i * m_Ddispinfo_t
			q.offset = offset

			self._dispinfo[i] = q
			self._dispinfo_byface[q.MapFace] = q
		end

		self:ClearLump( 26 )
		return self._dispinfo, self._dispinfo_byface
	end

	local MAX_MAP_FACES = 65536

	--- Returns all original faces. ( Warning, uses a lot of memory )
	--- @return OriginalFace[]
	function meta:GetOriginalFaces()
		if self._originalfaces then return self._originalfaces end

		--- @class OriginalFace[]
		self._originalfaces = {}
		local data = self:GetLump( 27 )

		for i = 1, math.min( data:Size() / 448, MAX_MAP_FACES ) do
			--- @class OriginalFace
			--- @field styles number[]
			--- @field LightmapTextureMinsInLuxels number[]
			--- @field LightmapTextureSizeInLuxels number[]
			local t = {}
			t.plane 	= self:GetPlanes()[data:ReadUShort()]
			t.side 		= data:ReadByte()
			t.onNode 	= data:ReadByte()
			t.firstedge = data:ReadLong()
			t.numedges 	= data:ReadShort()
			t.texinfo 	= data:ReadShort()
			t.dispinfo				= data:ReadShort()
			t.surfaceFogVolumeID	= data:ReadShort()
			t.styles				= { data:ReadByte(), data:ReadByte(), data:ReadByte(), data:ReadByte() }
			t.lightofs				= data:ReadLong()
			t.area					= data:ReadFloat()
			t.LightmapTextureMinsInLuxels	= { data:ReadLong(), data:ReadLong() }
			t.LightmapTextureSizeInLuxels	= { data:ReadLong(), data:ReadLong() }
			t.origFace			= data:ReadLong()
			t.numPrims			= data:ReadUShort()
			t.firstPrimID		= data:ReadUShort()
			t.smoothingGroups	= data:ReadULong()
			t.__map = self
			t.__id = i
			self._originalfaces[i] = t
		end

		self:ClearLump( 27 )
		return self._originalfaces
	end
end

-- Model The brush-models embedded within the map. 0 is always the entire map.
do
	--- @class BModel
	local meta_bmodel = {}
	meta_bmodel.__index = meta_bmodel

	--- Returns a list of BModels ( Brush Models )
	--- @return BModel
	function meta:GetBModels()
		if self._bmodel then return self._bmodel end
		self._bmodel = {}
		local data = self:GetLump( 14 )
		for i = 0, data:Size() / 384 - 1 do
			--- @class BModel
			local t = {}
			t.mins = data:ReadVector()
			t.maxs = data:ReadVector()
			t.origin = data:ReadVector()
			t.headnode = data:ReadLong()
			t.firstface = data:ReadLong()
			t.numfaces = data:ReadLong()
			t.__map = self
			setmetatable( t, meta_bmodel )
			self._bmodel[i] = t
		end

		self:ClearLump( 14 )
		return self._bmodel
	end

	--- Returns a list of Faces making up this bmodel
	--- @return BSPFaceObject[]
	function meta_bmodel:GetFaces()
		local t = {}
		local c = 1
		local faces = self.__map:GetFaces()

		for i = self.firstface, self.firstface + self.numfaces - 1 do
			t[c] = faces[i]
			c = c + 1
		end

		return t
	end

	--- Locates the BModelIndex for the said faceIndex
	--- @param faceId number
	--- @return number
	function meta:FindBModelIDByFaceIndex( faceId )
		local bModels = self:GetBModels()

		for i = 0, #bModels do
			local q = bModels[i]
			if q.numfaces >= 0 and faceId >= q.firstface and faceId < q.firstface + q.numfaces then
				return i
			end
		end

		return 0
	end
end

-- Special custom functions
do
	local lower = string.lower

	--- Returns true if the position is outside the map
	--- @param position Vector
	--- @return boolean
	function meta:IsOutsideMap( position )
		local leaf = self:PointInLeaf( 0, position )
		if not leaf then return true end -- No leaf? Shouldn't be possible.
		return leaf:IsOutsideMap()
	end

	--- Returns a list of all materials used by the map.
	--- @return IMaterial[]
	function meta:GetMaterials()
		if self._materials then	return self._materials end

		--- @type IMaterial[]
		self._materials = {}

		for _, v in pairs( self:GetTextures() ) do
			if v then
				local m = Material( v )
				if m then table.insert( self._materials, m ) end
			end
		end

		return self._materials
	end

	--- Returns true if the texture is used by the map.
	--- @param texture string
	--- @return boolean
	function meta:HasTexture( texture )
		texture = lower( texture )

		for _, v in pairs( self:GetTextures() ) do
			if v and lower( v ) == texture then
				return true
			end
		end

		return false
	end

	--- Returns true if the material is used by the map.
	--- @param material IMaterial
	--- @return boolean
	function meta:HasMaterial( material )
		return self:HasTexture( material:GetName() )
	end

	--- Returns true if the skybox is rendering at this position.
	--- Note: Seems to be broken in EP2 and beyond, where the skybox is rendered at all times regardless of position.
	--- @return boolean
	function meta:IsRenderingSkyboxAtPosition( position )
		local leaf = self:PointInLeaf( 0, position )
		if not leaf then return false end -- No leaf? Shouldn't be possible
		return leaf:HasSkyboxInPVS()
	end

	--- Returns a list of skybox leafs (If the map has a skybox)
	--- @return BSPLeafObject[]
	function meta:GetSkyboxLeafs()
		if self._skyboxleafs then return self._skyboxleafs end

		--- @type BSPLeafObject[]
		self._skyboxleafs = {}

		local t = self:FindByClass( "sky_camera" )
		if #t < 1 then return self._skyboxleafs end -- Unable to locate skybox leafs

		local p = t[1].origin
		if not p then return self._skyboxleafs end
		local leaf = self:PointInLeaf( 0, p )
		if not leaf then return self._skyboxleafs end

		local area = leaf.area

		local i = 1
		for _, l in ipairs( self:GetLeafs() ) do
			if l.area == area then
				self._skyboxleafs[i] = l
				i = i + 1
			end
		end

		return self._skyboxleafs
	end

	--- Returns the size of the skybox
	--- @return Vector? # The minimum size of the skybox
	--- @return Vector? # The maximum size of the skybox
	function meta:GetSkyboxSize()
		if self._skyboxmin and self._skyboxmaxs then return self._skyboxmin, self._skyboxmaxs end

		for _, leaf in ipairs( self:GetSkyboxLeafs() ) do
			if not self._skyboxmin then
				self._skyboxmin = Vector( leaf.mins )
			else
				self._skyboxmin.x = math.min( self._skyboxmin.x, leaf.mins.x )
				self._skyboxmin.y = math.min( self._skyboxmin.y, leaf.mins.y )
				self._skyboxmin.z = math.min( self._skyboxmin.z, leaf.mins.z )
			end
			if not self._skyboxmaxs then
				self._skyboxmaxs = Vector( leaf.maxs )
			else
				self._skyboxmaxs.x = math.max( self._skyboxmaxs.x, leaf.maxs.x )
				self._skyboxmaxs.y = math.max( self._skyboxmaxs.y, leaf.maxs.y )
				self._skyboxmaxs.z = math.max( self._skyboxmaxs.z, leaf.maxs.z )
			end
		end

		return self._skyboxmin, self._skyboxmaxs
	end
end
