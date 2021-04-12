function cost_metric_matrix(n_wp, weights)
    # TODO levarage sparsity ?
    acc_block = [1 -2 1; -2 4 -2; 1 -2 1]
    A_sub = zeros(n_wp, n_wp)
    for i in 2:n_wp-1
        A_sub[i-1:i+1, i-1:i+1] += acc_block
    end
    weight_matrix = Diagonal(weights.^2)
    A = kron(A_sub, weight_matrix)
    return A
end

function create_straight_trajectory(q_start, q_goal, n_wp)
    interval = (q_goal - q_start) / (n_wp - 1)
    xi = vcat([q_start + interval * (i-1) for i in 1:n_wp]...)
    return xi
end

function convertto_nlopt_const(const_canonical)
    function inner(val::Vector, x::Vector, jac::Matrix)
        val_, jac_ = const_canonical(x)
        copy!(val, -val_)
        length(jac) > 0 && copy!(jac, -transpose(jac_))
    end
    return inner
end

function convertto_nlopt_objective(objective_canonical)
    function inner(x::Vector, grad::Vector)
        val, grad_ = objective_canonical(x)
        length(grad) > 0 && copy!(grad, grad_)
        return val
    end
    return inner
end

function plan_trajectory(
        sscc::SweptSphereCollisionChecker,
        joints::Vector{Joint},
        sdf::SignedDistanceFunction,
        q_start, q_goal, n_wp
        ;
        ftol_abs=1e-3
        )
    n_dof = length(joints)
    n_whole = n_dof * n_wp

    function create_objective()
        weights = ones(n_dof)
        A = cost_metric_matrix(n_wp, weights)
        function objective(xi)
            val = transpose(xi) * A * xi
            grad = 2 * A * xi
            return val, grad
        end
        return objective
    end

    function create_ineqconst()
        n_coll = length(sscc.sphere_links)

        # declare beforehand to avoid additional allocation 
        n_ineq = n_coll * n_wp
        jac_mat = zeros(n_ineq, n_whole)
        val_vec = zeros(n_ineq)
        function ineqconst(xi::Vector)
            xi_reshaped = reshape(xi, (n_dof, n_wp))
            for i in 1:n_wp
                angles = xi_reshaped[:, i]
                set_joint_angles(sscc.mech, joints, angles)
                dists, grads = compute_coll_dists_and_grads(sscc, joints, sdf)

                # jac_mat has a block diagonal structure # TODO use BlockArray?
                jac_mat[1+n_coll*(i-1):n_coll*i, 1+n_dof*(i-1):n_dof*i] = transpose(grads)
                val_vec[1+n_coll*(i-1):n_coll*i] = dists
            end
            return val_vec, jac_mat
        end
        return ineqconst, n_ineq
    end

    function create_eqconst()
        # n_dof * 2 means sum of dofs of start and end points
        # the jac_mat is static, so defined offline here
        n_eq = n_dof * 2
        jac_mat = zeros(n_eq, n_whole) 
        jac_mat[1:n_dof, 1:n_dof] = -Matrix{Float64}(I, n_dof, n_dof)
        jac_mat[n_dof+1:end, end-n_dof+1:end] = -Matrix{Float64}(I, n_dof, n_dof)

        val_vec = zeros(n_dof * 2)
        function eqconst(xi::Vector)
            xi_reshaped = reshape(xi, (n_dof, n_wp))
            val_vec[1:n_dof] = q_start - xi_reshaped[:, 1]
            val_vec[n_dof+1:end] = q_goal - xi_reshaped[:, end]
            return val_vec, jac_mat
        end
        return eqconst, n_eq
    end

    xi_init = create_straight_trajectory(q_start, q_goal, n_wp)

    opt = Opt(:LD_SLSQP, n_whole)
    f = create_objective()
    opt.min_objective = convertto_nlopt_objective(f)

    g, n_ineq = create_ineqconst()
    inequality_constraint!(opt, convertto_nlopt_const(g), [1e-8 for _ in 1:n_ineq])

    h, n_eq = create_eqconst()
    equality_constraint!(opt, convertto_nlopt_const(h), [1e-8 for _ in 1:n_eq])

    opt.ftol_abs = ftol_abs
    minf, xi_solved, ret = NLopt.optimize(opt, xi_init)
    q_seq = reshape(xi_solved, (n_dof, n_wp))
    return q_seq
end
