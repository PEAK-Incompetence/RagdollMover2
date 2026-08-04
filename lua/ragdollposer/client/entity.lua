---@class RGPEntity: Entity
---@field rgp_client ClientEntity
---@field rgp_index integer

---@class ClientEntity: Entity
---@field rgp_isclient true
---@field rgp_bonecallback integer

---@type Entity[]
local Entities = {}
---@type ClientEntity[]
local ClientEntities = {}

---@type {[ClientEntity]: Entity}
local ClientToEntity = {}
---@type {[Entity]: ClientEntity}
local EntityToClient = {}
---@type {[ClientEntity]: boolean}
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
		entity:RemoveCallback("BuildBonePositions", entity.rgp_bonecallback)
		entity:Remove()
	end
	ClientEntities = {}

	local dirty = false
	for i, entity in ipairs(Entities) do
		---@cast entity RGPEntity
		if entity:IsMarkedForDeletion() then
			dirty = true
			continue
		end
		EntityMatrices[entity] = {}
		local min, max = entity:GetRenderBounds()
		EntityRenderBounds[entity] = { min, max }

		local client = ents.CreateClientProp()
		---@cast client ClientEntity
		client:SetModel(entity:GetModel()) ---@diagnostic disable-line: param-type-mismatch
		client:SetupBones()
		client:InvalidateBoneCache()
		client:Spawn()

		client.RenderOverride = renderOverride
		client:SetPos(entity:GetPos())

		ClientToEntity[client] = entity
		ClientFirstSet[client] = false
		EntityToClient[entity] = client
		client.rgp_bonecallback = client:AddCallback("BuildBonePositions", clientBoneManipulator)
		clientBoneManipulator(client, client:GetBoneCount())

		entity.rgp_client = client
		entity.rgp_index = i

		client.rgp_isclient = true

		table.insert(ClientEntities, client)
	end
end

hook.Remove("EntityRemoved", "RagdollPoser_EntityRemoved")
hook.Add("EntityRemoved", "RagdollPoser_EntityRemoved", function(ent, fullUpdate)
	if fullUpdate then
		return
	end
	---@cast ent RGPEntity
	if IsValid(ent.rgp_client) then
		table.remove(Entities, ent.rgp_index)
		ent.rgp_client:Remove()
		MGR.RefreshEntities(Entities)
	end
end)

---Bone indices for the matrices are offset by 1, i.e.
---
---```lua
---	local matrices = RagdollPoser.Entity.GetMatrices(entity)
---	local matrix = matrices[b + 1]
---```
---@param entity Entity
---@return VMatrix[]
function MGR.GetMatrices(entity)
	return EntityMatrices[entity]
end

---Get all entities of the selected assembly
---@param entities Entity[]
function MGR.RefreshEntities(entities)
	hook.Run("RagdollPoser_Entity_PreRefresh", ClientToEntity)

	Entities = entities
	MGR.CreateEntities()

	hook.Run("RagdollPoser_Entity_PostRefresh", EntityToClient)
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
	if IsValid(ent) and bone then
		MGR.RefreshEntities(entities)
		if not RagdollPoser.Selection:GetSelection()[1] then
			RagdollPoser.Selection:SelectOne(bone, ent)
		end
	end
end)
RagdollPoser.Networking.DefineReceiver("SendAssemblyInfo2", function(len, ply)
	print("Get assembly info2")
end)

for _, ent in ipairs(ents.GetAll()) do
	---@cast ent Entity|ClientEntity
	if ent.rgp_isclient then
		ent:Remove()
	end
end

RagdollPoser.Entity = MGR
