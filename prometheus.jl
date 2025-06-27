module PrometheusClient

export PrometheusQueryClient,
       PrometheusQueryConfig,
       PrometheusQueryResult,
       promql,
       prom_labels,
       prom_metrics

using Dates
using Distributed

using HTTP
using JSON3
using DataFrames
using DataFramesMeta

include("./PrometheusQuery.jl")

using .PrometheusTypes

Base.@kwdef struct PrometheusQueryClient
    url::String = "http://localhost:9090"
    api::String = "/api/v1/"

    function PrometheusQueryClient(url::String, api::String)::PrometheusQueryClient
        url = rstrip(rstrip(url), '/')
        api = rstrip(api, '/')

        new(url, api)
    end
end

Option{T} = Union{T, Nothing}

@kwdef mutable struct PrometheusQueryConfig
    ### Prometheus query string
    query::String

    ### Point-in-time to query the specific metric as referenced by `PrometheusQuery.query`
    time::Option{DateTime} = nothing

    ### Starting date to query the specific metric in a range as referenced by `PrometheusQuery.query`
    start_date::Option{DateTime} = nothing

    ### Ending date to query the specific metric in a range as referenced by `PrometheusQuery.query`
    ### Note that if this is left unbounded, it can consume lots of resources on the Prometheus server
    end_date::Option{DateTime} = nothing

    ### Step/interval to run query in. Some metrics in the prometheus server have varying metric intervals,
    ### so some results may require interpolation using a time-series fill-forward function to make comparisons
    ### between metrics for useful statistical analysis
    step::Dates.Period = Dates.Second(30)

    ### Timeout for the prometheus database to consider cancelling the submitted query.
    ### Defaults to `10 seconds`
    timeout::Dates.Period = Dates.Second(10)

    ### Point-in-time query permits for querying metrics at a specific
    ### time, but does not permit querying between a range.
    ### This flag is mutually exclusive w/ `PrometheusQuery.range_query`,
    ### i.e. only one can be set true
    instant_query::Bool = !isnothing(time)

    ### Query for data in a specified date range. This flag is mutually exclusive
    ### w/ `PrometheusQuery.instant_query`, i.e. only one can be true
    range_query::Bool = !isnothing(start_date)

    ### Limit of results to return. Defaults to `0` (disabled; no limit)
    limit::Int64 = 0

    ### Labels to filter from the resulting DataFrame
    filter_labels::Vector{String} = String["__name__"]
end

mutable struct PrometheusQueryResult
    df::DataFrame
    warnings::Vector{String}
    errors::Vector{<:Exception}
end

const RFC3339_FORMAT = Dates.dateformat"yyyy-mm-ddTHH:MM:SS.sZ"
const empty_df = DataFrame()

function promql_error(warnings::Vector{String}, errors::Vector{<:Exception})::PrometheusQueryResult
    return PrometheusQueryResult(empty_df, warnings, errors)
end

function promclient_url_normalize(p::PrometheusQueryClient)::String
    return rstrip(p.url, '/') * '/' * lstrip(rstrip(p.api, '/'), '/') * '/'
end

function prom_instant_query_df(
    q::PrometheusQueryConfig,
    response,
    warnings::Vector{String},
    exceptions::Vector{Exception},
)::PrometheusQueryResult

    r = try JSON3.read(response.body |> String, PrometheusQueryResponse{PrometheusInstantQuery});
    catch e
        push!(exceptions, e)
        push!(exceptions, ErrorException("Prometheus query results JSON parsing failed with body: $(String(response.body))"))
        return promql_error(warnings, exceptions)
    end

    if r.status != "success"
        push!(exceptions, ErrorException("Prometheus query ended in success = false; body = $(response.body)"))
        return promql_error(warnings, exceptions)
    end

    data = r.data.result
    data_type = r.data.resultType

    if data_type != "vector"
        push!(exceptions, "Expected type \"vector\", got unsupported type returned in query: $(data_type)")
        return promql_error(warnings, exceptions)
    end

    labels = Dict{String, Vector{Union{String, Nothing}}}()
    vals = (ts=DateTime[], value=Float64[])

    if isempty(data)
        push!(warnings, "promql(PrometheusQueryResult): Query returned zero values")
        return PrometheusQueryResult(empty_df, warnings, exceptions)
    end

    filter_labels = q.filter_labels
    if "__name__" ∉ filter_labels
        push!(filter_labels, "__name__")
    end

    all_labels = Set{String}(filter(
        x -> x ∉ filter_labels,
        reduce(vcat, [keys(result.metric) |> collect for result in r.data.result])
    ))
    dfs = Distributed.pmap(r.data.result) do result
        df_pairs = Pair[]
        for metric in all_labels
            v = get(result.metric, metric, nothing)
            push!(df_pairs, metric => v)
        end

        push!(df_pairs, "ts" => result.value.ts)
        push!(df_pairs, "value" => result.value.value)
        
        DataFrame(df_pairs)
    end

    return PrometheusQueryResult(
        sort(reduce(vcat, dfs), :ts),
        warnings,
        exceptions
    )
end

function prom_range_query_df(
    q::PrometheusQueryConfig,
    response,
    warnings::Vector{String},
    exceptions::Vector{Exception},
)::PrometheusQueryResult

    r = try JSON3.read(response.body |> String, PrometheusQueryResponse{PrometheusRangeQuery});
    catch e
        push!(exceptions, e)
        push!(exceptions, ErrorException("Prometheus query results JSON parsing failed with body: $(String(response.body))"))
        return promql_error(warnings, exceptions)
    end

    if r.status != "success"
        push!(exceptions, ErrorException("Prometheus query ended in success = false; body = $(response.body)"))
        return promql_error(warnings, exceptions)
    end

    if r.data.resultType != "matrix"
        push!(exceptions, "Expected type \"vector\", got unsupported type returned in query: $(r.data.resultType)")
        return promql_error(warnings, exceptions)
    end
    
    if isempty(r.data.result)
        push!(warnings, "prom_range_query_df(PrometheusQueryResult): Query returned zero values")
        return PrometheusQueryResult(empty_df, warnings, exceptions)
    end

    filter_labels = q.filter_labels
    if "__name__" ∉ filter_labels
        push!(filter_labels, "__name__")
    end

    all_labels = Set{String}(filter(
        x -> x ∉ filter_labels,
        reduce(vcat, [keys(result.metric) |> collect for result in r.data.result])
    ))
    dfs = Distributed.pmap(r.data.result) do result
        df_pairs = Pair[]
        for metric in all_labels
            v = get(result.metric, metric, nothing)
            push!(df_pairs, metric => fill(v, length(result.values)))
        end

        push!(df_pairs, "ts" => DateTime[data.ts for data in result.values])
        push!(df_pairs, "value" => Float64[data.value for data in result.values])
        
        DataFrame(df_pairs)
    end

    return PrometheusQueryResult(
        sort(reduce(vcat, dfs), :ts),
        warnings,
        exceptions
    )
end

function promql(p::PrometheusQueryClient, q::PrometheusQueryConfig)::PrometheusQueryResult
    warnings = String[]
    exceptions = Exception[]

    instant_query = q.instant_query
    range_query = q.range_query

    if instant_query && range_query || !(instant_query || range_query)
        push!(warnings, "promql(PrometheusQuery): instant_query and range_query are both set to $(instant_query && range_query)")

        instant_query = !isnothing(q.time)
        range_query = !isnothing(q.start_date)

        if instant_query && range_query
            push!(warnings, "promql(PrometheusQuery): both query `time` and `start_date` are defined, causing instant_query and range_query to default to `true`. Defaulting to: instant_query=$(instant_query), query_range=$(query_range)")
            instant_query = false
        end
    end

    if q.range_query && isnothing(q.start_date)
        push!(exceptions, ArgumentError("expecting range_query but start_date is empty"))
    end

    if !isempty(exceptions)
        return promql_error(warnings, errors)
    end

    params = Dict(
        "query" => q.query,
        "timeout" => string(round(q.timeout, Dates.Second) |> Dates.value) * 's',
        "limit" => q.limit |> string
    )

    if instant_query
        params["time"] = Dates.format(q.time, RFC3339_FORMAT)
    else
        params["start"] = Dates.format(q.start_date, RFC3339_FORMAT)
        params["end"] = isnothing(q.end_date) ?
            Dates.format(now(UTC), RFC3339_FORMAT) :
            Dates.format(q.end_date, RFC3339_FORMAT)
        params["step"] = string(round(q.step, Dates.Second) |> Dates.value) * "s"

        if q.end_date |> isnothing
            push!(warnings, "promql(PrometheusQuery): defaulted to end_time=now(UTC) because end_date is empty")
        end
    end

    query_type = instant_query ?
        "query" :
        "query_range"

    url = promclient_url_normalize(p) * query_type
    response = try HTTP.post(url; body=params);
    catch e
        push!(exceptions, e)
    end

    if !isempty(exceptions)
        return promql_error(warnings, exceptions)
    end

    return instant_query ?
        prom_instant_query_df(q, response, warnings, exceptions) :
        prom_range_query_df(q, response, warnings, exceptions)
end

function promql(client::Vector{PrometheusQueryClient}, query::String)::Union{Nothing, DataFrame}
    return vcat(promql.(client, query))
end

function prom_labels(p::PrometheusQueryClient)::Vector{String}
    url = promclient_url_normalize(p) * "labels"
    response = HTTP.get(url)
    r = JSON.parse(String(response.body))

    if r["status"] != "success"
        error("Prometheus query failed: $(r.error)")
    end

    return r["data"]
end

Base.@kwdef struct PrometheusMetric
    metric::String
    help::String
    target::Dict{String, Any}
    unit::Union{String, Nothing}
    type::String
end

function prom_metrics(p::PrometheusQueryClient)::Vector{String}
    url = promclient_url_normalize(p) * "label/__name__/values"
    response = HTTP.get(url)
    r = JSON.parse(String(response.body))

    if r["status"] != "success"
        error("Prometheus query failed: $(r.error)")
    end

    return r["data"]
end

end