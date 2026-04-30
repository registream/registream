{smcl}
{* *! version {{VERSION}} {{STHLP_DATE}}}{...}
{viewerjumpto "Syntax" "registream##syntax"}{...}
{viewerjumpto "Description" "registream##description"}{...}
{viewerjumpto "RegiStream modules" "registream##modules"}{...}
{viewerjumpto "First-run setup" "registream##setup"}{...}
{viewerjumpto "Commands" "registream##commands"}{...}
{viewerjumpto "Configuration" "registream##config"}{...}
{viewerjumpto "Examples" "registream##examples"}{...}
{viewerjumpto "Stored results" "registream##results"}{...}
{viewerjumpto "Privacy" "registream##privacy"}{...}
{viewerjumpto "Authors" "registream##authors"}{...}
{viewerjumpto "Citing RegiStream" "registream##citation"}{...}
{viewerjumpto "Support" "registream##support"}{...}

{title:Title}

{p2colset 5 20 22 2}{...}
{p2col :{cmd:registream} {hline 2}}Infrastructure for Register Data Research{p_end}
{p2colreset}{...}

{marker syntax}{...}
{title:Syntax}

{pstd}
{ul:Configuration & Settings}
{p_end}

{p 8 15 2}
{cmd:registream info}
{p_end}

{p 8 15 2}
{cmd:registream config} [{cmd:,} {it:options}]
{p_end}

{pstd}
{ul:Updates}
{p_end}

{p 8 15 2}
{cmd:registream update} [{cmd:package}]
{p_end}

{pstd}
{ul:Usage & Statistics}
{p_end}

{p 8 15 2}
{cmd:registream stats} [{cmd:all}]
{p_end}

{pstd}
{ul:Reference & Citation}
{p_end}

{p 8 15 2}
{cmd:registream version}
{p_end}

{p 8 15 2}
{cmd:registream cite}
{p_end}

{marker description}{...}
{title:Description}

{pstd}
{cmd:RegiStream} is an ecosystem for register data research.
The {cmd:registream} command provides shared infrastructure (configuration
management, update checking, usage tracking, and citation) used by all
RegiStream modules.
{p_end}

{pstd}
Data work is handled by individual modules:
{p_end}

{phang2}
{hline 2} {help autolabel:autolabel}: apply variable and value labels from structured metadata{break}
{hline 2} {help datamirror:datamirror}: coefficient-faithful synthetic data with SDC-safe extract
{p_end}

{marker modules}{...}
{title:RegiStream modules}

{pstd}
{help autolabel:autolabel}: Automatically apply variable and value labels from
structured metadata. Supports six Nordic domains (Statistics Sweden, Statistics
Denmark, Statistics Norway, Försäkringskassan, Socialstyrelsen, Statistics
Iceland) plus institutional metadata. See {help autolabel:help autolabel}.
{p_end}

{pstd}
{help datamirror:datamirror}: Build coefficient-faithful synthetic data for
replication outside secure environments. Extracts marginals, correlations, and
regression checkpoints with automatic small-cell suppression. See
{help datamirror:help datamirror}.
{p_end}

{marker setup}{...}
{title:First-run setup}

{pstd}
When you first run RegiStream or any of its modules, you'll be asked to choose a setup mode:
{p_end}

{phang2}
{bf:1) Offline Mode}
{p_end}
{pmore2}
{hline 2} No internet connections{break}
{hline 2} Manual metadata management{break}
{hline 2} Local usage logging only (stays on your machine)
{p_end}

{phang2}
{bf:2) Standard Mode} (recommended)
{p_end}
{pmore2}
{hline 2} Automatic metadata downloads{break}
{hline 2} Automatic update checks (daily){break}
{hline 2} Local usage logging only{break}
{hline 2} No online telemetry
{p_end}

{phang2}
{bf:3) Full Mode} (Help improve RegiStream)
{p_end}
{pmore2}
{hline 2} Everything in Standard Mode, plus:{break}
{hline 2} Online telemetry: sends anonymized usage data to help improve RegiStream
{p_end}

{pstd}
You can change these settings at any time using {cmd:registream config}.
{p_end}

{pstd}
{bf:Non-interactive sessions} (CI, scripts, batch mode): set the
environment variable {cmd:REGISTREAM_AUTO_APPROVE=yes} to silently pick
Full Mode; without it, the first-run wizard cannot prompt and the
command fails. This matches the Python client; the R client defaults to
a transient Offline-Mode config instead for CRAN-check safety.
{p_end}

{marker commands}{...}
{title:Commands}

{dlgtab:info}

{pstd}
Display current configuration and settings.
{p_end}

{phang2}
{cmd:. registream info}
{p_end}

{pstd}
Shows:
{p_end}

{pmore2}
{hline 2} Configuration directory location{break}
{hline 2} Current version{break}
{hline 2} All active settings (usage_logging, telemetry_enabled, internet_access, auto_update_check){break}
{hline 2} Citation information
{p_end}

{dlgtab:config}

{pstd}
Update configuration settings. With no options, displays current settings (same as {cmd:registream info}).
{p_end}

{phang2}
{cmd:. registream config}
{p_end}

{phang2}
{cmd:. registream config, telemetry_enabled(false)}
{p_end}

{pstd}
See {help registream##config:Configuration section} below for all available settings and mode presets.
{p_end}

{dlgtab:update}

{pstd}
Check for and install RegiStream package updates.
{p_end}

{phang2}
{cmd:. registream update}: check and install package updates (default)
{p_end}

{phang2}
{cmd:. registream update package}: same as above
{p_end}

{pstd}
For metadata dataset updates, use {help autolabel:autolabel}:
{p_end}

{phang2}
{cmd:. autolabel update datasets}
{p_end}

{dlgtab:stats}

{pstd}
View your local usage statistics.
{p_end}

{phang2}
{cmd:. registream stats}
{p_end}

{phang2}
{cmd:. registream stats all}
{p_end}

{pstd}
Shows how many times you've used RegiStream and when. With {cmd:all},
aggregates across every anonymous user id found in the local usage log
(useful on shared machines); without it, shows statistics for the
current user only.
{p_end}

{dlgtab:version}

{pstd}
Display the current version of RegiStream.
{p_end}

{phang2}
{cmd:. registream version}
{p_end}

{pstd}
Output:
{p_end}

{pmore}
RegiStream version {{VERSION}}
{p_end}

{dlgtab:cite}

{pstd}
Display citation information for use in publications.
{p_end}

{phang2}
{cmd:. registream cite}
{p_end}

{pstd}
Shows the recommended citation format along with details about datasets used.
{p_end}

{marker config}{...}
{title:Configuration}

{dlgtab:Available settings}

{pstd}
The four privacy / connectivity flags accept {cmd:true} or {cmd:false};
{cmd:dm_min_cell_size} takes a positive integer and
{cmd:dm_quantile_trim} takes a non-negative real between 0 and 50.
{p_end}

{phang}
{opt usage_logging(true|false)}: Local usage logging (default: true){break}
Stores command history in {cmd:~/.registream/usage_stata.csv}
{p_end}

{phang}
{opt telemetry_enabled(true|false)}: Online telemetry (default: false){break}
Sends anonymized usage data to registream.org
{p_end}

{phang}
{opt internet_access(true|false)}: Internet features (default: true){break}
Allows automatic metadata downloads and update checks
{p_end}

{phang}
{opt auto_update_check(true|false)}: Auto-update checks (default: true){break}
Daily background check for package updates
{p_end}

{phang}
{opt dm_min_cell_size(#)}: Datamirror privacy threshold (default: 50){break}
Minimum cell size below which datamirror suppresses marginals and
correlations in synthetic-data export. Must be a positive integer.
{p_end}

{phang}
{opt dm_quantile_trim(#)}: Datamirror continuous-SDC threshold (default: 1){break}
Percentile at which {cmd:q0} and {cmd:q100} in {cmd:marginals_cont.csv}
are top- and bottom-coded. The default of 1 plateaus {cmd:q0} at the
1st percentile and {cmd:q100} at the 99th, retiring the raw max/min
columns that the Brandt-Franconi ESSnet guidelines classify as unsafe
by default. Must be a non-negative real between 0 and 50. Setting to
0 stores raw max/min and should only be used on data already top- and
bottom-coded upstream.
{p_end}

{dlgtab:Mode presets}

{pstd}
{bf:Offline Mode}:
{p_end}

{phang2}
{cmd:. registream config, usage_logging(true) internet_access(false) telemetry_enabled(false) auto_update_check(false)}
{p_end}

{pstd}
{bf:Standard Mode}:
{p_end}

{phang2}
{cmd:. registream config, usage_logging(true) internet_access(true) telemetry_enabled(false) auto_update_check(true)}
{p_end}

{pstd}
{bf:Full Mode}:
{p_end}

{phang2}
{cmd:. registream config, usage_logging(true) internet_access(true) telemetry_enabled(true) auto_update_check(true)}
{p_end}

{pstd}
You can also set individual settings (e.g., {cmd:registream config, telemetry_enabled(false)}).
{p_end}

{dlgtab:Custom directory}

{pstd}
By default, RegiStream stores files in:
{p_end}

{pmore2}
{hline 2} macOS: {cmd:/Users/username/.registream/}{break}
{hline 2} Linux: {cmd:/home/username/.registream/}{break}
{hline 2} Windows: {cmd:C:/Users/username/AppData/Local/registream/}
{p_end}

{pstd}
To use a custom directory, set before first run:
{p_end}

{phang2}
{cmd:. global registream_dir "/your/custom/path"}
{p_end}

{marker examples}{...}
{title:Examples}

{dlgtab:Configuration}

{phang2}
{cmd:. registream info} {it:(view current settings)}
{p_end}

{phang2}
{cmd:. registream config, telemetry_enabled(false)} {it:(disable online telemetry)}
{p_end}

{dlgtab:Updates}

{phang2}
{cmd:. registream update} {it:(check and install package updates)}
{p_end}

{phang2}
{cmd:. autolabel update datasets} {it:(update metadata; see {help autolabel})}
{p_end}

{dlgtab:Usage}

{phang2}
{cmd:. registream stats} {it:(view your usage statistics)}
{p_end}

{dlgtab:Reference}

{phang2}
{cmd:. registream version} {it:(show version)}
{p_end}

{phang2}
{cmd:. registream cite} {it:(show citation for publications)}
{p_end}


{marker results}{...}
{title:Stored results}

{pstd}
{cmd:registream} stores the following in {cmd:r()}:
{p_end}

{synoptset 20 tabbed}{...}
{p2col 5 20 24 2: Scalars}{p_end}
{synopt:{cmd:r(status)}}0 if successful, 1 if error{p_end}

{p2col 5 20 24 2: Macros}{p_end}
{synopt:{cmd:r(dir)}}Directory where RegiStream stores configuration and cached metadata{p_end}
{synopt:{cmd:r(version)}}Installed core version{p_end}


{marker privacy}{...}
{title:Privacy and Usage Tracking}

{pstd}
RegiStream has two separate tracking systems:
{p_end}

{dlgtab:1. Local Usage Logging (NOT a GDPR issue)}

{pstd}
Stores data {bf:only on your machine}; never transmitted anywhere.
{p_end}

{pmore2}
{hline 2} Stored in {cmd:~/.registream/usage_stata.csv}{break}
{hline 2} Like {cmd:.bash_history} for RegiStream commands{break}
{hline 2} Default: Enabled{break}
{hline 2} You control: View ({cmd:registream stats}), Delete (rm file), Disable ({cmd:registream config, usage_logging(false)})
{p_end}

{dlgtab:2. Online Telemetry (GDPR compliant)}

{pstd}
Opt-in system that sends {bf:fully anonymous} data to registream.org.
{p_end}

{pmore2}
{hline 2} Default: Disabled (requires explicit consent){break}
{hline 2} Anonymous: One-way hash ID, cannot identify individuals{break}
{hline 2} What's sent: command, timestamp, version, OS (NOT your data or file paths){break}
{hline 2} Why: Helps improve RegiStream{break}
{hline 2} Enable: {cmd:registream config, telemetry_enabled(true)}{break}
{hline 2} Disable: {cmd:registream config, telemetry_enabled(false)}
{p_end}

{pstd}
For server-side data deletion, email support@registream.org with your anonymous ID (from {cmd:registream stats}).
{p_end}

{dlgtab:User control}

{pstd}
You have complete control over both systems:
{p_end}

{pmore2}
{bf:Configuration:}{break}
{hline 2} View all settings: {cmd:registream info}{break}
{hline 2} Change any setting: {cmd:registream config, option(value)}
{p_end}

{pmore2}
{bf:Local data:}{break}
{hline 2} View statistics: {cmd:registream stats}{break}
{hline 2} Access raw CSV: {cmd:~/.registream/usage_stata.csv}{break}
{hline 2} Disable: {cmd:registream config, usage_logging(false)}{break}
{hline 2} Delete: {cmd:rm ~/.registream/usage_stata.csv}
{p_end}

{pmore2}
{bf:Online telemetry:}{break}
{hline 2} Disable: {cmd:registream config, telemetry_enabled(false)}{break}
{hline 2} Request server deletion: Email support@registream.org with anonymous ID
{p_end}

{marker authors}{...}
{title:Authors}

{pstd}Jeffrey Clark{break}
{{AFFILIATION_JEFFREY}}{break}
Email: {browse "mailto:{{EMAIL_JEFFREY}}":{{EMAIL_JEFFREY}}}
{p_end}

{pstd}Jie Wen{break}
{{AFFILIATION_JIE}}{break}
Email: {browse "mailto:{{EMAIL_JIE}}":{{EMAIL_JIE}}}
{p_end}

{marker citation}{...}
{title:Citing RegiStream}

{pstd}
To cite the {cmd:RegiStream} package in publications:
{p_end}

{pstd}
{{CITATION_REGISTREAM_STHLP_APA_VERSIONED}}
{p_end}

{pstd}
For dataset-specific citations, use {cmd:registream cite} to see recommended format.
{p_end}

{marker support}{...}
{title:Support}

{pstd}
{hline 2} Documentation: {browse "https://registream.org/docs"}{break}
{hline 2} Support & FAQ: {browse "https://registream.org"}{break}
{hline 2} Contact: {browse "mailto:support@registream.org":support@registream.org}
{p_end}
