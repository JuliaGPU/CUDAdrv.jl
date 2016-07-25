import Base: unsafe_convert, cconvert

export
    CuLink, complete, destroy, addPTX, addPTXFile

# #if __CUDA_API_VERSION >= 5050


typealias CuLinkState_t Ptr{Void}

immutable CuLink
    handle::CuLinkState_t

    options::Dict{CUjit_option,Any}
    optionKeys::Vector{CUjit_option}
    optionVals::Vector{Ptr{Void}}

    function CuLink()
        handle_ref = Ref{CuLinkState_t}()

        options = Dict{CUjit_option,Any}()
        options[ERROR_LOG_BUFFER] = Array(UInt8, 1024*1024)
        @static if DEBUG
            options[GENERATE_LINE_INFO] = true
            options[GENERATE_DEBUG_INFO] = true

            options[INFO_LOG_BUFFER] = Array(UInt8, 1024*1024)
            options[LOG_VERBOSE] = true
        end
        optionKeys, optionVals = encode(options)

        @apicall(:cuLinkCreate,
                (Cuint, Ptr{CUjit_option}, Ptr{Ptr{Void}}, Ptr{CuModule_t}),
                length(optionKeys), optionKeys, optionVals, handle_ref)

        new(handle_ref[], options, optionKeys, optionVals)
    end
end

"datai sinvalidated after destroy"
function complete(l::CuLink)
    cubin_ref = Ref{Ptr{Void}}()
    size_ref = Ref{Csize_t}()

    try
        @apicall(:cuLinkComplete,
                (Ptr{CuLinkState_t}, Ptr{Ptr{Void}}, Ptr{Csize_t}),
                l.handle, cubin_ref, size_ref)
    catch err
        (err == ERROR_NO_BINARY_FOR_GPU || err == ERROR_INVALID_IMAGE) || rethrow(err)
        options = decode(l.optionKeys, l.optionVals)
        rethrow(CuError(err.code, options[ERROR_LOG_BUFFER]))
    end

    @static if DEBUG
        options = decode(l.optionKeys, l.optionVals)
        if isempty(options[INFO_LOG_BUFFER])
            debug("JIT info log is empty")
        else
            debug("JIT info log: ", repr_indented(options[INFO_LOG_BUFFER]))
        end
    end

    return unsafe_wrap(Array, convert(Ptr{UInt8}, cubin_ref[]), size_ref[])
end

function destroy(l::CuLink)
    @apicall(:cuLinkDestroy, (Ptr{CuLinkState_t},), l.handle)
end

function addPTX(l::CuLink, name::String, data::String)
    # NOTE: ccall can't directly convert String to Ptr{Void}, so do it manually
    typed_ptr = pointer(unsafe_convert(Cstring, cconvert(Cstring, data)))
    untyped_ptr = convert(Ptr{Void}, typed_ptr)

    @apicall(:cuLinkAddData,
             (Ptr{CuLinkState_t}, CUjit_input, Ptr{Void}, Csize_t, Cstring, Cuint, Ptr{CUjit_option}, Ptr{Ptr{Void}}),
             l.handle, PTX, untyped_ptr, length(data), name, 0, C_NULL, C_NULL)
end

function addPTXFile(l::CuLink, path::String)
    @apicall(:cuLinkAddFile,
             (Ptr{CuLinkState_t}, CUjit_input, Cstring, Cuint, Ptr{CUjit_option}, Ptr{Ptr{Void}}),
             l.handle, PTX, path, 0, C_NULL, C_NULL)
end
