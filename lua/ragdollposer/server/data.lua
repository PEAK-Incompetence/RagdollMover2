-- Store player info

---[SERVER]
---
---Receive pose matrices from the client to influence the serverside pose
---
---This also receives other locks and IK data for duplicator support
---
---Server constraints should be identical to client constraints
---
---@class RagdollPoser.Data
---@field Players table<Player, PlayerData>
local MGR = RagdollPoser.Data or {}

---@type table<Player, PlayerData>
MGR.Players = MGR.Players or {}

---@class PlayerData
---@field SelectedEntity Entity
---@field SelectedBone integer
---@field SelectedEntities Entity[]
---@field SelectedEntitySet table<Entity, Entity>
---@field Constraints table<Entity, NetworkedConstraint[]>
---@field Hovering boolean Prevent entity selection when hovering over the gizmo

RagdollPoser.Networking.SendAssemblyInfo = RagdollPoser.Networking.DefineSender("SendAssemblyInfo")
RagdollPoser.Networking.SendSubPoseResponse = RagdollPoser.Networking.DefineSender("SendSubPoseResponse")

local entityReferenceFields = { "target", "otherTarget" }

MGR.DuplicatorKey = "RagdollPoser"

local function prepareConstraintsForDuplication(constraints)
	local copiedConstraints = table.Copy(constraints or {})
	for _, constraint in ipairs(copiedConstraints) do
		local state = constraint.State
		if not istable(state) then
			continue
		end

		local references = {}
		for _, field in ipairs(entityReferenceFields) do
			local target = state[field]
			if IsValid(target) then
				references[field] = target:EntIndex()
			end
			state[field] = nil
		end

		if next(references) then
			constraint.__RagdollPoserEntityRefs = references
		end
	end

	return copiedConstraints
end

local function restoreDuplicatedConstraintReferences(constraints, entity, createdEntities)
	for _, constraint in ipairs(constraints) do
		local references = constraint.__RagdollPoserEntityRefs
		local state = constraint.State
		if references and istable(state) then
			for field, originalIndex in pairs(references) do
				local target = createdEntities[originalIndex]
				if IsValid(target) then
					state[field] = target
				else
					state[field] = NULL
					RagdollPoser.Log(
						"Could not remap RagdollPoser constraint ",
						field,
						" reference ",
						originalIndex,
						" for ",
						entity
					)
				end
			end
			constraint.__RagdollPoserEntityRefs = nil
		end
	end
end

local function sendSubPose(len, ply)
	local entityCount = net.ReadUInt(RagdollPoser.Constants.MAX_EDICT_BITS)

	for _ = 1, entityCount do
		local entity = net.ReadEntity()
		local matrixCount = net.ReadUInt(RagdollPoser.Constants.MAX_BONE_BITS)
		---@type VMatrix[]
		local matrices = {}
		local bones = {}
		local boneSet = {}
		for _ = 1, matrixCount do
			local b = net.ReadUInt(RagdollPoser.Constants.MAX_BONE_BITS)
			boneSet[b] = table.insert(bones, b)
			matrices[b] = net.ReadMatrix()
		end

		if IsValid(entity) then
			local class = entity:GetClass()
			RagdollPoser.ServerTransformer:DoTransform(class, entity, bones, boneSet, matrices)
		end
	end

	RagdollPoser.Networking.SendSubPoseResponse()
	net.Send(ply)
end
RagdollPoser.Networking.DefineReceiver("SendSubPose", sendSubPose)

local copiedEntities = {}
local function trackEntityDuplicators(entity)
	duplicator.ClearEntityModifier(entity, MGR.DuplicatorKey)
	duplicator.StoreEntityModifier(entity, MGR.DuplicatorKey, {})

	if not copiedEntities[entity] then
		entity.OnEntityCopyTableFinish = nil
		function entity:OnEntityCopyTableFinish(data)
			if IsValid(data.rgp_player) then
				RagdollPoser.Log("Do tool duplication for ", entity)
				local d = MGR.Players[self.rgp_player]
				data.EntityMods[MGR.DuplicatorKey] = prepareConstraintsForDuplication(d.Constraints[entity])
				data.rgp_player = nil
				self.rgp_player = nil
			elseif game.SinglePlayer() then
				RagdollPoser.Log("Do GMod save duplication for ", entity)
				local d = MGR.Players[Entity(1)]
				data.EntityMods[MGR.DuplicatorKey] = prepareConstraintsForDuplication(d.Constraints[entity])
			end
		end

		copiedEntities[entity] = true
	end
end

hook.Add("LoadGModSave", "RagdollPoser_ClearCopiedEntities", function(savedata, mapname, maptime)
	copiedEntities = {}
end)

hook.Remove("CanTool", "RagdollPoser_Data_TrackDuplicator")
hook.Add("CanTool", "RagdollPoser_Data_TrackDuplicator", function(ply, tr, toolname)
	if toolname == "duplicator" and ply:KeyDown(IN_ATTACK2) then
		local ent = tr.Entity
		if IsValid(ent) then
			RagdollPoser.Log(ply, " copied ", ent, " for duplication")
			ent.rgp_player = ply
		end
	end
end)

---@return NetworkedConstraint[]
local function readConstraints()
	local constraints = {}
	local constraintCount = net.ReadUInt(RagdollPoser.ConstraintBits)
	for i = 1, constraintCount do
		local type = net.ReadUInt(RagdollPoser.ConstraintTypeBits)
		local name = net.ReadString()
		local state = net.ReadTable()
		constraints[i] = {
			Type = type,
			Name = name,
			State = state,
		}
	end
	return constraints
end

local function updateConstraints(len, ply)
	local data = MGR.Players[ply]
	local playerConstraints = data.Constraints or {}

	---@type table<Entity, NetworkedConstraint[]>
	local entityConstraints = {}
	local entityCount = net.ReadUInt(RagdollPoser.Constants.MAX_EDICT_BITS)
	for _ = 1, entityCount do
		local entity = net.ReadEntity()
		entityConstraints[entity] = readConstraints()
		if IsValid(entity) then
			trackEntityDuplicators(entity)
		end
	end
	for entity, constraints in pairs(entityConstraints) do
		if IsValid(entity) then
			playerConstraints[entity] = constraints
		end
	end
	data.Constraints = playerConstraints
end
RagdollPoser.Networking.DefineReceiver("UpdateConstraints", updateConstraints)

local function clearConstraints(len, ply)
	local data = MGR.Players[ply]
	local playerConstraints = data.Constraints or {}

	local entity = net.ReadEntity()
	if IsValid(entity) then
		playerConstraints[entity] = nil
	end
	data.Constraints = playerConstraints
end
RagdollPoser.Networking.DefineReceiver("ClearConstraints", clearConstraints)

---@return NetworkedConstraint
local function readConstraint()
	local type = net.ReadUInt(RagdollPoser.ConstraintTypeBits)
	local name = net.ReadString()
	local state = net.ReadTable()
	return {
		Type = type,
		Name = name,
		State = state, ---@diagnostic disable-line
	}
end

local function updateConstraint(len, ply)
	local data = MGR.Players[ply]
	local playerConstraints = data.Constraints or {}

	local entity = net.ReadEntity()
	local index = net.ReadUInt(RagdollPoser.ConstraintBits)
	local constraint = readConstraint() ---@as NetworkedConstraint
	if IsValid(entity) then
		playerConstraints[entity][index] = constraint
		data.Constraints = playerConstraints
		trackEntityDuplicators(entity)
	end
end
RagdollPoser.Networking.DefineReceiver("UpdateConstraint", updateConstraint)

local function initializePlayer(pl)
	if not MGR.Players[pl] then
		local data = {
			SelectedEntity = NULL,
			SelectedBone = -1,
			SelectedEntities = {},
			SelectedEntitySet = {},
			Constraints = {},
			Hovering = false,
		}
		MGR.Players[pl] = data
		return data
	end
end

hook.Add("SetupMove", "RagdollPoser_ReportPlayerData", function(pl)
	initializePlayer(pl)
end)

hook.Add("PlayerDisconnected", "RagdollPoser_RemovePlayerData", function(pl)
	MGR.Players[pl] = nil
end)

---@param ply Player
---@param ent Entity
---@param data NetworkedConstraint[]
local function entityModifier(ply, ent, data)
	local d = MGR.Players[ply]
	if not d then
		d = initializePlayer(ply)
	end
	d.Constraints[ent] = data

	local previousPostEntityPaste = ent.PostEntityPaste
	ent.PostEntityPaste = function(self, pastePlayer, pastedEntity, createdEntities)
		restoreDuplicatedConstraintReferences(data, self, createdEntities)
		d.Constraints[self] = data
		duplicator.ClearEntityModifier(pastedEntity, MGR.DuplicatorKey)
		duplicator.StoreEntityModifier(pastedEntity, MGR.DuplicatorKey, prepareConstraintsForDuplication(data))
		if previousPostEntityPaste then
			previousPostEntityPaste(self, pastePlayer, pastedEntity, createdEntities)
		end
		self.PostEntityPaste = previousPostEntityPaste
	end
end
duplicator.RegisterEntityModifier(MGR.DuplicatorKey, entityModifier)

for _, pl in ipairs(player.GetAll()) do
	initializePlayer(pl)
end

---@param constraints NetworkedConstraint[]
local function writeConstraints(constraints)
	local count = #constraints
	net.WriteUInt(count, RagdollPoser.ConstraintBits)
	for i = 1, count do
		local constraint = constraints[i]
		-- Do backwards compatibility with old dupe data
		if isstring(constraint.Type) then
			constraint.Type = RagdollPoser.ConstraintTypes[constraint.Type]
		end

		net.WriteUInt(constraint.Type, RagdollPoser.ConstraintTypeBits)
		net.WriteString(constraint.Name)
		net.WriteTable(constraint.State)
	end
end

---@param pl Player
---@param entity Entity
---@param bone integer
---@param entities Entity[]
---@param constraints table<Entity, NetworkedConstraint[]>
function MGR:RefreshEntities(pl, entity, bone, entities, constraints)
	RagdollPoser.Log("refreshing", pl, entity, bone, entities)
	constraints = constraints or {}
	RagdollPoser.Networking.SendAssemblyInfo()
	net.WriteEntity(entity)
	net.WriteUInt(bone, RagdollPoser.Constants.MAX_BONE_BITS)
	net.WriteUInt(#entities, RagdollPoser.Constants.MAX_ENTITY_LIST_BITS)
	for i = 1, #entities do
		local e = entities[i]
		net.WriteEntity(e)
		local cs = constraints[e]
		net.WriteBool(cs ~= nil)
		if cs then
			writeConstraints(cs)
		end
	end
	net.Send(pl)
end

---@param entity Entity
function MGR.ValidateModelEntity(entity)
	-- Send only entities with a model
	return entity.GetModel and entity:GetModel()
end

---@param entity Entity
---@return Entity[] constrainedList Network-friendly constrained list
---@return table<Entity, Entity> constrainedTable Duplicator-friendly constrained list
function MGR.GetConstrainedEntities(entity)
	local constrainedTab = constraint.GetAllConstrainedEntities(entity)
	local constrainedList = {}
	for _, ent in pairs(constrainedTab or {}) do
		if MGR.ValidateModelEntity(ent) then
			table.insert(constrainedList, ent)
		end
	end
	-- Add prop_effect entities in here automatically
	if IsValid(entity.AttachedEntity) then
		constrainedList[#constrainedList + 1] = entity.AttachedEntity
		constrainedTab[entity.AttachedEntity] = entity.AttachedEntity
	end
	return constrainedList, constrainedTab
end

---@param ent Entity
local function constraintRemoved(ent)
	if ent:IsConstraint() then
		local ent1, ent2 = ent:GetConstrainedEntities()
		if not ent1 and not ent2 then
			return
		end
		for player, data in pairs(MGR.Players) do
			local targetEnt = data.SelectedEntity
			if targetEnt and (ent1 == targetEnt or ent2 == targetEnt) then
				timer.Simple(0, function()
					if IsValid(targetEnt) then
						local constrainedList, constrainedTab = MGR.GetConstrainedEntities(targetEnt)
						local bone = data.SelectedBone
						local constraints = data.Constraints or {}
						MGR:RefreshEntities(player, targetEnt, bone, constrainedList, constraints)
						MGR:Update(player, targetEnt, bone, constrainedList, constrainedTab)
					else
						MGR:RefreshEntities(player, NULL, 0, {}, {})
						MGR:Update(player, nil, nil, nil, nil)
					end
				end)
			end
		end
	end
end
hook.Add("EntityRemoved", "RagdollPoser_ConstraintRemoved", constraintRemoved)

local function entityRemoved(ent)
	local doUpdate = false
	local players = {}
	for player, info in pairs(MGR.Players) do
		if info.Constraints and info.Constraints[ent] then
			doUpdate = true
			info.Constraints[ent] = nil
			table.insert(players, player)
		end
	end
end
hook.Add("EntityRemoved", "RagdollPoser_EntityRemoved", entityRemoved)

function MGR:Update(pl, entity, bone, entities, constrainedEntities)
	local data = MGR.Players[pl] or {}

	if IsValid(data.SelectedEntity) then
		data.SelectedEntity:CPPISetOwner(pl)
		for _, e in ipairs(data.SelectedEntities) do
			e:CPPISetOwner(NULL)
		end
	end

	data.SelectedEntity = entity or NULL
	data.SelectedBone = bone or -1
	data.SelectedEntities = entities or {}
	data.SelectedEntitySet = constrainedEntities or {}

	if IsValid(entity) then
		entity:CPPISetOwner(pl)
		for _, e in ipairs(entities or {}) do
			e:CPPISetOwner(pl)
		end
	end

	MGR.Players[pl] = data
end

RagdollPoser.Networking.EntityPhysBoneCount = RagdollPoser.Networking.DefineSender("EntityPhysBoneCount")

---@param entity Entity
function MGR:UpdatePhysBoneCount(entity, count)
	RagdollPoser.Networking.EntityPhysBoneCount()
	net.WriteEntity(entity)
	net.WriteUInt(count, RagdollPoser.Constants.MAX_PHYSBONE_BITS)
	net.Broadcast()
end

local function updateHover(len, pl)
	local hovering = net.ReadBool()
	local data = MGR.Players[pl]
	if data then
		data.Hovering = hovering
	end
end
RagdollPoser.Networking.DefineReceiver("UpdateHovering", updateHover)

local function countPhysics(model)
	local modelInfo = util.GetModelInfo(model)
	local keyvalues = modelInfo and util.KeyValuesToTablePreserveOrder(modelInfo.KeyValues or "")
	if not keyvalues then
		return 0
	end

	local count = 0
	-- 32 is the max number of physics object we can have (index 0 .. 31)
	for i = 1, 32 do
		if keyvalues[i] and keyvalues[i].Key == "solid" then
			count = count + 1
		end
	end
	return count
end

local function sendPhysBoneCount(entity)
	timer.Simple(0, function()
		if IsValid(entity) and entity.GetModel and entity:GetModel() then
			-- Suppose we spawn an entity from the spawnmenu or any other means and we do some bonemerging
			-- These would be considered "firstSpawned"
			-- If we spawned this entity and we had manipulated them in the past with RagdollPoser, do not set this to true
			-- That way, constraints don't double up if we have a bonemerge constraint
			entity:SetNWBool(
				"rgp_firstSpawned",
				not (entity.EntityMods and entity.EntityMods[MGR.DuplicatorKey] ~= nil)
			)

			local count = countPhysics(entity:GetModel())
			MGR:UpdatePhysBoneCount(entity, count > 0 and count or 1)
		end
	end)
end
hook.Add("OnEntityCreated", "RagdollPoser_SendPhysBone", sendPhysBoneCount)

local function updateSelectedBone(len, ply)
	local data = MGR.Players[ply]
	local bone = net.ReadUInt(RagdollPoser.Constants.MAX_BONE_BITS)
	local entity = net.ReadEntity()

	if IsValid(entity) then
		data.SelectedEntity = entity
	end
	data.SelectedBone = bone
end
RagdollPoser.Networking.DefineReceiver("UpdateSelectedBone", updateSelectedBone)

function MGR:SetOffset(ply, offset)
	RagdollPoser.Networking.SetOffset()
	net.WriteVector(offset)
	net.Send(ply)
end

RagdollPoser.Networking.SetOffset = RagdollPoser.Networking.DefineSender("SetOffset")

RagdollPoser.Data = MGR
