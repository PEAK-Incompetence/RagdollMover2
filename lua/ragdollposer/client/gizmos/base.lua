---@class GizmoBase
local Base = {}
Base.__index = Base

local scaledMatrix = Matrix()
local forward = Vector()
local right = Vector()
local up = Vector()
local outputScale = Vector()

-- Project an affine scale onto the source bone's orthogonal axes, discarding shear.
function Base.SetShearFreeScale(output, source, scaleMatrix)
	scaledMatrix:Set(scaleMatrix)
	scaledMatrix:Mul(source)

	local angles = source:GetAngles()
	forward:Set(source:GetForward())
	if forward:LengthSqr() < 1e-12 then
		forward:Set(angles:Forward())
	end
	forward:Normalize()

	up:Set(source:GetUp())
	up:Sub(forward * up:Dot(forward))
	if up:LengthSqr() < 1e-12 then
		right:Set(angles:Right())
		right:Sub(forward * right:Dot(forward))
		right:Normalize()
		up:Set(right:Cross(forward))
	else
		up:Normalize()
		right:Set(forward:Cross(up))
		right:Normalize()
	end

	up:Set(right:Cross(forward))
	up:Normalize()

	outputScale.x = scaledMatrix:GetForward():Dot(forward)
	outputScale.y = scaledMatrix:GetRight():Dot(right)
	outputScale.z = scaledMatrix:GetUp():Dot(up)

	output:Set(source)
	output:SetTranslation(scaledMatrix:GetTranslation())
	output:SetForward(forward)
	output:SetRight(right)
	output:SetUp(up)
	output:SetScale(outputScale)
end

---@param v Vector Vector to project
---@param n Vector Normal vector of plane
---@return Vector projection Projection of vector on the plane
function Base:ProjectVectorToPlane(v, n)
	local projection = v - v:Dot(n) / n:LengthSqr() * n
	return projection
end

---@param v Vector Vector to project. Must be unit
---@param n Vector Normal vector of plane. Must be unit
---@return Vector projection Projection of vector on the plane
function Base:ProjectUnitToPlane(v, n)
	local projection = v - v:Dot(n) * n
	return projection
end

function Base:Init()
	local base = setmetatable({}, Base)
	return base
end

---@param eyepos Vector
---@param direction Vector
---@param props GizmoProps
---@return Vector? intersectionPoint
function Base:Intersect(eyepos, direction, props) end

---@param props GizmoProps
---@return Vector axis
function Base:GetDirection(props)
	return vector_origin
end

function Base:FinishTransform() end

function Base:SendVertexMetaData(vertexObject, vertexProps) end

-- When we switch the orientation, change the `_direction` field
---@param orientation GizmoOrientation
---@param props GizmoProps
function Base:UpdateOrientation(orientation, props) end

---@param props GizmoProps
---@param selected boolean
function Base:Draw(props, selected) end

--- Info about delta
--- - [1] delta
--- - [2] start
--- - [3] endPos
---@class DeltaProps
---@field [1] Vector delta
---@field [2] Vector start
---@field [3] Vector endPos

---@param start Vector
---@param endPos Vector
---@param props GizmoProps
---@param mirrorAxis integer
---@param eyeDelta Vector
---@return DeltaProps deltaProps
function Base:ProcessDelta(start, endPos, props, mirrorAxis, eyeDelta)
	return {}
end

---@param start Vector
---@param endPos Vector
---@param props GizmoProps
---@param mirrorAxis integer
---@param delta number
---@return DeltaProps deltaProps
function Base:ProcessDeltaUI(start, endPos, props, mirrorAxis, delta)
	return {}
end

---Calculate and cache before performing the transform
---@param direction Vector
---@param initials table
function Base:PreTransform(direction, initials) end

---@param directions Vector[] The directions of transformation--either a vector or an axis of rotation. This is an array because we might want to transform multiple bones in different directions
---@param deltaProps DeltaProps
---@param transform VMatrix The initial state to mutate
---@param accumulations number[] Accumulation of translation or rotation, which we can use for snapping behaviors
---@param initials table Accumulation of translation or rotation, which we can use for snapping behaviors
---@param gizmoProps GizmoProps
---@return VMatrix
function Base:Transform(directions, deltaProps, transform, accumulations, initials, gizmoProps) end

---@param transform VMatrix
---@param locals LocalMatrixInfo[] Matrices where [1] is the child bone and [2] is the child bone matrix relative to its parent
---@param parents integer[] Dictionary where a child bones are keys and their parent bone is the value
---@param output VMatrix[]
function Base:PostTransform(transform, locals, parents, output) end

return Base
