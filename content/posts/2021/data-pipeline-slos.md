---
title: Time based SLO for Kafka data pipelines
date: 2022-01-17T18:05:48+01:00
draft: true
description: >
  Using a time based approach to define SLOs for Kafka based data pipelines.
---

{{< picture "hero" "Data processing illustration" >}}

The [Google SRE Book][workbook] has a complete chapter devoted to Data processing pipelines,
including a section that deals with best practices to _Define_ and _Measure_ Service Level Objectives
(SLOs) for this type of workloads.

The SRE book advices to focus on one (or more) of the following properties of the data to monitor
your data pipeline:

## Data freshness

SLOs focused on this property take into account how fresh the events arriving to the pipeline are.
For instance:

* X% of data processed in Y [seconds, days, minutes].
* The oldest data is not older than Y [seconds, days, minutes].
* The pipeline job has completed successfully within Y [seconds, days, minutes].

## Data correctness

The goal with the category is to evaluate that our pipeline is producing the expected output. Feeding
test data to the pipeline, could allows us to assert if the expected values/events are produced by
our pipeline. It may be also possible to define some sort of monitoring on the discrepancy between
the input of your pipeline and the output.

<!-- The main issue with this category is that data correctness
varies widely between applications. -->

## Data isolation/load balancing

This could be interpreted as priority of the data, using the right amount of resources (CPU, memory,
network tiers) for those pipelines that have higher priority. Your SLO should reflect this priority
and events with higher priority should have a tighter SLO. This should also ensure that all the
running data pipelines do not interfere with each other.

## End-to-end measurement

If you have a data pipeline that has multiple stages it may be useful to not only measure the SLOs of
the individual components but also pay close attention to an end-to-end SLO.

These are key properties to take into account when creating an SLO for a data pipeline but not very
well suited for our particular case: we deal with logging/monitoring data (or events).

When creating an SLO (or any alert, really) we need to make sure that it is **actionable**. An alert
due an SLO violation where you cannot do anything is not helpful at all.

In our case we are only responsible for one of the _pipelines_ that consume the data. Events are
produced by our applications (maintained by multiple teams) and are written into our central Kafka
cluster(s). From there, multiple consumers use the data. Our particular case is ingesting the events
into a few Elasticsearch clusters that are used for debugging and for visualizing/querying the data.

> How can we best define an SLO specific for our case?

If we create an SLO around _data freshness_ then our SLO will be influenced by the producers, if they
go down or have a communication issue with Kafka (our central queue) our SLO will suffer. In this
case, our SLO will cover failure modes that are not within the scope of our team. An SLO in the
form of _The pipeline job has completed successfully within Y [seconds, days, minutes]_ doesn't work
either because our pipelines/processors are always running.

Since we don't control the data flowing through the pipeline, defining a SLO around _data
correctness_ is out of our scope. The producers are the ones that know which data is included in the
events.

<!-- , and they usually check this *after* the data has passed through our pipeline (in
Kibana/Elasticsearch). -->

_Data isolation/Load balancing_ is normally ensured by the producers writing data into different
topics, and each topic being configured with a variable number of partitions and consumed with a
proper number of consumer instances. The number of processors working on the same topic depends on
how critical the data is and how much data is produced.

If we instead try to define an end-to-end SLO we have the same issue as before: our SLO will include
components out of our control.

<!-- This may be a very interesting key for creating SLOs, but it depends a lot on how your organization
works. If you are not responsible for creating the data or for the queuing system in between, then
your SLO may end up measuring too many components out of your control, rendering the SLO non
actionable. -->

<!-- Having an end-to-end SLO is desired in some situations, specially when we are shipping features to
an external user. This works great as a measurement of the general reliability of your service, this
means that any component involved in the request flow from the user that is down should affect the
SLO. -->

Previously we were creating threshold alerts over the _consumer lag_ of our pipelines. If the amount
of events in the queue that hadn't been consumed yet passed a given value an alert would be
triggered.

We define the _lag_ of a kafka consumer group as the difference between the offset of the the last
message written into the topic and the offset of the last consumed message. We track this value under
a metric called `kafka_consumergroup_lag`.

{{< mark "lag-query" >}}
```promql
sum(kafka_consumergroup_lag) by (topic, consumergroup)
```

Over this metric we set up a max threshold (let's say 250k) and we triggered an alert if the result
of the query went above that value.

This was not perfect, if we have a sudden burst in data written into a topic (enough to go above our
threshold) this alert may trigger: but, if the data is processed _fast enough_, do we really care
that we are processing more data? The entire purpose of our pipeline is to process data.

This alert is also susceptible to minor temporary slowdowns of the pipeline (or storage system). If
processors cannot keep up with the incoming data we want to get notified, but, if we just had a small
hiccup (due to new Elasticsearch indices being created, for instance) do we want to get notified
then?

## Let's focus on time

If instead of thinking about the _number of events to process_ we start to think about how long it
will take to _process the existing lag_ then it is easier to reason about the alerting conditions.

We do not have to think anymore about how many events are in the queue, or how fast the lag is being
processed. If we set an SLO over this metric is easier to understand **and communicate** to other
teams: _this pipeline may have a delay of up to Y [seconds, minutes, hours]_.

This should also help us to fight alert fatigue, we do not need to continuously tweak the threshold
for each topic (which depending on volume of events). Because we are focusing on _how fast_ the
processor(s) will consume the existing lag, our alerting is independent of the amount of data written
to the topic and also resilient to temporary slowdowns that don't make us miss our target.

In practice this allows to use the _speed_ of the processor as a control variable for the amount of
lag in the topic, while still focusing in a single numeric dimension.

What our alerting query needs to do now is evaluate periodically something like:

```ruby
current_lag / processor_speed > $threshold
```

The `current_lag` can be fetched by the previous [query](#lag-query). For the `processor_speed` we
can rely on the [`rate()`][rate]/[`deriv()`][deriv] query functions of the
`kafka_consumergroup_current_offset_sum` metric (the actual function to use depends on the metric
type). A query like:

```promql
rate(kafka_consumergroup_current_offset_sum[5m])
```

or

```promql
deriv(kafka_consumergroup_current_offset_sum[5m])
```

will return the per-second rate of change of the committed offset for a given consumer group and
topic.

{{< info >}}

If your processor exposes any internal metric that exposes maximum throughput (events/second, for
example) you should use that metric as part of the SLO calculation. In this post we will focus
on metrics purely collected from Kafka. The upside is that these metrics are independent from which
processors/consumers are used but they may be a bit less precise.

{{</ info >}}

Putting these two queries together as we mentioned before we get:

```promql
kafka_consumergroup_lag
/
rate(kafka_consumergroup_current_offset_sum[1h])
```

This query still has one issue, it uses the current "speed of the processor" for calculating how long
it will take to process the current consumer lag. Unless your processor is running at full throughput
**all the time** this will lead to longer estimated times for processing the lag. What we *really*
need is the maximum throughput of the processor:

```ruby
current_lag / max(processor_speed)
```

For this we can use the [`max_over_time()`][max_over_time] function:

```promql
max_over_time(rate(kafka_consumergroup_current_offset_sum[5m])[2d:5m])
```

This query will calculate the rate of change of the consumer's offset at a 5m window and it will get
the max value over the last 2 days using a `5m` window. The query uses the [subquery
support][subquery] added to Prometheus since version 2.7.

{{< mark "recording-rule" >}}
> Depending on how much time you go back to calculate the `max_over_time()`, your query can become
> slow. For a production environment, our recommendation is to setup a [recording
> rule][recording-rule] for pre-calculating the max throughput of your pipelines.

Keep in mind that this query will only return the max throughput **already seen** (in the requested
interval). It is also possible that your processor can consume data faster than the values seen in
the given interval. It is also possible that the speed of your processor changes depending on which
host is running. The good news is that as soon as the processor shows that is able to process data
faster the estimated time for consuming the lag will be updated automatically.

Combining these two parts into a single query:

```promql
kafka_consumergroup_lag
/
max_over_time(rate(kafka_consumergroup_current_offset_sum[4m])[2d:5m])
```

Graphing these values in Grafana (and setting the Y axis to seconds) we get something like:

{{< picture "consume-time-graph" "Plot of the time to consume the lag at maximum throughput" >}}

Another benefit of this approach is that just by eyeballing the graph we can answer the question of
how long is going to take to process certain lag. This was a common question that we ask ourselves
when we are recovering from an incident, and we try to include in our incident updates.

<!-- This new query makes it easier to create an actionable alert that is more resilient to sudden
temporary bursts or slowdowns of the processor. At the same time, this alert works better than a
plain threshold on the lag, if the processor stops even with little traffic, the amount of time
needed to process the lag will increase and it will trigger, even if the number of queued events is
not that high. -->

There is one additional condition that we can add _just_ for our alert. If we get a burst of new data
but we can see that the lag is going down it is possible that don't want to be alerted at all. We can
_encode_ this requirement as: _if the lag is increasing_ by adding the following to our query:

```promql
and deriv(
  kafka_consumergroup_lag[20m]
) > 0
```

If the lag is increasing **and** is going to take longer than our defined threshold then we want to
trigger a notification.

> Of course, this type of additional constraints to the alert will depend on your specific
> environment and how the data is used after it leaves the pipeline.

More complex situations regarding triggering or not a notification (especially if it involves waking
up teammates) can be encoded in other components like [Alertmanager][alertmanager]. If we are in the
middle of the day and people are actively using the data then it is more likely that you want to know
that the data is going to be a bit delayed, and maybe inform the teams that use/own the data. But if
this happens in the middle of the night and the data is going to be available before people wake up
in the morning, _maybe_ this is not urgent enough to get on-call engineers out of their bed.

## Results

We applied this approach to a few of our pipelines, and in a recent incident we noticed the
difference. For this topic in question we previously had an alert that would trigger if the lag went
above a fixed threshold of **200k** events. 200k represents roughly 2 times the peak value observed
for this topic during normal days. This seems like a good value to start with (see panel 1 of the
[screenshot](#screenshot)).

We had one Grafana panel with the old threshold alert and right next the one that estimates the time
that is going to take to consume the lag. During the incident, the lag was increasing for this
particular topic until it reached values above 500k. This triggered our old alerting and we got a
Slack notification. Taking a look at the new panel that contained the time based estimation (see
panel 2 of the [screenshot](#screenshot)). Our new query was estimating that the lag _would_ be
processed in less than 2 minutes.

{{< mark "screenshot" >}}
Our new alert would not have fired for this incident, checking the lag a couple of minutes later ...
it was effectively gone.

{{< picture "incident" "Old threshold-based alert next to our new time based" >}}

If we zoom in the time when our processor started to consume data again, we can see that our
estimation of the time needed to consume the lag was right:

{{< picture "recovery" "Old threshold-based alert next to our new time based" >}}

## Recording rule

As [mentioned before](#recording-rule) if you plan to use this approach in a production environment
it is recommended to use a recording rule to track the maximum throughput of your
processors/consumers. In the following snippet you can see how we have set up a new metric
`pipeline_throughput`:

```yaml
groups:
  - name: PipelineThroughput
    rules:
    - record: pipeline_throughput
      expr: max_over_time(rate(kafka_consumergroup_current_offset_sum[5m])[2d:5m])
```

Keep in mind that we are keeping all the labels from the original
`kafka_consumergroup_current_offset_sum` because the evaluation time for this group is usually quite
fast.

<!-- _People vector created by [pch.vector - www.freepik.com](https://www.freepik.com/vectors/people)_ -->

[srebook]: https://sre.google/sre-book/data-processing-pipelines/
[workbook]: https://sre.google/workbook/data-processing/
[rate]: https://prometheus.io/docs/prometheus/latest/querying/functions/#rate
[deriv]: https://prometheus.io/docs/prometheus/latest/querying/functions/#deriv
[deriv]: https://prometheus.io/docs/prometheus/latest/querying/functions/#deriv
[max_over_time]: https://prometheus.io/docs/prometheus/latest/querying/functions/#aggregation_over_time
[alertmanager]: https://prometheus.io/docs/alerting/latest/alertmanager/
[subquery]: https://prometheus.io/blog/2019/01/28/subquery-support/
[recording-rule]: https://prometheus.io/docs/prometheus/latest/configuration/recording_rules/