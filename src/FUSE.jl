__precompile__(true)

module FUSE

using IMAS
import Plots
using Plots
using Printf
using InteractiveUtils
import SnoopPrecompile

#= ===== =#
#  UTILS  #
#= ===== =#
include("utils_begin.jl")

#= =================== =#
#  ABSTRACT PARAMETERS  #
#= =================== =#
include("parameters.jl")

#= ====================== =#
#  PHYSICS and TECHNOLOGY  #
#= ====================== =#
include("physics.jl")
include("technology.jl")

#= ====== =#
#  DDINIT  #
#= ====== =#
include(joinpath("ddinit", "init.jl"))
include(joinpath("ddinit", "init_from_ods.jl"))
include(joinpath("ddinit", "init_pulse_schedule.jl"))
include(joinpath("ddinit", "init_equilibrium.jl"))
include(joinpath("ddinit", "init_build.jl"))
include(joinpath("ddinit", "init_core_profiles.jl"))
include(joinpath("ddinit", "init_core_sources.jl"))
include(joinpath("ddinit", "init_currents.jl"))
include(joinpath("ddinit", "init_pf_active.jl"))
include(joinpath("ddinit", "init_others.jl"))
include(joinpath("ddinit", "gasc.jl"))

#= ====== =#
#  ACTORS  #
#= ====== =#
# the order of include matters due to import/using statements as well as the dependency of defines structures
include(joinpath("actors", "abstract_actors.jl"))

include(joinpath("actors", "equilibrium", "solovev_actor.jl"))
include(joinpath("actors", "equilibrium", "chease_actor.jl"))
include(joinpath("actors", "equilibrium", "tequila_actor.jl"))
include(joinpath("actors", "equilibrium", "equilibrium_actor.jl"))

include(joinpath("actors", "pf", "pf_active_actor.jl"))
include(joinpath("actors", "pf", "pf_passive_actor.jl"))

include(joinpath("actors", "build", "oh_magnet.jl"))
include(joinpath("actors", "build", "tf_magnet.jl"))
include(joinpath("actors", "build", "stresses_actor.jl"))
include(joinpath("actors", "build", "fluxswing_actor.jl"))
include(joinpath("actors", "build", "lfs_actor.jl"))
include(joinpath("actors", "build", "hfs_actor.jl"))
include(joinpath("actors", "build", "cx_actor.jl"))

include(joinpath("actors", "nuclear", "blanket_actor.jl"))
include(joinpath("actors", "nuclear", "neutronics_actor.jl"))

include(joinpath("actors", "current", "qed_actor.jl"))
include(joinpath("actors", "current", "steadycurrent_actor.jl"))
include(joinpath("actors", "current", "current_actor.jl"))

include(joinpath("actors", "hcd", "simple_common.jl"))
include(joinpath("actors", "hcd", "ec_simple_actor.jl"))
include(joinpath("actors", "hcd", "ic_simple_actor.jl"))
include(joinpath("actors", "hcd", "lh_simple_actor.jl"))
include(joinpath("actors", "hcd", "nb_simple_actor.jl"))
include(joinpath("actors", "hcd", "hcd_actor.jl"))

include(joinpath("actors", "pedestal", "pedestal_actor.jl"))

include(joinpath("actors", "divertors", "divertors_actor.jl"))

include(joinpath("actors", "transport", "tauenn_actor.jl"))
include(joinpath("actors", "transport", "neoclassical_actor.jl"))
include(joinpath("actors", "transport", "tglf_actor.jl"))
include(joinpath("actors", "transport", "flux_calculator_actor.jl"))
include(joinpath("actors", "transport", "flux_matcher_actor.jl"))
include(joinpath("actors", "transport", "fixed_profiles_actor.jl"))
include(joinpath("actors", "transport", "core_transport_actor.jl"))

include(joinpath("actors", "stability", "limits_actor.jl"))
include(joinpath("actors", "stability", "limit_models.jl"))

include(joinpath("actors", "balance_plant", "heat_transfer_actor.jl"))
include(joinpath("actors", "balance_plant", "thermal_cycle_actor.jl"))
include(joinpath("actors", "balance_plant", "power_needs_actor.jl"))
include(joinpath("actors", "balance_plant", "balance_of_plant_actor.jl"))
include(joinpath("actors", "balance_plant", "balance_of_plant_plot.jl"))

include(joinpath("actors", "costing", "costing_utils.jl"))
include(joinpath("actors", "costing", "sheffield_costing_actor.jl"))
include(joinpath("actors", "costing", "aries_costing_actor.jl"))
include(joinpath("actors", "costing", "gasc_costing_actor.jl"))
include(joinpath("actors", "costing", "costing_actor.jl"))

# NOTE: compound actors should be defined last
include(joinpath("actors", "compound", "stationary_plasma_actor.jl"))
include(joinpath("actors", "compound", "dynamic_plasma_actor.jl"))
include(joinpath("actors", "compound", "whole_facility_actor.jl"))

#= ========== =#
#  PARAMETERS  #
#= ========== =#
include("parameters_inits.jl")
include("parameters_actors.jl")
include("signal.jl")

#= ============ =#
#  OPTIMIZATION  #
#= ============ =#
include("optimization.jl")

#= ========= =#
#  WORKFLOWS  #
#= ========= =#
include(joinpath("workflows", "optimization_workflow.jl"))
include(joinpath("workflows", "DB5_validation_workflow.jl"))

#= ======= =#
#  LOGGING  #
#= ======= =#
include("logging.jl")

#= ===== =#
#  UTILS  #
#= ===== =#
include("utils_end.jl")

#= ========== =#
#  PRECOMPILE  #
#= ========== =#
include("precompile.jl")

#= ====== =#
#= EXPORT =#
#= ====== =#
export IMAS, @ddtime, constants, ±, ↔, Logging
export step, pulse, ramp, trap

end
