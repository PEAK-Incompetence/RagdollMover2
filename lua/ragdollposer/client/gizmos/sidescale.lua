-- Instead of drawing an arrow from vertices, let's draw a quad
-- oriented along its side while always facing us (beam). We'll use a
-- erode / dilate shader algorithm to shrink and grow the arrow.

---@module "base"
---@class GizmoSideScale: GizmoBase
local scale = include("base.lua")

---@param props GizmoProps
---@param orientation GizmoOrientation
function scale:Draw(props, orientation) end

-- Orient the directions
function scale:PreTransform(directions) end

---@param directions Vector[][]
---@param delta number[]
---@param transforms VMatrix[]
function scale:Transform(directions, delta, transforms)
	for j, d in ipairs(delta) do
		for i, matrix in ipairs(transforms) do
			matrix:SetTranslation((directions[i][j] or directions[1][j]) * d)
		end
	end
end

---@param direction Vector Vector(1, 0, 0) = XY, Vector(0, 1, 0) = YZ, Vector(0, 0, 1) = ZX
---@return GizmoSideScale
local function initialize(direction)
	local base = scale:Init()
	---@cast base GizmoSideScale
	return base
end

return initialize
