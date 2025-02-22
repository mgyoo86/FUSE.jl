import HDF5

#= ====================== =#
#  StudyDatabaseGenerator  #
#= ====================== =#

"""
    study_parameters(::Type{Val{:DatabaseGenerator}})::Tuple{FUSEparameters__ParametersStudyDatabaseGenerator,ParametersAllActors}

Generates a database of dds from `ini` and `act` based on ranges specified in `ini` (i.e. `ini.equilibrium.R0 = 5.0 ↔ [4.0, 10.0]`)

It's also possible to run the database generator on Vector of `ini`s and `act`s. NOTE: the length of the `ini`s and `act`s must be the same.

There is a example notebook in `FUSE_examples/study_database_generator.ipynb` that goes through the steps of setting up, running and analyzing this study
"""
function study_parameters(::Type{Val{:DatabaseGenerator}})::Tuple{FUSEparameters__ParametersStudyDatabaseGenerator,ParametersAllActors}

    sty = FUSEparameters__ParametersStudyDatabaseGenerator{Real}()
    act = ParametersActors()

    # Change act for the default DatabaseGenerator run
    act.ActorCoreTransport.model = :FluxMatcher
    act.ActorFluxMatcher.evolve_pedestal = false
    act.ActorTGLF.warn_nn_train_bounds = false
    act.ActorFluxMatcher.evolve_rotation = :fixed

    # finalize
    set_new_base!(sty)
    set_new_base!(act)

    return sty, act
end

Base.@kwdef mutable struct FUSEparameters__ParametersStudyDatabaseGenerator{T<:Real} <: ParametersStudy{T}
    _parent::WeakRef = WeakRef(nothing)
    _name::Symbol = :StudyDatabaseGenerator
    server::Switch{String} = study_common_parameters(; server="localhost")
    n_workers::Entry{Int} = study_common_parameters(; n_workers=missing)
    file_save_mode::Switch{Symbol} = study_common_parameters(; file_save_mode=:safe_write)
    release_workers_after_run::Entry{Bool} = study_common_parameters(; release_workers_after_run=true)
    save_dd::Entry{Bool} = study_common_parameters(; save_dd=true)
    save_folder::Entry{String} = Entry{String}("-", "Folder to save the database runs into")
    n_simulations::Entry{Int} = Entry{Int}("-", "Number of sampled simulations")
    data_storage_policy::Switch{Symbol} = study_common_parameters(; data_storage_policy=:separate_folders)
end

mutable struct StudyDatabaseGenerator <: AbstractStudy
    sty::FUSEparameters__ParametersStudyDatabaseGenerator
    ini::Union{ParametersAllInits,Vector{<:ParametersAllInits}}
    act::Union{ParametersAllActors,Vector{<:ParametersAllActors}}
    dataframe::Union{DataFrame,Missing}
    iterator::Union{Vector{Int},Missing}
    workflow::Union{Function,Missing}
end

function StudyDatabaseGenerator(sty::ParametersStudy, ini::ParametersAllInits, act::ParametersAllActors; kw...)
    sty = sty(kw...)
    study = StudyDatabaseGenerator(sty, ini, act, missing, missing, missing)
    return setup(study)
end

function StudyDatabaseGenerator(sty::ParametersStudy, inis::Vector{<:ParametersAllInits}, acts::Vector{<:ParametersAllActors}; kw...)
    @assert length(inis) == length(acts)
    sty = sty(kw...)
    study = StudyDatabaseGenerator(sty, inis, acts, missing, missing, missing)
    return setup(study)
end

function _setup(study::StudyDatabaseGenerator)
    sty = study.sty

    check_and_create_file_save_mode(sty)

    parallel_environment(sty.server, sty.n_workers)

    return study
end

"""
    _run(study::StudyDatabaseGenerator)

Runs the DatabaseGenerator with sty settings in parallel on designated cluster
"""
function _run(study::StudyDatabaseGenerator)
    sty = study.sty

    @assert sty.n_workers == length(Distributed.workers()) "The number of workers =  $(length(Distributed.workers())) isn't the number of workers you requested = $(sty.n_workers)"

    if typeof(study.ini) <: ParametersAllInits && typeof(study.act) <: ParametersAllActors
        iterator = collect(1:sty.n_simulations)
    elseif typeof(study.ini) <: Vector{<:ParametersAllInits} && typeof(study.act) <: Vector{<:ParametersAllActors}
        @assert length(study.ini) == length(study.act)
        iterator = collect(1:length(study.ini))
    else
        error("DatabaseGenerator should never be here: ini and act are incompatible")
    end

    study.iterator = iterator

    # paraller run
    println("running $(sty.n_simulations) simulations with $(sty.n_workers) workers on $(sty.server)")

    if study.sty.data_storage_policy == :separate_folders
        FUSE.ProgressMeter.@showprogress pmap(item -> run_case(study, item), iterator)
    elseif study.sty.data_storage_policy == :merged_hdf5
        dataframe_list = FUSE.ProgressMeter.@showprogress pmap(item -> run_case(study, item, Val{:hdf5}), iterator)
        study.dataframe = reduce(vcat, dataframe_list)

        _merge_h5_files_and_write_csv_file(study; cleanup=true)

    else
        error("DatabaseGenerator should never be here: data_storage_policy must be either `:separate_folders` or `merged_hdf5`")
    end

    analyze(study; extract_results=false)

    # Release workers after run
    if sty.release_workers_after_run
        Distributed.rmprocs(Distributed.workers())
        @info "released workers"
    end

    return study
end

function _merge_h5_files_and_write_csv_file(study::StudyDatabaseGenerator; cleanup::Bool=false)
    sty = study.sty
    date_time_str = Dates.format(Dates.now(), "yyyy-mm-ddTHH:MM:SS")
    merged_hdf5_filename = "database_$(date_time_str).h5"

    save_folder = study.sty.save_folder

    IMAS.h5merge(joinpath(save_folder, merged_hdf5_filename),
        joinpath(save_folder, "tmp_h5_output");
        h5_strip_group_prefix=true,
        cleanup)

    # write study.dataframe into a separate csv file
    csv_filepath = joinpath(sty.save_folder, "extract_$(date_time_str).csv")
    CSV.write(csv_filepath, study.dataframe)

    # write study.dataframe into the mergedh5 file as well
    HDF5.h5open(joinpath(sty.save_folder, merged_hdf5_filename), "r+") do fid
        io_buffer = IOBuffer()
        CSV.write(io_buffer, study.dataframe)
        csv_text = String(take!(io_buffer))
        HDF5.write(fid, "extract.csv", csv_text)
        attr = HDF5.attrs(fid["/extract.csv"])
        attr["date_time"] = date_time_str
        attr["FUSE_version"] = string(pkgversion(FUSE))
    end
end


"""
    _analyze(study::StudyDatabaseGenerator)

Example of analyze plots to display after the run feel free to change this method for your needs
"""
function _analyze(study::StudyDatabaseGenerator; extract_results::Bool=true, re_extract::Bool=false)
    if extract_results
        extract_results(study; re_extract)
    end
    df = study.dataframe
    display(histogram(df.Te0; xlabel="Te0 [keV]", ylabel="Number of simulations per bin", legend=false))
    display(histogram(df.Ti0; xlabel="Ti0 [keV]", ylabel="Number of simulations per bin", legend=false))
    display(histogram(df.ne0; xlabel="ne0 [m⁻³]]", ylabel="Number of simulations per bin", legend=false))
    return study
end

"""
    run_case(study::AbstractStudy, item::String)

Run a single case based by setting up a dd from ini and act and then executing the workflow_DatabaseGenerator workflow (feel free to change the workflow based on your needs)
"""
function run_case(study::AbstractStudy, item::Int)
    sty = study.sty
    @assert isa(study.workflow, Function) "Make sure to specicy a workflow to study.workflow that takes dd, ini , act as arguments"

    original_dir = pwd()
    savedir = abspath(joinpath(sty.save_folder, "$(item)__$(Dates.now())__$(getpid())"))
    mkdir(savedir)
    cd(savedir)

    # Redirect stdout and stderr to the file
    original_stdout = stdout  # Save the original stdout
    original_stderr = stderr  # Save the original stderr
    file_log = open("log.txt", "w")

    # ini/act variations
    if typeof(study.ini) <: ParametersAllInits
        ini = rand(study.ini)
    elseif typeof(study.ini) <: Vector{<:ParametersAllInits}
        ini = study.ini[item]
    end
    if typeof(study.act) <: ParametersAllActors
        act = rand(study.act)
    elseif typeof(study.act) <: Vector{<:ParametersAllActors}
        act = study.act[item]
    end

    dd = IMAS.dd()

    try
        redirect_stdout(file_log)
        redirect_stderr(file_log)

        study.workflow(dd, ini, act)

        # save simulation data to directory
        save(savedir, sty.save_dd ? dd : nothing, ini, act; timer=true, freeze=false, overwrite_files=true)

        return nothing
    catch error
        if isa(error, InterruptException)
            rethrow(error)
        end

        # save empty dd and error to directory
        save(savedir, nothing, ini, act; error, timer=true, freeze=false, overwrite_files=true)
    finally
        redirect_stdout(original_stdout)
        redirect_stderr(original_stderr)
        cd(original_dir)
        close(file_log)
    end
end

function run_case(study::AbstractStudy, item::Int, ::Type{Val{:hdf5}}; kw...)
    sty = study.sty
    @assert isa(study.workflow, Function) "Make sure to specicy a workflow to study.workflow that takes dd, ini , act as arguments"

    original_dir = pwd()
    if !isdir(sty.save_folder)
        mkdir(sty.save_folder)
    end
    cd(sty.save_folder)

    # Redirect stdout and stderr to the file
    original_stdout = stdout  # Save the original stdout
    original_stderr = stderr  # Save the original stderr

    # ini/act variations
    if typeof(study.ini) <: ParametersAllInits
        ini = rand(study.ini)
    elseif typeof(study.ini) <: Vector{ParametersAllInits}
        ini = study.ini[item]
    end

    if typeof(study.act) <: ParametersAllActors
        act = rand(study.act)
    elseif typeof(study.act) <: Vector{ParametersAllActors}
        act = study.act[item]
    end

    dd = IMAS.dd()

    # zero_pad_length = length(string(sty.n_simulations))
    # parent_group = "case$(lpad(item,zero_pad_length,"0"))"

    parent_group = "case_$item"
    tmp_log_filename = "tmp_log_case_$item.txt"
    tmp_log_io = open(tmp_log_filename, "w+")


    try
        redirect_stdout(tmp_log_io)
        redirect_stderr(tmp_log_io)

        study.workflow(dd, ini, act)

        save2hdf("tmp_h5_output", parent_group, (sty.save_dd ? dd : nothing), ini, act, tmp_log_io;
                            timer=true, freeze=false, overwrite_groups=true, kw...)


        this_df = DataFrame(IMAS.extract(dd,:all))
        this_df[!,:gen] = fill(item, nrow(this_df))

        return this_df
    catch error
        if isa(error, InterruptException)
            rethrow(error)
        end

        # save empty dd and error to directory
        save2hdf("tmp_h5_output", parent_group, nothing, ini, act, tmp_log_io;
                            error_info=error, timer=true, freeze=false, overwrite_groups=true, kw...)
    finally
        redirect_stdout(original_stdout)
        redirect_stderr(original_stderr)
        close(tmp_log_io)
        rm(tmp_log_filename; force=true)

        cd(original_dir)
    end
end