#--------------------------------------------------------
# external packages
#--------------------------------------------------------
using Crayons.Box
using DifferentialEquations
using Gridap
using GridapGmsh
using MPI
using Revise
using WriteVTK

#Plots
using Plots; gr()
plotlyjs()

#Constants
const TInt   = Int64
const TFloat = Float64

#--------------------------------------------------------
# jexpresso modules
#--------------------------------------------------------
include("./IO/mod_inputs.jl")
include("./Mesh/mod_mesh.jl")
include("./basis/basis_structs.jl")
include("./Infrastructure/Kopriva_functions.jl")
include("./Infrastructure/2D_3D_structures.jl")
include("./mass_matrix.jl")
include("../tests/plot_lagrange_polynomial.jl")
#--------------------------------------------------------

struct EDGES <:At_geo_entity end
struct FACES <:At_geo_entity end
#MPI.Init()
#comm = MPI.COMM_WORLD

#if MPI.Comm_rank(comm) == 0
mod_inputs_print_welcome()

#--------------------------------------------------------
#User inputs:
#--------------------------------------------------------
inputs        = Dict{}()
inputs, nvars = mod_inputs_user_inputs()

#--------------------------------------------------------
# Create/read mesh
#--------------------------------------------------------
mod_mesh_mesh_driver(inputs)


#--------------------------------------------------------
# Problem setup
#--------------------------------------------------------
N = 1

exact_quadrature = false

P1  = LGL1D()
P2  = CGL1D()
T1  = NodalGalerkin()
T2  = Collocation()

#--------------------------------------------------------
# Build interpolation nodes:
#             the user decides among LGL, GL, etc. 
# Return:
# ξ = ND.ξ.ξ
# ω = ND.ξ.ω
#--------------------------------------------------------
#Interpolation points
ND = build_nodal_Storage([N],P1,T1) # --> ξ <- ND.ξ.ξ
ξ  = ND.ξ.ξ

if exact_quadrature    
    #
    # Exact quadrature:
    # Quadrature order (Q = N+1) ≠ polynomial order (N)
    #
    TP  = Exact()
    Q   = N + 1
    NDq = build_nodal_Storage([Q],P1,T1) # --> ξ <- ND.ξ.ξ
    ξq  = NDq.ξ.ξ
    ω   = NDq.ξ.ω
    
else  
    #
    # Inexact quadrature:
    # Quadrature and interpolation orders coincide (Q = N)
    #
    TP  = Inexact()
    Q   = N
    NDq = ND
    ξq  = ξ
    ω   = ND.ξ.ω
end



#--------------------------------------------------------
# Build Lagrange polynomials:
#
# Return:
# ψ     = basis.ψ[N+1, Q+1]
# dψ/dξ = basis.dψ[N+1, Q+1]
#--------------------------------------------------------
ξr    = ξq #range(-1, 1, length=100) #Used for plotting purposes only
basis = build_Interpolation_basis!(LagrangeBasis(), ξ, ξq, TFloat)
#plot_basis(basis.ψ, ξ, ξr)


M = build_element_matrices!(TP, basis.ψ, ω, 1, N, Q, TFloat)



#ElementMassMatrix(Int64(inputs[:nop]), Int64(inputs[:nop]), MassMatrix1D(), Float64)
