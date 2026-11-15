# Signal

A standalone Hugo theme for an observability and Site Reliability Engineering journal. Dark graphite surfaces, mint accents, monospace metadata, and an abstract observability constellation. No remote fonts, JavaScript dependencies, analytics, or CSS build step.

## Preview

The site's `config.toml` activates `theme = "signal"`.

```sh
hugo server --disableFastRender
```

Open the local URL printed by Hugo. To preview the previous theme without changing configuration:

```sh
hugo server --theme jorgelbg
```

Production build:

```sh
hugo --minify
```

## Included

- Homepage with latest posts, topic counts, author panel, and optional RSS link.
- Paginated post archives, taxonomy collections, and topic index.
- Article pages with reading time, syntax highlighting, table of contents, and adjacent posts.
- About/projects page, Dashflare project page, and custom 404.
- Local SVG favicon, Open Graph metadata, canonical URLs, and RSS discovery.
- Responsive layouts, keyboard focus indicators, skip link, reduced-motion support.
- A privacy-friendly `x` shortcode that links to a referenced social post instead of loading a third-party widget. This also supports content using that shortcode on older Hugo versions.

The hero illustration is an abstract constellation of service nodes, trace paths, log events, and metric waves—not a product dashboard or live monitoring data. CSS-only animations send trace fragments between nodes, ripple outward from the hub, and sweep along the metric wave. Hover or keyboard-focus the illustration to pause it. `prefers-reduced-motion` disables all animation while preserving the static composition.

## Configuration

Uses existing `params.name`, `params.bio`, `params.description`, `params.aboutAuthor`, `params.enableRSS`, `params.customCSS`, and `params.customJS`. Social links use `params.social`, since current Hugo versions removed `Site.Social`:

```toml
[params.social]
  github = "https://github.com/jorgelbg"
  mastodon = "https://mastodon.social/@jorgelbg"
```

The existing top-level `[social]` configuration remains in place for the older themes. The Signal about page uses the existing profile parameters and `/images/avatar@2x.png`; edit `layouts/about/list.html` to change the selected projects. The site's legacy placeholder About content is suppressed, while replacement Markdown content will render normally.

The Dashflare page links to the project rather than loading the site's old waiting-list iframe.

## Files and overrides

- `static/signal/style.css`: design tokens, components, responsive rules, and Chroma colors.
- `layouts/partials/signal/`: namespaced partials that avoid the root site's legacy `post-list.html` override.
- `layouts/_default/`: base, article, list, and taxonomy templates.

Existing root shortcodes continue to take precedence. Existing themes are not inherited from or modified.

## Compatibility and checks

The theme templates support Hugo 0.80+, but this repository's current root `layouts/shortcodes/picture.html` uses `hugo.IsServer`, which requires a newer Hugo than the 0.80.0 pinned in the existing deployment workflow. Use a current Hugo release to build this checkout unchanged. That pre-existing shortcode and the deployment workflow have been left untouched.

Validated with Hugo 0.169.0. Theme templates also built with Hugo 0.80.0 using a temporary, external copy of the root picture shortcode with its older `.Site.IsServer` equivalent. Browser checks cover home, archive, tags, tag collection, About, Dashflare, 404, and an article at 1440px, 390px, and 320px widths, with no horizontal page overflow or JavaScript errors.
