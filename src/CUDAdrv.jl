__precompile__()

module CUDAdrv

using Compat
using Compat.String

include("../deps/ext.jl")

const ONLY_LOAD = haskey(ENV, "CUDADRV_ONLY_LOAD")

if ONLY_LOAD
    # special mode where the package is loaded without requiring a successful build.
    # this is useful for loading in unsupported environments, eg. Travis + Documenter.jl
    const libcuda_path = ""
    const libcuda_version = v"999"  # make sure all functions are available
end
const libcuda = libcuda_path

include(joinpath("util", "logging.jl"))

include("types.jl")
include("base.jl")

# CUDA Driver API wrappers
include("init.jl")
include("errors.jl")
include("version.jl")
include("devices.jl")
include("context.jl")
include(joinpath("context", "primary.jl"))
include("pointer.jl")   # not a wrapper, but used by them
include("module.jl")
include("memory.jl")
include("stream.jl")
include("events.jl")
include("execution.jl")
include("profile.jl")

include("array.jl")

include("deprecated.jl")

end
