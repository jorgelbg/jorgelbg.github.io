---
title: "How to rename index patterns in Kibana"
date: 2019-05-21T17:00:00+02:00
draft: false
description: >
    How to rename index patterns in Kibana without
    breaking your existing visualizations or dashboards.
tags: ["kibana", "index-pattern"]
images:
- /posts/2019/rename-kibana-index-patterns/kibana.png
---

If you have been using Kibana long enough you probably have a large collection
of visualizations and dashboards already created. From time to time you may have
a need to *rename* an already index pattern. Turns out that Kibana doesn't
support this. You can refresh the index pattern and you can drop it but that's
it. There is an [open issue in Github]
(https://github.com/elastic/kibana/issues/17542) to address this issue, but it
is still open at the time of writing this post.

To be clear, let's assume that, for the scope of this post, you have an index
pattern called `logstash*` that matches your daily indices (`logstash-%Y.%m.%d`)
`logstash-2019.04.03`. `logstash-2019.04.05`, etc. But now you start ingesting
data for your `dev` environment and the new indexes follow the pattern
`logstash_dev-%Y.%m.%d`. We can see that the old index pattern will also match
the new events. In a perfect world you have your index patterns as specific as
possible to avoid this issues, but if you're working on a legacy system you may
not be able to foresee this issue from the beginning.

You may want to drop the index pattern and create it again but if you're using a
recent version of Kibana, the `_id` of the index pattern is different than the
`title` or `name`. This means that when you drop the index pattern you
visualizations will have broken, pointing to an index pattern that no longer
exists. If you have defined some [scripted
fields](https://www.elastic.co/guide/en/kibana/current/scripted-fields.html)
these will be also lost. If you do this, you may [run into some
issues](https://github.com/elastic/beats/issues/10117).

The proposed workflow is to export the exact object that we need (an index
pattern) update it with the new pattern, delete the old copy and import it
again. The advantage of this approach is that since we're importing an index it
will keep the old `_id` field, which means that all your old
visualizations/dashboards will continue to work.

> Normally on the [Kibana Saved
> Objects](https://www.elastic.co/guide/en/kibana/current/managing-saved-objects.html)
> section you can edit the raw JSON of the visualizations/dashboards. But for
> some reason they don't allow the same for the index patterns. If you click on
> the index pattern it will just redirect you to the "Index patterns" section.
> In this section you cannot (unfortunately) edit the title/name of the index
> pattern.

## Step by step guide

First, let's export the index pattern that we want to update

![Index pattern export](/posts/2019/rename-kibana-index-patterns/export-ui.png)

Open the JSON file with all the saved index patterns and (for safety) remove all
other index patterns, except the one that you need. You may end up with a JSON
similar to:

```json
[
  {
    "_id": "ehtekygbbnvfb0",
    "_type": "index-pattern",
    "_source": {
      "notExpandable": true,
      "timeFieldName": "@timestamp",
      "title": "logstash*",
      "fields": "[{\"name\":\"@timestamp\",\"type\":\"date\",
        \"count\":0,\"scripted\":false,
        \"searchable\":true,\"aggregatable\":true,
        \"readFromDocValues\":true}]"
        ...
    },
    "_meta": {
      "savedObjectVersion": 2
    },
    "_migrationVersion": {
      "index-pattern": "6.5.0"
    }
  }
]
```

Now you can edit the `title` field to match the new index pattern, in our case
this could be `logstash-*`. Since we include the `-` we're making sure that the
`logstash_dev*` indices are not matched by this index pattern. You may end up
with a JSON file similar to:

{{< highlight json "hl_lines=3 8" >}}
[
  {
    "_id": "ehtekygbbnvfb0",
    "_type": "index-pattern",
    "_source": {
      "notExpandable": true,
      "timeFieldName": "@timestamp",
      "title": "logstash-*",
      "fields": "[{\"name\":\"@timestamp\",\"type\":\"date\",
        \"count\":0,\"scripted\":false,
        \"searchable\":true,\"aggregatable\":true,
        \"readFromDocValues\":true}]"
        ...
    },
    "_meta": {
      "savedObjectVersion": 2
    },
    "_migrationVersion": {
      "index-pattern": "6.5.0"
    }
  }
]
{{< /highlight >}}

It is very important to keep the same `_id`. This is the field that Kibana will
use to know which index pattern the visualizations will query.

Delete your old index pattern.

Import the new index pattern by clicking on the Import icon on the Kibana Saved
objects section and dragging your edited JSON into the UI.

![Saved Objects import
UI](/posts/2019/rename-kibana-index-patterns/import-ui.png)

At this point, if you open your old dashboard everything should be working as
before;

## Summary

TBH this is, simply put, a workaround. This a feature that I expected Kibana
offered out of the box. If not baked into the UI at least through the edition of
the Saved Objects UI. Sadly this is not the case.

I've oriented this post around using Kibana since, the [import
API](https://www.elastic.co/guide/en/kibana/current/dashboard-import-api-import.html)
for exporting and importing the saved objects. The same is posible by using the
Kibana API.

{{< info >}}

If you want to know more about the structure of the documents that Kibana
persists in ES (for its internal use) you should check [this blog
post](https://www.elastic.co/blog/kibana-under-the-hood-object-persistence)

{{< /info >}}