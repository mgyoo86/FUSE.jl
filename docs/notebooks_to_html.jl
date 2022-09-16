using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))
using ProgressMeter

execute = "--execute" in ARGS

dirs = ["cases", "actors", "tutorials", "workflows"]

# Converts all notebooks in examples/... to .md and stores them in docs/src
current_path = @__DIR__

failed = String[]
for dir in dirs
    example_folder = joinpath(current_path, "..", "examples", dir)
    files_to_convert = readdir(example_folder)[findall(x -> endswith(x, ".ipynb"), readdir(example_folder))]

    @showprogress for case in files_to_convert
        ipynb = joinpath(example_folder, case)
        casename = split(case, ".")[1]
        srcname = joinpath(example_folder, "$casename.md")
        srcfiles = joinpath(example_folder, casename * "_files")
        dstname = joinpath(current_path, "src", "example_$(dir)__$(casename).md")
        dstfiles = joinpath(current_path, "src", "assets", "$(casename)_files")

        if isfile(dstname)
            @warn "$dstname exists: skipping nbconvert"
        else
            if !execute
                run(`jupyter nbconvert --to markdown $ipynb`)
            else
                try
                    @info "converting $ipynb"
                    run(`jupyter nbconvert --execute --to markdown $ipynb`)
                catch e
                    run(`jupyter nbconvert --to markdown $ipynb`)
                    push!(failed, ipynb)
                    @error "error executing $ipynb: skipping nbconvert"
                end
            end
            run(`rm -rf $dstfiles`)
            if isdir(srcfiles)
                run(`mv -f $srcfiles $dstfiles`)
            end
        end

        if isfile(srcname)
            run(`cp -f $srcname $dstname`)
            txt = open(dstname, "r") do io
                txt = read(io, String)
                txt = replace(txt, "$(casename)_files" => "assets/$(casename)_files")
                txt = replace(txt, "assets/assets/$(casename)_files" => "assets/$(casename)_files")
                txt = replace(txt, r"\[[0-9]+m" => "")
                return txt = replace(txt, r"```julia" => "```@julia")
            end
            open(dstname, "w") do io
                return write(io, txt)
            end
        end
    end
end

if length(failed) > 0
    for ipynb in failed
        @error @error "error executing $ipynb"
    end
end