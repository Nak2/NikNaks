-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
local NikNaks = NikNaks
local CurTime, setmetatable, IsValid = CurTime, setmetatable, IsValid
local min, max, cos = math.min, math.max, math.cos

--- @class LPathFollower
--- @field _segments LPathFollowerSegment[]
local meta = {}
meta.__index = meta
meta.__tostring = function( self )
	return "LPathFollower Age: " .. self:GetAge()
end
NikNaks.__metatables["LPathFollower"] = meta

--[[
	t._segments = {}
	t._entity = nil		-- Overrides the last position in the segments
	t._age = CurTime()
	
]]
--- Creates an empty path-follower
--- @param start_pos  Vector
--- @return LPathFollower
function meta.CreatePathFollower( start_pos )
	--- @class LPathFollower
	local t = {}
	t._segments = {}
	t._start = start_pos
	t._length = 0
	t._age = CurTime()
	t._valid = true
	t._cursor = 1
	t._cursor_dis = 0
	t._cursor_lef = 0

	return setmetatable( t, meta )
end

--- Adds a segment.
--- @param from Vector
--- @param to Vector
--- @param curvature number
--- @param move_type number
--- @return LPathFollowerSegment
function meta:AddSegment( from, to, curvature, move_type )
	--- @class LPathFollowerSegment
	local seg = {}
		seg.curvature = curvature or 0
		seg.move_type = move_type or 1
		seg.distanceFromStart = from:Distance( to )

		local n = ( to - from ):GetNormalized()
		seg.forward = n
		seg.yaw = ( -n ):Angle().y

		if n.z > 0.7 or n.z < -0.7 then
			self.how = 9
		else
			if n.y < -0.5 then -- North
				seg.how = 0
			elseif n.y > 0.5 then -- South
				seg.how = 2
			elseif n.x > 0.5 then -- East
				seg.how = 1
			else				-- West
				seg.how = 3
			end
		end

		seg.length = from:Distance( to )
		seg.s_lengh = self._length
		seg.pos = to
		--seg.ladder
		--seg.node
		--seg.area
		--seg.nna

	self._length = self._length + seg.length
	self._segments[#self._segments + 1] = seg
	return seg
end

-- Default easy functions
do
	--- Returns the length of the path.
	function meta:GetLength()
		return self._length or 0
	end

	--- Returns the first segment.
	function meta:FirstSegment()
		return self._segments[1]
	end

	--- Returns the last segment.
	function meta:LastSegment()
		return self._segments[#self._segments]
	end

	--- Returns all segments.
	function meta:GetAllSegments()
		return self._segments
	end

	--- Returns the age of the path.
	function meta:GetAge()
		return CurTime() - self._age
	end

	--- Resets the age of the path.
	function meta:ResetAge()
		self._age = CurTime()
	end

	--- Returns true if the path is valid.
	function meta:IsValid()
		return self._valid or false
	end

	--- Invalidates the path.
	function meta:Invalidate()
		self._valid = false
	end

	--- Returns the starting position of the path.
	function meta:GetStart()
		return self._start
	end

	--- Returns the ending position of the path (Note, will update if the target is an entity).
	function meta:GetEnd()
		if IsValid( self.target_ent ) then
			return self.target_ent:GetPos()
		end

		return self._segments[#self._segments].pos
	end
end

-- Cursor
local findClosestSeg
do
	--- Returns the cursor position.
	--- @return number
	--- @return number
	local function findCursor( self, distance )
		local q = self._segments
		distance = min( self._length, distance )

		for i = 1, #q do
			if distance <= q[i].s_lengh + q[i].length then
				return i, distance - ( q[i].s_lengh + q[i].length )
			end
		end

		return 1, distance
	end

	--- Returns the closest segment and its index.
	--- @param position Vector
	--- @return LPathFollowerSegment
	--- @return number
	findClosestSeg = function( self, position )
		local c, d, q

		for i, seg in pairs( self._segments ) do
			local dis = seg.pos:DistToSqr( position )
			if not c or c > dis then
				c = dis
				d = seg
				q = i
			end
		end

		return d, q
	end

	--- Returns the closest position along the path to said position.
	--- @param position Vector
	--- @return Vector
	local function findClosestBetween( A, dir, position, maxLength )
		local v = position - A
		local d = v:Dot( dir )
		return A + dir * max( 0, min( d, maxLength ) )
	end

	--- Returns the position on the path by given distance
	--- @param distance number
	--- @return Vector
	function meta:GetPositionOnPath( distance )
		local seg_id, lef = findCursor( self, distance )
		local t = self._segments
		local seg = t[seg_id]
		return seg.pos + seg.forward * lef
	end

	--- Returns the closest position along the path to said position.
	--- @param position Vector
	--- @return Vector
	function meta:GetClosestPosition( position )
		-- Locate the closest points
		local seg, seg_id = findClosestSeg( self, position )
		if not seg then return self:GetStart() end -- Fallback to the start pos

		local max_seg = #self._segments

		if seg_id <= 1 then
			local n_seg = self._segments[seg_id + 1]
			local v1 = findClosestBetween( self:GetStart(), seg.forward, position, seg.length )
			local v2 = findClosestBetween( seg.pos, n_seg.forward, position, n_seg.length )
			if v1:DistToSqr( position ) > v2:DistToSqr( position ) then
				return v2
			else
				return v1
			end
		elseif seg_id >= max_seg then
			local s_seg = self._segments[max_seg - 1]
			return findClosestBetween( s_seg.pos, seg.forward, position, seg.length )
		else
			local p_seg = self._segments[seg_id - 1]
			local n_seg = self._segments[seg_id + 1]
			local v1 = findClosestBetween( p_seg.pos, seg.forward, position, seg.length )
			local v2 = findClosestBetween( seg.pos, n_seg.forward, position, n_seg.length )
			if v1:DistToSqr( position ) > v2:DistToSqr( position ) then
				return v2
			else
				return v1
			end
		end
	end

	--- Moves the cursor to the start of the path.
	function meta:MoveCursorToStart()
		self._cursor_dis = 0
		self._cursor_lef = 0
		self._cursor = 1
	end

	--- Moves the cursor to the end of the path.
	function meta:MoveCursorToEnd()
		self._cursor_dis = self:GetLength()
		self._cursor = #self._segments
		self._cursor_lef = self._segments[self._cursor].length
	end

	--- Returns the cursor progress along the path
	--- @return number
	function meta:GetCursorPosition()
		return self._cursor_dis
	end

	--- Moves the cursor to said distance.
	--- @param distance number
	function meta:MoveCursorTo( distance )
		self._cursor_dis = distance
		local seg_id, lef = findCursor( self, distance )
		self._cursor = seg_id
		self._cursor_lef = lef
	end

	--- Moves the cursor said distance
	--- @param distance number
	function meta:MoveCursor( distance )
		self._cursor_dis = self._cursor_dis + distance
		local nd = self._cursor_lef + distance
		local seg = self._segments[self._cursor]
		if nd < 0 or nd > seg.length then -- New segment
			local seg_id, lef = findCursor( self, self._cursor_dis )
			self._cursor = seg_id
			self._cursor_lef = lef
		else
			self._cursor_lef = nd
		end
	end

	--- Returns the closest sequence.
	--- @param position Vector
	--- @return LPathFollowerSegment
	--- @return number
	function meta:FindClosestSeg( position )
		return findClosestSeg( self, position )
	end

	--- Returns the distance from the path.
	--- @param position Vector
	--- @return number
	function meta:FindDistanceFromPath( position )
		return self:GetClosestPosition( position ):Distance( position )
	end

end

-- NPC stuff
do
	--[[
		By default in Gmod, you're reuired to create a pathfind object, and then compute it.
		However I've found many situations where I could reuse a path. I.e a group of NPC's.
		So to stick to the closest "Gmod way", path:Update can be called on multiple entities and got a goal argument.

		C function here: https://github.com/Joshua-Ashton/Source-PlusPlus/blob/4056819cea889d73626a1cbc09518b2f8ba5dda4/src/game/shared/cstrike/bot/nav_path.cpp#L472 
	]]
	function meta:Update( ent, toleranceSqrt )
		-- Make sure it is a valid entity and it has loco
		if not IsValid( ent ) or not ent.loco then return true end

		local entPos = ent:GetPos()
		local seq, id = nil, ent._cursor

		-- Located the closest segment, and use that
		if not id then
			seq, id = findClosestSeg( self, entPos )
			ent._cursor = id
		else
			seq = self._segments[id]
		end

		if not seq then return true end -- No segment, we must have reached the end

		local goal = seq.pos
		if goal:DistToSqr( entPos ) < toleranceSqrt then
			if id >= #self._segments then return true end -- Reached the end
			id = id + 1
			seq = self._segments[id]
			goal = seq.pos
			ent._cursor = ent._cursor + 1
		end

		ent.loco:Approach( goal, 1 )
		ent.loco:FaceTowards( goal )
		ent:SetAngles( Angle( 0, ( ent:GetPos() - goal ):Angle().y, 0 ) )
	end

end

-- NET
do
	function NikNaks.net.WritePath( path )
		local n = #path._segments
		net.WriteUInt( n, 16 )
		net.WriteFloat( path._age )
		net.WriteVector( path._start )

		for i = 1, n do
			local seg = path._segments[i]
			net.WriteVector( seg.pos - seg.length * seg.forward )
			net.WriteVector( seg.pos )
			net.WriteFloat( seg.curvature )
			net.WriteUInt( seg.move_type, 8 )
		end
	end

	function NikNaks.net.ReadPath()
		local n = net.ReadUInt( 16 )
		local age = net.ReadFloat()
		local path = meta.CreatePathFollower( net.ReadVector() )
		path._age = age

		for _ = 1, n do
			path:AddSegment( net.ReadVector(), net.ReadVector(), net.ReadFloat(), net.ReadUInt( 8 ) )
		end

		return path
	end
end

-- Debug
do
	local mat_goal = Material("editor/assault_rally")
	local mat_start = Material("effects/powerup_agility_hud")

	local tMat = Material("effects/bluelaser1")
	local m = Material("hud/arrow_big")

	local point = Material("hud/freezecam_callout_arrow")
	local cir = Material("hud/cart_point_neutral_opaque")
	local mat_arrow = Material("vgui/glyph_expand")

	local mat_solider = Material("hud/bomb_carried")
	local jump_man = Material("hud/death_wheel_1")

	local col_walk = color_white
	local col_climb = Color(155,55,155)
	local col_fly = Color(55,55,255)
	local col_jump = Color(125, 55, 255)

	local mov = bit.bor(NikNaks.CAP_MOVE_GROUND, NikNaks.CAP_MOVE_CLIMB, NikNaks.CAP_MOVE_JUMP)
	local point_b = Material("hud/cart_point_blue")
	local point_c = Material("hud/expanding_vert_middle_blue_bg")

	function meta:DebugRender()
		local l
		for i, seg in ipairs(self:GetAllSegments()) do
			render.SetMaterial(cir)
			render.DrawSprite( seg.pos, 16, 16 )
			if l then
				local col = color_white
				if seg.move_type == NikNaks.CAP_MOVE_CLIMB then
					col = col_climb
				elseif seg.move_type == NikNaks.CAP_MOVE_FLY then
					col = col_fly
				elseif seg.move_type == NikNaks.CAP_MOVE_JUMP then
					col = col_jump
				end
				local d = seg.pos:Distance(l)
				local n = (SysTime() * 2) % 1
				m:SetVector("$color",Vector(col.r,col.g,col.b) / 255)
				render.SetMaterial(m)
				render.DrawBeam( seg.pos, l, 30, n, d / 40 + n, col )
				render.SetMaterial(point)
				render.DrawBeam( l + seg.forward * 10,l + seg.forward * 30, 20, 0, 1)
			end
			l = seg.pos
		end

		local num = max(1, self:GetLength() / 800)
		for i = 1, num do
			local dis = (CurTime() * 100 + i * 800) % self:GetLength()
			local pos = self:GetPositionOnPath( dis )
			local q = 1 + cos(SysTime() * 10 + i) * 0.1
			render.SetMaterial(mat_arrow)
			render.DrawBeam( pos + Vector(0,0,16), pos, 16, q - 1, q, color_white )
			render.SetMaterial(mat_solider)
			render.DrawSprite( pos + Vector(0,0,20), 16, 16 )
		end
	end
end

