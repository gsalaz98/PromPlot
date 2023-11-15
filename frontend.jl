using GLMakie
using UnicodePlots

include("prometheus.jl")
include("utils.jl")


const FONT_COURIER = Makie.to_font("Courier")
const MAX_LEGEND_CHAR_LIMIT = 180

const RED::RGBAf = RGBAf(1.0, 0.0, 0.0, 1.0)
const WHITE::RGBAf = RGBAf(1.0, 1.0, 1.0, 1.0)
const VERY_DARK::RGBAf = RGBAf(0.1, 0.1, 0.1, 1.0)

function format_label_table(labels::Vector{String})::Vector{String}
    # Takes a vector of strings split by ',' and returns a vector of strings
    # with equal width padding for each column
    cols = Dict()
    for label in labels
        for (idx, col) in enumerate(split(label, ","))
            colwidth = get!(cols, idx, 0)
            if length(col) > colwidth
                cols[idx] = length(col)
            end
        end
    end

    formatted_labels = []
    for label in labels
        final_label = ""
        for (idx, col) in enumerate(split(label, ","))
            if idx < length(split(label, ","))
                final_label *= lpad(col, cols[idx]) * ", "
            else
                final_label *= col
            end
        end

        if length(final_label) > MAX_LEGEND_CHAR_LIMIT
            final_label = final_label[begin:MAX_LEGEND_CHAR_LIMIT - 3] * "..."
        end
        push!(formatted_labels, final_label)
    end

    return formatted_labels
end

function render_data(fig, layout, ax, df, status_label; is3d=false, series_limit=100)
    try empty!(ax); catch _; end;
    # TODO: the legend is recreated each time we update the plot, and not 
    # thrown away to be collected, so we have duplicate data and it gets glitchy
    try delete!(layout[1, 2]); catch _; end;
    try delete!(layout[2, 2]); catch _; end;

    dfgroups = groupby(df, allbut(df, [:ts, :value]))
    series = []
    series_visible = Observable{Bool}[]
    labels = String[]

    for (idx, dfg) in dfgroups |> enumerate
        visible = Observable{Bool}(true)

        push!(labels, join(dfg[begin, allbut(dfg, [:ts, :value])], ","))
        push!(series_visible, visible)

        if is3d
            push!(series, lines!(
                ax, dfg[:, :ts] .- dfg[begin, :ts],
                fill(idx, size(dfg)[1]),
                dfg[:, :value];
                visible=visible
            ))
        else
            push!(series, lines!(
                ax,
                dfg[:, :ts] .- dfg[begin, :ts],
                dfg[:, :value];
                visible=visible
            ))
        end

        if idx >= series_limit
            status_label.text[] = "Total series count exceeded $series_limit, truncating series (total: $(length(dfgroups)))"
            break
        end
    end

    ax.xlabel[] = "Time (s)"
    if is3d
        ax.ylabel[] = "Series Index"
        ax.zlabel[] = "Value"
    else
        ax.ylabel[] = "Value"
    end

    toggles = [
        Toggle(
            fig;
            active=false,
            framecolor_active=:black,
            framecolor_inactive=VERY_DARK,
            buttoncolor=series[idx].color
        ) for idx in labels |> eachindex
    ]
    
    formatted_labels = [
        Label(
            fig;
            text=i,
            font=FONT_COURIER,
            fontsize=14
        ) for i in format_label_table(labels)
    ]

    layout[1, 2] = grid!(hcat(toggles, formatted_labels))
    # TODO: add pagination to the Legend
    #layout[2, 2] = Button(fig, label="Next >")

    colsize!(layout, 1, Aspect(1, 1))

    on(events(fig).mousebutton) do e
        if e.action !== Mouse.release
            return Consume(false)
        end

        # Scan all of the active toggles and hide series that are inactive.
        # We show all series if all toggles are set to inactive.
        if !all(x -> x.active.val, toggles)
            for (idx, t) in enumerate(toggles)
                series_visible[idx][] = true
            end

            return Consume(false)
        end

        for (idx, t) in enumerate(toggles)
            series_visible[idx][] = t.active.val
        end

        return Consume(false)
    end
end

function validate_df(df, status_label; update_text::Bool=true)::Bool
    if isnothing(df)
        if update_text
            status_label.color[] = RED
            status_label.text[] = "Prometheus returned no data"
        end
        return false
    end

    if update_text
        status_label.color[] = WHITE
    end

    return true
end

function init_window(p::PrometheusQueryClient; is3d=false, series_limit=100)
    initial_resolution = (3840, 2160)

    GLMakie.activate!(; framerate=60.0)
    set_theme!(theme_black(); resolution=initial_resolution, framerate=60.0)

    fig = Figure(resolution=initial_resolution)

    plot_layout = GridLayout(1, 2)
    user_layout = GridLayout(3, 1)

    fig[1, 1] = plot_layout
    fig[2, 1] = user_layout

    ax::Union{Axis, Axis3} = is3d ? 
        Axis3(plot_layout[1, 1]; aspect=1) :
        Axis(plot_layout[1, 1]; aspect=1)

    colsize!(plot_layout, 1, Aspect(1, 1))

    prev_toggle_status = false
    is3d_toggle = Toggle(
        fig;
        active=prev_toggle_status,
        framecolor_active=:black,
        framecolor_inactive=VERY_DARK
    )

    live_mode_toggle = Toggle(
        fig;
        active=false,
        framecolor_active=:black,
        framecolor_inactive=VERY_DARK
    )

    user_layout[1, 1] = grid!(
        hcat(
            is3d_toggle,
            Label(fig, "3D Plot", fontsize=16),
            live_mode_toggle,
            Label(fig, "Live Data", fontsize=16)
        )
    )

    tb = Textbox(
        user_layout[2, 1]; 
        placeholder="PromQL Query (e.g. `irate(container_cpu_usage_seconds_total{container_name=\"prometheus\"}[5m])`)",
        focused=true,
        fontsize=24,
        font=FONT_COURIER,
        width=Auto(),
        tellwidth=false,
    )
    status_label = Label(
        user_layout[3, 1];
        text=" ",
        font=FONT_COURIER,
        fontsize=16,
        width=Auto(),
        tellwidth=false
    )

    df::Union{Nothing, DataFrame} = nothing

    on(events(fig).mousebutton) do _ 
        if prev_toggle_status == is3d_toggle.active[]
            return Consume(false)
        end

        delete!(ax)

        prev_toggle_status = is3d_toggle.active[]
        ax = prev_toggle_status ? 
            Axis3(plot_layout[1, 1]) :
            Axis(plot_layout[1, 1])

        if validate_df(df, status_label; update_text=false)
            render_data(fig, plot_layout, ax, df, status_label, is3d=is3d_toggle.active[], series_limit=series_limit)
        end

        return Consume(false)
    end

    on(events(fig).keyboardbutton) do e
        if e.action !== Keyboard.release
            return Consume(false)
        end

        try 
            df = promql(p, tb.stored_string[])
        catch err
            status_label.color[] = RED
            status_label.text[] = "$err"
            return Consume(false)
        end

        if validate_df(df, status_label; update_text=true)
            render_data(fig, plot_layout, ax, df, status_label, is3d=is3d_toggle.active[], series_limit=series_limit)
        end

        return Consume(false)
    end

    return fig
end