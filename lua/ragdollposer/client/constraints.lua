---[CLIENT]
---
---@class RagdollPoser.Constants
local MGR = {}

---@alias Space integer
MGR.Space = {
	World = 0,
	Custom = 1,
	Pose = 2,
	Local = 3,
}

---@type Constraint[]
MGR.Constraints = {}
---@type table<string, fun(state: ConstraintState?): Constraint>
MGR.ConstraintConstructors = {}

-- Store constraints per selection? It's data after all
local ConstraintStacks = {}

-- DAG for evaluating constraints

function MGR:GetConstraints()
	return self.Constraints
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

---@param type string
---@param state ConstraintState?
---@return Constraint?
function MGR:Push(type, state)
	local constructor = self.ConstraintConstructors[type]
	if constructor then
		local constraint = constructor(state)
		table.insert(ConstraintStacks, constraint)

		hook.Run("RagdollPoser_Constraints_ConstraintCreated", { constraint })
	end
end

function MGR:Remove() end

function MGR:Swap(c, d) end

--- TODO: where should i put constraint UI? in a separate window? in a tab on the control panel? or in a separate tool?

RagdollPoser.Constraints = MGR

MGR:Init()
