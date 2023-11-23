# PromPlot
Plot Prometheus graphs in the command line and GUI, with realtime support.

## Notice
I am currently looking for work. If you would like to have me on your team, please reach out to `gerardo@salazar.pub`

# Demo
![Example PromPlot 2D CLI Plot Realtime](./docs/promplot_example_cli.gif)
![Example PromPlot 2D Graphing Display](./docs/promplot_example_2d.png)
![Example PromPlot 3D Graphing Display](./docs/promplot_example_3d.png)

# Getting started
Making this application installable via `krew` is in the roadmap and will hopefully be the
preferred method of installation in the future.

### Quick Start
1. `julia` (start REPL)
2. `] activate .`
3. `] instantiate`
4. `exit()`
5. `julia --project=. PromPlot.jl --promql "idelta((sum by (method, path) (kubelet_http_requests_duration_seconds_sum))[24h:])" --url "http://prometheus.my-cluster.k8s.internal:9090"`
6. Replace the `--url` argument with your Prometheus server

### Available options:
```
usage: PromPlot.jl [--promql PROMQL] [--gui GUI] [--tui TUI]
                   [--limit LIMIT] [--url URL] [--is3d IS3D]
                   [--start START] [--end END] [--step STEP]
                   [--realtime REALTIME]
                   [--realtime-update REALTIME_UPDATE]
                   [--realtime-range REALTIME_RANGE] [-h]

optional arguments:
  --promql PROMQL       Prometheus PromQL Query (required)
  --gui GUI             Plot in GUI - Required for 3D Mode (type: Bool, default: false)
  --tui TUI             Plot in CLI/TUI (type: Bool, default: true)
  --limit LIMIT         Maximum number of series to plot (type: Int64, default: 25)
  --url URL             Prometheus URL (default: "http://localhost:9090")
  --is3d IS3D           Start in 3D Plotting Mode (default: false)
  --start START         Query Start Date (default = now(UTC) - 2h)
  --end END             Query End Date (default = now(UTC))
  --step STEP           Query Resolution (default: "1m")
  --realtime REALTIME   Enable realtime updates (type: Bool, default: true)
  --realtime-update     Realtime update interval (default: "5s")
  --realtime-range      Realtime update range (default: "1h")
  -h, --help            show this help message and exit
```