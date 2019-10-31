using CUDAdrv

using Test

@testset "CUDAdrv" begin

# make sure everything we export actually exists
for sym in names(CUDAdrv)
    getfield(CUDAdrv, sym)
end

# idem for the unexported API
for x in CUDAdrv.unexported_api
    @assert Meta.isexpr(x, :(.))
    mod, name = x.args
    getfield(mod, name.value)
end

include("util.jl")
include("array.jl")

include("pointer.jl")

@test length(devices()) > 0
if length(devices()) > 0
    @test CuCurrentContext() == nothing

    # pick most recent device (based on compute capability)
    global dev = nothing
    for newdev in devices()
        if dev == nothing || capability(newdev) > capability(dev)
            dev = newdev
        end
    end
    @info "Testing using device $(name(dev))"

    global ctx = CuContext(dev)
    @test CuCurrentContext() != nothing

    @testset "API wrappers" begin
        include("errors.jl")
        include("version.jl")
        include("devices.jl")
        include("context.jl")
        include("module.jl")
        include("memory.jl")
        include("stream.jl")
        include("execution.jl")
        include("events.jl")
        include("profile.jl")
        include("occupancy.jl")
    end

    include("gc.jl")

    include("examples.jl")
end

end
