module DgSolver

include("interpolation.jl")
include("dg_containers.jl")

using ...Trixi
using ..Solvers # Use everything to allow method extension via "function <parent_module>.<method>"
using ...Equations: AbstractEquation, initial_conditions, calcflux!, riemann!, sources, calc_max_dt
import ...Equations: nvariables # Import to allow method extension
using ...Auxiliary: timer
using ...Mesh: TreeMesh
using ...Mesh.Trees: leaf_cells, length_at_cell, n_directions, has_neighbor,
                     opposite_direction, has_coarse_neighbor, has_child
using .Interpolation: interpolate_nodes, calc_dhat,
                      polynomial_interpolation_matrix, calc_lhat, gauss_lobatto_nodes_weights
using StaticArrays: SVector, SMatrix, MMatrix
using TimerOutputs: @timeit
using Printf: @sprintf, @printf

export Dg
export set_initial_conditions
export nvariables
export equations
export polydeg
export rhs!
export calc_dt
export calc_error_norms
export analyze_solution


# Main DG data structure that contains all relevant data for the DG solver
struct Dg{Eqn <: AbstractEquation, V, N, Np1, NAna, NAnap1} <: AbstractSolver
  equations::Eqn
  elements::ElementContainer{V, N}
  n_elements::Int

  surfaces::SurfaceContainer{V, N}
  n_surfaces::Int

  nodes::SVector{Np1}
  weights::SVector{Np1}
  dhat::SMatrix{Np1, Np1}
  lhat::SMatrix{Np1, 2}

  analysis_nodes::SVector{NAnap1}
  analysis_weights::SVector{NAnap1}
  analysis_weights_volume::SVector{NAnap1}
  analysis_vandermonde::SMatrix{NAnap1, Np1}
  analysis_total_volume::Float64
end


# Convenience constructor to create DG solver instance
function Dg(equation::AbstractEquation{V}, mesh::TreeMesh, N::Int) where V
  # Get cells for which an element needs to be created (i.e., all leaf cells)
  leaf_cell_ids = leaf_cells(mesh.tree)
  n_elements = length(leaf_cell_ids)

  # Initialize elements
  elements = ElementContainer{V, N}(n_elements)
  elements.cell_ids .= leaf_cell_ids

  # Initialize surfaces
  n_surfaces = count_required_surfaces(mesh, leaf_cell_ids)
  @assert n_surfaces == n_elements "In 1D and periodic domains, n_surf must be the same as n_elem"
  surfaces = SurfaceContainer{V, N}(n_surfaces)

  # Connect surfaces and elements
  init_connectivity!(elements, surfaces, mesh)

  # Initialize interpolation data structures
  nodes, weights = gauss_lobatto_nodes_weights(N + 1)
  dhat = calc_dhat(nodes, weights)
  lhat = zeros(N + 1, 2)
  lhat[:, 1] = calc_lhat(-1.0, nodes, weights)
  lhat[:, 2] = calc_lhat( 1.0, nodes, weights)

  # Initialize data structures for error analysis (by default, we use twice the
  # number of analysis nodes as the normal solution)
  NAna = 2 * (N + 1) - 1
  analysis_nodes, analysis_weights = gauss_lobatto_nodes_weights(NAna + 1)
  analysis_weights_volume = analysis_weights
  analysis_vandermonde = polynomial_interpolation_matrix(nodes, analysis_nodes)
  analysis_total_volume = sum(mesh.tree.length_level_0.^ndim)

  # Create actual DG solver instance
  dg = Dg{typeof(equation), V, N, N + 1, NAna, NAna + 1}(
      equation, elements, n_elements, surfaces, n_surfaces, nodes, weights,
      dhat, lhat, analysis_nodes, analysis_weights, analysis_weights_volume,
      analysis_vandermonde, analysis_total_volume)

  # Calculate inverse Jacobian and node coordinates
  for element_id in 1:n_elements
    cell_id = leaf_cell_ids[element_id]
    dx = length_at_cell(mesh.tree, cell_id)
    dg.elements.inverse_jacobian[element_id] = 2/dx
    dg.elements.node_coordinates[:, element_id] = (
        @. mesh.tree.coordinates[1, cell_id] + dx/2 * nodes[:])
  end

  return dg
end


# Return polynomial degree for a DG solver
@inline polydeg(::Dg{Eqn, N}) where {Eqn, N} = N


# Return number of nodes in one direction
@inline nnodes(::Dg{Eqn, N}) where {Eqn, N} = N + 1


# Return system of equations instance for a DG solver
@inline Solvers.equations(dg::Dg) = dg.equations


# Return number of variables for the system of equations in use
@inline nvariables(dg::Dg) = nvariables(equations(dg))


# Return number of degrees of freedom
@inline Solvers.ndofs(dg::Dg) = dg.n_elements * (polydeg(dg) + 1)^ndim


# Count the number of surfaces that need to be created
# FIXME: This is currently (for 1D) overkill, but should serve as a blueprint
# for an extension to 2D
function count_required_surfaces(mesh::TreeMesh, cell_ids)
  count = 0

  # Iterate over all cells
  for cell_id in cell_ids
    for dir in 1:n_directions(mesh.tree)
      # Only count surfaces in positive direction to avoid double counting
      if dir % 2 == 0
        count += 1
        continue
      end
    end
  end

  return count
end


# Initialize connectivity between elements and surfaces
# FIXME: This is currently (for 1D) overkill, but should serve as a blueprint
# for an extension to 2D
function init_connectivity!(elements, surfaces, mesh)
  # Construct cell -> element mapping for easier algorithm implementation
  tree = mesh.tree
  c2e = zeros(Int, length(tree))
  for element_id in 1:nelements(elements)
    c2e[elements.cell_ids[element_id]] = element_id
  end

  # Reset surface count
  count = 0

  # Iterate over all elements to find neighbors and to connect via surfaces
  for element_id in 1:nelements(elements)
    # Get cell id
    cell_id = elements.cell_ids[element_id]

    # Find neighbor cell in positive x-direction
    direction = 2
    if has_neighbor(tree, cell_id, direction)
      # Find direct neighbor
      neighbor_cell_id = tree.neighbor_ids[direction, cell_id]

      # Check if neighbor has children - if yes, find appropriate child neighbor
      if has_child(tree, neighbor_cell_id, opposite_direction(direction))
        neighbor_cell_id = tree.child_ids[opposite_direction(direction), neighbor_cell_id]
      end
    elseif has_coarse_neighbor(tree, cell_id, direction)
      neighbor_cell_id = tree.neighbor_ids[direction, tree.parent_ids[cell_id]]
    else
      error("this cannot happen in 1D with periodic BCs")
    end

    # Create surface between elements
    count += 1
    surfaces.neighbor_ids[direction, count] = c2e[neighbor_cell_id]
    surfaces.neighbor_ids[opposite_direction(direction), count] = element_id

    # Set surface ids in elements
    elements.surface_ids[direction, element_id] = count
    elements.surface_ids[opposite_direction(direction), c2e[neighbor_cell_id]] = count
  end

  @assert count == nsurfaces(surfaces) "Actual surface count does not match expectations"
end


# Calculate L2/Linf error norms based on "exact solution"
function calc_error_norms(dg::Dg, t::Float64)
  # Gather necessary information
  equation = equations(dg)
  n_nodes_analysis = length(dg.analysis_nodes)

  # Set up data structures
  l2_error = zeros(nvariables(equation))
  linf_error = zeros(nvariables(equation))
  u_exact = zeros(nvariables(equation))

  # Iterate over all elements for error calculations
  for element_id = 1:dg.n_elements
    # Interpolate solution and node locations to analysis nodes
    u = interpolate_nodes(dg.elements.u[:, :, element_id],
                          dg.analysis_vandermonde, nvariables(equation))
    x = interpolate_nodes(reshape(dg.elements.node_coordinates[:, element_id], 1, :),
                          dg.analysis_vandermonde, 1)

    # Calculate errors at each analysis node
    jacobian = (1 / dg.elements.inverse_jacobian[element_id])^ndim
    for i = 1:n_nodes_analysis
      u_exact = initial_conditions(equation, x[i], t)
      diff = similar(u_exact)
      @. diff = u_exact - u[:, i]
      @. l2_error += diff^2 * dg.analysis_weights_volume[i] * jacobian
      @. linf_error = max(linf_error, abs(diff))
    end
  end

  # For L2 error, divide by total volume
  @. l2_error = sqrt(l2_error / dg.analysis_total_volume)

  return l2_error, linf_error
end


# Calculate error norms and print information for user
function Solvers.analyze_solution(dg::Dg{Eqn, N}, time::Real, dt::Real,
                                  step::Integer, runtime_absolute::Real,
  runtime_relative::Real) where {Eqn, N}
  equation = equations(dg)

  l2_error, linf_error = calc_error_norms(dg, time)

  println()
  println("-"^80)
  println(" Simulation running '$(equation.name)' with N = $N")
  println("-"^80)
  println(" #timesteps:    " * @sprintf("% 14d", step))
  println(" dt:            " * @sprintf("%10.8e", dt))
  println(" sim. time:     " * @sprintf("%10.8e", time))
  println(" run time:      " * @sprintf("%10.8e s", runtime_absolute))
  println(" Time/DOF/step: " * @sprintf("%10.8e s", runtime_relative))
  print(" Variable:    ")
  for v in 1:nvariables(equation)
    @printf("  %-14s", equation.varnames_cons[v])
  end
  println()
  print(" L2 error:    ")
  for v in 1:nvariables(equation)
    @printf("  %10.8e", l2_error[v])
  end
  println()
  print(" Linf error:  ")
  for v in 1:nvariables(equation)
    @printf("  %10.8e", linf_error[v])
  end
  println()
  println()
end


# Call equation-specific initial conditions functions and apply to all elements
function Solvers.set_initial_conditions(dg::Dg, time::Float64)
  equation = equations(dg)

  for element_id = 1:dg.n_elements
    for i = 1:(polydeg(dg) + 1)
      dg.elements.u[:, i, element_id] .= initial_conditions(
          equation, dg.elements.node_coordinates[i, element_id], time)
    end
  end
end


# Calculate time derivative
function Solvers.rhs!(dg::Dg, t_stage)
  # Reset u_t
  @timeit timer() "reset ∂u/∂t" dg.elements.u_t .= 0.0

  # Calculate volume flux
  @timeit timer() "volume flux" calc_volume_flux!(dg)

  # Calculate volume integral
  @timeit timer() "volume integral" calc_volume_integral!(dg, dg.elements.u_t,
                                                          dg.dhat, dg.elements.flux)

  # Prolong solution to surfaces
  @timeit timer() "prolong2surfaces" prolong2surfaces!(dg)

  # Calculate surface fluxes
  @timeit timer() "surface flux" calc_surface_flux!(dg.surfaces.flux, dg.surfaces.u, dg)

  # Calculate surface integrals
  @timeit timer() "surface integral" calc_surface_integral!(dg, dg.elements.u_t, dg.surfaces.flux, 
                                                            dg.lhat, dg.elements.surface_ids)

  # Apply Jacobian from mapping to reference element
  @timeit timer() "Jacobian" apply_jacobian!(dg)

  # Calculate source terms
  @timeit timer() "source terms" calc_sources!(dg, t_stage)
end


# Calculate and store volume fluxes
function calc_volume_flux!(dg)
  N = polydeg(dg)
  equation = equations(dg)

  @inbounds Threads.@threads for element_id = 1:dg.n_elements
     @views calcflux!(dg.elements.flux[:, :, element_id], equation,
                      dg.elements.u, element_id, nnodes(dg))
  end
end


# Calculate volume integral and update u_t
function calc_volume_integral!(dg, u_t::Array{Float64, 3}, dhat::SMatrix, flux::Array{Float64, 3})
  @inbounds Threads.@threads for element_id = 1:dg.n_elements
    for i = 1:nnodes(dg)
      for v = 1:nvariables(dg)
        for j = 1:nnodes(dg)
          u_t[v, i, element_id] += dhat[i, j] * flux[v, j, element_id]
        end
      end
    end
  end
end


# Prolong solution to surfaces (for GL nodes: just a copy)
function prolong2surfaces!(dg)
  equation = equations(dg)

  for s = 1:dg.n_surfaces
    left = dg.surfaces.neighbor_ids[1, s]
    right = dg.surfaces.neighbor_ids[2, s]
    for v = 1:nvariables(dg)
      dg.surfaces.u[1, v, s] = dg.elements.u[v, nnodes(dg), left]
      dg.surfaces.u[2, v, s] = dg.elements.u[v, 1, right]
    end
  end
end


# Calculate and store fluxes across surfaces
function calc_surface_flux!(flux_surfaces::Array{Float64, 2}, u_surfaces::Array{Float64, 3}, dg)
  @inbounds Threads.@threads for surface_id = 1:dg.n_surfaces
    riemann!(flux_surfaces, u_surfaces, surface_id, equations(dg), nnodes(dg))
  end
end


# Calculate surface integrals and update u_t
function calc_surface_integral!(dg, u_t::Array{Float64, 3}, flux_surfaces::Array{Float64, 2},
                                lhat::SMatrix, surface_ids::Array{Int, 2})
  for element_id = 1:dg.n_elements
    left = surface_ids[1, element_id]
    right = surface_ids[2, element_id]

    for v = 1:nvariables(dg)
      u_t[v, 1,          element_id] -= flux_surfaces[v, left ] * lhat[1,          1]
      u_t[v, nnodes(dg), element_id] += flux_surfaces[v, right] * lhat[nnodes(dg), 2]
    end
  end
end


# Apply Jacobian from mapping to reference element
function apply_jacobian!(dg)
  for element_id = 1:dg.n_elements
    for i = 1:nnodes(dg)
      for v = 1:nvariables(dg)
        dg.elements.u_t[v, i, element_id] *= -dg.elements.inverse_jacobian[element_id]
      end
    end
  end
end


# Calculate source terms and apply them to u_t
function calc_sources!(dg::Dg, t)
  equation = equations(dg)
  if equation.sources == "none"
    return
  end

  for element_id = 1:dg.n_elements
    sources(equations(dg), dg.elements.u_t, dg.elements.u,
            dg.elements.node_coordinates, element_id, t, nnodes(dg))
  end
end


# Calculate stable time step size
function Solvers.calc_dt(dg::Dg, cfl)
  min_dt = Inf
  for element_id = 1:dg.n_elements
    dt = calc_max_dt(equations(dg), dg.elements.u, element_id, nnodes(dg),
                     dg.elements.inverse_jacobian[element_id], cfl)
    min_dt = min(min_dt, dt)
  end

  return min_dt
end

end # module
