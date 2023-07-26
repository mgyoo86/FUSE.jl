import QED
import FiniteElementHermite

#= ======== =#
#  ActorQED  #
#= ======== =#
Base.@kwdef mutable struct FUSEparameters__ActorQED{T} <: ParametersActor where {T<:Real}
    _parent::WeakRef = WeakRef(nothing)
    _name::Symbol = :not_set
    Δt::Entry{Float64} = Entry{Float64}("s", "Evolve for Δt")
    Nt::Entry{Int} = Entry{Int}("-", "Number of time steps during evolution", default=100)
    solve_for::Switch{Symbol} = Switch{Symbol}([:ip, :vloop], "-", "Solve for specified Ip or Vloop", default=:ip)
end

mutable struct ActorQED{D,P} <: PlasmaAbstractActor
    dd::IMAS.dd{D}
    par::FUSEparameters__ActorQED{P}
    η::Function
    QI::QED.QED_state
    QO::QED.QED_state
    t0::Float64
    t1::Float64
end

"""
    ActorQED(dd::IMAS.dd, act::ParametersAllActors; kw...)

Evolves the plasma current using the QED current diffusion solver

!!! note 
    Stores data in `dd.core_profiles`, `dd.equilbrium`
"""
function ActorQED(dd::IMAS.dd, act::ParametersAllActors; kw...)
    actor = ActorQED(dd, act.ActorQED; kw...)
    step(actor)
    finalize(actor)
    return actor
end

function ActorQED(dd::IMAS.dd, par::FUSEparameters__ActorQED; kw...)
    logging_actor_init(ActorQED)
    par = par(kw...)

    eqt = dd.equilibrium.time_slice[]
    prof1d = dd.core_profiles.profiles_1d[]

    QI = qed_init_from_imas(eqt, prof1d)
    QO = deepcopy(QI)

    return ActorQED(dd, par, η_imas(prof1d), QI, QO, dd.global_time, dd.global_time + par.Δt)
end

function _step(actor::ActorQED)
    dd = actor.dd
    par = actor.par

    # staircase approach
    actor.QO = deepcopy(actor.QI)
    tnow = actor.t0
    δt = par.Δt / par.Nt
    for k in 1:par.Nt
        tnow += δt
        if par.solve_for == :ip
            Ip = IMAS.get_time_array(dd.pulse_schedule.flux_control.i_plasma.reference, :data, tnow, :linear)
            Vedge = nothing
        else
            error("Vloop advance not supported")
        end
        actor.QO = QED.diffuse(actor.QO, η_imas(dd.core_profiles.profiles_1d[tnow]), δt, 1; Vedge, Ip)
    end

    return actor
end

function _finalize(actor::ActorQED)
    dd = actor.dd

    # go to the next global time
    dd.global_time = actor.t1

    # set the total toroidal current for new time slices in both equilibrium as well as core_profiles IDSs
    # NOTE: Here really we only care about core_profiles, since when the equilibrium actor is run,
    # then the new equilibrium time slice will be prepared based on the core_profiles current
    eqt = dd.equilibrium.time_slice[actor.t0]
    eqt_new = deepcopy(eqt)
    push!(dd.equilibrium.time_slice, eqt_new, actor.t1)
    @ddtime(dd.equilibrium.vacuum_toroidal_field.b0 = dd.equilibrium.vacuum_toroidal_field.b0[end])
    dΡ_dρ = eqt_new.profiles_1d.rho_tor[end]
    ρ = eqt_new.profiles_1d.rho_tor / dΡ_dρ
    eqt_new.profiles_1d.q = 1.0 ./ actor.QO.ι.(ρ)
    eqt_new.profiles_1d.j_tor = actor.QO.JtoR.(ρ) ./ eqt_new.profiles_1d.gm9

    # core_profiles
    cp1d_new = cp1d = dd.core_profiles.profiles_1d[actor.t0]
    cp1d_new = deepcopy(cp1d)
    cp1d_new.time = actor.t1
    push!(dd.core_profiles.profiles_1d, cp1d_new, actor.t1)
    IMAS.j_total_from_equilibrium!(eqt_new, cp1d_new)

    # update core_sources related to current
    IMAS.bootstrap_source!(dd)
    IMAS.ohmic_source!(dd)

    return actor
end

# utils
function qed_init_from_imas(eqt::IMAS.equilibrium__time_slice, prof1d::IMAS.core_profiles__profiles_1d)
    rho_tor = eqt.profiles_1d.rho_tor
    R0, B0 = IMAS.vacuum_r0_b0(eqt)
    gm1 = eqt.profiles_1d.gm1
    f = eqt.profiles_1d.f
    dvolume_drho_tor = eqt.profiles_1d.dvolume_drho_tor
    q = eqt.profiles_1d.q
    j_tor = eqt.profiles_1d.j_tor
    gm9 = eqt.profiles_1d.gm9

    if ismissing(prof1d, :j_non_inductive)
        ρ_j_non_inductive = nothing
    else
        ρ_j_non_inductive = (prof1d.grid.rho_tor_norm, prof1d.j_non_inductive)
    end

    return QED.initialize(rho_tor, B0, gm1, f, dvolume_drho_tor, q, j_tor, gm9; ρ_j_non_inductive)
end

function η_imas(prof1d::IMAS.core_profiles__profiles_1d; use_log::Bool=true)
    rho = prof1d.grid.rho_tor_norm
    η = 1.0 ./ prof1d.conductivity_parallel
    return QED.η_FE(rho, η; use_log)
end
