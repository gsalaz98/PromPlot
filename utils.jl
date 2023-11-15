using DataFrames

function allbut(df::T, cols::Vector{Symbol}) where T <: AbstractDataFrame
    return setdiff(names(df), string.(cols))
end