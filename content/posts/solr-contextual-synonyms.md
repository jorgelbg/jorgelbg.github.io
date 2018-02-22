---
title: "Solr Contextual Synonyms"
date: 2018-02-22T03:02:16+01:00
draft: true
---

## TL;DR

Solr comes with a great set of tools to dealing with usual text processing tasks. One of this tools is the `SynonymFilterFactory` which allow us to specify a list of synonyms. This token filter comes with a couple of very useful features and some caveats (LINKS TO SOME POST REFERENCING SOME OF THE PROBLEMS), specially when dealing with multiword synonyms.

To not give any false hopes, lets start saying that this approach does not solve the multiword synonym problem in Solr, there are a lot of very smart people working on this (like [Ted Sullivan](https://github.com/detnavillus) from [Lucidworks](https://lucidworks.com/)).

This post describes a component to index token synonyms as a payload when adding documents into your Solr server/cluster, so instead of a big file of synonyms, for defining a synonym you just send a payload to that token. This approach works well for single term synonyms and decentralize the managing of the synonyms, which is great in a cloud-like environment, if you don't want to read the article and want to do a quick test, wrap the component from [this github repo](http://github.com/jorgelbg/solr-synonym-payload) and follow the instructions to build a jar and use it in your Solr installation. If you want to know how this works, then continue reading.

## A bit of history

A few weeks ago on a [question posted on stackoverflow.com](http://stackoverflow.com/question-id) a user was trying to find a way to have a special kind of synonyms, which is something that I've started to call "contextual synonyms". The idea is that the occurrence of the same word in the same doc or field doesn't necessary means that the synonym should be used on both cases, for instance, if we take the following example: `Bill talked to the white house about the bill`. For the sake of this post lets say that the first occurrence of `Bill` was in fact a reference of `Bill Clinton` and the second term `bill` was a reference to some law. One particular use case may require that a query like `Clinton` should match this document (I know, I know I'm doing a lot of assumptions, but bear with me until the end, and you're already reading this so, you've taken the long road 😃). If we use the traditional synonym mechanism built in Solr, then we may set up a synonym like:

```
bill => clinton
```

In this case we are assuming that the `LowerCaseFilterFactory` is being used, and then we hit a problem: Solr doesn't know how to differentiate between the first `bill` and the second occurrence of `bill`. We need some mechanism to tell Solr that `clinton` is also a synonym of the **first** occurrence of `bill` but not the second one, so a query like: `"clinton talked"` should match our document but `"about clinton"` should not.

Solr doesn't provide an out-of-the-box approach for doing this, but using a very simple Lucene/Solr sauce we can accomplish our goal. Lucene stores internally the start/end position of each token, perhaps we can write "something" that apply the synonyms in the desired positions? Turns out that Lucene/Solr already provides a way to add some "metadata" to a given token, this metadata is known as a *payload* and could be anything that we want, is essentially an array of `bytes` (`bytes[]`). Solr provides the `DelimitedPayloadTokenFilter` that provides an easy mechanism to attach a payload to a token in a very straightforward syntax, for instance using the `|` character. And also comes bundled with a couple of encoders (`FloatEncoder`, `IntegerEncoder`, `IdentityEncoder`) to store floats, integers, and strings. And we could write our own encoder if we needed to.

In Solr indexing payloads is very easy, in this case we're using the (`|`) pipe character:

```xml
<filter class="solr.DelimitedPayloadTokenFilterFactory" delimiter="|" encoder="identity"/>
```

In this case, any token that arrives to this `DelimitedPayloadTokenFilterFactory` in the form of: `A|B` will add the `B` portion as a payload to the `A` token an remove the `|B` portion of the token. So if we send the following into Solr: `Bill|Clinton talked to the white house about the bill`, `Clinton` will be stored as the payload of the `Bill` token and the later `bill` will remain unchanged.

But this doesn't solve our problem, yes, we now have a token stored in the inverted index with the corresponding synonym as a payload, but Solr/Lucene queries are done on the tokens itself and not on the payloads, at the end a payload is a metadata that usually [is used to influence the score calculation](https://lucidworks.com/blog/2014/06/13/end-to-end-payload-example-in-solr/). One solution could be to implement a custom and *easier* synonym filter that looks for the token's payload and if found add this *payload info* into the token stream as a synonym. This token filter will be a lot easier than the existing implementation, mainly because no rule parsing of a file and no guessing which rule apply to each token is needed; of course it will be also less powerful, since we're talking about a synonym to a **token** we don't have the ability to define a multiword synonym. For instance using `SynonymFilterFactory` we could specify the following synonym:

```
domain name server => dns
```

In each occurrence of `domain name server`, the synonym will be used. With our implementation this wouldn't be possible because we're attaching each synonym in the corresponding token, so the current token doesn't know about the previous/next tokens.

## The code

So now we know what we need to write, so let's doit.

Writing a `TokenFilter` is not really that hard, but of course depends on the task at hand, in this case is very easy. We need a class that extends the `TokenFilter` class and overrides the `public boolean incrementToken()` method. This method is used to advance the stream to the next token and should return `false` for the end of the stream of tokens and `true` otherwise. The clever previous sentence was extracted from the JavaDoc of the class in case you're wondering.

Our custom filter should access the payload of the term using the  `PayloadAttribute` class, this property will give read/write access to the payload of the current term. The API around the token stream is an iterator and each call to `incrementToken()` will advance to the next token.

Suppose we send the following document into solr: `A B|E C`, what we're trying to say is that `E` is a synonym of `B`, so phrase queries should continue to work as expected, bottom line we need our method to output a token graph (YES! Token streams in Lucene are actually graphs!!) like this:

```
(A0) ----> (B1) ----> (C2)
   \                  /
     ----> (E1) ----
```

Actually the previous graph is not an exact representation of a `TokenStream`, if we're going to get serious the graph will look more like this:

```
       A          B          C
(0)  -----> (1) -----> (2) -----> (3)
               \      /
                -----  
                  E
```

The tokens are really placed in the edges of the graph and the nodes are the states/positions of the token. But for our task at hand we can think on the first graph for an easier representation.


So `B` and `E` should have the same position in the token graph (1). so a phrase query like: `"B C"` will match our document, but also `"E C"` or `"A E"`. To accomplish this we will need to use the `PositionIncrementAttribute` class. The code for our `incrementToken()` method is roughly something like:

```java
if (!extraTokens.isEmpty()) {
  restoreState(state);

  posIncrAtt.setPositionIncrement(0);             // keep the same position of the token
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

Since the `incrementToken()` method returns the metadata for the next token, we need to save the state of the attributes to "insert" the synonym in the right place, also we need to set the position increment to 0 or we wont insert the term in the right position. Basically we detect the token with a payload and in the next call we add the payload as a token. In the actual implementation we do a couple more of things, optionally remove the payload once has been extracted (we don't need it anymore), and generate several synonyms for the same token, splitting the payload using a delimiter character.

### Testing

How do we test that our implementation is working properly? At this stage you may compile your project, generate a jar and add it to Solr and hope that all works well. The best way of doing this is actually writing a Unit Test, and since we're writing code for Lucene, the Lucene team has been kind enough to provide a very useful base test case for token streams: `BaseTokenStreamTestCase` so lets hook this up with Junit4 and write our own test cases.

But what do we want to test?

To chain things in Solr, we need the `solr.DelimitedPayloadTokenFilterFactory` class to index tokens and payloads, but this logic is already tested in the Lucene/Solr codebase, so we should start with tokens that already have a payload, this is how our filter will actually work. For this I implemented a very dummy `TokenFilter` with the only purpose to attach an specified payload to a set of tokens:

```java
private final class DummyPayloadTokenFilter extends TokenFilter {
  private final CharTermAttribute termAtt = addAttribute(CharTermAttribute.class);
  private final PayloadAttribute payAtt = addAttribute(PayloadAttribute.class);

  private final List<String> payloadTokens = Arrays.asList("A", "B", "C");
  private final PayloadEncoder encoder = new IdentityEncoder();
  private final BytesRef payload;

  private WordTokenFilter(TokenStream input) {
    super(input);
    this.payload = encoder.encode("D".toCharArray());
  }

  private WordTokenFilter(TokenStream input, String payloadValue) {
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

But how do we test a `TokenFilter`? regarding of the logic implemented essentially we start with a test string: `A B C`, this test string needs to be tokenized into a `TokenStream`, using the very handy helper method `whitespaceMockTokenizer()` that actually mocks the inner working of a tokenizer (thanks Lucene guys). Once we have an actual `TokenStream` to feed to our filter we can start asserting things. What we want to do is call `incrementToken()` and at each step check if the current term is correct and if any other term attribute (such as our beloved payload) has also the expected value.

This assertions are not that hard to write, but peeking around the Lucene test suite I came across this handy method than resembled a lot to what I was writing, so I use it instead (no harm no fall).

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

So using this method our test code is basically a series of calls to `assertTermEquals` passing the right arguments, for our initial test string assuming that only the `A` token carries a payload, our expected `TokenStream` should be `A D B C`, meaning that `D` is a synonym of `A`. For testing this logic we could use a test method like:

```java
@Test
public void testSingleSynonym() throws Exception {
  String test = "A B C";

  PayloadSynonymTokenFilter filter = new PayloadSynonymTokenFilter(new WordTokenFilter(whitespaceMockTokenizer(test)),
      false, false, "_");

  CharTermAttribute termAtt = filter.getAttribute(CharTermAttribute.class);
  PayloadAttribute payAtt = filter.getAttribute(PayloadAttribute.class);

  filter.reset();

  assertTermEquals("A", filter, termAtt, payAtt, "D".getBytes(StandardCharsets.UTF_8));
  assertTermEquals("D", filter, termAtt, payAtt, "D".getBytes(StandardCharsets.UTF_8));
  assertTermEquals("B", filter, termAtt, payAtt, null);
  assertTermEquals("C", filter, termAtt, payAtt, null);
  assertFalse(filter.incrementToken());

  filter.end();
  filter.close();
}
```

For the `A` and `D` tokens we're also checking that the payload is still there (since we haven't removed it yet), but for `B` and `C` there should be no payload at all, so we pass a `null` parameter to validate this assumption.

Its important to check that the filter returns `false` when it reaches the end of the `TokenStream`.

Of course there is one thing missing from our test, if we go back to the couple of figures that we explained in the start of the post (yes, those figures about the `TokenStream` being a graph and stuff) we should notice that both the original token and the *synonym token* should have the same **positional information**: both terms should be in the same position. The real meaning of this is that when we add the new token extracted from the payload into the `TokenStream` we should set the position increment to `0`, which Lucene will recognize and put the token in the same position, to check this we need to use the `PositionIncrementAttribute` class:

```java
PositionIncrementAttribute posIncAtt = filter.getAttribute(PositionIncrementAttribute.class);

assertEquals(0, posIncAtt.getPositionIncrement());
```

In the rest of the `TokenStream` the position increment should be `1` (if we are not doing anything special), so we could also check this if we wanted to. I think a bit more of explanation could be helpful, since we are working with a `TokenStream`, Lucene uses attributes to store information about a single token. Lucene doesn't actually works with the position of the term in the stream, but rather it handles the *increment* of each token; then at the end Lucene uses this increment information to figure out the actual position, which is what we can see in the analysis page of the Solr Admin UI and used for phrase match, span queries, etc.

## Using in Solr

The entire code of this example is available in this [Github repo](http://github.com) you can build it using maven and then enable it in your Solr/Fusion installation as a normal filter:

```xml
<fieldtype name="payloads" stored="false" indexed="true" class="solr.TextField" >
 <analyzer>
   <tokenizer class="solr.WhitespaceTokenizerFactory"/>
   <filter class="solr.DelimitedPayloadTokenFilterFactory" delimiter="|" encoder="identity"/>
   <filter class="solr.custom.PayloadSynonymTokenFilterFactory"/>
 </analyzer>
</fieldtype>
```

Once we have our `fieldtype` defined we can use the very helpful Analysis page of the Solr Admin UI to check if things are working as expected. If we use the test string: `Bill|Clinton talked about the bill` in the Field value (index) input and select our payload `fieldtype` we can see an output similar to what is shown in the figure. A quick inspection reveals that the tokens `Bill` and `Clinton` share a lot of the same attributes, and the `Clinton` token has a type of `SYNONYM`.

## Advantages to this approach?

One question you may been doing yourself if what advantages provides this approach? As said before this doesn't solve the already existing problems of the `SynonymFilter` of Lucene/Solr. This approach *decentralize* the managing of the synonyms. Usually your synonyms live in a big text file on the filesystem of your Solr server, and adding new synonyms usually means editing that file and adding a new rule in a new line. In recent versions of Solr the `ManagedSynonymFilterFactory` class provides the possibility of managing the synonym list, using HTTP calls into the Solr server which is great, but if you have a cloud-like environment with different teams indexing and searching data in your cluster, probably you don't want them messing with each others synonyms. If you're dealing with single term synonyms this filter put the power of adding/removing the synonyms at the tips of your teams fingers, so with a basic document update you can add a new synonyms or delete existing ones which makes it great to use in [cloud-like](http://traygrainger.com) environments, or when you're dealing with a lot of dynamic fields and not the same synonyms apply to all of your data, essentially this is a way of making your synonyms contextualized to the exact desired token, or to provide some sort of "semantics" into it and not just blindly matching tokens. 

To wrap things up this has been a fun exercise and perhaps an atypical use of Lucene/Solr payloads, if its useful to you then use it if not I hope you've enjoyed the reading, I've enjoyed the journey!