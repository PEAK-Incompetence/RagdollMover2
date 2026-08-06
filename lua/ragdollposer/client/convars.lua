---@alias InputConVarInfo {[1]: InputAction, [2]: ConVar}

---@type InputConVarInfo[]
local inputConVars = {}

---@param name string
---@param helptext string
---@param default string|number
---@param action InputAction
---@return ConVar
local function registerInputConVar(name, helptext, default, action)
	local convar = CreateClientConVar(name, default, true, true, helptext, BUTTON_CODE_NONE, BUTTON_CODE_LAST)

	table.insert(inputConVars, { action, convar })

	return convar
end

registerInputConVar("ragdollposer_cycle_key", "Input for switching gizmo modes", KEY_E, RagdollPoser.Actions.CycleGizmo)

local function refreshKeys()
	for _, convarInfo in ipairs(inputConVars) do
		RagdollPoser.Input:RegisterKey(convarInfo[1], convarInfo[2]:GetInt())
	end
end

hook.Add("CreateMove", "RagdollPoser_InitializeServerReceiver", function(_)
	refreshKeys()

	hook.Remove("CreateMove", "RagdollPoser_InitializeServerReceiver")
end)
