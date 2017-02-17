# Stream management

export
    CuStream, CuDefaultStream, synchronize


const CuStream_t = Ptr{Void}

type CuStream
    handle::CuStream_t
    ctx::CuContext
    function CuStream(handle::CuStream_t, ctx=CuCurrentContext())
        obj = new(handle, ctx)
        block_finalizer(obj, ctx)
        finalizer(obj, finalize)
        return obj
    end
    CuStream(handle::CuStream_t, ctx::CuContext, _) = new(handle, ctx)
end

Base.unsafe_convert(::Type{CuStream_t}, s::CuStream) = s.handle

Base.:(==)(a::CuStream, b::CuStream) = a.handle == b.handle
Base.hash(s::CuStream, h::UInt) = hash(s.handle, h)

function CuStream(flags::Integer=0)
    handle_ref = Ref{CuStream_t}()
    @apicall(:cuStreamCreate, (Ptr{CuStream_t}, Cuint),
                              handle_ref, flags)

    return CuStream(handle_ref[])
end

function finalize(s::CuStream)
    @trace("Finalizing CuStream at $(Base.pointer_from_objref(s))")
    @apicall(:cuStreamDestroy, (CuModule_t,), s)
    unblock_finalizer(s, s.ctx)
end

@inline CuDefaultStream() = CuStream(convert(CuStream_t, C_NULL), CuContext(C_NULL), 0)

synchronize(s::CuStream) = @apicall(:cuStreamSynchronize, (CuStream_t,), s)
