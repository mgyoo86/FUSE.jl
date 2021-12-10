@Base.kwdef mutable struct PFcoilsOptTrace
    λ_regularize::Vector = []
    cost_ψ::Vector = []
    cost_currents::Vector = []
    cost_bound::Vector = []
    cost_spacing::Vector = []
    cost_total::Vector = []
end

mutable struct PFcoilsOptActor <: AbstractActor
    eq_in::IMAS.equilibrium
    eq_out::IMAS.equilibrium
    time::Real
    pf_active::IMAS.pf_active
    radial_build::IMAS.radial_build
    symmetric::Bool
    λ_regularize::Real
    trace::PFcoilsOptTrace
end

#= == =#
# INIT #
#= == =#
using Equilibrium
using PolygonOps
using StaticArrays
using DSP
using Random
using Interpolations
using Optim
using AD_GS
using LinearAlgebra
using Statistics
using Plots
import Contour

const coils_turns_spacing = 0.05

#= ================== =#
#  init pf_active IDS  #
#= ================== =#


function finite_size_OH_coils(z, clereance)
    ez = diff(z) / 2.0 .+ z[1:end-1]
    ez = vcat((ez[1] - ez[2]) + ez[1], ez, (ez[end] - ez[end-1]) + ez[end])
    ez = (ez .- minimum(ez)) ./ (maximum(ez) - minimum(ez)) * (maximum(z) - minimum(z)) .+ minimum(z)
    ez_centers = diff(ez) / 2.0 .+ ez[1:end-1]
    ez_centers = [abs(z)<1E-6 ? 0 : z for z in ez_centers] # correct small deviations near zero
    ez_heights = diff(ez) .- clereance
    return ez_centers, ez_heights
end

"""
    init(pf_active::IMAS.pf_active, rb::IMAS.radial_build, ncoils_OH::Int, n_pf_coils_per_gap_region::Vector)

Use radial build layers outline to initialize PF coils distribution
"""
function init(pf_active::IMAS.pf_active, rb::IMAS.radial_build, ncoils_OH::Int, n_pf_coils_per_gap_region::Vector)

    resolution = 257
    rmask, zmask, mask = IMAS.structures_mask(rb, resolution=resolution)

    resize!(rb.pf_coils_rail, length(n_pf_coils_per_gap_region) + 1)

    # OH coils are distributed on a rail within the OH region
    OH_layer = IMAS.get_radial_build(rb, type=1)
    r_ohcoils = ones(ncoils_OH) .* (sum(extrema(OH_layer.outline.r)) / 2.)
    w = maximum(OH_layer.outline.r) - minimum(OH_layer.outline.r)
    z_ohcoils = collect(range(minimum(OH_layer.outline.z), maximum(OH_layer.outline.z), length=ncoils_OH))
    z_ohcoils, h_ohcoils = finite_size_OH_coils(z_ohcoils, w / 2.0)
    rb.pf_coils_rail[1].name = "OH"
    rb.pf_coils_rail[1].coils_number = ncoils_OH
    rb.pf_coils_rail[1].outline.r = r_ohcoils
    rb.pf_coils_rail[1].outline.z = z_ohcoils
    rb.pf_coils_rail[1].outline.distance = range(-1, 1, length=ncoils_OH)
    for (r, z, h) in zip(r_ohcoils, z_ohcoils, h_ohcoils)
        k = length(pf_active.coil) + 1
        resize!(pf_active.coil, k)
        resize!(pf_active.coil[k].element, 1)
        pf_active.coil[k].identifier = "optim"
        pf_active.coil[k].name = "OH"
        pf_active.coil[k].element[1].geometry.rectangle.r = r
        pf_active.coil[k].element[1].geometry.rectangle.z = z
        pf_active.coil[k].element[1].geometry.rectangle.width = w
        pf_active.coil[k].element[1].geometry.rectangle.height = h
        # pf_active.coil[k].element[1].turns_with_sign = 1
        set_turns_from_spacing!(pf_active.coil[k], coils_turns_spacing, +1)
        set_field_time_array(pf_active.coil[k].current, :time, 1, 0.0)
        set_field_time_array(pf_active.coil[k].current, :data, 1, 0.0)
    end

    # Now add actual PF coils to regions of vacuum
    krail = 0
    for (k, layer) in enumerate(rb.layer)
        if (layer.hfs == 1 || k == length(rb.layer)) && ! is_missing(layer.outline, :r)
            if ! is_missing(layer, :material) && layer.material == "vacuum"

                krail += 1
                if isa(n_pf_coils_per_gap_region[krail], Int)
                    ncoils = n_pf_coils_per_gap_region[krail]
                else
                    ncoils = length(n_pf_coils_per_gap_region[krail])
                end

                # add rail info to radial_build IDS
                rb.pf_coils_rail[1 + krail].name = replace(replace(layer.name, "hfs " => ""), "lfs " => "")
                rb.pf_coils_rail[1 + krail].coils_number = ncoils

                if ncoils == 0
                    rb.pf_coils_rail[1 + krail].outline.r = Float64[]
                    rb.pf_coils_rail[1 + krail].outline.z = Float64[]
                    rb.pf_coils_rail[1 + krail].outline.distance = Float64[]
                    continue
                end

                # pick layers with outline information
                if layer.hfs == 1
                    outer_layer = IMAS.get_radial_build(rb, identifier=rb.layer[k].identifier, hfs=1)
                    inner_layer = IMAS.get_radial_build(rb, identifier=rb.layer[k + 1].identifier, hfs=[1,0])
                else
                    inner_layer = IMAS.get_radial_build(rb, identifier=rb.layer[k - 1].identifier, hfs=1)
                    outer_layer = IMAS.get_radial_build(rb, identifier=rb.layer[k].identifier, hfs=[1,0])
                end

                # take two outlines and interpolate them on the same θ
                # inner_r, inner_z, outer_r, outer_z, θ = two_curves_same_θ(inner_layer.outline.r, inner_layer.outline.z, outer_layer.outline.r, outer_layer.outline.z)

                buff = 0.5
                buff *= krail                

                clerance = buff/(rmask[2] - rmask[1])/2
                clerance = Int(ceil(clerance))

                # generate rail between the two layers where coils will be placed and will be able to slide during the `optimization` phase
                poly = LibGEOS.buffer(xy_polygon(inner_layer.outline.r, inner_layer.outline.z), buff)
                mid_r = [v[1] for v in LibGEOS.coordinates(poly)[1]]
                mid_z = [v[2] for v in LibGEOS.coordinates(poly)[1]]

                # mark what regions on that rail do not intersect solid structures and can hold coils
                valid_k = []
                for (k, (r, z)) in enumerate(zip(mid_r, mid_z))
                    ir = argmin(abs.(rmask .- r))
                    iz = argmin(abs.(zmask .- z))
                    if (ir - clerance) < 1 || (ir + clerance) > length(rmask) || (iz - clerance) < 1 || (iz + clerance) > length(zmask)
                        continue
                    end
                    if all(mask[(-clerance:clerance) .+ ir,(-clerance:clerance) .+ iz] .== 0)
                        push!(valid_k, k)
                    end
                end
                istart = argmax(diff(valid_k))
                valid_r = fill(NaN, size(mid_r)...)
                valid_z = fill(NaN, size(mid_z)...)
                valid_r[valid_k] = mid_r[valid_k]
                valid_z[valid_k] = mid_z[valid_k]
                valid_r = vcat(valid_r[istart + 1:end], valid_r[1:istart])
                valid_z = vcat(valid_z[istart + 1:end], valid_z[1:istart])

                if isa(n_pf_coils_per_gap_region[krail], Int)
                    coils_distance = range(-(1-1/ncoils),1-1/ncoils,length=ncoils)
                else
                    coils_distance = n_pf_coils_per_gap_region[krail]
                end

                # evaluate distance along rail
                d_distance = sqrt.(diff(vcat(valid_r, valid_r[1])).^2.0 .+ diff(vcat(valid_z, valid_z[1])).^2.0)
                d_distance[isnan.(d_distance)] .= 0.0
                distance = cumsum(d_distance)
                valid_z = valid_z[d_distance .!= 0]
                valid_r = valid_r[d_distance .!= 0]
                distance = distance[d_distance .!= 0]
                distance = (distance .- distance[1])
                distance = (distance ./ distance[end]).*2.0.-1.0

                # add rail info to radial_build IDS
                rb.pf_coils_rail[1 + krail].outline.r = valid_r
                rb.pf_coils_rail[1 + krail].outline.z = valid_z
                rb.pf_coils_rail[1 + krail].outline.distance = distance

                # uniformely distribute coils
                r_coils = IMAS.interp(distance, valid_r)(coils_distance)
                z_coils = IMAS.interp(distance, valid_z)(coils_distance)
                z_coils = [abs(z)<1E-6 ? 0 : z for z in z_coils]

                # populate IMAS data structure
                for (r, z) in zip(r_coils, z_coils)
                    k = length(pf_active.coil) + 1
                    resize!(pf_active.coil, k)
                    resize!(pf_active.coil[k].element, 1)
                    pf_active.coil[k].identifier = "optim"
                    pf_active.coil[k].name = "pf"
                    pf_active.coil[k].element[1].geometry.rectangle.r = r
                    pf_active.coil[k].element[1].geometry.rectangle.z = z
                    pf_active.coil[k].element[1].geometry.rectangle.width = buff
                    pf_active.coil[k].element[1].geometry.rectangle.height = buff
                    # pf_active.coil[k].element[1].turns_with_sign = 1
                    set_turns_from_spacing!(pf_active.coil[k], coils_turns_spacing, +1)
                    set_field_time_array(pf_active.coil[k].current, :time, 1, 0.0)
                    set_field_time_array(pf_active.coil[k].current, :data, 1, 0.0)
                end
            end
        end
    end

    # valid_r=IMAS.get_radial_build(rb, type=5, hfs=1).outline.r
    # valid_z=IMAS.get_radial_build(rb, type=5, hfs=1).outline.z
    # distance=cumsum(sqrt.(diff(valid_r).^2+diff(valid_z).^2))
    # distance.-=distance[1]
    # distance./=distance[end]
    # coils_distance=range(0,1,length=61)
    # r_coils = IMAS.interp(distance, valid_r[1:end-1])(coils_distance)
    # z_coils = IMAS.interp(distance, valid_z[1:end-1])(coils_distance)
    # for (r,z) in collect(zip(r_coils, z_coils))
    #     k = length(pf_active.coil) + 1
    #     resize!(pf_active.coil,k)
    #     resize!(pf_active.coil[k].element, 1)
    #     pf_active.coil[k].identifier = "fixed"
    #     pf_active.coil[k].element[1].geometry.rectangle.r = r
    #     pf_active.coil[k].element[1].geometry.rectangle.z = z
    #     pf_active.coil[k].element[1].geometry.rectangle.width = 0.0
    #     pf_active.coil[k].element[1].geometry.rectangle.height = 0.0
    #     pf_active.coil[k].element[1].turns_with_sign = 1
    #     set_field_time_array(pf_active.coil[k].current, :time, 1, 0.0)
    #     set_field_time_array(pf_active.coil[k].current, :data, 1, -(mod(k,2)==0 ? 1 : -1) * 5E4 * z^3)
    # end

    return pf_active
end

#= =============== =#
#  PFcoilsOptActor  #
#= =============== =#
function PFcoilsOptActor(eq_in::IMAS.equilibrium, rb::IMAS.radial_build, ncoils_OH::Int, ncoils_per_region::Vector, λ_regularize=1E-13)
    # initialize coils location
    pf_active = IMAS.pf_active()
    init(pf_active, rb, ncoils_OH, ncoils_per_region)

    # basic constructors
    eq_out = deepcopy(eq_in)
    symmetric = false
    time_index = 1
    time = eq_in.time[time_index]

    # constructor
    actor = PFcoilsOptActor(eq_in, eq_out, time, pf_active, rb, symmetric, λ_regularize, PFcoilsOptTrace())

    return actor
end

# Dispatching AD_GS on IMAS.pf_active__coil
mutable struct GS_IMAS_pf_active__coil <: AD_GS.AbstractCoil
    pf_active__coil::IMAS.pf_active__coil
    r::Real
    z::Real
    width::Real
    height::Real
    turns_with_sign::Real
    spacing::Real
    time_current::Vector{T} where T <: Real
    time::Vector{T} where T <: Real
    time_index::Int
end

function Base.getproperty(coil::GS_IMAS_pf_active__coil, field::Symbol)
    if field == :current
        return getfield(coil,:time_current)[coil.time_index]
    else
        return getfield(coil, field)
    end
end

function Base.setproperty!(coil::GS_IMAS_pf_active__coil, field::Symbol, value)
    if field == :current
        getfield(coil,:time_current)[coil.time_index] = value
    else
        setfield!(coil, field, value)
    end
    if field in [:width, :height, :spacing]
        s = sign(getfield(coil, :turns_with_sign))
        turns = Int(ceil(coil.width .* coil.height ./ coil.spacing.^2))
        setfield!(coil, :turns_with_sign, s * turns)
    end
end

function GS_IMAS_pf_active__coil(pf_active__coil)
    return GS_IMAS_pf_active__coil(pf_active__coil,
                                    pf_active__coil.element[1].geometry.rectangle.r,
                                    pf_active__coil.element[1].geometry.rectangle.z,
                                    pf_active__coil.element[1].geometry.rectangle.width,
                                    pf_active__coil.element[1].geometry.rectangle.height,
                                    pf_active__coil.element[1].turns_with_sign,
                                    get_spacing_from_turns(pf_active__coil),
                                    pf_active__coil.current.data,
                                    pf_active__coil.current.time,
                                    1)
end

function transfer_info_GS_coil_to_IMAS(coil::GS_IMAS_pf_active__coil)
    pf_active__coil = coil.pf_active__coil
    pf_active__coil.element[1].geometry.rectangle.r = coil.r
    pf_active__coil.element[1].geometry.rectangle.z = coil.z
    pf_active__coil.element[1].geometry.rectangle.width = coil.width
    pf_active__coil.element[1].geometry.rectangle.height = coil.height
    pf_active__coil.element[1].turns_with_sign = coil.turns_with_sign
    pf_active__coil.current.time = coil.time
    pf_active__coil.current.data = coil.time_current
end

function set_turns_from_spacing!(coil::GS_IMAS_pf_active__coil)
    pf_active__coil = getfield(coil,:pf_active__coil)
    return set_turns_from_spacing!(pf_active__coil, coil.spacing)
end

function set_turns_from_spacing!(pf_active__coil::IMAS.pf_active__coil, spacing::Real)
    s = sign(pf_active__coil.element[1].turns_with_sign)
    set_turns_from_spacing!(pf_active__coil, spacing, s)
end

function set_turns_from_spacing!(pf_active__coil::IMAS.pf_active__coil, spacing::Real, s::Int)
    area = (pf_active__coil.element[1].geometry.rectangle.width * pf_active__coil.element[1].geometry.rectangle.height)
    pf_active__coil.element[1].turns_with_sign = s * Int(ceil(area / spacing^2))
end

function get_spacing_from_turns(coil::GS_IMAS_pf_active__coil)
    pf_active__coil = getfield(coil,:pf_active__coil)
    return get_spacing_from_turns(pf_active__coil)
end

function get_spacing_from_turns(pf_active__coil::IMAS.pf_active__coil)
    return sqrt((pf_active__coil.element[1].geometry.rectangle.width * pf_active__coil.element[1].geometry.rectangle.height) / abs(pf_active__coil.element[1].turns_with_sign))
end

function AD_GS.Green(coil::GS_IMAS_pf_active__coil, R::Real, Z::Real)
    if coil.pf_active__coil.name == "OH"
        n = Int(ceil(coil.height / coil.width / 2.0))
        if n <= 1
            n = 1
            z_filaments = coil.z
        else
            z_filaments = range(coil.z - coil.height / 2.0, coil.z + coil.height / 2.0, length=n)
        end
        green = []
        for z in z_filaments
            push!(green, AD_GS.Green(coil.r, z, R, Z, coil.turns_with_sign / n))
        end
        return sum(green)
    else
        return AD_GS.Green(coil.r, coil.z, R, Z, coil.turns_with_sign)
    end
    #return AD_GS.Green(AD_GS.ParallelogramCoil(coil.r, coil.z, coil.width, coil.height, 0.0, 90.0, nothing), R, Z, coil.turns_with_sign/4)
    #return AD_GS.Green(AD_GS.ParallelogramCoil(coil.r, coil.z, coil.width, coil.height, 0.0, 90.0, coil.spacing), R, Z)
end

# step
function mask_interpolant_function(rb::IMAS.radial_build)
    # generate mask
    rmask, zmask, mask = IMAS.structures_mask(rb)

    # Cubic spline interpolation on the log to ensure positivity of the cost
    mask_log_interpolant_raw = Interpolations.CubicSplineInterpolation((rmask, zmask), log10.(1 .+ mask))
    mask_log_interpolant_raw = Interpolations.extrapolate(mask_log_interpolant_raw.itp, Interpolations.Flat());
    function mask_log_interpolant(r, z)
        return (10.0.^(mask_log_interpolant_raw(r, z)) .- 1)
    end
    return mask_log_interpolant
end

function pack_mask(optim_coils::Vector, λ_regularize::Float64, symmetric::Bool)::Vector{Float64}
    coilz = []
    for c in optim_coils
        if (! symmetric) || (c.z >= 0)
            push!(coilz,c.r)
            if (! symmetric) || (c.z > 0)
                push!(coilz,c.z)
            end
        end
    end
    packed = vcat(coilz, log10(λ_regularize))
    return packed
end

function unpack_mask!(optim_coils::Vector, packed::Vector, symmetric::Bool)
    coilz = packed[1:end - 1]
    λ_regularize = packed[end]
    kz=0
    posz=[]
    negz=[]
    for (k,c) in enumerate(optim_coils)
        if (! symmetric) || (c.z >= 0.0)
            kz += 1
            c.r = coilz[kz]
            if (! symmetric) || (c.z > 0.0)
                kz += 1
                c.z = coilz[kz]
                push!(posz,k)
            end
        else
            push!(negz,k)
        end
    end
    if symmetric
        for (knz,kpz) in zip(negz,posz)
            optim_coils[knz].r = optim_coils[kpz].r
            optim_coils[knz].z = -optim_coils[kpz].z
            optim_coils[knz].current = optim_coils[kpz].current
        end
    end
    return 10^λ_regularize
end

function optimize_coils_mask(eq::IMAS.equilibrium; pinned_coils::Vector, optim_coils::Vector, fixed_coils::Vector, symmetric::Bool, λ_regularize::Real, λ_ψ::Real, λ_null::Real, λ_currents::Real, rb::IMAS.radial_build, maxiter::Int, verbose::Bool)

    fixed_eqs = []
    for time_index in 1:length(eq.time_slice)
        if eq.time_slice[time_index].time < 0
            push!(fixed_eqs, AD_GS.field_null_on_boundary(eq.time_slice[time_index].global_quantities.psi_boundary,
                                                          eq.time_slice[time_index].boundary.outline.r,
                                                          eq.time_slice[time_index].boundary.outline.z,
                                                          fixed_coils))
        else
            push!(fixed_eqs, AD_GS.ψp_on_fixed_eq_boundary(IMAS2Equilibrium(eq.time_slice[time_index]), fixed_coils))
        end
    end

    mask_interpolant = mask_interpolant_function(rb)
    packed = pack_mask(optim_coils, λ_regularize, symmetric)
    trace = PFcoilsOptTrace()

    packed_tmp = []
    function placement_cost(packed; do_trace=false)
        push!(packed_tmp, packed)
        λ_regularize = unpack_mask!(optim_coils, packed, symmetric)
        coils = vcat(pinned_coils, optim_coils)
        all_cost_ψ=[]
        all_cost_currents=[]
        for fixed_eq in fixed_eqs
            currents, cost_ψ0 = AD_GS.currents_to_match_ψp(fixed_eq..., coils, λ_regularize=λ_regularize, return_cost=true)
            push!(all_cost_ψ, cost_ψ0 / λ_ψ)
            push!(all_cost_currents, norm((exp.(currents/λ_currents).-1.0)/(exp(1)-1)) / length(currents))
        end
        cost_ψ=norm(all_cost_ψ)/length(all_cost_ψ)
        cost_currents=norm(all_cost_currents)/length(all_cost_currents)
        cost_bound = norm(mask_interpolant.([c.r for c in optim_coils], [c.z for c in optim_coils]))/10
        cost_spacing = 0
        for (k1, c1) in enumerate(optim_coils)
            for (k2, c2) in enumerate(optim_coils)
                if k1 == k2
                    continue
                end
                cost_spacing += 1 / (sqrt((c1.r - c2.r)^2 + (c1.z - c2.z)^2) + 0.001)
            end
        end
        cost_spacing = cost_spacing / (length(optim_coils)^2 + 1)
        cost = sqrt(cost_ψ^2 + cost_currents^2 + cost_bound^2 + cost_spacing^2)
        if do_trace
            push!(trace.λ_regularize, no_Dual(λ_regularize))
            push!(trace.cost_ψ, no_Dual(cost_ψ))
            push!(trace.cost_currents, no_Dual(cost_currents))
            push!(trace.cost_bound, no_Dual(cost_bound))
            push!(trace.cost_spacing, no_Dual(cost_spacing))
            push!(trace.cost_total, no_Dual(cost))
        end
        return cost
    end

    function clb(x)
        placement_cost(packed_tmp[end]; do_trace=true)
        false
    end
    
    # use NelderMead() ; other optimizer that works is Newton(), others have trouble
    res = Optim.optimize(placement_cost, packed, Optim.NelderMead(), Optim.Options(time_limit=60 * 2, iterations=maxiter, callback=clb); autodiff=:forward)

    if verbose println(res) end
    packed = Optim.minimizer(res)

    λ_regularize = unpack_mask!(optim_coils, packed, symmetric)
    
    return λ_regularize, trace
end

function pack_rail(rb::IMAS.radial_build, λ_regularize::Float64, symmetric::Bool)::Vector{Float64}
    distances = []
    for rail in rb.pf_coils_rail
        # not symmetric
        if ! symmetric
            coil_distances = collect(range(-1.0, 1.0, length=rail.coils_number + 2))[2:end - 1]
        # even symmetric
        elseif mod(rail.coils_number, 2) == 0
            coil_distances = collect(range(-1.0, 1.0, length=rail.coils_number + 2))[2 + Int(rail.coils_number // 2):end - 1]
        # odd symmetric
        else
            coil_distances = collect(range(-1.0, 1.0, length=rail.coils_number + 2))[2 + Int((rail.coils_number - 1) // 2) + 1:end - 1]
        end
        append!(distances, coil_distances)
    end
    packed = vcat(distances, log10(λ_regularize))
    return packed
end

function unpack_rail!(optim_coils::Vector, packed::Vector, symmetric::Bool, rb::IMAS.radial_build)
    distances = packed[1:end - 1]
    λ_regularize = packed[end]

    if length(optim_coils) != 0 # optim_coils have zero length in case of the `static` optimization
        kcoil = 0
        koptim = 0
        for rail in rb.pf_coils_rail
            r_interp = IMAS.interp(rail.outline.distance, rail.outline.r, extrapolation_bc=:flat)
            z_interp = IMAS.interp(rail.outline.distance, rail.outline.z, extrapolation_bc=:flat)
            # not symmetric
            if ! symmetric
                dkcoil = rail.coils_number
                coil_distances = distances[kcoil + 1:kcoil + dkcoil]
            # even symmetric
            elseif mod(rail.coils_number, 2) == 0
                dkcoil = Int(rail.coils_number // 2)
                coil_distances = distances[kcoil + 1:kcoil + dkcoil]
                coil_distances = vcat(- reverse(coil_distances), coil_distances)
            # odd symmetric
            else
                dkcoil = Int((rail.coils_number - 1) // 2)
                coil_distances = distances[kcoil + 1:kcoil + dkcoil]
                coil_distances = vcat(- reverse(coil_distances), 0.0, coil_distances)
            end
            kcoil += dkcoil

            # mirror coil position when they reach the end of the rail
            while any(coil_distances .< -1) || any(coil_distances .> 1)
                coil_distances[coil_distances .< -1] = -2.0 .- coil_distances[coil_distances .< -1]
                coil_distances[coil_distances .> 1] = 2.0 .- coil_distances[coil_distances .> 1]
            end

            # get coils r and z from distances
            r_coils = r_interp.(coil_distances)
            z_coils = z_interp.(coil_distances)

            # do not let the OH coils ovelap
            if rail.name == "OH"
                z_coils, h_coils = finite_size_OH_coils(z_coils, optim_coils[1].width / 2.0)
            end

            # assign to optim coils
            for k in 1:length(r_coils)
                koptim += 1
                optim_coils[koptim].r = r_coils[k]
                optim_coils[koptim].z = z_coils[k]
                if rail.name == "OH"
                    optim_coils[koptim].height = h_coils[k]
                end
            end
        end
    end

    return 10^λ_regularize
end

function optimize_coils_rail(eq::IMAS.equilibrium; pinned_coils::Vector, optim_coils::Vector, fixed_coils::Vector, symmetric::Bool, λ_regularize::Real, λ_ψ::Real, λ_null::Real, λ_currents::Real, rb::IMAS.radial_build, maxiter::Int, verbose::Bool)

    fixed_eqs = []
    for time_index in 1:length(eq.time_slice)
        if eq.time_slice[time_index].time <0
            push!(fixed_eqs, AD_GS.field_null_on_boundary(eq.time_slice[time_index].global_quantities.psi_boundary,
                                                          eq.time_slice[time_index].boundary.outline.r,
                                                          eq.time_slice[time_index].boundary.outline.z,
                                                          fixed_coils))
        else
            push!(fixed_eqs, AD_GS.ψp_on_fixed_eq_boundary(IMAS2Equilibrium(eq.time_slice[time_index]), fixed_coils))
        end
    end

    packed = pack_rail(rb, λ_regularize, symmetric)
    trace = PFcoilsOptTrace()

    packed_tmp = []
    function placement_cost(packed; do_trace=false)
        push!(packed_tmp, packed)
        λ_regularize = unpack_rail!(optim_coils, packed, symmetric, rb)
        coils = vcat(pinned_coils, optim_coils)
        all_cost_ψ=[]
        all_cost_currents=[]
        for (time_index,fixed_eq) in enumerate(fixed_eqs)
            for coil in vcat(pinned_coils, optim_coils, fixed_coils)
                coil.time_index = time_index
            end
            currents, cost_ψ0 = AD_GS.currents_to_match_ψp(fixed_eq..., coils, λ_regularize=λ_regularize, return_cost=true)
            if eq.time_slice[time_index].time <0
                push!(all_cost_ψ, cost_ψ0 / λ_null)
            else
                push!(all_cost_ψ, cost_ψ0 / λ_ψ)
            end
            push!(all_cost_currents, norm((exp.(currents/λ_currents).-1.0)/(exp(1)-1)) / length(currents))
        end
        cost_ψ = norm(all_cost_ψ) / length(all_cost_ψ)
        cost_currents = norm(all_cost_currents) / length(all_cost_currents)
        cost_spacing = 0
        for (k1, c1) in enumerate(optim_coils)
            for (k2, c2) in enumerate(optim_coils)
                if k1 == k2
                    continue
                end
                cost_spacing += 1 / (sqrt((c1.r - c2.r)^2 + (c1.z - c2.z)^2) + 0.001)
            end
        end
        cost_spacing = cost_spacing / (length(optim_coils)^2 + 1)
        cost = sqrt(cost_ψ^2 + cost_currents^2 + cost_spacing^2)
        if do_trace
            push!(trace.λ_regularize, no_Dual(λ_regularize))
            push!(trace.cost_ψ, no_Dual(cost_ψ))
            push!(trace.cost_currents, no_Dual(cost_currents))
            push!(trace.cost_bound, NaN)
            push!(trace.cost_spacing, no_Dual(cost_spacing))
            push!(trace.cost_total, no_Dual(cost))
        end
        return cost
    end

    function clb(x)
        placement_cost(packed_tmp[end]; do_trace=true)
        false
    end
    
    if maxiter == 0
        placement_cost(packed)
        λ_regularize = unpack_rail!(optim_coils, packed, symmetric, rb)
    else
        # use NelderMead() ; other optimizer that works is Newton(), others have trouble
        res = Optim.optimize(placement_cost, packed, Optim.NelderMead(), Optim.Options(time_limit=60 * 2, iterations=maxiter, callback=clb); autodiff=:forward)
        if verbose println(res) end
        packed = Optim.minimizer(res)
        λ_regularize = unpack_rail!(optim_coils, packed, symmetric, rb)
    end

    return λ_regularize, trace
end

function step(actor::PFcoilsOptActor;
              symmetric=actor.symmetric,
              λ_regularize=actor.λ_regularize,
              λ_ψ=1E-2,
              λ_null=1,
              λ_currents=1E5,
              maxiter=10000,
              optimization_scheme=:rail,
              verbose=false)

    # sort coils
    # - optim: coils that have theri position and current optimized
    # - pinned: coisl with fixed position but current is optimized
    # - fixed: fixed position and current
    fixed_coils = GS_IMAS_pf_active__coil[]
    pinned_coils = GS_IMAS_pf_active__coil[]
    optim_coils = GS_IMAS_pf_active__coil[]
    for coil in actor.pf_active.coil
        if coil.identifier == "pinned"
            push!(pinned_coils, GS_IMAS_pf_active__coil(coil))
        elseif (coil.identifier == "optim") && (coil.name == "OH") && (optimization_scheme == :mask)
            push!(pinned_coils, GS_IMAS_pf_active__coil(coil))
        elseif (coil.identifier == "optim") && (optimization_scheme == :static)
            push!(pinned_coils, GS_IMAS_pf_active__coil(coil))
        elseif coil.identifier == "optim"
            push!(optim_coils, GS_IMAS_pf_active__coil(coil))
        elseif coil.identifier == "fixed"
            push!(fixed_coils, GS_IMAS_pf_active__coil(coil))
        else
            error("Accepted type of coil.identifier are only \"optim\", \"pinned\", or \"fixed\"")
        end
    end

    # do nothing, simply evaluate equilibrium given existing coil currents
    if maxiter < 0
        # pass

    # run optimization
    else

        for coil in vcat(pinned_coils, optim_coils, fixed_coils)
            coil.time_current = actor.eq_in.time .* 0.0
            coil.time = actor.eq_in.time
        end

        rb = actor.radial_build
        # run mask type optimizer
        if optimization_scheme == :mask
            (λ_regularize, trace) = optimize_coils_mask(actor.eq_in; pinned_coils, optim_coils, fixed_coils, symmetric, λ_regularize, λ_ψ, λ_null, λ_currents, rb, maxiter, verbose)
        # run rail type optimizer
        elseif optimization_scheme in [:rail, :static]
            (λ_regularize, trace) = optimize_coils_rail(actor.eq_in; pinned_coils, optim_coils, fixed_coils, symmetric, λ_regularize, λ_ψ, λ_null, λ_currents, rb, maxiter, verbose)
        else
            error("Supported PFcoilsOptActor optimization_scheme are `:static`, `:rail`, or `:mask`")
        end
        actor.λ_regularize = λ_regularize
        actor.trace = trace

        # transfer the results to IMAS.pf_active
        for coil in vcat(pinned_coils, optim_coils, fixed_coils)
            transfer_info_GS_coil_to_IMAS(coil)
        end
    end

    # update equilibrium
    for time_index in 1:length(actor.eq_in.time_slice)
        if actor.eq_in.time_slice[time_index].time < 0
            continue
        end
        for coil in vcat(pinned_coils, optim_coils, fixed_coils)
            coil.time_index = time_index
        end

        # convert equilibrium to Equilibrium.jl format, since this is what AD_GS uses
        EQfixed = IMAS2Equilibrium(actor.eq_in.time_slice[time_index])

        # update ψ map
        ψ_f2f = AD_GS.fixed2free(EQfixed, vcat(pinned_coils, optim_coils, fixed_coils), EQfixed.r, EQfixed.z)
        actor.eq_out.time_slice[time_index].profiles_2d[1].psi = transpose(ψ_f2f)
        # IMAS.flux_surfaces(actor.eq_out.time_slice[time_index]) #### PROBLEM
    end

    return actor
end

# plotting
"""
    plot_pfcoilsactor_cx(pfactor::PFcoilsOptActor; time_index=1, equilibrium=true, mask=false, rail=true)

Plot PFcoilsOptActor optimization cross-section
"""
@recipe function plot_pfcoilsactor_cx(pfactor::PFcoilsOptActor; time_index=1, equilibrium=true, radial_build=true, coils_flux=false, mask=false, rail=false, plot_r_buffer=1.6)

    # if there is no equilibrium then treat this as a field_null plot
    field_null = false
    if length(pfactor.eq_out.time_slice[time_index].profiles_2d)==0 || IMAS.is_missing(pfactor.eq_out.time_slice[time_index].profiles_2d[1], :psi)
        coils_flux = true
        field_null = true
    end

    # when plotting coils_flux the radial_build is not visible anyways
    if coils_flux
        radial_build = false
    end

    # setup plotting area
    xlim = [0.0, maximum(pfactor.radial_build.layer[end].outline.r)]
    ylim = [minimum(pfactor.radial_build.layer[end].outline.z), maximum(pfactor.radial_build.layer[end].outline.z)]
    xlim --> xlim * plot_r_buffer
    ylim --> ylim
    aspect_ratio --> :equal

    # plot radial build
    if radial_build
        @series begin
            exclude_layers --> [:oh]
            pfactor.radial_build
        end
    end

    # plot coils_flux
    if coils_flux
        resolution = 129
        R = range(xlim[1], xlim[2], length=resolution)
        Z = range(ylim[1], ylim[2], length=resolution)

        coils = [GS_IMAS_pf_active__coil(coil) for coil in pfactor.pf_active.coil]
        for coil in coils
            coil.time_index=time_index
        end

        # ψ coil currents
        ψbound = pfactor.eq_out.time_slice[time_index].global_quantities.psi_boundary
        ψ = AD_GS.coils_flux(2*pi, coils, R, Z)

        ψmin = minimum(x->isnan(x) ? Inf : x, ψ)
        ψmax = maximum(x->isnan(x) ? -Inf : x, ψ)
        ψabsmax = maximum(x->isnan(x) ? -Inf : x, abs.(ψ))
        
        if field_null
            clims = (-ψabsmax/10+ψbound, ψabsmax/10+ψbound)
        else
            clims = (ψmin, ψmax)
        end

        @series begin
            seriestype --> :contourf
            c --> :diverging
            colorbar_entry --> false
            levels --> range(clims[1],clims[2],length=21)
            linewidth --> 0.0
            R, Z, transpose(ψ)
        end

        if field_null
            @series begin
                seriestype --> :contour
                colorbar_entry --> false
                levels --> [ψbound]
                linecolor --> :black
                R, Z, transpose(ψ)
            end
        end

        @series begin
            outlines --> true
            exclude_layers --> [:oh]
            pfactor.radial_build
        end
    end

    # plot equilibrium
    if equilibrium
        if field_null
            @series begin
                label --> "Field null region"
                seriescolor --> :red
                pfactor.eq_out.time_slice[time_index]
            end
        else
            @series begin
                label --> "Final"
                seriescolor --> :red
                pfactor.eq_out.time_slice[time_index]
            end
            @series begin
                label --> "Target"
                seriescolor --> :blue
                lcfs --> true
                linestyle --> :dash
                pfactor.eq_in.time_slice[time_index]
            end
        end
    end

    # plot pf_active coils
    @series begin
        time_index --> time_index
        pfactor.pf_active
    end

    # plot optimization rails
    if rail
        for (krail, rail) in enumerate(pfactor.radial_build.pf_coils_rail)
            if ! is_missing(rail.outline,:r)
                @series begin
                    label --> (radial_build ? "Coil opt. rail" : "")
                    primary --> krail == 1 ? true : false
                    color --> :gray
                    linestyle --> :dash
                    rail.outline.r, rail.outline.z
                end
            end
        end
    end

    # plot optimization mask
    if mask
        rmask, zmask, cmask = IMAS.structures_mask(pfactor.radial_build)
        cl = Contour.contour(rmask, zmask, cmask, 0.5)
        for line in Contour.lines(cl)
            @series begin
                label --> (radial_build ? "Coil opt. mask" : "")
                seriescolor --> :magenta
                linewidth --> 3
                Contour.coordinates(line)
            end
        end
    end

end

"""
    plot_pfcoilsactor_trace(trace::PFcoilsOptTrace, what::Symbol=:cost; start_at::Int=1)

Plot PFcoilsOptActor optimization trace

Attributes:
- what::Symbol=:cost or :currents or individual fields of the PFcoilsOptTrace structure
- start_at=::Int=1 index of the first element of the trace to start plotting
"""
@recipe function plot_pfcoilsactor_trace(trace::PFcoilsOptTrace, what::Symbol=:cost; start_at=1)
    start_at = minimum([start_at, length(trace.cost_total)])
    x = start_at:length(trace.cost_total)
    legend --> :bottomleft
    if what == :cost
        if sum(trace.cost_ψ[start_at:end]) > 0.0
            @series begin
                label --> "ψ"
                yscale --> :log10
                x, trace.cost_ψ[start_at:end]
            end
        end
        if sum(trace.cost_currents[start_at:end]) > 0.0
            @series begin
                label --> "currents"
                yscale --> :log10
                x, trace.cost_currents[start_at:end]
            end
        end
        if sum(trace.cost_bound[start_at:end]) > 0.0
            @series begin
                label --> "bounds"
                yscale --> :log10
                x, trace.cost_bound[start_at:end]
            end
        end
        if sum(trace.cost_spacing[start_at:end]) > 0.0
            @series begin
                label --> "spacing"
                yscale --> :log10
                x, trace.cost_spacing[start_at:end]
            end
        end
        @series begin
            label --> "total"
            yscale --> :log10
            linestyle --> :dash
            color --> :black
            # ylim --> [minimum(trace.cost_total[start_at:end]) / 10,maximum(trace.cost_total[start_at:end])]
            x, trace.cost_total[start_at:end]
        end

    elseif what == :currents
        @series begin
            label --> "Starting"
            getfield(trace, what)[start_at:end][1,:]
        end
        @series begin
            label --> "Final"
            getfield(trace, what)[start_at:end][end,:]
        end

    else
        @series begin
            if occursin("cost_", String(what))
                yscale --> :log10
            end
            label --> String(what)
            x, getfield(trace, what)[start_at:end]
        end
    end
end
