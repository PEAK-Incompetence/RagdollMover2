---AI assisted in the math for the shearing/scaling.
---The other weird optimizations against garbage-collection were done by me
---It works well.

---@module "gizmo/base"
---@class GizmoScale: GizmoBase
---@field _direction Vector
---@field _axis Vector
---@field _color Color
local scale = include("base.lua")

local dxLevel = render.GetDXLevel()
local dx11 = dxLevel >= 110 and dxLevel <= 114

local scaleMaterial = Material(dx11 and "ragdollposer/scale_dx11" or "ragdollposer/scale")
local texture = scaleMaterial:GetTexture("$basetexture")
local width, height = texture:Width(), texture:Height()

local tempMin, tempMax = Vector(-1, -1, -1), Vector(1, 1, 1)
local centerPadding = 0.05

local developer = GetConVar("developer")

---@param eyepos Vector
---@param direction Vector
---@param props GizmoProps
---@return Vector? intersectionPoint
function scale:Intersect(eyepos, direction, props)
	render.SetColorMaterialIgnoreZ()
	local scale = props.scale

	local angle = props.orientation == RagdollPoser.Gizmo.Orientation.Local and props.ang or angle_zero
	if developer:GetBool() then
		render.DrawBox(
			props.finalPos,
			angle,
			tempMin + self._direction * scale * centerPadding,
			tempMax + self._direction * scale
		)
	end
	local result = util.IntersectRayWithOBB(
		eyepos,
		direction * 16384,
		props.finalPos,
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
function scale:Draw(props, selected)
	local mat = scaleMaterial
	local color = selected and YELLOW or self._color

	local endPos = props.finalPos + self._axis * props.scale

	mat:SetFloat("$c0_x", props.width)
	mat:SetFloat("$c0_y", color.r)
	mat:SetFloat("$c0_z", color.g)
	mat:SetFloat("$c0_w", color.b)
	mat:SetFloat("$c1_z", 1 / width)
	mat:SetFloat("$c1_w", 1 / height)
	render.SetMaterial(mat)

	render.DrawBeam(props.finalPos, endPos, props.scale * 0.5, 0, 1)
end

---@param props GizmoProps
---@return Vector axis
function scale:GetDirection(props)
	return self._axis
end

local sharedDeltaProps = {
	Vector(),
	Vector(),
	Vector(),
}

function scale:ProcessDelta(start, endPos, props, mirrorAxis, eyeDelta)
	local eyePos, eyeVec, eyeAng = RagdollPoser.View:GetView()
	local forward = -eyeAng:Forward()
	if not self.start then
		self.start = (util.IntersectRayWithPlane(eyePos, start * 16384, props.finalPos, forward) or start)
	end
	if not self.mirrorStart and mirrorAxis >= 0 then
		self.mirrorStart = (util.IntersectRayWithPlane(eyePos, start * 16384, props.finalPos, forward) or start)
	end

	local startHit = mirrorAxis >= 0 and self.mirrorStart or self.start
	local endHit = (util.IntersectRayWithPlane(eyePos, endPos * 16384, props.finalPos, forward) or endPos)

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

function scale:ProcessDeltaUI(start, endPos, props, mirrorAxis, delta)
	local eyePos, eyeVec, eyeAng = RagdollPoser.View:GetView()
	local forward = eyeAng:Forward()
	local back = -forward
	if not self.start then
		self.start = props.finalPos
	end
	if not self.mirrorStart and mirrorAxis >= 0 then
		self.mirrorStart = props.finalPos
	end
	if not self.deltaAccumulate then
		self.deltaAccumulate = 0
	end

	self.deltaAccumulate = self.deltaAccumulate + delta
	local startHit = mirrorAxis >= 0 and self.mirrorStart or self.start
	local endHit = startHit + self._axis * self.deltaAccumulate

	if mirrorAxis >= 0 then
		self.mirrorStart = endHit
	end
	self.start = endHit

	sharedDeltaProps[1]:Set(endHit)
	sharedDeltaProps[1]:Sub(startHit)

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

---Scales are with respect to the bone. If we want to make this scale
---in different ways (i.e. wrt world, wrt view), we need to calculate
---directions with respect to the parent
function scale:PreTransform(v)
	self.start = nil
	self.mirrorStart = nil
	self.deltaAccumulate = nil
	return v
end

function scale:UpdateOrientation(orientation, props)
	if orientation == RagdollPoser.Gizmo.Orientation.Local then
		self._axis = LocalToWorld(self._direction, angle_zero, vector_origin, props.ang)
	else
		self._axis:Set(self._direction)
	end
end

local ZERO_MATRIX = Matrix()

local IDENTITY_MATRIX = Matrix()
IDENTITY_MATRIX:Identity()

local SCALE_MATRIX = Matrix()
SCALE_MATRIX:Identity()

local T_INV = Matrix()
local R = Matrix()
local S = Matrix()
local T = Matrix()
local R_INV = Matrix()

local SCALE_VECTOR = Vector(1, 1, 1)

local VECTOR_ONE = RagdollPoser.Constants.VECTOR_ONE

local COLOR = Color(255, 0, 0)

---@param directions Vector[]
---@param deltaProps DeltaProps
---@param transform VMatrix
---@param accumulations number[]
---@param props GizmoProps
function scale:Transform(directions, deltaProps, transform, accumulations, initials, props)
	local delta = deltaProps[1]
	---@type {[1]: VMatrix, [2]: Vector, [3]: VMatrix}
	local initialTransformTable = initials[1]

	if not initialTransformTable then
		local rotationMatrix = transform * IDENTITY_MATRIX
		rotationMatrix:SetTranslation(vector_origin)
		rotationMatrix:SetScale(VECTOR_ONE)
		initialTransformTable = { transform * IDENTITY_MATRIX, transform:GetScale(), rotationMatrix, 0 }
		initials[1] = initialTransformTable
	end

	local vector = directions[1]

	local _, eyeVec, _ = RagdollPoser.View:GetView()
	local screenVector = self:ProjectUnitToPlane(vector, eyeVec)

	local length = screenVector:Dot(delta) * 0.1
	local initialTransform = initialTransformTable[1]
	if props.precision then
		length = length * 0.5
	end
	accumulations[1] = accumulations[1] + length

	-- FIXME: Scale snapping seems to oscillate weirdly
	if props.snap then
		local snap = math.Truncate(accumulations[1] / props.snapValue) * props.snapValue
		length = (snap - initialTransformTable[4]) * 0.1
		initialTransformTable[4] = snap
	end

	local scaleAngles = vector:Angle()
	local bonePos = initialTransform:GetTranslation()

	T_INV:Set(ZERO_MATRIX)
	R:Set(ZERO_MATRIX)
	S:Set(ZERO_MATRIX)
	T:Set(ZERO_MATRIX)
	R_INV:Set(ZERO_MATRIX)

	T_INV:SetTranslation(-bonePos)
	R:SetAngles(scaleAngles)
	SCALE_VECTOR.x = 1 + length
	S:Scale(SCALE_VECTOR)
	T:SetTranslation(bonePos)
	R_INV:Set(R:GetInverseTR())

	R_INV:Mul(T_INV)
	S:Mul(R_INV)
	R:Mul(S)
	T:Mul(R)
	SCALE_MATRIX:Set(T)

	scale.SetShearFreeScale(transform, initialTransform, SCALE_MATRIX)

	debugoverlay.Axis(transform:GetTranslation(), transform:GetAngles(), 1, 0.1, true)
	debugoverlay.Line(transform:GetTranslation(), transform:GetTranslation() + vector * 10, 0.5)
	debugoverlay.Line(
		transform:GetTranslation(),
		transform:GetTranslation() + SCALE_MATRIX:GetAngles():Forward() * 10,
		0.5,
		COLOR,
		true
	)

	return transform
end

---Move children by default. Otherwise, we do scaling just like the inflator
function scale:PostTransform(transform, locals, parents, output)
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
			local newChildMatrix = worldMatrix[parentBone] * localChildMatrix
			local cleanChildMatrix = Matrix()
			scale.SetShearFreeScale(cleanChildMatrix, newChildMatrix, SCALE_MATRIX)

			output[childBone] = cleanChildMatrix
			worldMatrix[childBone] = newChildMatrix
		end
	end
end

function scale:FinishTransform() end

---@param direction Vector
---@return GizmoScale scale
local function initialize(direction)
	local base = scale:Init()
	---@cast base GizmoScale

	if direction then
		base._direction = direction
		base._axis = direction
		base._color = direction:ToColor()
		RagdollPoser.Log("Set arrow direction to ", direction)
	end
	return base
end

if RagdollPoser.Gizmo and not RagdollPoser.Gizmo:IsRefreshing() then
	hook.Run("RagdollPoser_Gizmo_Refresh", "scale")
end

return initialize
