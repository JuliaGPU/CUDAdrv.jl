# mark symbols as public API without exporting them
const unexported_api = Vector{Expr}()
macro public(ex)
    args = if isa(ex, Symbol)
        (ex,)
    elseif Meta.isexpr(ex, :tuple)
        ex.args
    else
        error("Invalid use of @public")
    end

    for ex in args
        sym = if isa(ex, Symbol)
            ex
        elseif Meta.isexpr(ex, :macrocall)
            ex.args[1]
        else
            error("Invalid argument to @public")
        end

        push!(unexported_api, :($__module__.$sym))
    end

    return
end


# redeclare enum values without a prefix
#
# this is useful when enum values from an underlying C library, typically prefixed for the
# lack of namespacing in C, are to be used in Julia where we do have module namespacing.
#
# the rewritten instances are considered public API
macro enum_without_prefix(enum, prefix)
    if isa(enum, Symbol)
        mod = __module__
    elseif Meta.isexpr(enum, :(.))
        mod = getfield(__module__, enum.args[1])
        enum = enum.args[2].value
    else
        error("Do not know how to refer to $enum")
    end
    enum = getfield(mod, enum)
    prefix = String(prefix)

    ex = quote end
    for instance in instances(enum)
        name = String(Symbol(instance))
        @assert startswith(name, prefix)
        shorthand = Symbol(name[length(prefix)+1:end])
        push!(ex.args, :(const $shorthand = $(mod).$(Symbol(name))))

        push!(unexported_api, :($__module__.$shorthand))
    end

    return esc(ex)
end
