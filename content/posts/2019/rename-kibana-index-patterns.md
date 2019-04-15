---
title: "Renaming index patterns in Kibana"
date: 2019-04-15T15:39:05+02:00
draft: true
description: >
    How to rename index patterns in Kibana without breaking your existing
    visualizations or dashboards.
---

If you have been using Kibana long enough you probably have a large collection
of visualizations and dashboards already created. From time to time you may have
a need to *rename* an already index pattern. Turns out that Kibana doesn't
support this. You can refresh the index pattern and you can drop it but that's
it.

Just to be clear, let's assume that, for the scope of this post, you have an
index pattern called `logstash*` that matches your daily indices
(`logstash-%Y.%m.%d`) `logstash-2019.04.03`. `logstash-2019.04.05`, etc. But now
you start ingesting data for your `dev` environment and the new indexes follow
the pattern `logstash_dev-%Y.%m.%d`. We can see that the old index pattern will
also match the new events. In a perfect world you have your index patterns as
specific as possible to avoid this issues, but if you're working on a legacy
system you may not be able to forsee this issue from the beginning.

You may be inclined to drop the index pattern and create it again but if you're
using a recent version of Kibana, the `_id` of the index pattern is different
than the `title` or `name`. This means that when you drop the index pattern you
visualizations will be broken, pointing to an index pattern that no longer
exists. Also, if you have defined some [scripted
fields](https://www.elastic.co/guide/en/kibana/current/scripted-fields.html)
these will be lost.

Since all of the Kibana settings are persisted in the `.kibana` index there is
one obvious way which is writing some `curl` commands and updating the specific
document that refers to the `logstash*` index pattern. Although this should work
it could be potentially a disaster if you manage to modify what should not be
modified.

The basic workflow is just to export the exact object that we need (an index
pattern) modify it in our favorite code editor, delete the old copy and import
it again. The advantage that this have is that since we're importing a index it
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

1. First let's export the index pattern that we want to update

![Index pattern export](https://jorgelbg.blob.core.windows.net/jorgelbg-dropshare/Screen-Shot-2019-04-15-4-39-09.38-PM.png)

> Make sure to only export the index patterns that you want to edit, otherwise
> you will have a potentially very large JSON file.

2. Now you can open the JSON file with all the saved index patterns and (just
   for safety) remove all other index patterns, except the one that you need.
   You may end up with a JSON similar to:

```json
[
  {
    "_id": "ehtekygbbnvfb0",
    "_type": "index-pattern",
    "_source": {
      "notExpandable": true,
      "timeFieldName": "@timestamp",
      "title": "logstash*",
      "fields": "[{\"name\":\"@timestamp\",\"type\":\"date\",\"count\":0,\"scripted\":false,
        \"searchable\":true,\"aggregatable\":true,\"readFromDocValues\":true}]"
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

3. Now you can edit the `title` field to match the new index pattern, in our
   case this could be `logstash-*`. Since we include the `-` we're making sure
   that the `logstash_dev*` indices are not matched by this index pattern. You
   may endup with a JSON file similar to:

```json
[
  {
    "_id": "ehtekygbbnvfb0",
    "_type": "index-pattern",
    "_source": {
      "notExpandable": true,
      "timeFieldName": "@timestamp",
      "title": "logstash*",
      "fields": "[{\"name\":\"@timestamp\",\"type\":\"date\",\"count\":0,\"scripted\":false,
        \"searchable\":true,\"aggregatable\":true,\"readFromDocValues\":true}]"
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

It is very important to keep the same `_id`. This is the field that Kibana will
use to know which index pattern is associated with a given visualization.

4. Delete your old index pattern.

5. Import the new index pattern by clicking in the Import icon on the Kibana
   Saved objects section and dragging your edited JSON into the UI.

![Kibana import UI](https://jorgelbg.blob.core.windows.net/jorgelbg-dropshare/Screen-Shot-2019-04-15-5-04-43.22-PM.png)

Now if you open some of your old visualizations, you will notice that the index
pattern is working for the desired subset of the data and none of your
visualizations are broken.

## Summary

TBH this is, simply put, a workaround. This a feature that I expected Kibana
offered out of the box. If not directly into the UI at least through the edition
of the Saved Objects UI. Sadly this is not the case.

I've oriented this post around using Kibana since, the [import
API](https://www.elastic.co/guide/en/kibana/current/dashboard-import-api-import.html)
will validate the payload. If you modify the ES documents directly you can
literally modify the document in any way that you want, which may cause
unintended consequences.