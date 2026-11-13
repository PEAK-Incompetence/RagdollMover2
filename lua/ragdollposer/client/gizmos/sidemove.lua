-- Instead of drawing an arrow from vertices, let's draw a quad
-- oriented along its side while always facing us (beam). We'll use a
-- erode / dilate shader algorithm to shrink and grow the arrow.

---@module "gizmo/base"
---@class GizmoSideMove: GizmoBase
---@field _axis Vector
---@field _direction Vector
---@field right Vector
---@field up Vector
---@field forward Vector
local sidemove = include("base.lua")

local developer = GetConVar("developer")

local squareLength = 0.15
local offset = 0.3
local YELLOW = Color(255, 255, 0)

local math_abs = math.abs
---@param vector Vector
local function makePositive(vector)
	vector:SetUnpacked(math_abs(vector.x), math_abs(vector.y), math_abs(vector.z))
end

local angleMatrix = Matrix()
---@param props GizmoProps
---@param selected boolean
function sidemove:Draw(props, selected)
	local color = selected and YELLOW or self._color
	local scale = props.scale

	local right = self.right
	local up = self.up
	local forward = self.forward

	render.SetColorMaterialIgnoreZ()
	render.CullMode(MATERIAL_CULLMODE_NONE)
	render.DrawQuadEasy(
		props.finalPos + (right + up + forward):GetNormalized() * scale * offset,
		self._axis,
		scale * squareLength,
		scale * squareLength,
		color,
		0
	)
	render.CullMode(MATERIAL_CULLMODE_CCW)
end

local tempMin, tempMax = Vector(-1, -1, -1), Vector(1, 1, 1)

function sidemove:Intersect(eyepos, direction, props)
	render.SetColorMaterialIgnoreZ()

	local scale = props.scale
	local angle = props.orientation == RagdollPoser.Gizmo.Orientation.Local and props.ang or angle_zero

	local right = self.right
	local up = self.up
	local forward = self.forward

	local off = (right + up + forward):GetNormalized() * scale * offset

	if developer:GetBool() then
		render.DrawBox(props.finalPos, angle, tempMin + off, tempMax + off)
	end
	local center = props.finalPos + off
	local hitPos = util.IntersectRayWithPlane(eyepos, direction * 16384, center, self._axis)

	if hitPos then
		local distance = hitPos:DistToSqr(center)

		local result = distance < (0.5 * squareLength * scale) ^ 2
		if result then
			debugoverlay.Box(hitPos, tempMin, tempMax, 0.1)
		end

		return result and hitPos
	end
end

function sidemove:UpdateOrientation(orientation, props)
	self.forward = self._direction:Cross(Vector(1, 0, 0))
	self.right = self._direction:Cross(Vector(0, 1, 0))
	self.up = self._direction:Cross(Vector(0, 0, 1))
	makePositive(self.forward)
	makePositive(self.right)
	makePositive(self.up)
	if orientation == RagdollPoser.Gizmo.Orientation.Local then
		self._axis = LocalToWorld(self._direction, angle_zero, vector_origin, props.ang)
		-- assume self._axis is Vector(1, 0, 0)
		-- one of these will end up zeroing out
		self.forward = LocalToWorld(self.forward, angle_zero, vector_origin, props.ang)
		self.right = LocalToWorld(self.right, angle_zero, vector_origin, props.ang)
		self.up = LocalToWorld(self.up, angle_zero, vector_origin, props.ang)
	else
		self._axis:Set(self._direction)
	end
end

-- Orient the directions
function sidemove:PreTransform(directions) end

local sharedDeltaProps = {
	Vector(),
	Vector(),
	Vector(),
}

function sidemove:ProcessDelta(start, endPos, props, mirrorAxis, eyeDelta)
	local eyePos, eyeVec, eyeAng = RagdollPoser.View:GetView()
	local forward = eyeAng:Forward()
	local back = -forward

	local startHit = (
		util.IntersectRayWithPlane(eyePos + eyeDelta, start * 16384, props.finalPos + eyeDelta, back) or start
	)
	local endHit = (
		util.IntersectRayWithPlane(eyePos + eyeDelta, endPos * 16384, props.finalPos + eyeDelta, back) or endPos
	)

	sharedDeltaProps[1]:Set(endHit)
	sharedDeltaProps[1]:Sub(startHit)
	sharedDeltaProps[1]:Add(eyeDelta)

	if mirrorAxis >= 0 then
		local length = sharedDeltaProps[1]:Length()
		local vector = sharedDeltaProps[1]:Angle()
		vector:RotateAroundAxis(eyeAng:Up(), 180)
		sharedDeltaProps[1]:Set(vector:Forward())
		sharedDeltaProps[1]:Mul(length)
	end

	sharedDeltaProps[2]:Set(startHit)
	sharedDeltaProps[3]:Set(endHit)

	return sharedDeltaProps
end

---@param directions Vector[]
---@param deltaProps DeltaProps
---@param transforms VMatrix[]
---@param accumulations number[]
function sidemove:Transform(directions, deltaProps, transforms, accumulations, initials, props)
	local delta = deltaProps[1]
	local right = self.right
	local up = self.up
	local forward = self.forward

	local vector = (right + up + forward):GetNormalized()
	for i, matrix in ipairs(transforms) do
		local accumulationIndex = accumulations[i] and i or 1

		local movement = right * right:Dot(delta) + forward * forward:Dot(delta) + up * up:Dot(delta)
		movement:Rotate(matrix:GetInverse():GetAngles())
		accumulations[accumulationIndex] = accumulations[accumulationIndex] + delta:Length()
		matrix:Translate(movement)
		debugoverlay.Axis(matrix:GetTranslation(), matrix:GetAngles(), 1, 0.1, true)
		debugoverlay.Line(matrix:GetTranslation(), matrix:GetTranslation() + vector * 10, 0.5)
	end
end
---@param direction Vector Vector(1, 0, 0) = XY, Vector(0, 1, 0) = YZ, Vector(0, 0, 1) = ZX
---@return GizmoSideMove sidemove
local function initialize(direction)
	local base = sidemove:Init()
	---@cast base GizmoSideMove
	if direction then
		-- Direction denotes the normal vector defining plane, so
		-- if X is our normal, then we control the YZ plane
		base._direction = direction
		base._axis = direction
		local color = direction:ToColor()
		base._color = color
	end
	return base
end

if RagdollPoser.Gizmo and not RagdollPoser.Gizmo:IsRefreshing() then
	hook.Run("RagdollPoser_Gizmo_Refresh", "sidemove")
end

return initialize
