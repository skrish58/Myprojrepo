# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

function Initialize-Lcm
{
    <#
    .SYNOPSIS
    Configures a computer's DSC Local Configuration Manager (LCM).

    .DESCRIPTION
    The Local Configuration Manager (LCM) is the Windows PowerShell Desired State Configuration (DSC) engine. It runs on all target computers, and it is responsible for calling the configuration resources that are included in a DSC configuration script. It can be configured to receive changes (i.e. `Push` mode) or pull and apply changes its own changes (i.e. `Pull` mode).

    ## Push Mode

    Push mode is simplest. The LCM only applies configurations that are pushed to it via `Start-DscConfiguration`. It is expected that all resources needed by the LCM are installed and available on the computer. To use `Push` mode, use the `Push` switch.

    ## Pull Mode
    
    In order to get a computer to pulls its configuration automatically, you need to configure its LCM so it knows where and how to find its DSC pull server. The pull server holds all the resources and modules needed by the computer's configuration.

    The LCM can pull from two sources: a DSC website (the web download manager) or an SMB files hare (the file download manager). To use the web download manager, specify the URL to the website with the `ServerUrl` parameter. To use the file download manager, specify the path to the resources with the `SourcePath` parameter. This path can be an SMB share path or a local (on the LCM's computer) file system path. No matter where the LCM pulls its configuration from, you're responsible for putting all modules, resources, and .mof files at that location.

    The most frequently the LCM will *download* new configuration is every 15 minutes. This is the minimum interval. The refresh interval is set via the `RefreshIntervalMinutes` parameter. The LCM will only *apply* a configuration on one of the refreshes. At most, it will apply configuration every 2nd refresh (i.e. every other refresh). You can control the frequency when configuration is applied via the `ConfigurationFrequency` parameter. For example, if `RefreshIntervalMinutes` is set to `30`, and `ConfigurationFrequency` is set to 4, then configuration will be downloaded every 30 minutes, and applied every two hours (i.e. `30 * 4 = 120` minutes).

    The `ConfigurationMode` parameter controls *how* the LCM applies its configuration. It supports three values:

     * `ApplyOnly`: Configuration is applied once and isn't applied again until a new configuration is detected. If the computer's configuration drifts, no action is taken.
     * `ApplyAndMonitor`: The same as `ApplyOnly`, but if the configuration drifts, it is reported in event logs.
     * `ApplyAndAutoCorrect`: The same as `ApplyOnly`, and when the configuratio drifts, the discrepency is reported in event logs, and the LCM attempts to correct the configuration drift.

    When credentials are needed on the target computer, the DSC system encrypts those credentials with a public key when generating the configuration. Those credentials are then decrypted on the target computer, using the corresponding private key. A computer can't run its configuration until the private key is installed. Use the `CertFile` and `CertPassword` parameters to specify the path to the certificate containing the private key and the private key's password, respectively. This function will upload the certificate to the target computer and install it in the proper Windows certificate store. To generate a public/private key pair, use `New-RsaKeyPair`.

    Returns an object representing the computer's updated LCM settings.

    See [Windows PowerShell Desired State Configuration Local Configuration Manager](http://technet.microsoft.com/en-us/library/dn249922.aspx) for more information.

    `Initialize-Lcm` is new in Carbon 2.0.

    .LINK
    New-RsaKeyPair

    .LINK
    Start-DscPullConfiguration
    
    .LINK
    http://technet.microsoft.com/en-us/library/dn249922.aspx

    .EXAMPLE
    Initialize-Lcm -Push -ComputerName '1.2.3.4'

    Demonstrates how to configure an LCM to use push mode.

    .EXAMPLE
    Initialize-Lcm -ConfigurationID 'fc2ffe50-13cd-4cd2-9942-d25ac66d6c13' -ComputerName '10.1.2.3' -ServerUrl 'https://10.4.5.6/PSDSCPullServer.dsc'

    Demonstrates the minimum needed to configure a computer (in this case, `10.1.2.3`) to pull its configuration from a DSC web server.

    .EXAMPLE
    Initialize-Lcm -ConfigurationID 'fc2ffe50-13cd-4cd2-9942-d25ac66d6c13' -ComputerName '10.1.2.3' -SourcePath '\\10.4.5.6\DSCResources'

    Demonstrates the minimum needed to configure a computer (in this case, `10.1.2.3`) to pull its configuration from an SMB file share.

    .EXAMPLE
    Initialize-Lcm -CertFile 'D:\Projects\Resources\PrivateKey.pfx' -CertPassword $secureStringPassword -ConfigurationID 'fc2ffe50-13cd-4cd2-9942-d25ac66d6c13' -ComputerName '10.1.2.3' -SourcePath '\\10.4.5.6\DSCResources'

    Demonstrates how to upload the private key certificate on to the targer computer(s).

    .EXAMPLE
    Initialize-Lcm -RefreshIntervalMinutes 25 -ConfigurationFrequency 3 -ConfigurationID 'fc2ffe50-13cd-4cd2-9942-d25ac66d6c13' -ComputerName '10.1.2.3' -SourcePath '\\10.4.5.6\DSCResources'

    Demonstrates how to use the `RefreshIntervalMinutes` and `ConfigurationFrequency` parameters to control when the LCM downloads new configuration and applies that configuration. In this case, new configuration is downloaded every 25 minutes, and apllied every 75 minutes (`RefreshIntervalMinutes * ConfigurationFrequency`).
    #>
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true,ParameterSetName='Push')]
        [Switch]
        # Configures the LCM to receive its configuration via pushes using `Start-DscConfiguration`.
        $Push,

        [Parameter(Mandatory=$true,ParameterSetName='PullWebDownloadManager')]
        [string]
        # Configures the LCM to pull its configuration from a DSC website using the web download manager
        $ServerUrl,

        [Parameter(ParameterSetName='PullWebDownloadManager')]
        [Switch]
        # When using the web download manager, allow the `ServerUrl` to use an unsecured, http connection when contacting the DSC web pull server.
        $AllowUnsecureConnection,

        [Parameter(Mandatory=$true,ParameterSetName='PullFileDownloadManager')]
        [string]
        # Configures the LCM to pull its configuration from an SMB share or directory. This is the path to the SMB share where resources can be found. Local paths are also allowed, e.g. `C:\DscResources`.
        $SourcePath,

        [Parameter(Mandatory=$true,ParameterSetName='PullWebDownloadManager')]
        [Parameter(Mandatory=$true,ParameterSetName='PullFileDownloadManager')]
        [Guid]
        # The GUID that identifies what configuration to pull to the computer. The Local Configuration Manager will look for a '$Guid.mof' file to pull.
        $ConfigurationID,

        [Parameter(Mandatory=$true,ParameterSetName='PullWebDownloadManager')]
        [Parameter(Mandatory=$true,ParameterSetName='PullFileDownloadManager')]
        [ValidateSet('ApplyOnly','ApplyAndMonitor','ApplyAndAutoCorrect')]
        [string]
        # Specifies how the Local Configuration Manager applies configuration to the target computer(s). It supports three values: `ApplyOnly`, `ApplyAndMonitor`, or `ApplyAndAutoCorrect`.
        $ConfigurationMode,

        [Parameter(Mandatory=$true)]
        [string[]]
        # The computer(s) whose Local Configuration Manager to configure.
        $ComputerName,

        [PSCredential]
        # The credentials to use when connecting to the target computer(s).
        $Credential,

        [Parameter(ParameterSetName='PullWebDownloadManager')]
        [Parameter(ParameterSetName='PullFileDownloadManager')]
        [Switch]
        # Controls whether new configurations downloaded from the configuration server are allowed to overwrite the old ones on the target computer(s).
        $AllowModuleOverwrite,

        [Alias('Thumbprint')]
        [string]
        # The thumbprint of the certificate to use to decrypt secrets. If `CertFile` is given, this parameter is ignored in favor of the certificate in `CertFile`.
        $CertificateID = $null,

        [string]
        # The path to the certificate containing the private key to use when decrypting credentials. The certificate will be uploaded and installed for you.
        $CertFile,

        [object]
        # The password for the certificate specified by `CertFile`. It can be a `string` or a `SecureString`.
        $CertPassword,

        [Alias('RebootNodeIfNeeded')]
        [Switch]
        # Reboot the target computer(s) if needed.
        $RebootIfNeeded,

        [Parameter(ParameterSetName='PullWebDownloadManager')]
        [Parameter(ParameterSetName='PullFileDownloadManager')]
        [ValidateRange(30,[Int32]::MaxValue)]
        [Alias('RefreshFrequencyMinutes')]
        [int]
        # The interval (in minutes) at which the target computer(s) will contact the pull server to *download* its current configuration. The default (and minimum) interval is 15 minutes.
        $RefreshIntervalMinutes = 30,

        [Parameter(ParameterSetName='PullWebDownloadManager')]
        [Parameter(ParameterSetName='PullFileDownloadManager')]
        [ValidateRange(1,([int]([Int32]::MaxValue)))]
        [int]
        # The frequency (in number of `RefreshIntervalMinutes`) at which the target computer will run/implement its current configuration. The default (and minimum) frequency is 2 refresh intervals. This value is multiplied by the `RefreshIntervalMinutes` parameter to calculate the interval in minutes that the configuration is applied.
        $ConfigurationFrequency = 1,

        [Parameter(ParameterSetName='PullWebDownloadManager')]
        [Parameter(ParameterSetName='PullFileDownloadManager')]
        [PSCredential]
        # The credentials the Local Configuration Manager should use when contacting the pull server.
        $LcmCredential
    )

    Set-StrictMode -Version 'Latest'

    Use-CallerPreference -Cmdlet $PSCmdlet -Session $ExecutionContext.SessionState

    $thumbprint = $null
    if( $CertificateID )
    {
        $thumbprint = $CertificateID
    }
    $privateKey = $null
    if( $CertFile )
    {
        $CertFile = Resolve-FullPath -Path $CertFile
        if( -not (Test-Path -Path $CertFile -PathType Leaf) )
        {
            Write-Error ('Certificate file ''{0}'' not found.' -f $CertFile)
            return
        }

        $privateKey = Get-Certificate -Path $CertFile -Password $CertPassword
        if( -not $privateKey )
        {
            return
        }
        if( -not $privateKey.HasPrivateKey )
        {
            Write-Error ('Certificate file ''{0}'' does not have a private key.' -f $CertFile)
            return
        }
        $thumbprint = $privateKey.Thumbprint
    }
    
    $credentialParam = @{ }
    if( $Credential )
    {
        $credentialParam.Credential = $Credential
    }

    $ComputerName = $ComputerName | 
                        Where-Object { 
                            if( Test-Connection -ComputerName $_ -Quiet ) 
                            {
                                return $true
                            }
                            
                            Write-Error ('Computer ''{0}'' not found or is unreachable.' -f $_)
                            return $false
                        }
    if( -not $ComputerName )
    {
        return
    }

    # Upload the private key, if one was given.
    if( $privateKey )
    {
        # Get the bytes of the private key as a base-64 encoded string for easy transfer to the destination computer.
        $certBytes = [IO.File]::ReadAllBytes($CertFile)
        $encodedCert = [Convert]::ToBase64String( $certBytes )

        Invoke-Command -ComputerName $ComputerName @credentialParam -ScriptBlock {
            param(
                [Parameter(Mandatory=$true)]
                [string]
                # The certificate's thumbprint.
                $Thumbprint,

                [Parameter(Mandatory=$true)]
                [string]
                # The base-64 encoded certificate to install.
                $EncodedCertificate,

                # The password for the certificate.
                $Password,

                [bool]
                $WhatIf,

                [Management.Automation.ActionPreference]
                $Verbosity
            )

            Set-StrictMode -Version 'Latest'

            $WhatIfPreference = $WhatIf
            $VerbosePreference = $Verbosity

            $certPath = Join-Path -Path 'cert:\LocalMachine\My' -ChildPath $Thumbprint
            if( (Test-Path -Path $certPath -PathType Leaf) )
            {
                $cert = Get-Item -Path $certPath
                if( $cert.HasPrivateKey )
                {
                    Write-Verbose -Message ('{0} ({1}) found at {2}' -f $cert.Subject,$cert.Thumbprint,$certPath)
                    return
                }
            }

            $tempDir = 'Carbon+Initialize-Lcm+Install-Certificate+{0}' -f [IO.Path]::GetRandomFileName()
            $tempDir = Join-Path -Path $env:TEMP -ChildPath $tempDir
            New-Item -Path $tempDir -ItemType 'Directory' -WhatIf:$false | Out-Null

            try
            {
                $certBytes = [Convert]::FromBase64String( $EncodedCertificate )
                $certFilePath = Join-Path -Path $tempDir -ChildPath ([IO.Path]::GetRandomFileName())
                [IO.File]::WriteAllBytes( $certFilePath, $certBytes )

                $keyFlags = [Security.Cryptography.X509Certificates.X509KeyStorageFlags]::MachineKeySet -bor [Security.Cryptography.X509Certificates.X509KeyStorageFlags]::PersistKeySet
                $cert = New-Object 'Security.Cryptography.X509Certificates.X509Certificate2'
                $cert.Import( $certFilePath, $Password, $keyFlags )

                $store = New-Object 'Security.Cryptography.X509Certificates.X509Store' ([Security.Cryptography.X509Certificates.StoreName]::My),([Security.Cryptography.X509Certificates.StoreLocation]::LocalMachine)
                $store.Open( ([Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite) )

                $description = $cert.FriendlyName
                if( -not $description )
                {
                    $description = $cert.Subject
                }

                if( $PSCmdlet.ShouldProcess( 'install into LocalMachine''s My store', ('{0} ({1})' -f $description,$cert.Thumbprint) ) )
                {
                    Write-Verbose ('Installing certificate ''{0}'' ({1}) into Local Machine''s My store.' -f $description,$cert.Thumbprint)
                    $store.Add( $cert )
                }
                $store.Close()
            }
            finally
            {
                Remove-Item -Path $tempDir -Recurse -ErrorAction Ignore -WhatIf:$false
            }
        } -ArgumentList $thumbprint,$encodedCert,$CertPassword,$WhatIfPreference,$VerbosePreference
    }

    $sessions = New-CimSession -ComputerName $ComputerName @credentialParam

    $originalWhatIf = $WhatIfPreference
    $WhatIfPreference = $false
    configuration Lcm 
    {
        Set-StrictMode -Off

        $configID = $null
        if( $ConfigurationID )
        {
            $configID = $ConfigurationID.ToString()
        }

        node $AllNodes.NodeName
        {
            if( $Node.RefreshMode -eq 'Push' )
            {
                LocalConfigurationManager
                {
                    CertificateID = $thumbprint;
                    RebootNodeIfNeeded = $RebootIfNeeded;
                    RefreshMode = 'Push';
                }
            }
            else
            {
                if( $Node.RefreshMode -like '*FileDownloadManager' )
                {
                    $downloadManagerName = 'DscFileDownloadManager'
                    $customData = @{ SourcePath = $SourcePath }
                }
                else
                {
                    $downloadManagerName = 'WebDownloadManager'
                    $customData = @{
                                        ServerUrl = $ServerUrl;
                                        AllowUnsecureConnection = $AllowUnsecureConnection.ToString();
                                  }
                }

                LocalConfigurationManager
                {
                    AllowModuleOverwrite = $AllowModuleOverwrite;
                    CertificateID = $thumbprint;
                    ConfigurationID = $configID;
                    ConfigurationMode = $ConfigurationMode;
                    ConfigurationModeFrequencyMins = $RefreshIntervalMinutes * $ConfigurationFrequency;
                    Credential = $LcmCredential;
                    DownloadManagerCustomData = $customData;
                    DownloadManagerName = $downloadManagerName;
                    RebootNodeIfNeeded = $RebootIfNeeded;
                    RefreshFrequencyMins = $RefreshIntervalMinutes;
                    RefreshMode = 'Pull'
                }
            }
        }
    }
    $WhatIfPreference = $originalWhatIf

    $tempDir = New-TempDirectory -Prefix 'Carbon+Initialize-Lcm+' -WhatIf:$false

    try
    {
        [object[]]$allNodes = $ComputerName | ForEach-Object { @{ NodeName = $_; PSDscAllowPlainTextPassword = $true; RefreshMode = $PSCmdlet.ParameterSetName } }
        $configData = @{
            AllNodes = $allNodes
        }

        $whatIfParam = @{ }
        if( (Get-Command -Name 'Lcm').Parameters.ContainsKey('WhatIf') )
        {
            $whatIfParam['WhatIf'] = $false
        }

        & Lcm -OutputPath $tempDir @whatIfParam -ConfigurationData $configData | Out-Null

        Set-DscLocalConfigurationManager -ComputerName $ComputerName -Path $tempDir @credentialParam

        Get-DscLocalConfigurationManager -CimSession $sessions
    }
    finally
    {
        Remove-Item -Path $tempDir -Recurse -WhatIf:$false
    }
}
