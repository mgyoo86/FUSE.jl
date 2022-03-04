function Parameters(::Type{Val{:FPP}}; init_from::Symbol)
    par = Parameters()
    par.general.casename = "FPP_$(init_from)"
    par.general.init_from = init_from

    par.gasc.filename = joinpath(dirname(abspath(@__FILE__)), "..", "sample", "FPP_fBS_PBpR_scan.json")
    par.gasc.case = 59
    par.gasc.no_small_gaps = true
    gasc = GASC(par.gasc.filename, par.gasc.case)

    if init_from == :ods
        par.ods.filename = joinpath(dirname(abspath(@__FILE__)), "..", "sample", "fpp_gasc_59_step.json")
    else
        par.core_profiles.rot_core = 0.0
        par.core_profiles.bulk = :DT
    end

    par.build.is_nuclear_facility = true
    par.build.symmetric = false

    par.tf.shape = 3
    par.tf.n_coils = 16
    par.tf.technology = coil_technology(gasc, :TF)

    par.oh.technology = coil_technology(gasc, :OH)

    par.pf_active.n_oh_coils = 6
    par.pf_active.n_pf_coils_inside = 0
    par.pf_active.technology = coil_technology(gasc, :PF)
    par.pf_active.n_pf_coils_outside = 4

    par.material.shield = "Tungsten"
    par.material.blanket = "FLiBe"

    return set_new_base!(par)
end
