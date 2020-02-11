---
title: "Better URL search with Elasticsearch"
date: 2020-01-01T11:46:14-05:00
draft: false
description: >
    Improved URL search in Elasticsearch using custom analyzers.
tags: ["elasticsearch", "search", "url"]
---

> 🚀 This article has been crossposted in the [trivago tech blog](https://tech.trivago.com/2020/02/11/better-url-search-with-elasticsearch/).

At trivago, we generate a huge amount of logs and we have our [own custom setup for shipping
logs](https://tech.trivago.com/2016/01/19/logstash_protobuf_codec/) using mostly [Protocol
Buffers](https://developers.google.com/protocol-buffers). Eventually we end up with some fields in ES
that contain partial (or full) URLs. For instance in our specific case we store the [query
component](https://en.wikipedia.org/wiki/URL#Syntax) of the URL in a field called `query` and the
[path component](https://en.wikipedia.org/wiki/URL#Syntax) in a field named `url_path`. Sample values
for these fields could be:

```sh
url_path = "/webservice/search/hotels/43326/rates"
query = "from_date=2020-06-01T00:00:00%2B02:00&to_date=2020-06-10T00:00:00%2B02:00&currency=EUR&room_type=9&room_0=2a&fixed_status=1"
```

We use the ELK stack as the core of our logging pipeline. Since Elasticsearch's primary use-case was that of a search engine, it comes equipped with a diverse assortment of tools to process data. Searching on
these URL-like texts is not the same as trying to search in a summary of a book. When a field is
defined as `text` in ES, it will apply by default the [Standard
Analyzer](https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis-standard-analyzer.html).

The Standard Analyzer uses the [Standard
Tokenizer](https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis-standard-tokenizer.html),
which provides grammar-based tokenization. Put simply: if the value of the field would be an English
sentence written using ASCII characters, the tokenizer will split the text based on punctuation signs,
spaces and some special characters (like `/` for instance).

This tokenizer works quite well for our `url_path` field:

```bash
POST _analyze
{
 "tokenizer": "standard",
 "text": "/webservice/search/hotels/43326/rates"
}
```

Producing the following list of tokens:

```json
[ "webservice", "search", "hotels", "43326", "rates" ]
```


If we test the value of the `query` field against this tokenizer, we can see that it produces a lot
of useless tokens:

```json
[ "from_date", "2020", "06", "01T00", "00", "00", "2B02", "00", "to_date", "2020", "06", "10T00", "00", "00", "2B02", "00", "currency", "EUR", "room_type", "9", "room_0", "2a", "fixed_status", "1" ]
```

Although it detected the `from_date` field, it fails to tokenize the value of the query
parameters as a single token, which makes searching very difficult.

It is more likely for a user to want to find documents where `currency` is set to `EUR` or
`room_type` equal to `9`. Generalizing this means that the users are interested in matching on the
key/value pairs present in the query string.

Let's go over a couple of ways we could approach this.

We could pre-process the data and make our Logstash pipeline split the data into multiple
fields (using the [`kv` filter](https://www.elastic.co/guide/en/logstash/current/plugins-filters-kv.html)
for instance). Creating a new field for each attribute in the query string could lead to a
cardinality explosion in our indexes, even more, considering that any user could create
random key/value pairs.

We could work around the cardinality issue by flattening the structure and having a couple of nested
fields (`name` and `value`):

* `query.name` the field that could hold the attribute name
* `query.value` that would hold the value

This approach would introduce yet another problem. The `query` field would have to be an array of objects
and as such, it would lead to queries matching in unexpected ways. Let me explain:

If we have the following values for our `query` field (as an array of objects) in a couple of documents:

```json
"query": [
    { "name":"currency", "value":"EUR" },
    { "name":"room_type", "value":"9" },
]
```

A query such as this one:

```js
query.name:"currency" AND query.value:"9"
```

would match our sample document although it would be matching for the _"wrong reasons"_. In our
example, `currency` doesn't have a value of `9`, but since both boolean conditions are evaluated as
`true`, the given document would produce a match. It is more likely that the user firing this query
wants to match on `currency` having the value `9` which _should not_ produce any matches in our sample
data.

## Our solution

Since our end goal is to match by attribute name/value pair, if we could make these pairs a **single
token**, we would accomplish our goal with the benefit of having a single field and not strange
matches. With this approach, each key/value pair of the query string would be a single
token in the form of `name1=value1` and `name2=value2`. This means that then we could write a query
like:

```js
query:"currency=EUR"
```

This changes how we can query the data, but it guarantees that it would not produce false matches.
Since we don't generate new fields dynamically, there is also no risk of having cardinality issues.

The tokenization can be implemented in different places in the pipeline. Using the [split
filter](https://www.elastic.co/guide/en/logstash/current/plugins-filters-split.html) or the
previously mentioned [kv
filter](https://www.elastic.co/guide/en/logstash/current/plugins-filters-kv.html). We decided to
use a [custom pattern analyzer](https://www.elastic.co/guide/en/elasticsearch/reference/current/analysis-pattern-analyzer.html) on the Elasticsearch side.

Our `pattern_analyzer` uses a custom tokenizer defined as:

```json
"url_pattern": {
    "pattern": "&",
    "type": "pattern"
}
```

We also use a custom `char_filter` to handle the decoding of some special characters into their ASCII
equivalent, which makes the queries more user friendly:

```json
"char_filter": {
    "url_escape_filter_mapping": {
        "type": "mapping",
        "mappings": [
            "%20 => +",
            "%2B => +",
            "%2C => ,",
            "%3A => :",
            "%5E => ^",
            "%7C => |",
            "%3D => =",
            "%5B => [",
            "%5D => ]"
        ]
    }
}
```

Finally, we define a custom analyzer called `pattern_analyzer`:

```json
"pattern_analyzer": {
    "filter": [
        "lowercase",
        "asciifolding",
        "stop",
        "unique"
    ],
    "char_filter": [
        "html_strip",
        "url_escape_filter_mapping"
    ],
    "type": "custom",
    "tokenizer": "url_pattern"
}
```

This analyzer is used in our mapping templates:

```json
"query": {
    "norms": false,
    "analyzer": "pattern_analyzer",
    "type": "text"
},
```

If we test the initial value of our `query` field against the field using the custom analyzer:

```bash
POST accesslogs/_analyze
{
    "field": "query",
    "text": "from_date=2020-06-01T00:00:00%2B02:00&to_date=2020-06-10T00:00:00%2B02:00&currency=EUR&room_type=9&room_0=2a&fixed_status=1"
}
```

We get a more useful list of tokens:

```json
[ "from_date=2020-06-01t00:00:00+02:00", "to_date=2020-06-10t00:00:00+02:00", "currency=eur", "room_type=9", "room_0=2a", "fixed_status=1" ]
```

Using this list of tokens, it is easier to find those specific requests that we're looking for. It is
even more intuitive what is going on if we need to share the query with a colleague.

{{< info >}}

We could've decided to write our own tokenizer to deal with URLs. It would have provided us with full
control over the Token Stream (i.e tokens) produced by Elasticsearch. Still, dealing with custom
analyzers involves writing and maintaining custom plugins, which would have been definitively more
difficult to support in the long run. Instead, we chose to leverage the already quite flexible
toolbox provided by Elasticsearch.

{{</ info >}}

## Thanks

I want to thank my colleague [🦄 Dario Segger](https://github.com/unidario) (currently ex-teammate)
that did the implementation described in this post. We've been using this approach for some time now.
