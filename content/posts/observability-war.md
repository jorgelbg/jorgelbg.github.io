the observability war

I've played a bit with Honeycomb and I think they have a great use case and they're in fact different
than any other big provider like Datadog, Appdynamics, etc.

My main issue with @mipsytipsy definition of o11y is that they're trying to focuse on a single tool
that solves all the problem while the OSS solutions (partially) use different tools for different
things.

Elasticsearch is, from my point of view, in the best place to create something like what honeycomb has.

o11y control theory definition  .

https://twitter.com/lizthegrey/status/1212020766776184832

{{< tweet 877500564405444608 >}}

https://gohugo.io/content-management/shortcodes/

https://www.instana.com/blog/the-data-fog-of-observability/

I agree that Prometheus *by itself* it is not observability, but the observability concept doesn't say that you
need one tool and one tool alone to get observability. My believe is that if you combine metrics and
logs and traces in a _meaningful_ way you will be able to _observer_ your distributed systems.

The key point (from where I'm standing) is that by *just* collecting metrics, logs and traces you
automatically get observability, no, you need to connect them in a meaning ful way. Again, IMHO this
is what it is still lacking in the OSS world (and Grafana is working towards that goal). Honeycomb,
being a single tool is able to provide a very tight integration between these type of data. Even more
they approach this in a unique way.