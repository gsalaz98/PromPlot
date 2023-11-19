using ArgParse

if abspath(PROGRAM_FILE) != @__FILE__
    include("prometheus.jl")
    include("plot_gui.jl")
    return
end

s = ArgParseSettings(exit_after_help=true)
add_arg_table(s,
    "--promql",
    Dict(
        :help => "Prometheus PromQL Query (required)",
        :default => nothing
    ),
    "--gui",
    Dict(
        :help => "Plot in GUI - Required for 3D Mode",
        :default => true
    ),
    "--tui",
    Dict(
        :help => "Plot in CLI/TUI",
        :default => false
    ),
    "--limit",
    Dict(
        :help => "Maximum number of series to plot",
        :arg_type => Int,
        :default => 25
    ),
    "--url",
    Dict(
        :help => "Prometheus URL",
        :arg_type => String,
        :default => "http://localhost:9090"
    ),
    "--is3d",
    Dict(
        :help => "Start in 3D Plotting Mode",
        :default => false
    ),
    "--start",
    Dict(
        :help => "Query Start Date (default = now(UTC) - 2h)",
        :arg_type => String,
        :default => nothing
    ),
    "--end",
    Dict(
        :help => "Query End Date (default = now(UTC))",
        :arg_type => String,
        :default => nothing
    )
)


args = parse_args(s; as_symbols=true)

if args[:promql] === nothing || isempty(args[:promql])
    ArgParse.show_help(s)
    return
end

include("prometheus.jl")
# TODO: Add support for multiple clients to query multiple clusters in one plot
p = PrometheusQueryClient(url=args[:url])

if !test_prometheus_connection(p)
    println("Prometheus connection to $(args[:url]) failed, exiting...")
    return
end

is_gui_plot = args[:gui]
if is_gui_plot
    include("plot_gui.jl")
    fig = init_window(
        p; 
        query=args[:promql],
        series_limit=args[:series_limit],
        is3d=args[:is3d],
        startdate=args[:start],
        enddate=args[:end]
    )

    display(fig)

    close_window = Channel{Bool}(1)
    on(events(fig).window_open) do window_open
        if !window_open
            println("Exiting plot...")
            put!(close_window, true)
        end
    end

    if take!(close_window)
        return
    end
end