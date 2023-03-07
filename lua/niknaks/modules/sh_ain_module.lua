-- Copyright © 2022-2072, Nak, https://steamcommunity.com/id/Nak2/
-- All Rights Reserved. Not allowed to be reuploaded.
local NikNaks = NikNaks
local util_TraceLine, Vector, table_insert, table_Count, table_SortByKey = util.TraceLine, Vector, table.insert, table.Count, table.SortByKey
local floor, band = math.floor, bit.band
local FindEntityHull = util.FindEntityHull

NikNaks.NodeGraph = {}

--- @class NodeGraph
local n_meta = {}
n_meta.__index = n_meta
n_meta.__tostring = function( self ) return
	"NodeGraph: " .. ( self._file or "New" )
end
NikNaks.__metatables["NodeGraph"] = n_meta

--- @class ain_node
local ain_node = {}
ain_node.__tostring = function( self )
	return "Ain Node: " .. self:GetID()
end
ain_node.__index = ain_node

--- @class ain_link
local ain_link = {}
ain_link.__index = ain_link

-- Load AIN file.
local error_detected = {}
do
	-- Reads and returns the node from AIN file
	--- @param b BitBuffer
	local function readNode( b )
		--- @class ain_node
		local t = {}
			t.pos = b:ReadVector()
			t.yaw = b:ReadFloat()
			t.flOffsets = {}
			for i = 0, ( NikNaks.NUM_HULLS or 10 ) - 1 do
				t.flOffsets[i] = b:ReadFloat()	-- Float
			end
			t.nodeType = b:ReadByte() 			-- Byte
			t.nodeInfo = b:ReadUShort()			-- UShort
			t.zone = b:ReadShort()

		-- Clamp Invalid
		if t.nodeType < NikNaks.NODE_TYPE_INVALID or t.nodeType > ( NikNaks.NODE_TYPE_WATER or 5 ) then
			t.nodeType = NikNaks.NODE_TYPE_INVALID
		end

		-- Trade down ( Cause Source-nodes fly in the air )
		if t.nodeType == NikNaks.NODE_TYPE_GROUND then
			local trace = util_TraceLine( {
				start = t.pos + Vector( 0, 0, 50 ),
				endpos = t.pos - Vector( 0, 0, 128 ),
				mask = MASK_SOLID_BRUSHONLY
			} )
			-- Sometimes trace-line fails for some reason.
			if trace then
				t.pos = trace.Hit and trace.HitPos or t.pos
			end
		end

		return setmetatable( t, ain_node )
	end

	--- Read and returns the link from AIN file.
	--- @param b BitBuffer
	local function readLink( b )
		--- @class ain_link
		--- @field moves number[]
		local l = {}
		l.srcId = b:ReadShort() + 1 		-- Short
		l.destId = b:ReadShort() + 1		-- Short
		l.moves = {}

		for i = 0, ( NikNaks.NUM_HULLS or 10 ) - 1 do
			l.moves[i] = b:ReadByte() 	-- Byte
		end

		return setmetatable( l, ain_link )
	end

	--- Parses the link data.
	--- @param self NodeGraph
	--- @param link ain_link
	local function parseLink( self, link )
		local from 	= self._nodes[link.srcId]
		local to 	= self._nodes[link.destId]

		from._connect[#from._connect + 1] = { to, link }
		to._connect[#to._connect + 1] = { from, link }
		if to.zone ~= from.zone then
			error_detected[to] = true
			error_detected[from] = true
		end

		for i = 0, ( NikNaks.NUM_HULLS or 10 ) - 1 do
			local _type = link.moves[i]
			if _type ~= 0 then
				if not from._connect_hull[i] then from._connect_hull[i] = {} end
				if not to._connect_hull[i] then to._connect_hull[i] = {} end

				table_insert( from._connect_hull[i], { to, _type } )
				table_insert( to._connect_hull[i], 	{ from, _type } )
			end
		end
	end

	-- Easy Add function
	local function add( tab, x, y, node )
		if not tab[x] then tab[x] = {} end

		local c = tab[x][y]
		if not c then
			c = {}
			tab[x][y] = c
		end

		c[#c + 1] = node
	end

	--- Function to add the node to a nodegraph.
	--- @param self NodeGraph
	--- @param node ain_node
	local function addNodeToGraph( self, node )
		local ng = self._nodegraph
		local p = node.pos
		local xf, yf = p.x / 1000, p.y / 1000
		local x, y = floor( xf ), floor( yf )
		add( ng, x, y, node )

		local L = xf % 1 < 0.5
		local B = yf % 1 < 0.5

		if L then
			add( ng, x - 1, y, node )
			if B then
				add( ng, x, y - 1, node )
				add( ng, x - 1, y - 1, node )
			else
				add( ng, x, y + 1, node )
				add( ng, x - 1, y + 1, node )
			end
		else
			add( ng, x + 1, y, node )
			if B then
				add( ng, x, y - 1, node )
				add( ng, x + 1, y - 1, node )
			else
				add( ng, x, y + 1, node )
				add( ng, x + 1, y + 1, node )
			end
		end

	end

	-- Tries to patch the table error_detected
	local function scan( node, tab, zone )
		for _, t in pairs( node:GetConnections() ) do
			local n = t[1]
			if not tab[n:GetID()] then
				tab[n:GetID()] = n

				local z = n:GetZone()
				zone[z] = ( zone[z] or 0 ) + 1
				scan( t[1], tab, zone )
			end
		end
	end

	--- @return number
	local function patchZones()
		local fixes = 0

		for _ = 1, table_Count( error_detected ) do
			local node = next( error_detected )
			if not node then break end
			local tab, zone = {}, {}
			scan( node, tab, zone )

			-- Take the most commen zone
			zone = table_SortByKey( zone )[1]

			for _, n in pairs( tab ) do
				if n.zone ~= zone then
					fixes = fixes + 1
					n.zone = zone
				end
				error_detected[n] = nil
			end
		end

		return fixes
	end

	-- Load map data and add it to the nodegraph.
	local l = {
	--	["info_hint"] = true,
		["info_node_hint"] = NikNaks.NODE_TYPE_GROUND,
		["info_node_air_hint"] = NikNaks.NODE_TYPE_AIR,
		["info_node_climb"] = NikNaks.NODE_TYPE_CLIMB
	}

	local function parseEntity( self, ent )
		if not ent.classname then return end

		local _type = l[ent.classname]
		if not _type then return end

		-- local node = self:GetNode(v.nodeid)
		-- For some reason, node ID won't match the entities. I guess there are some internal magic to correct this, 
		-- but our only way is to use the position-data instead. Note that Z position might change cause of trace.
		local node = self:FindNode( ent.origin, _type )

		if not node then
			ErrorNoHaltWithStack( "Unable to locate " .. _type .. "'s node!" )
		else
			node.hint = ent
		end
	end

	local function parseMap( self )
		for _, v in pairs( NikNaks.CurrentMap:GetEntities() ) do
			parseEntity( self, v )
		end
	end

	local thisMap = "maps/graphs/" .. game.GetMap() .. ".ain"

	--- Loads the NodeGraph from a file. Note: Can output "AIN_ERROR_ZONEPATCH", if the file had invalid zones that got patched.
	--- @param fileName string
	--- @return NodeGraph|nil
	--- @return number AIN_ERROR_*
	local function loadAin( fileName )
		-- Make sure you can't create a nodegraph if entities hasn't been initialised 
		assert( NikNaks.PostInit, "Can't use AIN before InitPostEntity!" )

		if not fileName and _nodeG then return _nodeG end
		if not fileName then fileName = "maps/graphs/" .. game.GetMap() .. ".ain" end
		if not string.match( fileName, "%.ain$" ) and not string.match( fileName, "%.dat$" ) then
			-- Add file type
			fileName = fileName .. ".ain"
		end

		--if thisMapObject and fileName == thisMap then return thisMapObject end

		if not file.Exists( fileName, "GAME" ) then return end

		--- @type BitBuffer
		local b = NikNaks.BitBuffer.OpenFile( fileName, "GAME" )

		-- Create new NG object
		--- @class NodeGraph
		local n = {}
		n._version = b:ReadLong()
		n._map_version = b:ReadLong()
		if n._version ~= 37 then -- This is an old / newer AIN file.
			local s = n._version > 37 and "newer" or "older"
			print( "[NodeGraph]: This .AIN version is " .. s .. ", not the supported 37!" )
			return nil, NikNaks.AIN_ERROR_VERSIONNUM
		end

		n._file = fileName

		--- @type ain_node[]
		n._nodes = {}

		--- @type ain_link[]
		n._links = {}

		n._lookup = {}
		n._nodegraph = {} -- This is a custom table to speed up finding nearby notes. Locating notes is one of the costly things.
		setmetatable( n, n_meta )

		-- Load nodes
		local num_nodes = b:ReadLong()
		error_detected = {}
		for i = 1, num_nodes do			-- No limitsh ere
			--- @class ain_node
			local a = readNode( b )
			a._id = i
			a._connect = {} -- A list of nodes connect to this.
			a._connect_hull = {} -- A list of nodes connect to this, by hull.
			n._nodes[i] = a
			addNodeToGraph( n, a )
		end

		-- Read Links
		local num_links = b:ReadLong()
		for i = 1, num_links do			-- No limits here
			--- @class ain_link
			local link = readLink( b )
			link._id = i
			n._links[i] = link
			parseLink( n, link )
		end

		-- Read lookup
		for i = 1, num_nodes do
			n._lookup[i] = b:ReadLong()
		end

		local err = table.Count( error_detected )

		if err > 0 then
			print( "NodeGraph: Detected zone errors in " .. fileName .. "!" )
			print( "NodeGraph: Patching zones .." )
			local s = SysTime()
			local fixed = patchZones() or 0
			print( string.format( "NodeGraph: Took %fms to fix " .. fixed .. " nodes.", SysTime() - s ) )
		end

		if fileName == thisMap then
			parseMap( n )
			-- thisMapObject = n
		end

		--local leftOver = b:Read()
		--print("LEFTOVER: ", string.byte(leftOver), #leftOver)
		return n, err > 0 and NikNaks.AIN_ERROR_PATCHEDDATA
	end
	NikNaks.NodeGraph.LoadAin = loadAin

	local varNG
	--- Returns the nodegraph for the current map and caches it
	--- @return NodeGraph|boolean
	--- @return number? AIN_ERROR_*
	function NikNaks.NodeGraph.GetMap()
		assert( NikNaks.PostInit, "Can't use AIN before InitPostEntity!" )
		if varNG ~= nil then return varNG end

		local a, err = loadAin()
		varNG = a or false
		return varNG, err
	end
end

-- Node Meta
do
	function ain_node:__tostring()
		return "ain_node [" .. self:GetID() .. "]"
	end

	--- Returns the node ID.
	function ain_node:GetID()
		return self._id or -1
	end

	--- Returns true if the node is valid.
	function ain_node:IsValid()
		return self._id >= 0 and self:GetType() > NikNaks.NODE_TYPE_DELETED
	end

	--- Returns the node position.
	--- @return Vector
	function ain_node:GetPos( hull )
		if not hull then hull = 0 end
		return self.pos + Vector( 0, 0, self.flOffsets[hull] )
	end

	--- Returns the node YAW.
	function ain_node:GetYaw()
		return self.yaw
	end

	--- Returns the node type.
	--- @return number NODE_TYPE
	function ain_node:GetType()
		return self.nodeType
	end

	--- Returns the node info.
	function ain_node:GetInfo()
		return self.nodeInfo
	end

	--- Returns the node zone. It should match any notes connected to this one.
	function ain_node:GetZone()
		return self.zone
	end
end

-- Link Meta
do
	function ain_link:__tostring()
		return "ain_link [" .. self:GetID() .. "]"
	end

	--- Returns the link ID.
	function ain_link:GetID()
		return self._id or -1
	end

	--- Returns the move bitflags.
	--- @param HULL number
	function ain_link:GetMove( HULL )
		return self.moves[HULL or 0]
	end

	--- Checks to see if it has any of said move flag
	--- @param HULL number
	--- @param flag number
	function ain_link:HasMoveFlag( HULL, flag )
		return band( self.moves[HULL or 0], flag ) ~= 0
	end

	--- Returns the node ID of the source node.
	function ain_link:GetSrcID()
		return self.srcId
	end

	--- Returns the node IF of the distination node.
	function ain_link:GetDestID()
		return self.destId
	end
end

-- Special Node Meta
do
	--- Returns all the connections from this node.
	--- @return table
	function ain_node:GetConnections()
		return self._connect
	end

	local e_t = {}
	--- Returns all the connections from this node, with said hull that aren't invalid.
	--- @param hull number
	--- @return table
	function ain_node:GetConnectionsByHull( hull )
		return self._connect_hull[hull] or e_t
	end

	--- Returns true if the node_type match.
	--- @param NODE_TYPE number
	--- @return boolean
	function ain_node:IsNodeType( NODE_TYPE )
		if NODE_TYPE == NikNaks.NODE_TYPE_ANY then return true end
		if self.nodeType == NODE_TYPE then return true end
		return false
	end
end

-- Get Grid Nodes
do
	local function scan( node, tab )
		for _, t in pairs( node:GetConnections() ) do
			if not tab[t[1]:GetID()] then
				tab[t[1]:GetID()] = t[1]
				scan( t[1], tab )
			end
		end
	end

	--- A function returning all nodes connected to this one. A bit costly.
	--- @return table
	function ain_node:GetAllGridNodes()
		local p = {}
		local tab = {}
		scan( self, tab )

		for _, node in pairs( tab ) do
			p[#p + 1] = node
		end

		return p
	end
end

-- NodeGraph
do
	-- Adds a dis-cost if node isn't visible. 1 = clear, 10 = blocked
	local function traceCheck( from, to )
		local trace = util_TraceLine( {
			start = from,
			endpos = to,
			mask = MASK_SOLID_BRUSHONLY
		} )

		if not trace then return false end

		return not trace.Hit and trace.Fraction < 1
	end

	--- Returns the AIN version. Should be 37.
	function n_meta:GetVersion()
		return self._version
	end

	--- Returns the AIN map-version.
	function n_meta:GetMapVersion()
		return self._map_version
	end

	--- Returns the given ain_node at said ID. 
	--- @param id number
	function n_meta:GetNode( id )
		return self._nodes[id]
	end

	--- Returns a list of all nodes. With the ID as keys.
	function n_meta:GetAllNodes()
		return self._nodes
	end

	--- Returns the nearest node
	--- @param position Vector
	--- @param NODE_TYPE? number
	--- @param Zone? number
	--- @return ain_node
	function n_meta:FindNode( position, NODE_TYPE, Zone, HULL )
		NODE_TYPE = NODE_TYPE or NikNaks.NODE_TYPE_GROUND
		local x, y = floor( position.x / 1000 ), floor( position.y / 1000 )
		local c, v

		-- Use the nodegraph to search, if none at position, scan all nodes ( slow )
		local ng = self._nodegraph[x] and self._nodegraph[x][y]
		if ng then
			for _, node in pairs( ng ) do
				if Zone and node.zone ~= Zone then continue end
				if not node:IsNodeType( NODE_TYPE ) then continue end
				local vis = traceCheck( position, node:GetPos( HULL ) + Vector( 0, 0, 60 ) )
				if not vis then continue end
				local d = position:DistToSqr( node:GetPos( HULL ) + Vector( 0, 0, 60 )  )
				if not c or d < c then
					c = d
					v = node
				end
			end

			if v then return v end
		end

		-- We didn't find a node within the chunk, or a chunk with no matching note type. We need to scan everything.
		for _, node in pairs( self._nodes ) do
			if Zone and node.zone ~= Zone then continue end
			if not node:IsNodeType( NODE_TYPE ) then continue end
			local vis = traceCheck( position, node:GetPos( HULL ) + Vector( 0, 0, 60 )  )
			local d = position:DistToSqr( node:GetPos() )

			if not vis then
				d = d * 100
			end

			if not c or d < c then
				c = d
				v = node
			end
		end

		return v
	end

	--- Returns the nearest node with a connection matching the hull.
	--- @param position Vector
	--- @param NODE_TYPE? number
	--- @param HULL number
	--- @param Zone? number
	--- @return ain_node
	function n_meta:FindNodeWithHull( position, NODE_TYPE, Zone, HULL )
		NODE_TYPE = NODE_TYPE or NikNaks.NODE_TYPE_GROUND
		local x, y = floor( position.x / 1000 ), floor( position.y / 1000 )
		local c, v

		-- Use the nodegraph to search, if none at position, scan all nodes ( slow )
		local ng = self._nodegraph[x] and self._nodegraph[x][y]
		if ng then
			for _, node in pairs( ng ) do
				if Zone and node.zone ~= Zone then continue end
				if not node:IsNodeType( NODE_TYPE ) then continue end
				if #node._connect_hull[HULL] < 1 then continue end

				local d = position:DistToSqr( node:GetPos( HULL ) + Vector( 0, 0, 60 )  )
				if not c or d < c then
					c = d
					v = node
				end
			end

			if v then return v end
		end

		-- We didn't find a node within the chunk, or a chunk with no matching note type. We need to scan everything.
		for _, node in pairs( self._nodes ) do
			if Zone and node.zone ~= Zone then continue end
			if not node:IsNodeType( NODE_TYPE ) then continue end
			if #node._connect_hull[HULL] < 1 then continue end

			local d = position:DistToSqr( node:GetPos( HULL ) + Vector( 0, 0, 60 )  )
			if not c or d < c then
				c = d
				v = node
			end
		end
		return v
	end

	--- Returns the nearest node with said HintType.
	--- @param position Vector
	--- @param NODE_TYPE? number
	--- @param HintType number
	--- @param HintGroup? number
	--- @param Zone? number
	--- @return ain_node
	function n_meta:FindHintNode( position, NODE_TYPE, HintType, HintGroup, Zone, HULL )
		NODE_TYPE = NODE_TYPE or NikNaks.NODE_TYPE_GROUND
		local x, y = floor( position.x / 1000 ), floor( position.y / 1000 )
		local c, v

		-- Use the nodegraph to search, if none at position, scan all nodes ( slow )
		local ng = self._nodegraph[x] and self._nodegraph[x][y]
		if ng then
			for _, node in pairs( ng ) do
				if not node.hint or node.hint.hinttype ~= HintType then continue end
				if HintGroup and node.hint.group ~= HintGroup then continue end
				if Zone and node.zone ~= Zone then continue end
				if not node:IsNodeType( NODE_TYPE ) then continue end

				local d = position:DistToSqr( node:GetPos( HULL ) )
				if not c or d < c then
					c = d
					v = node
				end
			end

			if v then return v end
		end

		-- We didn't find a node within the chunk, or a chunk with no matching note type. We need to scan everything.
		for _, node in pairs( self._nodes ) do
			if not node.hint or node.hint.hinttype ~= HintType then continue end
			if HintGroup and node.hint.group ~= HintGroup then continue end
			if Zone and node.zone ~= Zone then continue end
			if not node:IsNodeType( NODE_TYPE ) then continue end

			local d = position:DistToSqr( node:GetPos( HULL ) )
			if not c or d < c then
				c = d
				v = node
			end
		end

		return v
	end

	local MAX_NODES = MAX_NODES or 4096 	-- This is the limit for Source, not NikNaks.
	--- Returns the nodegraph as a BitBuffer.
	--- @return BitBuffer
	function n_meta:SaveToBuf()
		local b = NikNaks.BitBuffer()
			b:WriteLong( self:GetVersion() ) -- Should be 37
			b:WriteLong( self._map_version )

		-- Write node num
		local note_num = #self._nodes
		if note_num > MAX_NODES then
			print( "[NodeGrpah]: Warning! Reached over the default MAX_NODES limits. " .. fileName .. " will only work with NikNak's pathfinding." )
		end

		b:WriteLong( note_num )

		for i = 1, note_num do
			local node = self._nodes[i]
			b:WriteVector( node.pos )
			b:WriteFloat( node.yaw )
			for j = 0, ( NikNaks.NUM_HULLS or 10 ) - 1 do
				b:WriteFloat( node.flOffsets[j] )
			end
			b:WriteByte( node.nodeType )
			b:WriteUShort( node.nodeInfo )
			b:WriteShort( node.zone )
		end

		-- Write links. No limits I know of.
		local num = #self._links
		b:WriteLong( num )
		for i = 1, num do
			local l = self._links[i]
			b:WriteShort( l.srcId - 1 )
			b:WriteShort( l.destId - 1 )
			for ii = 0, ( NikNaks.NUM_HULLS or 10 ) - 1 do
				b:WriteByte( l.moves[ii] )
			end
		end

		-- Write lookup
		for i = 1, note_num do
			b:WriteLong( self._lookup[i] )
		end

		return b
	end

	--- Saves the nodegraph to a file.
	--- @param filePath string
	function n_meta:SaveAin( filePath )
		filePath = filePath or self._file or "nodegraph"
		if not string.match( filePath, ".dat$" ) then filePath = filePath .. ".dat" end -- Add file type. We use .dat to stop users from opening it in notepad.
		self:SaveToBuf():SaveToFile( filePath )
		print( "[NodeGraph]: Saved to " .. tostring( "data/" .. filePath ) )
	end

	--- Overrides and generates all the zones in the nodegraph. This can fix zone-errors.
	function n_meta:GenerateZones()
		-- Load all nodes to list.
		local s = SysTime()
		local all_nodes = {}
		local nodes = self._nodes
		for i = 1, #nodes do
			local node = nodes[i]
			all_nodes[node:GetID()] = node
		end

		-- For each node ..
		local zone = 0
		for _ = 1, #nodes do
			local id, node = next( all_nodes )
			if not id then break end -- No more nodes left.
			all_nodes[id] = nil -- Remove this node
			node.zone = zone

			-- For each node connected to this one, set the zone to match.
			for _, con in pairs( node:GetAllConnections() ) do
				con.zone = zone
				all_nodes[con:GetID()] = nil -- Remove said node from the lookup table.
			end

			zone = zone + 1
		end

		print( string.format( "[NodeGraph] Generated zones within: %f", SysTime() - s ) )
	end
end

-- A* PathFinder Node functions
do
	local cost_l, t_cost, open_list, closed_list, move_list = {}, {}, {}, {}, {}
	function ain_node:ClearSearchLists()
		cost_l, t_cost, open_list, closed_list, move_list = {}, {}, {}, {}, {}
	end

	--- Sets the cost for pathfinding.
	--- @param cost number
	function ain_node:SetCostSoFar( cost )
		cost_l[self:GetID()] = cost
	end

	--- Returns the cost so far.
	--- @return number
	function ain_node:GetCostSoFar()
		return cost_l[self:GetID()] or -1
	end

	--- Sets the total cost.
	--- @param cost number
	function ain_node:SetTotalCost( cost )
		t_cost[self:GetID()] = cost
	end

	--- Returns the total cost.
	--- @return number
	function ain_node:GetTotalCost()
		return t_cost[self:GetID()] or -1
	end

	---Adds the node to the open list.
	function ain_node:AddToOpenList()
		open_list[#open_list + 1] = self
	end

	--- Returns true if the node is on the open list.
	--- @return boolean
	function ain_node:IsOpen()
		for i = 1, #open_list do
			if open_list[i]:GetID() == self:GetID() then return true end
		end

		return false
	end

	--- Returns true if the open list is empty.
	--- @return boolean
	function ain_node:IsOpenListEmpty()
		if next( open_list ) then return false end
		return true
	end

	local function sorter( a, b )
		return a:GetTotalCost() < b:GetTotalCost()
	end

	--- Updates the open list.
	function ain_node:UpdateOnOpenList()
		table.sort( open_list, sorter )
	end

	--- Pops the open list and returns the kiwest total cost node.
	function ain_node:PopOpenList()
		return table.remove( open_list, 1 )
	end

	--- Adds the node to the closed list.
	function ain_node:AddToClosedList()
		closed_list[self:GetID()] = true
	end

	--- Returns true if the node is within the closed list.
	--- @return boolean
	function ain_node:IsClosed()
		return closed_list[self:GetID()] or false
	end

	--- Removes the node from the closed list.
	function ain_node:RemoveFromClosedList()
		closed_list[self:GetID()] = nil
	end

	--- Sets the move-type to this node.
	--- @param CAP_MOVE number
	function ain_node:SetMoveType( CAP_MOVE )
		move_list[self:GetID()] = CAP_MOVE
	end

	--- Returns the move-type to this node.
	--- @return number
	function ain_node:GetMoveType()
		return move_list[self:GetID()]
	end
end

-- A* PathFinder
local LPFMeta = NikNaks.__metatables["LPathFollower"]
do
	local function heuristic_cost_estimate( start, goal, HULL )
		-- Perhaps play with some calculations on which corner is closest/farthest or whatever
		return start:GetPos( HULL ):Distance( goal:GetPos( HULL ) )
	end

	local function reconstruct_path( cameFrom, current )
		local total_path = { current }
		while ( cameFrom[current] ) do
			current = cameFrom[current]
			table.insert( total_path, current )
		end

		return total_path
	end

	-- Finds the best move option
	local function getMultiplier( moveoptions, canWalk, canJump, canClimb, canFly, JumpMultiplier, ClimbMultiplier )
		if canFly and band( moveoptions, NikNaks.CAP_MOVE_FLY ) ~= 0 then -- Flying seems to always be the best option
			return NikNaks.CAP_MOVE_FLY, 1
		end

		-- We like to jump more than walking
		if canJump and JumpMultiplier < 1 and band( moveoptions, NikNaks.CAP_MOVE_JUMP ) ~= 0 then
			return NikNaks.CAP_MOVE_JUMP, JumpMultiplier
		end

		if canWalk and band( moveoptions, NikNaks.CAP_MOVE_GROUND ) ~= 0 then
			return NikNaks.CAP_MOVE_GROUND, 1
		elseif canClimb and band( moveoptions, NikNaks.CAP_MOVE_CLIMB ) ~= 0 then -- %20 climb cost
			return NikNaks.CAP_MOVE_CLIMB, ClimbMultiplier
		elseif canJump and band( moveoptions, NikNaks.CAP_MOVE_JUMP ) ~= 0 then
			return NikNaks.CAP_MOVE_JUMP, JumpMultiplier
		end
	end

	--[[
		Tries to A* pathfind to the location.
		true = Same Nodes
		false = Unable to pathfind at all
		table = List of nodes from goal towards the start
	]]
	local function AStart( node_start, node_goal, HULL, BitCapability, JumpMultiplier, ClimbMultiplier, generator, MaxDistance )
		if not node_start or not node_goal then return false end
		if node_start == node_goal then return true end

		local band = band
		node_start:ClearSearchLists()
		node_start:AddToOpenList()

		local cameFrom = {}
		node_start:SetCostSoFar( 0 )
		node_start:SetTotalCost( heuristic_cost_estimate( node_start, node_goal, HULL ) )
		node_start:UpdateOnOpenList()

		local canWalk 	= band( BitCapability, NikNaks.CAP_MOVE_GROUND )	~= 0
		local canFly 	= band( BitCapability, NikNaks.CAP_MOVE_FLY )		~= 0
		local canClimb 	= band( BitCapability, NikNaks.CAP_MOVE_CLIMB )		~= 0
		local canJump 	= band( BitCapability, NikNaks.CAP_MOVE_JUMP )		~= 0

		while not node_start:IsOpenListEmpty()  do
			local current = node_start:PopOpenList()
			if ( current == node_goal ) then
				return reconstruct_path( cameFrom, current )
			end

			current:AddToClosedList()

			for _, tab in pairs( current:GetConnectionsByHull( HULL ) ) do
				local neighbor = tab[1]
				if not neighbor then continue end

				local moveoptions =  band( BitCapability, tab[2] or 0 )
				if moveoptions == 0 then continue end -- Unable to use this link. No options

				local CAP_MOVE, Multi = getMultiplier( moveoptions, canWalk, canJump, canClimb, canFly, JumpMultiplier, ClimbMultiplier  )
				if not CAP_MOVE then continue end

				-- Cost calculator
				local newCostSoFar
				if not generator then -- Custom generator
					newCostSoFar = current:GetCostSoFar() + heuristic_cost_estimate( current, neighbor, HULL ) * Multi
				else -- Default generator
					-- TODO: Elevator? Check L4D elevator maps and what they are.
					newCostSoFar = current:GetCostSoFar() + generator( current, neighbor, CAP_MOVE, BitCapability, heuristic_cost_estimate( current, neighbor, HULL ) * Multi )
				end

				if newCostSoFar < 0 or MaxDistance and newCostSoFar > MaxDistance then -- Check if we went over max-distance
					continue
				end

				if ( neighbor:IsOpen() or neighbor:IsClosed() ) and neighbor:GetCostSoFar() <= newCostSoFar then
					-- This node is already open/close and the cost is shorter
					continue
				else
					neighbor:SetCostSoFar( newCostSoFar );
					neighbor:SetTotalCost( newCostSoFar + heuristic_cost_estimate( neighbor, node_goal, HULL ) )
					neighbor:SetMoveType( CAP_MOVE )

					if ( neighbor:IsClosed() ) then
						neighbor:RemoveFromClosedList()
					end

					if ( neighbor:IsOpen() ) then
						-- This area is already on the open list, update its position in the list to keep costs sorted
						neighbor:UpdateOnOpenList()
					else
						neighbor:AddToOpenList()
					end

					cameFrom[neighbor] = current
				end
			end
		end

		return false
	end


	--- A* pathfinding using the NodeGraph.
	--- @param start_pos Vector|Entity
	--- @param end_pos Vector|Entity
	--- @param NODE_TYPE? number
	--- @param options? table
	--- @param HULL_SIZE? number
	--- @param generator? function		-- A funtion that allows you to calculate your own cost: func( node, fromNode, CAP_MOVE, elevator, length )
	--- @return LPathFollower|boolean
	function n_meta:PathFind( start_pos, end_pos, NODE_TYPE, options, HULL_SIZE, generator )
		if UseZone == nil then UseZone = true end
		if not options then options = {} end

		local MaxDistance 		= options.MaxDistance or 100000
		local BitCapability 	= options.BitCapability or ( NODE_TYPE == NikNaks.NODE_TYPE_AIR and NikNaks.CAP_MOVE_FLY or NikNaks.CAP_MOVE_GROUND ) -- Make default walk, unless NODE_TYPE is fly )
		local JumpMultiplier 	= options.JumpMultiplier or 1.4
		local ClimbMultiplier 	= options.ClimbMultiplier or 1.2

		if not JumpMultiplier then JumpMultiplier = 1.4 			-- Default, make it kinda hate jumping around
		elseif JumpMultiplier < 0.3 then JumpMultiplier = 0.3 end	-- Make sure it can't go below 0.3. Can inf loop if so.

		if not NODE_TYPE then NODE_TYPE = NikNaks.NODE_TYPE_GROUND end			-- Default node: Ground.

		-- Entity checks
		local ent	= start_pos.OBBMins and start_pos
		local ent_e	= end_pos.OBBMins and end_pos

		if ent then
			start_pos = ent:GetPos()
			if not HULL_SIZE then
				if ent.GetHullType then
					HULL_SIZE = ent:GetHullType() -- Get the hulltype from the hulltype function, if that is the starting entity.
				else
					HULL_SIZE = FindEntityHull( ent ) or 0 -- Get the hull size from the OBB, use Hull Human as fallback
				end
			end
		elseif not HULL_SIZE then
			HULL_SIZE = 0 -- Hull Human
		end

		if ent_e then
			end_pos = ent_e:GetPos() + ent_e:OBBCenter()
		end

		-- Find the start and end node.
		local start_node = self:FindNode( start_pos, NODE_TYPE )
		if not start_node then return false end

		local offset = start_pos - start_node:GetPos( HULL_SIZE ) -- Sway the position a bit for the node to be located
		local end_node 	= self:FindNode( end_pos + offset,	NODE_TYPE, start_node:GetZone() ) -- Find an end-node. matching the starting node's zone.
		if not end_node then return false end

		-- Path find to location
		local t = AStart( start_node, end_node, HULL_SIZE, BitCapability, JumpMultiplier, ClimbMultiplier, generator, MaxDistance )
		local def_cap = NODE_TYPE == NikNaks.NODE_TYPE_AIR and NikNaks.CAP_MOVE_FLY or NikNaks.CAP_MOVE_GROUND

		if t == false then -- Unable to pathfind to location
			return false
		elseif t == true then -- Same location, return an "empty" path object.
			local p = LPFMeta.CreatePathFollower( start_pos )
			local s = p:AddSegment( start_pos, end_pos, 0, def_cap )
			s.target_ent = ent_e -- The last position of the pathfollower, is an entity.
			p._generator = generator
			p._MaxDistance = MaxDistance
			return p
		else -- A table of locations
			local p = LPFMeta.CreatePathFollower( start_pos )
			local lP = start_pos

			-- Add end pos
			for i = #t, 1, -1  do
				local node = t[i]
				local s = p:AddSegment( lP, node:GetPos(), 0, node:GetMoveType() or def_cap )
				s.node = node
				lP = t[i]:GetPos()
			end

			local s = p:AddSegment( lP, end_pos, 0, def_cap )
			s.target_ent = ent_e
			p._generator = generator
			p._MaxDistance = MaxDistance

			return p
		end
	end

	--- A cheap lookup function. Checks to see if we can reach the position using nearby nodes.
	--- Note that this use zones and might have false positives on maps with a broken NodeGraph.
	--- @param start_pos Vector
	--- @param end_pos Vector
	--- @param NODE_TYPE? number
	--- @param HULL_SIZE? number
	--- @param max_dis? number -- Distance to nearest node
	--- @return boolean
	function n_meta:CanMaybeReach( start_pos, end_pos, NODE_TYPE, HULL_SIZE, max_dis )
		if not HULL_SIZE then HULL_SIZE = 0 end
		if not NODE_TYPE then NODE_TYPE = NikNaks.NODE_TYPE_GROUND end

		local a = self:FindNode( start_pos,	NODE_TYPE )
		if not a then
			return false
		elseif max_dis and a:GetPos():Distance( start_pos ) > max_dis then
			return false
		end

		local b = self:FindNode( end_pos, NODE_TYPE, a:GetZone() )
		if not b then
			return false
		elseif max_dis and b:GetPos():Distance( start_pos ) > max_dis then
			return false
		end

		return true
	end

end

-- ASync. Calculates 10 paths pr tick.
do
	local async, run = {}, false
	local function remove_hook()
		if not run then return end
		run = false
		hook.Remove( "Think","ain_apath" )
	end

	local function add_hook()
		if run then return end
		run = true

		hook.Add( "Think", "ain_apath", function()
			local n = #async
			if n < 1 then
				return remove_hook() -- None left to calculate
			end

			for i = n, 1, -1 do
				local ok, message = coroutine.resume( async[i] )
				if ( ok == false ) then
					ErrorNoHalt( " Error: ", message, "\n" )
					table.remove( async, 1 )
				elseif message then
					table.remove( async, 1 )
				end
			end
		end )
	end

	--- A* pathfinding using the NodeGraph. Returns the result in the callback. Calculates 20 paths pr tick.
	--- @param start_pos Vector|Entity
	--- @param end_pos Vector|Entity
	--- @param callback function 		-- Returns the result. LPathFollower or false
	--- @param NODE_TYPE? number
	--- @param options? table
	--- @param HULL_SIZE? number
	--- @param generator? function		-- A funtion that allows you to calculate your own cost: func( node, fromNode, CAP_MOVE, elevator, length )
	function n_meta:PathFindASync( start_pos, end_pos, callback, NODE_TYPE, options, HULL_SIZE, generator )
		add_hook() -- Make sure the async runs
		local count = 0

		local function awaitGen( current, neighbor, CAP_MOVE, elevator, h_cost_estimate )
			count = count + 1
			if count > 20 then
				count = 0
				coroutine.yield()
			end
			if generator then return generator( current, neighbor, CAP_MOVE, elevator, h_cost_estimate ) end
			return current:GetCostSoFar() + h_cost_estimate
		end

		table.insert( async, coroutine.create( function()
			callback( self:PathFind( start_pos, end_pos, NODE_TYPE, HULL_SIZE, BitCapability, JumpMultiplier, awaitGen, MaxDistance, UseZone ) )
			return true
		end ) )
	end
end

if SERVER then return end
do
	local c = {
		[NikNaks.NODE_TYPE_AIR 		] = Color( 155, 155, 255 ),
		[NikNaks.NODE_TYPE_GROUND 	] = Color( 155, 255, 155 ),
		--[NODE_TYPE_WATER 	]= Color(0,0,255) ,
		[NikNaks.NODE_TYPE_CLIMB 	] = Color( 155, 155, 155 )
	}
	local l = {}
	for i = 0, 9 do
		l[i] = Material( "sprites/key_" .. i )
	end

	local hType = {
		[0]    = "None",
		[2]    = "Window",
		[12]   = "Act Busy",
		[13]   = "Visually Interesting",
		[14]   = "Visually Interesting(Dont aim)",
		[15]   = "Inhibit Combine Mines",
		[16]   = "Visually Interesting (Stealth mode)",
		[100]  = "Crouch Cover Medium",	-- Angles + FOV is important
		[101]  = "Crouch Cover Low",		-- Angles + FOV is important
		[102]  = "Waste Scanner Spawn",
		[103]  = "Entrance / Exit Pinch (Cut content from Antlion guard)",
		[104]  = "Guard Point",
		[105]  = "Enemy Disadvantage Point",
		[106]  = "Health Kit (Cut content from npc_assassin)",
		[400]  = "Antlion: Burrow Point",
		[401]  = "Antlion: Thumper Flee Point",
		[450]  = "Headcrab: Burrow Point",
		[451]  = "Headcrab: Exit Pod Point",
		[500]  = "Roller: Patrol Point",
		[501]  = "Roller: Cleanup Spot",
		[700]  = "Crow: Fly to point",
		[701]  = "Crow: Perch point",
		[900]  = "Follower: Wait point",
		[901]  = "Override jump permission",
		[902]  = "Player squad transition point",
		[903]  = "NPC exit point",
		[904]  = "Strider mnode",
		[950]  = "Player Ally: Push away destination",
		[951]  = "Player Ally: Fear withdrawal destination",
		[1000] = "HL1 World: Machinery",
		[1001] = "HL1 World: Blinking Light",
		[1002] = "HL1 World: Human Blood",
		[1003] = "HL1 World: Alien Blood",
	}

	local function getH( num )
		if not num then return "?" end
		if hType[num] then
			return hType[num] .. "[" .. num .. "]"
		end
		return num
	end

	function ain_node:DebugRender( size )
		--if self.zone ~= 4 then return end
		size = size or 32

		if self.hint then
			render.SetMaterial( l[self.zone % 10] )
			render.DrawSprite( self:GetPos(), size, size, HSVToColor( ( CurTime() * 420 ) % 360, 0.5, 0.5 ) )

			if LocalPlayer():GetPos():DistToSqr( self:GetPos() ) < 40000 then
				local angle = EyeAngles()
				angle:RotateAroundAxis( angle:Up(), -90 )
				angle:RotateAroundAxis( angle:Forward(), 90 )
				cam.Start3D2D( self:GetPos() + Vector( 0, 0, 30 ), angle, 0.1 )
					draw.DrawText( "HintType: " .. getH( self.hint.hinttype ), "DermaLarge", 0, 0, color_white, TEXT_ALIGN_CENTER )

					if self.hint.targetnode and self.hint.targetnode > -1 then
						draw.DrawText( "Target node: " .. self.hint.targetnode, "DermaLarge", 0, 30, color_white, TEXT_ALIGN_CENTER )
					elseif ( self.hint.hinttype or 0 ) > 0 or not self.hint.group then
						draw.DrawText( "ID node: " .. self.hint.nodeid, "DermaLarge", 0, 30, color_white, TEXT_ALIGN_CENTER )
					else
						draw.DrawText( "Group node: " .. self.hint.group, "DermaLarge", 0, 30, color_white, TEXT_ALIGN_CENTER )
					end
				cam.End3D2D()
			end
		elseif self.zone <= 9 then
			render.SetMaterial( l[self.zone % 10] )
			render.DrawSprite( self:GetPos() + Vector( 0, 0, 15 ), size, size, c[self:GetType()] )
		else
			local angle = EyeAngles()
				angle:RotateAroundAxis( angle:Up(), -90 )
				angle:RotateAroundAxis( angle:Forward(), 90 )
			cam.Start3D2D( self:GetPos() + Vector( 0, 0, 30 ), angle, 0.5 )
				draw.DrawText( "" .. self.zone, "DermaLarge", 0, 0, color_white, TEXT_ALIGN_CENTER )
			cam.End3D2D()
		end

		local h = 0
		for _, v in pairs( self._connect ) do
			if v[2]:HasMoveFlag( h, NikNaks.CAP_MOVE_GROUND ) then -- or v[2]:HasMoveFlag( h, CAP_MOVE_FLY ) then
				render.DrawLine( self:GetPos(), v[1]:GetPos(), c[self:GetType()] )
			end
		end
	end
end

function n_meta:DebugRender()
	local lp = LocalPlayer()
	if not lp then return end
	local x, y = math.floor( lp:GetPos().x / 1000 ), math.floor( lp:GetPos().y / 1000 )

	-- Use the nodegraph to search, if none at position, scan all nodes ( slow )
	local ng = self._nodegraph[x] and self._nodegraph[x][y]
	if not ng then return end

	for _, v in pairs( ng ) do
		v:DebugRender()
	end
end
