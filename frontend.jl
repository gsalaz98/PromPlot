using GLMakie
using UnicodePlots

include("prometheus.jl")
include("utils.jl")


const FONT_COURIER = Makie.to_font("Courier")

const MAX_LEGEND_ENTRY_CHAR_LIMIT = 40
const MAX_LEGEND_CHAR_LIMIT = 140

const RED::RGBAf = RGBAf(1.0, 0.0, 0.0, 1.0)
const WHITE::RGBAf = RGBAf(1.0, 1.0, 1.0, 1.0)
const VERY_DARK::RGBAf = RGBAf(0.1, 0.1, 0.1, 1.0)

const NORMAL_CURSOR = GLMakie.GLFW.CreateStandardCursor(GLMakie.GLFW.ARROW_CURSOR)
const HAND_CURSOR = GLMakie.GLFW.CreateStandardCursor(GLMakie.GLFW.HAND_CURSOR)


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
        label_count = length(split(label, ","))

        for (idx, col) in enumerate(split(label, ","))
            # Truncate per column so that we can fit more columns in the legend
            if length(col) > MAX_LEGEND_ENTRY_CHAR_LIMIT
                col = col[begin:MAX_LEGEND_ENTRY_CHAR_LIMIT - 3] * "..."
            end

            if idx < label_count
                # Get the minimum of the column width or the max entry, since we are
                # going to be truncating the label anyway
                final_label *= lpad(col, min(cols[idx], MAX_LEGEND_ENTRY_CHAR_LIMIT)) * ", "
            else
                final_label *= col
            end
        end

        if length(final_label) > MAX_LEGEND_CHAR_LIMIT
            final_label = final_label[begin:MAX_LEGEND_CHAR_LIMIT - 3]
            if !endswith(final_label, "...")
                final_label *= "..."
            end
        end
        push!(formatted_labels, final_label)
    end

    return formatted_labels
end

function render_data(fig, layout, ax, df, status_label; page=1, is3d=false, series_limit=100)
    try empty!(ax); catch _; end;

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
        Button(
            layout[1, 2];
            label="",
            buttoncolor=series[idx].color
        ) for idx in labels |> eachindex
    ]
    
    formatted_labels = [
        Label(
            layout[1, 2];
            text=i,
            font=FONT_COURIER,
            fontsize=14
        ) for i in format_label_table(labels)
    ]

    series_indexes = Dict()
    for (idx, s) in enumerate(series)
        series_indexes[s] = idx
    end


    # Pagination for the Legend
    prev_button = Button(layout[2, 2]; label="Previous", buttoncolor=:blue)
    next_button = Button(layout[2, 2]; label="Next", buttoncolor=:blue)

    layout[1, 2] = grid!(hcat(toggles, formatted_labels))
    layout[2, 2] = grid!(hcat(prev_button, next_button))

    colsize!(layout, 1, Aspect(1, 1))

    glscreen = display(fig).glscreen

    for b in toggles
        on(b.clicks) do e
            # Scan all of the active toggles and hide series that are inactive.
            # We show all series if all toggles are set to inactive.
            if all(x -> x.clicks.val % 2 == 0, toggles)
                for (idx, t) in enumerate(toggles)
                    series_visible[idx][] = true
                    t.buttoncolor[] = RGBAf(t.buttoncolor.val.r, t.buttoncolor.val.g, t.buttoncolor.val.b, 1.0)
                end
                return Consume(false)
            end

            for (idx, t) in enumerate(toggles)
                # The number of clicks will be odd if the toggle is active
                is_active = t.clicks[] % 2 == 1
                series_visible[idx][] = is_active
                t.buttoncolor[] = RGBAf(
                    t.buttoncolor.val.r,
                    t.buttoncolor.val.g,
                    t.buttoncolor.val.b,
                    is_active ? 1.0 : 0.25)
            end

            return Consume(false)
        end

        active = nothing
        requires_reset = false
        on(events(fig).mouseposition) do m
            p, _ = pick(fig)

            if active != p && !isnothing(active)
                active.linewidth[] = 1.5
                active = nothing
            end

            if isnothing(p)
                GLMakie.GLFW.SetCursor(glscreen, NORMAL_CURSOR)
                if requires_reset
                    for t in toggles 
                        t.buttoncolor[] = RGBAf(t.buttoncolor.val.r, t.buttoncolor.val.g, t.buttoncolor.val.b, 1.0)
                    end
                end

                requires_reset = false
                return Consume(false)
            end

            if p in series
                p.linewidth[] = 5.0
                active = p
                GLMakie.GLFW.SetCursor(glscreen, HAND_CURSOR)
                requires_reset = true
                # Darken the rest of the legends to show which value we have selected
                seriesidx = series_indexes[p]

                for (idx, t) in enumerate(toggles)
                    t.buttoncolor[] = RGBAf(
                        t.buttoncolor.val.r,
                        t.buttoncolor.val.g,
                        t.buttoncolor.val.b,
                        idx == seriesidx ? 1.0 : 0.25
                    )
                end
            end

            return Consume(false)
        end
    end

    return vcat(toggles, formatted_labels, prev_button, next_button)
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

    is3d_button = Button(
        fig;
        label="3D Plot",
        buttoncolor=:blue,
        labelcolor=:white,
    )

    live_mode_button = Button(
        fig;
        label="Live Data",
        buttoncolor=:blue,
        labelcolor=:white,
    )

    user_layout[1, 1] = grid!(
        hcat(
            is3d_button,
            live_mode_button,
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
    gc = nothing
    is3d = false

    on(is3d_button.clicks) do clicks
        delete!(ax)

        is3d = clicks % 2 != 0
        ax = is3d ?
            Axis3(plot_layout[1, 1]) :
            Axis(plot_layout[1, 1])

        # Counter-intuitive, but if we toggled 3D, we want to have the option to revert
        if is3d
            is3d_button.label[] = "2D Plot"
        else
            is3d_button.label[] = "3D Plot"
        end

        if validate_df(df, status_label; update_text=false)
            if !isnothing(gc)
                for g in gc
                    delete!(g)
                end
            end
            gc = render_data(fig, plot_layout, ax, df, status_label, is3d=is3d, series_limit=series_limit)
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
            if !isnothing(gc)
                for g in gc
                    delete!(g)
                end
            end
            gc = render_data(fig, plot_layout, ax, df, status_label, is3d=is3d, series_limit=series_limit)
        end

        return Consume(false)
    end

    return fig
end