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
const DARK_BLUE::RGBAf = RGBAf(25/255, 25/255, 112/255, 1.0)
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
        # Right pad to have consistent formatting with labels and have consistent
        # placement of the plot and legend labels; aligns centered text properly.
        push!(formatted_labels, rpad(final_label, MAX_LEGEND_CHAR_LIMIT))
    end

    return formatted_labels
end

function draw_ax!(fig, layout, ax, df, query, startdate, enddate, is3d; title=nothing)
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

    df_start = minimum(df[:, :ts])

    for (idx, dfg) in dfgroups |> enumerate
        colnames = allbut(dfg, [:ts, :value])
        colvalues = values(dfg[1, allbut(dfg, [:ts, :value])])
        push!(labels, join(["$i=$j" for (i, j) in zip(colnames, colvalues)], ","))
        
        visible = Observable{Bool}(true)
        push!(series_visible, visible)

        if is3d
            push!(series, lines!(
                ax, dfg[:, :ts] .- df_start,
                fill(idx, size(dfg)[1]),
                dfg[:, :value];
                visible=visible
            ))
        else
            push!(series, lines!(
                ax,
                dfg[:, :ts] .- df_start,
                dfg[:, :value];
                visible=visible
            ))
        end
    end

    ax.title[] = isnothing(title) ? 
        join(("Query: " * query, "Start: " * startdate * ", End: " * enddate), "\n") :
        title

    ax.titlesize[] = 24
    ax.titlefont[] = FONT_COURIER

    dateformat = "u dd HH:MM:SS"
    if unix2datetime(maximum(df[:, :ts])) - unix2datetime(df_start) < Dates.Day(1)
        dateformat = "HH:MM:SS"
    end

    ax.xtickformat = x -> Dates.format.(unix2datetime.(x .+ df_start), dateformat)

    if is3d
        ax.ylabel[] = "Series Index"
        ax.zlabel[] = "Value"
    end

    return series, series_visible, labels
end

function render_data!(fig, layout, ax, df, status_label; query=nothing, startdate=nothing, enddate=nothing, orientation=:col, is3d=false, series_limit=100)
    series, series_visible, labels = draw_ax!(
        fig,
        layout,
        ax,
        df,
        query,
        startdate,
        enddate,
        is3d
    )

    lrow = orientation == :col ? 1 : 2
    lcol = orientation == :col ? 2 : 1

    page = Observable{Int}(1)
    results_per_page = orientation == :col ? 20 : 5

    start_idx = @lift(($page - 1) * results_per_page + 1)
    end_idx = @lift(min($start_idx + results_per_page - 1, length(labels)))

    button_clicked = [Observable{Bool}(false) for _ in eachindex(series)]

    prev_button = Button(
        layout[lrow, lcol];
        label="Prev",
        buttoncolor=@lift($page == 1 ? DARK_BLUE : BLUE),
        labelcolor=:white,
        width=70,
        halign=:left
    )

    next_button = Button(
        layout[lrow, lcol];
        label="Next",
        buttoncolor=@lift($page == ceil(length(labels) / results_per_page) ? DARK_BLUE : BLUE),
        labelcolor=:white,
        width=70,
        halign=:left
    )

    is3d_button = Button(
        layout[lrow, lcol];
        label="3D Plot",
        buttoncolor=:blue,
        labelcolor=:white,
        halign=:left
    )

    page_changed_fn = nothing
    on(is3d_button.clicks) do clicks
        # Save the title so that we can restore it after we wipe out the axis
        title = ax.title[]

        # Wipe out the previous Axis(3)
        delete!(ax)

        is3d = clicks % 2 != 0
        ax = is3d ?
            Axis3(layout[1, 1]) :
            Axis(layout[1, 1])

        # Counter-intuitive, but if we toggled 3D, we want to have the option to revert
        if is3d
            is3d_button.label[] = "2D Plot"
        else
            is3d_button.label[] = "3D Plot"
        end

        series, series_visible, labels = draw_ax!(
            fig,
            layout,
            ax,
            df,
            query,
            startdate,
            enddate,
            is3d;
            title=title
        )

        if !isnothing(page_changed_fn)
            page_changed_fn.f(0)
        end
    end

    on(next_button.clicks) do next_click
        page[] = min(page.val + 1, convert(Int, ceil(length(labels) / results_per_page)))
        return Consume(true)
    end

    on(prev_button.clicks) do prev_click
        page[] = max(page.val - 1, 1)
        return Consume(true)
    end

    toggles_gc = nothing
    formatted_labels_gc = nothing
    glscreen = nothing

    page_changed_fn = on(page; update=true) do _
        if !isnothing(toggles_gc)
            for t in toggles_gc
                delete!(t)
            end
        end
        if !isnothing(formatted_labels_gc)
            for l in formatted_labels_gc
                delete!(l)
            end
        end

        toggles_gc = toggles = [
            Button(
                layout[lrow, lcol];
                label="",
                buttoncolor=series[idx].color
            ) for idx in start_idx.val:end_idx.val
        ]
    
        formatted_labels_gc = formatted_labels = [
            Label(
                layout[lrow, lcol];
                text=i,
                font=FONT_COURIER,
                fontsize=14,
                halign=:left
            ) for i in format_label_table(labels[start_idx.val:end_idx.val])
        ]

        series_indexes = Dict()
        for (idx, s) in enumerate(series)
            series_indexes[s] = idx
        end

        block_series = Dict()
        for (b, s) in zip(toggles, series[start_idx.val:end_idx.val])
            block_series[b] = s
        end

        layout[lrow, lcol] = grid!(hcat(toggles, formatted_labels))
        layout[lrow + 1, lcol] = grid!(hcat(prev_button, next_button, is3d_button))


        for b in toggles
            active = nothing

            button_click_fn = on(b.clicks) do sidx
                # Scan all of the active toggles and hide series that are inactive.
                # We show all series if all toggles are set to inactive.
                sidx = nothing
                if isnothing(active)
                    sidx = series_indexes[block_series[b]]
                else
                    sidx = series_indexes[active]
                end

                button_clicked[sidx][] = !button_clicked[sidx][]
                if all(x -> !x.val, button_clicked)
                    for idx in eachindex(button_clicked)
                        series_visible[idx][] = true
                        if idx >= start_idx.val && idx <= end_idx.val
                            t = toggles[idx - start_idx.val + 1]
                            t.buttoncolor[] = RGBAf(t.buttoncolor.val.r, t.buttoncolor.val.g, t.buttoncolor.val.b, 1.0)
                        end
                    end

                    reset_limits!(ax)
                    return Consume(true)
                end

                # Keep track if we've made any changes, so that we can reset the
                # limits of the graph if there are new graphs
                has_update = false

                for idx in eachindex(series)
                    # The number of clicks will be odd if the toggle is active
                    t = nothing
                    is_active = button_clicked[idx].val

                    previous_active = series_visible[idx].val
                    series_visible[idx][] = is_active

                    has_update = has_update || previous_active != is_active

                    if idx >= start_idx.val && idx <= end_idx.val
                        t = toggles[idx - start_idx.val + 1]
                        t.buttoncolor[] = RGBAf(
                            t.buttoncolor.val.r,
                            t.buttoncolor.val.g,
                            t.buttoncolor.val.b,
                            is_active ? 1.0 : 0.25)
                    end
                end

                if has_update
                    reset_limits!(ax)
                end

                return Consume(true)
            end

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
                    if !isnothing(glscreen)
                        GLMakie.GLFW.SetCursor(glscreen, NORMAL_CURSOR)
                    end
                    if requires_reset
                        all_off = all(x -> !x.val, button_clicked)
                        for (idx, t) in zip(start_idx.val:end_idx.val, toggles)
                            t.buttoncolor[] = RGBAf(
                                t.buttoncolor.val.r, 
                                t.buttoncolor.val.g, 
                                t.buttoncolor.val.b, 
                                all_off || button_clicked[idx].val ? 1.0 : 0.25
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

                    if isnothing(glscreen)
                        glscreen = GLMakie.GLFW.GetCurrentContext()
                    end

                    GLMakie.GLFW.SetCursor(glscreen, HAND_CURSOR)
                    # Darken the rest of the legends to show which value we have selected
                    seriesidx = series_indexes[p]

                    for (idx, t) in zip(start_idx.val:end_idx.val, toggles)
                        t.buttoncolor[] = RGBAf(
                            t.buttoncolor.val.r,
                            t.buttoncolor.val.g,
                            t.buttoncolor.val.b,
                            idx == seriesidx || button_clicked[idx].val ? 1.0 : 0.25
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
                if isnothing(current_active)
                    return
                end

                if mc.button != Mouse.left || mc.action != Mouse.release
                    return
                end

                # Toggle the series visibility by triggering the legend event handler
                active_index = series_indexes[current_active]
                if active_index < start_idx.val || active_index > end_idx.val
                    # Find the page that this plot is on and advance the page observable
                    page[] = convert(Int, ceil(active_index / results_per_page))
                    return Consume(false)
                end

                active_index = active_index - start_idx.val + 1
                button_click_fn.f(0)

                return Consume(true)
            end
        end
    end

    return vcat(
        toggles_gc, 
        formatted_labels_gc
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
        width=250 
        ,
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

            gc = render_data!(
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
            gc = render_data!(
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