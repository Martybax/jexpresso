function user_bc_dirichlet!(q,gradq,x,y,t,mesh,metrics,tag)
    c  = 1.0
    x0 = y0 = -0.8
    kx = ky = sqrt(2)/2
    ω  = 0.2
    d  = 0.5*ω/sqrt(log(2)); d2 = d*d
    e = exp(- ((kx*(x - x0) + ky*(y - y0)-c*t)^2)/d2)
    q[1] = e
    q[2] = kx*e/c
    q[3] = ky*e/c
    return q
end

function user_bc_neumann(q,gradq,x,y,t,mesh,metrics,tag)
    return zeros(3,1)
end