#= ========= =#
#  OH magnet  #
#= ========= =#
"""
    oh_maximum_J_B!(bd::IMAS.build; j_tolerance)

Evaluate maxium OH current density and magnetic field for given geometry and technology

NOTES:
* Equations from GASC (Stambaugh FST 2011)
* Also relevant: `Engineering design solutions of flux swing with structural requirements for ohmic heating solenoids` Smith, R. A. September 30, 1977
"""
function oh_maximum_J_B!(bd::IMAS.build; j_tolerance)
    OH = IMAS.get_build(bd, type=_oh_)
    innerSolenoidRadius = OH.start_radius
    outerSolenoidRadius = OH.end_radius

    # find maximum superconductor critical_j given self-field
    function max_J_OH(x)
        currentDensityOH = abs(x[1])
        magneticFieldSolenoidBore = currentDensityOH / 1E6 * (0.4 * pi * outerSolenoidRadius * (1.0 - innerSolenoidRadius / outerSolenoidRadius))
        critical_j = coil_Jcrit(magneticFieldSolenoidBore, bd.oh.technology)
        # do not use relative error here. Absolute error tells optimizer to lower currentDensityOH if critical_j==0
        return abs(critical_j - currentDensityOH * (1.0 + j_tolerance))
    end
    res = Optim.optimize(max_J_OH, 0.0, 1E9, Optim.GoldenSection(), rel_tol=1E-3)

    # solenoid maximum current and field
    bd.oh.max_j = abs(res.minimizer[1])
    bd.oh.max_b_field = bd.oh.max_j / 1E6 * (0.4 * pi * outerSolenoidRadius * (1.0 - innerSolenoidRadius / outerSolenoidRadius))
    bd.oh.critical_j = coil_Jcrit(bd.oh.max_b_field, bd.oh.technology)
end

"""
    oh_required_J_B!(bd::IMAS.build, double_swing::Bool=true)

Evaluate OH current density and B_field required for given rampup and flattop
NOTES:
* Equations from GASC (Stambaugh FST 2011)
* Also relevant: `Engineering design solutions of flux swing with structural requirements for ohmic heating solenoids` Smith, R. A. September 30, 1977
"""
function oh_required_J_B!(bd::IMAS.build, double_swing::Bool=true)
    OH = IMAS.get_build(bd, type=_oh_)
    innerSolenoidRadius = OH.start_radius
    outerSolenoidRadius = OH.end_radius

    totalOhFluxReq = bd.flux_swing_estimates.rampup + bd.flux_swing_estimates.flattop + bd.flux_swing_estimates.pf

    # Calculate magnetic field at solenoid bore required to match flux swing request
    RiRo_factor = innerSolenoidRadius / outerSolenoidRadius
    magneticFieldSolenoidBore = 3.0 * totalOhFluxReq / pi / outerSolenoidRadius^2 / (RiRo_factor^2 + RiRo_factor + 1.0) / (double_swing ? 2 : 1)
    currentDensityOH = magneticFieldSolenoidBore / (0.4 * pi * outerSolenoidRadius * (1 - innerSolenoidRadius / outerSolenoidRadius))

    # minimum requirements for OH
    bd.oh.max_b_field = magneticFieldSolenoidBore
    bd.oh.max_j = currentDensityOH * 1E6
    bd.oh.critical_j = coil_Jcrit(bd.oh.max_b_field, bd.oh.technology)
end

"""
    max_flattop_flux!(bd::IMAS.build, eqt::IMAS.equilibrium__time_slice, cp1d::IMAS.core_profiles__profiles_1d; double_swing::Bool=true)

Estimate OH flux requirement during flattop (if j_ohmic profile is missing then steady state ohmic profile is assumed)
"""
function max_flattop_flux!(bd::IMAS.build, eqt::IMAS.equilibrium__time_slice, cp1d::IMAS.core_profiles__profiles_1d; double_swing::Bool=true)
    OH = IMAS.get_build(bd, type=_oh_)
    innerSolenoidRadius = OH.start_radius
    outerSolenoidRadius = OH.end_radius

    # estimate oh flattop flux and duration
    RiRo_factor = innerSolenoidRadius / outerSolenoidRadius
    totalOhFlux = bd.oh.max_b_field * (pi * outerSolenoidRadius^2 * (RiRo_factor^2 + RiRo_factor + 1.0) * (double_swing ? 2 : 1)) / 3.0
    bd.flux_swing_estimates.flattop = totalOhFlux - bd.flux_swing_estimates.rampup - bd.flux_swing_estimates.pf
    if ismissing(cp1d, :j_ohmic)
        j_ohmic = IMAS.j_ohmic_steady_state(eqt, cp1d)
    else
        j_ohmic = cp1d.j_ohmic
    end
    bd.oh.flattop_estimate = bd.flux_swing_estimates.flattop / abs(integrate(cp1d.grid.area, j_ohmic ./ cp1d.conductivity_parallel))
end

#= ========= =#
#  TF magnet  #
#= ========= =#
"""
    tf_maximum_J_B!(bd::IMAS.build; j_tolerance)

Evaluate maxium TF current density and magnetic field for given geometry and technology
"""
function tf_maximum_J_B!(bd::IMAS.build; j_tolerance)
    hfsTF = IMAS.get_build(bd, type=_tf_, fs=_hfs_)
    TF_cx_area = hfsTF.thickness * bd.tf.wedge_thickness

    # find maximum superconductor critical_j given self-field
    function max_J_TF(x)
        currentDensityTF = abs(x[1])
        current_TF = currentDensityTF * TF_cx_area
        max_b_field = current_TF / hfsTF.end_radius / 2pi * constants.μ_0 * bd.tf.coils_n
        critical_j = coil_Jcrit(max_b_field, bd.tf.technology)
        # do not use relative error here. Absolute error tells optimizer to lower currentDensityTF if critical_j==0
        return abs(critical_j - currentDensityTF * (1.0 + j_tolerance))
    end
    res = Optim.optimize(max_J_TF, 0.0, 1E9, Optim.GoldenSection(), rel_tol=1E-3)

    # tf maximum current and field
    bd.tf.max_j = abs(res.minimizer[1])
    current_TF = bd.tf.max_j * TF_cx_area
    bd.tf.max_b_field = current_TF / hfsTF.end_radius / 2pi * constants.μ_0 * bd.tf.coils_n
    bd.tf.critical_j = coil_Jcrit(bd.tf.max_b_field, bd.tf.technology)
end

"""
    tf_required_J_B!(bd::IMAS.build)

Evaluate TF current density given a B_field
"""
function tf_required_J_B!(bd::IMAS.build, eq::IMAS.equilibrium)
    hfsTF = IMAS.get_build(bd, type=_tf_, fs=_hfs_)
    lfsTF = IMAS.get_build(bd, type=_tf_, fs=_lfs_)
    B0 = abs(maximum(eq.vacuum_toroidal_field.b0))
    R0 = (hfsTF.end_radius + lfsTF.start_radius) / 2.0

    # current in the TF coils
    current_TF = B0 * R0 * 2pi / constants.μ_0 / bd.tf.coils_n
    TF_cx_area = hfsTF.thickness * bd.tf.wedge_thickness

    bd.tf.max_b_field = B0 * R0 / hfsTF.end_radius
    bd.tf.max_j = current_TF / TF_cx_area
    bd.tf.critical_j = coil_Jcrit(bd.tf.max_b_field, bd.tf.technology)
end

#= ========== =#
#  flux-swing #
#= ========== =#
mutable struct FluxSwingActor <: AbstractActor
    dd::IMAS.dd
end

function ActorParameters(::Type{Val{:FluxSwingActor}})
    par = ActorParameters(nothing)
    return par
end

function FluxSwingActor(dd::IMAS.dd, act::ActorParameters; kw...)
    par = act.FluxSwingActor(kw...)
    actor = FluxSwingActor(dd)
    step(actor)
    finalize(actor)
    return actor
end

function step(actor::FluxSwingActor; j_tolerance::Float64=0.4, only=:all)
    bd = actor.dd.build
    eq = actor.dd.equilibrium
    eqt = eq.time_slice[]
    cp = actor.dd.core_profiles
    cp1d = cp.profiles_1d[]

    if only ∈ [:all, :tf]
        # find what's the best this TF can do given its geometry and technology
        tf_maximum_J_B!(bd; j_tolerance)
    end
    if only ∈ [:all, :oh]
        # find what's the best this OH can do given its geometry and technology
        oh_maximum_J_B!(bd; j_tolerance)

        # breakdown of OH flux swing usage
        bd.flux_swing_estimates.rampup = rampup_flux_estimates(eqt, cp)
        bd.flux_swing_estimates.pf = pf_flux_estimates(eqt)
        bd.flux_swing_estimates.flattop = flattop_flux_estimates(bd, eqt, cp1d)

        max_flattop_flux!(bd, eqt, cp1d)
    end
    return actor
end

# function step(actor::FluxSwingActor; j_tolerance=NaN)
#     bd = actor.dd.build
#     eq = actor.dd.equilibrium
#     eqt = eq.time_slice[]
#     cp = actor.dd.core_profiles
#     cp1d = cp.profiles_1d[]

#     bd.flux_swing_estimates.rampup = rampup_flux_estimates(eqt, cp)
#     bd.flux_swing_estimates.pf = pf_flux_estimates(eqt)
#     bd.flux_swing_estimates.flattop = flattop_flux_estimates(bd, eqt, cp1d)
#     oh_required_J_B!(bd)
#     max_flattop_flux!(bd, eqt, cp1d)

#     tf_required_J_B!(bd, eq)

#     return actor
# end

"""
    rampup_flux_estimates(eqt::IMAS.equilibrium__time_slice, cp::IMAS.core_profiles)

Estimate OH flux requirement during rampup, where
eqt is supposed to be the equilibrium right at the end of the rampup phase, beginning of flattop
and core_profiles is only used to get core_profiles.global_quantities.ejima
"""
function rampup_flux_estimates(eqt::IMAS.equilibrium__time_slice, cp::IMAS.core_profiles)
    ###### what equilibrium time-slice should we use to evaluate rampup flux requirements?

    # from IMAS dd to local variables
    majorRadius = eqt.boundary.geometric_axis.r
    minorRadius = eqt.boundary.minor_radius
    elongation = eqt.boundary.elongation
    plasmaCurrent = eqt.global_quantities.ip / 1E6 # in [MA]
    li = eqt.global_quantities.li_3 # what li
    ejima = @ddtime cp.global_quantities.ejima

    # evaluate plasma inductance
    plasmaInductanceInternal = 0.4 * 0.5 * pi * majorRadius * li
    plasmaInductanceExternal = 0.4 * pi * majorRadius * (log(8.0 * majorRadius / minorRadius / sqrt(elongation)) - 2.0)
    plasmaInductanceTotal = plasmaInductanceInternal + plasmaInductanceExternal

    # estimate rampup flux requirement
    rampUpFlux = (ejima * 0.4 * pi * majorRadius + plasmaInductanceTotal) * plasmaCurrent

    return abs(rampUpFlux)
end

"""
    flattop_flux_estimates(bd::IMAS.build, eqt::IMAS.equilibrium__time_slice, cp1d::IMAS.core_profiles__profiles_1d)

Estimate OH flux requirement during flattop (if j_ohmic profile is missing then steady state ohmic profile is assumed)
"""
function flattop_flux_estimates(bd::IMAS.build, eqt::IMAS.equilibrium__time_slice, cp1d::IMAS.core_profiles__profiles_1d)
    if ismissing(cp1d, :j_ohmic)
        j_ohmic = IMAS.j_ohmic_steady_state(eqt, cp1d)
    else
        j_ohmic = cp1d.j_ohmic
    end
    return abs(integrate(cp1d.grid.area, j_ohmic ./ cp1d.conductivity_parallel)) * bd.oh.flattop_duration # V*s
end

"""
    pf_flux_estimates(eqt::IMAS.equilibrium__time_slice)

Estimate vertical field from PF coils and its contribution to flux swing, where
`eqt` is supposed to be the equilibrium right at the end of the rampup phase, beginning of flattop
"""
function pf_flux_estimates(eqt::IMAS.equilibrium__time_slice)
    # from IMAS dd to local variables
    majorRadius = eqt.boundary.geometric_axis.r
    minorRadius = eqt.boundary.minor_radius
    elongation = eqt.boundary.elongation
    plasmaCurrent = eqt.global_quantities.ip / 1E6 # in [MA]
    betaP = eqt.global_quantities.beta_pol
    li = eqt.global_quantities.li_3 # what li does Stambaugh FST 2011 use?

    # estimate vertical field and its contribution to flux swing
    verticalFieldAtCenter = 0.1 * plasmaCurrent / majorRadius * (log(8.0 * majorRadius / (minorRadius * sqrt(elongation))) - 1.5 + betaP + 0.5 * li)
    fluxFromVerticalField = 0.8 * verticalFieldAtCenter * pi * (majorRadius^2 - (majorRadius - minorRadius)^2)

    return -abs(fluxFromVerticalField)
end

#= ============== =#
#  OH TF stresses  #
#= ============== =#
mutable struct StressesActor <: AbstractActor
    dd::IMAS.dd
end

function ActorParameters(::Type{Val{:StressesActor}})
    par = ActorParameters(nothing)
    return par
end

function StressesActor(dd::IMAS.dd, act::ActorParameters; kw...)
    par = act.StressesActor(kw...)
    actor = StressesActor(dd)
    step(actor)
    finalize(actor)
    return actor
end

function step(actor::StressesActor)
    eq = actor.dd.equilibrium
    bd = actor.dd.build
    sm = actor.dd.solid_mechanics

    R_tf_in = IMAS.get_build(bd, type=_tf_, fs=_hfs_).start_radius
    R_tf_out = IMAS.get_build(bd, type=_tf_, fs=_hfs_).end_radius
    R0 = (R_tf_in + R_tf_out) / 2.0
    B0 = maximum(eq.vacuum_toroidal_field.b0)
    Bz_oh = bd.oh.max_b_field
    R_oh_in = IMAS.get_build(bd, type=_oh_).start_radius
    R_oh_out = IMAS.get_build(bd, type=_oh_).end_radius
    f_struct_tf = bd.tf.technology.fraction_stainless
    f_struct_oh = bd.oh.technology.fraction_stainless

    bucked = sm.center_stack.bucked == 1
    noslip = sm.center_stack.noslip == 1
    plug = sm.center_stack.plug == 1
    empty!(sm.center_stack)

    for oh_on in [true, false]
        solve_1D_solid_mechanics!(
            sm.center_stack,
            R0,
            B0,
            R_tf_in,
            R_tf_out,
            oh_on ? Bz_oh : 0.0,
            R_oh_in,
            R_oh_out;
            bucked=bucked,
            noslip=noslip,
            plug=plug,
            f_struct_tf=f_struct_tf,
            f_struct_oh=f_struct_oh,
            f_struct_pl=1.0,
            n_points=5,
            verbose=false
        )
    end

end

@recipe function plot_StressesActor(actor::StressesActor)
    @series begin
        actor.dd.solid_mechanics.center_stack.stress
    end
end

#= ========== =#
#  LFS sizing  #
#= ========== =#
mutable struct LFSsizingActor <: AbstractActor
    dd::IMAS.dd
end

function ActorParameters(::Type{Val{:LFSsizingActor}})
    par = ActorParameters(nothing)
    par.do_plot = Entry(Bool, "", "plot"; default=false)
    par.verbose = Entry(Bool, "", "verbose"; default=false)
    return par
end

function LFSsizingActor(dd::IMAS.dd, act::ActorParameters; kw...)
    par = act.LFSsizingActor(kw...)
    if par.do_plot
        plot(dd.build)
    end
    actor = LFSsizingActor(dd)
    step(actor; par.verbose)
    finalize(actor)
    if par.do_plot
        display(plot!(dd.build; cx=false))
    end
    return actor
end

function step(actor::LFSsizingActor; verbose::Bool=false)
    dd = actor.dd

    new_TF_radius = IMAS.R_tf_ripple(IMAS.get_build(dd.build, type=_plasma_).end_radius, dd.build.tf.ripple, dd.build.tf.coils_n)

    itf = IMAS.get_build(dd.build, type=_tf_, fs=_lfs_, return_index=true) - 1
    iplasma = IMAS.get_build(dd.build, type=_plasma_, return_index=true) + 1

    # resize layers proportionally
    # start from the vacuum gaps before resizing the material layers
    for vac in [true, false]
        old_TF_radius = IMAS.get_build(dd.build, type=_tf_, fs=_lfs_).start_radius
        delta = new_TF_radius - old_TF_radius
        if verbose
            println("TF radius changed by $delta [m]")
        end
        thicknesses = [dd.build.layer[k].thickness for k in iplasma:itf if !vac || lowercase(dd.build.layer[k].material) == "vacuum"]
        for k in iplasma:itf
            if !vac || lowercase(dd.build.layer[k].material) == "vacuum"
                dd.build.layer[k].thickness *= (1 + delta / sum(thicknesses))
                hfs_thickness = IMAS.get_build(dd.build, identifier=dd.build.layer[k].identifier, fs=_hfs_).thickness
                if dd.build.layer[k].thickness < hfs_thickness
                    dd.build.layer[k].thickness = hfs_thickness
                end
            end
        end
    end

end

#= ========== =#
#  HFS sizing  #
#= ========== =#
mutable struct HFSsizingActor <: AbstractActor
    stresses_actor::StressesActor
    fluxswing_actor::FluxSwingActor
end

function ActorParameters(::Type{Val{:HFSsizingActor}})
    par = ActorParameters(nothing)
    par.j_tolerance = Entry(Float64, "", "Tolerance on the conductor current limits"; default=0.4)
    par.stress_tolerance = Entry(Float64, "", "Tolerance on the structural stresses limits"; default=0.2)
    par.fixed_plasma_start_radius = Entry(Bool, "", "Pad/trim center stack layers so not to move plasma start radius"; default=false)
    par.do_plot = Entry(Bool, "", "plot"; default=false)
    par.verbose = Entry(Bool, "", "verbose"; default=false)
    return par
end

function HFSsizingActor(dd::IMAS.dd, act::ActorParameters; kw...)
    par = act.HFSsizingActor(kw...)
    if par.do_plot
        plot(dd.build)
    end
    fluxswing_actor = FluxSwingActor(dd)
    stresses_actor = StressesActor(dd)
    actor = HFSsizingActor(stresses_actor, fluxswing_actor)
    step(actor; verbose=par.verbose, j_tolerance=par.j_tolerance, stress_tolerance=par.stress_tolerance, fixed_plasma_start_radius=par.fixed_plasma_start_radius)
    finalize(actor)
    if par.do_plot
        display(plot!(dd.build; cx=false))
    end
    return actor
end

function step(actor::HFSsizingActor; verbose::Bool=false, j_tolerance::Real=0.4, stress_tolerance::Real=0.2, fixed_plasma_start_radius::Bool=false, do_plot=false)

    function target_value_cost(value, target, tolerance)
        return (value .* (1.0 .+ tolerance) .- target) ./ target
    end

    function assign_PL_OH_TF_thicknesses(x0, what)
        x0 = map(abs, x0)
        for k in 1:iplasma-1
            dd.build.layer[k].thickness = old_thicknesses[k]
        end
        if what == :oh
            plug.thickness, OH.thickness = x0
        elseif what == :tf
            TFhfs.thickness = x0[1]
        else
            plug.thickness, OH.thickness, TFhfs.thickness = x0
        end
        #dd.build.oh.technology.fraction_stainless = dd.build.tf.technology.fraction_stainless = (atan(fraction_stainless) + pi / 2) / pi
        if fixed_plasma_start_radius
            new_plasma_radius = dd.build.layer[iplasma].start_radius
            scale = old_plasma_radius / new_plasma_radius
            for k in 1:iplasma-1
                dd.build.layer[k].thickness *= scale
            end
        end
        TFlfs.thickness = TFhfs.thickness
    end

    function cost(x0, what)
        # assign optimization arguments and evaluate coils currents and stresses
        assign_PL_OH_TF_thicknesses(x0, what)
        step(actor.fluxswing_actor; j_tolerance, only=what)
        step(actor.stresses_actor)
        R0 = (TFhfs.end_radius + TFlfs.start_radius) / 2.0

        # OH and plug sizing based on stresses
        if what ∈ [:oh, :all]
            c_soh = target_value_cost(maximum(dd.solid_mechanics.center_stack.stress.vonmises.oh), stainless_steel.yield_strength, stress_tolerance)
            if !ismissing(dd.solid_mechanics.center_stack.stress.vonmises, :pl)
                c_spl = target_value_cost(maximum(dd.solid_mechanics.center_stack.stress.vonmises.pl), stainless_steel.yield_strength, stress_tolerance)
            else
                c_spl = 0.0
            end
        else
            c_soh = c_spl = 0.0
        end

        # TF sizing based on stresses
        if what ∈ [:tf, :all]
            c_stf = target_value_cost(maximum(dd.solid_mechanics.center_stack.stress.vonmises.tf), stainless_steel.yield_strength, stress_tolerance)
        else
            c_stf = 0.0
        end

        # OH sizing based on flattop_duration requirement
        if what ∈ [:oh, :all]
            c_fl = target_value_cost(dd.build.oh.flattop_estimate, dd.build.oh.flattop_duration, 0.0)
        else
            c_fl = 0.0
        end

        # TF sizing based on B0 requirement
        if what ∈ [:tf, :all]
            B0 = dd.build.tf.max_b_field * TFhfs.end_radius / R0
            c_b0 = target_value_cost(B0, target_B0, 0.0) * 10
        else
            c_b0 = 0.0
        end

        # try not to change aspect ratio and minimize OH and TF layers thicknesses
        new_plasma_radius = dd.build.layer[iplasma].start_radius
        c_cs = target_value_cost(new_plasma_radius, old_plasma_radius, 0.0)
        c_cs += OH.thickness / old_plasma_radius
        c_cs += TFhfs.thickness / old_plasma_radius

        if do_plot
            push!(C_SOH, c_soh)
            push!(C_STF, c_stf)
            push!(C_FL, c_fl)
            push!(C_B0, c_b0)
            push!(C_CS, c_cs)
        end

        # total cost
        return norm(vcat([c_soh, c_stf, c_spl], [c_fl, c_b0, c_cs]))
    end

    @assert actor.stresses_actor.dd === actor.fluxswing_actor.dd
    dd = actor.stresses_actor.dd
    target_B0 = maximum(abs.(dd.equilibrium.vacuum_toroidal_field.b0))

    # init
    plug = dd.build.layer[1]
    OH = IMAS.get_build(dd.build, type=_oh_)
    TFhfs = IMAS.get_build(dd.build, type=_tf_, fs=_hfs_)
    TFlfs = IMAS.get_build(dd.build, type=_tf_, fs=_lfs_)
    iplasma = IMAS.get_build(dd.build, type=_plasma_, return_index=true)
    old_plasma_radius = dd.build.layer[iplasma].start_radius
    fraction_stainless = tan(0.9 * pi - pi / 2)
    eq_R0 = dd.equilibrium.vacuum_toroidal_field.r0

    if do_plot
        C_SOH = []
        C_STF = []
        C_FL = []
        C_B0 = []
        C_CS = []
    end

    # initialize all dd fields
    step(actor.fluxswing_actor; j_tolerance, only=:all)

    # plug and OH optimization
    old_thicknesses = [layer.thickness for layer in dd.build.layer]
    res_oh = Optim.optimize(x0 -> cost(x0, :oh), [plug.thickness, OH.thickness], Optim.NelderMead(), Optim.Options(time_limit=60, iterations=1000); autodiff=:forward)
    assign_PL_OH_TF_thicknesses(res_oh.minimizer, :oh)
    step(actor.fluxswing_actor; j_tolerance, only=:oh)
    step(actor.stresses_actor)

    # TF optimization
    old_thicknesses = [layer.thickness for layer in dd.build.layer]
    res_tf = Optim.optimize(x0 -> cost(x0, :tf), [TFhfs.thickness], Optim.NelderMead(), Optim.Options(time_limit=60, iterations=1000); autodiff=:forward)
    assign_PL_OH_TF_thicknesses(res_tf.minimizer, :tf)
    step(actor.fluxswing_actor; j_tolerance, only=:tf)
    step(actor.stresses_actor)

    # combined plug+OH+TF optimization
    res_all = nothing
    if (dd.solid_mechanics.center_stack.bucked == 1 || dd.solid_mechanics.center_stack.noslip == 1 || dd.solid_mechanics.center_stack.plug == 1) || fixed_plasma_start_radius
        old_thicknesses = [layer.thickness for layer in dd.build.layer]
        res_all = Optim.optimize(x0 -> cost(x0, :all), [OH.thickness, max(0.0, (plug.thickness - OH.thickness)), TFhfs.thickness], Optim.NelderMead(), Optim.Options(time_limit=60, iterations=1000); autodiff=:forward)
        assign_PL_OH_TF_thicknesses(res_all.minimizer, :all)
        step(actor.fluxswing_actor; j_tolerance, only=:all)
        step(actor.stresses_actor)
    end

    if do_plot
        p = plot()
        plot!(p, C_SOH, label="SOH")
        plot!(p, C_STF, label="STF")
        plot!(p, C_FL, label="FL")
        plot!(p, C_B0, label="B0")
        plot!(p, C_CS, label="CS")
        display(p)
    end

    if verbose
        display(res_oh)
        display(res_tf)
        if res_all !== nothing
            display(res_all)
        end

        R0 = (TFhfs.end_radius + TFlfs.start_radius) / 2.0
        @show target_B0
        @show dd.build.tf.max_b_field * TFhfs.end_radius / R0

        @show dd.build.oh.flattop_estimate
        @show dd.build.oh.flattop_duration

        @show dd.build.oh.max_j
        @show dd.build.oh.critical_j
        @show dd.build.oh.max_b_field

        @show dd.build.tf.max_j
        @show dd.build.tf.critical_j
        @show dd.build.tf.max_b_field

        @show maximum(dd.solid_mechanics.center_stack.stress.vonmises.oh)
        @show stainless_steel.yield_strength

        @show maximum(dd.solid_mechanics.center_stack.stress.vonmises.tf)
        @show stainless_steel.yield_strength
    end

    # @assert target_B0 * j_tolerance / 2.0 < dd.build.tf.max_b_field / TFhfs.end_radius * R0
    # @assert dd.build.oh.flattop_estimate * j_tolerance / 2.0 < dd.build.oh.flattop_duration
    # @assert dd.build.oh.max_j < dd.build.oh.critical_j
    # @assert dd.build.tf.max_j < dd.build.tf.critical_j
    # @assert maximum(dd.solid_mechanics.center_stack.stress.vonmises.oh) < stainless_steel.yield_strength
    # @assert maximum(dd.solid_mechanics.center_stack.stress.vonmises.tf) < stainless_steel.yield_strength

    return actor
end

#= ============= =#
#  cross-section  #
#= ============= =#

mutable struct CXbuildActor <: AbstractActor
    dd::IMAS.dd
end

function ActorParameters(::Type{Val{:CXbuildActor}})
    par = ActorParameters(nothing)
    par.rebuild_wall = Entry(Bool, "", "Rebuild wall based on equilibrium"; default=false)
    par.do_plot = Entry(Bool, "", "plot"; default=false)
    return par
end

function CXbuildActor(dd::IMAS.dd, act::ActorParameters; kw...)
    par = act.CXbuildActor(kw...)
    actor = CXbuildActor(dd)
    step(actor; rebuild_wall=par.rebuild_wall)
    finalize(actor)
    if par.do_plot
        plot(dd.build)
        display(plot!(dd.build; cx=false))
    end
    return actor
end

function step(actor::CXbuildActor; rebuild_wall::Bool=true)
    if rebuild_wall
        empty!(actor.dd.wall)
    end
    build_cx(actor.dd)
end

"""
    wall_from_eq(bd::IMAS.build, eqt::IMAS.equilibrium__time_slice; divertor_length_length_multiplier::Real=1.0)

Generate first wall outline starting from an equilibrium
"""
function wall_from_eq(bd::IMAS.build, eqt::IMAS.equilibrium__time_slice; divertor_length_length_multiplier::Real=1.0)
    # Inner radii of the plasma
    R_hfs_plasma = IMAS.get_build(bd, type=_plasma_).start_radius
    R_lfs_plasma = IMAS.get_build(bd, type=_plasma_).end_radius

    # Plasma as buffered convex-hull polygon of LCFS and strike points
    ψb = IMAS.find_psi_boundary(eqt)
    ψa = eqt.profiles_1d.psi[1]
    δψ = 0.10 # this sets the length of the strike divertor legs
    r_in, z_in, _ = IMAS.flux_surface(eqt, ψb * (1 - δψ) + ψa * δψ, true)
    Z0 = eqt.global_quantities.magnetic_axis.z
    rlcfs, zlcfs, _ = IMAS.flux_surface(eqt, ψb, true)
    theta = range(0.0, 2 * pi, length=101)
    private_extrema = []
    private = IMAS.flux_surface(eqt, ψb, false)
    a = 0
    for (pr, pz) in private
        if sign(pz[1] - Z0) != sign(pz[end] - Z0)
            # open flux surface does not encicle the plasma
            continue
        elseif IMAS.minimum_distance_two_shapes(pr, pz, rlcfs, zlcfs) > (maximum(zlcfs) - minimum(zlcfs)) / 20
            # secondary Xpoint far away
            continue
        elseif (sum(pz) - Z0) < 0
            # lower private region
            index = argmax(pz)
            a = minimum(z_in) - minimum(zlcfs)
            a = min(a, pz[index] - minimum(pz))
        else
            # upper private region
            index = argmin(pz)
            a = maximum(zlcfs) - maximum(z_in)
            a = min(a, maximum(pz) - pz[index])
        end
        Rx = pr[index]
        Zx = pz[index]
        a *= divertor_length_length_multiplier
        cr = a .* cos.(theta) .+ Rx
        cz = a .* sin.(theta) .+ Zx
        append!(private_extrema, IMAS.intersection(cr, cz, pr, pz))
    end
    h = [[r, z] for (r, z) in vcat(collect(zip(rlcfs, zlcfs)), private_extrema)]
    hull = convex_hull(h)
    R = [r for (r, z) in hull]
    R[R.<R_hfs_plasma] .= R_hfs_plasma
    R[R.>R_lfs_plasma] .= R_lfs_plasma
    Z = [z for (r, z) in hull]
    hull_poly = xy_polygon(R, Z)
    plasma_poly = LibGEOS.buffer(hull_poly, ((R_lfs_plasma - R_hfs_plasma) - (maximum(rlcfs) - minimum(rlcfs))) / 2.0)

    # make the divertor domes in the plasma
    δψ = 0.05 # how close to the LCFS shoudl the divertor plates be
    for (pr, pz) in IMAS.flux_surface(eqt, ψb * (1 - δψ) + ψa * δψ, false)
        if pr[1] != pr[end]
            pz[1] = pz[1] * 2
            pz[end] = pz[end] * 2
            plasma_poly = LibGEOS.difference(plasma_poly, xy_polygon(pr, pz))
        end
    end

    # plasma first wall
    pr = [v[1] for v in LibGEOS.coordinates(plasma_poly)[1]]
    pz = [v[2] for v in LibGEOS.coordinates(plasma_poly)[1]]

    return pr, pz
end

"""
    build_cx(dd::IMAS.dd)

Translates 1D build to 2D cross-sections starting either wall information
If wall information is missing, then the first wall information is generated starting from equilibrium time_slice
"""
function build_cx(dd::IMAS.dd)
    wall = IMAS.first_wall(dd.wall)
    if wall === missing
        pr, pz = wall_from_eq(dd.build, dd.equilibrium.time_slice[])
        resize!(dd.wall.description_2d, 1)
        resize!(dd.wall.description_2d[1].limiter.unit, 1)
        dd.wall.description_2d[1].limiter.unit[1].outline.r = pr
        dd.wall.description_2d[1].limiter.unit[1].outline.z = pz
        wall = IMAS.first_wall(dd.wall)
    end
    return build_cx(dd.build, wall.r, wall.z)
end

"""
    build_cx(bd::IMAS.build, pr::Vector{Float64}, pz::Vector{Float64})

Translates 1D build to 2D cross-sections starting from R and Z coordinates of plasma first wall
"""
function build_cx(bd::IMAS.build, pr::Vector{Float64}, pz::Vector{Float64})
    ipl = IMAS.get_build(bd, type=_plasma_, return_index=true)
    itf = IMAS.get_build(bd, type=_tf_, fs=_hfs_, return_index=true)

    # plasma pr/pz scaled to 1D radial build
    start_radius = bd.layer[ipl].start_radius
    end_radius = bd.layer[ipl].end_radius
    pr1 = minimum(pr)
    pr2 = maximum(pr)
    fact = (end_radius - start_radius) / (pr2 - pr1)
    pz .= pz .* fact
    pr .= (pr .- pr1) .* fact .+ start_radius
    bd.layer[ipl].outline.r = pr
    bd.layer[ipl].outline.z = pz

    coils_inside = any([contains(lowercase(l.name), "coils") for l in bd.layer])

    # all layers between plasma and OH
    # k+1 means the layer inside (ie. towards the plasma)
    # k   is the current layer
    # k-1 means the layer outside (ie. towards the tf)
    # forward pass: from plasma to TF _convex_hull_ and then desired TF shape
    tf_to_plasma = IMAS.get_build(bd, fs=_hfs_, return_only_one=false, return_index=true)
    plasma_to_tf = reverse(tf_to_plasma)
    for k in plasma_to_tf
        if k == itf + 1
            # layer that is inside of the TF sets TF shape
            FUSE.optimize_shape(bd, k + 1, k, BuildLayerShape(bd.tf.shape); tight=!coils_inside)
        else
            # everything else is conformal convex hull
            FUSE.optimize_shape(bd, k + 1, k, _convex_hull_)
        end
    end
    # reverse pass: from TF to plasma only with negative offset
    # Blanket layer adapts from wall to TF shape
    if bd.layer[tf_to_plasma[end]].type == Int(_wall_)
        n = 2
    else
        n = 1
    end
    for k in tf_to_plasma[1:end-n]
        FUSE.optimize_shape(bd, k, k + 1, _offset_)
    end

    # _in_
    D = minimum(IMAS.get_build(bd, type=_tf_, fs=_hfs_).outline.z)
    U = maximum(IMAS.get_build(bd, type=_tf_, fs=_hfs_).outline.z)
    for k in IMAS.get_build(bd, fs=_in_, return_index=true, return_only_one=false)
        L = bd.layer[k].start_radius
        R = bd.layer[k].end_radius
        bd.layer[k].outline.r, bd.layer[k].outline.z = rectangle_shape(L, R, D, U)
    end

    # _out_
    iout = IMAS.get_build(bd, fs=_out_, return_index=true, return_only_one=false)
    if lowercase(bd.layer[iout[end]].name) == "cryostat"
        olfs = IMAS.get_build(bd, fs=_lfs_, return_index=true, return_only_one=false)[end]
        FUSE.optimize_shape(bd, olfs, iout[end], _silo_)
        for k in reverse(iout[2:end])
            FUSE.optimize_shape(bd, k, k - 1, _offset_)
        end
    else
        for k in iout
            L = 0
            R = bd.layer[k].end_radius
            D = minimum(bd.layer[k-1].outline.z) - bd.layer[k].thickness
            U = maximum(bd.layer[k-1].outline.z) + bd.layer[k].thickness
            bd.layer[k].outline.r, bd.layer[k].outline.z = rectangle_shape(L, R, D, U)
        end
    end

    return bd
end

"""
    optimize_shape(bd::IMAS.build, obstr_index::Int, layer_index::Int, shape::BuildLayerShape)

Generates outline of layer in such a way to maintain minimum distance from inner layer
"""
function optimize_shape(bd::IMAS.build, obstr_index::Int, layer_index::Int, shape::BuildLayerShape; tight::Bool=false)
    layer = bd.layer[layer_index]
    obstr = bd.layer[obstr_index]
    # display("Layer $layer_index = $(layer.name)")
    # display("Obstr $obstr_index = $(obstr.name)")
    if layer.fs == Int(_out_)
        l_start = 0
        l_end = layer.end_radius
        o_start = 0
        o_end = obstr.end_radius
    else
        if obstr.fs in [Int(_lhfs_), Int(_out_)]
            o_start = obstr.start_radius
            o_end = obstr.end_radius
        else
            o_start = obstr.start_radius
            o_end = IMAS.get_build(bd, identifier=obstr.identifier, fs=_lfs_).end_radius
        end
        l_start = layer.start_radius
        l_end = IMAS.get_build(bd, identifier=layer.identifier, fs=_lfs_).end_radius
    end
    hfs_thickness = o_start - l_start
    lfs_thickness = l_end - o_end
    oR = obstr.outline.r
    oZ = obstr.outline.z
    if layer.fs == Int(_out_)
        target_minimum_distance = lfs_thickness
    else
        if tight
            target_minimum_distance = min(hfs_thickness, lfs_thickness)
        else
            target_minimum_distance = (hfs_thickness + lfs_thickness) / 2.0
        end
    end
    r_offset = (lfs_thickness .- hfs_thickness) / 2.0

    # update shape
    layer.shape = Int(shape)

    # handle offset, negative offset, offset & convex-hull
    if layer.shape in [Int(_offset_), Int(_convex_hull_)]
        poly = LibGEOS.buffer(xy_polygon(oR, oZ), (hfs_thickness + lfs_thickness) / 2.0)
        R = [v[1] .+ r_offset for v in LibGEOS.coordinates(poly)[1]]
        Z = [v[2] for v in LibGEOS.coordinates(poly)[1]]
        if layer.shape == Int(_convex_hull_)
            h = [[r, z] for (r, z) in collect(zip(R, Z))]
            hull = convex_hull(h)
            R = vcat([r for (r, z) in hull], hull[1][1])
            Z = vcat([z for (r, z) in hull], hull[1][2])
            R, Z = IMAS.resample_2d_line(R, Z)
        end
        layer.outline.r, layer.outline.z = R, Z

    else # handle shapes
        if layer.shape> 1000
            layer.shape = mod(layer.shape, 1000)
        end
        if layer.shape> 100
            layer.shape = mod(layer.shape, 100)
        end

        if layer.shape == Int(_silo_)
            is_up_down_symmetric = false
        elseif abs(sum(oZ) / sum(abs.(oZ))) < 1E-2
            is_up_down_symmetric = true
        else
            is_up_down_symmetric = false
        end

        is_negative_D = false
        if layer.shape != Int(_silo_)
            _, imaxr = findmax(oR)
            _, iminr = findmin(oR)
            _, imaxz = findmax(oZ)
            _, iminz = findmin(oZ)
            r_at_max_z, max_z = oR[imaxz], oZ[imaxz]
            r_at_min_z, min_z = oR[iminz], oZ[iminz]
            z_at_max_r, max_r = oZ[imaxr], oR[imaxr]
            z_at_min_r, min_r = oZ[iminr], oR[iminr]
            a = 0.5 * (max_r - min_r)
            R = 0.5 * (max_r + min_r)
            δu = (R - r_at_max_z) / a
            δl = (R - r_at_min_z) / a
            if δu+δl < 0
                is_negative_D = true
            end
        end

        if is_negative_D
            layer.shape = layer.shape + 1000
        end

        if !is_up_down_symmetric
            layer.shape = layer.shape + 100
        end

        func = shape_function(layer.shape)
        layer.shape_parameters = init_shape_parameters(layer.shape, oR, oZ, l_start, l_end, target_minimum_distance)

        layer.outline.r, layer.outline.z = func(l_start, l_end, layer.shape_parameters...)
        layer.shape_parameters = optimize_shape(oR, oZ, target_minimum_distance, func, l_start, l_end, layer.shape_parameters)
        layer.outline.r, layer.outline.z = func(l_start, l_end, layer.shape_parameters...; resample=false)
    end
    # display(plot!(layer.outline.r, layer.outline.z))
end

function assign_build_layers_materials(dd::IMAS.dd, ini::InitParameters)
    bd = dd.build
    for (k, layer) in enumerate(bd.layer)
        if k == 1 && ini.center_stack.plug
            layer.material = ini.material.wall
        elseif layer.type == Int(_plasma_)
            layer.material = any([layer.type in [Int(_blanket_), Int(_shield_)] for layer in dd.build.layer]) ? "DT_plasma" : "DD_plasma"
        elseif layer.type == Int(_gap_)
            layer.material = "Vacuum"
        elseif layer.type == Int(_oh_)
            layer.material = ini.oh.technology.material
            assign_coil_technology(dd, ini, :oh)
        elseif layer.type == Int(_tf_)
            layer.material = ini.tf.technology.material
            assign_coil_technology(dd, ini, :tf)
        elseif layer.type == Int(_shield_)
            layer.material = ini.material.shield
        elseif layer.type == Int(_blanket_)
            layer.material = ini.material.blanket
        elseif layer.type == Int(_wall_)
            layer.material = ini.material.wall
        elseif layer.type == Int(_vessel_)
            layer.material = "Water, Liquid"
        elseif layer.type == Int(_cryostat_)
            layer.material = ini.material.wall
        end
    end
end
