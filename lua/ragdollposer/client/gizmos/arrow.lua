-- Instead of drawing an arrow from vertices, let's draw a quad
-- oriented along its side while always facing us (beam). We'll use a
-- erode / dilate shader algorithm to shrink and grow the arrow.

---@module "base"
---@class GizmoArrow: GizmoBase
---@field _direction Vector
local arrow = include("base.lua")

---@param pos Vector
---@param ang Angle
---@param orientation GizmoOrientation
function arrow:Draw(pos, ang, orientation) end

---@param directions Vector[]
---@param delta number
---@param transforms VMatrix[]
function arrow:Transform(directions, delta, transforms)
	for i, matrix in ipairs(transforms) do
		matrix:SetTranslation((directions[i] or directions[1]) * delta)
	end
end

---@param direction Vector
---@return GizmoArrow
local function initialize(direction)
	local base = arrow:Init()
	---@cast base GizmoArrow

	if v then
		base._direction = direction
		RagdollPoser.Log("Set arrow direction to ", v)
	end

	return base
end

return initialize
