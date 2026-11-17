-- Instead of drawing an arrow from vertices, let's draw a quad
-- oriented along its side while always facing us (beam). We'll use a
-- erode / dilate shader algorithm to shrink and grow the arrow.

---@module "gizmo/base"
---@class GizmoSideScale: GizmoBase
---@field _axis Vector
---@field _direction Vector
---@field _color Color
---@field forward Vector
---@field up Vector
---@field right Vector
---@field deltaNormal Vector
local sidescale = include("base.lua")

local squareLength = 0.15
local offset = 0.3
local YELLOW = Color(255, 255, 0)

local developer = GetConVar("developer")

local math_abs = math.abs
---@param vector Vector
local function makePositive(vector)
	vector:SetUnpacked(math_abs(vector.x), math_abs(vector.y), math_abs(vector.z))
end

---@param props GizmoProps
---@param selected boolean
function sidescale:Draw(props, selected)
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

function sidescale:Intersect(eyepos, direction, props)
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

function sidescale:UpdateOrientation(orientation, props)
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

function sidescale:GetDirection()
	local axes = {}
	for _, axis in ipairs({ self.forward, self.right, self.up }) do
		if axis:LengthSqr() > 0 then
			axes[#axes + 1] = axis
		end
	end
	return axes
end

function sidescale:PreTransform(directions)
	self.start = nil
	self.mirrorStart = nil
	local eyePos, eyeVec, eyeAng = RagdollPoser.View:GetView()
	self.deltaNormal = -eyeAng:Forward()
	return directions
end

local sharedDeltaProps = {
	Vector(),
	Vector(),
	Vector(),
}

function sidescale:ProcessDelta(start, endPos, props, mirrorAxis, eyeDelta)
	local eyePos, eyeVec, eyeAng = RagdollPoser.View:GetView()
	local forward = -eyeAng:Forward()
	if not self.start then
		self.start = (util.IntersectRayWithPlane(eyePos, start * 16384, props.finalPos, self.deltaNormal) or start)
	end
	if not self.mirrorStart and mirrorAxis >= 0 then
		self.mirrorStart = (
			util.IntersectRayWithPlane(eyePos, start * 16384, props.finalPos, self.deltaNormal) or start
		)
	end

	local startHit = mirrorAxis >= 0 and self.mirrorStart or self.start
	local endHit = (util.IntersectRayWithPlane(eyePos, endPos * 16384, props.finalPos, self.deltaNormal) or endPos)

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

local ZERO_MATRIX = Matrix()
local IDENTITY_MATRIX = Matrix()
IDENTITY_MATRIX:Identity()

local SCALE_MATRIX = Matrix()
local AXIS_SCALE_MATRIX = Matrix()
local T_INV = Matrix()
local R = Matrix()
local S = Matrix()
local T = Matrix()
local R_INV = Matrix()

local SCALE_VECTOR = Vector(1, 1, 1)
local VECTOR_ONE = Vector(1, 1, 1)
local COLOR = Color(255, 0, 0)

local function setAxisScale(axis, factor, bonePos, result)
	T_INV:Set(ZERO_MATRIX)
	R:Set(ZERO_MATRIX)
	S:Set(ZERO_MATRIX)
	T:Set(ZERO_MATRIX)
	R_INV:Set(ZERO_MATRIX)

	T_INV:SetTranslation(-bonePos)
	R:SetAngles(axis:Angle())
	SCALE_VECTOR:SetUnpacked(factor, 1, 1)
	S:Scale(SCALE_VECTOR)
	T:SetTranslation(bonePos)
	R_INV:Set(R:GetInverseTR())

	R_INV:Mul(T_INV)
	S:Mul(R_INV)
	R:Mul(S)
	T:Mul(R)
	result:Set(T)
end

---@param directions Vector[]
---@param deltaProps DeltaProps
---@param transform VMatrix
---@param accumulations number[]
---@param initials table
---@param props GizmoProps
function sidescale:Transform(directions, deltaProps, transform, accumulations, initials, props)
	local delta = deltaProps[1]
	local axes = self:GetDirection()
	local axisA, axisB = axes[1], axes[2]
	if not axisA or not axisB then
		return
	end

	local initialTransformTable = initials[1]
	if not initialTransformTable then
		local rotationMatrix = transform * IDENTITY_MATRIX
		rotationMatrix:SetTranslation(vector_origin)
		rotationMatrix:SetScale(VECTOR_ONE)
		initialTransformTable = { transform * IDENTITY_MATRIX, transform:GetScale(), rotationMatrix, 0, 0 }
		initials[1] = initialTransformTable
	end

	local bonePos = initialTransformTable[1]:GetTranslation()
	local lengthA = axisA:Dot(delta) * 0.1
	local lengthB = axisB:Dot(delta) * 0.1

	accumulations[1] = accumulations[1] + lengthA
	accumulations[2] = accumulations[2] + lengthB

	-- FIXME: Scale snapping seems to oscillate weirdly
	if props.snap then
		local snapA = math.Truncate(accumulations[1] / props.snapValue) * props.snapValue
		local snapB = math.Truncate(accumulations[2] / props.snapValue) * props.snapValue
		lengthA = (snapA - initialTransformTable[#initialTransformTable - 1]) * 0.1
		lengthB = (snapB - initialTransformTable[#initialTransformTable]) * 0.1
		initialTransformTable[#initialTransformTable - 1] = snapA
		initialTransformTable[#initialTransformTable] = snapB
	end

	setAxisScale(axisA, 1 + lengthA, bonePos, SCALE_MATRIX)
	setAxisScale(axisB, 1 + lengthB, bonePos, AXIS_SCALE_MATRIX)
	SCALE_MATRIX:Set(AXIS_SCALE_MATRIX * SCALE_MATRIX)

	sidescale.SetShearFreeScale(transform, initialTransformTable[1], SCALE_MATRIX)
	debugoverlay.Axis(transform:GetTranslation(), transform:GetAngles(), 1, 0.1, true)
	debugoverlay.Line(transform:GetTranslation(), transform:GetTranslation() + axisA * 10, 0.5)
	debugoverlay.Line(transform:GetTranslation(), transform:GetTranslation() + axisB * 10, 0.5, COLOR, true)

	return transform
end

function sidescale:PostTransform(transform, locals, parents, output)
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
			sidescale.SetShearFreeScale(cleanChildMatrix, newChildMatrix, SCALE_MATRIX)

			output[childBone] = cleanChildMatrix
			worldMatrix[childBone] = newChildMatrix
		end
	end
end

---@param direction Vector Vector(1, 0, 0) = XY, Vector(0, 1, 0) = YZ, Vector(0, 0, 1) = ZX
---@return GizmoSideScale sidescale
local function initialize(direction)
	local base = sidescale:Init()
	---@cast base GizmoSideScale
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
	hook.Run("RagdollPoser_Gizmo_Refresh", "sidescale")
end

return initialize
