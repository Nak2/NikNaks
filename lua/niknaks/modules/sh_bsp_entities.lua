-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
-- License: https://github.com/Nak2/NikNaks/blob/main/LICENSE

-- Entities are stored in a KeyValues table.
-- However we can't use the KeyValuesToTablePreserveOrder function, since some BSPs have errors within Entity Lump.

--- @class BSPEntity # An object that represents an entity within the BSP.
--- @field origin Vector
--- @field angles Angle
--- @field rendercolor? Color
--- @field ontrigger? table
--- @field classname? string
--- @field model? string
--- @field targetname? string
--- @field world_mins? string
--- @field world_maxs? string
--- @field scale? number
--- @field coldworld? number
--- @field mapCreationId number Same as Entity:MapCreationID()
--- @field hammerId number

local string_find, string_byte = string.find, string.byte

--- Locates the next enter-token
--- @param data string
--- @param pos number
--- @return number
local function findNextToken( data, pos )
	return string_find( data, "{", pos, true ) or -1
end

--- Locates the next exit-token
local function findNextExitToken( data, pos )
	local keypos = 0
	local i = pos

	while true do
		-- Jump straight to the next character that matters
		i = string_find( data, '["{}]', i )
		if not i then return end

		local c = string_byte( data, i )
		if c == 34 then -- '"': braces inside a quoted string don't count, skip to the closing quote
			i = string_find( data, '"', i + 1, true )
			if not i then return end
		elseif c == 123 then -- '{'
			keypos = keypos + 1
		else -- '}'
			keypos = keypos - 1
			if keypos == 0 then return i end
		end

		i = i + 1
	end
end

--- Convert a few things to make it easier to read entities.
--- @param t BSPEntity
local function postEntParse( t, index )

	t.origin = util.StringToType( t.origin or "0 0 0" --[[@as string]], "Vector" )
	t.angles = util.StringToType( t.angles or "0 0 0" --[[@as string]], "Angle" )

	if t.rendercolor then
		local c = util.StringToType( t.rendercolor or "255 255 255" --[[@as string]], "Vector" )
		t.rendercolor = Color( c.x, c.y, c.z, 255 )
	end

	-- Make sure ontrigger is a table.
	if t.ontrigger and type( t.ontrigger ) ~= "table" then
		t.ontrigger = { t.ontrigger }
	end

	t.index = index
	t.mapCreationId = index + 1234
	t.hammerId = t.mapCreationId -- Deprecated misnomer, kept for backwards compatibility.
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

--- @return BSPEntity
local function ParseEntity( str, index )
	--- @class BSPEntity
	local t = {}

	for key, value in string.gmatch( str, [["(.-)".-"(.-)"]] ) do
		value = tonumber( value ) or value
		if t[key] then
			if type( t[key] ) ~= "table" then
				t[key] = { t[key], value }
			else
				table.insert( t[key], value )
			end
		elseif _tableTypes[key] then
			t[key] = { value }
		else
			t[key] = value
		end
	end

	postEntParse( t, index )

	return t
end

--- Parses the entity data from the BSP data.
--- @param data string
--- @return BSPEntity[]
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
		local t = ParseEntity( str, id )
		tab[id - 1] = t
	end

	return tab
end

--- @class BSPObject
local meta = NikNaks.__metatables["BSP"]

---Returns the first value of an entity key, ignoring the key's case. Raw entity data is left unchanged.
---@param entity BSPEntity
---@param name string
---@return any
function NikNaks.EntityValue( entity, name )
	local value = entity[name]
	if value == nil then
		name = name:lower()
		for key, other in pairs( entity ) do
			if type( key ) == "string" and key:lower() == name then value = other break end
		end
	end
	if type( value ) == "table" then return value[1] end
	return value
end

---Parses a Hammer output action. ESC-delimited parameters may contain commas.
---A missing input is Use; a missing or zero fire count means unlimited, as in Source.
---@param value string
---@return table? action # target, input, parameter, delay, remaining
function NikNaks.ParseEntityOutput( value )
	if type( value ) ~= "string" then return nil end
	local delimiter = value:find( "\27", 1, true ) and "\27" or ","
	local fields, first = {}, 1
	for i = 1, 4 do
		local at = value:find( delimiter, first, true )
		fields[i] = value:sub( first, at and at - 1 or #value )
		first = at and at + 1 or #value + 1
	end
	local remaining = tonumber( value:sub( first ):match( "^%s*([%+%-]?%d+)" ) ) or -1
	return {
		target = fields[1], input = fields[2] ~= "" and fields[2] or "Use",
		parameter = fields[3], delay = tonumber( fields[4] ) or 0,
		remaining = remaining == 0 and -1 or remaining,
	}
end

--- Returns a list of all raw-entity data within the BSP.
--- @return BSPEntity[]
function meta:GetEntities()
	if self._entities then return self._entities end

	-- Since it is stringbased, it is best to keep it as a string.
	local data = self:GetLumpString( 0 )

	-- Parse all entities
	self._entities = parseEntityData( data )

	return self._entities
end

--- Returns the raw entity data for the specified index.
--- @param index number
--- @return BSPEntity?
function meta:GetEntity( index )
	return self:GetEntities()[index]
end

local function entMatchesClass( v, class )
	local vClass = v.classname
	return vClass ~= nil and class ~= nil and string.match( vClass, class ) ~= nil
end

--- Returns a list of BSPEntities, matching the class.
--- @param class string
--- @return BSPEntity[]
function meta:FindByClass( class )
	return NikNaks.LINQ( self:GetEntities() )
		:Where( entMatchesClass, class )
		:ToTable()
end

local function entMatchesField( v, field, value )
	return v[field] == value
end

--- Returns a list of BSPEntities, matching the given key/value pair. Works with any parsed
--- entity key, not just classname/model/targetname (e.g. "target", "spawnflags", "parentname").
--- @param key string
--- @param value any
--- @return BSPEntity[]
function meta:FindByKeyValue( key, value )
	return NikNaks.LINQ( self:GetEntities() )
		:Where( entMatchesField, key, value )
		:ToTable()
end

--- Returns a list of BSPEntities, matching the model.
--- @param model string
--- @return BSPEntity[]
function meta:FindByModel( model )
	return NikNaks.LINQ( self:GetEntities() )
		:Where( entMatchesField, "model", model )
		:ToTable()
end

--- Returns a list of entity data, matching the targetname.
--- @param name string
--- @return BSPEntity[]
function meta:FindByName( name )
	return NikNaks.LINQ( self:GetEntities() )
		:Where( entMatchesField, "targetname", name )
		:ToTable()
end

local function entInBox( v, boxMins, boxMaxs )
	local origin = v.origin
	return origin ~= nil and origin:WithinAABox( boxMins, boxMaxs )
end

--- Returns a list of entity data, within the specified box. Note: This (I think) is slower than ents.FindInBox
--- @param boxMins Vector
--- @param boxMaxs Vector
--- @return BSPEntity[]
function meta:FindInBox( boxMins, boxMaxs )
	return NikNaks.LINQ( self:GetEntities() )
		:Where( entInBox, boxMins, boxMaxs )
		:ToTable()
end

local function entInSphere( v, origin, radiusSqr )
	local vOrigin = v.origin
	return vOrigin ~= nil and vOrigin:DistToSqr( origin ) <= radiusSqr
end

--- Returns a list of entity data, within the specified sphere. Note: This (I think) is slower than ents.FindInSphere
--- @param origin Vector
--- @param radius number
--- @return BSPEntity[]
function meta:FindInSphere( origin, radius )
	local radiusSqr = radius ^ 2

	return NikNaks.LINQ( self:GetEntities() )
		:Where( entInSphere, origin, radiusSqr )
		:ToTable()
end

--- Returns the BSPEntity, matching the map creation ID (same as Entity:MapCreationID()).
--- @param mapCreationId number
--- @return BSPEntity?
function meta:FindByMapCreationID( mapCreationId )
	return NikNaks.LINQ( self:GetEntities() )
		:Where( entMatchesField, "mapCreationId", mapCreationId )
		:First()
end

--- Returns the BSPEntity, matching the map creation ID.
--- Note: this is NOT the Hammer "hammerid" keyvalue.
---@deprecated This function is deprecated. Use FindByMapCreationID instead.
meta.FindByHammerID = meta.FindByMapCreationID
