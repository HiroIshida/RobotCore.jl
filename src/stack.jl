# This works like stack data structure but has limited elements
# to avoid additionaly memory allocation
mutable struct PseudoStack{T}
    data::Vector{T}
    idx_top::Int
    n_max::Int
end
function PseudoStack(T, n_max)
    data = fill(zero(T), n_max)
    idx_top = 0
    PseudoStack{T}(data, idx_top, n_max)
end

function Base.pop!(ps::PseudoStack) 
    @debugassert ps.idx_top>0
    ps.idx_top -= 1
    @inbounds return ps.data[ps.idx_top+1]
end

function Base.push!(ps::PseudoStack, elem)
    @debugassert ps.idx_top<=ps.n_max
    ps.idx_top += 1
    @inbounds ps.data[ps.idx_top] = elem
end
Base.isempty(ps::PseudoStack) = (ps.idx_top == 0)
