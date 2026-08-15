---@module "base"
---@class GizmoBall: GizmoBase
---@field _color Color
---@field _selectedColor Color
local ball = include("base.lua")
---@module "quaternion"
local quaternion = include("ragdollposer/shared/quaternion.lua")

local BALL_SCALE = 0.40

function ball:Intersect(eyepos, direction, props)
	local hit1, hit2 = util.IntersectRayWithSphere(eyepos, direction * 16384, props.pos, props.scale * BALL_SCALE)

	if hit1 then
		-- debugoverlay.Sphere(eyepos + direction * hit1 * 16384, 2, 0.2, self._selectedColor, true)
		return eyepos + direction * hit1
	end
end

---@param props GizmoProps
---@param orientation GizmoOrientation
function ball:Draw(props, orientation, selected)
	local color = selected and self._selectedColor or self._color

	render.SetColorMaterialIgnoreZ()
	render.DrawSphere(props.pos, props.scale * BALL_SCALE, 12, 12, color)
end

---Convert directions to quaternions
---@param direction Vector
---@return any
function ball:PreTransform(direction)
	local x, y = input.GetCursorPos()
	self.xi, self.yi = x, y
	self.xDelta, self.yDelta = 0, 0
	return Vector()
end

-- Define it here and modify the angle axis, so we don't have to create a quaternion every frame
local rotationQuaternion = quaternion.new(1)

local min, max = Vector(-1, -1, -1) * 5, Vector(1, 1, 1) * 5

---@param directions Quaternion[]
---@param start Vector
---@param endPos Vector
---@param transforms VMatrix[]
function ball:Transform(directions, start, endPos, transforms, accumulations, props)
	local x, y = input.GetCursorPos()
	local scale = props.scale
	self.xDelta = self.xDelta + RagdollPoser.Input.xMove
	self.yDelta = self.yDelta + RagdollPoser.Input.yMove
	local eyeang = MainEyeAngles()
	local left = -eyeang:Right()
	local up = eyeang:Up()

	-- The closer we are to the gizmo, the more precise the movement should be
	local eyedist = MainEyePos():Distance(props.pos) / 60

	local dx = (x - self.xi) * 18 + self.xDelta * 4
	local dy = (y - self.yi) * 18 + self.yDelta * 4

	local distance = math.sqrt(dx ^ 2 + dy ^ 2)
	-- The smaller the ball, the more rotation we give
	local angle = distance / scale * eyedist

	local axis = -left * dy + up * dx
	axis:Normalize()

	rotationQuaternion:SetAngleAxis(angle, axis)

	debugoverlay.BoxAngles(props.pos, min, max, rotationQuaternion:Angle(), 0.2)

	-- Store initial orientation
	self.startQuaternions = self.startQuaternions or {}

	for i, matrix in ipairs(transforms) do
		local quat = self.startQuaternions[i]
		if not self.startQuaternions[i] then
			local qi = quaternion.fromAngle(matrix:GetAngles())
			local w, x, y, z = qi:Unpack()
			quat = quaternion.new(w, x, y, z)
			self.startQuaternions[i] = quat
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

function ball:FinishTransform()
	self.startQuaternions = {}
end

function ball:GetDirection()
	return Vector()
end

---@return GizmoBall
local function initialize()
	local base = ball:Init()

	base._color = Color(255, 255, 0, 24)
	base._selectedColor = Color(255, 255, 0, 48)
	---@cast base GizmoBall
	return base
end

return initialize
