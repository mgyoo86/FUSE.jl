import NumericalIntegration: cumul_integrate

function init_nbi(dd::IMAS.dd, ini::ParametersInit, act::ParametersActor)
    init_nbi(dd, ini.nbi.power_launched, ini.nbi.beam_energy, ini.nbi.beam_mass, ini.nbi.toroidal_angle)
    SimpleNBIactor(dd, act)
end

function init_nbi(
    dd::IMAS.dd,
    power_launched::Union{Real,Vector},
    beam_energy::Union{Real,Vector},
    beam_mass::Union{Real,Vector},
    toroidal_angle::Union{Real,Vector})

    power_launched, beam_energy, beam_mass, toroidal_angle = same_length_vectors(power_launched, beam_energy, beam_mass, toroidal_angle)

    for idx in 1:length(power_launched)
        nbu = resize!(dd.nbi.unit, idx)
        nbu.name = length(power_launched) > 1 ? "nbi_$idx" : "nbi"
        @ddtime(nbu.energy.data = beam_energy[idx])
        @ddtime(nbu.power_launched.data = power_launched[idx])
        nbu.available_launch_power = power_launched[idx]
        nbu.species.a = beam_mass[idx]
        # 1 beamlet
        beamlet = resize!(nbu.beamlets_group, 1)
        beamlet.angle = toroidal_angle[idx] / 360 * 2pi
    end

    return dd
end

function init_ec(dd::IMAS.dd, ini::ParametersInit, act::ParametersActor)
    init_ec(dd, ini.ec.power_launched)
    SimpleECactor(dd, act)
end

function init_ec(dd::IMAS.dd, power_launched::Union{Real,Vector})
    (power_launched,) = same_length_vectors(power_launched)
    for idx in 1:length(power_launched)
        ecl = resize!(dd.ec_launchers.launcher, idx)
        ecl.name = length(power_launched) > 1 ? "ec_$idx" : "ec"
        @ddtime(ecl.power_launched.data = power_launched[idx])
        ecl.available_launch_power = power_launched[idx]
    end
end

function init_ic(dd::IMAS.dd, ini::ParametersInit, act::ParametersActor)
    init_ic(dd, ini.ic.power_launched)
    SimpleICactor(dd, act)
end

function init_ic(dd::IMAS.dd, power_launched::Union{Real,Vector})
    (power_launched,) = same_length_vectors(power_launched)
    for idx in 1:length(power_launched)
        ica = resize!(dd.ic_antennas.antenna, idx)
        ica.name = length(power_launched) > 1 ? "ic_$idx" : "ic"
        @ddtime(ica.power_launched.data = power_launched[idx])
        ica.available_launch_power = power_launched[idx]
    end
end

function init_lh(dd::IMAS.dd, ini::ParametersInit, act::ParametersActor)
    init_lh(dd, ini.lh.power_launched)
    SimpleLHactor(dd, act)
end

function init_lh(dd::IMAS.dd, power_launched::Union{Real,Vector})
    (power_launched,) = same_length_vectors(power_launched)
    for idx in 1:length(power_launched)
        lha = resize!(dd.lh_antennas.antenna, idx)
        lha.name = length(power_launched) > 1 ? "lh_$idx" : "lh"
        @ddtime(lha.power_launched.data = power_launched[idx])
        lha.available_launch_power = power_launched[idx]
    end
end

function init_core_sources(dd::IMAS.dd, ini::ParametersInit, act::ParametersActor)
    init_from = ini.general.init_from

    if init_from == :ods
        dd1 = IMAS.json2imas(ini.ods.filename)
        if !ismissing(dd1.core_sources, :time) && length(keys(dd1.core_sources.time)) > 0
            dd.global_time = max(dd.global_time, maximum(dd1.core_sources.time))
            dd.core_sources = dd1.core_sources
        else
            init_from = :scalars
        end
    end

    if init_from == :scalars
        if !ismissing(ini.nbi, :power_launched) && any(ini.nbi.power_launched .> 0)
            init_nbi(dd, ini, act)
        end
        if !ismissing(ini.ec, :power_launched) && any(ini.ec.power_launched .> 0)
            init_ec(dd, ini, act)
        end
        if !ismissing(ini.ic, :power_launched) && any(ini.ic.power_launched .> 0)
            init_ic(dd, ini, act)
        end
        if !ismissing(ini.lh, :power_launched) && any(ini.lh.power_launched .> 0)
            init_lh(dd, ini, act)
        end
    end

    return dd
end

