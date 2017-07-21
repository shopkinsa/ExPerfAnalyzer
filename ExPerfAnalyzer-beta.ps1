[CmdletBinding()]
Param(
[Parameter(Mandatory=$true,ParameterSetName="FileDirectory")][string]$PerfmonFileDirectory,
[Parameter(Mandatory=$false,ParameterSetName="FileDirectory")]
	[Parameter(ParameterSetName="SingleFile")][int64]$MaxSamples = [Int64]::MaxValue,
[Parameter(Mandatory=$false,ParameterSetName="FileDirectory")]
	[Parameter(ParameterSetName="SingleFile")][DateTime]$StartTime = [DateTime]::MinValue,
[Parameter(Mandatory=$false,ParameterSetName="FileDirectory")]
	[Parameter(ParameterSetName="SingleFile")][DateTime]$EndTime = [DateTime]::MaxValue,
[Parameter(Mandatory=$true,ParameterSetName="SingleFile")][string]$PerfmonFile
)

<#
Code Flow 

ExPerfAnalzer of blg files.
-After of the logic is collected that is needed for get-PerformanceDataFromFileLocal, then we run that and save all the data into a variable 
-Return of this variable is going to be in a list of each file. We are treating each file as their own data results for the time being. 
-For each file (item in the list) we are going to create their own PerformanceHealth.ServerPerformanceObject 
-going to past the list of counter names to create the object 
-After object is created, store all the data. Loop till completed 
-Then analyze the data as the previous logic determined 

#>

#Class
Add-Type @"

namespace PerformanceHealth
{
	public class HealthReport
	{
		public string ChangeTime;
		public string Status;
		public string Reason;
		public string DisplayInfo;
		//public System.Array ChangeLog; 
	}

	public class HealthReportEntries
	{
		public string ChangeTime;
		public string Status;
		public string Reason;
		public string DisplayInfo; 
	}

	public class ServerPerformanceObject
	{
		public string ServerName;
		public string FileName; 
		public System.DateTime StartTime;
		public System.DateTime EndTime;
		public AccuracyObject Accuracy;
		public HealthReport HealthReport;
		//public System.Array CounterData;
	}
	
	public class CounterDataObject
	{
		public string ObjectName;
		public string CounterName;
		public string ServerName;
		public string CounterCategory;
		public HealthReport HealthReport;
		public string DetectIssuesType;
		public CounterThresholds Threshold;
		

	}

	/*
	public class CounterSetObject
	{
		public string Name; 
		public string DetectIssuesType;
		public CounterThresholds Threshold;
		public HealthReport HealthReport;
		//public System.Array Instances; 

	}
	*/
	public class CounterThresholds
	{
		public double MaxValue;
		public double WarningValue;
		public double AverageValue; 
	}

	public class InstanceObject
	{
		public string InstanceName;
		public string FullName;
		public string CounterType; 
		public DisplayOptionsObject DisplayOptions;
		public AccuracyObject Accuracy;
		public HealthReport HealthReport;
		public QuickSummaryStatsObject QuickSummaryStats;
		//public System.Array QuickViewValues; 
		//public System.Array RawData;
	}

	public class DisplayOptionsObject 
	{
		public double FormatDivider;
		public string FormatString;
	}

	public class QuickSummaryStatsObject
	{
		public double Avg;
		public double Min;
		public double Max;
		public System.DateTime StartTime;
		public System.DateTime EndTime; 
		public System.TimeSpan Duration; 
	}

	public class QuickViewValuesObject
	{
		public System.DateTime TimeStamp;
		public double CookedValue;
	}

	public class RawDataObject
	{
		public System.DateTime TimeStamp;
		//public UInt64 TimeBase; 
		//public UInt64 RawValue;
		//public UInt64 SecondValue;
		public double CookedValue; 
	}

	public class AccuracyObject
	{
		public double Percentage;
		public int SumDatPoints;
		public int EstimatedDataPoints; 
	}

}

"@ 

<#
Main Object class 

[array]aMainObject
	[ServerPerformanceObject]
		[string]ServerName
		[string]FileName
		[DateTime]StartTime
		[DateTime]EndTime
		[AccuracyObject]Accuracy
			[double]Percentage
			[int]SumDataPoints
			[int]EstimatedDataPoints		
		[HealthReport]
			[string/enum]Status
			[string]ChangeTime
			[string]Reason
			[string]DisplayInfo
			[Array]ChangeLog
				[HealthReportEntries]
					[string]ChangeTime
					[string/enum]Status
					[string]Reason
					[string]DisplayInfo
		[array]CounterData
				[CounterDataObject]
					[string]ObjectName
					[string]CounterName
					[string]ServerName
					[string]CounterCategory
					[HealthReport]
					[CounterThresholds]Threshold
						[double]MaxValue
						[double]WarningValue
						[double]AverageValue
					[string]DetectIssuesType
					[Array]Instances
						[InstanceObject]
							[string]InstanceName
							[string]FullName
							[string]CounterType
							[AccuracyObject]Accuracy
							[DisplayOptions]
								[double]FormatDivider
								[string]FormatString
							[HealthReport]
							[QuickSummaryStats]
								[double]Avg
								[double]Min
								[double]Max
								[DateTime]StartTime
								[DateTime]EndTime
								[TimeSpan]Duration
							[Array]QuickViewValues
								[DateTime]TimeStamp
								[double]CookedValue
							[Array]RawData
								[DateTime]TimeStamp
								[UInt64]TimeBase
								[UInt64]RawValue
								[UInt64]SecondValue
								[Double]CookedValue

#>


<#
Format of the xml counters 
<Counter Name = "">
	<Category></Category>
	<CounterSetName></CounterSetName>
	<CounterName></CounterName>
	<DisplayOptions>
		<FormatDivider></FormatDivider>
		<FormatString></FormatString>
	</DisplayOptions>
	<Threshold>
		<Average></Average>
		<Maxvalue></Maxvalue>
		<WarningValue></WarningValue>
	</Threshold>
	<MonitorChecks>
		<Main></Main>
	</MonitorChecks>
</Counter>

<Counter Name = "\Processor(_Total)\% Processor Time">
	<Category>Processor</Category>
	<CounterSetName>Processor</CounterSetName>
	<CounterName>% Processor Time</CounterName>
	<DisplayOptions>
		<FormatDivider>100</FormatDivider>
		<FormatString>{0:p1}</FormatString>
	</DisplayOptions>
	<Threshold>
		<Average>75</Average>
		<Maxvalue>95</Maxvalue>
		<WarningValue>85</WarningValue>
	</Threshold>
	<MonitorChecks>
		<Main>NormalGreaterThanThresholdCheck</Main>
	</MonitorChecks>
</Counter>
<Counter Name = "\System\Processor Queue Length">
	<Category>Processor</Category>
	<CounterSetName>System</CounterSetName>
	<CounterName>Processor Queue Length</CounterName>
	<DisplayOptions>
		<FormatDivider>1</FormatDivider>
		<FormatString>{0:N0}</FormatString>
	</DisplayOptions>
	<Threshold>
		<Average>2</Average>
		<Maxvalue>200</Maxvalue>
		<WarningValue>120</WarningValue>
	</Threshold>
	<MonitorChecks>
		<Main>NormalGreaterThanThresholdCheck</Main>
	</MonitorChecks>
</Counter>
<Counter Name = "\System\Context Switches/sec">
	<Category>Processor</Category>
	<CounterSetName>System</CounterSetName>
	<CounterName>Context Switches/sec</CounterName>
	<DisplayOptions>
		<FormatDivider>1</FormatDivider>
		<FormatString>{0:N0}</FormatString>
	</DisplayOptions>
	<Threshold>
		<Average>90000</Average>
		<Maxvalue>200000</Maxvalue>
		<WarningValue>150000</WarningValue>
	</Threshold>
	<MonitorChecks>
		<Main>NormalGreaterThanThresholdCheck</Main>
	</MonitorChecks>
</Counter>
<Counter Name = "\Memory\Available MBytes">
	<Category>Memory</Category>
	<CounterSetName>Memory</CounterSetName>
	<CounterName>Available MBytes</CounterName>
	<DisplayOptions>
		<FormatDivider>1048576</FormatDivider>
		<FormatString>{0:N0}MB</FormatString>
	</DisplayOptions>
	<Threshold>
		<Average>1536</Average>
		<Maxvalue>512</Maxvalue>
		<WarningValue>1024</WarningValue>
	</Threshold>
	<MonitorChecks>
		<Main>NormalLessThanThresholdCheck</Main>
	</MonitorChecks>
</Counter>

#>

$xmlCountersToAnalyze = [xml]@"
<Counters>
<Counter Name = "\LogicalDisk(*)\Avg. Disk sec/Read">
	<Category>Disk</Category>
	<CounterSetName>LogicalDisk</CounterSetName>
	<CounterName>Avg. Disk sec/Read</CounterName>
	<DisplayOptions>
		<FormatDivider>0.001</FormatDivider>
		<FormatString>{0:N1}ms</FormatString>
	</DisplayOptions>
	<Threshold>
		<Average>0.020</Average>
		<Maxvalue>0.001</Maxvalue>
		<WarningValue>0.001</WarningValue>
	</Threshold>
	<MonitorChecks>
		<Main>DeepGreaterThanThresholdCheck</Main>
	</MonitorChecks>
</Counter>
<Counter Name = "\LogicalDisk(*)\Avg. Disk sec/Write">
	<Category>Disk</Category>
	<CounterSetName>LogicalDisk</CounterSetName>
	<CounterName>Avg. Disk sec/Write</CounterName>
	<DisplayOptions>
		<FormatDivider>0.001</FormatDivider>
		<FormatString>{0:N1}ms</FormatString>
	</DisplayOptions>
	<Threshold>
		<Average>0.020</Average>
		<Maxvalue>0.001</Maxvalue>
		<WarningValue>0.001</WarningValue>
	</Threshold>
	<MonitorChecks>
		<Main>DeepGreaterThanThresholdCheck</Main>
	</MonitorChecks>
</Counter>
<Counter Name = "\LogicalDisk(*)\Avg. Disk sec/Transfer">
	<Category>Disk</Category>
	<CounterSetName>LogicalDisk</CounterSetName>
	<CounterName>Avg. Disk sec/Transfer</CounterName>
	<DisplayOptions>
		<FormatDivider>0.001</FormatDivider>
		<FormatString>{0:N1}ms</FormatString>
	</DisplayOptions>
	<Threshold>
		<Average>0</Average>
		<Maxvalue>0</Maxvalue>
		<WarningValue>0</WarningValue>
	</Threshold>
	<MonitorChecks>
		<Main>None</Main>
	</MonitorChecks>
</Counter>
<Counter Name = "\LogicalDisk(*)\Disk Transfers/sec">
	<Category>Disk</Category>
	<CounterSetName>LogicalDisk</CounterSetName>
	<CounterName>Disk Transfers/sec</CounterName>
	<DisplayOptions>
		<FormatDivider>1</FormatDivider>
		<FormatString>{0:N1}</FormatString>
	</DisplayOptions>
	<Threshold>
		<Average>0</Average>
		<Maxvalue>0</Maxvalue>
		<WarningValue>0</WarningValue>
	</Threshold>
	<MonitorChecks>
		<Main>None</Main>
	</MonitorChecks>
</Counter>
<Counter Name = "\LogicalDisk(*)\Disk Bytes/sec">
	<Category>Disk</Category>
	<CounterSetName>LogicalDisk</CounterSetName>
	<CounterName>Disk Bytes/sec</CounterName>
	<DisplayOptions>
		<FormatDivider>1024</FormatDivider>
		<FormatString>{0:N0}KB</FormatString>
	</DisplayOptions>
	<Threshold>
		<Average>0</Average>
		<Maxvalue>0</Maxvalue>
		<WarningValue>0</WarningValue>
	</Threshold>
	<MonitorChecks>
		<Main>None</Main>
	</MonitorChecks>
</Counter>
<Counter Name = "\LogicalDisk(*)\Avg. Disk Queue Length">
	<Category>Disk</Category>
	<CounterSetName>LogickDisk</CounterSetName>
	<CounterName>Avg. Disk Queue Length</CounterName>
	<DisplayOptions>
		<FormatDivider>1</FormatDivider>
		<FormatString>{0:N2}</FormatString>
	</DisplayOptions>
	<Threshold>
		<Average>0</Average>
		<Maxvalue>0</Maxvalue>
		<WarningValue>0</WarningValue>
	</Threshold>
	<MonitorChecks>
		<Main>None</Main>
	</MonitorChecks>
</Counter>
<Counter Name = "\LogicalDisk(*)\% Idle Time">
	<Category>Disk</Category>
	<CounterSetName>LogicalDisk</CounterSetName>
	<CounterName>% Idle Time</CounterName>
	<DisplayOptions>
		<FormatDivider>100</FormatDivider>
		<FormatString>{0:p1}</FormatString>
	</DisplayOptions>
	<Threshold>
		<Average>0</Average>
		<Maxvalue>0</Maxvalue>
		<WarningValue>0</WarningValue>
	</Threshold>
	<MonitorChecks>
		<Main>None</Main>
	</MonitorChecks>
</Counter>
</Counters>
"@

#"\\*\LogicalDisk(*)\Avg. Disk sec/Read","\\*\LogicalDisk(*)\Avg. Disk sec/Write","\\*\LogicalDisk(*)\Avg. Disk sec/Transfer","\\*\LogicalDisk(*)\Disk Transfers/sec","\\*\LogicalDisk(*)\Disk Bytes/sec","\\*\LogicalDisk(*)\Avg. Disk Queue Length","\\*\LogicalDisk(*)\% Idle Time","\\*\Processor(_Total)\% Processor Time","\\*\System\Processor Queue Length","\\*\System\Context Switches/sec","\\*\Memory\Available MBytes","\\*\Netlogon(*)\*","\\*\Processor Information(*)\% of Maximum Frequency"
#"\LogicalDisk(*)\Avg. Disk sec/Read","\LogicalDisk(*)\Avg. Disk sec/Write","\LogicalDisk(*)\Avg. Disk sec/Transfer","\LogicalDisk(*)\Disk Transfers/sec","\LogicalDisk(*)\Disk Bytes/sec","\LogicalDisk(*)\Avg. Disk Queue Length","\LogicalDisk(*)\% Idle Time","\Processor(_Total)\% Processor Time","\System\Processor Queue Length","\System\Context Switches/sec","\Memory\Available MBytes","\Netlogon(*)\*","\Processor Information(*)\% of Maximum Frequency"
Function Get-PerformanceDataFromFileLocal {
	[CmdletBinding()]
	[OutputType([System.Collections.Generic.List[System.Object]])]
	param(
		[parameter(mandatory=$true)][string[]]$FullPath,
		[parameter(mandatory=$true)][string[]]$Counters,
		[parameter(mandatory=$true)][Int64]$MaxSamples,
		[parameter(mandatory=$true)][DateTime]$StartTime,
		[parameter(mandatory=$true)][DateTime]$EndTime
	)

	Write-Verbose ("[{0}]: Passed {1} files." -f [DateTime]::Now, $FullPath.Count)
	[System.Collections.Generic.List[System.Object]]$aCounterSamples = New-Object System.Collections.Generic.List[System.Object]
	if($FullPath.Count -gt 0)
	{
		
		foreach($file in $FullPath)
		{
			$importParams = @{
				Path = $file
				StartTime = $StartTime
				EndTime = $EndTime
				MaxSamples = $MaxSamples
				ErrorAction = "SilentlyContinue"
				Verbose = $false
			}

			if($Counters -ne $null -and $Counters.Count -gt 0)
			{
				$importParams.Add("Counter", $Counters)
			}

			Write-Verbose ("[{0}]: Importing counters from file. File Size: {1}MB. File Name: {2}." -f [DateTime]::Now, ((Get-Item $file).Length / 1024 / 1024), $file)
			$importCounterSamples = (Import-Counter @importParams).CounterSamples
			$importCounterSamples | Add-Member -Name FileName -Value $file -MemberType NoteProperty
			Write-Verbose ("[{0}]: Finished Importing counters from file. File Name: {1}" -f [DateTime]::Now, $file)
			$aCounterSamples.Add($importCounterSamples)
		}

	}
	#This returns an Array that contains the results per file in their own array. The function after this needs to be able to pull out and review the data as needed. 
	return $aCounterSamples

}


Function Convert-PerformanceCounterSampleObjectToServerPerformanceObject {
[CmdletBinding()]
param(
	[Parameter(Mandatory=$true)][Array]$RawData,
	[Parameter(Mandatory=$false)][System.Collections.Generic.List[System.Object]]$AddToThisObject
)

	Function Get-FullCounterNameObject
	{
		param(
			[Parameter(Mandatory=$true)][string]$FullCounterSamplePath 
		)
		#\\adt-e2k13aio1\logicaldisk(harddiskvolume1)\avg. disk sec/read
		$iEndOfServerIndex = $FullCounterSamplePath.IndexOf("\",2) #\\adt-e2k13aio1 <> \logicaldisk(harddiskvolume1)\avg. disk sec/read
		$iStartOfCounterIndex = $FullCounterSamplePath.LastIndexOf("\") + 1#\\adt-e2k13aio1\logicaldisk(harddiskvolume1)\ <> avg. disk sec/read
		$iEndOfCounterObjectIndex = $FullCounterSamplePath.IndexOf("(")
		if($iEndOfCounterObjectIndex -eq -1){$iEndOfCounterObjectIndex = $FullCounterSamplePath.LastIndexOf("\")}
		$obj = New-Object -TypeName PSObject 
		$obj | Add-Member -Name ServerName -MemberType NoteProperty -Value ($FullCounterSamplePath.Substring(2,($iEndOfServerIndex - 2)))
		$obj | Add-Member -Name ObjectName -MemberType NoteProperty -Value   ($FullCounterSamplePath.Substring($iEndOfServerIndex + 1, $iEndOfCounterObjectIndex - $iEndOfServerIndex - 1 ))
		$obj | Add-Member -Name CounterName -MemberType NoteProperty -Value ($FullCounterSamplePath.Substring($FullCounterSamplePath.LastIndexOf("\") + 1))
	
		return $obj
	}

	Function Build-ServerPerformanceObject_Instance {
	param(
		[Parameter(Mandatory=$true)][object]$PerformanceCounterSample 
	)
		[PerformanceHealth.InstanceObject]$instanceDataPerfObject = New-Object -TypeName PerformanceHealth.InstanceObject
		$instanceDataPerfObject.InstanceName = $PerformanceCounterSample.InstanceName 
		$instanceDataPerfObject.FullName = $PerformanceCounterSample.Path 
		$instanceDataPerfObject.CounterType = $PerformanceCounterSample.CounterType 
		$instanceDataPerfObject.Accuracy = New-Object -TypeName PerformanceHealth.AccuracyObject 
		$instanceDataPerfObject.DisplayOptions = New-Object -TypeName PerformanceHealth.DisplayOptionsObject
		$instanceDataPerfObject.HealthReport = New-Object -TypeName PerformanceHealth.HealthReport
		$instanceDataPerfObject.QuickSummaryStats = New-Object -TypeName PerformanceHealth.QuickSummaryStatsObject 
		#$tquickViewValues = New-Object -TypeName PerformanceHealth.QuickViewValuesObject
		#$tRawData = New-Object -TypeName PerformanceHealth.RawDataObject
		#[System.Collections.Generic.List[System.Object]]$tqvv = New-Object -TypeName System.Collections.Generic.List[System.Object]
		#[System.Collections.Generic.List[System.Object]]$trd = New-Object -TypeName System.Collections.Generic.List[System.Object]
		#$tqvv.Add($tquickViewValues)
		#$trd.Add($tRawData)
		#$instanceDataPerfObject | Add-Member -Name QuickViewValues -MemberType NoteProperty -Value $tqvv
		#$instanceDataPerfObject | Add-Member -Name RawData -MemberType NoteProperty -Value $trd 
		return $instanceDataPerfObject
	}

	Function Build-ServerPerformanceObject_CounterData {
	param(
		[Parameter(Mandatory=$true)][object]$PerformanceCounterSample 
	)
		$counterNameObject = Get-FullCounterNameObject -FullCounterSamplePath $PerformanceCounterSample.Path 
		[PerformanceHealth.CounterDataObject]$counterDataPerfObject = New-Object PerformanceHealth.CounterDataObject
		$counterDataPerfObject.ObjectName = $counterNameObject.ObjectName
		$counterDataPerfObject.CounterName = $counterNameObject.CounterName
		$counterDataPerfObject.ServerName = $counterNameObject.ServerName
		$counterDataPerfObject.CounterCategory = [String]::Empty
		$counterDataPerfObject.HealthReport = New-Object PerformanceHealth.HealthReport 
		$counterDataPerfObject.DetectIssuesType = [string]::Empty
		$counterDataPerfObject.Threshold = New-Object PerformanceHealth.CounterThresholds
		[System.Collections.Generic.List[System.Object]]$instanceData = New-Object System.Collections.Generic.List[System.Object]
		$instanceDataObject = Build-ServerPerformanceObject_Instance -PerformanceCounterSample $PerformanceCounterSample
		$instanceData.Add($instanceDataObject)
		$counterDataPerfObject | Add-Member -Name Instances -MemberType NoteProperty -Value $instanceData 
		return $counterDataPerfObject
	}

	Function Build-ServerPerformanceObject_Server {
	param(
		[Parameter(Mandatory=$true)][object]$PerformanceCounterSample
	)
		$counterNameObject = Get-FullCounterNameObject -FullCounterSamplePath $PerformanceCounterSample.Path 
		[PerformanceHealth.ServerPerformanceObject]$serverPerfObject = New-Object -TypeName PerformanceHealth.ServerPerformanceObject
		$serverPerfObject.FileName = $PerformanceCounterSample.FileName 
		$serverPerfObject.ServerName = $counterNameObject.ServerName
		$serverPerfObject.Accuracy = New-Object -TypeName PerformanceHealth.AccuracyObject 
		$serverPerfObject.HealthReport = New-Object -TypeName PerformanceHealth.HealthReport 
		$serverPerfObject.StartTime = [System.DateTime]::MinValue
		$serverPerfObject.EndTime = [System.DateTime]::MaxValue
		[System.Collections.Generic.List[System.Object]]$counterData = New-Object System.Collections.Generic.List[System.Object]
		$counterDataObject = Build-ServerPerformanceObject_CounterData -PerformanceCounterSample $PerformanceCounterSample 
		$counterData.Add($counterDataObject)
		$serverPerfObject | Add-Member -Name CounterData -MemberType NoteProperty -Value $counterData
		return $serverPerfObject
	}

	Function Add-ServerPerformanceObject_ValueTemp {
	[CmdletBinding()]
	[OutputType([System.Collections.Generic.List[System.Object]])]
	param(
		[Parameter(Mandatory=$true)][array]$CounterSampleData
	)
		Write-Verbose("[{0}] : Calling Add-ServerPerformanceObject_Value" -f [system.dateTime]::Now)
		$values = New-Object System.Collections.Generic.List[System.Object]
		$measure_loop = Measure-Command {
			foreach($csd in $CounterSampleData)
			{
				$values.Add($csd)
			}
		}
		Write-Verbose("[{0}] : Took {1} seconds to process {2} items" -f [datetime]::Now, $measure_loop.Seconds, $CounterSampleData.Count)
		return $values
	}

	Function Add-ServerPerformanceObject_InstanceValues {
	[CmdletBinding()]
	param(
		[Parameter(Mandatory=$true)][array]$PerformanceCounterSamplesGroup,
		[Parameter(Mandatory=$true)][object]$InstanceDataObject 
	)

		foreach($pcsg in $PerformanceCounterSamplesGroup)
		{
			$tRawData = New-Object -TypeName PerformanceHealth.RawDataObject
			$tRawData.TimeStamp = $pcsg.TimeStamp
			$tRawData.CookedValue = $pcsg.CookedValue 
			$tRawData | Add-Member -Name TimeBase -MemberType NoteProperty $pcsg.TimeBase 
			$tRawData | Add-Member -Name RawValue -MemberType NoteProperty $pcsg.RawValue
			$tRawData | Add-Member -Name SecondValue -MemberType NoteProperty $pcsg.SecondValue
			$InstanceDataObject.RawData.Add($tRawData)
		}
		
		return $InstanceDataObject
	}
##############################################################
	#Raw data is going to be in this style of format 
	<#
FileName         : C:\location\ADT-E2K13AIO1_Full_000001.blg
Path             : \\adt-e2k13aio1\logicaldisk(harddiskvolume1)\avg. disk sec/read
InstanceName     : harddiskvolume1
CookedValue      : 0
RawValue         : 0
SecondValue      : 0
MultipleCount    : 0
CounterType      : AverageTimer32
Timestamp        : 12/1/2015 7:10:52 AM
Timestamp100NSec : 130934274521380000
Status           : 0
DefaultScale     : 3
TimeBase         : 10000000
	#>
	#So the first thing we should is group the data by the path 
	$groupPathData = $RawData | group path 
	foreach($gpd in $groupPathData)
	{
		$gpd = $gpd.Group | select -Skip 1 
		$counterNameObject = Get-FullCounterNameObject -FullCounterSamplePath $gpd[0].path 
		#need to find the index of the AddToThisObject for the server 
		$index_Server = [int]::MinValue
		$tick = 0
		foreach($server in $AddToThisObject)
		{
			if($counterNameObject.ServerName -eq $server.ServerName)
			{
				$index_Server = $tick
				break;
			}
			$tick++
		}
		#if we don't have a server index of this, we need to move on and create one 
		if($index_Server -eq [int]::MinValue)
		{
			Write-Verbose("Detected new server to add to the main object. Server: {0}" -f $counterNameObject.ServerName)
			$AddToThisObject.Add((Build-ServerPerformanceObject_Server -PerformanceCounterSample $gpd[0]))
			$index_Server = $AddToThisObject.Count - 1 # this should be correct to determine the index, otherwise i will need to create a function of the above loop 
			
			$AddToThisObject[$index_Server].CounterData[0].Instances[0] = Add-ServerPerformanceObject_ValueTemp -CounterSampleData $gpd
			
		}
		else
		{
			##### need to start working at this point need to start adding other counters into the main array 
			$index_CounterData = [int]::MinValue
			$tick = 0 
			foreach($counterData in $AddToThisObject[$index_Server].CounterData)
			{
				if(($counterNameObject.ObjectName -eq $counterData.ObjectName) -and ($counterNameObject.CounterName -eq $counterData.CounterName))
				{
					$index_CounterData = $tick
					break; 
				}
				$tick++ 
			}
			if($index_CounterData -eq [int]::MinValue)
			{
				#We have a different counter and we need to create one
				Write-Verbose("Creating a new counter Server: {0} Object: {1} Counter: {2} " -f $counterNameObject.ServerName, $counterNameObject.ObjectName, $counterNameObject.CounterName)
				$counterDataObject = Build-ServerPerformanceObject_CounterData -PerformanceCounterSample $gpd[0]
				$AddToThisObject[$index_Server].CounterData.Add($counterDataObject)
				$index_CounterData = $AddToThisObject[$index_Server].CounterData.Count - 1 
				
				$AddToThisObject[$index_Server].CounterData[$index_CounterData].Instances[0] = Add-ServerPerformanceObject_ValueTemp -CounterSampleData $gpd
				
			}

			#we are looking at the instances  
			else
			{
				$index_InstanceData = [int]::MinValue
				$tick = 0 
				foreach($instanceData in $AddToThisObject[$index_Server].CounterData[$index_CounterData].Instances)
				{
					if($instanceData.InstanceName -eq $gpd[0].InstanceName)
					{
						$index_InstanceData = $tick
						break;
					}
					$tick++
				}

				if($index_InstanceData -eq [int]::MinValue)
				{
					Write-Verbose("Creating a new instance [{0}] for Server: {1} Object: {2} Counter: {3}" -f $gpd[0].InstanceName, $counterNameObject.ServerName,$counterNameObject.ObjectName,$counterNameObject.CounterName)
					#we don't have this index so we need to build it first 
					$instanceDatObject = Build-ServerPerformanceObject_Instance -PerformanceCounterSample $gpd[0]
					$AddToThisObject[$index_Server].CounterData[$index_CounterData].Instances.Add($instanceDatObject)
					$index_InstanceData = $AddToThisObject[$index_Server].CounterData[$index_CounterData].Instances.Count - 1 
				}

				$AddToThisObject[$index_Server].CounterData[$index_CounterData].Instances[$index_InstanceData] = Add-ServerPerformanceObject_ValueTemp -CounterSampleData $gpd
			}

		}

	}
	
	Return $AddToThisObject 
}

Function Add-CountersToAnalyzeToObject {
[CmdletBinding()]
param(
[Parameter(Mandatory=$true)][xml]$XmlList,
[Parameter(Mandatory=$true)][object]$mainObject
)
	Write-Verbose("Calling Add-CountersToAnalyzeToObject")

	foreach($xmlCounter in $XmlList.Counters.Counter)
	{
		#for each server loop
		foreach($serverObject in $mainObject)
		{
			
			foreach($counterDataObject in $serverObject.CounterData)
			{

				if($counterDataObject.ObjectName -like ("*" + $xmlCounter.CounterSetName) -and
					$counterDataObject.CounterName -eq $xmlCounter.CounterName)
				{

					$counterDataObject.DetectIssuesType = $xmlCounter.MonitorChecks.Main 
					$counterDataObject.Threshold.MaxValue = $xmlCounter.Threshold.MaxValue
					$counterDataObject.Threshold.WarningValue = $xmlCounter.Threshold.WarningValue 
					$counterDataObject.Threshold.AverageValue = $xmlCounter.Threshold.Average
					$counterDataObject.CounterCategory = $xmlCounter.Category
					foreach($instanceObjects in $counterDataObject.Instances)
					{
						$instanceObjects.DisplayOptions.FormatDivider = $xmlCounter.DisplayOptions.FormatDivider
						$instanceObjects.DisplayOptions.FormatString = $xmlCounter.DisplayOptions.FormatString
					}
					
					break;
				}
			}
		}
	}
	return $mainObject
}


Function Analyze-DataOfObject {
param(
[Parameter(Mandatory=$true)][object]$mainObject 
)
	Write-Verbose("Calling Analyze-DataOfObject")
	foreach($serverObj in $mainObject)
	{
		foreach($counterDataObj in $serverObj.CounterData)
		{
			foreach($instanceObj in $counterDataObj.Instances)
			{
				$bTime = $false
				if($instanceObj.RawData[0].TimeStamp -eq [System.DateTime]::MinValue)
				{
					$bTime = $true
					$startTime = $instanceObj.RawData[1].TimeStamp 
					$skip = 2
				}
				else
				{
					$startTime = $instanceObj.RawData[0].TimeStamp
					$skip = 1
				}
				$measured = $instanceObj.RawData | Select-Object -Skip $skip | Measure-Object -Property CookedValue -Maximum -Minimum -Average

				$instanceObj.QuickSummaryStats.Min = $measured.Minimum
				$instanceObj.QuickSummaryStats.Max = $measured.Maximum
				$instanceObj.QuickSummaryStats.StartTime = $startTime
				$instanceObj.QuickSummaryStats.EndTime = $instanceObj.RawData[-1].TimeStamp
				$instanceObj.QuickSummaryStats.Duration = New-TimeSpan $($instanceObj.QuickSummaryStats.StartTime) $($instanceObj.QuickSummaryStats.EndTime)
				#Calculate Averages 
				#Average calculation for Average counters taken from these references:
				#https://msdn.microsoft.com/en-us/library/ms804010.aspx
				#https://blogs.msdn.microsoft.com/ntdebugging/2013/09/30/performance-monitor-averages-the-right-way-and-the-wrong-way/

				if($instanceObj.CounterType -like "AverageTimer*")
				{
					$index = 0 
					if($bTime)
					{
						$index = 1
					}
					$numTicksDiff = $instanceObj.RawData[-1].RawValue - $instanceObj.RawData[$index].RawValue 
					$frequency = $instanceObj.RawData[-1].TimeBase
					$numOpsDif = $instanceObj.RawData[-1].SecondValue - $instanceObj.RawData[$index].SecondValue 
					if($frequency -ne 0 -and $numOpsDif -ne 0 -and $numTicksDiff -ne 0)
					{
						$instanceObj.QuickSummaryStats.Avg = ($numTicksDiff / $frequency) / $numOpsDif
					}

				}
				else
				{
					$instanceObj.QuickSummaryStats.Avg = $measured.Average
				}

			}
		}
	}

	return $mainObject
}

Function Output-QuickSummaryDetails {
param(
[parameter(Mandatory=$true)][object]$ServerObject,
[parameter(Mandatory=$false)][string]$FullOutPutLocation
)
	Write-Verbose("Calling Output-QuickSummaryDetails")

	$Script:displayString = [string]::Empty
	$strLength_detail = 48 
	$strLength_columnWidth = 12
	Function AddLine {
	param(
	[Parameter(Mandatory=$true)][string]$New_Line
	)
		$Script:displayString += $New_Line + "`r`n"
	}




	AddLine("Exchange Perfmon Log Summary")
	AddLine("============================")
	AddLine("{0,-18} : {1}" -f "Server", $ServerObject.ServerName )
	AddLine("{0,-18} : {1}" -f "Start Time", $ServerObject.StartTime)
	AddLine("{0,-18} : {1}" -f "End Time",$ServerObject.EndTime)
	AddLine("{0,-18} : {1}" -f "Duration",(New-TimeSpan $($ServerObject.StartTime) $($ServerObject.EndTime)).ToString())
	#Need to add Sample Interval & Accuracy 

	$groupCounterCategory = $ServerObject.CounterData | Group-Object CounterCategory | ?{$_.Name -ne ""} | Sort-Object Name
	$groupCounterCategoryN = $ServerObject.CounterData | Group-Object CounterCategory | ?{$_.Name -eq ""}

	foreach($gcategory in $groupCounterCategory)
	{
		AddLine(" ")
		AddLine("{0,-$strLength_detail} {1,$strLength_columnWidth} {2,$strLength_columnWidth} {3,$strLength_columnWidth}" -f $gcategory.Name, "Min","Max","Avg")
		AddLine("==========================================================================================")

		foreach($counterObject in $gcategory.Group)
		{
			if($counterObject.Instances[0].InstanceName -eq "")
			{
				AddLine("{0,-$strLength_detail} {1,$strLength_columnWidth} {2,$strLength_columnWidth} {3,$strLength_columnWidth}" -f ("\" + $counterObject.ObjectName + "\" + $counterObject.CounterName), 
					($counterObject.Instances[0].DisplayOptions.FormatString -f ($counterObject.Instances[0].QuickSummaryStats.Min / $counterObject.Instances[0].DisplayOptions.FormatDivider)),
					($counterObject.Instances[0].DisplayOptions.FormatString -f ($counterObject.Instances[0].QuickSummaryStats.Max / $counterObject.Instances[0].DisplayOptions.FormatDivider)),
					($counterObject.Instances[0].DisplayOptions.FormatString -f ($counterObject.Instances[0].QuickSummaryStats.Avg / $counterObject.Instances[0].DisplayOptions.FormatDivider)))
			}
			else
			{
				AddLine("{0,-$($strLength_detail+2)}" -f ("\" + $counterObject.ObjectName + "(*)\" + $counterObject.CounterName))
				foreach($instanceObject in $counterObject.Instances)
				{
					AddLine("{0,-$strLength_detail} {1,$strLength_columnWidth} {2,$strLength_columnWidth} {3,$strLength_columnWidth}" -f $instanceObject.InstanceName,
						($instanceObject.DisplayOptions.FormatString -f ($instanceObject.QuickSummaryStats.Min / $instanceObject.DisplayOptions.FormatDivider)),
						($instanceObject.DisplayOptions.FormatString -f ($instanceObject.QuickSummaryStats.Max / $instanceObject.DisplayOptions.FormatDivider)),
						($instanceObject.DisplayOptions.FormatString -f ($instanceObject.QuickSummaryStats.Avg / $instanceObject.DisplayOptions.FormatDivider))
					)
				}
			}
		}

	}

	foreach($gcategory in $groupCounterCategoryN.Group)
	{
		AddLine(" ")
		AddLine("{0,-$strLength_detail} {1,$strLength_columnWidth} {2,$strLength_columnWidth} {3,$strLength_columnWidth}" -f ($gcategory.ObjectName + " - " + $gcategory.CounterName), "Min","Max","Avg")
		AddLine("==========================================================================================")

		Foreach($instanceObject in $gcategory.Instances)
		{
			AddLine("{0,-$strLength_detail} {1,$strLength_columnWidth} {2,$strLength_columnWidth} {3,$strLength_columnWidth}" -f $instanceObject.InstanceName,
				$instanceObject.QuickSummaryStats.Min,
				$instanceObject.QuickSummaryStats.Max,
				$instanceObject.QuickSummaryStats.Avg
			)
		}
	}

	AddLine(" ")
	AddLine(" ")
	AddLine("Analysis Stats")
	AddLine("================")
	AddLine("{0,-24} : {1}" -f "Report Generated by", "ExPerfAnalyzer.ps1 v1.0")
	AddLine("{0,-24} : {1}" -f "Written by", "Matthew Huynh (mahuynh@microsoft.com) & David Paulson (dpaul@microsoft.com")

			
		
		
	$Script:displayString
}


Function Get-CountersFromXml {
param(
[Parameter(Mandatory=$true)][xml]$xmlCounters,
[Parameter(Mandatory=$false)][bool]$IncludeWildForServers = $false
)
	$aCounters = New-Object System.Collections.Generic.List[System.Object]
	if($IncludeWildForServers)
	{
		foreach($counter in $xmlCounters.Counters.Counter)
		{
			$aCounters.Add("\\*" + $counter.Name)
		}
	}
	else
	{
		foreach($counter in $xmlCounters.Counters.Counter)
		{
			$aCounters.Add($counter.Name)
		}
	}

	return $aCounters
}

Function Main {

	$script:processStartTime = [System.DateTime]::Now

	#determine the logic we want out of the script 
	Switch($PSCmdlet.ParameterSetName)
	{
		"FileDirectory"
		{
			Write-Verbose("File Directory Option detected")
			if(-not (Test-Path $PerfmonFileDirectory))
			{
				Write-Host("Path {0} doesn't appear to valid. Stopping the script" -f $PerfmonFileDirectory) -ForegroundColor Red
				exit
			}
			
			$AllFiles = (Get-ChildItem $PerfmonFileDirectory | ?{$_.Name.EndsWith(".blg")}).VersionInfo.FileName 
			
			
			switch($AllFiles.Count)
			{
				0
					{
						Write-Host("Doesn't appear to be any blg files in the path {0}. Stopping the script" -f $PerfmonFileDirectory)
						exit
					}
				#Need to use different logic if only 1 file was detected 
				1
					{
						Write-Verbose("We have detected {0} files that we can use in the directory {1}" -f ($AllFiles.count), $PerfmonFileDirectory)
						$rawLocalData = Get-PerformanceDataFromFileLocal -FullPath $AllFiles -Counters (Get-CountersFromXml -xmlCounters $xmlCountersToAnalyze -IncludeWildForServers $true) -MaxSamples $MaxSamples -StartTime $StartTime -EndTime $EndTime
						$mainObject = Convert-PerformanceCounterSampleObjectToServerPerformanceObject -RawData $rawLocalData -AddToThisObject (New-Object System.Collections.Generic.List[System.Object])
						$mainObject = Add-CountersToAnalyzeToObject -XmlList $xmlCountersToAnalyze -mainObject $mainObject
						$mainObject = Analyze-DataOfObject -mainObject $mainObject
						$displayResults = Output-QuickSummaryDetails -ServerObject $mainObject 
						$displayResults
						break
					}
				#else there are more files 
				default
					{
						Write-Verbose("We have detected {0} files that we can use in the directory {1}" -f ($AllFiles.count), $PerfmonFileDirectory)
						break
					}
			}
			



			break;
		}
		"SingleFile"
		{
			if((-not (Test-Path $PerfmonFile)) -or (-not $PerfmonFile.EndsWith(".blg")))
			{
				Write-Host("File {0} doesn't appear to exist or is a blg files. Stopping the script" -f $PerfmonFile)
				exit
			}
			Write-Verbose("Single File appears to be detected. Running against file {0}." -f $PerfmonFile)
			$rawLocalData = Get-PerformanceDataFromFileLocal -FullPath $PerfmonFile -Counters (Get-CountersFromXml -xmlCounters $xmlCountersToAnalyze -IncludeWildForServers $true) -MaxSamples $MaxSamples -StartTime $StartTime -EndTime $EndTime
			$mainObject = Convert-PerformanceCounterSampleObjectToServerPerformanceObject -RawData $rawLocalData -AddToThisObject (New-Object System.Collections.Generic.List[System.Object])
			Write-Debug ("debug entry")
			$mainObject = Add-CountersToAnalyzeToObject -XmlList $xmlCountersToAnalyze -mainObject $mainObject
			$mainObject = Analyze-DataOfObject -mainObject $mainObject
			$displayResults = Output-QuickSummaryDetails -ServerObject $mainObject 
			$displayResults 
			break;
		}

	}

	
	
}


$ptime = Measure-Command{ Main }
Write-Host("Script took {0} seconds to complete" -f $ptime.TotalSeconds)