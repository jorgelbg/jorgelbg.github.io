---
title: "SLOs for a data pipeline"
date: 2021-08-11T18:05:48+01:00
draft: true
description: >
  Improved alerting for monitoring the lag of your data pipeline. Concrete example with PromQL and
  Kafka.
---

The [Google SRE Book]([workbook]) has a complete chapter devoted to Data processing pipelines, it
even includes a section that deals with best practices to Define and Measure Service Level Objectives
(SLOs) for this type of workload.

Some of the SLOs defined in this chapter focus around the following properties of the data pipeline:

## Data freshness

SLOs focused on this property take into account how fresh the events arriving to the pipeline are.
For instance:

* X% of data processed in Y [seconds, days, minutes].
* The oldest data is no older than Y [seconds, days, minutes].
* The pipeline job has completed successfully within Y [seconds, days, minutes].

## Data correctness

The main issue with this category is that data correctness varies widely between applications. Also,
we may need to feed test data to the pipeline, this allows us to assert expected values/events within
our pipeline. It may be also possible to define some sort of monitoring on the discrepancy between
the input of your pipeline and the output.

## Data isolation/load balancing

This could be interpreted as priority of the data, and using the right amount of resources (cpu,
memory, network tiers) for the data that has higher priority. Your SLO should reflect this priority
and events with higher priority should have a tighter SLO.

## End-to-end measurement

If you have a data pipeline that has multiple stages it may be useful to not only measure the SLOs of
the individual components but also pay close attention to an end-to-end SLO. This category is quite
important when you are looking for instance at data that is using for debugging.

This may be a very interesting key for creating SLOs, but it depends a lot on how your organization
works. If you are not responsible for creating the data or for the queuing system in between then
your SLO may end up depending on other components that are out of you control and that you may not be
directly responsible.

In our case we are only responsible for the exact _pipeline_ of the data. Events are produced by our
applications and are written into our central Kafka queue. From there, multiple consumers use the
data. Our particular case is ingesting it into an Elasticsearch cluster that is used for debugging
and for visualizing/querying the data in multiples ways.

How can we define an SLO specific for our case?

If we create an SLO around our _data freshness_ then our SLO will be influenced by the producers, if
they go down or have a communication issue with Kafka (our central queue) then we will get SLO
violations. In this case our SLO will cover failure modes that are not included within the
scope of our pipeline. An SLO in the form of _The pipeline job has completed successfully within Y
[seconds, days, minutes]_ may work, but this is more effective when we have pipelines that run for a
given set of data and stop.

Since we don't control the data flowing through the pipeline, defining a _data correctness_ is quite
tricky. The producers are the ones that know which data is encoded in the events, and they usually
check this *after* the data passed through our pipeline (in Elasticsearch).

_data isolation/load balancing_ is normally ensured by the producers writing data into different
topics, and each topic is consumed with a variable number of processor instances. The number of
processors working on the same topic depends on how critical the data, how many partitions the
topic has and how much data is produced.

If we instead try to define an end-to-end SLO we have the same issue that our SLO will still include
components out of our responsibility.

Having an end-to-end SLO is desired in some situations, specially when we are shipping features to
an external user. This works great as a measurement of the general reliability of your service, this
means that any component involved in the request flow from the user that is down should affect the
SLO.

# variance picture

For our particular case an end-to-end SLO creates too much variance, over components that we cannot
influence. Previously we were creating alerts over the amount of data in the topic. If the amount
events in the queue passed a given threshold then it would send an alert.

We define the _lag_ of a kafka topic as the difference between the last committed offset to the topic
and the last offset of a given consumer group. We track this value in our monitoring setup, under a
metric called `kafka_consumergroup_lag`.

```js
sum(kafka_consumergroup_lag) by (topic, consumergroup)
```

Over this metric we set a max threshold and we can alert if the result of the query goes above a
given threshold.

This alert may trigger if we have a sudden burst in data written to the topic: but if the data is
processed _fast enough_, do we really care that we are processing more data? The entire purpose of
our processors is to process data.

This alert is also susceptible to minor slowdowns of the pipeline or storage system. I mean, sure if
we cannot index the data from our processors we want to get an alert but not every time that there is
a temporal slowdown due to network congestion or new indices being created.

If instead of thinking about the _number of events to process_ we start think about how long it takes
to process the existing lag then it is easier to reason about the alerting conditions.

We do not have to think anymore about how many events are in the queue's topic. If we set an SLO over
this metric is easier to understand and communicate: _we support a pipeline delay of up to Y
[seconds, days, minutes]_.

This should also help to avoid alert fatigue, we do not need to continuously tweak the threshold for
each topic. Because we are focusing on _how fast_ the processor will process the existing lag, a
normal value should work fine for almost all topics and the amount of data written/consumed will
dictate how fast this "error budget" is consumed.

In practice this allows to use the _speed_ of the processor as a control variable for the amount of
lag in the topic, while still focusing in a single numeric dimension.

What our alerting query needs to calculate now is something like:

```js
current_lag / speed > $THRESHOLD
```

The `current_lag` can be fetched by the previous query. For the `speed` we can rely on the
[`rate()`][rate]/[`deriv()`][deriv] query functions (the actual function to use depends on the metric
type). A query like:

```js
rate(kafka_consumergroup_lag_sum[1h])
```

or

```js
deriv(kafka_consumergroup_lag_sum[1h])
```

will return the per-second rate of change/derivative of the underline metric.

Putting those 2 queries together as we mentioned before we get:

```js
kafka_consumergroup_lag
/
deriv(kafka_consumergroup_lag_sum[1h])
```

The main issue with this query is that it uses the current "speed of the processor" for calculating
how long it will take to process the current amount of data. Unless your processor is running at full
throughput all the time this will lead to skewed results. What we *really* want to calculate is:

```js
current_lag / max(speed) > $THRESHOLD
```

For this we need to use the [`max_over_time()`][max_over_time] function:

```js
max_over_time(deriv(kafka_consumergroup_lag_sum[4m])[2d:5m])
```

This query relies on the [subquery support](https://prometheus.io/blog/2019/01/28/subquery-support/)
added to Prometheus back in version 2.7.

This query will calculate the derivative of the processing speed at a 4m window and will get the max
value over the last 2 days using a `5m` window.

> Depending on how back your query goes to calculate the `max_over_time` your query can become slow.
> Our recommendation is to go old-school (before Prometheus supported subqueries at all) and setup a
> recording rule for pre-calculating these values.

Keep in mind that this query will only return the max seen throughput (in the given interval). It is
possible that your processor is faster than the values seen in the given interval.

Combining these two parts into a single query:

```js
kafka_consumergroup_lag_sum
/
max_over_time(deriv(kafka_consumergroup_lag_sum[4m])[2d:5m])
```

Graphing these values in Grafana and setting the axis to seconds we get something like:

{{< picture "consume-time-graph" "Plot of the time to consume the lag at maximum throughput" >}}

It is now easier to understand how long it will take to process the lag and set an alert on this
value. If it takes longer than 30 minutes we get an alert.

<!-- This new query makes it easier to create an actionable alert that is more resilient to sudden
temporary bursts or slowdowns of the processor. At the same time, this alert works better than a
plain threshold on the lag, if the processor stops even with little traffic, the amount of time
needed to process the lag will increase and it will trigger, even if the number of queued events is
not that high. -->

I would say that there is one additional condition that we can add to our alert. If we get a burst of
new data but we are sure that it is going to be processed in a sensible amount of data we may not
want to get an alert at all. We can _encode_ this requirement as: _and if the lag is increasing_:

For this we need to append the following to our query:

```js
and deriv(
  kafka_consumergroup_lag_sum[20m]
) > 0
```

This means that if the lag is increasing and it is going to take longer than our threshold then for
sure we want to get a notification.

> Of course this type of constraints to our alert depend on your specific environment and on how the
> data is used after it leaves your pipeline.

This situation may be better handled in [Alertmanager][alertmanager] (or similar component), if we
are in the middle of the day and people are actively using the data then it is more likely that you
want to know that the data is going to be a bit delayed, and maybe inform the teams that use the
data. But if this happens in the middle of the night and the data is going to be available before
people start working then _maybe_ and just maybe this is not urgent enough to wake people up.


_People vector created by [pch.vector - www.freepik.com](https://www.freepik.com/vectors/people)_

[srebook]: https://sre.google/sre-book/data-processing-pipelines/
[workbook]: https://sre.google/workbook/data-processing/
[rate]: https://prometheus.io/docs/prometheus/latest/querying/functions/#rate
[deriv]: https://prometheus.io/docs/prometheus/latest/querying/functions/#deriv
[deriv]: https://prometheus.io/docs/prometheus/latest/querying/functions/#deriv
[max_over_time]: https://prometheus.io/docs/prometheus/latest/querying/functions/#aggregation_over_time
[alertmanager]: https://prometheus.io/docs/alerting/latest/alertmanager/
