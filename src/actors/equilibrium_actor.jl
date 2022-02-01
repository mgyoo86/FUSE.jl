using Equilibrium
using Printf
import ForwardDiff
import Optim

#= ==================== =#
#  init equilibrium IDS  #
#= ==================== =#

"""
    init(eqt::IMAS.equilibrium__time_slice; B0::Real, R0::Real, ϵ::Real, δ::Real, κ::Real, beta_n::Real, ip::Real, x_point::Union{Vector, NTuple{2}, Bool}=false)

Initialize equilibrium IDS based on some basic Miller geometry parameters
"""
function init(eq::IMAS.equilibrium;
              B0::Real, R0::Real, ϵ::Real, δ::Real, κ::Real, beta_n::Real, ip::Real,
              x_point::Union{Vector,NTuple{2},Bool}=false)
    eqt = eq.time_slice[]
    empty!(eqt)
    eqt.boundary.minor_radius = ϵ * R0
    eqt.boundary.geometric_axis.r = R0
    eqt.boundary.elongation = κ
    eqt.boundary.triangularity = δ
    eqt.profiles_1d.psi = [1.0]
    eqt.profiles_1d.f = [B0 * R0]
    eqt.global_quantities.ip = ip
    eqt.global_quantities.beta_normal = beta_n
    if x_point === true
        x_point = (R0 * (1 - 1.1 * δ * ϵ), -R0 * 1.1 * κ * ϵ)
    end
    if isa(x_point, Union{Vector,Tuple})
        resize!(eqt.boundary.x_point, 1)
        eqt.boundary.x_point[1].r = x_point[1]
        eqt.boundary.x_point[1].z = x_point[2]
    end
    @ddtime eq.vacuum_toroidal_field.b0 = B0
    return eqt
end

"""
    field_null_surface(eqt, scale = 0.25, abs_psi_boundary = 0.1)

Return field null surface by scaling an existing equilibrium time_slice
"""
function field_null_surface(eqt::IMAS.equilibrium__time_slice, scale::Real = 0.25, abs_psi_boundary::Real = 0.1)
    eqb = IMAS.equilibrium__time_slice()
    eqb.global_quantities.psi_boundary = sign(eqt.profiles_1d.psi[1] - eqt.profiles_1d.psi[end]) * abs_psi_boundary
    eqb.boundary.outline.r, eqb.boundary.outline.z, _ = IMAS.flux_surface(eqt, eqt.profiles_1d.psi[1] * (1 - scale) + eqt.profiles_1d.psi[end] * scale)
    eqb.boundary.outline.r .-= minimum(eqb.boundary.outline.r) .- minimum(IMAS.flux_surface(eqt, eqt.profiles_1d.psi[end])[1])
    eqb.profiles_1d.psi = [eqb.global_quantities.psi_boundary]
    eqb.profiles_1d.f = [eqt.profiles_1d.f[end]]
    return eqb
end

#= ======================= =#
#  SolovevEquilibriumActor  #
#= ======================= =#
mutable struct SolovevEquilibriumActor <: AbstractActor
    eqt::IMAS.equilibrium__time_slice
    S::SolovevEquilibrium
end

function SolovevEquilibriumActor(dd::IMAS.dd; kw...)
    return SolovevEquilibriumActor(dd.equilibrium.time_slice[]; kw...)
end

"""
    function SolovevEquilibriumActor(eqt::IMAS.equilibrium__time_slice, qstar=1.5, alpha=0.0, symmetric=true)

Constructor for the SolovevEquilibriumActor structure
“One size fits all” analytic solutions to the Grad–Shafranov equation
Phys. Plasmas 17, 032502 (2010); https://doi.org/10.1063/1.3328818

- qstar: Kink safety factor

- alpha: Constant affecting the pressure
"""
function SolovevEquilibriumActor(eqt::IMAS.equilibrium__time_slice;
                                 qstar=1.5,
                                 alpha=0.0,
                                 symmetric=true) # symmetric should really be passed/detected through IMAS

    a = eqt.boundary.minor_radius
    R0 = eqt.boundary.geometric_axis.r
    κ = eqt.boundary.elongation
    δ = eqt.boundary.triangularity
    ϵ = a / R0
    B0 = abs(eqt.profiles_1d.f[end] / R0)

    if length(eqt.boundary.x_point) > 0
        xpoint = (eqt.boundary.x_point[1].r, eqt.boundary.x_point[1].z)
    else
        xpoint = nothing
    end

    S0 = solovev(B0, R0, ϵ, δ, κ, alpha, qstar, B0_dir=1, Ip_dir=1, symmetric=symmetric, xpoint=xpoint)

    SolovevEquilibriumActor(eqt, S0)
end

"""
    IMAS2Equilibrium(eqt::IMAS.equilibrium__time_slice)

Convert IMAS.equilibrium__time_slice to Equilibrium.jl EFIT structure
"""
function IMAS2Equilibrium(eqt::IMAS.equilibrium__time_slice)
    dim1 = range(eqt.profiles_2d[1].grid.dim1[1], eqt.profiles_2d[1].grid.dim1[end], length=length(eqt.profiles_2d[1].grid.dim1))
    @assert collect(dim1) ≈ eqt.profiles_2d[1].grid.dim1
    dim2 = range(eqt.profiles_2d[1].grid.dim2[1], eqt.profiles_2d[1].grid.dim2[end], length=length(eqt.profiles_2d[1].grid.dim2))
    @assert collect(dim2) ≈ eqt.profiles_2d[1].grid.dim2
    psi = range(eqt.profiles_1d.psi[1], eqt.profiles_1d.psi[end], length=length(eqt.profiles_1d.psi))
    @assert collect(psi) ≈ eqt.profiles_1d.psi

    Equilibrium.efit(   Equilibrium.cocos(11), # COCOS
                        dim1, # Radius/R range
                        dim2, # Elevation/Z range
                        psi, # Polodial Flux range (polodial flux from magnetic axis)
                        eqt.profiles_2d[1].psi, # Polodial Flux on RZ grid (polodial flux from magnetic axis)
                        eqt.profiles_1d.f, # Polodial Current
                        eqt.profiles_1d.pressure, # Plasma pressure
                        eqt.profiles_1d.q, # Q profile
                        eqt.profiles_1d.psi .* 0, # Electric Potential
                        (eqt.global_quantities.magnetic_axis.r, eqt.global_quantities.magnetic_axis.z), # Magnetic Axis (raxis,zaxis)
                        Int(sign(eqt.profiles_1d.f[end]) * sign(eqt.global_quantities.ip)) # sign(dot(J,B))
                    )
end

"""
    step(actor::SolovevEquilibriumActor; verbose=false)

Non-linear optimization to obtain a target `ip` and `beta_normal`
"""
function step(actor::SolovevEquilibriumActor; verbose=false)
    S0 = actor.S

    target_ip = abs(actor.eqt.global_quantities.ip)
    target_beta = actor.eqt.global_quantities.beta_normal

    B0, R0, epsilon, delta, kappa, alpha, qstar, target_ip, target_beta = promote(S0.B0, S0.R0, S0.epsilon, S0.delta, S0.kappa, S0.alpha, S0.qstar, target_ip, target_beta)

    function cost(x)
        # NOTE: Ip/Beta calculation is very much off in Equilibrium.jl for diverted plasmas because boundary calculation is wrong
        S = solovev(B0, R0, epsilon, delta, kappa, x[1], x[2], B0_dir=1, Ip_dir=1, symmetric=true, xpoint=nothing)
        beta_cost = (Equilibrium.beta_n(S) - target_beta) / target_beta
        ip_cost = (Equilibrium.plasma_current(S) - target_ip) / target_ip
        c = sqrt(beta_cost^2 + ip_cost^2)
        return c
    end

    res = Optim.optimize(cost, [alpha, qstar], Optim.NelderMead(), Optim.Options(g_tol=1E-3))
    
    if verbose
        println(res)
    end

    actor.S = solovev(B0, R0, epsilon, delta, kappa, res.minimizer[1], res.minimizer[2], B0_dir=1, Ip_dir=1, symmetric=S0.symmetric, xpoint=S0.xpoint)

    # @show Equilibrium.beta_t(actor.S)
    # @show Equilibrium.beta_p(actor.S)
    # @show Equilibrium.beta_n(actor.S)
    # @show Equilibrium.plasma_current(actor.S)

    return res
end

"""
    finalize(actor::SolovevEquilibriumActor,
             resolution::Int=129,
             rlims::NTuple{2,<:Real}=Equilibrium.limits(actor.S)[1],
             zlims::NTuple{2,<:Real}=Equilibrium.limits(actor.S)[2])::IMAS.equilibrium__time_slice

Store SolovevEquilibriumActor data in IMAS.equilibrium format
"""
function finalize(actor::SolovevEquilibriumActor,
                  resolution::Int=129,
                  rlims::NTuple{2,<:Real}=Equilibrium.limits(actor.S)[1],
                  zlims::NTuple{2,<:Real}=Equilibrium.limits(actor.S)[2])::IMAS.equilibrium__time_slice

    tc = transform_cocos(3, 11)

    eqt = actor.eqt
    sign_Ip = sign(eqt.global_quantities.ip)
    sign_Bt = sign(eqt.profiles_1d.f[end])

    empty!(eqt)
    eqt.boundary.geometric_axis.r = actor.S.R0
    eqt.profiles_1d.psi = collect(range(Equilibrium.psi_limits(actor.S)..., length=resolution)) * (tc["PSI"] * sign_Ip)

    eqt.profiles_1d.pressure = Equilibrium.pressure(actor.S, eqt.profiles_1d.psi)
    eqt.profiles_1d.dpressure_dpsi = Equilibrium.pressure_gradient(actor.S, eqt.profiles_1d.psi) / (tc["PSI"] * sign_Ip)

    eqt.profiles_1d.f = Equilibrium.poloidal_current(actor.S, eqt.profiles_1d.psi) * (tc["F"] * sign_Bt)
    eqt.profiles_1d.f_df_dpsi = eqt.profiles_1d.f .* Equilibrium.poloidal_current_gradient(actor.S, eqt.profiles_1d.psi) * (tc["F"] * sign_Bt) / (tc["PSI"] * sign_Ip)

    eqt.global_quantities.magnetic_axis.r, eqt.global_quantities.magnetic_axis.z = Equilibrium.magnetic_axis(actor.S)

    resize!(eqt.profiles_2d, 1)
    eqt.profiles_2d[1].grid_type.index = 1
    eqt.profiles_2d[1].grid.dim1 = range(rlims[1], rlims[2], length=resolution)
    eqt.profiles_2d[1].grid.dim2 = range(zlims[1], zlims[2], length=Int(ceil(resolution * actor.S.kappa)))

    eqt.profiles_2d[1].psi = [actor.S(rr, zz) for rr in eqt.profiles_2d[1].grid.dim1, zz in eqt.profiles_2d[1].grid.dim2] * (tc["PSI"] * sign_Ip)

    IMAS.flux_surfaces(eqt)

    return eqt
end