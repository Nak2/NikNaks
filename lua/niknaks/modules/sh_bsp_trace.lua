
--- @class BSPObject
local meta_bsp = NikNaks.__metatables["BSP"]

--- @class BSPFaceObject
local meta_face = NikNaks.__metatables["BSP Faces"]

--- @class BSPLeafObject
local meta_leaf = NikNaks.__metatables["BSP Leaf"]

--- @class BSPBrushObject
local meta_brush = NikNaks.__metatables["BSP Brush"]

local DIST_EPSILON = 0.03125
local FLT_EPSILON = 1.192092896e-07

--- Returns a new trace-reult
--- @param startPos Vector
--- @param endPos Vector
--- @return table
local function newTrace( startPos, endPos)
	local t = {
		StartPos = startPos,
		EndPos = endPos,
		HitPos = endPos,
		Normal = ( endPos - startPos ):GetNormalized(),
		Fraction = 1,
		FractionLeftSolid = 0
	}
	return t
end

local mt = getmetatable(Vector(0,0,0))
local dot = mt.Dot
local cross = mt.Cross

--- Checks to see if the triangle is intersecting and returns the intersection.
--- @param orig Vector The origin of the ray.
--- @param dir Vector The normalized direction.
--- @param v0 Vector The first vertex of the triangle.
--- @param v1 Vector The second vertex of the triangle.
--- @param v2 Vector The third vertex of the triangle.
--- @return Vector? Intersection
local function IsRayIntersectingTriangle(orig, dir, v0, v1, v2)
	local v0v1 = v1 - v0
	local v0v2 = v2 - v0
	local pvec = cross(dir,v0v2)
	local det = dot(v0v1, pvec)

	-- Ray and triangle are parallel if det is close to 0
	if det > -0.0001 and det < 0.0001 then
        return -- No intersection.
    end

	local invDet = 1 / det

	local tvec = orig - v0
	local u = dot(tvec, pvec) * invDet
	if (u < 0 or u > 1) then return end

	local qvec = cross(tvec,v0v1)
	local v = dot(dir, qvec) * invDet
	if (v < 0 or u + v > 1) then return end

	local distance = dot(v0v2, qvec) * invDet
	if distance > 0 then
		return orig + dir * distance
	end

	return nil
end

--- Checks to see if ray is intersecting the given face.
--- @param origin Vector
--- @param dir Vector The normalized direction.
--- @return Vector? -- The intersection point if found, otherwise nil
function meta_face:LineDirectionIntersection( origin, dir )
	local poly = self:GetVertexs()
	if not poly then return end
	local j = 1
	for i = 1, #poly - 2 do
		local v0 = poly[1]
		local v1 = poly[i + 1]
		local v2 = poly[i + 2]
		local hitPos = IsRayIntersectingTriangle(origin, dir, v0, v1, v2)
		if hitPos then return hitPos end
		j = j + 3
	end
	return nil
end

--- Checks to see if the line segment is intersecting the given face.
--- @param startPos Vector
--- @param endPos Vector
--- @return Vector? -- The intersection point if found, otherwise nil
function meta_face:LineSegmentIntersection( startPos, endPos )
	local plane = self.plane
	local dot1 = plane:DistTo(startPos)
	local dot2 = plane:DistTo(endPos)

	if (dot1 > 0) ~= (dot2 > 0) or true then
		local t = dot1 / ( dot1 - dot2 )

		if t <= 0 or t >= 1 then return end
		local poly = self:GetVertexs()
		if not poly then return end
		for i = 1, #poly - 2 do
            local v0 = poly[1]
            local v1 = poly[i + 1]
            local v2 = poly[i + 2]

            -- Check if ray is intersecting triangle point v0, v1 and v2
			local hit = IsRayIntersectingTriangle(startPos, (endPos - startPos):GetNormalized(), v0, v1, v2)
            if hit then return hit end
        end
	end
end


--- Returns the BrushObject that the ray is intersecting, if any.
--- @param origin Vector
--- @param dir Vector
---@return BSPBrushObject?
function meta_leaf:IsRayIntersecting( origin, dir )
	for _, brush in pairs( self:GetBrushes() ) do
		local hit = brush:IsRayIntersecting( origin, dir )
		if hit then return brush end
	end
end

--- Casts a ray on the brush
--- @param self BSPObject
--- @param brush BSPBrushObject
--- @param startPos Vector
--- @param endPos Vector
--- @param trace table
--- @return boolean
local function rayCastBrush( self, brush, startPos, endPos, trace)
	local sides = self:GetBrushSides()
	if #sides < 1 then return false end

	local f_enter = -99
	local f_leave = 1
	local starts_out = false
	local ends_out = false
	for _, side in pairs( sides ) do
		if side.bevel == 1 then continue end

		local plane = side.plane
		local start_dist = startPos:Dot( plane.normal ) - plane.dist
		local end_dist = endPos:Dot( plane.normal ) - plane.dist
		if start_dist > 0 then
			starts_out = true
			if end_dist > 0 then return end
		else
			if end_dist <= 0 then continue end
			ends_out = true
		end

		if start_dist > end_dist then
			local fraction = math.max( start_dist - DIST_EPSILON, 0 )
			fraction = fraction / ( start_dist - end_dist )
			f_enter = math.max( f_enter, fraction )
		else
			local fraction = ( start_dist + DIST_EPSILON ) / ( start_dist - end_dist )
			f_leave = math.min( f_leave, fraction)
		end
	end

	if starts_out then
		if trace.FractionLeftSolid - f_enter > 0 then
			starts_out = false
		end
	end

	if not starts_out then
		trace.StartSolid = true
		trace.Content = brush.Content
		
		if not ends_out then
			trace.AllSolid = true
			trace.Fraction = 0
			trace.FractionLeftSolid = 1
		else
			if f_leave ~= 1 and f_leave > trace.FractionLeftSolid then
				trace.FractionLeftSolid = f_leave
				if trace.Fraction <= f_leave then
					trace.Fraction = 1
				end
			end
		end
		return false
	end

	if f_enter < f_leave then
		if f_enter > -99 and f_enter < trace.Fraction then
			if f_enter < 0 then
				f_enter = 0
			end
			trace.Fraction = f_enter
			trace.Brush = brush
			trace.Content = brush.Content
		end
	end
	return false
end

-- Raycasts a BSPFaceObject and returns the result in the trace table.
---@param face BSPFaceObject
---@param trace table
---@return boolean
local function rayCastFace( face, trace )
	local startPos = trace.StartPos
	local endPos = trace.EndPos

	local plane = face.plane
	local dot1 = plane:DistTo(startPos)
	local dot2 = plane:DistTo(endPos)

	if (dot1 > 0) ~= (dot2 > 0) or true then

		if math.abs(dot1 - dot2) < DIST_EPSILON then return false end

		local t = dot1 / ( dot1 - dot2 )

		if t <= 0 or t >= trace.Fraction then return false end
		local intersection = startPos + (endPos - startPos) * t
		local hit = face:LineDirectionIntersection(startPos, trace.Normal)
		if hit then
			trace.Fraction = t
			trace.HitPos = intersection
			trace.HitNormal = plane.normal
			trace.Face = face
			trace.Hit = true
			trace.HitSky = face:IsSkyBox3D() or face:IsSkyBox()
			trace.SurfaceFlags = face:GetTexInfo().flags
			return true
		end
	end
	return false
end

do
	local dot = Vector().Dot
	local min, max = math.min, math.max
	local nodes = {}
	local leafs = {}

	local middle = Vector()
	---@param self BSPObject
	---@param nodeIndex number
	---@param startFraction number
	---@param endFraction number
	---@param startPos Vector
	---@param endPos Vector
	---@param trace table
	---@param mask number? The surface flags to check for. (SURF_*)
	local function rayCastNode( self, nodeIndex, startFraction, endFraction, startPos, endPos, trace, mask )
		local traceFraction = trace.Fraction
		if traceFraction <= startFraction then return end

		if nodeIndex < 0 then
			---@type BSPLeafObject
			local leaf = leafs[ -nodeIndex - 1]
			if trace.StartSolid or traceFraction < 1 then return end
			for _, face in ipairs(leaf:GetFaces()) do
				if dot(face.plane.normal,trace.Normal) < 0 then
					-- Check mask
					if mask and bit.band(face:GetTexInfo().flags, mask) == 0 then continue end
					rayCastFace(face, trace)
				end
			end
			return
		end

		--- @type MapNode
		local node = nodes[nodeIndex]
		if not node or not node.plane then return end

		local plane = node.plane
		local start_dist, end_dist = 0,0

		if plane.type == 0 then
			start_dist = startPos.x - plane.dist
			end_dist = endPos.x - plane.dist
		elseif plane.type == 1 then
			start_dist = startPos.y - plane.dist
			end_dist = endPos.y - plane.dist
		elseif plane.type == 2 then
			start_dist = startPos.z - plane.dist
			end_dist = endPos.z - plane.dist
		else
			start_dist = dot(startPos, plane.normal) - plane.dist
			end_dist = dot(endPos, plane.normal) - plane.dist
		end

		if start_dist >= 0 and end_dist >= 0 then
			rayCastNode(self, node.children[1], startFraction, endFraction, startPos, endPos, trace, mask)
		elseif start_dist < 0 and end_dist < 0 then
			rayCastNode(self, node.children[2], startFraction, endFraction, startPos, endPos, trace, mask)
		else
			local side_id, fraction_first, fraction_second = 0, 0, 0
			local inversed_distance = 1 / (start_dist - end_dist)

			if start_dist < end_dist then
				side_id = 2
				fraction_first = (start_dist + FLT_EPSILON) * inversed_distance
				fraction_second = (start_dist + FLT_EPSILON) * inversed_distance
			elseif end_dist < start_dist then
				side_id = 1
				fraction_first = (start_dist + FLT_EPSILON) * inversed_distance
				fraction_second = (start_dist - FLT_EPSILON) * inversed_distance
			else
				side_id = 1
				fraction_first, fraction_second = 1, 0
			end

			fraction_first = min(1, max(0, fraction_first))
			fraction_second = min(1, max(0, fraction_second))
			local difX = endPos.x - startPos.x
			local difY = endPos.y - startPos.y
			local difZ = endPos.z - startPos.z

			local fraction_middle = startFraction + (endFraction - startFraction) * fraction_first
			middle.x = startPos.x + fraction_first * difX
			middle.y = startPos.y + fraction_first * difY
			middle.z = startPos.z + fraction_first * difZ

			rayCastNode(self, node.children[side_id], startFraction, fraction_middle, startPos, middle, trace, mask)

			fraction_middle = startFraction + (endFraction - startFraction) * fraction_second
			middle.x = startPos.x + fraction_second * difX
			middle.y = startPos.y + fraction_second * difY
			middle.z = startPos.z + fraction_second * difZ
			side_id = (side_id == 1) and 2 or 1

			rayCastNode(self, node.children[side_id], fraction_middle, endFraction, middle, endPos, trace, mask)
		end
	end

	--- Returns a lua-based surface trace result.
	--- Supports mask for surface flags (SURF_*). See https://developer.valvesoftware.com/wiki/BSP_flags_(Source)
	---
	--- **Note**: If the trace starts inside a brush, faces facing away will be ignored. Using a mask enhances performance, focusing solely on faces matching the mask.
	--- @param startPos Vector
	--- @param endPos Vector
	--- @param mask SURF? The surface flags to check for. (SURF_*)
	--- @return table
	function meta_bsp:SurfaceTraceLine( startPos, endPos, mask)
		local trace = newTrace( startPos, endPos )
		nodes = self:GetNodes()
		leafs = self:GetLeafs()
		rayCastNode(self, 0, 0, 1, startPos, endPos, trace, mask)
		if trace.Fraction < 1 then
			trace.Hit = true
		end
		return trace
	end
end
