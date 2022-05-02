using Revise
using FUSE
using Test

@testset "InitParameters" begin
    par = FUSE.InitParameters()

    @test typeof(par.equilibrium) <: FUSE.InitParameters

    @test_throws FUSE.NotsetParameterException par.equilibrium.B0

    par.equilibrium.B0 = 1.0
    @test par.equilibrium.B0 == 1.0

    @test par.equilibrium[:B0]._name == :B0
    @test par[:equilibrium]._name == :equilibrium

    ini = FUSE.InitParameters()
    ini1 = FUSE.InitParameters()
    ini.tf = ini1.tf
    @test ini.tf._parent.value !== ini1.tf._parent.value

    @test_throws Exception par.equilibrium.B0 = "a string"

    par.equilibrium.B0 = missing
    @test_throws FUSE.NotsetParameterException par.equilibrium.B0

    @test_throws FUSE.InexistentParameterException par.equilibrium.does_not_exist = 1.0

    @test keys(par.equilibrium) == keys(FUSE.InitParameters(:equilibrium))

    @test_throws FUSE.InexistentParameterException FUSE.InitParameters(:does_not_exist)

    ini, act = FUSE.case_parameters(:ITER; init_from=:scalars)

    @test typeof(ini) <: FUSE.InitParameters

    @test typeof(act) <: FUSE.ActorParameters

    @test ini.equilibrium.B0 == -5.3

    @test (ini.general.init_from = :ods) == :ods

    @test_throws FUSE.BadParameterException ini.general.init_from = :odsa

    @test_throws FUSE.InexistentParameterException FUSE.InitParameters(:inexistent_group)

    @test_throws UndefKeywordError FUSE.case_parameters(:ITER)

    for par in subtypes(FUSE.ActorAbstract)
        par = Symbol(replace(string(par), "FUSE." => ""))
        @test typeof(FUSE.ActorParameters(par)) <: FUSE.ActorParameters
    end

end
