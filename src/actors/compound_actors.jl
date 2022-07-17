#= ========================= =#
#  ActorEquilibriumTransport  #
#= ========================= =#
Base.@kwdef mutable struct ActorEquilibriumTransport <: PlasmaAbstractActor
    dd::IMAS.dd
    actor_jt::Union{Nothing,ActorSteadyStateCurrent}
    actor_eq::Union{Nothing,ActorEquilibrium}
    actor_tr::Union{Nothing,ActorTauenn}
end

function ParametersActor(::Type{Val{:ActorEquilibriumTransport}})
    par = ParametersActor(nothing)
    par.do_plot = Entry(Bool, "", "plot"; default=false)
    par.iterations = Entry(Int, "", "transport-equilibrium iterations"; default=1)
    return par
end

"""
    ActorEquilibriumTransport(dd::IMAS.dd, act::ParametersAllActors; kw...)

Compound actor that runs the following actors in succesion:
```julia
ActorSteadyStateCurrent(dd, act)    # Current evolution to steady-state 
ActorTauenn(dd, act)                # For transport
ActorEquilibrium(dd, act)           # Equilibrium
```

!!! note 
    Stores data in `dd.equilibrium, dd.core_profiles, dd.core_sources`
"""
function ActorEquilibriumTransport(dd::IMAS.dd, act::ParametersAllActors; kw...)
    par = act.ActorEquilibriumTransport(kw...)
    actor = ActorEquilibriumTransport(dd, nothing, nothing, nothing)
    step(actor; act, iterations=par.iterations, do_plot=par.do_plot)
    finalize(actor)
    return actor
end

function step(actor::ActorEquilibriumTransport; act::Union{Missing,ParametersAllActors}=missing, iterations::Int=1, do_plot::Bool=false)
    dd = actor.dd
    if act === missing
        act = ParametersAllActors()
    end

    if do_plot
        pe = plot(dd.equilibrium; color=:gray, label="old", coordinate=:rho_tor_norm)
        pp = plot(dd.core_profiles; color=:gray, label=" (old)")
        ps = plot(dd.core_sources; color=:gray, label=" (old)")
    end

    # Set j_ohmic to steady state
    ActorSteadyStateCurrent(dd, act)

    for iteration in 1:iterations
        # run transport actor
        actor.actor_tr = ActorTauenn(dd, act)

        # prepare equilibrium input based on transport core_profiles output
        prepare(dd, :ActorEquilibrium, act)

        # run equilibrium actor with the updated beta
        actor.actor_eq = ActorEquilibrium(dd, act)

        # Set j_ohmic to steady state
        actor.actor_jt = ActorSteadyStateCurrent(dd, act)
    end

    if do_plot
        display(plot!(pe, dd.equilibrium, coordinate=:rho_tor_norm))
        display(plot!(pp, dd.core_profiles))
        display(plot!(ps, dd.core_sources))
    end

    return actor
end


#= ================== =#
#  ActorWholeFacility  #
#= ================== =#
Base.@kwdef mutable struct ActorWholeFacility <: FacilityAbstractActor
    dd::IMAS.dd
end

function ParametersActor(::Type{Val{:ActorWholeFacility}})
    par = ParametersActor(nothing)
    return par
end

"""
    ActorWholeFacility(dd::IMAS.dd, act::ParametersAllActors; kw...)

Compound actor that runs all the actors needed to model the whole plant

!!! note 
    Stores data in `dd`
"""
function ActorWholeFacility(dd::IMAS.dd, act::ParametersAllActors; kw...)
    par = act.ActorWholeFacility(kw...)
    actor = ActorWholeFacility(dd)
    step(actor; act)
    finalize(actor)
    return actor
end

function step(actor::ActorWholeFacility; act::Union{Missing,ParametersAllActors}=missing, iterations::Int=1, do_plot::Bool=false)
    dd = actor.dd
    ActorEquilibriumTransport(dd, act)
    ActorHFSsizing(dd, act)
    ActorLFSsizing(dd, act)
    ActorCXbuild(dd, act)
    ActorPFcoilsOpt(dd, act)
    ActorNeutronics(dd, act)
    ActorBlanket(dd, act)
    ActorDivertors(dd, act)
    ActorBalanceOfPlant(dd,act)
    ActorCosting(dd, act)
    return actor
end