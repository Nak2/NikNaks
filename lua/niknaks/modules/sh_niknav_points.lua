-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.

local band = bit.band

---@class NikNav_HintPoint
local meta_hintp = {}
meta_hintp.__index = meta_hintp
meta_hintp.MetaName = "NikNav_HintPoint"
debug.getregistry().NikNav_HintPoint = meta_hintp

---@class NikNav_MovePoint
local meta_movep = {}
meta_movep.__index = meta_movep
meta_movep.MetaName = "NikNav_MovePoint"
debug.getregistry().NikNav_MovePoint = meta_movep

-- Hint Point meta-functions
do
	local hType = {
		[0] = "None",
		[2] = "Window",
		[12] = "Act Busy",
		[13] = "Visually Interesting",
		[14] = "Visually Interesting(Dont aim)",
		[15] = "Inhibit Combine Mines",
		[16] = "Visually Interesting (Stealth mode)",
		[100] = "Crouch Cover Medium",	-- Angles + FOV is important
		[101] = "Crouch Cover Low",		-- Angles + FOV is important
		[102] = "Waste Scanner Spawn",
		[103] = "Entrance / Exit Pinch (Cut content from Antlion guard)",
		[104] = "Guard Point",
		[105] = "Enemy Disadvantage Point",
		[106] = "Health Kit (Cut content from npc_assassin)",
		[400] = "Antlion: Burrow Point",
		[401] = "Antlion: Thumper Flee Point",
		[450] = "Headcrab: Burrow Point",
		[451] = "Headcrab: Exit Pod Point",
		[500] = "Roller: Patrol Point",
		[501] = "Roller: Cleanup Spot",
		[700] = "Crow: Fly to point",
		[701] = "Crow: Perch point",
		[900] = "Follower: Wait point",
		[901] = "Override jump permission",
		[902] = "Player squad transition point",
		[903] = "NPC exit point",
		[904] = "Strider mnode",
		[950] = "Player Ally: Push away destination",
		[951] = "Player Ally: Fear withdrawal destination",
		[1000]= "HL1 World: Machinery",
		[1001]= "HL1 World: Blinking Light",
		[1002]= "HL1 World: Human Blood",
		[1003]= "HL1 World: Alien Blood",
		--- NikNav Variables
		[1020]= "Sniper Spot",			-- A point where the NPC can snipe
		[1021]= "Perfect sniper Spot",	-- A perfect point where the NPC can snipe
		[1022]= "Exposed Spot"			-- Aspot in the open, usually on a ledge or cliff
	}
	function meta_hintp:GetID()
		return self.n_id
	end
	
	function meta_hintp:GetPos()
		return self.m_pos
	end

	function meta_hintp:GetYaw()
		return self.m_yaw
	end

	function meta_hintp:GetFOV()
		return self.m_fov
	end

	function meta_hintp:GetHint()
		return self.m_hint
	end

	function meta_hintp:GetHintText()
		return hType[self.m_hint] or self.m_hint
	end

	function meta_hintp:GetHintActivity()
		return self.m_hintactivity
	end

	function meta_hintp:GetArea()
		return self.m_area
	end

	function meta_hintp:SetEnabled( bool )
		if bool == nil then bool = true end
		self.m_enabled = bool
	end

	function meta_hintp:IsEnabled()
		return self.m_enabled or false
	end
end

-- Move Point meta-functions
do
	function meta_movep:GetID()
		return self.n_id
	end
	
	function meta_movep:GetPos()
		return self.m_pos
	end

	function meta_movep:GetEndPos()
		return self.m_endpos
	end

	function meta_movep:GetRadius()
		return self.m_radius
	end

	function meta_movep:IsOneWay()
		return self.m_oneway
	end

	function meta_movep:GetTypeFlag()
		return self.m_type
	end

	function meta_movep:HasTypeFlag( flag )
		return band(self.m_type, flag) ~= 0
	end

	function meta_movep:GetDistance()
		return self.m_length
	end

	function meta_movep:GetArea()
		return self.m_area
	end

	function meta_movep:GetEndArea()
		return self.m_area_to
	end

	function meta_movep:SetEnabled( bool )
		if bool == nil then bool = true end
		self.m_enabled = bool
	end

	function meta_movep:IsEnabled()
		return self.m_enabled or false
	end
end

-- Save & Load
do
	meta_hintp.__load = function( mesh, bytebuffer )
		local id = #mesh.m_hintpoints + 1
		local t = {}
		t.m_id			= id
		t.m_pos 		= bytebuffer:ReadVector()
		t.m_yaw			= bytebuffer:ReadFloat()
		t.m_fov			= bytebuffer:ReadFloat()
		t.m_hint 		= bytebuffer:ReadUShort()
		t.m_hintactivity= bytebuffer:ReadString()
		t.m_enabled		= true
		setmetatable(t, meta_hintp)
		mesh.m_hintpoints[id] = t
		t:UpdateArea( mesh )
		return t
	end

	meta_hintp.__save = function( HintPoint, bytebuffer )
		bytebuffer:WriteVector( HintPoint.m_pos )
		bytebuffer:WriteFloat(  HintPoint.m_yaw )
		bytebuffer:WriteFloat(  HintPoint.m_fov )
		bytebuffer:WriteUShort( HintPoint.m_hint )
		bytebuffer:WriteString( HintPoint.m_hintactivity )
	end

	meta_movep.__load = function( mesh, bytebuffer )
		local id = #mesh.m_movepoints + 1
		local t = {}
		t.m_id			= id
		t.m_pos 		= bytebuffer:ReadVector()
		t.m_endpos		= bytebuffer:ReadVector()
		t.m_radius		= bytebuffer:ReadFloat()
		t.m_oneway		= bytebuffer:ReadBool()
		t.m_type		= bytebuffer:ReadByte()
		t.m_length 		= t.m_pos:Distance(t.m_endpos)
		t.m_enabled		= true
		setmetatable(t, meta_movep)
		mesh.m_movepoints[id] = t
		t:UpdateArea( mesh )
		return t
	end

	meta_movep.__save = function( MovePoint, bytebuffer )
		bytebuffer:WriteVector(MovePoint.m_pos)
		bytebuffer:WriteVector(MovePoint.m_endpos)
		bytebuffer:WriteFloat(MovePoint.m_raidus)
		bytebuffer:WriteBool(MovePoint.m_oneway and true or false)
		bytebuffer:WriteByte(MovePoint.m_type)
	end
end

-- Area <-> MovePoint & HintPoint
do
	local meta_area = FindMetaTable( "NikNav_Area" )
	---Returns a list of all hint points near the area
	---@return table
	function meta_area:GetHintPoints()
		return self.m_hintpoints
	end

	---Returns a list of all move points near the area
	---@return table
	function meta_area:GetHintPoints()
		return self.m_movepoints
	end

	---Updates the hint-area data
	function meta_hintp:UpdateArea( mesh )
		-- Remove self from old area
		if self.m_area then
			self.m_area.m_hintpoints[self.m_id] = nil
		end
		-- Find nearest area and tell them about it
		self.m_area = mesh:GetArea( self.m_pos )
		if not self.m_area then return end
		self.m_area.m_hintpoints[self.m_id] = self
	end

	---Updates the hint-area data
	function meta_movep:UpdateArea( mesh )
		-- Remove self from old areas
		if self.m_area then
			self.m_area.m_hintpoints[self.m_id] = nil
		end
		if self.m_area_to then
			self.m_area_to.m_hintpoints[self.m_id] = nil
		end
		-- Find nearest area and tell them about it
		self.m_area = mesh:GetArea( self.m_pos )
		self.m_area_to = mesh:GetArea( self.m_endpos )
		if not self.m_area or not self.m_area_to then return end -- Need both areas to be valid
		-- Tell both areas about the move-point (Unless oneway, then only the start pos)
		self.m_area.m_movepoints[self.m_id] = self
		if not self.m_oneway then
			self.m_area_to.m_movepoints[self.m_id] = self
		end
	end

	---Removes self from the area
	function meta_hintp:DecoupleArea()
		if self.m_area then
			self.m_area.m_hintpoints[self.m_id] = nil
		end
	end

	---Removes self from the area
	function meta_movep:DecoupleArea()
		-- Remove self from old areas
		if self.m_area then
			self.m_area.m_hintpoints[self.m_id] = nil
		end
		if self.m_area_to then
			self.m_area_to.m_hintpoints[self.m_id] = nil
		end
	end
end

-- Debug Render
if CLIENT then
	local cir = Material("gui/point.png")
	local c_b = Color(0,0,0,200)
	function meta_hintp:DebugRender()
		local angle = EyeAngles()
		angle:RotateAroundAxis( angle:Up(), -90 )
		angle:RotateAroundAxis( angle:Forward(), 90 )
		render.SetMaterial(cir)
		render.DrawBeam(self.m_pos + Vector(0,0,16 + math.sin(CurTime() * 5) * 5), self.m_pos, 16, 0, 1, color_white)
		cam.Start3D2D( self.m_pos + Vector(0,0,40),angle, 0.2 )
			surface.SetFont("DermaLarge")
			local tw, th = surface.GetTextSize(self:GetHintText())
			tw = tw + 10
			th = th + 5
			surface.SetDrawColor(c_b)
			surface.DrawRect( -tw / 2,0,tw,th)
			draw.DrawText( self:GetHintText(), "DermaLarge", 0, 0, color_white, TEXT_ALIGN_CENTER, TEXT_ALIGN_CENTER  )
		cam.End3D2D()
	end

	local climb = Material("tools/climb_alpha")
	function meta_movep:DebugRender()
		render.SetMaterial(climb)
		render.DrawBeam( self.m_pos, self.m_endpos, 25, self.m_length / 25, 0, color_white )
	end
end