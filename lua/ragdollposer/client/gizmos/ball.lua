---@module "base"
---@class GizmoBall: GizmoBase
local ball = include("base.lua")
---@module "quaternion"
local quaternion = include("ragdollposer/shared/quaternion.lua")

---@param pos Vector
---@param ang Angle
---@param orientation GizmoOrientation
function ball:Draw(pos, ang, orientation) end

---Convert directions to quaternions
function ball:PreTransform() end

---@param directions Quaternion[]
---@param delta number
---@param transforms VMatrix[]
function ball:Transform(directions, delta, transforms)
	for i, matrix in ipairs(transforms) do
		local qi = quaternion.fromAngle(matrix:GetAngles())
		directions[i]:SetAngleAxis(delta, directions[i].__axis)
		qi:Mul(directions[i])

		matrix:SetAngles(qi:Angle())
	end
end

---@return GizmoBall
local function initialize()
	local base = ball:Init()
	---@cast base GizmoBall
	return base
end

return initialize
