function user_inputs()
    inputs = Dict(
        #---------------------------------------------------------------------------
        # User define your inputs below: the order doesn't matter
        #---------------------------------------------------------------------------
        :equation_set => "ns",
        :problem      => "none",
        :tend         => 2.5,
        :lexact_integration => false,
        :lread_gmsh   => true,
        #:gmsh_filename => "./demo/gmsh_grids/2d-grid.msh",
        #:gmsh_filename => "./demo/gmsh_grids/hexa_oneblock.msh",
        #:gmsh_filename => "./demo/gmsh_grids/hexa_UNSTR.msh",
        #:gmsh_filename => "./demo/gmsh_grids/hexa_UNSTR_coarse.msh",
        :gmsh_filename => "./demo/gmsh_grids/hexa_oneblock-2x1x1.msh",
        #:gmsh_filename => "./demo/gmsh_grids/hexa_oneblock-1x1x1.msh",
        :nsd                 => 3,           #number of space dimensions
        :interpolation_nodes =>"lgl",        #Choice: lgl, cgl 
        :nop                 => 2,         #Polynomila order
    ) #Dict
    #---------------------------------------------------------------------------
    # END User define your inputs below: the order doesn't matter
    #---------------------------------------------------------------------------

    return inputs
    
end