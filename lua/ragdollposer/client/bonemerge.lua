---@class RagdollPoser.Bonemerge
local MGR = RagdollPoser.Bonemerge or {}

-- ---Return a table of bones, where odd number indices is the bonemergeEntity's bone,
-- ---and even indices is the parentEntity's bone that it will follow
-- ---@param bonemergeEntity Entity
-- ---@param parentEntity Entity
-- local function defaultMerge(bonemergeEntity, parentEntity)
-- 	local bones = {}
-- 	RagdollPoser.Entity:ExposeBones(bonemergeEntity)
-- 	RagdollPoser.Entity:ExposeBones(parentEntity)
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

local badEntities = {
	manipulate_bone = true,
	manipulate_flex = true,
}

---@param parentEntity Entity
---@return boolean
function MGR:VerifySpawned(parentEntity)
	local firstSpawned = parentEntity:GetNWBool("rgp_firstSpawned")
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
			if badEntities[class] then
				continue
			end

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

local parentRigidMatrix = Matrix()
local childRigidMatrix = Matrix()
local relativeRigidMatrix = Matrix()
local localScale = Vector()
local rigidForward = Vector()
local rigidRight = Vector()
local rigidUp = Vector()

local function scaleAlongAxis(scale, axis)
	return (scale * axis):Length()
end

local function setRigidMatrix(output, source)
	rigidForward:Set(source:GetForward())
	rigidRight:Set(source:GetRight())
	rigidUp:Set(source:GetUp())
	if rigidForward:LengthSqr() < 1e-12 or rigidRight:LengthSqr() < 1e-12 or rigidUp:LengthSqr() < 1e-12 then
		return false
	end

	rigidForward:Normalize()
	rigidRight:Normalize()
	rigidUp:Normalize()

	output:Identity()
	output:SetTranslation(source:GetTranslation())
	output:SetForward(rigidForward)
	output:SetRight(rigidRight)
	output:SetUp(rigidUp)
	return true
end

local function getIndependentManipulationScale(worldScale, parentScale, relativeAngles)
	local forwardScale = scaleAlongAxis(parentScale, relativeAngles:Forward())
	local rightScale = scaleAlongAxis(parentScale, relativeAngles:Right())
	local upScale = scaleAlongAxis(parentScale, relativeAngles:Up())

	localScale.x = worldScale.x / forwardScale
	localScale.y = worldScale.y / rightScale
	localScale.z = worldScale.z / upScale
	return localScale
end

---@type table<string, fun(b: Entity, p: Entity, bone: integer): integer>
local parentBoneMap = {
	ent_advbonemerge = function(bonemergeEntity, parentEntity, bone)
		if bonemergeEntity.AdvBone_BoneInfo then
			local info = bonemergeEntity.AdvBone_BoneInfo[bone]
			return info and info.parent and parentEntity:LookupBone(info.parent)
		end
	end,
	ent_composite = function(bonemergeEntity, parentEntity, bone)
		local parentBone = bonemergeEntity:GetParentAttachment()
		if parentBone ~= 0 then
			return parentBone
		end
		return parentEntity:LookupBone(bonemergeEntity:GetBoneName(bone))
	end,
}

---@type table<string, fun(bonemergeEntity: Entity, parentEntity: Entity, bone: integer, parentBone: integer, output: VMatrix): integer>
local sendTransformMap = {
	ent_advbonemerge = function(bonemergeEntity, parentEntity, bone, parentBone, output)
		local childMatrices = RagdollPoser.Entity:GetMatrices(bonemergeEntity)
		local parentMatrices = RagdollPoser.Entity:GetMatrices(parentEntity)

		local parentMatrix = parentMatrices and parentMatrices[parentBone + 1]
		local childMatrix = childMatrices and childMatrices[bone + 1]
		if not parentMatrix or not childMatrix then
			output:Identity()
			return
		end

		local parentInverse = parentMatrix:GetInverse()
		if not parentInverse then
			RagdollPoser.Log("Cannot build bonemerge pose for ", bonemergeEntity, ": parent bone matrix is singular")
			output:Identity()
			return
		end

		if not setRigidMatrix(parentRigidMatrix, parentMatrix) or not setRigidMatrix(childRigidMatrix, childMatrix) then
			RagdollPoser.Log("Cannot build bonemerge pose for ", bonemergeEntity, ": bone rotation basis is degenerate")
			output:Identity()
			return
		end

		local relativeMatrix = parentInverse * childMatrix
		relativeRigidMatrix:Set(parentRigidMatrix:GetInverseTR() * childRigidMatrix)
		local relativeAngles = relativeRigidMatrix:GetAngles()

		output:Identity()
		output:SetTranslation(relativeMatrix:GetTranslation())
		output:SetAngles(relativeAngles)
		output:SetScale(
			getIndependentManipulationScale(childMatrix:GetScale(), parentMatrix:GetScale(), relativeAngles)
		)
	end,
	ent_composite = function(bonemergeEntity, parentEntity, bone, parentBone, output)
		local bmMatrices = RagdollPoser.Entity:GetMatrices(bonemergeEntity)
		local pMatrices = RagdollPoser.Entity:GetMatrices(parentEntity)

		if bonemergeEntity:GetBoneParent(bone) == -1 then
			local currentMatrix = Matrix()
			currentMatrix:Set(bmMatrices[bone + 1])
			currentMatrix:SetScale(RagdollPoser.Constants.VECTOR_ONE)

			local currentParentTransform = Matrix()
			currentParentTransform:Set(pMatrices[parentBone + 1])
			currentParentTransform:SetScale(RagdollPoser.Constants.VECTOR_ONE)

			local currentLocal = currentParentTransform:GetInverse() * currentMatrix

			local pastMatrix = bonemergeEntity:GetBoneMatrix(bone)
			pastMatrix:SetScale(RagdollPoser.Constants.VECTOR_ONE)

			local pastParentTransform = parentEntity:GetBoneMatrix(parentBone)
			pastParentTransform:SetScale(RagdollPoser.Constants.VECTOR_ONE)

			local pastLocal = pastParentTransform:GetInverse() * pastMatrix

			-- Get the difference between the new offset and current offset
			local delta = currentLocal * pastLocal:GetInverse()
			local existingLocal = Matrix()
			existingLocal:Translate(bonemergeEntity:GetLocalPos())
			existingLocal:Rotate(bonemergeEntity:GetLocalAngles())

			local finalLocal = delta * existingLocal

			output:Identity()
			output:Set(finalLocal)
			output:SetScale(currentMatrix:GetScale())
		else
			local currentMatrix = bmMatrices[bone + 1]
			output:Identity()
			local client = RagdollPoser.Entity:GetClientFromEntity(bonemergeEntity)
			RagdollPoser.Helpers.GetNonPhysicalBonePose(client, bone, output)
			output:SetScale(currentMatrix:GetScale())
		end
	end,
	ent_bonemerged = function(bonemergeEntity, parentEntity, bone, parentBone, output)
		local bmMatrices = RagdollPoser.Entity:GetMatrices(bonemergeEntity)
		local pmMatrices = RagdollPoser.Entity:GetMatrices(parentEntity)
		local currentMatrix = bmMatrices and bmMatrices[bone + 1]
		local parentMatrix = pmMatrices and pmMatrices[parentBone + 1]

		if not currentMatrix or not parentMatrix then
			output:Identity()
			return
		end

		local localMatrix = parentMatrix:GetInverse() * currentMatrix


		output:Identity()
		output:SetScale(localMatrix:GetScale())
	end
}

---@type table<string, fun(bonemergeEntity: Entity, parentEntity: Entity, bone: integer, output: VMatrix)>
local transformOriginMap = {
	ent_advbonemerge = function(bonemergeEntity, parentEntity, bone, output)
		output:Identity()
		local parentBone = bonemergeEntity:GetBoneParent(bone)
		local bmMatrices = RagdollPoser.Entity:GetMatrices(bonemergeEntity)
		if parentBone >= 0 then
			-- 1. Get transforms
			local currentTransform = Matrix()
			currentTransform:Set(bmMatrices[bone + 1])
			currentTransform:SetScale(RagdollPoser.Constants.VECTOR_ONE)

			local currentParentTransform = Matrix()
			currentParentTransform:Set(bmMatrices[parentBone + 1])
			currentParentTransform:SetScale(RagdollPoser.Constants.VECTOR_ONE)

			local currentLocal = currentParentTransform:GetInverse() * currentTransform

			local pastTransform = bonemergeEntity:GetBoneMatrix(bone)
			pastTransform:SetScale(RagdollPoser.Constants.VECTOR_ONE)

			local pastParentTransform = bonemergeEntity:GetBoneMatrix(parentBone)
			pastParentTransform:SetScale(RagdollPoser.Constants.VECTOR_ONE)

			local pastLocal = pastParentTransform:GetInverse() * pastTransform

			-- 2. Get existing manipulation
			local existingPos = bonemergeEntity:GetManipulateBonePosition(bone)
			local existingAng = bonemergeEntity:GetManipulateBoneAngles(bone)

			-- 3. Position: ManipulateBonePosition is purely in parentBone's space
			-- Since localPos = bindPos + ManipulateBonePosition, and bindPos never changes:
			-- currentLocalPos - pastLocalPos == newManipPos - existingPos
			local posDelta = currentLocal:GetTranslation() - pastLocal:GetTranslation()
			local newManipPos = existingPos + posDelta

			-- 4. Rotation: ManipulateBoneAngles is in the bone's bind space (localAng = bindAng * ManipulateBoneAngles)
			-- First find bindAng from pastLocal and existingAng:
			local existingRot = Matrix()
			existingRot:SetAngles(existingAng)

			local pastRot = Matrix()
			pastRot:SetAngles(pastLocal:GetAngles())

			local bindRot = pastRot * existingRot:GetInverse()

			-- Now solve bindRot * newManipRot = currentRot:
			local currentRot = Matrix()
			currentRot:SetAngles(currentLocal:GetAngles())

			local newManipRot = bindRot:GetInverse() * currentRot

			output:Identity()
			output:SetTranslation(newManipPos)
			output:SetAngles(newManipRot:GetAngles())
		else
			-- if the bone we're doing origin with doesn't have a parent bone, then we use the parent entity's origin
			-- Steps for preserving origin
			-- 1. Get our current parent and bone matrix and calculate their local offset
			-- 2. Get our past parent and bone matrix and calculate their local offset
			-- 3. Calculate delta between local offsets, also calculate delta between past parent and current parent
			-- 4. Apply deltas to the current bone manipulate angles
			local parentClient = RagdollPoser.Entity:GetClientFromEntity(parentEntity)

			local currentTransform = Matrix()
			currentTransform:Set(bmMatrices[bone + 1])
			currentTransform:SetScale(RagdollPoser.Constants.VECTOR_ONE)

			local currentParentTransform = Matrix()
			currentParentTransform:Set(parentClient:GetBoneMatrix(0))
			currentParentTransform:SetScale(RagdollPoser.Constants.VECTOR_ONE)

			local currentLocal = currentParentTransform:GetInverse() * currentTransform

			local pastTransform = bonemergeEntity:GetBoneMatrix(bone)
			pastTransform:SetScale(RagdollPoser.Constants.VECTOR_ONE)

			local pastParentTransform = parentEntity:GetBoneMatrix(0)
			pastParentTransform:SetScale(RagdollPoser.Constants.VECTOR_ONE)

			local pastLocal = pastParentTransform:GetInverse() * pastTransform
			local parentDelta = currentParentTransform * pastParentTransform:GetInverse()

			-- Get the difference between the new offset and current offset
			local delta = currentLocal:GetInverse() * pastLocal

			local parentMatrix = parentEntity:GetBoneMatrix(0)
			local childMatrix = bmMatrices and bmMatrices[bone + 1]
			if not parentMatrix or not childMatrix then
				output:Identity()
				return
			end

			output:Identity()
			output:Translate(childMatrix:GetTranslation() - parentMatrix:GetTranslation())
			-- First, if we have rotated our parent, rotate it first
			output:Rotate(parentDelta:GetAngles())
			-- Then get the bone manipulate angles
			output:Rotate(bonemergeEntity:GetManipulateBoneAngles(bone))
			-- and apply our deltas
			output:Rotate(delta:GetInverse():GetAngles())
			output:SetScale(childMatrix:GetScale())
		end
	end,
	ent_composite = function(bonemergeEntity, parentEntity, bone, output)
		output:Identity()
	end,
}


---@param bonemergeEntity Entity
---@param parentEntity Entity
---@param bone integer
function MGR:GetParentBone(bonemergeEntity, parentEntity, bone)
	local class = bonemergeEntity:GetClass()
	local func = parentBoneMap[class]
	local parentBone = parentEntity:LookupBone(bonemergeEntity:GetBoneName(bone))
	if func then
		parentBone = func(bonemergeEntity, parentEntity, bone) or parentBone
	end
	return parentBone
end

---@param bonemergeEntity Entity
---@param bone integer
---@param output VMatrix
function MGR:GetBonemergePose(bonemergeEntity, bone, output)
	-- client entity bone matrices are represented in world space, but we're interested in their offset from the parent entity that they are representing
	-- so let's just get current offsets from the bonemergeEntity and parentEntity

	local parentEntity = bonemergeEntity:GetParent()
	if not IsValid(parentEntity) then
		output:Identity()
		return
	end

	local class = bonemergeEntity:GetClass()
	local boneName = bonemergeEntity:GetBoneName(bone)

	local parentBoneGetter = parentBoneMap[class]
	local parentBone = parentEntity:LookupBone(boneName)
	if parentBoneGetter then
		parentBone = parentBoneGetter(bonemergeEntity, parentEntity, bone)
	end
	local transformer = sendTransformMap[class]
	if parentBone and transformer then
		transformer(bonemergeEntity, parentEntity, bone, parentBone, output)
	else
		-- Reset bone matrix back to identity.
		output:Identity()
		local originFunc = transformOriginMap[class]
		if originFunc then
			originFunc(bonemergeEntity, parentEntity, bone, output)
		end
	end
end

function MGR:IsBonemergeEntity(entity)
	return bonemergeClasses[entity:GetClass()]
end

RagdollPoser.Bonemerge = MGR
