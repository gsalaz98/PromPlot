# Required features to ship
* [x] Date indexes for Makie
* [x] Navigation pane for series with different grouped metrics
* [x] 3D Plotting for prometheus metrics (done)
* [x] Live plotting and updates (partially done, GUI needs support)
* [ ] Support for different plot types
* [x] CLI MVP (done)
* [ ] Multiple PrometheusQueryClients to query multiple servers at the same time and label the time series respectively
* [-] Dashboard creation/loading for users who would like the ability to run dashboards locally, consider using Grafana dashboard JSON as source of truth/dashboard definition (in progress, MVP achieved)
* [ ] Support for Grafana variables: `$__range`, `$__interval`, `$__rate_interval`

# Wanted features
* [ ] Integration w/ different metrics operators such as `node-exporter`, `kube-state-metrics`, `vpa`, `hpa`, etc.