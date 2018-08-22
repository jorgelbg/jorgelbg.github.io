---
title: "Logs and metrics for Small Data"
date: 2018-08-22T11:42:44+02:00
draft: true
---

This post is a personal comment. I'm going to talk about how using some tools thought for "Big Data"™ makes sense for common development tasks. If you hear someone talking about ELK, Grafana or Prometheus. You wouldn't thing about a system to run your laptop during development, right?


# Logs
Concatenating files, parsing logs, are some of those tasks that are part of our daily routine as developers. We type lots of commands (usually connected via pipes `|`) to accomplish a given goal.

Of course, I love my terminal. I spend a great amount of time in the console: committing code,  running tests, etc. I guess that typing something like:

```
$ cat ../../fixtures/json/payload1.json | tr -d '\n' | gsed 's/]}/]}\n/g' | phony --tick 100ms | ./main
```

Is very common for the majority of developers out there.

A few days ago, in my spare time, I was troubleshooting a bug with a Java application. I was debugging a local run of a crawl cycle using [Apache Nutch](http://nutch.apache.org/). My normal workflow involves several panels in my terminal (iTerm) and a lot of `cat`, `grep`, `sed`, etc.

At some point, I realized that the events I was looking for in the logs were spread in several log files and in different positions. Finding those events was not going to be easy. I needed to not only find one specific line, but the cases happening around that specific line.

And, it hit me. I have to do this several times a day at my normal job. As part of the Web performance team, we need to watch graphs and find specific events in hundreds of servers. Of course, dealing with that amount of data required some infrastructure. We have an ELK cluster that holds ~30TB of logs, and we use Kibana on a daily basis for this very purpose. It has to be like this, no one would think of maintaining an application at this scale without a centralized logging system, right?

Well, why couldn’t I use the same setup in my project? Right? Turns out that replicating a similar setup on my laptop wasn’t that difficult. Docker and the fact that elastic provides all its products as Docker images was a blessing.

I only needed to send the logs into Elasticsearch. Then search the desired information using Kibana.

I used Logstash to ingest the logs, you only need to find how you want your logs stored in Elasticsearch. It's possible that you'll ([need to deal with Stack traces](https://sematext.com/blog/handling-stack-traces-with-logstash/). There are plenty of resources on how to do this (and more) online.

Now it was only a matter of running one more container: Kibana. Which allowed using the full-text search capabilities of Elasticsearch. And that was it!.

The best of all: Although I spent some more minutes settings things up, no more than 30 minutes, for sure. The setup is already there for the next time that I need to use it.

It’s amazing how Docker have allowed us to run these tools without any complex installation. Could I’ve done the same using the good old terminal commands? Definitively! But sometimes is easier to use the same setup that you use for dealing with hundreds of servers.

# Metrics

The second part of this post is about metrics. Recently I’ve been working on a very interesting project at work. Enough to say that involves HTTP connections and payloads.

In the beginning, we focus on building the prototype and validating the initial idea. Then, we structured the code as a reusable library. But, at some point in-between we were curious to see how our little experiment was behaving.

Since this was only to please our curiosity we didn’t want to spend a lot of time on it.  What we needed was at the core a histogram, so we wrote a little piece of code. Calculate the length of the payload and store that as a key of the map and a counter as the value. At the end of our test, we printed the map to the terminal.

It’s no coincidence that I’m it the Web Performance Team 🤔 we are responsible for looking at graphs the entire day. I like graphs! I wanted to see some graphs!

In a more serious note. Although the map allowed us to see the distribution of the payload size still lacked one thing. How was behaving our code *over time*? For this, we changed our implementation and printed the first `N` samples to the terminal. Of course, at some point, I just copied the numbers into Excel and created a couple of graphs (I mentioned that I like graphs right?).

After we implemented the core feature of the application, I still wanted to see some "real time" graphs. I mean, the Excel visualization was great, but it was not very interactive.

At this point again, I realized that we’ve already solved this problem on a larger scale. We use InfluxDB & Grafana for creating dashboards and monitoring our entire infrastructure & application. More recently we’ve been using Prometheus and the new pull approach as well.

I didn’t want to send the metrics of my local application into our production InfluxDB server. There was no good reason to do so. I ended up replicating our “production” environment on my laptop for my personal use.

A simple `docker-compose.yml` file with only 57 lines and a few default config files in my local repo were enough. Ok, I ended up wanting to try the new [Grafana Explore UI for Prometheus](https://promcon.io/2018-munich/talks/explore-your-prometheus-data-in-grafana/) so I added one more config file for Grafana.

A few more lines to instrument my code with [client_golang](https://github.com/prometheus/client_golang) and that was it.

![Grafana dashboard with Prometheus datasource](/images/logs-and-metrics/grafana-prometheus.png "Grafana dashboard")

# TL;DR

We often hear how good is Docker for replicating your local environment in production. Or how it can revolutionize your CI/CD pipeline. We also heard about the new version of "it works on my machine" 😂

{{< tweet 917564505416073216 >}}

And of course, it's true, but sometimes we forget that it also works the other way around. Docker allows developers to apply already proven solution to problems in a local environment.

Tools like Elasticsearch, Logstash, and Kibana can deal with huge amounts of data. But, can also work for "small data" problems, like debugging some issues in your local environment.

At the same time, Prometheus, InfluxDB, and Grafana have made storing and visualizing metrics a very easy task.
