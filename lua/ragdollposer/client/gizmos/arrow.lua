-- Instead of drawing an arrow from vertices, let's draw a quad
-- oriented along its side while always facing us (beam). We'll use a
-- erode / dilate shader algorithm to shrink and grow the arrow.

---@module "base"
---@class GizmoArrow: GizmoBase
---@field _direction Vector
---@field _color Color
local arrow = include("base.lua")

local arrowMaterial = Material("ragdollposer/arrow")
local texture = arrowMaterial:GetTexture("$basetexture")
local width, height = texture:Width(), texture:Height()

local tempMin, tempMax = Vector(-1, -1, -1), Vector(1, 1, 1)
local centerPadding = 0.05

---@param eyepos Vector
---@param direction Vector
---@param props GizmoProps
---@return Vector?
function arrow:Intersect(eyepos, direction, props)
	render.SetColorMaterialIgnoreZ()
	local scale = props.scale

	render.DrawBox(
		props.pos,
		props.ang,
		tempMin + self._direction * scale * centerPadding,
		tempMax + self._direction * scale
	)
	local result = util.IntersectRayWithOBB(
		eyepos,
		direction * 16384,
		props.pos,
		props.ang,
		tempMin + self._direction * scale * centerPadding,
		tempMax + self._direction * scale
	)
	if result then
		debugoverlay.Box(result, tempMin, tempMax, 0.1)
	end
	return result
end

local YELLOW = Color(255, 255, 0)

---@param props GizmoProps
---@param orientation GizmoOrientation
function arrow:Draw(props, orientation, selected)
	-- print(self._direction)

	local mat = arrowMaterial
	local color = selected and YELLOW or self._color

	local endPos = props.pos + self._direction * props.scale

	mat:SetFloat("$c0_x", props.width)
	mat:SetFloat("$c0_y", color.r)
	mat:SetFloat("$c0_z", color.g)
	mat:SetFloat("$c0_w", color.b)
	mat:SetFloat("$c1_z", 1 / width)
	mat:SetFloat("$c1_w", 1 / height)
	render.SetMaterial(mat)

	render.DrawBeam(props.pos, endPos, props.scale * 0.5, 0, 1)
	-- render.DrawBox(props.pos, props.ang, -tempMax, tempMax + self._direction * props.scale)
	-- render.DrawBox(props.pos, props.ang, tempMin, tempMax)
end

function arrow:GetDirection()
	return self._direction
end

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

	if direction then
		base._direction = direction
		base._color = direction:ToColor()
		RagdollPoser.Log("Set arrow direction to ", direction)
	end

	return base
end

return initialize
