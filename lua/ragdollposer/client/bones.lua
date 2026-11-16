---[CLIENT]
---
---Tracks the bone type for all entities that have been spawned
---
---@class RagdollPoser.Bones
local MGR = RagdollPoser.Bones or {}

---@alias BoneType integer
MGR.BoneType = {
	Physics = 0,
	Manipulate = 1,
	Procedural = 2,
	Jiggle = 3,
}

---@type {[string]: BoneType[]}
MGR.ModelBones = MGR.ModelBones or {}

---@param entity Entity
---@param bone integer
---@return BoneType
function MGR:GetBoneType(entity, bone)
	local model = entity:GetModel()
	return self.ModelBones[model][bone]
end

---@param ent Entity
---@param bone integer
---@return boolean
local function isPhysBone(ent, bone)
	return RagdollPoser.Helpers.BoneToPhysBone(ent, bone) ~= -1
end

---@param entity Entity
---@param model string?
function MGR:ReportModel(entity, model)
	model = model or entity:GetModel()
	if model and not self.ModelBones[model] then
		---@type BoneType[]
		local boneTypes = {}
		RagdollPoser.Entity:ExposeBones(entity)

		for b = 0, entity:GetBoneCount() - 1 do
			local isPhys = isPhysBone(entity, b)
			if isPhys then
				boneTypes[b] = MGR.BoneType.Physics
			elseif entity:BoneHasFlag(b, BONE_ALWAYS_PROCEDURAL) then
				boneTypes[b] = MGR.BoneType.Procedural
			else
				boneTypes[b] = MGR.BoneType.Manipulate
			end
		end
		self.ModelBones[model] = boneTypes
	end
end

RagdollPoser.Bones = MGR
