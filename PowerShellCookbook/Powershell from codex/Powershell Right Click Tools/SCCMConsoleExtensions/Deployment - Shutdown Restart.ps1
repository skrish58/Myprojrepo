﻿<#
Written by Ryan Ephgrave for ConfigMgr 2012 Right Click Tools
http://psrightclicktools.codeplex.com/
GUI Generated By: SAPIEN Technologies PrimalForms (Community Edition) v1.0.10.0
#>

$ShutdownRestartAction = $args[0]
$DeploymentName = $args[1]
$DeploymentID = $args[2]
$AssignmentID = $args[3]
$FeatureType = $args[4]
$Statuses = $args[5]
$IndexNumber = $args[6]
$Delay = $args[7]
$Server = $args[8]
$Namespace = $args[9]
$msg = $args[10]
$script:ActionCancel = $false


$FormName = "$ShutdownRestartAction - $DeploymentName"

$GetDirectory = $MyInvocation.MyCommand.path
$Directory = Split-Path $GetDirectory

function GenerateForm {

<#
Variables:

$DeploymentName - Deployment name for the DeploymentNameLbl
$NumSuccess - Number of successful actions
$NumUnsuccess - Number of unsuccessful actions
$SuccessView - Datagridview of successful actions
$UnsuccessView - Datagridview of unsuccessful actions
$LogBox - Richtextbox for logs
$CloseCancel - What the close/cancel button will show

#>

#region Import the Assemblies
[reflection.assembly]::loadwithpartialname("System.Drawing") | Out-Null
[reflection.assembly]::loadwithpartialname("System.Windows.Forms") | Out-Null
#endregion

#region Generated Form Objects
$ResultsForm = New-Object System.Windows.Forms.Form
$ReRunBtn = New-Object System.Windows.Forms.Button
$LogBox = New-Object System.Windows.Forms.RichTextBox
$UnsuccessLbl = New-Object System.Windows.Forms.Label
$UnsuccessView = New-Object System.Windows.Forms.DataGridView
$CloseCancelBtn = New-Object System.Windows.Forms.Button
$AboutBtn = New-Object System.Windows.Forms.Button
$SuccessView = New-Object System.Windows.Forms.DataGridView
$SuccessLbl = New-Object System.Windows.Forms.Label
$RunningOnLbl = New-Object System.Windows.Forms.Label
$DeploymentNameLbl = New-Object System.Windows.Forms.Label
$InitialFormWindowState = New-Object System.Windows.Forms.FormWindowState
#endregion Generated Form Objects

$AboutBtn_OnClick= 
{
	$ArgList = @()
	$ArgList += @("`"$Directory\SilentOpenPS.vbs`"")
	$ArgList += @("`"$Directory\About.ps1`"")
	Start-Process wscript.exe -ArgumentList $ArgList
}

$CloseCancelBtn_OnClick= 
{
	$CloseCancelText = $CloseCancelBtn.Text
	if ($CloseCancelText -eq "Close") {
		$ResultsForm.close()
	}
	else {
		$script:CancelAction = $true
	}
}

$ViewSelection_Changed=
{

}

$OnClose=
{
	$ProcessID = [System.Diagnostics.Process]::GetCurrentProcess()
	$ProcID = $ProcessID.ID
	& taskkill /PID $ProcID /T /F
}

$ResizeEnd=
{
	$FormWidth = $ResultsForm.Size.Width
	$DataGridWidth = $FormWidth - 70
	$DataGridWidth = $DataGridWidth / 2
	$System_Drawing_Size.Height = $UnsuccessView.Size.Height
	$System_Drawing_Size.Width = $DataGridWidth
	$UnsuccessView.Size = $System_Drawing_Size
	$SuccessView.Size = $System_Drawing_Size
	$System_Drawing_Point.X = 12
	$System_Drawing_Point.Y = 81
	$SuccessView.Location = $System_Drawing_Point
	$System_Drawing_Size.Height = 23
	$System_Drawing_Size.Width = $DataGridWidth
	$UnsuccessLbl.Size = $System_Drawing_Size
	$SuccessLbl.Size = $System_Drawing_Size
	$System_Drawing_Point.X = 12
	$System_Drawing_Point.Y = 55
	$SuccessLbl.Location = $System_Drawing_Point
}

$OnLoadForm_StateCorrection=
{
	$ResultsForm.WindowState = $InitialFormWindowState
	$ReRunBtn.Visible = $false
	$ReRunBtn.enabled = $false
	$System_Windows_Forms_DataGridViewTextBoxColumn_1 = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
	$System_Windows_Forms_DataGridViewTextBoxColumn_1.AutoSizeMode = 6
	$System_Windows_Forms_DataGridViewTextBoxColumn_1.HeaderText = "Device Name"
	$System_Windows_Forms_DataGridViewTextBoxColumn_1.Name = ""
	$System_Windows_Forms_DataGridViewTextBoxColumn_1.ReadOnly = $True
	$SuccessView.Columns.Add($System_Windows_Forms_DataGridViewTextBoxColumn_1)|Out-Null
	$System_Windows_Forms_DataGridViewTextBoxColumn_2 = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
	$System_Windows_Forms_DataGridViewTextBoxColumn_2.HeaderText = "Action taken"
	$System_Windows_Forms_DataGridViewTextBoxColumn_2.Name = ""
	$System_Windows_Forms_DataGridViewTextBoxColumn_2.ReadOnly = $True
	$System_Windows_Forms_DataGridViewTextBoxColumn_2.AutoSizeMode = 6
	$SuccessView.Columns.Add($System_Windows_Forms_DataGridViewTextBoxColumn_2)|Out-Null
	$System_Windows_Forms_DataGridViewTextBoxColumn_3 = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
	$System_Windows_Forms_DataGridViewTextBoxColumn_3.HeaderText = "Logged On User"
	$System_Windows_Forms_DataGridViewTextBoxColumn_3.Name = ""
	$System_Windows_Forms_DataGridViewTextBoxColumn_3.ReadOnly = $True
	$System_Windows_Forms_DataGridViewTextBoxColumn_3.AutoSizeMode = 6
	$SuccessView.Columns.Add($System_Windows_Forms_DataGridViewTextBoxColumn_3)|Out-Null
	$System_Windows_Forms_DataGridViewTextBoxColumn_4 = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
	$System_Windows_Forms_DataGridViewTextBoxColumn_4.HeaderText = "Logged On Domain"
	$System_Windows_Forms_DataGridViewTextBoxColumn_4.Name = ""
	$System_Windows_Forms_DataGridViewTextBoxColumn_4.ReadOnly = $True
	$System_Windows_Forms_DataGridViewTextBoxColumn_4.AutoSizeMode = 6
	$SuccessView.Columns.Add($System_Windows_Forms_DataGridViewTextBoxColumn_4)|Out-Null
	$System_Windows_Forms_DataGridViewTextBoxColumn_5 = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
	$System_Windows_Forms_DataGridViewTextBoxColumn_5.HeaderText = "Device Name"
	$System_Windows_Forms_DataGridViewTextBoxColumn_5.Name = ""
	$System_Windows_Forms_DataGridViewTextBoxColumn_5.ReadOnly = $True
	$System_Windows_Forms_DataGridViewTextBoxColumn_5.AutoSizeMode = 6
	$UnSuccessView.Columns.Add($System_Windows_Forms_DataGridViewTextBoxColumn_5)|Out-Null
	$System_Windows_Forms_DataGridViewTextBoxColumn_6 = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
	$System_Windows_Forms_DataGridViewTextBoxColumn_6.AutoSizeMode = 6
	$System_Windows_Forms_DataGridViewTextBoxColumn_6.HeaderText = "Off/Error"
	$System_Windows_Forms_DataGridViewTextBoxColumn_6.Name = ""
	$System_Windows_Forms_DataGridViewTextBoxColumn_6.ReadOnly = $True
	$UnSuccessView.Columns.Add($System_Windows_Forms_DataGridViewTextBoxColumn_6)|Out-Null
	$System_Windows_Forms_DataGridViewTextBoxColumn_7 = New-Object System.Windows.Forms.DataGridViewTextBoxColumn
	$System_Windows_Forms_DataGridViewTextBoxColumn_7.AutoSizeMode = 6
	$System_Windows_Forms_DataGridViewTextBoxColumn_7.HeaderText = "Error Message"
	$System_Windows_Forms_DataGridViewTextBoxColumn_7.Name = ""
	$System_Windows_Forms_DataGridViewTextBoxColumn_7.ReadOnly = $True
	$UnSuccessView.Columns.Add($System_Windows_Forms_DataGridViewTextBoxColumn_7)|Out-Null
	$script:CancelAction = $false
	$CloseCancelBtn.Text = "Cancel"
	$ReRunBtn.Enabled = $false
	$JobTimer = @{}
	$NumSuccess = 0
	$NumUnsuccess = 0
	$count = 0
	$CompList = $null
	$Statuses = $Statuses | Out-String
	$DeploySuccess = 0
	$DeployInProg = 0
	$DeployError = 0
	$DeployRequire = 0
	$DeployUnknown = 0
	$RunningOn = "Running on "
	if ($FeatureType -eq 1) {
		$strquery = "select * from SMS_R_System inner join SMS_AppDeploymentAssetDetails As Deploy on Deploy.MachineID = SMS_R_System.ResourceID where Deploy.AssignmentID = '$AssignmentID'"
		Get-WmiObject -Query $strquery -Namespace $Namespace -ComputerName $Server | ForEach-Object {
			$StatusCode = $_.Deploy.StatusType
			if ($StatusCode -eq 1 -and $Statuses.contains("1")){
				$CompList += @($_.SMS_R_System.ResourceNames[0])
				$DeploySuccess++
			}
			elseif ($StatusCode -eq 2 -and $Statuses.contains("2")){
				$CompList += @($_.SMS_R_System.ResourceNames[0])
				$DeployInProg++
			}
			elseif ($StatusCode -eq 3 -and $Statuses.contains("3")) {
				$CompList += @($_.SMS_R_System.ResourceNames[0])
				$DeployRequire++
			}
			elseif ($StatusCode -eq 5 -and $Statuses.contains("5")) {
				$CompList += @($_.SMS_R_System.ResourceNames[0])
				$DeployError++
			}
		}
		if ($Statuses.contains("4")) {
			$strquery = "select * from SMS_R_System inner join SMS_CIDeploymentUnknownAssetDetails as Deploy on Deploy.MachineID = SMS_R_System.ResourceID where Deploy.AssignmentID = '$AssignmentID'"
			Get-WmiObject -Query $strquery -Namespace $Namespace -ComputerName $Server | ForEach-Object {
				$CompList += @($_.SMS_R_System.ResourceNames[0])
				$DeployUnknown++
			}
		}
		If ($DeploySuccess -ne 0) {$RunningOn = $RunningOn + "Successful ($DeploySuccess) "}
		if ($DeployInProg -ne 0) {$RunningOn = $RunningOn + "In Progress ($DeployInProg) "}
		if ($DeployRequire -ne 0) {$RunningOn = $RunningOn + "Requirements Not Met ($DeployRequire) "}
		if ($DeployUnknown -ne 0) {$RunningOn = $RunningOn + "Unknown ($DeployUnknown) "}
		if ($DeployError -ne 0) {$RunningOn = $RunningOn + "Error ($DeployError)"}
		$RunningOnLbl.Text = $RunningOn
	}
	elseif ($FeatureType -eq 5) {
		$strquery = "select * from SMS_R_System inner join SMS_SUMDeploymentAssetDetails As Deploy on Deploy.ResourceID = SMS_R_System.ResourceID where Deploy.AssignmentID = '$AssignmentID'"
		Get-WmiObject -Query $strquery -Namespace $Namespace -ComputerName $Server | ForEach-Object {
			$StatusCode = $_.Deploy.StatusType
			if ($StatusCode -eq 1 -and $Statuses.contains("1")){
				$CompList += @($_.SMS_R_System.ResourceNames[0])
				$DeploySuccess++
			}
			elseif ($StatusCode -eq 2 -and $Statuses.contains("2")){
				$CompList += @($_.SMS_R_System.ResourceNames[0])
				$DeployInProg++
			}
			elseif ($StatusCode -eq 3 -and $Statuses.contains("3")) {
				$CompList += @($_.SMS_R_System.ResourceNames[0])
				$DeployRequire++
			}
			elseif ($StatusCode -eq 4 -and $Statuses.contains("4")) {
				$CompList += @($_.SMS_R_System.ResourceNames[0])
				$DeployUnknown++
			}
			elseif ($StatusCode -eq 5 -and $Statuses.contains("5")) {
				$CompList += @($_.SMS_R_System.ResourceNames[0])
				$DeployError++
			}
		}
		If ($DeploySuccess -ne 0) {$RunningOn = $RunningOn + "Successful ($DeploySuccess) "}
		if ($DeployInProg -ne 0) {$RunningOn = $RunningOn + "In Progress ($DeployInProg) "}
		if ($DeployRequire -ne 0) {$RunningOn = $RunningOn + "Requirements Not Met ($DeployRequire) "}
		if ($DeployUnknown -ne 0) {$RunningOn = $RunningOn + "Unknown ($DeployUnknown) "}
		if ($DeployError -ne 0) {$RunningOn = $RunningOn + "Error ($DeployError)"}
		$RunningOnLbl.Text = $RunningOn
	}
	else {
		$strquery = "select * from SMS_R_System inner join SMS_ClassicDeploymentAssetDetails As Deploy on Deploy.DeviceID = SMS_R_System.ResourceID where Deploy.DeploymentID = '$DeploymentID'"
		Get-WmiObject -Query $strquery -Namespace $Namespace -ComputerName $Server | ForEach-Object {
			$StatusCode = $_.Deploy.StatusType
			if ($StatusCode -eq 1 -and $Statuses.contains("1")){
				$CompList += @($_.SMS_R_System.ResourceNames[0])
				$DeploySuccess++
			}
			elseif ($StatusCode -eq 2 -and $Statuses.contains("2")){
				$CompList += @($_.SMS_R_System.ResourceNames[0])
				$DeployInProg++
			}
			elseif ($StatusCode -eq 3 -and $Statuses.contains("3")) {
				$CompList += @($_.SMS_R_System.ResourceNames[0])
				$DeployRequire++
			}
			elseif ($StatusCode -eq 4 -and $Statuses.contains("4")) {
				$CompList += @($_.SMS_R_System.ResourceNames[0])
				$DeployUnknown++
			}
			elseif ($StatusCode -eq 5 -and $Statuses.contains("5")) {
				$CompList += @($_.SMS_R_System.ResourceNames[0])
				$DeployError++
			}
		}
		If ($DeploySuccess -ne 0) {$RunningOn = $RunningOn + "Successful ($DeploySuccess) "}
		if ($DeployInProg -ne 0) {$RunningOn = $RunningOn + "In Progress ($DeployInProg) "}
		if ($DeployRequire -ne 0) {$RunningOn = $RunningOn + "Requirements Not Met ($DeployRequire) "}
		if ($DeployUnknown -ne 0) {$RunningOn = $RunningOn + "Unknown ($DeployUnknown) "}
		if ($DeployError -ne 0) {$RunningOn = $RunningOn + "Error ($DeployError)"}
		$RunningOnLbl.Text = $RunningOn
	}
	$CompList = $CompList | Sort-Object 
	foreach($CompName in $CompList) {
		[System.Windows.Forms.Application]::DoEvents()
		if ($script:CancelAction -eq $false){
			$JobName = "ShutdownRestart_" + $CompName
			$CurrTime = Get-Date
			$JobTimer.add("$CompName",$CurrTime)
			$CurrentTime = $CurrTime.ToLongTimeString()
			$LogText = "$CurrentTime - Starting $ShutdownRestartAction of $CompName`n"
			$LogBox.Text = $LogBox.Text + $LogText
			$LogScrollTo = $LogBox.Text.Length - 250
			$LogBox.Select($LogScrollTo,0)
			$LogBox.ScrollToCaret()
			$ArgList = @()
			$ArgList += @($CompName)
			$ArgList += @($ShutdownRestartAction)
			$ArgList += @($IndexNumber)
			$ArgList += @($Delay)
			$ArgList += @($msg)
			$ArgList += @($Directory)
			Start-Job -Name $JobName -ArgumentList $ArgList -ScriptBlock {
				$CompName = $args[0]
				$strAction = $args[1]
				$IndexNum = $args[2]
				$Delay = $args[3]
				$msg = $args[4]
				$Directory = $args[5]
				$psexec = "$Directory\psexec.exe"
				$LoggedOnUser = $null
				$LoggedOnDomain = $null
				If (test-connection -computername $CompName -count 1 -quiet){
					$Error.Clear()
					if ($strAction -eq "Restart"){
						if ($IndexNum -eq 0){
							& shutdown.exe /r /f /t $Delay /d p:0:0 /m $CompName /c $msg
							if ($Error[0]){
								$ErrorMsg = $Error[0]
								$strOutput = $CompName + "||Error||" + $ErrorMsg
							}
							else {$strOutput = $CompName + "||Restart"}
						}
						elseif ($IndexNum -eq 1){
							Get-WmiObject -ComputerName $CompName -class Win32_OperatingSystem | ForEach-Object {$WinDirectory = $_.WindowsDirectory}
							$CopyDirectory = $WinDirectory.ToLower().replace("c:","\\$CompName\c$")
							Copy-Item "$Directory\ConfigMgr_Shutdown_Utility.exe" $CopyDirectory -Force
							Copy-Item "$Directory\ConfigMgr_Shutdown_Utility.vbs" $CopyDirectory -Force
							$strQuery = "Select SessionID,Name from Win32_Process where Name='explorer.exe'"
							$SentShutdown = $false
							Get-WmiObject -ComputerName $CompName -Query $strQuery | ForEach-Object{
								if ($_.Name -ne $null){
									$SessionID = $_.SessionID
									& $psexec "\\$CompName" /d /s /i $SessionID wscript.exe "$WinDirectory\ConfigMgr_Shutdown_Utility.vbs" "$WinDirectory\ConfigMgr_Shutdown_Utility.exe" /r /t $Delay /msg "`"$msg`"" | Out-Null
									$SentShutdown = $true
								}
							}
							if ($SentShutdown -eq $false) {& shutdown.exe /r /f /t $Delay /d p:0:0 /m $CompName /c $msg}
							if ($Error[0]) {$strOutput = $CompName + "||Error||" + $Error[0]}
							else {$strOutput = $Compname + "||Gave prompt to cancel restart||" + $LoggedOnUser + "||" + $LoggedOnDomain}
						}
						elseif ($IndexNum -eq 2){
							$skip = 0
							$strQuery = "Select * from Win32_Process where Name='explorer.exe'"
							Get-WmiObject -ComputerName $CompName -query $strQuery | ForEach-Object{
								if ($_.Name -ne $null){
									$skip = 1
									$LoggedOnUser = $_.GetOwner().User
									$LoggedOnDomain = $_.GetOwner().Domain
									$strOutput = "$CompName" + "||Skipped||" + $LoggedOnUser + "||" + $LoggedOnDomain
								}
							}
							if ($skip -eq 0){
								$Error.Clear()
								& shutdown.exe /r /f /t $Delay /d p:0:0 /m $CompName /c $msg
								if ($Error[0]){
									$ErrorMsg = $Error[0]
									$strOutput = $CompName + "||Error||" + $ErrorMsg
								}
								else {$strOutput = $CompName + "||Restart"}
							}
						}
					}
					elseif ($strAction -eq "Shutdown"){
						if ($IndexNum -eq 0){
							& shutdown.exe /s /f /t $Delay /d p:0:0 /m $CompName /c $msg
							if ($Error[0]){
								$ErrorMsg = $Error[0]
								$strOutput = $CompName + "||Error||" + $ErrorMsg
							}
							else {$strOutput = "$CompName ||Shutdown"}
						}
						elseif ($IndexNum -eq 1){
							Get-WmiObject -ComputerName $CompName -class Win32_OperatingSystem | ForEach-Object {$WinDirectory = $_.WindowsDirectory}
							$CopyDirectory = $WinDirectory.ToLower().replace("c:","\\$CompName\c$")
							Copy-Item "$Directory\ConfigMgr_Shutdown_Utility.exe" $CopyDirectory -Force
							Copy-Item "$Directory\ConfigMgr_Shutdown_Utility.vbs" $CopyDirectory -Force
							$strQuery = "Select SessionID,Name from Win32_Process where Name='explorer.exe'"
							$SentShutdown = $false
							Get-WmiObject -ComputerName $CompName -Query $strQuery | ForEach-Object{
								if ($_.Name -ne $null){
									$SessionID = $_.SessionID
									& $psexec "\\$CompName" /d /s /i $SessionID wscript.exe "$WinDirectory\ConfigMgr_Shutdown_Utility.vbs" "$WinDirectory\ConfigMgr_Shutdown_Utility.exe" /s /t $Delay /msg "`"$msg`"" | Out-Null
									$SentShutdown = $true
								}
							}
							if ($SentShutdown -eq $false) {& shutdown.exe /s /f /t $Delay /d p:0:0 /m $CompName /c $msg}
							if ($Error[0]) {$strOutput = $CompName + "||Error||" + $Error[0]}
							else {$strOutput = $Compname + "||Gave prompt to cancel restart||" + $LoggedOnUser + "||" + $LoggedOnDomain}
						}
						elseif ($IndexNum -eq 2){
							$skip = 0
							$strQuery = "Select * from Win32_Process where Name='explorer.exe'"
							Get-WmiObject -ComputerName $CompName -query $strQuery | ForEach-Object{
								if ($_.Name -ne $null){
									$skip = 1
									$LoggedOnUser = $_.GetOwner().User
									$LoggedOnDomain = $_.GetOwner().Domain
									$strOutput = "$CompName" + "||Skipped||" + $LoggedOnUser + "||" + $LoggedOnDomain
								}
							}
							if ($skip -eq 0){
								$Error.Clear()
								& shutdown.exe /s /f /t $Delay /d p:0:0 /m $CompName /c $msg
								if ($Error[0]){
									$ErrorMsg = $Error[0]
									$strOutput = $CompName + "||Error||" + $ErrorMsg
								}
								else {$strOutput = $CompName + "||Shutdown"}
							}
						}
					}
				}
				else {$strOutput = "$CompName ||Off"}
				Write-Output $strOutput
			} | Out-Null
			[System.Windows.Forms.Application]::DoEvents()
			Receive-Job -Name "ShutdownRestart_*" | ForEach-Object {
				[System.Windows.Forms.Application]::DoEvents()
				$count++
				$strOutput = $_
				$strOutput = $strOutput | Out-String
				$CurrTime = Get-Date
				$CurrentTime = $CurrTime.ToLongTimeString()
				if ($strOutput.contains("||Off")){
					$NumUnsuccess++
					$strOutput = $strOutput.replace(" ||Off","")
					$LogBox.Text = $LogBox.Text + "$CurrentTime - Error pinging $strOutput"
					$UnsuccessView.Rows.Add("$strOutput","Off")
					$UnsuccessLbl.Text = "$NumUnsuccess Unsuccessful"
				}
				elseif ($strOutput.contains("||Skipped")) {
					$OutputArray = $strOutput.Split("||")
					$SkipMessage = "Skipped because " + $OutputArray[6] + "\" + $OutputArray[4] + " is logged on" 
					$LogBox.Text = $LogBox.Text + "$CurrentTime - Skipped " + $OutputArray[0] + " because " + $OutputArray[4] + " is logged on...`n"
					$UnSuccessView.Rows.Add($OutputArray[0],"Skipped",$SkipMessage)
					$NumUnSuccess++
					$UnSuccessLbl.Text = "$NumSuccess Successful"
				}
				elseif ($strOutput.contains("||Error")) {
					$LogBox.Text = $LogBox.Text + "$CurrentTime - Received error from " + $OutputArray[0] + "`n"
					$OutputArray = $strOutput.Split("||")
					$UnsuccessView.Rows.Add($OutputArray[0],"Error",$OutputArray[4])
					$NumUnsuccess++
					$UnsuccessLbl.Text = "$NumUnsuccess Unsuccessful"
				}
				else {
					$OutputArray = $strOutput.Split("||")
					$SuccessView.Rows.Add($OutputArray[0],$OutputArray[2],$OutputArray[4],$OutputArray[6])
					$LogBox.Text = $LogBox.Text + "$CurrentTime - $ShutdownRestartAction " + $OutputArray[0] + "`n"
					$Numsuccess++
					$SuccessLbl.Text = "$NumSuccess Successful"
				}
				$LogScrollTo = $LogBox.Text.Length - 250
				$LogBox.Select($LogScrollTo,0)
				$LogBox.ScrollToCaret()
			}
			do {
				[System.Windows.Forms.Application]::DoEvents()
				$RunningJobs = 0
				$IgnoredJobs = 0
				get-job | where-object {$_.Name -like "ShutdownRestart_*" -and $_.State -eq "Running"} | ForEach-Object {
					[System.Windows.Forms.Application]::DoEvents()
					$JobID = $_.ID
					if ($SkippedJobs -inotcontains "$JobID") {
						$RunningJobs++
						$CurrTime = Get-Date
						$CurrentTime = $CurrTime.ToLongTimeString()
						$JobCompName = $_.Name
						$JobCompName = $JobCompName.replace("ShutdownRestart_","")
						$StartTime = $JobTimer["$JobCompName"]
						$CompareTime = $CurrTime - $StartTime
						if ($CompareTime.Minutes -gt 2 -and $IgnoredJobs -eq 0){
							$SkippedJobs += @("$JobID")
							$IgnoredJobs++
							$LogBox.Text = $LogBox.Text + "$CurrentTime - $JobCompName timed out...`n"
							$LogScrollTo = $LogBox.Text.Length - 250
							$LogBox.Select($LogScrollTo,0)
							$LogBox.ScrollToCaret()
							$UnsuccessView.Rows.Add("$JobCompName","Timed out after 2 minutes","Possible WMI problems")
							$NumUnsuccess++
							$UnsuccessLbl.Text = "$NumUnsuccess Unsuccessful"
						}
					}
				}
				if ($RunningJobs -gt 20) {
					[System.Windows.Forms.Application]::DoEvents()
					Start-Sleep 1
					$LogBox.Text = $LogBox.Text + "$CurrentTime - Can only run 20 jobs at once, waiting on some to finish before continuing...`n"
					$LogScrollTo = $LogBox.Text.Length - 250
					$LogBox.Select($LogScrollTo,0)
					$LogBox.ScrollToCaret()
				}
			} while ($RunningJobs -gt 20 -and $script:CancelAction -ne $true)
		}
	}
	do {
		[System.Windows.Forms.Application]::DoEvents()
		$RunningJobs = 0
		$IgnoredJobs = 0
		get-job | where-object {$_.Name -like "ShutdownRestart_*" -and $_.State -eq "Running"} | ForEach-Object {
			[System.Windows.Forms.Application]::DoEvents()
			$JobID = $_.ID
			if ($SkippedJobs -inotcontains "$JobID") {
				$RunningJobs++
				$CurrTime = Get-Date
				$CurrentTime = $CurrTime.ToLongTimeString()
				$JobCompName = $_.Name
				$JobCompName = $JobCompName.replace("ShutdownRestart_","")
				$StartTime = $JobTimer["$JobCompName"]
				$CompareTime = $CurrTime - $StartTime
				if ($CompareTime.Minutes -gt 2 -and $IgnoredJobs -eq 0){
					$SkippedJobs += @($_.ID)
					$IgnoredJobs++
					$LogBox.Text = $LogBox.Text + "$CurrentTime - $JobCompName timed out...`n"
					$LogScrollTo = $LogBox.Text.Length - 250
					$LogBox.Select($LogScrollTo,0)
					$LogBox.ScrollToCaret()
					$UnsuccessView.Rows.Add("$JobCompName","Timed out after 2 minutes","Possible WMI problems")
					$NumUnsuccess++
					$UnsuccessLbl.Text = "$NumUnsuccess Unsuccessful"
				}
			}
		}
		if ($RunningJobs -gt 0) {
			[System.Windows.Forms.Application]::DoEvents()
			Start-Sleep 1
			$LogBox.Text = $LogBox.Text + "$CurrentTime - Waiting on $RunningJobs jobs to complete still. It will time out after 2 minutes if it is still running...`n"
			$LogScrollTo = $LogBox.Text.Length - 250
			$LogBox.Select($LogScrollTo,0)
			$LogBox.ScrollToCaret()
		}
	} while ($RunningJobs -gt 0 -and $script:CancelAction -ne $true)
	Receive-Job -Name "ShutdownRestart_*" | ForEach-Object {
		[System.Windows.Forms.Application]::DoEvents()
		$count++
		$strOutput = $_
		$strOutput = $strOutput | Out-String
		$CurrTime = Get-Date
		$CurrentTime = $CurrTime.ToLongTimeString()
		if ($strOutput.contains("||Off")){
			$NumUnsuccess++
			$strOutput = $strOutput.replace(" ||Off","")
			$LogBox.Text = $LogBox.Text + "$CurrentTime - Error pinging $strOutput"
			$UnsuccessView.Rows.Add("$strOutput","Off")
			$UnsuccessLbl.Text = "$NumUnsuccess Unsuccessful"
		}
		elseif ($strOutput.contains("||Skipped")) {
			$OutputArray = $strOutput.Split("||")
			$SkipMessage = "Skipped because " + $OutputArray[6] + "\" + $OutputArray[4] + " is logged on" 
			$LogBox.Text = $LogBox.Text + "$CurrentTime - Skipped " + $OutputArray[0] + " because " + $OutputArray[4] + " is logged on...`n"
			$UnSuccessView.Rows.Add($OutputArray[0],"Skipped",$SkipMessage)
			$NumUnSuccess++
			$UnSuccessLbl.Text = "$NumUnsuccess Unsuccessful"
		}
		elseif ($strOutput.contains("||Error")) {
			$LogBox.Text = $LogBox.Text + "$CurrentTime - Received error from " + $OutputArray[0] + "`n"
			$OutputArray = $strOutput.Split("||")
			$UnsuccessView.Rows.Add($OutputArray[0],"Error",$OutputArray[4])
			$NumUnsuccess++
			$UnsuccessLbl.Text = "$NumUnsuccess Unsuccessful"
		}
		else {
			$OutputArray = $strOutput.Split("||")
			$SuccessView.Rows.Add($OutputArray[0],$OutputArray[2],$OutputArray[4],$OutputArray[6])
			$LogBox.Text = $LogBox.Text + "$CurrentTime - $ShutdownRestartAction " + $OutputArray[0] + "`n"
			$Numsuccess++
			$SuccessLbl.Text = "$NumSuccess Successful"
		}
		$LogScrollTo = $LogBox.Text.Length - 250
		$LogBox.Select($LogScrollTo,0)
		$LogBox.ScrollToCaret()
	}
	$ReRunBtn.Enabled = $true
	$CloseCancelBtn.Text = "Close"
	$CurrTime = Get-Date
	$CurrentTime = $CurrTime.ToLongTimeString()
	$LogBox.Text = $LogBox.Text + "$CurrentTime - Finished!`n"
}

#region Generated Form Code
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 555
$System_Drawing_Size.Width = 532
$ResultsForm.ClientSize = $System_Drawing_Size
$ResultsForm.DataBindings.DefaultDataSourceUpdateMode = 0
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 600
$System_Drawing_Size.Width = 550
$ResultsForm.MinimumSize = $System_Drawing_Size
$ResultsForm.Name = "ResultsForm"
$ResultsForm.Text = "$FormName"

$ReRunBtn.Anchor = 10

$ReRunBtn.DataBindings.DefaultDataSourceUpdateMode = 0

$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 361
$System_Drawing_Point.Y = 520
$ReRunBtn.Location = $System_Drawing_Point
$ReRunBtn.Name = "ReRunBtn"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 23
$System_Drawing_Size.Width = 75
$ReRunBtn.Size = $System_Drawing_Size
$ReRunBtn.TabIndex = 9
$ReRunBtn.Text = "Rerun"
$ReRunBtn.UseVisualStyleBackColor = $True
$ReRunBtn.add_Click($ReRunBtn_OnClick)

$ResultsForm.Controls.Add($ReRunBtn)

$LogBox.Anchor = 14
$LogBox.DataBindings.DefaultDataSourceUpdateMode = 0
$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 12
$System_Drawing_Point.Y = 418
$LogBox.Location = $System_Drawing_Point
$LogBox.Name = "LogBox"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 96
$System_Drawing_Size.Width = 505
$LogBox.Size = $System_Drawing_Size
$LogBox.TabIndex = 8
$LogBox.WordWrap = $False
$LogBox.Text = ""

$ResultsForm.Controls.Add($LogBox)

$UnsuccessLbl.Anchor = 1
$UnsuccessLbl.DataBindings.DefaultDataSourceUpdateMode = 0

$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 278
$System_Drawing_Point.Y = 55
$UnsuccessLbl.Location = $System_Drawing_Point
$UnsuccessLbl.Name = "UnsuccessLbl"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 23
$System_Drawing_Size.Width = 240
$UnsuccessLbl.Size = $System_Drawing_Size
$UnsuccessLbl.TabIndex = 7
$UnsuccessLbl.Text = "$NumUnSuccess Unsuccessful"
$UnsuccessLbl.TextAlign = 32

$ResultsForm.Controls.Add($UnsuccessLbl)

$UnsuccessView.AllowUserToAddRows = $False
$UnsuccessView.AllowUserToDeleteRows = $False
$UnsuccessView.AllowUserToResizeRows = $False
$UnsuccessView.Anchor = 3
$UnsuccessView.ClipboardCopyMode = 2
$UnsuccessView.ColumnHeadersHeightSizeMode = 1
$UnsuccessView.DataBindings.DefaultDataSourceUpdateMode = 0
$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 278
$System_Drawing_Point.Y = 81
$UnsuccessView.Location = $System_Drawing_Point
$UnsuccessView.Name = "UnsuccessView"
$UnsuccessView.ReadOnly = $True
$UnsuccessView.RowHeadersVisible = $False
$UnsuccessView.RowHeadersWidthSizeMode = 1
$UnsuccessView.RowTemplate.Height = 24
$UnsuccessView.SelectionMode = 0
$UnsuccessView.ShowCellErrors = $False
$UnsuccessView.ShowRowErrors = $False
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 331
$System_Drawing_Size.Width = 240
$UnsuccessView.Size = $System_Drawing_Size
$UnsuccessView.TabIndex = 6
$UnsuccessView.add_SelectionChanged($ViewSelection_Changed)

$ResultsForm.Controls.Add($UnsuccessView)

$CloseCancelBtn.Anchor = 10

$CloseCancelBtn.DataBindings.DefaultDataSourceUpdateMode = 0

$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 442
$System_Drawing_Point.Y = 520
$CloseCancelBtn.Location = $System_Drawing_Point
$CloseCancelBtn.Name = "CloseCancelBtn"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 23
$System_Drawing_Size.Width = 75
$CloseCancelBtn.Size = $System_Drawing_Size
$CloseCancelBtn.TabIndex = 5
$CloseCancelBtn.Text = "$CloseCancel"
$CloseCancelBtn.UseVisualStyleBackColor = $True
$CloseCancelBtn.add_Click($CloseCancelBtn_OnClick)

$ResultsForm.Controls.Add($CloseCancelBtn)

$AboutBtn.Anchor = 6

$AboutBtn.DataBindings.DefaultDataSourceUpdateMode = 0

$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 12
$System_Drawing_Point.Y = 520
$AboutBtn.Location = $System_Drawing_Point
$AboutBtn.Name = "AboutBtn"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 23
$System_Drawing_Size.Width = 75
$AboutBtn.Size = $System_Drawing_Size
$AboutBtn.TabIndex = 4
$AboutBtn.Text = "About"
$AboutBtn.UseVisualStyleBackColor = $True
$AboutBtn.add_Click($AboutBtn_OnClick)

$ResultsForm.Controls.Add($AboutBtn)

$SuccessView.AllowUserToAddRows = $False
$SuccessView.AllowUserToDeleteRows = $False
$SuccessView.AllowUserToResizeRows = $False
$SuccessView.Anchor = 3
$SuccessView.ClipboardCopyMode = 2
$SuccessView.ColumnHeadersHeightSizeMode = 1
$SuccessView.DataBindings.DefaultDataSourceUpdateMode = 0
$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 12
$System_Drawing_Point.Y = 81
$SuccessView.Location = $System_Drawing_Point
$SuccessView.Name = "SuccessView"
$SuccessView.ReadOnly = $True
$SuccessView.RowHeadersVisible = $False
$SuccessView.RowHeadersWidthSizeMode = 1
$SuccessView.RowTemplate.Height = 24
$SuccessView.SelectionMode = 0
$SuccessView.ShowCellErrors = $False
$SuccessView.ShowRowErrors = $False
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 331
$System_Drawing_Size.Width = 240
$SuccessView.Size = $System_Drawing_Size
$SuccessView.TabIndex = 3
$SuccessView.add_SelectionChanged($ViewSelection_Changed)

$ResultsForm.Controls.Add($SuccessView)

$SuccessLbl.Anchor = 1
$SuccessLbl.DataBindings.DefaultDataSourceUpdateMode = 0

$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 12
$System_Drawing_Point.Y = 55
$SuccessLbl.Location = $System_Drawing_Point
$SuccessLbl.Name = "SuccessLbl"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 23
$System_Drawing_Size.Width = 240
$SuccessLbl.Size = $System_Drawing_Size
$SuccessLbl.TabIndex = 2
$SuccessLbl.Text = "$NumSuccess Successful"
$SuccessLbl.TextAlign = 32

$ResultsForm.Controls.Add($SuccessLbl)

$RunningOnLbl.Anchor = 13
$RunningOnLbl.DataBindings.DefaultDataSourceUpdateMode = 0

$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 12
$System_Drawing_Point.Y = 32
$RunningOnLbl.Location = $System_Drawing_Point
$RunningOnLbl.Name = "RunningOnLbl"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 23
$System_Drawing_Size.Width = 505
$RunningOnLbl.Size = $System_Drawing_Size
$RunningOnLbl.TabIndex = 1
$RunningOnLbl.Text = "$ShutdownRestartAction"
$RunningOnLbl.TextAlign = 32

$ResultsForm.Controls.Add($RunningOnLbl)

$DeploymentNameLbl.Anchor = 13
$DeploymentNameLbl.DataBindings.DefaultDataSourceUpdateMode = 0

$System_Drawing_Point = New-Object System.Drawing.Point
$System_Drawing_Point.X = 12
$System_Drawing_Point.Y = 9
$DeploymentNameLbl.Location = $System_Drawing_Point
$DeploymentNameLbl.Name = "DeploymentNameLbl"
$System_Drawing_Size = New-Object System.Drawing.Size
$System_Drawing_Size.Height = 23
$System_Drawing_Size.Width = 505
$DeploymentNameLbl.Size = $System_Drawing_Size
$DeploymentNameLbl.TabIndex = 0
$DeploymentNameLbl.Text = "$DeploymentName"
$DeploymentNameLbl.TextAlign = 32

$ResultsForm.Controls.Add($DeploymentNameLbl)

#endregion Generated Form Code

$InitialFormWindowState = $ResultsForm.WindowState

$ResultsForm.add_Load($OnLoadForm_StateCorrection)
$ResultsForm.add_SizeChanged($ResizeEnd)
$ResultsForm.add_Closing($OnClose)

$ResultsForm.ShowDialog()| Out-Null

}

GenerateForm