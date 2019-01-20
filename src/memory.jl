# Raw memory management

export Mem

module Mem

using CUDAdrv
import CUDAdrv: @apicall, CuStream_t, CuDevice_t



## buffer type

struct Buffer
    ptr::Ptr{Cvoid}
    bytesize::Int

    ctx::CuContext
end

Base.unsafe_convert(::Type{Ptr{T}}, buf::Buffer) where {T} = convert(Ptr{T}, buf.ptr)

function view(buf::Buffer, bytes::Int)
    bytes > buf.bytesize && throw(BoundsError(buf, bytes))
    return Mem.Buffer(buf.ptr+bytes, buf.bytesize-bytes, buf.ctx)
end



## refcounting

const refcounts = Dict{Buffer, Int}()

function refcount(buf::Buffer)
    get(refcounts, Base.unsafe_convert(Ptr{Cvoid}, buf), 0)
end

"""
    retain(buf)

Increase the refcount of a buffer.
"""
function retain(buf::Buffer)
    refcount = get!(refcounts, buf, 0)
    refcounts[buf] = refcount + 1
    return
end

"""
    release(buf)

Decrease the refcount of a buffer. Returns `true` if the refcount has dropped to 0, and
some action needs to be taken.
"""
function release(buf::Buffer)
    haskey(refcounts, buf) || error("Release of unmanaged $buf")
    refcount = refcounts[buf]
    @assert refcount > 0 "Release of dead $buf"
    refcounts[buf] = refcount - 1
    return refcount==1
end


## memory info

"""
    info()

Returns a tuple of two integers, indicating respectively the free and total amount of memory
(in bytes) available for allocation by the CUDA context.
"""
function info()
    free_ref = Ref{Csize_t}()
    total_ref = Ref{Csize_t}()
    @apicall(:cuMemGetInfo, (Ptr{Csize_t},Ptr{Csize_t}), free_ref, total_ref)
    return convert(Int, free_ref[]), convert(Int, total_ref[])
end

"""
    free()

Returns the free amount of memory (in bytes), available for allocation by the CUDA context.
"""
free() = info()[1]

"""
    total()

Returns the total amount of memory (in bytes), available for allocation by the CUDA context.
"""
total() = info()[2]

"""
    used()

Returns the used amount of memory (in bytes), allocated by the CUDA context.
"""
used() = total()-free()


## generic interface (for documentation purposes)

"""
Allocate linear memory on the device and return a buffer to the allocated memory. The
allocated memory is suitably aligned for any kind of variable. The memory will not be freed
automatically, use [`free(::Buffer)`](@ref) for that.
"""
function alloc end

"""
Free device memory.
"""
function free end

"""
Initialize device memory with a repeating value.
"""
function set! end

"""
Upload memory from host to device.
Executed asynchronously on `stream` if `async` is true.
"""
function upload end
@doc (@doc upload) upload!

"""
Download memory from device to host.
Executed asynchronously on `stream` if `async` is true.
"""
function download end
@doc (@doc download) download!

"""
Transfer memory from device to device.
Executed asynchronously on `stream` if `async` is true.
"""
function transfer end
@doc (@doc transfer) transfer!


## pointer-based

@enum(CUmem_attach, ATTACH_GLOBAL = 0x01,
                    ATTACH_HOST   = 0x02)
                    #ATTACH_SINGLE = 0x04) # Defined but not valid
@enum(CUmem_hostalloc, default       = 0x00,
                       mapped        = 0x02,
                       portable      = 0x01,
                       writecombined = 0x04)

function hostalloc(bytesize::Integer, flags::CUmem_hostalloc=default)
    ptr_ref = Ref{Ptr{Cvoid}}()
    @apicall(:cuMemAllocHost, (Ptr{Ptr{Cvoid}}, Csize_t, Cuint), ptr_ref, bytesize, flags)
    return Buffer(ptr_ref[], bytesize, CuCurrentContext())
end

function freehost(buf::Buffer)
    if buf.ptr != C_NULL
    @apicall(:cuMemFreeHost, (Ptr{Cvoid},), buf.ptr)
    end
    return
end
"""
    alloc(bytes::Integer)

Allocate `bytesize` bytes of memory.

Note that, contrary to the CUDA API, zero-size allocations are permitted. Such allocations
will point to the null pointer, and are not attached to a valid context.
"""
function alloc(bytesize::Integer, managed=false; flags::CUmem_attach=ATTACH_GLOBAL)
    bytesize == 0 && return Buffer(C_NULL, 0, CuContext(C_NULL))

    ptr_ref = Ref{Ptr{Cvoid}}()
    if !managed
        @apicall(:cuMemAlloc, (Ptr{Ptr{Cvoid}}, Csize_t), ptr_ref, bytesize)
    else
        @apicall(:cuMemAllocManaged, (Ptr{Ptr{Cvoid}}, Csize_t, Cuint), ptr_ref, bytesize, flags)
    end
    return Buffer(ptr_ref[], bytesize, CuCurrentContext())
end

function prefetch(buf::Buffer, bytes=buf.bytesize; stream::CuStream=CuDefaultStream())
    bytes > buf.bytesize && throw(BoundsError(buf, bytes))
    dev = device(buf.ctx)
    @apicall(:cuMemPrefetchAsync, (Ptr{Cvoid}, Csize_t, CuDevice_t, CuStream_t),
             buf, bytes, dev, stream)
end

@enum(CUmem_advise, ADVISE_SET_READ_MOSTLY          = 0x01,
                    ADVISE_UNSET_READ_MOSTLY        = 0x02,
                    ADVISE_SET_PREFERRED_LOCATION   = 0x03,
                    ADVISE_UNSET_PREFERRED_LOCATION = 0x04,
                    ADVISE_SET_ACCESSED_BY          = 0x05,
                    ADVISE_UNSET_ACCESSED_BY        = 0x06)

function advise(buf::Buffer, advice::CUmem_advise, bytes=buf.bytesize, device=device(buf.ctx))
    bytes > buf.bytesize && throw(BoundsError(buf, bytes))
    @apicall(:cuMemAdvise, (Ptr{Cvoid}, Csize_t, Cuint, CuDevice_t),
             buf, bytes, advice, device)
end

function free(buf::Buffer)
    if buf.ptr != C_NULL
        @apicall(:cuMemFree, (Ptr{Cvoid},), buf.ptr)
    end
    return
end

for T in [UInt8, UInt16, UInt32]
    bits = 8*sizeof(T)
    fn_sync = Symbol("cuMemsetD$(bits)")
    fn_async = Symbol("cuMemsetD$(bits)Async")
    @eval begin
        @doc $"""
            set!(buf::Buffer, value::$T, len::Integer, [stream=CuDefaultStream()]; async=false)

        Initialize device memory by copying the $bits-bit value `val` for `len` times.
        Executed asynchronously if `async` is true.
        """
        function set!(buf::Buffer, value::$T, len::Integer,
                      stream::CuStream=CuDefaultStream(); async::Bool=false)
            if async
                @apicall($(QuoteNode(fn_async)),
                         (Ptr{Cvoid}, $T, Csize_t, CuStream_t),
                         buf.ptr, value, len, stream)
            else
                @assert stream==CuDefaultStream()
                @apicall($(QuoteNode(fn_sync)),
                         (Ptr{Cvoid}, $T, Csize_t),
                         buf.ptr, value, len)
            end
        end
    end
end

"""
    upload!(dst::Buffer, src, nbytes::Integer, [stream=CuDefaultStream()]; async=false)

Upload `nbytes` memory from `src` at the host to `dst` on the device.
"""
function upload!(dst::Buffer, src::Ref, nbytes::Integer,
                 stream::CuStream=CuDefaultStream(); async::Bool=false)
    if async
        @apicall(:cuMemcpyHtoDAsync,
                 (Ptr{Cvoid}, Ptr{Cvoid}, Csize_t, CuStream_t),
                 dst, src, nbytes, stream)
    else
        @assert stream==CuDefaultStream()
        @apicall(:cuMemcpyHtoD,
                 (Ptr{Cvoid}, Ptr{Cvoid}, Csize_t),
                 dst, src, nbytes)
    end
end

#When using pinned host memory, src can be a buffer
function upload!(dst::Buffer, src::Buffer, nbytes::Integer,
                 stream::CuStream=CuDefaultStream(); async::Bool=false)
    if async
        @apicall(:cuMemcpyHtoDAsync,
                 (Ptr{Cvoid}, Ptr{Cvoid}, Csize_t, CuStream_t),
                 dst, src, nbytes, stream)
    else
        @assert stream==CuDefaultStream()
        @apicall(:cuMemcpyHtoD,
                 (Ptr{Cvoid}, Ptr{Cvoid}, Csize_t),
                 dst, src, nbytes)
    end
end

"""
    download!(dst::Ref, src::Buffer, nbytes::Integer, [stream=CuDefaultStream()]; async=false)

Download `nbytes` memory from `src` on the device to `src` on the host.
"""
function download!(dst::Ref, src::Buffer, nbytes::Integer,
                   stream::CuStream=CuDefaultStream(); async::Bool=false)
    if async
        @apicall(:cuMemcpyDtoHAsync,
                 (Ptr{Cvoid}, Ptr{Cvoid}, Csize_t, CuStream_t),
                 dst, src, nbytes, stream)
    else
        @assert stream==CuDefaultStream()
        @apicall(:cuMemcpyDtoH,
                 (Ptr{Cvoid}, Ptr{Cvoid}, Csize_t),
                 dst, src, nbytes)
    end
end
# When using host pinned memory, destination can be a buffer
function download!(dst::Buffer, src::Buffer, nbytes::Integer,
                   stream::CuStream=CuDefaultStream(); async::Bool=false)
    if async
        @apicall(:cuMemcpyDtoHAsync,
                 (Ptr{Cvoid}, Ptr{Cvoid}, Csize_t, CuStream_t),
                 dst, src, nbytes, stream)
    else
        @assert stream==CuDefaultStream()
        @apicall(:cuMemcpyDtoH,
                 (Ptr{Cvoid}, Ptr{Cvoid}, Csize_t),
                 dst, src, nbytes)
    end
end

"""
    transfer!(dst::Buffer, src::Buffer, nbytes::Integer, [stream=CuDefaultStream()]; async=false)

Transfer `nbytes` of device memory from `src` to `dst`.
"""
function transfer!(dst::Buffer, src::Buffer, nbytes::Integer,
                   stream::CuStream=CuDefaultStream(); async::Bool=false)
    if async
        @apicall(:cuMemcpyDtoDAsync,
                 (Ptr{Cvoid}, Ptr{Cvoid}, Csize_t, CuStream_t),
                 dst, src, nbytes, stream)
    else
        @assert stream==CuDefaultStream()
        @apicall(:cuMemcpyDtoD,
                 (Ptr{Cvoid}, Ptr{Cvoid}, Csize_t),
                 dst, src, nbytes)
    end
end


## array based

"""
    alloc(src::AbstractArray)

Allocate space to store the contents of `src`.
"""
function alloc(src::AbstractArray)
    return alloc(sizeof(src))
end

"""
    upload!(dst::Buffer, src::AbstractArray, [stream=CuDefaultStream()]; async=false)

Upload the contents of an array `src` to `dst`.
"""
function upload!(dst::Buffer, src::AbstractArray,
                 stream=CuDefaultStream(); async::Bool=false)
    upload!(dst, Ref(src, 1), sizeof(src), stream; async=async)
end

"""
    upload(src::AbstractArray)::Buffer

Allocates space for and uploads the contents of an array `src`, returning a Buffer.
Cannot be executed asynchronously due to the synchronous allocation.
"""
function upload(src::AbstractArray) # TODO: stream, async
    dst = alloc(src)
    upload!(dst, src)
    return dst
end

"""
    download!(dst::AbstractArray, src::Buffer, [stream=CuDefaultStream()]; async=false)

Downloads memory from `src` to the array at `dst`. The amount of memory downloaded is
determined by calling `sizeof` on the array, so it needs to be properly preallocated.
"""
function download!(dst::AbstractArray, src::Buffer,
                   stream::CuStream=CuDefaultStream(); async::Bool=false)
    ref = Ref(dst, 1)
    download!(ref, src, sizeof(dst), stream; async=async)
    return
end

function loadPinned(dst::Buffer, src::AbstractArray)
    if (sizeof(src) > dst.bytesize) || (sizeof(src) < dst.bytesize)
        throw(ArgumentError("size of destination does not match size of source (bytes)"))
    end
    srcptr = Ref(src, 1)
    ccall((:memcpy, "libc.so.6"),Ptr{Cvoid},(Ptr{Cvoid},Ptr{Cvoid}, Csize_t), dst.ptr, srcptr, dst.bytesize)
    end

function unloadPinned(dst::AbstractArray, src::Buffer)
    if (sizeof(dst) > src.bytesize) || (sizeof(dst) < src.bytesize)
        throw(ArgumentError("size of destination does not match size of source (bytes)"))
    end
    dstptr = Ref(dst,1)
    ccall((:memcpy, "libc.so.6"),Ptr{Cvoid},(Ptr{Cvoid},Ptr{Cvoid}, Csize_t), dstptr, src.ptr, src.bytesize)
end
## type based

function check_type(::Type{Buffer}, T)
    if isa(T, UnionAll) || T.abstract || !isconcretetype(T)
        throw(ArgumentError("cannot represent abstract or non-leaf object"))
    end
    Base.datatype_pointerfree(T) || throw(ArgumentError("cannot handle non-ptrfree objects"))
    sizeof(T) == 0 && throw(ArgumentError("cannot represent singleton objects"))
end

"""
    alloc(T::Type, [count::Integer=1])

Allocate space for `count` objects of type `T`.
"""
function alloc(::Type{T}, count::Integer=1) where {T}
    check_type(Buffer, T)

    return alloc(sizeof(T)*count)
end

"""
    download(::Type{T}, src::Buffer, [count::Integer=1], [stream=CuDefaultStream()]; async=false)::Vector{T}

Download `count` objects of type `T` from the device at `src`, returning a vector.
"""
function download(::Type{T}, src::Buffer, count::Integer=1,
                  stream::CuStream=CuDefaultStream(); async::Bool=false) where {T}
    dst = Vector{T}(undef, count)
    download!(dst, src, stream; async=async)
    return dst
end

end
