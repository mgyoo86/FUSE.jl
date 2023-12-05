
function case_parameters(::Type{Val{:STEP}}; init_from::Symbol=:scalars, pf_from::Symbol=:scalars)::Tuple{ParametersAllInits,ParametersAllActors}
    ini, act = case_parameters(:STEP_scalars)

    if init_from == :ods
        # Fix the core profiles
        dd = IMAS.json2imas(ini.ods.filename)
        cp1d = dd.core_profiles.profiles_1d[]

        rho = cp1d.grid.rho_tor_norm
        cp1d.electrons.density_thermal = ((1.0 .- rho .^ 4) .* 1.6 .+ 0.4) .* 1E20

        cp1d.zeff = fill(ini.core_profiles.zeff, length(rho))
        cp1d.rotation_frequency_tor_sonic = IMAS.Hmode_profiles(0.0, ini.core_profiles.rot_core / 8, ini.core_profiles.rot_core, length(cp1d.grid.rho_tor_norm), 1.4, 1.4, 0.05)

        # Set ions:
        bulk_ion, imp_ion, he_ion = resize!(cp1d.ion, 3)
        # 1. DT
        IMAS.ion_element!(bulk_ion, ini.core_profiles.bulk)
        @assert bulk_ion.element[1].z_n == 1.0 "Bulk ion `$(ini.core_profiles.bulk)` must be a Hydrogenic isotope [:H, :D, :DT, :T]"
        # 2. Impurity
        IMAS.ion_element!(imp_ion, ini.core_profiles.impurity)
        # 3. He
        IMAS.ion_element!(he_ion, :He4)

        # pedestal
        summary = dd.summary
        @ddtime summary.local.pedestal.n_e.value = cp1d.electrons.density_thermal[argmin(abs.(rho .- (1 - ini.core_profiles.w_ped)))]
        @ddtime summary.local.pedestal.position.rho_tor_norm = 1 - ini.core_profiles.w_ped
        @ddtime summary.local.pedestal.zeff.value = ini.core_profiles.zeff

        # Zeff and quasi neutrality for a helium constant fraction with one impurity specie
        niFraction = zeros(3)
        # DT == 1
        # Imp == 2
        # He == 3
        zimp = imp_ion.element[1].z_n
        niFraction[3] = ini.core_profiles.helium_fraction
        niFraction[1] = (zimp - ini.core_profiles.zeff + 4 * niFraction[3] - 2 * zimp * niFraction[3]) / (zimp - 1)
        niFraction[2] = (ini.core_profiles.zeff - niFraction[1] - 4 * niFraction[3]) / zimp^2
        @assert !any(niFraction .< 0.0) "zeff impossible to match for given helium fraction [$(ini.core_profiles.helium_fraction))] and zeff [$(ini.core_profiles.zeff)]"
        ni_core = 0.0
        for i in 1:length(cp1d.ion)
            cp1d.ion[i].density_thermal = cp1d.electrons.density_thermal .* niFraction[i]
            cp1d.ion[i].temperature = cp1d.ion[1].temperature
            ni_core += cp1d.electrons.density_thermal[1] * niFraction[i]
        end

        act.ActorFixedProfiles.update_pedestal = false
        ini.equilibrium.pressure_core = 1.175e6

        # ===========
        # pf_active
        if pf_from == :ods
            coils = dd.pf_active.coil
            pf_rz = [
                (2.0429184549356223, 8.6986301369863),
                (4.017167381974248, 9.623287671232877),
                (6.815450643776823, 9.623287671232877),
                (6.832618025751072, 6.386986301369863),
                (8.309012875536478, 2.1061643835616444),
                (8.309012875536478, -2.1061643835616444),
                (6.832618025751072, -6.386986301369863),
                (6.815450643776823, -9.623287671232877),
                (4.017167381974248, -9.623287671232877),
                (2.0429184549356223, -8.6986301369863)]

            oh_zh = [
                (-6.471803481967896, 0.9543053940181108),
                (-5.000022627813203, 0.9677463150606198),
                (0.0, 4.9731407857281855),
                (5.000022627813203, 0.9677463150606198),
                (6.471803481967896, 0.9543053940181108)]

            r_oh = ini.build.layers[1].thickness + ini.build.layers[2].thickness / 2.0
            b = ini.equilibrium.ϵ * ini.equilibrium.R0 * ini.equilibrium.κ
            z_oh = (ini.equilibrium.Z0 - b, ini.equilibrium.Z0 + b)
            z_ohcoils, h_oh = FUSE.size_oh_coils([z_oh[1], z_oh[2]], 0.1, ini.oh.n_coils, 1.0, 0.0)
            oh_zh = [(z, h_oh) for z in z_ohcoils]

            empty!(coils)
            resize!(coils, length(oh_zh) .+ length(pf_rz))

            for (idx, (z, h)) in enumerate(oh_zh)
                resize!(coils[idx].element, 1)
                pf_geo = coils[idx].element[1].geometry
                pf_geo.geometry_type = 2
                pf_geo.rectangle.r = r_oh
                pf_geo.rectangle.z = z
                pf_geo.rectangle.height = h
                pf_geo.rectangle.width = ini.build.layers[2].thickness
            end

            for (idx, (r, z)) in enumerate(pf_rz)
                idx += length(oh_zh)
                resize!(coils[idx].element, 1)
                pf_geo = coils[idx].element[1].geometry
                pf_geo.geometry_type = 2
                pf_geo.rectangle.r = r
                pf_geo.rectangle.z = z
                pf_geo.rectangle.height = 0.61
                pf_geo.rectangle.width = 0.53
            end

            IMAS.set_coils_function(coils)
        end
        # ===========

        ini.general.dd = dd
        ini.general.init_from = :ods
    end

    return ini, act
end


"""
    case_parameters(:STEP)

STEP

Arguments:
"""
function case_parameters(::Type{Val{:STEP_scalars}})::Tuple{ParametersAllInits,ParametersAllActors}
    ini = ParametersInits(; n_ec=1)
    act = ParametersActors()
    #### INI ####

    ini.general.casename = "STEP"
    ini.general.init_from = :scalars
    ini.ods.filename = joinpath(@__DIR__, "..", "sample", "STEP_starting_point.json")

    ini.build.layers = OrderedCollections.OrderedDict(
        :gap_OH => 0.233,
        :OH => 0.133,
        :gap_TF_OH => 0.016847172081829065,
        :hfs_TF => 0.4043321299638989,
        :hfs_gap_coils => 0.0,
        :hfs_thermal_shield => 0.03369434416365813,
        :hfs_vacuum_vessel => 0.5559566787003614,
        :hfs_blanket => 0.030541516245487195,
        :hfs_first_wall => 0.02,
        :plasma => 4.380264741275571,
        :lfs_first_wall => 0.02,
        :lfs_blanket => 0.6538868832731644,
        :lfs_vacuum_vessel => 0.6064981949458499,
        :lfs_thermal_shield => 0.13477737665463252 + 0.06738868832731626,
        :lfs_gap_coils => 0.25,
        :lfs_TF => 0.4043321299638989,
        :gap_cryostat => 1.5,
        :cryostat => 0.2
    )
    ini.build.layers[:cryostat].shape = :rectangle
    ini.build.plasma_gap = 0.125
    ini.build.symmetric = true
    ini.build.divertors = :double
    ini.build.n_first_wall_conformal_layers = 5

    ini.equilibrium.B0 = 3.2
    ini.equilibrium.R0 = 3.6
    ini.equilibrium.ϵ = 2.0 / ini.equilibrium.R0
    ini.equilibrium.κ = 2.93
    ini.equilibrium.δ = 0.59
    ini.equilibrium.ip = 21.1e6 # from PyTok
    ini.equilibrium.xpoints = :double
    ini.equilibrium.boundary_from = :scalars

    ini.core_profiles.zeff = 2.5 # from PyTok
    ini.core_profiles.rot_core = 0.0
    ini.core_profiles.bulk = :DT
    ini.core_profiles.impurity = :Ne #Barium :Ba
    ini.core_profiles.helium_fraction = 0.01  # No helium fraction in PyTok

    ini.core_profiles.greenwald_fraction = 1.0
    ini.core_profiles.greenwald_fraction_ped = 0.7
    ini.core_profiles.T_ratio = 1.0
    ini.core_profiles.T_shaping = 2.5
    ini.core_profiles.n_shaping = 1.1
    ini.core_profiles.ejima = 0.0

    ini.oh.n_coils = 8
    ini.oh.technology = :HTS

    ini.pf_active.n_coils_inside = 6
    ini.pf_active.n_coils_outside = 0
    ini.pf_active.technology = :ITER

    ini.tf.n_coils = 12
    ini.tf.technology = :HTS
    ini.tf.shape = :rectangle
    ini.tf.ripple = 0.005 # this is to avoid the TF coming in too close

    act.ActorPFcoilsOpt.symmetric = true
    act.ActorEquilibrium.symmetrize = true

    ini.ec_launcher[1].power_launched = 150.e6 #  some at rho = 0.7 with a 0.2 width some in core 

    ini.requirements.flattop_duration = 1800.0
    ini.requirements.tritium_breeding_ratio = 1.1
    ini.requirements.power_electric_net = 236e6 # from PyTok

    act.ActorFluxMatcher.evolve_densities = :flux_match
    act.ActorTGLF.user_specified_model = "sat1_em_iter"

    act.ActorStabilityLimits.models = Symbol[]

    set_new_base!(ini)
    set_new_base!(act)

    return ini, act
end
