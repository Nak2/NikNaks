-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
-- License: https://github.com/Nak2/NikNaks/blob/main/LICENSE

local NikNaks = NikNaks
NikNaks.Map = {}

local obj_tostring = "BSP %s [ %s ]"
local format = string.format

--- @class BSPObject
local meta = NikNaks.__metatables["BSP"]

--- @return File
local function openFile( self )
	assert( self._mapfile, "BSP object has nil mapfile path!" )
	return file.Open( self._mapfile, "rb", "GAME" )
end

--- Reads the lump header.
--- @param self BSPObject
--- @param f BitBuffer
local function read_lump_h( self, f )
	-- "How do we stop people loading L4D2 maps in other games?"
	-- "I got it, we scrample the header."

	--- @class BSPLumpHeader
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
--- @param fileName string
--- @return BSPObject
--- @return BSP_ERROR_CODE?
function NikNaks.Map( fileName )
	-- Handle filename
	if not fileName then
		if thisMapObject then return thisMapObject end -- Return this map
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
	--- Returns the mapname.
	--- @return string
	function meta:GetMapName()
		return self._mapname or "Unknown"
	end

	--- Returns the mapfile.
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
	--- @return number
	function meta:GetSize()
		return self._size
	end
end


-- Lump functions
do
	if SERVER then
		---Returns true if the server has a lumpfile for the given lump
		---@param lump_id number
		---@return bool
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

	-- A list of lumps that are known to be LZMA compressed for TF2 / other. In theory we could apply it to everything
	-- However there might be some rare cases where the data start with "LZMA", and trigger this.

	--- Returns the data lump as a bytebuffer. This will also be cached onto the BSP object.
	--- @param lump_id number
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
		local data

		-- Check for LUMPs
		local lumpPath = "maps/" .. self._mapname .. "_l_" .. lump_id .. ".lmp"
		if file.Exists( lumpPath, "GAME" ) then -- L4D has _s_ and _h_ files too. Depending on the gamemode.
			data = file.Read( lumpPath, "GAME" )
		elseif lump_h.filelen > 0 then
			local f = openFile( self )
			f:Seek( lump_h.fileofs )
			data = f:Read( lump_h.filelen )
			f:Close()
		else
			data = ""
		end

		-- TF2 have some maps that are LZMA compressed.
		data = LZMADecompress( data )

		-- Create bytebuffer object with the data and return it
		--- @type BitBuffer
		self._lumpstream[lump_id] = NikNaks.BitBuffer( data or "" )

		return self._lumpstream[lump_id]
	end

	--- Deletes lump_data cached in the BSP module.
	--- @param lump_id number
	function meta:ClearLump( lump_id )
		self._lumpstream[lump_id] = nil
	end

	--- Returns the lump version.
	--- @return number
	function meta:GetLumpVersion( lump_id )
		return self._lumpheader[ lump_id ].version
	end

	--- Returns the data lump as a datastring. 
	--- This won't be cached or saved, but it is faster than to parse the data into a bytebuffer and useful if you need the raw data.
	--- @param lump_id number
	--- @return string
	function meta:GetLumpString( lump_id )
		local lump_h = self._lumpheader[lump_id]
		assert( lump_h, "Tried to read invalid lumpheader!" )

		-- The raw lump data
		local data

		local lumpPath = "maps/" .. self._mapname .. "_l_" .. lump_id .. ".lmp"
		if file.Exists( lumpPath, "GAME" ) then
			data = file.Read( lumpPath, "GAME" )
		elseif lump_h.filelen > 0 then
			local f = openFile( self )
			f:Seek( lump_h.fileofs )
			data = f:Read( lump_h.filelen )
			f:Close()
		else
			data = ""
		end

		-- TF2 have some maps that are LZMA compressed.
		data = LZMADecompress( data )
		return data
	end

	--- Returns a list of gamelumps.
	--- @return BSPLumpHeader[]
	function meta:GetGameLumpHeaders()
		if self._gamelump then return self._gamelump end
		self._gamelump = {}

		local lump = self:GetLump( 35 )

		for i = 0, math.min( 63, lump:ReadLong() ) do
			--- @class BSPLumpHeader
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

	--- Returns gamelump number, matching the gLumpID.
	--- @param GameLumpID number
	--- @return BSPLumpHeader
	function meta:FindGameLump( GameLumpID )
		for _, v in pairs( self:GetGameLumpHeaders() ) do
			if v.id == GameLumpID then
				return v
			end
		end
	end

	--- @class GameLump
	--- @field buffer BitBuffer
	--- @field version number
	--- @field flags number

	--- Returns the game lump as a bytebuffer. This will also be cached on the BSP object.
	--- @param gameLumpID any
	---	@return GameLump
	function meta:GetGameLump( gameLumpID )
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

-- Word Data
do
	local default = [[detail\detailsprites.vmt]]

	--- Returns the detail-metail the map uses.
	--- @return string
	function meta:GetDetailMaterial()
		local wEnt = self:GetEntities()[0]
		return wEnt and wEnt.detailmaterial or default
	end

	--- Returns true if the map is a cold world. ( Flag set in the BSP )
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
	--- @class CubeMap
	local cubemeta = {}
	cubemeta.__index = cubemeta
	cubemeta.__tostring = function( self ) return
		format( obj_tostring, "Cubemap", "Index: " .. self:GetIndex() )
	end

	function cubemeta:GetPos() return self.origin end
	function cubemeta:GetSize() return self.size end
	function cubemeta:GetIndex() return self.id or -1 end
	function cubemeta:GetTexture() return self.texture end

	--- Returns the CubeMaps in the map.
	--- @return CubeMap[]
	function meta:GetCubemaps()
		if self._cubemaps then return self._cubemaps end

		local b = self:GetLump( 42 )
		local len = b:Size()

		--- @type CubeMap[]
		self._cubemaps = {}
		for _ = 1, math.min( 1024, len / 128 ) do
			--- @class CubeMap
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

	--- Returns the nearest cubemap to a position.
	--- @param pos Vector
	--- @return CubeMap
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

	--- @return string[]
	function meta:GetTexdataStringData()
		if self._texstr then return self._texstr end

		--- @type string[]
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
	--- @return TextureData[]
	function meta:GetTexData()
		if self._tdata then return self._tdata end

		--- @type TextureData[]
		self._tdata = {}

		-- Load TexdataStringTable		
		self:GetTextures()
		local b = self:GetLump( 2 )
		local count = b:Size() / 256 + 1

		for i = 0, count - 1 do
			--- @class TextureData
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
	--- Returns a list of all planes
	--- @return Plane[]
	function meta:GetPlanes()
		if self._plane then return self._plane end

		--- @type Plane[]
		self._plane = {}

		local data = self:GetLump( 1 )
		for i = 0, data:Size() / 160 - 1 do
			--- @class Plane
			local t = {}

			t.normal = data:ReadVector() -- Normal vector
			t.dist = data:ReadFloat() -- distance form origin
			t.type = data:ReadLong() -- plane axis indentifier

			self._plane[i] = t
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
		--- @field VisData VisbilityData[]
		local t = { VisData = {} }
		local visData = t.VisData

		for i = 0, num_clusters - 1 do
			--- @class VisbilityData
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
	--- Returns the leaf the point is within. Use 0 If unsure about iNode.
	--- @param iNode number
	--- @param point Vector
	--- @return LeafObject
	function meta:PointInLeaf( iNode, point )
		if iNode < 0 then
			return self:GetLeafs()[-1 -iNode]
		end

		local node = self:GetNodes()[iNode]
		local plane = self:GetPlanes()[node.planenum]
		local dist = point:Dot( plane.normal ) - plane.dist

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

	--- Returns the leaf the point is within, but allows caching by feeding the old VisLeaf. 
	--- Will also return a boolean indicating if the leaf is new.
	--- @param iNode number
	--- @param point Vector
	--- @param lastVis LeafObject?
	--- @return LeafObject
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
			--- @type Plane
			local p = planes[n.planenum]

			if position:Dot( p.normal ) < p.dist then
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
	--- @return BrushObject[]
	function meta:GetLeafBrushes()
		if self._leafbrush then return self._leafbrush end

		--- @type BrushObject[]
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
	--- @return table<number, LeafObject[]>
	function meta:GetLeafClusters()
		if self._clusters then return self._clusters end

		--- @type table<number, LeafObject[]>
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

	--- Returns the DispInfo data.
	--- @return DispInfo[]
	function meta:GetDispInfo()
		if self._dispinfo then return self._dispinfo end

		--- @type DispInfo[]
		self._dispinfo = {}
		local data = self:GetLump( 26 )

		for i = 0, data:Size() / 1408 - 1 do
			--- @class DispInfo
			local q = {}
			q.startPosition = data:ReadVector()
			q.DispVertStart = data:ReadLong()
			q.DispTriStart = data:ReadLong()
			q.power = data:ReadLong()
			q.minTess = data:ReadLong()
			q.smoothingAngle = data:ReadFloat()
			q.contents = data:ReadLong()
			q.MapFace = data:ReadUShort()
			q.LightmapAlphaStart = data:ReadLong()
			q.LightmapSamplePositionStart = data:ReadLong()
			-- 46 bytes used. 130 bytes left regarding corner neighbors .. ect
			-- allowedVerts are 40 bytes (10 * 4), therefore neighbors are 90 bytes
			data:Skip( 720 ) -- CDispCornerNeighbors + CDispNeighbor
			q.allowedVerts = {}
			for _ = 0, m_AllowedVerts - 1 do
				q.allowedVerts[i] = data:ReadULong()
			end
			self._dispinfo[i] = q
		end

		self:ClearLump( 26 )
		return self._dispinfo
	end

	---!! DEBUG FUNCTIONS !!
	function meta:GetMaterialMeshs()
		if self._materialmesh then return self._materialmesh end
		self._materialmesh = {}
		-- Build a list of faces-mesh data.
		local _meshData = {}
		local faces = self:GetFaces()
		for i = 1, #faces do
			local face = faces[i]
			local s = face:GetTexture()
			if not _meshData[s] then _meshData[s] = {} end
			local _facemesh = face:GenerateVertexTriangleData()
			if not _facemesh then continue end
			for i = 1, #_facemesh do
				table.insert( _meshData[s], _facemesh[i] )
			end
		end
		-- Generate the meshes
		for tex, meshData in pairs( _meshData ) do
			local _mat = Material( tex )
			local _mesh = Mesh( _mat )
			table.insert( _MESHBUILD, _mesh )
			mesh.Begin( _mesh, MATERIAL_TRIANGLES, #meshData )
			for i = 1, #meshData do
				local vert = meshData[i]
				-- > Mesh
				mesh.Normal( vert.normal )
				mesh.Position( vert.pos ) -- Set the position
				mesh.TexCoord( 0, vert.u, vert.v ) -- Set the texture UV coordinates
				mesh.TexCoord( 1, vert.lu, vert.lv ) -- Set the lightmap UV coordinates
				mesh.TexCoord( 2, vert.lu, vert.lv  ) -- Set the lightmap UV coordinates?
				--mesh.TexCoord( 2, self.LightmapTextureSizeInLuxels[1], self.LightmapTextureSizeInLuxels[2] ) -- Set the texture UV coordinates
				--mesh.TexCoord( 2, self.LightmapTextureMinsInLuxels[1], self.LightmapTextureMinsInLuxels[2] ) -- Set the texture UV coordinates
				mesh.AdvanceVertex()
			end
			mesh.End()
			self._materialmesh[_mat] = _mesh
		end
		return self._materialmesh
	end

	-- Do I need thse?
	local function BakeTriangles( triangle )
		for i = 1, #triangle, 3 do
			local A, B, C = triangle[ i ], triangle[ i + 1 ], triangle[ i + 2 ]
			local p = A.pos
			local edge1 = B.pos - p
			local edge2 = C.pos - p
			local deltaUV1 = Vector( B.u - A.u, B.v - A.v )
			local deltaUV2 = Vector( C.u - A.u, C.v - A.v )
			
			local f = 1 / (deltaUV1.x * deltaUV2.y - deltaUV2.x * deltaUV1.y);
			local tangent = Vector(0,0,0)
			local bitangent = Vector(0,0,0)

			tangent.x = f * (deltaUV2.y * edge1.x - deltaUV1.y * edge2.x)
			tangent.y = f * (deltaUV2.y * edge1.y - deltaUV1.y * edge2.y)
			tangent.z = f * (deltaUV2.y * edge1.z - deltaUV1.y * edge2.z)


			bitangent.x = f * (-deltaUV2.x * edge1.x + deltaUV1.x * edge2.x);
			bitangent.y = f * (-deltaUV2.x * edge1.y + deltaUV1.x * edge2.y);
			bitangent.z = f * (-deltaUV2.x * edge1.z + deltaUV1.x * edge2.z);

			local binormal = bitangent:GetNormalized()

			tangent = Vector(1,0,0)
			binormal = Vector(0,1,0)

			--bitangent = bitangent:GetNormalized()
			triangle[ i ].tangent = tangent
			triangle[ i + 1 ].tangent =tangent
			triangle[ i + 2 ].tangent = tangent
			
			triangle[ i ].binormal = binormal
			triangle[ i + 1 ].binormal = binormal
			triangle[ i + 2 ].binormal = binormal

			local udata = {0,0,1,1}
			triangle[ i ].userdata = udata
			triangle[ i + 1 ].userdata = udata
			triangle[ i + 2 ].userdata = udata
		end
	end

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
			--- @LightmapTextureMinsInLuxels number[]
			--- @LightmapTextureSizeInLuxels number[]
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
	--- @return FaceObject[]
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
		return leaf:Has2DSkyboxInPVS()
	end

	--- Returns a list of skybox leafs (If the map has a skybox)
	--- @return LeafObject[]
	function meta:GetSkyboxLeafs()
		if self._skyboxleafs then return self._skyboxleafs end

		--- @type LeafObject[]
		self._skyboxleafs = {}

		local t = self:FindByClass( "sky_camera" )
		if #t < 1 then return self._skyboxleafs end -- Unable to locate skybox leafs

		local p = t[1].origin
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
	--- @return Vector|nil
	--- @return Vector|nil
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

-- Old debug code below
if true then return end

function TESTVPS()
	--map:PVSForOrigin(Vector(0,0,0)) -- Warmup
	local vec = LocalPlayer():GetPos()
	local s = SysTime()
	local map = NikNaks.Map()
	local vec = map:PVSForOrigin(vec)
	print(string.format("%fs", SysTime() - s))
end


local cTrace, i = nil, 0

local oldLeaf
local matList = {}
PVS_DEBUG = false
hook.Add("PostDrawOpaqueRenderables", "TEST2", function(a, b)
	if a then return end
	local leaf, new = NikNaks.CurrentMap:PointInLeafCache(0, LocalPlayer():GetShootPos(), oldLeaf)
	--if not leaf then return end
	--leaf:DebugRender()
	if a or not PVS_DEBUG then return end
	--for id, leaf in pairs( NikNaks.CurrentMap:GetLeafClusters()[0] ) do
	--	leaf:DebugRender()
	--end
	local leaf, new = NikNaks.CurrentMap:PointInLeafCache(0, LocalPlayer():GetShootPos(), oldLeaf)
	
	oldLeaf = leaf
	if new then
		print(string.format("Leaf %i, Area %i, Cluster %i, Flags %i", leaf.__id, leaf.area, leaf.cluster, leaf.flags))
	end
	local PVS = NikNaks.CurrentMap:PVSForOrigin( EyePos())

	for _, leaf in pairs( PVS:GetLeafs() ) do
		if type(leaf) == "number" then continue end
		leaf:DebugRender( leaf:Has2DSkyInPVS() and Color(0,0,255) or leaf:Has3DSkyInPVS() and Color(255,0,0) or Color(0,255,0))
	end

	--for id, leaf2 in pairs( NikNaks.CurrentMap:GetLeafs() ) do
	--	if type(leaf2) == "number" then continue end
	--	if leaf2.area ~= leaf.area then continue end
	--	leaf2:DebugRender()
	--end
end)

hook.Add("PostDrawOpaqueRenderables", "TEST", function()
	if not NikNaks or not NikNaks.CurrentMap then return end
	if true then return end
	i = i + 1
	local a, b = Entity(497):GetPos(), Entity(498):GetPos()
	if i > 10 then
		cTrace = NikNaks.CurrentMap:TestTraceLeaf(a, b)
		i = 0
	end
	if not cTrace then return end
	--render.DrawLine( a, b, color_white, true )
	render.DrawLine( a, cTrace.hitpos, cTrace.hit and Color(0,255,0) or color_white, true )
	render.SetMaterial(mat)
	render.DrawQuadEasy( cTrace.hitpos, cTrace.hitnormal, 64, 64, color_white, (CurTime() * -20) % 360 )

	debugRender(cTrace)
end)


local mat = Material("effects/wheel_ring")
local cMat = Material("vgui/avatar_default")
local qMat = cMat
local lMat
local function GetMat( str )
	if lMat and lMat == str then return cMat end
	lMat = str
	cMat = Material(str)
	return cMat
end

local function debugRender( trace )
	local angle = EyeAngles()

	-- Only use the Yaw component of the angle
	angle = Angle( 0, angle.y - 90, 90 )
	local mat = cMat
	if trace.surface and trace.surface.nameStringTableID then
		mat = GetMat(trace.surface.nameStringTableID)
	end

	cam.Start3D2D( trace.hitpos, angle, .5 )
		draw.SimpleText( "Fraction: " .. trace.fraction, "Default", 0, 0, color_white )
		draw.SimpleText( "Hit: " .. tostring(trace.hit), "Default", 0, 14, color_white )
	cam.End3D2D()
	if not trace.hit then return end
	qMat:SetTexture("$basetexture", mat:GetTexture("$basetexture"))
	render.SetMaterial(qMat)
	render.DrawQuadEasy(trace.hitpos + Vector(0,0,32) -EyeAngles():Forward() * 10, -EyeAngles():Forward(), 32, 32, color_white, 180)
	qMat:SetTexture("$basetexture", "effects/wheel_ring")
end


local function emptyTrace()
	return {
		mins = Vector(0,0,0),
		maxs = Vector(0,0,0),
		extents = Vector(0,0,0)
	}
end

local NEVER_UPDATED = -9999
local DIST_EPSILON = 0.03125
function DM_ClipBoxToBrush(trace, mins, maxs, p1, p2, self)
	if self.numsides < 1 then return end
	
	local ofs = Vector(0,0,0)
	local dist = 0

	local enterfrac = NEVER_UPDATED
	local leavefrac = 1
	local clipplane

	local getout = false
	local startout = false
	local leadside = nil
	
	if not trace.ispoint then
		for i = 1, self.numsides - 1 do
			local side = self.sides[i]
			local plane = side.plane

			ofs.x = plane.normal.x < 0 and maxs.x or mins.x
			ofs.y = plane.normal.y < 0 and maxs.y or mins.y
			ofs.z = plane.normal.z < 0 and maxs.z or mins.z

			dist = ofs:Dot( plane.normal )
			dist = plane.dist - dist

			d1 = p1:Dot( plane.normal ) - dist
			d2 = p2:Dot( plane.normal ) - dist

			if d1 > 0 and d2 > 0 then return end

			if d2 > 0 then getout = true end
			if d1 > 0 then startout = true end

			if d1 <= 0 and d2 <= 0 then continue end

			if d1 > d2 then
				local f = (d1 - DIST_EPSILON) / (d1 - d2)
				if f > enterfrac then
					enterfrac = f
					clipplane = plane
					leadside = side
				end
			else
				f = (d1+DIST_EPSILON) / (d1 - d2)
				if f < leavefrac then leavefrac = f end
			end
		end
	else
		for i = 1, self.numsides - 1 do
			local side = self.sides[i]
			local plane = side.plane

			local texinfo = self.__map:GetTexInfo()[ side.texinfo ]
			local surfaces = self.__map:GetTexData()[ texinfo.texdata ]
			--if surfaces and surfaces.nameStringTableID == "TOOLS/TOOLSNODRAW" then continue end
			
			if side.bevel == 1 then continue end

			dist = plane.dist
			d1 = p1:Dot(plane.normal) - dist
			d2 = p2:Dot(plane.normal) - dist
			
			if d1 > 0 and d2 > 0 then return end

			if d2 > 0 then getout = true end
			if d1 > 0 then startout = true end
			
			if d1 < 0 and d2 < 0 then continue end
			if d1 > d2 then
				f = (d1 - DIST_EPSILON) / (d1-d2)
				if f > enterfrac then
					enterfrac = f
					clipplane = plane
					leadside = side
				end
			else
				f = (d1+DIST_EPSILON) / (d1-d2)
				if f < leavefrac then leavefrac = f end
			end
		end
	end
	if not startout then
		trace.startspolid = true
		if not getout then
			trace.allsolid = true
		end
		return
	end
	if enterfrac < leavefrac then
		if enterfrac > NEVER_UPDATED and enterfrac < trace.fraction then
			if enterfrac < 0 then
				enterfrac = 0
			end
			trace.fraction = enterfrac
			trace.plane = clipplane
			trace.type = clipplane.type
			if leadside.texinfo ~= -1 then
				local texinfo = self.__map:GetTexInfo()[ leadside.texinfo ]
				trace.surface = self.__map:GetTexData()[ texinfo.texdata ]
			else
				trace.surface = 0
			end
			trace.side = leadside
			trace.contents = self.contents
		end
	end
	return trace
end

function meta:TestTraceLeaf(from, to)
	local leaf = self:PointInLeaf(0, from)
	local flb = leaf.firstleafbrush

	local trace = emptyTrace()
	trace.startsolid = false
	trace.fraction = 1
	trace.ispoint = true
	trace.hitnormal = Vector(0,0,0)
	for i = 0, leaf.numleafbrushes - 1 do
		local v = self:GetLeafBrushes()[flb + i]
		--If brush is solid
		if bit.band(v.contents, 1) == 0 then continue end
		DM_ClipBoxToBrush( trace, trace.mins, trace.maxs, from, to, v)
		if trace.fraction ~= 1 or trace.startsolid then
			if trace.startsolid then
				trace.fraction = 0
			end
			trace.hit = true
			trace.hitnormal = trace.plane.normal
			trace.hitpos = from + (to - from) * trace.fraction
			return trace
		end
	end
	trace.hitpos = to
	trace.hit = false
	return trace
end

function meta:TestTrace(from, to)
	local trace = emptyTrace()
	trace.startsolid = false
	trace.fraction = 1
	trace.ispoint = false
	trace.hitnormal = Vector(0,0,0)
	for k, v in pairs( self:GetBrushes() ) do
		--local v = self:GetLeafBrushes()[flb + i]
		--If brush is solid
		if bit.band(v.contents, 1) == 0 then continue end
		DM_ClipBoxToBrush( trace, trace.mins, trace.maxs, from, to, v)
		if trace.fraction ~= 1 or trace.startsolid then
			if trace.startsolid then
				trace.fraction = 0
			end
			trace.hit = true
			trace.hitnormal = trace.plane.normal
			trace.hitpos = from + (to - from) * trace.fraction
			return trace
		end
	end
	trace.hitpos = to
	trace.hit = false
	return trace
end

-- Can't load these maps normally
local brokenMaps = {
	["d2_coast_02.bsp"] = true,
	["ep1_citadel_00_demo.bsp"] = true
}

local function assertMap( BSP )
	-- Check Entity
	local worldent = BSP:GetEntities()[0]
	assert(worldent.classname == "worldspawn", "Invalid MapEntity!")
	-- Check leaf
	local leaf = BSP:GetLeafs()[0]
	assert(leaf.numleaffaces == 0, "Invalid Leaf")
	assert(leaf.leafWaterDataID == -1, "Invalid Leaf")
	assert(leaf.maxs.x == 0, "Invalid Leaf")
	-- Check face
	local face = BSP:GetFaces()[0]
	assert(face, "Invalid Face")
	BSP:GetTextures()
end

function NikNaks.MapDebug( areYouSure )
	if not areYouSure or areYouSure ~= "iamsure" then return end
	print("Scanning all maps for any parse / data errors")
	local t = file.Find("maps/*.BSP", "GAME")
	local list = {}
	for _, mapString in pairs( t ) do
		if brokenMaps[mapString] then continue end
		table.insert(list, mapString)
	end
	local maps = #list
	local thread = coroutine.create(function()
		while true do
			if #list < 1 then coroutine.yield(true) return end
			local mapname = table.remove(list, 1)
			print("> Testing", mapname)
			local s = SysTime()
			local BSP = NikNaks.Map( mapname )
			assert( BSP, "Unable to parse MAP" )
			assertMap( BSP )
			print(string.format("%s took %fs", string.NiceSize(BSP._size), SysTime() - s))
			coroutine.wait( 0.1 )
		end
	end)
	hook.Add("Think", "NikNaks.BSPDEBUG", function()
		local noerr, yield = coroutine.resume( thread )
		if yield or not noerr then
			print(string.format("Scanned %i maps.", maps))
			hook.Remove("Think", "NikNaks.BSPDEBUG")
		end
	end)		
end
