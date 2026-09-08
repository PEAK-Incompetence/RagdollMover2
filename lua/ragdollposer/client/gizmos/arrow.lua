-- Instead of drawing an arrow from vertices, let's draw a quad
-- oriented along its side while always facing us (beam). We'll use a
-- erode / dilate shader algorithm to shrink and grow the arrow.

---@module "gizmo/base"
---@class GizmoArrow: GizmoBase
---@field _direction Vector
---@field _axis Vector
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
---@return Vector? intersectionPoint
function arrow:Intersect(eyepos, direction, props)
	render.SetColorMaterialIgnoreZ()
	local scale = props.scale

	local angle = props.orientation == RagdollPoser.Gizmo.Orientation.Local and props.ang or angle_zero
	render.DrawBox(
		props.pos,
		angle,
		tempMin + self._direction * scale * centerPadding,
		tempMax + self._direction * scale
	)
	local result = util.IntersectRayWithOBB(
		eyepos,
		direction * 16384,
		props.pos,
		angle,
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
---@param selected boolean
function arrow:Draw(props, selected)
	local mat = arrowMaterial
	local color = selected and YELLOW or self._color

	local endPos = props.pos + self._axis * props.scale

	mat:SetFloat("$c0_x", props.width)
	mat:SetFloat("$c0_y", color.r)
	mat:SetFloat("$c0_z", color.g)
	mat:SetFloat("$c0_w", color.b)
	mat:SetFloat("$c1_z", 1 / width)
	mat:SetFloat("$c1_w", 1 / height)
	render.SetMaterial(mat)

	render.DrawBeam(props.pos, endPos, props.scale * 0.5, 0, 1)
end

---@param props GizmoProps
---@return Vector axis
function arrow:GetDirection(props)
	return self._axis
end

local sharedDeltaProps = {
	Vector(),
	Vector(),
	Vector(),
}

local mirrorMatrix = Matrix()
mirrorMatrix:Identity()

function arrow:ProcessDelta(start, endPos, props, mirrorAxis)
	local forward = MainEyeAngles():Forward()
	local back = -forward
	local eyePos = MainEyePos()

	local startHit = (util.IntersectRayWithPlane(eyePos, start * 16384, props.pos, back) or start)
	local endHit = (util.IntersectRayWithPlane(eyePos, endPos * 16384, props.pos, back) or endPos)

	sharedDeltaProps[1]:Set(endHit)
	sharedDeltaProps[1]:Sub(startHit)

	if mirrorAxis >= 0 then
		local length = sharedDeltaProps[1]:Length()
		local vector = sharedDeltaProps[1]:Angle()
		vector:RotateAroundAxis(MainEyeAngles():Up(), 180)
		sharedDeltaProps[1]:Set(vector:Forward())
		sharedDeltaProps[1]:Mul(length)
	end

	sharedDeltaProps[2]:Set(startHit)
	sharedDeltaProps[3]:Set(endHit)

	return sharedDeltaProps
end

function arrow:PreTransform(v)
	return v
end

function arrow:UpdateOrientation(orientation, props)
	if orientation == RagdollPoser.Gizmo.Orientation.Local then
		self._axis = LocalToWorld(self._direction, angle_zero, vector_origin, props.ang)
	else
		self._axis:Set(self._direction)
	end
end

---@param directions Vector[]
---@param deltaProps DeltaProps
---@param transforms VMatrix[]
---@param accumulations number[]
function arrow:Transform(directions, deltaProps, transforms, accumulations, initials, props)
	local delta = deltaProps[1]
	for i, matrix in ipairs(transforms) do
		local vector = directions[i] or directions[1]
		local accumulationIndex = accumulations[i] and i or 1

		local length = vector:Dot(delta)
		local movement = vector * length
		accumulations[accumulationIndex] = accumulations[accumulationIndex] + length
		movement:Rotate(matrix:GetInverse():GetAngles())
		matrix:Translate(movement)
		debugoverlay.Axis(matrix:GetTranslation(), matrix:GetAngles(), 1, 0.1, true)
		debugoverlay.Line(matrix:GetTranslation(), matrix:GetTranslation() + vector * 10, 0.5)
	end
end

---@param direction Vector
---@return GizmoArrow arrow
local function initialize(direction)
	local base = arrow:Init()
	---@cast base GizmoArrow

	if direction then
		base._direction = direction
		base._axis = direction
		base._color = direction:ToColor()
		RagdollPoser.Log("Set arrow direction to ", direction)
	end

	return base
end

return initialize
