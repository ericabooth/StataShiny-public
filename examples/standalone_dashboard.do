*--------------------------------------------------------------------*
* standalone_dashboard.do
*
*   The simplest possible statashiny use -- NO webdoc2 required.
*   Builds one self-contained .html dashboard with a searchable,
*   sortable data table. Double-click the output to open it.
*
*   Run it line by line, or:   do standalone_dashboard.do
*--------------------------------------------------------------------*

* 1. Prepare some data (one row per origin)
sysuse auto, clear
collapse (mean) price mpg weight length (count) n=price, by(foreign)
label var foreign "Origin"
label var price   "Mean Price ($)"
label var mpg     "Mean MPG"
label var weight  "Mean Weight (lbs)"
label var length  "Mean Length (in)"
label var n       "Number of Cars"

* 2. Build the dashboard
*    - first call sets the title and (replace) starts a fresh file
*    - second call defines a table fed by variables in memory
*    - third call writes the .html and opens it in your browser
statashiny, title("Auto Summary Table") replace
statashiny autotab, output(table) ///
    label("Automobile Descriptives by Origin") ///
    vars(foreign price mpg weight length n)
statashiny, build export("standalone_dashboard.html") open
