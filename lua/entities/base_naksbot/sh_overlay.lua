
if SERVER then
	util.AddNetworkString("b_naksbot_s")

	---Overlays are requires to be precahced on the server. You need to run this on the server, or client-side ragdolls won't spawn on death.
	---@param mdl any
	function ENT:SetOverlay( mdl )
		util.PrecacheModel( mdl )
	end

	---Networks the sound. This fixes model-flex (Mouth movment) on overlays
	---@param soundName string
	---@param soundLevel? number
	---@param pitchPercent? number
	---@param volume? number
	---@param channel? number
	---@param soundFlags? number
	---@param dps? number
	function ENT:EmitSoundOverlay( soundName, soundLevel, pitchPercent, volume, channel, soundFlags, dps )
		net.Start( "b_naksbot_s" )
			net.WriteEntity( self )
			net.WriteString( soundName )
			net.WriteUInt( soundLevel or 75, 9 )
			net.WriteUInt( pitchPercent or 100, 8 )
			net.WriteFloat( volume or 1 )
			net.WriteUInt( channel or 0 , 8)
			net.WriteUInt( soundFlags or 0, 11 )
			net.WriteUInt( dps or 0, 8 )
		net.SendPAS( self:GetPos() )
	end
else
	net.Receive("b_naksbot_s", function()
		local ent = net.ReadEntity()
		if not IsValid( ent ) then return end -- Idk what the entity is
		local snd, slvl, pPer, vol, chan, flag, dsp = net.ReadString(), net.ReadUInt(9), net.ReadUInt(8), net.ReadFloat(), net.ReadUInt(8), net.ReadUInt(11), net.ReadUInt(8)
		if not IsValid( ent._overlay ) then
			ent:EmitSound( snd, slvl, pPer, vol, chan, flag, dsp )
		else
			ent._overlay:EmitSound( snd, slvl, pPer, vol, chan, flag, dsp )
		end
	end)

	local b = false
	local function enabling_hack()
		if b then return end
		b = true
		-- Fix overlays desyncing when the entity leaves PVS
		hook.Add("NotifyShouldTransmit", "base_naksbot_CO", function(ent, b)
			if not IsValid( ent ) then return end
			if ent.Base ~= "base_naksbot" then return end
			if (ent._overlay and b) then
				SafeRemoveEntity(ent._overlay)
			end
		end)

		-- Copy bone
		local function GSetRPos(self, vec )
			local bones = self:GetPhysicsObjectCount()
			if ( bones < 2 ) then return end
			local pos = self:GetPos()
			local vel = self:GetVelocity()
			for bone = 0, bones do
				local b = self:GetPhysicsObjectNum( bone )
				if !b then continue end
		
				local bpos = b:GetPos() - pos
				--b:EnableCollisions( false )
				b:SetPos( vec + bpos )
				b:SetVelocity(vel)
			end
		
			return self
		end
		-- Repalce regdolls from NPC's, not being the overlay 
		hook.Add("CreateClientsideRagdoll", "base_naksbot_CCR", function(ent, rag)
			if not IsValid( ent ) then return end
			if ent.Base ~= "base_naksbot" then return end
			local o_rag = ent._overlay
			if not IsValid( o_rag ) then return end
			local ragdoll = ClientsideRagdoll( o_rag:GetModel(), RENDERGROUP_OTHER )
			ragdoll:SetNoDraw( false )
			ragdoll:DrawShadow( true )
			timer.Simple(5, function()
				if !IsValid(ragdoll) then return end
				ragdoll:SetSaveValue( "m_bFadingOut", true )
			end)

			GSetRPos(ragdoll, rag:GetPos())	
			for bone = 0, ragdoll:GetPhysicsObjectCount() do
				local phys = ragdoll:GetPhysicsObjectNum(bone)
				local ent_bone = ragdoll:TranslatePhysBoneToBone(bone)
				local bonepos, boneang = rag:GetBonePosition(ent_bone)
		
				local o_phys = rag:GetPhysicsObjectNum(bone)
				if IsValid(phys) and IsValid(rag) and IsValid(o_phys) then
					phys:SetPos(bonepos)
					phys:SetAngles(boneang)
					
					phys:AddVelocity(o_phys:GetVelocity())
				end
			end
			SafeRemoveEntity(rag)
			SafeRemoveEntity(o_rag)
		end)
	end

	local function fix_delete( ent )
		SafeRemoveEntity(ent._overlay)
	end

	---Allows you to "override" the model with another. Copying the basae animations. Note you
	---@param mdl string
	function ENT:SetOverlay( mdl )
		enabling_hack() -- Allows the models to be replaced.
		self._renderOverlay = mdl
		if IsValid(self._overlay) then
			self._overlay:SetModel( mdl )
		end
		self:CallOnRemove("fix_overlay",fix_delete) -- Removes the overlay on entity deletion.
	end
	-- renders the overlay model or self.
	function ENT:DrawOverlay()
		if not self._renderOverlay then
			self:DrawModel()
		else
			if not IsValid(self._overlay) then
				self._overlay = ClientsideModel(self._renderOverlay, RENDERGROUP_OTHER)
				self._overlay:SetParent(self)
				self._overlay:AddEffects(EF_BONEMERGE)
				self._overlay:SetPos(self:GetPos())
				self._overlay:SetAngles(self:GetAngles())
				self:DrawShadow(false)
			end
		end
	end

	ENT.Draw = ENT.DrawOverlay

	---Plays the sound on the overlay, if the NPC has one.
	---@param soundName string
	---@param soundLevel? number
	---@param pitchPercent? number
	---@param volume? number
	---@param channel? number
	---@param soundFlags? number
	---@param dps? number
	function ENT:EmitSoundOverlay( soundName, soundLevel, pitchPercent, volume, channel, soundFlags, dps )
		if not IsValid( ent._overlay ) then
			ent:EmitSound( soundName, soundLevel, pitchPercent, volume, channel, soundFlags, dps )
		else
			ent._overlay:EmitSound( soundName, soundLevel, pitchPercent, volume, channel, soundFlags, dps )
		end
	end
end

