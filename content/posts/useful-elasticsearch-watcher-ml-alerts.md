---
title: "Useful alerts with Elastic Watcher & Machine Learning"
description: >
 Create more useful alerts using Elastic's Watcher and
 Machine Learning.
date: 2019-03-15T17:00:00+01:00
draft: false
---

Alerts should be meaningful, simply getting a notification about something
happening is not enough. A [good alert](https://blog.danslimmon.com/2017/10/02/what-makes-a-good-alert/)
should be **actionable** and **investigable**. For me, this means getting a
answer to the following questions:

### What happened?

Was the traffic to the Web site unusually low? Did the number of errors
increase? This is the type of information that the alert should contain in a
clear and visible way.

### Why an alert triggered?

What does it mean if the traffic is *unusually low*, would a 5% qualify for
this category? What about 10%? How much are too many errors? What *type* of
errors has increased?

### What's next?

Now that I've received this alert, what to do next? What should I check first?
How do I get a first glance at the situation?

These questions are even more important if you add Machine Learning&trade; into
the mix. ML is not the holy grail of alerting. Yet, it can help detect
situations that you didn't foresee before. This means that sometimes you would
get a notification about an *anomaly* that will be the first time that happens.
If an alert answers the three previous questions it will steer you in the right
direction.

## Let's build something

Elastic stack now supports (with the addition of X-pack)
[alerting](https://www.elastic.co/products/stack/alerting). Even more
powerful (if you can afford it) combined with the use of [Machine
Learning](https://www.elastic.co/products/stack/machine-learning). And yes,
sounds pretty cool, and it is well integrated into
[Kibana](https://www.elastic.co/de/products/kibana).

Eventually, you will have more than one ML job configured, and it is likely that
this number will increase. Having 1 alerting job for each individual ML job
will not scale. Watcher UI it is simple enough if you want a simple threshold-based alert. But if you really want to use what Watcher offers you will end up
writing a ton of JSON to have a flexible enough alert.

If you google enough you will find a few [blog posts](https://www.elastic.co/blog/alerting-on-machine-learning-jobs-in-elasticsearch-v55)
and even some [example jobs](https://github.com/elastic/examples/blob/master/Alerting/Sample%20Watches/ml_examples/bucket_watch.json)
that will help you. But the example alerts that you usually find for Watcher
are very simple. No one can write a perfect example tailored to your particular needs.

In a more practical way an alert should include, to answer the previous three questions:

* The name of the job that triggered the anomaly.

This name should be clear and related to the data/situations that it is checking.

* Which specific feature(s) influenced this result.

If you have a multi-metric job you will want to know which specific metric(s) triggered the anomaly.

* A link to the Anomaly Explorer clearing showing the issue.

Probably you have a lot of dashboards in your ES cluster. Perhaps you're even
using [Grafana](https://grafana.com/) with ES. Providing a link to all
dashboards in your organization that are related to the main issue is out of
the question. A link to the Anomaly explorer clearly highlighting the issue
should be a good start.

A reasonable useful alert message may look like:

```
Job <job name>.
Anomaly of score=<score> at <timestamp> influenced by:
<metric> score=<metric score>, actual=<value>, (typical=<value>)
<metric1> score=<metric1 score>, actual=<value>, (typical=<value>)

<deep dive link>
```

[This alert example](https://github.com/elastic/examples/blob/master/Alerting/Sample%20Watches/ml_examples/bucket_watch.json)
it's a good starting point.

First of all, we don't want to keep 1 alert per ML job because we would need to
add one new alert every time that we add a new job, and also it would lead to a
lot of duplication.

Let's remove the `term` query that it's matching in the `job_id`:

```json
"term": {
 "job_id": "farequote_response"
}
```

Now our alert will "watch" all jobs in the cluster. You can also tweak the rest
of the options: `interval`, the `range` filter, etc.

The core issue of the alert is what its included in the `text` key inside the
specific `actions` elements:

```
"actions": {
  "log": {
    "logging": {
      "text": "Anomalies:\n{{#ctx.payload.hits.hits}}
        score={{_source.anomaly_score}}
        at time={{_source.timestamp}}\n{{/ctx.payload.hits.hits}}"
    }
  }
}
```

In a real-life scenario this would be probably the message posted to a
specific Slack (or similar) channel. We need to collect some information
before sending the alert.

Thankfully ES Watcher supports [transform scripts](https://www.elastic.co/guide/en/x-pack/current/transform-script.html)
written in [painless](https://www.elastic.co/guide/en/elasticsearch/reference/master/modules-scripting-painless.html).
Which will allow us to do a lot of transformations to the data before the
alert is sent.

#### Get the name of the job that triggered the anomaly.

We can take the job name or `job_id` from the first element that matches our query scheduled query:

```js
return [
 'job_id': ctx.payload.first.hits.hits.0._source.job_id
]
```

#### Round the scores (not a lot of useful information after 2 decimal places)

For rounding the scores we can use the [DecimalFormat](https://www.elastic.co/guide/en/elasticsearch/painless/6.1/painless-api-reference.html)
class:

```js
def df = new DecimalFormat('##.##');

return [
 'anomaly_score': df.format(ctx.payload.anomaly_score)
]
```

#### Get the start time & end time of the anomaly

This is a bit tricky, we know when the anomaly was triggered, but we still need
to provide a timeframe to Kibana in order to show the anomaly when it happened.
For this we can take the moment when the anomaly was triggered and
substract/add some minutes to get a timeframe when the anomaly should be
clearly visible:

```python
def current = Instant
  .ofEpochMilli(ctx.payload.first.hits.hits.0._source.timestamp)
  .atZone(ZoneId.systemDefault());

return [
 'start_time' : current.minus(Duration.ofMinutes(20))
    .format(DateTimeFormatter.ISO_INSTANT),
 'end_time' : current.plus(Duration.ofMinutes(20))
    .format(DateTimeFormatter.ISO_INSTANT)
]
```

For this example, we're assuming a [-20 minutes, +20 minutes] window around the
anomaly timestamp.

#### Get the list of metrics that triggered the anomaly.

Finally, we need a list of all metrics (influencers) that triggered the anomaly.
A bit more of scripting:

```js
return [
 'anomaly_details': ctx.payload.second.hits.hits.stream().map( p -> [
    'metric': p._source.partition_field_value,
    'score': df.format(p._source.record_score),
    'actual': df.format(p._source.actual.0),
    'typical':df.format(p._source.typical.0)
  ]).collect(Collectors.toList())
]
```

### Gluing everything

Now that our transform script provides a more friendly view of the data we can
configure the actual message that is going to be posted to your
email/chat/ system.

When visualizing an anomaly in the Anomaly explorer in Kibana you may notice
that it has a URL similar to this one.

```
http://kibana/app/ml#/explorer?_g=(ml:(jobIds:!(<JOB_NAME>)),refreshInterval:(pause:!f,value:30000),time:(from:'<START_TIME>',mode:quick,to:'<END_TIME>'))&_a=(filters:!(),mlCheckboxShowCharts:(showCharts:!t),mlExplorerSwimlane:(viewBy:domain.keyword),mlSelectInterval:(interval:(display:Auto,val:auto)),mlSelectLimit:(limit:(display:'10',val:10)),mlSelectSeverity:(threshold:(display:major,val:50)))
```

Now we can interpolate the data extracted from the anomaly into this link and
go from Slack to Kibana showing exactly what we need to see.

Finally the `text` section of our alert would look similar to:

```json
"text": "
  *Job*: {{ctx.payload.job_id}}\n
  Anomaly of score={{ctx.payload.anomaly_score}} at
  {{ctx.payload.bucket_time}} influenced by:\n
  {{#ctx.payload.anomaly_details}}influencer={{metric}}:
  score={{score}}, actual={{actual}} (typical={{typical}})\n
  {{/ctx.payload.anomaly_details}}\n\n

  :kibana: <KIBANA_URL>"
}
```

> Note: I've removed the `KIBANA_URL` because it was discussed before and was making the entire example harder to read.

## TL;DR

After gluing everything together we get a notification that looks like:

![Final example alert in Slack](/images/es-watcher-ml-alert/final-alert-example.png "Example of an alert with all information in Slack")

You can get the full code for the example discussed in this blog post [in this gist](https://gist.github.com/jorgelbg/b1111add2436ca946b1b049fb63aaddb).
