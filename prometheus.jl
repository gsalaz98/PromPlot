using Dates

using HTTP
using JSON
using DataFrames
using DataFramesMeta
using GLMakie
using TimeseriesTools

import UnicodePlots


Base.@kwdef struct PrometheusQueryClient
    url::String = "http://localhost:9090"
    api::String = "/api/v1/"
end

const RFC3339_FORMAT = Dates.dateformat"yyyy-mm-ddTHH:MM:SS.sZ"

function promql(
    client::PrometheusQueryClient, 
    query::String; 
    startdate::Union{Nothing, Union{String, DateTime}}=nothing,
    enddate::Union{Nothing, Union{String, DateTime}}=nothing,
    step::Union{Nothing, String}=nothing,
    timeout::Union{Nothing, String}=nothing)::Union{Nothing, DataFrame}

    # Remove potential whitespace and append a trailing slash
    url = rstrip(rstrip(client.url), '/') * client.api * "query_range"
    fallback_query_url = rstrip(rstrip(client.url), '/') * client.api * "query"

    if isnothing(startdate)
        startdate = Dates.format(now(UTC) - Dates.Hour(2), RFC3339_FORMAT)
    elseif isa(startdate, DateTime)
        startdate = Dates.format(startdate, RFC3339_FORMAT)
    end
    if isnothing(enddate)
        enddate = Dates.format(now(UTC), RFC3339_FORMAT)
    elseif isa(enddate, DateTime)
        enddate = Dates.format(enddate, RFC3339_FORMAT)
    end
    if isnothing(step)
        step = "1m"
    end
    if isnothing(timeout)
        timeout = "30s"
    end

    params = Dict(
        "query" => query,
        "start" => startdate,
        "end" => enddate,
    )

    if !isnothing(step)
        params["step"] = step
    end
    if !isnothing(timeout)
        params["timeout"] = timeout
    end

    attempt_fallback = false
    repsonse = try response = HTTP.post(url; body=params);
    catch e
        println("Prometheus query_range request failed: $e, attempting fallback query"); 
        attempt_fallback = true
    end

    if attempt_fallback
        response = try HTTP.post(fallback_query_url; body=Dict(
            "query" => query,
            "timeout" => timeout
        ));
        catch e
            error("Prometheus query request failed: $e")
        end
    end

    r_json = try JSON.parse(String(response.body));
    catch e
        println(response.body)
        error("Prometheus query results JSON parsing failed: $e")
    end;

    if r_json["status"] != "success"
        error("Prometheus query error: $(r_json.error)")
    end

    data = r_json["data"]["result"]
    data_type = r_json["data"]["resultType"]

    supported_types = ["matrix", "vector"]#, "scalar", "string"]
    if !(data_type in supported_types)
        error("Unsupported type returned in query: $data_type")
    end

    # Todo: expand functionality to allow omitting labels from results
    exclude_labels = Dict("__name__" => true)
    labels = Dict{String, Vector{Union{String, Nothing}}}()
    vals = (ts=Float64[], value=Float64[])

    if isempty(data)
        return nothing
    end

    for result in data
        if data_type == "vector"
            push!(vals[:ts], result["value"][1])
            push!(vals[:value], parse(Float64, result["value"][2]))
            for (label, removelabel) in exclude_labels
                if removelabel
                    delete!(result["metric"], label)
                end
            end
            for (k, v) in result["metric"]
                labelcol = get!(labels, k, Union{String, Nothing}[])
                push!(labelcol, v)
            end
            for k in keys(labels)
                if !haskey(result["metric"], k)
                    labelcol = get!(labels, k, Union{Nothing, String}[])
                    push!(labelcol, nothing)
                end
            end
        elseif data_type == "matrix"
            for entry in result["values"]
                push!(vals[:ts], entry[1])
                push!(vals[:value], parse(Float64, entry[2]))
            end
            for (label, removelabel) in exclude_labels
                if removelabel
                    delete!(result["metric"], label)
                end
            end

            fill_length = length(result["values"])
            for (k, v) in result["metric"]
                labelcol = get!(labels, k, Union{Nothing, String}[])
                append!(labelcol, fill(v, fill_length))
            end
            # Fill in any missing values as Nothing.
            # This will guarantee that we've added all the values possible
            # from here on out and are effectively forward filling the values.
            # However, if we encounter a new value for a label and we're already
            # somewhat deep into adding label values, we'll have to go back and
            # fill in the missing values from the start of the data, according to
            # what max(length(labels)) - length(labels[k]) is
            for k in keys(labels)
                if !haskey(result["metric"], k)
                    labelcol = get!(labels, k, Union{Nothing, String}[])
                    append!(labelcol, fill(nothing, fill_length))
                end
            end
        end
    end

    # Find any labels that need to have nothings added in to the start of the
    # arrays to pad out the data to be the same length as the longest label
    maxlen = maximum(length, values(labels))
    for v in labels |> values
        if length(v) < maxlen
            prepend!(v, fill(nothing, maxlen - length(v)))
        end
    end

    return sort(hcat(DataFrame(labels), DataFrame(vals)), :ts)
end

function promql(client::Vector{PrometheusQueryClient}, query::String)::Union{Nothing, DataFrame}
    return vcat(promql.(client, query))
end

function prom_labels(client::PrometheusQueryClient)::Vector{String}
    url = client.url * "labels"
    response = HTTP.get(url)
    r_json = JSON.parse(String(response.body))

    if r_json["status"] != "success"
        error("Prometheus query failed: $(r_json.error)")
    end

    return r_json["data"]
end

Base.@kwdef struct PrometheusMetric
    metric::String
    help::String
    target::Dict{String, Any}
    unit::Union{String, Nothing}
    type::String
end

function prom_metrics(client::PrometheusQueryClient)::Vector{PrometheusMetric}
    url = rstrip(rstrip(client.url), '/') * '/' * client.api * "targets/metadata"
    response = HTTP.get(url)
    r_json = JSON.parse(String(response.body))

    if r_json["status"] != "success"
        error("Prometheus query failed: $(r_json.error)")
    end

    data = r_json["data"]
    return [PrometheusMetric(
        metric=get(i, "metric", nothing),
        help=get(i, "help", nothing),
        target=get(i, "target", nothing),
        unit=get(i, "unit", nothing),
        type=get(i, "type", nothing)
    ) for i in data]
end