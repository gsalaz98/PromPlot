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

function create_label(df)
    colnames = allbut(df, [:ts, :value])
    colvalues = values(df[1, allbut(df, [:ts, :value])])
    return join(["$i=$j" for (i, j) in sort(zip(colnames, colvalues), by=(x -> x[1]))], ",")
end

function draw_ax!(fig, layout, ax, df, query, startdate, enddate, is3d; title=nothing, ax_width=Relative(0.85))
    try 
        # 3D plots don't have an empty! method defined, so let's clear the 
        # whole axis and start anew
        empty!(ax)

        if is3d
            delete!(ax)
            ax = is3d ? 
                Axis3(layout[1, 1]; width=ax_width) : 
                Axis(layout[1, 1]; width=ax_width)
        end
    catch;
    end;

    dfgroups = groupby(df, allbut(df, [:ts, :value]))

    series = []
    data_x = Dict{String, Observable{Vector{Float64}}}()
    data_y = Dict{String, Observable{Vector{Float64}}}()
    data_z = Dict{String, Observable{Vector{Int64}}}()

    series_visible = Observable{Bool}[]
    labels = String[]
    df_start = minimum(df[:, :ts])

    for (idx, dfg) in dfgroups |> enumerate
        joined_label = create_label(dfg)
        push!(labels, joined_label)
        
        visible = Observable{Bool}(true)

        xs = Observable{Vector{Float64}}(dfg[:, :ts] .- df_start)
        ys = Observable{Vector{Float64}}(dfg[:, :value])
        zs = Observable{Vector{Float64}}(fill(idx, size(dfg)[1]))

        push!(series_visible, visible)

        data_x[joined_label] = xs
        data_y[joined_label] = ys
        data_z[joined_label] = zs

        if is3d
            push!(series, lines!(
                ax,
                xs,
                zs,
                ys,
                visible=visible
            ))
        else
            push!(series, lines!(
                ax,
                xs,
                ys,
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

    return series, series_visible, labels, data_x, data_y, data_z
end

function update_ax!(ax, df, xs, ys, zs)
    dateformat = "u dd HH:MM:SS"
    df_start = minimum(df[:, :ts])

    if unix2datetime(maximum(df[:, :ts])) - unix2datetime(df_start) < Dates.Day(1)
        dateformat = "HH:MM:SS"
    end

    ax.xtickformat = x -> Dates.format.(unix2datetime.(x .+ df_start), dateformat)
    dfgroup = groupby(df, allbut(df, [:ts, :value]))

    for (idx, dfg) in dfgroup |> enumerate
        label = create_label(dfg)

        xs[label].val = dfg[:, :ts] .- df_start
        ys[label].val = dfg[:, :value]
        zs[label].val = fill(idx, size(dfg)[1])

        # We notify after the fact because otherwise we get a broadcast error
        # because Makie.jl attempts to plot the data before we are done updating
        notify.((xs[label], ys[label], zs[label]))
    end
    
    reset_limits!(ax)
end

function render_data!(
    client::PrometheusQueryClient,
    fig::Figure, 
    layout::GridLayout, 
    ax::Union{Axis, Axis3},
    df::DataFrame;
    query::Union{Nothing, String}=nothing, 
    step::String="1s",
    startdate::Union{Nothing, String}=nothing, 
    enddate::Union{Nothing, String}=nothing,
    realtime::Bool=false,
    realtime_update_period::Dates.Period=Dates.Second(5),
    realtime_range_period::Dates.Period=Dates.Hour(1),
    orientation::Symbol=:col,
    is3d::Bool=false,
    title::Union{Nothing, String}=nothing,
    ax_width=Relative(0.85)
)
    series, series_visible, labels, xs, ys, zs = draw_ax!(
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

    page_changed_fn = nothing
    window_closed = false

    on(events(fig).window_open) do window_open
        window_closed = !window_open
        return Consume(false)
    end

    if realtime
        Threads.@spawn :interactive begin
            while !window_closed
                sleep(realtime_update_period)
                try
                    df = promql(
                        client,
                        query,
                        startdate=now(UTC) - realtime_range_period,
                        enddate=now(UTC),
                        step=step,
                        timeout=nothing
                    )
                catch err
                    println(err)
                    return
                end

                try
                    if !validate_df(df)
                        println("Query produced empty DataFrame: $query")
                        continue
                    end

                    title = isnothing(title) ? 
                        join(("Query: " * query, "Start: " * startdate * ", End: " * enddate), "\n") :
                        title

                    update_ax!(
                        ax,
                        df,
                        xs,
                        ys,
                        zs
                    )

                    if !isnothing(page_changed_fn)
                        page_changed_fn.f(1)
                    end
                catch e
                    println("Error updating plot: $e")
                end
            end
        end
    end

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

    series_indexes = Dict()
    for (idx, s) in enumerate(series)
        series_indexes[s] = idx
    end

    on(is3d_button.clicks) do clicks
        # Save the title so that we can restore it after we wipe out the axis
        title = ax.title[]

        # Wipe out the previous Axis(3)
        delete!(ax)

        is3d = clicks % 2 != 0
        ax = is3d ?
            Axis3(layout[1, 1]; width=ax_width) :
            Axis(layout[1, 1]; width=ax_width)

        # Counter-intuitive, but if we toggled 3D, we want to have the option to revert
        if is3d
            is3d_button.label[] = "2D Plot"
        else
            is3d_button.label[] = "3D Plot"
        end

        series, series_visible, labels, xs, ys, zs = draw_ax!(
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

        series_indexes = Dict()
        for (idx, s) in enumerate(series)
            series_indexes[s] = idx
        end

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

    toggles_max = min(results_per_page, length(series))
    on_screen_toggles = [
        Button(
            layout[lrow, lcol];
            label="",
            buttoncolor=series[idx].color,
            buttoncolor_active=series[idx].color,
            buttoncolor_hover=series[idx].color,
        ) for idx in collect(eachindex(series))[begin:toggles_max]
    ]

    formatted_labels = [i for i in format_label_table(labels)]
    on_screen_labels = [
        Label(
            layout[lrow, lcol];
            text=i,
            font=FONT_COURIER,
            fontsize=14,
            halign=:left
        ) for i in format_label_table(labels)[begin:toggles_max]
    ]

    layout[lrow, lcol] = grid!(hcat(on_screen_toggles, on_screen_labels))
    layout[lrow + 1, lcol] = grid!(hcat(prev_button, next_button, is3d_button))

    block_series = Dict()

    page_changed_fn = on(page; update=true) do _
        for idx in start_idx.val:end_idx.val
            element_idx = idx - start_idx.val + 1

            label = on_screen_labels[element_idx]
            toggle = on_screen_toggles[element_idx]

            toggle.buttoncolor[] = series[idx].color.val
            toggle.buttoncolor_active[] = series[idx].color.val
            toggle.buttoncolor_hover[] = series[idx].color.val

            label.text[] = formatted_labels[idx]

            block_series[toggle] = series[idx]
        end

        if end_idx.val - start_idx.val != results_per_page - 1
            for idx in ((end_idx.val - start_idx.val) + 2):results_per_page
                label = on_screen_labels[idx]
                toggle = on_screen_toggles[idx]

                label.text[] = ""
                toggle.buttoncolor[] = BLACK
                toggle.buttoncolor_active[] = BLACK
                toggle.buttoncolor_hover[] = BLACK
            end
        end
    end

    active = nothing
    button_click_fns = []

    for b in on_screen_toggles
        button_click_fn = on(b.clicks) do _
            if b.buttoncolor.val == BLACK
                # The button is disabled and not visible, do nothing with the click
                return Consume(true)
            end

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
                        t = on_screen_toggles[idx - start_idx.val + 1]
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
                    t = on_screen_toggles[idx - start_idx.val + 1]
                    if is_active && t.buttoncolor.val.alpha != 1.0
                        t.buttoncolor[] = RGBAf(
                            t.buttoncolor.val.r,
                            t.buttoncolor.val.g,
                            t.buttoncolor.val.b,
                            0.25)
                    elseif !is_active && t.buttoncolor.val.alpha != 0.25
                        t.buttoncolor[] = RGBAf(
                            t.buttoncolor.val.r,
                            t.buttoncolor.val.g,
                            t.buttoncolor.val.b,
                            1.0)
                    end
                end
            end

            if has_update
                reset_limits!(ax)
            end

            return Consume(true)
        end

        push!(button_click_fns, button_click_fn)
    end

    glscreen = nothing
    requires_reset = false

    on(events(fig).mouseposition) do m
        p, _ = pick(fig)

        b = nothing
        button_mouseover = false
        for button in on_screen_toggles
            if isempty(button.blockscene.children)
                continue
            end

            first_child = first(button.blockscene.children)
            if isempty(first_child.plots)
                continue
            end

            button_mouseover = mouseover(button.blockscene, first(first_child.plots))
            if button_mouseover
                b = button
                break
            end
        end

        if button_mouseover
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
                for (idx, t) in zip(start_idx.val:end_idx.val, on_screen_toggles)
                    if (all_off || button_clicked[idx].val) && t.buttoncolor.val.alpha != 1.0
                        t.buttoncolor[] = RGBAf(
                            t.buttoncolor.val.r,
                            t.buttoncolor.val.g,
                            t.buttoncolor.val.b,
                            1.0
                        )
                    elseif (!all_off && !button_clicked[idx].val) && t.buttoncolor.val.alpha != 0.25
                        t.buttoncolor[] = RGBAf(
                            t.buttoncolor.val.r,
                            t.buttoncolor.val.g,
                            t.buttoncolor.val.b,
                            0.25
                        )
                    end
                end
                for s in series
                    if s.alpha.val != 1.0
                        s.alpha[] = 1.0
                    end
                end
            end

            requires_reset = false
            return Consume(false)
        end

        if p in series
            if !isnothing(b) && b.buttoncolor.val == BLACK
                return Consume(false)
            end

            requires_reset = true
            active = p

            p.linewidth[] = 5.0
            p.overdraw[] = true

            if isnothing(glscreen)
                glscreen = GLMakie.GLFW.GetCurrentContext()
            end

            GLMakie.GLFW.SetCursor(glscreen, HAND_CURSOR)
            # Darken the rest of the legends to show which value we have selected
            if !haskey(series_indexes, p)
                return Consume(false)
            end

            sidx = series_indexes[p]

            for (idx, t) in zip(start_idx.val:end_idx.val, on_screen_toggles)
                if idx == sidx || button_clicked[idx].val
                    t.buttoncolor[] = RGBAf(
                        t.buttoncolor.val.r,
                        t.buttoncolor.val.g,
                        t.buttoncolor.val.b,
                        1.0
                    )
                elseif t.buttoncolor.val.alpha != 0.25
                    t.buttoncolor[] = RGBAf(
                        t.buttoncolor.val.r,
                        t.buttoncolor.val.g,
                        t.buttoncolor.val.b,
                        0.25
                    )
                end
            end

            for s in series
                if s != p && s.alpha.val != 0.5
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
        end

        active_index = active_index - start_idx.val + 1
        button_click_fns[active_index].f(0)

        return Consume(true)
    end

    return fig
end

function validate_df(df)::Bool
    return !isnothing(df)
end

function init_window(
    p::PrometheusQueryClient;
    query::Union{Nothing, String}=nothing,
    is3d::Bool=false,
    startdate::Union{Nothing, Union{DateTime, String}}=nothing,
    enddate::Union{Nothing, Union{DateTime, String}}=nothing,
    step::String="30s",
    realtime::Bool=false,
    realtime_update::String="5s",
    realtime_range::Union{Nothing, String}="30s"
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

    live_mode_button = Button(
        fig;
        label=realtime ? "Live Data" : "Static Data",
        buttoncolor=:blue,
        labelcolor=:white,
    )

    update_interval_dropdown = Menu(
        fig;
        options=UPDATE_RESOLUTION_OPTIONS,
        default=step,
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

    realtime_range_period = parse_period(realtime_range)
    realtime_update_period = parse_period(realtime_update)

    if isnothing(startdate)
        startdate = string(now(UTC) - realtime_range_period) * "Z"
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

        if validate_df(df)
            render_data!(
                p,
                fig,
                plot_layout,
                ax,
                df;
                query=tb.stored_string[],
                startdate=startdate,
                enddate=enddate,
                is3d=is3d,
                step=update_interval_dropdown.selection[],
                realtime=realtime,
                realtime_update_period=realtime_update_period,
                realtime_range_period=realtime_range_period
            )
        end

        return Consume(false)
    end

    on(update_interval_dropdown.selection) do selection
        update_query.f(nothing)
        return Consume(false)
    end

    on(live_mode_button.clicks) do
        realtime = !realtime
        if realtime
            live_mode_button.label[] = "Static Data"
        else
            live_mode_button.label[] = "Live Data"
        end

        update_query.f(nothing)
        return Consume(false)
    end

    return fig
end