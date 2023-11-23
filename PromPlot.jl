using ArgParse

include("prometheus.jl")

if abspath(PROGRAM_FILE) != @__FILE__
    return
end

include("plot_gui.jl")
include("plot_tui.jl")

function main()
    s = ArgParseSettings(exit_after_help=true, autofix_names=true)
    add_arg_table(s,
        "--promql",
        Dict(
            :help => "Prometheus PromQL Query (required)",
            :default => nothing
        ),
        "--gui",
        Dict(
            :help => "Plot in GUI - Required for 3D Mode",
            :arg_type => Bool,
            :default => false
        ),
        "--tui",
        Dict(
            :help => "Plot in CLI/TUI",
            :arg_type => Bool,
            :default => true
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
        ),
        "--step",
        Dict(
            :help => "Query Resolution (default = 1m)",
            :arg_type => String,
            :default => "1m"
        ),
        "--realtime",
        Dict(
            :help => "Enable realtime updates (default = false)",
            :arg_type => Bool,
            :default => true
        ),
        "--realtime-update",
        Dict(
            :help => "Realtime update interval (default = 5s)",
            :arg_type => String,
            :default => "5s"
        ),
        "--realtime-range",
        Dict(
            :help => "Realtime update range (default = 1h)",
            :arg_type => String,
            :default => "1h"
        ),
    )


    args = parse_args(s; as_symbols=true)

    if args[:promql] === nothing || isempty(args[:promql])
        ArgParse.show_help(s)
        return
    end

    # TODO: Add support for multiple clients to query multiple clusters in one plot
    p = PrometheusQueryClient(url=args[:url])

    if !test_prometheus_connection(p)
        println("Prometheus connection to $(args[:url]) failed, exiting...")
        return
    end

    is_gui_plot = args[:gui]
    is_tui_plot = args[:tui]

    if is_tui_plot && !is_gui_plot
        init_terminal(
            p; 
            query=args[:promql],
            startdate=args[:start],
            enddate=args[:end],
            update_resolution=args[:step],
            realtime=args[:realtime],
            realtime_update=args[:realtime_update],
            realtime_range=args[:realtime_range],
            series_limit=args[:limit]
        )

        exit()
    end

    if is_gui_plot
        fig = init_window(
            p; 
            query=args[:promql],
            series_limit=args[:limit],
            is3d=args[:is3d],
            startdate=args[:start],
            enddate=args[:end], 
            update_resolution=args[:step]
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
            exit()
        end
    end
end

main()