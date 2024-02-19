txt = String["""

```@meta
CurrentModule = IMAS
```

# IMAS data structure

FUSE data is organized into hierarchical Interface Data Structures (IDSs), according to the ITER IMAS ontology.
In addition to the usual IMAS IDSs (which we include on a need-by-need basis) FUSE also defines some of its own IDSs,
to hold data that does not (yet?) fit into IMAS. Notable examples are the `build`, `solid_mechanics`, `balance_of_plant`, and `costing` IDSs.

`dd = IMAS.dd()` (which stands for "data dictionary") is the root of the FUSE data structure

"""]

for name in sort!(collect(fieldnames(IMAS.dd)))
    if name == :global_time || startswith(string(name), "_")
        continue
    else
        basename = replace("$name", "_" => " ")
        push!(
            txt,
            """## $basename
            ```@example
            using IMASDD # hide
            IMASDD.$name{Float64} # hide
            ```\n"""
        )
    end
end
open("$(@__DIR__)/dd.md", "w") do io
    return write(io, join(txt, "\n"))
end

function dd_details_md(io, ids)
    ProgressMeter.@showprogress "$ids" for leaf in collect(AbstractTrees.Leaves(ids))
        name = "$(leaf.location)"
        info = IMAS.info(name)
        documentation = get(info, "documentation", "N/A")
        units = get(info, "units", "")
        if !isempty(units)
            units = "* **Units:** `$(units)`\n    "
        end
        data_type = get(info, "data_type", "")
        if !isempty(data_type)
            data_type = "* **Data Type:** `$(data_type)`\n    "
        end
        coordinates = get(info, "coordinates", "")
        if !isempty(coordinates)
            coordinates = "* **Coordinates:** `$(String[k for k in coordinates])`\n    "
        end
        txt = """

        ------------

        ```@raw html
        <div id='$name'></div>
        ```
        !!! note "$name"
            $documentation
            $(units)$(data_type)$(coordinates)
        """
        write(io, txt)
    end
end

open("$(@__DIR__)/dd_details.md", "w") do io
    for key in fieldnames(IMAS.dd)
        if key == :global_time || startswith(string(key), "_")
            continue
        end
        dd_details_md(io, getfield(IMAS, key){Float64})
    end
end
