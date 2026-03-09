-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
-- License: https://github.com/Nak2/NikNaks/blob/main/LICENSE

local obj_tostring = "BSP %s [ %s ]"
local format = string.format

--- @class BSPObject
local meta = NikNaks.__metatables["BSP"]

--- @class BSPBrushObject
local meta_brush = {}
meta_brush.__index = meta_brush
meta_brush.__tostring = function( self ) return format( obj_tostring, "BSP Brush", self.__id ) end
meta_brush.MetaName = "BSP Brush"
NikNaks.__metatables["BSP Brush"] = meta_brush

local DIST_EPSILON = 0.03125
local MAX_MAP_BRUSHES = 16384
local MAX_MAP_BRUSHSIDES = 163840

--- Returns an array of the brush-data with brush-sides.
--- @return BSPBrushObject[]
function meta:GetBrushes()
	if self._brushes then return self._brushes end

	self._brushes = {}

	local data = self:GetLump( 18 )
	for id = 1, math.min( data:Size() / 96, MAX_MAP_BRUSHES ) do
		--- @class BSPBrushObject
		local t = {}
		local first = data:ReadLong()
		local num = data:ReadLong()
		t.contents = data:ReadLong()
		t.numsides = num
		--- @type BrushSideObject[]
		t.sides = {}
		t.__id = id
		t.__map = self

		local brushSides = self:GetBrushSides()
		local n = 1
		for i = first, first + num - 1 do
			t.sides[n] = brushSides[i]
			n = n + 1
		end

		self._brushes[id] = setmetatable( t, meta_brush )
	end

	self:ClearLump( 18 )
	return self._brushes
end

--- Returns an array of brushside-data.
--- @return BrushSideObject[]
function meta:GetBrushSides()
	if self._brushside then return self._brushside end

	self._brushside = {}

	local data = self:GetLump( 19 )
	local planes = self:GetPlanes()
	for i = 1, math.min( data:Size() / 64, MAX_MAP_BRUSHSIDES ) do
		--- @class BrushSideObject
		local t = {}
			t.plane = planes[ data:ReadUShort() ]
			t.texinfo = data:ReadShort()
			t.dispinfo = data:ReadShort()
			local q = data:ReadShort()
			t.bevel = bit.band( q, 0x1 ) == 1 -- Seems to be 1 if used for collision detection
			t.thin = bit.rshift( q, 8 ) == 1 -- For Portal 2 / Alien Swarm
		self._brushside[i - 1] = t
	end

	self:ClearLump( 19 )
	return self._brushside
end

---Returns the index of the brush.
---@return integer
function meta_brush:GetIndex()
	return self.__id or -1
end

--- Returns the content flag the brush has.
--- @return CONTENTS
function meta_brush:GetContents()
	return self.contents
end

--- Returns true if the brush has said content
--- @param CONTENTS CONTENTS
--- @return boolean
function meta_brush:HasContents( CONTENTS )
	if CONTENTS == 0 then return self.contents == CONTENTS end
	return bit.band( self.contents, CONTENTS ) ~= 0
end

-- Texture Stuff

--- Returns the TexInfo for the brush-side.
--- @param side number
--- @return table
function meta_brush:GetTexInfo( side )
	return self.__map:GetTexInfo()[self.sides[side].texinfo]
end

--- Returns the TexData for the brush-side.
--- @param side number
--- @return table
function meta_brush:GetTexData( side )
	return self.__map:GetTexData()[ self:GetTexInfo( side ).texdata]
end

--- Returns the texture for the brush-side.
--- @param side number
--- @return string
function meta_brush:GetTexture( side )
	local t = self:GetTexData( side ) or {}
	return t.nameStringTableID
end

--- Returns the Material for the brush-side.
--- @param side number
--- @return IMaterial
function meta_brush:GetMaterial( side )
	if self._material and self._material[side] then return self._material[side] end
	if not self._material then self._material = {} end

	self._material[side] = Material( self:GetTexture( side ) or "__error" )
	return self._material[side]
end

--- Returns all sides of the brush.
--- @return BrushSideObject[]
function meta_brush:GetSides()
	return self.sides
end

--- Returns a specific side of the brush (1-indexed).
--- @param n number
--- @return BrushSideObject?
function meta_brush:GetSide( n )
	return self.sides[n]
end

--- Returns the number of sides the brush has.
--- @return number
function meta_brush:GetNumSides()
	return self.numsides
end

--- Returns true if the brush is solid.
--- @return boolean
function meta_brush:IsSolid()
	return bit.band( self.contents, CONTENTS_SOLID ) ~= 0
end

--- Returns true if the brush is a water volume.
--- @return boolean
function meta_brush:IsWater()
	return bit.band( self.contents, CONTENTS_WATER ) ~= 0
end

--- Returns true if the brush is a player-clip (blocks players, not bullets).
--- @return boolean
function meta_brush:IsPlayerClip()
	return bit.band( self.contents, CONTENTS_PLAYERCLIP ) ~= 0
end

--- Returns true if the brush is an NPC-clip (blocks NPCs, not players or bullets).
--- @return boolean
function meta_brush:IsNPCClip()
	return bit.band( self.contents, CONTENTS_MONSTERCLIP ) ~= 0
end

do
	local MAX_MAP_COORD = 16384
	local CLIP_EPS      = 0.01

	---Clip poly
	local function clipPoly( verts, nx, ny, nz, dist )
		local nv = #verts
		if nv < 3 then return verts, {} end
		local out, clips = {}, {}
		for i = 1, nv do
			local a  = verts[i]
			local b  = verts[i % nv + 1]
			local da = nx * a.x + ny * a.y + nz * a.z - dist
			local db = nx * b.x + ny * b.y + nz * b.z - dist
			if da <= CLIP_EPS then out[#out + 1] = a end
			if ( da > CLIP_EPS ) ~= ( db > CLIP_EPS ) then
				local t = da / ( da - db )
				local p = Vector( a.x + ( b.x - a.x ) * t,
				                  a.y + ( b.y - a.y ) * t,
				                  a.z + ( b.z - a.z ) * t )
				out[#out + 1]   = p
				clips[#clips + 1] = p
			end
		end
		return out, clips
	end

	local function sortCapPoly( pts, nx, ny, nz )
		local n = #pts
		if n < 3 then return pts end
		-- Centroid
		local cx, cy, cz = 0, 0, 0
		for _, p in ipairs( pts ) do cx = cx + p.x; cy = cy + p.y; cz = cz + p.z end
		cx = cx / n; cy = cy / n; cz = cz / n
		-- Orthonormal tangent basis in the plane
		local ux = math.abs( nz ) < 0.9 and 0 or 1
		local uy = 0
		local uz = math.abs( nz ) < 0.9 and 1 or 0
		local tx = ny * uz - nz * uy;  local ty = nz * ux - nx * uz;  local tz = nx * uy - ny * ux
		local tl = math.sqrt( tx * tx + ty * ty + tz * tz )
		if tl < 1e-6 then return pts end
		tx = tx / tl;  ty = ty / tl;  tz = tz / tl
		-- bitangent = cross(tangent, normal) → right-handed basis, CCW from +normal
		local bx = ty * nz - tz * ny;  local by = tz * nx - tx * nz;  local bz = tx * ny - ty * nx
		-- Sort by angle
		local wa = {}
		for _, p in ipairs( pts ) do
			local dx, dy, dz = p.x - cx, p.y - cy, p.z - cz
			wa[#wa + 1] = { p = p, a = math.atan2( bx*dx + by*dy + bz*dz,
			                                        tx*dx + ty*dy + tz*dz ) }
		end
		table.sort( wa, function( a, b ) return a.a < b.a end )
		local s = {}
		for _, e in ipairs( wa ) do s[#s + 1] = e.p end
		-- Guarantee CCW winding by checking against the expected normal
		if #s >= 3 then
			local v1x = s[2].x - s[1].x;  local v1y = s[2].y - s[1].y;  local v1z = s[2].z - s[1].z
			local v2x = s[3].x - s[1].x;  local v2y = s[3].y - s[1].y;  local v2z = s[3].z - s[1].z
			local dot = ( v1y*v2z - v1z*v2y ) * nx
			          + ( v1z*v2x - v1x*v2z ) * ny
			          + ( v1x*v2y - v1y*v2x ) * nz
			if dot < 0 then
				local lo, hi = 1, #s
				while lo < hi do s[lo], s[hi] = s[hi], s[lo]; lo = lo + 1; hi = hi - 1 end
			end
		end
		return s
	end

	--- Fan-triangulate a convex polygon, appending { pos, normal } vertices to tris.
	local function fanTri( verts, normal, tris )
		local n = #verts
		if n < 3 then return end
		local p0 = verts[1]
		for i = 2, n - 1 do
			tris[#tris + 1] = { pos = p0,         normal = normal }
			tris[#tris + 1] = { pos = verts[i],   normal = normal }
			tris[#tris + 1] = { pos = verts[i+1], normal = normal }
		end
	end

	--- Core carving function.
	--- planelist: array of { nx, ny, nz, dist } half-spaces (keep dot(n,p) <= dist).
	--- Returns a flat { pos = Vector, normal = Vector }[] triangle list.
	local function carveBox( planelist )
		local m = MAX_MAP_COORD
		local polys = {
			{ n = Vector( 0, 0,-1), v = { Vector(-m,-m,-m), Vector(-m, m,-m), Vector( m, m,-m), Vector( m,-m,-m) } },
			{ n = Vector( 0, 0, 1), v = { Vector(-m,-m, m), Vector( m,-m, m), Vector( m, m, m), Vector(-m, m, m) } },
			{ n = Vector( 0,-1, 0), v = { Vector(-m,-m,-m), Vector( m,-m,-m), Vector( m,-m, m), Vector(-m,-m, m) } },
			{ n = Vector( 0, 1, 0), v = { Vector(-m, m,-m), Vector(-m, m, m), Vector( m, m, m), Vector( m, m,-m) } },
			{ n = Vector(-1, 0, 0), v = { Vector(-m,-m,-m), Vector(-m,-m, m), Vector(-m, m, m), Vector(-m, m,-m) } },
			{ n = Vector( 1, 0, 0), v = { Vector( m,-m,-m), Vector( m, m,-m), Vector( m, m, m), Vector( m,-m, m) } },
		}

		for _, pl in ipairs( planelist ) do
			local pnx, pny, pnz, pd = pl.nx, pl.ny, pl.nz, pl.dist
			local newPolys, capPts = {}, {}

			for _, poly in ipairs( polys ) do
				local clipped, clips = clipPoly( poly.v, pnx, pny, pnz, pd )
				if #clipped >= 3 then
					newPolys[#newPolys + 1] = { n = poly.n, v = clipped }
				end
				for _, cp in ipairs( clips ) do capPts[#capPts + 1] = cp end
			end

			-- Build cap polygon from the intersection edge points.
			if #capPts >= 3 then
				local unique = {}
				for _, p in ipairs( capPts ) do
					local dup = false
					for _, u in ipairs( unique ) do
						if math.abs( p.x - u.x ) < 0.1
						and math.abs( p.y - u.y ) < 0.1
						and math.abs( p.z - u.z ) < 0.1 then dup = true; break end
					end
					if not dup then unique[#unique + 1] = p end
				end
				if #unique >= 3 then
					local sorted = sortCapPoly( unique, pnx, pny, pnz )
					newPolys[#newPolys + 1] = { n = Vector( pnx, pny, pnz ), v = sorted }
				end
			end

			polys = newPolys
		end

		local tris = {}
		for _, poly in ipairs( polys ) do fanTri( poly.v, poly.n, tris ) end
		return tris
	end

	--- Generates a triangle list for the brush by carving a box with its planes.
	--- @return PolygonMeshVertex[]
	function meta_brush:GenerateVertexData()
		if self._vertData then return self._vertData end
		local planelist = {}
		for i = 1, self.numsides do
			local n = self.sides[i].plane.normal
			planelist[i] = { nx = n.x, ny = n.y, nz = n.z, dist = self.sides[i].plane.dist }
		end
		self._vertData = carveBox( planelist )
		return self._vertData
	end

	if CLIENT then
		--- Builds and caches an IMesh for the brush.
		--- @param col Color? Tint color (default white)
		--- @return IMesh|false
		function meta_brush:BuildMesh( col )
			if self._mesh ~= nil then return self._mesh end
			col = col or color_white
			local verts = self:GenerateVertexData()
			if not verts or #verts == 0 then self._mesh = false; return false end
			local cr, cg, cb, ca = col.r, col.g, col.b, col.a
			local nv = #verts
			self._mesh = Mesh()
			mesh.Begin( self._mesh, MATERIAL_TRIANGLES, nv / 3 )
			for i = 1, nv do
				local v = verts[i]
				mesh.Position( v.pos )
				mesh.Normal( v.normal )
				mesh.Color( cr, cg, cb, ca )
				mesh.TexCoord( 0, 0, 0 )
				mesh.AdvanceVertex()
			end
			mesh.End()
			table.insert( NIKNAKS_TABOMESH, self._mesh )
			return self._mesh
		end

		--- Deletes the cached mesh.
		--- @return self
		function meta_brush:DeleteMesh()
			if self._mesh then self._mesh:Destroy() end
			self._mesh  = nil
			self._vertData = nil
			return self
		end
	end

	NikNaks._carveBox = carveBox
end

--- Returns true if the point is inside the brush
--- @param position Vector
--- @return boolean
function meta_brush:IsPointInside( position )
	for i = 1, self.numsides do
		local side = self.sides[i]
		local plane = side.plane
		if plane.normal:Dot( position ) - plane.dist > DIST_EPSILON then
			return false
		end
	end

	return true
end
