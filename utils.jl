using Dates
using DataFrames

function allbut(df::T, cols::Vector{Symbol}) where T <: AbstractDataFrame
    return setdiff(names(df), string.(cols))
end

function parse_period(period::T) where T <: AbstractString
    if endswith(period, "s")
        return Dates.Second(parse(Int, period[1:end-1]))
    elseif endswith(period, "m")
        return Dates.Minute(parse(Int, period[1:end-1]))
    elseif endswith(period, "h")
        return Dates.Hour(parse(Int, period[1:end-1]))
    elseif endswith(period, "d")
        return Dates.Day(parse(Int, period[1:end-1]))
    elseif endswith(period, "w")
        return Dates.Week(parse(Int, period[1:end-1]))
    elseif endswith(period, "M")
        return Dates.Month(parse(Int, period[1:end-1]))
    elseif endswith(period, "y")
        return Dates.Year(parse(Int, period[1:end-1]))
    else
        error("Invalid period: $period")
    end
end

function get_startdate(startdate::Union{Nothing, Union{DateTime, String}}, realtime_range_period::Union{Nothing, Dates.Period}=nothing)
    if isnothing(realtime_range_period)
        realtime_range_period = Dates.Hour(1)
    end

    if isnothing(startdate)
        return Dates.format(now(UTC) - realtime_range_period, RFC3339_FORMAT)
    elseif isa(startdate, DateTime)
        return Dates.format(startdate, RFC3339_FORMAT)
    end

    return startdate
end

function get_enddate(enddate::Union{Nothing, Union{DateTime, String}})
    if isnothing(enddate)
        return Dates.format(now(UTC), RFC3339_FORMAT)
    elseif isa(enddate, DateTime)
        return Dates.format(enddate, RFC3339_FORMAT)
    end

    return enddate
end