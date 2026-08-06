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
MGR.Players = RagdollPoser.Data.Players or {}

---@alias PlayerData {[1]: Entity, [2]: integer, [3]: Entity[], [4]: {[Entity]: Entity}}

---@type {[string]: {[integer]: integer}}
local boneToPhysMap = {}

---@param ent Entity Entity to translate bone
---@param bone integer Bone id
---@return integer physBone Physics object id
local function BoneToPhysBone(ent, bone)
	local model = ent:GetModel()
	if boneToPhysMap[model] and boneToPhysMap[model][bone] then
		return boneToPhysMap[model][bone]
	else
		boneToPhysMap[model] = boneToPhysMap[model] or {}
		for i = 0, ent:GetPhysicsObjectCount() - 1 do
			local b = ent:TranslatePhysBoneToBone(i)
			if bone == b then
				boneToPhysMap[model][b] = i
				return i
			end
		end
		boneToPhysMap[model][bone] = -1
		return -1
	end
end

RagdollPoser.Networking.SendAssemblyInfo = RagdollPoser.Networking.DefineSender("SendAssemblyInfo")
RagdollPoser.Networking.SendAssemblyInfo2 = RagdollPoser.Networking.DefineSender("SendAssemblyInfo2")

RagdollPoser.Networking.DefineReceiver("SendSubPose", function(len, ply)
	local entity = net.ReadEntity()
	local matrixCount = net.ReadUInt(8)
	---@type VMatrix[]
	local matrices = {}
	for i = 1, matrixCount do
		matrices[i - 1] = net.ReadMatrix()
	end

	for b = 0, entity:GetBoneCount() - 1 do
		local matrix = matrices[b]
		-- print(matrix)
		local physBone = BoneToPhysBone(entity, b)
		local po = entity:GetPhysicsObjectNum(physBone)
		if po and matrix then
			print(entity:GetBoneName(b))
			po:SetPos(matrix:GetTranslation())
			po:SetAngles(matrix:GetAngles())
			po:Wake()
			po:EnableMotion(false)
		end
	end
end)

RagdollPoser.Networking.DefineReceiver("SendSubPose2", function(len, ply)
	print("Get sub pose2")
end)

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
---@return Entity[]
---@return {[Entity]: Entity}
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

RagdollPoser.Data = MGR
