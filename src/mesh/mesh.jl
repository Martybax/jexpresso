using Test
using DelimitedFiles
using DataStructures
using Gridap
using Gridap.Arrays
using Gridap.Arrays: Table
using Gridap.Geometry
using Gridap.Fields
using Gridap.ReferenceFEs
using Gridap.CellData
using Gridap.Geometry: GridMock
using GridapGmsh
using LinearAlgebra
using UnicodePlots
using Printf
using Revise
using ElasticArrays
using StaticArrays

export St_mesh
export mod_mesh_mesh_driver
export mod_mesh_build_mesh!
export mod_mesh_read_gmsh!

const VERTEX_NODES = UInt64(1)
const EDGE_NODES   = UInt64(2)
const FACE_NODES   = UInt64(4)


abstract type AbstractSpaceDimensions end
struct NSD_1D <: AbstractSpaceDimensions end
struct NSD_2D <: AbstractSpaceDimensions end
struct NSD_3D <: AbstractSpaceDimensions end

#abstract type At_geo_entity end

include("../basis/basis_structs.jl")
include("../NodeRenumbering/src/create_adjacency_graph.jl")
include("../NodeRenumbering/src/node_degrees.jl")
include("../NodeRenumbering/src/RCM.jl")
include("../NodeRenumbering/src/renumbering.jl")
include("../NodeRenumbering/src/create_RCM_adjacency.jl")
include("../NodeRenumbering/src/adjacency_visualization.jl")


Base.@kwdef mutable struct St_mesh{TInt, TFloat}
    
    x::Union{Array{TFloat}, Missing} = zeros(2)
    y::Union{Array{TFloat}, Missing} = zeros(2)
    z::Union{Array{TFloat}, Missing} = zeros(2)
    
    x_ho::Union{Array{TFloat}, Missing} = zeros(2)
    y_ho::Union{Array{TFloat}, Missing} = zeros(2)
    z_ho::Union{Array{TFloat}, Missing} = zeros(2)

    Δx::Union{Array{TFloat}, Missing} = zeros(2)
    Δy::Union{Array{TFloat}, Missing} = zeros(2)
    Δz::Union{Array{TFloat}, Missing} = zeros(2)
    
    xmin::Union{TFloat, Missing} = -1.0;
    xmax::Union{TFloat, Missing} = +1.0;
    
    ymin::Union{TFloat, Missing} = -1.0;
    ymax::Union{TFloat, Missing} = +1.0;

    zmin::Union{TFloat, Missing} = -1.0;
    zmax::Union{TFloat, Missing} = +1.0;
    
    npx::Union{TInt, Missing} = 1
    npy::Union{TInt, Missing} = 1
    npz::Union{TInt, Missing} = 1
    
    nelem::Union{TInt, Missing} = 1
    npoin::Union{TInt, Missing} = 1        # This is updated after populating with high-order nodes
    npoin_linear::Union{TInt, Missing} = 1 # This is always the original number of the first-order grid

    nedges::Union{TInt, Missing} = 1       # total number of edges
    nedges_bdy::Union{TInt, Missing} = 1   # bdy edges
    nedges_int::Union{TInt, Missing} = 1   # internal edges

    nfaces::Union{TInt, Missing} = 1       # total number of faces
    nfaces_bdy::Union{TInt, Missing} = 1   # bdy faces
    nfaces_int::Union{TInt, Missing} = 1   # internal faces
    
    nsd::Union{TInt, Missing} = 1
    nop::Union{TInt, Missing} = 4
    ngl::Union{TInt, Missing} = nop + 1
    npoin_el::Union{TInt, Missing} = 1     # Total number of points in the reference element
    
    NNODES_EL::Union{TInt, Missing}  =  2^nsd
    NEDGES_EL::Union{TInt, Missing}  = 12
    NFACES_EL::Union{TInt, Missing}  =  6
    EDGE_NODES::Union{TInt, Missing} =  2
    FACE_NODES::Union{TInt, Missing} =  4

    
    #low and high order connectivity tables
    cell_node_ids::Table{Int64,Vector{Int64},Vector{Int64}}    = Gridap.Arrays.Table(zeros(nelem), zeros(1))
    cell_node_ids_ho::Table{Int64,Vector{Int64},Vector{Int64}} = Gridap.Arrays.Table(zeros(nelem), zeros(1))
    cell_edge_ids::Table{Int64,Vector{Int64},Vector{Int64}}    = Gridap.Arrays.Table(zeros(nelem), zeros(1))
    cell_face_ids::Table{Int64,Vector{Int64},Vector{Int64}}    = Gridap.Arrays.Table(zeros(nelem), zeros(1))

    #conn              = ElasticArray{Int64}(undef, ngl*nelem)
    connijk           = Array{Int64}(undef, 0)
    conn              = Array{Int64}(undef, 0)
    conn_unique_edges = ElasticArray{Int64}(undef,  1, 2)
    conn_unique_faces = ElasticArray{Int64}(undef,  1, 4)

    conn_edge_el      = Array{Int64}(undef, 0,0,0)
    conn_face_el      = Array{Int64}(undef, 0,0,0)
    face_in_elem      = Array{Int64}(undef, 0,0,0)
    
end

function mod_mesh_read_gmsh!(mesh::St_mesh, gmsh_filename::String)

    #
    # Read GMSH grid from file
    #
    model    = GmshDiscreteModel(gmsh_filename, renumber=true)
    topology = get_grid_topology(model)
    mesh.nsd = num_cell_dims(model)
    
    d_to_num_dfaces = [num_vertices(model), num_edges(model), num_cells(model)]
    #@show labels = FaceLabeling(d_to_num_dfaces)
    #@show get_face_entity(labels,0) .= get_isboundary_face(model,0) .+ 1
    #@show get_face_entity(labels,1) .= get_isboundary_face(model,1) .+ 1
    #@show get_face_entity(labels,2) .= get_isboundary_face(model,2) .+ 1
    
    POIN_flg = 0
    EDGE_flg = 1
    FACE_flg = 2
    ELEM_flg = 3
    
    if mesh.nsd == 3
        SD = NSD_3D()

        mesh.NNODES_EL  = 8
        mesh.NEDGES_EL  = 12
        mesh.NFACES_EL  = 6
        mesh.EDGE_NODES = 2
        mesh.FACE_NODES = 4
    elseif mesh.nsd == 2

        SD = NSD_2D()
        ELEM_flg = FACE_flg
        
        mesh.NNODES_EL  = 4
        mesh.NEDGES_EL  = 4
        mesh.NFACES_EL  = 1
        mesh.EDGE_NODES = 2
        mesh.FACE_NODES = 4
    elseif mesh.nsd == 1
        SD = NSD_1D()

        mesh.NNODES_EL  = 2
        mesh.NEDGES_EL  = 1
        mesh.NFACES_EL  = 0
        mesh.EDGE_NODES = 2
        mesh.FACE_NODES = 0
    else
        error( " WRONG NSD: This is not theoretical physics: we only handle 1, 2, or 3 dimensions!")
    end
    
    #dump(topology)
    #
    # Mesh elements, nodes, faces, edges
    #
    mesh.npoin_linear = num_faces(model,POIN_flg)    
    mesh.npoin        = mesh.npoin_linear     #This will be updated for the high order grid
    mesh.nedges       = num_faces(model,EDGE_flg)
    mesh.nfaces       = num_faces(model,FACE_flg)   
    mesh.nelem        = num_faces(model,ELEM_flg)
        
    mesh.nfaces_bdy   = count(get_isboundary_face(topology,mesh.nsd-1))
    mesh.nfaces_int   = mesh.nfaces - mesh.nfaces_bdy
    mesh.nedges_bdy   = count(get_isboundary_face(topology,mesh.nsd-2))
    mesh.nedges_int   = mesh.nedges - mesh.nedges_bdy
    
    println(" # GMSH LINEAR GRID PROPERTIES")
    println(" # N. elements       : ", mesh.nelem)
    println(" # N. points         : ", mesh.npoin_linear)
    println(" # N. edges          : ", mesh.nedges)
    println(" # N. internal edges : ", mesh.nedges_int)
    println(" # N. boundary edges : ", mesh.nedges_bdy)
    println(" # N. faces          : ", mesh.nfaces) 
    println(" # N. internal faces : ", mesh.nfaces_int)
    println(" # N. boundary faces : ", mesh.nfaces_bdy)
    println(" # GMSH LINEAR GRID PROPERTIES ...................... END")
    
    ngl                     = mesh.nop + 1
    tot_linear_poin         = mesh.npoin_linear
    
    tot_edges_internal_nodes = mesh.nedges*(ngl-2)
    tot_faces_internal_nodes = mesh.nfaces*(ngl-2)*(ngl-2)
    tot_vol_internal_nodes   = mesh.nelem*(ngl-2)^(mesh.nsd)
    
    el_edges_internal_nodes = mesh.NEDGES_EL*(ngl-2)
    el_faces_internal_nodes = mesh.NFACES_EL*(ngl-2)^(ngl-2)
    el_vol_internal_nodes   = (ngl-2)^(mesh.nsd)
    
    #Update number of grid points from linear count to total high-order points
    mesh.npoin = tot_linear_poin + tot_edges_internal_nodes + tot_faces_internal_nodes + (mesh.nsd - 2)*tot_vol_internal_nodes
    
    if (mesh.nop > 1)
        println(" # GMSH HIGH-ORDER GRID PROPERTIES")
        println(" # N. edges internal points   : ", tot_edges_internal_nodes)
        println(" # N. faces internal points   : ", tot_faces_internal_nodes)
        println(" # N. volumes internal points : ", tot_vol_internal_nodes)
        println(" # N. total high order points : ", mesh.npoin)
        println(" # GMSH HIGH-ORDER GRID PROPERTIES ...................... END")
    end
    
    #
    # Resize (using resize! from ElasticArrays) as needed
    # 
    resize!(mesh.x, (mesh.npoin_linear))
    resize!(mesh.y, (mesh.npoin_linear))
    resize!(mesh.z, (mesh.npoin_linear))

    mesh.conn_edge_el = Array{Int64}(undef, 2, mesh.NEDGES_EL, mesh.nelem)
    mesh.conn_face_el = Array{Int64}(undef, 4, mesh.NFACES_EL, mesh.nelem)
    mesh.face_in_elem = Array{Int64}(undef, 2, mesh.NFACES_EL, mesh.nelem)
    
    mesh.npoin_el = mesh.NNODES_EL + el_edges_internal_nodes + el_faces_internal_nodes + (mesh.nsd - 2)*el_vol_internal_nodes

    mesh.conn = Array{Int64}(undef, mesh.npoin_el, mesh.nelem)
    #@info mesh.npoin mesh.npoin_el
    
    #
    # Connectivity matrices
    #
    mesh.cell_node_ids     = model.grid.cell_node_ids
    mesh.conn_unique_faces = get_face_nodes(model, FACE_flg) #faces --> 4 nodes
    mesh.conn_unique_edges = get_face_nodes(model, EDGE_flg) #edges --> 2 nodes

    mesh.cell_edge_ids     = get_faces(topology, mesh.nsd, 1) #edge map from local to global numbering i.e. iedge_g = cell_edge_ids[1:NELEM][1:NEDGES_EL]
    mesh.cell_face_ids     = get_faces(topology, mesh.nsd, mesh.nsd-1) #face map from local to global numbering i.e. iface_g = cell_face_ids[1:NELEM][1:NFACE_EL]

    #show(stdout, "text/plain",  mesh.conn_unique_faces)
    #show(stdout, "text/plain",  mesh.conn_unique_edges)
    
    if (mesh.nsd == 1)
        nothing
    elseif (mesh.nsd == 2)
        
        mesh.connijk = Array{Int64}(undef, mesh.ngl, mesh.ngl, mesh.nelem)
        for iel = 1:mesh.nelem
            mesh.conn[1, iel] = mesh.cell_node_ids[iel][1]
            mesh.conn[2, iel] = mesh.cell_node_ids[iel][2]
            mesh.conn[3, iel] = mesh.cell_node_ids[iel][4]
            mesh.conn[4, iel] = mesh.cell_node_ids[iel][3]
            
            mesh.connijk[1,  ngl, iel] = mesh.cell_node_ids[iel][1]
            mesh.connijk[1,    1, iel] = mesh.cell_node_ids[iel][2]
            mesh.connijk[ngl,  1, iel] = mesh.cell_node_ids[iel][3]
            mesh.connijk[ngl,ngl, iel] = mesh.cell_node_ids[iel][4]
        end
         
        #Fill in elements dictionary needed by NodeOrdering.jl
        elements = Dict(
            kk => mesh.conn[1:4, kk]
            for kk = 1:mesh.nelem)
        element_types = Dict(
            kk => :Quad4
            for kk = 1:mesh.nelem)
        #@info elements
        #@info element_types

        original_grid_adj = Dict{Int, Vector{Int}}(
            1 => [5, 8],
            2 => [5, 6],
            3 => [6, 7],
            4 => [7, 8],
            5 => [1, 2, 10],
            6 => [2, 3, 11],
            7 => [3, 4, 11],
            8 => [1, 4, 10],
            9 => [2, 4, 10, 11],
            10 => [5, 8, 9],
            11 => [6, 7, 9]
        )
       #= original_grid_adj = Dict{Int, Vector{Int}}(
                       7 => [5, 6, 9],
                       9 => [7, 8],
                       4 => [2, 6],
                       2 => [4, 3, 1],
                       3 => [5, 6, 2, 1],
                       8 => [6, 9],
                       5 => [7, 3],
                       6 => [7, 3, 8, 4],
                       1 => [3, 2]);=#
        testmat = adjacency_visualization(original_grid_adj)
        display(UnicodePlots.heatmap(testmat))
        error(" SIAMP QUI")
        
        adjacency = create_adjacency_graph(elements, element_types)
        degrees = node_degrees(adjacency)
        neworder = RCM(adjacency, degrees, tot_linear_poin, tot_linear_poin)
        finalorder = renumbering(neworder)
        RCM_adjacency = create_RCM_adjacency(adjacency, finalorder)
        newmatrix = adjacency_visualization(RCM_adjacency)
        display(UnicodePlots.heatmap(newmatrix))
        error(" SIAMP QUI")
        
        for ip = 1:mesh.npoin_linear
            mesh.x[ip] = model.grid.node_coordinates[ip][1]
            mesh.y[ip] = model.grid.node_coordinates[ip][2]
            @printf(" %.6f %.6f  %d\n", mesh.x[ip],  mesh.y[ip], ip)
        end
        open("./COORDS_LO.dat", "w") do f
            for ip = 1:mesh.npoin_linear
                mesh.x[ip] = model.grid.node_coordinates[ip][1]
                mesh.y[ip] = model.grid.node_coordinates[ip][2]
                @printf(f, " %.6f %.6f 0.000000 %d\n", mesh.x[ip],  mesh.y[ip], ip)
            end
        end #f
    elseif (mesh.nsd == 3)
        mesh.connijk = Array{Int64}(undef, mesh.ngl, mesh.ngl, mesh.ngl, mesh.nelem)
        for iel = 1:mesh.nelem
            mesh.conn[1, iel] = mesh.cell_node_ids[iel][2]
            mesh.conn[2, iel] = mesh.cell_node_ids[iel][6]
            mesh.conn[3, iel] = mesh.cell_node_ids[iel][8]
            mesh.conn[4, iel] = mesh.cell_node_ids[iel][4]
            mesh.conn[5, iel] = mesh.cell_node_ids[iel][1]
            mesh.conn[6, iel] = mesh.cell_node_ids[iel][5]
            mesh.conn[7, iel] = mesh.cell_node_ids[iel][7]
            mesh.conn[8, iel] = mesh.cell_node_ids[iel][3]
        end
        
        #Fill in elements dictionary needed by NodeOrdering.jl
        elements = Dict(
            kk => mesh.conn[1:8, kk]
            for kk = 1:mesh.nelem)
        element_types = Dict(
            kk => :Hexa8
            for kk = 1:mesh.nelem)
       
        open("./COORDS_LO.dat", "w") do f
            for ip = 1:mesh.npoin_linear
                mesh.x[ip] = model.grid.node_coordinates[ip][1]
                mesh.y[ip] = model.grid.node_coordinates[ip][2]
                mesh.z[ip] = model.grid.node_coordinates[ip][3]
                @printf(f, " %.6f %.6f %.6f %d\n", mesh.x[ip],  mesh.y[ip], mesh.z[ip], ip)
            end
        end #f
    end

error(" STOP here MESH.jl")
    
#
# Add high-order points to edges, faces, and elements (volumes)
#
# initialize LGL struct and buyild Gauss-Lobatto-xxx points
Legendre = St_Legendre{Float64}(0.0, 0.0, 0.0, 0.0)
lgl      = St_lgl{Float64}(zeros(mesh.nop+1),
                           zeros(mesh.nop+1))
build_lgl!(Legendre, lgl, mesh.nop)


println(" # POPULATE GRID with SPECTRAL NODES ............................ ")
#
# Edges
#
populate_conn_edge_el!(mesh, SD)
@time add_high_order_nodes_edges1!(mesh, lgl, SD)
error("QUO")
#
# Faces
#
populate_conn_face_el!(mesh, SD)
@time add_high_order_nodes_faces!(mesh, lgl, SD)

#
# Volume
#
# NOTICE: in 2D we consider only edges and 2D faces
#         
@time add_high_order_nodes_volumes!(mesh, lgl, SD)

show(stdout, "text/plain", mesh.conn')
println(" # POPULATE GRID with SPECTRAL NODES ............................ DONE")

#writevtk(model,"gmsh_grid")
end


function populate_conn_edge_el!(mesh::St_mesh, SD::NSD_2D)
    
    for iel = 1:mesh.nelem

        #
        # CGNS numbering
        #
       @show ip1 = mesh.cell_node_ids[iel][4]
       @show ip2 = mesh.cell_node_ids[iel][3]
       @show ip3 = mesh.cell_node_ids[iel][1]
       @show ip4 = mesh.cell_node_ids[iel][2]
        
	# Edges bottom face:
	@show iedg_el = 1
        @show mesh.conn_edge_el[1, iedg_el, iel] = ip1
	@show mesh.conn_edge_el[2, iedg_el, iel] = ip2
	@show iedg_el = 2
	@show mesh.conn_edge_el[1, iedg_el, iel] = ip2
	@show mesh.conn_edge_el[2, iedg_el, iel] = ip3
	@show iedg_el = 3
	@show mesh.conn_edge_el[1, iedg_el, iel] = ip3
	@show mesh.conn_edge_el[2, iedg_el, iel] = ip4
	@show iedg_el = 4
	@show mesh.conn_edge_el[1, iedg_el, iel] = ip4
	@show mesh.conn_edge_el[2, iedg_el, iel] = ip1
        
    end
    
end #populate_edge_el!

function populate_conn_edge_el!(mesh::St_mesh, SD::NSD_3D)
    
    for iel = 1:mesh.nelem

        #
        # CGNS numbering
        #
        ip1 = mesh.cell_node_ids[iel][2]
        ip2 = mesh.cell_node_ids[iel][6]
        ip3 = mesh.cell_node_ids[iel][8]
        ip4 = mesh.cell_node_ids[iel][4]
        ip5 = mesh.cell_node_ids[iel][1]
        ip6 = mesh.cell_node_ids[iel][5]
        ip7 = mesh.cell_node_ids[iel][7]
        ip8 = mesh.cell_node_ids[iel][3]
        
	# Edges bottom face:
	iedg_el = 1
        mesh.conn_edge_el[1, iedg_el, iel] = ip1
	mesh.conn_edge_el[2, iedg_el, iel] = ip2
	iedg_el = 2
	mesh.conn_edge_el[1, iedg_el, iel] = ip2
	mesh.conn_edge_el[2, iedg_el, iel] = ip3
	iedg_el = 3
	mesh.conn_edge_el[1, iedg_el, iel] = ip3
	mesh.conn_edge_el[2, iedg_el, iel] = ip4
	iedg_el = 4
	mesh.conn_edge_el[1, iedg_el, iel] = ip4
	mesh.conn_edge_el[2, iedg_el, iel] = ip1

	#Vertical edges
	iedg_el = 5
	mesh.conn_edge_el[1, iedg_el, iel] = ip1
	mesh.conn_edge_el[2, iedg_el, iel] = ip5
	iedg_el = 6
	mesh.conn_edge_el[1, iedg_el, iel] = ip2
	mesh.conn_edge_el[2, iedg_el, iel] = ip6
	iedg_el = 7
	mesh.conn_edge_el[1, iedg_el, iel] = ip3
	mesh.conn_edge_el[2, iedg_el, iel] = ip7
	iedg_el = 8
	mesh.conn_edge_el[1, iedg_el, iel] = ip4
	mesh.conn_edge_el[2, iedg_el, iel] = ip8
        
        #Edges top face
	iedg_el = 9
	mesh.conn_edge_el[1, iedg_el, iel] = ip5
	mesh.conn_edge_el[2, iedg_el, iel] = ip6
	iedg_el = 10
	mesh.conn_edge_el[1, iedg_el, iel] = ip6
	mesh.conn_edge_el[2, iedg_el, iel] = ip7
	iedg_el = 11
	mesh.conn_edge_el[1, iedg_el, iel] = ip7
	mesh.conn_edge_el[2, iedg_el, iel] = ip8
	iedg_el = 12
	mesh.conn_edge_el[1, iedg_el, iel] = ip8
	mesh.conn_edge_el[2, iedg_el, iel] = ip5
	
    end
    
end #populate_edge_el!

function populate_conn_face_el!(mesh::St_mesh, SD::NSD_2D)
    
    for iel = 1:mesh.nelem
        
        #
        # CGNS numbering
        #
        @show ip1 = mesh.cell_node_ids[iel][4]
        @show ip2 = mesh.cell_node_ids[iel][3]
        @show ip3 = mesh.cell_node_ids[iel][1]
        @show ip4 = mesh.cell_node_ids[iel][2]
                
        #
        # Local faces node connectivity:
        # i.e. what nodes belong to a given local face in iel:
        #
        face_el = 1
        mesh.conn_face_el[1, face_el, iel] = ip1
        mesh.conn_face_el[2, face_el, iel] = ip2
        mesh.conn_face_el[3, face_el, iel] = ip3
        mesh.conn_face_el[4, face_el, iel] = ip4
        
    end
    
end #populate_face_el

function populate_conn_face_el!(mesh::St_mesh, SD::NSD_3D)
    
    for iel = 1:mesh.nelem
        
        #
        # CGNS numbering
        #
        ip1 = mesh.cell_node_ids[iel][2]
        ip2 = mesh.cell_node_ids[iel][6]
        ip3 = mesh.cell_node_ids[iel][8]
        ip4 = mesh.cell_node_ids[iel][4]
        ip5 = mesh.cell_node_ids[iel][1]
        ip6 = mesh.cell_node_ids[iel][5]
        ip7 = mesh.cell_node_ids[iel][7]
        ip8 = mesh.cell_node_ids[iel][3]
        
        #
        # Local faces node connectivity:
        # i.e. what nodes belong to a given local face in iel:
        #
        face_el = 1
        mesh.conn_face_el[1, face_el, iel] = ip1
        mesh.conn_face_el[2, face_el, iel] = ip4
        mesh.conn_face_el[3, face_el, iel] = ip3
        mesh.conn_face_el[4, face_el, iel] = ip2

        face_el = 2
        mesh.conn_face_el[1, face_el, iel] = ip1
        mesh.conn_face_el[2, face_el, iel] = ip2
        mesh.conn_face_el[3, face_el, iel] = ip6
        mesh.conn_face_el[4, face_el, iel] = ip5
        
        face_el = 3
        mesh.conn_face_el[1, face_el, iel] = ip2
        mesh.conn_face_el[2, face_el, iel] = ip3
        mesh.conn_face_el[3, face_el, iel] = ip7
        mesh.conn_face_el[4, face_el, iel] = ip6
        
        face_el = 4
        mesh.conn_face_el[1, face_el, iel] = ip3
        mesh.conn_face_el[2, face_el, iel] = ip4
        mesh.conn_face_el[3, face_el, iel] = ip8
        mesh.conn_face_el[4, face_el, iel] = ip7
        
        face_el = 5
        mesh.conn_face_el[1, face_el, iel] = ip1
        mesh.conn_face_el[2, face_el, iel] = ip5
        mesh.conn_face_el[3, face_el, iel] = ip8
        mesh.conn_face_el[4, face_el, iel] = ip4
        
        face_el = 6
        mesh.conn_face_el[1, face_el, iel] = ip5
        mesh.conn_face_el[2, face_el, iel] = ip6
        mesh.conn_face_el[3, face_el, iel] = ip7
        mesh.conn_face_el[4, face_el, iel] = ip8
        
    end
    
end #populate_face_el


function  add_high_order_nodes!(mesh::St_mesh) end

function  add_high_order_nodes_1D_native_mesh!(mesh::St_mesh)
    
    if (mesh.nop < 2) return end
    
    println(" # POPULATE 1D GRID with SPECTRAL NODES ............................ ")
    println(" # ...")

    Legendre = St_Legendre{Float64}(0.0, 0.0, 0.0, 0.0)
    lgl      = St_lgl{Float64}(zeros(mesh.nop+1),
                               zeros(mesh.nop+1))
    build_lgl!(Legendre, lgl, mesh.nop)

    
    x1, x2 = Float64(0.0), Float64(0.0)    
    ξ::typeof(lgl.ξ[1]) = 0.0

    ngl                      = mesh.nop + 1
    tot_linear_poin          = mesh.npoin_linear
    tot_vol_internal_nodes   = mesh.nelem*(ngl-2)
    el_internal_nodes        = ngl - 2
    el_nodes                 = ngl
    
    #Increase number of grid points from linear count to total high-order points
    mesh.npoin = mesh.npoin_linear + tot_vol_internal_nodes
    resize!(mesh.x, (mesh.npoin))
    
    #
    # First pass: build coordinates and store IP into conn_edge_poin[iedge_g, l]
    #
    ip = tot_linear_poin + 1
    for iel_g = 1:mesh.nelem

        ip1 = iel_g
        ip2 = iel_g + 1
        
        mesh.conn[1, iel_g], mesh.conn[ngl, iel_g] = ip1, ip2
        x1, x2 = mesh.x[ip1], mesh.x[ip2]
        
        iconn = 1
        for l=2:ngl-1
            ξ = lgl.ξ[l];
            
            mesh.x[ip] = x1*(1.0 - ξ)*0.5 + x2*(1.0 + ξ)*0.5;
            
            #mesh.conn[2 + iconn, iel_g] = ip #OK
            mesh.conn[l, iel_g] = ip #OK
            iconn = iconn + 1
            
            ip = ip + 1
        end
    end
    
    println(" # POPULATE 1D GRID with SPECTRAL NODES ............................ DONE")
    return 
end

function  add_high_order_nodes_edges!(mesh::St_mesh, lgl::St_lgl, SD::NSD_2D)
    
    if (mesh.nop < 2) return end
    
    println(" # POPULATE GRID with SPECTRAL NODES ............................ EDGES")
    println(" # ...")
    
    x1, y1 = Float64(0.0), Float64(0.0)
    x2, y2 = Float64(0.0), Float64(0.0)
    
    ξ::typeof(lgl.ξ[1]) = 0.0

    ngl                      = mesh.nop + 1
    tot_linear_poin          = mesh.npoin_linear
    tot_edges_internal_nodes = mesh.nedges*(ngl-2)
    tot_vol_internal_nodes   = mesh.nelem*(ngl-2)*(ngl-2)

    el_edges_internal_nodes  = mesh.NEDGES_EL*(ngl-2)
    
    #Increase number of grid points from linear count to total high-order points
    mesh.npoin = mesh.npoin_linear + tot_edges_internal_nodes + tot_vol_internal_nodes

    if length(mesh.x_ho) < mesh.npoin
        resize!(mesh.x_ho, (mesh.npoin))
    end
    if length(mesh.y_ho) < mesh.npoin        
        resize!(mesh.y_ho, (mesh.npoin))
    end
    
    conn_edge_poin::Array{Int64, 2}  = zeros(mesh.nedges, mesh.ngl)

    open("./COORDS_HO_edges.dat", "w") do f
        #
        # First pass: build coordinates and store IP into conn_edge_poin[iedge_g, l]
        #
        ip = tot_linear_poin + 1
        for iedge_g = 1:mesh.nedges
            
            ip1 = mesh.conn_unique_edges[iedge_g][1]
            ip2 = mesh.conn_unique_edges[iedge_g][2]
            
            conn_edge_poin[iedge_g,        1] = ip1
            conn_edge_poin[iedge_g, mesh.ngl] = ip2
            
            x1, y1 = mesh.x[ip1], mesh.y[ip1]
            x2, y2 = mesh.x[ip2], mesh.y[ip2]
            
            #@printf(" %d: (ip1, ip2) = (%d %d) ", iedge_g, ip1, ip2)
            for l=2:ngl-1
                ξ = lgl.ξ[l];
                
                mesh.x_ho[ip] = x1*(1.0 - ξ)*0.5 + x2*(1.0 + ξ)*0.5;
	        mesh.y_ho[ip] = y1*(1.0 - ξ)*0.5 + y2*(1.0 + ξ)*0.5;
                
                conn_edge_poin[iedge_g, l] = ip
                
                #@printf(" lgl %d: %d %d ", l, iedge_g, conn_edge_poin[iedge_g, l])
                @printf(f, " %.6f %.6f 0.000000 %d\n", mesh.x_ho[ip],  mesh.y_ho[ip], ip)
                ip = ip + 1
            end
        end
    end #do f
    #show(stdout, "text/plain", conn_edge_poin)
    #@info "-----2D edges"
    
    #
    # Second pass: populate mesh.conn[1:8+el_edges_internal_nodes, ∀ elem]\n")
    #
    cache_edge_ids = array_cache(mesh.cell_edge_ids) # allocation here  
    for iel = 1:mesh.nelem
        edge_ids = getindex!(cache_edge_ids, mesh.cell_edge_ids, iel)
        iconn = 1
        for iedge_el = 1:length(edge_ids)
            iedge_g = edge_ids[iedge_el]
            for l = 2:ngl-1
                ip = conn_edge_poin[iedge_g, l]
                mesh.conn[2^mesh.nsd + iconn, iel] = ip #OK
                iconn = iconn + 1
            end
        end
    end
    #show(stdout, "text/plain", mesh.conn')
    
    println(" # POPULATE GRID with SPECTRAL NODES ............................ EDGES DONE")
    
    return 
end

function  add_high_order_nodes_edges1!(mesh::St_mesh, lgl::St_lgl, SD::NSD_2D)
    
    if (mesh.nop < 2) return end
    
    println(" # POPULATE GRID with SPECTRAL NODES ............................ EDGES")
    println(" # ...")
    
    x1, y1 = Float64(0.0), Float64(0.0)
    x2, y2 = Float64(0.0), Float64(0.0)
    
    ξ::typeof(lgl.ξ[1]) = 0.0

    ngl                      = mesh.nop + 1
    tot_linear_poin          = mesh.npoin_linear
    tot_edges_internal_nodes = mesh.nedges*(ngl-2)
    tot_vol_internal_nodes   = mesh.nelem*(ngl-2)*(ngl-2)

    el_edges_internal_nodes  = mesh.NEDGES_EL*(ngl-2)
    
    #Increase number of grid points from linear count to total high-order points
    mesh.npoin = mesh.npoin_linear + tot_edges_internal_nodes + tot_vol_internal_nodes

    if length(mesh.x_ho) < mesh.npoin
        resize!(mesh.x_ho, (mesh.npoin))
    end
    if length(mesh.y_ho) < mesh.npoin        
        resize!(mesh.y_ho, (mesh.npoin))
    end
    
    conn_edge_poin::Array{Int64, 2}  = zeros(mesh.nedges, mesh.ngl)
    @info size(mesh.cell_edge_ids,1)
    @info size(mesh.cell_edge_ids,2)
    
    open("./COORDS_HO_edges.dat", "w") do f
        #
        # First pass: build coordinates and store IP into conn_edge_poin[iedge_g, l]
        #
        for iel = 1:mesh.nelem
            for iedg_el = 1:length(mesh.conn_edge_el[1, :, iel])

                ip = tot_linear_poin + 1
                for iedge_g = 1:mesh.nedges
                    if iedge_g == mesh.cell_edge_ids[iel, iedg_el]

                        ip1 = mesh.conn_edge_el[1, iedg_el, iel]
                        ip2 = mesh.conn_edge_el[2, iedg_el, iel]
                        #ip1 = mesh.conn_unique_edges[iedge_g][1]
                        #ip2 = mesh.conn_unique_edges[iedge_g][2]
                        
                        conn_edge_poin[iedge_g,        1] = ip1
                        conn_edge_poin[iedge_g, mesh.ngl] = ip2
                        
                        x1, y1 = mesh.x[ip1], mesh.y[ip1]
                        x2, y2 = mesh.x[ip2], mesh.y[ip2]
                        
                        #@printf(" %d: (ip1, ip2) = (%d %d) ", iedge_g, ip1, ip2)
                        for l=2:ngl-1
                            ξ = lgl.ξ[l];
                            
                            mesh.x_ho[ip] = x1*(1.0 - ξ)*0.5 + x2*(1.0 + ξ)*0.5;
	                    mesh.y_ho[ip] = y1*(1.0 - ξ)*0.5 + y2*(1.0 + ξ)*0.5;
                            
                            conn_edge_poin[iedge_g, l] = ip
                            
                            #@printf(" lgl %d: %d %d ", l, iedge_g, conn_edge_poin[iedge_g, l])
                            @printf(f, " %.6f %.6f 0.000000 %d\n", mesh.x_ho[ip],  mesh.y_ho[ip], ip)
                            ip = ip + 1
                        end
                    end
                end
            end
        end
    end #do f
    #show(stdout, "text/plain", conn_edge_poin)
    #@info "-----2D edges"
    
    #
    # Second pass: populate mesh.conn[1:8+el_edges_internal_nodes, ∀ elem]\n")
    #
    cache_edge_ids = array_cache(mesh.cell_edge_ids) # allocation here  
    for iel = 1:mesh.nelem
        edge_ids = getindex!(cache_edge_ids, mesh.cell_edge_ids, iel)
        iconn = 1
        for iedge_el = 1:length(edge_ids)
            iedge_g = edge_ids[iedge_el]
            for l = 2:ngl-1
                ip = conn_edge_poin[iedge_g, l]
                mesh.conn[2^mesh.nsd + iconn, iel] = ip #OK
                iconn = iconn + 1
            end
        end
    end
    #show(stdout, "text/plain", mesh.conn')
    
    println(" # POPULATE GRID with SPECTRAL NODES ............................ EDGES DONE")
    
    return 
end

function  add_high_order_nodes_edges!(mesh::St_mesh, lgl::St_lgl, SD::NSD_3D)
    
    if (mesh.nop < 2) return end
    
    println(" # POPULATE GRID with SPECTRAL NODES ............................ EDGES")
    println(" # ...")
    
    x1, y1, z1 = Float64(0.0), Float64(0.0), Float64(0.0)
    x2, y2, z2 = Float64(0.0), Float64(0.0), Float64(0.0)
    
    ξ::typeof(lgl.ξ[1]) = 0.0

    ngl                      = mesh.nop + 1
    tot_linear_poin          = mesh.npoin_linear
    tot_edges_internal_nodes = mesh.nedges*(ngl-2)
    tot_faces_internal_nodes = mesh.nfaces*(ngl-2)*(ngl-2)
    tot_vol_internal_nodes   = mesh.nelem*(ngl-2)*(ngl-2)*(ngl-2)
    el_edges_internal_nodes  = mesh.NEDGES_EL*(ngl-2)
    
    #Increase number of grid points from linear count to total high-order points
    mesh.npoin = mesh.npoin_linear + tot_edges_internal_nodes + tot_faces_internal_nodes + tot_vol_internal_nodes

    if length(mesh.x_ho) < mesh.npoin
        resize!(mesh.x_ho, (mesh.npoin))
    end
    if length(mesh.y_ho) < mesh.npoin        
        resize!(mesh.y_ho, (mesh.npoin))
    end
    if length(mesh.z_ho) < mesh.npoin        
        resize!(mesh.z_ho, (mesh.npoin))
    end
    
    conn_edge_poin::Array{Int64, 2}  = zeros(mesh.nedges, mesh.ngl)
    open("./COORDS_HO_edges.dat", "w") do f
        #
        # First pass: build coordinates and store IP into conn_edge_poin[iedge_g, l]
        #
        ip = tot_linear_poin + 1
        for iedge_g = 1:mesh.nedges
            
            ip1 = mesh.conn_unique_edges[iedge_g][1]
            ip2 = mesh.conn_unique_edges[iedge_g][2]
            
            conn_edge_poin[iedge_g,        1] = ip1
            conn_edge_poin[iedge_g, mesh.ngl] = ip2
            
            x1, y1, z1 = mesh.x[ip1], mesh.y[ip1], mesh.z[ip1]
            x2, y2, z2 = mesh.x[ip2], mesh.y[ip2], mesh.z[ip2]
            
            @printf(" %d: (ip1, ip2) = (%d %d) ", iedge_g, ip1, ip2)
            for l=2:ngl-1
                ξ = lgl.ξ[l];
                
                mesh.x_ho[ip] = x1*(1.0 - ξ)*0.5 + x2*(1.0 + ξ)*0.5;
	        mesh.y_ho[ip] = y1*(1.0 - ξ)*0.5 + y2*(1.0 + ξ)*0.5;
	        mesh.z_ho[ip] = z1*(1.0 - ξ)*0.5 + z2*(1.0 + ξ)*0.5;
                
                conn_edge_poin[iedge_g, l] = ip
                
                #@printf(" lgl %d: %d %d ", l, iedge_g, conn_edge_poin[iedge_g, l])
                @printf(f, " %.6f %.6f %.6f %d\n", mesh.x_ho[ip],  mesh.y_ho[ip], mesh.z_ho[ip], ip)
                ip = ip + 1
            end
        end
    end #do f
    #show(stdout, "text/plain", conn_edge_poin)
    #@info "-----3D edges"
    
    #
    # Second pass: populate mesh.conn[1:8+el_edges_internal_nodes, ∀ elem]\n")
    #
    cache_edge_ids = array_cache(mesh.cell_edge_ids) # allocation here  
    for iel = 1:mesh.nelem
        edge_ids = getindex!(cache_edge_ids, mesh.cell_edge_ids, iel)
        iconn = 1
        for iedge_el = 1:length(edge_ids)
            iedge_g = edge_ids[iedge_el]
            for l = 2:ngl-1
                ip = conn_edge_poin[iedge_g, l]
                mesh.conn[2^mesh.nsd + iconn, iel] = ip #OK
                iconn = iconn + 1
            end
        end
    end
    #show(stdout, "text/plain", mesh.conn')
    #error("now")
    
    println(" # POPULATE GRID with SPECTRAL NODES ............................ EDGES DONE")
    return 
end


function  add_high_order_nodes_faces!(mesh::St_mesh, lgl::St_lgl, SD::NSD_2D)

    if (mesh.nop < 2) return end
    
    println(" # POPULATE GRID with SPECTRAL NODES ............................ FACES")
    println(" # ...")
    
    x1, y1 = Float64(0.0), Float64(0.0)
    x2, y2 = Float64(0.0), Float64(0.0)
    x3, y3 = Float64(0.0), Float64(0.0)
    x4, y4 = Float64(0.0), Float64(0.0)
    
    ξ::typeof(lgl.ξ[1]) = 0.0
    ζ::typeof(lgl.ξ[1]) = 0.0
    
    ngl                      = mesh.nop + 1
    tot_linear_poin          = mesh.npoin_linear
    tot_edges_internal_nodes = mesh.nedges*(ngl-2)
    tot_faces_internal_nodes = mesh.nfaces*(ngl-2)*(ngl-2)
    
    el_edges_internal_nodes  = mesh.NEDGES_EL*(ngl-2)
    el_faces_internal_nodes  = mesh.NFACES_EL*(ngl-2)*(ngl-2)
    
    #Increase number of grid points from linear count to total high-order points
    mesh.npoin = mesh.npoin_linear + tot_edges_internal_nodes + tot_faces_internal_nodes
    
    if length(mesh.x_ho) < mesh.npoin
        setize!(mesh.x_ho, (mesh.npoin))
    end
    if length(mesh.y_ho) < mesh.npoin
        resize!(mesh.y_ho, (mesh.npoin))
    end
    
    conn_face_poin::Array{Int64, 3}  = zeros(mesh.nelem, mesh.ngl, mesh.ngl)

    open("./COORDS_HO_faces.dat", "w") do f
        #
        # First pass:
        #
        ip  = tot_linear_poin + tot_edges_internal_nodes + 1
        for iface_g = 1:mesh.nelem #NOTICE: in 2D the faces are the elements themselves
            iel = iface_g
            #GGNS numbering
            ip1 = mesh.cell_node_ids[iel][1]
            ip2 = mesh.cell_node_ids[iel][2]
            ip3 = mesh.cell_node_ids[iel][4]
            ip4 = mesh.cell_node_ids[iel][3]

            conn_face_poin[iface_g, 1, 1]     = ip1
            conn_face_poin[iface_g, ngl, 1]   = ip2
            conn_face_poin[iface_g, ngl, ngl] = ip4
            conn_face_poin[iface_g, 1, ngl]   = ip3
            
            x1, y1 = mesh.x[ip1], mesh.y[ip1]
            x2, y2 = mesh.x[ip2], mesh.y[ip2]
            x3, y3 = mesh.x[ip3], mesh.y[ip3]
            x4, y4 = mesh.x[ip4], mesh.y[ip4]
            
            for l=2:ngl-1
                ξ = lgl.ξ[l];
                
                for m=2:ngl-1
                    ζ = lgl.ξ[m];
                    
	            mesh.x_ho[ip] = (x1*(1 - ξ)*(1 - ζ)*0.25
                                     + x2*(1 + ξ)*(1 - ζ)*0.25
		                     + x3*(1 + ξ)*(1 + ζ)*0.25			
		                     + x4*(1 - ξ)*(1 + ζ)*0.25)
                    
                    mesh.y_ho[ip] =  (y1*(1 - ξ)*(1 - ζ)*0.25
		                      + y2*(1 + ξ)*(1 - ζ)*0.25
		                      + y3*(1 + ξ)*(1 + ζ)*0.25
		                      + y4*(1 - ξ)*(1 + ζ)*0.25)

                    conn_face_poin[iface_g, l, m] = ip
                    mesh.connijk[l, m, iel] = ip
                    
                    @printf(f, " %.6f %.6f 0.000000 %d\n", mesh.x_ho[ip],  mesh.y_ho[ip], ip)
                    
	            ip = ip + 1
                end
            end
        end
    end #do f

    #
    # Second pass: populate mesh.conn[1:8+el_edges_internal_nodes+el_faces_internal_nodes, ∀ elem]\n")
    #
    cache_face_ids = array_cache(mesh.cell_face_ids) # allocation here    
    for iel = 1:mesh.nelem
        iface_g = iel
        iconn = 1
        for l = 2:ngl-1
            for m = 2:ngl-1
                ip = conn_face_poin[iface_g, l, m]
                mesh.conn[2^mesh.nsd + el_edges_internal_nodes + iconn, iel] = ip
                iconn = iconn + 1
            end
        end
    end
    #
    # Populate connijk[i,j,iel]
    #
    #Left edge
    for iel = 1:mesh.nelem
        for m = ngl-1:-1:2
            j = ngl - m
            mesh.connijk[1, m, iel] = mesh.conn[4 + j, iel]
            @info j
        end
    end
    #Right edge
    for iel = 1:mesh.nelem
        for m = ngl-1:-1:2
            j = ngl - m
            @info mesh.connijk[ngl, m, iel] = mesh.conn[4 + ngl-2 + j, iel] 4 + ngl-2 + j
            
        end
    end


    
    
    #show(stdout, "text/plain", mesh.conn')
    
    println(" # POPULATE GRID with SPECTRAL NODES ............................ FACES DONE")

end

function  add_high_order_nodes_faces!(mesh::St_mesh, lgl::St_lgl, SD::NSD_3D)

    if (mesh.nop < 2) return end
    
    println(" # POPULATE GRID with SPECTRAL NODES ............................ FACES")
    println(" # ...")
    
    x1, y1, z1 = Float64(0.0), Float64(0.0), Float64(0.0)
    x2, y2, z2 = Float64(0.0), Float64(0.0), Float64(0.0)
    x3, y3, z3 = Float64(0.0), Float64(0.0), Float64(0.0)
    x4, y4, z4 = Float64(0.0), Float64(0.0), Float64(0.0)
    
    ξ::typeof(lgl.ξ[1]) = 0.0
    ζ::typeof(lgl.ξ[1]) = 0.0
    
    ngl                      = mesh.nop + 1
    tot_linear_poin          = mesh.npoin_linear
    tot_edges_internal_nodes = mesh.nedges*(ngl-2)
    tot_faces_internal_nodes = mesh.nfaces*(ngl-2)*(ngl-2)
    tot_vol_internal_nodes   = mesh.nelem*(ngl-2)*(ngl-2)*(ngl-2)

    el_edges_internal_nodes  = mesh.NEDGES_EL*(ngl-2)
    el_faces_internal_nodes  = mesh.NFACES_EL*(ngl-2)*(ngl-2)
    
    #Increase number of grid points from linear count to total high-order points
    mesh.npoin = mesh.npoin_linear + tot_edges_internal_nodes + tot_faces_internal_nodes + tot_vol_internal_nodes
    

    if length(mesh.x_ho) < mesh.npoin
        setize!(mesh.x_ho, (mesh.npoin))
    end
    if length(mesh.y_ho) < mesh.npoin
        resize!(mesh.y_ho, (mesh.npoin))
    end
    if length(mesh.z_ho) < mesh.npoin
        resize!(mesh.z_ho, (mesh.npoin))
    end
    
    conn_face_poin::Array{Int64, 3}  = zeros(mesh.nedges, mesh.ngl, mesh.ngl)

    open("./COORDS_HO_faces.dat", "w") do f
        #
        # First pass:
        #
        ip  = tot_linear_poin + tot_edges_internal_nodes + 1
        for iface_g = 1:mesh.nfaces
            
            #GGNS numbering
            ip1 = mesh.conn_unique_faces[iface_g][1]
            ip2 = mesh.conn_unique_faces[iface_g][2]
            ip3 = mesh.conn_unique_faces[iface_g][4]
            ip4 = mesh.conn_unique_faces[iface_g][3]

            conn_face_poin[iface_g, 1, 1]     = ip1
            conn_face_poin[iface_g, ngl, 1]   = ip2
            conn_face_poin[iface_g, ngl, ngl] = ip4
            conn_face_poin[iface_g, 1, ngl]   = ip3
            
            x1, y1, z1 = mesh.x[ip1], mesh.y[ip1], mesh.z[ip1]
            x2, y2, z2 = mesh.x[ip2], mesh.y[ip2], mesh.z[ip2]
            x3, y3, z3 = mesh.x[ip3], mesh.y[ip3], mesh.z[ip3]
            x4, y4, z4 = mesh.x[ip4], mesh.y[ip4], mesh.z[ip4]
            
            for l=2:ngl-1
                ξ = lgl.ξ[l];
                
                for m=2:ngl-1
                    ζ = lgl.ξ[m];
                    
	            mesh.x_ho[ip] = (x1*(1 - ξ)*(1 - ζ)*0.25
                                     + x2*(1 + ξ)*(1 - ζ)*0.25
		                     + x3*(1 + ξ)*(1 + ζ)*0.25			
		                     + x4*(1 - ξ)*(1 + ζ)*0.25)
                    
                    mesh.y_ho[ip] =  (y1*(1 - ξ)*(1 - ζ)*0.25
		                      + y2*(1 + ξ)*(1 - ζ)*0.25
		                      + y3*(1 + ξ)*(1 + ζ)*0.25
		                      + y4*(1 - ξ)*(1 + ζ)*0.25)
                    
                    mesh.z_ho[ip] =  (z1*(1 - ξ)*(1 - ζ)*0.25
		                      + z2*(1 + ξ)*(1 - ζ)*0.25
		                      + z3*(1 + ξ)*(1 + ζ)*0.25
		                      + z4*(1 - ξ)*(1 + ζ)*0.25)

                    conn_face_poin[iface_g, l, m] = ip
                    
                    @printf(f, " %.6f %.6f %.6f %d\n", mesh.x_ho[ip],  mesh.y_ho[ip], mesh.z_ho[ip], ip)
                    
	            ip = ip + 1
                end
            end
        end
    end #do f

    #
    # Second pass: populate mesh.conn[1:8+el_edges_internal_nodes+el_faces_internal_nodes, ∀ elem]\n")
    #
    cache_face_ids = array_cache(mesh.cell_face_ids) # allocation here    
    for iel = 1:mesh.nelem
        iconn = 1
        face_ids = getindex!(cache_face_ids, mesh.cell_face_ids, iel)
        for iface_el = 1:length(face_ids)
            iface_g = face_ids[iface_el]
            for l = 2:ngl-1
                for m = 2:ngl-1
                    ip = conn_face_poin[iface_g, l, m]
                    mesh.conn[8 + el_edges_internal_nodes + iconn, iel] = ip
                    iconn = iconn + 1
                end
            end
        end
    end
    
    println(" # POPULATE GRID with SPECTRAL NODES ............................ FACES DONE")

end

function  add_high_order_nodes_volumes!(mesh::St_mesh, lgl::St_lgl, SD::NSD_2D)
    nothing
end

function  add_high_order_nodes_volumes!(mesh::St_mesh, lgl::St_lgl, SD::NSD_3D)

    if (mesh.nop < 2) return end
    
    println(" # POPULATE GRID with SPECTRAL NODES ............................ VOLUMES")
    println(" # ...")
    
    x1, y1, z1 = Float64(0.0), Float64(0.0), Float64(0.0)
    x2, y2, z2 = Float64(0.0), Float64(0.0), Float64(0.0)
    x3, y3, z3 = Float64(0.0), Float64(0.0), Float64(0.0)
    x4, y4, z4 = Float64(0.0), Float64(0.0), Float64(0.0)
    x5, y5, z5 = Float64(0.0), Float64(0.0), Float64(0.0)
    x6, y6, z6 = Float64(0.0), Float64(0.0), Float64(0.0)
    x7, y7, z7 = Float64(0.0), Float64(0.0), Float64(0.0)
    x8, y8, z8 = Float64(0.0), Float64(0.0), Float64(0.0)
    
    ξ::typeof(lgl.ξ[1]) = 0.0
    η::typeof(lgl.ξ[1]) = 0.0
    ζ::typeof(lgl.ξ[1]) = 0.0

    ngl                      = mesh.nop + 1
    tot_linear_poin          = mesh.npoin_linear
    tot_edges_internal_nodes = mesh.nedges*(ngl-2)
    tot_faces_internal_nodes = mesh.nfaces*(ngl-2)*(ngl-2)
    tot_vol_internal_nodes   = mesh.nelem*(ngl-2)*(ngl-2)*(ngl-2)

    el_edges_internal_nodes  = mesh.NEDGES_EL*(ngl-2)
    el_faces_internal_nodes  = mesh.NFACES_EL*(ngl-2)*(ngl-2)
    el_vol_internal_nodes    = (ngl-2)*(ngl-2)*(ngl-2)
    
    #Increase number of grid points from linear count to titak high-order points
    mesh.npoin = tot_linear_poin + tot_edges_internal_nodes + tot_faces_internal_nodes + tot_vol_internal_nodes
    
    if length(mesh.x_ho) < mesh.npoin
        resize!(mesh.x_ho, (mesh.npoin))
    end
    if length(mesh.y_ho) < mesh.npoin
        resize!(mesh.y_ho, (mesh.npoin))
    end
    if length(mesh.z_ho) < mesh.npoin
        resize!(mesh.z_ho, (mesh.npoin))
    end
    
    open("./COORDS_HO_vol.dat", "w") do f
        ip  = tot_linear_poin + tot_edges_internal_nodes + tot_faces_internal_nodes + 1
        for iel = 1:mesh.nelem

            iconn = 1
            
            #
            # CGNS numbering
            #
            ip1 = mesh.cell_node_ids[iel][2]
            ip2 = mesh.cell_node_ids[iel][6]
            ip3 = mesh.cell_node_ids[iel][8]
            ip4 = mesh.cell_node_ids[iel][4]
            ip5 = mesh.cell_node_ids[iel][1]
            ip6 = mesh.cell_node_ids[iel][5]
            ip7 = mesh.cell_node_ids[iel][7]
            ip8 = mesh.cell_node_ids[iel][3]
            
            x1, y1, z1 = mesh.x[ip1], mesh.y[ip1], mesh.z[ip1]
            x2, y2, z2 = mesh.x[ip2], mesh.y[ip2], mesh.z[ip2]
            x3, y3, z3 = mesh.x[ip3], mesh.y[ip3], mesh.z[ip3]
            x4, y4, z4 = mesh.x[ip4], mesh.y[ip4], mesh.z[ip4]     
            x5, y5, z5 = mesh.x[ip5], mesh.y[ip5], mesh.z[ip5]
            x6, y6, z6 = mesh.x[ip6], mesh.y[ip6], mesh.z[ip6]
            x7, y7, z7 = mesh.x[ip7], mesh.y[ip7], mesh.z[ip7]
            x8, y8, z8 = mesh.x[ip8], mesh.y[ip8], mesh.z[ip8]
            
            for l=2:ngl-1
                ξ = lgl.ξ[l];
                
                for m=2:ngl-1
                    η = lgl.ξ[m];
                    
                    for n=2:ngl-1
                        ζ = lgl.ξ[n];
                        
                        
	                mesh.x_ho[ip] = (x1*(1 - ξ)*(1 - η)*(1 - ζ)*0.125
			                 + x2*(1 + ξ)*(1 - η)*(1 - ζ)*0.125
			                 + x3*(1 + ξ)*(1 + η)*(1 - ζ)*0.125
			                 + x4*(1 - ξ)*(1 + η)*(1 - ζ)*0.125
			                 + x5*(1 - ξ)*(1 - η)*(1 + ζ)*0.125
			                 + x6*(1 + ξ)*(1 - η)*(1 + ζ)*0.125
			                 + x7*(1 + ξ)*(1 + η)*(1 + ζ)*0.125
			                 + x8*(1 - ξ)*(1 + η)*(1 + ζ)*0.125)
                        
	                mesh.y_ho[ip] = (y1*(1 - ξ)*(1 - η)*(1 - ζ)*0.125
			                 + y2*(1 + ξ)*(1 - η)*(1 - ζ)*0.125
			                 + y3*(1 + ξ)*(1 + η)*(1 - ζ)*0.125
			                 + y4*(1 - ξ)*(1 + η)*(1 - ζ)*0.125
			                 + y5*(1 - ξ)*(1 - η)*(1 + ζ)*0.125
			                 + y6*(1 + ξ)*(1 - η)*(1 + ζ)*0.125
			                 + y7*(1 + ξ)*(1 + η)*(1 + ζ)*0.125
			                 + y8*(1 - ξ)*(1 + η)*(1 + ζ)*0.125)
                        
	                mesh.z_ho[ip] = (z1*(1 - ξ)*(1 - η)*(1 - ζ)*0.125
			                 + z2*(1 + ξ)*(1 - η)*(1 - ζ)*0.125
			                 + z3*(1 + ξ)*(1 + η)*(1 - ζ)*0.125
			                 + z4*(1 - ξ)*(1 + η)*(1 - ζ)*0.125
			                 + z5*(1 - ξ)*(1 - η)*(1 + ζ)*0.125
			                 + z6*(1 + ξ)*(1 - η)*(1 + ζ)*0.125
			                 + z7*(1 + ξ)*(1 + η)*(1 + ζ)*0.125
			                 + z8*(1 - ξ)*(1 + η)*(1 + ζ)*0.125)

                        mesh.conn[8 + el_edges_internal_nodes + el_faces_internal_nodes + iconn, iel] = ip

                        @printf(f, " %.6f %.6f %.6f %d\n", mesh.x_ho[ip],  mesh.y_ho[ip], mesh.z_ho[ip], ip)

                        ip = ip + 1
                        iconn = iconn + 1
                    end
                end
            end 
        end
    end # do f 
    #show(stdout, "text/plain", mesh.conn')
    
    println(" # POPULATE GRID with SPECTRAL NODES ............................ VOLUMES DONE")

end

function mod_mesh_build_mesh!(mesh::St_mesh)

    if (mesh.nsd > 1)
        @error(" USE GMSH to build a higher-dimensional grid!")
    end
    
    println(" # BUILD LINEAR CARTESIAN GRID ............................")
    
    mesh.npoin_linear = mesh.npx
    mesh.npoin        = mesh.npoin_linear #This will be updated for high order grids
    mesh.nelem        = mesh.npx - 1
    
    Δx::TFloat=0.0
    resize!(mesh.Δx, mesh.nelem)
    
    Δx = abs(mesh.xmax - mesh.xmin)/(mesh.nelem)
    mesh.npoin = mesh.npx

    mesh.x[1] = mesh.xmin
    for i = 2:mesh.npx
        mesh.x[i] = mesh.x[i-1] + Δx
        mesh.Δx[i-1] = Δx #Constant for the sake of simplicity in 1D problems. This may change later
    end
    mesh.NNODES_EL  = 2
    
    println(" # 1D NATIVE LINEAR GRID PROPERTIES")
    println(" # N. elements       : ", mesh.nelem)
    println(" # N. points         : ", mesh.npoin_linear)
    println(" # 1D NATIVE LINEAR GRID PROPERTIES ...................... END")
    
    ngl                     = mesh.nop + 1
    tot_linear_poin         = mesh.npoin_linear    
    tot_vol_internal_nodes  = mesh.nelem*(ngl-2)  
    el_vol_internal_nodes   = (ngl-2)
    
    #Update number of grid points from linear count to total high-order points
    mesh.npoin = tot_linear_poin + tot_vol_internal_nodes
    
    if (mesh.nop > 1)
        println(" # 1D NATIVE HIGH-ORDER GRID PROPERTIES")
        println(" # N. volumes internal points : ", tot_vol_internal_nodes)
        println(" # N. total high order points : ", mesh.npoin)
        println(" # 1D NATIVE HIGH-ORDER GRID PROPERTIES ...................... END")
    end
    
    
    # Resize (using resize! from ElasticArrays) as needed
    resize!(mesh.x, (mesh.npoin))    
    mesh.npoin_el = ngl

    #allocate mesh.conn and reshape it
    mesh.conn = Array{Int64}(undef, mesh.npoin_el, mesh.nelem)
    #mesh.conn = reshape(mesh.conn, mesh.npoin_el, mesh.nelem)
    
    for iel = 1:mesh.nelem
        mesh.conn[1, iel] = iel
        mesh.conn[2, iel] = iel + 1
    end
    
    #Add high-order nodes
    add_high_order_nodes_1D_native_mesh!(mesh)

    #plot_1d_grid(mesh)
    
    println(" # BUILD LINEAR CARTESIAN GRID ............................ DONE")
    
end


function mod_mesh_mesh_driver(inputs::Dict)
    
    if (haskey(inputs, :lread_gmsh) && inputs[:lread_gmsh]==true)
        
        println(" # Read gmsh grid and populate with high-order points ")
        
        # Initialize mesh struct: the arrays length will be increased in mod_mesh_read_gmsh
        mesh = St_mesh{TInt,TFloat}(nsd=Int64(inputs[:nsd]),
                                    nop=Int64(inputs[:nop]))
        
        # Read gmsh grid using the GridapGmsh reader
        mod_mesh_read_gmsh!(mesh, inputs[:gmsh_filename])
        
        println(" # Read gmsh grid and populate with high-order points ........................ DONE")
        
    else
        
        println(" # Build native grid")

        # Initialize mesh struct for native structured grid:
        if (haskey(inputs, :nsd))
            
            if (inputs[:nsd]==1)
                println(" # ... build 1D grid ")
                mesh = St_mesh{TInt,TFloat}(x = zeros(Int64(inputs[:npx])),
                                            npx  = Int64(inputs[:npx]),
                                            xmin = Float64(inputs[:xmin]), xmax = Float64(inputs[:xmax]),
                                            nop=Int64(inputs[:nop]))
                
            elseif (inputs[:nsd]==2)
                println(" # ... build 2D grid ")
                mesh = St_mesh{TInt,TFloat}(x = zeros(Int64(inputs[:npx])),
                                            z = zeros(Int64(inputs[:npz])),
                                            npx  = Int64(inputs[:npx]),
                                            npz  = Int64(inputs[:npz]), 
                                            xmin = Float64(inputs[:xmin]), xmax = Float64(inputs[:xmax]),
                                            zmin = Float64(inputs[:zmin]), zmax = Float64(inputs[:zmax]),
                                            nop=Int64(inputs[:nop]))
                
            elseif (inputs[:nsd]==3)
                println(" # ... build 3D grid ")
                mesh = St_mesh{TInt,TFloat}(x = zeros(Int64(inputs[:npx])),
                                            y = zeros(Int64(inputs[:npy])),
                                            z = zeros(Int64(inputs[:npz])),
                                            npx  = Int64(inputs[:npx]),
                                            npy  = Int64(inputs[:npy]),
                                            npz  = Int64(inputs[:npz]), 
                                            xmin = Float64(inputs[:xmin]), xmax = Float64(inputs[:xmax]),
                                            ymin = Float64(inputs[:ymin]), ymax = Float64(inputs[:ymax]),
                                            zmin = Float64(inputs[:zmin]), zmax = Float64(inputs[:zmax]),
                                            nop=Int64(inputs[:nop]))
            else
                @error( " INPUT ERROR: nsd must be an integer in [1, 2, 3] ")
            end
            
        else
            
            #
            # Default grid is 1D if `nsd` is not defined in user_input.jl
            #
            println(" # ... build DEFAULT 1D grid")
            println(" # ...... DEFINE NSD in your input dictionary if you want a different grid!")
            mesh = St_mesh{TInt,TFloat}(x = zeros(Int64(inputs[:npx])),
                                        npx  = Int64(inputs[:npx]),
                                        xmin = Float64(inputs[:xmin]), xmax = Float64(inputs[:xmax]),
                                        nop=Int64(inputs[:nop]))
        end
        
        mod_mesh_build_mesh!(mesh)
        
        #Write structured grid to VTK
        #vtkfile = vtk_grid("mySTRUCTURED_GRID", mesh.x, mesh.y, mesh.z) # 3-D
        #outfiles = vtk_save(vtkfile)
        
        println(" # Build navite grid ........................ DONE")
    end

    #dump(mesh)
    return mesh
    
end


#=
function populate_face_in_elem!(face_in_elem::Array{Int64, 3}, nelem, NFACES_EL, conn_face_el_sort::Array{Int64, 3})

    iface = Int64(0)
    for ifac = 1:NFACES_EL
        for iel = 1:nelem	    
	    for jfac = 1:NFACES_EL
                for jel = iel:nelem
		    
		    if(     conn_face_el_sort[iel,ifac,1] === conn_face_el_sort[jel,jfac,1] && 
			    conn_face_el_sort[iel,ifac,2] === conn_face_el_sort[jel,jfac,2] && 
			    conn_face_el_sort[iel,ifac,3] === conn_face_el_sort[jel,jfac,3] && 
			    conn_face_el_sort[iel,ifac,4] === conn_face_el_sort[jel,jfac,4] && 
			    iel ≠ jel) 
			
			face_in_elem[1, ifac, iel] = iel
			face_in_elem[2, ifac, iel] = jel
			
			face_in_elem[1, jfac, jel] = jel
			face_in_elem[2, jfac, jel] = iel
			
			#@info " SHARED FACE:  face %d of ELEMENT %d is shared with face %d of ELEMENT %d - (%d %d %d %d) = (%d %d %d %d)\n", ifac+1,iel+1, jfac+1, jel+1, conn_face_el_sort[iel,ifac,1], conn_face_el_sort[iel,ifac,2], conn_face_el_sort[iel,ifac,3], conn_face_el_sort[iel,ifac,4],  conn_face_el_sort[jel,jfac,1], conn_face_el_sort[jel,jfac,2], conn_face_el_sort[jel,jfac,3], conn_face_el_sort[jel,jfac,4]
			iface = iface + 1;
		    end
		end
	    end
	end
    end     
    nfaces_int = Int64(iface)    
end
=#
