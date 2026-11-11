-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.

---@class File
local FILE = FindMetaTable( "File" )

-- Exstra file functions

if not FILE.IsValid then

	--- Returns true if the file is valid and can be written to.
	--- @return boolean
	function FILE:IsValid()
		local str = tostring( self )
		return str ~= "[NULL File]" and str ~= "File [NULL]"
	end
end

if not FILE.WriteVector then
	--- Writes a vector to the file.
	--- @param vector Vector
	function FILE:WriteVector( vector )
		self:WriteFloat( vector.x )
		self:WriteFloat( vector.y )
		self:WriteFloat( vector.z )
	end

	--- Reads a vector from the file.
	--- @return Vector
	function FILE:ReadVector()
		return Vector( self:ReadFloat(), self:ReadFloat(), self:ReadFloat() )
	end
end

NikNaks.file = {}
--- Same as file.Write, but will automatically create folders and return true if successful.
--- @param fileName string
--- @param contents string
--- @return boolean
function NikNaks.file.WriteEx( fileName, contents )
	local a = string.Explode( "/", fileName )
	assert( #a <= 10, "Unable to create an unreasonable array of folders!" )

	if #a > 1 then
		file.CreateDir( string.GetPathFromFilename( fileName ) )
	end

	local f = file.Open( fileName, "wb", "DATA" )
	if not f then return false end

	f:Write( contents )
	f:Close()

	return true
end
