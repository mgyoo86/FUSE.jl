import FRESCO

#= =========== =#
#  ActorFRESCO  #
#= =========== =#
Base.@kwdef mutable struct FUSEparameters__ActorFRESCO{T<:Real} <: ParametersActor{T}
    _parent::WeakRef = WeakRef(nothing)
    _name::Symbol = :not_set
    _time::Float64 = NaN
    #== actor parameters ==#
    control::Switch{Symbol} = Switch{Symbol}([:vertical, :shape], "-", ""; default=:shape)
    number_of_iterations::Entry{Tuple{Int,Int}} = Entry{Tuple{Int,Int}}("-", "Number of outer and inner iterations"; default=(100, 3))
    relax::Entry{Float64} = Entry{Float64}("-", "Relaxation on the Picard iterations"; default=0.5)
    tolerance::Entry{Float64} = Entry{Float64}("-", "Tolerance for terminating iterations"; default=1e-4)
    #== data flow parameters ==#
    fixed_grid::Switch{Symbol} = Switch{Symbol}([:poloidal, :toroidal], "-", "Fix P and Jt on this rho grid"; default=:toroidal)
    #== display and debugging parameters ==#
    do_plot::Entry{Bool} = act_common_parameters(; do_plot=false)
    debug::Entry{Bool} = Entry{Bool}("-", "Print debug information withing FRESCO solve"; default=true)
    #== IMAS psi grid settings ==#
    nR::Entry{Int} = Entry{Int}("-", "Grid resolution along R"; default=129)
    nZ::Entry{Int} = Entry{Int}("-", "Grid resolution along Z"; default=129)
end

mutable struct ActorFRESCO{D,P} <: SingleAbstractActor{D,P}
    dd::IMAS.dd{D}
    par::FUSEparameters__ActorFRESCO{P}
    canvas::Union{Nothing,FRESCO.Canvas}
    profile::Union{Nothing,FRESCO.PressureJtoR}
end

"""
    ActorFRESCO(dd::IMAS.dd, act::ParametersAllActors; kw...)

Runs the Fixed boundary equilibrium solver FRESCO
"""
function ActorFRESCO(dd::IMAS.dd, act::ParametersAllActors; kw...)
    actor = ActorFRESCO(dd, act.ActorFRESCO; kw...)
    step(actor)
    finalize(actor)
    return actor
end

function ActorFRESCO(dd::IMAS.dd{D}, par::FUSEparameters__ActorFRESCO{P}; kw...) where {D<:Real,P<:Real}
    logging_actor_init(ActorFRESCO)
    par = par(kw...)
    return ActorFRESCO(dd, par, nothing, nothing)
end

"""
    _step(actor::ActorFRESCO)

Runs FRESCO on the r_z boundary, equilibrium pressure and equilibrium j_tor
"""
function _step(actor::ActorFRESCO)
    dd = actor.dd
    par = actor.par
    eqt = dd.equilibrium.time_slice[]
    eqt1d = eqt.profiles_1d

    actor.canvas = FRESCO.Canvas(dd, par.nR, par.nZ)

    pressure = IMAS.IMASdd.DataInterpolations.CubicSpline(eqt1d.pressure, eqt1d.psi_norm; extrapolate=true)
    JtoR = IMAS.IMASdd.DataInterpolations.CubicSpline(eqt1d.j_tor .* eqt1d.gm9, eqt1d.psi_norm; extrapolate=true)
    actor.profile = FRESCO.PressureJtoR(pressure, JtoR)

    FRESCO.solve!(actor.canvas, actor.profile, par.number_of_iterations...; par.relax, par.debug, par.control, par.tolerance)

    # display(plot(actor.canvas))

    return actor
end

# finalize by converting FRESCO canvas to dd.equilibrium
function _finalize(actor::ActorFRESCO)
    canvas = actor.canvas
    profile = actor.profile
    dd = actor.dd
    eq = dd.equilibrium
    eqt = eq.time_slice[]
    eqt1d = eqt.profiles_1d
    eq2d = resize!(eqt.profiles_2d, 1)[1]

    eqt.global_quantities.magnetic_axis.r = canvas.Raxis
    eqt.global_quantities.magnetic_axis.z = canvas.Zaxis
    eqt.global_quantities.psi_boundary = canvas.Ψbnd
    eqt.global_quantities.psi_axis = canvas.Ψaxis

    Npsi = length(eqt1d.psi)
    eqt1d.psi = range(canvas.Ψaxis, canvas.Ψbnd, Npsi)
    eqt1d.dpressure_dpsi = FRESCO.pprime.(Ref(canvas), Ref(profile), eqt1d.psi_norm)
    if length(canvas._gm1) == Npsi
        gm1 = canvas._gm1
    else
        psin = range(0.0, 1.0, length(canvas._gm1))
        gitp = DataInterpolations.CubicSpline(canvas._gm1, psin; extrapolate=false)
        gm1 = gitp.(eqt1d.psi_norm)
    end
    eqt1d.f_df_dpsi = FRESCO.ffprime.(Ref(canvas), Ref(profile), eqt1d.psi_norm, gm1)

    fend = eq.vacuum_toroidal_field.b0[end] * eq.vacuum_toroidal_field.r0
    f2 = 2 * IMAS.cumtrapz(eqt1d.psi, eqt1d.f_df_dpsi)
    f2 .= f2 .- f2[end] .+ fend^2
    eqt1d.f = sign(fend) .* sqrt.(f2)

    pend = eqt1d.pressure[end]
    eqt1d.pressure = IMAS.cumtrapz(eqt1d.psi, eqt1d.dpressure_dpsi)
    eqt1d.pressure .+= pend .- eqt1d.pressure[end]

    eq2d.grid_type.index = 1
    eq2d.grid.dim1 = collect(range(canvas.Rs[1], canvas.Rs[end], Npsi))
    eq2d.grid.dim2 = collect(range(canvas.Zs[1], canvas.Zs[end], Npsi))
    FRESCO.update_interpolation!(canvas)
    eq2d.psi = [canvas._Ψitp(r, z) for r in eq2d.grid.dim1, z in eq2d.grid.dim2]

    return actor
end
