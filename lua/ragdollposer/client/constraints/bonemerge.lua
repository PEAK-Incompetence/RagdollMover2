---@class BonemergeConstraint: Constraint
---@field _offset VMatrix?
local lock = include("base.lua")

local VECTOR_ONE = Vector(1, 1, 1)

lock.Properties = {
	type = "bonemerge",
	category = "#tool.ragdollposer.constraint.category.transform",
	name = "#tool.ragdollposer.constraint.bonemerge.name",
	short = "#tool.ragdollposer.constraint.bonemerge.short",
	desc = "#tool.ragdollposer.constraint.bonemerge.desc",
	help = "#tool.ragdollposer.constraint.bonemerge.help",
	icon = "icon16/brick.png",
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

local function getMergeRootBones(parentTarget, childTarget, fallbackParentBone)
	if childTarget:GetBoneCount() <= 0 then
		return
	end

	local childBone = 0
	local parentBone = parentTarget:LookupBone(childTarget:GetBoneName(childBone))
	if not isnumber(parentBone) or parentBone < 0 then
		parentBone = fallbackParentBone
	end
	if not isnumber(parentBone) or parentBone < 0 or parentBone >= parentTarget:GetBoneCount() then
		return
	end

	return parentBone, childBone
end

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
			RagdollPoser.Entity.ExposeBones(target)
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
		for _, target in ipairs(RagdollPoser.Entity.GetEntities()) do
			if IsValid(target) then
				menu:AddOption(getEntityName(target), function()
					constraint.State.otherTarget = target
					updateTarget(target)
					ui.otherTarget:SetText(getEntityName(target))
					RagdollPoser.Constraints:UpdateConstraint(constraint.Owner, constraint)
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

	local parentClient = RagdollPoser.Entity.GetClientFromEntity(parentTarget)
	local childClient = RagdollPoser.Entity.GetClientFromEntity(childTarget)
	if not IsValid(parentClient) or not IsValid(childClient) then
		return
	end

	RagdollPoser.Entity.ExposeBones(parentClient)
	RagdollPoser.Entity.ExposeBones(childClient)
	local parentMatrices = RagdollPoser.Entity.GetMatrices(parentTarget)
	local childMatrices = RagdollPoser.Entity.GetMatrices(childTarget)
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
		if matrix then
			transformedBones[#transformedBones + 1] = bone
		end

		for _, child in ipairs(childClient:GetChildBones(bone)) do
			capture(child)
		end
	end

	capture(0)
	return transformedBones
end

---@return boolean
function lock:EvaluatePose(entity, context)
	local transforms = context and context.transforms
	local transformedBones = context and context.transformedBones
	local parentTarget = self.State.target
	local childTarget = self.State.otherTarget
	if self.State.enabled == false or not IsValid(parentTarget) or not IsValid(childTarget) or not context then
		return false
	end

	local influence = math.Clamp(self.State.influence or 1, 0, 1)
	if influence == 0 then
		return false
	end

	if entity == childTarget then
		local client = RagdollPoser.Entity.GetClientFromEntity(childTarget)
		local transformed = context.transformedByClient and context.transformedByClient[client]
		if not transformed then
			return false
		end

		local childBone = 0
		if transformed[childBone] == nil then
			return false
		end

		local parentMatrices = RagdollPoser.Entity.GetMatrices(parentTarget)
		local childMatrices = context.transforms
		if not parentMatrices or not childMatrices then
			return false
		end

		return captureOffset(self, parentTarget, childTarget, parentMatrices, childMatrices)
	end

	if entity ~= self.Owner or parentTarget ~= entity or not transformedBones or not transforms then
		return false
	end

	local childMatrices = RagdollPoser.Entity.GetMatrices(childTarget)
	if not childMatrices then
		return false
	end

	local parentRootBone, childRootBone = getMergeRootBones(parentTarget, childTarget, self.State.bone)
	local parentRoot = parentRootBone and transforms[parentRootBone + 1]
	local childClient = RagdollPoser.Entity.GetClientFromEntity(childTarget)
	local transformed = context.transformedByClient and context.transformedByClient[childClient]
	if childRootBone and transformed and transformed[childRootBone] ~= nil then
		return captureOffset(self, parentTarget, childTarget, transforms, childMatrices)
	end

	local worldOffset
	if self._offset and parentRoot then
		-- Rotate the saved root-relative offset with the parent's current root pose.
		worldOffset = parentRoot * self._offset * parentRoot:GetInverse()
	end

	for _, bone in ipairs(transformedBones) do
		local boneName = entity:GetBoneName(bone)
		local childBone = childTarget:LookupBone(boneName)
		local parentMatrix = transforms[bone + 1]
		local childMatrix = childBone and childMatrices[childBone + 1]
		if parentMatrix and childMatrix then
			childMatrix:Set(worldOffset and worldOffset * parentMatrix or parentMatrix)
			if not self._offset or childBone ~= childRootBone then
				childMatrix:Translate(childTarget:GetManipulateBonePosition(childBone))
				childMatrix:Rotate(childTarget:GetManipulateBoneAngles(childBone))
				childMatrix:Scale(childTarget:GetManipulateBoneScale(childBone))
			end
		end
	end

	return true
end

-- FIXME: What's the point of these output stuff?
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
	-- print("lock bruh")
	base.State.target = base.Owner
	return base
end

if RagdollPoser.Constraints and not RagdollPoser.Constraints:IsRefreshing() then
	hook.Run("RagdollPoser_Constraints_Refresh", lock.Properties.type)
end

return createConstraint
