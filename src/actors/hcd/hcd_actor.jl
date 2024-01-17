#= ======== =#
#  ActorHCD  #
#= ======== =#
Base.@kwdef mutable struct FUSEparameters__ActorHCD{T} <: ParametersActor where {T<:Real}
    _parent::WeakRef = WeakRef(nothing)
    _name::Symbol = :not_set
    ec_model::Switch{Symbol} = Switch{Symbol}([:ECsimple, :none], "-", "EC source actor to run"; default=:ECsimple)
    ic_model::Switch{Symbol} = Switch{Symbol}([:ICsimple, :none], "-", "IC source actor to run"; default=:ICsimple)
    lh_model::Switch{Symbol} = Switch{Symbol}([:LHsimple, :none], "-", "LH source actor to run"; default=:LHsimple)
    nb_model::Switch{Symbol} = Switch{Symbol}([:NBsimple, :none], "-", "NB source actor to run"; default=:NBsimple)
    pellet_model::Switch{Symbol} = Switch{Symbol}([:Pelletsimple, :none], "-", "Pellet source actor to run"; default=:Pelletsimple)
end

mutable struct ActorHCD{D,P} <: PlasmaAbstractActor{D,P}
    dd::IMAS.dd{D}
    par::FUSEparameters__ActorHCD{P}
    ec_actor::Union{Missing,ActorECsimple{D,P}}
    ic_actor::Union{Missing,ActorICsimple{D,P}}
    lh_actor::Union{Missing,ActorLHsimple{D,P}}
    nb_actor::Union{Missing,ActorNBsimple{D,P}}
    pellet_actor::Union{Missing,ActorPelletsimple{D,P}}
end

"""
    ActorHCD(dd::IMAS.dd, act::ParametersAllActors; kw...)

Provides a common interface to run HCD actors
"""
function ActorHCD(dd::IMAS.dd, act::ParametersAllActors; kw...)
    actor = ActorHCD(dd, act.ActorHCD, act; kw...)
    step(actor)
    finalize(actor)
    return actor
end

function ActorHCD(dd::IMAS.dd, par::FUSEparameters__ActorHCD, act::ParametersAllActors; kw...)
    logging_actor_init(ActorHCD)
    par = par(kw...)
    if par.ec_model == :ECsimple
        ec_actor = ActorECsimple(dd, act.ActorECsimple)
    else
        ec_actor = missing
    end
    if par.ic_model == :ICsimple
        ic_actor = ActorICsimple(dd, act.ActorICsimple)
    else
        ic_actor = missing
    end
    if par.lh_model == :LHsimple
        lh_actor = ActorLHsimple(dd, act.ActorLHsimple)
    else
        lh_actor = missing
    end
    if par.nb_model == :NBsimple
        nb_actor = ActorNBsimple(dd, act.ActorNBsimple)
    else
        nb_actor = missing
    end
    if par.pellet_model == :Pelletsimple
        pellet_actor = ActorPelletsimple(dd, act.ActorPelletsimple)
    else
        pellet_actor = missing
    end
    return ActorHCD(dd, par, ec_actor, ic_actor, lh_actor, nb_actor,pellet_actor)
end

"""
    _step(actor::ActorHCD)

Runs through the selected HCD actor's step
"""
function _step(actor::ActorHCD)
    if actor.ec_actor !== missing
        step(actor.ec_actor)
    end
    if actor.ic_actor !== missing
        step(actor.ic_actor)
    end
    if actor.lh_actor !== missing
        step(actor.lh_actor)
    end
    if actor.nb_actor !== missing
        step(actor.nb_actor)
    end
    if actor.pellet_actor !== missing
        step(actor.pellet_actor)
    end
    return actor
end

"""
    _finalize(actor::ActorHCD)

Finalizes the selected CHD actor's finalize
"""
function _finalize(actor::ActorHCD)
    if actor.ec_actor !== missing
        finalize(actor.ec_actor)
    end
    if actor.ic_actor !== missing
        finalize(actor.ic_actor)
    end
    if actor.lh_actor !== missing
        finalize(actor.lh_actor)
    end
    if actor.nb_actor !== missing
        finalize(actor.nb_actor)
    end
    if actor.pellet_actor !== missing
        finalize(actor.pellet_actor)
    end
    return actor
end