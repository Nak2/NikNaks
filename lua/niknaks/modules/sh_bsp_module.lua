-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
local NikNaks = NikNaks
NikNaks.Map = {}
---@class BSPObject
local meta = {}
meta.__index = meta
meta.__tostring = function(self) return "BSP Map" .. (self._mapfile and " [" .. self._mapfile .. "]" or "[Empty]") end
meta.MetaName = "BSP"
debug.getregistry().BSP = meta

local function openFile( self )
	assert(self._mapfile, "BSP object has nil mapfile path!")
	local f = file.Open(self._mapfile,"rb","GAME")
	if not f then return end
	return f
end

-- Reads the lump header
local function read_lump_h( self, f )
	-- "How do we stop people loading L4D2 maps in other games?"
	-- "I got it, we scrample the header."
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
	else -- Try and figure it out
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

local nulls = string.char( 0, 0, 0, 0 )
-- Parse LZMA. These are for gamelumps, entities, PAK files and staticprops (Version 10?) from TF2
local function LZMADecompress( str )
	if str:sub(0, 4) ~= "LZMA" then return str end
	local actualSize= str:sub(5, 8)
	local lzmaSize 	= NikNaks.ByteBuffer.StringToInt( str:sub(9, 12) )
	if lzmaSize <= 0 then return "" end -- Invalid length
	local t = str:sub( 13, 17)
	local data = str:sub(18, 18 + lzmaSize) -- Why not just read all of it? What data is after this? Tell me your secrets Valve.
	return util.Decompress( t .. actualSize .. nulls .. data ) or str
end

-- Returns a BSP object to be read.
local thisMap, thisMapObject = "maps/" .. game.GetMap() .. ".bsp"

---Reads the BSP file and returns it as an object.
---@param fileName string
---@param keep_file_open? boolean
---@return BSPObject
---@return BSP_ERROR_CODE
function NikNaks.Map.ReadBSP( fileName )
	-- Handle filename
	if not fileName then
		if thisMapObject then return thisMapObject end -- Return this map
		fileName = thisMap
	else
		if not string.match(fileName,".bsp$") then fileName = fileName .. ".bsp" end -- Add file header
		if not string.match(fileName, "^maps/") and not file.Exists(fileName, "GAME") then -- Map doesn't exists and no folder indecated.
			fileName = "maps/" .. fileName	-- Add "maps" folder
		end
	end
	
	-- Check to see if it is the map we're on. This function might be called multiple times, better to cache it.
	if thisMap == fileName and thisMapObject then
		return thisMapObject
	end

	if not file.Exists(fileName,"GAME") then return nil, NikNaks.BSP_ERROR_FILENOTFOUND end -- File not found
	local f = file.Open(fileName,"rb","GAME")
	if not f then return nil, NikNaks.BSP_ERROR_FILECANTOPEN end -- Unable to open file

	-- Read the header
	if f:Read(4) ~= "VBSP" then
		f:Close()
		return nil, NikNaks.BSP_ERROR_NOT_BSP
	end

	-- Create BSP object
	local BSP = {}
	setmetatable(BSP, meta)
	BSP._mapfile = fileName
	BSP._size	 = f:Size()
	BSP._mapname = string.GetFileFromFilename( fileName )
	BSP._mapname = string.match(BSP._mapname, "(.+).bsp$") or BSP._mapname
	BSP._version = f:ReadLong()
	BSP._fileobj = f
	if BSP._version > 21 then
		f:Close()
		return nil, NikNaks.BSP_ERROR_TOO_NEW
	end

	-- Read Lump Header
	BSP._lumpheader = {}
	for i = 0, 63 do
		BSP._lumpheader[i] = read_lump_h( BSP, f )
	end
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
	---Returns the mapname.
	---@return striing
	function meta:GetMapName()
		return self._mapname or "Unknown"
	end

	---Returns the mapfile.
	---@return string
	function meta:GetMapFile()
		return self._mapfile or "No file"
	end

	---Returns the map-version.
	---@return number
	function meta:GetVersion()
		return self._version
	end
end

-- Lump functions
do
	-- A list of lumps that are known to be LZMA compressed for TF2 / other. In theory we could apply it to everything
	-- However there might be some rare cases where the data start with "LZMA", and trigger this.
	local LZMALumps = {
		[0] = true,
		[35]= true,
		[40]= true,
	}
	---Returns the data lump as a bytebuffer. This will also be cached onto the BSP object.
	---@param lump_id number
	---@return ByteBuffer
	function meta:GetLump( lump_id )
		local lumpStream = self._lumpstream[lump_id]
		if lumpStream then
			lumpStream:Seek(0) -- Reset the read position
			return lumpStream
		end
		local lump_h = self._lumpheader[lump_id]
		assert( lump_h, "Tried to read invalid lumpheader!" )
		-- Get raw data
		local data
		if file.Exists("maps/" .. self._mapname .. "_l_" .. lump_id .. ".lmp", "GAME") then -- L4D has _s_ and _h_ files too. Depending on the gamemode
			data = file.Read("maps/" .. self._mapname .. "_l_" .. lump_id .. ".lmp", "GAME")
		else
			local f = openFile( self )
			f:Seek(lump_h.fileofs)
			data = f:Read( lump_h.filelen )
			f:Close()
		end
		-- TF2 have some maps that are LZMA compressed.
		if LZMALumps[ lump_id ] then
			data = LZMADecompress( data )
		end
		-- Create bytebuffer object with the data and return it
		self._lumpstream[lump_id] = NikNaks.ByteBuffer.Create( data or "" )
		return self._lumpstream[lump_id]
	end

	---Deletes cached lummp_data
	---@param lump_id number
	function meta:ClearLump( lump_id )
		self._lumpstream[lump_id] = nil
	end

	---Returns the data lump as a datastring. 
	---This won't be cached or saved, but it is faster than to parse the data into a bytebuffer and useful if you need the raw data.
	---@param lump_id number
	---@return string
	function meta:GetLumpString( lump_id )
		local lump_h = self._lumpheader[lump_id]
		assert( lump_h, "Tried to read invalid lumpheader!" )
		-- Get raw data
		local data
		if file.Exists("maps/" .. self._mapname .. "_l_" .. lump_id .. ".lmp", "GAME") then
			data = file.Read("maps/" .. self._mapname .. "_l_" .. lump_id .. ".lmp", "GAME")
		else
			local f = openFile( self )
			f:Seek(lump_h.fileofs)
			data = f:Read( lump_h.filelen )
			f:Close()
		end
		-- TF2 have some maps that are LZMA compressed.
		if LZMALumps[ lump_id ] then
			data = LZMADecompress( data )
		end
		return data
	end

	---Returns a list of gamelumps.
	---@return table
	function meta:GetGameLumpHeaders( )
		if self._gamelump then return self._gamelump end
		self._gamelump = {}
		local lump = self:GetLump( 35 )
		for i = 0, math.min(63, lump:ReadLong() ) do
			self._gamelump[i] = {
				id = lump:ReadLong(),
				flags = lump:ReadUShort(),
				version = lump:ReadUShort(),
				fileofs = lump:ReadLong(),
				filelen = lump:ReadLong()
			}
		end
		self:ClearLump( 35 )
		return self._gamelump
	end

	---Returns gamelump number, matching the gLumpID.
	---@param GameLumpID number
	---@return table|nil
	function meta:FindGameLump( GameLumpID )
		for k, v in pairs( self:GetGameLumpHeaders() ) do
			if v.id == GameLumpID then
				return v
			end
		end
	end

	---Returns the game lump as a bytebuffer. This will also be cached on the BSP object.
	---@param gameLumpID any
	---@return ByteBuffer
	---@return number version
	---@return numeer flags
	function meta:GetGameLump(gameLumpID)
		if self._gamelumps[gameLumpID] then
			self._gamelumps[gameLumpID]:Seek(0)
			return self._gamelumps[gameLumpID]
		end
		local t = self:FindGameLump( gameLumpID )
		-- If no gamelump can be found, set and return an empty bytebuffer.
		if not t then
			self._gamelumps[gameLumpID] = NikNaks.ByteBuffer.Create()
			return self._gamelumps[gameLumpID]
		end
		local f = openFile( self )
		f:Seek( t.fileofs )
		self._gamelumps[gameLumpID] = NikNaks.ByteBuffer.Create( LZMADecompress( f:Read( t.filelen ) ) )
		return self._gamelumps[gameLumpID], t.version, t.flags
	end
end

-- Entities
do
	-- Parses raw data into a table
	local function parseDataToEnt( s )
		local t = {}
		local d = util.KeyValuesToTablePreserveOrder("t" .. s)
		local c = {}
		for i = 1, #d do
			local k = d[i].Key
			if t[k] then -- Multiple keys for this one
				if NikNaks.type(t[k]) ~= "table" then --Convert to a table
					t[k] = {t[k]}
				end
				table.insert(t[k], d[i].Value)
			else
				t[k] = d[i].Value
			end
		end
		return t
	end

	---Returns a list of all entities within the BSP.
	---@return table
	function meta:GetEntities()
		if self._entities then return self._entities end
		-- Since it is stringbased, it is best to keep it as a string.
		local data = self:GetLumpString(0) or ""
		-- Parse all entities
		self._entities = {}
		local i = 0
		for s in string.gmatch( data, "%{.-%\n}" ) do
			local t = parseDataToEnt(s)
			-- Convert a few things to make it easier
				t.origin = util.StringToType(t.origin or "0 0 0","Vector")
				t.angles = util.StringToType(t.angles or "0 0 0","Angle")
				local c = util.StringToType(t.rendercolor or "255 255 255","Vector")
				t.rendercolor = Color(c.x,c.y,c.z)
			self._entities[i] = t
			i = i + 1
		end
		return self._entities
	end

	---Returns the raw entity data said entity.
	---@param index number
	---@return table
	function meta:GetEntity( index )
		return self:GetEntities()[index]
	end

	---Returns a list of entity data, matching the class.
	---@param class string
	---@return table
	function meta:FindByClass( class )
		local t = {}
		for _, v in pairs( self:GetEntities() ) do
			if not v.classname then continue end
			if not string.match(v.classname, class) then continue end
			t[#t + 1] = v
		end
		return t
	end

	---Returns a list of entity data, matching the model.
	---@param model string
	---@return table
	function meta:FindByModel( model )
		local t = {}
		for _, v in pairs( self:GetEntities() ) do
			if not v.model then continue end
			if v.model ~= class then continue end
			t[#t + 1] = v
		end
		return t
	end

	---Returns a list of entity data, matching the name ( targetname ).
	---@param name string
	---@return table
	function meta:FindByName( name )
		local t = {}
		for _, v in pairs( self:GetEntities() ) do
			if not v.targetname then continue end
			if v.targetname ~= class then continue end
			t[#t + 1] = v
		end
		return t
	end

	---Returns a list of entity data, within the specified box. Note: This (I think) is slower than ents.FindInBox
	---@param boxMins Vector
	---@param boxMaxs Vector
	---@return table
	function meta:FindInBox( boxMins, boxMaxs )
		local t = {}
		for _, v in pairs( self:GetEntities() ) do
			if not v.origin then continue end
			if not v.origin:WithinAABox(boxMins, boxMaxs) then continue end
			t[#t + 1] = v
		end
		return t
	end

	---Returns a list of entity data, within the specified sphere. Note: This (I think) is slower than ents.FindInSphere
	---@param origin Vector
	---@param radius number
	function meta:FindInSphere( origin, radius )
		radius = radius ^ 2
		local t = {}
		for _, v in pairs( self:GetEntities() ) do
			if not v.origin then continue end
			if v.origin:DistToSqr(origin) > radius then continue end
			t[#t + 1] = v
		end
		return t
	end
end

-- Static Props
do
	local sp_meta = FindMetaTable("StaticProp")
	local function CreateStaticProp(f, version, m, staticSize)
		local s = f:Tell()
		local obj = {}
		-- Version 4
			obj.Origin = f:ReadVector()								-- Vector (3 float) 12 bytes
			obj.Angles = Angle( f:ReadFloat(),f:ReadFloat(),f:ReadFloat() )	-- Angle (3 float) 	12 bytes
		-- Version 4
			obj.PropType = m[f:ReadUShort() + 1]					-- unsigned short 			2 bytes
			obj.First_leaf = f:ReadUShort()						-- unsigned short 			2 bytes
			obj.LeafCount = f:ReadUShort()							-- unsigned short 			2 bytes
			obj.Solid = f:ReadByte()								-- unsigned char 			1 byte
			obj.Flags = f:ReadByte()								-- unsigned char 			1 byte
			obj.Skin = f:ReadLong()									-- int 						4 bytes
			obj.FadeMinDist = f:ReadFloat()							-- float 					4 bytes
			obj.FadeMaxDist = f:ReadFloat()							-- float 					4 bytes
			obj.LightingOrigin = f:ReadVector()							-- Vector (3 float) 		12 bytes
																	-- 56 bytes used
		-- Version 5
			if version >= 5 then
				obj.ForcedFadeScale = f:ReadFloat()					-- float 					4 bytes
			end
																	-- 60 bytes used
		-- Version 6 and 7
			if version >= 6 and version <= 7 then
				obj.MinDXLevel = f:ReadUShort()					-- unsigned short 			2 bytes
				obj.MaxDXLevel = f:ReadUShort()					-- unsigned short 			2 bytes
		-- Version 8
			elseif version >= 8 then
				obj.MinCPULevel = f:ReadByte()					-- unsigned char 			1 byte
				obj.MaxCPULevel = f:ReadByte()					-- unsigned char 			1 byte
				obj.MinGPULevel = f:ReadByte()					-- unsigned char 			1 byte
				obj.MaxGPULevel = f:ReadByte()					-- unsigned char 			1 byte
			end
		-- Version 7
			if version >= 7 then 									-- color32 ( 32-bit color) 	4 bytes
				obj.DiffuseModulation = Color( f:ReadByte() * 255,f:ReadByte() * 255,f:ReadByte() * 255,f:ReadByte() * 255 )
			end
		-- Somewhere between here are a lot of troubles. Lets reverse and start from the bottom it to be sure.
			local bSkip = 0
		-- Version 11 								UniformScale [4 bytes]
			if version >= 11 then
				f:Seek(s + staticSize - 4)
				obj.UniformScale = f:ReadFloat()
				bSkip = bSkip + 4
			else
				obj.UniformScale = 1 -- Scale is not supported in lower versions
			end
		-- Version 10+ (Bitflags) 					FlagsEx [4 bytes]
			if version >= 10 then -- unsigned int
				f:Seek(s + staticSize - bSkip - 4)
				obj.flags = f:ReadULong()
				bSkip = bSkip + 4
			end
		-- Version 9 and 10 						DisableX360 [4 bytes]
			if version >= 9 and version <= 10 then
				f:Seek(s + staticSize - bSkip - 4)
				obj.DisableX360 = f:ReadLong() ~= 0	-- bool (4 bytes)
			end
			setmetatable(obj, sp_meta)
		return obj,f:Tell() - s + bSkip
	end

	---Returns a list of staticprops.
	---@return table
	function meta:GetStaticProps()
		if self._staticprops then return self._staticprops end
		local b, version, flags = self:GetGameLump( 1936749168 ) -- 1936749168 == "sprp"
		if b:Size() < 1 then
			self._staticprops = {}
			self._staticprops_mdl = {}
			return self._staticprops
		end
		-- Load the model list. This list is used by the static_props.
		self._staticprops_mdl = {}
		local n = b:ReadLong()
		if n > 16384 then -- Check if we overread the max static props.
			ErrorNoHalt(self._mapfile .. " has more than 16384 models!")
			self._staticprops = {}
			return self._staticprops
		end
		for i = 1,n do
			-- All model-paths are saved as char[128]. Any overflow is nullbytes.
			local model = ""
			for i2 = 1,128 do
				local c = string.char(b:ReadByte())
				if string.match(c,"[%w_%-%.%/]") then
					model = model .. c
				end
			end
			self._staticprops_mdl[i] = model
		end
		-- Read the leafs. Unused atm.
		do
			local n = b:ReadLong()
			local mx = 16384 * 2
			if n > mx then
				ErrorNoHalt(self._mapfile .. " has more than " .. mx .. " staticprop leafs!")
				self._staticprops = {}
				return self._staticprops
			end
			for i = 1, n do
				b:ReadUShort() -- Unsigned
			end
		end
		-- Read static props
		local count = b:ReadLong()
		if count > 16384 then -- Check if we are above the max staticprop.
			ErrorNoHalt(self._mapfile .. " has more than 16384 staticprops!")
			self._staticprops = {}
			return self._staticprops
		end
		-- We calculate the amount of static props within this space. It is more stable.
		local staticStart = b:Tell()
		local endPos = b:Size()
		local staticSize = (endPos - b:Tell()) / count
		local staticUsed = 0
		self._staticprops = {}
		for i = 0, count - 1 do
			-- This is to try and get as much valid data we can.
			b:Seek(staticStart + staticSize * i)
			local sObj, sizeused = CreateStaticProp(b,version, self._staticprops_mdl, staticSize)
			staticUsed = sizeused
			sObj.Index = i
			self._staticprops[i] = sObj
		end
		return self._staticprops
	end

	---Returns the static-prop object from said index.
	---@param index number
	---@return StaticProp
	function meta:GetStaticProp( index )
		return self:GetStaticProps()[index]
	end

	---Returns a list of all static-prop models used by the map.
	---@return table
	function meta:GetStaticPropModels()
		if self._staticprops_mdl then return self._staticprops_mdl end
		self:GetStaticProps() -- If no model list, then load the gamelump.
		return self._staticprops_mdl
	end

	---Returns a list of all static-props matching the model.
	---@param model string
	---@return table
	function meta:FindStaticByModel( model )
		local t = {}
		for _, v in pairs( self:GetStaticProps() ) do
			if not v.PropType then continue end
			if v.PropType ~= class then continue end
			t[#t + 1] = v
		end
		return t
	end

	---Returns a list of all static-props, within the specified box.
	---@param boxMins Vector
	---@param boxMaxs Vector
	---@return table
	function meta:FindStaticInBox( boxMins, boxMaxs )
		local t = {}
		for _, v in pairs( self:GetStaticProps() ) do
			if not v.Origin then continue end
			if not v.Origin:WithinAABox(boxMins, boxMaxs) then continue end
			t[#t + 1] = v
		end
		return t
	end

	---Returns a list of all static-props, within the specified sphere.
	---@param origin Vector
	---@param radius number
	---@return table
	function meta:FindStaticInSphere( origin, radius )
		radius = radius ^ 2
		local t = {}
		for _, v in pairs( self:GetStaticProps() ) do
			if not v.Origin then continue end
			if v.Origin:DistToSqr(origin) > radius then continue end
			t[#t + 1] = v
		end
		return t
	end
end

-- Word Data
do
	function meta:GetDetailMaterial()
		local wEnt = self:GetEntities()[0]
		if not wEnt then return [[detail\detailsprites.vmt]] end
		return wEnt.detailmaterial
	end

	function meta:IsColdWorld()
		local wEnt = self:GetEntity(0)
		if not wEnt then return false end
		return wEnt.coldworld == 1
	end

	function meta:WorldMin()
		if self._wmin then return self._wmin end
		local wEnt = self:GetEntity(0)
		if not wEnt then
			self._wmin = NikNaks.vector_zero
			return self._wmin
		end
		self._wmin = util.StringToType(wEnt.world_mins or "0 0 0","Vector") or NikNaks.vector_zero
		return self._wmin
	end

	function meta:WorldMax()
		if self._wmax then return self._wmax end
		local wEnt = self:GetEntity(0)
		if not wEnt then
			self._wmax = NikNaks.vector_zero
			return self._wmax
		end
		self._wmax = util.StringToType(wEnt.world_maxs or "0 0 0","Vector") or NikNaks.vector_zero
		return self._wmax
	end

	function meta:GetBounds()
		return self:WorldMin(), self:WorldMax()
	end

	function meta:GetSkyBoxPos()
		if self._skyCamPos then return self._skyCamPos end
		local t = self:FindByClass("sky_camera")
		if #t < 1 then
			self._skyCamPos = NikNaks.vector_zero
		else
			self._skyCamPos = t[1].origin
		end
		return self._skyCamPos
	end

	function meta:GetSkyBoxScale()
		if self._skyCamScale then return self._skyCamScale end
		local t = self:FindByClass("sky_camera")
		if #t < 1 then
			self._skyCamScale = 1
		else
			self._skyCamScale = t[1].scale
		end
		return self._skyCamScale
	end

	function meta:HasSkyBox()
		if self._skyCam ~= nil then return self._skyCam end
		self._skyCam = #self:FindByClass("sky_camera") > 0
		return self._skyCam
	end
end

-- Cubemaps
do
	-- Create class
	---@class CubeMap
	local cubemeta = {}
	cubemeta.__index = cubemeta
	function cubemeta:GetPos()
		return self.origin
	end
	function cubemeta:GetSize()
		return self.size
	end
	function cubemeta:GetIndex()
		return self.id
	end
	function cubemeta:GetTexture()
		return self.texture
	end
	function meta:GetCubemaps()
		if self._cubemaps then return self._cubemaps end
		local b = self:GetLump( 42 )
		local len = b:Size()
		self._cubemaps = {}

		for i = 1, math.min(1024, len / 16) do
			local t = {}
			setmetatable(t, cubemeta)
			t.origin = Vector( b:ReadLong(), b:ReadLong(), b:ReadLong() )
			t.size = b:ReadLong()
			t.texture = ""
			if self:GetVersion() <= 19 then
				t.texture = "maps/" .. self:GetMapName() .. "/c" .. t.origin.x .. "_" .. t.origin.y .. "_" .. t.origin.z
			else
				t.texture = "maps/" .. self:GetMapName() .. "/c" .. t.origin.x .. "_" .. t.origin.y .. "_" .. t.origin.z .. ".hdr"
			end
			if t.size == 0 then
				t.size = 32
			end
			t.id = table.insert(self._cubemaps, t) - 1
		end
		self:ClearLump( 42 )
		return self._cubemaps
	end
	function meta:FindNearestCubemap( pos )
		local lr,lc
		for k,v in ipairs( self:GetCubemaps() ) do
			local cd = v:GetPos():DistToSqr(pos)
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
	local max_data = 256000

	---Returns a list of textures used by the map.
	---@return table
	function meta:GetTextures()
		if self._textures then return self._textures end
		local data = self:GetLumpString(43)
		self._textures = {}
		if #data > max_data then
			ErrorNoHalt(self._mapfile .. " has invalid TexDataStringData!")
			return self._textures
		end
		for s in string.gmatch( data, "[^%z]+" ) do
			table.insert(self._textures, s:lower())
		end
		return self._textures
	end

	---Returns a list of material-data used by the map
	---@return table
	function meta:GetTextureData()
		if self._tdata then return self._tdata end
		self._tdat = {}
		-- Load TexdataStringTable		
		local tex = self:GetTextures()
		local b = self:GetLump( 2 )
		local n = b:Size() / 32 + 1
		for I = 1, n do
			local t = {}
			t.reflectivity = b:ReadVector()
			local n = b:ReadLong()
			t.nameStringTableID = tex[n] or tostring(n)
			t.width = b:ReadLong()
			t.height = b:ReadLong()
			t.view_width = b:ReadLong()
			t.view_height = b:ReadLong()
			table.insert(self._tdat, t)
		end
		self:ClearLump( 2 )
		return self._tdat
	end

	---Returns a lsit of all materials used by the map
	function meta:GetMaterials()
		if self._materials then	return self._materials end
		self._materials = {}
		for k, v in ipairs( self:GetTextures() ) do
			if not v then continue end
			local m = Material( v )
			if not m then continue end
			table.insert(self._materials, m )
		end
		return self._materials
	end
end

-- Geometric Functions

-- Nodes, leafs and planes
do
	---Returns a list of all planes
	---@return table
	function meta:GetPlanes()
		if self._plane then return self._plane end
		self._plane = {}
		local data = self:GetLump( 1 )
		for i = 0, data:Size() / 20 - 1 do
			self._plane[i] = {
				["normal"] = data:ReadVector(), -- Normal vector
				["dist"] = data:ReadFloat(), -- distance form origin
				["type"] = data:ReadLong() -- plane axis indentifier
			}
		end
		self:ClearLump( 1 )
		return self._plane
	end

	local MAX_MAP_VERTEXS = 65536
	---Returns an array of coordinates of all the vertices (corners) of brushes in the map geometry.
	---@return table
	function meta:GetVertex()
		if self._vertex then return self._vertex end
		local data = self:GetLump( 3 )
		self._vertex = {}
		for i = 0, math.min(data:Size() / 12, MAX_MAP_VERTEXS ) - 1 do
			self._vertex[i] = data:ReadVector()
		end
		self:ClearLump(3)
		return self._vertex
	end

	local MAX_MAP_NODES = 65536
	---Returns a table of map nodes
	---@return table
	function meta:GetNodes()
		if self._node then return self._node end
		self._node = {}
		local data = Map.ReadBSP():GetLump(5)
		for i = 0, math.min( data:Size() / 32, MAX_MAP_NODES ) - 1 do
			local t = {}
				t.planenum = data:ReadLong()
				t.children = {data:ReadLong(), data:ReadLong()}
				t.mins = Vector(data:ReadShort(), data:ReadShort(), data:ReadShort())
				t.maxs = Vector(data:ReadShort(), data:ReadShort(), data:ReadShort())
				t.firstFace = data:ReadUShort()
				t.numFaces = data:ReadUShort()
				t.area = data:ReadShort()
				t.padding = data:ReadShort()
			self._node[i] = t
		end
		self:ClearLump( 5 )
		return self._node
	end

	---Returns a table of map leafs
	---@return table
	function meta:GetLeafs()
		if self._leafs then return self._leafs end
		self._leafs = {}
		local data = Map.ReadBSP():GetLump(10)
		local size = self._version <= 19 and 36 or 32 -- Wiki is wrong
		for i = 0, data:Size() / size - 1 do
			local t = {}
				t.contents = data:ReadLong() 	-- 4
				t.cluster = data:ReadShort() 	-- 6
				t.area = data:ReadShort()		-- 8
				t.flags = data:ReadShort()		-- 10
				t.mins = Vector(data:ReadShort(), data:ReadShort(), data:ReadShort()) -- 16
				t.maxs = Vector(data:ReadShort(), data:ReadShort(), data:ReadShort()) -- 22
				t.firstleafface = data:ReadUShort()		-- 24
				t.numleaffaces = data:ReadUShort()		-- 26
				t.firstleafbrush = data:ReadUShort()	-- 28
				t.numleafbrushes = data:ReadUShort()	-- 30
				t.leafWaterDataID = data:ReadShort()	-- 32
			if self._version <= 19 then
				t.padding = data:ReadShort()
			end
			self._leafs[i] = t
		end
		self:ClearLump( 10 )
		return self._leafs
	end

	local MAX_MAP_EDGES = 256000
	---Returns all edges
	---@return table
	function meta:GetEdges()
		if self._edge then return self._edge end
		local data = self:GetLump( 12 )
		self._edge = {}
		for i = 1, math.min(data:Size() / 4, MAX_MAP_EDGES) do
			self._edge[i] = {data:ReadShort(), data:ReadShort()}
		end
		self:ClearLump( 12 )
		return self._edge
	end

	local MAX_MAP_SURFEDGES = 512000
	---Returns all surfedges
	---@return table
	function meta:GetSurfEdges()
		if self._surfedge then return self._surfedge end
		local data = self:GetLump( 13 )
		self._surfedge = {}
		for i = 1, math.min( data:Size() / 4, MAX_MAP_SURFEDGES ) do
			self._surfedge[i] = data:ReadLong()
		end
		self:ClearLump( 13 )
		return self._surfedge
	end

	---Returns a list of LeafWaterData. Holds the data of leaf nodes that are inside water.
	---@return table
	function meta:GetLeafWaterData( )
		if self._pLeafWaterData then return self._pLeafWaterData end
		local data = self:GetLump( 36 )
		self._pLeafWaterData = {}
		for i = 1, data:Size() / 10 do
			local t = {}
			t.surfaceZ = data:ReadFloat()
			t.minZ = data:ReadFloat()
			t.surfaceTexInfoID = data:ReadShort()
			data:Skip(2) -- A short that is always 0x00
			table.insert(self._pLeafWaterData, t)
		end
		self:ClearLump( 36 )
		return self._pLeafWaterData
	end
end

-- Faces
do
	local MAX_MAP_FACES = 65536 
	---Returns all faces. ( Warning, uses a lot of memory )
	---@return table
	function meta:GetFaces()
		if self._faces then return self._faces end
		self._faces = {}
		local data = self:GetLump( 7 )
		for i = 1, math.min(data:Size() / 56, MAX_MAP_FACES) do
			local t = {}
			t.plane 	= self:GetPlanes()[ data:ReadUShort() ]
			t.side 		= data:ReadByte()
			t.onNode 	= data:ReadByte() -- 1 if on node, 0 if in leaf
			t.firstedge = data:ReadLong()
			t.numedges 	= data:ReadShort()
			t.texinfo 	= data:ReadShort() -- Texture info
			t.dispinfo	= data:ReadShort() -- Displacement info
			t.surfaceFogVolumeID	= data:ReadShort()
			t.styles				= {data:ReadByte(), data:ReadByte(), data:ReadByte(), data:ReadByte()}
			t.lightofs				= data:ReadLong()
			t.area					= data:ReadFloat()
			t.LightmapTextureMinsInLuxels	= {data:ReadLong(), data:ReadLong()}
			t.LightmapTextureSizeInLuxels	= {data:ReadLong(), data:ReadLong()}
			t.origFace			= data:ReadLong()
			t.numPrims			= data:ReadUShort()
			t.firstPrimID		= data:ReadUShort()
			t.smoothingGroups	= data:ReadULong()
			self._faces[i] = t
		end
		self:ClearLump( 7 )
		return self._faces
	end

	---Returns all original faces. ( Warning, uses a lot of memory )
	---@return table
	function meta:GetOriginalFaces()
		if self._originalfaces then return self._originalfaces end
		self._originalfaces = {}
		local data = self:GetLump( 27 )
		for i = 1, math.min(data:Size() / 56, MAX_MAP_FACES) do
			local t = {}
			t.plane 	= self:GetPlanes()[ data:ReadUShort() ]
			t.side 		= data:ReadByte()
			t.onNode 	= data:ReadByte()
			t.firstedge = data:ReadLong()
			t.numedges 	= data:ReadShort()
			t.texinfo 	= data:ReadShort()
			t.dispinfo				= data:ReadShort()
			t.surfaceFogVolumeID	= data:ReadShort()
			t.styles				= {data:ReadByte(), data:ReadByte(), data:ReadByte(), data:ReadByte()}
			t.lightofs				= data:ReadLong()
			t.area					= data:ReadFloat()
			t.LightmapTextureMinsInLuxels	= {data:ReadLong(), data:ReadLong()}
			t.LightmapTextureSizeInLuxels	= {data:ReadLong(), data:ReadLong()}
			t.origFace			= data:ReadLong()
			t.numPrims			= data:ReadUShort()
			t.firstPrimID		= data:ReadUShort()
			t.smoothingGroups	= data:ReadULong()
			self._originalfaces[i] = t
		end
		self:ClearLump( 27 )
		return self._originalfaces
	end
end

-- Brushes
do
	-- NOTE: A lot of map creators delete this lump, to stop others decompiling their map.
	local MAX_MAP_BRUSHES = 8192
	function meta:GetBrushs()
		if self._brushes then return self._brushes end
		self._brushes = {}
		local data = self:GetLump( 18 )
		for i = 1, math.min(data:Size() / 12, MAX_MAP_BRUSHES) do
			local t = {}
			local first = data:ReadLong()
			local num = data:ReadLong()
			t.contents = data:ReadLong()
			t.sides = {}
			for i = first, first + num - 1 do
				t.sides[#t.sides + 1] = self:GetBrusheSides()[i]
			end
			table.insert(self._brushes,t)
		end
		self:ClearLump( 18 )
		return self._brushes
	end

	local MAX_MAP_BRUSHSIDES = 65536 
	function meta:GetBrusheSides()
		if self._brushside then return self._brushside end
		self._brushside = {}
		local data = self:GetLump( 19 )
		for i = 1, math.min(data:Size() / 8, MAX_MAP_BRUSHSIDES) do
			local t = {}
				t.plane = self:GetPlanes()[ data:ReadUShort() ]
				t.texinfo = data:ReadShort()
				t.dispinfo = data:ReadShort()
				t.bevel = data:ReadShort() -- Seems to be 1 if used for collision detection
			table.insert(self._brushside,t)
		end
		self:ClearLump( 19 )
		return self._brushside
	end
end