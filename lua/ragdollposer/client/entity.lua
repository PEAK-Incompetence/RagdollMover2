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

	if source:HasFlexManipulatior() then
		client:SetFlexScale(source:GetFlexScale())
		for i = 0, source:GetFlexNum() - 1 do
			client:SetFlexWeight(i, source:GetFlexWeight(i))
		end
	end

	client:SetRenderMode(source:GetRenderMode())
	client:SetColor(source:GetColor())
end

-- 4x4 Bayer threshold matrix (values 0..15)
local bayer4x4 = {
	{ 0,  8,  2,  10 },
	{ 12, 4,  14, 6 },
	{ 3,  11, 1,  9 },
	{ 15, 7,  13, 5 },
}

-- Create a render target to store the above 4x4 Bayer slop
local checkerRT = GetRenderTargetEx(
	"_rt_rgp_ghost",
	4, 4,
	RT_SIZE_NO_CHANGE,
	MATERIAL_RT_DEPTH_NONE,
	bit.bor(1, 256), -- TEXTUREFLAGS_POINTSAMPLE (1) + TEXTUREFLAGS_NOLOD (256)
	0,
	IMAGE_FORMAT_RGBA8888
)

-- Opacity threshold: 8 out of 16 pixels = 50% opacity (adjust 1..15 as desired)
local opacityThreshold = 13
local function initRT()
	render.PushRenderTarget(checkerRT)
	render.OverrideAlphaWriteEnable(true, true)
	render.Clear(0, 0, 0, 0, false, false)

	for y = 0, 3 do
		for x = 0, 3 do
			if bayer4x4[y + 1][x + 1] < opacityThreshold then
				render.SetViewPort(x, y, 1, 1)
				render.Clear(255, 255, 255, 255, false, false)
			end
		end
	end

	render.SetViewPort(0, 0, ScrW(), ScrH())
	render.OverrideAlphaWriteEnable(false, false)
	render.PopRenderTarget()
end
initRT()

local checkerMat = CreateMaterial("ghost_bayer4x4_mat", "UnlitGeneric", {
	["$basetexture"] = checkerRT:GetName(),
	["$alphatest"] = 1,
	["$alphatestreference"] = 0.5,
})

local texMatrix = Matrix()

---Display the entity
---@param self ClientEntity
local function renderOverride(self, flags)
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
			local transparentFlags = bit.bor(flags, STUDIO_NOSHADOWS, STUDIO_STATIC_LIGHTING, STUDIO_SKIP_DECALS,
				STUDIO_DRAWTRANSLUCENTSUBMODELS)

			copyVisualsToClient(self, entity)
			entity:DrawModel(flags)

			-- 1. Map the 4x4 Bayer pattern 1:1 to screen pixels (w / 4, h / 4)
			local w, h = ScrW(), ScrH()
			texMatrix:Identity()
			texMatrix:SetScale(Vector(w * 0.25, h * 0.25, 1))
			checkerMat:SetMatrix("$basetexturetransform", texMatrix)

			render.SetStencilEnable(true)
			render.ClearStencil()

			-- Isolate on stencil bit 8 (0x08) so hover halos on bit 1 don't collide
			render.SetStencilWriteMask(0x08)
			render.SetStencilTestMask(0x08)
			render.SetStencilReferenceValue(8)
			render.SetStencilCompareFunction(STENCIL_ALWAYS)
			render.SetStencilPassOperation(STENCIL_REPLACE)
			render.SetStencilFailOperation(STENCIL_KEEP)
			render.SetStencilZFailOperation(STENCIL_KEEP)

			render.OverrideColorWriteEnable(true, false)
			render.OverrideDepthEnable(true, false)

			render.SetMaterial(checkerMat)
			render.DrawScreenQuadEx(0, 0, w, h)

			render.OverrideDepthEnable(false, false)
			render.OverrideColorWriteEnable(false, false)

			-- 2. Draw ghost with softened contrast modulation to prevent strobing
			render.SetStencilWriteMask(0x00)
			render.SetStencilCompareFunction(STENCIL_EQUAL)
			render.SetStencilPassOperation(STENCIL_KEEP)

			render.SetColorModulation(0.85, 0.85, 0.85)
			cam.IgnoreZ(xray:GetBool())
			self:DrawModel(transparentFlags)
			cam.IgnoreZ(false)
			render.SetColorModulation(1, 1, 1)

			render.SetStencilEnable(false)
		end
	end
end

-- We want these entities to move
local noShadowList = {
	ent_peplus = true
}

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
			-- Entities without a shadow don't update immediately (prop_effect), so detect that and set our placement
			if entity:IsEffectActive(EF_NOSHADOW) and (not IsValid(entity:GetParent()) or noShadowList[entity:GetClass()]) then
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
		entity:SetupBones()
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
		local name = net.ReadString()                        -- Name
		local state = net.ReadTable()                        -- State
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
