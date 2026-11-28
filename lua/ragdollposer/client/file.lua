---[CLIENT]
---
---File related operations, input and output
---
---@class RagdollPoser.File
local MGR = {}

---@enum ConstraintLoadType
MGR.ConstraintLoadType = {
    Replace = 0,
    Append = 1,
    Prepend = 2,
}

MGR.ConstraintLoadError = {
    ReadError = 1,
    DeserializeError = 2,
    InvalidError = 3,
}

MGR.ConstraintSaveError = {
    EmptyError = 1,
    SaveFailedError = 2,
}

MGR.ConstraintTypeLoad = table.Flip(MGR.ConstraintLoadType)
---@param constraints NetworkedConstraint[]
local function getConstraintBatch(constraints)
    ---@type ConstraintBatch[]
    local batch = {}
    for i, constraint in ipairs(constraints) do
        batch[i] = {
            type = constraint.Type,
            state = constraint.State,
            name = constraint.Name
        }
    end
    return batch
end

---@type table<ConstraintLoadType, fun(entity: Entity, constraints: NetworkedConstraint[], targetSelected: boolean)>
MGR.ConstraintLoadTypeFunctions = {
    [MGR.ConstraintLoadType.Replace] = function(entity, constraints, targetSelected)
        return pcall(RagdollPoser.Constraints.SetEntityConstraints, RagdollPoser.Constraints, entity, constraints)
    end,
    [MGR.ConstraintLoadType.Append] = function(entity, constraints, targetSelected)
        local batch = getConstraintBatch(constraints)
        return pcall(RagdollPoser.Constraints.PushBatch, RagdollPoser.Constraints, entity, batch)
    end,
    [MGR.ConstraintLoadType.Prepend] = function(entity, constraints, targetSelected)
        local batch = getConstraintBatch(constraints)
        return pcall(RagdollPoser.Constraints.PushBatch, RagdollPoser.Constraints, entity, batch, 1)
    end,
}

---@param selected Entity Entity to load constraints
---@param path string Constraint path to open
---@param loadType ConstraintLoadType How to load constraints
---@param targetSelected boolean Whether to have selected stuff work
---@param loadCallback function Callback for deferred requests
function MGR:LoadConstraintPreset(selected, path, loadType, targetSelected, loadCallback)
    RagdollPoser.Log("Load constraint preset ", path, " with type ", self.ConstraintTypeLoad[loadType],
        ". Target selected: ",
        targetSelected)

    local constraintString = file.Read(path, "DATA")
    if not constraintString then return false, self.ConstraintLoadError.ReadError end

    local constraints = util.JSONToTable(constraintString)
    if not constraints then return false, self.ConstraintLoadError.DeserializeError end

    local loadFunc = self.ConstraintLoadTypeFunctions[loadType]

    if loadFunc then
        local function doLoad()
            local success, err = loadFunc(selected, constraints, targetSelected)
            loadCallback(success, err)
        end

        local existing = RagdollPoser.Constraints:GetConstraintStack(selected)
        if loadType == MGR.ConstraintLoadType.Replace and existing[1] then
            Derma_Query("#tool.ragdollposer.constraint.load.warning", "#tool.ragdollposer.warning",
                "#tool.ragdollposer.load", doLoad,
                "#tool.ragdollposer.cancel")
        else
            doLoad()
        end
        return true
    else
        return false, self.ConstraintLoadError.InvalidError
    end
end

---@param constraints Constraint[]
---@param path string Constraint path to save
function MGR:SaveConstraintPreset(constraints, path)
    RagdollPoser.Log("Save constraint preset ", path)

    if not constraints[1] then
        -- Don't save empty constraint presets
        return false, self.ConstraintSaveError.EmptyError
    end

    ---@type NetworkedConstraint[]
    local serialized = {}
    for i, constraint in ipairs(constraints) do
        local s = constraint:Serialize(true)
        s._id = nil
        serialized[i] = s
    end

    local json = util.TableToJSON(serialized, true)
    local code = 0
    local saveOperation = false
    if json then
        saveOperation = file.Write(path, json)
        if not saveOperation then
            code = self.ConstraintSaveError.SaveFailedError
        end
    end

    return saveOperation, code
end

---@param path string Subtitle path to open
function MGR:LoadCustomSubtitles(path)
    MsgN("Load subtitles ", path)
end

local function initializeDirectories()
    if not file.IsDir("ragdollposer", "DATA") then
        file.CreateDir("ragdollposer")
    end

    if not file.IsDir("ragdollposer/constraints", "DATA") then
        file.CreateDir("ragdollposer/constraints")
    end

    if not file.IsDir("ragdollposer/subtitles", "DATA") then
        file.CreateDir("ragdollposer/subtitles")
    end
end

local function storeConstraintDefaults()
    local dataStatic = "data_static/ragdollposer/constraints/"
    local data = "ragdollposer/constraints/"
    local files = {
        "default_ik_hl2.txt",
        "default_ik_tf2.txt"
    }

    for _, f in ipairs(files) do
        local path = dataStatic .. f
        local newPath = data .. f
        if not file.Exists(newPath, "DATA") then
            print("do write")
            file.Write(newPath, file.Read(path, "GAME"))
        end
    end
end

function MGR:Initialize()
    initializeDirectories()
    storeConstraintDefaults()
end

RagdollPoser.File = MGR

MGR:Initialize()
