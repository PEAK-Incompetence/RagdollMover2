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
---@field Constraints table<Entity, SerializedConstraint[]>

RagdollPoser.Networking.SendAssemblyInfo = RagdollPoser.Networking.DefineSender("SendAssemblyInfo")
RagdollPoser.Networking.SendSubPoseResponse = RagdollPoser.Networking.DefineSender("SendSubPoseResponse")

local function sendSubPose(len, ply)
	local entityCount = net.ReadUInt(13)

	for _ = 1, entityCount do
		local entity = net.ReadEntity()
		local matrixCount = net.ReadUInt(8)
		---@type VMatrix[]
		local matrices = {}
		local bones = {}
		for _ = 1, matrixCount do
			local b = net.ReadUInt(8)
			table.insert(bones, b)
			matrices[b] = net.ReadMatrix()
		end

		-- PrintTable(matrices)
		-- PrintTable(bones)

		for _, b in ipairs(bones) do
			local matrix = matrices[b]
			local physBone = RagdollPoser.Helpers.BoneToPhysBone(entity, b)
			local po = entity:GetPhysicsObjectNum(physBone)
			if RagdollPoser.Helpers.IsStaticProp(entity) then
				po = entity:GetPhysicsObject()
			end
			if matrix then
				if po then
					po:SetPos(matrix:GetTranslation())
					po:SetAngles(matrix:GetAngles())
					po:Wake()
					po:EnableMotion(false)
				else
					entity:ManipulateBonePosition(b, matrix:GetTranslation())
					entity:ManipulateBoneAngles(b, matrix:GetAngles())
				end
				entity:ManipulateBoneScale(b, matrix:GetScale())
			end
		end
	end

	RagdollPoser.Networking.SendSubPoseResponse()
	net.Send(ply)
end
RagdollPoser.Networking.DefineReceiver("SendSubPose", sendSubPose)

local function updateConstraints(len, ply)
	local data = MGR.Players[ply]
	local playerConstraints = data.Constraints or {}

	---@type table<Entity, SerializedConstraint[]>
	local entityConstraints = {}
	local count = net.ReadUInt(13)
	for _ = 1, count do
		local entity = net.ReadEntity()
		print(entity)
		entityConstraints[entity] = net.ReadTable(true)
	end
	for entity, constraints in pairs(entityConstraints) do
		playerConstraints[entity] = constraints
	end
	data.Constraints = playerConstraints
end
RagdollPoser.Networking.DefineReceiver("UpdateConstraints", updateConstraints)

local function updateConstraint(len, ply)
	local data = MGR.Players[ply]
	local playerConstraints = data.Constraints or {}

	local entity = net.ReadEntity()
	local index = net.ReadUInt(13)
	local constraint = net.ReadTable() ---@as SerializedConstraint
	playerConstraints[entity][index] = constraint
	data.Constraints = playerConstraints
end
RagdollPoser.Networking.DefineReceiver("UpdateConstraint", updateConstraint)

local function initializePlayer(pl)
	if not MGR.Players[pl] then
		MGR.Players[pl] = {
			SelectedEntity = NULL,
			SelectedBone = -1,
			SelectedEntities = {},
			SelectedEntitySet = {},
			Constraints = {},
		}
	end
end

hook.Add("SetupMove", "RagdollPoser_ReportPlayerData", function(pl)
	initializePlayer(pl)
end)

hook.Add("PlayerDisconnected", "RagdollPoser_RemovePlayerData", function(pl)
	MGR.Players[pl] = nil
end)

for _, pl in ipairs(player.GetAll()) do
	initializePlayer(pl)
end

---@param pl Player
---@param entity Entity
---@param bone integer
---@param entities Entity[]
---@param constraints table<Entity, SerializedConstraint[]>
function MGR.RefreshEntities(pl, entity, bone, entities, constraints)
	RagdollPoser.Log("refreshing", pl, entity, bone, entities)
	constraints = constraints or {}
	RagdollPoser.Networking.SendAssemblyInfo()
	net.WriteEntity(entity)
	net.WriteUInt(bone, 8)
	net.WriteUInt(#entities, 10)
	for i = 1, #entities do
		local e = entities[i]
		net.WriteEntity(e)
		local cs = constraints[e]
		net.WriteBool(cs ~= nil)
		if cs then
			net.WriteTable(cs, true)
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
	for _, ent in pairs(constrainedTab) do
		if MGR.ValidateModelEntity(ent) then
			table.insert(constrainedList, ent)
		end
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
						MGR.RefreshEntities(player, targetEnt, bone, constrainedList, constraints)
						MGR:Update(player, targetEnt, bone, constrainedList, constrainedTab)
					else
						MGR.RefreshEntities(player, NULL, 0, {}, {})
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
		if info.Constraints[ent] then
			doUpdate = true
			info.Constraints[ent] = nil
			table.insert(players, player)
		end
	end
end
hook.Add("EntityRemoved", "RagdollPoser_EntityRemoved", entityRemoved)

function MGR:Update(pl, entity, bone, entities, constrainedEntities)
	-- TODO: Expand this maybe, also make it use table fields if we don't plan to use this often
	local data = MGR.Players[pl] or {}
	data.SelectedEntity = entity
	data.SelectedBone = bone
	data.SelectedEntities = entities
	data.SelectedEntitySet = constrainedEntities
	MGR.Players[pl] = data
end

RagdollPoser.Networking.EntityPhysBoneCount = RagdollPoser.Networking.DefineSender("EntityPhysBoneCount")

---@param entity Entity
function MGR.UpdatePhysBoneCount(entity)
	RagdollPoser.Networking.EntityPhysBoneCount()
	-- print("entityphysbonecount send", entity, entity:GetPhysicsObjectCount())
	net.WriteEntity(entity)
	net.WriteUInt(entity:GetPhysicsObjectCount(), 5)
	net.Broadcast()
end

local function sendPhysBoneCount(entity)
	timer.Simple(0, function()
		if IsValid(entity) and entity.GetModel and entity:GetModel() and entity:GetPhysicsObjectCount() > 0 then
			MGR.UpdatePhysBoneCount(entity)
		end
	end)
end
hook.Add("OnEntityCreated", "RagdollPoser_SendPhysBone", sendPhysBoneCount)

local function updateSelectedBone(len, ply)
	local data = MGR.Players[ply]
	local bone = net.ReadUInt(8)
	local entity = net.ReadEntity()

	if IsValid(entity) then
		data.SelectedEntity = entity
	end
	data.SelectedBone = bone
end
RagdollPoser.Networking.DefineReceiver("UpdateSelectedBone", updateSelectedBone)

RagdollPoser.Data = MGR
