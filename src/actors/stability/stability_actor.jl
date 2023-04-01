#= =================== =#
#  ActorStability       #
#= =================== =#
Base.@kwdef mutable struct FUSEparameters__ActorStability{T} <: ParametersActor where {T<:Real}
    _parent::WeakRef = WeakRef(nothing)
    _name::Symbol = :not_set
    stability_actor::Switch{Symbol} = Switch(Symbol, [:BetaLimit, :CurrentLimit, :DensityLimit, :Limits, :None], "-", "Stability Actor to run"; default=:Limits)
end

mutable struct ActorStability<: PlasmaAbstractActor
    dd::IMAS.dd
    par::FUSEparameters__ActorStability
    #stab_actor::PlasmaAbstractActor
    stab_actor::Union{Nothing, ActorBetaLimit, ActorCurrentLimit, ActorDensityLimit}
end

"""
    ActorStability(dd::IMAS.dd, act::ParametersAllActors; kw...)

Provides a common interface to run multiple stability actors
"""
function ActorStability(dd::IMAS.dd, act::ParametersAllActors; kw...)
    par = act.ActorStability(kw...)
    actor = ActorStability(dd, par, act)
    step(actor)
    finalize(actor)
    return actor
end



function ActorStability(dd::IMAS.dd, par::FUSEparameters__ActorStability, act::ParametersAllActors; kw...)
    logging_actor_init(ActorStability)
    par = par(kw...)

    print("act: ")
    println(act.ActorStability.stability_actor)
    print("par: ")
    println(par.stability_actor)

    if par.stability_actor == :None 
        error("stability_actor $(par.stability_actor) is not supported yet")
    elseif par.stability_actor == :Limits
        error("stability_actor $(par.stability_actor) is not supported yet")
        #stab_actor.ActorBetaLimit = ActorBetaLimit(dd, act.ActorBetaLimit)
        #stab_actor.ActorCurrentLimit = ActorCurrentLimit(dd, act.ActorCurrentLimit)
        #stab_actor = ActorDensityLimit(dd, act.ActorDensityLimit)
        stab_actor = deepcopy(act)
        stab_actor.ActorStability.stability_actor = :None
        par.stability_actor = :None
        temp1_actor = ActorBetaLimit(dd, act)
        temp2_actor = ActorCurrentLimit(dd, act)
        temp3_actor = ActorDensityLimit(dd, act)
    elseif par.stability_actor == :BetaLimit
        stab_actor = ActorBetaLimit(dd, act.ActorBetaLimit)
    elseif par.stability_actor == :CurrentLimit
        stab_actor = ActorCurrentLimit(dd, act.ActorCurrentLimit)
    elseif par.stability_actor == :DensityLimit
        stab_actor = ActorDensityLimit(dd, act.ActorDensityLimit)
    else
        error("stability_actor $(par.stability_actor) is not supported yet")
    end

    #dd.stability.time_slice[].all_cleared = 1

    return ActorStability(dd, par, stab_actor)
end


"""
    step(actor::ActorStability)

Runs through the selected stability actor's step
"""
function _step(actor::ActorStability)
    step(actor.stab_actor)
    return actor
end

"""
    finalize(actor::ActorStability)

    Finalizes the selected stability actor
"""
function _finalize(actor::ActorStability)
    dd = actor.dd

    dd.stability.framework = String(actor.par.stability_actor)
    
    finalize(actor.stab_actor)

    return actor
end







# function ActorStability(dd::IMAS.dd, par::FUSEparameters__ActorStability, act::ParametersAllActors; stability_actors::Vector{:Symbol} , kw...)
    
#     stab_actor = deepcopy(act)
#     if :BetaLimit in stability_actors
#         stab_actor.ActorStability.stability_actor = :BetaLimit
#         stab_actor = ActorStability(dd, stab_actor.ActorBetaLimit)
#     end
#     if :CurrentLimit in stability_actors
#         stab_actor = ActorCurrentLimit(dd, act.ActorCurrentLimit)
#     end
#     if :DensityLimit in stability_actors
#         stab_actor = ActorDensityLimit(dd, act.ActorDensityLimit)
#     end
#     stab_actor = ActorBetaLimit(dd, act.ActorBetaLimit)
#     stab_actor = ActorCurrentLimit(dd, act.ActorCurrentLimit)
#     #stab_actor = ActorDensityLimit(dd, act.ActorDensityLimit)

#     return ActorStability(dd, par, stab_actor)
# end