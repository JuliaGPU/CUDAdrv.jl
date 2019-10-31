module CUDAdrv

using CEnum

using Printf


## source code includes

# essential functionality
include("pointer.jl")
const CUdeviceptr = CuPtr{Cvoid}

include("util.jl")

# low-level wrappers
include("libcuda_common.jl")
include("error.jl")
include("libcuda.jl")
include("libcuda_aliases.jl")

# high-level wrappers
include("version.jl")
include("devices.jl")
include("context.jl")
include(joinpath("context", "primary.jl"))
include("stream.jl")
include("memory.jl")
include("module.jl")
include("events.jl")
include("execution.jl")
include("profile.jl")
include("occupancy.jl")

include("deprecated.jl")


## initialization

function __init__()
    if ccall(:jl_generating_output, Cint, ()) == 1
        # don't initialize when we, or any package that depends on us, is precompiling.
        # this makes it possible to precompile on systems without CUDA,
        # at the expense of using the packages in global scope.
        return
    end

    silent = parse(Bool, get(ENV, "CUDA_INIT_SILENT", "false"))
    try
        # compiler barrier to avoid *seeing* `ccall`s to unavailable libraries
        Base.invokelatest(__hidden_init__)
        @eval functional() = true
    catch ex
        # don't actually fail to keep the package loadable
        silent || @error """CUDAdrv.jl failed to initialize; the package will not be functional.
                            To silence this message, import with ENV["CUDA_INIT_SILENT"]=true,
                            and be sure to inspect the value of CUDAdrv.functional().""" exception=(ex, catch_backtrace())
        @eval functional() = false
    end
end

function __hidden_init__()
    if haskey(ENV, "_") && basename(ENV["_"]) == "rr"
        error("Running under rr, which is incompatible with CUDA")
    end

    cuInit(0)

    if version() <= v"9"
        @warn "CUDAdrv.jl only supports NVIDIA drivers for CUDA 9.0 or higher (yours is for CUDA $(version()))"
    end
end

end
