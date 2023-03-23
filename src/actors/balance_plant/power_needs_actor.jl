#= =============== =#
#  ActorPowerNeeds  #
#= =============== =#
Base.@kwdef mutable struct FUSEparameters__ActorPowerNeeds{T} <: ParametersActor where {T<:Real}
    _parent::WeakRef = WeakRef(Nothing)
    _name::Symbol = :not_set
    model::Switch{Symbol} = Switch(Symbol, [:gasc, :EU_DEMO, :FUSE], "-", "Power plant electrical needs model"; default=:FUSE)
    do_plot::Entry{Bool} = Entry(Bool, "-", "plot"; default=false)
end

mutable struct ActorPowerNeeds <: FacilityAbstractActor
    dd::IMAS.dd
    par::FUSEparameters__ActorPowerNeeds
end

"""
    ActorPowerNeeds(dd::IMAS.dd, act::ParametersAllActors; kw...)

Power needs actor that calculates the needed power to operate the plant

* `model = :gasc` simply assumes that the power to balance a plant is 7% of the electricity generated.
* `model = :EU_DEMO` subdivides the power plant electrical needs to [:cryostat, :tritium_handling, :pumping] using  EU-DEMO numbers.
* `model = :FUSE` subdivides power plant needs and self-consistently calculates the power needs according to FUSE
!!! note 
    Stores data in `dd.balance_of_plant.power_electric_plant_operation`
"""
function ActorPowerNeeds(dd::IMAS.dd, act::ParametersAllActors; kw...)
    par = act.ActorPowerNeeds(kw...)
    actor = ActorPowerNeeds(dd, par, act)
    step(actor)
    finalize(actor)
    return actor
end

function ActorPowerNeeds(dd::IMAS.dd, par::FUSEparameters__ActorPowerNeeds, act::ParametersAllActors; kw...)
    logging_actor_init(ActorPowerNeeds)
    par = par(kw...)
    return ActorPowerNeeds(dd, par)
end

function _step(actor::ActorPowerNeeds)
    dd = actor.dd
    par = actor.par
    bop = dd.balance_of_plant

    bop_electric = bop.power_electric_plant_operation

    ## heating and current drive systems
    system = :HCD
    idx = IMAS.name_2_index(bop_electric.system)[system]
    sys = resize!(bop_electric.system, "name" => string(system), "index" => idx)
    sys.power = zeros(length(bop.time))
    for (idx, hcd_system) in enumerate(intersect([:nbi, :ec_launchers, :ic_antennas, :lh_antennas], keys(dd)))
        sub_sys = resize!(sys.subsystem, "name" => string(hcd_system), "index" => idx)
        @ddtime(sub_sys.power = electricity(getproperty(dd, hcd_system)))
        sys.power .+= sub_sys.power
    end

    ## Other subsytems based on model
    if par.model == :gasc
        sys = resize!(bop_electric.system, "name" => "BOP_gasc", "index" => 2)
        sys.power = 0.07 .* bop_thermal.power_electric_generated

    elseif par.model == :FUSE

        # For now electrical needs same as DEMO but pumping self-consistent
        bop_systems = [:cryostat, :tritium_handling, :pumping, :pf_active]
        for system in bop_systems
            idx = IMAS.name_2_index(bop_electric.system)[system]
            sys = resize!(bop_electric.system, "name" => string(system), "index" => idx)
            if system == :pumping
                @ddtime(sys.power = electricity(:pumping, dd.balance_of_plant))
            else

                @ddtime(sys.power = electricity(system))
            end
        end

    elseif par.model == :EU_DEMO
        # More realistic DEMO numbers
        bop_systems = [:cryostat, :tritium_handling, :pumping, :pf_active]
        for system in bop_systems
            idx = IMAS.name_2_index(bop_electric.system)[system]
            sys = resize!(bop_electric.system, "name" => string(system), "index" => idx)
            sys.power = electricity(system)
        end
    end
    return actor
end

function heating_and_current_drive_calc(system_unit)
    power_electric_total = 0.0
    for item_unit in system_unit
        efficiency = prod([getproperty(item_unit.efficiency, i) for i in keys(item_unit.efficiency)])
        power_electric_total += @ddtime(item_unit.power_launched.data) / efficiency
    end
    return power_electric_total
end

function electricity(nbi::IMAS.nbi)
    return heating_and_current_drive_calc(nbi.unit)
end

function electricity(ec_launchers::IMAS.ec_launchers)
    return heating_and_current_drive_calc(ec_launchers.beam)
end

function electricity(ic_antennas::IMAS.ic_antennas)
    return heating_and_current_drive_calc(ic_antennas.antenna)
end

function electricity(lh_antennas::IMAS.lh_antennas)
    return heating_and_current_drive_calc(lh_antennas.antenna)
end

function electricity(symbol::Symbol)
    return electricity(Val{symbol})
end

#= =================== =#
#  EU DEMO electricity  #
#= =================== =#

# Dummy functions values taken from DEMO 2017  https://iopscience.iop.org/article/10.1088/0029-5515/57/1/016011
function electricity(::Type{Val{:cryostat}})
    return 30e6 # We
end

function electricity(::Type{Val{:tritium_handling}})
    return 15e6# We
end

function electricity(::Type{Val{:pumping}})
    return 80e6 # We    (Note this should not be a constant!)
end

function electricity(::Type{Val{:pf_active}})
    return 0.0 # We    (Note this should not be a constant!)
end

#= =================== =#
#  FUSE electricity     #
#= =================== =#

function electricity(::Type{Val{:pumping}}, bop::IMAS.balance_of_plant)
    return @ddtime(bop.heat_transfer.breeder.circulator_power) + @ddtime(bop.heat_transfer.divertor.circulator_power) + @ddtime(bop.heat_transfer.wall.circulator_power)
end

function electricity(symbol::Symbol, bop::IMAS.balance_of_plant)
    return electricity(Val{symbol}, bop)
end