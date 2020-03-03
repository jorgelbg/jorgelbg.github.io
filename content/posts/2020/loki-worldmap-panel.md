---
title: "Displaying geohash information from Loki in the Worldmap Panel plugin"
date: 2020-03-02T21:49:10+01:00
draft: true
description: >
  Web UI tool for testing tokenizer strings for the dissect processor against a few
  logline samples.
tags: ["grafana", "loki", "worldmap", "geohash"]
---

[Loki](https://grafana.com/oss/loki/) is a new~ish project from [Grafana](https://grafana.com), yes
the same company behind the popular open source observability platform. Loki itself, is a
horizontally-scalable, highly-available, multi-tenant log aggregation system inspired by Prometheus.

On fewer words Lokis is like Prometheus but for your logs. This means that although it doesn't
provide all the full text search capabilities of Elasticsearch it allows filtering by a set of
labels for each log stream. This translates into a more cost-effective solution.

Even though Loki was announced on [KubeCon
18'](https://kccna18.sched.com/event/GrXC/on-the-oss-path-to-full-observability-with-grafana-david-kaltschmidt-grafana-labs).
It is still under active development. As expected the team is building in parallel the internal Loki
components: ingestion, storage and query layer and the Grafana support as a visualization UI on top
of Loki. It was not until recently that I've started to play with Loki. My main experience is about
running larg [Solr](https://lucene.apache.org/solr/) and/or
[Elasticsearch](https://www.elastic.co/de/elasticsearch) clusters, but I was looking for something
that was a bit easier and cheaper to host by myself. After all I was not really interested in all
the features from the ELK stack.

At the moment my data consist in a few labels and basically no actually log line, which is ok. I'm
mostly more interested only on the labels. Some of those labels (in my case) contained the latitude (`lat`),
longitude (`long`) and geohash (`geohash`) of a given location. I also included some descripted
information like `place` and `country`.

I wanted to plot this into a map using the [Worldmap
Panel](https://grafana.com/grafana/plugins/grafana-worldmap-panel/installation). Yet, it was a bit
tricky. I had previously running a container with the latest version of Grafana, since I was using
already the Explore UI from Grafana with the Loki datasource to check the incoming data. I ran the
following command to add the worldmap panel:

```bash
$ docker run -d -p 3000:3000 -e "GF_INSTALL_PLUGINS=grafana-worldmap-panel" grafana/grafana
```

My initial though was to point the Worldmap Panel to the Loki datasource and run one of the
[LogQL](https://github.com/grafana/loki/blob/master/docs/logql.md) queries against it. The query
ended up looking like:

```js
sum(count_over_time({geohash=~".+"}[1h])) by (geohash,lat,long,country,place)
```

This didn't work at all. Using the query inspector from Grafana I noticed that the response payload
from Loki was almost identical to the output of a Prometheus query. My next step was
to try and replicate the setup as shown in [this
post](https://www.robustperception.io/using-geohashes-with-the-worldmap-panel-and-prometheus).

Trying to show the data setting the Location Data as a geohash yielded this error:
```
Error: Missing geohash value
```
Which made a bit of sense, since we need to set the `{{ geohash }}` as the legend of our query. This
makes the `geohash` label (when using a Prometheus datasource) available to the Worldmap panel. Since
the legen input is missing from the Loki datasource it is not possible to do set it up this way.
Since I already have the `lat` and `long` available directly from the query, I also tried to use the
Location Data as a table, the setup ended up looking like:

{{< picture "loki-table-fail" "Setup of the Loki datasource as a table" "50%" >}}

Although this setup didn't produced any error it didn't visualized anything on the map either 🤷‍♂️.
The missing **piece of the puzzle** is that we can configure the Loki datasource as a Prometheus
datasource in Grafana 🤯.

To do this we need to create a Prometheus datasource in Grafana but point it out to the Loki
endpoint:

{{< picture "loki-and-prometheus-datasources" "Both datasources configured in the Grafana instance" >}}

As you can see we use the same URL, but we need to manually add the `/loki` path to the Prometheus datasource.

Using Loki as a Prometheus datasources allows us to use exactly the same query as before, but have
access to the configuration options only available for a Prometheus datasource. We can now follow the
instructions [previously mentioned
post](https://www.robustperception.io/using-geohashes-with-the-worldmap-panel-and-prometheus) to
visualize the labels stored in a Loki datasource in the Worldmap panel.

## Summary

The TL;DR of this post is that you are able to configure a Loki datasource as a Prometheus datasource
in Grafana wich will provide the same whistles and bells of a normal Prometheus server, except that
LogQL, the query language implemented by Loki, is a subset of PromQL, which means that not all
functions, aggregatios or operators will be available.

This step of configuring Loki as a Prometheus datasource is mandatory (so far) to get the Worldmap
Panel plugin playing nicely with your Loki datasource. I imagine that in the no so far future Grafana
will do some of this settings automtically depending on how you want to use the data, which might
make things (like using a 3rd party plugin) easier with Loki.

