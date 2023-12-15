#= ======== =#
#  plotting  #
#= ======== =#
"""
    plot_ActorPF_cx(
        actor::ActorPFactive{D,P};
        time_index=nothing,
        equilibrium=true,
        build=true,
        coils_flux=false,
        rails=false,
        plot_r_buffer=1.6) where {D<:Real,P<:Real}

Plot recipe for ActorPFdesign and ActorPFactive
"""
@recipe function plot_ActorPF_cx(
    actor::ActorPFactive{D,P};
    time_index=nothing,
    equilibrium=true,
    build=true,
    coils_flux=false,
    rails=false,
    control_points=true,
    plot_r_buffer=1.6) where {D<:Real,P<:Real}

    @assert typeof(time_index) <: Union{Nothing,Integer}
    @assert typeof(equilibrium) <: Bool
    @assert typeof(build) <: Bool
    @assert typeof(coils_flux) <: Bool
    @assert typeof(rails) <: Bool
    @assert typeof(control_points) <: Bool
    @assert typeof(plot_r_buffer) <: Real

    dd = actor.dd
    par = actor.par

    if time_index === nothing
        time_index = findfirst(x -> x.time == dd.global_time, actor.eq_out.time_slice)
    end
    time0 = actor.eq_out.time_slice[time_index].time

    # if there is no equilibrium then treat this as a field_null plot
    eqt2d = findfirst(:rectangular, actor.eq_out.time_slice[time_index].profiles_2d)
    field_null = false
    if eqt2d === nothing || ismissing(eqt2d, :psi)
        coils_flux = equilibrium
        field_null = true
    end

    # when plotting coils_flux the build is not visible anyways
    if coils_flux
        build = false
    end

    # setup plotting area
    xlim = [0.0, maximum(dd.build.layer[end].outline.r)]
    ylim = [minimum(dd.build.layer[end].outline.z), maximum(dd.build.layer[end].outline.z)]
    xlim --> xlim * plot_r_buffer
    ylim --> ylim
    aspect_ratio --> :equal

    # plot build
    if build
        @series begin
            exclude_layers --> [:oh]
            alpha --> 0.25
            label := false
            dd.build
        end
        @series begin
            exclude_layers --> [:oh]
            wireframe := true
            dd.build
        end
    end

    # plot coils_flux
    if coils_flux
        ngrid = 129
        R = range(xlim[1], xlim[2], ngrid)
        Z = range(ylim[1], ylim[2], Int(ceil(ngrid * (ylim[2] - ylim[1]) / (xlim[2] - xlim[1]))))

        coils = GS4_IMAS_pf_active__coil{D,D}[]
        for coil in dd.pf_active.coil
            if IMAS.is_ohmic_coil(coil)
                coil_tech = dd.build.oh.technology
            else
                coil_tech = dd.build.pf_active.technology
            end
            coil = GS4_IMAS_pf_active__coil(coil, coil_tech, par.green_model)
            coil.time_index = time_index
            push!(coils, coil)
        end

        # ψ coil currents
        ψbound = actor.eq_out.time_slice[time_index].global_quantities.psi_boundary
        ψ = [sum(VacuumFields.ψ(coil, r, z; Bp_fac=2π) for coil in coils) for r in R, z in Z]

        ψmin = minimum(x -> isnan(x) ? Inf : x, ψ)
        ψmax = maximum(x -> isnan(x) ? -Inf : x, ψ)
        ψabsmax = maximum(x -> isnan(x) ? -Inf : x, abs.(ψ))

        if field_null
            clims = (-ψabsmax / 10 + ψbound, ψabsmax / 10 + ψbound)
        else
            clims = (ψmin, ψmax)
        end

        @series begin
            seriestype --> :contourf
            c --> :diverging
            colorbar_entry --> false
            levels --> range(clims[1], clims[2], 21)
            linewidth --> 0.0
            R, Z, transpose(ψ)
        end

        if field_null
            @series begin
                seriestype --> :contour
                colorbar_entry --> false
                levels --> [ψbound]
                linecolor --> :gray
                R, Z, transpose(ψ)
            end
        end

        @series begin
            wireframe --> true
            exclude_layers --> [:oh]
            dd.build
        end
    end

    # plot equilibrium
    if equilibrium
        if field_null
            pc = dd.pulse_schedule.position_control
            @series begin
                cx := true
                label --> "Field null region"
                color --> :red
                IMAS.boundary(pc, 1)
            end
        else
            @series begin
                cx := true
                label --> "Final"
                color --> :red
                actor.eq_out.time_slice[time_index]
            end
            @series begin
                cx := true
                label --> "Original"
                color --> :gray
                lcfs --> true
                lw := 1
                actor.dd.equilibrium.time_slice[time_index]
            end
        end
    end

    # plot pf_active coils
    @series begin
        time0 --> time0
        dd.pf_active
    end

    # plot optimization rails
    if rails
        @series begin
            label --> (build ? "Coil opt. rail" : "")
            dd.build.pf_active.rail
        end
    end

    # plot control points
    if control_points
        if !isempty(actor.boundary_control_points)
            @series begin
                color := :blue
                linestyle := :dash
                linewidth := 1.5
                label := "Boundary constraint"
                [cpt.R for cpt in actor.boundary_control_points], [cpt.Z for cpt in actor.boundary_control_points]
            end
        end
        if !isempty(actor.flux_control_points)
            @series begin
                color := :blue
                seriestype := scatter
                markerstrokewidth := 0
                label := "Flux constraints"
                [cpt.R for cpt in actor.flux_control_points], [cpt.Z for cpt in actor.flux_control_points]
            end
        end
        if !isempty(actor.saddle_control_points)
            @series begin
                color := :blue
                seriestype := scatter
                markerstrokewidth := 0
                marker := :star
                label := "Saddle constraints"
                [cpt.R for cpt in actor.saddle_control_points], [cpt.Z for cpt in actor.saddle_control_points]
            end
        end
    end
end
