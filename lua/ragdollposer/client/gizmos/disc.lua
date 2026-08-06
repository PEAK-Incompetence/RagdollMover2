---@module "base"
---@class GizmoDisc: GizmoBase
---@field _axis Vector
local disc = include("base.lua")
---@module "quaternion"
local quaternion = include("ragdollposer/shared/quaternion.lua")

local RED = Color(255, 0, 0)
local GREEN = Color(0, 255, 0)
local BLUE = Color(0, 0, 255)

-- DiscMaterial shaders come from legacy Ragdoll Mover. These should go inside `disc.lua`
local DiscMaterial = Material("ragdollposer/disc")
local DiscMaterialPartial = Material("ragdollposer/disc_partial")

local dummy_model = ClientsideModel("models/shadertest/vertexlit.mdl")
dummy_model:SetModelScale(0) -- make it invisible
local function sendVertexMetadata(x, y, z)
	render.SuppressEngineLighting(true)

	render.SetModelLighting(0, x, y, z)

	dummy_model:DrawModel()

	render.SuppressEngineLighting(false)
end

local verts = {}

---@param mat IMaterial
---@param color Color
---@param pos Vector
---@param normal Vector
---@param width number
local function drawQuad(linepos, mat, color, pos, normal, scale, width)
	for i, point in ipairs(linepos) do
		verts[i] = LocalToWorld(point * scale, angle_zero, pos, normal:Angle())
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
	render.DrawQuad(verts[1], verts[2], verts[3], verts[4], color)
end

---@param pos Vector
---@param ang Angle
---@param orientation GizmoOrientation
function disc:Draw(pos, ang, orientation) end

---Convert directions to quaternions
function disc:PreTransform() end

---@param directions Quaternion[]
---@param delta number
---@param transforms VMatrix[]
function disc:Transform(directions, delta, transforms)
	for i, matrix in ipairs(transforms) do
		local qi = quaternion.fromAngle(matrix:GetAngles())
		directions[i]:SetAngleAxis(delta, directions[i].__axis)
		qi:Mul(directions[i])

		matrix:SetAngles(qi:Angle())
	end
end

---@param axis Vector
function disc:SetRotationAxis(axis) end

---@param v Vector? axis of rotation
---@return GizmoDisc
local function initialize(v)
	local base = disc:Init()
	---@cast base GizmoDisc

	-- If we don't define a rotation axis, then have it face us all the time
	if v then
		base:SetRotationAxis(v)
		RagdollPoser.Log("Set rotation axis to ", v)
	end

	return base
end

return initialize
