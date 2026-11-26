---@class Constraint
---@field State ConstraintState
---@field Properties ConstraintProps
local Base = {}
Base.__index = Base

Base._id = 0

local IDENTITY_MATRIX = Matrix()
IDENTITY_MATRIX:Identity()

---@class ConstraintProps
Base.Properties = {
	type = "base",
	category = "",
	name = "",
	desc = "",
}

---@class ConstraintState
Base.State = {
	enabled = true,
	key = BUTTON_CODE_INVALID,
	target = NULL,
	bone = -1,
	influence = 1,
}

-- TODO: Provide colors from theming
local ENABLED_COLOR = Color(255, 255, 255, 128)
local DISABLED_COLOR = Color(255, 255, 255, 32)
---@param target Entity
---@param bone integer
---@param spriteMat IMaterial
---@param enabledColor Color?
---@param disabledColor Color?
function Base:DrawIcon(target, bone, spriteMat, enabledColor, disabledColor)
	local matrix = self:GetTransformFromBone(target, bone)
	if not matrix then
		return
	end
	enabledColor = enabledColor or ENABLED_COLOR
	disabledColor = disabledColor or DISABLED_COLOR

	render.SetMaterial(spriteMat)
	render.DrawSprite(matrix:GetTranslation(), 2, 2, self.State.enabled and ENABLED_COLOR or DISABLED_COLOR)
end

-- Consider using an enum for types to reduce net cost

---@class SerializedConstraint
---@field Type string
---@field Name string
---@field State ConstraintState
---@field _id integer

---@class NetworkedConstraint
---@field Type integer
---@field Name string
---@field State ConstraintState

---@param entry ConstraintEntry
---@param props ConstraintProps
---@param state ConstraintState
function Base:ConstructUITemplate(entry, props, state)
	local ui = {}

	local function header()
		-- entity to target
		---@class ConstraintTargetSearch: DTextEntry
		ui.target = entry:TextEntry("#tool.ragdollposer.constraint.target", "")
		-- bone of entity to target
		---@class ConstraintBoneSearch: DTextEntry
		---@field Menu DMenu
		ui.bone = entry:TextEntry("#tool.ragdollposer.constraint.bone", "")

		-- Instead of typing directly into the forms, open up a menu for available bones with a floating search entry
		ui.target:SetEditable(false)
		ui.target:SetMouseInputEnabled(true)

		local choices = {}
		local function updateTarget(target)
			choices = {}
			if IsValid(target) then
				RagdollPoser.Entity:ExposeBones(target)
				for i = 0, target:GetBoneCount() - 1 do
					table.insert(choices, target:GetBoneName(i))
				end

				ui.bone:SetPlaceholderText("#tool.ragdollposer.constraint.bone.help")
			end
		end

		local function getEntityName(entity)
			local model = RagdollPoser.Helpers.GetModelNameNice(entity)
			return Format("%s: %s", model, tostring(entity))
		end

		local function updateBone(entity, index)
			local name = entity:GetBoneName(index)
			ui.bone:SetText(name)
			ui.bone:SetTooltip(Format("%s: %d", language.GetPhrase("#tool.ragdollposer.constraint.bone.index"), index))
		end

		if IsValid(state.target) then
			updateTarget(state.target)
			ui.target:SetText(getEntityName(state.target))
			if state.bone > -1 then
				updateBone(state.target, state.bone)
			end
		end

		function ui.target.OnMousePressed(base, mousecode)
			if mousecode == MOUSE_LEFT then
				local menu = DermaMenu()

				local entities = RagdollPoser.Entity:GetEntities()
				for _, entity in ipairs(entities) do
					local name = getEntityName(entity)
					menu:AddOption(name, function()
						self.State.target = entity
						base:SetText(name)
						updateTarget(entity)
						RagdollPoser.Constraints:UpdateConstraint(self.Owner, self)
						RagdollPoser.Constraints:UpdateSingleGraph(self.Owner, self)
					end)
				end

				menu:Open()
			elseif mousecode == MOUSE_RIGHT then
				local menu = DermaMenu()

				menu:AddOption("#tool.ragdollposer.constraint.target.unset", function()
					self.State.target = NULL
					base:SetText("")
					updateTarget(NULL)
					RagdollPoser.Constraints:UpdateConstraint(self.Owner, self)
					RagdollPoser.Constraints:UpdateSingleGraph(self.Owner, self)
				end)
				menu:AddOption("#tool.ragdollposer.constraint.target.set.picker", function() end)

				menu:Open()
			end
		end

		function ui.bone.GetAutoComplete(_, text)
			local suggestions = {}

			local target = self.State.target
			if IsValid(target) then
				for _, result in ipairs(RagdollPoser.Helpers.Filter(text, choices, false)) do
					table.insert(suggestions, choices[result[1]])
				end
			end

			return suggestions
		end

		---Overrides the original function by not calling OnTextChanged, allowing the user
		---to still look through the search options without closing it
		function ui.bone:UpdateFromMenu()
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
		function ui.bone.OnValueChange(pnl, newBoneName)
			local target = self.State.target
			if IsValid(target) then
				local bone = target:LookupBone(newBoneName)
				if bone then
					self.State.bone = bone
					updateBone(target, bone)
					RagdollPoser.Constraints:UpdateConstraint(self.Owner, self)
				end
			end
		end
	end

	-- implement ui bone stuff using bone search utility from ragdoll puppeteer

	local function footer()
		ui.influence = entry:NumSlider("#tool.ragdollposer.constraint.influence", "", 0, 1, 3)
		ui.influence:SetValue(state.influence or 1)
		function ui.influence.OnValueChanged(base, newValue)
			self.State.influence = newValue
		end
	end

	-- Give explicit builder functions for UI. That way, we can define stuff in between our header and footers
	return ui, header, footer
end

---@param entry ConstraintEntry
---@param props ConstraintProps
---@param state ConstraintState
---@return table<any, Panel>
function Base:ConstructUI(entry, props, state) end

---@return SerializedConstraint
function Base:Serialize()
	return {
		Type = self.Properties.type,
		Name = self.Properties.name,
		State = self.State,
		_id = self._id,
	}
end

---@param state ConstraintState?
---@param name string?
function Base:Init(entity, state, name)
	local id = self._id + 1

	local base = setmetatable({
		_id = id,
		Owner = entity,
		Properties = table.Copy(self.Properties),
		State = table.Copy(self.State),
	}, Base)
	for key, value in pairs(state or {}) do
		base.State[key] = value
	end

	base.Properties.name = name or base.Properties.name
	self._id = id
	return base
end

-- Save some bone info here
---@param entity Entity
---@param transform VMatrix
---@param locals VMatrix[]
---@param parents integer[]
---@return integer[]
function Base:PreEvaluate(entity, transform, locals, parents) end

---@param entity Entity
---@param controlledBone integer
---@param transform VMatrix
---@param locals LocalMatrixInfo[]
---@param parents integer[]
---@param output VMatrix[]
function Base:Evaluate(entity, controlledBone, transform, locals, parents, output) end

---@class PoseEvaluationContext
---@field transformedBones integer[]
---@field transforms VMatrix[]
---@field transformedByClient table<ClientEntity, table<integer, VMatrix>>
---@field selectedBoneMatrices table<integer, VMatrix>
---@field forceCurrentGoal boolean

---@param entity Entity
---@param context PoseEvaluationContext
---@return boolean?
function Base:EvaluatePose(entity, context) end

---@param entity Entity
---@param bone integer
---@return VMatrix
function Base:GetTransformFromBone(entity, bone)
	if not IsValid(entity) or bone < 0 then
		return
	end
	local matrices = RagdollPoser.Entity:GetMatrices(entity)
	return matrices and matrices[bone + 1]
end

function Base:Draw() end

---@param entity Entity
---@param controlledBone integer
---@param locals LocalMatrixInfo[]
---@param parents integer[]
---@param output VMatrix[]
function Base:PostEvaluate(entity, controlledBone, locals, parents, output) end

function Base:CaptureLockPose()
	self._snapshot = {}

	local target = self.State.target
	local lockedBone = self.State.bone
	if
		self.State.enabled == false
		or not IsValid(target)
		or not isnumber(lockedBone)
		or lockedBone < 0
		or lockedBone >= target:GetBoneCount()
	then
		return
	end

	local client = RagdollPoser.Entity:GetClientFromEntity(target)
	RagdollPoser.Entity:ExposeBones(client)
	local matrices = RagdollPoser.Entity:GetMatrices(client)
	local visited = {}

	local transformedBones = {}
	local function capture(bone)
		if visited[bone] then
			return
		end
		visited[bone] = true
		table.insert(transformedBones, bone)

		local matrix = matrices and matrices[bone + 1] or client:GetBoneMatrix(bone)
		if matrix then
			self._snapshot[bone] = matrix * IDENTITY_MATRIX
		end

		for _, child in ipairs(client:GetChildBones(bone)) do
			capture(child)
		end
	end

	capture(lockedBone)
	return transformedBones
end

function Base:ApplyLock(entity, controlledBone, component, output)
	if self.State.enabled == false then
		return false
	end

	local target = self.State.target
	local lockedBone = self.State.bone
	if not IsValid(target) or target ~= entity or not self._snapshot then
		return false
	end
	local client = RagdollPoser.Entity:GetClientFromEntity(target)

	local walk = controlledBone
	while walk and walk >= 0 do
		if walk == lockedBone then
			return false
		end
		walk = client:GetBoneParent(walk)
	end

	local influence = math.Clamp(self.State.influence or 1, 0, 1)
	if influence == 0 then
		return false
	end

	local initial = self._snapshot[lockedBone]
	local matrix = output[lockedBone]
	if not initial or not matrix then
		return false
	end

	if component == "position" then
		matrix:SetTranslation(LerpVector(influence, matrix:GetTranslation(), initial:GetTranslation()))
	elseif component == "rotation" then
		matrix:SetAngles(LerpAngle(influence, matrix:GetAngles(), initial:GetAngles()))
	elseif component == "scale" then
		matrix:SetScale(LerpVector(influence, matrix:GetScale(), initial:GetScale()))
	else
		return false
	end

	return true
end

function Base:PostApplyLock(lockedBone, locals, parents, output)
	local matrix = output[lockedBone]
	if not matrix then
		return
	end

	local worldMatrix = { [lockedBone] = matrix }
	for _, localMatrixInfo in ipairs(locals) do
		local bone = localMatrixInfo[1]
		local localMatrix = localMatrixInfo[2]
		local parentBone = parents[bone]
		local parentMatrix = worldMatrix[parentBone]
		if parentMatrix and localMatrix then
			local childMatrix = parentMatrix * localMatrix
			output[bone] = childMatrix
			worldMatrix[bone] = childMatrix
		end
	end
end

return Base
