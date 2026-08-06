---@class GizmoBase
local Base = {}
Base.__index = Base

---How the gizmo is rotated when selecting a bone
---@enum GizmoOrientation
Base.Orientation = {
	World = 0, -- no orientation
	Local = 1, -- oriented to bone
}

---The point relative to where transforms occur; useful for multiple bones
---@enum GizmoPivot
Base.Pivot = {
	Median = 0,
	Bounding = 1,
	Individual = 2,
}

function Base:Init()
	local base = setmetatable({}, Base)
	return base
end

---@param eyepos Vector
---@param direction Vector
function Base:Intersect(eyepos, direction) end

---@param pos Vector
---@param ang Angle
---@param orientation GizmoOrientation
function Base:Draw(pos, ang, orientation) end

---Calculate and cache before performing the transform
function Base:PreTransform() end

---@param directions Vector[] The directions of transformation--either a vector or an axis of rotation. This is an array because we might want to transform multiple bones in different directions
---@param delta number[] The amount of transformation, from x and y axes
---@param transforms VMatrix[] The initial state to mutate
function Base:Transform(directions, delta, transforms) end

return Base
