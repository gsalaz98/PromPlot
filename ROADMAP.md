# Required features to ship
* [ ] Scrollbar `Makie.Block` implementation to allow for elements with many entries so that they don't overflow to the rest of the figure
* [ ] Date indexes for Makie
* [ ] Navigation pane for series with different grouped metrics
* [x] 3D Plotting for prometheus metrics (done)
* [-] Live plotting and updates (partially done, GUI needs support)
* [ ] Different plot types
* [x] CLI MVP (done)
* [ ] Multiple PrometheusQueryClients to query multiple servers at the same time and label the time series respectively
* [ ] Dashboard creation/loading for users who would like the ability to run dashboards locally, consider using Grafana dashboard JSON as source of truth/dashboard definition

# Wanted features
* [ ] Integration w/ different metrics operators such as `node-exporter`, `kube-state-metrics`, `vpa`, `hpa`, etc.