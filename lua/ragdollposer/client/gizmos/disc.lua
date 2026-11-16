---@module "gizmo/base"
---@class GizmoDisc: GizmoBase
---@field _direction Vector canonical axis with respect to the world
---@field _axis Vector axis determined by orientation mode
---@field _color Color
---@field _facesUs boolean
local disc = include("base.lua")
---@module "quaternion"
local quaternion = include("ragdollposer/shared/quaternion.lua")

local VECTOR_ONE = Vector(1, 1, 1)

local dxLevel = render.GetDXLevel()
local dx11 = dxLevel >= 110 and dxLevel <= 114
local dx12 = dxLevel >= 120

-- DiscMaterial shaders come from legacy Ragdoll Mover. These should go inside `disc.lua`
local discMaterial = Material(dx11 and "ragdollposer/disc_dx11" or "ragdollposer/disc")
local discMaterialPartial = Material(dx11 and "ragdollposer/disc_partial_dx11" or "ragdollposer/disc_partial")

local scaleMultiplier = 1.5

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
		verts[i] = LocalToWorld(point * scale * scaleMultiplier, angle_zero, pos, normal:Angle())
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
	local hitPos = util.IntersectRayWithPlane(eyepos, direction * 16384, props.finalPos, self._axis)
	local distSqr = hitPos and hitPos:DistToSqr(props.finalPos) or -1
	local halfScale = (self._facesUs and 0.625 or 0.5) * props.scale

	local isValid = distSqr < (halfScale * 1.0 * scaleMultiplier * scaleMultiplier) ^ 2
		and distSqr > (halfScale * 0.9 * scaleMultiplier * scaleMultiplier) ^ 2
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
	local eyePos, eyeVec, eyeAng = RagdollPoser.View:GetView()

	local mat = not self._facesUs and props.partial and discMaterialPartial or discMaterial
	local discScale = 1 * scaleMultiplier
	if self._facesUs then
		local forward = -eyeAng:Forward()
		self._axis = forward
		self._direction = forward
		discScale = 1.25 * scaleMultiplier
	end

	drawQuad(mat, color, props.finalPos, self._axis, discScale * props.scale, props.width)
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
---@param initials table
---@return any
function disc:PreTransform(direction, initials)
	return direction
end

-- Define it here and modify the angle axis, so we don't have to create a quaternion every frame
local rotationQuaternion = quaternion.new(1)

local sharedDeltaProps = {
	Vector(),
	Vector(),
	Vector(),
}

local mirrorMatrix = Matrix()
mirrorMatrix:Identity()

function disc:ProcessDelta(start, endPos, props, mirrorAxis, eyeDelta)
	local eyePos, eyeVec, eyeAng = RagdollPoser.View:GetView()
	local startHit = (util.IntersectRayWithPlane(eyePos, start * 16384, props.finalPos, self._axis) or start)
		- props.finalPos
	local endHit = (util.IntersectRayWithPlane(eyePos, endPos * 16384, props.finalPos, self._axis) or endPos)
		- props.finalPos
		+ eyeDelta

	local mirrorNormal = vector_origin
	if mirrorAxis == 0 then
		mirrorNormal = eyeAng:Right()
	elseif mirrorAxis == 1 then
		mirrorNormal = eyeAng:Up()
	end
	if mirrorAxis >= 0 then
		startHit = startHit - 2 * mirrorNormal:Dot(startHit) * mirrorNormal
		endHit = endHit - 2 * mirrorNormal:Dot(endHit) * mirrorNormal
	end

	startHit:Normalize()
	endHit:Normalize()

	sharedDeltaProps[1]:Set(endHit)
	sharedDeltaProps[1]:Sub(startHit)
	sharedDeltaProps[2]:Set(startHit)
	sharedDeltaProps[3]:Set(endHit)

	return sharedDeltaProps
end

function disc:ProcessDeltaUI(start, endPos, props, mirrorAxis, delta)
	local eyePos, eyeVec, eyeAng = RagdollPoser.View:GetView()
	local side = self._axis:Angle():Right()
	local up = self._axis:Angle():Up()
	local scale = props.scale
	local startHit = props.finalPos + side * scale
	local endHit = props.finalPos + (side + up * delta):GetNormalized() * scale

	print(endHit:GetNormalized():Dot(startHit:GetNormalized()))

	local mirrorNormal = vector_origin
	if mirrorAxis == 0 then
		mirrorNormal = eyeAng:Right()
	elseif mirrorAxis == 1 then
		mirrorNormal = eyeAng:Up()
	end
	if mirrorAxis >= 0 then
		startHit = startHit - 2 * mirrorNormal:Dot(startHit) * mirrorNormal
		endHit = endHit - 2 * mirrorNormal:Dot(endHit) * mirrorNormal
	end

	startHit:Normalize()
	endHit:Normalize()

	sharedDeltaProps[1]:Set(endHit)
	sharedDeltaProps[1]:Sub(startHit)
	sharedDeltaProps[2]:Set(startHit)
	sharedDeltaProps[3]:Set(endHit)

	return sharedDeltaProps
end

local scaleFreeTransform = Matrix()
scaleFreeTransform:Identity()

---@param directions Vector[]
---@param deltaProps DeltaProps
---@param transform VMatrix
---@param accumulations number[]
---@param props GizmoProps
function disc:Transform(directions, deltaProps, transform, accumulations, initials, props)
	local startHit, endHit = deltaProps[2], deltaProps[3]

	local direction = directions[1]
	local accumulationIndex = 1

	local qi = quaternion.fromAngle(transform:GetAngles())
	local axis = direction
	local angle = math.atan2((startHit:Cross(endHit)):Dot(axis), startHit:Dot(endHit))
	local degrees = math.deg(angle)
	local newRot = accumulations[accumulationIndex] + degrees
	accumulations[accumulationIndex] = newRot
	rotationQuaternion:SetAngleAxis(degrees, axis)
	rotationQuaternion:Mul(qi)
	debugoverlay.Line(
		transform:GetTranslation(),
		transform:GetTranslation() + rotationQuaternion.__axis * 10,
		0.2,
		nil,
		true
	)
	debugoverlay.Axis(transform:GetTranslation(), rotationQuaternion:Angle(), 10, 0.2, true)

	local initialScale = initials[1]
	if not initialScale then
		initialScale = transform:GetScale()
		initials[1] = initialScale
	end

	scaleFreeTransform:Set(transform)
	scaleFreeTransform:SetScale(VECTOR_ONE)

	if props.relativerotate then
		local ang = rotationQuaternion:Angle()
		local offsetPos = WorldToLocal(props.pos, angle_zero, props.finalPos, props.ang)
		local pos = LocalToWorld(offsetPos, ang, props.finalPos, ang)
		scaleFreeTransform:SetTranslation(pos)
		scaleFreeTransform:SetAngles(ang)
	else
		scaleFreeTransform:SetAngles(rotationQuaternion:Angle())
	end

	transform:Set(scaleFreeTransform)
	transform:SetScale(initialScale)
	return transform
end

---Do all the child bones offset
function disc:PostTransform(transform, locals, parents, output)
	local worldMatrix = {}
	local worldMatrixCount = 0
	for i, localMatrixInfo in ipairs(locals) do
		local childBone = localMatrixInfo[1]
		local localChildMatrix = localMatrixInfo[2]
		local parentBone = parents[childBone]
		if not worldMatrix[parentBone] then
			if worldMatrixCount == 0 then
				worldMatrix[parentBone] = transform
				worldMatrixCount = 1
			end
		end

		if localChildMatrix then
			local newMatrix = worldMatrix[parentBone] * localChildMatrix
			output[childBone] = newMatrix
			worldMatrix[childBone] = newMatrix
			worldMatrixCount = worldMatrixCount + 1
		end
	end
end

function disc:GetDirection()
	if self._facesUs then
		local eyePos, eyeVec, eyeAng = RagdollPoser.View:GetView()
		return -eyeAng:Forward()
	end
	return self._axis
end

---@param v Vector? axis of rotation
---@return GizmoDisc disc
local function initialize(v)
	local base = disc:Init()
	---@cast base GizmoDisc

	-- If we don't define a rotation axis, then have it face us all the time
	if v then
		base._direction = v
		base._axis = v
		base._color = v:ToColor()
		-- RagdollPoser.Log("Set rotation axis to ", v)
	else
		base._facesUs = true
		local eyePos, eyeVec, eyeAng = RagdollPoser.View:GetView()
		base._direction = -eyeAng:Forward()
		base._axis = -eyeAng:Forward()
		base._color = Color(192, 192, 192, 255)
	end

	return base
end

if RagdollPoser.Gizmo and not RagdollPoser.Gizmo:IsRefreshing() then
	hook.Run("RagdollPoser_Gizmo_Refresh", "disc")
end

return initialize
