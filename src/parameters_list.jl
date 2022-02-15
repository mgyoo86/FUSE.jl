top_level_parameters = [:general, :equilibrium, :coil, :build, :gasc, :ods]

function Parameters()
    params = Parameters(Dict{Symbol,Union{Parameter,Parameters}}())
    for item in top_level_parameters
        setproperty!(params, item, Parameters(item))
    end
    return params
end

function Parameters(what::Symbol)
    if what in top_level_parameters
        params = Parameters(Dict{Symbol,Union{Parameter,Parameters}}())

        if what == :general
            general = params
            general.init_from = Entry(Symbol, "", "Initialize run from") # [:ods, :scalars, :gasc]

        elseif what == :equilibrium
            equilibrium = params
            equilibrium.B0 = Entry(Real, IMAS.equilibrium__vacuum_toroidal_field, :b0)
            equilibrium.B0 = Entry(Real, IMAS.equilibrium__vacuum_toroidal_field, :b0)
            equilibrium.R0 = Entry(Real, IMAS.equilibrium__vacuum_toroidal_field, :r0)
            equilibrium.Z0 = Entry(Real, IMAS.equilibrium__vacuum_toroidal_field, :r0)
            equilibrium.ϵ = Entry(Real, "", "Plasma aspect ratio")
            equilibrium.δ = Entry(Real, IMAS.equilibrium__time_slice___boundary, :triangularity)
            equilibrium.κ = Entry(Real, IMAS.equilibrium__time_slice___boundary, :elongation)
            equilibrium.βn = Entry(Real, IMAS.equilibrium__time_slice___global_quantities, :beta_normal)
            equilibrium.ip = Entry(Real, IMAS.equilibrium__time_slice___global_quantities, :ip)
            equilibrium.x_point = Entry(Bool, IMAS.equilibrium__time_slice___boundary, :x_point)
            equilibrium.symmetric = Entry(Bool, "", "Is plasma up-down symmetric")
            equilibrium.ngrid = Entry(Int, "", "Resolution of the equilibrium grid"; default=129)

        elseif what == :coil
            coil = params
            coil.green_model = Entry(Symbol, "", "Model to be used for the Greens function table of the PF coils"; default=:simple) # [:simple, :....]

        elseif what == :build
            build = params
            build.n_oh_coils = Entry(Int, "", "Number of OH coils")
            build.n_pf_coils_inside = Entry(Int, "", "Number of PF coils inside of the TF")
            build.n_pf_coils_outside = Entry(Int, "", "Number of PF coils outside of the TF")

            build.is_nuclear_facility = Entry(Bool, "", "Is this a nuclear facility")

        elseif what == :gasc
            gasc = params
            gasc.filename = Entry(String, "", "Output GASC .json file from which data will be loaded")
            gasc.case = Entry(Int, "", "Number of the GASC run to load")
            gasc.no_small_gaps = Entry(Bool, "", "Remove small gaps from the GASC radial build"; default=true)

        elseif what == :ods
            ods = params
            ods.filename = Entry(String, "", "ODS.json file from which equilibrium is loaded")
        end

    else
        params = Parameters()

        if what == :ITER
            params.ods.filename = joinpath(dirname(abspath(@__FILE__)), "..", "sample", "ITER_eq_ods.json")

            params.equilibrium.R0 = 6.2
            params.equilibrium.ϵ = 0.32
            params.equilibrium.κ = 1.85
            params.equilibrium.δ = 0.485
            params.equilibrium.B0 = 5.3
            params.equilibrium.Z0 = 0.4
            params.equilibrium.ip = 15.E6
            params.equilibrium.βn = 2.0
            params.equilibrium.x_point = true
            params.equilibrium.symmetric = false

            params.general.init_from = missing # omitted on purpose to force user to choose

            params.build.is_nuclear_facility = true
            params.build.n_oh_coils = 6
            params.build.n_pf_coils_inside = 0
            params.build.n_pf_coils_outside = 6

        elseif what == :CAT
            params.ods.filename = joinpath(dirname(abspath(@__FILE__)), "..", "sample", "CAT_eq_ods.json")

            params.general.init_from = :ods

            params.build.is_nuclear_facility = false
            params.build.n_oh_coils = 6
            params.build.n_pf_coils_inside = 0
            params.build.n_pf_coils_outside = 6

        elseif what == :D3D
            params.ods.filename = joinpath(dirname(abspath(@__FILE__)), "..", "sample", "D3D_eq_ods.json")

            params.general.init_from = :ods

            params.build.is_nuclear_facility = false
            params.build.n_oh_coils = 20
            params.build.n_pf_coils_inside = 18
            params.build.n_pf_coils_outside = 0

        elseif what == :FPP
            params.gasc.filename = joinpath(dirname(abspath(@__FILE__)), "..", "sample", "FPP_fBS_PBpR_scan.json")
            params.gasc.case = 59
            params.gasc.no_small_gaps = true

            params.general.init_from = :gasc

            params.build.is_nuclear_facility = true
            params.build.n_oh_coils = 6
            params.build.n_pf_coils_inside = 0
            params.build.n_pf_coils_outside = 6
        else
            throw(InexistentParameterException(what))
        end
    end
    
    return params
end
