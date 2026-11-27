---@class BonemergeConstraint: Constraint
---@field _offset VMatrix?
local lock = include("base.lua")

local VECTOR_ONE = RagdollPoser.Constants.VECTOR_ONE

lock.Properties = {
	type = "bonemerge",
	category = "#tool.ragdollposer.constraint.category.transform",
	name = "#tool.ragdollposer.constraint.bonemerge.name",
	short = "#tool.ragdollposer.constraint.bonemerge.short",
	desc = "#tool.ragdollposer.constraint.bonemerge.desc",
	help = "#tool.ragdollposer.constraint.bonemerge.help",
	icon = "icon16/link.png",
}

---@class BonemergeConstraintState: ConstraintState
---@field otherTarget Entity
---@field otherBone integer
lock.State = table.Merge(table.Copy(lock.State), {
	otherTarget = NULL,
	otherBone = -1,
})

local IDENTITY_MATRIX = Matrix()
IDENTITY_MATRIX:Identity()

local RED = Color(255, 0, 0, 128)
local DISABLED_RED = Color(255, 0, 0, 32)
local spriteMat = Material(lock.Properties.icon)
function lock:Draw()
	self:DrawIcon(self.State.target, self.State.bone, spriteMat)
	self:DrawIcon(self.State.otherTarget, self.State.otherBone, spriteMat, RED, DISABLED_RED)
end

---@param parentTarget Entity
---@param childTarget Entity
---@param fallbackParentBone integer
local function getMergeRootBones(parentTarget, childTarget, fallbackParentBone)
	if childTarget:GetBoneCount() <= 0 then
		return
	end

	local childBone = 0
	local parentBone = RagdollPoser.Bonemerge:GetParentBone(childTarget, parentTarget, childBone)
	if not isnumber(parentBone) or parentBone < 0 then
		parentBone = fallbackParentBone
	end
	if not isnumber(parentBone) or parentBone < 0 or parentBone >= parentTarget:GetBoneCount() then
		return
	end

	return parentBone, childBone
end

---@param constraint BonemergeConstraint
---@param parentTarget Entity
---@param childTarget Entity
---@param parentMatrices VMatrix[]
---@param childMatrices VMatrix[]
local function captureOffset(constraint, parentTarget, childTarget, parentMatrices, childMatrices)
	local parentBone, childBone = getMergeRootBones(parentTarget, childTarget, constraint.State.bone)
	local parentRoot = parentBone and parentMatrices[parentBone + 1]
	local childRoot = childBone and childMatrices[childBone + 1]
	if not parentRoot or not childRoot then
		return false
	end

	local parentInverse = parentRoot:GetInverse()
	if not parentInverse then
		constraint._offset = nil
		RagdollPoser.Log("Cannot capture bonemerge offset: parent root matrix is singular for ", parentTarget)
		return false
	end

	-- Keep the child's new placement relative to the parent root.
	constraint._offset = parentInverse * childRoot
	return true
end

function lock:ConstructUI(entry, props, state)
	local ui, header, footer = self:ConstructUITemplate(entry, props or self.Properties, state or self.State)
	header()

	local constraint = self
	ui.target:SetEditable(false)
	ui.target:SetMouseInputEnabled(false)
	ui.otherTarget = entry:TextEntry("#tool.ragdollposer.constraint.lockbone.child", "")
	ui.otherTarget:SetEditable(false)
	ui.otherTarget:SetMouseInputEnabled(true)

	local choices = {}

	local function updateTarget(target)
		choices = {}
		if IsValid(target) then
			RagdollPoser.Entity:ExposeBones(target)
			for i = 0, target:GetBoneCount() - 1 do
				table.insert(choices, target:GetBoneName(i))
			end
		end
	end

	local function getEntityName(entity)
		local model = RagdollPoser.Helpers.GetModelNameNice(entity)
		return Format("%s: %s", model, tostring(entity))
	end

	if IsValid(state.otherTarget) then
		updateTarget(state.otherTarget)
		ui.otherTarget:SetText(getEntityName(state.otherTarget))
	end

	ui.otherTarget:SetText(IsValid(state.otherTarget) and getEntityName(state.otherTarget) or "")
	function ui.otherTarget:OnMousePressed(mouseCode)
		if mouseCode ~= MOUSE_LEFT then
			return
		end

		local menu = DermaMenu()
		for _, target in ipairs(RagdollPoser.Entity:GetEntities()) do
			if IsValid(target) then
				menu:AddOption(getEntityName(target), function()
					constraint.State.otherTarget = target
					updateTarget(target)
					ui.otherTarget:SetText(getEntityName(target))
					RagdollPoser.Constraints:UpdateConstraint(constraint.Owner, constraint)
					RagdollPoser.Constraints:UpdateSingleGraph(constraint.Owner, constraint)
				end)
			end
		end
		menu:Open()
	end

	footer()
end

function lock:PreEvaluate(entity)
	local parentTarget = self.State.target
	local parentBone = self.State.bone
	local childTarget = self.State.otherTarget
	if
		self.State.enabled == false
		or entity ~= self.Owner
		or parentTarget ~= entity
		or not IsValid(parentTarget)
		or not IsValid(childTarget)
		or not isnumber(parentBone)
		or parentBone < 0
		or parentBone >= parentTarget:GetBoneCount()
	then
		return
	end

	local parentClient = RagdollPoser.Entity:GetClientFromEntity(parentTarget)
	local childClient = RagdollPoser.Entity:GetClientFromEntity(childTarget)
	if not IsValid(parentClient) or not IsValid(childClient) then
		return
	end

	RagdollPoser.Entity:ExposeBones(parentClient)
	RagdollPoser.Entity:ExposeBones(childClient)
	local parentMatrices = RagdollPoser.Entity:GetMatrices(parentTarget)
	local childMatrices = RagdollPoser.Entity:GetMatrices(childTarget)
	local parentMatrix = parentMatrices and parentMatrices[parentBone + 1]
	if not parentMatrix or not childMatrices then
		return
	end

	-- Refresh the drag-start offset so re-enabling the constraint cannot reuse a stale scale.
	if not captureOffset(self, parentTarget, childTarget, parentMatrices, childMatrices) then
		return
	end

	local visited = {}
	local transformedBones = {}

	local function capture(bone)
		if visited[bone] then
			return
		end
		visited[bone] = true

		local matrix = childMatrices[bone + 1]
		local parent = childClient:GetBoneParent(bone)
		local parentBoneMatrix = parent >= 0 and childMatrices[parent + 1]
		if matrix then
			transformedBones[#transformedBones + 1] = bone
			if parentBoneMatrix then
				self.transformedBonesLocal[bone] = parentBoneMatrix:GetInverse() * matrix
			end
		end

		for _, child in ipairs(childClient:GetChildBones(bone)) do
			capture(child)
		end
	end
	self.transformedBonesLocal = {}

	capture(0)
	return transformedBones
end

---@return boolean
function lock:EvaluatePose(entity, context)
	local transforms = context and context.transforms
	local transformedBones = context and context.transformedBones
	local transformedClientBones = context and context.transformedByClient
	local parentTarget = self.State.target
	local parentClient = RagdollPoser.Entity:GetClientFromEntity(parentTarget)
	local childTarget = self.State.otherTarget
	if self.State.enabled == false or not IsValid(parentTarget) or not IsValid(childTarget) or not context then
		return false
	end
	local parentTransformedBoneSet = transformedClientBones[parentClient]

	local influence = math.Clamp(self.State.influence or 1, 0, 1)
	if influence == 0 then
		return false
	end

	if entity == childTarget then
		local client = RagdollPoser.Entity:GetClientFromEntity(childTarget)
		local transformed = context.transformedByClient and context.transformedByClient[client]
		if not transformed then
			return false
		end

		local childBone = 0
		if transformed[childBone] == nil then
			return false
		end

		local parentMatrices = RagdollPoser.Entity:GetMatrices(parentTarget)
		local childMatrices = context.transforms
		if not parentMatrices or not childMatrices then
			return false
		end

		return captureOffset(self, parentTarget, childTarget, parentMatrices, childMatrices)
	end

	if entity ~= self.Owner or parentTarget ~= entity or not transformedBones or not transforms then
		return false
	end

	local childMatrices = RagdollPoser.Entity:GetMatrices(childTarget)
	if not childMatrices then
		return false
	end

	local parentRootBone, childRootBone = getMergeRootBones(parentTarget, childTarget, self.State.bone)
	local parentRoot = parentRootBone and transforms[parentRootBone + 1]
	local childClient = RagdollPoser.Entity:GetClientFromEntity(childTarget)
	local transformed = context.transformedByClient and context.transformedByClient[childClient]
	if childRootBone and transformed and transformed[childRootBone] ~= nil then
		return captureOffset(self, parentTarget, childTarget, transforms, childMatrices)
	end

	local childRoot = childMatrices[childRootBone + 1]

	if self._offset and parentRoot and childRoot then
		childRoot:Set(parentRoot * self._offset)
	end

	RagdollPoser.Entity:ExposeBones(childTarget)
	RagdollPoser.Entity:ExposeBones(parentTarget)
	-- Take the L and iterate over all child bone targets during transform
	for childBone = 0, childTarget:GetBoneCount() - 1 do
		if self._offset and childBone == childRootBone then
			continue
		end

		local parentBone = RagdollPoser.Bonemerge:GetParentBone(childTarget, parentTarget, childBone)
		local childMatrix = childMatrices[childBone + 1]
		-- At least not all of them, but still.
		-- TODO: Can we only check the bones that we are moving, including those from an IK chain or lock bones? Currently iterates through all bones if we have bonemerge
		-- Which can be expensive if we have alot of bonemerged stuff
		if not parentBone or not transforms[parentBone] then
			-- Let's make sure we're situated with respect to our parents
			-- local childParent = childTarget:GetBoneParent(childBone)
			-- -- If we're moving that we've selected, don't lock it
			-- if childParent >= 0 then
			-- 	childMatrix:Set(childMatrix * self.transformedBonesLocal[childBone]:GetInverse())
			-- end
			continue
		end

		local parentMatrix = transforms[parentBone + 1]
		if parentMatrix and childMatrix then
			-- TODO: Add a DoTransform section in bonemerge.lua for this stuff
			if childTarget:GetClass() == "ent_advbonemerge" then
				childMatrix:Set(parentMatrix)
				if not self._offset or childBone ~= childRootBone then
					childMatrix:Translate(childTarget:GetManipulateBonePosition(childBone))
					childMatrix:Rotate(childTarget:GetManipulateBoneAngles(childBone))
					childMatrix:Scale(childTarget:GetManipulateBoneScale(childBone))
				end
			elseif childTarget:GetClass() == "ent_composite" then
				if childTarget:GetParentAttachment() ~= 0 then
					local pastParentMatrix = parentTarget:GetBoneMatrix(parentBone)
					local previousMatrix = childTarget:GetBoneMatrix(childBone)
					local pastLocal = pastParentMatrix:GetInverse() * previousMatrix

					childMatrix:Set(parentMatrix * pastLocal)
				else
					childMatrix:Set(parentMatrix)
					if not self._offset or childBone ~= childRootBone then
						-- Composite bonemerges don't move at all, only scale
						childMatrix:Scale(childTarget:GetManipulateBoneScale(childBone))
					end
				end
			end
		end
	end

	-- TODO: Account for bones of the bonemerged entity that the parent entity doesn't have

	return true
end

function lock:GetOutputEntity()
	local target = self.State.otherTarget
	if IsValid(target) and target ~= self.State.target then
		return target
	end
end

function lock:GetOutputRoot()
	local target = self:GetOutputEntity()
	if IsValid(target) and target:GetBoneCount() > 0 then
		return 0
	end
end

local function createConstraint(entity, state, name)
	local base = lock:Init(entity, state, name)
	---@cast base BonemergeConstraint
	base.State.target = base.Owner
	return base
end

if RagdollPoser.Constraints and not RagdollPoser.Constraints:IsRefreshing() then
	hook.Run("RagdollPoser_Constraints_Refresh", lock.Properties.type)
end

return createConstraint
