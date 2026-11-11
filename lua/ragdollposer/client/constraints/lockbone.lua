---@class BoneLockConstraint: Constraint
local lock = include("base.lua")

lock.Properties = {
	type = "lockbone",
	category = "#tool.ragdollposer.constraint.category.transform",
	name = "#tool.ragdollposer.constraint.lockbone.name",
	desc = "#tool.ragdollposer.constraint.lockbone.desc",
	help = "#tool.ragdollposer.constraint.lockbone.help",
	icon = "icon16/brick.png",
}

---@class BoneLockConstraintState: ConstraintState
---@field otherTarget Entity
---@field otherBone integer
lock.State = table.Merge(table.Copy(lock.State), {
	otherTarget = NULL,
	otherBone = -1,
})

local IDENTITY_MATRIX = Matrix()
IDENTITY_MATRIX:Identity()

function lock:ConstructUI(entry, props, state)
	local ui, header, footer = self:ConstructUITemplate(entry, props or self.Properties, state or self.State)
	header()

	local constraint = self
	ui.target:SetEditable(false)
	ui.target:SetMouseInputEnabled(false)
	ui.otherTarget = entry:TextEntry("#tool.ragdollposer.constraint.lockbone.child", "")
	ui.otherTarget:SetEditable(false)
	ui.otherTarget:SetMouseInputEnabled(true)
	---@type ConstraintBoneSearch
	ui.otherBone = entry:TextEntry("#tool.ragdollposer.constraint.lockbone.childbone", "")

	local choices = {}

	local function updateTarget(target)
		choices = {}
		if IsValid(target) then
			RagdollPoser.Entity.ExposeBones(target)
			for i = 0, target:GetBoneCount() - 1 do
				table.insert(choices, target:GetBoneName(i))
			end

			ui.otherBone:SetPlaceholderText("#tool.ragdollposer.constraint.bone.help")
		end
	end

	local function getEntityName(entity)
		local model = RagdollPoser.Helpers.GetModelNameNice(entity)
		return Format("%s: %s", model, tostring(entity))
	end

	local function updateBone(entity, index)
		local name = entity:GetBoneName(index)
		ui.otherBone:SetText(name)
		ui.otherBone:SetTooltip(Format("%s: %d", language.GetPhrase("#tool.ragdollposer.constraint.bone.index"), index))
	end

	if IsValid(state.otherTarget) then
		updateTarget(state.otherTarget)
		ui.otherTarget:SetText(getEntityName(state.otherTarget))
		if state.otherBone > -1 then
			updateBone(state.otherTarget, state.otherBone)
		end
	end

	function ui.otherBone.GetAutoComplete(_, text)
		local suggestions = {}

		local target = constraint.State.otherTarget
		if IsValid(target) then
			for _, result in ipairs(RagdollPoser.Helpers.Filter(text, choices, false)) do
				table.insert(suggestions, choices[result[1]])
			end
		end

		return suggestions
	end

	---Overrides the original function by not calling OnTextChanged, allowing the user
	---to still look through the search options without closing it
	function ui.otherBone:UpdateFromMenu()
		---INFO: Menu is a field of DTextEntry, for autocomplete menu
		---@diagnostic disable-next-line: undefined-field
		local menu = self.Menu

		local pos = self.HistoryPos
		local num = menu:ChildCount()

		menu:ClearHighlights()

		if pos < 0 then
			pos = num
		end
		if pos > num then
			pos = 0
		end

		local item = menu:GetChild(pos)
		if not item then
			self.HistoryPos = pos
			return
		end

		menu:HighlightItem(item)

		local txt = item:GetText()

		self:SetText(txt)
		self:SetCaretPos(utf8.len(txt) or 0)

		self.HistoryPos = pos
	end

	---@param pnl DTextEntry
	---@param newBoneName string
	function ui.otherBone.OnValueChange(pnl, newBoneName)
		local target = constraint.State.otherTarget
		if IsValid(target) then
			local bone = target:LookupBone(newBoneName)
			if bone then
				constraint.State.otherBone = bone
				updateBone(target, bone)
				RagdollPoser.Constraints:UpdateConstraint(constraint.Owner, self)
			end
		end
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
					constraint.State.otherBone = -1
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
	self._snapshot = nil

	local parentTarget = self.State.target
	local parentBone = self.State.bone
	local childTarget = self.State.otherTarget
	local childBone = self.State.otherBone
	if
		self.State.enabled == false
		or entity ~= self.Owner
		or parentTarget ~= entity
		or not IsValid(parentTarget)
		or not IsValid(childTarget)
		or not isnumber(parentBone)
		or parentBone < 0
		or parentBone >= parentTarget:GetBoneCount()
		or not isnumber(childBone)
		or childBone < 0
		or childBone >= childTarget:GetBoneCount()
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

	local snapshot = {
		parent = parentMatrix * IDENTITY_MATRIX,
		locals = {},
	}
	local visited = {}

	local function capture(bone)
		if visited[bone] then
			return
		end
		visited[bone] = true

		local matrix = childMatrices[bone + 1]
		if matrix then
			snapshot.locals[bone] = parentMatrix:GetInverse() * matrix
		end

		for _, child in ipairs(childClient:GetChildBones(bone)) do
			capture(child)
		end
	end

	capture(childBone)
	self._snapshot = snapshot
end

function lock:EvaluatePose(entity, controlledBones, transforms)
	local snapshot = self._snapshot
	local parentTarget = self.State.target
	local childTarget = self.State.otherTarget
	local parentBone = self.State.bone
	if
		self.State.enabled == false
		or entity ~= self.Owner
		or parentTarget ~= entity
		or not IsValid(childTarget)
		or not snapshot
		or not transforms
	then
		return
	end

	local currentParent = transforms[parentBone + 1]
	local childMatrices = RagdollPoser.Entity.GetMatrices(childTarget)
	if not currentParent or not childMatrices then
		return
	end

	local influence = math.Clamp(self.State.influence or 1, 0, 1)
	if influence == 0 then
		return
	end

	local parentMatrix = snapshot.parent * IDENTITY_MATRIX
	parentMatrix:SetTranslation(LerpVector(influence, snapshot.parent:GetTranslation(), currentParent:GetTranslation()))
	parentMatrix:SetAngles(LerpAngle(influence, snapshot.parent:GetAngles(), currentParent:GetAngles()))
	parentMatrix:SetScale(LerpVector(influence, snapshot.parent:GetScale(), currentParent:GetScale()))

	for bone, relativeMatrix in pairs(snapshot.locals) do
		local matrix = childMatrices[bone + 1]
		if matrix then
			matrix:Set(parentMatrix * relativeMatrix)
		end
	end
end

-- FIXME: What's the point of these output stuff?
function lock:GetOutputEntity()
	local target = self.State.otherTarget
	if self.State.enabled ~= false and IsValid(target) and target ~= self.State.target then
		return target
	end
end

function lock:GetOutputRoot()
	local target = self:GetOutputEntity()
	local bone = self.State.otherBone
	if IsValid(target) and isnumber(bone) and bone >= 0 and bone < target:GetBoneCount() then
		return bone
	end
end

function lock:PostEvaluate()
	self._snapshot = nil
end

local function createConstraint(state, name)
	local base = lock:Init(state, name)
	---@cast base BoneLockConstraint
	-- print("lock bruh")
	base.State.target = base.Owner
	return base
end

return createConstraint
