---@module "base"
---@class GizmoDisc: GizmoBase
---@field _direction Vector canonical axis with respect to the world
---@field _axis Vector axis determined by orientation mode
---@field _color Color
---@field _facesUs boolean
local disc = include("base.lua")
---@module "quaternion"
local quaternion = include("ragdollposer/shared/quaternion.lua")

-- DiscMaterial shaders come from legacy Ragdoll Mover. These should go inside `disc.lua`
local DiscMaterial = Material("ragdollposer/disc")
local DiscMaterialPartial = Material("ragdollposer/disc_partial")

-- Avoid clones of this
-- TODO: move this to the gizmo object and do dependency injection
DUMMY_MODEL = DUMMY_MODEL or ClientsideModel("models/shadertest/vertexlit.mdl")
DUMMY_MODEL:SetModelScale(0) -- make it invisible
local function sendVertexMetadata(x, y, z)
	render.SuppressEngineLighting(true)

	render.SetModelLighting(0, x, y, z)

	DUMMY_MODEL:DrawModel()

	render.SuppressEngineLighting(false)
end

local linePositions = {
	Vector(0, 1, 0),
	Vector(0, 0, 1),
	Vector(0, -1, 0),
	Vector(0, 0, -1),
}
local verts = {}

---@param mat IMaterial
---@param color Color
---@param pos Vector
---@param normal Vector
---@param width number
local function drawQuad(mat, color, pos, normal, scale, width)
	for i, point in ipairs(linePositions) do
		verts[i] = LocalToWorld(point * scale, angle_zero, pos, normal:Angle())
	end

	local eyepos = LocalPlayer():EyePos()
	local minDist, maxDist = math.huge, -math.huge
	for _, point in ipairs(verts) do
		minDist = math.min(minDist, eyepos:Distance(point))
		maxDist = math.max(maxDist, eyepos:Distance(point))
	end

	sendVertexMetadata(minDist, maxDist, 0)
	mat:SetFloat("$c0_x", width)
	mat:SetFloat("$c0_y", color.r / 255)
	mat:SetFloat("$c0_z", color.g / 255)
	mat:SetFloat("$c0_w", color.b / 255)
	render.SetMaterial(mat)
	render.DrawQuad(verts[1], verts[2], verts[3], verts[4], color)
end

local tempMin, tempMax = Vector(-1, -1, -1), Vector(1, 1, 1)

function disc:Intersect(eyepos, direction, props)
	local hitPos = util.IntersectRayWithPlane(eyepos, direction * 16384, props.pos, self._axis)
	local distSqr = hitPos and hitPos:DistToSqr(props.pos) or -1
	local halfScale = (self._facesUs and 0.625 or 0.5) * props.scale

	local isValid = distSqr < (halfScale * 1.1) ^ 2 and distSqr > (halfScale * 0.8) ^ 2
	if isValid and hitPos then
		debugoverlay.Sphere(hitPos, 2, 0.1, nil, true)
		return hitPos
	end
end

local YELLOW = Color(255, 255, 0)

---@param props GizmoProps
---@param selected boolean
function disc:Draw(props, selected)
	local color = selected and YELLOW or self._color

	local mat = props.partial and DiscMaterialPartial or DiscMaterial
	local discScale = 1
	if self._facesUs then
		local forward = -MainEyeAngles():Forward()
		self._axis = forward
		self._direction = forward
		discScale = 1.25
	end

	drawQuad(mat, color, props.pos, self._axis, discScale * props.scale, props.width)
end

function disc:UpdateOrientation(orientation, props)
	if orientation == RagdollPoser.Gizmo.Orientation.Local then
		self._axis = LocalToWorld(self._direction, angle_zero, vector_origin, props.ang)
	else
		self._axis:Set(self._direction)
	end
end

---Convert directions to quaternions
---@param direction Vector
---@return any
function disc:PreTransform(direction)
	local quat = quaternion.new(1)
	return quat:SetAngleAxis(0, direction)
end

---@param directions Quaternion[]
---@param start Vector
---@param endPos Vector
---@param transforms VMatrix[]
---@param accumulations number[]
---@param props GizmoProps
function disc:Transform(directions, start, endPos, transforms, accumulations, props)
	local delta = endPos - start

	for i, matrix in ipairs(transforms) do
		local direction = directions[i] or directions[1]
		local accumulationIndex = accumulations[i] and i or 1

		local startHit = (util.IntersectRayWithPlane(MainEyePos(), start * 16384, props.pos, self._axis) or start)
			- props.pos
		local endHit = (util.IntersectRayWithPlane(MainEyePos(), endPos * 16384, props.pos, self._axis) or endPos)
			- props.pos

		startHit:Normalize()
		endHit:Normalize()

		local qi = quaternion.fromAngle(matrix:GetAngles())

		local _, axis = direction:AngleAxis()
		local angle = math.atan2((startHit:Cross(endHit)):Dot(axis), startHit:Dot(endHit))
		local degrees = math.deg(angle)
		local newRot = accumulations[accumulationIndex] + degrees
		accumulations[accumulationIndex] = newRot
		local rotation = quaternion.new(1)
		rotation:SetAngleAxis(degrees, axis)
		rotation:Mul(qi)

		matrix:SetAngles(rotation:Angle())
	end
end

---Do all the child bones offset
function disc:PostTransform(transforms, locals, indices, parents)
	local worldMatrix = {}
	for i, b in ipairs(indices) do
		local matrix = transforms[i]
		local localChildMatrix = locals[b]
		if matrix and not localChildMatrix then
			worldMatrix[b] = matrix
		end

		if matrix and localChildMatrix then
			local newMatrix = worldMatrix[parents[b]] * localChildMatrix
			transforms[i] = newMatrix
			worldMatrix[b] = newMatrix
		end
	end
end

function disc:GetDirection()
	if self._facesUs then
		return -MainEyeAngles():Forward()
	end
	return self._axis
end

---@param v Vector? axis of rotation
---@return GizmoDisc
local function initialize(v)
	local base = disc:Init()
	---@cast base GizmoDisc

	-- If we don't define a rotation axis, then have it face us all the time
	if v then
		base._direction = v
		base._axis = v
		base._color = v:ToColor()
		RagdollPoser.Log("Set rotation axis to ", v)
	else
		base._facesUs = true
		base._direction = -MainEyeAngles():Forward()
		base._axis = -MainEyeAngles():Forward()
		base._color = Color(192, 192, 192, 255)
	end

	return base
end

return initialize
