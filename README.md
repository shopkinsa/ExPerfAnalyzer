## Running the script
    .\ExPerfAnalyzer.ps1 .\EXSERVER01_FULL_000001.BLG

## Registering script as a default handler
Execute the script with no parameters and it will register itself as a shell handler for perfmon .blg files. You can then right-click any .blg file and select *ExPerfAnalyzer* to quickly parse the log.

## Inspiration
This script was inspired by [Performance Analysis of Logs (PAL)](https://pal.codeplex.com) and PMA.VBS (an internal tool used by Windows support).

## FAQ
- **This takes forever to run.**

    It's faster than PAL.

- **Why don't I just use PAL?**

    You could, but PAL takes even longer to run and throws a lot of false positives.
	
- **What's the expected running time?**

	v0.2.2 and an Intel Core i7-4810MQ @ 2.8Ghz processed a 1GB perfmon sitting on an SSD in 13 seconds.

- **Can I edit this script however I'd like?**

    Yes, that's the magic of open source software!

- **Do you accept pull requests? Can I contribute to the script?**

    Of course!

## Changelog
* v0.2.2 (2018-01-16)
  - First position parameter is bound to PerfmonFile param
* v0.2.1 (2017-08-31)
  - Major performance improvements
  - Script structure changes
* v0.2.0 (2017-06-05)
  - Kubilay Ekici added ActiveSync counters
* v0.1.9 (2016-12-20)
  - using \Processor(_Total)\% Processor Time as the counter to auto-detect server name now
* v0.1.8 (2016-12-15)
  - added top 10 processes by working set
  - made the N in top N processes a variable so it can be customized
* v0.1.7 (2016-10-12)
  - failure to find the input file stops the script
  - Import-Counter errors are now hidden during execution
* v0.1.6 (2016-10-11)
  - improved formatting
  - increased min/max/avg column width from 10 to 12 characters
* v0.1.5 (2016-10-10)
  - reverted to single-server support only
  - added counter: HttpProxy\Average ClientAccess Server Processing Latency
  - added top 10 processes by % Processor Time
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

## Contributing
This project has adopted the [Microsoft Open Source Code of Conduct](https://opensource.microsoft.com/codeofconduct/). For more information see the [Code of Conduct FAQ](https://opensource.microsoft.com/codeofconduct/faq/) or contact [opencode@microsoft.com](mailto:opencode@microsoft.com) with any additional questions or comments.
