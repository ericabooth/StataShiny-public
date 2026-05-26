*--------------------------------------------------------------------*
* mwe_statashiny.do
*
*   A complete minimum working example that combines:
*     1. webdoc2  -- builds the HTML report page (narrative + analysis)
*     2. statashiny -- builds TWO interactive widgets embedded via iframe:
*          (a) a searchable/sortable DATA TABLE
*          (b) an interactive VISUALIZATION (live histogram simulator)
*
*   Build it with:
*       webdoc2 mwe_statashiny.do, open cleanup
*
*   Output (all written to the current working directory, so the
*   iframes resolve correctly when opened via file://):
*       mwe_statashiny.html   <- the report (open this one)
*       shiny_table.html      <- embedded interactive table
*       shiny_viz.html         <- embedded interactive chart
*
*   Requirements: webdoc (SSC), webdoc2, and statashiny all on the adopath.
*
*   House rules that keep webdoc2 happy:
*     - wdinit NAME, replace   uses a BARE name (never quoted)
*     - statashiny / wdiframe lines go OUTSIDE any wd/button block
*     - iframe targets must sit in the SAME folder as the report
*--------------------------------------------------------------------*


*====================================================================*
* STEP 1.  Build the interactive TABLE widget (statashiny)            *
*          Collapse the auto data to one row per origin, then ship    *
*          it to a searchable DataTable.                              *
*====================================================================*
sysuse auto, clear
collapse (mean) price mpg weight length (count) n=price, by(foreign)
label var foreign "Origin"
label var price   "Mean Price ($)"
label var mpg     "Mean MPG"
label var weight  "Mean Weight (lbs)"
label var length  "Mean Length (in)"
label var n       "Number of Cars"

statashiny, title("Auto Summary Table") replace
statashiny autotab, output(table) ///
    label("Automobile Descriptives by Origin") ///
    vars(foreign price mpg weight length n)
statashiny, build export("shiny_table.html")


*====================================================================*
* STEP 2.  Build the interactive VISUALIZATION widget (statashiny)    *
*          A live histogram simulator: move the sliders and the       *
*          Chart.js bar chart redraws in the browser.                 *
*====================================================================*
statashiny, title("Live Histogram Simulator") replace ///
    subtitle("Drag the inputs -- the chart redraws instantly")
statashiny obs,  input(num) label("Sample Size")    val(1000) min(100) step(100)
statashiny bins, input(num) label("Number of Bins") val(20)   min(5)   max(50)
statashiny chart_container, output(val) label("Simulated Normal Histogram")

statashiny, calc("if (!window.hChart) { ")
statashiny, calc("  let ctx = document.getElementById('chart_container'); ")
statashiny, calc("  let cv = document.createElement('canvas'); ctx.appendChild(cv); ")
statashiny, calc("  window.hChart = new Chart(cv, { type: 'bar', data: { labels: [], ")
statashiny, calc("    datasets: [{label: 'Frequency', data: [], backgroundColor: '#0d6efd'}] } }); ")
statashiny, calc("} ")
statashiny, calc("let n = parseInt(document.getElementById('obs').value); ")
statashiny, calc("let b = parseInt(document.getElementById('bins').value); ")
statashiny, calc("let data = []; for(let i=0; i<n; i++) { let s=0; for(let j=0; j<6; j++) s+=Math.random(); data.push(s-3); } ")
statashiny, calc("let counts = new Array(b).fill(0); ")
statashiny, calc("data.forEach(v => { let idx = Math.floor(((v+3)/6)*b); if(idx>=0 && idx<b) counts[idx]++; }); ")
statashiny, calc("window.hChart.data.labels = Array.from({length: b}, (_, i) => (i - b/2).toFixed(1)); ")
statashiny, calc("window.hChart.data.datasets[0].data = counts; window.hChart.update(); ")
statashiny, build export("shiny_viz.html")


*====================================================================*
* STEP 3.  Build the webdoc2 report page that ties it all together    *
*====================================================================*
wdinit mwe_statashiny, replace

* Navbar with in-page anchor links
wdnavbar StataShiny + webdoc2 Demo
wdnavdropdown Sections
    wdnavdropdownitem Overview     , href(#overview)
    wdnavdropdownitem Analysis     , href(#analysis)
    wdnavdropdownitem Table        , href(#interactive-table)
    wdnavdropdownitem Visualization, href(#interactive-visualization)
wdnavdropdownclose
wdnavitem GitHub Pages demo , href(https://ericabooth.github.io/statashiny_Example_Site/)
wdnavbarclose

* ---- Overview ----
wputh1 Overview
wdtoc Contents, depth(2)
wput This page was generated entirely from one Stata do-file. The narrative and static output come from webdoc2; the two interactive widgets below come from statashiny and are embedded with wdiframe.

* ---- Simple analysis (static, logged inline) ----
wputh1 Analysis

wputh2 Summary statistics
wput Basic descriptives for the classic auto dataset:
wd
sysuse auto, clear
summarize price mpg weight length
wdclose

wputh2 Regression (collapsible)
wput Click to reveal the model. Price regressed on fuel economy, weight, and origin:
button
sysuse auto, clear
regress price mpg weight foreign
buttonclose

* ---- Interactive TABLE (statashiny via iframe) ----
wputh1 Interactive Table
wput The table below is fully searchable and sortable -- it is a live statashiny widget, not a static image. Type in the search box or click a column header.
wdiframe shiny_table.html, height(480px)

* ---- Interactive VISUALIZATION (statashiny via iframe) ----
wputh1 Interactive Visualization
wput Move the sliders to change the simulated sample size and bin count. The Chart.js histogram redraws instantly in your browser.
wdiframe shiny_viz.html, height(620px)

webdoc close
