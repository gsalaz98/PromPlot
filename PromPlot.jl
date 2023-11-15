include("prometheus.jl")
include("frontend.jl")

p = PrometheusQueryClient()
init_window(p; series_limit=20)