---Handle rendering and collision of gizmo

---@class RagdollPoser.Gizmo
local MGR = {
	_pos = Vector(),
	_ang = Angle(),
	_scale = 30,
	_width = 0.25,
	_offset = Vector(),

	_linePositions = {
		Vector(0, 1, 1),
		Vector(0, -1, 1),
		Vector(0, -1, -1),
		Vector(0, 1, -1),
	},

	_moving = false,

	_entity = NULL,
	_bone = -1,
}

local currentMatrix = Matrix()

---@param entity Entity
---@param bone integer
---@param offset Vector?
function MGR:Select(entity, bone, offset)
	print(entity, bone)

	entity:CopyBoneMatrix(bone, currentMatrix)
	self._pos = currentMatrix:GetTranslation()
	self._ang = currentMatrix:GetAngles()
	self._left = -self._ang:Right()

	self._entity = entity
	self._bone = bone
end

function MGR:IsMoving()
	return self._moving
end

---@param pos Vector
function MGR:SetPosition(pos)
	self._pos = pos
	hook.Run("RagdollPoser_GizmoPositionSet", pos)
end

RagdollPoser.Networking.SendSubPose = RagdollPoser.Networking.DefineSender("SendSubPose")
RagdollPoser.Networking.SendSubPose2 = RagdollPoser.Networking.DefineSender("SendSubPose2")

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

local showBones = false

local mat = Matrix()

local lastMove = false
hook.Remove("CreateMove", "RagdollPoser_GizmoMouseInput")
hook.Add("CreateMove", "RagdollPoser_GizmoMouseInput", function(cmd)
	local pl = LocalPlayer()
	local weap = pl:GetActiveWeapon()
	local tool = pl:GetTool()
	local equipped = IsValid(weap) and weap:GetClass() == "gmod_tool" and tool and tool:GetMode() == RagdollPoser.Mode

	MGR._moving = cmd:KeyDown(IN_ATTACK)

	if equipped then
		if lastMove ~= MGR._moving then
			if lastMove and IsValid(RagdollPoser.Gizmo._entity) then
				RagdollPoser.Networking.SendSubPose()
				local matrices = RagdollPoser.Entity.GetMatrices(RagdollPoser.Gizmo._entity)
				net.WriteEntity(RagdollPoser.Gizmo._entity)
				net.WriteUInt(#matrices, 8)
				for i = 1, #matrices do
					net.WriteMatrix(matrices[i])
				end
				net.SendToServer()
			end
		end
	end

	lastMove = MGR._moving
end)

-- Make sure you are in the 2D rendering context
function MGR:DrawBones()
	if LocalPlayer():KeyPressed(IN_WALK) then
		-- print(showBones)
		showBones = not showBones
	end

	if showBones then
		local ents = RagdollPoser.Entity.GetClientEntities()
		for _, ent in ipairs(ents) do
			if not IsValid(ent) then
				continue
			end

			for b = 0, ent:GetBoneCount() - 1 do
				local name = ent:GetBoneName(b)
				-- TODO: Get invisible bones (e.g. weapon_bone)
				if name == "__INVALIDBONE__" then
					continue
				end
				-- print(b, name)

				ent:CopyBoneMatrix(b, mat)
				local p = mat:GetTranslation()
				local data = p:ToScreen()
				if not data.visible then
					continue
				end
				local x, y = data.x, data.y

				-- TODO: Categorize based on bone type
				surface.DrawCircle(x, y, 2, GREEN)
			end
		end
	end
end

-- Make sure you are in the 3D rendering context
function MGR:Draw()
	local mat = DiscMaterial

	local linepos = self._linePositions

	-- print(self._pos)
	if self._pos then
		render.SetMaterial(mat)
		render.CullMode(MATERIAL_CULLMODE_NONE)
		drawQuad(linepos, mat, RED, self._pos, self._ang:Forward(), self._scale, self._width)
		drawQuad(linepos, mat, GREEN, self._pos, -self._ang:Right(), self._scale, self._width)
		drawQuad(linepos, mat, BLUE, self._pos, self._ang:Up(), self._scale, self._width)
		render.CullMode(MATERIAL_CULLMODE_CCW)
	end
end

RagdollPoser.Gizmo = MGR
