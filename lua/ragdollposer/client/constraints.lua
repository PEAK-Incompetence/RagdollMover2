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
		return constructor(entity, state, name)
	end
end

local function refreshStack(entity, removedIndex)
	local stack = EntityConstraintStacks[entity]
	if stack then
		for i = removedIndex, #stack.array do
			local constraint = stack.array[i]
			stack.set[constraint._id] = i
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
			constraint:PreEvaluate(transforms, indices, locals, parents)
		end
	end
end
function MGR:Evaluate(entity, transforms, indices, locals, parents)
	local stack = EntityConstraintStacks[entity]
	if stack then
		for _, constraint in ipairs(stack.array) do
			constraint:Evaluate(transforms, indices, locals, parents)
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
	local constraint = constructConstraint(entity, type, state, name)
	if constraint then
		stack.set[constraint._id] = table.insert(stack.array, constraint)

		hook.Run("RagdollPoser_Constraints_ConstraintCreated", entity, { constraint })
	end
	EntityConstraintStacks[entity] = stack
	self:UpdateConstraints()
end

---@param constraints table<Entity, SerializedConstraint[]>
function MGR:SetConstraints(constraints)
	print("setting constraints")
	for entity, serialized in pairs(constraints) do
		local array = {}
		local set = {}
		for _, s in ipairs(serialized) do
			local constraint = constructConstraint(entity, s.Type, s.State, s.Name)
			if constraint then
				set[constraint._id] = table.insert(array, constraint)
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

function MGR:UpdateConstraint(entity, constraint)
	for entity, stack in pairs(EntityConstraintStacks) do
		if not IsValid(entity) then
			EntityConstraintStacks[entity] = nil
		end
	end

	local stack = EntityConstraintStacks[entity]
	if stack then
		print("update single constraint")
		PrintTable(stack)
		print(constraint._id)
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
		local removedIndex = stack.set[id]
		table.remove(stack.array, removedIndex)
		refreshStack(entity, removedIndex)
		self:UpdateConstraints()
	end
end

---@param entity Entity
---@param c Constraint
---@param d Constraint
function MGR:Swap(entity, c, d)
	local stack = EntityConstraintStacks[entity]
	if stack then
		local i = stack.set[c._id]
		local j = stack.set[d._id]
		stack.set[c._id] = j
		stack.set[d._id] = i
		stack.array[i] = d
		stack.array[j] = c
		self:UpdateConstraints()
	end
end

hook.Remove("EntityRemoved", "RagdollPoser_Constraints_EntityRemoved")
hook.Add("EntityRemoved", "RagdollPoser_Constraints_EntityRemoved", function(ent, fullUpdate)
	if fullUpdate then
		return
	end

	EntityConstraintStacks[ent] = nil
end)

--- TODO: where should i put constraint UI? in a separate window? in a tab on the control panel? or in a separate tool?

RagdollPoser.Networking.UpdateConstraint = RagdollPoser.Networking.DefineSender("UpdateConstraint")
RagdollPoser.Networking.UpdateConstraints = RagdollPoser.Networking.DefineSender("UpdateConstraints")

RagdollPoser.Constraints = MGR

MGR:Init()
