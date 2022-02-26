import NumericalIntegration: integrate

#= ====================== =#
#     simple H&CD actors   #
#= ====================== =#
mutable struct simpleNBIactor <: AbstractActor
    dd :: IMAS.dd
    width :: Vector
    rho_0 :: Vector
    current_efficiency :: Vector
end

mutable struct simpleECactor <: AbstractActor
    dd :: IMAS.dd
    width :: Vector
    rho_0 :: Vector
    current_efficiency :: Vector
end

mutable struct simpleICactor <: AbstractActor
    dd :: IMAS.dd
    width :: Vector
    rho_0 :: Vector
    current_efficiency :: Vector
end

mutable struct simpleLHactor <: AbstractActor
    dd :: IMAS.dd
    width :: Vector
    rho_0 :: Vector
    current_efficiency :: Vector
end

function simpleNBIactor(dd::IMAS.dd, width::Real=0.3, rho_0::Real = 0.0, current_efficiency::Real = 0.3)
    nbeam = ones(length(dd.nbi.unit))
    return simpleNBIactor(dd, nbeam .* width, nbeam .* rho_0, nbeam .* current_efficiency)
end

function simpleECactor(dd::IMAS.dd, width::Real=0.1, rho_0::Real = 0.0, current_efficiency::Real = 0.2)
    n_launchers = ones(length(dd.ec_launchers.launcher))
    return simpleECactor(dd, n_launchers .* width, n_launchers .* rho_0, n_launchers .* current_efficiency)
end

function simpleICactor(dd::IMAS.dd, width::Real=0.1, rho_0::Real = 0.0, current_efficiency::Real = 0.125)
    n_antennas = ones(length(dd.ic_antennas.antenna))
    return simpleICactor(dd, n_antennas .* width, n_antennas .* rho_0, n_antennas .* current_efficiency)
end

function simpleLHactor(dd::IMAS.dd, width::Real=0.15, rho_0::Real = 0.6, current_efficiency::Real = 0.4)
    n_antennas = ones(length(dd.lh_antennas.antenna))
    return simpleICactor(dd, n_antennas .* width, n_antennas .* rho_0, n_antennas .* current_efficiency)
end

function gaussian_source_to_dd(isource,name, index, rho_cp, volume_cp, area_cp, power_launched, ion_electron_fraction, rho_0, width, gauss_order; electrons_particles=missing, momentum_tor=missing, j_parallel=missing)
    gaussian = sgaussian(rho_cp, rho_0, width, gauss_order)
    gaussian_vol = gaussian / integrate(volume_cp, gaussian)
    gaussian_area = gaussian / integrate(area_cp, gaussian)

    total_ion_energy = power_launched .* gaussian_vol .* ion_electron_fraction
    electrons_energy = power_launched .* gaussian_vol .* (1 .- ion_electron_fraction)

    if electrons_particles !== missing
        electrons_particles = gaussian_vol .* electrons_particles
    end
    if momentum_tor !== missing
        momentum_tor =  gaussian_area .* momentum_tor
    end
    if j_parallel !== missing
        j_parallel = gaussian_area .* j_parallel
    end
    IMAS.new_source(isource, index, name, rho_cp, volume_cp; electrons_energy, total_ion_energy, electrons_particles, j_parallel, momentum_tor)
end


function step(actor::simpleNBIactor; verbose=false)
    for (idx, nbi_u) in enumerate(actor.dd.nbi.unit)
        eqt = actor.dd.equilibrium.time_slice[]
        cp1d = actor.dd.core_profiles.profiles_1d[]
        cs = actor.dd.core_sources

        beam_energy = @ddtime (nbi_u.energy.data)
        beam_mass = nbi_u.species.a
        power_launched = @ddtime(nbi_u.power_launched.data)

        rho_cp = cp1d.grid.rho_tor_norm
        volume_cp = IMAS.interp(eqt.profiles_1d.rho_tor_norm, eqt.profiles_1d.volume)[rho_cp]
        area_cp = IMAS.interp(eqt.profiles_1d.rho_tor_norm, eqt.profiles_1d.area)[rho_cp]

        ion_electron_fraction = IMAS.sivukhin_fraction(cp1d, beam_energy, beam_mass)

        beam_particles = power_launched / (beam_energy * constants.e)
        momentum_source= sin(nbi_u.beamlets_group[1].angle) * beam_particles * sqrt(2 * beam_energy * constants.e / beam_mass / constants.m_u) * beam_mass * constants.m_u 

        ne_vol = integrate(volume_cp,cp1d.electrons.density) / volume_cp[end]
        j_parallel = actor.current_efficiency / eqt.boundary.geometric_axis.r / (ne_vol/1e19) * power_launched

        isource = resize!(cs.source, "identifier.name" => "beam_$idx")
        gaussian_source_to_dd(isource, "beam_$idx", 2, rho_cp, volume_cp, area_cp, power_launched, ion_electron_fraction, actor.rho_0[idx], actor.width[idx], 2; electrons_particles=beam_particles, momentum_tor=momentum_source, j_parallel=j_parallel)
    end
end

function step(actor::simpleECactor; verbose=false)
    for (idx, ec_launcher) in enumerate(actor.dd.ec_launchers.launcher)
        eqt = actor.dd.equilibrium.time_slice[]
        cp1d = actor.dd.core_profiles.profiles_1d[]
        cs = actor.dd.core_sources

        power_launched = @ddtime(ec_launcher.power_launched.data)

        rho_cp = cp1d.grid.rho_tor_norm
        volume_cp = IMAS.interp(eqt.profiles_1d.rho_tor_norm, eqt.profiles_1d.volume)[rho_cp]
        area_cp = IMAS.interp(eqt.profiles_1d.rho_tor_norm, eqt.profiles_1d.area)[rho_cp]

        ion_electron_fraction = 0.

        ne_vol = integrate(volume_cp,cp1d.electrons.density) / volume_cp[end]
        j_parallel = actor.current_efficiency / eqt.boundary.geometric_axis.r / (ne_vol/1e19) * power_launched

        isource = resize!(cs.source, "identifier.name" => "ec_launcher_$idx")
        gaussian_source_to_dd(isource, "ec_launcher_$idx", 3, rho_cp, volume_cp, area_cp, power_launched, ion_electron_fraction, actor.rho_0[idx], actor.width[idx], 1; j_parallel=j_parallel)
    end
end

function step(actor::simpleICactor; verbose=false)
    for (idx, ic_antenna) in enumerate(actor.dd.ic_antennas.antenna)
        eqt = actor.dd.equilibrium.time_slice[]
        cp1d = actor.dd.core_profiles.profiles_1d[]
        cs = actor.dd.core_sources

        power_launched = @ddtime(ic_antenna.power_launched.data)

        rho_cp = cp1d.grid.rho_tor_norm
        volume_cp = IMAS.interp(eqt.profiles_1d.rho_tor_norm, eqt.profiles_1d.volume)[rho_cp]
        area_cp = IMAS.interp(eqt.profiles_1d.rho_tor_norm, eqt.profiles_1d.area)[rho_cp]

        ion_electron_fraction = 0.25

        ne_vol = integrate(volume_cp,cp1d.electrons.density) / volume_cp[end]
        j_parallel = actor.current_efficiency / eqt.boundary.geometric_axis.r / (ne_vol/1e19) * power_launched

        isource = resize!(cs.source, "identifier.name" => "ic_antenna_$idx")
        gaussian_source_to_dd(isource, "ic_antenna_$idx", 5, rho_cp, volume_cp, area_cp, power_launched, ion_electron_fraction, actor.rho_0[idx], actor.width[idx], 1; j_parallel=j_parallel)
    end
end

function step(actor::simpleLHactor; verbose=false)
    for (idx, lh_antenna) in enumerate(actor.dd.lh_antennas.antenna)
        eqt = actor.dd.equilibrium.time_slice[]
        cp1d = actor.dd.core_profiles.profiles_1d[]
        cs = actor.dd.core_sources

        power_launched = @ddtime(lh_antenna.power_launched.data)

        rho_cp = cp1d.grid.rho_tor_norm
        volume_cp = IMAS.interp(eqt.profiles_1d.rho_tor_norm, eqt.profiles_1d.volume)[rho_cp]
        area_cp = IMAS.interp(eqt.profiles_1d.rho_tor_norm, eqt.profiles_1d.area)[rho_cp]

        ion_electron_fraction = 0.25

        ne_vol = integrate(volume_cp,cp1d.electrons.density) / volume_cp[end]
        j_parallel = actor.current_efficiency / eqt.boundary.geometric_axis.r / (ne_vol/1e19) * power_launched

        isource = resize!(cs.source, "identifier.name" => "lh_antenna_$idx")
        gaussian_source_to_dd(isource, "lh_antenna_$idx", 4, rho_cp, volume_cp, area_cp, power_launched, ion_electron_fraction, actor.rho_0[idx], actor.width[idx], 1; j_parallel=j_parallel)
    end
end

function sgaussian(rho::Union{LinRange,Vector}, rho_0::Real, width::Real, order::Real = 1.0)
    return exp.(-((rho .- rho_0) .^ 2 / 2width^2) .^ order)
end
