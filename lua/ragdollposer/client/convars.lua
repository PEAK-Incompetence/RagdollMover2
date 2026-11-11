---@alias InputConVarInfo {[1]: InputAction, [2]: ConVar}

---@type InputConVarInfo[]
local inputConVars = {}

local changeCallbackSuffix = "_change_callback"

---@param name string
---@param helptext string
---@param default string|number
---@param action InputAction
---@return ConVar
local function registerInputConVar(name, helptext, default, action)
	local convar = CreateClientConVar(name, default, true, true, helptext, BUTTON_CODE_NONE, BUTTON_CODE_LAST)
	local function changeCallback(cvar, old, new)
		if string.match(new[1], "%a") then
			new = input.GetKeyCode(new[1])
		end
		new = tonumber(new)
		if new then
			RagdollPoser.Input:RegisterKey(action, new)
		end
	end
	cvars.RemoveChangeCallback(name, name .. changeCallbackSuffix)
	cvars.AddChangeCallback(name, changeCallback, name .. changeCallbackSuffix)

	table.insert(inputConVars, { action, convar })

	return convar
end

registerInputConVar("ragdollposer_cycle_key", "Input for switching gizmo modes", KEY_E, RagdollPoser.Actions.CycleGizmo)
registerInputConVar(
	"ragdollposer_select_key",
	"Input for switching to bone select mode",
	KEY_LALT,
	RagdollPoser.Actions.SelectBone
)
registerInputConVar(
	"ragdollposer_select_root_key",
	"Input for switching between the root bone and selected bone",
	KEY_R,
	RagdollPoser.Actions.SelectRoot
)

local function refreshKeys()
	for _, convarInfo in ipairs(inputConVars) do
		RagdollPoser.Input:RegisterKey(convarInfo[1], convarInfo[2]:GetInt())
	end
end

hook.Add("CreateMove", "RagdollPoser_InitializeKeys", function(_)
	refreshKeys()

	hook.Remove("CreateMove", "RagdollPoser_InitializeKeys")
end)
