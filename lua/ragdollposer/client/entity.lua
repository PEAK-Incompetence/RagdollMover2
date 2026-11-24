---@class RGPEntity: Entity
---@field rgp_index integer

---@class ClientEntity: Entity
---@field rgp_isclient true

---[CLIENT]
---
---Stores and displays client representations of server entities
---
---Modify the matrices of the client representation. Then send the
---matrices of the modified result to the server
---
---FIXME: This is still not hot refresh friendly
---
---@class RagdollPoser.Entity
local MGR = RagdollPoser.Entity or {}

---@type Entity[]
MGR.Entities = MGR.Entities or {}
---@type ClientEntity[]
MGR.ClientEntities = MGR.ClientEntities or {}

---@type {[ClientEntity]: Entity}
MGR.ClientToEntity = MGR.ClientToEntity or {}
---@type {[Entity]: ClientEntity}
MGR.EntityToClient = MGR.EntityToClient or {}
---@type {[ClientEntity]: boolean}
MGR.ClientShouldUpdate = MGR.ClientShouldUpdate or {}
---@type {[ClientEntity]: integer}
MGR.ClientBoneCallbacks = MGR.ClientBoneCallbacks or {}
---@type {[Entity]: integer}
MGR.EntityPhysBoneCount = MGR.EntityPhysBoneCount or {}

---@alias BonePoseInfo {[1]: Vector, [2]: Angle, [3]: Vector, [4]: Angle, [5]: integer, [6]: integer}
---@type {[string]: BonePoseInfo[]}
local PoseTrees = {}

local function refreshClientData()
	MGR.ClientEntities = {}
	MGR.ClientToEntity = {}
	MGR.ClientShouldUpdate = {}
	MGR.ClientBoneCallbacks = {}
end

---@type {[Entity]: VMatrix[]}
MGR.EntityMatrices = MGR.EntityMatrices or {}
MGR.EntityRenderBounds = MGR.EntityRenderBounds or {}

local static = CreateClientConVar(
	"ragdollposer_static",
	1,
	true,
	true,
	"If set to 1, client entities will not track their entities. This is useful if you don't want the ragdoll to move around from a set pose.",
	0,
	1
)

local xray = CreateClientConVar(
	"ragdollposer_xray_selection",
	0,
	true,
	true,
	"If set to 1, selected will render in front of all models.",
	0,
	1
)

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

	client:SetRenderMode(source:GetRenderMode())
	client:SetColor(source:GetColor())
end

---Display the entity
---@param self ClientEntity
local function renderOverride(self, flags)
	local transparentFlags = bit.bor(flags, STUDIO_NOSHADOWS, STUDIO_DRAWTRANSLUCENTSUBMODELS)
	if RagdollPoser.Helpers.Equipped() then
		-- Draw the entity underneath the ghost
		local entity = MGR.ClientToEntity[self]
		local root = RagdollPoser.Helpers.GetAncestor(entity)

		local constrainedEntities = RagdollPoser.Constraints:GetGraphForEntity(entity)
		local shouldDraw = RagdollPoser.Selection:IsEntitySelected(root)
			or RagdollPoser.Selection:IsEntitySelected(entity)
		if constrainedEntities then
			for _, constrained in ipairs(constrainedEntities.array) do
				if RagdollPoser.Selection:IsEntitySelected(constrained) then
					shouldDraw = true
					break
				end
			end
		end

		-- Only draw if the selected entity is the `root` or has the `root` as its parent.
		if not shouldDraw then
			return
		end

		if IsValid(entity) then
			copyVisualsToClient(self, entity)

			entity:DrawModel(flags)
			cam.IgnoreZ(xray:GetBool())
			render.OverrideColorWriteEnable(true, false)
			self:DrawModel(transparentFlags)
			render.OverrideColorWriteEnable(false, false)
			render.SetBlend(0.5)
			self:DrawModel(transparentFlags)
			render.SetBlend(1)
			cam.IgnoreZ(false)
		end
	end
end

---@param self ClientEntity
---@param numbones integer
---@param staticProp boolean? Only called from explicitly
local function clientBoneManipulator(self, numbones, staticProp)
	local shouldUpdate = MGR.ClientShouldUpdate[self]
	local entity = MGR.ClientToEntity[self]
	local matrixSet = MGR.EntityMatrices[entity]
	local renderBounds = MGR.EntityRenderBounds[entity]
	local static = static:GetBool()
	local isMoving = RagdollPoser.Gizmo:IsMoving() or RagdollPoser.Gizmo:IsOperating()

	if not matrixSet then
		return
	end
	for b = 0, numbones - 1 do
		local m = matrixSet[b + 1]
		if not ismatrix(m) then
			m = Matrix()
			matrixSet[b + 1] = m
		end
		if shouldUpdate or (not static and not isMoving) then
			entity:CopyBoneMatrix(b, m)
			renderBounds[1], renderBounds[2] = entity:GetRenderBounds()
			if entity:GetClass() == "prop_effect" then
				-- TODO: Are there other entities that have a delay unless you hover over them?
				m:SetTranslation(entity:GetPos())
				m:SetAngles(entity:GetAngles())
			end
		end

		local name = self:GetBoneName(b)
		if m then
			if staticProp then
				self:SetPos(m:GetTranslation())
				self:SetAngles(m:GetAngles())
				self:EnableMatrix("EnableMatrix", m)
			elseif name ~= "__INVALIDBONE__" then
				self:SetBoneMatrix(b, m)
			end
		end
	end
	if not static and not isMoving then
		RagdollPoser.Gizmo:SetTransformFromSelection(RagdollPoser.Selection:GetSelection())
	end
	MGR.ClientShouldUpdate[self] = false

	local m = matrixSet[1]
	if m then
		-- If we don't set this, then the render bounds won't update to our current position
		self:SetPos(m:GetTranslation())
	end
	self:SetRenderBounds(renderBounds[1], renderBounds[2])
end

---@type ClientEntity[]
MGR.StaticProps = MGR.StaticProps or {}
local function updateStaticProps()
	local staticProps = MGR.StaticProps
	-- TODO: Support scaling static props (they don't scale at all)
	for i = 1, #staticProps do
		local clientProp = staticProps[i] --[[@as ClientEntity]]
		MGR:ExposeBones(clientProp)
		clientBoneManipulator(clientProp, 1, true)
	end
end
hook.Remove("PreDrawOpaqueRenderables", "RagdollPoser_Entity_StaticProps")
hook.Add("PreDrawOpaqueRenderables", "RagdollPoser_Entity_StaticProps", updateStaticProps)

function MGR:CreateEntities()
	for _, client in ipairs(self.ClientEntities) do
		if IsValid(client) then
			client.RenderOverride = nil
			client:RemoveCallback("BuildBonePositions", self.ClientBoneCallbacks[client])
			client:Remove()
			self.ClientToEntity[client] = nil
			self.ClientShouldUpdate[client] = nil
		end
	end
	refreshClientData()
	self.StaticProps = {}

	local dirties = {}
	for i, entity in ipairs(self.Entities) do
		---@cast entity RGPEntity
		if not IsValid(entity) or entity:IsMarkedForDeletion() then
			dirties[i] = entity
			continue
		end
		self.EntityMatrices[entity] = {}
		local min, max = entity:GetRenderBounds()
		self.EntityRenderBounds[entity] = { min, max }

		local client = ents.CreateClientProp()
		---@cast client ClientEntity
		client:SetModel(entity:GetModel()) ---@diagnostic disable-line: param-type-mismatch
		client:SetupBones()
		client:InvalidateBoneCache()
		client:Spawn()

		client.RenderOverride = renderOverride
		client:SetPos(entity:GetPos())

		self.ClientToEntity[client] = entity
		self.ClientShouldUpdate[client] = true
		self.EntityToClient[entity] = client
		self.ClientBoneCallbacks[client] = client:AddCallback("BuildBonePositions", clientBoneManipulator)
		local modelInfo = util.GetModelInfo(entity:GetModel())
		local isStaticProp = modelInfo.StaticProp
		if isStaticProp then
			-- Static props bone manipulators build bone positions, so we get hook to do that for us.
			table.insert(self.StaticProps, client)
		end
		clientBoneManipulator(client, client:GetBoneCount(), isStaticProp)

		entity.rgp_index = i

		client.rgp_isclient = true

		table.insert(self.ClientEntities, client)
	end

	if dirties[1] then
		for dirty, _ in SortedPairs(dirties, true) do
			table.remove(self.Entities, dirty)
		end
	end
end

---Helper function which calls SetupBones and InvalidateBoneCache to show invisible bones
---@param entity Entity
function MGR:ExposeBones(entity)
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
	if IsValid(MGR.EntityToClient[ent]) then
		table.remove(MGR.Entities, ent.rgp_index)
		MGR.EntityToClient[ent]:Remove()
		MGR.EntityRenderBounds[ent] = nil
		MGR:RefreshEntities(MGR.Entities)
		hook.Run("RagdollPoser_Entity_PostRefresh", MGR.EntityToClient)
	end
end)

---Bone indices for the matrices are offset by 1, i.e.
---
---```lua
---	local matrices = RagdollPoser.Entity:GetMatrices(entity)
---	local matrix = matrices[b + 1]
---```
---@param entity Entity
---@return VMatrix[] entityMatrices
function MGR:GetMatrices(entity)
	return self.EntityMatrices[entity]
end

---
---
---@param entity Entity
function MGR:UpdateRenderBounds(entity)
	local renderBounds = self.EntityRenderBounds[entity]
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
	local rootMatrix = ent:GetBoneMatrix(0)
	local rootPos = rootMatrix and rootMatrix:GetTranslation() or entPos
	local rootAngles = rootMatrix and rootMatrix:GetAngles() or entAngles
	for b = 0, ent:GetBoneCount() - 1 do
		local parent = ent:GetBoneParent(b)
		local isPhysBone = RagdollPoser.Helpers.BoneToPhysBone(ent, b) >= 0
		local bMatrix = ent:GetBoneMatrix(b)
		if bMatrix then
			local pos1, ang1 = WorldToLocal(bMatrix:GetTranslation(), bMatrix:GetAngles(), rootPos, rootAngles)
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
function MGR:GetDefaultPoseTreeFor(entity)
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
---	local matrices = RagdollPoser.Entity:GetMatrices(client)
---	local matrix = matrices[b + 1]
---```
---@param client ClientEntity
---@return VMatrix[] clientMatrices
function MGR:GetMatricesFromClient(client)
	return self.EntityMatrices[self.ClientToEntity[client]]
end

---Get all entities of the selected assembly
---@param entities Entity[]
function MGR:RefreshEntities(entities)
	hook.Run("RagdollPoser_Entity_PreRefresh", self.ClientToEntity)

	self.Entities = entities
	self:CreateEntities()

	for entity, client in pairs(self.EntityToClient) do
		if not IsValid(client) then
			self.EntityToClient[entity] = nil
		end
	end
end

---@param client ClientEntity
---@return Entity entity
function MGR:GetEntityFromClient(client)
	return self.ClientToEntity[client]
end

---@param entity Entity
---@return ClientEntity client
function MGR:GetClientFromEntity(entity)
	return self.EntityToClient[entity]
end

---@return Entity[] entities
function MGR:GetEntities()
	return self.Entities
end

---@return Entity[] clients
function MGR:GetClientEntities()
	return self.ClientEntities
end

---@param entity Entity
function MGR:UpdateEntity(entity)
	local client = self.EntityToClient[entity]
	if client and IsValid(client) then
		self.ClientShouldUpdate[client] = true
		clientBoneManipulator(client, client:GetBoneCount())
	end
end

--- Assume we are in the receiving process
---@return NetworkedConstraint[]
local function readConstraints()
	---@type NetworkedConstraint[]
	local networkedConstraints = {}
	local count = net.ReadUInt(RagdollPoser.ConstraintBits)
	for i = 1, count do
		local type = net.ReadUInt(RagdollPoser.ConstraintTypeBits) -- Type
		local name = net.ReadString() -- Name
		local state = net.ReadTable() -- State
		networkedConstraints[i] = {
			Type = type,
			Name = name,
			State = state, ---@diagnostic disable-line
		}
	end
	return networkedConstraints
end

-- After receiving entity info, create `prop_dynamic` clones of the given entities,
-- move it and copy the pose of the ragdoll, and either
-- a) stay put, or
-- b) track the ragdoll pose

local function sendAssemblyInfo()
	local ent = net.ReadEntity()
	local bone = net.ReadUInt(RagdollPoser.Constants.MAX_BONE_BITS)
	local count = net.ReadUInt(RagdollPoser.Constants.MAX_ENTITY_LIST_BITS)
	---@type Entity[]
	local entities = {}
	-- print(ent, bone, count)
	local constraintCount = 0
	---@type table<Entity, NetworkedConstraint[]>
	local entityConstraints = {}
	for i = 1, count do
		local e = net.ReadEntity()
		entities[i] = e
		local hasConstraint = net.ReadBool()
		if hasConstraint then
			constraintCount = constraintCount + 1
			entityConstraints[e] = readConstraints()
		end
	end

	if constraintCount > 0 then
		RagdollPoser.Constraints:SetConstraints(entityConstraints)
	end

	if IsValid(ent) and bone then
		MGR:RefreshEntities(entities)
		hook.Run("RagdollPoser_Entity_PostRefresh", MGR.EntityToClient)
		local selection = RagdollPoser.Selection:GetSelection()
		if selection[#selection] ~= ent then
			RagdollPoser.Selection:ResetFilter()
			RagdollPoser.Selection:SelectOne(bone, MGR.EntityToClient[ent], false)
		end
	else
		MGR:RefreshEntities(entities)
		hook.Run("RagdollPoser_Entity_PostRefresh", MGR.EntityToClient)
		RagdollPoser.Selection:Unselect()
	end
end
RagdollPoser.Networking.DefineReceiver("SendAssemblyInfo", sendAssemblyInfo)

---@param entity Entity
---@return integer physBoneCount
function MGR:GetPhysBoneCount(entity)
	local model = entity:GetModel()
	return self.EntityPhysBoneCount[model]
end

local function getPhysBoneCount(len, ply)
	local entity = net.ReadEntity()
	local count = net.ReadUInt(RagdollPoser.Constants.MAX_PHYSBONE_BITS)
	if IsValid(entity) then
		local model = entity:GetModel()

		if model and not MGR.EntityPhysBoneCount[model] then
			MGR.EntityPhysBoneCount[model] = count
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

function MGR:Reset()
	for _, client in ipairs(self.ClientEntities) do
		if IsValid(client) then
			client.RenderOverride = nil
			client:RemoveCallback("BuildBonePositions", self.ClientBoneCallbacks[client])
			client:Remove()
			self.ClientToEntity[client] = nil
			self.ClientShouldUpdate[client] = nil
		end
	end
	refreshClientData()
end

MGR:Reset()

RagdollPoser.Entity = MGR
