# Contiguous on-device arrays (host side representation)

export
    CuArray, CuVector, CuMatrix


## construction

"""
    CuArray{T}(dims)
    CuArray{T,N}(dims)

Construct an uninitialized `N`-dimensional dense CUDA array with element type `T`, where `N`
is determined from the length or number of `dims`. `dims` may be a tuple or a series of
integer arguments corresponding to the lengths in each dimension. If the rank `N` is
supplied explicitly as in `Array{T,N}(dims)`, then it must match the length or number of
`dims`.

Type aliases `CuVector` and `CuMatrix` are available for respectively 1 and 2-dimensional
data.
"""
CuArray

@compat type CuArray{T,N} <: AbstractArray{T,N}
    devptr::DevicePtr{T}
    shape::NTuple{N,Int}

    # inner constructors (exact types, ie. Int not <:Integer)
    function (::Type{CuArray{T,N}}){T,N}(shape::NTuple{N,Int})
        if !isbits(T)
            # non-isbits types results in an array with references to CPU objects
            throw(ArgumentError("CuArray with non-bit element type not supported"))
        elseif (sizeof(T) == 0)
            throw(ArgumentError("CuArray with zero-sized element types does not make sense"))
        end

        len = prod(shape)
        devptr = Mem.alloc(T, len)

        obj = new{T,N}(devptr, shape)
        finalizer(obj, unsafe_free!)
        return obj
    end
    function (::Type{CuArray{T,N}}){T,N}(shape::NTuple{N,Int}, devptr::DevicePtr{T})
        # semi-hidden constructor, only called by unsafe_convert
        new{T,N}(devptr, shape)
    end
end

@compat const CuVector{T} = CuArray{T,1}
@compat const CuMatrix{T} = CuArray{T,2}

# outer constructors, partially parameterized
(::Type{CuArray{T}}){T,N,I<:Integer}(dims::NTuple{N,I})   = CuArray{T,N}(dims)
(::Type{CuArray{T}}){T,N,I<:Integer}(dims::Vararg{I,N})   = CuArray{T,N}(dims)

# outer constructors, fully parameterized
(::Type{CuArray{T,N}}){T,N,I<:Integer}(dims::NTuple{N,I}) = CuArray{T,N}(Int.(dims))
(::Type{CuArray{T,N}}){T,N,I<:Integer}(dims::Vararg{I,N}) = CuArray{T,N}(Int.(dims))

function unsafe_free!(a::CuArray)
    if isvalid(a.devptr.ctx)
        @trace("Finalizing CuArray at $(Base.pointer_from_objref(a))")
        Mem.free(a.devptr)
        a.devptr = CU_NULL
    else
        @trace("Skipping finalizer for CuArray at $(Base.pointer_from_objref(a))) because context is no longer valid")
    end
end

Base.unsafe_convert{T}(::Type{DevicePtr{T}}, a::CuArray{T}) = a.devptr

Base.:(==)(a::CuArray, b::CuArray) = a.devptr == b.devptr
Base.hash(a::CuArray, h::UInt) = hash(a.devptr, h)

Base.pointer(a::CuArray) = a.devptr

# override the Base isequal, which compares values
Base.isequal(a::CuArray, b::CuArray) = a == b

Base.similar{T}(a::CuVector{T})                     = CuArray{T}(length(a))
Base.similar{T}(a::CuVector{T}, S::Type)            = CuArray{S}(length(a))
Base.similar{T}(a::CuArray{T}, m::Int)              = CuArray{T}(m)
Base.similar{N}(a::CuArray, T::Type, dims::Dims{N}) = CuArray{T,N}(dims)
Base.similar{T,N}(a::CuArray{T}, dims::Dims{N})     = CuArray{T,N}(dims)


## array interface

Base.size(g::CuArray) = g.shape
Base.length(g::CuArray) = prod(g.shape)

Base.showarray(io::IO, a::CuArray, repr::Bool = true; kwargs...) =
    Base.showarray(io, Array(a), repr; kwargs...)


## memory management

"""
    copy!{T}(dst::CuArray{T}, src::Array{T})

Copy an array from a host array `src` to a device array `dst` in place. Both arrays should
have an equal length.
"""
function Base.copy!{T}(dst::CuArray{T}, src::Array{T})
    if length(dst) != length(src)
        throw(ArgumentError("Inconsistent array length."))
    end
    Mem.upload(dst.devptr, pointer(src), length(src) * sizeof(T))
    return dst
end

"""
    copy!{T}(dst::Array{T}, src::CuArray{T})

Copy an array from a device array `src` to a host array `dst` in place. Both arrays should
have an equal length.
"""
function Base.copy!{T}(dst::Array{T}, src::CuArray{T})
    if length(dst) != length(src)
        throw(ArgumentError("Inconsistent array length."))
    end
    Mem.download(pointer(dst), src.devptr, length(src) * sizeof(T))
    return dst
end

"""
    copy!{T}(dst::CuArray{T}, src::CuArray{T})

Copy an array from a device array `src` to a device array `dst` in place. Both arrays should
have an equal length.
"""
function Base.copy!{T}(dst::CuArray{T}, src::CuArray{T})
    if length(dst) != length(src)
        throw(ArgumentError("Inconsistent array length."))
    end
    Mem.transfer(dst.devptr, src.devptr, length(src) * sizeof(T))
    return dst
end


### convenience functions

"""
    CuArray{T}(src::Array{T})

Transfer a host array `src` to device, returning a [`CuArray`](@ref).
"""
CuArray{T,N}(src::Array{T,N}) = copy!(CuArray{T,N}(size(src)), src)

"""
    Array{T}(g::CuArray{T})

Transfer a device array `src` to host, returning an `Array`.
"""
Base.Array{T,N}(src::CuArray{T,N}) = copy!(Array{T,N}(size(src)), src)
