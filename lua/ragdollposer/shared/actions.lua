---[SERVER AND CLIENT]
---
---For every action
---
---@alias InputAction integer
RagdollPoser.Actions = {
	CycleGizmo = 0,
	SelectBone = 1,
	ToggleConstraint = 2,
}

RagdollPoser.ActionName = table.Flip(RagdollPoser.Actions)
