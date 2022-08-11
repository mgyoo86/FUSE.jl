import AbstractTrees

abstract type AbstractParameter end
abstract type AbstractParameters end

#= ===== =#
#  Entry  #
#= ===== =#
mutable struct Entry{T} <: AbstractParameter
    _name::Union{Missing,Symbol}
    _parent::WeakRef
    units::String
    description::String
    value::T
    base::T
    default::T
    lower::Union{Missing,Float64}
    upper::Union{Missing,Float64}
end

"""
    Entry(T, units::String, description::String; default = missing)

Defines a entry parameter
"""
function Entry(T, units::String, description::String; default=missing)
    return Entry{Union{Missing,T}}(missing, WeakRef(missing), units, description, default, default, default, missing, missing)
end

function Entry(T, ids::Type, field::Symbol; default=missing)
    txt = IMAS.info(ids, field)
    return Entry(T, get(txt, "units", ""), get(txt, "documentation", ""); default)
end

#= ====== =#
#  Switch  #
#= ====== =#
struct SwitchOption
    value::Any
    description::String
end

mutable struct Switch <: AbstractParameter
    _name::Union{Missing,Symbol}
    _parent::WeakRef
    options::Dict{Any,SwitchOption}
    units::String
    description::String
    value::Any
    base::Any
    default::Any
end

"""
    Switch(options, units::String, description::String; default = missing)

Defines a switch parameter
"""
function Switch(options::Dict{Any,SwitchOption}, units::String, description::String; default=missing)
    if !in(default, keys(options))
        error("$(repr(default)) is not a valid option: $(collect(keys(options)))")
    end
    return Switch(missing, WeakRef(missing), options, units, description, default, default, default)
end

function Switch(options::Vector{<:Pair}, units::String, description::String; default=missing)
    opts = Dict{Any,SwitchOption}()
    for (key, desc) in options
        opts[key] = SwitchOption(key, desc)
    end
    return Switch(missing, WeakRef(missing), opts, units, description, default, default, default)
end

function Switch(options::Vector{<:Union{Symbol,String}}, units::String, description::String; default=missing)
    opts = Dict{eltype(options),SwitchOption}()
    for key in options
        opts[key] = SwitchOption(key, "$key")
    end
    return Switch(missing, WeakRef(missing), opts, units, description, default, default, default)
end

function Switch(options, ids::Type{<:IMAS.IDS}, field::Symbol; default=missing)
    location = "$(IMAS.fs2u(ids)).$(field)"
    txt = IMAS.info(location)
    return Switch(options, get(txt, "units", ""), get(txt, "documentation", ""); default)
end

function Base.setproperty!(p::Switch, key::Symbol, value)
    if typeof(value) <: Pair
        p.options[value.first].value = value.second
        value = value.first
    end
    if (value !== missing) && !(value in keys(p.options))
        throw(BadParameterException([key], value, collect(keys(p.options))))
    end
    return setfield!(p, :value, value)
end

function parameter_color(p::AbstractParameter)
    value = p.value
    if value === missing
        color = :yellow
    elseif typeof(value) == typeof(p.default) && value == p.default
        color = :green
    elseif typeof(value) == typeof(p.base) && value == p.base
        color = :blue
    else
        color = :red
    end
end

function Base.show(io::IO, p::AbstractParameter)
    color = parameter_color(p)
    printstyled(io, join(path(p), "."); bold=true, color=color)
    for item in fieldnames(typeof(p))
        if startswith(string(item), "_")
            continue
        end
        printstyled(io, "\n- $item: "; bold=true)
        printstyled(io, "$(getfield(p, item))")
    end
end

#= ====================== =#
#  Optimization parameter  #
#= ====================== =#
struct OptParameter
    nominal::Real
    lower::Real
    upper::Real
end

"""
    ↔(x::Real, r::AbstractVector)

"leftrightarrow" unicode constructor for OptParameter
"""
function ↔(x::Real, r::AbstractVector)
    @assert typeof(x) == typeof(r[1]) == typeof(r[end]) "type of optimization range does not match the nominal value"
    return OptParameter(x, r[1], r[end])
end

function opt_parameters(p::AbstractParameters, opt_vector=AbstractParameter[])
    _parameters = getfield(p, :_parameters)
    for k in keys(_parameters)
        parameter = _parameters[k]
        if typeof(parameter) <: AbstractParameters
            opt_parameters(parameter, opt_vector)
        elseif typeof(parameter) <: Entry
            if parameter.lower !== missing
                push!(opt_vector, parameter)
            end
        end
    end
    return opt_vector
end

#= ============== =#
#  ParametersInit  #
#= ============== =#
mutable struct ParametersInit <: AbstractParameters
    _name::Union{Missing,Symbol}
    _parent::WeakRef
    _parameters::Dict{Symbol,Union{AbstractParameter,AbstractParameters}}
end

function ParametersInit(::Nothing)
    return ParametersInit(missing, WeakRef(missing), Dict{Symbol,Union{AbstractParameter,ParametersInit}}())
end

function ParametersInit(group::Symbol; kw...)
    if length(methods(ParametersInit, (Type{Val{group}},))) == 0
        throw(InexistentParameterException(ParametersInit, [group]))
    end
    par = ParametersInit(Val{group}; kw...)
    par._name = group
    return par
end

#= ================== =#
#  ParametersAllInits  #
#= ================== =#
mutable struct ParametersAllInits <: AbstractParameters
    _name::Union{Missing,Symbol}
    _parent::WeakRef
    _parameters::Dict{Symbol,Union{AbstractParameter,AbstractParameters}}
end

function ParametersAllInits(::Nothing)
    return ParametersAllInits(missing, WeakRef(missing), Dict{Symbol,Union{AbstractParameter,ParametersInit}}())
end

"""
    ParametersAllInits()

Generates all initalization parameters 
"""
function ParametersAllInits()
    ini = ParametersAllInits(missing, WeakRef(missing), Dict{Symbol,Union{AbstractParameter,ParametersInit}}())
    for item in [:general, :equilibrium, :core_profiles, :pf_active, :oh, :tf, :center_stack, :nbi, :ec_launchers, :ic_antennas, :lh_antennas, :build, :gasc, :ods, :material, :target]
        setproperty!(ini, item, ParametersInit(item))
    end
    ini._name = :ini
    return ini
end

#= =============== =#
#  ParametersActor  #
#= =============== =#
mutable struct ParametersActor <: AbstractParameters
    _name::Union{Missing,Symbol}
    _parent::WeakRef
    _parameters::Dict{Symbol,Union{AbstractParameter,AbstractParameters}}
end

function ParametersActor(::Nothing)
    return ParametersActor(missing, WeakRef(missing), Dict{Symbol,Union{AbstractParameter,ParametersActor}}())
end

function ParametersActor(group::Symbol; kw...)
    if length(methods(ParametersActor, (Type{Val{group}},))) == 0
        throw(InexistentParameterException(ParametersActor, [group]))
    end
    pars = ParametersActor(Val{group}; kw...)
    pars._name = group
    return pars
end

#= =================== =#
#  ParametersAllActors  #
#= =================== =#
mutable struct ParametersAllActors <: AbstractParameters
    _name::Union{Missing,Symbol}
    _parent::WeakRef
    _parameters::Dict{Symbol,Union{AbstractParameter,AbstractParameters}}
end

function ParametersAllActors(::Nothing)
    return ParametersAllActors(missing, WeakRef(missing), Dict{Symbol,Union{AbstractParameter,ParametersActor}}())
end

"""
    ParametersAllActors()

Generates actor parameters 
"""
function ParametersAllActors()
    act = ParametersAllActors(missing, WeakRef(missing), Dict{Symbol,Union{AbstractParameter,ParametersActor}}())
    for par in concretetypes(AbstractActor)
        par = Symbol(replace(string(par), "FUSE." => ""))
        try
            setproperty!(act, par, ParametersActor(par))
        catch e
            if typeof(e) <: InexistentParameterException
                @warn sprint(showerror, e)
            else
                rethrow()
            end
        end
    end

    act._name = :act
    return act
end

#= ========== =#
#  Parameters  #
#= ========== =#
function path(p::Union{AbstractParameter,AbstractParameters})
    name = getfield(p, :_name)
    if name === missing
        return Symbol[]
    end
    pp = Symbol[name]
    while typeof(p._parent.value) <: AbstractParameters
        if p._parent.value._name === missing
            break
        end
        pushfirst!(pp, p._parent.value._name)
        p = p._parent.value
    end
    return pp
end

function Base.keys(p::AbstractParameters)
    return keys(getfield(p, :_parameters))
end

function Base.values(p::AbstractParameters)
    return values(getfield(p, :_parameters))
end

function Base.getindex(p::AbstractParameters, field::Symbol)
    return getfield(p, :_parameters)[field]
end

function Base.setindex!(p::AbstractParameters, value::Any, field::Symbol)
    return getfield(p, :_parameters)[field] = value
end

function Base.getproperty(p::AbstractParameters, key::Symbol)
    if key ∈ fieldnames(typeof(p))
        return getfield(p, key)
    elseif key ∉ keys(p)
        throw(InexistentParameterException(typeof(p), vcat(path(p), key)))
    end
    parameter = p[key]

    if typeof(parameter) <: AbstractParameters
        value = parameter
    elseif typeof(parameter) <: Entry
        value = parameter.value
    elseif typeof(parameter) <: Switch
        if parameter.value === missing
            throw(NotsetParameterException(vcat(path(p), key), collect(keys(parameter.options))))
        end
        value = parameter.options[parameter.value].value
    else
        error("Unrecognized type $(typeof(parameter))")
    end

    if value === missing
        throw(NotsetParameterException(vcat(path(p), key)))
    end

    return value
end

"""
    getproperty(p::AbstractParameters, key::Symbol, default)

Return value of `key` parameter or `default` if parameter is missing
NOTE: This is useful because accessing a `missing` parameter would raise an error
"""
function Base.getproperty(p::AbstractParameters, key::Symbol, default)
    value = p[key].value
    if value === missing
        return default
    else
        return value
    end
end

function Base.deepcopy(p::Union{AbstractParameter,AbstractParameters})
    p1 = Base.deepcopy_internal(p, Base.IdDict())
    p1._parent = WeakRef(missing)
    return p1
end

function Base.setproperty!(p::AbstractParameters, key::Symbol, value)
    if key ∈ fieldnames(typeof(p))
        return setfield!(p, key, value)
    elseif typeof(value) <: Union{AbstractParameter,AbstractParameters}
        if typeof(value._parent.value) <: Union{AbstractParameter,AbstractParameters}
            value = deepcopy(value)
        end
        setfield!(value, :_parent, WeakRef(p))
        setfield!(value, :_name, key)
        p[key] = value
        return value
    end

    if !(key in keys(p))
        throw(InexistentParameterException(typeof(p), vcat(path(p), key)))
    end
    parameter = p[key]

    if typeof(parameter) <: Switch
        try
            return parameter.value = value
        catch e
            if typeof(e) <: BadParameterException # retrhow the exception but add more to the path information
                throw(BadParameterException(vcat(path(p), key), value, collect(keys(parameter.options))))
            end
        end
    else
        if typeof(value) <: OptParameter
            parameter.value = value.nominal
            if typeof(value.nominal) <: Integer
                parameter.lower = value.lower - 0.5
                parameter.upper = value.upper + 0.5
            else
                parameter.lower = value.lower
                parameter.upper = value.upper
            end
        else
            return parameter.value = value
        end
    end

    return value
end

function Base.iterate(par::AbstractParameters)
    Base.iterate(par, collect(keys(par)))
end

function Base.iterate(par::AbstractParameters, state)
    if isempty(state)
        return nothing
    end
    key = popfirst!(state)
    data = par[key]#.value
    return key => data, state
end

function Base.show(io::IO, ::MIME"text/plain", pars::AbstractParameters, depth::Int=0)
    return AbstractTrees.print_tree(io, pars)
end

function AbstractTrees.children(pars::AbstractParameters)
    return [pars[k] for k in sort(collect(keys(pars)))]
end

function AbstractTrees.printnode(io::IO, pars::AbstractParameters)
    printstyled(io, pars._name; bold=true)
end

function AbstractTrees.children(par::AbstractParameter)
    if typeof(par.value) <: AbstractDict
        return [k => par.value[k] for k in sort(collect(keys(par.value)))]
    else
        return []
    end
end

function AbstractTrees.printnode(io::IO, par::AbstractParameter)
    color = parameter_color(par)
    if typeof(par.value) <: AbstractDict
        printstyled(io, "$(par._name)[:]"; bold=true)
    else
        printstyled(io, par._name)
        printstyled(io, " ➡ ")
        printstyled(io, "$(repr(par.value))"; color=color)
        if length(replace(par.units,"-"=>"")) > 0 && par.value !== missing
            printstyled(io, " [$(par.units)]"; color=color)
        end
    end
end

function set_new_base!(p::AbstractParameters)
    for item in keys(p)
        parameter = p[item]
        if typeof(parameter) <: AbstractParameters
            set_new_base!(parameter)
        else
            setfield!(parameter, :base, parameter.value)
        end
    end
    return p
end

function Base.ismissing(p::AbstractParameters, field::Symbol)::Bool
    return p[field].value === missing
end

"""
    (par::AbstractParameters)(kw...)

This functor is used to override the parameters at function call
"""
function (par::AbstractParameters)(kw...)
    par = deepcopy(par)
    if !isempty(kw)
        for (key, value) in kw
            setproperty!(par, key, value)
        end
    end
    return par
end

function doc(parameters::AbstractParameters)
    if typeof(parameters) <: ParametersActor
        ppath = "act.$(parameters._name)"
    else
        ppath = "ini.$(parameters._name)"
    end
    txt = []
    for par in sort(collect(keys(parameters)))
        if typeof(parameters[par]) <: AbstractParameters
            push!(txt, "**`$(ppath).$par`**: $(typeof(parameters[par]))")
        else
            if isempty(parameters[par].units)
                units = ""
            else
                units = " [$(parameters[par].units)]"
            end
            push!(txt, "**`$(ppath).$par`**:$units $(parameters[par].description)")
        end
    end
    if isempty(txt)
        return ""
    else
        return "* " * join(txt, "\n* ")
    end
end

"""
    par2dict(par::AbstractParameters)

Convert FUSE parameters to dictionary
"""
function par2dict(par::AbstractParameters)
    ret = Dict()
    return par2dict!(par, ret)
end

function par2dict!(par::AbstractParameters, ret::AbstractDict)
    data = getfield(par, :_parameters)
    return par2dict!(data, ret)
end

function par2dict!(data::AbstractDict, ret::AbstractDict)
    for item in keys(data)
        if typeof(data[item]) <: AbstractParameters
            ret[item] = Dict()
            par2dict!(data[item], ret[item])
        elseif typeof(data[item]) <: AbstractParameter
            ret[item] = Dict()
            ret[item][:value] = data[item].value
            ret[item][:units] = data[item].units
            ret[item][:description] = data[item].description
        end
    end
    return ret
end

"""
    ini2json(ini::ParametersAllInits, filename::String; kw...)

Save the FUSE parameters to a JSON file with give `filename`
`kw` arguments are passed to the JSON.print function
"""
function ini2json(ini::ParametersAllInits, filename::String; kw...)
    return par2json(ini, filename; kw...)
end

"""
    act2json(act::ParametersAllActors, filename::String; kw...)

Save the FUSE parameters to a JSON file with give `filename`
`kw` arguments are passed to the JSON.print function
"""
function act2json(act::ParametersAllActors, filename::String; kw...)
    return par2json(act, filename; kw...)
end

function par2json(@nospecialize(par::AbstractParameters), filename::String; kw...)
    open(filename, "w") do io
        JSON.print(io, par2dict(par); kw...)
    end
end

function dict2par!(dct::AbstractDict, par::AbstractParameters)
    for (key, val) in par
        if typeof(val) <: AbstractParameters
            dict2par!(dct[string(key)], val)
        elseif dct[string(key)]["value"] === nothing
            setproperty!(par, key, missing)
        elseif typeof(dct[string(key)]["value"]) <: AbstractVector # this could be done more generally
            setproperty!(par, key, Real[k for k in dct[string(key)]["value"]])
        else
            try
                setproperty!(par, key, Symbol(dct[string(key)]["value"]))
            catch e
                try
                    setproperty!(par, key, dct[string(key)]["value"])
                catch e
                    display((key, e))
                end
            end
        end
    end
    return par
end

function json2par(filename::AbstractString, par_data::AbstractParameters)
    json_data = JSON.parsefile(filename)
    return dict2par!(json_data, par_data)
end

function json2ini(filename::AbstractString)
    return json2par(filename, ParametersAllInits())
end

function json2act(filename::AbstractString)
    return json2par(filename, ParametersAllActors())
end

#= ================= =#
#  Parameters errors  #
#= ================= =#
struct InexistentParameterException <: Exception
    parameter_type::DataType
    path::Vector{Symbol}
end
Base.showerror(io::IO, e::InexistentParameterException) = print(io, "$(e.parameter_type).$(join(e.path,".")) does not exist")

struct NotsetParameterException <: Exception
    path::Vector{Symbol}
    options::Vector{Any}
end
NotsetParameterException(path::Vector{Symbol}) = NotsetParameterException(path, [])
function Base.showerror(io::IO, e::NotsetParameterException)
    if length(e.options) > 0
        print(io, "Parameter $(join(e.path,".")) is not set. Valid options are: $(join(map(repr,e.options),", "))")
    else
        print(io, "Parameter $(join(e.path,".")) is not set")
    end
end

struct BadParameterException <: Exception
    path::Vector{Symbol}
    value::Any
    options::Vector{Any}
end
Base.showerror(io::IO, e::BadParameterException) =
    print(io, "Parameter $(join(e.path,".")) = $(repr(e.value)) is not one of the valid options: $(join(map(repr,e.options),", "))")

#= ============ =#
#  case studies  #
#= ============ =#
# NOTE only called once at precompile time, kernel needs to be restarted to include new file in cases
for filename in readdir(joinpath(@__DIR__, "..", "cases"))
    if endswith(filename, ".jl")
        include("../cases/" * filename)
    end
end

function case_parameters(case::Symbol; kw...)
    if length(methods(case_parameters, (Type{Val{case}},))) == 0
        throw(InexistentParameterException(Parameters, [case]))
    end
    return case_parameters(Val{case}; kw...)
end

#= ======= =#
#  prepare  #
#= ======= =#
"""
    prepare(actor_type::DataType, dd::IMAS.dd, act::ParametersAllActors; kw...)

Dispatch `prepare` function for different actors based on actor_type that is passed
"""
function prepare(dd::IMAS.dd, actor_name::Symbol, act::ParametersAllActors; kw...)
    prepare(dd, Val{actor_name}, act; kw...)
    return dd
end