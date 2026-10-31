---[CLIENT]
---
---@class RagdollPoser.Constraints
local MGR = RagdollPoser.Constraints or {}

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

-- DAG for evaluating constraints

---@param entity Entity
---@param type string
---@param state ConstraintState?
---@param name string?
local function constructConstraint(entity, type, state, name)
	local constructor = MGR.ConstraintConstructors[type]
	if constructor then
		local constraint = constructor(entity, state, name)
		if constraint then
			MGR._nextConstraintID = (MGR._nextConstraintID or 0) + 1
			constraint._id = MGR._nextConstraintID
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

function MGR:Init()
	local files = file.Find("lua/ragdollposer/client/constraints/*.lua", "GAME", "namedesc")
	for _, f in ipairs(files or {}) do
		if f == "base.lua" then
			continue
		end

		---@type fun(): Constraint
		local constructor = include("constraints/" .. f)
		---@type Constraint
		local constraint = constructor()
		table.insert(self.Constraints, constraint)
		self.ConstraintConstructors[constraint.Properties.type] = constructor
	end
end

-- Check for cycles on the stack.
function MGR:ValidateStack() end

function MGR:PreEvaluate(entity, transforms, indices, locals, parents)
	local stack = EntityConstraintStacks[entity]
	if stack then
		for _, constraint in ipairs(stack.array) do
			constraint:PreEvaluate(entity, transforms, indices, locals, parents)
		end
	end
end
function MGR:Evaluate(entity, controlledBone, transforms, indices, locals, parents)
	local stack = EntityConstraintStacks[entity]
	if stack then
		for _, constraint in ipairs(stack.array) do
			constraint:Evaluate(entity, controlledBone, transforms, indices, locals, parents)
		end
	end
end

function MGR:EvaluatePose(entity, controlledBones, transforms)
	local stack = EntityConstraintStacks[entity]
	if stack then
		for _, constraint in ipairs(stack.array) do
			constraint:EvaluatePose(entity, controlledBones, transforms)
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

function MGR:PostEvaluate(entity)
	local stack = EntityConstraintStacks[entity]
	if stack then
		for _, constraint in ipairs(stack.array) do
			constraint:PostEvaluate()
		end
	end
end

---@param entity Entity
---@param type string
---@param state ConstraintState?
---@param name string?
---@return Constraint?
function MGR:Push(entity, type, state, name)
	local stack = EntityConstraintStacks[entity] or { set = {}, array = {} }
	EntityConstraintStacks[entity] = stack
	refreshStack(entity)
	local constraint = constructConstraint(entity, type, state, name)
	if constraint then
		local index = #stack.array + 1
		stack.array[index] = constraint
		stack.set[constraint._id] = index
		EntityConstraintStacks[entity] = stack
		hook.Run("RagdollPoser_Constraints_ConstraintCreated", entity, { constraint })
	end
	EntityConstraintStacks[entity] = stack
	self:UpdateConstraints()
end

---@param constraints table<Entity, SerializedConstraint[]>
function MGR:SetConstraints(constraints)
	print("setting constraints")
	PrintTable(constraints)
	for entity, serialized in pairs(constraints) do
		local array = {}
		local set = {}
		for _, s in ipairs(serialized) do
			local constraint = constructConstraint(entity, s.Type, s.State, s.Name)
			if constraint then
				local index = #array + 1
				array[index] = constraint
				set[constraint._id] = index
			end
		end
		local stack = { set = set, array = array }
		PrintTable(stack)
		EntityConstraintStacks[entity] = stack
	end
end

function MGR:UpdateConstraints()
	for entity, stack in pairs(EntityConstraintStacks) do
		if not IsValid(entity) then
			EntityConstraintStacks[entity] = nil
		end
	end

	RagdollPoser.Networking.UpdateConstraints()
	local count = table.Count(EntityConstraintStacks)
	net.WriteUInt(count, 13)
	for entity, stack in pairs(EntityConstraintStacks) do
		net.WriteEntity(entity)
		local serializedConstraints = {}
		for _, constraint in ipairs(stack.array) do
			table.insert(serializedConstraints, constraint:Serialize())
		end
		net.WriteTable(serializedConstraints, true)
	end
	net.SendToServer()
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
		net.WriteUInt(stack.set[constraint._id], 13)
		net.WriteTable(constraint:Serialize())
		net.SendToServer()
	end
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
			local entity = RagdollPoser.Entity.GetEntityFromClient(client)
			local stack = EntityConstraintStacks[entity]
			if not stack then
				continue
			end

			for _, constraint in ipairs(stack.array) do
				if constraint.State.key == key then
					print("pressed")
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

RagdollPoser.Constraints = MGR

MGR:Init()
