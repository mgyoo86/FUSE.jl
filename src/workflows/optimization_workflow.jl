mutable struct MultiobjectiveOptimizationResults
    workflow::Function
    ini::ParametersInit
    act::ParametersActor
    state::Metaheuristics.State
    opt_ini::Vector{<:Parameter}
    objectives_functions::Vector{<:ObjectiveFunction}
end

"""
    workflow_multiobjective_optimization(
        ini::ParametersInit,
        act::ParametersActor,
        workflow::Function,
        objectives_functions::Vector{<:ObjectiveFunction}=ObjectiveFunction[];
        N::Int=10,
        iterations::Int=N,
        continue_results::Union{Missing,MultiobjectiveOptimizationResults}=missing)

Find multi-objective optimum solution for `workflow(ini, act)`
"""
function workflow_multiobjective_optimization(
    ini::ParametersInit,
    act::ParametersActor,
    workflow::Function,
    objectives_functions::Vector{<:ObjectiveFunction}=ObjectiveFunction[];
    N::Int=10,
    iterations::Int=N,
    continue_results::Union{Missing,MultiobjectiveOptimizationResults}=missing)

    println("Running on $(nprocs()) processes")
    if isempty(objectives_functions)
        error("Must specify objective functions. Available pre-baked functions from ObjectivesFunctionsLibrary:\n  * " * join(keys(ObjectivesFunctionsLibrary), "\n  * "))
    end

    # itentify optimization variables in ini
    opt_ini = opt_parameters(ini)
    println("== Actuators ==")
    for optpar in opt_ini
        println(optpar)
    end
    println()
    println("== Objectives ==")
    for objf in objectives_functions
        println(objf)
    end
    println()

    # optimization boundaries
    bounds = [[optpar.lower for optpar in opt_ini] [optpar.upper for optpar in opt_ini]]'

    # test running function with nominal parameters
    workflow(ini, act)

    # optimize
    options = Metaheuristics.Options(seed=1, parallel_evaluation=true, store_convergence=true, iterations=iterations)
    algorithm = Metaheuristics.NSGA2(; N, options)
    if continue_results !== missing
        println("Restarting simulation")
        algorithm.status = continue_results.state
    end
    flush(stdout)
    p = Progress(iterations; desc="Iteration", showspeed=true)
    @time state = Metaheuristics.optimize(X -> optimization_engine(workflow, ini, act, X, opt_ini, objectives_functions, p), bounds, algorithm)

    return MultiobjectiveOptimizationResults(workflow, ini, act, state, opt_ini, objectives_functions)
end
