--- [CLIENT]
---
--- This client module gets the world-space matrices for the selected entity and converts them to a compatible
--- space for the given entity's class. Then it handles sending the transforms over.
---
--- Each class transformer function has its own methods for handling matrix data. It performs the computations
--- to get entities to the correct space. This agrees with our restriction to keep calculations entirely on
--- the client
---
--- There are three known spaces:
--- - World-space (Ragdolls, physics props): Entities that you can immediately move with the physgun
--- - Bone local space (ManipulateBone*): Bonemerged entities
--- - Entity local space (Entity:SetLocalPos): Parented entities
---
--- Gotchas:
--- - Try not to mutate the main matrices if they will be used for descendant bones
---
---@class RagdollPoser.ClientTransformer
local MGR = RagdollPoser.ClientTransformer or {}

---@alias EntitySendFunction fun(entity: Entity, client: ClientEntity, bones: integer[], matrices: VMatrix[])

---Bone matrices and entity's angles aren't consistent with each other
---so we need to correct this
---@param entity Entity
---@param bone integer
---@param matrix VMatrix
local function fixAngleOffset(entity, bone, matrix)
	local m1 = Matrix()
	m1:Rotate(entity:GetAngles())
	local m2 = Matrix()
	m2:Rotate(entity:GetBoneMatrix(bone):GetAngles())
	local offset = m2:GetTransposed() * m1
	local trace = offset:GetField(1, 1) + offset:GetField(2, 2) + offset:GetField(3, 3)
	local difference = math.acos(math.Clamp((trace - 1) * 0.5, -1, 1))
	if difference >= 1e-6 then
		local rotation = matrix * offset
		matrix:SetAngles(rotation:GetAngles())
	end
end

local function genericManipulate() end

local IDENTITY_MATRIX = Matrix()
IDENTITY_MATRIX:Identity()
local boneMatrix = Matrix()
boneMatrix:Identity()

function MGR:RestoreDefaults()
	---Entity classes that map to a function that does the transforming
	---@type table<string, EntitySendFunction>
	self.EntityMap = {
		prop_ragdoll = function(entity, client, bones, matrices)
			for _, b in ipairs(bones) do
				net.WriteUInt(b, RagdollPoser.Constants.MAX_BONE_BITS)
				local matrix = matrices[b + 1]
				local physbone = RagdollPoser.Helpers.BoneToPhysBone(entity, b)
				if physbone >= 0 then
					-- Send world transforms and everything
					net.WriteMatrix(matrix)
				else
					if isBonemerge then
						RagdollPoser.Bonemerge:GetBonemergePose(entity, b, boneMatrix)
					else
						RagdollPoser.Helpers.GetNonPhysicalBonePose(client, b, boneMatrix)
						boneMatrix:SetScale(matrix:GetScale())
					end
					net.WriteMatrix(boneMatrix)
				end
			end
		end,
		prop_physics = function(entity, client, bones, matrices)
			for _, b in ipairs(bones) do
				net.WriteUInt(b, RagdollPoser.Constants.MAX_BONE_BITS)
				local matrix = matrices[b + 1]

				local physbone = RagdollPoser.Helpers.BoneToPhysBone(entity, b)
				if physbone >= 0 then
					-- Send world transforms and everything
					fixAngleOffset(entity, b, matrix)
					net.WriteMatrix(matrix)
				else
					RagdollPoser.Helpers.GetNonPhysicalBonePose(client, b, boneMatrix)
					boneMatrix:SetScale(matrix:GetScale())
					net.WriteMatrix(boneMatrix)
				end
			end
		end,
		prop_dynamic = function(entity, client, bones, matrices)
			local parent = entity:GetParent()
			local clientParent = IsValid(parent) and RagdollPoser.Entity:GetClientFromEntity(parent)
			for _, b in ipairs(bones) do
				net.WriteUInt(b, RagdollPoser.Constants.MAX_BONE_BITS)
				local matrix = matrices[b + 1]

				if b == 0 then
					boneMatrix:Set(matrix)
					if IsValid(clientParent) then
						-- Steps
						-- 1. Get current local transform from its current parent.
						-- 2. Get past current local transform from its past parent
						-- 3. Get offset between current and past locals.
						-- 4. Apply offset to existing GetLocalPos / LocalAng states

						local currentMatrix = Matrix()
						currentMatrix:Set(matrix)
						currentMatrix:SetScale(RagdollPoser.Constants.VECTOR_ONE)

						local currentParentTransform = Matrix()
						currentParentTransform:Translate(clientParent:GetPos())
						currentParentTransform:Rotate(clientParent:GetAngles())

						local currentLocal = currentParentTransform:GetInverse() * currentMatrix

						local pastMatrix = entity:GetBoneMatrix(0)
						pastMatrix:SetScale(RagdollPoser.Constants.VECTOR_ONE)

						local pastParentTransform = Matrix()
						pastParentTransform:Translate(parent:GetPos())
						pastParentTransform:Rotate(parent:GetAngles())

						local pastLocal = pastParentTransform:GetInverse() * pastMatrix

						local existingLocal = Matrix()
						existingLocal:Translate(entity:GetLocalPos())
						existingLocal:Rotate(entity:GetLocalAngles())

						-- Get the difference between the new offset and current offset
						local delta = currentLocal * pastLocal:GetInverse()

						-- TODO: Do scaling for effect props
						local finalLocal = delta * existingLocal
						boneMatrix:Identity()
						boneMatrix:Translate(finalLocal:GetTranslation())
						boneMatrix:Rotate(finalLocal:GetAngles())
					end

					net.WriteMatrix(boneMatrix)
				else
					RagdollPoser.Helpers.GetNonPhysicalBonePose(client, b, boneMatrix)
					boneMatrix:SetScale(matrix:GetScale())
					net.WriteMatrix(boneMatrix)
				end
			end
		end,
		prop_animated = function(entity, client, bones, matrices)
			local baseline = RagdollPoser.Gizmo._transformBaseline[client]
			-- FIXME: Animated Props jitter when I have this enabled. Probably cause of SetupBones?
			for _, b in ipairs(bones) do
				net.WriteUInt(b, RagdollPoser.Constants.MAX_BONE_BITS)
				local matrix = matrices[b + 1]

				if b == 0 then
					local rootMatrix = entity:GetBoneMatrix(0)
					rootMatrix:SetScale(RagdollPoser.Constants.VECTOR_ONE)

					local entityTransform = Matrix()
					entityTransform:Translate(entity:GetPos())
					entityTransform:Rotate(entity:GetAngles())
					-- fixAngleOffset(entity, b, entityBoneTransform)

					local offset = rootMatrix:GetInverse() * entityTransform
					boneMatrix:Set(matrix * offset)
					net.WriteMatrix(boneMatrix)
				else
					-- local baseMatrix = entity:GetBoneMatrix(b)
					local baseMatrix = baseline[b + 1]
					local p = client:GetBoneParent(b)

					-- First, calculate the offset from itself
					local manip
					if p then
						-- local parentBase = entity:GetBoneMatrix(p)
						local parentBase = baseline[p + 1]
						local parentCurrent = matrices[p + 1]

						local parentOffset = parentBase:GetInverse() * baseMatrix
						manip = parentOffset:GetInverse() * (parentCurrent:GetInverse() * matrix)
					else
						manip = baseMatrix:GetInverse() * matrix
					end

					-- Then apply the offset on the existing manipulate bone
					boneMatrix:Identity()
					boneMatrix:Translate(entity:GetManipulateBonePosition(b))
					boneMatrix:Rotate(entity:GetManipulateBoneAngles(b))
					boneMatrix:Scale(entity:GetManipulateBoneScale(b))

					net.WriteMatrix(boneMatrix * manip)
				end
			end
		end,
		prop_effect = function(entity, client, bones, matrices)
			for _, b in ipairs(bones) do
				net.WriteUInt(b, RagdollPoser.Constants.MAX_BONE_BITS)
				local matrix = matrices[b + 1]

				local physbone = RagdollPoser.Helpers.BoneToPhysBone(entity, b)
				if physbone >= 0 then
					-- Send world transforms and everything
					fixAngleOffset(entity, b, matrix)
					net.WriteMatrix(matrix)
				else
					RagdollPoser.Helpers.GetNonPhysicalBonePose(client, b, boneMatrix)
					boneMatrix:SetScale(matrix:GetScale())
					net.WriteMatrix(boneMatrix)
				end
			end
		end,
		ent_advbonemerge = function(entity, client, bones, matrices)
			for _, b in ipairs(bones) do
				net.WriteUInt(b, RagdollPoser.Constants.MAX_BONE_BITS)

				RagdollPoser.Bonemerge:GetBonemergePose(entity, b, boneMatrix)
				net.WriteMatrix(boneMatrix)
			end
		end,
		ent_composite = function(entity, client, bones, matrices)
			for _, b in ipairs(bones) do
				net.WriteUInt(b, RagdollPoser.Constants.MAX_BONE_BITS)

				RagdollPoser.Bonemerge:GetBonemergePose(entity, b, boneMatrix)
				net.WriteMatrix(boneMatrix)
			end
		end,
		ent_bonemerged = function(entity, client, bones, matrices)
			for _, b in ipairs(bones) do
				net.WriteUInt(b, RagdollPoser.Constants.MAX_BONE_BITS)

				RagdollPoser.Bonemerge:GetBonemergePose(entity, b, boneMatrix)
				net.WriteMatrix(boneMatrix)
			end
		end,
	}
end

local warningColor = Color(255, 255, 0)
---@param class string The entity class to transform
---@param transformFunction EntitySendFunction
---@param override boolean Override the existing transform function. For quick patches
function MGR:AddTransform(class, transformFunction, override)
	if self.EntityMap[class] and not override then
		MsgC(
			warningColor,
			"[Ragdoll Poser]: A transform function for ",
			class,
			" already exists. Pass `true` as the third argument of this function if you want to override the existing class"
		)
	end
	self.EntityMap[class] = transformFunction
end

local aliases = {
	hl_camera = "prop_physics",
	gmod_cameraprop = "prop_physics",
	phys_bonemerge = "ent_bonemerged",
	phys_bonemerge_parent = "ent_bonemerged",
}

function MGR:SendTransform(entity, bones)
	local class = entity:GetClass()
	class = aliases[class] or class
	if string.find(class, "npc_") then
		class = "prop_animated"
	end
	if string.find(class, "weapon_") then
		class = "ent_bonemerged"
	end

	local func = self.EntityMap[class]
	if func then
		IDENTITY_MATRIX:Identity()
		boneMatrix = Matrix()

		local client = RagdollPoser.Entity:GetClientFromEntity(entity)
		RagdollPoser.Entity:ExposeBones(entity)
		RagdollPoser.Entity:ExposeBones(client)
		net.WriteEntity(entity)
		local matrices = RagdollPoser.Entity:GetMatrices(entity)
		local count = #bones
		net.WriteUInt(count, RagdollPoser.Constants.MAX_BONE_BITS)
		func(entity, client, bones, matrices)
	end
end

RagdollPoser.ClientTransformer = MGR

MGR:RestoreDefaults()
