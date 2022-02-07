__precompile__()

module FUSE

using IMAS

#= ======= =#
#= INCLUDE =#
#= ======= =#
include("utils.jl")

include("physics.jl")

include("actors.jl")

include("parameters.jl")

#= ====== =#
#= EXPORT =#
#= ====== =#
export init, step, finalize
export IMAS, is_missing, @ddtime, @coords
export fuse_parameters, plasma_parameters, physics_models

end
