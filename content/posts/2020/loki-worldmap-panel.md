---
title: "Loki Worldmap Panel"
date: 2020-03-02T21:49:10+01:00
draft: true
description: >
  Web UI tool for testing tokenizer strings for the dissect processor against a few
  logline samples.
tags: ["filebeat", "dissect", "test", "ui"]
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
