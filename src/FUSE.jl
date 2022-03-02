module FUSE

__precompile__(true)

using IMAS
using Plots
using Printf

#= ======= =#
#  UTILS  #
#= ======= =#
include("utils.jl")

#= ========== =#
#  PARAMETERS  #
#= ========== =#
include("parameters.jl")
include("parameters_list.jl")

#= ====================== =#
#  PHYSICS and TECHNOLOGY  #
#= ====================== =#
include("physics.jl")
include("technology.jl")

#= ====== =#
#  DDINIT  #
#= ====== =#
include("ddinit/init_equilibrium.jl")
include("ddinit/init_build.jl")
include("ddinit/init_core_profiles.jl")
include("ddinit/init_core_sources.jl")
include("ddinit/init_pf_active.jl")
include("ddinit/init_others.jl")

#= ====== =#
#  ACTORS  #
#= ====== =#
abstract type AbstractActor end
function finalize(actor::AbstractActor)
    actor
end
include("actors/equilibrium_actor.jl")
include("actors/pf_active_actor.jl")
include("actors/build_actor.jl")
include("actors/current_actor.jl")
include("actors/sources_actor.jl")
include("actors/transport_actor.jl")

#= ========= =#
#  WORKFLOWS  #
#= ========= =#
include("workflows.jl")

#= ====== =#
#= EXPORT =#
#= ====== =#
export init, step, finalize
export IMAS, is_missing, @ddtime, @coords, constants, ±
export fuse_parameters, plasma_parameters, physics_models
export Parameters

end
