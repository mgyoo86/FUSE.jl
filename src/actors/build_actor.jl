#= ========== =#
#  flux-swing #
#= ========== =#

mutable struct FluxSwingActor <: AbstractActor
    dd::IMAS.dd
    flattop_duration::Real
end

function FluxSwingActor(dd::IMAS.dd, act::ActorParameters)
    actor = FluxSwingActor(dd, act.oh.flattop_duration)
    step(actor)
    finalize(actor)
    return actor
end

function step(flxactor::FluxSwingActor)
    bd = flxactor.dd.build
    eq = flxactor.dd.equilibrium
    eqt = eq.time_slice[]
    cp = flxactor.dd.core_profiles
    cp1d = cp.profiles_1d[]

    bd.flux_swing_requirements.rampup = rampup_flux_requirements(eqt, cp)
    bd.flux_swing_requirements.flattop = flattop_flux_requirements(eqt, cp1d, flxactor.flattop_duration)
    bd.flux_swing_requirements.pf = pf_flux_requirements(eqt)

    oh_peakJ(bd)
    tf_peakJ(bd, eq)

    return flxactor
end

"""
    rampup_flux_requirements(eqt::IMAS.equilibrium__time_slice, cp::IMAS.core_profiles)

Estimate OH flux requirement during rampup

NOTES:
* Equations from GASC (Stambaugh FST 2011)
* eqt is supposed to be the equilibrium right at the end of the rampup phase, beginning of flattop
* core_profiles is only used to get core_profiles.global_quantities.ejima
"""
function rampup_flux_requirements(eqt::IMAS.equilibrium__time_slice, cp::IMAS.core_profiles)

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
    flattop_flux_requirements(eqt::IMAS.equilibrium__time_slice, cp1d::IMAS.core_profiles__profiles_1d, flattop_duration::Real)

Estimate OH flux requirement during flattop (if j_ohmic profile is missing then steady state ohmic profile is assumed)
"""
function flattop_flux_requirements(eqt::IMAS.equilibrium__time_slice, cp1d::IMAS.core_profiles__profiles_1d, flattop_duration::Real)
    if ismissing(cp1d, :j_ohmic)
        j_ohmic = IMAS.j_ohmic_steady_state(eqt, cp1d)
    else
        j_ohmic = cp1d.j_ohmic
    end
    return integrate(cp1d.grid.area, j_ohmic ./ cp1d.conductivity_parallel .* flattop_duration) # V*s
end

"""
    pf_flux_requirements(eqt::IMAS.equilibrium__time_slice)

Estimate vertical field from PF coils and its contribution to flux swing

NOTES:
* Equations from GASC (Stambaugh FST 2011)
* eqt is supposed to be the equilibrium right at the end of the rampup phase, beginning of flattop
"""
function pf_flux_requirements(eqt::IMAS.equilibrium__time_slice)
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

"""
    oh_peakJ(bd::IMAS.build, double_swing::Bool=true)

Evaluate OH current density and B_field required for rampup and flattop

NOTES:
* Equations from GASC (Stambaugh FST 2011)
* Also relevant: `Engineering design solutions of flux swing with structural requirements for ohmic heating solenoids` Smith, R. A. September 30, 1977
"""
function oh_peakJ(bd::IMAS.build, double_swing::Bool=true)
    innerSolenoidRadius = IMAS.get_build(bd, type=_oh_).start_radius
    outerSolenoidRadius = IMAS.get_build(bd, type=_oh_).end_radius
    totalOhFluxReq = bd.flux_swing_requirements.rampup + bd.flux_swing_requirements.flattop + bd.flux_swing_requirements.pf

    # Calculate magnetic field at solenoid bore required to match flux swing request
    RiRoFactor = innerSolenoidRadius / outerSolenoidRadius
    magneticFieldSolenoidBore = 3.0 * totalOhFluxReq / pi / outerSolenoidRadius^2 / (RiRoFactor^2 + RiRoFactor + 1.0) / (double_swing ? 2 : 1)
    currentDensityOH = magneticFieldSolenoidBore / (0.4 * pi * outerSolenoidRadius * (1 - innerSolenoidRadius / outerSolenoidRadius))

    # minimum requirements for OH
    bd.oh.max_b_field = magneticFieldSolenoidBore
    bd.oh.max_j = currentDensityOH * 1E6
    bd.oh.critical_j = coil_Jcrit(bd.oh.max_b_field, bd.oh.technology)
end

"""
    tf_peakJ(bd::IMAS.build)

Evaluate TF current density given a B_field
"""
function tf_peakJ(bd::IMAS.build, eq::IMAS.equilibrium)
    hfsTF = IMAS.get_build(bd, type=_tf_, fs=_hfs_)
    B0 = abs(maximum(eq.vacuum_toroidal_field.b0))
    R0 = eq.vacuum_toroidal_field.r0

    # current in the TF coils
    current_TF = B0 * R0 * 2pi / constants.μ_0 / bd.tf.coils_n
    TF_cx_area = hfsTF.thickness * bd.tf.wedge_thickness

    bd.tf.max_b_field = B0 * R0 / hfsTF.end_radius
    bd.tf.max_j = current_TF / TF_cx_area
    bd.tf.critical_j = coil_Jcrit(bd.tf.max_b_field, bd.tf.technology)
end

#= ======== =#
#  stresses  #
#= ======== =#
mutable struct StressesActor <: AbstractActor
    dd::IMAS.dd
    bucked::Bool
    noslip::Bool
    plug::Bool
end

function StressesActor(dd::IMAS.dd, act::ActorParameters)
    actor = StressesActor(dd, act.center_stack.bucked, act.center_stack.noslip, act.center_stack.plug)
    step(actor)
    finalize(actor)
    return actor
end

function step(stressactor::StressesActor)
    eq = stressactor.dd.equilibrium
    bd = stressactor.dd.build

    R0 = eq.vacuum_toroidal_field.r0
    B0 = maximum(eq.vacuum_toroidal_field.b0)
    R_tf_in = IMAS.get_build(bd, type=_tf_, fs=_hfs_).start_radius
    R_tf_out = IMAS.get_build(bd, type=_tf_, fs=_hfs_).end_radius
    Bz_oh = bd.oh.max_b_field
    R_oh_in = IMAS.get_build(bd, type=_oh_).start_radius
    R_oh_out = IMAS.get_build(bd, type=_oh_).end_radius
    f_struct_tf = bd.tf.technology.fraction_stainless
    f_struct_oh = bd.oh.technology.fraction_stainless

    smcs = empty!(stressactor.dd.solid_mechanics.center_stack)

    for oh_on in [true, false]
        solve_1D_solid_mechanics!(
            smcs,
            R0,
            B0,
            R_tf_in,
            R_tf_out,
            oh_on ? Bz_oh : 0.0,
            R_oh_in,
            R_oh_out;
            bucked=stressactor.bucked,
            noslip=stressactor.noslip,
            plug=stressactor.plug,
            f_struct_tf=f_struct_tf,
            f_struct_oh=f_struct_oh,
            f_struct_pl=1.0,
            n_points=5,
            verbose=false
        )
    end

end

@recipe function plot_StressesActor(sactor::StressesActor)
    @series begin
        sactor.dd.solid_mechanics.center_stack.stress
    end
end

#= ====== =#
#  sizing  #
#= ====== =#

mutable struct OHTFsizingActor <: AbstractActor
    stresses_actor::StressesActor
    fluxswing_actor::FluxSwingActor
end

function OHTFsizingActor(dd::IMAS.dd, act::ActorParameters; kw...)
    fluxswing_actor = FluxSwingActor(dd, act)
    stresses_actor = StressesActor(dd, act)
    actor = OHTFsizingActor(stresses_actor, fluxswing_actor)
    step(actor; kw...)
    finalize(actor)
    return actor
end

function step(actor::OHTFsizingActor; verbose=false, j_tolerance=0.4, stress_tolerance=0.2)

    function cost(x0)
        plug.thickness, OH.thickness, TFhfs.thickness = map(abs, x0)
        TFlfs.thickness = TFhfs.thickness

        step(actor.fluxswing_actor)
        step(actor.stresses_actor)

        # ratios to evenly split the cost among different objectives
        jtf2joh_ratio = dd.build.tf.critical_j / dd.build.oh.critical_j
        stress2j_ratio = (dd.build.tf.critical_j + dd.build.oh.critical_j) / 2.0 / stainless_steel.yield_strength

        c = ((1 - (1 + j_tolerance) * dd.build.oh.max_j / dd.build.oh.critical_j) * jtf2joh_ratio)^2
        c += ((1 - (1 + stress_tolerance) * maximum(dd.solid_mechanics.center_stack.stress.vonmises.oh / stainless_steel.yield_strength)) * stress2j_ratio)^2
        c += (1 - (1 + j_tolerance) * dd.build.tf.max_j / dd.build.tf.critical_j)^2
        c += ((1 - (1 + stress_tolerance) * maximum(dd.solid_mechanics.center_stack.stress.vonmises.tf) / stainless_steel.yield_strength) * stress2j_ratio)^2
        if !ismissing(dd.solid_mechanics.center_stack.stress.vonmises, :pl)
            c += ((1 - (1 + stress_tolerance) * maximum(dd.solid_mechanics.center_stack.stress.vonmises.pl) / stainless_steel.yield_strength) * stress2j_ratio)^2
        end
        return sqrt(c)
    end

    @assert actor.stresses_actor.dd === actor.fluxswing_actor.dd
    dd = actor.stresses_actor.dd

    plug = dd.build.layer[1]
    OH = IMAS.get_build(dd.build, type=_oh_)
    TFhfs = IMAS.get_build(dd.build, type=_tf_, fs=_hfs_)
    TFlfs = IMAS.get_build(dd.build, type=_tf_, fs=_lfs_)

    res = Optim.optimize(cost, [plug.thickness, OH.thickness, TFhfs.thickness], Optim.NelderMead(), Optim.Options(time_limit=60, iterations=1000, g_tol=1E-6); autodiff=:forward)
    plug.thickness, OH.thickness, TFhfs.thickness = map(abs, res.minimizer)
    TFlfs.thickness = TFhfs.thickness
    step(actor.fluxswing_actor)
    step(actor.stresses_actor)

    if verbose
        display(res)
        @show dd.build.oh.max_j
        @show dd.build.oh.critical_j
        @show dd.build.tf.max_j
        @show dd.build.tf.critical_j
        @show maximum(dd.solid_mechanics.center_stack.stress.vonmises.oh)
        @show stainless_steel.yield_strength
        @show maximum(dd.solid_mechanics.center_stack.stress.vonmises.tf)
        @show stainless_steel.yield_strength
    end

    return actor
end

#= ============= =#
#  cross-section  #
#= ============= =#

mutable struct CXbuildActor <: AbstractActor
    dd::IMAS.dd
    tf_shape::IMAS.BuildLayerShape
end

function CXbuildActor(dd::IMAS.dd, tf_shape::Symbol)
    CXbuildActor(dd, to_enum(tf_shape))
end

function CXbuildActor(dd::IMAS.dd, act::ActorParameters; rebuild_wall=(act.general.init_from != :ods), kw...)
    if rebuild_wall # regenerate build based on new equilibrium
        empty!(dd.wall)
    end
    actor = CXbuildActor(dd, act.tf.shape)
    step(actor; kw...)
    finalize(actor)
    return actor
end

function step(cx_actor::CXbuildActor)
    build_cx(cx_actor.dd, cx_actor.tf_shape)
end