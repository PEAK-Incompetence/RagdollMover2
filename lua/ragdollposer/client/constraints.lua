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
---@type table<string, fun(props: ConstraintProps?, state: ConstraintState?): Constraint>
MGR.ConstraintConstructors = {}

-- Store constraints per entity
-- And cascade updates, so if we moved an IK target that both entities share, both entities should update
-- So that means iterate over entityconstraintstacks?
---@type table<Entity, Constraint[]>
local EntityConstraintStacks = MGR.EntityConstraintStacks or {}
MGR.EntityConstraintStacks = EntityConstraintStacks

-- DAG for evaluating constraints

---@param type string
---@param props ConstraintProps?
---@param state ConstraintState?
local function constructConstraint(type, props, state)
	local constructor = MGR.ConstraintConstructors[type]
	if constructor then
		return constructor(props, state)
	end
end

function MGR:GetConstraints()
	return self.Constraints
end

function MGR:GetConstraintStack(entity)
	return EntityConstraintStacks[entity]
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

function MGR:EvaluateStack(transforms, indices, locals, parents) end

---@param entity Entity
---@param type string
---@param props ConstraintProps?
---@param state ConstraintState?
---@return Constraint?
function MGR:Push(entity, type, props, state)
	local stack = EntityConstraintStacks[entity] or {}
	local constraint = constructConstraint(type, props, state)
	if constraint then
		table.insert(stack, constraint)

		hook.Run("RagdollPoser_Constraints_ConstraintCreated", entity, { constraint })
	end
	EntityConstraintStacks[entity] = stack
	self:UpdateConstraints()
end

---@param constraints table<Entity, SerializedConstraint[]>
function MGR:SetConstraints(constraints)
	for entity, serialized in pairs(constraints) do
		local deserialized = {}
		for _, s in ipairs(serialized) do
			local constraint = constructConstraint(s.Type, s.Properties, s.State)
			if constraint then
				table.insert(deserialized, constraint)
			end
		end
		EntityConstraintStacks[entity] = deserialized
	end
end

function MGR:UpdateConstraints()
	RagdollPoser.Networking.UpdateConstraints()
	net.WriteUInt(table.Count(EntityConstraintStacks), 13)
	for entity, constraints in pairs(EntityConstraintStacks) do
		net.WriteEntity(entity)
		local serializedConstraints = {}
		for _, constraint in ipairs(constraints) do
			table.insert(serializedConstraints, constraint:Serialize())
		end
		net.WriteTable(serializedConstraints, true)
	end
	net.SendToServer()
end

function MGR:Remove(entity)
	self:UpdateConstraints()
end

function MGR:Swap(entity, c, d)
	self:UpdateConstraints()
end

--- TODO: where should i put constraint UI? in a separate window? in a tab on the control panel? or in a separate tool?

RagdollPoser.Networking.UpdateConstraints = RagdollPoser.Networking.DefineSender("UpdateConstraints")

RagdollPoser.Constraints = MGR

MGR:Init()
