module PrometheusTypes

using Dates
import StructTypes

export PrometheusQueryResponse,
       PrometheusQueryStats,
       PrometheusInstantQuery,
       PrometheusInstantResult,
       PrometheusRangeQuery,
       PrometheusRangeResult,
       PrometheusData

struct PrometheusData
    ts::DateTime
    value::Float64

    PrometheusData(v::Vector{Any}) = new(unix2datetime(v[1]), parse(Float64, v[2]))
end

struct PrometheusRangeResult
    metric::Dict{String, String}
    values::Vector{PrometheusData}
end

struct PrometheusRangeQuery
    resultType::String
    result::Union{Nothing, Vector{PrometheusRangeResult}}
end

struct PrometheusInstantResult
    metric::Dict{String, String}
    value::PrometheusData
end

struct PrometheusInstantQuery
    resultType::String
    result::Union{Nothing, Vector{PrometheusInstantResult}}
end

struct PrometheusQueryStats
    seriesFetched::String
    executionTimeMsec::Int64
end

struct PrometheusQueryResponse{T}
    status::String
    isPartial::Bool
    data::T
    stats::PrometheusQueryStats
end

StructTypes.StructType(::Type{PrometheusData}) = StructTypes.ArrayType()

StructTypes.StructType(::Type{PrometheusRangeResult}) = StructTypes.Struct()
StructTypes.StructType(::Type{PrometheusRangeQuery}) = StructTypes.Struct()

StructTypes.StructType(::Type{PrometheusInstantResult}) = StructTypes.Struct()
StructTypes.StructType(::Type{PrometheusInstantQuery}) = StructTypes.Struct()

StructTypes.StructType(::Type{PrometheusQueryStats}) = StructTypes.Struct()
StructTypes.StructType(::Type{PrometheusQueryResponse}) = StructTypes.Struct()

end