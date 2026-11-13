--- "Omniposition" gizmo: move something relative to your view plane

---@module "gizmo/base"
---@class GizmoOmni: GizmoBase
---@field _color Color
---@field eyePos Vector
---@field eyeAng Angle
---@field eyeVec Vector
local arrow = include("base.lua")

local dxLevel = render.GetDXLevel()
local dx11 = dxLevel >= 110 and dxLevel <= 114

local arrowMaterial = Material(dx11 and "ragdollposer/arrow_dx11" or "ragdollposer/arrow")
local texture = arrowMaterial:GetTexture("$basetexture")
local width, height = texture:Width(), texture:Height()

local tempMin, tempMax = Vector(-1, -1, -1), Vector(1, 1, 1)
local centerPadding = 0.05

local developer = GetConVar("developer")

local scaleMultiplier = 0.05

---@param eyepos Vector
---@param direction Vector
---@param props GizmoProps
---@return Vector? intersectionPoint
function arrow:Intersect(eyepos, direction, props)
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
function arrow:Draw(props, selected)
	local color = selected and YELLOW or self._color

	render.SetColorMaterialIgnoreZ()
	-- literally a square breh
	render.DrawSprite(props.finalPos, props.scale * scaleMultiplier, props.scale * scaleMultiplier, color)
end

---@param props GizmoProps
---@return Vector axis
function arrow:GetDirection(props)
	return vector_origin
end

local sharedDeltaProps = {
	Vector(),
	Vector(),
	Vector(),
}

local mirrorMatrix = Matrix()
mirrorMatrix:Identity()

function arrow:ProcessDelta(start, endPos, props, mirrorAxis, eyeDelta)
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

function arrow:PreTransform(v)
	local eyePos, eyeVec, eyeAng = RagdollPoser.View:GetView()

	self.eyePos = eyePos
	self.eyeVec = eyeVec
	self.eyeAng = eyeAng

	return v
end

function arrow:UpdateOrientation(orientation, props) end

---@param directions Vector[]
---@param deltaProps DeltaProps
---@param transforms VMatrix[]
---@param accumulations number[]
function arrow:Transform(directions, deltaProps, transforms, accumulations, initials, props)
	local delta = deltaProps[1]
	for i, matrix in ipairs(transforms) do
		local vector = directions[i] or directions[1]
		local accumulationIndex = accumulations[i] and i or 1

		local length = delta:Length()
		accumulations[accumulationIndex] = accumulations[accumulationIndex] + length
		local movement = delta * 1
		movement:Rotate(matrix:GetInverse():GetAngles())
		matrix:Translate(movement)
		debugoverlay.Axis(matrix:GetTranslation(), matrix:GetAngles(), 1, 0.1, true)
		debugoverlay.Line(matrix:GetTranslation(), matrix:GetTranslation() + delta * 10, 0.5)
	end
end

---@return GizmoOmni arrow
local function initialize()
	local base = arrow:Init()
	---@cast base GizmoOmni

	-- TODO: Make the omni gizmo customizable by the player
	base._color = Color(255, 165, 0, 255)

	return base
end

if RagdollPoser.Gizmo and not RagdollPoser.Gizmo:IsRefreshing() then
	hook.Run("RagdollPoser_Gizmo_Refresh", "omni")
end

return initialize
