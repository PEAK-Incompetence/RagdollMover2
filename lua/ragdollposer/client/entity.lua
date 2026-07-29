---@type Entity[]
local Entities = {}
---@type Entity[]
local ClientEntities = {}

---@type {[Entity]: Entity}
local ClientToEntity = {}
---@type {[Entity]: Entity}
local EntityToClient = {}
---@type {[Entity]: boolean}
local ClientFirstSet = {}

---@type {[Entity]: VMatrix[]}
local EntityMatrices = {}
local EntityRenderBounds = {}

local MGR = {}

local static = CreateClientConVar(
	"ragdollposer_static",
	1,
	true,
	true,
	"If set to 1, client entities will not track their entities. This is useful if you don't want the ragdoll to move around from a set pose.",
	0,
	1
)
cvars.RemoveChangeCallback("ragdollposer_static", "RagdollPoser_StaticCVarChanged")
cvars.AddChangeCallback("ragdollposer_static", function(convar, oldValue, newValue)
	RagdollPoser.Entity.RefreshEntities(Entities)
end, "RagdollPoser_StaticCVarChanged")

---@param self Entity
local function renderOverride(self, flags)
	cam.IgnoreZ(true)
	render.OverrideColorWriteEnable(true, false)
	self:DrawModel(flags)
	render.OverrideColorWriteEnable(false, false)
	render.SetBlend(0.75)
	self:DrawModel(flags)
	render.SetBlend(1)
	cam.IgnoreZ(false)
end

---@param self Entity
---@param numbones integer
local function clientBoneManipulator(self, numbones)
	local firstSet = self.rgp_firstSet
	local entity = ClientToEntity[self]
	local matrixSet = EntityMatrices[entity]
	local renderBounds = EntityRenderBounds[entity]
	for b = 0, numbones - 1 do
		local m = matrixSet[b + 1]
		if not ismatrix(m) then
			m = Matrix()
			matrixSet[b + 1] = m
		end
		if not firstSet or not static:GetBool() then
			entity:CopyBoneMatrix(b, m)
			renderBounds[1], renderBounds[2] = entity:GetRenderBounds()
		end

		local name = self:GetBoneName(b)
		if m and name ~= "__INVALIDBONE__" then
			self:SetBoneMatrix(b, m)
		end
	end
	self.rgp_firstSet = true

	self:SetRenderBounds(renderBounds[1], renderBounds[2])
end

function MGR.CreateEntities()
	for _, entity in ipairs(ClientEntities) do
		entity:RemoveCallback("BuildBonePositions", entity.bonecallback)
		entity:Remove()
	end
	ClientEntities = {}

	local dirty = false
	for i, entity in ipairs(Entities) do
		if entity:IsMarkedForDeletion() then
			dirty = true
			continue
		end
		EntityMatrices[entity] = {}
		local min, max = entity:GetRenderBounds()
		EntityRenderBounds[entity] = { min, max }

		local client = ents.CreateClientProp()
		client:SetModel(entity:GetModel())
		client:SetupBones()
		client:InvalidateBoneCache()
		client:Spawn()

		client.RenderOverride = renderOverride
		client:SetPos(entity:GetPos())

		ClientToEntity[client] = entity
		ClientFirstSet[client] = false
		EntityToClient[entity] = client
		client.bonecallback = client:AddCallback("BuildBonePositions", clientBoneManipulator)

		entity.rgp_client = client
		entity.rgp_index = i

		client.rgp_isclient = true

		table.insert(ClientEntities, client)
	end
end

hook.Add("EntityRemoved", "RagdollPoser_EntityRemoved", function(ent, fullUpdate)
	if fullUpdate then
		return
	end

	print(ent.rgp_client)
	if IsValid(ent.rgp_client) then
		table.remove(Entities, ent.rgp_index)
		ent.rgp_client:Remove()
		MGR.RefreshEntities(Entities)
	end
end)

---@param entity Entity
---@return VMatrix[]
function MGR.GetMatrices(entity)
	return EntityMatrices[entity]
end

hook.Add("RagdollPoser_GizmoPositionSet", "RagdollPoser_SetBonePosition", function(pos)
	local entity = RagdollPoser.Gizmo._entity
	if IsValid(entity) then
		local client = EntityToClient[entity]
		local matrix = EntityMatrices[entity][RagdollPoser.Gizmo._bone + 1]
		print(RagdollPoser.Gizmo._bone)
		if matrix then
			matrix:SetTranslation(pos)
		end
	end
end)

---Get all entities of the selected assembly
---@param entities Entity[]
function MGR.RefreshEntities(entities)
	Entities = entities
	MGR.CreateEntities()
end

---@return Entity[]
function MGR.GetEntities()
	return Entities
end

---@return Entity[]
function MGR.GetClientEntities()
	return ClientEntities
end

-- After receiving entity info, create `prop_dynamic` clones of the given entities,
-- move it and copy the pose of the ragdoll, and either
-- a) stay put, or
-- b) track the ragdoll pose

RagdollPoser.Networking.DefineReceiver("SendAssemblyInfo", function(len, ply)
	local ent = net.ReadEntity()
	local bone = net.ReadUInt(8)
	local count = net.ReadUInt(10)
	local entities = {}
	for i = 1, count do
		entities[i] = net.ReadEntity()
	end
	print(ent, bone)
	if IsValid(ent) and bone then
		MGR.RefreshEntities(entities)
		RagdollPoser.Gizmo:Select(ent, bone)
	end
end)
RagdollPoser.Networking.DefineReceiver("SendAssemblyInfo2", function(len, ply)
	print("Get assembly info2")
end)

for _, ent in ipairs(ents.GetAll()) do
	if ent.rgp_isclient then
		ent:Remove()
	end
end

RagdollPoser.Entity = MGR
