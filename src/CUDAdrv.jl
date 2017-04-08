__precompile__()

module CUDAdrv

using Compat
using Compat.String

const ext = joinpath(dirname(@__DIR__), "deps", "ext.jl")
if !isfile(ext)
    error("Unable to load $ext\n\nPlease run Pkg.build(\"CUDAdrv\") and restart Julia.")
else
    include(ext)
end
const libcuda = libcuda_path

include(joinpath("util", "logging.jl"))

# CUDA API wrappers
include("errors.jl")
include("base.jl")
include("devices.jl")
include("context.jl")
include(joinpath("context", "primary.jl"))
include("pointer.jl")
include("module.jl")
include("memory.jl")
include("stream.jl")
include("execution.jl")
include("events.jl")
include("profile.jl")

include("array.jl")

function __init__()
    # check validity of CUDA library
    @debug("Checking validity of $(libcuda_path)")
    if version() != libcuda_version
        error("CUDA library version has changed. Please re-run Pkg.build(\"CUDAdrv\") and restart Julia.")
    end

    __init_logging__()
    if haskey(ENV, "_") && basename(ENV["_"]) == "rr"
        warn("running under rr, which is incompatible with CUDA -- disabling initialization")
    else
        @apicall(:cuInit, (Cint,), 0)
    end
end

end
