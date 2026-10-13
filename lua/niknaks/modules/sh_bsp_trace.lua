
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
	for i = 1, #poly - 2 do
		local v0 = poly[1]
		local v1 = poly[i + 1]
		local v2 = poly[i + 2]
		local hitPos = IsRayIntersectingTriangle(origin, dir, v0, v1, v2)
		if hitPos then return hitPos end
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

	if (dot1 > 0) ~= (dot2 > 0) then
		local t = dot1 / ( dot1 - dot2 )

		if t <= 0 or t >= 1 then return end
		local poly = self:GetVertexs()
		if not poly then return end
		local dir = (endPos - startPos):GetNormalized()
		for i = 1, #poly - 2 do
            local v0 = poly[1]
            local v1 = poly[i + 1]
            local v2 = poly[i + 2]

            -- Check if ray is intersecting triangle point v0, v1 and v2
			local hit = IsRayIntersectingTriangle(startPos, dir, v0, v1, v2)
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

	if (dot1 > 0) ~= (dot2 > 0) then

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

	-- The segment is passed as six numbers instead of Vectors. The old shared "middle" Vector was handed down as
	-- startPos/endPos and then overwritten by the recursion below it, corrupting the parent's second half.
	---@param nodeIndex number
	---@param startFraction number
	---@param endFraction number
	---@param sx number
	---@param sy number
	---@param sz number
	---@param ex number
	---@param ey number
	---@param ez number
	---@param trace table
	---@param mask number? The surface flags to check for. (SURF_*)
	local function rayCastNode( nodeIndex, startFraction, endFraction, sx, sy, sz, ex, ey, ez, trace, mask )
		local traceFraction = trace.Fraction
		if traceFraction <= startFraction then return end

		if nodeIndex < 0 then
			---@type BSPLeafObject
			local leaf = leafs[ -nodeIndex - 1]
			if trace.StartSolid or traceFraction < 1 then return end
			local normal = trace.Normal
			local faces = leaf:GetFaces()
			for i = 1, #faces do
				local face = faces[i]
				if dot(face.plane.normal, normal) < 0 then
					-- Check mask
					if mask and bit.band(face:GetTexInfo().flags, mask) == 0 then continue end
					rayCastFace(face, trace)
				end
			end
			return
		end

		--- @type MapNode
		local node = nodes[nodeIndex]
		if not node then return end

		local plane = node.plane
		if not plane then return end

		local start_dist, end_dist
		local ptype, pdist = plane.type, plane.dist

		if ptype == 0 then
			start_dist = sx - pdist
			end_dist = ex - pdist
		elseif ptype == 1 then
			start_dist = sy - pdist
			end_dist = ey - pdist
		elseif ptype == 2 then
			start_dist = sz - pdist
			end_dist = ez - pdist
		else
			local nx, ny, nz = plane.nx, plane.ny, plane.nz
			start_dist = sx * nx + sy * ny + sz * nz - pdist
			end_dist = ex * nx + ey * ny + ez * nz - pdist
		end

		if start_dist >= 0 and end_dist >= 0 then
			rayCastNode(node.children[1], startFraction, endFraction, sx, sy, sz, ex, ey, ez, trace, mask)
		elseif start_dist < 0 and end_dist < 0 then
			rayCastNode(node.children[2], startFraction, endFraction, sx, sy, sz, ex, ey, ez, trace, mask)
		else
			local side_id, fraction_first, fraction_second = 0, 0, 0
			local inversed_distance = 1 / (start_dist - end_dist)

			if start_dist < end_dist then
				side_id = 2
				fraction_first = (start_dist - FLT_EPSILON) * inversed_distance
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
			local difX, difY, difZ = ex - sx, ey - sy, ez - sz

			local fraction_middle = startFraction + (endFraction - startFraction) * fraction_first
			rayCastNode(node.children[side_id], startFraction, fraction_middle, sx, sy, sz,
				sx + fraction_first * difX, sy + fraction_first * difY, sz + fraction_first * difZ, trace, mask)

			fraction_middle = startFraction + (endFraction - startFraction) * fraction_second
			side_id = (side_id == 1) and 2 or 1

			rayCastNode(node.children[side_id], fraction_middle, endFraction,
				sx + fraction_second * difX, sy + fraction_second * difY, sz + fraction_second * difZ, ex, ey, ez, trace, mask)
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
		rayCastNode(0, 0, 1, startPos.x, startPos.y, startPos.z, endPos.x, endPos.y, endPos.z, trace, mask)
		if trace.Fraction < 1 then
			trace.Hit = true
		end
		return trace
	end
end
