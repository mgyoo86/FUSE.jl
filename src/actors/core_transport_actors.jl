#= =================== =#
#  ActorCoreTransport  #
#= =================== =#
mutable struct ActorCoreTransport <: PlasmaAbstractActor
    dd::IMAS.dd
    par::ParametersActor
    turb_actor::PlasmaAbstractActor
    neoclassical_actor::PlasmaAbstractActor
end

function ParametersActor(::Type{Val{:ActorCoreTransport}})
    par = ParametersActor(nothing)
    par.rho_transport = Entry(AbstractVector, "", "rho core transport grid"; default=0.2:0.1:0.8)
    par.turbulence_actor = Switch([:TGLF, :None], "", "Turbulence Actor to run"; default=:TGLF)
    par.neoclassical_actor = Switch([:Neoclassical, :None], "", "Neocalssical actor to run"; default=:Neoclassical)
    return par
end

"""
    ActorCoreTransport(dd::IMAS.dd, act::ParametersAllActors; kw...)

The ActorCoreTransport provides a common interface to run multiple equilibrium actors
"""
function ActorCoreTransport(dd::IMAS.dd, act::ParametersAllActors; kw...)
    par = act.ActorCoreTransport(kw...)
    actor = ActorCoreTransport(dd, par, act)
    step(actor)
    finalize(actor)
    return actor
end

function ActorCoreTransport(dd::IMAS.dd, par::ParametersActor, act::ParametersAllActors; kw...)
    par = par(kw...)
    if par.turbulence_actor == :TGLF
        act.ActorTGLF.rho_transport = par.rho_transport
        turb_actor = ActorTGLF(dd, act.ActorTGLF)
    end

    if par.neoclassical_actor == :Neoclassical
        act.ActorNeoclassical.rho_transport = par.rho_transport
        neoclassical_actor = ActorNeoclassical(dd, act.ActorNeoclassical)
    end
    return ActorCoreTransport(dd, par, turb_actor, neoclassical_actor)
end

"""
    step(actor::ActorCoreTransport)

Runs through the selected equilibrium actor's step
"""
function step(actor::ActorCoreTransport)
    step(actor.turb_actor)
    step(actor.neoclassical_actor)
end

"""
    finalize(actor::ActorCoreTransport)

Finalizes the selected equilibrium actor
"""
function finalize(actor::ActorCoreTransport)
    finalize(actor.turb_actor)
    finalize(actor.neoclassical_actor)
end

#= ============ =#
#  ActorTGLF  #
#= ============ =#
include("tglf_actors.jl")

#= ================= =#
#  ActorNeoclassical  #
#= ================= =#
include("neoclassical_actors.jl")
