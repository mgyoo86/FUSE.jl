import RABBIT
using Plots

#= =========== =#
#  ActorRABBIT  #
#= =========== =#
Base.@kwdef mutable struct FUSEparameters__ActorRABBIT{T<:Real} <: ParametersActorPlasma{T}
    _parent::WeakRef = WeakRef(nothing)
    _name::Symbol = :not_set
    _time::Float64 = NaN
end

mutable struct ActorRABBIT{D,P} <: SingleAbstractActor{D,P}
    dd::IMAS.dd{D}
    par::FUSEparameters__ActorRABBIT{P}
    outputs::Union{RABBIT.RABBIToutputs,Vector{<:RABBIT.RABBIToutputs}}
end

function ActorRABBIT(dd::IMAS.dd, par::FUSEparameters__ActorRABBIT; kw...)
    par = par(kw...)
    return ActorRABBIT(dd, par, RABBIT.RABBIToutputs[])
end

"""
    ActorRABBIT(dd::IMAS.dd, act::ParametersAllActors; kw...)

"""
function ActorRABBIT(dd::IMAS.dd, act::ParametersAllActors; kw...)
    actor = ActorRABBIT(dd, act.ActorRABBIT; kw...)
    step(actor)
    finalize(actor)
    return actor
end

function _step(actor::ActorRABBIT)
    dd = actor.dd
    
    all_inputs = RABBIT.FUSEtoRABBITinput(dd)

    powe_data, powi_data, rho_data, time_data = RABBIT.run_RABBIT(all_inputs; remove_inputs=true)
    output = RABBIT.RABBIToutputs()

    output.powe_data = powe_data
    output.powi_data = powi_data
    output.rho_data = rho_data 
    output.time_data = time_data 

    actor.outputs = output

    return actor

end

function _finalize(actor::ActorRABBIT)
    dd = actor.dd
    cs = dd.core_sources

    num_t = length(actor.outputs.time_data)
    num_rho = length(actor.outputs.rho_data)

    powe = reshape(actor.outputs.powe_data, num_rho, num_t)
    powi = reshape(actor.outputs.powi_data, num_rho, num_t)

    source = resize!(cs.source, :nbi, "identifier.name" => "nbi"; wipe=false)
    prof_1d = resize!(source.profiles_1d, num_t)[num_t]
    ion = resize!(source.profiles_1d[1].ion, 1)[1] # fix this

    source.profiles_1d[1].grid.rho_tor_norm = actor.outputs.rho_data
    for i in 1:length(num_t)
        source.profiles_1d[i].ion[1].energy = powi[:,i]
        source.profiles_1d[i].electrons.energy = powe[:,i] 
    end

    p = plot(actor.outputs.rho_data, powe[:,1])

    for i in 2:length(actor.outputs.time_data)
        plot!(p, actor.outputs.rho_data, powe[:,i])
    end

    xlabel!(p, "rho")
    ylabel!(p, "Power density profile to electrons - W/m^3 ")
    display(p)

    pp = plot(actor.outputs.rho_data, powi[:,1])

    for i in 2:length(actor.outputs.time_data)
        plot!(pp, actor.outputs.rho_data, powi[:,i])
    end

    xlabel!(pp, "rho")
    ylabel!(pp, "Power density profile to ions - W/m^3 ")
    display(pp)
   
    return actor

end