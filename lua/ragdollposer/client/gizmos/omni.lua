--- "Omniposition" gizmo: move something relative to your view plane

local VECTOR_ONE = RagdollPoser.Constants.VECTOR_ONE

---@module "gizmo/base"
---@class GizmoOmni: GizmoBase
---@field _color Color
---@field eyePos Vector
---@field eyeAng Angle
---@field eyeVec Vector
local omni = include("base.lua")

local dxLevel = render.GetDXLevel()
local dx11 = dxLevel >= 110 and dxLevel <= 114

local tempMin, tempMax = Vector(-1, -1, -1), Vector(1, 1, 1)
local centerPadding = 0.05

local developer = GetConVar("developer")

local scaleMultiplier = 0.05

---@param eyepos Vector
---@param direction Vector
---@param props GizmoProps
---@return Vector? intersectionPoint
function omni:Intersect(eyepos, direction, props)
	render.SetColorMaterialIgnoreZ()
	local scale = props.scale

	local angle = props.orientation == RagdollPoser.Gizmo.Orientation.Local and props.ang or angle_zero
	if developer:GetBool() then
		render.DrawBox(props.finalPos, angle, tempMin * scale * scaleMultiplier, tempMax * scale * scaleMultiplier)
	end
	local result = util.IntersectRayWithOBB(
		eyepos,
		direction * 16384,
		props.finalPos,
		angle,
		tempMin * scale * scaleMultiplier,
		tempMax * scale * scaleMultiplier
	)
	if result then
		debugoverlay.Box(result, tempMin, tempMax, 0.1)
	end
	return result
end

local YELLOW = Color(255, 255, 0)

local dxLevel = render.GetDXLevel()
local dx11 = dxLevel >= 110 and dxLevel <= 114
local dx12 = dxLevel >= 120

local gridMaterial = Material(dx11 and "ragdollposer/grid_dx11" or "ragdollposer/grid")

-- Avoid clones of this
-- TODO: move this to the gizmo object and do dependency injection
DUMMY_MODEL = DUMMY_MODEL or ClientsideModel("models/shadertest/vertexlit.mdl")
DUMMY_MODEL:SetModelScale(0) -- make it invisible
---@param gridSize number
---@param xOffset number
---@param yOffset number
local function sendVertexMetadata(gridSize, xOffset, yOffset)
	render.SuppressEngineLighting(true)

	render.SetModelLighting(0, gridSize, xOffset, yOffset)

	DUMMY_MODEL:DrawModel()

	render.SuppressEngineLighting(false)
end

---@param props GizmoProps
---@param selected boolean
function omni:Draw(props, selected)
	local color = selected and YELLOW or self._color

	local scale = props.scale
	render.SetColorMaterialIgnoreZ()
	-- literally a square breh
	render.DrawSprite(props.finalPos, scale * scaleMultiplier, scale * scaleMultiplier, color)
	if RagdollPoser.Gizmo:IsMoving() and props.snap and self.eyeVec then
		local gridSize = scale * 10
		sendVertexMetadata(gridSize / props.snapValue, gridSize * 0.267, gridSize * 0.267)
		gridMaterial:SetFloat("$c0_x", props.width * 0.5 / props.snapValue)
		gridMaterial:SetFloat("$c0_y", props.width * 0.5 / props.snapValue)
		render.SetMaterial(gridMaterial)
		render.DrawQuadEasy(props.finalPos, self.eyeVec, gridSize, gridSize, color, 0)
	end
end

---@param props GizmoProps
---@return Vector axis
function omni:GetDirection(props)
	return vector_origin
end

local sharedDeltaProps = {
	Vector(),
	Vector(),
	Vector(),
}

local mirrorMatrix = Matrix()
mirrorMatrix:Identity()

function omni:ProcessDelta(start, endPos, props, mirrorAxis, eyeDelta)
	local eyePos, eyeVec, eyeAng = self.eyePos, self.eyeVec, self.eyeAng
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
	sharedDeltaProps[1]:Add(self:ProjectVectorToPlane(eyeDelta, back))

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

function omni:PreTransform(v)
	local eyePos, eyeVec, eyeAng = RagdollPoser.View:GetView()

	self.eyePos = eyePos
	self.eyeVec = eyeVec
	self.eyeAng = eyeAng

	return v
end

function omni:UpdateOrientation(orientation, props) end

-- Try to prevent some matrix creations to avoid gc cycles
local scaleFreeTransform = Matrix()
scaleFreeTransform:Identity()

---@param directions Vector[]
---@param deltaProps DeltaProps
---@param transform VMatrix
---@param accumulations number[]
---@param props GizmoProps
function omni:Transform(directions, deltaProps, transform, accumulations, initials, props)
	local delta = deltaProps[1]
	local vector = directions[1]

	scaleFreeTransform:Set(transform)
	scaleFreeTransform:SetScale(VECTOR_ONE)

	local eyePos, eyeVec, eyeAng = self.eyePos, self.eyeVec, self.eyeAng

	local right = self.eyeAng:Right()
	local up = self.eyeAng:Up()
	local rightLength = right:Dot(delta)
	local upLength = up:Dot(delta)

	if props.precision then
		rightLength = rightLength * 0.5
		upLength = upLength * 0.5
	end

	accumulations[1] = accumulations[1] + rightLength
	accumulations[2] = accumulations[2] + upLength
	local lastSnap = initials[1]
	if not lastSnap then
		lastSnap = 0
		initials[1] = lastSnap
		initials[2] = lastSnap
	end

	if props.snap then
		local rightSnap = math.Truncate(accumulations[1] / props.snapValue) * props.snapValue
		local upSnap = math.Truncate(accumulations[2] / props.snapValue) * props.snapValue
		rightLength = rightSnap - initials[1]
		upLength = upSnap - initials[2]
		initials[1] = rightSnap
		initials[2] = upSnap
	end

	local trace = RagdollPoser.View:GetTrace()

	if props.attach and trace.HitPos then
		-- FIXME: After switching out of surface attach, bring the object back to the
		-- initial plane
		transform:SetTranslation(trace.HitPos)
	else
		local scale = transform:GetScale()
		local movement = right * rightLength + up * upLength
		movement:Rotate(scaleFreeTransform:GetInverse():GetAngles())

		transform:Translate(movement / scale)
	end
	debugoverlay.Axis(transform:GetTranslation(), transform:GetAngles(), 1, 0.1, true)
	debugoverlay.Line(transform:GetTranslation(), transform:GetTranslation() + delta * 10, 0.5)

	return transform
end

function omni:PostTransform(transform, locals, parents, output)
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

---@return GizmoOmni arrow
local function initialize()
	local base = omni:Init()
	---@cast base GizmoOmni

	-- TODO: Make the omni gizmo customizable by the player
	base._color = Color(255, 165, 0, 255)

	return base
end

if RagdollPoser.Gizmo and not RagdollPoser.Gizmo:IsRefreshing() then
	hook.Run("RagdollPoser_Gizmo_Refresh", "omni")
end

return initialize
