# statashiny

**Build interactive HTML dashboards, calculators, and searchable data tables straight from Stata — no web development required.**

`statashiny` turns Stata variables and coefficients into a single self-contained `.html` file with live, interactive widgets:

- **Searchable, sortable data tables** (powered by DataTables)
- **Live charts** that recompute in the browser as you move sliders (powered by Chart.js)
- **Value cards, numeric inputs, checkboxes** laid out with Bootstrap 5

You write Stata; `statashiny` writes the HTML, CSS, and JavaScript. The output is one portable file you can email, drop on a shared drive, host on GitHub Pages, or embed inside a [`webdoc2`](https://github.com/ericabooth/webdoc2-stata-public) report with an `<iframe>`.

> 🔗 **See it live:** [**ericabooth.github.io/statashiny_Example_Site**](https://ericabooth.github.io/statashiny_Example_Site/) — a working example site built entirely with `statashiny` (+ `webdoc2`) and hosted free on GitHub Pages.

---

## Why you'd reach for this

A static regression table shows one number. A `statashiny` dashboard lets your audience *explore*:

- **Scenarios** — "What happens to predicted price if MPG rises 10%?"
- **Interactions** — "How does origin change the weight–price relationship?"
- **Uncertainty** — watch confidence bands widen as simulated N shrinks.

And because the output is plain HTML with CDN-loaded libraries, **there's nothing to install for the viewer** — it opens in any browser, offline or online.

---

## Install

`statashiny` is **standalone** — for basic dashboards it has no Stata dependencies (the interactive libraries load from public CDNs in the browser at view time).

```stata
net install statashiny, ///
    from("https://raw.githubusercontent.com/ericabooth/statashiny-stata-public/main/") ///
    replace
```

Confirm it's ready:

```stata
which statashiny
help  statashiny
```

Requires Stata 16+. To also build full report *pages* around your dashboards (as in the combined example below), install [`webdoc2`](https://github.com/ericabooth/webdoc2-stata-public) too — but that's optional.

Manual install: drop `statashiny.ado` and `statashiny.sthlp` anywhere on your Stata `adopath`.

---

## 60-second quickstart (standalone)

A searchable, sortable table from data in memory — three commands:

```stata
sysuse auto, clear
collapse (mean) price mpg weight length (count) n=price, by(foreign)
label var price "Mean Price ($)"

statashiny, title("Auto Summary Table") replace
statashiny autotab, output(table) label("Descriptives by Origin") ///
    vars(foreign price mpg weight length n)
statashiny, build export("dashboard.html") open
```

`open` pops it straight into your browser. That's the whole workflow:

1. `statashiny, title(...) replace` — start a new dashboard
2. add inputs / outputs (`output(table)`, `output(val)`, `input(num)`, `input(check)`, …)
3. `statashiny, build export("file.html") open` — write the HTML and open it

The full example is [examples/standalone_dashboard.do](examples/standalone_dashboard.do).

---

## The MWE: a full report page with two live widgets (statashiny + webdoc2)

[examples/mwe_statashiny.do](examples/mwe_statashiny.do) builds **one HTML report** that contains:

1. a narrative + simple analysis (summary stats and a collapsible regression) via `webdoc2`,
2. an **interactive table** widget, and
3. an **interactive visualization** (a live histogram simulator),

with the two widgets embedded as iframes. Build it with:

```stata
webdoc2 mwe_statashiny.do, open cleanup
```

The shape of the do-file:

```stata
* 1. Build the interactive TABLE widget -> shiny_table.html
sysuse auto, clear
collapse (mean) price mpg weight length (count) n=price, by(foreign)
label var price "Mean Price ($)"
statashiny, title("Auto Summary Table") replace
statashiny autotab, output(table) label("Descriptives by Origin") ///
    vars(foreign price mpg weight length n)
statashiny, build export("shiny_table.html")

* 2. Build the interactive VISUALIZATION widget -> shiny_viz.html
statashiny, title("Live Histogram Simulator") replace
statashiny obs,  input(num) label("Sample Size") val(1000) min(100) step(100)
statashiny bins, input(num) label("Number of Bins") val(20) min(5) max(50)
statashiny chart_container, output(val) label("Simulated Normal Histogram")
statashiny, calc("if (!window.hChart) { ... Chart.js setup ... }")
statashiny, calc("... read inputs, build histogram, hChart.update(); ")
statashiny, build export("shiny_viz.html")

* 3. Build the report page that embeds them both
wdinit mwe_statashiny, replace
wputh1 Analysis
wd
sysuse auto, clear
summarize price mpg weight length
wdclose
wputh1 Interactive Table
wdiframe shiny_table.html, height(480px)
wputh1 Interactive Visualization
wdiframe shiny_viz.html, height(620px)
webdoc close
```

Run it and you get `mwe_statashiny.html` (open this), plus `shiny_table.html` and `shiny_viz.html` beside it.

> ⚠️ **iframe gotcha (read this).** When you open the report by double-clicking it (a `file://` URL), browsers only let an iframe load files **from the same folder**. So always `export()` your widgets with a **plain filename** (no path) — that writes them next to the report — and reference them with a plain filename in `wdiframe`/`<iframe src=...>`. If a panel shows up blank, this is almost always why. (Hosting the folder on a web server, like GitHub Pages, removes the restriction entirely.)

---

## Output types at a glance

| Command | What it makes |
| --- | --- |
| `statashiny, title(...) replace` | Start a new dashboard |
| `statashiny ID, output(table) vars(...)` | Searchable/sortable DataTable from variables in memory |
| `statashiny ID, output(table) vars(...) toggles` | …plus auto checkboxes to show/hide each column |
| `statashiny ID, output(val) label(...) [prefix() suffix()]` | A value "card" that JavaScript fills in |
| `statashiny ID, output(raw) label("<...html...>")` | Drop in arbitrary HTML (e.g. a chart container) |
| `statashiny ID, input(num) val() min() max() step()` | A numeric input the user can change |
| `statashiny ID, input(check) [checked]` | A checkbox |
| `statashiny, calc("...JS...")` | Add JavaScript to the live `updateDashboard()` function |
| `statashiny, build export("file.html") [open]` | Write the HTML (and optionally open it) |

Full reference with five worked examples (CI explorer, policy simulator, histogram, difference-in-differences): `help statashiny`.

---

## Publishing to GitHub Pages (like the demo site)

The demo at [ericabooth.github.io/statashiny_Example_Site](https://ericabooth.github.io/statashiny_Example_Site/) is just `statashiny` output committed to a repo with Pages turned on:

1. Put your built `.html` files (report + widgets, all in one folder) in a GitHub repo.
2. Repo **Settings → Pages → Source: Deploy from a branch**, pick `main` and `/ (root)`.
3. Your site goes live at `https://<user>.github.io/<repo>/<file>.html`.

Because Pages serves over `https://`, the `file://` iframe restriction disappears — widgets in subfolders, external links, and absolute paths all work.

---

## Author

Eric A. Booth · Texas 2036 · [eric.a.booth@gmail.com](mailto:eric.a.booth@gmail.com) · [@ericabooth](https://github.com/ericabooth)

Issues and PRs welcome at [github.com/ericabooth/statashiny-stata-public](https://github.com/ericabooth/statashiny-stata-public).
