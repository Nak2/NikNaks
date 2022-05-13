-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.

-- MAP Alias

-- Load the current map
local BSP = Map.ReadBSP()

-- Smaller functions
do
	---Returns the mapname.
	---@return striing
	function Map.GetMapName()
		return BSP:GetMapName()
	end

	---Returns the mapfile.
	---@return string
	function Map.GetMapFile()
		return BSP:GetMapFile()
	end

	---Returns the map-version.
	---@return number
	function Map.GetVersion()
		return BSP:GetVersion()
	end
end

-- Lump functions
do
	---Returns the data lump as a bytebuffer. This will also be cached onto the BSP object.
	---@param lump_id number
	---@return ByteBuffer
	function Map.GetLump( lump_id )
		return BSP:GetLump( lump_id )
	end

	---Deletes cached lummp_data
	---@param lump_id number
	function Map.ClearLump( lump_id )
		BSP:ClearLump( lump_id )
	end

	---Returns the data lump as a datastring. 
	---This won't be cached or saved, but it is faster than to parse the data into a bytebuffer and useful if you need the raw data.
	---@param lump_id number
	---@return string
	function Map.GetLumpString( lump_id )
		return BSP:GetLumpString( lump_id )
	end

	---Returns a list of gamelumps.
	---@return table
	function Map.GetGameLumpHeaders( )
		return BSP:GetGameLumpHeaders()
	end

	---Returns gamelump number, matching the gLumpID.
	---@param GameLumpID number
	---@return table|nil
	function Map.FindGameLump( GameLumpID )
		return BSP:FindGameLump( GameLumpID )
	end

	---Returns the game lump as a bytebuffer. This will also be cached on the BSP object.
	---@param gameLumpID any
	---@return ByteBuffer
	---@return number version
	---@return numeer flags
	function Map.GetGameLump(gameLumpID)
		return BSP:GetGameLump(gameLumpID)
	end
end

-- Entities
do
	---Returns a list of all entities within the BSP.
	---@return table
	function Map.GetEntities()
		return BSP:GetEntities()
	end

	---Returns the raw entity data said entity.
	---@param index number
	---@return table
	function Map.GetEntity( index )
		return BSO:GetEntity( index )
	end

	---Returns a list of entity data, matching the class.
	---@param class string
	---@return table
	function Map.FindByClass( class )
		return BSP:FindByClass( class )
	end

	---Returns a list of entity data, matching the model.
	---@param model string
	---@return table
	function Map.FindByModel( model )
		return BSP:FindByModel( model )
	end

	---Returns a list of entity data, matching the name ( targetname ).
	---@param name string
	---@return table
	function Map.FindByName( name )
		return BSP:FindByName( name )
	end

	---Returns a list of entity data, within the specified box. Note: This (I think) is slower than ents.FindInBox
	---@param boxMins Vector
	---@param boxMaxs Vector
	---@return table
	function Map.FindInBox( boxMins, boxMaxs )
		return BSP:FindInBox( boxMins, boxMaxs )
	end

	---Returns a list of entity data, within the specified sphere. Note: This (I think) is slower than ents.FindInSphere
	---@param origin Vector
	---@param radius number
	function Map.FindInSphere( origin, radius )
		return BSP:FindInSphere( origin, radius )
	end
end

-- Static Props
do
	---Returns a list of staticprops.
	---@return table
	function Map.GetStaticProps()
		return BSP:GetStaticProps()
	end

	---Returns the static-prop object from said index.
	---@param index number
	---@return StaticProp
	function Map.GetStaticProp( index )
		return BSP:GetStaticProp( index )
	end

	---Returns a list of all static-prop models used by the map.
	---@return table
	function Map.GetStaticPropModels()
		return BSP:GetStaticPropModels()
	end

	---Returns a list of all static-props matching the model.
	---@param model string
	---@return table
	function Map.FindStaticByModel( model )
		return BSP:FindStaticByModel( model )
	end

	---Returns a list of all static-props, within the specified box.
	---@param boxMins Vector
	---@param boxMaxs Vector
	---@return table
	function Map.FindStaticInBox( boxMins, boxMaxs )
		return BSP:FindStaticInBox( boxMins, boxMaxs )
	end

	---Returns a list of all static-props, within the specified sphere.
	---@param origin Vector
	---@param radius number
	---@return table
	function Map.FindStaticInSphere( origin, radius )
		return BSP:FindStaticInSphere( origin, radius )
	end
end

-- Word Data
do
	function Map.GetDetailMaterial()
		return BSP:GetDetailMaterial()
	end

	function Map.IsColdWorld()
		return BSP:IsColdWorld()
	end

	function Map.WorldMin()
		return BSP:WorldMin()
	end

	function Map.WorldMax()
		return BSP:WorldMax()
	end

	function Map.GetBounds()
		return BSP:GetBounds()
	end

	function Map.GetSkyBoxPos()
		return BSP:GetSkyBoxPos()
	end

	function Map.GetSkyBoxScale()
		return BSP:GetSkyBoxScale()
	end

	function Map.HasSkyBox()
		return BSP:HasSkyBox()
	end
end

-- Cubemaps
do
	function Map.GetCubemaps()
		return BSP:GetCubemaps()
	end
	function Map.FindNearestCubemap( pos )
		return BSP:FindNearestCubemap( pos )
	end
end

-- Textures and materials
do
	---Returns a list of textures used by the map.
	---@return table
	function Map.GetTextures()
		return BSP:GetTextures()
	end

	---Returns a list of material-data used by the map
	---@return table
	function Map.GetTextureData()
		return BSP:GetTextureData()
	end

	---Returns a lsit of all materials used by the map
	function Map.GetMaterials()
		return BSP:GetMaterials()
	end
end