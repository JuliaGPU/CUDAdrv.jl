# Contiguous on-device arrays

import Base: length, size, copy!, unsafe_convert, Array

export
    CuArray, free


type CuArray{T,N} <: AbstractArray{T,N}
    ptr::DevicePtr{T}
    shape::NTuple{N,Int}
    len::Int

    function CuArray(::Type{T}, shape::NTuple{N,Int})
        if (sizeof(T) == 0)
            throw(ArgumentError("CuArray with zero-sized element types does not make sense"))
        end
        len = prod(shape)
        ptr = cualloc(T, len)
        new(ptr, shape, len)
    end
end


## Host-side functionality

# Define outer constructors for parameter-less construction
CuArray{T}(::Type{T}, len::Int) = CuArray{T,1}(T, (len,))
CuArray{T,N}(::Type{T}, shape::NTuple{N,Int}) = CuArray{T,N}(T, shape)

unsafe_convert{T,N}(::Type{DevicePtr{T}}, a::CuArray{T,N}) = a.ptr

"Free GPU memory allocated to the pointer"
function free(g::CuArray)
    if !isnull(g.ptr)
        free(g.ptr)
        g.ptr = DevicePtr{eltype(g.ptr)}()
    end
end

"Copy an array from device to host in place"
function copy!{T}(dst::Array{T}, src::CuArray{T})
    if length(dst) != length(src) 
        throw(ArgumentError("Inconsistent array length."))
    end
    nbytes = length(src) * sizeof(T)
    @apicall(:cuMemcpyDtoH, (Ptr{Void}, Ptr{Void}, Csize_t),
                           pointer(dst), src.ptr.inner, nbytes)
    return dst
end

"Copy an array from host to device in place"
function copy!{T}(dst::CuArray{T}, src::Array{T})
    if length(dst) != length(src)
        throw(ArgumentError("Inconsistent array length."))  
    end
    nbytes = length(src) * sizeof(T)
    @apicall(:cuMemcpyHtoD, (Ptr{Void}, Ptr{Void}, Csize_t),
                           dst.ptr.inner, pointer(src), nbytes)
    return dst
end

"Transfer an array from host to device, returning a pointer on the device"
CuArray{T,N}(a::Array{T,N}) = copy!(CuArray(T, size(a)), a)

"Transfer an array on the device to host"
Array{T}(g::CuArray{T}) = copy!(Array(T, size(g)), g)


## Generic functionality

length(g::CuArray) = g.len
size(g::CuArray) = g.shape
