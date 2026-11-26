---[CLIENT]
---
---@class RagdollPoser.Constraints
local MGR = RagdollPoser.Constraints or {
	---@type boolean
	_refreshing = false,
}

---@alias Space integer
MGR.Space = {
	World = 0,
	Custom = 1,
	Pose = 2,
	Local = 3,
}

---@type Constraint[]
MGR.Constraints = {}
---@type table<string, fun(entity: Entity, state: ConstraintState?, name: string?): Constraint>
MGR.ConstraintConstructors = {}

---@class Constraints
---@field array Constraint[]
---@field set table<integer, integer>

-- Store constraints per entity
-- And cascade updates, so if we moved an IK target that both entities share, both entities should update
-- So that means iterate over entityconstraintstacks?
---@type table<Entity, Constraints>
local EntityConstraintStacks = MGR.EntityConstraintStacks or {}
MGR.EntityConstraintStacks = EntityConstraintStacks

---TODO: This is only used for drawing entities in the same
---graph. Ensure we don't get DAGs
---@type table<Entity, SetArray<Entity>>
local EntityGraph = MGR.EntityGraph or {}
MGR.EntityGraph = EntityGraph

-- DAG for evaluating constraints

---@class SetArray<T>
---@field set table<T, integer>
---@field array T[]

---@generic T: Entity
---@return SetArray<T>
local function createSetArray()
	return {
		set = {},
		array = {},
	}
end

---@param entity Entity
---@param type string
---@param state ConstraintState?
---@param name string?
local function constructConstraint(entity, type, state, name)
	local constructor = MGR.ConstraintConstructors[type]
	if constructor then
		local constraint = constructor(entity, state, name)
		if constraint then
			if isnumber(id) then
				constraint._id = id
				MGR._nextConstraintID = math.max(MGR._nextConstraintID or 0, id)
			else
				MGR._nextConstraintID = (MGR._nextConstraintID or 0) + 1
				constraint._id = MGR._nextConstraintID
			end
		end
		return constraint
	end
end

local function refreshStack(entity)
	local stack = EntityConstraintStacks[entity]
	if not stack then
		return
	end

	local maxID = MGR._nextConstraintID or 0
	for _, constraint in ipairs(stack.array) do
		if isnumber(constraint._id) then
			maxID = math.max(maxID, constraint._id)
		end
	end

	MGR._nextConstraintID = maxID
	stack.set = {}
	local seen = {}
	for index, constraint in ipairs(stack.array) do
		if not isnumber(constraint._id) or seen[constraint._id] then
			MGR._nextConstraintID = MGR._nextConstraintID + 1
			constraint._id = MGR._nextConstraintID
		end
		seen[constraint._id] = true
		stack.set[constraint._id] = index
	end
end

local function getLockBoneOutput(constraint)
	if constraint.Properties.type ~= "lockbone" or constraint.State.enabled == false then
		return
	end

	local target = constraint.State.otherTarget
	local bone = constraint.State.otherBone
	if IsValid(target) and isnumber(bone) and bone >= 0 and bone < target:GetBoneCount() then
		return target, bone
	end
end

local function getConstraintOutputEntity(constraint, entity)
	local target = constraint.GetOutputEntity and constraint:GetOutputEntity()
	local root = constraint.GetOutputRoot and constraint:GetOutputRoot()
	if IsValid(target) and isnumber(root) and root >= 0 and root < target:GetBoneCount() then
		return target
	end
	return entity
end

local function isBoneInSubtree(entity, bone, root)
	local client = RagdollPoser.Entity:GetClientFromEntity(entity)
	if not IsValid(client) then
		return false
	end

	local current = bone
	while current and current >= 0 do
		if current == root then
			return true
		end
		current = client:GetBoneParent(current)
	end
	return false
end

local function wasBoneTransformed(entity, bone, transformedByClient)
	local client = RagdollPoser.Entity:GetClientFromEntity(entity)
	local transformed = transformedByClient and transformedByClient[client]
	return transformed and transformed[bone] ~= nil
end

local function forEachIKAfterLock(constraint, callback)
	local target, bone = getLockBoneOutput(constraint)
	if not target or target == constraint.Owner then
		return
	end

	local stack = EntityConstraintStacks[target]
	if stack then
		for _, dependent in ipairs(stack.array) do
			local effector = dependent.State.bone
			if
				dependent.Properties.type == "ik"
				and dependent._id > constraint._id
				and isBoneInSubtree(target, effector, bone)
			then
				callback(dependent, target, effector)
			end
		end
	end
end

function MGR:GetConstraints()
	return self.Constraints
end

function MGR:GetConstraintStack(entity)
	local stack = EntityConstraintStacks[entity]
	return stack and stack.array or {}
end

---@param entity Entity
---@param id integer
---@return integer?
function MGR:GetConstraintIndex(entity, id)
	refreshStack(entity)
	local stack = EntityConstraintStacks[entity]
	return stack and stack.set[id]
end

function MGR:Init(constraintType)
	if constraintType then
		self:SetRefreshing(true)
		local success, err = pcall(function()
			---@type fun(): Constraint
			local constructor = include("ragdollposer/client/constraints/" .. constraintType .. ".lua")
			---@type Constraint
			local constraint = constructor()
			for i, c in ipairs(self.Constraints) do
				if c.Properties.type == constraintType then
					self.Constraints[i] = constraint
				end
			end
			self.ConstraintConstructors[constraint.Properties.type] = constructor
		end)
		self:SetRefreshing(false)

		if not success then
			ErrorNoHaltWithStack("There was an error during constraint construction:", err, "\n")
		end
		return
	end
	self.Constraints = {}

	local files = file.Find("lua/ragdollposer/client/constraints/*.lua", "GAME", "namedesc")
	for _, f in ipairs(files or {}) do
		if f == "base.lua" then
			continue
		end

		self:SetRefreshing(true)
		local success, err = pcall(function()
			---@type fun(): Constraint
			local constructor = include("ragdollposer/client/constraints/" .. f)
			---@type Constraint
			local constraint = constructor()
			table.insert(self.Constraints, constraint)
			self.ConstraintConstructors[constraint.Properties.type] = constructor
		end)
		self:SetRefreshing(false)
		if not success then
			ErrorNoHaltWithStack("There was an error during constraint construction:", err, "\n")
		end
	end
end

-- Check for cycles on the stack.
function MGR:ValidateStack() end

---@return table<Entity, integer[]>
function MGR:PreEvaluate(entity, transform, locals, parents)
	local stack = EntityConstraintStacks[entity]
	local transformedBones = {}
	if stack then
		local preparedConstraints = {}
		for _, constraint in ipairs(stack.array) do
			local outputEntity = getConstraintOutputEntity(constraint, entity)
			local bones = constraint:PreEvaluate(entity, transform, locals, parents)
			if bones then
				transformedBones[outputEntity] = transformedBones[outputEntity] or {}
				table.Add(transformedBones[outputEntity], bones)
			end

			forEachIKAfterLock(constraint, function(dependent, target)
				if not preparedConstraints[dependent] then
					local dependentBones = dependent:PreEvaluate(target)
					if dependentBones then
						transformedBones[target] = transformedBones[target] or {}
						table.Add(transformedBones[target], dependentBones)
					end
					preparedConstraints[dependent] = true
				end
			end)
		end
	end
	return transformedBones
end

---@param entity Entity
---@param controlledBone integer
---@param transform VMatrix
---@param locals LocalMatrixInfo[]
---@param output VMatrix[]
function MGR:Evaluate(entity, controlledBone, transform, locals, parents, output)
	local stack = EntityConstraintStacks[entity]
	if stack then
		for _, constraint in ipairs(stack.array) do
			constraint:Evaluate(entity, controlledBone, transform, locals, parents, output)
		end
	end
end

local dependentPoseContext = {
	transformedBones = {},
	transforms = {},
	transformedByClient = {},
	selectedBoneMatrices = {},
	forceCurrentGoal = true,
}

---@param entity Entity
---@param context PoseEvaluationContext
function MGR:EvaluatePose(entity, context)
	local stack = EntityConstraintStacks[entity]
	if stack then
		local appliedLockBones = {}
		local linkedLockBones = {}
		for _, constraint in ipairs(stack.array) do
			local target, bone = getLockBoneOutput(constraint)
			local outputSelected = target and wasBoneTransformed(target, bone, context.transformedByClient)
			if target and target ~= entity then
				if not outputSelected then
					table.insert(linkedLockBones, constraint)
				end
			elseif outputSelected then
				continue
			else
				local forceCurrentGoal = false
				if constraint.Properties.type == "ik" and #appliedLockBones > 0 then
					for _, lockedBone in ipairs(appliedLockBones) do
						local effector = constraint.State.bone
						if isBoneInSubtree(entity, effector, lockedBone.bone) then
							forceCurrentGoal = true
							break
						end
					end
				end

				context.forceCurrentGoal = forceCurrentGoal
				local applied = constraint:EvaluatePose(entity, context)
				if applied and target == entity then
					table.insert(appliedLockBones, { bone = bone })
				end
			end
		end

		for _, constraint in ipairs(linkedLockBones) do
			context.forceCurrentGoal = false
			local applied = constraint:EvaluatePose(entity, context)
			if applied then
				forEachIKAfterLock(constraint, function(dependent, outputEntity, outputBone)
					local client = RagdollPoser.Entity:GetClientFromEntity(outputEntity)
					if IsValid(client) then
						local outputMatrices = RagdollPoser.Entity:GetMatricesFromClient(client)
						if outputMatrices then
							dependentPoseContext.transforms = outputMatrices
							dependent:EvaluatePose(outputEntity, dependentPoseContext)
						end
					end
				end)
			end
		end
	end

	local parent = entity:GetParent()
	local parentStack = IsValid(parent) and EntityConstraintStacks[parent]
	if parentStack then
		for _, constraint in ipairs(parentStack.array) do
			if constraint.Properties.type ~= "bonemerge" or constraint:GetOutputEntity() ~= entity then
				continue
			end

			local root = constraint:GetOutputRoot()
			if isnumber(root) and wasBoneTransformed(entity, root, context.transformedByClient) then
				constraint:EvaluatePose(entity, context)
			end
		end
	end
end

function MGR:Draw()
	for _, stack in pairs(EntityConstraintStacks) do
		for _, constraint in ipairs(stack.array) do
			constraint:Draw()
		end
	end
end

---@param entity Entity
---@param controlledBone integer
---@param locals LocalMatrixInfo[]
---@param parents integer[]
---@param output VMatrix[]
function MGR:PostEvaluate(entity, controlledBone, locals, parents, output)
	local stack = EntityConstraintStacks[entity]
	if stack then
		for _, constraint in ipairs(stack.array) do
			constraint:PostEvaluate(entity, controlledBone, locals, parents, output)
		end
	end
end

---@param entity Entity
---@param type string
---@param state ConstraintState?
---@param name string?
---@return Constraint?
function MGR:Push(entity, type, state, name)
	local stack = EntityConstraintStacks[entity] or createSetArray()
	EntityConstraintStacks[entity] = stack
	refreshStack(entity)
	local constraint = constructConstraint(entity, type, state, name)
	if constraint then
		local index = #stack.array + 1
		stack.array[index] = constraint
		stack.set[constraint._id] = index
		EntityConstraintStacks[entity] = stack
		self:UpdateSingleGraph(entity, constraint)
		hook.Run("RagdollPoser_Constraints_ConstraintCreated", entity, { constraint })
	end
	EntityConstraintStacks[entity] = stack
	self:UpdateConstraints()
end

---@class ConstraintBatch
---@field type string
---@field state ConstraintState?
---@field name string?

---@param entity Entity
---@param batch ConstraintBatch[]
---@return Constraint[]?
function MGR:PushBatch(entity, batch)
	local stack = EntityConstraintStacks[entity] or createSetArray()
	EntityConstraintStacks[entity] = stack
	refreshStack(entity)
	local constraints = {}
	for _, b in ipairs(batch) do
		local type, state, name = b.type, b.state, b.name
		local constraint = constructConstraint(entity, type, state, name)
		if constraint then
			local index = #stack.array + 1
			stack.array[index] = constraint
			stack.set[constraint._id] = index
			constraints[#constraints + 1] = constraint
			EntityConstraintStacks[entity] = stack
		end
	end
	hook.Run("RagdollPoser_Constraints_ConstraintCreated", entity, constraints)
	EntityConstraintStacks[entity] = stack
	self:UpdateConstraints()
	self:UpdateGraph()
end

---@param constraints table<Entity, NetworkedConstraint[]>
function MGR:SetConstraints(constraints)
	---Clear the existing constraint stack for the upcoming one
	---@diagnostic disable-next-line
	EntityConstraintStacks = {}
	for _, serialized in pairs(constraints) do
		for _, s in ipairs(serialized) do
			if isnumber(s._id) then
				MGR._nextConstraintID = math.max(MGR._nextConstraintID or 0, s._id)
			end
		end
	end

	for entity, serialized in pairs(constraints) do
		local array = {}
		local set = {}
		for _, s in ipairs(serialized) do
			local constraint = constructConstraint(entity, RagdollPoser.TypeConstraints[s.Type], s.State, s.Name)
			if constraint then
				local index = #array + 1
				array[index] = constraint
				set[constraint._id] = index
			end
		end
		local stack = { set = set, array = array }
		EntityConstraintStacks[entity] = stack
	end
	self:UpdateGraph()
end

function MGR:AddEntityRelation(entityA, entityB)
	if IsValid(entityA) then
		self.EntityGraph[entityA] = self.EntityGraph[entityA] or createSetArray()
	end
	if IsValid(entityB) then
		self.EntityGraph[entityB] = self.EntityGraph[entityB] or createSetArray()
	end

	if IsValid(entityA) and IsValid(entityB) then
		if not self.EntityGraph[entityA].set[entityB] and not self.EntityGraph[entityB].set[entityA] then
			self.EntityGraph[entityA].set[entityB] = table.insert(self.EntityGraph[entityA].array, entityB)
			self.EntityGraph[entityB].set[entityA] = table.insert(self.EntityGraph[entityB].array, entityA)
		end
	end
end

-- TODO: Add an incremental version so we don't have to traverse this on every Push
function MGR:UpdateGraph()
	self.EntityGraph = {}
	for entity, stack in pairs(EntityConstraintStacks) do
		for _, constraint in ipairs(stack.array) do
			local target = constraint.State.target
			local otherTarget = constraint.State.otherTarget

			self:AddEntityRelation(entity, target)
			self:AddEntityRelation(target, otherTarget)
			self:AddEntityRelation(entity, otherTarget)
		end
	end
end

---@param entity Entity
---@param constraint Constraint
function MGR:UpdateSingleGraph(entity, constraint)
	---@type SetArray<Entity>
	local graph = self.EntityGraph[entity]
	if graph then
		-- Clean up NULL entities
		for e, id in SortedPairsByValue(graph.set, true) do
			if not IsValid(e) then
				graph.set[e] = nil
				table.remove(graph.array, id)
			end
		end
	end

	local constraintEntity = constraint.State.target
	local otherEntity = constraint.State.otherTarget
	self:AddEntityRelation(entity, constraintEntity)
	self:AddEntityRelation(entity, otherEntity)
	self:AddEntityRelation(constraintEntity, otherEntity)
end

---@param entity Entity
---@return SetArray<Entity>
function MGR:GetGraphForEntity(entity)
	return self.EntityGraph[entity]
end

---@param stack Constraints
---@param serializedConstraints SerializedConstraint[]
local function sendConstraints(stack, serializedConstraints)
	net.WriteUInt(#stack.array, RagdollPoser.ConstraintBits)
	for i, constraint in ipairs(serializedConstraints) do
		net.WriteUInt(RagdollPoser.ConstraintTypes[constraint.Type], RagdollPoser.ConstraintTypeBits)
		net.WriteString(constraint.Name)
		net.WriteTable(constraint.State)
	end
end

function MGR:UpdateConstraints()
	for entity, stack in pairs(EntityConstraintStacks) do
		if not IsValid(entity) then
			EntityConstraintStacks[entity] = nil
		end
	end

	RagdollPoser.Networking.UpdateConstraints()
	local entityCount = table.Count(EntityConstraintStacks)
	net.WriteUInt(entityCount, RagdollPoser.Constants.MAX_EDICT_BITS)
	for entity, stack in pairs(EntityConstraintStacks) do
		net.WriteEntity(entity)
		local serializedConstraints = {}
		for _, constraint in ipairs(stack.array) do
			table.insert(serializedConstraints, constraint:Serialize())
		end
		sendConstraints(stack, serializedConstraints)
	end
	net.SendToServer()
end

---@param constraint SerializedConstraint
local function sendConstraint(constraint)
	net.WriteUInt(RagdollPoser.ConstraintTypes[constraint.Type], RagdollPoser.ConstraintTypeBits)
	net.WriteString(constraint.Name)
	net.WriteTable(constraint.State)
end

---@param entity Entity
---@param constraint Constraint
function MGR:UpdateConstraint(entity, constraint)
	for entity, stack in pairs(EntityConstraintStacks) do
		if not IsValid(entity) then
			EntityConstraintStacks[entity] = nil
		end
	end

	local stack = EntityConstraintStacks[entity]
	if stack then
		refreshStack(entity)
		RagdollPoser.Networking.UpdateConstraint()
		net.WriteEntity(entity)
		net.WriteUInt(stack.set[constraint._id], RagdollPoser.ConstraintBits)
		sendConstraint(constraint:Serialize())
		net.SendToServer()
	end
	self:UpdateSingleGraph(entity, constraint)
end

---@param entity Entity
---@param id integer
function MGR:Remove(entity, id)
	local stack = EntityConstraintStacks[entity]
	if stack then
		refreshStack(entity)
		local removedIndex = stack.set[id]
		if not removedIndex then
			return
		end
		table.remove(stack.array, removedIndex)
		refreshStack(entity)
		self:UpdateConstraints()
		self:UpdateGraph()
	end
end

function MGR:Clear(entity)
	local stack = EntityConstraintStacks[entity]
	if stack then
		stack.array = {}
		stack.set = {}
		refreshStack(entity)

		RagdollPoser.Networking.ClearConstraints()
		net.WriteEntity(entity)
		net.SendToServer()
	end
end

---@param entity Entity
---@param c Constraint
---@param d Constraint
function MGR:Swap(entity, c, d)
	local stack = EntityConstraintStacks[entity]
	if not stack then
		return false
	end
	refreshStack(entity)

	local i = stack.set[c._id]
	local j = stack.set[d._id]
	if not i or not j or i == j or stack.array[i] ~= c or stack.array[j] ~= d then
		return false
	end

	stack.array[i], stack.array[j] = d, c
	refreshStack(entity)
	self:UpdateConstraints()
	self:UpdateGraph()
	hook.Run("RagdollPoser_Constraints_ConstraintOrderChanged", entity)
	return true
end

---@param entity Entity
---@param c Constraint
---@param d Constraint
---@param isAfter boolean equivalent to isBelow in UI
function MGR:MoveTo(entity, c, d, isAfter)
	local stack = EntityConstraintStacks[entity]
	if not stack then
		return false
	end
	refreshStack(entity)

	local i = stack.set[c._id]
	local j = stack.set[d._id]
	if not i or not j or i == j or stack.array[i] ~= c or stack.array[j] ~= d then
		return false
	end

	table.remove(stack.array, i)
	refreshStack(entity)
	j = stack.set[d._id]
	local newI = j

	if isAfter then
		newI = newI + 1
	end
	table.insert(stack.array, newI, c)
	refreshStack(entity)
	self:UpdateConstraints()
	hook.Run("RagdollPoser_Constraints_ConstraintOrderChanged", entity)
	return true
end

hook.Remove("EntityRemoved", "RagdollPoser_Constraints_EntityRemoved")
hook.Add("EntityRemoved", "RagdollPoser_Constraints_EntityRemoved", function(ent, fullUpdate)
	if fullUpdate then
		return
	end

	EntityConstraintStacks[ent] = nil
end)

local function onKeyPress(actions, key)
	if actions[RagdollPoser.Actions.ToggleConstraint] then
		local checked = false
		local selected = RagdollPoser.Selection:GetSelectedEntities()
		for client in pairs(selected) do
			local entity = RagdollPoser.Entity:GetEntityFromClient(client)
			local stack = EntityConstraintStacks[entity]
			if not stack then
				continue
			end

			for _, constraint in ipairs(stack.array) do
				if constraint.State.key == key then
					checked = true
					constraint.State.enabled = not constraint.State.enabled
				end
			end
		end

		if checked then
			MGR:UpdateConstraints()
		end
	end
end
hook.Add("RagdollPoser_Input_KeyPress", "RagdollPoser_Constraints_Toggle", onKeyPress)

--- TODO: where should i put constraint UI? in a separate window? in a tab on the control panel? or in a separate tool?

RagdollPoser.Networking.UpdateConstraint = RagdollPoser.Networking.DefineSender("UpdateConstraint")
RagdollPoser.Networking.UpdateConstraints = RagdollPoser.Networking.DefineSender("UpdateConstraints")
RagdollPoser.Networking.ClearConstraints = RagdollPoser.Networking.DefineSender("ClearConstraints")

function MGR:SetRefreshing(state)
	self._refreshing = state
end

function MGR:IsRefreshing(state)
	return self._refreshing
end

RagdollPoser.Constraints = MGR

MGR:Init()

hook.Add("RagdollPoser_Constraints_Refresh", "Constraints", function()
	MGR:Init()
end)
