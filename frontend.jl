using GLMakie
using UnicodePlots

include("prometheus.jl")

function init_window()
    GLMakie.activate!(; framerate=60.0)
    set_theme!(theme_black(); resolution=(3840, 2160))

    fig = Figure()

    presentation_layout = GridLayout()
    bottom_layout = GridLayout()
    input_layout = GridLayout()
    options_layout = GridLayout()

    bottom_layout[1, 1] = input_layout
    bottom_layout[1, 2] = options_layout

    fig.layout[1, 1] = presentation_layout
    fig.layout[2, 1] = bottom_layout

    rowgap!(fig.layout, 1, Fixed(100))
    rowsize!(fig.layout, 2, Relative(1/8))

    p = PrometheusQueryClient(scheme="http", port=9090)
    metrics = sort([i.metric for i in prom_metrics(p)])

    blk = Makie.RGB(0, 0, 0)
    blkg = Makie.RGB(0.1, 0.1, 0.1)
    wht = Makie.RGB(1, 1, 1)

    ax = Axis(presentation_layout[1, 1])
    Textbox(input_layout[1, 1]; placeholder="PromQL Query", fontsize=32, font=:italic, width=Auto(), height=50)
    Menu(input_layout[1, 2], options=metrics, cell_color_active=blk, cell_color_hover=blkg, cell_color_inactive_even=blk, cell_color_inactive_odd=blk, dropdown_arrow_color=blk, selection_cell_color_inactive=blk, textcolor=:black)

    colsize!(bottom_layout, 1, Relative(0.5))
    colsize!(bottom_layout, 2, Relative(0.05))

    return fig
end

init_window()