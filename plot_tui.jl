using Dates
using Tidier
using TerminalUserInterfaces
const TUI = TerminalUserInterfaces
using UnicodePlots

include("prometheus.jl")
include("utils.jl")


@kwdef mutable struct PlotOut
    fig::String
end

@kwdef mutable struct Model <: TUI.Model
    p::PrometheusQueryClient
    query::Union{Nothing, String} = nothing
    startdate::Union{Nothing, Union{DateTime, String}} = nothing
    enddate::Union{Nothing, Union{DateTime, String}} = nothing
    update_resolution::Union{Nothing, String} = nothing
    series_limit::Int = 25
    realtime::Bool = true
    realtime_range::Period = Dates.Hour(1)
    realtime_update_period::Period = Dates.Second(5)

    df::Union{Nothing, DataFrame} = nothing
    plotindex::Int = 0
    plots::Vector{PlotOut} = []
    plotlabel_current::Union{Nothing, String} = nothing
    plotlabels::Vector{Dict{String, String}} = []
    plotindexesbylabel::Dict{String, Int} = Dict()

    quit::Bool = false
end

function TUI.init!(m::Model, t::TUI.TerminalBackend)
    if !m.realtime
        return
    end

    # Recreation of the event loop of the TUI library
    # so that we can update the model in realtime
    while !m.quit
        evt = TUI.try_get_event(t, wait=Dates.Second(m.realtime_update_period).value)
        isnothing(evt) ?
            update!(m) :
            TUI.update!(m, evt)

        TUI.render(t, m)
        TUI.draw(t)
    end
end

function get_title_padding(fig)
    padding = 0
    for (idx, c) in fig |> enumerate
        if c == ' '
            padding = idx
        else
            break
        end
    end

    return padding
end

function TUI.render(p::PlotOut, area::TUI.Rect, buf::TUI.Buffer)
    padding = get_title_padding(p.fig)
    final_fig = [!startswith(i, ' ') ? repeat(' ', padding) * i : i for i in split(p.fig, "\n")]

    for (idx, row) in enumerate(final_fig)
        for (cidx, c) in enumerate(row)
            TUI.set(buf, cidx, idx, c, TUI.Crayon())
        end
    end
end

function reduce_title_length(labels)
    title = ""
    current_line = ""
    label_length = length(labels)

    for (idx, label) in enumerate(labels)
        # Limit to 3 labels per line in the title
        if length(current_line) >= 60
            title *= current_line
            title *= '\n'
            current_line = ""
        end
        
        current_line *= label
        if idx != label_length
            current_line *= ", "
        end
    end

    title *= current_line
    return title
end

function TUI.view(m::Model)
    if isnothing(m.df)
        return
    end

    empty!(m.plots)
    dfgroup = groupby(m.df, allbut(m.df, [:ts, :value]))

    for (idx, dfg) in dfgroup |> enumerate
        colnames = allbut(dfg, [:ts, :value])
        colvalues = values(dfg[1, allbut(dfg, [:ts, :value])])

        labels = ["$i=$j" for (i, j) in zip(colnames, colvalues)]
        labels_sorted = join(sort(labels))

        m.plotindexesbylabel[labels_sorted] = idx

        plot = lineplot(
            unix2datetime.(dfg[:, :ts]), 
            dfg[:, :value]; 
            title=reduce_title_length(labels),
            xlabel="Time", 
            format="u dd HH:MM:SS"
        )

        out = string(plot; color=false)
        padding = get_title_padding(out)

        header = repeat(' ', padding) * "Query: " * m.query
        header *= "\n"
        header *= repeat(' ', padding) * "Start: " * m.startdate * ", End: " * m.enddate * ", Step: " * m.update_resolution
        header *= "\n"
        header *= repeat(' ', padding) * "Labels:\n"

        out = header * out

        push!(m.plots, PlotOut(out))
    end

    if isnothing(m.plotlabel_current)
        m.plotlabel_current = m.plotindexesbylabel |> keys |> first
    end

    m.plotindex = m.plotindexesbylabel[m.plotlabel_current]
    m.plots[m.plotindex]
end


function update!(m::Model)
    nowutc = now(UTC)
    m.enddate = Dates.format(nowutc, RFC3339_FORMAT)
    m.startdate = Dates.format(nowutc - m.realtime_range, RFC3339_FORMAT)

    m.df = promql(
        m.p,
        m.query;
        startdate=m.startdate,
        enddate=m.enddate,
        step=m.update_resolution
    )

    if isnothing(m.df)
        return
    end
end

function TUI.update!(m::Model, event::TUI.KeyEvent)
    if TUI.keycode(event) == "q" && event.data.kind == "Press"
        m.quit = true
        return
    end

    if !m.realtime
        return
    end

    update!(m)
end

function init_terminal(
    p::PrometheusQueryClient;
    query::Union{Nothing, String}=nothing,
    startdate::Union{Nothing, Union{DateTime, String}}=nothing,
    enddate::Union{Nothing, Union{DateTime, String}}=nothing,
    update_resolution::Union{Nothing, String}=nothing,
    realtime::Bool=true,
    realtime_update::String="5s",
    realtime_range::String="1h",
    series_limit::Int=25,
)

    if isnothing(query)
        return
    end
    
    realtime_range_period = parse_period(realtime_range)
    realtime_update_period = parse_period(realtime_update)

    startdate = get_startdate(startdate)
    enddate = get_enddate(enddate)

    if isnothing(update_resolution)
        update_resolution = "1m"
    end

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

    m = Model(
        p,
        query,
        startdate,
        enddate,
        update_resolution,
        series_limit,
        realtime,
        realtime_range_period,
        realtime_update_period,
        
        df,
        0,
        PlotOut[],
        nothing,
        [],
        Dict(),

        false
    )

    TUI.app(m)
end