---@class RGPEntity: Entity
---@field rgp_index integer

---@class ClientEntity: Entity
---@field rgp_isclient true

---@type Entity[]
local Entities = {}
---@type ClientEntity[]
local ClientEntities = {}

---@type {[ClientEntity]: Entity}
local ClientToEntity = {}
---@type {[Entity]: ClientEntity}
local EntityToClient = {}
---@type {[ClientEntity]: boolean}
local ClientShouldUpdate = {}
---@type {[ClientEntity]: integer}
local ClientBoneCallbacks = {}
---@type {[Entity]: integer}
local EntityPhysBoneCount = {}

---@alias BonePoseInfo {[1]: Vector, [2]: Angle, [3]: Vector, [4]: Angle, [5]: integer, [6]: integer}
---@type {[string]: BonePoseInfo[]}
local PoseTrees = {}

local function refreshClientData()
	ClientEntities = {}
	ClientToEntity = {}
	ClientShouldUpdate = {}
	ClientBoneCallbacks = {}
end

---@type {[Entity]: VMatrix[]}
local EntityMatrices = {}
local EntityRenderBounds = {}

---[CLIENT]
---
---Stores and displays client representations of server entities
---
---Modify the matrices of the client representation. Then send the
---matrices of the modified result to the server
---
---@class RagdollPoser.Entity
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

--- @param client ClientEntity
--- @param source Entity
local function copyVisualsToClient(client, source)
	client:SetSkin(source:GetSkin())
	for _, bodyGroup in ipairs(source:GetBodyGroups()) do
		client:SetBodygroup(bodyGroup.id, source:GetBodygroup(bodyGroup.id))
	end

	client:SetFlexScale(source:GetFlexScale())
	for i = 0, source:GetFlexNum() - 1 do
		client:SetFlexWeight(i, source:GetFlexWeight(i))
	end
end

---@param self ClientEntity
local function renderOverride(self, flags)
	local transparentFlags = bit.bor(flags, STUDIO_NOSHADOWS, STUDIO_DRAWTRANSLUCENTSUBMODELS)
	if RagdollPoser.Helpers.Equipped() then
		-- Draw the entity underneath the ghost
		local entity = ClientToEntity[self]
		copyVisualsToClient(self, entity)

		entity:DrawModel(flags)
		cam.IgnoreZ(true)
		render.OverrideColorWriteEnable(true, false)
		self:DrawModel(transparentFlags)
		render.OverrideColorWriteEnable(false, false)
		render.SetBlend(0.75)
		self:DrawModel(transparentFlags)
		render.SetBlend(1)
		cam.IgnoreZ(false)
	end
end

---@param self ClientEntity
---@param numbones integer
---@param staticProp boolean? Only called from explicitly
local function clientBoneManipulator(self, numbones, staticProp)
	local shouldUpdate = ClientShouldUpdate[self]
	local entity = ClientToEntity[self]
	local matrixSet = EntityMatrices[entity]
	local renderBounds = EntityRenderBounds[entity]
	for b = 0, numbones - 1 do
		local m = matrixSet[b + 1]
		if not ismatrix(m) then
			m = Matrix()
			matrixSet[b + 1] = m
		end
		if shouldUpdate or not static:GetBool() then
			entity:CopyBoneMatrix(b, m)
			renderBounds[1], renderBounds[2] = entity:GetRenderBounds()
		end

		local name = self:GetBoneName(b)
		if m then
			if staticProp then
				self:SetPos(m:GetTranslation())
				self:SetAngles(m:GetAngles())
			elseif name ~= "__INVALIDBONE__" then
				self:SetBoneMatrix(b, m)
			end
		end
	end
	ClientShouldUpdate[self] = false

	local m = matrixSet[1]
	if m then
		-- If we don't set this, then the render bounds won't update to our current position
		self:SetPos(m:GetTranslation())
	end
	self:SetRenderBounds(renderBounds[1], renderBounds[2])
end

---@type ClientEntity[]
local staticProps = {}
local function updateStaticProps()
	for i = 1, #staticProps do
		local clientProp = staticProps[i] --[[@as ClientEntity]]
		MGR.ExposeBones(clientProp)
		clientBoneManipulator(clientProp, 1, true)
	end
end
hook.Remove("PreDrawOpaqueRenderables", "RagdollPoser_Entity_StaticProps")
hook.Add("PreDrawOpaqueRenderables", "RagdollPoser_Entity_StaticProps", updateStaticProps)

function MGR.CreateEntities()
	for _, client in ipairs(ClientEntities) do
		client:RemoveCallback("BuildBonePositions", ClientBoneCallbacks[client])
		client:Remove()
		ClientToEntity[client] = nil
		ClientShouldUpdate[client] = nil
	end
	refreshClientData()
	staticProps = {}

	local dirties = {}
	for i, entity in ipairs(Entities) do
		---@cast entity RGPEntity
		if not IsValid(entity) or entity:IsMarkedForDeletion() then
			dirties[i] = entity
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
		ClientShouldUpdate[client] = true
		EntityToClient[entity] = client
		ClientBoneCallbacks[client] = client:AddCallback("BuildBonePositions", clientBoneManipulator)
		local modelInfo = util.GetModelInfo(entity:GetModel())
		local isStaticProp = modelInfo.StaticProp
		if isStaticProp then
			-- Static props bone manipulators build bone positions, so we get hook to do that for us.
			table.insert(staticProps, client)
		end
		clientBoneManipulator(client, client:GetBoneCount(), isStaticProp)

		entity.rgp_index = i

		client.rgp_isclient = true

		table.insert(ClientEntities, client)
	end

	if dirties[1] then
		for dirty, _ in SortedPairs(dirties, true) do
			table.remove(Entities, dirty)
		end
	end
end

---Helper function which calls SetupBones and InvalidateBoneCache to show invisible bones
---@param entity Entity
function MGR.ExposeBones(entity)
	if IsValid(entity) then
		entity:SetupBones()
		entity:InvalidateBoneCache()
	end
end

hook.Remove("EntityRemoved", "RagdollPoser_Entity_EntityRemoved")
hook.Add("EntityRemoved", "RagdollPoser_Entity_EntityRemoved", function(ent, fullUpdate)
	if fullUpdate then
		return
	end

	---@cast ent RGPEntity
	if IsValid(EntityToClient[ent]) then
		table.remove(Entities, ent.rgp_index)
		EntityToClient[ent]:Remove()
		EntityRenderBounds[ent] = nil
		MGR.RefreshEntities(Entities)
		hook.Run("RagdollPoser_Entity_PostRefresh", EntityToClient)
	end
end)

---Bone indices for the matrices are offset by 1, i.e.
---
---```lua
---	local matrices = RagdollPoser.Entity.GetMatrices(entity)
---	local matrix = matrices[b + 1]
---```
---@param entity Entity
---@return VMatrix[] entityMatrices
function MGR.GetMatrices(entity)
	return EntityMatrices[entity]
end

---
---
---@param entity Entity
function MGR.UpdateRenderBounds(entity)
	local renderBounds = EntityRenderBounds[entity]
	if renderBounds then
		renderBounds[1], renderBounds[2] = entity:GetRenderBounds()
	end
end

---Source: https://github.com/NO-LOAFING/AnimpropOverhaul/blob/a3a6268a5d57655611a8b8ed43dcf43051ecd93a/lua/entities/prop_animated.lua#L3550
---@param ent Entity|CSEnt Entity in reference pose
---@return BonePoseInfo[] defaultPose Array consisting of a bones offsets from the entity, and offsets from its parent bones
local function getDefaultPoseTree(ent)
	local defaultPose = {}
	local entPos = ent:GetPos()
	local entAngles = ent:GetAngles()
	for b = 0, ent:GetBoneCount() - 1 do
		local parent = ent:GetBoneParent(b)
		local isPhysBone = RagdollPoser.Helpers.BoneToPhysBone(ent, b) >= 0
		local bMatrix = ent:GetBoneMatrix(b)
		if bMatrix then
			local pos1, ang1 = WorldToLocal(bMatrix:GetTranslation(), bMatrix:GetAngles(), entPos, entAngles)
			local pos2, ang2 = pos1 * 1, ang1 * 1
			if parent > -1 then
				local pMatrix = ent:GetBoneMatrix(parent)
				pos2, ang2 = WorldToLocal(
					bMatrix:GetTranslation(),
					bMatrix:GetAngles(),
					pMatrix:GetTranslation(),
					pMatrix:GetAngles()
				)
			end

			defaultPose[b + 1] = { pos1, ang1, pos2, ang2, parent, isPhysBone }
		else
			defaultPose[b + 1] = { vector_origin, angle_zero, vector_origin, angle_zero, -1, false }
		end
	end

	return defaultPose
end

---Get the default pose of an entity
---
---```lua
---	local poseTree = GetDefaultPoseTreeFor(entity)
---	PrintTable(poseTree[b + 1])
---```
---
---@param entity Entity
---@return BonePoseInfo[] defaultPose Array consisting of a bones offsets from the entity, and offsets from its parent bones
function MGR.GetDefaultPoseTreeFor(entity)
	local model = entity:GetModel()
	local tree = PoseTrees[model]
	if tree then
		return tree
	end

	---@diagnostic disable
	local csModel = ClientsideModel(entity:GetModel())
	csModel:DrawModel()
	csModel:SetupBones()
	csModel:InvalidateBoneCache()
	tree = getDefaultPoseTree(csModel)
	csModel:Remove()

	PoseTrees[model] = tree
	---@diagnostic enable

	return tree
end

---Bone indices for the matrices are offset by 1, i.e.
---
---```lua
---	local matrices = RagdollPoser.Entity.GetMatrices(client)
---	local matrix = matrices[b + 1]
---```
---@param client ClientEntity
---@return VMatrix[] clientMatrices
function MGR.GetMatricesFromClient(client)
	return EntityMatrices[ClientToEntity[client]]
end

---Get all entities of the selected assembly
---@param entities Entity[]
function MGR.RefreshEntities(entities)
	hook.Run("RagdollPoser_Entity_PreRefresh", ClientToEntity)

	Entities = entities
	MGR.CreateEntities()

	for entity, client in pairs(EntityToClient) do
		if not IsValid(client) then
			EntityToClient[entity] = nil
		end
	end
end

---@param client ClientEntity
---@return Entity entity
function MGR.GetEntityFromClient(client)
	return ClientToEntity[client]
end

---@param entity Entity
---@return ClientEntity client
function MGR.GetClientFromEntity(entity)
	return EntityToClient[entity]
end

---@return Entity[] entities
function MGR.GetEntities()
	return Entities
end

---@return Entity[] clients
function MGR.GetClientEntities()
	return ClientEntities
end

---@param entity Entity
function MGR.UpdateEntity(entity)
	local client = EntityToClient[entity]
	if client and IsValid(client) then
		ClientShouldUpdate[client] = true
		clientBoneManipulator(client, client:GetBoneCount())
	end
end

-- After receiving entity info, create `prop_dynamic` clones of the given entities,
-- move it and copy the pose of the ragdoll, and either
-- a) stay put, or
-- b) track the ragdoll pose

local function sendAssemblyInfo()
	local ent = net.ReadEntity()
	local bone = net.ReadUInt(8)
	local count = net.ReadUInt(10)
	---@type Entity[]
	local entities = {}
	print(ent, bone, count)
	local constraintCount = 0
	---@type table<Entity, SerializedConstraint[]>
	local entityConstraints = {}
	for i = 1, count do
		local e = net.ReadEntity()
		entities[i] = e
		local hasConstraint = net.ReadBool()
		if hasConstraint then
			constraintCount = constraintCount + 1
			entityConstraints[e] = net.ReadTable(true)
		end
	end

	if constraintCount > 0 then
		RagdollPoser.Constraints:SetConstraints(entityConstraints)
	end

	if IsValid(ent) and bone then
		MGR.RefreshEntities(entities)
		hook.Run("RagdollPoser_Entity_PostRefresh", EntityToClient)
		local selection = RagdollPoser.Selection:GetSelection()
		if selection[#selection] ~= ent then
			RagdollPoser.Selection:SelectOne(bone, EntityToClient[ent], false)
		end
	else
		MGR.RefreshEntities(entities)
		hook.Run("RagdollPoser_Entity_PostRefresh", EntityToClient)
		RagdollPoser.Selection:Unselect()
	end
end
RagdollPoser.Networking.DefineReceiver("SendAssemblyInfo", sendAssemblyInfo)

---@param entity Entity
---@return integer physBoneCount
function MGR.GetPhysBoneCount(entity)
	local model = entity:GetModel()
	return EntityPhysBoneCount[model]
end

local function getPhysBoneCount(len, ply)
	local entity = net.ReadEntity()
	local count = net.ReadUInt(5)
	if IsValid(entity) then
		local model = entity:GetModel()

		if model and not EntityPhysBoneCount[model] then
			EntityPhysBoneCount[model] = count
			RagdollPoser.Bones:ReportModel(entity, model)
		end
	end
end
RagdollPoser.Networking.DefineReceiver("EntityPhysBoneCount", getPhysBoneCount)

for _, ent in ipairs(ents.GetAll()) do
	---@cast ent Entity|ClientEntity
	if ent.rgp_isclient then
		ent:Remove()
	end
end

RagdollPoser.Entity = MGR
