---[CLIENT]
---
---@class RagdollPoser.Constants
local MGR = {}

---@enum Space
MGR.Space = {
	World = 0,
	Custom = 1,
	Pose = 2,
	Local = 3,
}

local ConstraintStacks = {}

-- DAG for evaluating constraints

-- Check for cycles on the stack.
function MGR:ValidateStack() end

function MGR:EvaluateStack(transforms, indices, locals, parents) end

function MGR:Push(constraint) end

function MGR:Remove() end

function MGR:Swap(c, d) end

--- TODO: where should i put constraint UI? in a separate window? in a tab on the control panel? or in a separate tool?

RagdollPoser.Constraints = MGR
