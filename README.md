## Running the script
    .\ExPerfAnalyzer.ps1 EXSERVER01_FULL_000001.BLG

## Registering script as a default handler
Execute the script with no parameters and it will register itself as a shell handler for perfmon .blg files. You can then right-click any .blg file and select *ExPerfAnalyzer* to quickly parse the log.

## Project Vision
The tool is a PowerShell script currently. We are investigating new platforms and technologies as PowerShell is not performant enough for us.

## Inspiration
This script was inspired by [Performance Analysis of Logs (PAL)](https://pal.codeplex.com) and PMA.VBS (an internal tool used by Windows support).

## Changelog
* v0.1.4 (2016-09-30)
  - executing the script without an input file will register itself as a shell handler for perfmon .blg files
  - summary text file will be opened at end of script execution
* v0.1.3 (2016-09-29)
  - made Servers optional (script will auto-detect the first server present in BLG)
  - added validation for input file extension
* v0.1.2 (2016-09-28)
  - added more counters like disk, MSExchangeADAccess, RpcClientAccess
* v0.1.1 (2016-09-28)
  - refactored counter parsing logic to be more structured
  - counters can show custom string format
  - counters are displayed in order and in logical groups
* v0.1.0 (2016-09-28)
  - initial script
