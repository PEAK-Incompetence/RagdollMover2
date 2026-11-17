-- Instead of drawing an arrow from vertices, let's draw a quad
-- oriented along its side while always facing us (beam). We'll use a
-- erode / dilate shader algorithm to shrink and grow the arrow.

local VECTOR_ONE = Vector(1, 1, 1)

---@module "gizmo/base"
---@class GizmoArrow: GizmoBase
---@field _direction Vector
---@field _axis Vector
---@field _color Color
local arrow = include("base.lua")

local dxLevel = render.GetDXLevel()
local dx11 = dxLevel >= 110 and dxLevel <= 114

local arrowMaterial = Material(dx11 and "ragdollposer/arrow_dx11" or "ragdollposer/arrow")
local texture = arrowMaterial:GetTexture("$basetexture")
local width, height = texture:Width(), texture:Height()

local tempMin, tempMax = Vector(-1, -1, -1), Vector(1, 1, 1)
local centerPadding = 0.05

local developer = GetConVar("developer")

---@param eyepos Vector
---@param direction Vector
---@param props GizmoProps
---@return Vector? intersectionPoint
function arrow:Intersect(eyepos, direction, props)
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
function arrow:Draw(props, selected)
	local mat = arrowMaterial
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
	if RagdollPoser.Gizmo:IsMoving() then
		render.DrawLine(props.finalPos - self._axis * 1000, props.finalPos + self._axis * 1000, color_white, true)
	end
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

function arrow:ProcessDelta(start, endPos, props, mirrorAxis, eyeDelta)
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

function arrow:ProcessDeltaUI(start, endPos, props, mirrorAxis, delta)
	local eyePos, eyeVec, eyeAng = RagdollPoser.View:GetView()
	local forward = eyeAng:Forward()
	local back = -forward

	sharedDeltaProps[1]:Set(self._axis * delta)

	if mirrorAxis >= 0 then
		local length = sharedDeltaProps[1]:Length()
		local vector = sharedDeltaProps[1]:Angle()
		vector:RotateAroundAxis(eyeAng:Up(), 180)
		sharedDeltaProps[1]:Set(vector:Forward())
		sharedDeltaProps[1]:Mul(length)
	end

	sharedDeltaProps[2]:Set(props.finalPos)
	sharedDeltaProps[3]:Set(props.finalPos + sharedDeltaProps[1])

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

-- Try to prevent some matrix creations to avoid gc cycles
local scaleFreeTransform = Matrix()
scaleFreeTransform:Identity()

---@param directions Vector[]
---@param deltaProps DeltaProps
---@param transform VMatrix
---@param accumulations number[]
---@param props GizmoProps
function arrow:Transform(directions, deltaProps, transform, accumulations, initials, props)
	local delta = deltaProps[1]
	local vector = directions[1]

	-- Project the driven axis onto the screen
	-- Why do this? It allows the translate to follow the mouse closely, even
	-- when the axis we're manipulating closely aligngs with our view
	local _, eyeVec, _ = RagdollPoser.View:GetView()
	local screenVector = self:ProjectUnitToPlane(vector, eyeVec)

	local length = screenVector:Dot(delta)
	accumulations[1] = accumulations[1] + length

	local lastSnap = initials[1]
	if not lastSnap then
		lastSnap = 0
		initials[1] = lastSnap
	end

	if props.snap then
		local snap = math.Truncate(accumulations[1] / props.snapValue) * props.snapValue
		length = snap - lastSnap
		initials[1] = snap
	end
	local movement = vector * length

	scaleFreeTransform:Set(transform)
	scaleFreeTransform:SetScale(VECTOR_ONE)
	local scale = transform:GetScale()
	movement:Rotate(scaleFreeTransform:GetInverse():GetAngles())

	transform:Translate(movement / scale)

	debugoverlay.Axis(transform:GetTranslation(), transform:GetAngles(), 1, 0.1, true)
	debugoverlay.Line(transform:GetTranslation(), transform:GetTranslation() + vector * 10, 0.5)
	return transform
end

function arrow:PostTransform(transform, locals, parents, output)
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

if RagdollPoser.Gizmo and not RagdollPoser.Gizmo:IsRefreshing() then
	hook.Run("RagdollPoser_Gizmo_Refresh", "arrow")
end

return initialize
