---@class GizmoBase
local Base = {}
Base.__index = Base

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

---Calculate and cache before performing the transform
---@param direction Vector
---@param initials table
function Base:PreTransform(direction, initials) end

---@param directions Vector[] The directions of transformation--either a vector or an axis of rotation. This is an array because we might want to transform multiple bones in different directions
---@param deltaProps DeltaProps
---@param transforms VMatrix[] The initial state to mutate
---@param accumulations table Accumulation of translation or rotation, which we can use for snapping behaviors
---@param initials table Accumulation of translation or rotation, which we can use for snapping behaviors
---@param gizmoProps GizmoProps
function Base:Transform(directions, deltaProps, transforms, accumulations, initials, gizmoProps) end

---@param transforms VMatrix[]
---@param locals VMatrix[] Matrices where the key is the child bone and the value is the child bone matrix relative to its parent
---@param indices integer[]
---@param parents integer[] Dictionary where a child bones are keys and their parent bone is the value
function Base:PostTransform(transforms, locals, indices, parents) end

return Base
