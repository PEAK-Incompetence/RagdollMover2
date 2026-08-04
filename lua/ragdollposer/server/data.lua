-- Store player info

RagdollPoser.Data = RagdollPoser.Data or {
	Players = {},
}

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
	if not RagdollPoser.Data.Players[pl] then
		RagdollPoser.Data.Players[pl] = {}
	end
end)

hook.Add("PlayerDisconnected", "RagdollPoser_RemovePlayerData", function(pl)
	RagdollPoser.Data.Players[pl] = nil
end)

for _, pl in ipairs(player.GetAll()) do
	if not RagdollPoser.Data.Players[pl] then
		RagdollPoser.Data.Players[pl] = {}
	end
end
