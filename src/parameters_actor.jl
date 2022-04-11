"""
    ActorParameters()

Generates actor parameters 
"""
function ActorParameters()
    par = ActorParameters(Symbol[], Dict{Symbol,Union{Parameter,ActorParameters}}())
    for item in [:SolovevActor, :CXbuildActor, :OHTFsizingActor, :PFcoilsOptActor]
        setproperty!(par, item, ActorParameters(item))
    end
    return par
end

