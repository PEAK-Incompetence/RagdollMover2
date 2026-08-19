-- Store player info

---[SERVER]
---
---Receive pose matrices from the client to influence the serverside pose
---
---This also receives other locks and IK data for duplicator support
---
---@class RagdollPoser.Data
local MGR = {}

---@type {[Player]: PlayerData}
MGR.Players = RagdollPoser.Data and RagdollPoser.Data.Players or {}

---@alias PlayerData {[1]: Entity, [2]: integer, [3]: Entity[], [4]: {[Entity]: Entity}}

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
			-- print(matrix)
			local physBone = RagdollPoser.Helpers.BoneToPhysBone(entity, b)
			local po = entity:GetPhysicsObjectNum(physBone)
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

hook.Add("SetupMove", "RagdollPoser_ReportPlayerData", function(pl)
	if not MGR.Players[pl] then
		MGR.Players[pl] = {}
	end
end)

hook.Add("PlayerDisconnected", "RagdollPoser_RemovePlayerData", function(pl)
	MGR.Players[pl] = nil
end)

for _, pl in ipairs(player.GetAll()) do
	if not MGR.Players[pl] then
		MGR.Players[pl] = {}
	end
end

---@param pl Player
---@param entity Entity
---@param bone integer
---@param entities Entity[]
function MGR.RefreshEntities(pl, entity, bone, entities)
	RagdollPoser.Log("refreshing", pl, entity, bone, entities)
	RagdollPoser.Networking.SendAssemblyInfo()
	net.WriteEntity(entity)
	net.WriteUInt(bone, 8)
	net.WriteUInt(#entities, 10)
	for i = 1, #entities do
		net.WriteEntity(entities[i])
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
---@return {[Entity]: Entity} constrainedTable Duplicator-friendly constrained list
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
		for player, data in pairs(RagdollPoser.Data.Players) do
			local targetEnt = data[1]
			if ent1 == targetEnt or ent2 == targetEnt then
				timer.Simple(0, function()
					local constrainedList, constrainedTab = RagdollPoser.Data.GetConstrainedEntities(targetEnt)
					RagdollPoser.Data.RefreshEntities(player, targetEnt, data[2], constrainedList)
					RagdollPoser.Data:Update(player, targetEnt, data[2], constrainedList, constrainedTab)
				end)
			end
		end
	end
end
hook.Add("EntityRemoved", "RagdollPoser_ConstraintRemoved", constraintRemoved)

function MGR:Update(pl, entity, bone, entities, constrainedEntities)
	-- TODO: Expand this maybe, also make it use table fields if we don't plan to use this often
	RagdollPoser.Data.Players[pl] = { entity, bone, entities, constrainedEntities }
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

RagdollPoser.Data = MGR
