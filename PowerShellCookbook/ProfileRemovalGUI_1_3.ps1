<#
    .SYNOPSIS
        This GUI allows you to remove local profiles from both local and remote servers.
    
    .DESCRIPTION
        This GUI allows you to remove local profiles from both local and remote servers. Compatible with XP and above operating
        systems. Adjust $maxConcurrentJobs to suit your needs for asynchronous jobs.
        
    .NOTES
        Author: Boe Prox
        Created: 28 Sept 2011
        Modified: 13 Oct 2011
        Version: 1.0 
            -> Initial Build
        Version: 1.1 
            -> Code updates to include consolidating functions into two scriptblocks based on role that can be called 
                within a background job
            -> Background processing of initial connection to computer to prevent UI freeze
        Version: 1.2
            -> Added LastAccess column to UI
            -> Added autorefresh of list view after removal of profiles
            -> Added cancel button
            -> Fixed bug where some profile folders were not being included in registry or wmi queries but folders existed
        Version: 1.3
            -> Added better check to see if userprofile is actively in use
#>
$VerbosePreference = 'silentlycontinue'
#Determine if this instance of PowerShell can run WPF 
Write-Verbose "Checking the apartment state"
If ($host.Runspace.ApartmentState -ne "STA") {
    Write-Warning "This script must be run in PowerShell started using -STA switch!`nScript will attempt to open PowerShell in STA and run re-run script."
    Start-Process -File PowerShell.exe -Argument "-STA -noprofile -file $($myinvocation.mycommand.definition)"
    Break
}

<#Validate user is an Administrator
Write-Verbose "Checking Administrator credentials"
If (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Warning "You are not running this as an Administrator!`nRe-running script and will prompt for administrator credentials."
    Start-Process -Verb "Runas" -File PowerShell.exe -Argument "-STA -noprofile -file $($myinvocation.mycommand.definition)"
    Break
}
#>

#Stop and remove any jobs currently running
Write-Verbose "Removing PS jobs"
Get-Job | Remove-Job -Force -ea silentlycontinue

#Ensure that we are running the GUI from the correct location
Set-Location $(Split-Path $MyInvocation.MyCommand.Path)
$Path = $(Split-Path $MyInvocation.MyCommand.Path)
Write-Verbose "Current location: $Path"

#Set max concurrent jobs
$maxConcurrentJobs = 10

#Load Required Assemblies
Add-Type –assemblyName PresentationFramework
Add-Type –assemblyName PresentationCore
Add-Type –assemblyName WindowsBase

#Load Functions
Function Global:RemoveProfileJob {
    Write-Verbose "Queue Count: $($queue.count)"
    if( $queue.Count -gt 0)
    {
        $guid = $queue.Dequeue()
        $userprofile = $ListView.DataContext.rows.Find($guid)
        $j = Start-Job -Name $guid -ScriptBlock {
                param($ProfilePath,$server,$type,$RegistryPath,$WMIPath)
                If ((Get-WmiObject -ComputerName $server -Class Win32_OperatingSystem).Version -gt 6) {
                    Remove-PostVistaProfile $ProfilePath $server $type $wmipath
                } Else {
                    Remove-PreVistaProfile $ProfilePath $server $type $registrypath
                }
            } -ArgumentList $userprofile.localpath,$server,$userprofile.type,$userprofile.registrypath,$userprofile.wmipath -InitializationScript $removesb
        Register-ObjectEvent -InputObject $j -EventName StateChanged -Action {
            $VerbosePreference = 'silentlycontinue'
            $EventMessage = $eventsubscriber
            $SID = $eventsubscriber.sourceobject.name
            #Declare value for server to be updated in grid
            $Global:ProgressBar.Value++
            $Global:Window.Dispatcher.Invoke( "Render", $Global:updatelayout, $null, $null)
            Write-Verbose "Retrieving data from $($eventsubscriber.sourceobject.name)"        
            $Global:status = Receive-Job -Job $eventsubscriber.sourceobject
            $userprofile = $ListView.DataContext.rows.Find($eventsubscriber.sourceobject.name)
            #Update UI
            If ($status -ne 'Error') {
                $Global:StatusTextBox.Text = "Removed {0}" -f $userprofile.username
            } Else {
                $Global:StatusTextBox.Text = "Failed to Remove {0}" -f $userprofile.username
            }
            Write-Verbose "Updating: $($eventsubscriber.sourceobject.name)"
            Write-Verbose "Removing Event Job"           
            Remove-Job -Job $eventsubscriber.sourceobject
            Write-Verbose "Unregistering Event"           
            Unregister-Event $eventsubscriber.SourceIdentifier
            Write-Verbose "Removing background Job"           
            Remove-Job -Name $eventsubscriber.SourceIdentifier            
            If ($queue.count -gt 0 -OR (Get-Job)) {
                Write-Verbose "Running RemoveProfileJob"
                RemoveProfileJob
                }
            ElseIf (-NOT (Get-Job))
            {
                Write-Verbose "Starting Update-ProfileUI job"
                $j = Start-Job -InitializationScript $querysb -Name $server -ScriptBlock {
                    Param($server)
                    If ((Get-WmiObject -ComputerName $server -Class Win32_OperatingSystem).Version -gt 6) {
                        Get-PostVistaProfile $server
                    } Else {
                        Get-PreVistaProfile $server
                    }    
                } -argumentList $Server
                Register-ObjectEvent -InputObject $j -EventName StateChanged -Action {
                    $VerbosePreference = 'silentlycontinue'
                    $EventMessage = $eventsubscriber
                    Write-Verbose "Retrieving data from $($eventsubscriber.sourceobject.name)"        
                    $Global:status = Receive-Job -Job $eventsubscriber.sourceobject
                    #Update UI
                    Update-ProfileUI $Status
                    Write-Verbose "Updating: $($eventsubscriber.sourceobject.name)"
                    Write-Verbose "Removing Event Job"           
                    Remove-Job -Job $eventsubscriber.sourceobject
                    Write-Verbose "Unregistering Event"           
                    Unregister-Event $eventsubscriber.SourceIdentifier
                    Write-Verbose "Removing background Job"           
                    Remove-Job -Name $eventsubscriber.SourceIdentifier
                    [Float]$Global:ProgressBar.Value = $Global:ProgressBar.Maximum
                    $End = New-Timespan $Start (Get-Date)                     
                    $Global:StatusTextBox.Text = "Completed in: {0}" -f $end                    
                    $ComputerButton.IsEnabled = $True
                    $RemoveProfileButton.IsEnabled = $True            
                }             
            }                
                    Write-Verbose "RemoveProfileJob started"
        } | Out-Null
        Write-Verbose "Created Event for $($J.Name)"
    } 
}

Function Global:New-DataTable {
    #New Data Table
    $Global:DataTable = New-Object System.Data.DataTable
    $DataTable.TableName = 'Profile'
     
    #Create Columns with Names and Types
    $colGUID = New-Object System.Data.DataColumn GUID,([string])
    $colUserName = New-Object System.Data.DataColumn UserName,([string])
    $colSID = New-Object System.Data.DataColumn SID, ([string])
    $colLocalPath = New-Object System.Data.DataColumn LocalPath, ([string])
    $colLastAccess = New-Object System.Data.DataColumn LastAccess, ([datetime])
    $colIsActive = New-Object System.Data.DataColumn IsActive, ([string])
    $colType = New-Object System.Data.DataColumn Type, ([string])
    $colWMIPath = New-Object System.Data.DataColumn WMIPath, ([string])
    $colRegistryPath = New-Object System.Data.DataColumn RegistryPath, ([string])

    #Add Columns into Data Table
    $DataTable.Columns.Add($colGUID)    
    $DataTable.Columns.Add($colLocalPath)    
    $DataTable.Columns.Add($colUserName)    
    $DataTable.Columns.Add($colSID)
    $DataTable.Columns.Add($colLastAccess)
    $DataTable.Columns.Add($colIsActive)
    $DataTable.Columns.Add($colType)
    $DataTable.Columns.Add($colWMIPath)
    $DataTable.Columns.Add($colRegistryPath)
     
    #Set Primary Key for GUID
    $DataTable.PrimaryKey = @($DataTable.Columns[0])
}   

Function PreVistaLocalProfile {
Param ($Server)
    $basekey = "LocalMachine"
    $registry = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey($basekey,$Server)
    $SubKey = $registry.OpenSubKey("Software\Microsoft\Windows NT\CurrentVersion\ProfileList",$True)
    $ErrorActionPreference = 'SilentlyContinue'
    $ActiveUsers = Get-WmiObject Win32_Process -ComputerName $server | ForEach {
        $user = $_.GetOwner().User
        If ($user -eq 'SYSTEM') {
            'systemprofile'
        } ElseIf ($user -eq 'NETWORK SERVICE') {
            'NetworkService'
        } ElseIf ($user -eq 'LOCAL SERVICE') {
            'LocalService'
        } Else {
            $user
        }
    } | Select -Unique
    $ErrorActionPreference = 'Continue'
    $Registrydata = ForEach ($key in $Subkey.GetSubKeyNames()) {
        $RegProfile = $registry.OpenSubKey("Software\Microsoft\Windows NT\CurrentVersion\ProfileList\$key",$True)
        $LocalPath = ($RegProfile.GetValue("ProfileImagePath") -replace "C:\\","\\$($Server)\C$\")
        $UserName = Split-Path $LocalPath -Leaf
        $regpath = ($RegProfile.name -replace "HKEY_LOCAL_MACHINE\\","")
        New-Object PSObject -Property @{
            Username = $UserName
            LocalPath = $LocalPath
            SID = $key
            IsActive = If ($ActiveUsers -contains $Username) {$True} Else {$False}
            RegistryPath = $regpath
            Type = 'Registry'
            WMIPath = $Null
            LastAccess = (Get-Item $LocalPath -erroraction Silentlycontinue).LastWriteTime
        }
    }    
    $Directory = Get-ChildItem "\\$server\c$\Documents and Settings" | Where {
        @($Registrydata | Select -Expand LocalPath) -notcontains $_.Fullname
    } -EA silentlycontinue |
        Select @{L='LocalPath';E={$_.FullName}},
            @{L='UserName';E={Split-Path $_.FullName -Leaf}},
            @{L='SID';E={$Null}},
            @{L='IsActive';E={$False}},
            @{L='Type';E={'Directory'}},
            @{L='RegistryPath';E={$Null}},
            @{L='WMIPath';E={$Null}},
            @{L='LastAccess';E={$_.LastWriteTime}}
    If ($Directory.count -gt 0) {
        $data = $Registrydata + $Directory
    } Else {
        $data = $Registrydata
    } 
    Write-Output $Data
} 

Function PostVistaLocalProfile {
    Param ($Server)
    $wmi = Get-WmiObject -ComputerName $server -Class Win32_UserProfile |
        Select SID,@{L='LocalPath';E={($_.LocalPath -replace "C:\\","\\$($server)\C$\")}},
            @{L='IsActive';E={$_.Loaded}},
            @{L='Type';E={'WMI'}},
            @{L='WMIPath';E={$_.Path.Path}},
            @{L='RegistryPath';E={$Null}},
            @{L='LastAccess';E={(Get-Item ($_.LocalPath -replace "C:\\","\\$($server)\C$\") -erroraction Silentlycontinue).LastWriteTime}}
    $Directory = Get-ChildItem "\\$server\c$\users" | Where {
        @($wmi | Select -Expand LocalPath) -notcontains $_.Fullname
    } -EA silentlycontinue |
        Select @{L='LocalPath';E={$_.FullName}},
            @{L='SID';E={$Null}},
            @{L='IsActive';E={"NA"}},
            @{L='Type';E={'Directory'}},  
            @{L='WMIPath';E={$Null}},
            @{L='RegistryPath';E={$Null}},
            @{L='LastAccess';E={$_.LastWriteTime}}
    If ($Directory.count -gt 0) {
        $data = ($wmi + $Directory)
    } Else {
        $data = $wmi
    }
    Write-Output $Data 
}

Function Global:Update-ProfileUI {
    Param ($Data)
    New-DataTable
    ForEach ($d in $Data) {
        #Create new row
        $dr = $DataTable.NewRow()
        #Add Data To Row
        $dr.GUID = [guid]::NewGuid()
        $dr.UserName = (Split-Path $d.LocalPath -Leaf)
        $dr.SID = $d.sid
        $dr.LocalPath = $d.localpath
        $dr.IsActive = $d.IsActive
        $dr.Type = $d.type
        $dr.WMIPath = $d.WMIPath
        $dr.RegistryPath = $d.RegistryPath
        Try {
            $dr.LastAccess = $d.LastAccess
        } Catch {
            $dr.LastAccess = [DBNull]::Value
        }
        #Add Row To Data Table
        $DataTable.Rows.Add($dr)
        $Global:Listview.DataContext = $DataTable
        $b = new-object System.Windows.Data.Binding
        $b.source = $DataTable
        [void]$Global:Listview.SetBinding([System.Windows.Controls.ListView]::ItemsSourceProperty,$b)  
        $CountLabel.Content = "Profile Count: {0}" -f ($ListView.DataContext.Rows).count
    }
    [System.Windows.Data.CollectionViewSource]::GetDefaultView( $ListView.ItemsSource ).Refresh()

}

Function PreVistaRemoveProfile {
    Param (
    $ProfilePath,
    $server,
    $type,
    $RegistryPath
    )
    If ($Type -eq 'Registry') {
        $registry = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey("LocalMachine",$server)
        $registry.DeleteSubKeyTree($RegistryPath)
        Remove-Item $ProfilePath -Recurse -Force -ErrorAction SilentlyContinue
    } ElseIf ($Type -eq 'Directory') {
        Try {
            Remove-Item $ProfilePath -Recurse -Force -EA SilentlyContinue
        } Catch {}
    }
}

Function PostVistaRemoveProfile {
    Param (
    $ProfilePath,
    $server,
    $type,
    $WMIPath  
    )
    If ($Type -eq 'WMI') {
        Remove-WmiObject -Path $WMIpath
    } ElseIf ($Type -eq 'Directory') {
        Try {
            Remove-Item $ProfilePath -Recurse -Force -EA SilentlyContinue
        } Catch {}
    }    
}

#Build Query Scriptblock
$previstaqueryscript = (Get-Command PreVistaLocalProfile).definition
$vistaqueryscript = (Get-Command PostVistaLocalProfile).definition
$Global:querysb = [scriptblock]::Create(
    "Function Get-PreVistaProfile {$previstaqueryscript}`
     Function Get-PostVistaProfile {$vistaqueryscript}"
)

#Build Removal Scriptblock
$previstaremovescript = (Get-Command PreVistaRemoveProfile).definition
$postvistarmeovescript = (Get-Command PostVistaRemoveProfile).definition
$Global:removesb = [scriptblock]::Create(
    "Function Remove-PreVistaProfile {$previstaremovescript}`
     Function Remove-PostVistaProfile {$postvistarmeovescript}"
)

#Build the GUI
[xml]$xaml = @"
<Window
    xmlns='http://schemas.microsoft.com/winfx/2006/xaml/presentation'
    xmlns:x='http://schemas.microsoft.com/winfx/2006/xaml'
    x:Name='Window' Title='Profile Removal Tool V1.3' WindowStartupLocation = 'CenterScreen' 
    SizeToContent = 'WidthAndHeight' ResizeMode = 'CanMinimize' ShowInTaskbar = 'True'>
        <Window.Background>
        <LinearGradientBrush StartPoint='0,0' EndPoint='0,1'>
            <LinearGradientBrush.GradientStops> <GradientStop Color='#C4CBD8' Offset='0' /> <GradientStop Color='#E6EAF5' Offset='0.2' /> 
            <GradientStop Color='#CFD7E2' Offset='0.9' /> <GradientStop Color='#C4CBD8' Offset='1' /> </LinearGradientBrush.GradientStops>
        </LinearGradientBrush>
    </Window.Background> 
    <Grid x:Name = 'ParentGrid' ShowGridLines = 'false'>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition Height = '1*'/>
            <RowDefinition Height = '1*'/>
            <RowDefinition Height = 'Auto'/>
            <RowDefinition Height = 'Auto'/>
            <RowDefinition Height = 'Auto'/>
        </Grid.RowDefinitions> 
        <StackPanel Grid.Row = '0' Orientation = 'Horizontal'>
            <TextBox x:Name = 'ComputerTextBox' Width = '200'/> 
            <Button x:Name = 'ComputerButton' Content = 'Connect'/>
            <Label />
            <Button x:Name = 'CancelButton' Content = 'Cancel'/>
        </StackPanel>
        <ListView x:Name = 'ListView' Grid.Row = '1'>
            <ListView.View>
                <GridView x:Name = 'GridView'>
                    <GridViewColumn x:Name = 'UserNameColumn' Width = '100' DisplayMemberBinding = '{Binding Path = UserName}'>
                        <GridViewColumnHeader x:Name = 'UserNameColumnHeader' Content = 'UserName' />
                    </GridViewColumn> 
                    <GridViewColumn x:Name = 'SIDColumn' Width = '295' DisplayMemberBinding = '{Binding Path = SID}'> 
                        <GridViewColumnHeader x:Name = 'SIDColumnHeader' Content = 'SID' />
                    </GridViewColumn>                     
                    <GridViewColumn x:Name = 'LocalPathColumn' Width = '225' DisplayMemberBinding = '{Binding Path = LocalPath}'> 
                        <GridViewColumnHeader x:Name = 'LocalPathColumnHeader' Content = 'LocalPath' />
                    </GridViewColumn>   
                    <GridViewColumn x:Name = 'LastAccessColumn' Width = '140' DisplayMemberBinding = '{Binding Path = LastAccess}'> 
                        <GridViewColumnHeader x:Name = 'LastAccessColumnHeader' Content = 'LastAccess' />
                    </GridViewColumn>                     
                    <GridViewColumn x:Name = 'IsActiveColumn' Width = '75' DisplayMemberBinding = '{Binding Path = IsActive}'> 
                        <GridViewColumnHeader x:Name = 'IsActiveColumnHeader' Content = 'IsActive' />
                    </GridViewColumn>                                                       
                </GridView>
            </ListView.View>
        </ListView>
        <Grid Grid.Row = '2'>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition Height = 'Auto'/>
            <RowDefinition Height = 'Auto'/>
        </Grid.RowDefinitions>         
            <Button x:Name = 'RemoveProfileButton' HorizontalAlignment = 'Left' Grid.Column = '0' Grid.Row = '0' Content = 'Remove Profiles'/>
            <Label x:Name = 'CountLabel' HorizontalAlignment = 'Right' Grid.Column = '1' Grid.Row = '0' Content = 'Profile Count: '/>
        </Grid>
        <ProgressBar x:Name = 'ProgressBar' Grid.Row = '3' Height = '20' ToolTip = 'Displays progress of current action via a graphical progress bar.'> </ProgressBar>   
        <TextBox x:Name = 'StatusTextBox' Grid.Row = '4' IsReadOnly = 'True' ToolTip = 'Displays current status of operation'> Waiting for Action... </TextBox>        
    </Grid>    
</Window>
"@ 

$reader=(New-Object System.Xml.XmlNodeReader $xaml)
$Global:Window=[Windows.Markup.XamlReader]::Load( $reader )

#Connect to Controls
$LastAccessColumnHeader = $Window.FindName('LastAccessColumnHeader')
$Global:RemoveProfileButton = $Window.FindName('RemoveProfileButton')
$CancelButton = $Window.FindName('CancelButton')
$CountLabel = $Window.FindName('CountLabel')
$LocalPathColumnHeader = $Window.FindName('LocalPathColumnHeader')
$SIDColumnHeader = $Window.FindName('SIDColumnHeader')
$UserNameColumnHeader = $Window.FindName('UserNameColumnHeader')
$IsActiveColumnHeader = $Window.FindName('IsActiveColumnHeader')
$Global:ListView = $Window.FindName('ListView')
$Global:ComputerButton = $Window.FindName('ComputerButton')
$ComputerTextBox = $Window.FindName('ComputerTextBox')
$Global:ProgressBar = $Window.FindName('ProgressBar')
$Global:StatusTextBox = $Window.FindName('StatusTextBox')

##Events
#LastAccess columns sort
$LastAccessColumnHeader.Add_Click({
    $Listview.Items.SortDescriptions.Clear() 
    If ($lastaccesssort -eq "descending")  {
        Write-Verbose "Sorting Ascending via UserName Column"
        $lastaccess_ascend = New-Object System.ComponentModel.SortDescription("LastAccess","Ascending")
        $Listview.Items.SortDescriptions.Add($lastaccess_ascend)
        $Listview.Items.Refresh()
        $lastaccesssort = "ascending"
        }
    ElseIf ($lastaccesssort -eq "ascending")  {
        Write-Verbose "Sorting Descending via UserName Column"
        $lastaccess_descend = New-Object System.ComponentModel.SortDescription("LastAccess","Descending")
        $Listview.Items.SortDescriptions.Add($lastaccess_descend)
        $Listview.Items.Refresh()
        $lastaccesssort = "descending"
        }
    Else {
        Write-Verbose "Sorting Ascending via UserName Column"
        $lastaccess_ascend = New-Object System.ComponentModel.SortDescription("LastAccess","Ascending")
        $Listview.Items.SortDescriptions.Add($lastaccess_ascend)
        $Listview.Items.Refresh()
        $lastaccesssort = "ascending"   
        }   
    })

#UserName columns sort
$UserNameColumnHeader.Add_Click({
    $Listview.Items.SortDescriptions.Clear() 
    If ($usernamesort -eq "descending")  {
        Write-Verbose "Sorting Ascending via UserName Column"
        $user_ascend = New-Object System.ComponentModel.SortDescription("UserName","Ascending")
        $Listview.Items.SortDescriptions.Add($user_ascend)
        $Listview.Items.Refresh()
        $usernamesort = "ascending"
        }
    ElseIf ($usernamesort -eq "ascending")  {
        Write-Verbose "Sorting Descending via UserName Column"
        $username_descend = New-Object System.ComponentModel.SortDescription("UserName","Descending")
        $Listview.Items.SortDescriptions.Add($username_descend)
        $Listview.Items.Refresh()
        $usernamesort = "descending"
        }
    Else {
        Write-Verbose "Sorting Ascending via UserName Column"
        $user_ascend = New-Object System.ComponentModel.SortDescription("UserName","Ascending")
        $Listview.Items.SortDescriptions.Add($user_ascend)
        $Listview.Items.Refresh()
        $usernamesort = "ascending"   
        }   
    })

#SID columns sort
$SIDColumnHeader.Add_Click({
    $Listview.Items.SortDescriptions.Clear() 
    If ($sidsort -eq "descending")  {
        Write-Verbose "Sorting Ascending via SID Column"
        $sid_ascend = New-Object System.ComponentModel.SortDescription("SID","Ascending")
        $Listview.Items.SortDescriptions.Add($sid_ascend)
        $Listview.Items.Refresh()
        $sidsort = "ascending"
        }
    ElseIf ($sidsort -eq "ascending")  {
        Write-Verbose "Sorting Descending via SID Column"
        $sid_descend = New-Object System.ComponentModel.SortDescription("SID","Descending")
        $Listview.Items.SortDescriptions.Add($sid_descend)
        $Listview.Items.Refresh()
        $sidsort = "descending"
        }
    Else {
        Write-Verbose "Sorting Ascending via SID Column"
        $sid_ascend = New-Object System.ComponentModel.SortDescription("SID","Ascending")
        $Listview.Items.SortDescriptions.Add($sid_ascend)
        $Listview.Items.Refresh()
        $sidsort = "ascending"   
        }   
    })    

#LocalPath columns sort
$LocalPathColumnHeader.Add_Click({
    $Listview.Items.SortDescriptions.Clear() 
    If ($localpathsort -eq "descending")  {
        Write-Verbose "Sorting Ascending via LocalPath Column"
        $localpath_ascend = New-Object System.ComponentModel.SortDescription("LocalPath","Ascending")
        $Listview.Items.SortDescriptions.Add($localpath_ascend)
        $Listview.Items.Refresh()
        $localpathsort = "ascending"
        }
    ElseIf ($localpathsort -eq "ascending")  {
        Write-Verbose "Sorting Descending via LocalPath Column"
        $localpath_descend = New-Object System.ComponentModel.SortDescription("LocalPath","Descending")
        $Listview.Items.SortDescriptions.Add($localpath_descend)
        $Listview.Items.Refresh()
        $localpathsort = "descending"
        }
    Else {
        Write-Verbose "Sorting Ascending via LocalPath Column"
        $localpath_ascend = New-Object System.ComponentModel.SortDescription("LocalPath","Ascending")
        $Listview.Items.SortDescriptions.Add($localpath_ascend)
        $Listview.Items.Refresh()
        $localpathsort = "ascending"   
        }   
    })   
#IsActive columns sort
$IsActiveColumnHeader.Add_Click({
    $Listview.Items.SortDescriptions.Clear() 
    If ($IsActivesort -eq "descending")  {
        Write-Verbose "Sorting Ascending via IsActive Column"
        $IsActive_ascend = New-Object System.ComponentModel.SortDescription("IsActive","Ascending")
        $Listview.Items.SortDescriptions.Add($IsActive_ascend)
        $Listview.Items.Refresh()
        $IsActivesort = "ascending"
        }
    ElseIf ($IsActivesort -eq "ascending")  {
        Write-Verbose "Sorting Descending via IsActive Column"
        $IsActive_descend = New-Object System.ComponentModel.SortDescription("IsActive","Descending")
        $Listview.Items.SortDescriptions.Add($IsActive_descend)
        $Listview.Items.Refresh()
        $IsActivesort = "descending"
        }
    Else {
        Write-Verbose "Sorting Ascending via IsActive Column"
        $IsActive_ascend = New-Object System.ComponentModel.SortDescription("IsActive","Ascending")
        $Listview.Items.SortDescriptions.Add($IsActive_ascend)
        $Listview.Items.Refresh()
        $IsActivesort = "ascending"   
        }   
    })

#Connect Computer
$ComputerButton.Add_Click({
    $ComputerButton.IsEnabled = $False
    $RemoveProfileButton.IsEnabled = $False
    $Global:Server = $computertextbox.text
    $Global:StatusTextBox.Foreground = "Black"
    $Global:StatusTextBox.Text = "Retrieving list of profiles from $server..." 
    If (Test-Connection -ComputerName $Server -Count 1 -Quiet) {
        $j = Start-Job -InitializationScript $querysb -Name $server -ScriptBlock {
            Param($server)
            If ((Get-WmiObject -ComputerName $server -Class Win32_OperatingSystem).Version -gt 6) {
                Get-PostVistaProfile $server
            } Else {
                Get-PreVistaProfile $server
            }    
        } -argumentList $Server
        Register-ObjectEvent -InputObject $j -EventName StateChanged -Action {
            $VerbosePreference = 'silentlycontinue'
            $EventMessage = $eventsubscriber
            Write-Verbose "Retrieving data from $($eventsubscriber.sourceobject.name)"        
            $Global:status = Receive-Job -Job $eventsubscriber.sourceobject
            #Update UI
            Update-ProfileUI $Status
            Write-Verbose "Updating: $($eventsubscriber.sourceobject.name)"
            Write-Verbose "Removing Event Job"           
            Remove-Job -Job $eventsubscriber.sourceobject
            Write-Verbose "Unregistering Event"           
            Unregister-Event $eventsubscriber.SourceIdentifier
            Write-Verbose "Removing background Job"           
            Remove-Job -Name $eventsubscriber.SourceIdentifier
            $Global:StatusTextBox.Text = "Connected to $server" 
            $ComputerButton.IsEnabled = $True
            $RemoveProfileButton.IsEnabled = $True            
        }    
    } Else {
        $Global:StatusTextBox.Foreground = "Red"
        $Global:StatusTextBox.Text = "$server is unreachable!" 
        $ComputerButton.IsEnabled = $True
        $RemoveProfileButton.IsEnabled = $True                
    }   
})

#Remove Profiles
$RemoveProfileButton.Add_Click({
    If ($Listview.Items.count -gt 0) {
        $ComputerButton.IsEnabled = $False
        $RemoveProfileButton.IsEnabled = $False
        $Global:StatusTextBox.Foreground = "Black"
        $Global:StatusTextBox.Text = "Removing selected profiles from $server..."     
        $profiles = $Listview.SelectedItems | Select -ExpandProperty guid
        [Float]$Global:ProgressBar.Maximum = $profiles.count            
        $Global:updatelayout = [Windows.Input.InputEventHandler]{ $ProgressBar.UpdateLayout() }
        $Global:Start = Get-Date
        [Float]$ProgressBar.Value = 0

        # Read the input and queue it up
        $queue = [System.Collections.Queue]::Synchronized( (New-Object System.Collections.Queue) )

        foreach($item in $profiles) {
            Write-Verbose "Adding $item to queue"
            $queue.Enqueue($item)
        }

        # Start up to the max number of concurrent jobs 
        # Each job will take care of running the rest
        For( $i = 0; $i -lt $maxConcurrentJobs; $i++ ) {
            RemoveProfileJob
        }    
    }    
}) 

#Cancel Button
$CancelButton.Add_Click({
    Write-Verbose "Cancelling currently running operations"
    Get-Job | Remove-Job -Force -ErrorAction SilentlyContinue
    $ComputerButton.IsEnabled = $True
    $RemoveProfileButton.IsEnabled = $True  
    $Global:StatusTextBox.Text = "Operation Cancelled"      
})

#Timer Event
$Window.Add_SourceInitialized({
    #Create Timer object
    Write-Verbose "Creating timer object"
    $Global:timer = new-object System.Windows.Threading.DispatcherTimer 
    #Fire off every 5 seconds
    Write-Verbose "Adding 5 second interval to timer object"
    $timer.Interval = [TimeSpan]"0:0:5.00"
    #Add event per tick
    Write-Verbose "Adding Tick Event to timer object"
    $timer.Add_Tick({
        [Windows.Input.InputEventHandler]{ $Global:Window.UpdateLayout() }
        })
    #Start timer
    Write-Verbose "Starting Timer"
    $timer.Start()
    })

#Window Close Cleanup
$Global:Window.Add_Closed({
    $timer.Stop() 
    #Stop and remove any jobs currently running
    Write-Verbose "Removing PS jobs"
    Get-EventSubscriber | Unregister-Event -Force -ea silentlycontinue
    Get-Job | Remove-Job -Force -ea silentlycontinue
    #Remove global variables   
    Remove-Variable StatusTextBox -Scope Global -ea silentlycontinue
    Remove-Variable ProgressBar -Scope Global -ea silentlycontinue
    Remove-Variable ListView -scope Global -ea silentlycontinue
    Remove-Variable Window -scope Global -ea silentlycontinue 
    Remove-Variable RemoveProfileButton -scope Global -ea silentlycontinue 
    Remove-Variable ComputerButton -scope Global -ea silentlycontinue 
    Remove-Variable Server -scope Global -ea silentlycontinue 
    Remove-Variable Timer -scope Global -ea silentlycontinue 
    Remove-Variable querysb -scope Global -ea silentlycontinue 
    Remove-Variable removesb -scope Global -ea silentlycontinue 
    Remove-Variable updatelayout -scope Global -ea silentlycontinue
    Remove-Variable DataTable -scope Global -ea silentlycontinue  
    })
#Display UI
[void]$Global:Window.ShowDialog()