*! version 1.5.4  09nov2026  Eric A. Booth
*! - the abbreviations c() for calc(), o(raw) for output(raw) and l() for
*!   label() work; they were accepted and silently dropped.
*! - calc() code wrapped in compound quotes (needed when the JavaScript holds a
*!   double quote) reaches the page without the delimiters, which used to be a
*!   JS syntax error that disabled the whole dashboard.  Options are found by a
*!   quote-aware scan, so calc( or label( inside the text no longer misroutes.
*! - title(), subtitle(), label(), prefix() and suffix() may contain double
*!   quotes (they stopped with r(198) or "unmatched quote").
*! - min() and max() are written only when given; the undocumented -1000/1000
*!   defaults capped larger values.
*! - an unknown input() or output() type is an error instead of a no-op.
*! - build export() expands a leading ~ and treats a leading backslash (also
*!   a \\server UNC path) as absolute.
*! version 1.5.3  09nov2026  Eric A. Booth
*! - escape line breaks (LF, CR, U+2028, U+2029) and "<" in string values,
*!   variable labels and value labels.  A free-text value with a line break,
*!   or one holding </script>, broke the whole <script> block, so every table
*!   on the page rendered empty while -build- reported success.  All escaping
*!   now goes through one Mata helper, _statashiny_jsesc().
*! version 1.5.2  02aug2026  Eric A. Booth
*! - also escape the double quote.  A value or label containing one, e.g. a
*!   6" pipe or a label like the "quoted" column, aborted -build- with r(198)
*!   and left a truncated .html on disk.  It is emitted as the JS escape
*!   backslash-u-0022, so no quote character survives into the Stata string
*!   that -file write- has to parse.
*! version 1.5.1  02aug2026  Eric A. Booth
*! - escape ' and \ in string values, variable labels and value labels before
*!   they reach the generated JavaScript.  A value like O'Brien, or a label like
*!   "Client's score", used to close the JS string early: the whole data array
*!   then failed to parse and the table rendered empty.
*! - build reports how many controls and panels it wrote, so a dashboard built
*!   without -replace- no longer silently inherits the previous one's panels.
*! - build explains itself when a table asks for variables that are not in
*!   memory, instead of stopping on a bare "variable ... not found".
*! version 1.5.0  26may2026  Eric A. Booth
*! - output(table) now emits value-label text for labeled numeric variables
*!   (e.g. "Foreign" instead of 1); falls back to the number when unlabeled.
program define statashiny
    version 16

    * 1. Backward Compatibility Check (first word is a legacy subcommand)
    mata: st_local("first", ustrregexm(st_local("0"), "^[ ]*([A-Za-z_]+)") ? ustrregexs(1) : "")
    if inlist("`first'", "init", "input_num", "input_check", "output_val", "output_table", "output_raw", "data_from_memory", "calc", "build") {
        gettoken subcmd 0 : 0, parse(" ,")
        _statashiny_`subcmd' `macval(0)'
        exit
    }

    * 2. Raw HTML / Calc Check (bypass -syntax- for complex strings).
    *    The scan runs in Mata, outside quoted text, and knows the documented
    *    abbreviations: o(raw) for output(raw), c() for calc(), l() for label().
    mata: st_local("israw",  strofreal(_statashiny_hasraw(st_local("0"))))
    if `israw' {
        _statashiny_handle_raw `macval(0)'
        exit
    }
    mata: st_local("iscalc", strofreal(_statashiny_findopt(st_local("0"), ("calc","cal","ca","c"), 0) > 0))
    if `iscalc' {
        _statashiny_handle_calc `macval(0)'
        exit
    }

    * 3. Consolidated Syntax
    syntax [anything(name=id)] [, ///
        Input(string) Output(string) Calc(string) Build ///
        Title(string) Subtitle(string) Replace Open ///
        Label(string) Val(string) Min(string) Max(string) Step(real 1) ///
        Vars(varlist) Checked Toggles ///
        Prefix(string) Suffix(string) ///
        EXPort(string) ]

    * Initialization
    if `"`macval(title)'"' != "" | "`replace'" != "" {
        _statashiny_init, title(`"`macval(title)'"') subtitle(`"`macval(subtitle)'"') `replace'
    }

    * Inputs
    if "`input'" != "" {
        if inlist("`input'", "num", "number") {
            local mm ""
            if `"`min'"' != "" local mm `"`mm' min(`min')"'
            if `"`max'"' != "" local mm `"`mm' max(`max')"'
            _statashiny_input_num, var("`id'") label(`"`macval(label)'"') val(`"`macval(val)'"') `mm' step(`step')
        }
        else if inlist("`input'", "check", "checkbox") {
            _statashiny_input_check, var("`id'") label(`"`macval(label)'"') `checked'
        }
        else {
            di as error `"statashiny: input(`input') is not a known type; use input(num) or input(check)"'
            exit 198
        }
    }

    * Outputs
    if "`output'" != "" {
        if inlist("`output'", "val", "value") {
            _statashiny_output_val, id("`id'") label(`"`macval(label)'"') prefix(`"`macval(prefix)'"') suffix(`"`macval(suffix)'"')
        }
        else if "`output'" == "table" {
            _statashiny_output_table, id("`id'") label(`"`macval(label)'"')
            _statashiny_data_from_memory, id("`id'") vars(`vars')
            if "`toggles'" != "" {
                local i = 0
                foreach v of varlist `vars' {
                    local lab : var label `v'
                    if `"`macval(lab)'"' == "" local lab "`v'"
                    _statashiny_input_check, var("toggle_`id'_`i'") label(`"Show `macval(lab)'"') checked
                    _statashiny_calc "if (window.table_`id') table_`id'.column(`i').visible(document.getElementById('toggle_`id'_`i'').checked);"
                    local ++i
                }
            }
        }
        else {
            di as error `"statashiny: output(`output') is not a known type; use output(val), output(table) or output(raw)"'
            exit 198
        }
    }

    * Build
    if "`build'" != "" {
        _statashiny_build, `open' export(`"`export'"')
    }
    
    * Help fallback
    if `"`id'`input'`output'`build'`replace'"' == "" & `"`macval(title)'"' == "" {
        help statashiny
    }
end

* output(raw): the HTML is the argument of label() (or l()), taken verbatim
program define _statashiny_handle_raw
    mata: st_local("found", strofreal(_statashiny_findopt(st_local("0"), ("label","labe","lab","la","l"), 0) > 0))
    if !`found' {
        di as error "statashiny: output(raw) needs the HTML in label(), e.g. label(" _char(34) "<div>...</div>" _char(34) ")"
        exit 198
    }
    mata: st_global("S_outputs", st_global("S_outputs") + " " + _statashiny_optval(st_local("0"), ("label","labe","lab","la","l")))
end

* calc(): the JavaScript is the argument of calc() (or c()), taken verbatim.
* Compound quotes `"..."' are stripped here, so code holding a double quote
* reaches the page without the delimiters.
program define _statashiny_handle_calc
    mata: st_global("S_calc_js", st_global("S_calc_js") + " " + _statashiny_optval(st_local("0"), ("calc","cal","ca","c")) + " ")
end

program define _statashiny_init
    syntax [, Title(string) Subtitle(string) Replace]
    if `"`macval(title)'"' == "" local title "StataShiny Dashboard"
    global S_title `"`macval(title)'"'
    global S_subtitle `"`macval(subtitle)'"'
    global S_inputs ""
    global S_outputs ""
    global S_calc_js ""
    global S_table_list ""
    di as txt `"StataShiny initialized: `macval(title)'"'
end

program define _statashiny_input_num
    syntax, Var(string) Label(string) [Val(string) Min(string) Max(string) Step(real 1)]
    if `"`val'"' == "" local val 0
    * min() and max() are written only when given (they used to default to
    * -1000 and 1000, which capped any larger value without saying so).
    local lim ""
    if `"`min'"' != "" {
        capture confirm number `min'
        if _rc {
            di as error `"statashiny: min(`min') is not a number"'
            exit 198
        }
        local lim `"`lim' min="`min'""'
    }
    if `"`max'"' != "" {
        capture confirm number `max'
        if _rc {
            di as error `"statashiny: max(`max') is not a number"'
            exit 198
        }
        local lim `"`lim' max="`max'""'
    }
    local html `"<div class="mb-3">"'
    local html `"`macval(html)'<label class="form-label small uppercase fw-bold">`macval(label)'</label>"'
    local html `"`macval(html)'<input type="number" class="form-control form-control-sm" id="`var'" value="`macval(val)'"`lim' step="`step'" oninput="updateDashboard()">"'
    local html `"`macval(html)'</div>"'
    mata: st_global("S_inputs", st_global("S_inputs") + " " + st_local("html"))
end

program define _statashiny_input_check
    syntax, Var(string) Label(string) [Checked]
    local chk = cond("`checked'"!="", "checked", "")
    local html `"<div class="form-check mb-2">"'
    local html `"`macval(html)'<input class="form-check-input" type="checkbox" id="`var'" `chk' onchange="updateDashboard()">"'
    local html `"`macval(html)'<label class="form-check-label small">`macval(label)'</label>"'
    local html `"`macval(html)'</div>"'
    mata: st_global("S_inputs", st_global("S_inputs") + " " + st_local("html"))
end

program define _statashiny_output_val
    syntax, Id(string) Label(string) [Prefix(string) Suffix(string)]
    local html `"<div class="card mb-3 statashiny-component"><div class="card-body">"'
    local html `"`macval(html)'<h6 class="card-subtitle mb-2 text-muted uppercase small fw-bold">`macval(label)'</h6>"'
    local html `"`macval(html)'<div class="card-text h4 text-primary">`macval(prefix)'<span id="`id'">---</span>`macval(suffix)'</div>"'
    local html `"`macval(html)'</div></div>"'
    mata: st_global("S_outputs", st_global("S_outputs") + " " + st_local("html"))
end

program define _statashiny_output_raw
    mata: st_global("S_outputs", st_global("S_outputs") + " " + st_local("0"))
end

program define _statashiny_output_table
    syntax, Id(string) Label(string)
    local html `"<div class="card mb-3 statashiny-component"><div class="card-body">"'
    local html `"`macval(html)'<h6 class="card-subtitle mb-3 text-muted uppercase small fw-bold">`macval(label)'</h6>"'
    local html `"`macval(html)'<div class="table-responsive"><table id="`id'" class="table table-hover table-sm stripe row-border" style="width:100%"></table></div>"'
    local html `"`macval(html)'</div></div>"'
    mata: st_global("S_outputs", st_global("S_outputs") + " " + st_local("html"))
end

program define _statashiny_data_from_memory
    syntax, Id(string) [Vars(varlist)]
    global S_table_list "$S_table_list `id':`vars'|"
end

program define _statashiny_calc
    mata: st_global("S_calc_js", st_global("S_calc_js") + " " + _statashiny_unquote(st_local("0")) + " ")
end

program define _statashiny_build
    syntax [, Open EXPort(string)]

    * Resolve output path:
    *   - No export() → "statashiny_dashboard.html" in current working directory
    *   - export("name.html")          → CWD/name.html (relative)
    *   - export("/abs/path/file.html") → absolute path used verbatim
    *   - export("rel/dir/file.html")   → CWD/rel/dir/file.html
    if `"`export'"' == "" {
        local path `"`c(pwd)'/statashiny_dashboard.html"'
    }
    else {
        local path `"`export'"'
        * Expand a leading ~ (Stata's file commands accept it, but the
        * relative test below used to turn it into <cwd>/~/...).
        if `"`path'"' == "~" | substr(`"`path'"', 1, 2) == "~/" | substr(`"`path'"', 1, 2) == "~" + char(92) {
            local home : env HOME
            if "`c(os)'" == "Windows" {
                local up : env USERPROFILE
                if `"`up'"' != "" local home `"`up'"'
                if `"`home'"' == "" {
                    local hd : env HOMEDRIVE
                    local hp : env HOMEPATH
                    local home `"`hd'`hp'"'
                }
            }
            if `"`home'"' == "" {
                di as error "statashiny build: cannot expand ~ (HOME is not set)"
                exit 198
            }
            local path `"`home'`=substr(`"`path'"', 2, .)'"'
        }
        * Treat as relative unless it starts with "/" (Unix), "\" (Windows,
        * including \\server UNC paths) or a drive letter.
        if substr(`"`path'"', 1, 1) != "/" & substr(`"`path'"', 1, 1) != char(92) & substr(`"`path'"', 2, 1) != ":" {
            local path `"`c(pwd)'/`path'"'
        }
    }

    tempname fh
    cap file open `fh' using `"`path'"', write replace
    if _rc {
        di as error `"statashiny build: cannot write to "`path'""'
        di as error `"  (check that the directory exists and is writable)"'
        exit 603
    }
    local title : copy global S_title
    local subtitle : copy global S_subtitle
    local inputs : copy global S_inputs
    local outputs : copy global S_outputs
    local scripts : copy global S_calc_js

    * A dashboard is assembled in global macros, and those are only cleared when
    * -replace- (or title()) runs an init.  Building a second dashboard without
    * -replace- therefore silently carries the first one's panels along with it.
    * Rather than add an option, count what is about to be written and say so:
    * "3 panels" when the user expected 1 is the clue that -replace- was missed.
    * NB: -: subinstr local- returns the SUBSTITUTED STRING; the tally goes to
    * the macro named in count().  They must be different macros.
    local n_ctrl  = 0
    local n_panel = 0
    if `"`macval(inputs)'"' != "" {
        local _junk : subinstr local inputs "updateDashboard()" "", all count(local n_ctrl)
    }
    if `"`macval(outputs)'"' != "" {
        local _junk : subinstr local outputs "statashiny-component" "", all count(local n_panel)
    }
    if `"`macval(title)'"' == "" {
        local title "StataShiny Dashboard"
        di as txt "statashiny build: no title() was set; using the default."
    }

    file write `fh' `"<!DOCTYPE html><html><head><meta charset='utf-8'><title>`macval(title)'</title>"' _n
    file write `fh' "<link href='https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css' rel='stylesheet'>" _n
    file write `fh' "<link rel='stylesheet' type='text/css' href='https://cdn.datatables.net/1.13.4/css/dataTables.bootstrap5.min.css'/>" _n
    file write `fh' "<script src='https://code.jquery.com/jquery-3.6.0.min.js'></script>" _n
    file write `fh' "<script src='https://cdn.jsdelivr.net/npm/chart.js'></script>" _n
    file write `fh' "<script type='text/javascript' src='https://cdn.datatables.net/1.13.4/js/jquery.dataTables.min.js'></script>" _n
    file write `fh' "<script type='text/javascript' src='https://cdn.datatables.net/1.13.4/js/dataTables.bootstrap5.min.js'></script>" _n
    file write `fh' "<style>body{padding:30px;background:#f8f9fa;font-family:sans-serif;}.statashiny-component{border:none;border-radius:12px;box-shadow:0 4px 20px rgba(0,0,0,0.05);background:white;margin-bottom:1.5rem;}.sidebar{padding:25px;background:#fff;}.form-label{font-weight:700;font-size:0.75rem;color:#666;}.uppercase{text-transform:uppercase;letter-spacing:1px;}</style></head><body>" _n

    file write `fh' `"<div class='container-fluid'><div class='row mb-2'><div class='col-12'><h2 class='fw-bold text-dark'>`macval(title)'</h2>"' _n
    if `"`macval(subtitle)'"' != "" {
        file write `fh' `"<h5 class='text-muted'>`macval(subtitle)'</h5>"' _n
    }
    file write `fh' "<hr></div></div><div class='row'>" _n
    if trim(`"`macval(inputs)'"') != "" {
        file write `fh' `"<div class='col-md-3'><div class='statashiny-component sidebar shadow-sm'><h6>Parameters</h6><hr> `macval(inputs)' </div></div>"' _n
        file write `fh' `"<div class='col-md-9'> `macval(outputs)' </div></div></div>"' _n
    }
    else {
        file write `fh' `"<div class='col-12'> `macval(outputs)' </div></div></div>"' _n
    }
    file write `fh' "<script>" _n
    local tlist "$S_table_list"
    while "`tlist'" != "" {
        gettoken entry tlist : tlist, parse("|")
        if "`entry'" == "|" continue
        local id = substr("`entry'", 1, strpos("`entry'", ":")-1)
        local vars = substr("`entry'", strpos("`entry'", ":")+1, .)
        if "`vars'" == "" local vars _all
        * Every table is written from the data in memory AT BUILD TIME, not from
        * whatever was loaded when output(table) was called.  Registering two
        * tables from two different datasets therefore fails here with a bare
        * "variable ... not found", which tells the user nothing about why.
        capture confirm variable `vars'
        if _rc {
            file close `fh'
            di as error "statashiny build: table `id' asks for variables that are not in memory."
            di as error "  Every table is written from the data loaded when -build- runs, so all"
            di as error "  tables in one dashboard must come from the same dataset. Load the data"
            di as error "  first, then register the tables, then build."
            exit 111
        }
        file write `fh' "var cols_`id' = ["
        foreach v of varlist `vars' {
            local lab : var label `v'
            if "`lab'" == "" local lab "`v'"
            * A label such as "Client's score" used to close the JS string
            * early, so the whole <script> block failed to parse and the table
            * rendered empty.  Escape it with the same helper as the values
            * (_statashiny_jsesc, at the end of this file).
            mata: st_local("lab", _statashiny_jsesc(st_local("lab")))
            file write `fh' `"{ title: '`macval(lab)'' },"'
        }
        file write `fh' "]; var data_`id' = ["
        forvalues i = 1/`=_N' {
            file write `fh' "["
            foreach v of varlist `vars' {
                capture confirm numeric variable `v'
                if _rc {
                    * String variable, quoted for JS.  A value like O'Brien
                    * used to close the quote early and break the entire data
                    * array -- the table then rendered empty, with nothing but a
                    * console error to show for it.
                    local val = `v'[`i']
                    mata: st_local("val", _statashiny_jsesc(st_local("val")))
                    file write `fh' `"'`macval(val)'', "'
                }
                else if missing(`v'[`i']) {
                    * Stata's . (missing) is not valid JS — emit null instead.
                    * Without this, the whole data array fails to parse and DataTables
                    * silently shows an empty table.
                    file write `fh' "null, "
                }
                else {
                    local val = `v'[`i']
                    * Labeled numeric: emit the value-label text (as a JS string)
                    * instead of the bare numeric code, e.g. "Foreign" not 1.
                    * Falls back to the number when the value has no label entry.
                    local vlname : value label `v'
                    if "`vlname'" != "" & `val' == int(`val') {
                        local lbl : label `vlname' `val'
                        mata: st_local("lbl", _statashiny_jsesc(st_local("lbl")))
                        file write `fh' `"'`macval(lbl)'', "'
                    }
                    else {
                        file write `fh' "`val', "
                    }
                }
            }
            file write `fh' "],"
        }
        file write `fh' "]; window.table_`id' = null;" _n
        file write `fh' "$(document).ready(function(){ window.table_`id' = $('#`id'').DataTable({data:data_`id', columns:cols_`id', pageLength:10}); });" _n
    }
    file write `fh' "function updateDashboard(){ try{ " _n
    file write `fh' `"`macval(scripts)'"' _n
    file write `fh' " }catch(e){console.warn('Dashboard update failed:', e);} }" _n
    file write `fh' "$(document).ready(function(){ setTimeout(updateDashboard, 700); });" _n
    file write `fh' "</script></body></html>" _n
    file close `fh'
    di as txt "StataShiny built: `n_ctrl' control(s), `n_panel' panel(s)." ///
       _n as txt "  (start a new dashboard with -statashiny, title(...) replace-;" ///
       _n as txt "   without it, panels accumulate from the previous one.)" ///
       _n as smcl `"File: {browse `"`path'"'}"'
    if "`open'" != "" {
        cap file close _ss_fh
        tempfile _ss_sh
        if ("`c(os)'" == "MacOSX") | regexm("`c(machine_type)'", "Mac") {     // Apple-Silicon Stata reports c(os)=="Unix"
            file open _ss_fh using "`_ss_sh'", write text replace
            file write _ss_fh "/usr/bin/open " _char(34) `"`path'"' _char(34) _n
            file close _ss_fh
            shell sh "`_ss_sh'"
        }
        else if "`c(os)'" == "Windows" {
            file open _ss_fh using "`_ss_sh'.cmd", write text replace
            file write _ss_fh "start " _char(34) _char(34) " " _char(34) `"`path'"' _char(34) _n
            file close _ss_fh
            shell "`_ss_sh'.cmd"
        }
        else {
            file open _ss_fh using "`_ss_sh'", write text replace
            file write _ss_fh "xdg-open " _char(34) `"`path'"' _char(34) _n
            file close _ss_fh
            shell sh "`_ss_sh'"
        }
    }
end

* ---------------------------------------------------------------------------
* _statashiny_jsesc: make text safe inside a single-quoted JavaScript string
* that sits in an inline <script> block.  Used for string values, variable
* labels and value labels.  A raw line break (LF, CR, U+2028, U+2029) ends a
* JS string literal, and a "</script>" in the text ends the whole <script>
* element; either one left every table on the page empty while -build-
* reported success.  Every "<" is written as the escape backslash-u-003c, which
* also covers "</script>" and "<!--"; the browser decodes it back to "<", so
* the table shows the same text.  The double quote becomes backslash-u-0022 so
* no quote character reaches the Stata string that -file write- parses.
* Backslash goes first so the escapes added after it are not doubled.
* ---------------------------------------------------------------------------
mata:
string scalar _statashiny_jsesc(string scalar s)
{
    string scalar bs
    bs = char(92)
    s = subinstr(s, bs, bs + bs)
    s = subinstr(s, char(34), bs + "u0022")
    s = subinstr(s, "'", bs + "'")
    s = subinstr(s, char(13), bs + "r")
    s = subinstr(s, char(10), bs + "n")
    s = subinstr(s, uchar(8232), bs + "u2028")
    s = subinstr(s, uchar(8233), bs + "u2029")
    s = subinstr(s, "<", bs + "u003c")
    return(s)
}

// ---------------------------------------------------------------------------
// Option scanning for the calc()/output(raw) bypass.  User text often holds
// quotes, parentheses and the very words "calc(" or "label(", so the scan
// skips anything inside "..." or compound quotes and matches option names
// only at the start of the line or after a space or comma.
// ---------------------------------------------------------------------------

// position of the first top-level  name(  for any name in nm (longest
// names first); 0 when absent.  The name's length goes to len.
real scalar _statashiny_findopt(string scalar s, string rowvector nm, real scalar len)
{
    real scalar i, j, n, depth, inq, L
    string scalar c, c2, prev
    n = strlen(s)
    depth = 0
    inq = 0
    for (i = 1; i <= n; i++) {
        c  = substr(s, i, 1)
        c2 = substr(s, i, 2)
        if (!inq & c2 == char(96) + char(34)) {
            depth++
            i++
            continue
        }
        if (depth > 0 & c2 == char(34) + char(39)) {
            depth--
            i++
            continue
        }
        if (depth > 0) continue
        if (c == char(34)) {
            inq = !inq
            continue
        }
        if (inq) continue
        prev = (i == 1 ? " " : substr(s, i - 1, 1))
        if (prev != " " & prev != ",") continue
        for (j = 1; j <= cols(nm); j++) {
            L = strlen(nm[j])
            if (strlower(substr(s, i, L + 1)) == nm[j] + "(") {
                len = L
                return(i)
            }
        }
    }
    len = 0
    return(0)
}

// the text between the "(" at position open and its matching ")", with
// quoted text skipped while matching
string scalar _statashiny_argat(string scalar s, real scalar open)
{
    real scalar i, n, depth, inq, par
    string scalar c, c2
    n = strlen(s)
    depth = 0
    inq = 0
    par = 0
    for (i = open; i <= n; i++) {
        c  = substr(s, i, 1)
        c2 = substr(s, i, 2)
        if (!inq & c2 == char(96) + char(34)) {
            depth++
            i++
            continue
        }
        if (depth > 0 & c2 == char(34) + char(39)) {
            depth--
            i++
            continue
        }
        if (depth > 0) continue
        if (c == char(34)) {
            inq = !inq
            continue
        }
        if (inq) continue
        if (c == "(") par++
        if (c == ")") {
            par--
            if (par == 0) return(substr(s, open + 1, i - open - 1))
        }
    }
    // unbalanced: everything after "(" up to the last ")"
    return(substr(s, open + 1, max((0, strrpos(s, ")") - open - 1))))
}

// strip one layer of compound quotes `"..."' or plain quotes "..."
string scalar _statashiny_unquote(string scalar s)
{
    real scalar n
    s = strtrim(s)
    n = strlen(s)
    if (n >= 4 & substr(s, 1, 2) == char(96) + char(34) & substr(s, n - 1, 2) == char(34) + char(39)) {
        return(substr(s, 3, n - 4))
    }
    if (n >= 2 & substr(s, 1, 1) == char(34) & substr(s, n, 1) == char(34)) {
        return(substr(s, 2, n - 2))
    }
    return(s)
}

// the unquoted argument of the first top-level option named in nm
string scalar _statashiny_optval(string scalar s, string rowvector nm)
{
    real scalar p, L
    L = 0
    p = _statashiny_findopt(s, nm, L)
    if (p == 0) return("")
    return(_statashiny_unquote(_statashiny_argat(s, p + L)))
}

// is there a top-level output(raw) (or o(raw), out( raw ), ...)?
real scalar _statashiny_hasraw(string scalar s)
{
    real scalar p, L
    L = 0
    p = _statashiny_findopt(s, ("output","outpu","outp","out","ou","o"), L)
    if (p == 0) return(0)
    return(strlower(strtrim(_statashiny_argat(s, p + L))) == "raw")
}
end
