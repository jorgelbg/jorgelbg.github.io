---
title: "Solr Contextual Synonyms with Payloads"
date: 2018-03-06T01:00:00+01:00
draft: false
---

## TL;DR

Solr comes with a great set of tools to dealing with usual text processing tasks. One of this tools is the `SynonymFilterFactory` which allow to specify a list of synonyms. Last year we saw some [improvements to this feature](https://lucidworks.com/2017/04/18/multi-word-synonyms-solr-adds-query-time-support/), focused around multi word synonyms.
Even with the new changes introduced in Solr there are still some caveats, as explained by [Doug on this post](https://opensourceconnections.com/blog/2018/02/20/edismax-and-multiterm-synonyms-oddities/). To be honest this was developed some time ago, back when Solr 5 was the "cool" new version 😁.

This post describes a component to index token synonyms as a payload. Instead of a big file, you send the synonym as a payload for the desired token. This approach works great for single term synonyms, specifying the synonyms at index time. If you're curious about how this works, then continue reading.

## A bit of history

Some time ago I suggested a similar approach in this [question, posted on stackoverflow.com](https://stackoverflow.com/questions/34122982/lucene-solr-store-offset-information-for-certain-keywords). A user was asking to store positional information about the tokens. The end goal was to define something that we could call "contextual synonyms".

> Contextual synonym: a single term can relate to different concepts in the same text.

For instance, if we take a look at the following sentence: `Bill talked to the white house about the bill`. The first occurrence of `Bill` could be a reference to  `Bill Clinton`. While the second appearance of `bill` relates to some law<sup>1</sup>. One business rule could be that a query with the term `Clinton` should match this document. I know, I know I'm doing a lot of assumptions, but bear with me until the end. If we use the traditional synonym mechanism built in Solr, then we may set up a synonym like:

```
bill => clinton
```

> Figuring out to which tokens apply the synonym is out of the scope of this post.

Let's assume that we're using the `LowerCaseFilterFactory`. Solr doesn't know how to differentiate between the two occurrences of `bill`. We need some mechanism to tell Solr that `clinton` is also a synonym of only the **first** occurrence of `bill`. In short, this query: `"clinton talked"` should then match our document, but not this one `"about clinton"`.

Solr doesn't provide an out-of-the-box approach for deciding when to apply or not a synonym. But using some Lucene/Solr sauce we can do it. Lucene stores  some positional information for each token. What we want is to have some mechanism to adding the synonym only for certain tokens. Turns out that Lucene already provides a way to attach some "metadata" to a token: a payload. This *payload* could be anything that we want. It's encoded as an array of `bytes` (`bytes[]`). Solr exposes this feature as a `TokenFilter` that uses a delimiter to split the token from the payload. We also have access to several encoders (`FloatEncoder`, `IntegerEncoder`, `IdentityEncoder`) to store `floats`, `integers`, and `strings`.

In Solr indexing payloads is very easy, in this case we're using the (`|`) pipe character as the delimiter.

```xml
<filter class="solr.DelimitedPayloadTokenFilterFactory" delimiter="|" encoder="identity"/>
```

Any token in the form of `A|B` sent to Solr will be interpreted as token `A` with payload `B`. The `DelimitedPayloadTokenFilterFactory` will remove `|B` from the token before sending it down the analysis chain. If we send the following into Solr:

```
Bill|Clinton talked to the white house about the bill
```

`Clinton` will be stored as the payload of the `Bill` token and the later `bill` will remain unchanged.

This doesn't solve our problem, but we're on track, so far we've found a way to send custom tokens (synonyms) into Solr. The *payload* metadata is usually [used to influence the score calculation](https://lucidworks.com/blog/2014/06/13/end-to-end-payload-example-in-solr/). We're going to write our own `TokenFilter` that reads the payload and will add it to the token stream.

This should be a more straight forward synonym implementation. We don't need to parse any rule to find which synonym to use, and we already know *where* and *what* token to add.

<!-- This token filter will be a lot easier than the existing implementation, mainly because no rule parsing of a file and no guessing which rule apply to each token is needed; of course it will be also less powerful, since we're talking about a synonym to a **token** we don't have the ability to define a multiword synonym. For instance using `SynonymFilterFactory` we could specify the following synonym:

```
domain name server => dns
```

In each occurrence of `domain name server`, the synonym will be used. With our implementation this wouldn't be possible because we're attaching each synonym in the corresponding token, so the current token doesn't know about the previous/next tokens. -->

## The code

Now we know what we need to write, so let's doit.

Writing a `TokenFilter` is not that hard, but of course depends on the task at hand. We need a class that extends from `TokenFilter`  and overrides the `incrementToken()` method. As described on JavaDoc:

> This method is used to advance the stream to the next token and should return `false` for the end of the stream of tokens and `true` otherwise.

Our custom filter will access the term's payload using the  `PayloadAttribute` class. This property will provide read/write access to the payload of the current term. The API around the token stream is an iterator, and each call to `incrementToken()` will advance to the next token.

Suppose we send the following document into solr: `A B|E C`, what we're trying to say is that `E` is a synonym of `B`. This means that phrase queries should continue to work as expected. Bottom line we need our method to output a token graph (Yes! Token streams in Lucene are graphs‼️) like this:
```json
(A0) ----> (B1) ----> (C2)
  \                  /
    -----> (E1) ----
```

Actually, the previous graph is not an exact representation of a `TokenStream`. If we're going to get serious the graph will look more like this:

```json
       A          B          C
(0)  -----> (1) -----> (2) -----> (3)
               \      /
                -----  
                  E
```

The tokens are placed in the edges of the graph and the nodes are the states/positions of the token. But for our task at hand we can rely on the first graph for an easier representation.

So `B` and `E` should have the same position in the token graph (1). A phrase query like: `"B C"` will match our document, but also `"E C"` or `"A E"`. To do this we'll need to use the `PositionIncrementAttribute` class. The code for our `incrementToken()` method is roughly something like:

```java
if (!extraTokens.isEmpty()) {
  restoreState(state);

  posIncrAtt.setPositionIncrement(0); // keep the same position of the token
  typeAtt.setType(SynonymFilter.TYPE_SYNONYM);
  termAtt.setEmpty().append(extraTokens.remove());

  return true;
}

if (input.incrementToken()) {
  BytesRef payload = payAtt.getPayload();

  extraTokens.add(payload.utf8ToString());
  state = captureState();

  return true;
}

return false;
}
```

The `incrementToken()` method returns the metadata for the next token. Because of this, we need to save the state of the attributes to "insert" the  synonym in the right position. Also the position increment needs to be set to 0 or the term will be in the wrong position.

Our implementation detects the token with a payload and in the next call we add the payload as a new token. In the final implementation we do a couple more of things:

- remove the payload (since we don't need it anymore)
- split the payload using a delimiter character to generate several synonyms

## Testing

How do we test that our implementation is working as intended? At this stage you may compile your project, generate a jar and add it to Solr and hope that all works well.

The best approach for testing our implementation is writing a Unit Test. Thanks to the amazing committers and community, Lucene already ships with `BaseTokenStreamTestCase`. A base class that provides several helper methods for testing.

But what do we want to test?

To "glue" everything in Solr, we need the `solr.DelimitedPayloadTokenFilterFactory` to index tokens and payloads. But this class is already tested in the Lucence/Solr codebase. For testing our custom filter we need tokens with payloads attached. Let's write a dummy `TokenFilter` that will provide us with a proper stream of tokens with payloads.

```java
private final class DummyPayloadTokenFilter extends TokenFilter {
  private final CharTermAttribute termAtt = addAttribute(CharTermAttribute.class);
  private final PayloadAttribute payAtt = addAttribute(PayloadAttribute.class);

  private final List<String> payloadTokens = Arrays.asList("A", "B", "C");
  private final PayloadEncoder encoder = new IdentityEncoder();
  private final BytesRef payload;

  private DummyPayloadTokenFilter(TokenStream input) {
    super(input);
    this.payload = encoder.encode("D".toCharArray());
  }

  private DummyPayloadTokenFilter(TokenStream input, String payloadValue) {
    super(input);
    this.payload = encoder.encode(payloadValue.toCharArray());
  }

  @Override
  public boolean incrementToken() throws IOException {
    if (input.incrementToken()) {
      if (payloadTokens.contains(termAtt.toString())) payAtt.setPayload(payload);
      return true;
    } else {
      return false;
    }
  }
}
```

With this dummy `TokenFilter` we can wrap a mock of a `TokenStream` and feed it into our `PayloadSynonymTokenFilter` and test our custom logic.

Now to the next item, how do we test a `TokenFilter`? We need to start with a string (`A B C`), which needs to converted into a `TokenStream`. For this we can use the handy helper method `whitespaceMockTokenizer()`. This methods will tokenize the string at any occurrence of a whitespace character. Once we have an actual `TokenStream` to feed to our filter we can start writting assertions.

We need to call `incrementToken()` and at each step check if the current term is correct and if any other term attribute (such as our beloved payload) has also the expected value.

This assertions are not hard to write. Peeking around the Lucene test suite I came across this handy method than resembled a lot to what I was writing. I decided to use it instead (no harm no fall).

```java
void assertTermEquals(String expected, TokenStream stream, CharTermAttribute termAtt, PayloadAttribute payAtt,
    byte[] expectPay) throws Exception {
  assertTrue(stream.incrementToken());
  assertEquals(expected, termAtt.toString());
  BytesRef payload = payAtt.getPayload();

  if (payload != null) {
    assertTrue(payload.length + " does not equal: " + expectPay.length, payload.length == expectPay.length);
    for (int i = 0; i < expectPay.length; i++) {
      assertTrue(expectPay[i] + " does not equal: " + payload.bytes[i + payload.offset],
          expectPay[i] == payload.bytes[i + payload.offset]);
    }
  } else {
    assertTrue("expectPay is not null and it should be", expectPay == null);
  }
}
```

Using this method our test code is a series of calls to `assertTermEquals` passing the right arguments.

Let's go back to our initial test string. Assuming that only the `A` token carries a payload, our expected `TokenStream` should look like `A D B C`.  `D` should be a synonym of `A`: both `A` and `D` should have the same position in the stream. The test would look something like:

```java
@Test
public void testSingleSynonym() throws Exception {
  String test = "A B C";

  PayloadSynonymTokenFilter filter = new PayloadSynonymTokenFilter(
    new DummyPayloadTokenFilter(whitespaceMockTokenizer(test)),
    false, false, "_"
  );

  CharTermAttribute termAtt = filter.getAttribute(CharTermAttribute.class);
  PayloadAttribute payAtt = filter.getAttribute(PayloadAttribute.class);

  filter.reset();

  assertTermEquals("A", filter, termAtt, payAtt,
    "D".getBytes(StandardCharsets.UTF_8)
  );
  assertTermEquals("D", filter, termAtt, payAtt,
    "D".getBytes(StandardCharsets.UTF_8)
  );
  assertTermEquals("B", filter, termAtt, payAtt, null);
  assertTermEquals("C", filter, termAtt, payAtt, null);
  assertFalse(filter.incrementToken());

  filter.end();
  filter.close();
}
```

For the `A` and `D` tokens we're also checking that the payload is still there (since we haven't removed it yet), but for `B` and `C` there should be no payload at all, so we pass a `null` parameter to validate this assumption.

Its important to check that the filter returns `false` when it reaches the end of the `TokenStream`.

There is still something missing in our test. Let's go back to the couple of figures at the beginning of the post, where we represent the `TokenStream` as a graph. In those graphs we can see that the token and the synonym should have the same **positional information**. In other words, both terms should be at the same position within the token stream. Or, said in the "Lucene jargon" the position increment of the synonym should be `0`. To check this in our test we need to use the `PositionIncrementAttribute` class:

```java
PositionIncrementAttribute posIncAtt =
    filter.getAttribute(PositionIncrementAttribute.class);

assertEquals(0, posIncAtt.getPositionIncrement());
```

The default position increment for the rest of the `TokenStream` should be 1, which we could also test.

Lucene use "attributes" to store information about a single token. Instead of storing the actual position of a term, Lucene stores the increment of each token. This `increment` is then used to figure out the actual position of the token in the stream. We can see this information in the analysis page of the Solr Admin UI. This is the internal mechanism that Lucene uses for phrase search and span queries, etc.

## Using in Solr

The entire code of this example is available in this [Github repo](https://github.com/jorgelbg/solr-payload-synonyms). You can build it using maven and then enable it in your Solr/Fusion installation as a normal filter:

```xml
<fieldtype name="payloads" stored="false" indexed="true" class="solr.TextField" >
 <analyzer>
   <tokenizer class="solr.WhitespaceTokenizerFactory"/>
   <filter class="solr.DelimitedPayloadTokenFilterFactory" delimiter="|" encoder="identity"/>
   <filter class="solr.custom.PayloadSynonymTokenFilterFactory"/>
 </analyzer>
</fieldtype>
```

Once our `fieldtype` is defined we can use the very helpful Analysis page of the Solr Admin UI to check if things are working as expected. If we use the test string: `Bill|Clinton talked about the bill` in the Field value (index) input and select our payload `fieldtype` we can see an output similar to what is shown in the figure.

![Solr Admin UI](/images/solr-synonyms/analysis-ui.png "Solr Admin UI")

A quick inspection, reveals that the tokens `Bill` and `Clinton` have the same positional information. Also the `Clinton` token has a defined type of `SYNONYM`.

## Advantages to this approach?

One question you may been doing yourself is what advantages provides this approach?

This approach *decentralizes* the synonyms management. Usually your synonyms live in a big text file on the filesystem of your Solr server. Adding new synonyms  means editing that file and adding a new rule.

In recent Solr versions, the `ManagedSynonymFilterFactory` class provides an HTTP endpoint to do this. But it is not a good idea to give everyone on your team access to this endpoints. I used this approach in a cloud-like environment for Solr. We provided Solr as a service to different teams with different needs. Along with the service we provided our own utility library for interacting with Solr.  In this library we did the heavy lifting and exposed a clean and easy API for the developers.

In this environment this approach gave control over the synonyms to each developer. They could customize their synonyms  without knowing the inner workings of Solr.

And of course this solves part of our initial statement: tailoring  a synonym to a specific term/token.

To wrap things up this has been a fun exercise and an atypical use of Lucene/Solr payloads. If it is useful to you then use it if not I hope you've enjoyed the reading, I've enjoyed the journey!
