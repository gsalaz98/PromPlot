using Dates
using GLMakie
using UnicodePlots

include("prometheus.jl")
include("utils.jl")


const FONT_COURIER = Makie.to_font("Courier")

const MAX_LEGEND_ENTRY_CHAR_LIMIT = 40
const MAX_LEGEND_CHAR_LIMIT = 140

const UPDATE_RESOLUTION_OPTIONS = [
    "1s",
    "2s",
    "5s",
    "10s",
    "30s",
    "1m",
    "2m",
    "5m",
    "10m",
    "20m",
    "30m",
    "1h"
]

const RED::RGBAf = RGBAf(1.0, 0.0, 0.0, 1.0)
const WHITE::RGBAf = RGBAf(1.0, 1.0, 1.0, 1.0)
const BLUE::RGBAf = RGBAf(0.0, 0.0, 1.0, 1.0)
const VERY_DARK::RGBAf = RGBAf(0.1, 0.1, 0.1, 1.0)
const BLACK::RGBAf = RGBAf(0.0, 0.0, 0.0, 1.0)

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

function render_data(fig, layout, ax, df, status_label; query=nothing, startdate=nothing, enddate=nothing, page=1, is3d=false, series_limit=100)
    try 
        # 3D plots don't have an empty! method defined, so let's clear the 
        # whole axis and start anew
        empty!(ax)

        if is3d
            delete!(ax)
            ax = is3d ? 
                Axis3(layout[1, 1]) : 
                Axis(layout[1, 1])
        end
    catch;
    end

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

    inspector = DataInspector(fig; range=0, enabled=false)

    ax.title[] = join(("Query: " * query, "Start: " * startdate * ", End: " * enddate), "\n")
    ax.titlesize[] = 24
    ax.titlefont[] = FONT_COURIER

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

    block_series = Dict()
    for (b, s) in zip(toggles, series)
        block_series[b] = s
    end

    layout[1, 2] = grid!(hcat(toggles, formatted_labels))

    glscreen = display(fig).glscreen

    for b in toggles
        has_toggled_legend = false

        on(b.clicks) do e
            # Scan all of the active toggles and hide series that are inactive.
            # We show all series if all toggles are set to inactive.
            if all(x -> x.clicks.val % 2 == 0, toggles)
                has_toggled_legend = false

                for (idx, t) in enumerate(toggles)
                    series_visible[idx][] = true
                    t.buttoncolor[] = RGBAf(t.buttoncolor.val.r, t.buttoncolor.val.g, t.buttoncolor.val.b, 1.0)
                end

                reset_limits!(ax)
                return Consume(true)
            end

            # Keep track if we've made any changes, so that we can reset the
            # limits of the graph if there are new graphs
            has_update = false

            for (idx, t) in enumerate(toggles)
                # The number of clicks will be odd if the toggle is active
                is_active = t.clicks[] % 2 == 1
                has_toggled_legend = has_toggled_legend || is_active

                previous_active = series_visible[idx].val
                series_visible[idx][] = is_active

                has_update = has_update || previous_active != is_active

                t.buttoncolor[] = RGBAf(
                    t.buttoncolor.val.r,
                    t.buttoncolor.val.g,
                    t.buttoncolor.val.b,
                    is_active ? 1.0 : 0.25)
            end

            if has_update
                reset_limits!(ax)
            end

            return Consume(true)
        end

        active = nothing
        requires_reset = false

        on(events(fig).mouseposition) do m
            p, _ = pick(fig)
            block_mouseover = try mouseover(b.blockscene, b.blockscene.children[begin].plots[begin]); catch _; false; end;

            if block_mouseover
                # Emulate a picked plot, the rest of the code should handle it gracefully
                p = block_series[b]
                requires_reset = false
            end

            if active != p && !isnothing(active)
                for s in series
                    s.alpha[] = 1.0
                end
                
                active.linewidth[] = 1.5
                active.overdraw[] = false
                active = nothing
            end

            if isnothing(p)
                GLMakie.GLFW.SetCursor(glscreen, NORMAL_CURSOR)
                if requires_reset
                    all_off = all(x -> x.clicks.val % 2 == 0, toggles)
                    for t in toggles
                        t.buttoncolor[] = RGBAf(
                            t.buttoncolor.val.r, 
                            t.buttoncolor.val.g, 
                            t.buttoncolor.val.b, 
                            all_off || t.clicks.val % 2 == 1 ? 1.0 : 0.25
                        )
                    end
                    for s in series
                        s.alpha[] = 1.0
                    end
                end

                requires_reset = false
                return Consume(false)
            end

            if p in series
                requires_reset = true

                active = p

                p.linewidth[] = 5.0
                p.overdraw[] = true

                Makie.enable!(inspector)

                GLMakie.GLFW.SetCursor(glscreen, HAND_CURSOR)
                # Darken the rest of the legends to show which value we have selected
                seriesidx = series_indexes[p]

                for (idx, t) in enumerate(toggles)
                    t.buttoncolor[] = RGBAf(
                        t.buttoncolor.val.r,
                        t.buttoncolor.val.g,
                        t.buttoncolor.val.b,
                        idx == seriesidx || t.clicks[] % 2 == 1 ? 1.0 : 0.25
                    )
                end

                for s in series
                    if s != p
                        s.alpha[] = 0.5
                    end
                end
            end

            return Consume(false)
        end

        on(events(fig).mousebutton) do mc
            # Save the variable to avoid potentially losing the reference
            current_active = active
            if !isnothing(current_active)
                if mc.button == Mouse.left && mc.action == Mouse.release
                    # Toggle the series visibility by triggering the legend event handler
                    update_block = toggles[series_indexes[current_active]]
                    update_block.clicks[] += 1

                    return Consume(true)
                end
            end
        end
    end

    return vcat(
        toggles, 
        formatted_labels,
        inspector
    )
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

function init_window(
    p::PrometheusQueryClient;
    query::Union{Nothing, String}=nothing,
    is3d::Bool=false,
    startdate::Union{Nothing, Union{DateTime, String}}=nothing,
    enddate::Union{Nothing, Union{DateTime, String}}=nothing,
    update_resolution::Union{Nothing, String}=nothing,
    series_limit::Int=100
)
    initial_resolution = (3840, 2160)

    GLMakie.activate!(; framerate=60.0)
    set_theme!(theme_black(); resolution=initial_resolution, framerate=60.0)

    fig = Figure(resolution=initial_resolution)

    plot_layout = GridLayout(1, 2)
    user_layout = GridLayout(4, 1)

    fig[1, 1] = plot_layout
    fig[2, 1] = user_layout

    ax::Union{Axis, Axis3} = is3d ? 
        Axis3(plot_layout[1, 1]) :
        Axis(plot_layout[1, 1])

    colsize!(plot_layout, 1, initial_resolution[1] / 3.25)
    colsize!(plot_layout, 2, Auto(true, 1))
    rowsize!(plot_layout, 1, initial_resolution[2] / 2)

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

    if isnothing(update_resolution)
        update_resolution = "5s"
    end

    update_interval_dropdown = Menu(
        fig;
        options=UPDATE_RESOLUTION_OPTIONS,
        default=update_resolution,
        textcolor=WHITE,
        cell_color_active=BLUE,
        selection_cell_color_inactive=BLUE,
        cell_color_inactive_even=VERY_DARK,
        cell_color_inactive_odd=VERY_DARK,
        cell_color_hover=BLUE,
        dropdown_arrow_color=WHITE,

        width=60,
        height=Auto(),
    )

    if isnothing(startdate)
        startdate = string(now(UTC) - Dates.Hour(2)) * "Z"
    end
    startdate_tb = Textbox(
        fig;
        placeholder="Start Date",
        stored_string=startdate,
        focused=false,
        fontsize=16,
        font=FONT_COURIER,
        width=250,
        tellwidth=false,
        halign=:left
    )

    if isnothing(enddate)
        enddate = string(now(UTC)) * "Z"
    end
    enddate_tb = tb = Textbox(
        fig;
        placeholder="End Date",
        stored_string=enddate,
        focused=false,
        fontsize=16,
        font=FONT_COURIER,
        width=250,
        tellwidth=false,
        halign=:left
    )

    user_layout[1, 1] = grid!(
        hcat(
            is3d_button,
            live_mode_button,
            Label(fig; text="Step:"),
            update_interval_dropdown
        )
    )

    user_layout[2, 1] = grid!(
        vcat(
            hcat(Label(fig; text="Start:"), startdate_tb),
            hcat(Label(fig; text="End:"), enddate_tb)
        )
    )

    tb = Textbox(
        user_layout[3, 1]; 
        placeholder="PromQL Query",
        stored_string=query,
        focused=true,
        fontsize=24,
        font=FONT_COURIER,
        width=Auto(),
        tellwidth=false,
    )
    status_label = Label(
        user_layout[4, 1];
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
        # Wipe out the previous Axis(3)
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
            # TODO: we can put garbage collection into a function since it is duplicated
            # below in the keyboard event handler
            if !isnothing(gc)
                for g in gc
                    try delete!(g); catch _; end;
                end
            end

            startdate = startdate_tb.stored_string.val
            enddate = enddate_tb.stored_string.val

            gc = render_data(
                fig, 
                plot_layout, 
                ax, 
                df, 
                status_label,
                query=tb.stored_string[],
                startdate=startdate,
                enddate=enddate,
                is3d=is3d, 
                series_limit=series_limit
            )
        end

        return Consume(false)
    end

    update_query = on(events(fig).keyboardbutton, update=!isnothing(query)) do e
        if !isnothing(e) && e.action !== Keyboard.release
            return Consume(false)
        end

        startdate = startdate_tb.stored_string.val
        enddate = enddate_tb.stored_string.val

        try 
            df = promql(
                p, 
                tb.stored_string[];
                startdate=startdate,
                enddate=enddate,
                step=update_interval_dropdown.selection[]
            )
        catch err
            status_label.color[] = RED
            status_label.text[] = "$err"
            return Consume(false)
        end

        if validate_df(df, status_label; update_text=true)
            if !isnothing(gc)
                for g in gc
                    try delete!(g); catch; end;
                end
            end
            gc = render_data(
                fig,
                plot_layout,
                ax,
                df,
                status_label,
                query=tb.stored_string[],
                startdate=startdate,
                enddate=enddate,
                is3d=is3d,
                series_limit=series_limit
            )
        end

        return Consume(false)
    end

    on(update_interval_dropdown.selection) do selection
        update_query.f(nothing)
        return Consume(false)
    end

    return fig
end