using Dates
using DataFrames
using DataFramesMeta
using JSON3

include("./prometheus.jl")
include("./PrometheusQuery.jl")

using .PrometheusClient
using .PrometheusTypes

#rangeq = JSON3.read("./out_matrix.json", PrometheusQueryResponse{PrometheusRangeQuery});
#instant = JSON3.read("./out_instant.json", PrometheusQueryResponse{PrometheusInstantQuery});

p = PrometheusQueryClient(url="http://localhost:8481", api="/select/0/prometheus/api/v1")
q = PrometheusQueryConfig(query="apiserver_response_sizes_sum",
    #time=unix2datetime(1750893930.297),
    start_date=now(UTC) - Dates.Second(60),
    end_date=now(UTC),
    filter_labels=["component", "group", "job"],
    limit=1)

#labels = prom_metrics(p)

result = promql(p, q)