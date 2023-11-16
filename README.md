# PromPlot
Plot Prometheus graphs in the command line or in a GUI with [`Makie.jl`](https://github.com/MakieOrg/Makie.jl)

![Example PromPlot 2D Graphing Display](./docs/promplot_example_2d.png)
![Example PromPlot 3D Graphing Display](./docs/promplot_example_3d.png)

# Getting started
TODO, but some instructions on getting a local dev environment setup are as follows:

Eventually, I want to make this installable via `krew` so that it can be used as a `kubectl` plugin.

### Quick Start
1. Set the `url` in `PromPlot.jl` for the `PrometheusQueryClient`
2. `julia PromPlot.jl`
3. Type your query in to the Textbox

Note: PromPlot will default to `http://localhost:9090` for Prometheus server is no URL is specified
