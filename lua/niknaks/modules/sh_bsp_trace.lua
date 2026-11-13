
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

--- Returns the face's vertices as a flat number array and the vertex count.
--- @param face BSPFaceObject
--- @return number[] xyz
--- @return number count
local function flatVertexs( face )
	local flat = face._vertexFlat
	if flat then return flat, face._vertexCount end

	local poly = face:GetVertexs()
	local count = poly and #poly or 0
	flat = {}
	for i = 1, count do
		local v = poly[i]
		local j = i * 3
		flat[j - 2], flat[j - 1], flat[j] = v.x, v.y, v.z
	end

	face._vertexFlat = flat
	face._vertexCount = count
	return flat, count
end

--- Möller-Trumbore intersection algorithm.
--- Returns the distance along the ray to the first triangle that is hit, or nil.
--- @param v number[] Flat vertex array
--- @param count number Vertex count
--- @return number?
local function rayPolygonDistance( v, count, ox, oy, oz, dx, dy, dz )
	local ax, ay, az = v[1], v[2], v[3]
	for i = 1, count - 2 do
		local j = i * 3
		local e1x, e1y, e1z = v[j + 1] - ax, v[j + 2] - ay, v[j + 3] - az
		local e2x, e2y, e2z = v[j + 4] - ax, v[j + 5] - ay, v[j + 6] - az

		-- pvec = dir x e2
		local px, py, pz = dy * e2z - dz * e2y, dz * e2x - dx * e2z, dx * e2y - dy * e2x
		local det = e1x * px + e1y * py + e1z * pz

		-- Ray and triangle are parallel if det is close to 0
		if det <= -0.0001 or det >= 0.0001 then
			local invDet = 1 / det
			local tx, ty, tz = ox - ax, oy - ay, oz - az
			local u = ( tx * px + ty * py + tz * pz ) * invDet
			if u >= 0 and u <= 1 then
				-- qvec = tvec x e1
				local qx, qy, qz = ty * e1z - tz * e1y, tz * e1x - tx * e1z, tx * e1y - ty * e1x
				local w = ( dx * qx + dy * qy + dz * qz ) * invDet
				if w >= 0 and u + w <= 1 then
					local distance = ( e2x * qx + e2y * qy + e2z * qz ) * invDet
					if distance > 0 then return distance end
				end
			end
		end
	end
end

--- Checks to see if ray is intersecting the given face.
--- @param origin Vector
--- @param dir Vector The normalized direction.
--- @return Vector? -- The intersection point if found, otherwise nil
function meta_face:LineDirectionIntersection( origin, dir )
	local flat, count = flatVertexs( self )
	local distance = rayPolygonDistance( flat, count, origin.x, origin.y, origin.z, dir.x, dir.y, dir.z )
	if distance then return origin + dir * distance end
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
		local dir = (endPos - startPos):GetNormalized()
		local flat, count = flatVertexs( self )
		local distance = rayPolygonDistance( flat, count, startPos.x, startPos.y, startPos.z, dir.x, dir.y, dir.z )
		if distance then return startPos + dir * distance end
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

do
	local min, max, abs, band = math.min, math.max, math.abs, bit.band
	local nodes = {}
	local leafs = {}

	-- The ray of the trace being run: start, end and normalized direction. Set by SurfaceTraceLine.
	local rsx, rsy, rsz = 0, 0, 0
	local rex, rey, rez = 0, 0, 0
	local rdx, rdy, rdz = 0, 0, 0

	-- Raycasts a BSPFaceObject and returns the result in the trace table.
	---@param face BSPFaceObject
	---@param plane BSPPlane
	---@param trace table
	---@return boolean
	local function rayCastFace( face, plane, trace, anyHit )
		local nx, ny, nz, dist = plane.nx, plane.ny, plane.nz, plane.dist
		local dot1 = nx * rsx + ny * rsy + nz * rsz - dist
		local dot2 = nx * rex + ny * rey + nz * rez - dist

		if (dot1 > 0) ~= (dot2 > 0) then

			if abs(dot1 - dot2) < DIST_EPSILON then return false end

			local t = dot1 / ( dot1 - dot2 )

			if t <= 0 or t >= trace.Fraction then return false end

			local flat, count = flatVertexs( face )
			if rayPolygonDistance( flat, count, rsx, rsy, rsz, rdx, rdy, rdz ) then
				if anyHit then return true end
				local startPos, endPos = trace.StartPos, trace.EndPos
				trace.Fraction = t
				trace.HitPos = startPos + (endPos - startPos) * t
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

	local rayLen = 0
	local traceId = 0
	local dispLeafs = nil

	--- Works out the displaced grid points of a displacement faces.
	--- @param face BSPFaceObject
	--- @return number[]? xyz Flat array of points, row by row. Nil if the displacement is broken.
	--- @return number width Points per row
	local function displacementPoints( face )
		local dispInfo = face:GetDisplacementInfo()
		local corners = face:GetVertexs()
		if not dispInfo or not corners or #corners ~= 4 then return end

		-- The grid starts at the corner closest to the displacement's start position
		local start = dispInfo.startPosition
		local startIdx, minDist = 1, math.huge
		for i = 1, 4 do
			local dist = corners[i]:Distance( start )
			if dist < minDist then
				minDist = dist
				startIdx = i
			end
		end
		local A, B = corners[startIdx], corners[startIdx % 4 + 1]
		local C, D = corners[( startIdx + 1 ) % 4 + 1], corners[( startIdx + 2 ) % 4 + 1]
		local Ax, Ay, Az = A.x, A.y, A.z
		local Bx, By, Bz = B.x, B.y, B.z
		local ADx, ADy, ADz = D.x - Ax, D.y - Ay, D.z - Az
		local BCx, BCy, BCz = C.x - Bx, C.y - By, C.z - Bz

		local power2 = 2 ^ dispInfo.power
		local stride = power2 + 1
		local vertStart = dispInfo.DispVertStart
		local dispVertices = face.__map:GetDispVerts()

		local xyz = {}
		local minx, miny, minz = math.huge, math.huge, math.huge
		local maxx, maxy, maxz = -math.huge, -math.huge, -math.huge
		for index = 0, stride * stride - 1 do
			local vertex = dispVertices[vertStart + index]
			if not vertex then return end -- The lump ends early

			local t1 = index % stride / power2
			local t2 = math.floor( index / stride ) / power2
			local p0x, p0y, p0z = Ax + ADx * t1, Ay + ADy * t1, Az + ADz * t1
			local p1x, p1y, p1z = Bx + BCx * t1, By + BCy * t1, Bz + BCz * t1
			local vec, dist = vertex.vec, vertex.dist
			local x = p0x + ( p1x - p0x ) * t2 + vec.x * dist
			local y = p0y + ( p1y - p0y ) * t2 + vec.y * dist
			local z = p0z + ( p1z - p0z ) * t2 + vec.z * dist

			local j = index * 3
			xyz[j + 1], xyz[j + 2], xyz[j + 3] = x, y, z
			if x < minx then minx = x end if x > maxx then maxx = x end
			if y < miny then miny = y end if y > maxy then maxy = y end
			if z < minz then minz = z end if z > maxz then maxz = z end
		end

		return xyz, stride, minx, miny, minz, maxx, maxy, maxz
	end

	--- Builds the trace data for every displacement of the map. Done once, on the first trace.
	--- @param map BSPObject
	--- @return table<number, table[]>
	local function buildDisplacements( map )
		local byLeaf = {}
		for _, face in pairs( map:GetDisplacmentFaces() ) do
			local xyz, width, minx, miny, minz, maxx, maxy, maxz = displacementPoints( face )
			local texinfo = face:GetTexInfo()
			if xyz then
				-- Which way the grid's triangles wind, compared to the side the face points at
				local n = face.plane.normal
				local ax, ay, az = xyz[1], xyz[2], xyz[3]
				local b, c = width * 3, ( width + 1 ) * 3 -- Grid points ( row 2, col 1 ) and ( row 2, col 2 )
				local e1x, e1y, e1z = xyz[b + 1] - ax, xyz[b + 2] - ay, xyz[b + 3] - az
				local e2x, e2y, e2z = xyz[c + 1] - ax, xyz[c + 2] - ay, xyz[c + 3] - az
				local facing = ( e1y * e2z - e1z * e2y ) * n.x + ( e1z * e2x - e1x * e2z ) * n.y + ( e1x * e2y - e1y * e2x ) * n.z

				local record = {
					face = face,
					xyz = xyz,
					width = width,
					winding = facing >= 0 and 1 or -1,
					flags = texinfo and texinfo.flags or 0,
					minx = minx, miny = miny, minz = minz,
					maxx = maxx, maxy = maxy, maxz = maxz,
					traceId = 0, -- The trace this was last tested for, and what came out of it:
					distance = false,
					nx = 0, ny = 0, nz = 0,
				}

				local touched = map:AABBInLeafs( 0, Vector( minx, miny, minz ), Vector( maxx, maxy, maxz ), 1 )
				for i = 1, #touched do
					local id = touched[i].__id
					local list = byLeaf[id]
					if not list then
						list = {}
						byLeaf[id] = list
					end
					list[#list + 1] = record
				end
			end
		end
		return byLeaf
	end

	local function rayTriangle( v, a, b, c, winding, best )
		local ax, ay, az = v[a + 1], v[a + 2], v[a + 3]
		local e1x, e1y, e1z = v[b + 1] - ax, v[b + 2] - ay, v[b + 3] - az
		local e2x, e2y, e2z = v[c + 1] - ax, v[c + 2] - ay, v[c + 3] - az
		local px, py, pz = rdy * e2z - rdz * e2y, rdz * e2x - rdx * e2z, rdx * e2y - rdy * e2x
		local det = e1x * px + e1y * py + e1z * pz
		if det * winding < 0.0001 then return end -- Parallel, or seen from behind

		local invDet = 1 / det
		local tx, ty, tz = rsx - ax, rsy - ay, rsz - az
		local u = ( tx * px + ty * py + tz * pz ) * invDet
		if u < 0 or u > 1 then return end
		local qx, qy, qz = ty * e1z - tz * e1y, tz * e1x - tx * e1z, tx * e1y - ty * e1x
		local w = ( rdx * qx + rdy * qy + rdz * qz ) * invDet
		if w < 0 or u + w > 1 then return end
		local distance = ( e2x * qx + e2y * qy + e2z * qz ) * invDet
		if distance <= 0 or distance >= best then return end

		return distance, ( e1y * e2z - e1z * e2y ) * winding, ( e1z * e2x - e1x * e2z ) * winding, ( e1x * e2y - e1y * e2x ) * winding
	end

	local function rayDisplacement( rec, anyHit )
		rec.traceId = traceId
		rec.distance = false

		-- Does the ray get anywhere near it? Slab test against the bounding box.
		local tmin, tmax = 0, rayLen
		if rdx > -1e-9 and rdx < 1e-9 then
			if rsx < rec.minx or rsx > rec.maxx then return end
		else
			local t1, t2 = ( rec.minx - rsx ) / rdx, ( rec.maxx - rsx ) / rdx
			if t1 > t2 then t1, t2 = t2, t1 end
			if t1 > tmin then tmin = t1 end
			if t2 < tmax then tmax = t2 end
			if tmin > tmax then return end
		end
		if rdy > -1e-9 and rdy < 1e-9 then
			if rsy < rec.miny or rsy > rec.maxy then return end
		else
			local t1, t2 = ( rec.miny - rsy ) / rdy, ( rec.maxy - rsy ) / rdy
			if t1 > t2 then t1, t2 = t2, t1 end
			if t1 > tmin then tmin = t1 end
			if t2 < tmax then tmax = t2 end
			if tmin > tmax then return end
		end
		if rdz > -1e-9 and rdz < 1e-9 then
			if rsz < rec.minz or rsz > rec.maxz then return end
		else
			local t1, t2 = ( rec.minz - rsz ) / rdz, ( rec.maxz - rsz ) / rdz
			if t1 > t2 then t1, t2 = t2, t1 end
			if t1 > tmin then tmin = t1 end
			if t2 < tmax then tmax = t2 end
			if tmin > tmax then return end
		end

		-- Same triangles as the mesh: every grid cell is two triangles, the diagonal alternating like a checkerboard.
		local v, width, winding = rec.xyz, rec.width, rec.winding
		local best = rayLen
		local bnx, bny, bnz = 0, 0, 0
		for i = 1, width - 1 do
			for j = 1, width - 1 do
				local i1 = ( ( i - 1 ) * width + j - 1 ) * 3
				local i2 = ( i * width + j - 1 ) * 3
				local i3 = i2 + 3
				local i4 = i1 + 3
				local d, nx, ny, nz
				if ( i + j ) % 2 == 0 then
					d, nx, ny, nz = rayTriangle( v, i1, i2, i3, winding, best )
					if d and anyHit then rec.distance = d return end
					if d then best, bnx, bny, bnz = d, nx, ny, nz end
					d, nx, ny, nz = rayTriangle( v, i1, i3, i4, winding, best )
					if d and anyHit then rec.distance = d return end
					if d then best, bnx, bny, bnz = d, nx, ny, nz end
				else
					d, nx, ny, nz = rayTriangle( v, i1, i2, i4, winding, best )
					if d and anyHit then rec.distance = d return end
					if d then best, bnx, bny, bnz = d, nx, ny, nz end
					d, nx, ny, nz = rayTriangle( v, i2, i3, i4, winding, best )
					if d and anyHit then rec.distance = d return end
					if d then best, bnx, bny, bnz = d, nx, ny, nz end
				end
			end
		end

		if best < rayLen then
			rec.distance = best
			rec.nx, rec.ny, rec.nz = bnx, bny, bnz
		end
	end

	--- Raycasts the displacements registered with a leaf.
	--- @param list table[]
	--- @param trace table
	--- @param mask number?
	local function rayCastDisplacements( list, trace, mask, anyHit )
		for i = 1, #list do
			local rec = list[i]
			if not mask or band( rec.flags, mask ) ~= 0 then
				if rec.traceId ~= traceId then rayDisplacement( rec, anyHit ) end
				local distance = rec.distance
				if distance then
					local t = distance / rayLen
					if t < trace.Fraction then
						if anyHit then return true end
						local startPos, endPos = trace.StartPos, trace.EndPos
						local face = rec.face
						local normal = Vector( rec.nx, rec.ny, rec.nz )
						normal:Normalize()
						trace.Fraction = t
						trace.HitPos = startPos + (endPos - startPos) * t
						trace.HitNormal = normal
						trace.Face = face
						trace.Hit = true
						trace.HitSky = face:IsSkyBox3D() or face:IsSkyBox()
						trace.SurfaceFlags = rec.flags
					end
				end
			end
		end
	end

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
	local function rayCastNode( nodeIndex, startFraction, endFraction, sx, sy, sz, ex, ey, ez, trace, mask, anyHit )
		local traceFraction = trace.Fraction
		if traceFraction <= startFraction then return end

		if nodeIndex < 0 then
			---@type BSPLeafObject
			local leaf = leafs[ -nodeIndex - 1]
			if trace.StartSolid then return end
			local faces = leaf:GetFaces()
			for i = 1, #faces do
				local face = faces[i]
				local plane = face.plane
				-- Only faces that point against the ray
				if plane.nx * rdx + plane.ny * rdy + plane.nz * rdz < 0 then
					-- Check mask
					if not mask or band(face:GetTexInfo().flags, mask) ~= 0 then
						if rayCastFace( face, plane, trace, anyHit ) and anyHit then return true end
					end
				end
			end

			local displacements = dispLeafs and dispLeafs[ -nodeIndex - 1 ]
			if displacements then
				if rayCastDisplacements( displacements, trace, mask, anyHit ) and anyHit then return true end
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
			return rayCastNode( node.children[1], startFraction, endFraction, sx, sy, sz, ex, ey, ez, trace, mask, anyHit )
		elseif start_dist < 0 and end_dist < 0 then
			return rayCastNode( node.children[2], startFraction, endFraction, sx, sy, sz, ex, ey, ez, trace, mask, anyHit )
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
			local hit = rayCastNode( node.children[side_id], startFraction, fraction_middle, sx, sy, sz,
				sx + fraction_first * difX, sy + fraction_first * difY, sz + fraction_first * difZ, trace, mask, anyHit )
			if hit and anyHit then return true end

			fraction_middle = startFraction + (endFraction - startFraction) * fraction_second
			side_id = (side_id == 1) and 2 or 1

			return rayCastNode( node.children[side_id], fraction_middle, endFraction,
				sx + fraction_second * difX, sy + fraction_second * difY, sz + fraction_second * difZ, ex, ey, ez, trace, mask, anyHit )
		end
	end

	--- Returns a lua-based surface trace result.
	--- Supports mask for surface flags (SURF_*). See https://developer.valvesoftware.com/wiki/BSP_flags_(Source)
	---
	--- **Note**: If the trace starts inside a brush, faces facing away will be ignored. Using a mask enhances performance, focusing solely on faces matching the mask.
	--- @param startPos Vector
	--- @param endPos Vector
	--- @param mask SURF? The surface flags to check for. (SURF_*)
	--- @param ignoreDisplacements boolean? If true, displacements are skipped. This is faster.
	--- @return table
	function meta_bsp:SurfaceTraceLine( startPos, endPos, mask, ignoreDisplacements )
		local trace = newTrace( startPos, endPos )
		nodes = self:GetNodes()
		leafs = self:GetLeafs()
		local normal = trace.Normal
		rsx, rsy, rsz = startPos.x, startPos.y, startPos.z
		rex, rey, rez = endPos.x, endPos.y, endPos.z
		rdx, rdy, rdz = normal.x, normal.y, normal.z

		rayLen = startPos:Distance( endPos )
		dispLeafs = nil
		if not ignoreDisplacements and rayLen > 0 then
			local byLeaf = self._dispTraceLeafs
			if not byLeaf then
				byLeaf = buildDisplacements( self )
				self._dispTraceLeafs = byLeaf
			end
			dispLeafs = byLeaf
			traceId = traceId + 1
		end

		rayCastNode(0, 0, 1, startPos.x, startPos.y, startPos.z, endPos.x, endPos.y, endPos.z, trace, mask)
		if trace.Fraction < 1 then
			trace.Hit = true
		end
		return trace
	end

	--- Tests for any surface hit, with the same face winding, segment endpoints,
	--- mask and displacement rules as SurfaceTraceLine. Does not find the nearest
	--- hit or construct hit metadata. Sky-aware callers still need SurfaceTraceLine.
	--- @param startPos Vector
	--- @param endPos Vector
	--- @param mask SURF?
	--- @param ignoreDisplacements boolean?
	--- @return boolean
	function meta_bsp:SurfaceTraceBlocked( startPos, endPos, mask, ignoreDisplacements )
		nodes = self:GetNodes()
		leafs = self:GetLeafs()
		-- Keep native Vector normalization identical to the full trace at edges.
		local normal = ( endPos - startPos ):GetNormalized()
		rsx, rsy, rsz = startPos.x, startPos.y, startPos.z
		rex, rey, rez = endPos.x, endPos.y, endPos.z
		rdx, rdy, rdz = normal.x, normal.y, normal.z
		rayLen = startPos:Distance( endPos )
		dispLeafs = nil
		if not ignoreDisplacements and rayLen > 0 then
			local byLeaf = self._dispTraceLeafs
			if not byLeaf then
				byLeaf = buildDisplacements( self )
				self._dispTraceLeafs = byLeaf
			end
			dispLeafs = byLeaf
			traceId = traceId + 1
		end
		return rayCastNode( 0, 0, 1, startPos.x, startPos.y, startPos.z,
			endPos.x, endPos.y, endPos.z, { Fraction = 1 }, mask, true ) == true
	end
end
