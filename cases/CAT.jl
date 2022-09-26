"""
    case_parameters(:CAT)

GA Compact Advanced Tokamak design
"""
function case_parameters(::Type{Val{:CAT}})::Tuple{ParametersAllInits,ParametersAllActors}
    ini = ParametersAllInits()
    act = ParametersAllActors()

    ini.general.casename = "CAT"
    ini.general.init_from = :ods

    ini.ods.filename = joinpath(@__DIR__, "..", "sample", "CAT_eq_ods.json")

    ini.build.blanket = 1.0
    ini.build.shield = 0.5
    ini.build.vessel = 0.125
    ini.build.n_first_wall_conformal_layers = 2
    ini.material.shield = "Tungsten"
    ini.material.blanket = "FLiBe"

    ini.pf_active.n_oh_coils = 6
    ini.pf_active.n_pf_coils_inside = 0
    ini.pf_active.n_pf_coils_outside = 6
    ini.pf_active.technology = coil_technology(:ITER, :PF)

    ini.tf.shape = :princeton_D_scaled
    ini.tf.n_coils = 16
    ini.tf.technology = coil_technology(:ITER, :TF)

    ini.oh.technology = coil_technology(:ITER, :OH)
    ini.core_profiles.ne_ped = 7E19
    ini.core_profiles.greenwald_fraction = 0.8
    ini.core_profiles.helium_fraction = 0.01
    ini.core_profiles.T_shaping = 1.8
    ini.core_profiles.w_ped = 0.08
    ini.core_profiles.zeff = 2.5
    ini.core_profiles.rot_core = 0.0
    ini.core_profiles.bulk = :DT
    ini.core_profiles.impurity = :Ne

    ini.target.flattop_duration = 1000.0

    ini.nbi.power_launched = 20E6
    ini.nbi.beam_energy = 200e3
    ini.nbi.beam_mass = 2
    ini.nbi.toroidal_angle = 0.0

    act.ActorPFcoilsOpt.symmetric = true

    return set_new_base!(ini), set_new_base!(act)
end