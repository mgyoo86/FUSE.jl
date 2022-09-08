import EPEDNN

#= ============= =#
#  ActorPedestal  #
#= ============= =#
mutable struct ActorPedestal <: PlasmaAbstractActor
    dd::IMAS.dd
    par::ParametersActor
    epedmod::EPEDNN.EPEDmodel
    inputs::EPEDNN.InputEPED
    wped::Union{Missing,Real}
    pped::Union{Missing,Real}
end

function ParametersActor(::Type{Val{:ActorPedestal}})
    par = ParametersActor(nothing)
    par.blend_core_pedestal = Entry(Bool, "", "Blends the core and pedestal at the finalize step using default settings for the blender (rho_bound=0.8)"; default=true)
    par.temp_pedestal_ratio = Entry(Real, "", "Ratio of ion to electron temperatures"; default=1.0)
    par.eped_factor = Entry(Real, "", "Pedestal height multiplier (affects width by the squareroot)"; default=1.0)
    par.warn_nn_train_bounds = Entry(Bool, "", "Raise warnings if querying cases that are certainly outside of the training range"; default=false)
    par.only_powerlaw = Entry(Bool, "", "Use power-law pedestal fit (without NN correction)"; default=false)
    return par
end

"""
    ActorPedestal(dd::IMAS.dd, act::ParametersAllActors; kw...)

The ActorPedestal evaluates the pedestal boundary condition (height and width)
"""
function ActorPedestal(dd::IMAS.dd, act::ParametersAllActors; kw...)
    par = act.ActorPedestal(kw...)
    actor = ActorPedestal(dd, par)
    step(actor)
    finalize(actor)
    return actor
end

function ActorPedestal(dd::IMAS.dd, par::ParametersActor; kw...)
    par = par(kw...)

    epedmod = EPEDNN.loadmodelonce("EPED1NNmodel.bson")

    eq = dd.equilibrium
    eqt = eq.time_slice[]

    m = [ion.element[1].a for ion in dd.core_profiles.profiles_1d[].ion if Int(floor(ion.element[1].z_n)) == 1]
    m = sum(m) / length(m)
    if m < 2
        m = 2
    elseif m > 2
        m = 2.5
    end

    neped = @ddtime dd.summary.local.pedestal.n_e.value
    zeffped = @ddtime dd.summary.local.pedestal.zeff.value
    Bt = abs(@ddtime(eq.vacuum_toroidal_field.b0)) * eq.vacuum_toroidal_field.r0 / eqt.boundary.geometric_axis.r
    βn = @ddtime(dd.summary.global_quantities.beta_tor_thermal_norm.value)

    inputs = EPEDNN.InputEPED(
        eqt.boundary.minor_radius,
        βn,
        Bt,
        eqt.boundary.triangularity,
        abs(eqt.global_quantities.ip / 1e6),
        eqt.boundary.elongation,
        m,
        neped / 1e19,
        eqt.boundary.geometric_axis.r,
        zeffped)

    return ActorPedestal(dd, par, epedmod, inputs, missing, missing)
end

"""
    step(actor::ActorPedestal;
        warn_nn_train_bounds::Bool=actor.par.warn_nn_train_bounds,
        only_powerlaw::Bool=false)

Runs pedestal actor to evaluate pedestal width and height
"""
function step(actor::ActorPedestal;
    warn_nn_train_bounds::Bool=actor.par.warn_nn_train_bounds,
    only_powerlaw::Bool=false)

    sol = actor.epedmod(actor.inputs; only_powerlaw, warn_nn_train_bounds)

    actor.wped = sol.width.GH.H
    actor.pped = sol.pressure.GH.H

    return actor
end

"""
    finalize(actor::ActorPedestal;
        temp_pedestal_ratio::Real=actor.par.temp_pedestal_ratio,
        eped_factor::Real=actor.par.eped_factor,
        blend_core_pedestal::Bool=actor.par.blend_core_pedestal))

Writes results to dd.summary.local.pedestal and blends the pedestal if blend_core_pedestal == true
"""
function finalize(actor::ActorPedestal;
    temp_pedestal_ratio::Real=actor.par.temp_pedestal_ratio,
    eped_factor::Real=actor.par.eped_factor,
    blend_core_pedestal::Bool=actor.par.blend_core_pedestal)

    dd = actor.dd
    dd_ped = dd.summary.local.pedestal

    impurity = [ion.element[1].z_n for ion in dd.core_profiles.profiles_1d[].ion if Int(floor(ion.element[1].z_n)) != 1][1]
    zi = sum(impurity) / length(impurity)

    nival = actor.inputs.neped * 1e19 * (actor.inputs.zeffped - 1) / (zi^2 - zi)
    nval = actor.inputs.neped * 1e19 - zi * nival
    nsum = actor.inputs.neped * 1e19 + nval + nival
    tped = (actor.pped * 1e6) / nsum / constants.e
    
    @ddtime dd_ped.t_e.value = 2.0 * tped / (1.0 + temp_pedestal_ratio) * eped_factor
    @ddtime dd_ped.t_i_average.value = @ddtime(dd_ped.t_e.value) * temp_pedestal_ratio
    @ddtime dd_ped.position.rho_tor_norm = 1 - actor.wped * sqrt(eped_factor)

    if blend_core_pedestal
        IMAS.blend_core_pedestal_Hmode(dd)
    end
end
