---@module "gizmos/base"
---@class GizmoBall: GizmoBase
---@field _color Color
---@field _selectedColor Color
---@field xDelta integer
---@field yDelta integer
local ball = include("base.lua")
---@module "quaternion"
local quaternion = include("ragdollposer/shared/quaternion.lua")

local scaleMultiplier = 1.5
local BALL_SCALE = 0.6

---@param eyepos Vector
---@param direction Vector
---@param props GizmoProps
function ball:Intersect(eyepos, direction, props)
	if not props.drawsphere then
		return
	end

	local hit1, hit2 = util.IntersectRayWithSphere(
		eyepos,
		direction * 16384,
		props.finalPos,
		props.scale * BALL_SCALE * scaleMultiplier
	)

	if hit1 then
		-- debugoverlay.Sphere(eyepos + direction * hit1 * 16384, 2, 0.2, self._selectedColor, true)
		return eyepos + direction * hit1 * 16384
	end
end

---@param props GizmoProps
---@param selected boolean
function ball:Draw(props, selected)
	if not props.drawsphere then
		return
	end

	local color = selected and self._selectedColor or self._color

	render.SetColorMaterialIgnoreZ()
	render.DrawSphere(props.finalPos, props.scale * BALL_SCALE * scaleMultiplier, 12, 12, color)
end

---Convert directions to quaternions
---@param direction Vector
---@param initials VMatrix[]
---@return any
function ball:PreTransform(direction, initials)
	local x, y = input.GetCursorPos()
	self.xi, self.yi = x, y
	self.xDelta, self.yDelta = 0, 0

	return Vector()
end

function ball:ProcessDelta(start, endPos, props, mirrorAxis, eyeDelta)
	local x, y = input.GetCursorPos()
	local eyePos, eyeVec, eyeAng = RagdollPoser.View:GetView()
	local eyedist = eyePos:Distance(props.finalPos) / 60
	local forward = eyeAng:Forward()
	local right = eyeAng:Right()

	self.xDelta = self.xDelta + RagdollPoser.Input.xMove + right:Dot(eyeDelta) * props.scale / eyedist
	self.yDelta = self.yDelta + RagdollPoser.Input.yMove + forward:Dot(eyeDelta) * props.scale / eyedist

	local xSign, ySign = 1, 1
	if mirrorAxis == 0 then
		xSign = -xSign
	elseif mirrorAxis == 1 then
		ySign = -ySign
	end

	self.dx = xSign * ((x - self.xi) * 18 + self.xDelta * 4)
	self.dy = ySign * ((y - self.yi) * 18 + self.yDelta * 4)

	return { eyeDelta, start, endPos }
end

-- Define it here and modify the angle axis, so we don't have to create a quaternion every frame
local rotationQuaternion = quaternion.new(1)

local min, max = Vector(-1, -1, -1) * 5, Vector(1, 1, 1) * 5

---@param directions Quaternion[]
---@param deltaProps DeltaProps
---@param transforms VMatrix[]
function ball:Transform(directions, deltaProps, transforms, accumulations, initials, props)
	local eyePos, eyeVec, eyeAng = RagdollPoser.View:GetView()
	local left = -eyeAng:Right()
	local up = eyeAng:Up()

	local dx, dy = self.dx, self.dy

	-- The closer we are to the gizmo, the more precise the movement should be
	local eyedist = eyePos:Distance(props.finalPos) / 60
	local distance = math.sqrt(dx ^ 2 + dy ^ 2)
	local scale = props.scale
	-- The smaller the ball, the more rotation we give
	local angle = distance / scale * eyedist

	local axis = -left * dy + up * dx
	axis:Normalize()

	rotationQuaternion:SetAngleAxis(angle, axis)

	debugoverlay.BoxAngles(props.finalPos, min, max, rotationQuaternion:Angle(), 0.2)

	for i, matrix in ipairs(transforms) do
		local quat = initials[i]

		if not quat then
			local qi = quaternion.fromAngle(matrix:GetAngles())
			local w, x, y, z = qi:Unpack()
			quat = quaternion.new(w, x, y, z)
			initials[i] = quat
		end

		local accumulationIndex = accumulations[i] and i or 1

		accumulations[accumulationIndex] = accumulations[accumulationIndex] + angle

		rotationQuaternion:Mul(quat)

		matrix:SetAngles(rotationQuaternion:Angle())
	end
end

function ball:PostTransform(transforms, locals, indices, parents)
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

function ball:FinishTransform() end

function ball:GetDirection()
	return Vector()
end

---@return GizmoBall ball
local function initialize()
	local base = ball:Init()

	base._color = Color(255, 255, 0, 24)
	base._selectedColor = Color(255, 255, 0, 48)
	base.xDelta = 0
	base.yDelta = 0
	base.xi = 0
	base.yi = 0
	base.dx = 0
	base.dy = 0
	---@cast base GizmoBall
	return base
end

if RagdollPoser.Gizmo and not RagdollPoser.Gizmo:IsRefreshing() then
	hook.Run("RagdollPoser_Gizmo_Refresh", "ball")
end

return initialize
