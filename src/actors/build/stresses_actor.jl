#= ============== =#
#  OH TF stresses  #
#= ============== =#
Base.@kwdef mutable struct FUSEparameters__ActorStresses{T} <: ParametersActor where {T<:Real}
    _parent::WeakRef = WeakRef(nothing)
    _name::Symbol = :not_set
    do_plot::Entry{Bool} = Entry{Bool}("-", "Plot"; default=false)
    n_points::Entry{Int} = Entry{Int}("-", "Number of grid points"; default=5)
end

mutable struct ActorStresses{D,P} <: ReactorAbstractActor
    dd::IMAS.dd{D}
    par::FUSEparameters__ActorStresses{P}
    function ActorStresses(dd::IMAS.dd{D}, par::FUSEparameters__ActorStresses{P}; kw...) where {D<:Real,P<:Real}
        logging_actor_init(ActorStresses)
        par = par(kw...)
        return new{D,P}(dd, par)
    end
end

"""
    ActorStresses(dd::IMAS.dd, act::ParametersAllActors; kw...)

Estimates mechanical stresses on the center stack

!!! note 
    Stores data in `dd.solid_mechanics`
"""
function ActorStresses(dd::IMAS.dd, act::ParametersAllActors; kw...)
    actor = ActorStresses(dd, act.ActorStresses; kw...)
    step(actor; par.n_points)
    finalize(actor)
    if actor.par.do_plot
        display(plot(actor.dd.solid_mechanics.center_stack.stress))
    end
    return actor
end

function _step(actor::ActorStresses; n_points::Integer=5)
    eq = actor.dd.equilibrium
    bd = actor.dd.build
    sm = actor.dd.solid_mechanics

    plasma = IMAS.get_build_layer(bd.layer, type=_plasma_)
    R0 = (plasma.end_radius + plasma.start_radius) / 2.0
    B0 = maximum(abs.(eq.vacuum_toroidal_field.b0))

    R_tf_in = IMAS.get_build_layer(bd.layer, type=_tf_, fs=_hfs_).start_radius
    R_tf_out = IMAS.get_build_layer(bd.layer, type=_tf_, fs=_hfs_).end_radius
    
    Bz_oh = bd.oh.max_b_field
    
    R_oh_in = IMAS.get_build_layer(bd.layer, type=_oh_).start_radius
    R_oh_out = IMAS.get_build_layer(bd.layer, type=_oh_).end_radius
    
    f_struct_tf = bd.tf.technology.fraction_steel
    f_struct_oh = bd.oh.technology.fraction_steel

    bucked = sm.center_stack.bucked == 1
    noslip = sm.center_stack.noslip == 1
    plug = sm.center_stack.plug == 1
    
    for oh_on in (true, false)
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
            n_points=n_points,
            empty_smcs=oh_on,
            verbose=false
        )
    end

    return actor
end

@recipe function plot_ActorStresses(actor::ActorStresses)
    @series begin
        actor.dd.solid_mechanics.center_stack.stress
    end
end