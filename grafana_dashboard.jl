begin
using Dates
using GLMakie
using JSON

include("prometheus.jl")
include("utils.jl")
include("plot_gui.jl")

function dashboard(
    p::PrometheusQueryClient,
    dashboard_file::String;
    is3d::Bool=false,
    startdate::Union{Nothing, Union{DateTime, String}}=nothing,
    enddate::Union{Nothing, Union{DateTime, String}}=nothing,
    update_resolution::Union{Nothing, String}=nothing,
)
    initial_resolution = (3840, 2160)
    GLMakie.activate!(; framerate=60.0)
    set_theme!(theme_black(); resolution=initial_resolution, framerate=60.0)
    fig = Figure(resolution=initial_resolution)

    grafana_dashboard = JSON.parsefile(dashboard_file)
    if !haskey(grafana_dashboard, "panels")
        println("Invalid Grafana dashboard file, exiting...")
        return
    end

    panels = grafana_dashboard["panels"]
    if length(panels) == 0
        println("No panels found in Grafana dashboard file, exiting...")
        return
    end

    grafana_time_from = grafana_dashboard["time"]["from"]
    grafana_time_to = grafana_dashboard["time"]["to"]
    
    nowutc = now(UTC)

    startdate = nothing
    enddate = nothing

    if occursin("now", grafana_time_from)
        now_split = split(grafana_time_from, "-")
        # Assume that `now` is the first element. The second
        # element is the period to subtract from `now`
        if length(now_split) == 1
            error("We don't support this yet, only `now` start times are supported")
        end

        grafana_dashboard_start_period = parse_period(now_split[2])
        startdate = string(nowutc - grafana_dashboard_start_period) * "Z"
    end

    if occursin("now", grafana_time_to)
        now_split = split(grafana_time_to, "-")
        # Assume that `now` is the first element. The second
        # element is the period to subtract from `now`
        if length(now_split) == 1 && now_split[1] == "now"
            enddate = string(nowutc) * "Z"
        else
            grafana_dashboard_end_period = parse_period(now_split[2])
            enddate = string(nowutc - grafana_dashboard_end_period) * "Z"
        end
    end


    ax_layout = GridLayout(3, 2)

    colsize!(ax_layout, 1, Relative(0.5))
    colsize!(ax_layout, 2, Relative(0.5))

    fig[1, 1] = ax_layout
    
    prev_charts_button = Button(
        ax_layout[3, 1];
        label="Previous Page",
        buttoncolor=:blue,
        labelcolor=:white,
        halign=:left
    )

    next_charts_button = Button(
        ax_layout[3, 2];
        label="Next Page",
        buttoncolor=:blue,
        labelcolor=:white,
        halign=:right
    )
    
    ax_layout[3, 1] = prev_charts_button
    ax_layout[3, 2] = next_charts_button

    for (idx, panel) in panels |> enumerate
        grafana_queries = panel["targets"]
        title = panel["title"]

        row = min(2, convert(Int, ceil(idx / 2)))
        col = min(2, ((idx - 1) % 2) + 1)

        plot_layout = GridLayout(2, 1)
        ax_layout[row, col] = plot_layout

        ax = Axis(plot_layout[1, 1]; width=Relative(0.85))

        for grafana_query in grafana_queries
            query = grafana_query["expr"]
            df = promql(
                p,
                query;
                startdate=startdate,
                enddate=enddate,
                step=update_resolution
            )

            if isnothing(df)
                println("No data returned from Prometheus. Exiting...")
                return
            end

            render_data!(
                fig,
                plot_layout,
                ax,
                df,
                "",
                query=query,
                orientation=:row,
                startdate=startdate,
                enddate=enddate
            )
        end
        
        ax.title[] = title
    end

    display(fig)
    return
end

p = PrometheusQueryClient(url="http://192.168.39.20:31993")
dashboard(p, "dashboards/grafana.json")
end