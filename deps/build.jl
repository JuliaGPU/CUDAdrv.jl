# Discover the CUDA library

using Compat

const ext = joinpath(@__DIR__, "ext.jl")
try
    include(joinpath(dirname(@__DIR__), "src", "util", "logging.jl"))

    libcuda_name = is_windows() ? "nvcuda.dll" : "libcuda"
    debug("looking for $libcuda_name")

    libcuda = Libdl.find_library(libcuda_name)
    if libcuda == ""
        # NOTE: we don't immediately call `find_library` wich a set of (popular) locations,
        #       because those arbitrary locations might then override the system configuration
        #       (e.g. ld.so.conf) or user preferences (LD_LIBRARY_PATH)
        libcuda = Libdl.find_library(libcuda_name, ["/opt/cuda/lib", "/usr/local/cuda/lib"])
    end
    if isempty(libcuda)
        error("Could not find CUDA library; is the CUDA driver installed?")
    end

    # find the full path of the library
    # NOTE: we could just as well use the result of `find_library,
    #       but the user might have run this script with eg. LD_LIBRARY_PATH set
    #       so we save the full path in order to always be able to load the correct library
    libcuda_path = Libdl.dlpath(libcuda)
    info("found $libcuda at $libcuda_path")

    # find the library vendor
    libcuda_vendor = "NVIDIA"
    debug("vendor: $libcuda_vendor")

    # find the library version
    # NOTE: should be kept in sync with src/version.jl::version()
    version_ref = Ref{Cint}()
    lib = Libdl.dlopen(libcuda)
    sym = Libdl.dlsym(lib, :cuDriverGetVersion)
    status = ccall(sym, Cint, (Ptr{Cint},), version_ref)
    if status != 0
        error("could not obtain CUDA library version")
    end
    major = version_ref[] ÷ 1000
    minor = mod(version_ref[], 100) ÷ 10
    libcuda_version = VersionNumber(major, minor)
    debug("version: $libcuda_version")

    # check if we need to rebuild
    if isfile(ext)
        debug("checking validity of existing ext.jl")
        @eval module Previous; include($ext); end
        if  isdefined(Previous, :libcuda_version) && Previous.libcuda_version == libcuda_version &&
            isdefined(Previous, :libcuda_path)    && Previous.libcuda_path == libcuda_path &&
            isdefined(Previous, :libcuda_vendor)  && Previous.libcuda_vendor == libcuda_vendor
            info("CUDAdrv.jl has already been built for this CUDA library, no need to rebuild.")
            return
        end
    end

    # write ext.jl
    open(ext, "w") do fh
        write(fh, """
            const libcuda_path = "$(escape_string(libcuda_path))"
            const libcuda_version = v"$libcuda_version"
            const libcuda_vendor = "$libcuda_vendor"
            """)
    end
catch ex
    # if anything goes wrong, wipe the existing ext.jl to prevent the package from loading
    rm(ext; force=true)
    rethrow(ex)
end
