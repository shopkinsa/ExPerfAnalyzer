<#
Name:
  ExPerfAnalyzer.ps1

Description:
  Parses perfmon .blg files from an Exchange server captured with ExPerfWiz.ps1
  and produces a high-level summary in a text file.

Author:
  Matthew Huynh (mahuynh@microsoft.com)

Use:
  .\ExPerfAnalyzer.ps1 EXSERVER01_FULL_000001.BLG

Changelog:
  See https://github.com/Microsoft/ExPerfAnalyzer.
#>

Param(
  [Parameter(Mandatory=$False,Position=1)]
  [string]$PerfmonFilePath,
  [Parameter(Mandatory=$False,Position=2)]
  [string[]]$Servers
  )

# if you start the script with no parameters, it will register itself as a handler for perfmon BLG files.
if ($PerfmonFilePath.Trim().Length -eq 0) {
    New-PSDrive -PSProvider Registry -Root HKEY_CLASSES_ROOT -Name HKCR | Out-Null
    $scriptPath = $MyInvocation.MyCommand.Path
    $defaultCommand = 'powershell.exe -command "& ' + "'" + $scriptPath + "'" + " '%1'" + '"'
    Write-Debug $defaultCommand
    $newRegKey = New-Item HKCR:\Diagnostic.Perfmon.Document\shell\ExPerfAnalyzer\command -Force -Value $defaultCommand
    $string = "ExPerfAnalyzer {0}registered itself as a shell handler for perfmon .blg files."
    if ($newRegKey -ne $null) {
        Write-Host -ForegroundColor Green ($string -f "")
    } else {
        Write-Error ($string -f "failed to ")
    }
    exit
}

# declare script variables
$scriptVersion = "0.1.9"
$TOP_N_PROCESSES = 10 # show top 10 by default. change this if you want more or less.
$summary = @()
$totalSamples = 0
$earliestTimestamp = [System.DateTime]::MaxValue
$latestTimestamp = [System.DateTime]::MinValue
[int] $sampleInterval = 0 # this will be an average amongst all the samples
$outStr = ""
$detailLineStrLength = 48
$columnWidth = 12
$perfmonFile = Get-ChildItem $PerfmonFilePath -ErrorAction Stop
$perfmonFilename = $perfmonFile.Name
$outFile = $PerfmonFilePath + "-Summary.txt"
[string[]] $supportedFiletypes = ".blg", ".csv", ".tsv"

if ($perfmonFile.Extension -inotin $supportedFiletypes) {
    Write-Error ("Please input a proper perfmon file (" + ($supportedFiletypes -join ", ") + ").")
    exit
}

# if no Servers param, detect the servers in the BLG
if ($Servers -eq $null) {
    $serversDetectionTime = Measure-Command {
        Write-Host -ForegroundColor Green "Detecting server name..."
        [string] $firstCounter = (Import-Counter $PerfmonFilePath -Counter "\\*\Processor(_Total)\% Processor Time")[0].CounterSamples.Path
        $Servers = ($firstCounter -split '\\')[2]
        Write-Debug "Detected server: $Servers"
    }
    Write-Host "  completed in $("{0:N1}" -f $serversDetectionTime.TotalSeconds) seconds."
}

# the fun starts here!
$counters = @()
$topNcounters = @()
Write-Host -ForegroundColor Green "Initializing counter list..."
$counterInitTime = Measure-Command {
# define our enum so that the output can be ordered by Category
Add-Type -TypeDefinition @"
    public enum Category
    {
        Processor=0,
        Memory,
        NetworkInterface,
        Disk,
        MSExchangeADAccess,
        ASPNET,
        MSExchangeIS,
        HttpProxy,
        RpcClientAccess,
        TopNProcesses
    }
"@

######################
# PROCESSOR COUNTERS #
######################
$counters += New-Object PSObject -Prop @{'Category'=[Category]::Processor;
                                         'Name'="\Processor(*)\% Processor Time";
                                         'FormatDivider'=100;
                                         'FormatString'="{0:p1}";}
$counters += New-Object PSObject -Prop @{'Category'=[Category]::Processor;
                                         'Name'="\System\Processor Queue Length";
                                         'FormatDivider'=1;
                                         'FormatString'="{0:N0}";}
###################
# MEMORY COUNTERS #
###################
$counters += New-Object PSObject -Prop @{'Category'=[Category]::Memory;
                                         'Name'="\Memory\Available Bytes";
                                         'FormatDivider'=1MB;
                                         'FormatString'="{0:N0}MB";}
$counters += New-Object PSObject -Prop @{'Category'=[Category]::Memory;
                                         'Name'="\Memory\% Committed Bytes In Use";
                                         'FormatDivider'=100;
                                         'FormatString'="{0:p0}";}
$counters += New-Object PSObject -Prop @{'Category'=[Category]::Memory;
                                         'Name'="\Memory\Pool Paged Bytes";
                                         'FormatDivider'=1MB;
                                         'FormatString'="{0:N0}MB";}
$counters += New-Object PSObject -Prop @{'Category'=[Category]::Memory;
                                         'Name'="\Memory\Pool Nonpaged Bytes";
                                         'FormatDivider'=1MB;
                                         'FormatString'="{0:N0}MB";}
$counters += New-Object PSObject -Prop @{'Category'=[Category]::Memory;
                                         'Name'="\Memory\Commit Limit";
                                         'FormatDivider'=1MB;
                                         'FormatString'="{0:N0}MB";}
$counters += New-Object PSObject -Prop @{'Category'=[Category]::Memory;
                                         'Name'="\Memory\Cache Bytes";
                                         'FormatDivider'=1MB;
                                         'FormatString'="{0:N0}MB";}
#########################
# NETWORK INT. COUNTERS #
#########################
$counters += New-Object PSObject -Prop @{'Category'=[Category]::NetworkInterface;
                                         'Name'="\Network Interface(*)\Current Bandwidth";
                                         'FormatDivider'=1000000;
                                         'FormatString'="{0:N0}Mb";}
$counters += New-Object PSObject -Prop @{'Category'=[Category]::NetworkInterface;
                                         'Name'="\Network Interface(*)\Bytes Total/sec";
                                         'FormatDivider'=1KB;
                                         'FormatString'="{0:N0}KB";}
$counters += New-Object PSObject -Prop @{'Category'=[Category]::NetworkInterface;
                                         'Name'="\Network Interface(*)\Packets/sec";
                                         'FormatDivider'=1;
                                         'FormatString'="{0:N0}";}
$counters += New-Object PSObject -Prop @{'Category'=[Category]::NetworkInterface;
                                         'Name'="\Network Interface(*)\Packets Received Discarded";
                                         'FormatDivider'=1;
                                         'FormatString'="{0:N0}";}
$counters += New-Object PSObject -Prop @{'Category'=[Category]::NetworkInterface;
                                         'Name'="\Network Interface(*)\Packets Received Errors";
                                         'FormatDivider'=1;
                                         'FormatString'="{0:N0}";}
#################
# DISK COUNTERS #
#################
$counters += New-Object PSObject -Prop @{'Category'=[Category]::Disk;
                                         'Name'="\LogicalDisk(*)\Avg. Disk sec/Transfer";
                                         'FormatDivider'=0.001;
                                         'FormatString'="{0:N1}ms";}
$counters += New-Object PSObject -Prop @{'Category'=[Category]::Disk;
                                         'Name'="\LogicalDisk(*)\Disk Transfers/sec";
                                         'FormatDivider'=1;
                                         'FormatString'="{0:N1}";}
$counters += New-Object PSObject -Prop @{'Category'=[Category]::Disk;
                                         'Name'="\LogicalDisk(*)\Disk Bytes/sec";
                                         'FormatDivider'=1KB;
                                         'FormatString'="{0:N0}KB";}
$counters += New-Object PSObject -Prop @{'Category'=[Category]::Disk;
                                         'Name'="\LogicalDisk(*)\Avg. Disk Queue Length";
                                         'FormatDivider'=1;
                                         'FormatString'="{0:N2}";}
$counters += New-Object PSObject -Prop @{'Category'=[Category]::Disk;
                                         'Name'="\LogicalDisk(*)\% Idle Time";
                                         'FormatDivider'=100;
                                         'FormatString'="{0:p1}";}
###############################
# MSExchangeADAccess COUNTERS #
###############################
# these counters throw an CounterPathIsInvalid exception even though they succeed... unsure why.
$counters += New-Object PSObject -Prop @{'Category'=[Category]::MSExchangeADAccess;
                                         'Name'="\MSExchange ADAccess Domain Controllers(*)\LDAP Search Time";
                                         'FormatDivider'=1;
                                         'FormatString'="{0:N1}ms";}
$counters += New-Object PSObject -Prop @{'Category'=[Category]::MSExchangeADAccess;
                                         'Name'="\MSExchange ADAccess Domain Controllers(*)\LDAP Read Time";
                                         'FormatDivider'=1;
                                         'FormatString'="{0:N1}ms";}
####################
# ASP.NET COUNTERS #
####################
$counters += New-Object PSObject -Prop @{'Category'=[Category]::ASPNET;
                                         'Name'="\ASP.NET Apps v4.0.30319(*)\Requests Executing";
                                         'FormatDivider'=1;
                                         'FormatString'="{0:N0}";}
#########################
# MSExchangeIS COUNTERS #
#########################
$counters += New-Object PSObject -Prop @{'Category'=[Category]::MSExchangeIS;
                                         'Name'="\MSExchangeIS Client Type(*)\RPC Average Latency";
                                         'FormatDivider'=1;
                                         'FormatString'="{0:N1}ms";}
$counters += New-Object PSObject -Prop @{'Category'=[Category]::MSExchangeIS;
                                         'Name'="\MSExchangeIS Client Type(*)\RPC Operations/sec";
                                         'FormatDivider'=1;
                                         'FormatString'="{0:N0}";}
$counters += New-Object PSObject -Prop @{'Category'=[Category]::MSExchangeIS;
                                         'Name'="\MSExchangeIS Store(*)\Active mailboxes";
                                         'FormatDivider'=1;
                                         'FormatString'="{0:N0}";}
######################
# HttpProxy COUNTERS #
######################
$counters += New-Object PSObject -Prop @{'Category'=[Category]::HttpProxy;
                                         'Name'="\MSExchange HttpProxy(*)\Average ClientAccess Server Processing Latency";
                                         'FormatDivider'=1;
                                         'FormatString'="{0:N1}ms";}
############################
# RpcClientAccess COUNTERS #
############################
$counters += New-Object PSObject -Prop @{'Category'=[Category]::RpcClientAccess;
                                         'Name'="\MSExchange RpcClientAccess\RPC Averaged Latency";
                                         'FormatDivider'=1;
                                         'FormatString'="{0:N1}ms";}
$counters += New-Object PSObject -Prop @{'Category'=[Category]::RpcClientAccess;
                                         'Name'="\MSExchange RpcClientAccess\Active User Count";
                                         'FormatDivider'=1;
                                         'FormatString'="{0:N0}";}
$counters += New-Object PSObject -Prop @{'Category'=[Category]::RpcClientAccess;
                                         'Name'="\MSExchange RpcClientAccess\RPC Requests";
                                         'FormatDivider'=1;
                                         'FormatString'="{0:N0}";}
##########################
# TopNProcesses COUNTERS #
##########################
$topNCounters += New-Object PSObject -Prop @{'Category'=[Category]::TopNProcesses;
                                         'Name'="\Process(*)\% Processor Time";
                                         'FormatDivider'=100;
                                         'FormatString'="{0:p1}";}
$topNCounters += New-Object PSObject -Prop @{'Category'=[Category]::TopNProcesses;
                                         'Name'="\Process(*)\Working Set";
                                         'FormatDivider'=1MB;
                                         'FormatString'="{0:N0}MB";}
$counters += $topNCounters # we keep track of topNcounters for when we need to print later
}
Write-Host "  completed in $("{0:N1}" -f $counterInitTime.TotalSeconds) seconds."

# list of instance names we don't care about
[string[]] $ignoredInstances = "isatap", "harddiskvolume"

# list of counters we want to promote to server-level detail printing
[string[]] $listCountersPrintAtServerLevel = "MSExchange RpcClientAccess", "Memory", "Processor Queue Length"

function IsIgnoredInstance($str) {
    foreach ($s in $script:ignoredInstances) {
        if ($str -match $s) {
            return $true
        }
    }
    return $false
}

function IsPrintAtServerLevelCounter($str) {
    foreach ($s in $script:listCountersPrintAtServerLevel) {
        if ($str -match $s) {
            return $true
        }
    }
    return $false
}

function ParseCounters {
    $ErrorActionPreference = "SilentlyContinue"

    Write-Host -ForegroundColor Green "Parsing file..."

    $script:processingTime = Measure-Command {

        # summarize counters grouped by COUNTER, SERVER, INSTANCE
        foreach ($counter in $counters) {

            foreach ($server in $Servers) {
            
                # load in data from file
                $str = "\\" + $server + $counter.Name
                Write-Verbose "Processing counter: $str"
                $samples = Import-Counter $PerfmonFilePath -Counter $str

                $numSamples = $samples.Count
                $numInstances = $samples[0].CounterSamples.Count
                $script:totalSamples += $numSamples
                Write-Debug "$numSamples samples, $numInstances instances"

                # iterate through each instance
                for ($j = 0; $j -lt $numInstances; $j++) {

                    # prepare summary variables for instance
                    [string] $instanceName = $samples[0].CounterSamples[$j].Path.Split(("(", ")"))[1]
                    if (IsIgnoredInstance($instanceName)) {
                        Write-Debug "Ignoring instance: $instanceName"
                        continue
                    } else {
                        Write-Debug "Processing instance: $instanceName"
                    }
                    [double] $value = 0
                    [double] $max = 0
                    [double] $min = $samples[0].CounterSamples[$j].CookedValue

                    # summarize instance samples
                    for ($k = 0; $k -lt $numSamples; $k++) {
                        $v = $samples[$k].CounterSamples[$j]
                        $value += $v.CookedValue
                        if ($v.CookedValue -gt $max) { $max = $v.CookedValue }
                        if ($v.CookedValue -lt $min) { $min = $v.CookedValue }

                        if ($v.Timestamp -lt $script:earliestTimestamp) {
                            $script:earliestTimestamp = $v.Timestamp
                        }

                        if ($v.Timestamp -gt $script:latestTimestamp) {
                            $script:latestTimestamp = $v.Timestamp
                        }

                        if ($k -gt 0) {
                            $diff = ($v.Timestamp - $previousTimestamp).TotalSeconds
                            $script:sampleInterval = ($script:sampleInterval + $diff) / 2
                        }

                        $previousTimestamp = $v.Timestamp
                    }

                    # save instance summary
                    $summaryLine = New-Object System.Object
                    $summaryLine | Add-Member -Type NoteProperty -Name Category -Value $counter.Category
                    $summaryLine | Add-Member -Type NoteProperty -Name Counter -Value $counter.Name
                    $summaryLine | Add-Member -Type NoteProperty -Name Server -Value $server
                    if ($instanceName.Length -gt $script:detailLineStrLength) {
                        $instanceStr = $instanceName.Substring(0, $script:detailLineStrLength)
                    } else {
                        $instanceStr = $instanceName
                    }
                    $summaryLine | Add-Member -Type NoteProperty -Name Instance -Value $instanceStr
                    #$minStr = $counter.FormatString -f ($min / $counter.FormatDivider)
                    $summaryLine | Add-Member -Type NoteProperty -Name Min -Value $min
                    #$maxStr = $counter.FormatString -f ($max / $counter.FormatDivider)
                    $summaryLine | Add-Member -Type NoteProperty -Name Max -Value $max
                    $avg = $value / $numSamples
                    #$avgStr = $counter.FormatString -f ($avg / $counter.FormatDivider)
                    $summaryLine | Add-Member -Type NoteProperty -Name Avg -Value $avg
                    # only add lines that have meaningful value
                    if ($max -gt 0) { $script:summary += $summaryLine }
                } #end instance loop

            } # end server loop

        } # end counter loop
        
    }
    Write-Host "  completed in $("{0:N1}" -f $script:processingTime.TotalSeconds) seconds."
    $ErrorActionPreference = "Continue"
}

function AddLine([string] $str) {
    $script:outStr += $str + "`r`n"
}

function PrintSummary($lines) {
    foreach ($val in $lines) {
        # 1) We need to special case certain counters that do not have an instance so their value resides at the counter line instead
        # 2) _total can be shifted up to the counter line as well
        if (IsPrintAtServerLevelCounter($val.Counter)) {
            Write-Debug "printDetailLineAtCounterLevel = true"
            $printDetailLineAtCounterLevel = $true
        } else {
            $printDetailLineAtCounterLevel = $false
        }

        # grab the FormatString as we'll need it to format the min/max/avg
        $counter = $script:counters | ? {$_.Name -eq $val.Counter}
        $minStr = $counter.FormatString -f ($val.Min / $counter.FormatDivider)
        $maxStr = $counter.FormatString -f ($val.Max / $counter.FormatDivider)
        $avgStr = $counter.FormatString -f ($val.Avg / $counter.FormatDivider)

        $isNewCategory = $prevCategory -ne $val.Category
        $isNewCounter = $prevCounter -ne $val.Counter

        if ($isNewCategory) {
            # if new category, print Category
            $prevCategory = $val.Category
            AddLine("")
            AddLine("{0,-$($detailLineStrLength+2)} {1,$columnWidth} {2,$columnWidth} {3,$columnWidth}" -f $val.Category, "Min", "Max", "Avg")
            AddLine("==========================================================================================")
            $prevCounter = $null
        }

        # if printDetailLineAtCounterLevel, print Counter + detail
        # else
        #   if new counter, print counter
        #   print detail line

        if ($printDetailLineAtCounterLevel) {
            AddLine("{0,-$($detailLineStrLength+2)} {1,$columnWidth} {2,$columnWidth} {3,$columnWidth}" -f $val.Counter, $minStr, $maxStr, $avgStr)
        } else {

            # if new counter, print Counter
            if ($isNewCounter) {
                $prevCounter = $val.Counter
                AddLine("{0,-$($detailLineStrLength+2)}" -f $val.Counter)
            }

            # print the detail line
            AddLine("  {0,-$detailLineStrLength} {1,$columnWidth} {2,$columnWidth} {3,$columnWidth}" -f $val.Instance, $minStr, $maxStr, $avgStr)
        }

    }
}

function OutputSummary {
    Write-Host -ForegroundColor Green "Writing text file..."
    # uncomment the following line if you want the data sent directly to console
    # $script:summary | ft counter,server,instance,max,min,avg

    $writeTime = Measure-Command {
    
        # Log Summary
        AddLine("Exchange Perfmon Log Summary")
        AddLine("=============================")
        AddLine("{0,-18} : {1}" -f "Log Filename", $script:perfmonFilename)
        AddLine("{0,-18} : {1}" -f "Server", ($Servers -join ", "))
        AddLine("{0,-18} : {1}" -f "Earliest Timestamp", $script:earliestTimestamp)
        AddLine("{0,-18} : {1}" -f "Latest Timestamp", $script:latestTimestamp)
        AddLine("{0,-18} : {1}" -f "Log Duration", ($script:latestTimestamp - $script:earliestTimestamp))
        AddLine("{0,-18} : {1}s" -f "Sample Interval", $script:sampleInterval)

        # Counters by CATEGORY, COUNTER, SERVER, INSTANCE
        $regularSummary = ($script:summary | ? {$_.Counter -notin $topNcounters.Name} | sort Category, Counter, Server, Instance)
        foreach ($topNcounter in $topNcounters) {
            $topNSummary += ($script:summary | ? {$_.Counter -eq $topNcounter.Name -and $_.Instance -ne '_total' -and $_.Instance -ne 'idle'} | sort Avg -Descending | select -first $TOP_N_PROCESSES)
        }

        PrintSummary($regularSummary)
        PrintSummary($topNSummary)
        AddLine("")

        # Analysis Stats
        AddLine("Analysis Stats")
        AddLine("===============")
        AddLine("{0,-24} : {1}" -f "Report generated by", "ExPerfAnalyzer.ps1 v" + $script:scriptVersion)
        AddLine("{0,-24} : {1}" -f "Written by", "Matthew Huynh (mahuynh@microsoft.com)")
        $currTime = Get-Date
        AddLine("{0,-24} : {1}" -f "Generated On", $currTime.ToShortDateString() + " " + $currTime.ToShortTimeString())
        AddLine("{0,-24} : {1:N0}" -f "Total counters processed", $script:counters.Count)
        AddLine("{0,-24} : {1:N0}" -f "Total Samples", $script:totalSamples)
        AddLine("{0,-24} : {1:N1}s" -f "Total processing time", $script:processingTime.TotalSeconds)
        AddLine("{0,-24} : {1:N5}s" -f "Samples processed/sec", ([double]$script:totalSamples / $script:processingTime.TotalSeconds))
        AddLine("{0,-24} : {1:N5}s" -f "Proc. time per sample", ($script:processingTime.TotalSeconds / [double]$script:totalSamples))

        # write string to disk
        $outStr | Out-File $script:outFile
    }

    Write-Host "  completed in $("{0:N1}" -f $writeTime.TotalSeconds) seconds."
}

# parse our data
ParseCounters

# write output to text file
OutputSummary

# open file at the end
&$outFile