--- "Omniposition" gizmo: move something relative to your view plane

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

---@param props GizmoProps
---@param selected boolean
function omni:Draw(props, selected)
	local color = selected and YELLOW or self._color

	render.SetColorMaterialIgnoreZ()
	-- literally a square breh
	render.DrawSprite(props.finalPos, props.scale * scaleMultiplier, props.scale * scaleMultiplier, color)
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

---@param v Vector Vector to project
---@param n Vector Normal vector of plane
---@return Vector projection Projection of vector on the plane
local function projectVectorToPlane(v, n)
	local projection = v - v:Dot(n) / n:LengthSqr() * n
	return projection
end

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
	sharedDeltaProps[1]:Add(projectVectorToPlane(eyeDelta, back))

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

---@param directions Vector[]
---@param deltaProps DeltaProps
---@param transform VMatrix
---@param accumulations number[]
function omni:Transform(directions, deltaProps, transform, accumulations, initials, props)
	local delta = deltaProps[1]
	local vector = directions[1]
	local accumulationIndex = 1

	local length = delta:Length()
	accumulations[accumulationIndex] = accumulations[accumulationIndex] + length
	local movement = delta * 1
	movement:Rotate(transform:GetInverse():GetAngles())
	transform:Translate(movement)
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
