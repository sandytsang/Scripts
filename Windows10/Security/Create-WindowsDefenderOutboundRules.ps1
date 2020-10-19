<#
.SYNOPSIS
    This create Outboud firewall rules for Windows Defender Updates

.DESCRIPTION
    This script will automatic create outbound firewall rules and schedule task for Windows Defender Updates

.NOTES
    File name: Create-WindowsDefenderOutboundRules.ps1
    AUTHOR: Sandy Zeng
    Created:  2020-10-18
    COPYRIGHT:
    Sandy Zeng / https://www.sandyzeng.com
    Licensed under the MIT license.
    Please credit me if you fint this script useful and do some cool things with it.

.VERSION HISTORY:
    1.0.0 - (2020-10-18) Script created
#>

#Functions
function Write-LogEntry {
	param (
		[parameter(Mandatory = $true, HelpMessage = "Value added to the log file.")]
		[ValidateNotNullOrEmpty()]
		[string]$Value,

		[parameter(Mandatory = $true, HelpMessage = "Severity for the log entry. 1 for Informational, 2 for Warning and 3 for Error.")]
		[ValidateNotNullOrEmpty()]
		[ValidateSet("1", "2", "3")]
		[string]$Severity
	)
	# Determine log file location
	$LogFilePath = Join-Path -Path (Join-Path -Path $env:windir -ChildPath "Temp") -ChildPath "Create-WindowsDefenderOutboundRules.log"
		
	# Construct time stamp for log entry
	if (-not(Test-Path -Path 'variable:global:TimezoneBias')) {
		[string]$global:TimezoneBias = [System.TimeZoneInfo]::Local.GetUtcOffset((Get-Date)).TotalMinutes
		if ($TimezoneBias -match "^-") {
			$TimezoneBias = $TimezoneBias.Replace('-', '+')
		}
		else {
			$TimezoneBias = '-' + $TimezoneBias
		}
	}
	$Time = -join @((Get-Date -Format "HH:mm:ss.fff"), $TimezoneBias)
		
	# Construct date for log entry
	$Date = (Get-Date -Format "MM-dd-yyyy")
		
	# Construct context for log entry
	$Context = $([System.Security.Principal.WindowsIdentity]::GetCurrent().Name)
		
	# Construct final log entry
	$LogText = "<![LOG[$($Value)]LOG]!><time=""$($Time)"" date=""$($Date)"" component=""WindowsDefender"" context=""$($Context)"" type=""$($Severity)"" thread=""$($PID)"" file="""">"
		
	# Add value to log file
	try {
		Out-File -InputObject $LogText -Append -NoClobber -Encoding Default -FilePath $LogFilePath -ErrorAction Stop
	}
	catch [System.Exception] {
		Write-Warning -Message "Unable to append log entry to Create-WindowsDefenderOutboundRules.log file. Error message at line $($_.InvocationInfo.ScriptLineNumber): $($_.Exception.Message)"
	}
}

#Enable Core Networking - DNS (UDP-Out) firewall rule
try {
    Write-LogEntry -Value "Enable Core Networking - DNS (UDP-Out) firewall rule" -Severity 1
    Set-NetFirewallRule -DisplayName "Core Networking - DNS (UDP-Out)" -Enabled True -ErrorAction Stop
}
catch {
    Write-LogEntry -Value "Enable Core Networking - DNS (UDP-Out) firewall rule failed" -Severity 3    
    Write-LogEntry -Value "$_.Exception.Message" -Severity 3; exit 1
}

#Create Outbound Firewall rules for MpCmdRun
If (!(Get-NetFirewallRule -DisplayName "Custom - Allow Outbound MpCmdRun" -ErrorAction SilentlyContinue)) {
    Write-LogEntry -Value "Start creating firewall rule 'Custom - Allow Outbound MpCmdRun'" -Severity 1
    try {
        New-NetFirewallRule -DisplayName "Custom - Allow Outbound MpCmdRun" -Direction Outbound -Program "%ProgramFiles%\Windows Defender\MpCmdRun.exe" -Action Allow -Group "Windows Defender" -Verbose
        Write-LogEntry -Value "Firewall rule 'Custom - Allow Outbound MpCmdRun' is created." -Severity 1
    }
    catch {
        Write-LogEntry -Value "Create firewall rule 'Custom - Allow Outbound MpCmdRun' failed" -Severity 1       
        Write-LogEntry -Value "$_.Exception.Message" -Severity 3; exit 1
    }
}
else {
    Write-LogEntry -Value "Firewall rule name 'Custom - Allow Outbound MpCmdRun' is already exists." -Severity 2
    Write-LogEntry -Value "Please change firewall rule name and try again." -Severity 2
    exit 1
} 

#Create Outbound Firewall rules for svchost.exe
If (!(Get-NetFirewallRule -DisplayName "Custom - Allow Outbound svchost" -ErrorAction SilentlyContinue)) {
    Write-LogEntry -Value "Start creating firewall rule 'Custom - Allow Outbound svchost'" -Severity 1
    try {
        New-NetFirewallRule -DisplayName "Custom - Allow Outbound svchost" -Direction Outbound -Program "C:\Windows\System32\svchost.exe" -Action Allow -Group "Windows Defender" -Enabled False -Verbose
        Write-LogEntry -Value "Firewall rule 'Custom - Allow Outbound svchost is created.'" -Severity 1
    }
    catch {
        Write-LogEntry -Value "Create firewall rule 'Custom - Allow Outbound svchost' failed" -Severity 1        
        Write-LogEntry -Value "$_.Exception.Message" -Severity 3; exit 1
    }
}
else {
    Write-LogEntry -Value "Firewall rule name 'Custom - Allow Outbound svchost' is already exists." -Severity 2
    Write-LogEntry -Value "Please change firewall rule name and try again." -Severity 2
    exit 1
}  

#Create Task Scheduler for Windows Defender Update
$TaskName = "Custom - Windows Defender Update"
$taskdescription = "This task is for update Windows Defender every one hour"

If (!(Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue)) {
    Write-LogEntry -Value "Start creating Task Scheduler for Windows Defender Update" -Severity 1
    try {
        #Create Scheduled Task Actions
        Write-LogEntry -Value "Start creating Task Scheduler actions" -Severity 1
        $action = @()
        $action += New-ScheduledTaskAction -Execute 'netsh.exe' -Argument 'advfirewall firewall set rule name="Custom - Allow Outbound svchost" new enable=yes' -ErrorAction Stop
        $action += New-ScheduledTaskAction -Execute '"%ProgramFiles%\Windows Defender\MpCmdRun.exe"' -Argument 'SignatureUpdate' -ErrorAction Stop
        $action += New-ScheduledTaskAction -Execute 'netsh.exe' -Argument 'advfirewall firewall set rule name="Custom - Allow Outbound svchost" new enable=no' -ErrorAction Stop

        #Create Scheduled Task Trigger
        Write-LogEntry -Value "Start creating Task Scheduler Trigger daily start at 7am" -Severity 1
        $trigger = New-ScheduledTaskTrigger -Daily -At 7am -ErrorAction Stop

        #Create Scheduled Task Settings
        Write-LogEntry -Value "Start creating Task Scheduler Settings" -Severity 1
        $settings = New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 20) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 60) -ErrorAction Stop

        #Register Scheduled Task
        Write-LogEntry -Value "Start register Task Scheduler for Defender Update" -Severity 1
        Register-ScheduledTask -Action $action -Trigger $trigger -TaskName $taskname -Description $taskdescription -Settings $settings -User "NT AUTHORITY\SYSTEM" -RunLevel Highest -ErrorAction Stop

        #Wait until the schedule task is created
        do {
            $Task = Get-ScheduledTask -TaskName $taskname
        } until ($Task)

        #Configure trigger runs every hour
        Write-LogEntry -Value "Configure Task Scheduler for Windows defender Update runs every hour" -Severity 1        
        $Task.Triggers.Repetition.Duration = "P1D"
        $Task.Triggers.Repetition.Interval = "PT1H"
        $Task.Triggers.Repetition | Format-List *
        $Task | Set-ScheduledTask -User "NT AUTHORITY\SYSTEM" -ErrorAction Stop

        Write-LogEntry -Value "Task Scheduler for Windows defender Update is created" -Severity 1
        Start-ScheduledTask -TaskName $TaskName
    }
    catch {
        Write-LogEntry -Value "Create Task Scheduler for Windows Defender Update failed" -Severity 1       
        Write-LogEntry -Value "$_.Exception.Message" -Severity 3; exit 1
    }
}
else {
    Write-LogEntry -Value "Task Scheduler for Windows Defender Update is already exists." -Severity 2
    Write-LogEntry -Value "Please change Task Scheduler name and try again." -Severity 2
    exit 1
}