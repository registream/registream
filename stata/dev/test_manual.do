*** -------
* start with clean install, no registream dir, nothing

* Adjust to your local sibling-repo root if not the default below.
* (Layout: $REGISTREAM_ORG/{registream, autolabel, datamirror}.)
if "$REGISTREAM_ORG" == "" global REGISTREAM_ORG "~/Github/registream-org"

* Install autolabel
net install autolabel,  from("http://localhost:5000/install/stata") replace

* Activate host override (redirects API calls to localhost:5000).

do "$REGISTREAM_ORG/registream/stata/dev/host_override.do"

* do some lookups
autolabel lookup carb, domain(scb) lang(eng)
autolabel lookup ssyk*, domain(scb) lang(swe)


use "$REGISTREAM_ORG/autolabel/examples/lisa.dta" , clear





