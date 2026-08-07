-- Instead of drawing an arrow from vertices, let's draw a quad
-- oriented along its side while always facing us (beam). We'll use a
-- erode / dilate shader algorithm to shrink and grow the arrow.

---@module "base"
---@class GizmoScale: GizmoBase
local scale = include("base.lua")

---@param props GizmoProps
---@param orientation GizmoOrientation
function scale:Draw(props, orientation) end

---Scales are with respect to the bone. If we want to make this scale
---in different ways (i.e. wrt world, wrt view), we need to calculate
---directions with respect to the parent
function scale:PreTransform() end

---@param directions Vector[]
---@param delta number
---@param transforms VMatrix[]
function scale:Transform(directions, delta, transforms)
	for i, matrix in ipairs(transforms) do
		matrix:SetScale((directions[i] or directions[1]) * delta)
	end
end

---@param direction Vector
---@return GizmoScale
local function initialize(direction)
	local base = scale:Init()
	---@cast base GizmoScale

	if direction then
		base._direction = direction
		RagdollPoser.Log("Set arrow direction to ", v)
	end
	return base
end

return initialize
