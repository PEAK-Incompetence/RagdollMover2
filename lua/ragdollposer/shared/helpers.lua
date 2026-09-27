local MGR = {}

---Calculate the bone offsets with respect to the parent
---@source https://github.com/NO-LOAFING/AnimpropOverhaul/blob/a3a6268a5d57655611a8b8ed43dcf43051ecd93a/lua/entities/prop_animated.lua#L1889
---@param entity Entity Entity to obtain bone information
---@param child integer Child bone index
---@param defaultBonePose BonePoseInfo[]
---@return Vector positionOffset Position of child bone with respect to parent bone
---@return Angle angleOffset Angle of child bone with respect to parent bone
local function getBoneOffsetsOf(entity, child, defaultBonePose)
	local parent = entity:GetBoneParent(child)
	---@type VMatrix
	local cMatrix = entity:GetBoneMatrix(child)
	---@type VMatrix
	local pMatrix = entity:GetBoneMatrix(parent)

	if not cMatrix or not pMatrix or not defaultBonePose or #defaultBonePose == 0 then
		return vector_origin, angle_zero
	end

	local cAngles = cMatrix:GetAngles()

	local fPos, fAng = WorldToLocal(cMatrix:GetTranslation(), cAngles, pMatrix:GetTranslation(), pMatrix:GetAngles())
	local dPos = fPos - defaultBonePose[child + 1][3]

	local m = Matrix()
	m:Translate(defaultBonePose[parent + 1][1])
	m:Rotate(defaultBonePose[parent + 1][2])
	m:Rotate(fAng)

	local defaultAngle = defaultBonePose[child + 1][2]
	local _, dAng = WorldToLocal(m:GetTranslation(), m:GetAngles(), defaultBonePose[child + 1][1], defaultAngle)

	return dPos, dAng
end

---@type {[string]: {[integer]: integer}}
local boneToPhysMap = {}

---Try to manipulate the bone angles of the entity
---@source https://github.com/vlazed/animated-ragdoll-tool/blob/d64a89e56aafc4409f12b0c7340cd4dee52fdc52/lua/ragdollpuppeteer/lib/pose.lua#L273
---@param entity Entity The puppeteer to obtain nonphysical bone pose information
---@param bone integer Bone
---@param outputMatrix VMatrix Matrix to write values to
function MGR.GetNonPhysicalBonePose(entity, bone, outputMatrix)
	local defaultBonePose = RagdollPoser.Entity.GetDefaultPoseTreeFor(entity)

	if entity:GetBoneParent(bone) > -1 then
		local dPos, dAng = getBoneOffsetsOf(entity, bone, defaultBonePose)
		outputMatrix:SetTranslation(dPos)
		outputMatrix:SetAngles(dAng)
	else
		local bMatrix = entity:GetBoneMatrix(bone)
		local dPos, dAng = vector_origin, angle_zero
		if bMatrix then
			-- Get the position and angles of the bone with respect to the puppeteer systems
			local lPos, lAng =
				WorldToLocal(bMatrix:GetTranslation(), bMatrix:GetAngles(), entity:GetPos(), entity:GetAngles())

			-- ManipulateBonePosition delta
			dPos = lPos - defaultBonePose[bone + 1][1]
			-- ManipulateBoneAngles delta
			_, dAng = WorldToLocal(lPos, lAng, defaultBonePose[bone + 1][1], defaultBonePose[bone + 1][2])

			outputMatrix:SetTranslation(dPos)
			outputMatrix:SetAngles(dAng)
		end
	end
end

---@param ent Entity Entity to translate bone
---@param bone integer Bone id
---@return integer physBone Physics object id
function MGR.BoneToPhysBone(ent, bone)
	local model = ent:GetModel()
	if boneToPhysMap[model] and boneToPhysMap[model][bone] then
		return boneToPhysMap[model][bone]
	else
		boneToPhysMap[model] = boneToPhysMap[model] or {}
		local count = SERVER and ent:GetPhysicsObjectCount() or RagdollPoser.Entity.GetPhysBoneCount(ent)
		if CLIENT then
			-- On the frame that this is called, force the entity to
			-- show all hidden bones, like `weapon_bone`
			ent:SetupBones()
			ent:InvalidateBoneCache()
		end
		for i = 0, count - 1 do
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

local staticProps = {}
function MGR.IsStaticProp(entity)
	local model = entity:GetModel()
	local result = staticProps[model]
	if result ~= nil then
		return result
	end
	result = util.GetModelInfo(model).StaticProp
	staticProps[model] = result

	return result
end

if CLIENT then
	---[CLIENT]
	---
	---Check if the player has the RagdollPoser tool equipped
	---
	---@return boolean toolEquipped
	function MGR.Equipped()
		local pl = LocalPlayer()
		local weap = pl:GetActiveWeapon()
		local tool = pl:GetTool()
		---@cast tool TOOL
		return IsValid(weap) and weap:GetClass() == "gmod_tool" and tool and tool:GetMode() == RagdollPoser.Mode
	end
end

RagdollPoser.Helpers = MGR
