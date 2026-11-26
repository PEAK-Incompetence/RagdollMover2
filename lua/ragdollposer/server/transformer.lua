--- [SERVER]
---
--- Receive matrix data from the client and apply them to the correct places for a given entity class.
---
--- This module only sets positions. We shall not compute anything on the server
---
---@class RagdollPoser.ServerTransformer
local MGR = RagdollPoser.ServerTransformer or {}

---@alias EntityTransformFunction fun(entity: Entity, bones: integer[], boneSet: table<integer, integer>, matrices: VMatrix[]): boolean

local warningColor = Color(255, 255, 0)

---@param entity Entity
---@param bones integer[]
---@param boneSet table<integer, integer>
---@param matrices VMatrix[]
local function genericPhysicsProp(entity, bones, boneSet, matrices)
	local po = entity:GetPhysicsObject()
	for _, b in ipairs(bones) do
		local matrix = matrices[b]
		local physBone = RagdollPoser.Helpers.BoneToPhysBone(entity, b)
		if matrix then
			if physBone >= 0 then
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

---@param entity Entity
---@param bones integer[]
---@param boneSet table<integer, integer>
---@param matrices VMatrix[]
local function genericEntity(entity, bones, boneSet, matrices) end

---@param entity Entity
---@param bones integer[]
---@param boneSet table<integer, integer>
---@param matrices VMatrix[]
local function genericManipulate(entity, bones, boneSet, matrices)
	for _, b in ipairs(bones) do
		local matrix = matrices[b]
		if matrix then
			entity:ManipulateBonePosition(b, matrix:GetTranslation())
			entity:ManipulateBoneAngles(b, matrix:GetAngles())
			entity:ManipulateBoneScale(b, matrix:GetScale())
		end
	end
end

function MGR:RestoreDefaults()
	---Entity classes that map to a function that does the transforming
	---@type table<string, EntityTransformFunction>
	self.EntityMap = {
		prop_ragdoll = function(entity, bones, boneSet, matrices)
			for _, b in ipairs(bones) do
				local matrix = matrices[b]
				local physBone = RagdollPoser.Helpers.BoneToPhysBone(entity, b)
				local po = physBone >= 0 and entity:GetPhysicsObjectNum(physBone)
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
		end,
		prop_physics = genericPhysicsProp,
		prop_dynamic = function(entity, bones, boneSet, matrices)
			local index = boneSet[0]
			local rootMatrix = matrices[0]
			if rootMatrix then
				if IsValid(entity:GetParent()) then
					entity:SetLocalPos(rootMatrix:GetTranslation())
				else
					entity:SetPos(rootMatrix:GetTranslation())
				end
				entity:SetLocalAngles(rootMatrix:GetAngles())

				table.remove(bones, index)
				matrices[0] = nil
			end
			genericManipulate(entity, bones, boneSet, matrices)
		end,
		prop_animated = function(entity, bones, boneSet, matrices)
			local index = boneSet[0]
			local rootMatrix = matrices[0]
			if rootMatrix then
				entity:SetPos(rootMatrix:GetTranslation())
				entity:SetAngles(rootMatrix:GetAngles())
				table.remove(bones, index)
				matrices[0] = nil
			end
			genericManipulate(entity, bones, boneSet, matrices)
		end,
		prop_effect = genericPhysicsProp,
		ent_advbonemerge = genericManipulate,
		ent_composite = function(entity, bones, boneSet, matrices)
			local index = boneSet[0]
			local rootMatrix = matrices[0]
			if rootMatrix then
				entity:SetLocalPos(rootMatrix:GetTranslation())
				entity:SetLocalAngles(rootMatrix:GetAngles())
				entity:ManipulateBoneScale(0, rootMatrix:GetScale())
				table.remove(bones, index)
				matrices[0] = nil
			end
			genericManipulate(entity, bones, boneSet, matrices)
		end,
		ent_bonemerged = genericManipulate,
	}
end

---@param class string The entity class to transform
---@param transformFunction EntityTransformFunction
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
}

---@param class string
---@param entity Entity
---@param bones integer[]
---@param boneSet table<integer, integer>
---@param matrices VMatrix[]
function MGR:DoTransform(class, entity, bones, boneSet, matrices)
	class = aliases[class] or class
	if string.find(class, "npc_") then
		class = "prop_animated"
	end
	if string.find(class, "weapon_") then
		class = "prop_dynamic"
	end

	local func = self.EntityMap[class]
	if func then
		local success, err = pcall(func, entity, bones, boneSet, matrices)
		if not success and err then
			ErrorNoHaltWithStack(
				"There was a problem with trying to transform ",
				tostring(entity),
				". If you see this error, report it to the Ragdoll Mover 2 developers\n",
				err,
				"\n"
			)
		end
		return success
	end
end

RagdollPoser.ServerTransformer = MGR

MGR:RestoreDefaults()
hook.Run("RagdollPoser_ServerTransformer_AddTransform", MGR)
