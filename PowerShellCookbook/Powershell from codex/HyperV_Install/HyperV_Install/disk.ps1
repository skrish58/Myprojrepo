

Function Add-VMNewHardDisk 
{# .ExternalHelp  MAML-VMDisk.XML
    [CmdletBinding(SupportsShouldProcess=$True)]
    param(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $VM,
        
        [int]$ControllerID=0, 
       
        [int]$LUN=0, 
        
        [ValidateNotNullOrEmpty()]
        [string]$VHDPath, 
           
        [ValidateRange(1,127GB)]
        [long]$Size = 127GB, 
        
        [ValidateNotNullOrEmpty()][Alias("ParentDiskPath","ParentPath")]
        [string]$ParentVHDPath,
        
        [parameter()][ValidateNotNullOrEmpty()] 
        [string]$Server = ".", 
        
        [switch]$Fixed, 
        
        [switch]$SCSI,
        $PSC, 
        [switch]$Force
    )
    process {
        if ($psc -eq $null)  {$psc = $pscmdlet} ; if (-not $PSBoundParameters.psc) {$PSBoundParameters.add("psc",$psc)}
        if ($VM -is [String])                   {$VM = Get-VM -Name $VM -Server $Server}
        if ($VM.count -gt 1  -and -not $VHdPath) {[Void]$PSBoundParameters.Remove("VM") ;  $VM | ForEach-object {Add-VMNewHardDisk  -VM $_  @PSBoundParameters}}
        if ($VM.__CLASS -eq 'Msvm_ComputerSystem')  {        	
            if (-not $VHdPath) { $VHDPath = Join-path (Get-VhdDefaultPath -server $vm.__Server) ($vm.elementname + ".VHD")             }
            if ($parentDisk)   { New-VHD -wait -Psc $PSC -force:$force -Server $VM.__Server -VhdPath $vhdPath -parentDisk $ParentDisk  | out-default }
            elseif ($fixed)    { New-VHD -wait -Psc $PSC -force:$force -Server $VM.__Server -VhdPath $vhdPath -Size $size -Fixed       | out-default }
            else               { New-VHD -wait -Psc $PSC -force:$force -Server $VM.__Server -VhdPath $vhdPath -Size $size              | out-default }
            Add-VMDRIVE -psc $PSC -force:$force -VM $VM -ControllerID  $ControllerID -LUN $LUN -scsi:$scsi                             | Out-default 
            Add-VMDISK  -psc $PSC -force:$force -VM $VM -ControllerID  $ControllerID -LUN $LUN -VHDPath $VHDPath -scsi:$scsi           | Out-Default
        }
    }    
}

Function Add-VMDisk
{# .ExternalHelp  MAML-VMDisk.XML
  [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [parameter(ParameterSetName="Path", position=0 , Mandatory = $true, ValueFromPipeline = $true)]
        $VM,
        
        [parameter(ParameterSetName="Path", position=1)]
        [int]$ControllerID = 0,
        
        [parameter(ParameterSetName="Path", position=2)]
        [int]$LUN = 0 ,
        
        [parameter(Mandatory = $true, position=3)][Alias("VHDPath","ISOPath","Fullname")]
        [string]$Path,                #May support Script blocks in future

        [parameter(ParameterSetName="Path")][ValidateNotNullOrEmpty()] 
        $Server="." , #May need to look for VM(s) on Multiple servers
        
        [parameter(ParameterSetName="Path")]
        [switch]$SCSI, 
        
        [parameter(ParameterSetName="Drive")]
        $DriveRASD,
                

        [Alias("DVD")]
        [switch]$OpticalDrive,

        $PSC, 
        [switch]$Force
    )
    process {
        if ($psc -eq $null)  {$psc = $pscmdlet} ; if (-not $PSBoundParameters.psc) {$PSBoundParameters.add("psc",$psc)}
        if ($pscmdlet.ParameterSetName -eq "Path") {
            if ($VM -is [String]) {$VM       =(Get-VM -Name $VM -server $Server) }
            if ($VM.count -gt 1 ) {[Void]$PSBoundParameters.Remove("VM") ;  $VM | ForEach-object {Add-VMDisk -VM $_ @PSBoundParameters}}
            if ($VM.__CLASS -eq 'Msvm_ComputerSystem') {
                $DriveRASD = Get-VMDiskController -vm $vm -ControllerID $ControllerID -SCSI:$scsi -IDE:$(-not $scsi) | Get-VMDriveByController  -Lun $Lun 
                if (-not $driveRASD)  {[Void]$PSBoundParameters.Remove("Path") ; $DriveRASD = Add-vmdrive @PSBoundParameters; $PSBoundParameters.add("Path",$Path)}
            }
        }    
        if ($pscmdlet.ParameterSetName -eq "Drive") {$vm= get-vm $DriveRasd }
        if (($VM.__CLASS -eq 'Msvm_ComputerSystem') -and ($DriveRasd.__CLASS -eq 'Msvm_ResourceAllocationSettingData')) { 
            if ($OpticalDrive) {$diskRASD = New-VMRasd -resType ([ResourceType]::StorageExtent) -resSubType 'Microsoft Virtual CD/DVD Disk' -Server $VM.__Server 
                                if ($path -match "^\w:$") {$path = $(Get-WmiObject -ComputerName $vm.__SERVER -Query "Select * From win32_cdromdrive where Drive='$path'").deviceID }
                                else {Get-WmiObject -ComputerName $vm.__SERVER -Query "Select * From win32_cdromdrive" | foreach -begin {$CDDevices=@()} -process {$CDdevices += $_.deviceID}
                                      if (($Path -notmatch "iso$") -and ($CDdevices -notcontains $path)) {$path += ".ISO"}
                                      }
	    } 
            else                {$diskRASD = New-VMRasd -resType ([ResourceType]::StorageExtent) -resSubType 'Microsoft Virtual Hard Disk'   -Server $VM.__Server 
                                if ($Path -notmatch "VHD$") {$path += ".VHD"}
            }
            if ($Path -match "(\w:|\w)\\\w") {$diskRASD.Connection = $path} 
            else                             {$diskRASD.Connection = (join-path -ChildPath $path -path (Get-VhdDefaultPath -server $diskRasd.__SERVER) ) }
            $diskRASD.parent     = $DriveRasd.__Path 
            add-VmRasd -rasd $diskRasd -vm $vm -PSC $psc -force:$Force
        }
        elseif ($VM -isNOT [Array])  { write-warning $lstr_DriveNotFound }    
    } 
}


Function Add-VMDrive
{# .ExternalHelp  MAML-VMDisk.XML
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [parameter(ParameterSetName="Path" , Mandatory = $true, position=0, ValueFromPipeline = $true)]
        $VM,
        
        [parameter(ParameterSetName="Path" , Mandatory = $true, position=1)]
        [int]$ControllerID ,
        
        [parameter(Mandatory = $true, position=2)]
        [int]$LUN, 
        
        [parameter(ParameterSetName="Drive")]
        $ControllerRASD,
        
        [parameter(ParameterSetName="Path")][ValidateNotNullOrEmpty()]
        $Server = ".",  #May need to look for VM(s) on Multiple servers
       
        [Alias("DVD")]
        [switch]$OpticalDrive,
        
        [parameter(ParameterSetName="Path")]
        [switch]$SCSI,
        $PSC, 
        [switch]$Force
    )
    process {
        if ($psc -eq $null)  {$psc = $pscmdlet} ; if (-not $PSBoundParameters.psc) {$PSBoundParameters.add("psc",$psc)}
        if ($VM  -is [string]) { $VM = Get-VM -Name $VM -Server $Server}
        if ($VM.count -gt 1 )  { [Void]$PSBoundParameters.Remove("VM") ;  $VM | ForEach-object {Add-VMDrive -VM $_  @PSBoundParameters}}
        if ($pscmdlet.ParameterSetName -eq "Path") {
            if ($SCSI)            {$ControllerRASD=(Get-VMDiskController -VM $VM -ControllerID $ControllerID -SCSI)}
            else                  {$ControllerRASD=(Get-VMDiskController -VM $VM -ControllerID $ControllerID  -IDE)}
        }    
        if ($pscmdlet.ParameterSetName -eq "Drive") {$vm=get-vm $ControllerRASD }
        if (($VM.__CLASS -eq 'Msvm_ComputerSystem') -and ($ControllerRASD.__class -eq 'Msvm_ResourceAllocationSettingData') ) {
            if ($OpticalDrive)  { $diskRASD = New-VMRASD -ResType ([ResourceType]::DVDDrive) -ResSubType "Microsoft Synthetic DVD Drive"  -Server $VM.__Server}
            else                { $diskRASD = New-VMRASD -ResType ([ResourceType]::Disk)     -ResSubType "Microsoft Synthetic Disk Drive" -Server $VM.__Server}
            $diskRASD.Parent  = $ControllerRASD.__Path 
            $diskRASD.Address = $LUN
            add-VmRasd -rasd $diskRasd -vm $vm -PSC $psc -force:$force
        }
    }    
}


Function Add-VMFloppyDisk
{# .ExternalHelp  MAML-VMDisk.XML
    [CmdletBinding(SupportsShouldProcess=$true)]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeline = $true)]
        $VM,
        
        [parameter(Mandatory = $true)]
        [Alias("VFDPath")]
        $Path, 
        
        [parameter()][ValidateNotNullOrEmpty()] 
        $Server=".",  #May need to look for VM(s) on Multiple servers 
        $PSC,
        [Switch]$Force 
    )
    process{
        if ($psc -eq $null)  {$psc = $pscmdlet} 
        if ($VM -is [String]) {$VM=(Get-VM -Name $VM -server $Server) }
        if ($VM.count -gt 1 ) {[Void]$PSBoundParameters.Remove("VM") ;  $VM | ForEach-object {Add-VMFloppyDisk -VM $_ @PSBoundParameters}}
        if ($VM.__CLASS -eq 'Msvm_ComputerSystem') { 
                if ($Path -is [System.IO.FileInfo] )    {$Path = $Path.fullname } 
                if ($Path -notmatch "(\w:|\w)\\\w")     {$Path = join-path (Get-VhdDefaultPath $Server) $Path }
                if ($Path -notmatch "VFD$" )            {$Path = $Path + ".vfd"}
                if ($vm.__server -eq $env:COMPUTERNAME) {$path = (Resolve-Path $path -ErrorAction "silentlyContinue").path } 
                if ($path) {
                    $diskRASD=NEW-VMRasd -resType ([resourcetype]::StorageExtent) -resSubType 'Microsoft Virtual Floppy Disk' -server $vm.__Server 
                    $diskRASD.parent=(Get-WmiObject -computerName $vm.__server -NameSpace $HyperVNamespace -Query "Select * From MsVM_ResourceAllocationSettingData Where instanceId Like 'Microsoft:$($vm.name)%' and resourceSubtype = 'Microsoft Synthetic Diskette Drive'").__Path
                    $diskRASD.connection=$Path
                    add-VmRasd -rasd $diskRasd -vm $vm -PSC $psc -force:$force 
                } 
        }
   }     
}


Function Add-VMPassThrough
{# .ExternalHelp  MAML-VMDisk.XML
   [CmdletBinding(SupportsShouldProcess=$true)] 
   Param(
         [parameter(ParameterSetName="Path" , Mandatory = $true, ValueFromPipeline = $true)]
        $VM,
        
        [parameter(ParameterSetName="Path" , Mandatory = $true)]
        [int]$ControllerID ,
        
        [parameter(Mandatory = $true)]
        [int]$LUN, 
     
        [parameter(Mandatory = $true)]
        $PhysicalDisk,
     
        
        [parameter(ParameterSetName="Path")][ValidateNotNullOrEmpty()]
        $Server = ".",  #May need to look for VM(s) on Multiple servers if $physical disk is clustered
       
        [parameter(ParameterSetName="Path")]     
        [switch]$SCSI,
        
        [parameter(ParameterSetName="Drive")]
        $ControllerRASD,
       
        $PSC, 
        [switch]$Force
    )
    if ($psc -eq $null)  {$psc = $pscmdlet} 
    if ($pscmdlet.ParameterSetName -eq "Path") {
        if ($VM -is [String])  {$VM=(Get-VM -Name $VM -Server $server) }
        if ($SCSI) {$ControllerRASD=(Get-VMDiskController -vm $vm -ControllerID $ControllerID -SCSI)}
        else       {$ControllerRASD=(Get-VMDiskController -vm $vm -ControllerID $ControllerID -IDE) }
    }
    if ($pscmdlet.ParameterSetName -eq "Drive") {$vm=get-vm $ControllerRASD }
    if (($VM.__CLASS -eq 'Msvm_ComputerSystem') -AND  ($ControllerRASD.__CLASS -eq 'Msvm_ResourceAllocationSettingData')){ 
        $diskRASD = NEW-VMRasd -resType ([resourcetype]::disk)  -resSubType 'Microsoft Physical Disk Drive'   -server $vm.__Server
        $diskRASD.parent       = $ControllerRASD.__Path 
        $diskRASD.address      = $Lun
        $diskRASD.HostResource = [string]$PhysicalDisk.__path
        add-VmRasd -rasd $diskRasd -vm $vm -PSC $psc -force:$force  
 }
}


Function Add-VMSCSIController
{# .ExternalHelp  MAML-VMDisk.XML
    [CmdletBinding(SupportsShouldProcess=$true)]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeLine = $true)] 
        $VM,     
        
        [String]$Name=$lstr_VMBusSCSILabel,
        
        [parameter()][ValidateNotNullOrEmpty()] 
        $Server = ".",     #May need to look for VM(s) on Multiple servers
        $PSC, 
        [switch]$Force
    )
    process {
        if ($psc -eq $null)  {$psc = $pscmdlet} ; if (-not $PSBoundParameters.psc) {$PSBoundParameters.add("psc",$psc)}
        if ($VM -is [String]) {$VM=(Get-VM -Name $VM -Server $Server) }
        if ($VM.count -gt 1 ) {[Void]$PSBoundParameters.Remove("VM") ;  $VM | ForEach-object {Add-VMSCSIController -VM $_ @PSBoundParameters}}
        if ($VM.__CLASS -eq 'Msvm_ComputerSystem') {
            $SCSIRASD=NEW-VMRasd -ResType ([resourcetype]::ParallelSCSIHBA) -ResSubtype 'Microsoft Synthetic SCSI Controller' -Server $vm.__Server
            $SCSIRASD.elementName=$name
            add-VmRasd -rasd $SCSIRasd -vm $vm -PSC $psc -force:$force
       }
    }     
}


Function Compress-VHD
{# .ExternalHelp  MAML-VMDisk.XML    
    [CmdletBinding(SupportsShouldProcess=$True )]
    param(
         [parameter(Mandatory = $true, ValueFromPipelineByPropertyName =$true,ValueFromPipeline =$true)][Alias("Fullname","Path","DiskPath")][ValidateNotNullOrEmpty()]
        [string[]]$VHDPaths,              #Accept One string, multiple string, or convert objects to string from one of their properties. 
      
        [parameter(ValueFromPipelineByPropertyName =$true)][Alias("__Server")][ValidateNotNullOrEmpty()] 
        [string]$Server = ".",   #Only work with images on one server  
        
        [switch]$Wait,
        $PSC, 
        [switch]$Force
    )
    process {
        if ($psc -eq $null)  {$psc      = $pscmdlet} ; if (-not $PSBoundParameters.psc) {$PSBoundParameters.add("psc",$psc)}
        write-debug "Before Resolution VHDPaths = $VHDPaths"
       Foreach ($vhdPath in $vhdPaths) {
            if ($VHDPath -notmatch "(\w:|\w)\\\w") {$VHDPath   = Join-Path $(Get-VhdDefaultPath $Server) $VHDPath }
            if ($vhdpath -notmatch "VHD$" )        {$vhdPath  += ".VHD"}
            if ($Server -eq ".")                   {$VHDPath     = (Resolve-Path $VHDPath -errorAction "SilentlyContinue") | foreach-object {($_.path)} 
                                                    if ($vhdPath -is [array]) {[Void]$PSBoundParameters.Remove("VHDPaths"); Compress-VHD -VHDPaths $VHdpath @PSBoundParameters}      
            }
            write-debug "After Resolution VHDPath = $VHDPath"
            if ($vhdpath -is [string] -and ($force -or $psc.shouldProcess($VHDPath,$Lstr_VHDcompacting))) {          
                $ImageManagementService = Get-WmiObject -ComputerName $Server -Namespace $HyperVNamespace -Class $ImageManagementServiceName
                $ImageManagementService.CompactVirtualHardDisk($VHDPath) | Test-wmiResult -wait:$wait -JobWaitText ($Lstr_VHDcompacting + $vhdPath)`
                     -SuccessText ($Lstr_VHDcompactSuccess -f $vhdPath) -failText ($Lstr_VHDcompactFailure -f $vhdPath)    
            }
        }              
    }
}


Function Connect-VHDParent
{# .ExternalHelp  MAML-VMDisk.XML    
    [CmdletBinding(SupportsShouldProcess=$True )]
    param(
    
        [parameter(Mandatory = $true, ValueFromPipelineByPropertyName =$true,ValueFromPipeline =$true)][Alias("Fullname","Path","DiskPath")][ValidateNotNullOrEmpty()]
        [string[]]$VHDPaths,              #Accept One string, multiple string, or convert objects to string from one of their properties. 
        
        [parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][Alias("ParentDiskPath","ParentPath")]
        $ParentVHDPath,   
  
        [parameter()][ValidateNotNullOrEmpty()] 
        [string]$Server = ".",  #Only work with images on one server  
   
        $PSC, 
        [switch]$force
    )
    process {  
        write-debug "Before Resolution VHDPaths = $VHDPaths"
        if ($psc -eq $null)                        {$psc = $pscmdlet} ; if (-not $PSBoundParameters.psc) {$PSBoundParameters.add("psc",$psc)}
         ForEach ($VHDPath in $vhdPaths) {
            if ($VHDPath -notmatch "(\w:|\w)\\\w") {$VHDPath     = Join-Path $(Get-VhdDefaultPath $Server) $VHDPath }
            if ($vhdpath -notmatch "VHD$" )        {$vhdPath    += ".VHD"}    
            if ($Server -eq ".")                   {$VHDPath     = (Resolve-Path $VHDPath -errorAction "SilentlyContinue") | foreach-object {($_.path)} 
                                                    if ($vhdPath -is [array]) {[Void]$PSBoundParameters.Remove("VHDPaths") ; Connect-VHDParent -VHDPaths $VHdpath @PSBoundParameters} 
            }
            If ($vhdPath -is [String]){
                if ($ParentVHDPath -is [scriptblock]  ){$Parent      = Invoke-Expression $(".{$ParentVHDPath}") } else {$Parent = $ParentVHDPath}
                write-debug "Before Resolution Parent = $Parent"
                if ($Parent -notmatch "(\w:|\w)\\\w")  {$Parent      = Join-Path $(Get-VhdDefaultPath $Server) $Parent}
                if ($Parent -notmatch "VHD$" )         {$Parent     += ".VHD"}
                if ($Server -eq ".")                   {$Parent      = (Resolve-Path $Parent -ErrorAction "silentlyContinue" ).path }
            }
            write-Debug "After resolution: VHD = $vhdpath Parent =  $Parent" 
            if ($vhdpath -is [string] -and $Parent -is [string] -and ($force -or $psc.shouldProcess($VHDPath,$Lstr_VHDconnecting  ))) {          
                $ImageManagementService = Get-WmiObject -ComputerName $Server -Namespace $HyperVNamespace -Class $ImageManagementServiceName
                 $ImageManagementService.ReconnectParentVirtualHardDisk($VHDPath,$parent,$true) | Test-wmiResult -wait -JobWaitText ($Lstr_VHDconnecting + $vhdPath)`
                     -SuccessText ($Lstr_VHDconnectSuccess -f $vhdPath) -failText ($Lstr_VHDconnectFailure -f $vhdPath)    
            }
        }         
    }
}

Function Convert-VHD
{# .ExternalHelp  MAML-VMDisk.XML
    [CmdletBinding(SupportsShouldProcess=$True )]
    param(
        [parameter(Mandatory = $true, ValueFromPipelineByPropertyName =$true,ValueFromPipeline =$true)][Alias("Fullname","Path","DiskPath")][ValidateNotNullOrEmpty()]
        [string[]]$VHDPaths,          
        
        [parameter(Mandatory = $true)]
        [Alias("Destination","NewName")]
        $DestPath, #  can be a string or script block for example > dir d:\vhds | get-vhdinfo | where {$_.typeName -eq "Dynamic"} | convert-vhd -dest {$_ -replace ".VHD","-Fixed.VHD" } -type fixed
        
        [Parameter(Mandatory = $true)]
        [VHDType]$Type,
        
        [parameter(ValueFromPipelineByPropertyName =$true)][Alias("__Server")][ValidateNotNullOrEmpty()] 
        [string]$Server = ".",   #Only work with images on one server  
         
        [switch]$Wait,
        $PSC, 
        [switch]$Force
    )
    Process {
        write-debug "Before Resolution VHDPaths = $VHDPaths"
        foreach ($vhdpath in $vhdpaths) {
            if ($psc -eq $null)  {$psc = $pscmdlet} ; if (-not $PSBoundParameters.psc) {$PSBoundParameters.add("psc",$psc)}
            if ($VHDPath -notmatch "(\w:|\w)\\\w")         {$VHDPath      = Join-Path $(Get-VhdDefaultPath $Server) $VHDPath }
            if ($vhdpath -notmatch "VHD$" )                {$vhdPath     += ".VHD"}
            if ($Server -eq ".")                           {$VHDPath    = (Resolve-Path $VHDPath -errorAction "SilentlyContinue") | foreach-object {($_.path)} 
                                                           if ($vhdPath -is [array]) {[Void]$PSBoundParameters.Remove("VHDPaths") ; Convert-VHD -VHDPaths $VHdpath @PSBoundParameters}      
            }
            if ($vhdpath -is [string]) {
                if ($DestPath -is [scriptblock]  )             {$Destination  = Invoke-Expression $(".{$DestPath}") } else {$destination = $DestPath}
                write-debug "Before resolution Destination = $destination" 
                if ($Destination -match "^\.\\")               {$Destination  = Join-Path $pwd $(Split-Path $Destination -Leaf)  }  
                if ($Destination -notmatch "(\w:|\w)\\\w")     {$Destination  = Join-Path $(Get-VhdDefaultPath $Server) $Destination }
                if ($Destination -notmatch ".VHD$" )           {$Destination += ".VHD"}
                if (($Server -eq ".") -and -not (Test-path -path $Destination -IsValid)) {$Destination = $null } 
            }    
            write-Debug "After resolution: VHD = $vhdpath Destination =  $destination, server = $server "
            if ($vhdpath -is [string] -and  $Destination -Is [String] -and ($force -or $psc.shouldProcess($VHDPath,($Lstr_VHDConversion -f $destination)))) {  
                $ImageManagementService = Get-WmiObject -ComputerName $Server -Namespace $HyperVNamespace -Class $ImageManagementServiceName 
                $ImageManagementService.ConvertVirtualHardDisk($VHDPath, $Destination, $type) | Test-wmiResult -wait:$wait -JobWaitText ($Lstr_VHDConverting -f $vhdPath,$Destination)`
                     -SuccessText ($Lstr_VHDConvertSuccess -f $vhdPath,$Destination) -failText ($Lstr_VHDConvertFailure -f $vhdPath,$Destination)     
            }
        }
    }    
}


Function Dismount-VHD
{# .ExternalHelp  MAML-VMDisk.XML
    [CmdletBinding(SupportsShouldProcess=$True , ConfirmImpact='High' )]
    param(
        [parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true, valueFromPipeline=$true)][ValidateNotNullOrEmpty()][Alias("path","FullName")]
        [string[]]$VHDPaths,
        
        [parameter(ValueFromPipelineByPropertyName =$true)][Alias("__Server")][ValidateNotNullOrEmpty()] 
        [string]$Server = ".",   #Only work with images on one server  
        
        $PSC, 
        [switch]$Force
    )
    process {
        if ($psc -eq $null)  {$psc = $pscmdlet} ; if (-not $PSBoundParameters.psc) {$PSBoundParameters.add("psc",$psc)}
        write-debug "Before Resolution VHDPaths = $VHDPaths"
        Foreach ($vhdPath in $vhdPaths) {
            if ($vhdpath -notmatch ".VHD$" )       {$vhdPath += ".VHD"}
            if ($VHDPath -notmatch "(\w:|\w)\\\w") {$VHDPath  = Join-Path (Get-VhdDefaultPath)  $VHDPath }
            if ($Server -eq ".")                   {$VHDPath    = (Resolve-Path $VHDPath -errorAction "SilentlyContinue") | foreach-object {($_.path)} 
                                                     if ($vhdPath -is [array]) {[Void]$PSBoundParameters.Remove("VHDPaths") ; Dismount-vhd -VHDPaths $VHdpath  @PSBoundParameters}
            }      
            write-debug "After Resolution VHDPath = $VHDPath"
            if (($vhdPath -is [String] )) {
                if ($force -or $psc.shouldProcess($VHDPath,$lStr_DiskDismounting)) {
                    Get-VHDMountPoint -VHDPath $VHDPath | foreach-object {Remove-PSDrive -Name $_.deviceID.substring(0,1) -ErrorAction SilentlyContinue }
                    $ImageManagementService = Get-WmiObject -Namespace $HyperVNamespace -Class $ImageManagementServiceName
                    Test-wmiResult -result ($ImageManagementService.Unmount($VHDPath)) -wait -JobWaitText ($lStr_DiskDismounting + $vhdPath) `
                            -SuccessText ($lStr_DiskDismountSuccess -f $vhdPath) -failText ($lStr_DiskDismountFailed -f $vhdPath)  
                }
            }
       }
   }        
}


Function Expand-VHD
{# .ExternalHelp  MAML-VMDisk.XML
    [CmdletBinding(SupportsShouldProcess=$True )]
    param(
        [parameter(Mandatory=$true, ValueFromPipelineByPropertyName =$true, ValueFromPipeline=$true)]
        [ValidateNotNullOrEmpty()][Alias("Fullname","Path","DiskPath")]
        [String[]]$VHDPaths,                #may expand multiple VHDs 
        
        [ValidateRange(1gb,2040GB)]
        [long]$Size = 127GB,
        
        [parameter(ValueFromPipelineByPropertyName =$true)][Alias("__Server")][ValidateNotNullOrEmpty()] 
        [string]$Server = ".",   #Only work with images on one server  
        
        [switch]$Wait,
        $PSC, 
        [switch]$force
    )
    process {
        if ($psc -eq $null)  {$psc = $pscmdlet} ; if (-not $PSBoundParameters.psc) {$PSBoundParameters.add("psc",$psc)}
        write-debug "Before Resolution VHDPaths = $VHDPaths"
        Foreach ($VHDPath in $VHDPaths) {
            if ($VHDPath -notmatch "(\w:|\w)\\\w") {$VHDPath     = Join-Path $(Get-VhdDefaultPath $Server) $VHDPath }
            if ($vhdpath -notmatch "VHD$" )        {$vhdPath    += ".VHD"}        
            if ($Server -eq ".")                   {$VHDPath    = (Resolve-Path $VHDPath -errorAction "SilentlyContinue") | foreach-object {($_.path)} 
                                                     if ($vhdPath -is [array]) {[Void]$PSBoundParameters.Remove("VHDPaths") ; Expand-VHD -VHDPaths $VHdpath  @PSBoundParameters}
            }
            write-debug "After Resolution VHDPath = $VHDPath"    
            if ($vhdpath -is [string] -and ($force -or $psc.shouldProcess($VHDPath,$Lstr_VHDExpanding))) {  
                $ImageManagementService = Get-WmiObject -ComputerName $Server -Namespace $HyperVNamespace -Class $ImageManagementServiceName
                $currentSize            = (Get-VHDInfo -VHDPath $VHDPath -Server $Server).MaxInternalSize
                if ($Size -gt $currentSize) {
                    if ( ($ImageManagementService.ExpandVirtualHardDisk($VHDPath, $Size) | Test-wmiResult -wait:$wait -JobWaitText ($Lstr_VHDExpanding + $vhdPath)`
                                -SuccessText ($Lstr_VHDexpansionSuccess -f $vhdPath) -failText ($Lstr_VHDexpansionFailure -f $vhdPath) ) -eq [returnCode]::ok) {Get-VHDInfo -VHDPath $VHDPath -Server $Server }
                }   
                Else  {write-warning ($lstr_VHDExpandNotContract -f $VHDPath, $currentSize, $size) }
           }
       }
    }
}                

Function Get-VHD
{# .ExternalHelp  MAML-VMDisk.XML
    Param (
        [parameter(ValueFromPipelineByPropertyName  = $true, ValueFromPipeline  = $true)]
        [ValidateNotNullOrEmpty()][Alias("Fullname","VHDPath","DiskPath")]
        [String[]]$Paths ,       #Only accept a single search path 
        
        [parameter()][ValidateNotNullOrEmpty()] 
        $Server="."          #may need to get images from multiple servers   
    )
    process {
        ForEach ($path in $paths)  {
            if (-not $path) {$path = (Get-VhdDefaultPath -server $server)}
            $d = get-wmiobject -ComputerName $server -query ("select * from Win32_Directory where name='{0}'" -f $path.replace('\','\\') )
            if ($d) {$d.getrelated("cim_datafile")  | where-object {$_.extension -eq "VHD"} | Add-Member -MemberType ALIASPROPERTY -Name "fullname" -Value "Name" -PassThru |
                                                      Add-Member -MemberType ALIASPROPERTY -Name "Size" -Value "FileSize" -PassThru |sort-object -Property name }   
            else    { write-warning $lstr_DirectoryNotFound }
        }
    }
}



Function Get-VhdDefaultPath
{# .ExternalHelp  MAML-VMDisk.XML
    param ([parameter()][ValidateNotNullOrEmpty()]
           [String]$Server=".")    #Only work with images on one server  
    (Get-WmiObject -computerName $server -NameSpace $HyperVNamespace -Class "MsVM_VirtualSystemManagementServiceSettingData").DefaultVirtualHardDiskPath
}


Function Get-VHDInfo 
{# .ExternalHelp  MAML-VMDisk.XML
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true, ValueFromPipelineByPropertyName =$true,ValueFromPipeline =$true)][Alias("Fullname","Path","DiskPath")][ValidateNotNullOrEmpty()]
        [string[]]$VHDPaths,              #Accept One string, multiple string, or convert objects to string from one of their properties. 
        
        [parameter(ValueFromPipelineByPropertyName =$true)][Alias("__Server")][ValidateNotNullOrEmpty()] 
        [string]$Server = "."   #Only work with images on one server  
    )
    process {
        write-debug "Before Resolution VHDPaths = $VHDPaths"
         foreach ($vhdPath in $vhdPaths) {
            if ($VHDPath -notmatch "(\w:|\w)\\\w") {$VHDPath = Join-Path $(Get-VhdDefaultPath $Server) $VHDPath }
            if ($vhdpath -notmatch ".VHD$" )       {$vhdPath += ".VHD"}
            if ($Server -eq ".") {$VHDPath  = (Resolve-Path $VHDPath -errorAction "SilentlyContinue") | foreach-object {($_.path)} 
                                  if ($vhdPath -is [array]) {Get-vhdInfo -VHDPaths $vhdpath} }
            write-debug "After Resolution VHDPath = $VHDPath"
            if ($vhdpath -is [string])  { 
        	    $ImageManagementService = Get-WmiObject -ComputerName $Server -Namespace $HyperVNamespace -Class $ImageManagementServiceName
                $result = $ImageManagementService.GetVirtualHardDiskInfo($vhdPath)
                if ($result.returnValue -eq [ReturnCode]::OK) {
                    ([XML]$Result.info).SelectNodes("/INSTANCE/PROPERTY") | 
                        Foreach-object -begin   { $VHDObj = New-Object -TypeName System.Object
                                                  Add-Member -inputObject $VHDObj -MemberType NoteProperty -Name "Path"     -Value $vhdPath
                                        }`
                                       -process { Add-Member -inputObject $VHDObj -MemberType NoteProperty -Name $_.Name    -Value $_.Value} `
                                       -end     { Add-Member -inputObject $VHDObj -MemberType NoteProperty -Name "TypeName" -Value ([VHDType]$VHDObj.type)
						  Add-member -inputObject $VHDObj -MemberType scriptMethod -Name "ToString" -Value {$this.path} -force
                                                  $VHDObj }
                 }
                 else {Write-Error ($Lstr_GetDiskInfoFailed -f $VhdPath, [ReturnCode]$result.returnValue ) }
            }
       }
    }
}	


Function Get-VHDMountPoint 
{# .ExternalHelp  MAML-VMDisk.XML
    param(
        [parameter(Mandatory = $true, ValueFromPipelineByPropertyName =$true,ValueFromPipeline =$true)][Alias("Fullname","Path","DiskPath")][ValidateNotNullOrEmpty()]
        [string[]]$VHDPaths  ,            #Accept One string, multiple string, or convert objects to string from one of their properties. 
        [parameter(ValueFromPipelineByPropertyName =$true)][Alias("__Server")][ValidateNotNullOrEmpty()] 
        [string]$Server = "."   #Only work with images on one server  
    )
    Process {
        write-debug "Before Resolution VHDPaths = $VHDPaths"
       Foreach ($vhdPath in $vhdPaths) {
            if ($VHDPath -notmatch "(\w:|\w)\\\w") { $VHDPath = Join-Path $(Get-VhdDefaultPath $Server) $VHDPath }
            if ($vhdpath -notmatch ".VHD$" )       {$vhdPath += ".VHD"}
            if ($Server -eq ".")                   {$VHDPath     = (Resolve-Path $VHDPath -errorAction "SilentlyContinue") | foreach-object {($_.path)} 
                                                    if ($vhdPath -is [array]) {Get-VHDMountPoint -VHDPaths $VHdpath }
            }      
            write-debug "After Resolution VHDPath = $VHDPath, Server =$server"
            if ($vhdPath -is [String]){
        	    $MountedDiskImage = Get-WmiObject -ComputerName $server -Namespace $HyperVNamespace `
                                                  -Query ("select * from Msvm_MountedStorageImage where name='" + $vhdpath.replace("\","\\") + "' ")
                if ($MountedDiskImage) {(Get-WmiObject -ComputerName $server `
                                                      -Query ("SELECT * FROM Win32_DiskDrive WHERE Model='Msft Virtual Disk SCSI Disk Device' " + 
                                                                                           " AND ScsiTargetID=$($MountedDiskImage.TargetId)  " + 
                                                                                           " AND ScsiLogicalUnit=$($MountedDiskImage.Lun)    " + 
                                                                                           " AND ScsiPort=$($MountedDiskImage.PortNumber)"
                                                             )).getRelated("Win32_DiskPartition") |
                                                             foreach-object {$_.getRelated("win32_logicalDisk")} | 
                                                             Add-Member -MemberType NoteProperty -Name "Vhdpaths" -Value $vhdPath -PassThru
                }
            }
        }                       
    }
}


Function Get-VMDisk
{# .ExternalHelp  MAML-VMDisk.XML
    param(
        [parameter( ValueFromPipeline = $true)]
        $VM="%" , 
        
        [parameter()][ValidateNotNullOrEmpty()] 
        $Server =".",      #May need to look for VM(s) on Multiple servers
        
        [switch]$snapshot)
    process {     
        if ($vm -is [String]) {$vm = get-vm -Name $vm -Server $Server}
        if ($VM.count -gt 1 )  {[Void]$PSBoundParameters.Remove("VM") ;  $VM | ForEach-object {Get-VMDisk -VM $_ @PSBoundParameters}}
        If ($VM.__CLASS -eq 'Msvm_ComputerSystem')  {
           if ($snapshot)        {$VM = (,$VM + (get-vmsnapshot $vm)  | sort elementname) }
           foreach ($v in $vm) {
             foreach ($dc in (get-vmdiskcontroller -vm $v)) {
                 foreach ($drive in (Get-VMDriveByController -controller $dc)) {
                    if   ($drive.ResourceSubType -eq 'Microsoft Physical Disk Drive') {$drive | select-object -property `
                                                       @{name="VMElementName";        expression={$v.elementName}},
                                                       @{name="VMGUID";               expression={$v.Name}},
                                                       @{name="ControllerName";       expression={$dc.elementName}},
                                                       @{name="ControllerInstanceID"; expression={$dc.InstanceId}},
                                                       @{name="ControllerID";         expression={$dc.instanceID.split("\")[-1]}},
                                                       @{name="DriveName";            expression={"Passthrough Disk"}} ,
                                                       @{name="DriveInstanceID";      expression={$drive.instanceID}},
                                                       @{name="DriveLUN";             expression={$drive.address}},
                                                       @{name="DiskPath";             expression={"Physical drive: " + ([wmi]($drive.HostResource[0])).elementname}},
                                                       @{name="DiskImage";            expression={"Physical drive: " + ([wmi]($drive.HostResource[0])).elementname}},
                                                       @{name="DiskName";             expression={$_.ElementName}},
                                                       @{name="DiskInstanceID";       expression={$_.InstanceID}} 
                    }
                    else {$d= get-vmdiskByDrive -drive $drive 
                          if ($d) {$d | select-object -property `
                                                       @{name="VMElementName";        expression={$v.elementName}},
                                                       @{name="VMGUID";               expression={$v.Name}},
                                                       @{name="ControllerName";       expression={$dc.elementName}},
                                                       @{name="ControllerInstanceID"; expression={$dc.InstanceId}},
                                                       @{name="ControllerID";         expression={$dc.instanceID.split("\")[-1]}},
                                                       @{name="DriveName";            expression={$drive.caption}} ,
                                                       @{name="DriveInstanceID";      expression={$drive.instanceID}},
                                                       @{name="DriveLUN";             expression={$drive.address}},
                                                       @{name="DiskPath";             expression={$_.Connection}},
                                                       @{name="DiskImage";            expression={$p=$_.Connection[0] ; while ($p.toupper().EndsWith(".AVHD")) { $p=(Get-VHDInfo -vhdpath $p -Server $_.__server ).parentPath } ; $p}},
                                                       @{name="DiskName";             expression={$_.ElementName}},
                                                       @{name="DiskInstanceID";       expression={$_.InstanceID}} 
                          }
                          else  { $drive  | select-object -property `
                                                       @{name="VMElementName";        expression={$v.elementName}},
                                                       @{name="VMGUID";               expression={$v.Name}},
                                                       @{name="ControllerName";       expression={$dc.elementName}},
                                                       @{name="ControllerInstanceID"; expression={$dc.InstanceId}},
                                                       @{name="ControllerID";         expression={$dc.instanceID.split("\")[-1]}},
                                                       @{name="DriveName";            expression={$_.Caption}} ,
                                                       @{name="DriveInstanceID";      expression={$drive.instanceID}},
                                                       @{name="DriveLUN";             expression={$drive.address}},
                                                       @{name="DiskPath";             expression={$null}},
                                                       @{name="DiskImage";            expression={$null}},
                                                       @{name="DiskName";             expression={$null}},
                                                       @{name="DiskInstanceID";       expression={$null}} 
                                                       
                          }
                    }
                }
            }
         }   
        }
    }   
}


Function Get-VMDiskByDrive
{# .ExternalHelp  MAML-VMDisk.XML
    Param (
        [parameter(Mandatory = $true, ValueFromPipeLine = $true)]
        $Drive
    )
    process { 
        if ($Drive.count -gt 1 ) {$Drive | ForEach-Object {get-vmdiskByDrive -Drive $_} }
        if ($Drive.__CLASS -eq 'Msvm_ResourceAllocationSettingData') {
            If ($Drive.ResourceSubType -eq "Microsoft Physical Disk Drive") {$Drive}
            else {
                $DrivePath=$Drive.__Path.replace("\","\\")
                Get-WmiObject -computerName $drive.__server -Query "Select * From MsVM_ResourceAllocationSettingData Where PARENT='$DrivePath' " -NameSpace $HyperVNamespace |
                Add-Member -passthru -name "VMElementName" -MemberType noteproperty   -value $($Drive.VMelementName) 
            }
        }
    }
}


Function Get-VMDiskController
{# .ExternalHelp  MAML-VMDisk.XML
    [CmdletBinding()]
    param(
        [parameter(ValueFromPipeline = $true)]
        $VM = "%" ,
        
        $ControllerID="*",
        
        [parameter()][ValidateNotNullOrEmpty()] 
        $Server = ".",  #May need to look for VM(s) on Multiple servers
        
        [switch] $SCSI,
        
        [switch]$IDE
    )
    Process { get-vmsettingData -vm $vm -server $SERVER | foreach-object {
                $VMRASD = $_.getRelated("MSVM_ResourceAllocationSettingData")
 #               $VMRASD = Get-WmiObject -ComputerName $Server -Namespace $HyperVNamespace -Query "ASSOCIATORS OF {$_} where ResultClass = MSVM_ResourceAllocationSettingData"
                if ((-not $scsi) -and (-not $IDE) -and ($ControllerID -eq "*"))  {
                     $VMRASD |  Where-Object {($_.ResourceSubType -eq 'Microsoft Emulated IDE Controller') -or ($_.ResourceSubType -eq 'Microsoft Synthetic SCSI Controller')}
                }
                elseif ($scsi) {
                    $controllers =  $VMRASD | Where-Object {$_.ResourceSubType -eq 'Microsoft Synthetic SCSI Controller'}
    		            if ($controllerID -ne "*") {$controllers | select-object -first ([int]$controllerID + 1)  | select -last 1  }
                        else                       {if ($controllers) {$controllers}  }
                }    
                elseif ($IDE) { $VMRASD |  where-object  {($_.ResourceSubType -eq  'Microsoft Emulated IDE Controller') -and ($_.address -like $ControllerID)} |
                                           Add-Member -passthru -name "VMElementName" -MemberType noteproperty   -value $($vm.elementName) 
                 }
    }}
}


Function Get-VMDriveByController
{# .ExternalHelp  MAML-VMDisk.XML
    Param (
        [parameter(Mandatory = $true, ValueFromPipeLine = $true)]
        $Controller, 
        $LUN="%" 
    )
    process {
        if ($Controller.count -gt 1 ) {$Controller | ForEach-Object {Get-VMDriveByController -Controller  $_ -LUN $Lun} }
        if ($Controller.__CLASS -eq 'Msvm_ResourceAllocationSettingData') {
            $CtrlPath=$Controller.__Path.replace("\","\\")
            Get-WmiObject -computerName $controller.__server  -NameSpace $HyperVNamespace -Query "Select * From MsVM_ResourceAllocationSettingData Where PARENT='$ctrlPath' and Address Like '$Lun' "  | 
            Add-Member -passthru -name "VMElementName" -MemberType noteproperty   -value $($Controller.VMelementName) 
        }
    }
}


Function Get-VMFloppyDisk
{# .ExternalHelp  MAML-VMDisk.XML
    param(
        [parameter(ValueFromPipeline = $true)]
        $VM="%",
        
        [parameter()][ValidateNotNullOrEmpty()] 
        $Server="."
    )
    process {
        if ($VM -is [String]) {$VM=(Get-VM -Name $VM -Server $Server) }
        if ($VM.count -gt 1 ) {[Void]$PSBoundParameters.Remove("VM") ;  $VM | ForEach-object {Get-VMFloppyDisk -VM $_  @PSBoundParameters}}
        if ($vm.__CLASS -eq 'Msvm_ComputerSystem') {
            Get-WmiObject -computerName $vm.__server -NameSpace $HyperVNamespace -Query "Select * From MsVM_ResourceAllocationSettingData Where instanceId Like 'Microsoft:$($vm.name)%' and resourceSubtype = 'Microsoft Virtual Floppy Disk'"}
   }
}


Function Merge-VHD
{# .ExternalHelp  MAML-VMDisk.XML
   [CmdletBinding(SupportsShouldProcess=$True )]
    param(
        [parameter(Mandatory = $true, ValueFromPipelineByPropertyName  = $true,ValueFromPipeline =$true)][ValidateNotNullOrEmpty()][Alias("path","FullName")]
        [string[]]$VHDPaths, 
        
        [parameter(Mandatory = $true)][ValidateNotNullOrEmpty()]
        $DestPath,       # can be a string or a scriptblock 
        
        [parameter(ValueFromPipelineByPropertyName =$true)][Alias("__Server")][ValidateNotNullOrEmpty()] 
        [string]$Server = ".",   #Only work with images on one server   
        
        [switch]$Wait
    )
    Process {
       write-debug "Before Resolution VHDPaths = $VHDPaths"
       foreach ($vhdpath in $vhdpaths) {
            if ($DestPath -is [scriptblock]  )         { $Destination = Invoke-Expression $(".{$DestPath}") } else {$destination = $DestPath}
            write-debug "Before resolution Destination = $destination" 
            if ($Destination -notmatch "(\w:|\w)\\\w") { $Destination = Join-Path $(Get-VhdDefaultPath $Server) $Destination }
            if ($Destination -notmatch ".VHD$"  )      { $Destination += ".VHD"}
            if ($server="."                  )         { if (-not (Test-Path -Path $Destination -IsValid  -ErrorAction SilentlyContinue)) {$Destination = $null} }
            if ($VHDPath -notmatch "(\w:|\w)\\\w")     { $VHDPath      = Join-Path $(Get-VhdDefaultPath $Server) $VHDPath }
            if ($vhdpath -notmatch ".VHD$"   )         { $vhdPath     += ".VHD"}
            if ($Server -eq ".")                       {$VHDPath       = (Resolve-Path $VHDPath -errorAction "SilentlyContinue") | foreach-object {($_.path)} 
                                                        if ($vhdPath -is [array]) {Merge-VHD -VHDPaths $vhdpath -dest:$DestPath -wait:$wait} 
             }
            write-Debug "After resolution: VHD = $vhdpath Destination =  $destination"
            if ($vhdPath -is [string] -and $Destination -is [string] -and $pscmdlet.shouldProcess(($lStr_ServerName -f $server) , ($lstr_VHDMerge -f $VhdPath,$Destination) ) ) {
                $ImageManagementService = Get-WmiObject -ComputerName $Server -Namespace  $HyperVNamespace -Class $ImageManagementServiceName 
                if ( ($ImageManagementService.MergeVirtualHardDisk($VHDPath, $Destination)   | Test-wmiResult -wait:$wait -JobWaitText($lstr_VHDMerge -f $VhdPath,$Destination) `
                                    -SuccessText ($Lstr_VHDMergeSuccess -f $VHDPath,$Destination)  -failText ($Lstr_VHDMergeFailure -f $vhdPath ,$Destination) ) -eq [returnCode]::ok) {
                    Get-VHDInfo -VHDPath $VHDPath -Server $Server
                }  
            }
       }
    }     
}


Function Mount-VHD
{# .ExternalHelp  MAML-VMDisk.XML
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [parameter(Mandatory = $true, ValueFromPipelineByPropertyName  = $true,ValueFromPipeline =$true)][ValidateNotNullOrEmpty()][Alias("path","FullName")]
        $VHDPaths,
        
        $Partition,
        
        [parameter()][Alias("Letter")]
        $DriveLetter, 
        
        [parameter(ValueFromPipelineByPropertyName =$true)][Alias("__Server")][ValidateNotNullOrEmpty()] 
        [string]$Server = ".",   #Only work with images on one server  
               
        [Switch]$NoDriveLetter,
        
        [Switch]$Offline
    )
    process {
        if ($psc -eq $null)  {$psc = $pscmdlet} ; if (-not $PSBoundParameters.psc) {$PSBoundParameters.add("psc",$psc)}
        write-debug "Before Resolution VHDPaths = $VHDPaths"
        forEach ($vhdPath in $vhdPaths) {
            if ($VHDPath -notmatch "(\w:|\w)\\\w")          {$VHDPath  = Join-Path $(Get-VhdDefaultPath $Server) $VHDPath } 
            if ($vhdpath -notmatch "VHD$" )                 {$vhdPath += ".VHD"}
            write-debug "After Resolution VHDPath = $VHDPath"
            if ($Server -eq ".")                       {$VHDPath       = (Resolve-Path $VHDPath -errorAction "SilentlyContinue") | foreach-object {($_.path)} 
                                                        if ($vhdPath -is [array]) {Mount-VHD -VHDPaths $vhdpath -offline:$Offline }
            }                                                        
            if (($vhdPath -is [String]) -and   $psc.shouldProcess($VHDPath,$lstr_VHDMounting)) {
                $ImageManagementService = Get-WmiObject -Namespace $HyperVNamespace -Class $ImageManagementServiceName
                if ((Test-wmiResult -result ($ImageManagementService.Mount($VHDPath)) -wait -JobWaitText ($lstr_VHDMounting + $vhdPath)`
                                    -SuccessText ($lstr_vhdMountSuccess -f $vhdPath) -failText ($lstr_vhdMountFailure -f $vhdPath) ) -eq [returnCode]::ok)  {
                    Start-sleep -Seconds 2                
                    $MountedDiskImage = Get-WmiObject -Namespace $HyperVNamespace -query "SELECT * FROM MSVM_MountedStorageImage WHERE Name ='$($VHDPath.Replace("\", "\\"))'"
                    $Disk             = Get-WmiObject -Query ("SELECT * FROM Win32_DiskDrive " +  
                                                             " WHERE Model='Msft Virtual Disk SCSI Disk Device' AND ScsiTargetID=$($MountedDiskImage.TargetId) " + 
                                                             " AND   ScsiLogicalUnit=$($MountedDiskImage.Lun)   AND ScsiPort=$($MountedDiskImage.PortNumber)   " )
                    if ($Disk.Index  -is [uint32]) {
                        if ($offline) {   # Ensure the disk is offline. 
                            @("SELECT DISK $($Disk.Index)", "OFFLINE DISK", "EXIT") | DISKPART | Out-Null
                            Write-verbose $lstr_diskMountedOffline 
                            $disk | select-object -property model,size,index,partitions
                        } 
                        else { #First bring the disk on-line, then sort out drive letters
                            @("SELECT DISK $($Disk.Index)", "ONLINE DISK", "ATTRIBUTES DISK CLEAR READONLY", "EXIT") | DISKPART | Out-Null 
                            # BUGBUG:  Let's watch for disk arrival events instead of just sleeping.
                            Start-Sleep -Seconds 5     
                            
                            # only worry about Drive letters if a partition was identified
                            if ($partition) {
                                if ($NoDriveLetter)   {  # Make sure that no drive letter is currently assigned.
                                                        @("SELECT DISK $($Disk.Index)", "SELECT PARTITION $Partition", "REMOVE", "EXIT") | DISKPART | Out-Null 
                                }
                                else {   # A drive letter is wanted, but was a specific letter specified ? 
                                      if ($DriveLetter) { @("SELECT DISK $($Disk.Index)", "SELECT PARTITION $Partition", "ASSIGN LETTER=$DriveLetter", "EXIT") | DISKPART | Out-Null }
                                      else              { # A drive letter is wanted but not specified. If none was specified and one is already assigned to the VHD use that.
                                                          if (-not (get-vhdmountPoint $vhdPath | ForEach-Object{$_.DeviceID}) ) {
                                                              # If we still don't have a drive 
                                                              $DriveLetter = Get-FirstAvailableDriveLetter
                                                              @("SELECT DISK $($Disk.Index)", "SELECT PARTITION $Partition", "ASSIGN LETTER=$DriveLetter", "EXIT") | DISKPART | Out-Null  
                                                          }
                                      }
                                } 
                            }   # end of sorting Drive letters for the requested partition
                                # This may not be required with 2K8 R2 / PowerShell V2 
                            Get-VhdMountPoint -VHDPath $vhdPath | foreach-object  {if ( $(Wait-ForDisk -MountPoint $_.DeviceID)) {
                                New-PSDrive -Name $_.DeviceID.substring(0,1) -PSProvider FileSystem -Root "$($_.DeviceID)\" -Scope Global -ErrorAction SilentlyContinue
                            }}
                        }     # end of on-lining process
                    }         # end of Successful mount
                    else {write-error $lstr_DiskMountedNoID } #No disk index
                }     
            }
        }
    }
}    


Function New-VFD
{# .ExternalHelp  MAML-VMDisk.XML
    param(
        [parameter(Mandatory = $true, ValueFromPipeLine = $true)][Alias("path","FullName")]
        $VFDPaths, 
        
        [parameter()][ValidateNotNullOrEmpty()] 
        [string]$Server = ".",  #Only work with images on one server  
        
        [Switch]$wait
    )
    process {
        foreach ($VFDPath in $VFDPaths) {
            $ImageManagementService = Get-WmiObject -ComputerName $server -NameSpace $HyperVNamespace -Class $ImageManagementServiceName
            if ($VFDPath -notmatch "(\w:|\w)\\\w")  {$vfdPath = $(Join-Path $(Get-VHDDefaultPath -Server $server) $vfdPath) }
            if ($VFDpath -notmatch ".VFD$" )        {$VFDPath += ".VFD"}
            $result = $ImageManagementService.CreateVirtualFloppyDisk($vfdPath)
            if     ( $result.returnValue -eq [ReturnCode]::OK)         {Write-Verbose ($Lstr_VfDCreationSuccess    -f $VfDPath) ;  [System.IO.FileInfo]$vfdPath  }
            elseif ( $result.returnValue -eq [ReturnCode]::JobStarted) {
                $job = Test-WMIJob $result.job -Wait:$wait -Description ($Lstr_CreateVFD -f $vfdPath )
                if ($job.JobState -eq [JobState]::Completed)   {Write-Verbose ($Lstr_VfDCreationSuccess    -f $VfDPath) ; [System.IO.FileInfo]$vfdPath  }
                elseif (-not $wait -and ($job.jobState -eq [JobState]::running)) {Write-Warning ($Lstr_VFDCreationContinues    -f $VfDPath,$result.job) }
                else   {write-error ($LStr_WMIjobfailed2 -f [JobState]$job.JobState, $job.ErrorDescription) }       
            }
            else  {write-error ($lstr_CreateVFDFailed -f [ReturnCode]$result.returnValue ) }
        }
    }
}


Function New-VHD
{# .ExternalHelp  MAML-VMDisk.XML
    [CmdletBinding(SupportsShouldProcess=$True)]
    param(
        [parameter(Mandatory = $true, ValueFromPipeline = $true)][Alias("Path","FullName")][ValidateNotNullOrEmpty()]
        $VHDPaths,              # May create multiple VHDs at once. 
        
        [ValidateRange(1GB,2040GB)]
        [long]$Size = 127GB,

        [Alias("ParentDiskPath","ParentPath")]
        $ParentVHDPath,
        
        [parameter()][ValidateNotNullOrEmpty()] 
        [string]$Server = ".",  #Only work with images on one server  
        
        [switch]$Fixed,
        [switch]$Wait,
        $PSC, 
        [switch]$Force
    )
    process {
        if ($psc -eq $null)       {$psc = $pscmdlet} ; if (-not $PSBoundParameters.psc) {$PSBoundParameters.add("psc",$psc)}
        ForEach ($vhdpath in $vhdPaths ) {  
            if ($(Split-Path $VHDPath) -eq "") { $VHDPath = Join-Path $(Get-VhdDefaultPath $Server) $VHDPath }
            if ($vhdpath -notmatch ".VHD$" )   {$vhdPath += ".VHD"}
            if ((Test-Path -Path $VHDPath -IsValid) -and ($force -or $psc.shouldProcess($VHDPath,$lstr_VHDCreate)))  {
                $ImageManagementService = Get-WmiObject -ComputerName $Server -Namespace $HyperVNamespace -Class $ImageManagementServiceName
                if ($ParentVHDPath )  {
                    if ($ParentVHDPath -isNot [String])         {$ParentVHDPath = $ParentVHDPath.ToString() }
                    if ($(Split-Path $ParentVHDPath) -eq "")    {$ParentVHDPath = Join-Path $(Get-VhdDefaultPath $Server) $ParentVHDPath }
                    if ($ParentVHDPath -notmatch ".VHD$" )      {$ParentVHDPath += ".VHD"}
                    if ($server -eq ".")                        {$ParentVHDPath = (Resolve-Path -Path $ParentVHDPath -ErrorAction SilentlyContinue).path }         
                    if ($ParentVHDPath)                         {$result = $ImageManagementService.CreateDifferencingVirtualHardDisk($VHDPath, $ParentVHDPath)}
                    else                                    {write-warning $lstr_VHDBadParent; Return $null }
                }
                elseif($Fixed) { $result = $ImageManagementService.CreateFixedVirtualHardDisk(  $VHDPath, $Size) }
                else           { $result = $ImageManagementService.CreateDynamicVirtualHardDisk($VHDPath, $Size) }
                if ((Test-wmiResult -result $result -wait:$wait -JobWaitText ($lstr_VHDCreate + $vhdPath)`
                                -SuccessText ($Lstr_VHDCreationSuccess -f $vhdPath) -failText ($Lstr_VHDCreationFailure -f $vhdPath) ) -eq [returnCode]::ok) {[system.io.fileInfo]$vhdpath } 
            }
        }
    }      
}


Function Remove-VMDrive
{# .ExternalHelp  MAML-VMDisk.XML
    [CmdletBinding(SupportsShouldProcess=$true)]
    Param(
        [parameter(ParameterSetName="Path", Mandatory = $true, ValueFromPipeLine = $true, position=0)] 
        $VM, 
        
        [parameter(ParameterSetName="Path", Mandatory = $true, position=1)]
        [int]$ControllerID, 
        
        [parameter(ParameterSetName="Path", Mandatory = $true, position=2)]
        [int]$LUN, 

        [parameter(ParameterSetName="Path")][ValidateNotNullOrEmpty()] 
        $Server="." ,   #May need to look for VM(s) on Multiple servers
        
        [parameter(ParameterSetName="Path")]
        [switch]$SCSI, 
        
        [parameter(ParameterSetName="Drive")]
        $DriveRASD,
        
        [switch]$Diskonly,
        $PSC, 
        [switch]$Force
    )
    process {
        if ($psc -eq $null)  {$psc = $pscmdlet}  ; if (-not $PSBoundParameters.psc) {$PSBoundParameters.add("psc",$psc)}
        if ($pscmdlet.ParameterSetName -eq "Path") {
            if ($VM -is [String]) {$VM=(Get-VM -Name $VM -server $Server) }
            if ($VM.count -gt 1 )   { [Void]$PSBoundParameters.Remove("VM") ;  $VM | ForEach-object {Remove-VMDrive -VM $_  @PSBoundParameters}}
            if ($vm.__CLASS -eq 'Msvm_ComputerSystem') {$DriveRASD = Get-VMDiskController -vm $vm -ControllerID $ControllerID -SCSI:$SCSI -IDE:$(-not $scsi) |
                                                                            Get-VMDriveByController -Lun $Lun }
            else       {$DriveRASD=(Get-VMDriveByController -controller (Get-VMDiskController -vm $vm -ControllerID $ControllerID -IDE)  -Lun $lun )}
        }
        # if ($pscmdlet.ParameterSetName -eq "Drive") {$vm= get-vm $driveRasd }  
        if ($DriveRASD.__CLASS -eq 'Msvm_ResourceAllocationSettingData')  {
            get-vmdiskByDrive $DriveRASD | foreach-object { if ($_ -ne $DriveRASD) { remove-VMRASD -psc $psc -force:$force -rasd $_ }  #Exclude Passthrough disks
            if (-not $diskOnly)                                                    { remove-VMRASD -psc $psc -force:$force -rasd $DriveRASD } }      
        }
    }	
}


Function Remove-VMFloppyDisk
{# .ExternalHelp  MAML-VMDisk.XML
    [CmdletBinding(SupportsShouldProcess=$true)]
    Param (
        [parameter(Mandatory = $true, ValueFromPipeLine = $true)] 
        $VM, 
        
        [parameter()][ValidateNotNullOrEmpty()] 
        [string]$Server="." ,
        $PSC, 
        [switch]$Force
    )
    process {
        if ($psc -eq $null)  {$psc = $pscmdlet} ; if (-not $PSBoundParameters.psc) {$PSBoundParameters.add("psc",$psc)}
        if ($VM -is [String]) { $VM=(Get-VM -Name $VM -Server $Server) }
        if ($VM.count -gt 1 )  { [Void]$PSBoundParameters.Remove("VM") ;  $VM | ForEach-object {Remove-VMFloppyDisk -VM $_  @PSBoundParameters}}
        if ($vm.__CLASS -eq 'Msvm_ComputerSystem') {
            $floppyRASD = Get-VmFloppyDisk -VM $vm -Server $Server
            if ($floppyRASD) {remove-VMRasd -VM $vm -rasd $floppyRASD -PSC $psc -force:$force } 
        }
	}
}


Function Remove-VMSCSIController
{# .ExternalHelp  MAML-VMDisk.XML
    [CmdletBinding(SupportsShouldProcess=$true)]
    Param(
        [parameter(Mandatory = $true, ValueFromPipeLine = $true)] 
        $VM, 
        [parameter(Mandatory = $true)]
        [int]$ControllerID,
        [parameter()][ValidateNotNullOrEmpty()]  
        $Server=".",                    #May need to look for VM(s) on Multiple servers
        $PSC, 
        [switch]$Force
    )
    process {
        if ($psc -eq $null)  {$psc = $pscmdlet}  ; if (-not $PSBoundParameters.psc) {$PSBoundParameters.add("psc",$psc)}
        if ($VM -is [String]) {$VM=(Get-VM -Name $VM -Server $Server) }
        if ($VM.count -gt 1 ) {[Void]$PSBoundParameters.Remove("VM") ;  $VM | ForEach-object {Remove-VMSCSIcontroller -VM $_  @PSBoundParameters}}
        $controller= (Get-VMDiskController -vm $vm -ControllerID $ControllerID -SCSI)
        if ($Controller -is [System.Management.ManagementObject]) {
	        # to Avoid leaving orphaned objects, find and remove the drives bound to the controller (and the disks inserted into them)
            foreach ($drive in (Get-VMDriveByController $controller)) {Remove-VMdrive -DriveRASD $drive -psc $PSC -force:$force } 
            remove-VMRasd -VM $vm -rasd $controller -PSC $psc -force:$force
        }
    }	
}
Function Select-ClusterSharedVolume
{# .ExternalHelp  MAML-VMDisk.XML
    Param([parameter()][ValidateNotNullOrEmpty()][Alias("Cluster")]
          [string]$Server="."  #Only look at one cluster[node]
         )   
    if (-not (get-command -Name Get-ClusterSharedVolume -ErrorAction "SilentlyContinue")) {Write-Error "Cluster commands not loaded. Import-Modue FailoverClusters and try again" ; return}
    $CSVs=$(foreach ($vol in (Get-ClusterSharedVolume -cluster $server )) {foreach ($sharedVol in $vol.sharedvolumeinfo) { $sharedVol.partition | 
                 add-member -passthru -type Noteproperty -name "VolName"  -value $sharedvol.FriendlyVolumeName   |
                 add-member -passthru -type Noteproperty -name "DiskName" -value $vol.name                       |
                 add-member -passthru -type Noteproperty -name "Owner"    -value $vol.ownerNode.name }})

    select-list -InputObject $csvs -Property @{name="Name"; expression={$_.volname}},
                                             @{name="Size"; expression={($_.size/1gb).tostring("#,###.## GB")}},
                                             @{name="Free"; expression={($_.freespace / 1gb).tostring("#,###.## GB")}}  ,
                                             filesystem, owner
}     


Function Select-VMPhysicalDisk 
{# .ExternalHelp  MAML-VMDisk.XML
  Param ([parameter()][ValidateNotNullOrEmpty()] 
         [String]$Server = "." #only check one server
        )  
  $respool = get-wmiobject -computername $server -Namespace root\virtualization -query "Select * from Msvm_ResourcePool where ResourceSubType = 'Microsoft Physical Disk Drive'"
  Select-list -Property @("elementName") -InputObject $respool.getRelated("Msvm_DiskDrive") #(get-wmiobject -Namespace root\virtualization -query "associators of {$respool} where resultClass=Msvm_DiskDrive" ) 
}
#If you need to see how the disks map on to indexes which appear in the names "Disk 1" "Disk 2" use the following
# get-wmiobject win32_diskdrive | ft -a Index,Model,MediaType,@{label="Type";expression={$_.interfaceType}},SCSIBus,SCSIPort,@{Label="SCSILUN";expression={$_.SCSILogicalUnit}},SCSITartgetID,@{Label="Size";expression={(($_.size)/1Gb).tostring("#,##.0GB")}}


Function Set-VMDisk
{# .ExternalHelp  MAML-VMDisk.XML
    [CmdletBinding(SupportsShouldProcess=$true)]
    Param([parameter(ParameterSetName="Path" , Mandatory = $true, ValueFromPipeline = $true , position=0)]
        $VM,
        
        [parameter(ParameterSetName="Path" , position=1)]
        [int]$ControllerID = 0,
        
        [parameter(ParameterSetName="Path", position=2)]
        [int]$LUN = 0 ,
        
        [parameter(Mandatory = $true, position=3)][Alias("VHDPath")][AllowEmptyString()]
        [string]$Path,                     #May support script blocks in future
      
        [parameter(ParameterSetName="Path")][ValidateNotNullOrEmpty()] 
        $server="." ,    #May need to look for VM(s) on Multiple servers
        
        [parameter(ParameterSetName="Path")]
        [switch]$SCSI, 
        
        [Alias("DVD")]
        [switch]$OpticalDrive,
        
        [parameter(ParameterSetName="Drive")]
        $DriveRASD,
        
        $PSC, 
        [switch]$Force
    )
    process {
        if ($psc -eq $null)  {$psc = $pscmdlet} ; if (-not $PSBoundParameters.psc) {$PSBoundParameters.add("psc",$psc)}
        if ($pscmdlet.ParameterSetName -eq "Path") {
            if ($VM -is [String]) {$VM       =(Get-VM -Name $VM -server $Server) }
            if ($VM.count -gt 1 ) {[Void]$PSBoundParameters.Remove("VM") ;  $VM | ForEach-object {Set-VMDisk -VM $_ -psc $psc @PSBoundParameters}}
            if ($vm.__CLASS -eq 'Msvm_ComputerSystem') { 
                $DriveRASD= Get-VMDiskController -vm $vm -ControllerID $ControllerID -SCSI:$scsi -ide:$(-not $scsi) | Get-VMDriveByController -Lun $Lun 
                if (-not $driveRASD)  {[Void]$PSBoundParameters.Remove("Path") ; $DriveRASD = Add-vmdrive @PSBoundParameters}
            }
        }    
        if  ($DriveRasd.__CLASS -eq 'Msvm_ResourceAllocationSettingData') { 
            $DiskRASD = $DriveRASD | get-vmdiskByDrive 
            if ( $DiskRASD -is [System.Management.ManagementObject])  {
                If  ($opticalDrive -or ($driveRasD.caption -match "DVD")) {
                   if ($path -match "^\w:$") {$path = $(Get-WmiObject -ComputerName $vm.__SERVER -Query "Select * From win32_cdromdrive where Drive='$path'").deviceID }
                   else {Get-WmiObject -ComputerName $vm.__SERVER -Query "Select * From win32_cdromdrive" | foreach -begin {$CDDevices=@()} -process {$CDdevices += $_.deviceID}
                       if (($Path -notmatch "iso$") -and ($CDdevices -notcontains $path)) {$path += ".ISO"}
                   }
                }
                elseif ($Path -notmatch "VHD$" )     {$path += ".VHD"}      
                if     ($Path -match "(\w:|\w)\\\w") {$diskRASD.Connection = $path} 
                else                                 {$diskRASD.Connection = (join-path -ChildPath $path -path (Get-VhdDefaultPath -server $diskRasd.__SERVER) ) }
                Set-VMRASD -rasd $DiskRASD -psc $psc -force:$force  
            }    
            else {add-vmdisk @PSBoundParameters} 
        }
    }
}

Function Test-VHD
{# .ExternalHelp  MAML-VMDisk.XML
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true, ValueFromPipelineByPropertyName  = $true,ValueFromPipeline =$true)][Alias("Fullname","Path","DiskPath")]
        [string[]]$VHDPaths,             #may be single or multiple paths
        
        [parameter(ValueFromPipelineByPropertyName =$true)][Alias("__Server")][ValidateNotNullOrEmpty()] 
        [string]$Server = "."   #Only work with images on one server  
    )
    Process {
        write-debug "Before Resolution VHDPaths = $VHDPaths"
        Foreach ($VHDPath in $VHDPaths) {  
            if ($VHDPath -notmatch "(\w:|\w)\\\w") {$VHDPath     = Join-Path $(Get-VhdDefaultPath $Server) $VHDPath }
            if ($vhdpath -notmatch "VHD$" )        {$vhdPath    += ".VHD"}
            if ($Server -eq ".")                   {$VHDPath     = (Resolve-Path $VHDPath -errorAction "SilentlyContinue") | foreach-object {($_.path)} 
                                                    if ($vhdPath -is [array]) {Test-VHD -VHDPaths $VHdpath }
            }      
           
            write-debug "After Resolution VHDPath = $VHDPath, Server =$server"
            if ($vhdPath -is [String])                          {
                $ImageManagementService = Get-WmiObject -ComputerName $server -Namespace $HyperVNamespace -Class $ImageManagementServiceName
                write-verbose ($lstr_validating  -f $vhdPath)
                $result = $ImageManagementService.ValidateVirtualHardDisk($VHDPath)
                if     ($result.returnValue -eq [ReturnCode]::OK)         {  $true }
                elseif ($result.returnValue -eq [ReturnCode]::JobStarted) {
                    $job = Test-WMIJob $result.job -wait -Description ($lstr_validating -f $VHDPath)
                    if ($job.JobState -eq [JobState]::Completed) { $true }
                    else  {write-warning  $job.ErrorDescription
                            $false  
                    }
                }   
                else  { write-error  ($lStr_ErrorValidatingVHD -f [ReturnCode]$Result.ReturnValue ) 
                        return $false
               }
           }
        } 
    }     
}


Function Wait-ForDisk
{# .ExternalHelp  MAML-VMDisk.XML
    [CmdletBinding()]
    param(
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$MountPoint,
        
        [int]$Attempts = 10,
        
        [parameter()]
        [int]$MSPause = 1000
    )
    if ($mountPoint -notmatch "\:$") { $MountPoint += ":" }
    Write-Verbose "MountPoint = $MountPoint"
    do {
        if (-not (Get-WmiObject -Query "SELECT * FROM Win32_LogicalDisk WHERE DeviceID = '$MountPoint'")) { Start-Sleep -Milliseconds $MSPause}
        else {$Attempts = -1 }   
    } while ($Attempts-- -gt 0)
    [bool]$Attempts
}
