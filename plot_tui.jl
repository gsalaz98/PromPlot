using UnicodePlots

include("utils.jl")

function init_terminal(
    p::PrometheusQueryClient;
    query::Union{Nothing, String}=nothing,
    startdate::Union{Nothing, Union{DateTime, String}}=nothing,
    enddate::Union{Nothing, Union{DateTime, String}}=nothing,
    update_resolution::Union{Nothing, String}=nothing,
    series_limit::Int=25
)

    if isnothing(query)
        return
    end

    if isnothing(startdate)
        startdate = Dates.format(now(UTC) - Dates.Hour(2), RFC3339_FORMAT)
    elseif isa(startdate, DateTime)
        startdate = Dates.format(startdate, RFC3339_FORMAT)
    end

    if isnothing(enddate)
        enddate = Dates.format(now(UTC), RFC3339_FORMAT)
    elseif isa(enddate, DateTime)
        enddate = Dates.format(enddate, RFC3339_FORMAT)
    end

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

    if isnothing(p)
        return
    end

    println("Query: $query \n(start=$startdate, end=$enddate, step=$update_resolution)")
    dfgroup = groupby(df, allbut(df, [:ts, :value]))

    for (idx, dfg) in dfgroup |> enumerate
        if all(iszero, dfg[:, :value])
            continue
        end

        colnames = allbut(dfg, [:ts, :value])
        colvalues = values(dfg[1, allbut(dfg, [:ts, :value])])

        title = join(["$i=$j" for (i, j) in zip(colnames, colvalues)], ", ")
        out = lineplot(dfg[:, :ts] .- dfg[begin, :ts], dfg[:, :value]; title=title)
        display(out)

        if idx >= series_limit
            println("Series limit reached ($series_limit), witholding $(length(dfgroup) - series_limit) remaining series") 
            break
        end
    end
end