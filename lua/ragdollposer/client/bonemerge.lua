---@class RagdollPoser.Bonemerge
local MGR = RagdollPoser.Bonemerge or {}

-- ---Return a table of bones, where odd number indices is the bonemergeEntity's bone,
-- ---and even indices is the parentEntity's bone that it will follow
-- ---@param bonemergeEntity Entity
-- ---@param parentEntity Entity
-- local function defaultMerge(bonemergeEntity, parentEntity)
-- 	local bones = {}
-- 	RagdollPoser.Entity.ExposeBones(bonemergeEntity)
-- 	RagdollPoser.Entity.ExposeBones(parentEntity)
-- 	for i = 0, bonemergeEntity:GetBoneCount() - 1 do
-- 		local boneName = bonemergeEntity:GetBoneName(i)
-- 		if boneName ~= "__INVALIDBONE__" then
-- 			continue
-- 		end
-- 		local parentBone = parentEntity:LookupBone(boneName)
-- 		if parentBone then
-- 			bones[#bones + 1] = i
-- 			bones[#bones + 1] = parentBone
-- 		end
-- 	end
-- 	if not bones[1] then
-- 		bones = { 0, 0 }
-- 	end
-- 	return bones
-- end

-- local function advMerge(bonemergeEntity, parentEntity)
-- 	local boneInfo = bonemergeEntity.AdvBone_BoneInfo
-- 	if not boneInfo then
-- 		return { 0, 0 }
-- 	end
-- 	local bones = {}

-- 	for id, info in pairs(boneInfo) do
-- 		bones[#bones + 1] = id
-- 		bones[#bones + 1] = info.parent
-- 	end
-- 	return bones
-- end

--- Store some functions here that allow us to find the bone that we want to attach to
local bonemergeClasses = {
	ent_advbonemerge = true,
	ent_bonemerged = true,
	ent_composite = true,
}

local niceBonemergeNames = {
	ent_advbonemerge = "Advanced Bonemerge",
	ent_bonemerged = "Bonemerge",
	ent_composite = "Composite Bonemerge",
}

---@param parentEntity Entity
---@return boolean
function MGR:VerifySpawned(parentEntity)
	local firstSpawned = parentEntity:GetNWBool("rgp_firstSpawned")
	print(firstSpawned, parentEntity)
	return firstSpawned ~= nil and firstSpawned
end

---If the entity we spawned was spawned from the spawnmenu or any other nonduplicator means, selecting them will
---automatically set constraints
---I want to explore using constraints here, because one can disable constraints and have bonemerged entities move
---on their own with respect to the world; that's something that's never done at all
---@param entity Entity
function MGR:AddParentConstraints(entity)
	if self:VerifySpawned(entity) then
		entity:SetNWBool("rgp_firstSpawned", false)

		---@type ConstraintBatch[]
		local constraintBatch = {}
		for _, child in ipairs(entity:GetChildren()) do
			local class = child:GetClass()

			local name =
				Format("%s: %s", RagdollPoser.Helpers.GetModelNameNice(child), niceBonemergeNames[class] or class)

			if bonemergeClasses[class] then
				constraintBatch[#constraintBatch + 1] = {
					state = {
						bone = 0,
						enabled = true,
						influence = 1,
						name = name,
						target = entity,
						otherTarget = child,
						key = BUTTON_CODE_INVALID,
					},
					name = name,
					type = "bonemerge",
				}
			else
				-- TODO: For multiparent tools, find the bone that it targets
				constraintBatch[#constraintBatch + 1] = {
					state = {
						bone = 0,
						otherBone = 0,
						enabled = true,
						influence = 1,
						name = name,
						target = entity,
						otherTarget = child,
						key = BUTTON_CODE_INVALID,
					},
					name = name,
					type = "lockbone",
				}
			end
		end
		RagdollPoser.Constraints:PushBatch(entity, constraintBatch)
	end
end

local VECTOR_ONE = Vector(1, 1, 1)

---@param bonemergeEntity Entity
---@param bone integer
---@param output VMatrix
function MGR:GetBonemergePose(bonemergeEntity, bone, output)
	-- client entity bone matrices are represented in world space, but we're interested in their offset from the parent entity that they are representing
	-- so let's just get current offsets from the bonemergeEntity and parentEntity

	local childScaleMatrix = Matrix()
	local parentScaleMatrix = Matrix()
	local clientEntity = RagdollPoser.Entity.GetClientFromEntity(bonemergeEntity)
	local clientParentEntity = RagdollPoser.Entity.GetClientFromEntity(bonemergeEntity:GetParent())

	local boneName = clientEntity:GetBoneName(bone)
	local parentBone = clientParentEntity:LookupBone(boneName)
	if parentBone then
		-- TODO: Make scale matrices for a bonemerged entity work independently of its
		-- parent bone, regardless if bonemerge constraint is enabled or not
		local parentMatrix = clientParentEntity:GetBoneMatrix(parentBone)
		local childMatrix = clientEntity:GetBoneMatrix(bone)
		parentScaleMatrix:Identity()
		parentScaleMatrix:Rotate(parentMatrix:GetAngles())
		parentScaleMatrix:Translate(parentMatrix:GetTranslation())
		local localMatrix = parentMatrix:GetInverse() * childMatrix
		output:Set(localMatrix)
	else
		-- Reset bone matrix back to identity.
		output:Identity()
	end
end

function MGR:IsBonemergeEntity(entity)
	return bonemergeClasses[entity:GetClass()]
end

RagdollPoser.Bonemerge = MGR
