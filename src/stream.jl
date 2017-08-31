# Stream management

export
    CuStream, CuDefaultStream, synchronize


const CuStream_t = Ptr{Void}

type CuStream
    handle::CuStream_t
    ctx::CuContext
end

Base.unsafe_convert(::Type{CuStream_t}, s::CuStream) = s.handle

Base.:(==)(a::CuStream, b::CuStream) = a.handle == b.handle
Base.hash(s::CuStream, h::UInt) = hash(s.handle, h)

"""
    CuStream(flags=0)

Create a CUDA stream.
"""
function CuStream(flags::Integer=0)
    handle_ref = Ref{CuStream_t}()
    @apicall(:cuStreamCreate, (Ref{CuStream_t}, Cuint),
                              handle_ref, flags)

    ctx = CuCurrentContext()
    obj = CuStream(handle_ref[], ctx)
    finalizer(obj, unsafe_destroy!)
    return obj
end

function unsafe_destroy!(s::CuStream)
    if isvalid(s.ctx)
        @trace("Finalizing CuStream object at $(Base.pointer_from_objref(s))")
        @apicall(:cuStreamDestroy, (CuModule_t,), s)
    else
        @trace("Skipping finalizer for CuStream object at $(Base.pointer_from_objref(s)) because context is no longer valid")
    end
end

"""
    CuDefaultStream()

Return the default stream.
"""
@inline CuDefaultStream() = CuStream(convert(CuStream_t, C_NULL), CuContext(C_NULL))

"""
    synchronize(s::CuStream)

Wait until a stream's tasks are completed.
"""
synchronize(s::CuStream) = @apicall(:cuStreamSynchronize, (CuStream_t,), s)
