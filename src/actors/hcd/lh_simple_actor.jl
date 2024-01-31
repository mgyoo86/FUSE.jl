#= == =#
#  LH  #
#= == =#
Base.@kwdef mutable struct FUSEparameters__ActorLHsimple{T} <: ParametersActor where {T<:Real}
    _parent::WeakRef = WeakRef(nothing)
    _name::Symbol = :not_set
    _time::Float64 = NaN
    width::Entry{Union{T,AbstractVector{T}}} = Entry{Union{T,AbstractVector{T}}}("-", "Width of the deposition profile"; default=0.1)
    rho_0::Entry{Union{T,AbstractVector{T}}} = Entry{Union{T,AbstractVector{T}}}("-", "Radial location of the deposition profile"; default=0.8)
    ηcd_scale::Entry{Union{T,AbstractVector{T}}} = Entry{Union{T,AbstractVector{T}}}("-", "Scaling factor for nominal current drive efficiency"; default=1.0)
end

mutable struct ActorLHsimple{D,P} <: HCDAbstractActor{D,P}
    dd::IMAS.dd{D}
    par::FUSEparameters__ActorLHsimple{P}
    function ActorLHsimple(dd::IMAS.dd{D}, par::FUSEparameters__ActorLHsimple{P}; kw...) where {D<:Real,P<:Real}
        logging_actor_init(ActorLHsimple)
        par = par(kw...)
        return new{D,P}(dd, par)
    end
end

"""
    ActorLHsimple(dd::IMAS.dd, act::ParametersAllActors; kw...)

Estimates the Lower-hybrid electron energy deposition and current drive as a gaussian.

NOTE: Current drive efficiency from GASC, based on "G. Tonon 'Current Drive Efficiency Requirements for an Attractive Steady-State Reactor'"

!!! note

    Reads data in `dd.lh_antennas` and stores data in `dd.core_sources`
"""
function ActorLHsimple(dd::IMAS.dd, act::ParametersAllActors; kw...)
    actor = ActorLHsimple(dd, act.ActorLHsimple; kw...)
    step(actor)
    finalize(actor)
    return actor
end

function _step(actor::ActorLHsimple)
    dd = actor.dd
    par = actor.par

    eqt = dd.equilibrium.time_slice[]
    cp1d = dd.core_profiles.profiles_1d[]
    cs = dd.core_sources

    R0 = eqt.boundary.geometric_axis.r
    rho_cp = cp1d.grid.rho_tor_norm
    volume_cp = IMAS.interp1d(eqt.profiles_1d.rho_tor_norm, eqt.profiles_1d.volume).(rho_cp)
    area_cp = IMAS.interp1d(eqt.profiles_1d.rho_tor_norm, eqt.profiles_1d.area).(rho_cp)

    n_antennas = length(dd.lh_antennas.antenna)
    _, width, rho_0, ηcd_scale = same_length_vectors(1:n_antennas, par.width, par.rho_0, par.ηcd_scale)

    for (idx, lha) in enumerate(dd.lh_antennas.antenna)
        power_launched = @ddtime(dd.pulse_schedule.lh.antenna[idx].power.reference.data)
        @ddtime(lha.power_launched.data = power_launched)

        ion_electron_fraction_cp = zeros(length(rho_cp))

        ne20 = IMAS.interp1d(rho_cp, cp1d.electrons.density).(rho_0[idx]) / 1E20
        TekeV = IMAS.interp1d(rho_cp, cp1d.electrons.temperature).(rho_0[idx]) / 1E3
        zeff = IMAS.interp1d(rho_cp, cp1d.zeff).(rho_0[idx])

        eta = ηcd_scale[idx] * TekeV * 0.037 * B0 / (5.0 + zeff) / ne20^0.33
        j_parallel = eta / R0 / ne20 * power_launched
        j_parallel *= sign(eqt.global_quantities.ip)

        source = resize!(cs.source, :lh, "identifier.name" => lha.name; wipe=false)
        gaussian_source(
            source,
            lha.name,
            source.identifier.index,
            rho_cp,
            volume_cp,
            area_cp,
            power_launched,
            ion_electron_fraction_cp,
            rho_0[idx],
            width[idx],
            1.0;
            j_parallel=j_parallel
        )
    end
    return actor
end