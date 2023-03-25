import Weave

# ===================================== #
# extract data from FUSE save folder(s) #
# ===================================== #
"""
    IMAS.extract(dir::AbstractString, xtract::AbstractDict{Symbol,IMAS.ExtractFunction}=IMAS.ExtractFunctionsLibrary)::Vector{IMAS.ExtractFunction}

Read dd.json/h5 in a folder and extract data from it.
"""
function IMAS.extract(dir::AbstractString, xtract::AbstractDict{Symbol,IMAS.ExtractFunction}=IMAS.ExtractFunctionsLibrary)::Vector{IMAS.ExtractFunction}
    dd, ini, act = load(dir; load_ini=false, load_act=false)
    return extract(dd, xtract)
end

"""
    IMAS.extract(DD::Vector{<:Union{AbstractString,IMAS.dd}}, xtract::AbstractDict{Symbol,IMAS.ExtractFunction}=IMAS.ExtractFunctionsLibrary; filter_invalid::Symbol=:none)::DataFrames.DataFrame

Extract data from multiple folders or `dd`s and return results in DataFrame format.

Filtering can by done by `:cols` that have all NaNs, `:rows` that have any NaN, or both with `:all`
"""
function IMAS.extract(DD::Vector{<:Union{AbstractString,IMAS.dd}}, xtract::AbstractDict{Symbol,IMAS.ExtractFunction}=IMAS.ExtractFunctionsLibrary; filter_invalid::Symbol=:none)::DataFrames.DataFrame
    # allocate memory
    df = DataFrames.DataFrame(extract(DD[1], xtract))
    for k in 2:length(DD)
        push!(df, df[1, :])
    end

    # load the data
    p = ProgressMeter.Progress(length(DD); showspeed=true)
    Threads.@threads for k in eachindex(DD)
        df[k, :] = Dict(extract(DD[k], xtract))
        ProgressMeter.next!(p)
    end

    # filter
    if filter_invalid ∈ [:cols, :all]
        # drop columns that have all NaNs
        visnan(x::Vector) = isnan.(x)
        df = df[:, .!all.(visnan.(eachcol(df)))]
    end
    if filter_invalid ∈ [:rows, :all]
        # drop rows that have any NaNs
        df = filter(row -> all(x -> !(x isa Number && (isnan(x) || isinf(x))), row), df)
    end

    return df
end

"""
    DataFrames.DataFrame(xtract::AbstractDict{Symbol,IMAS.ExtractFunction})

Construct a DataFrame from a dictionary of IMAS.ExtractFunction
"""
function DataFrames.DataFrame(xtract::AbstractDict{Symbol,IMAS.ExtractFunction})
    return DataFrames.DataFrame(Dict(xtract))
end

"""
    Dict(xtract::AbstractDict{Symbol,IMAS.ExtractFunction})

Construct a Dictionary with the evaluated values of a dictionary of IMAS.ExtractFunction
"""
function Dict(xtract::AbstractDict{Symbol,IMAS.ExtractFunction})
    tmp = Dict()
    for xfun in values(xtract)
        tmp[xfun.name] = xfun.value
    end
    return tmp
end

# ==================== #
# save/load simulation #
# ==================== #
"""
    save(
        dd::IMAS.dd,
        ini::ParametersAllInits,
        act::ParametersAllActors,
        savedir::AbstractString;
        freeze::Bool=true,
        format::Symbol=:json)

Save FUSE (dd, ini, act) to dd.json/h5, ini.json, and act.json files
"""
function save(
    savedir::AbstractString,
    dd::IMAS.dd,
    ini::ParametersAllInits,
    act::ParametersAllActors;
    freeze::Bool=true,
    format::Symbol=:json)

    @assert format in [:hdf, :json] "format must be either `:hdf` or `:json`"
    mkdir(savedir) # purposely error if directory exists or path does not exist
    if format == :hdf
        IMAS.imas2hdf(dd, joinpath(savedir, "dd.h5"); freeze)
    elseif format == :json
        IMAS.imas2json(dd, joinpath(savedir, "dd.json"); freeze)
    end
    ini2json(ini, joinpath(savedir, "ini.json"))
    act2json(act, joinpath(savedir, "act.json"))
    return savedir
end

"""
    save(
        savedir::AbstractString,
        dd::IMAS.dd,
        ini::ParametersAllInits,
        act::ParametersAllActors,
        e::Exception;
        freeze::Bool=true,
        format::Symbol=:json)

Save FUSE (dd, ini, act) to dd.json/h5, ini.json, and act.json files and exception stacktrace to "error.txt"
"""
function save(
    savedir::AbstractString,
    dd::IMAS.dd,
    ini::ParametersAllInits,
    act::ParametersAllActors,
    e::Exception;
    freeze::Bool=true,
    format::Symbol=:json)

    save(savedir, dd, ini, act; freeze, format)

    open(joinpath(savedir, "error.txt"), "w") do file
        showerror(file, e, catch_backtrace())
    end

    return savedir
end

"""
    load(savedir::AbstractString; load_dd::Bool=true, load_ini::Bool=true, load_act::Bool=true)

Read (dd, ini, act) to dd.json/h5, ini.json, and act.json files.

Returns `missing` for files are not there or if `error.txt` file exists in the folder.
"""
function load(savedir::AbstractString; load_dd::Bool=true, load_ini::Bool=true, load_act::Bool=true)
    if isfile(joinpath(savedir, "error.txt"))
        @warn "$savedir simulation errored"
        return missing, missing, missing
    end
    dd = missing
    if load_dd
        if isfile(joinpath(savedir, "dd.h5"))
            dd = IMAS.hdf2imas(joinpath(savedir, "dd.h5"))
        elseif isfile(joinpath(savedir, "dd.json"))
            dd = IMAS.json2imas(joinpath(savedir, "dd.json"))
        end
    end
    ini = missing
    if load_ini && isfile(joinpath(savedir, "ini.json"))
        ini = json2ini(joinpath(savedir, "ini.json"))
    end
    act = missing
    if load_act && isfile(joinpath(savedir, "act.json"))
        act = json2act(joinpath(savedir, "act.json"))
    end
    return dd, ini, act
end

"""
    digest(dd::IMAS.dd; terminal_width::Int=136)

Provides concise and informative summary of `dd`, including several plots.
"""
function digest(dd::IMAS.dd; terminal_width::Int=136, line_char="─")
    #NOTE: this function is defined in FUSE and not IMAS because it uses Plots.jl and not BaseRecipies.jl

    IMAS.print_tiled(extract(dd); terminal_width, line_char)

    if !isempty(dd.build.layer)
        display(dd.build.layer)
    end

    # equilibrium with build and PFs
    p = plot(dd.equilibrium, legend=false)
    if !isempty(dd.build.layer)
        plot!(p[1], dd.build, legend=false)
    end
    if !isempty(dd.pf_active.coil)
        plot!(p[1], dd.pf_active, legend=false, colorbar=false)
    end
    display(p)

    # core profiles
    display(plot(dd.core_profiles, only=1))
    display(plot(dd.core_profiles, only=2))
    display(plot(dd.core_profiles, only=3))

    # core sources
    display(plot(dd.core_sources, only=1))
    display(plot(dd.core_sources, only=2))
    display(plot(dd.core_sources, only=3))
    display(plot(dd.core_sources, only=4))

    # neutron wall loading
    if !isempty(dd.neutronics.time_slice)
        xlim = extrema(dd.neutronics.first_wall.r)
        xlim = (xlim[1] - ((xlim[2] - xlim[1]) / 10.0), xlim[2] + ((xlim[2] - xlim[1]) / 10.0))
        display(plot(dd.neutronics.time_slice[].wall_loading; xlim))
    end

    # center stack stresses
    if !ismissing(dd.solid_mechanics.center_stack.grid, :r_oh)
        display(plot(dd.solid_mechanics.center_stack.stress))
    end

    # # balance of plant
    # if !missing(dd.balance_of_plant, :Q_plant)
    #     display(plot(dd.balance_of_plant))
    # end

    # costing
    if !ismissing(dd.costing.cost_direct_capital, :cost) && (dd.costing.cost_direct_capital.cost != 0)
        display(plot(dd.costing.cost_direct_capital))
    end

    return nothing
end

"""
    digest(dd::IMAS.dd, title::AbstractString, description::AbstractString="")

Write digest to PDF in current working directory.

PDF filename is based on title (with `" "` replaced by `"_"`)
"""
function digest(dd::IMAS.dd, title::AbstractString, description::AbstractString="")
    outfilename = joinpath(pwd(), "$(replace(title," "=>"_")).pdf")
    tmpdir = mktempdir()
    logger = SimpleLogger(stderr, Logging.Warn)
    try
        filename = redirect_stdout(Base.DevNull()) do
            with_logger(logger) do
                Weave.weave(joinpath(@__DIR__, "digest.jmd");
                    mod=@__MODULE__,
                    doctype="md2pdf",
                    template=joinpath(@__DIR__, "digest.tpl"),
                    out_path=tmpdir,
                    args=Dict(
                        :dd => dd,
                        :title => title,
                        :description => description))
            end
        end
        cp(filename, outfilename, force=true)
        return outfilename
    catch e
        println(tmpdir)
    else
        rm(tmpdir, recursive=true, force=true)
    end
end
