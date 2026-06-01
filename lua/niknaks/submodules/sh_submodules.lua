local function RegisterSubmodule(name, files)
    if SERVER then
        for _, file in ipairs(files) do
            AddCSLuaFile(file)
        end
    end

    local function onDemandLoad(self, key)
        setmetatable(NikNaks[name], nil)
        NikNaks[name] = {}
        for _, file in ipairs(files) do
            include(file)
        end
        return NikNaks[name][key]
    end

    NikNaks[name] = setmetatable({}, {
        __index = onDemandLoad
    })
end

RegisterSubmodule("Path", {
    "niknaks/submodules/ai/sh_map.lua",
    "niknaks/submodules/ai/sh_node.lua",
    "niknaks/submodules/ai/sh_file.lua",
    "niknaks/submodules/ai/sh_pathfinder.lua",
})
