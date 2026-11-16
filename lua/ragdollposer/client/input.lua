---[CLIENT]
---
---Handle input events by sending them through one place for other systems to hook onto
---
---Requirements
--- - There shall only be one keybind per action
---
---@class RagdollPoser.Input
---@
local MGR = RagdollPoser.Input or {
	xMove = 0,
	yMove = 0,
}

---@type table<InputAction, table<BUTTON_CODE, true>>
MGR.BoundActions = MGR.BoundActions or {}
---@type table<BUTTON_CODE, table<InputAction, true>>
MGR.KeyBinds = {}

---@type BUTTON_CODE[]
MGR.ActiveKeybinds = MGR.ActiveKeybinds or {}

local function refreshKeyBinds()
	local keySeen = {}
	MGR.ActiveKeybinds = {}
	MGR.KeyBinds = {}

	for action, keys in pairs(MGR.BoundActions) do
		for key in pairs(keys) do
			MGR.KeyBinds[key] = MGR.KeyBinds[key] or {}
			MGR.KeyBinds[key][action] = true
			if not keySeen[key] then
				MGR.ActiveKeybinds[#MGR.ActiveKeybinds + 1] = key
				keySeen[key] = true
			end
		end
	end
end
refreshKeyBinds()

---@param action InputAction
---@param keycode BUTTON_CODE
function MGR:UnregisterKey(action, keycode)
	-- If we are reassigning an action to another key, we need to remove it from the keybinds
	local keybinds = MGR.BoundActions[action] or {}
	keybinds[keycode] = nil
	MGR.BoundActions[action] = keybinds
	refreshKeyBinds()
	RagdollPoser.Log("Unregistered keybind ", input.GetKeyName(keycode), " for ", RagdollPoser.ActionName[action])
end

---@param action InputAction
---@param keycode BUTTON_CODE
function MGR:RegisterKey(action, keycode)
	-- If we are reassigning an action to another key, we need to remove it from the keybinds
	local keybinds = MGR.BoundActions[action] or {}
	keybinds[keycode] = true
	MGR.BoundActions[action] = keybinds
	refreshKeyBinds()
	RagdollPoser.Log("Registered keybind ", input.GetKeyName(keycode), " for ", RagdollPoser.ActionName[action])
end

---@alias InputCallback fun(x: integer, y: integer, tr: TraceResult)

---@type TraceResult
local traceOutput = {
	HitPos = vector_origin,
	Normal = vector_origin,
	StartPos = vector_origin,
}
local lastCheck = RealTime()

---@param cmd CUserCmd
local function mouseInput(cmd)
	local pl = LocalPlayer()
	local equipped = RagdollPoser.Helpers.Equipped()
	if equipped then
		local eyePos = MainEyePos()
		util.TraceLine({
			start = eyePos,
			endpos = eyePos + pl:GetAimVector() * 16384,
			filter = { pl, pl:GetViewEntity() },
			ignoreworld = RagdollPoser.Helpers.CanXRaySelect(pl, tobool(GetConVar("ragdollposer_xray"):GetBool())),
			output = traceOutput,
		})
		local tr = traceOutput

		local now = RealTime()
		local allowInput = now - lastCheck > RealFrameTime()
		local x, y = input.GetCursorPos()
		-- Get left-click and right-click events
		if (input.WasMousePressed(MOUSE_LEFT) or input.WasMouseDoublePressed(MOUSE_LEFT)) and allowInput then
			hook.Run("RagdollPoser_Input_LeftClickDown", x, y, tr)
			lastCheck = now
		end
		if input.WasMouseReleased(MOUSE_LEFT) and allowInput then
			hook.Run("RagdollPoser_Input_LeftClickUp", x, y, tr)
			lastCheck = now
		end
		if (input.WasMousePressed(MOUSE_RIGHT) or input.WasMouseDoublePressed(MOUSE_RIGHT)) and allowInput then
			hook.Run("RagdollPoser_Input_RightClickDown", x, y, tr)
			lastCheck = now
		end
		if input.WasMouseReleased(MOUSE_RIGHT) and allowInput then
			hook.Run("RagdollPoser_Input_RightClickUp", x, y, tr)
			lastCheck = now
		end
	end
end

hook.Remove("CreateMove", "RagdollPoser_MouseInput")
hook.Add("CreateMove", "RagdollPoser_MouseInput", mouseInput)

local keysDown = {}
local function keyboardInput()
	local equipped = RagdollPoser.Helpers.Equipped()
	if equipped then
		for _, key in ipairs(MGR.ActiveKeybinds) do
			if input.IsKeyDown(key) and not keysDown[key] then
				keysDown[key] = true
				local actions = MGR.KeyBinds[key]
				if actions then
					hook.Run("RagdollPoser_Input_KeyPress", MGR.KeyBinds[key], key)
				end
			elseif not input.IsKeyDown(key) and keysDown[key] then
				keysDown[key] = false
			end
		end
	end
end
hook.Remove("PlayerButtonDown", "RagdollPoser_KeyboardInput")
hook.Remove("KeyPress", "RagdollPoser_KeyboardInput")
hook.Remove("Think", "RagdollPoser_KeyboardInput")
hook.Add("Think", "RagdollPoser_KeyboardInput", keyboardInput)

local function mouseDelta(cmd, x, y, ang)
	MGR.xMove = x
	MGR.yMove = y
end
hook.Add("InputMouseApply", "RagdollPoser_MouseDelta", mouseDelta)

function MGR:ResetDelta()
	self.xMove = 0
	self.yMove = 0
end

RagdollPoser.Input = MGR
