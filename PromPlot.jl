include("prometheus.jl")
include("frontend_gui.jl")

p = PrometheusQueryClient(url="http://192.168.39.20:31565")
init_window(p; query="irate(container_cpu_usage_seconds_total[1m]) != 0", series_limit=25)