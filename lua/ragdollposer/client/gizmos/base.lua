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
---@return Vector?
function Base:Intersect(eyepos, direction, props) end

---@return Vector
function Base:GetDirection()
	return vector_zero
end

---@param props GizmoProps
---@param orientation GizmoOrientation
---@param selected boolean
function Base:Draw(props, orientation, selected) end

---Calculate and cache before performing the transform
function Base:PreTransform() end

---@param directions Vector[] The directions of transformation--either a vector or an axis of rotation. This is an array because we might want to transform multiple bones in different directions
---@param delta number[] The amount of transformation, from x and y axes
---@param transforms VMatrix[] The initial state to mutate
---@param locals VMatrix[] Matrices local to their parent
function Base:Transform(directions, delta, transforms, locals) end

return Base
