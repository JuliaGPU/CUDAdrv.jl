# Error type and decoding functionality

export CuError


#
# Versioning error
#

struct CuVersionError <: Exception
    symbol::Symbol
    minver::VersionNumber
end

function Base.showerror(io::IO, err::CuVersionError)
    @printf(io, "CUDA API version mismatch: use of %s requires at least CUDA %s",
            err.symbol, err.minver)
end


#
# API errors
#

# forward declaration in base.jl

Base.:(==)(x::CuError,y::CuError) = x.code == y.code

# NOTE: `name` and `description` require CUDA to be initialized
#       (and do they work in case of error 100 or 999?)

"""
    name(err::CuError)

Gets the string representation of an error code.

This name can often be used as a symbol in source code to get an instance of this error.
For example:

```jldoctest
julia> using CUDAdrv

julia> err = CuError(1)
CuError(1, ERROR_INVALID_VALUE)

julia> name(err)
"ERROR_INVALID_VALUE"

julia> CUDAdrv.ERROR_INVALID_VALUE
CuError(1, ERROR_INVALID_VALUE)
```
"""
function name(err::CuError)
    if vendor() == :rCUDA
        return string(get(return_codes, err.code, :ERROR_UNKNOWN))
    else
        str_ref = Ref{Cstring}()
        @apicall(:cuGetErrorName, (CuError_t, Ptr{Cstring}), err.code, str_ref)
        unsafe_string(str_ref[])[6:end]
    end
end

"""
    description(err::CuError)

Gets the string description of an error code.
"""
function description(err::CuError)
    str_ref = Ref{Cstring}()
    @apicall(:cuGetErrorString, (CuError_t, Ptr{Cstring}), err.code, str_ref)
    unsafe_string(str_ref[])
end

function Base.showerror(io::IO, err::CuError)
    @printf(io, "CUDA error: %s (code #%d, %s)", description(err), err.code, name(err))

    if err.meta != nothing
        print(io, "\n")
        print(io, err.meta)
    end
end

Base.show(io::IO, err::CuError) = @printf(io, "CuError(%d, %s)", err.code, name(err))

# known error constants
const return_codes = Dict{CuError_t,Symbol}(
    0   => :SUCCESS,

    1   => :ERROR_INVALID_VALUE,
    2   => :ERROR_OUT_OF_MEMORY,
    3   => :ERROR_NOT_INITIALIZED,
    4   => :ERROR_DEINITIALIZED,
    5   => :ERROR_PROFILER_DISABLED,
    6   => :ERROR_PROFILER_NOT_INITIALIZED,
    7   => :ERROR_PROFILER_ALREADY_STARTED,
    8   => :ERROR_PROFILER_ALREADY_STOPPED,
    100 => :ERROR_NO_DEVICE,
    101 => :ERROR_INVALID_DEVICE,
    200 => :ERROR_INVALID_IMAGE,
    201 => :ERROR_INVALID_CONTEXT,
    202 => :ERROR_CONTEXT_ALREADY_CURRENT,
    205 => :ERROR_MAP_FAILED,
    206 => :ERROR_UNMAP_FAILED,
    207 => :ERROR_ARRAY_IS_MAPPED,
    208 => :ERROR_ALREADY_MAPPED,
    209 => :ERROR_NO_BINARY_FOR_GPU,
    210 => :ERROR_ALREADY_ACQUIRED,
    211 => :ERROR_NOT_MAPPED,
    212 => :ERROR_NOT_MAPPED_AS_ARRAY,
    213 => :ERROR_NOT_MAPPED_AS_POINTER,
    214 => :ERROR_ECC_UNCORRECTABLE,
    215 => :ERROR_UNSUPPORTED_LIMIT,
    216 => :ERROR_CONTEXT_ALREADY_IN_USE,
    217 => :ERROR_PEER_ACCESS_UNSUPPORTED,
    218 => :ERROR_INVALID_PTX,
    300 => :ERROR_INVALID_SOURCE,
    301 => :ERROR_FILE_NOT_FOUND,
    302 => :ERROR_SHARED_OBJECT_SYMBOL_NOT_FOUND,
    303 => :ERROR_SHARED_OBJECT_INIT_FAILED,
    304 => :ERROR_OPERATING_SYSTEM,
    400 => :ERROR_INVALID_HANDLE,
    500 => :ERROR_NOT_FOUND,
    600 => :ERROR_NOT_READY,
    700 => :ERROR_ILLEGAL_ADDRESS,
    701 => :ERROR_LAUNCH_OUT_OF_RESOURCES,
    702 => :ERROR_LAUNCH_TIMEOUT,
    703 => :ERROR_LAUNCH_INCOMPATIBLE_TEXTURING,
    704 => :ERROR_PEER_ACCESS_ALREADY_ENABLED,
    705 => :ERROR_PEER_ACCESS_NOT_ENABLED,
    708 => :ERROR_PRIMARY_CONTEXT_ACTIVE,
    709 => :ERROR_CONTEXT_IS_DESTROYED,
    710 => :ERROR_ASSERT,
    711 => :ERROR_TOO_MANY_PEERS,
    712 => :ERROR_HOST_MEMORY_ALREADY_REGISTERED,
    713 => :ERROR_HOST_MEMORY_NOT_REGISTERED,
    714 => :ERROR_HARDWARE_STACK_ERROR,
    715 => :ERROR_ILLEGAL_INSTRUCTION,
    716 => :ERROR_MISALIGNED_ADDRESS,
    717 => :ERROR_INVALID_ADDRESS_SPACE,
    718 => :ERROR_INVALID_PC,
    719 => :ERROR_LAUNCH_FAILED,
    800 => :ERROR_NOT_PERMITTED,
    801 => :ERROR_NOT_SUPPORTED,
    999 => :ERROR_UNKNOWN
)
for code in return_codes
    @eval const $(code[2]) = CuError($(code[1]))
end
