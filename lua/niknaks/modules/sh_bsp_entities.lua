-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
-- License: https://github.com/Nak2/NikNaks/blob/main/LICENSE

-- Entities are stored in a KeyValues table.
-- However we can't use the KeyValuesToTablePreserveOrder function, since some BSPs have errors within Entity Lump.

--- @class EntityObject
--- @field origin? Vector
--- @field angles? Angle
--- @field rendercolor? Color
--- @field ontrigger? table
--- @field classname? string
--- @field model? string
--- @field targetname? string
--- @field world_mins? string
--- @field world_maxs? string
--- @field scale? number
--- @field coldworld? number

--- Locates the next enter-token
--- @param data string
--- @param pos number
--- @return number
local function findNextToken( data, pos )
	for i = pos, #data do
		if data[i] == "{" then return i end
	end

	return -1
end

--- Locates the next exit-token
local function findNextExitToken( data, pos )
	local keypos = 0
	local ignore = false

	for i = pos, #data do
		if data[i] == "\"" then ignore = not ignore
		elseif ignore then continue end

		if data[i] == "{" then keypos = keypos + 1
		elseif data[i] == "}" then
			keypos = keypos - 1
			if keypos == 0 then return i end
		end
	end
end

--- Convert a few things to make it easier to read entities.
--- @param t EntityObject
local function postEntParse( t )
	t.origin = util.StringToType( t.origin or "0 0 0", "Vector" )
	t.angles = util.StringToType( t.angles or "0 0 0", "Angle" )

	if t.rendercolor then
		local c = util.StringToType( t.rendercolor or "255 255 255", "Vector" )
		t.rendercolor = Color( c.x, c.y, c.z, 255 )
	end

	-- Make sure ontrigger is a table.
	if t.ontrigger and type( t.ontrigger ) ~= "table" then
		t.ontrigger = { t.ontrigger }
	end
end

-- A list of data-keys that can have multiple entries.
local _tableTypes = {
	["OnMapSpawn"] = 	true,
	["OnTrigger"] = 	true,
	["OnStartTouch"] = 	true,
	["OnArrivedAtDestinationNode"] = true,
	["OnPowered"] = 	true,
	["OnUnpowered"] = 	true,
	["OnExplode"] = 	true,
	["OnAllTrue"] = 	true,
}

--- @return EntityObject
local function ParseEntity( str )
	--- @class EntityObject
	local t = {}

	for key, value in string.gmatch( str, [["(.-)".-"(.-)"]] ) do
		value = tonumber( value ) or value
		if t[key] then
			if type( t[key] ) ~= "table" then
				t[key] = { t[key] }
			else
				table.insert( t[key], value )
			end
		elseif _tableTypes[key] then
			t[key] = { value }
		else
			t[key] = value
		end
	end

	postEntParse( t )

	return t
end

--- Tries to parse the entity-data.
--- @param data string
--- @return EntityObject[]
local function parseEntityData( data )
	-- Cut the data into bits
	local charPos = 1
	local tabData = {}
	for _ = 1, #data do -- while true do
		local nextToken = findNextToken( data, charPos )
		if nextToken < 0 then
			break -- No token found. EOF.
		else
			local exitToken = findNextExitToken( data, nextToken )
			if exitToken then
				tabData[#tabData + 1] = data:sub( nextToken, exitToken )
				charPos = exitToken
			else -- ERROR No exit token? Try and parse the rest.
				tabData[#tabData + 1] = data:sub( nextToken ) .. "}"
				NikNaks.Msg( [[[BSP] ParseEntity: No closing brace found!]] )
				break
			end
		end
	end

	local tab = {}
	for id, str in pairs( tabData ) do
		local t = ParseEntity( str )
		tab[id - 1] = t
	end

	return tab
end

--- @class BSPObject
local meta = NikNaks.__metatables["BSP"]

--- Returns a list of all raw-entity data within the BSP.
--- @return EntityObject[]
function meta:GetEntities()
	if self._entities then return self._entities end

	-- Since it is stringbased, it is best to keep it as a string.
	local data = self:GetLumpString( 0 )

	-- Parse all entities
	self._entities = parseEntityData( data )

	return self._entities
end

--- Returns the raw entity data said entity.
--- @param index number
--- @return EntityObject
function meta:GetEntity( index )
	return self:GetEntities()[index]
end

--- Returns a list of entity data, matching the class.
--- @param class string
--- @return EntityObject[]
function meta:FindByClass( class )
	local t = {}

	for _, v in pairs( self:GetEntities() ) do
		local vClass = v.classname
		if class and string.match( vClass, class ) then
			t[#t + 1] = v
		end
	end

	return t
end

--- Returns a list of entity data, matching the model.
--- @param model string
--- @return EntityObject[]
function meta:FindByModel( model )
	local t = {}

	for _, v in pairs( self:GetEntities() ) do
		if v.model == model then
			t[#t + 1] = v
		end
	end

	return t
end

--- Returns a list of entity data, matching the name ( targetname ).
--- @param name string
--- @return table
function meta:FindByName( name )
	local t = {}

	for _, v in pairs( self:GetEntities() ) do
		if v.targetname == name then
			t[#t + 1] = v
		end
	end

	return t
end

--- Returns a list of entity data, within the specified box. Note: This (I think) is slower than ents.FindInBox
--- @param boxMins Vector
--- @param boxMaxs Vector
--- @return table
function meta:FindInBox( boxMins, boxMaxs )
	local t = {}

	for _, v in pairs( self:GetEntities() ) do
		local origin = v.origin
		if origin and v.origin:WithinAABox( boxMins, boxMaxs ) then
			t[#t + 1] = v
		end
	end

	return t
end

--- Returns a list of entity data, within the specified sphere. Note: This (I think) is slower than ents.FindInSphere
--- @param origin Vector
--- @param radius number
function meta:FindInSphere( origin, radius )
	radius = radius ^ 2

	local t = {}

	for _, v in pairs( self:GetEntities() ) do
		local vOrigin = v.origin
		if vOrigin and vOrigin:DistToSqr( origin ) <= radius then
			t[#t + 1] = v
		end
	end

	return t
end
