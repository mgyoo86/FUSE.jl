#= ==================== =#
#  init equilibrium IDS  #
#= ==================== =#
"""
    init_equilibrium(dd::IMAS.dd, ini::ParametersAllInits, act::ParametersAllActors)

Initialize `dd.equilibrium` starting from 0D `ini` parameters and `act` actor parameters.
"""
function init_equilibrium(dd::IMAS.dd, ini::ParametersAllInits, act::ParametersAllActors)
    init_from = ini.general.init_from

    if init_from == :ods
        dd1 = IMAS.json2imas(ini.ods.filename)
        if !ismissing(dd1.equilibrium, :time) && length(keys(dd1.equilibrium.time)) > 0
            dd.global_time = max(dd.global_time, maximum(dd1.equilibrium.time))
            dd.equilibrium = dd1.equilibrium
            IMAS.flux_surfaces(dd.equilibrium.time_slice[])
        else
            init_from = :scalars
        end
    end

    if init_from == :scalars
        # init equilibrium
        init_equilibrium(
            dd.equilibrium;
            B0=ini.equilibrium.B0,
            R0=ini.equilibrium.R0,
            Z0=ini.equilibrium.Z0,
            ϵ=ini.equilibrium.ϵ,
            κ=ini.equilibrium.κ,
            δ=ini.equilibrium.δ,
            βn=ini.equilibrium.βn,
            ip=ini.equilibrium.ip,
            boundary_switch=ini.equilibrium.boundary_from,
            MXH_params=getproperty(ini.equilibrium, :MXH_params, missing),
            x_point=ini.equilibrium.x_point,
            symmetric=ini.equilibrium.symmetric)

        # solve equilibrium
        ActorEquilibrium(dd, act)
    end

    # field null surface
    if ini.equilibrium.field_null_surface > 0.0
        pushfirst!(dd.equilibrium.time_slice, field_null_surface(dd.equilibrium.time_slice[], ini.equilibrium.field_null_surface))
        pushfirst!(dd.equilibrium.vacuum_toroidal_field.b0, @ddtime(dd.equilibrium.vacuum_toroidal_field.b0))
        pushfirst!(dd.equilibrium.time, -Inf)
        dd.equilibrium.time_slice[1].time = -Inf
    end

    return dd
end

"""
    function init_equilibrium(
        eq::IMAS.equilibrium;
        B0::Real,
        R0::Real,
        Z0::Real,
        ϵ::Real,
        κ::Real,
        δ::Real,
        βn::Real,
        ip::Real,
        x_point::Union{Vector,NTuple{2},Bool} = false,
        symmetric::Bool=true)

Initialize equilibrium IDS based on some basic Miller geometry parameters
"""
function init_equilibrium(
    eq::IMAS.equilibrium;
    B0::Real,
    R0::Real,
    Z0::Real,
    ϵ::Real,
    κ::Real,
    δ::Real,
    βn::Real,
    ip::Real,
    boundary_switch::Symbol,
    rz_points::Union{Missing,Vector{Vector{<:Real}}}=missing,
    MXH_params::Union{Missing,Vector{<:Real}}=missing,
    x_point::Union{AbstractVector,NTuple{2},Bool}=false,
    symmetric::Bool=true)

    eqt = resize!(eq.time_slice)
    eqt.boundary.minor_radius = ϵ * R0
    eqt.boundary.geometric_axis.r = R0
    eqt.boundary.geometric_axis.z = Z0
    eqt.boundary.elongation = κ
    eqt.boundary.triangularity = δ
    eqt.global_quantities.ip = ip
    eqt.global_quantities.beta_normal = βn
    if x_point === true
        mr, mz = miller(R0, ϵ, κ, δ)
        mz .+= Z0
        i = argmax(abs.(IMAS.curvature(mr, mz)) .* (mz .< Z0))
        x_point = (mr[i], mz[i])
    end
    if isa(x_point, Union{AbstractVector,Tuple})
        resize!(eqt.boundary.x_point, 1)
        eqt.boundary.x_point[1].r = x_point[1]
        eqt.boundary.x_point[1].z = x_point[2]
        if symmetric
            resize!(eqt.boundary.x_point, 2)
            eqt.boundary.x_point[2].r = x_point[1]
            eqt.boundary.x_point[2].z = -x_point[2]
        end
    end
    eq.vacuum_toroidal_field.r0 = R0
    @ddtime eq.vacuum_toroidal_field.b0 = B0

    eq1d = eqt.profiles_1d
    p_core_estimate = 1.5 * IMAS.pressure_avg_from_beta_n(eqt.global_quantities.beta_normal, eqt.boundary.minor_radius, B0, eqt.global_quantities.ip)

    psin = eq1d.psi = LinRange(0, 1, 129)
    eq1d.j_tor = eqt.global_quantities.ip .* (1.0 .- psin .^ 2) ./ eqt.boundary.geometric_axis.r
    eq1d.pressure = p_core_estimate .- p_core_estimate .* psin

    # Set the boundary based on 
    if boundary_switch == :rz_points
        if ismissing(rz_points)
            error("ini.equilibrium.boundary_from is set as $boundary_switch but rz_points wasn't set")
        end
        eqt.boundary.outline.r, eqt.boundary.outline.z = rz_points[1], rz_points[2]
    elseif boundary_switch == :MXH_params
        if ismissing(MXH_params)
            error("ini.equilibrium.boundary_from is set as $boundary_switch but MXH_params wasn't set")
        end
        mxh = IMAS.MXH(MXH_params)()
        eqt.boundary.outline.r, eqt.boundary.outline.z = mxh[1], mxh[2]
    elseif boundary_switch == :scalars
        eqt.boundary.outline.r, eqt.boundary.outline.z = miller(R0, ϵ, κ, δ)
        eqt.boundary.outline.z .+= Z0
    end
    return eq
end

"""
    field_null_surface(eqt, scale = 0.25, abs_psi_boundary = 0.1)

Return field null surface by scaling an existing equilibrium time_slice
"""
function field_null_surface(eqt::IMAS.equilibrium__time_slice, scale::Real=0.25, abs_psi_boundary::Real=0.1)
    eqb = IMAS.equilibrium__time_slice()
    eqb.global_quantities.psi_boundary = sign(eqt.profiles_1d.psi[1] - eqt.profiles_1d.psi[end]) * abs_psi_boundary
    eqb.boundary.outline.r, eqb.boundary.outline.z, _ = IMAS.flux_surface(eqt, eqt.profiles_1d.psi[1] * (1 - scale) + eqt.profiles_1d.psi[end] * scale)
    eqb.boundary.outline.r .-= minimum(eqb.boundary.outline.r) .- minimum(IMAS.flux_surface(eqt, eqt.profiles_1d.psi[end])[1])
    eqb.profiles_1d.psi = [eqb.global_quantities.psi_boundary]
    eqb.profiles_1d.f = [eqt.profiles_1d.f[end]]
    return eqb
end