---
title: "Introducing pinentry-touchid"
date: 2021-08-03T14:00:00+02:00
description: >
  Introducing `pinentry-touchid` a small pinentry program that verifies the identity of the user via
  the Touch ID sensor in supported devices.
tags: ["pinentry", "touchid", "gpg", "mac"]
draft: false
images:
  - images/pinentry-touchid/login.png
---

{{< picture "login" "secure login image" "100%">}}

## Summary

This post introduces [pinentry-touchid][pinentry-touchid], a wrapper of [pinentry-mac][pinentry-mac]
that uses Touch ID for accessing your PIN/password from the Keychain. It will help you avoid typing
your password when interacting with your GPG keys (like when you sign a Git commit).

## See it in action

Here is a short clip on how [pinentry-touchid][pinentry-touchid] works (after configuring the
gpg-agent):

{{< rawhtml >}}

<video width=100% controls autoplay>
    <source src="/images/pinentry-touchid/pinentry-touchid.mp4" type="video/mp4">
    Your browser does not support the video tag.
</video>

{{< /rawhtml >}}

## Installation

It is possible to install [pinentry-touchid][pinentry-touchid] using Homebrew:

```bash
❯ brew tap jorgelbg/tap
❯ brew install pinentry-touchid
```

You can also download the binaries directly from our [releases][releases] page.

## A bit of history

I use GPG to sign my commits. So far, I’ve been using either pinentry-curses or the pinentry-mac for
typing my pin/password, when it is requested.

Since I got a Touch ID capable computer I've been enjoying the sweet life of Touch ID. The
use of Touch ID has spread on the macOS ecosystem and a lot of popular apps like 1Password support Touch
ID. Getting passwords autocompleted with 1Password is a breeze, I have to type 0 passwords, while
still getting a confirmation that it is me requesting the password, via Touch ID.


I also use [`gopass`][gopass] for storing tokens/secrets that I normally need in the shell. The main
reason for this is that it integrates nicely with the shell/terminal, even more than 1Password.
[`gopass`][gopass] makes using secrets in environment variables a breeze.

For instance, my environment is full of commands like this:

```js
❯ export GITHUB_API_TOKEN=$(gopass github/mytoken)
```

Since [`gopass`][gopass] uses a GPG key for encrypting the secrets I type my pin/password quite
often. As I say to my friends, I am a lazy driven developer 😂:

> ... the essence is to identify what is painful and then eliminate the pain.
>
> https://humblesoftwaredev.wordpress.com/2015/04/08/laziness-driven-development/

Typing my password all the time falls into the _painful/repetitive_ category for me. Yes, I could
increase the amount of time that the gpg-agent caches the password but that would be just a patch.
Turns out that this Macbook Pro already has something that would allow me to avoid typing the
password every single time: the Touch ID sensor.

It would be awesome if I could use Touch ID for getting the pin/password of my GPG key.
Unsurprisingly, I’m not the first person to want this. A simple Google search reveals multiple
[users][1] [requesting][2] [this][3]. Sadly, it is not supported yet by [pinentry-mac][pinentry-mac].

[pinentry-mac][pinentry-mac] already supports storing the pin/password in the macOS Keychain, but
accessing the entry does not use Touch ID. I ended up writing a small wrapper that saves the pin in
the macOS Keychain (following the same format as the default [pinentry-mac][pinentry-mac]) but guards
every access with Touch ID. It is backward compatible with [pinentry-mac][pinentry-mac] and calls
[pinentry-mac][pinentry-mac] for requesting a password from the user when there is no entry in the
Keychain for the given GPG key.

This was an interesting project, I learned a bit about [Assuan][assuan], the IPC protocol used by the
gpp-agent to communicate with any pinentry-like program.

## Caveats

The current version does not store the password in the [Secure
Enclave](https://support.apple.com/en-gb/guide/security/sec59b0b31ff/web) of your device. This
allowed us to reuse the same Keychain entry created by [pinentry-mac][pinentry-mac], if present. At
the same time, the entry created by [pinentry-touchid][pinentry-touchid] can be used by
[pinentry-mac][pinentry-mac] keeping compatibility between both programs. Also,
[go-keychain][go-keychain] does not offer support for the secure enclave (yet).

<!--
Looking back, perhaps this program should've been written in Swift, since it integrates better with
the macOS ecosystem, but, excluding a couple of features I ended up finding good libraries for Golang
that allowed me to have an initial prototype in a couple of hours (including research).
-->

## Acknowledgments

Finally, I would like to say thank you to the authors and contributors of [go-assuan][go-assuan],
[go-keychain][go-keychain], [gopass](github.com/gopasspw/pinentry) and [go-touchid][go-touchid].

_Touch ID icon made by [Freepik](https://www.freepik.com) from [Flaticon](https://www.flaticon.com/)._

[pinentry-touchid]: https://github.com/jorgelbg/pinentry-touchid
[pinentry-mac]: https://github.com/GPGTools/pinentry/tree/master/macosx
[gopass]: https://github.com/gopasspw/gopass
[1]: https://gpgtools.tenderapp.com/discussions/feedback/15650-pinentry-mac-use-apple-watch-touchid-to-unlock-gpg-key
[2]: https://superuser.com/questions/1461868/is-it-possible-to-use-macos-keychain-touchid-for-pinentry-program
[3]: https://twitter.com/adamyonk/status/808406995770413056
[go-keychain]: https://github.com/keybase/go-keychain
[go-assuan]: https://github.com/foxcpp/go-assuan
[go-touchid]: https://github.com/lox/go-touchid
[releases]: https://github.com/jorgelbg/pinentry-touchid/releases
[assuan]: https://www.gnupg.org/documentation/manuals/assuan
