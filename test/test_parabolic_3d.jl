module TestExamplesParabolic3D

using Test
using Trixi

include("test_trixi.jl")

# Start with a clean environment: remove Trixi.jl output directory if it exists
outdir = "out"
isdir(outdir) && rm(outdir, recursive=true)

@testset "SemidiscretizationHyperbolicParabolic (3D)" begin

  @trixi_testset "DGMulti: elixir_navierstokes_convergence.jl" begin
    @test_trixi_include(joinpath(examples_dir(), "dgmulti_3d", "elixir_navierstokes_convergence.jl"),
      cells_per_dimension = (4, 4, 4), tspan=(0.0, 0.1),
      l2 = [0.0005532847115849239, 0.000659263490965341, 0.0007776436127362806, 0.0006592634909662951, 0.0038073628897809185],
      linf = [0.0017039861523615585, 0.002628561703560073, 0.003531057425112172, 0.0026285617036090336, 0.015587829540351095]
    )
  end

  @trixi_testset "DGMulti: elixir_navierstokes_convergence_curved.jl" begin
    @test_trixi_include(joinpath(examples_dir(), "dgmulti_3d", "elixir_navierstokes_convergence_curved.jl"),
      cells_per_dimension = (4, 4, 4), tspan=(0.0, 0.1),
      l2 = [0.0014027227251207474, 0.0021322235533273513, 0.0027873741447455194, 0.0024587473070627423, 0.00997836818019202],
      linf = [0.006341750402837576, 0.010306014252246865, 0.01520740250924979, 0.010968264045485565, 0.047454389831591115]
    )
  end

  @trixi_testset "DGMulti: elixir_navierstokes_taylor_green_vortex.jl" begin
    @test_trixi_include(joinpath(examples_dir(), "dgmulti_3d", "elixir_navierstokes_taylor_green_vortex.jl"),
      cells_per_dimension = (4, 4, 4), tspan=(0.0, 0.25),
      l2 = [0.0001825713444029892, 0.015589736382772248, 0.015589736382771884, 0.021943924667273653, 0.01927370280244222],
      linf = [0.0006268463584697681, 0.03218881662749007, 0.03218881662697948, 0.053872495395614256, 0.05183822000984151]
    )
  end

  @trixi_testset "TreeMesh3D: elixir_navierstokes_convergence.jl" begin
    @test_trixi_include(joinpath(examples_dir(), "tree_3d_dgsem", "elixir_navierstokes_convergence.jl"),
      initial_refinement_level = 2, tspan=(0.0, 0.1),
      l2 = [0.0019582188528512257, 0.002653449504302844, 0.002898264205184629, 0.002653449504302853, 0.009511572365085706],
      linf = [0.013680656759085918, 0.0356910450154318, 0.023526343547736236, 0.035691045015431855, 0.11482570604041165]
    )
  end

  @trixi_testset "TreeMesh3D: elixir_navierstokes_convergence.jl (isothermal walls)" begin
    @test_trixi_include(joinpath(examples_dir(), "tree_3d_dgsem", "elixir_navierstokes_convergence.jl"),
      initial_refinement_level = 2, tspan=(0.0, 0.1),
      heat_bc_top_bottom=Isothermal((x, t, equations) -> Trixi.temperature(initial_condition_navier_stokes_convergence_test(x, t, equations), equations)),
      l2 = [0.00195468651965362, 0.0026554367897028506, 0.002892730402724066, 0.002655436789702817, 0.009596351796609566],
      linf = [0.013680508110645473, 0.035673446359424356, 0.024024936779729028, 0.03567344635942474, 0.11839497110809383]
    )
  end

  @trixi_testset "TreeMesh3D: elixir_navierstokes_convergence.jl (Entropy gradient variables)" begin
    @test_trixi_include(joinpath(examples_dir(), "tree_3d_dgsem", "elixir_navierstokes_convergence.jl"),
      initial_refinement_level=2, tspan=(0.0, 0.1), gradient_variables=GradientVariablesEntropy(),
      l2 = [0.0019770444875099307, 0.0026524750946399327, 0.00290860030832445, 0.0026524750946399396, 0.009509568981439294],
      linf = [0.01387936112914212, 0.03526260609304053, 0.023554197097368997, 0.035262606093040896, 0.11719963716509518]
    )
  end

  @trixi_testset "TreeMesh3D: elixir_navierstokes_convergence.jl (Entropy gradient variables, isothermal walls)" begin
    @test_trixi_include(joinpath(examples_dir(), "tree_3d_dgsem", "elixir_navierstokes_convergence.jl"),
      initial_refinement_level=2, tspan=(0.0, 0.1), gradient_variables=GradientVariablesEntropy(),
      heat_bc_top_bottom=Isothermal((x, t, equations) -> Trixi.temperature(initial_condition_navier_stokes_convergence_test(x, t, equations), equations)),
      l2 = [0.001974631423398113, 0.002654768259143932, 0.002907031063651286, 0.002654768259143901, 0.009587792882971452],
      linf = [0.01387919380137137, 0.035244084526358944, 0.02398614622061363, 0.03524408452635828, 0.12005056512506407]
    )
  end

  @trixi_testset "TreeMesh3D: elixir_navierstokes_convergence.jl (flux differencing)" begin
    @test_trixi_include(joinpath(examples_dir(), "tree_3d_dgsem", "elixir_navierstokes_convergence.jl"),
      initial_refinement_level = 2, tspan=(0.0, 0.1),
      volume_integral=VolumeIntegralFluxDifferencing(flux_central),
      l2 = [0.0019582188528180213, 0.002653449504301736, 0.0028982642051960006, 0.0026534495043017384, 0.009511572364811033],
      linf = [0.013680656758949583, 0.035691045015224444, 0.02352634354676752, 0.035691045015223424, 0.11482570603751441]
    )
  end

  @trixi_testset "TreeMesh3D: elixir_navierstokes_convergence.jl (Refined mesh)" begin
    @test_trixi_include(joinpath(examples_dir(), "tree_3d_dgsem", "elixir_navierstokes_convergence.jl"),
      tspan=(0.0, 0.0))
      LLID = Trixi.local_leaf_cells(mesh.tree)
      num_leafs = length(LLID)
      @assert num_leafs % 16 == 0
      Trixi.refine!(mesh.tree, LLID[1:Int(num_leafs/16)])
      tspan=(0.0, 1.0)
      semi = SemidiscretizationHyperbolicParabolic(mesh, (equations, equations_parabolic), initial_condition, solver;
                                             boundary_conditions=(boundary_conditions, boundary_conditions_parabolic),
                                             source_terms=source_terms_navier_stokes_convergence_test)
      ode = semidiscretize(semi, tspan)
      analysis_callback = AnalysisCallback(semi, interval=analysis_interval)
      callbacks = CallbackSet(summary_callback, alive_callback, analysis_callback)
      sol = solve(ode, RDPK3SpFSAL49(); abstol=time_int_tol, reltol=time_int_tol, dt = 1e-5,
            ode_default_options()..., callback=callbacks)
      ac_sol = analysis_callback(sol)
      @test ac_sol.l2 ≈ [0.0003991794175622818; 0.0008853745163670504; 0.0010658655552066817; 0.0008785559918324284; 0.001403163458422815]
      @test ac_sol.linf ≈ [0.0035306410538458177; 0.01505692306169911; 0.008862444161110705; 0.015065647972869856; 0.030402714743065218]
  end

  @trixi_testset "TreeMesh3D: elixir_navierstokes_taylor_green_vortex.jl" begin
    @test_trixi_include(joinpath(examples_dir(), "tree_3d_dgsem", "elixir_navierstokes_taylor_green_vortex.jl"),
      initial_refinement_level = 2, tspan=(0.0, 0.25),
      l2 = [0.00024173250389635442, 0.015684268393762454, 0.01568426839376248, 0.021991909545192333, 0.02825413672911425],
      linf = [0.0008410587892853094, 0.04740176181772552, 0.04740176181772507, 0.07483494924031157, 0.150181591534448]
    )
  end

  @trixi_testset "TreeMesh3D: elixir_navierstokes_taylor_green_vortex.jl (Refined mesh)" begin
    @test_trixi_include(joinpath(examples_dir(), "tree_3d_dgsem", "elixir_navierstokes_taylor_green_vortex.jl"),
      tspan=(0.0, 0.0))
      LLID = Trixi.local_leaf_cells(mesh.tree)
      num_leafs = length(LLID)
      @assert num_leafs % 32 == 0
      Trixi.refine!(mesh.tree, LLID[1:Int(num_leafs/32)])
      tspan=(0.0, 10.0)
      semi = SemidiscretizationHyperbolicParabolic(mesh, (equations, equations_parabolic),
                                             initial_condition, solver)
      ode = semidiscretize(semi, tspan)
      analysis_callback = AnalysisCallback(semi, interval=analysis_interval, save_analysis=true,
                                           extra_analysis_integrals=(energy_kinetic,
                                                                     energy_internal,
                                                                     enstrophy))
      callbacks = CallbackSet(summary_callback, alive_callback, analysis_callback)
      # Use CarpenterKennedy2N54 since `RDPK3SpFSAL49` gives slightly different results on different machines
      sol = solve(ode, CarpenterKennedy2N54(williamson_condition=false),
            dt=5e-3,
            save_everystep=false, callback=callbacks); 
      ac_sol = analysis_callback(sol)
      @test ac_sol.l2 ≈ [0.0013666103707729502; 0.2313581629543744; 0.2308164306264533; 0.17460246787819503; 0.28121914446544005]
      @test ac_sol.linf ≈ [0.006938093883741336; 1.028235074139312; 1.0345438209717241; 1.0821111605203542; 1.2669636522564645]

      # Ensure that we do not have excessive memory allocations 
      # (e.g., from type instabilities) 
      let 
        t = sol.t[end] 
        u_ode = sol.u[end] 
        du_ode = similar(u_ode) 
        @test (@allocated Trixi.rhs!(du_ode, u_ode, semi, t)) < 100
        @test (@allocated Trixi.rhs_parabolic!(du_ode, u_ode, semi, t)) < 100
      end
  end

  @trixi_testset "P4estMesh3D: elixir_navierstokes_convergence.jl" begin
    @test_trixi_include(joinpath(examples_dir(), "p4est_3d_dgsem", "elixir_navierstokes_convergence.jl"),
      initial_refinement_level = 2, tspan=(0.0, 0.1),
      l2 = [0.00026599105554982194, 0.000461877794472316, 0.0005424899076052261, 0.0004618777944723191, 0.0015846392581126832], 
      linf = [0.0025241668929956163, 0.006308461681816373, 0.004334939663169113, 0.006308461681804009, 0.03176343480493493]
    )
  end

  @trixi_testset "P4estMesh3D: elixir_navierstokes_taylor_green_vortex.jl" begin
    @test_trixi_include(joinpath(examples_dir(), "p4est_3d_dgsem", "elixir_navierstokes_taylor_green_vortex.jl"),
      initial_refinement_level = 2, tspan=(0.0, 0.25),
      l2 = [0.0001547509861140407, 0.015637861347119624, 0.015637861347119687, 0.022024699158522523, 0.009711013505930812], 
      linf = [0.0006696415247340326, 0.03442565722527785, 0.03442565722577423, 0.06295407168705314, 0.032857472756916195]
    )
  end
end

# Clean up afterwards: delete Trixi.jl output directory
@test_nowarn isdir(outdir) && rm(outdir, recursive=true)

end # module