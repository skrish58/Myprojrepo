function ConvertTo-ModuleService
{    
    <#
    .Synopsis
        Export a PowerShell module as a series of ASP.NET Handlers
    .Description
        Exports a Powershell module as a series of ASP.NET handlers        
    .Example
        Import-Module Pipeworks -Force -PassThru | ConvertTo-ModuleService -Force -Allowdownload
    #>
    [OutputType([Nullable])]
    param(
    #|Options Get-Module | Select-Object -ExpandProperty Name
    # The name of the module to export    
    [ValidateScript({
        if (-not (Get-Module "$_")) {
            $isavailable = Get-Module -ListAvailable "$_"
            if ($isavailable) {
                $isavailable | Import-Module -Global
            }
        }
    return $true
    })]        
    [Parameter(Mandatory=$true,Position=0,ParameterSetName='LoadedModule',ValueFromPipelineByPropertyName=$true)]
    [string]
    $Name,       
        
    # The order in which to display the commands
    [Parameter(Position=2)]
    [string[]]
    $CommandOrder,   
    
    # The Google Analytics ID used for the module
    [string]
    $AnalyticsId,
           
    # The directory where the generated module will be stored.  
    # If no directory is specified, the module will be put in Inetpub\wwwroot\ModuleName
    [string]
    $OutputDirectory,
    
    # If set, will overwrite files found in the output directory
    [Switch]
    $Force,
            
    # If set, will allow the module to be downloaded
    [Parameter(Position=1)]
    [switch]$AllowDownload,    
    
    # If set, will make changes to the web.config file to work for Intranet sites (anonymous authentication will be disabled, and windows authentication will be enabled).
    [Switch]$AsIntranetSite,
    
    # The Kerberos realm to use for authentication.      
    # Only works with -AsIntranetSite.  
    # If provided, Kerberos authentication will be used instead of NTLM.  
    # This is both faster, and more secure.
    [string]$Realm,
    
    # If provided, will run the site under an app pool with the credential
    [Management.Automation.PSCredential]
    $AppPoolCredential,
    
    # The port an intranet site should run on.
    [Uint32]$Port,
    
    # If a download URL is present, a download link will redirect to that URL.
    [uri]$DownloadUrl,
        
    # If set, the blog page will become the homepage of the module
    [Switch]$AsBlog,
    
    # If set, will add a URL rewriter rule to accept any URL that is not a real file.
    [Switch]$AcceptAnyUrl,
    
    # If this is set, will use this module URL as the module service URL.
    [Uri]$ModuleUrl,    
        
    
    # If set, will render a CSS style
    [Hashtable]$Style,
    
    # If set, will create appSettings in a web.config file.  This can be used to store common settings, like connection data.
    [Hashtable]$ConfigSetting = @{},
    
    # The margin on either side of the module content.  Defaults to 7.5%.
    [ValidateRange(0,100)]
    [Double]
    $MarginPercent = 3,
    
    # The margin on the left side of the module content. Defaults to 7.5%.
    [ValidateRange(0,100)]
    [Double]
    $MarginPercentLeft = 3,
    
    # The margin on the left side of the module content. Defaults to 7.5%.
    [ValidateRange(0,100)]
    [Double]
    $MarginPercentRight = 3,
    
    # The schematics used to produce the module service.  
    # Schematics let you quickly and easily give a look or feel around data or commands, and let you parameterize your deployment with the pipeworks manifest.
    [Alias('Schematic')]
    [string[]]
    $UseSchematic,    
        
    # If set, will run commands in a runspace for each user.  If not set, users will run in a pool
    [Switch]
    $IsolateRunspace,
    
    # The size of the runspace pool that will handle request.  The more runspaces in the pool, the more concurrent users
    [Uint16]
    $PoolSize = 2,

    [Timespan]
    $pulseInterval = "0:0:0.5",
    
    # If set, will reset IIS
    [Switch]
    $IISReset,

    
    # The maximum amount of that a page can run before it times out.
    [Timespan]
    $ExecutionTimeout = [Timespan]::FromSeconds(120),

    # The maximum request length.
    [Uint32]
    $MaximumRequestLength = 640kb,

    # If set, will show the default browser when the conversion is complete
    [Switch]
    $Show,

    # If provided, will visit this URL after the conversion is complete.  
    [Uri]
    [Alias('Page', 'ShowPage')]
    $Do,

    [Switch]
    $AsJob,

    [Uint32]
    $Throttle,

    # The amount of time static content will be cached for.  By default, one week.
    [Timespan]
    $CacheStaticContentFor = [Timespan]::FromDays(7),

    # If set, will not clean the output directory.  If you are trying to nest multiple pipeworks sites, this would be the way to go.
    [Switch]
    $DoNotClean,

    # If set, the module will be assumed to be nested beneath another module, and no DefaultDocument will be added to the web.config
    [Switch]
    $IsNested
    )
    
    
    begin {      
        $asJobOrElevate = {
            param($CommandInfo, [switch]$OnlyCommand, [string[]]$AdditionalModules, [Hashtable]$Parameter, [Switch]$RequireAdmin)
            
            $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
            $isAdmin = (New-Object Security.Principal.WindowsPrincipal $currentUser).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)
            
            if ($AsJob -or $Throttle -or (-not $isAdmin) -and $requireAdmin) {           
                if ($onlyCommand) {             
                    $AdditionalModules = $AdditionalModules | Select-Object -Unique
                    $myDefinition = [ScriptBLock]::Create("
$(if ($AdditionalModules) {
"
    Import-Module '$($AdditionalModules -join ("','"))'
"})
                    
function $commandInfo {
$($commandInfo | Select-Object -ExpandProperty Definition)
}

")                        
                } else {
                    $myModule = $CommandInfo.ScriptBlock.Module

                    $AdditionalModules += $myModule | Split-Path
                    $AdditionalModules += $myModule.RequiredModules | Split-Path
                    $AdditionalModules = $AdditionalModules | Select-Object -Unique
                    $myDefinition = [ScriptBLock]::Create("

$(if ($AdditionalModules) {
"
    Import-Module '$($AdditionalModules -join ("','"))'
"})

")                   
                }
            $null = $Parameter.Remove('AsJob')                                    
            $null = $Parameter.Remove('Throttle')
            $null = $Parameter.Remove('RequireAdmin')                                    
            $myJob= [ScriptBLock]::Create("" + {                        
param([Hashtable]$parameter)                         
                                    
} + $myDefinition + "                        
                                    
            $commandInfo `@parameter                        
")      


            
            if ($Throttle) {

                $jobLaunched=  $false
                
                do {
                    if ($myJobs) {
                        $myJobs | 
                            Receive-Job
                    }

                    
                    $runningJobs = $myJobs | 
                        Where-Object { $_.State -ne 'Running' }
if ($runningJobs) {
                        $runningJobs | 
                            Remove-Job -Force
                    }
                
                    

                    if ($myJobs.Count -lt $throttle) {
                        $null = Start-Job -Name "${MyCmd}_Background_Job" -ScriptBlock $myJob -ArgumentList $Parameter
                        $JobLaunched = $true
                    }

                    $myJobs =  Get-Job -Name "${MyCmd}_Background_Job" -ErrorAction SilentlyContinue
                    Write-Progress "Waiting for Jobs to Complete" "$($myJobs.Count) Running" -Id $ProgressId  
                } until ($jobLaunched)
                
                $myJobs =  Get-Job -Name "${MyCmd}_Background_Job" -ErrorAction SilentlyContinue
                $myJobs  | 
                    Wait-Job | 
                    Receive-Job
                return 
            } elseif ($asJob) {
                return Start-Job -ScriptBlock $myJob -ArgumentList $Parameter -Name "${CommandInfo}_Background_Job"
                
            } elseif ((-not $isAdmin) -and $RequireAdmin) {
                $fullCommand = 
"
`$parameter = $(Write-PowerShellHashtable -InputObject $parameter)
& { $myJob } `$parameter

"

                $encodedCommand = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($fullCommand))


                return  Start-Process powershell -Verb Runas -ArgumentList '-encodedCommand', $encodedCommand -PassThru
                
            }
        }
        }
        
        
        
        # All command services have to have a lot packed into each runspace, so a bit has to happen to set things up
        
        # - An InitialSessionState has to be created for the new runspace
        # - Potentially harmful or useless low-rights commands are removed from the runspace
        # - "Common" Functions are embedded into each handler
    
$resolveFinalUrl = {
# The tricky part is resolving the real URL of the service.  
# Split out the protocol
$protocol = $request['Server_Protocol'].Split("/", [StringSplitOptions]::RemoveEmptyEntries)[0]  
# And what it thinks it called the server
$serverName= $request['Server_Name']                     
$port = $request.Url.Port

# And the relative path beneath that URL
$shortPath = [IO.Path]::GetDirectoryName($request['PATH_INFO'])            
# Put them all together

if (($protocol -eq 'http' -and $port -eq 80) -or 
    ($protocol -eq 'https' -and $port -eq 443)) {
$remoteCommandUrl = 
    $Protocol + '://' + $ServerName.Replace('\', '/').TrimEnd('/') + '/' + $shortPath.Replace('\','/').TrimStart('/')
} else {
$remoteCommandUrl = 
    $Protocol + '://' + $ServerName.Replace('\', '/').TrimEnd('/') + ':' + $port + '/' + $shortPath.Replace('\','/').TrimStart('/')

}

# Now, if the pages was anything but Default, add the .ashx reference
$finalUrl = 
    if ($request['Url'].EndsWith("Default.ashx", [StringComparison]"InvariantCultureIgnoreCase")) {
        $u = $request['Url'].ToString()
        $remoteCommandUrl.TrimEnd("/") + "/" 
        # $remoteCommandUrl.TrimEnd("/") + $u.Substring($u.LastIndexOf("/"))

        
    } elseif ($request['Url'].EndsWith("Module.ashx", [StringComparison]"InvariantCultureIgnoreCase")) {
        $u = $request['Url'].ToString()
        $remoteCommandUrl.TrimEnd("/") + $u.Substring($u.LastIndexOf("/"))
    } else {
        $remoteCommandUrl.TrimEnd("/") + "/"
    }    
    

$fullUrl = "$($request.Url)"
if ($request -and $request.Params -and $request.Params["HTTP_X_ORIGINAL_URL"]) {
            
    #region Determine the Relative Path, Full URL, and Depth
    $originalUrl = $context.Request.ServerVariables["HTTP_X_ORIGINAL_URL"]
    $urlString = $request.Url.ToString().TrimEnd("/")
    $pathInfoUrl = $urlString.Substring(0, 
        $urlString.LastIndexOf("/"))
                                                            
    $protocol = ($request['Server_Protocol'].Split("/", 
        [StringSplitOptions]"RemoveEmptyEntries"))[0] 
    $serverName= $request['Server_Name']                     
            
    $port=  $request.Url.Port
    $fullOriginalUrl = 
        if (($Protocol -eq 'http' -and $port -eq 80) -or
            ($Protocol -eq 'https' -and $port -eq 443)) {
            $protocol+ "://" + $serverName + $originalUrl 
        } else {
            $protocol+ "://" + $serverName + ':' + $port + $originalUrl 
        }
                                                    
    $rindex = $fullOriginalUrl.IndexOf($pathInfoUrl, [StringComparison]"InvariantCultureIgnoreCase")
    $relativeUrl = $fullOriginalUrl.Substring(($rindex + $pathInfoUrl.Length))
    $rootUrl = $fullOriginalUrl.Substring(0, $pathInfoUrl.Length)
    if ($relativeUrl -like "*/*") {
        $depth = @($relativeUrl -split "/" -ne "").Count - 1                    
        if ($fullOriginalUrl.EndsWith("/")) { 
            $depth++
        }                                        
    } else {
        $depth  = 0
    }
    #endregion Determine the Relative Path, Full URL, and Depth                                                
    $fullUrl = $fullOriginalUrl
}
if (-not $rootUrl) {
    $rootUrl =  $fullurl.Substring(0, 
        $fullUrl.LastIndexOf("/"))     
}
$serviceUrl = $fullUrl
        }
              
$unpackItem = {
            $item = $_
            $item.psobject.properties |                         
                Where-Object { 
                    ('Timestamp', 'RowKey', 'TableName', 'PartitionKey' -notcontains $_.Name) -and
                    (-not "$($_.Value)".Contains(' ')) 
                }|                        
                ForEach-Object {
                    try {
                        $expanded = Expand-Data -CompressedData $_.Value
                        $item | Add-Member NoteProperty $_.Name $expanded -Force
                    } catch{
                        Write-Verbose $_
                    
                    }
                }
                
            $item.psobject.properties |                         
                Where-Object { 
                    ('Timestamp', 'RowKey', 'TableName', 'PartitionKey' -notcontains $_.Name) -and
                    (-not "$($_.Value)".Contains('<')) 
                }|                                   
                ForEach-Object {
                    try {
                        $fromMarkdown = ConvertFrom-Markdown -Markdown $_.Value
                        $item | Add-Member NoteProperty $_.Name $fromMarkdown -Force
                    } catch{
                        Write-Verbose $_
                    
                    }
                }

            $item                         
        }


        #region RefreshLatest
        $refreshLatest = {
            if (-not ($pipeworksManifest.Table -and $pipeworksManifest.Table.StorageAccountSetting -and $pipeworksManifest.Table.StorageKeySetting)) {
                throw 'The Pipeworks manifest must include three settings in order to retrieve items from table storage: Table, TableStorageAccountSetting, and TableStorageKeySetting'
                return
            }
            
            
            
            $storageAccount = (Get-WebConfigurationSetting -Setting $pipeworksManifest.Table.StorageAccountSetting)
            $storageKey = (Get-WebConfigurationSetting -Setting $pipeworksManifest.Table.StorageKeySetting)                                                           

            $latest = 
                Search-AzureTable -TableName $pipeworksManifest.Table.Name -Filter "PartitionKey eq '$PartitionKey'" -Select Timestamp, DatePublished, PartitionKey, RowKey -StorageAccount $storageAccount -StorageKey $storageKey |
                Sort-Object -Descending {
                    if ($_.DatePublished) {
                        [DateTime]$_.DatePublished
                    } else {
                        [DateTime]$_.Timestamp
                    }
                } |
                Select-Object -First 1 |
                Get-AzureTable -TableName $pipeworksManifest.Table.Name            
            
                                                                                                  
        }
        #endregion RefreshLatest

        # Writing the handler for a command actually involves writing several handlers, 
        # so we'll make this it's own little inline tool.  
        $writeSimpleHandler = {
        
param($cSharp, [Switch]$ShareRunspace, [Uint16]$PoolSize, [Switch]$ImportsPipeworks, [string[]]$EmbeddedCommand) 


        
        # Blacklist "bad" functions, and directory traversal
        $functionBlackList = 65..90 | 
            ForEach-Object -Begin {
                "ImportSystemModules", "Disable-PSRemoting", "Restart-Computer", "Clear-Host", "cd..", "cd\\", "more"
            } -Process { 
                [string][char]$_ + ":" 
            }
    

        if (-not $script:FunctionsInEveryRunspace) {
            $script:FunctionsInEveryRunspace = 'ConvertFrom-Markdown', 'Confirm-Person', 'Get-Person', 'Get-Web', 'Get-PipeworksManifest', 'Get-WebConfigurationSetting', 'Get-FunctionFromScript', 'Get-Walkthru', 
    'Get-WebInput', 'New-RssItem', 'Invoke-WebCommand', 'Out-RssFeed', 'Request-CommandInput', 'New-Region', 'New-WebPage', 'Out-Html', 
    'Write-Css', 'Write-Host', 'Write-Link', 'Write-ScriptHTML', 'Write-WalkthruHTML', 'Write-PowerShellHashtable', 'Compress-Data', 
    'Expand-Data', 'Import-PSData', 'Export-PSData', 'ConvertTo-ServiceUrl', 'Get-SecureSetting', 'Search-Engine', 'Get-Hash'


        }
 
        $embedSection = ""
        if (-not $ImportsPipeworks) {
                
         
        

            if (-not $EmbeddedCommand) {
                $EmbeddedCommand = $script:FunctionsInEveryRunspace
            }

            $EmbeddedCommand = $EmbeddedCommand | Select-Object -Unique
            $embedSection += foreach ($func in (Get-Command -Name $EmbeddedCommand -CommandType Function)) {

@"
        string compressed$($func.Name.Replace('-', ''))Defintion = "$(Compress-Data -String $func.Definition.ToString())";
        byte[] binaryDataFor$($func.Name.Replace('-', '')) = System.Convert.FromBase64String(compressed$($func.Name.Replace('-', ''))Defintion);
        System.IO.MemoryStream memoryStreamFor$($func.Name.Replace('-', '')) = new System.IO.MemoryStream(); 
        memoryStreamFor$($func.Name.Replace('-', '')).Write(binaryDataFor$($func.Name.Replace('-', '')), 0, binaryDataFor$($func.Name.Replace('-', '')).Length);
        memoryStreamFor$($func.Name.Replace('-', '')).Seek(0, 0);
        System.IO.Compression.GZipStream decompressorFor$($func.Name.Replace('-', '')) = 
            new System.IO.Compression.GZipStream(memoryStreamFor$($func.Name.Replace('-', '')), System.IO.Compression.CompressionMode.Decompress);
        System.IO.StreamReader readerFor$($func.Name.Replace('-', '')) = new System.IO.StreamReader(decompressorFor$($func.Name.Replace('-', '')));
        string decompressedDefinitionFor$($func.Name.Replace('-', '')) = readerFor$($func.Name.Replace('-', '')).ReadToEnd();
        SessionStateFunctionEntry $($func.Name.Replace('-',''))Command = new SessionStateFunctionEntry(
            "$($func.Name)", decompressedDefinitionFor$($func.Name.Replace('-', ''))
        );
        iss.Commands.Add($($func.Name.Replace('-',''))Command);
"@

        }               
        # Web handlers are essentially embedded C#, compiled on their first use.   The webCommandSequence class,
        # defined within this quite large herestring, is a bridge used to invoke PowerShell within a web handler.        
        
        }
        $webCmdSequence = @"
public class WebCommandSequence {
    public static InitialSessionState InitializeRunspace(string[] module) {
        InitialSessionState iss = InitialSessionState.CreateDefault();
        
        if (module != null) {
            iss.ImportPSModule(module);
        }
        $embedSection
        
        string[] commandsToRemove = new String[] { "$($functionBlacklist -join '","')"};
        foreach (string cmdName in commandsToRemove) {
            iss.Commands.Remove(cmdName, null);
        }
        
        
        return iss;
        
    }
    
    public static void InvokeScript(string script, 
        HttpContext context, 
        object arguments,
        bool throwError,
        bool shareRunspace) {
        
        PowerShell powerShellCommand = PowerShell.Create();
        bool justLoaded = false;
        Runspace runspace;
        RunspacePool runspacePool;
        PSInvocationSettings invokeWithHistory = new PSInvocationSettings();
        invokeWithHistory.AddToHistory = true;
        PSInvocationSettings invokeWithoutHistory = new PSInvocationSettings();
        invokeWithHistory.AddToHistory = false;
        
        if (! shareRunspace) {

            if (context.Session["UserRunspace"] == null) {                        
                justLoaded = true;
                InitialSessionState iss = WebCommandSequence.InitializeRunspace(null);
                Runspace rs = RunspaceFactory.CreateRunspace(iss);
                rs.ApartmentState = System.Threading.ApartmentState.STA;            
                rs.ThreadOptions = PSThreadOptions.ReuseThread;
                rs.Open();                
                powerShellCommand.Runspace = rs;
                context.Session.Add("UserRunspace",powerShellCommand.Runspace);
                powerShellCommand.
                    AddCommand("Set-ExecutionPolicy", false).
                    AddParameter("Scope", "Process").
                    AddParameter("ExecutionPolicy", "Bypass").
                    AddParameter("Force", true).
                    Invoke(null, invokeWithoutHistory);
                powerShellCommand.Commands.Clear();
            }

        

            runspace = context.Session["UserRunspace"] as Runspace;
            if (context.Application["Runspaces"] == null) {
                context.Application["Runspaces"] = new Hashtable();
            }
            if (context.Application["RunspaceAccessTimes"] == null) {
                context.Application["RunspaceAccessTimes"] = new Hashtable();
            }
            if (context.Application["RunspaceAccessCount"] == null) {
                context.Application["RunspaceAccessCount"] = new Hashtable();
            }

            Hashtable runspaceTable = context.Application["Runspaces"] as Hashtable;
            Hashtable runspaceAccesses = context.Application["RunspaceAccessTimes"] as Hashtable;
            Hashtable runspaceAccessCounter = context.Application["RunspaceAccessCount"] as Hashtable;

            if (! runspaceAccessCounter.Contains(runspace.InstanceId.ToString())) {
                runspaceAccessCounter[runspace.InstanceId.ToString()] = (int)0;
            }
            runspaceAccessCounter[runspace.InstanceId.ToString()] = ((int)runspaceAccessCounter[runspace.InstanceId.ToString()]) + 1;

            runspaceAccesses[runspace.InstanceId.ToString()] = DateTime.Now;


                    
            if (! runspaceTable.Contains(runspace.InstanceId.ToString())) {
                runspaceTable[runspace.InstanceId.ToString()] = runspace;
            }


            runspace.SessionStateProxy.SetVariable("Request", context.Request);
            runspace.SessionStateProxy.SetVariable("Response", context.Response);
            runspace.SessionStateProxy.SetVariable("Session", context.Session);
            runspace.SessionStateProxy.SetVariable("Server", context.Server);
            runspace.SessionStateProxy.SetVariable("Cache", context.Cache);
            runspace.SessionStateProxy.SetVariable("Context", context);
            runspace.SessionStateProxy.SetVariable("Application", context.Application);
            runspace.SessionStateProxy.SetVariable("JustLoaded", justLoaded);
            runspace.SessionStateProxy.SetVariable("IsSharedRunspace", false);
            powerShellCommand.Runspace = runspace;
            powerShellCommand.AddScript(@"
`$timeout = (Get-Date).AddMinutes(-20)
`$oneTimeTimeout = (Get-Date).AddMinutes(-1)
foreach (`$key in @(`$application['Runspaces'].Keys)) {
    if ('Closed', 'Broken' -contains `$application['Runspaces'][`$key].RunspaceStateInfo.State) {
        `$application['Runspaces'][`$key].Dispose()
        `$application['Runspaces'].Remove(`$key)
        continue
    }
    
    if (`$application['RunspaceAccessTimes'][`$key] -lt `$Timeout) {
        
        `$application['Runspaces'][`$key].CloseAsync()
        continue
    }    
}
").Invoke();

            powerShellCommand.Commands.Clear();
            powerShellCommand.AddScript(script, false);
            
            if (arguments is IDictionary) {
                powerShellCommand.AddParameters((arguments as IDictionary));
            } else if (arguments is IList) {
                powerShellCommand.AddParameters((arguments as IList));
            }
            Collection<PSObject> results = powerShellCommand.Invoke();        

        } else {
            if (context.Application["RunspacePool"] == null) {                        
                justLoaded = true;
                InitialSessionState iss = WebCommandSequence.InitializeRunspace(null);
                RunspacePool rsPool = RunspaceFactory.CreateRunspacePool(iss);
                rsPool.SetMaxRunspaces($PoolSize);
                rsPool.ApartmentState = System.Threading.ApartmentState.STA;            
                rsPool.ThreadOptions = PSThreadOptions.ReuseThread;
                rsPool.Open();                
                powerShellCommand.RunspacePool = rsPool;
                context.Application.Add("RunspacePool",rsPool);
                
                // Initialize the pool
                Collection<IAsyncResult> resultCollection = new Collection<IAsyncResult>();
                for (int i =0; i < $poolSize; i++) {
                    PowerShell execPolicySet = PowerShell.Create().
                        AddScript(@"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force 

#INSERTEVERYSECTIONIFNEEDED



", false);
                    execPolicySet.RunspacePool = rsPool;
                    resultCollection.Add(execPolicySet.BeginInvoke());
                }
                
                foreach (IAsyncResult lastResult in resultCollection) {
                    if (lastResult != null) {
                        lastResult.AsyncWaitHandle.WaitOne();
                    }
                }
                
                
                
                
                
                
                powerShellCommand.Commands.Clear();
            }
            

            powerShellCommand.RunspacePool = context.Application["RunspacePool"] as RunspacePool;
            
            
            string newScript = @"param(`$Request, `$Response, `$Server, `$session, `$Cache, `$Context, `$Application, `$JustLoaded, `$IsSharedRunspace, [Parameter(ValueFromRemainingArguments=`$true)]`$args)
            
            
            " + script;            
            powerShellCommand.AddScript(newScript, false);

            if (arguments is IDictionary) {
                powerShellCommand.AddParameters((arguments as IDictionary));
            } else if (arguments is IList) {
                powerShellCommand.AddParameters((arguments as IList));
            }            
            
            powerShellCommand.AddParameter("Request", context.Request);
            powerShellCommand.AddParameter("Response", context.Response);
            powerShellCommand.AddParameter("Session", context.Session);
            powerShellCommand.AddParameter("Server", context.Server);
            powerShellCommand.AddParameter("Cache", context.Cache);
            powerShellCommand.AddParameter("Context", context);
            powerShellCommand.AddParameter("Application", context.Application);
            powerShellCommand.AddParameter("JustLoaded", justLoaded);
            powerShellCommand.AddParameter("IsSharedRunspace", true);
            
            Collection<PSObject> results;
            try {
                results = powerShellCommand.Invoke();        
            } catch (Exception ex) {               
                if (
                    (String.Compare(ex.GetType().FullName, "System.Management.Automation.ParameterBindingValidationException") == 0) || 
                    (String.Compare(ex.GetType().FullName, "System.Management.Automation.RuntimeException") == 0)
                   ) {
                    // Parameter validation exception: clean it up a little.
                    ErrorRecord errRec = ex.GetType().GetProperty("ErrorRecord").GetValue(ex, null) as ErrorRecord;
                    if (errRec != null) {
                        try {
                            context.Response.StatusCode = (int)System.Net.HttpStatusCode.BadRequest;
                        } catch {
                        
                        }
                        context.Response.Write("<span class='ui-state-error' color='red'>" + errRec.InvocationInfo.PositionMessage + "</span><br/>");
                    }                    
                } else {
                    throw ex;
                }
            }
            
                        
            
            
        }
        
        
      
        foreach (ErrorRecord err in powerShellCommand.Streams.Error) {
            
            
            if (throwError) {
                if (err.Exception != null) {
                    if (err.Exception.GetType().GetProperty("ErrorRecord") != null) {
                        ErrorRecord errRec = err.Exception.GetType().GetProperty("ErrorRecord").GetValue(err.Exception, null) as ErrorRecord;
                        if (errRec != null) {
                            //context.Response.StatusCode = (int)System.Net.HttpStatusCode.PreconditionFailed;
                            //context.Response.StatusDescription = errRec.InvocationInfo.PositionMessage;
                            context.Response.Write("<span class='ui-state-error' style='line-height:200%' color='red'>" + err.Exception.ToString() + errRec.InvocationInfo.PositionMessage + "</span><br/>");
                        }                        
                        //context.Response.Flush();           
                    } else {
                        context.AddError(err.Exception);            
                    }   
                }
            } else {
                context.Response.Write("<span class='ui-state-error' style='line-height:200%' color='red'>" + err.Exception.ToString() + err.InvocationInfo.PositionMessage + "</span><br/>");                
            }            
        }
        
        if (powerShellCommand.InvocationStateInfo.Reason != null) {
            if (throwError) {                
                context.AddError(powerShellCommand.InvocationStateInfo.Reason);
            } else {                
                context.Response.Write("<span class='ui-state-error' style='line-height:200%' color='red'>" + powerShellCommand.InvocationStateInfo.Reason + "</span>");
            }
        }

        powerShellCommand.Dispose();
    
    }

}
"@      

        $webCommandSequence = $webCmdSequence


if ($pipeworksManifest.Every -and $pipeworksManifest.Every -is [Hashtable]) {
    $everySection = ""


    $n = 1
    foreach ($kv in $pipeworksManifest.Every.GetEnumerator()) {
        $interval = $kv.Key
        $everyAction = $kv.Value
        $everySection += "
`$everyTimer${n} = New-Object Timers.Timer -Property @{
    Interval = ([Timespan]'$interval').TotalMilliseconds
}

`$global:firstPulse = Get-Date

Register-ObjectEvent -InputObject `$everyTimer${n} -EventName Elapsed -SourceIdentifier EveryAction${n} -Action {
    $everyAction
    
}

`$everyTimer${n}.Start()
"    
        $n++
    }

    $webCommandSequence = $webCommandSequence.Replace('#INSERTEVERYSECTIONIFNEEDED', $everySection.Replace('"', '""'))
}





@"
<%@ WebHandler Language="C#" Class="Handler" %>
<%@ Assembly Name="System.Management.Automation, Version=1.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35" %>
using System;
using System.Web;
using System.Web.SessionState;
using System.Collections;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.Management.Automation;
using System.Management.Automation.Runspaces;

$webCommandSequence

public class Handler : IHttpHandler, IRequiresSessionState  {        
    public void ProcessRequest (HttpContext context) {
        $cSharp
    }
    
    public bool IsReusable {
    	get {
    	    return true;
    	}
    }
}    
"@    
}

                
    
    }
    process {     
    
        $theModule = Get-Module $name
        $theModulePaths = @($theModule| Split-Path)
        $theModulePaths += @($theModule.RequiredModules | Split-Path)
        $launched = . $asJobOrElevate $MyInvocation.MyCommand -additionalModules $theModulePaths -Parameter $psBoundParameters -RequireAdmin

        if ($launched) { return $launched} 

        if ($psCmdlet.ParameterSetName -eq 'LoadedModule') {
        
        
        $module = Get-Module $name | Select-Object -First 1       
        if (-not $module ) { return } 
        
        # Skip "accidental" modules
        if ($module.Path -like "*.ps1") { return } 
        
        
        
        
        
        
        if (-not $psBoundParameters.outputDirectory) {
            $outputDirectory = "${env:SystemDrive}\inetpub\wwwroot\$($Module.Name)\"            
            $outDirWasSet = $false    
        } else {
            $outDirWasSet = $true
        }

        if ((Test-Path $outputDirectory) -and (-not $force)) {
            Write-Error "$outputDirectory exists, use -Force to overwrite"
            return
        }
        if (-not $DoNotClean) {
            Write-Progress "Cleaning Output Directory" "$outputDirectory"
            Remove-Item $outputDirectory -Recurse -Force -ErrorVariable Issues
        }
        
        $null = New-Item -Path $outputDirectory -Force -ItemType Directory        
        Push-Location $outputDirectory
        $null = New-Item -Path "$outputDirectory\bin" -Force -ItemType Directory        
        



        # Urls to Rewrite stores the result. Each handler will need to rewrite several URLs for the functionality to work as expected
        $urlsToRewrite = @{}
        
        # To create a web command, we actually need to create several handlers and pages, depending on the options specified.        
        
                                    
        $moduleNumber = 0
        $realModule  = $module

        


        foreach ($m in $realModule) { 
            if (-not $m) { continue }       
            $moduleRoot = Split-Path $m.Path                     

            
            $ManifestPath = Join-Path $moduleRoot "$($module.Name).psd1"

            if (-not (Test-Path $ManifestPath)) {
"
# Module Manifest autogenerated by PowerShell Pipeworks.
@{
    ModuleVersion = 0.1
    ModuleToProcess = '$($module.Path | Split-Path -Leaf)'
}" |
    Set-Content $manifestPath
            }

            #region Initialize Pipeworks Manifest
            $pipeworksManifestPath = Join-Path $moduleRoot "$($module.Name).Pipeworks.psd1"
            $pipeworksManifest = if (Test-Path $pipeworksManifestPath) {
                try {                     
                    & ([ScriptBlock]::Create(
                        "data -SupportedCommand Add-Member, New-WebPage, New-Region, Write-CSS, Write-Ajax, Out-Html, Write-Link { $(
                            [ScriptBlock]::Create([IO.File]::ReadAllText($pipeworksManifestPath))                    
                        )}"))            
                } catch {
                    Write-Error "Could not read pipeworks manifest" 
                }                                                
            }
            
            if (-not $pipeworksManifest) { 
                $pipeworksManifest = @{
                    Pages = @{}
                    Posts = @{}
                    WebCommands = @{}                
                    Assets = @{}
                    Javascript = @{}
                    Download = @{}
                    CSS = @{}
                }
            }
            
            
            if ($pipeworksManifest.Css) {
                foreach ($cssItem in $pipeworksManifest.Css.GetEnumerator()) {
                    if ($cssItem.Value -like "*.less") {
                        if ($cssItem.Value -like "http*:*") {
                            # Public LESS file, download and compile
                            $lessCssFile = Get-Web -Url "$($cssItem.Value)" -UseWebRequest

                            $compiledLess = Use-Less -LessCss $lessCssFile

                            $lessDest = Join-Path "$moduleRoot\CSS" (([uri]$cssItem.Value).Segments[-1] -ireplace "\.less", ".css")

                            if (-not (Test-Path "$moduleRoot\CSS")) {
                                $null = New-Item -ItemType Directory -Path "$moduleRoot\CSS" -Force
                            }

                            [IO.File]::WriteAllText($lessDest, $compiledLess)

                        } elseif ($cssItem.Value -like "/*") {
                            # Private LESS file, resolve and compile
                            $lessCssFile = [IO.File]::ReadAllText((Join-Path $moduleRoot $cssItem.Value))

                            $compiledLess = Use-Less -LessCss $lessCssFile

                            $lessDest = (Join-Path $moduleRoot $cssItem.Value) -ireplace "\.less", ".css"
                            [IO.File]::WriteAllText($lessDest, $compiledLess)
                        }
                    }
                }
            }


            #region Inherit Settings from the Pipeworks Manifest
            if (-not ($Style -and $PipeworksManifest.Style)) {
                $Style = $PipeworksManifest.Style
            }
            
            
            # If there's no CSS style set, create a default one
            if (-not $Style) {
                $Style = @{
                    Body = @{
                        'Font-Family' = "'Segoe UI', 'Segoe UI Symbol', Helvetica, Arial, sans-serif"
                    }
                }
            }
            
            
            if (-not $psBoundParameters.MarginPercent -or ($psBoundParameters.MarginPercentLeft -and $psBoundParameters.MarginPercentRight)) {
                $marginPercentLeftString = "3%"
                $marginPercentRightString= "3%"
            } else {
                if ($psBoundParameters.MarginPercent) {
                    $marginPercentLeftString = $MarginPercent + "%"
                    $marginPercentRightString = $MarginPercent + "%"
                } else {
                    $marginPercentLeftString = $MarginPercentLeft+ "%"
                    $marginPercentRightString = $MarginPercentRight+ "%"
                }
            } 
            
            
            
            if ($pipeworksManifest.SecureSetting) {            
                foreach ($configSettingName in $pipeworksManifest.SecureSetting) {
                    if (-not $configSettingName) { continue }                
                    $settingValue = Get-SecureSetting -Name $configSettingName -ValueOnly -Type String
                    if ($settingValue) {
                        $configSetting[$configSettingName] = $settingValue
                    }
                }
            }
            
            if ($pipeworksManifest.SecureSettings) {            
                foreach ($configSettingName in $pipeworksManifest.SecureSettings) {
                    if (-not $configSettingName) { continue }                
                    $settingValue = Get-SecureSetting -Name $configSettingName -ValueOnly -Type String
                    if ($settingValue) {
                        $configSetting[$configSettingName] = $settingValue
                    }
                }
            }
                                    
            
            # If there's no analyticsId provided, and one exists in the pipeworks manifest, use it
            if (-not $analyticsId -and $pipeworksManifest.AnalyticsId) {
                $analyticsId = $pipeworksManifest.AnalyticsId
            }
            
            if (-not $AsIntranetSite -and $pipeworksManifest.AsIntranetSite) {
                $AsIntranetSite = $true
            }

            if ($pipeworksManifest.AppPoolUser) {
                if ($pipeworksManifest.AppPoolPasswordSetting -and (Get-SecureSetting -Name $pipeworksManifest.AppPoolPasswordsetting)) {
                    $newCred = New-Object Management.Automation.PSCredential $pipeworksManifest.AppPoolUser, (ConvertTo-SecureString -AsPlainText -Force (Get-SecureSetting $pipeworksManifest.AppPoolPasswordSetting -ValueOnly))
                    $appPoolCredential = $newCred
                } elseif (Get-SecureSetting -Name "${Module}AppPoolPassword") {
                    $newCred = New-Object Management.Automation.PSCredential $pipeworksManifest.AppPoolUser, (ConvertTo-SecureString -AsPlainText -Force (Get-SecureSetting "${Module}AppPoolPassword" -ValueOnly))
                    $appPoolCredential = $newCred
                } else {
                    $cred = Get-Credential -UserName $pipeworksManifest.AppPoolUser
                    Add-SecureSetting -Name "${Module}AppPoolPassword" -String $cred.GetNetworkCredential().Password
                    $AppPoolCredential = $cred
                }
                
            }

            if (-not $AllowDownload -and $pipeworksManifest.AllowDownload) {
                $AllowDownload = $true
            }


            if (-not $port -and ($pipeworksManifest.Port -as [uint32])) {
                $port = $pipeworksManifest.Port
            }
            
            
            $moduleBlogTitle = 
                if ($pipeworksManifest.Blog.Name) {
                    $pipeworksManifest.Blog.Name
                } else {
                    $module.Name
                }
            
            $moduleBlogDescription = 
                if ($pipeworksManifest.Blog.Description) {
                    $pipeworksManifest.Blog.Description
                } else {
                    $module.Description
                }
            
            $moduleBlogLink = 
                if ($pipeworksManifest.Blog.Link) {
                    $pipeworksManifest.Blog.Link
                } else {
                    "Blog.html"
                }

            if (-not $PipeworksManifest.Pages) {
                $PipeworksManifest.Pages = @{}
            }
            
            if (-not $PipeworksManifest.Javascript) {
                $PipeworksManifest.Javascript= @{}
            }
            
            if (-not $PipeworksManifest.CssFile) {
                $PipeworksManifest.CssFile = @{}
            }
            
            if (-not $PipeworksManifest.AssetFile) {
                $PipeworksManifest.AssetFile = @{}
            }
            #region Inherit Settings from the Pipeworks Manifest
            #endregion Initialize Pipeworks Manifest
                
            # Run the ezformat file, if present (and EZOut is loaded)
            if ((Test-Path "$moduleRoot\$($m.Name).ezformat.ps1") -and (Get-Module EZOut)) {                
                & "$moduleRoot\$($m.Name).ezformat.ps1"
            }
            $realModulePath = $m.Path
            $moduleNumber++
            
            if ($AllowDownload) {
                # If AllowDownload is set, create a .zip file to hold the module
                Write-Progress "Creating download" "Adding $($m) to zip file"
                $moduleZip = Join-Path $outputdirectory "$($m.Name).$($m.Version).Zip"
                if ($moduleNumber -eq 1 -and (Test-Path $moduleZip)) {                    
                    Remove-Item $moduleZip -Force
                }
                
                $tempModulePath = New-Item "$env:Temp\TempModule$(Get-Random)" -ItemType Directory
                $tempModuleDir = New-Item "$tempModulePath\$($m.Name)" -ItemType Directory
                
                
                
                
                # By looping thru all files with Get-ChildItem, hidden files get skipped.                
                $moduleFiles  = 
                    @(Get-ChildItem -Path $moduleRoot -Recurse |                    
                        Where-Object { -not $_.psIsContainer } | 
                        Copy-Item -Destination {                                                
                            $newPath = $_.FullName.Replace($moduleRoot, $tempModuleDir)
                            
                            $newDir = $newPAth  |Split-Path
                            if (-not (Test-Path $newDir)) {
                                $null = New-Item -ItemType Directory -Path "$newDir" -Force
                            }
                            
                            
                            Write-Progress "Copying $($req.name)" "$newPath"
                            $newPath             
                            
                        }  -passThru)
                # $null = Copy-ToZip -File $tempModuleDir -ZipFile $moduleZip -HideProgress    
                
                
                if ($m.RequiredModules) {
                    foreach ($requiredModuleInfo in $m.RequiredModules) {
                        
                        $requiredRoot = ($requiredModuleInfo | Split-Path)
                        $tempRequiredModuledir = New-Item "$tempModulePath\$($requiredModuleInfo.Name)" -ItemType Directory
                        $moduleFiles += Get-ChildItem $requiredRoot -Recurse | 
                            Where-Object { -not $_.psIsContainer } | 
                            Copy-Item -Destination {
                                $newPAth  = $_.FullName.Replace($requiredRoot, $tempRequiredModuleDir)
                                $newDir = $newPAth  |Split-Path 
                                if (-not (Test-Path $newDir)) {
                                    $null = New-Item -ItemType Directory -Path "$newDir" -Force
                                }
                                
                                
                                Write-Progress "Copying $($req.name)" "$newPath"
                                $newPath             
                            } -passthru
                            
                        #$null = Copy-ToZip -File $tempRequiredModuleDir -ZipFile $moduleZip -HideProgress    
                    }
                }
                $moduleList = @($RealModule.RequiredModules | 
                    Select-Object -ExpandProperty Name) + $realModule.Name
                        

                
                # Add an installer
                $installer = @'
echo "Installing modules from %~dp0"
'@

                $modulePaths = @()
                foreach ($m in $moduleList) {
                    $modulePaths += ('.\' + $m)
                    $installer += @"

xcopy "%~dp0$m" "%userprofile%\Documents\WindowsPowerShell\Modules\$m" /y /s /i /d 

"@
                }

                
                                    
                # Add shortcut items, if found in the pipeworks manifest                                                    
                if ($pipeworksManifest.Shortcut) {
                    $shortcutsFile = 
                        "`$moduleName = '$($realModule.Name)'" + {

$shell = New-Object -ComObject WScript.Shell
$startRoot = "$home\AppData\Roaming\Microsoft\Windows\Start Menu\Programs"
$moduleSubFolder = Join-Path $startRoot $moduleName
if (-not (Test-Path $moduleSubFolder)) {
    $null = New-Item -ItemType Directory -Path $moduleSubFolder
}

$modulefolder = Join-Path "$home\Documents\WindowsPowerShell\Modules" $moduleName                            

                        }
                    
                    $installer += @'

powershell -ExecutionPolicy Bypass -File "%~dp0AddShortcuts.ps1"

'@                    
                    foreach ($shortcutInfo in $pipeworksManifest.ShortCut.Getenumerator()) {
                        if ($shortcutInfo.Value -notlike "http*") {                        
                            $shortcutsFile += @"

`$sh = `$shell.CreateShortcut("`$moduleSubFolder\$($shortcutInfo.Key).lnk")                           
`$sh.WorkingDirectory = `$moduleFolder
`$sh.TargetPath = "`$psHome\powershell.exe"
`$sh.Arguments = '-executionpolicy bypass -windowstyle minimized -sta -command `$moduleDir = Join-Path `$env:UserProfile ''Documents\WindowsPowerShell\Modules'';Push-Location `$moduleDir;Import-Module `"$($modulePaths -join "`",`"")`";Pop-Location;$($shortcutInfo.Value)'
`$sh.Save()
"@
                        } else {
                            $shortcutsFile += @"

`$sh = `$shell.CreateShortcut("`$moduleSubFolder\$($shortcutInfo.Key).url")               
`$sh.TargetPath = "$($shortcutInfo.Value)"
`$sh.Save()
"@
                        }
                    }
                    
                    
                    
                    $shortcutsFile |
                        Set-Content "$tempModulePath\AddShortcuts.ps1"              
                }
                
                $installer |
                    Set-Content "$tempModulePath\install.cmd"              
                
                
                
                
                Get-ChildItem $tempModulePath -Recurse |
                    Out-Zip -zipFile $moduleZip -commonRoot $tempModulePath |
                    Out-Null
                
                
                if (Test-Path $moduleZip) {
                
                    # If there's a module.zip, it might have the wrong ACLs to be served up.  So make it allow anonymous access
                    $acl = 
                        Get-Acl -Path $moduleZip
                    $everyone =
                        New-Object Security.Principal.SecurityIdentifier ([Security.Principal.WellKnownSidType]"WorldSid", $null)
                    $allowAnonymous = 
                        New-Object Security.AccessControl.FileSystemAccessrule ($everyone , "ReadAndExecute","allow")                 
                    $acl.AddAccessRule($allowAnonymous )
                    Set-Acl -Path $moduleZip -AclObject $acl
                    
                    Remove-Item $tempModulePath -Recurse -Force
                }                
            }
        }                  

        Write-Progress "Creating Module Service" "Copying $($Module.name)"

        $moduleDir = (Split-Path $Module.Path)

        $moduleFiles=  Get-ChildItem -Path $moduleDir -Recurse -Force |
            Where-Object { -not $_.psIsContainer } 
        
        foreach ($moduleFile in $moduleFiles) {
            $moduleFile | 
                Copy-Item -Destination {                
                    $relativePath = $_.FullName.Replace("$moduleDir\", "")
                    $newPath = "$outputDirectory\bin\$($Module.Name)\$relativePath"                
                    $null = try {
                        New-Item -ItemType File -Path "$outputDirectory\bin\$($Module.Name)\$relativePath" -Force
                    } catch {
                        # Swallowing the error from creating a new file avoids the case where a file could not be removed, 
                        # and thus a terminating error stops the pipeline
                        $_
                    }
                    Write-Progress "Copying $($req.name)" "$newPath"
                    $newPath             
                } -Force #-ErrorAction SilentlyContinue 
        }
         
            



            $modulePath =  if ($module.Path -like "*.psm1") {
                $module.Path.Substring(0, $module.Path.Length - ".psm1".Length) + ".psd1"
            } else {
                
                $module.Path
            }
            
            $moduleFile = [IO.Path]::GetFileName($modulePath)
            $importChunk = @"
`$searchDirectory = if (`$request -and `$request.Params -and `$request.Params['PATH_TRANSLATED']) {
    `$([IO.Path]::GetDirectoryName(`$Request['PATH_TRANSLATED']))
} else {
    `$Request | Out-HTML
    return
    ''
}

`$searchOrder = @()
while (`$searchDirectory) {
    if (-not "`$searchDirectory`") {
        break
    }
    Set-Location `$searchDirectory 
    `$searchOrder += "`$searchDirectory\bin\$($Module.Name)"
    if (([IO.Directory]::Exists("`$searchDirectory\bin\$($Module.Name)"))) {
        #ImportRequiredModulesFirst
        Import-Module "`$searchDirectory\bin\$($Module.Name)\$moduleFile"
        break
    }
    `$searchDirectory = `$searchDirectory | Split-Path   
}
"@

        if ($Module.RequiredModules) {
            $importRequired = foreach ($req in $Module.RequiredModules) {
                # Make this callstack aware later                    

                $moduleDir = (Split-Path $req.Path)

                $moduleFiles = 
                Get-ChildItem -Path $moduleDir -Recurse -Force |                   
                    Where-Object { -not $_.psIsContainer }
                    
                foreach ($moduleFile in $moduleFiles) { 
                    $moduleFile | 
                        Copy-Item -Destination {
                        
                        
                            $relativePath = $_.FullName.Replace("$moduleDir\", "")
                            $newPath = "$outputDirectory\bin\$($req.Name)\$relativePath"                        
                            $null = New-Item -ItemType File -Path "$outputDirectory\bin\$($req.Name)\$relativePath" -Force
                            Write-Progress "Copying $($req.name)" "$newPath"
                            $newPath 
                        
                        } -Force #-ErrorAction SilentlyContinue
                }
                $reqDir = Split-Path $req.Path 
                "$(' ' * 8)Import-Module `"`$searchDirectory\bin\$($req.Name)\$($req.Name)`""
            }               
            $importChunk = $importChunk.Replace("#ImportRequiredModulesFirst", 
                $importRequired -join ([Environment]::NewLine))
        }

        $ModuleBranding = 
            if ($pipeworksManifest.Branding) {
                if (-not "$($pipeworksManifest.Branding)".Trim()) {
                    $pipeworksManifest.Branding
                } else {
                    ConvertFrom-Markdown $pipeworksManifest.Branding -ShowData                
                }
                
            } elseif ($module.CompanyName -eq 'Start-Automating') {
@"
<div style='text-align:right'>

<div style='font-size:.75em;text-align:right;'>
Provided By 
<a href='http://start-automating.com'>
<img src='http://StartAutomating.com/Assets/StartAutomating_100_Transparent.png' alt='Start-Automating' style='vertical-align:middle;width:60px;height:60px;border:0' />
</a>

</div>

<div style='font-size:.75em;text-align:right;'>
Powered With
<a href='http://powershellpipeworks.com'>
<img src='http://powershellpipeworks.com/assets/powershellpipeworks_150.png' alt='PowerShell Pipeworks' style='vertical-align:middle;width:60px;height:60px;border:0' />
</a>

</div>
</div>
"@
            } else {
@"
<div style='font-size:.75em;text-align:right'>
Powered With
<a href='http://powershellpipeworks.com'>
<img src='http://powershellpipeworks.com/assets/powershellpipeworks_150.png' alt='PowerShell Pipeworks' align='middle' style='width:60px;height:60px;border:0' />
</a>

</div>
"@
            } 

        $initModuleDefaults = [ScriptBlock]::Create(@"
if (-not `$global:PipeworksManifest) {
    if (`$PipeworksManifest) {
        `$global:PipeworksManifest = `$PipeworksManifest
    } else {
        `$global:PipeworksManifest = @{}
    }
    
}
if (-not `$global:PipeworksManifest.Style) {
    `$global:PipeworksManifest.Style = @{
        Body = @{
            'Font-Family' = "'Segoe UI', 'Segoe UI Symbol', Helvetica, Arial, sans-serif"            
            'color' = '#0248B2'
            'background-color' = '#FFFFFF'
        }
        'a' = @{
            'color' = '#012456'
        }
    }
    
}

if (-not `$global:PipeworksManifest.Css) {
    `$global:PipeworksManifest.Css = @{}
}

if (-not `$global:SiteForegroundColor) {
    `$global:SiteForegroundColor = `$global:PipeworksManifest.Style.Body.Color
}

if (-not `$global:SiteBackgroundColor) {
    `$global:SiteBackgroundColor = `$global:PipeworksManifest.Style.Body.'background-color'
}

if (-not `$global:SiteLinkColor) {
    `$global:SiteLinkColor = `$global:PipeworksManifest.Style.a.Color
}

if (-not `$global:PipeworksManifest.ModuleTemplate ) {
    `$global:PipeworksManifest.ModuleTemplate = 'Module'    
}

if (-not `$global:PipeworksManifest.CommandTemplate) {
    `$global:PipeworksManifest.CommandTemplate = 'Command'    
}

if (-not `$global:PipeworksManifest.TopicTemplate) {
    `$global:PipeworksManifest.TopicTemplate = 'Topic'    
}

if (-not `$global:PipeworksManifest.UseJQueryUI -and -not `$global:PipeworksManifest.UseBootstrap) {
    #`$global:PipeworksManifest.UseJQueryUI = `$true
    `$global:PipeworksManifest.Css['PipeworksCss'] = 'css/$($module).css'
}

if (-not `$global:PipeworksManifest.Ajax) {
    `$global:PipeworksManifest.NoAjax = `$true
}
"@)        
        
        # Create the embed command.
        $embedCommand = $importChunk
        $embedCommand = $embedCommand + @"
if (-not `$global:RealModule -or `$global:RealModule.Name -ne '$($module.Name)') {
`$realModule = `$module = Get-Module `"$($module.Name)`" | Select-Object -First 1
if (-not `$module) { `$response.Write(`$searchOrder -join '<BR/>'); `$response.Flush()  } 
`$moduleRoot = [IO.Path]::GetDirectoryName(`$module.Path)

`$global:RealModule = `$Module
`$global:PipeworksManifest = `$null
`$script:CachedTopics = @{}
`$script:CachedWalkthrus = @{}
`$cmdTabs = @{}
`$navBarData = @{}
`$navBarUrls = @{}
`$navBarOrder = @{}
`$coreAboutTopic = `$null
`$otherAboutTopics = `$null
`$walkThrus = @{}
`$aboutTopics = @()
`$allAboutFiles = `$null

} else {
    `$module = `$global:RealModule
}
`$moduleCommands = `$module.ExportedCommands.Values
`$moduleCompany = `$module.CompanyName
`$global:ModuleMaker = `$Module.CompanyName
`$pipeworksManifestPath = `$moduleRoot + '\' + "`$(`$module.Name).Pipeworks.psd1"
if (-not `$global:PipeworksManifest -and ([IO.File]::Exists(`$pipeworksManifestPath))) {
try {                     
    `$global:pipeworksManifest = & ([ScriptBlock]::Create(
        "data -SupportedCommand Add-Member, New-WebPage, New-Region, Write-CSS, Write-Ajax, Out-Html, Write-Link { `$(
            [ScriptBlock]::Create([IO.File]::ReadAllText(`$pipeworksManifestPath))                    
        )}"))            
} catch {
    Write-Error "Could not read pipeworks manifest" 
}                                                
}

$initModuleDefaults


`$script:CachedBrandingSlot = @'
$ModuleBranding
'@
"@
        
        $embedCommand = [ScriptBlock]::Create($embedCommand)  
        $moduleRoot = (Split-Path $module.Path)        


        if (-not $PipeworksManifest.UseJQueryUI -and -not $PipeworksManifest.UseBootstrap) {
            if (-not (Test-Path "$OutputDirectory\css\")) {
                $null= New-Item -ItemType Directory -Path "$OutputDirectory\css\" -Force
            }

            $pipeworksRoot = $MyInvocation.MYCommand.ScriptBlock.Module | Split-Path
            $lessCss = ([IO.File]::ReadAllText((Join-Path $pipeworksRoot "css\Pipeworks.less")))


            $options = @{}

            if ($pipeworksManifest.style.body.'background-color'){
                $options['Background'] = $pipeworksManifest.style.body.'background-color'
            }
            if ($pipeworksManifest.style.body.'color'){
                $options['Foreground'] = $pipeworksManifest.style.body.'color'
            }

            if ($pipeworksManifest.style.body.'font-Family') {
                $options['fontFamily'] = $pipeworksManifest.style.body.'font-Family'
            }


            $myCss = Use-Less -LessCss $lessCss -Option $options
            [IO.File]::WriteAllText("$OutputDirectory\css\$($module).css", $myCss)
        }
        
        #region Check for the presence of directories, and put items within them into the manifest
        
        
        # Pick out all possible cultures
        $cultureNames = [Globalization.CultureInfo]::GetCultures([Globalization.CultureTypes]::AllCultures) | 
            Select-Object -ExpandProperty Name


        $tokensInPages = New-Object Collections.ArrayList
        # Pages fall back on culture
        Write-Progress "Importing Pages" " " 
        $pagePaths  = @((Join-Path $moduleRoot "Pages"))


        foreach ($cultureName in $cultureNames) {
            if (-not $cultureName) { continue } 
            $pagePaths+= @((Join-Path $cultureName "Pages"))
        }



        
       

        foreach ($pagePath in $pagePaths) {
            if (Test-Path $pagePath) {
                Get-ChildItem $pagePath -Recurse |
                    Where-Object {                        
                        (-not $_.PSIsContainer) -and
                        '.htm', '.html', '.ashx','.aspx',
                            '.jpg', '.gif', '.jpeg', '.js', '.css', 
                            '.ico',
                            '.png', '.mpeg','.mp4',  
                            '.mp3', '.wav', '.pspage', '.docx', '.pptx', '.xlsx', '.md', '.psmd', '.pdf'
                            '.pspg', '.ps1' -contains $_.Extension
                    } | 
                    ForEach-Object -Process {
                        if ($_.Extension -ne '.ps1') {
                            # These are simple, just make the page
                            if ($_.Extension -ne '.pspage' -and 
                                $_.Extension -ne '.html' -and 
                                $_.Extension -ne '.psmd' -and 
                                $_.Extension -ne '.md') {

                                $bytes = try { [IO.File]::ReadAllBytes($_.Fullname) } catch { }
                                if ($bytes) {
                                    $pipeworksManifest.Pages[$_.Fullname.Replace(($module | Split-Path), "").Replace("Pages\","").TrimStart("\")] = $bytes
                                }

                            } else {
                                $text = [IO.File]::ReadAllText($_.Fullname)
                                $pipeworksManifest.Pages[$_.Fullname.Replace(($module | Split-Path), "").Replace("Pages\","").TrimStart("\")] = $text 
                                    
                                

                                
                            }
                            
                        } else {
                            
                            # Embed the ps1 file contents within a <| |>, but escape the <| |> contained within
                            $fileContents = "$([IO.File]::ReadAllText($_.Fullname))"
                            if ($fileContents) {
                                $sb = [ScriptBlock]::Create($fileContents)                                
                                $t = [Management.Automation.PSParser]::Tokenize($sb, [ref]$null)
                                $null = $tokensInPages.AddRange($t)
                            }
                            $fileContents = $fileContents.Replace("<|", "&lt;|").Replace("|>", "|&gt;")
                            $pipeworksManifest.Pages[($_.Fullname.Replace(($module | Split-Path), "").Replace("Pages\","")).Replace(".ps1", ".pspage").TrimStart("\")] = "<| $fileContents
|>"
                            
                            
                        }
                        
                    }
                    
            }
        }
        
        # Posts also fall back on culture
        $pagePaths  = (Join-Path $moduleRoot "Posts"),            
            (Join-Path $moduleRoot "Blog")
                        
        foreach ($cultureName in $cultureNames) {
            if (-not $cultureName) { continue } 
            $pagePaths+= @((Join-Path $cultureName "Blog"))
            $pagePaths+= @((Join-Path $cultureName "Posts"))
        }


        foreach ($pagePath in $pagePaths) {
            if (Test-Path $pagePath) {
                Get-ChildItem $pagePath |
                    Where-Object {                        
                        $_.Name -like "*.post.psd1" -or
                        $_.Name -like "*.pspost" -or
                        $_.Name -like "*.html"
                    } | 
                    ForEach-Object -Begin {
                        if (-not $PipeworksManifest.Posts) {
                            $PipeworksManifest.Posts = @{}
                        }
                    } -Process {
                        $pipeworksManifest.Posts[$_.Name.Replace(".post.psd1","").Replace(".pspost","").Replace(".html","")] = ".\$($_.Directory.Name)\$($_.Name)"
                    }
                    
            }
        }



        
        $jsPaths = (Join-Path $moduleRoot "JS"),            
            (Join-Path $moduleRoot "Javascript")
        
        foreach ($cultureName in $cultureNames) {
            if (-not $cultureName) { continue } 
            $jsPaths += @((Join-Path $cultureName "JS"))
            $jsPaths += @((Join-Path $cultureName "JavaScript"))
        }
        foreach ($jsPath in $jsPaths) {
            if (Test-Path $jsPath) {
                Get-ChildItem $jsPath |
                    Where-Object {                        
                        $_.Name -like "*.js"
                    } | 
                    ForEach-Object -Process {                                            
                        if (-not $_.psiscontainer) {                                        
                            $pipeworksManifest.Javascript[$_.Fullname.Replace(($module | Split-Path), "")] = [IO.File]::ReadAllBytes($_.Fullname)
                        }
                    }
                    
            }
        }
        
        $cssPaths = @(Join-Path $moduleRoot "CSS")

        foreach ($cultureName in $cultureNames) {
            if (-not $cultureName) { continue } 
            $cssPaths += @((Join-Path $cultureName "CSS"))            
        }

        foreach ($cssPath in $cssPaths) {
            if (Test-Path $cssPath) {
                Get-ChildItem $cssPath -Recurse |
                    ForEach-Object -Process {                                            
                        if (-not $_.psiscontainer) {                                        
                            $pipeworksManifest.CssFile[$_.Fullname.Replace(($module | Split-Path), "")] = [IO.File]::ReadAllBytes($_.Fullname)
                        }
                    }
                    
            }
        }
        
        $pipeworksRoot = Get-Module Pipeworks | Split-Path
        
        $assetPaths = (Join-Path $moduleRoot "Asset"),            
            (Join-Path $moduleRoot "Assets"),
            (Join-Path $moduleRoot "Resource"),
            (Join-Path $moduleRoot "Resources"),
            (Join-Path $moduleRoot "Image"),
            (Join-Path $moduleRoot "Images"),
            (Join-Path $moduleRoot "IMG"),
            (Join-Path $pipeworksRoot "Template"),
            (Join-Path $pipeworksRoot "Templates"),
            (Join-Path $moduleRoot "Template"),
            (Join-Path $moduleRoot "Templates")
            
        
        foreach ($cultureName in $cultureNames) {
            if (-not $cultureName) { continue } 
            $assetPaths  += @((Join-Path $cultureName "Asset"))                        
            $assetPaths  += @((Join-Path $cultureName "Assets"))           
            $assetPaths  += @((Join-Path $cultureName "Resource"))            
            $assetPaths  += @((Join-Path $cultureName "Resources"))            
            $assetPaths  += @((Join-Path $cultureName "Image"))            
            $assetPaths  += @((Join-Path $cultureName "Images"))            
            $assetPaths  += @((Join-Path $cultureName "IMG"))            
        }


        foreach ($assetPath in $assetPaths) {
            if (Test-Path $assetPath ) {
                Get-ChildItem $assetPath  -Recurse |
                    ForEach-Object -Process {     
                        $fileInfo  = $_
                        if (-not $_.psiscontainer) {                                                         
                            $pipeworksManifest.AssetFile[$_.Fullname.Replace($moduleRoot, "").Replace($pipeworksRoot, "")] = [IO.File]::ReadAllBytes($_.Fullname)
                        }
                    }
                    
            }
        }
        #endregion Check for the presence of directories, and put items within them into the manifest
        
        if ($pipeworksManifest.UseJQuery -and 
            -not ($pipeworksManifest.'JavaScript'.Keys -like "*jquery.min.js*")) {
            $latestJQuery = 
                Get-Web -Url "http://jquery.com/download/" -Tag 'a' | 
                Where-Object {$_.Xml.Href -like "*.min.js" } | 
                Select-Object -First 1 | 
                ForEach-Object  { $_.Xml.Href } | 
                Get-Web -Url {$_ } -UseWebRequest -AsByte


            $jQueryFile = New-item -ItemType File -Path $moduleRoot\JS\jquery.min.js -Force

            [IO.File]::WriteAllBytes($jQueryFile.FullName, $latestJQuery)
            

            $pipeworksManifest.Javascript["JS\jquery.min.js"] = $latestJQuery
        }

        if ($PipeworksManifest.UseTableSorter -and 
            -not ($pipeworksManifest.'JavaScript'.Keys -like "*tablesorter*")) {
                $tableSorterFile = New-item -ItemType File -Path $moduleRoot\JS\tablesorter.min.js -Force
                Get-Web http://tablesorter.com/__jquery.tablesorter.min.js |
                    Set-Content $moduleRoot\JS\tablesorter.min.js

            $pipeworksManifest.Javascript["JS\tablesorter.min.js"] = [IO.File]::ReadAllBytes("$moduleRoot\JS\tablesorter.min.js")                
        }

        if (($pipeworksManifest.UseRaphael  -or $pipeworksManifest.UseGRaphael )-and 
            -not ($pipeworksManifest.'JavaScript'.Keys -like "*raphael*")) {
            
            $raphael = New-item -ItemType File -Path $moduleRoot\JS\raphael-min.js -Force
            Get-Web -Url http://raphaeljs.com/raphael.js -UseWebRequest -HideProgress |
                Set-Content $raphael.Fullname -Encoding UTF8                

            $pipeworksManifest.Javascript["JS\raphael-min.js"] = [IO.File]::ReadAllBytes("$moduleRoot\JS\raphael-min.js")                
        }

        if ($pipeworksManifest.UseGRaphael -and 
            -not ($pipeworksManifest.'JavaScript'.Keys -like "*g.raphael*")) {
            
            $raphael = New-item -ItemType File -Path $moduleRoot\JS\g.raphael.js -Force
            Get-Web -url http://g.raphaeljs.com/g.raphael.js -UseWebRequest -HideProgress |
                Set-Content $raphael.Fullname                


            $raphaelBar = New-item -ItemType File -Path $moduleRoot\JS\g.bar.js -Force
            Get-Web -url http://g.raphaeljs.com/g.bar.js -UseWebRequest -HideProgress |
                Set-Content $raphaelBar.Fullname                

            $raphaelLine = New-item -ItemType File -Path $moduleRoot\JS\g.line.js -Force
            Get-Web -url http://g.raphaeljs.com/g.line.js -UseWebRequest -HideProgress |
                Set-Content $raphaelLine.Fullname                

            $raphaelPie = New-item -ItemType File -Path $moduleRoot\JS\g.pie.js -Force
            Get-Web -url http://g.raphaeljs.com/g.pie.js -UseWebRequest -HideProgress|
                Set-Content $raphaelPie.Fullname                

            $pipeworksManifest.Javascript["JS\g.raphael.js"] = [IO.File]::ReadAllBytes("$moduleRoot\JS\g.raphael.js")                
            $pipeworksManifest.Javascript["JS\g.line.js"] = [IO.File]::ReadAllBytes("$moduleRoot\JS\g.line.js")                
            $pipeworksManifest.Javascript["JS\g.pie.js"] = [IO.File]::ReadAllBytes("$moduleRoot\JS\g.pie.js")                
            $pipeworksManifest.Javascript["JS\g.bar.js"] = [IO.File]::ReadAllBytes("$moduleRoot\JS\g.bar.js")                
        }


        if (($pipeworksManifest.UseShiv -or $pipeworksManifest.UseShiv) -and
            -not ($pipeworksManifest.'JavaScript'.Keys -like "*shiv*")) {
            $shiv = @{
                "https://github.com/aFarkas/html5shiv/blob/master/dist/html5shiv.js?raw=true" = "JS\html5shiv.js"
            }

            
            $pipeworksManifest.Download+=$shiv
        }


        

        if (($pipeworksManifest.Bootstrap -or $pipeworksManifest.UseBootstrap) -and
            -not ($pipeworksManifest.'JavaScript'.Keys -like "*bootstrap*")) {
            
            
            $textColor = if ($pipeworksManifest.Style.Body.color) {
                $pipeworksManifest.Style.Body.color
            } else {
                "#0248b2"
            }


            $linkColor =  if ($pipeworksManifest.Style.a.color) {
                $pipeworksManifest.Style.a.color
            } else {
                "#0248b2"
            } 

            $backgroundColor = if ($pipeworksManifest.Style.body.'background-color') {
                $pipeworksManifest.Style.body.'background-color'
            } else {
                "#ffffff"
            }
            
            
            $fontFamily = if ($pipeworksManifest.Style.body.'font-family') {
                $pipeworksManifest.Style.body.'font-family'
            } else {
                "'Segoe UI', Helvetica, Arial, sans-serif"
            } 

            $fontSize = if ($pipeworksManifest.Style.body.'font-size') {
                $pipeworksManifest.Style.body.'font-size'
            } else {
                '15px'
            }
            
            $lineHeight = if ($pipeworksManifest.Style.body.'line-height') {
                $pipeworksManifest.Style.body.'line-height'
            } else {
                '21px'
            } 

            # Download a customized bootstrap, containing their core color scheme.            
            $r =
                Get-web -Url "http://bootstrap.herokuapp.com/" -Method POST -Parameter @{
                    js = '["bootstrap-transition.js","bootstrap-modal.js","bootstrap-dropdown.js","bootstrap-scrollspy.js","bootstrap-tab.js","bootstrap-tooltip.js","bootstrap-popover.js","bootstrap-affix.js","bootstrap-alert.js","bootstrap-button.js","bootstrap-collapse.js","bootstrap-carousel.js","bootstrap-typeahead.js"]'
                    css= '["reset.less","scaffolding.less","grid.less","layouts.less","type.less","code.less","labels-badges.less","tables.less","forms.less","buttons.less","sprites.less","button-groups.less","navs.less","navbar.less","breadcrumbs.less","pagination.less","pager.less","thumbnails.less","alerts.less","progress-bars.less","hero-unit.less","media.less","tooltip.less","popovers.less","modals.less","dropdowns.less","accordion.less","carousel.less","wells.less","close.less","utilities.less","component-animations.less","responsive-utilities.less","responsive-767px-max.less","responsive-768px-979px.less","responsive-1200px-min.less","responsive-navbar.less"]'
                    vars="{
`"@bodyBackground`":`"$backgroundColor`",
`"@inputBackground`":`"$backgroundColor`",
`"@inputText`":`"$fgColor`",
`"@tableBackground`":`"$backgroundColor`",
`"@heroUnitBackground`":`"$backgroundColor`",
`"@heroUnitHeadingColor`":`"$textColor`",
`"@heroLeadColor`":`"$textColor`",
`"@infoBackground`":`"$backgroundColor`",
`"@infoText`":`"$textColor`",
`"@placeHolderText`":`"$textColor`",
`"@headingsColor`":`"$textColor`",
`"@tableBackgroundAccount`":`"$backgroundColor`",
`"@tableBackgroundHover`":`"$textColor`",
`"@navbarBackground`":`"$backgroundColor`",
`"@navbarBackgroundHighlight`":`"$backgroundColor`",
`"@navbarSearchBackground`":`"$backgroundColor`",
`"@navbarLinkBackgroundActive`":`"$textColor`",
`"@navbarSearchBackgroundFocus`":`"$textColor`",
`"@navbarText`":`"$textColor`",
`"@navbarBrandColor`":`"$textColor`",
`"@navbarLinkColor`":`"$linkColor`",
`"@navbarLinkColorHover`":`"$textColor`",
`"@navbarLinkColorActive`":`"$textColor`",
`"@dropDownBackground`":`"$backgroundColor`",
`"@textColor`":`"$textColor`",
`"@dropdownBackground`":`"$backgroundColor`",
`"@dropdownLinkColor`":`"$linkColor`",
`"@dropdownLinkColorHover`":`"$backgroundColor`",
`"@dropdownLinkBackgroundHover`":`"$linkColor`",
`"@btnPrimaryBackground`":`"$LinkColor`",
`"@btnPrimaryBackgroundHighlight`":`"$backgroundColor`",
`"@formActionsBackground`":`"$backgroundColor`",
`"@linkColor`":`"$linkColor`",
`"@sansFontFamily`":`"$fontFamily`",
`"@monoFontFamily`":`"Menlo, Monaco, 'Consolas'`",
`"@baseFontSize`":`"$FontSize`",
`"@baseLineHeight`":`"$LineHeight`"}"
                    img='["glyphicons-halflings.png","glyphicons-halflings-white.png"]'
} -AsByte -UseWebRequest


            [IO.File]::WriteAllBytes("$moduleRoot\BootStrap.zip", $r)
            Expand-Zip -ZipPath "$moduleRoot\BootStrap.zip" -OutputPath "$moduleRoot"
            Remove-Item "$moduleRoot\bootstrap.zip"                                    


            # Replace cases of the input foreground with the real text color
            if ($backgroundColor -eq '#555555') {
                Write-Warning "The specific background color of #555555 will be replaced by the textColor: $textColor, because Bootstrap's customization engine doesn't allow customization of the input text color."
            }

            $bsCss = [IO.File]::ReadAllText("$ModuleRoot\css\bootstrap.css")
            [IO.File]::WriteAllText("$ModuleRoot\css\bootstrap.css", $bsCss.Replace('#555555', $textColor))

            $latestJQuery = 
                Get-Web -Url "http://jquery.com/download/" -Tag 'a' | 
                Where-Object {$_.Xml.Href -like "*.min.js" } | 
                Select-Object -First 1 | 
                ForEach-Object  { $_.Xml.Href } | 
                Get-Web -Url {$_ } -UseWebRequest -AsByte


            $jQueryFile = New-item -ItemType File -Path $moduleRoot\JS\jquery.min.js -Force

            [IO.File]::WriteAllBytes($jQueryFile.FullName, $latestJQuery)
            

            $pipeworksManifest.Javascript["JS\jquery.min.js"] = $latestJQuery


            $pipeworksManifest.Javascript["JS\bootstrap.min.js"] = [IO.File]::ReadAllBytes("$moduleRoot\JS\bootstrap.min.js")                
            $pipeworksManifest.Javascript["JS\bootstrap.js"] = [IO.File]::ReadAllBytes("$moduleRoot\JS\bootstrap.js")                
            $pipeworksManifest.Javascript["CSS\bootstrap.css"] = [IO.File]::ReadAllBytes("$moduleRoot\CSS\bootstrap.css")                
            $pipeworksManifest.Javascript["CSS\bootstrap.min.css"] = [IO.File]::ReadAllBytes("$moduleRoot\CSS\bootstrap.min.css")                
            $pipeworksManifest.Javascript["IMG\glyphicons-halflings-white.png"] = [IO.File]::ReadAllBytes("$moduleRoot\IMG\glyphicons-halflings-white.png")                
            $pipeworksManifest.Javascript["IMG\glyphicons-halflings.png"] = [IO.File]::ReadAllBytes("$moduleRoot\IMG\glyphicons-halflings.png")                
        }



        #region GitIt
        if ($pipeworksManifest.GitIt) {            

            if (-not $gitIt) {

            }


            foreach ($git in $pipeworksManifest.GitIt) {
                if ($git -is [Hashtable]) {
                    foreach ($kv in $git.GetEnumerator()) {
                        $gitAt = $kv.Key.Tostring().Replace("\","/")
                        if ($gitAt -notlike "*/*/*") {
                            Write-Error "Each key in $GitAt must include author and project"
                            return
                        }


                        if ($gitAt.EndsWith('*')) {
                            $treeUrl = "https://github.com/$($gitAt.TrimEnd('*/'))/tree"
                            $gitHtml = Get-Web -Url $treeUrl  -UseWebRequest
                        } else {
                            $gitBits = $gitAt -split '\/'
                            $gitUrl = 'https://raw.github.com/' + 
                                $gitBits[0] + 
                                '/' + 
                                $gitBits[1] + 
                                '/master/' + 
                                ($gitBits[2..($gitBits.Length - 1)] -join '/')
                            $gitTo = $kv.Value.ToString().Replace('/', '\')
                            $downloadedfile = New-item -ItemType File -Path "${moduleRoot}/$($gitTo.Replace('\', '/').TrimStart('/'))" -Force    
                            $content = Get-Web -Url $gitUrl -UseWebRequest -AsByte

                            if (-not $content) {
                                Write-Error "$GitAt not on GitHub"
                                continue
                            }
                            [IO.File]::WriteAllBytes($downloadedfile.Fullname, $content)                
               
                            $pipeworksManifest.AssetFile[$kv.Value] = [IO.File]::ReadAllBytes($downloadedfile.Fullname)
                        }
                        
                        
                
                        
                    }
                }
            }

        }

                
        #endregion GitIt

        #region Download
        if ($pipeworksManifest.Download -and $pipeworksManifest.Download -as [Hashtable]) {
            foreach ($kv in $pipeworksManifest.Download.GetEnumerator()) {
                if (-not $kv.Key) { continue } 
                $downloadedfile = New-item -ItemType File -Path "${moduleRoot}/$($kv.value)" -Force
                $content = $null
                
                $content = Get-Web -Url $kv.Key -AsByte -UseWebRequest
                if ($kv.key -like "*.min.js") {
                    $null = $content 
                }
                if (-not $content) {
                    continue
                }
                [IO.File]::WriteAllBytes($downloadedfile.Fullname, $content)                
               
                $pipeworksManifest.AssetFile[$kv.Value] = [IO.File]::ReadAllBytes("${moduleRoot}/$($kv.Value.ToString().Replace('\','/'))")
            }
        }
        
        #endregion Download
                
        #region Embedded Javascript, CSS, and Assets
        
        foreach ($directlyEmbeddedFileTable in 'Javascript', 'CssFile', 'AssetFile') {
            foreach ($fileAndData in $pipeworksManifest.$directlyEmbeddedFileTable.GetEnumerator()) {
                if (-not $fileAndData.Key) { continue } 
                try {
                $null = New-Item "$outputDirectory\$($fileAndData.Key)" -ItemType File -Force
                [IO.File]::WriteAllBytes("$outputDirectory\$($fileAndData.Key)", $fileAndData.Value)
                } catch {
                    $null = $_
                }
            }
        }
        
        
        #endregion
        
        
        #region Object Pages
        if ($pipeworksManifest.ObjectPages) {
            foreach ($objectPageInfo in $pipeworksManifest.ObjectPages.GetEnumerator()) {
                $pagename = $objectPageInfo.Key
                $value = $objectPageInfo.Value                
                $webOBjectPage = @"
`$storageAccount  = Get-WebConfigurationSetting -Setting `$pipeworksManifest.Table.StorageAccountSetting 
`$storageKey= Get-WebConfigurationSetting -Setting `$pipeworksManifest.Table.StorageKeySetting 
`$part, `$row  = '$($objectPageInfo.Value.Id)' -split '\:'
`$lMargin = '$marginPercentLeftString'
`$rMargin = '$marginPercentRightString'
`$pageName = '$($value.Title)'
"@ + {

if (-not $session["ObjectPage$($PageName)"]) {
    $session["ObjectPage$($PageName)"] = 
        Show-WebObject -StorageAccount $storageAccount -StorageKey $storageKey -Table $pipeworksManifest.Table.Name -Part $part -Row $row |
        New-Region -Style @{
            'Margin-Left' = $lMargin
            'Margin-Right' = $rMargin
            'Margin-Top' = '2%'
        } |
        New-WebPage  -Title $pageName
        
}

$session["ObjectPage$($PageName)"] | Out-HTML -WriteResponse

                }                
                $pipeworksManifest.Pages["$pagename.pspage"] = "<|
$webObjectPage
|>"                                        
            }
        }
        
        
        #endregion Object Pages
        
        
        #region Embed RSS Icon
        [IO.File]::WriteAllBytes("$outputDirectory\rss.png", 
            [Convert]::FromBase64String("                    
            iVBORw0KGgoAAAANSUhEUgAAAA4AAAAOCAYAAAAfSC3RAAAABGdBTUEAAK/
            INwWK6QAAABl0RVh0U29mdHdhcmUAQWRvYmUgSW1hZ2VSZWFkeXHJZTwAAA
            JDSURBVHjajJJNSBRhGMd/887MzrQxRSLbFuYhoUhEKsMo8paHUKFLdBDrU
            Idunvq4RdClOq8Hb0FBSAVCUhFR1CGD/MrIJYqs1kLUXd382N356plZFOrU
            O/MMz/vO83+e93n+f+1zF+kQBoOQNLBJg0CTj7z/rvWjGbEOIwKp9O7Wkht
            Qc/wMWrlIkP8Kc1lMS8eyFHpkpo5SgWCCVO7Z5JARhuz1Qg29fh87u6/9VW
            L1/SPc4Qy6n8c0FehiXin6dcCQaylDMhqGz8ydS2hKkmxNkWxowWnuBLHK6
            G2C8X6UJkBlxUmNqLYyNbzF74QLDrgFgh9LLE0NsPKxjW1Hz2EdPIubsOFd
            H2HgbwAlC4S19dT13o+3pS+vcSfvUcq9YnbwA6muW9hNpym/FWBxfh0CZkK
            GkPBZeJFhcWQAu6EN52QGZ/8prEKW+cdXq0039UiLXhUYzdjebOJQQI30UX
            p6mZn+Dtam32Afu0iyrgUvN0r+ZQbr8HncSpUVJfwRhBWC0hyGV8CxXBL5S
            WYf9sYBidYLIG2V87/ifVjTWAX6AlxeK2C0X8e58hOr/Qa2XJ3iLMWxB1h7
            2tHs7bgryzHAN2o2gJorTrLxRHVazd0o4TXiyV2Yjs90uzauGvvppmqcLjw
            mbZ3V7BO2HOrBnbgrQRqWUgTZ5+Snx4WeKfzCCrmb3axODKNH+vvUyWjqyK
            4DiKQ0eXSpFsgVvLJQWpH+xSpr4otg/HI0TR/t97cxTUS+QxIMRTLi/9ZYJ
            PI/AgwAoc3W7ZrqR2IAAAAASUVORK5CYII="))
        #endregion Embed RSS Icon

        #region HTML Based Blog
        
        # The value of the post field can either be a hashtable containing these items, or a relative path to a .post.psd1 containing 
        # these items.
        $hasPosts = $false
        if ($PipeworksManifest.Posts -and 
            $PipeworksManifest.Posts.GetType() -eq [Hashtable] ) {
            if (-not $hasPosts) {                
                
            }
            $hasPosts = $true
            
            $getPostFileNames = {
                param($post)
                
                $replacedPostTitle = $post.Title.Replace("|", " ").Replace("/", "-").Replace("\","-").Replace(":","-").Replace("!", "-").Replace(";", "-").Replace(" ", "_").Replace("@","at").Replace(",", " ")
                New-Object PSObject -Property @{
                    safeFileName = $replacedPostTitle + ".simple.html"
                    postFileName = $replacedPostTitle  + ".post.html"
                    postDirectory = $replacedPostTitle 
                    postRssFileName = $replacedPostTitle  + ".xml"
                    datePublishedFileName = try { ([DateTime]($post.DatePublished)).ToString("u").Replace(" ", "_").Replace(":", "-") + ".simple.html"} catch {}
                }
            }
                                                
            
            # Get the command now so we can remove anything else from the pagecontent hashtable later
            $rssItem = Get-Command New-RssItem | Select-Object -First 1 
            $moduleRssName = $moduleBlogTitle.Replace("|", " ").Replace("/", "-").Replace("\","-").Replace(":","-").Replace("!", "-").Replace(";", "-").Replace(" ", "_").Replace("@","at").Replace(",", "_")
            $allPosts = 
                foreach ($postAndContent in $PipeworksManifest.Posts.GetEnumerator()) {
                    
                    $pageName = $postAndContent.Key 
                    $pageContent = $postAndContent.Value
                        
                    $safePageName = $pageName.Replace("|", " ").Replace("/", "-").Replace("\","-").Replace(":","-").Replace("!", "-").Replace(";", "-").Replace(" ", "_").Replace("@","at").Replace(",", "_")
                    if ($pageContent -like ".\*") {
                        # Relative Path, try loading a post file                            
                        $pagePath = Join-Path $moduleRoot $pageContent.Substring(2)
                        if ($pagePath -notlike "*.htm*" -and (Test-Path $pagePath)) {
                            try {
                                $potentialPagecontent = [IO.File]::ReadAllText($pagePath)
                                $potentialPagecontentAsScriptBlock = [ScriptBlock]::Create($potentialPageContent)
                                $potentialPagecontentAsDataScriptBlock = [ScriptBlock]::Create("data { $potentialPagecontentAsScriptBlock }")
                                $pageContent = & $potentialPagecontentAsDataScriptBlock 
                            } catch {
                                $_ | Write-Error
                            }
                        } elseif (Test-Path $pagePath) {
                            # Page is HTML.
                            $pageContent = [IO.File]::ReadAllText($pagePath)
                            
                            # Try quickly to get the microdata from the HTML.
                            $foundMicroData = 
                                Get-Web -Html $pageContent -ItemType http://schema.org/BlogPosting -ErrorAction SilentlyContinue | 
                                Select-Object -First 1 
                            
                            if ($foundMicrodata) {
                                $pageContent = @{
                                    Title = $foundMicrodata.Name
                                    Description = $foundMicrodata.ArticleText
                                    DatePublished = $foundMicrodata.DatePublished
                                    Category = $foundMicrodata.Keyword
                                    Author = $foundMicrodata.author
                                    Link = $foundMicrodata.url
                                }
                            }
                            
                        }
                    } 
                            
                    $feedContent =                         
                        if ($pageContent -is [Hashtable]) {   
                            if (-not $pageContent.Description -and -not $pageContent.html) {                        
                                continue
                            }
                            
                            if ($pageContent.Html) {
                                $pageContent.Description = $pageContent.html
                            }                                                                 
                            
                            if (-not $pageContent.Title) {
                                $pageContent.Title = $pageName
                            }                                                                                    
                            
                            foreach ($key in @($pageContent.Keys)) {
                                if ($rssItem.Parameters.Keys -notcontains $key) {
                                    $pageContent.Remove($key)
                                }
                            }
                            
                            $fileNames = & $getPostFileNames $pageContent
                            $pageContent.Link = $filenames.postFileName
                            New-RssItem @pageContent 
                        } else {
                            Write-Debug "$safePageName could not be processed"
                            continue
                        }                                               
                                    
                    $safePageName = $fileNames.postFileName
                    $xmlDescription = $pageContent.Description 
                    
                    if (-not $pageContent.Description) { continue }
                    
                    $feedContent | 
                        Out-RssFeed -Title $pageName -Description $xmlDescription -Link "${safePageName}.Post.xml"| 
                        Set-Content "$outputDirectory\${safePageName}.Post.xml"                                        

                    $pageWidgetContent = $ExecutionContext.SessionState.InvokeCommand.ExpandString($blogPostTemplate)
                    $feedHtml = New-RssItem @pageContent -AsHtml
                    # Create an article page
                    New-WebPage -UseJQueryUI -Title $pageContent.Title -PageBody (
                        New-Region -Container 'Headerbar' -Border '0px' -Style @{
                            "margin-top"="1%"
                            'margin-left' = $MarginPercentLeftString
                            'margin-right' = $MarginPercentRightString
                        } -Content "        
    <h1 class='blogTitle'><a href='$moduleBlogLink'>$moduleBlogTitle</a></h1>
    <h4 class='blogDescription'>$moduleBlogDescription</h4>"), (
                        New-Region -Style @{
                            'margin-left' = $MarginPercentLeftString
                            'margin-right' = $MarginPercentRightString
                            'margin-top' = '10px'   
                            'border' = '0px' 
                        } -AsWidget -ItemType http://schema.org/BlogPosting -Content $feedHtml  
                        ) | 
    Set-Content "$outputDirectory\${safePageName}" -PassThru |
    Set-Content "$outputDirectory\$($safePageName.Replace('.post.html', '.html'))"
                                        
                    # Emit the page content, so the whole feed can be generated
                    $feedContent
                }
            
            
            if ($allPosts) { 
                $moduleRss = $allPosts  |                         
                    Out-RssFeed -Title $moduleBlogTitle -Description $module.Description -Link "\$($module.Name).xml" |
                    Set-Content "$outputDirectory\$moduleRssName.xml" -PassThru |
                    Set-Content "$outputDirectory\Rss.xml" -PassThru
            } else {
                $moduleRss = @()
            }
                
            $categories = $moduleRss | 
                Select-Xml //item/category | 
                Group-Object { $_.Node.'#text'}                
                
            $postsByYear = $moduleRss | 
                Select-Xml //item/pubDate | 
                Group-Object { ([DateTime]$_.Node.'#text').Year }                
                
            $postsByYearAndMonth = $moduleRss | 
                Select-Xml //item/pubDate |                 
                Group-Object { 
                    ([DateTime]$_.Node.'#text').ToString("y")
                }
                
            $allGroups = @($categories) + $postsByYear + $postsByYearAndMonth
             
            foreach ($groupPage in $allGroups) {
                if (-not $groupPage) { continue } 
                $catLink = $groupPage.Name.Replace("|", " ").Replace("/", "-").Replace("\","-").Replace(":","-").Replace("!", "-").Replace(";", "-").Replace(" ", "_").Replace("@","at").Replace(",", "_") + ".posts.html"
                $groupPage.Group |                     
                    ForEach-Object { 
                        $_.Node.SelectSingleNode("..")
                    } | 
                    Sort-Object -Descending { ([datetime]$_.pubdate).'#text' } | 
                    Select-Object title, creator, pubdate, link, category, @{
                        Name='Description';
                        Expression={
                            $_.Description.InnerXml.Substring("<![CDATA[".Length).TrimEnd("]]>")
                        }
                    } | 
                    New-RssItem -AsHTML |
                    New-Region -ItemType http://schema.org/BlogPosting -AsWidget -Style @{
                        'margin-left' = $MarginPercentLeftString
                        'margin-right' = $MarginPercentRightString
                        'margin-top' = '10px'   
                        'border' = '0px' 
                    }|
                    ForEach-Object -Begin {
                        New-Region -Container 'Headerbar' -Border '0px' -Style @{
                            "margin-top"="1%"
                            'margin-left' = $MarginPercentLeftString
                            'margin-right' = $MarginPercentRightString
                        } -Content "        
    <h1 class='blogTitle'><a href='$moduleBlogLink'>$moduleBlogTitle</a></h1>
    <p class='blogDescription'>$moduleBlogDescription</p>
    <h2 class='blogCategoryHeader' style='text-align:right'>$($groupPage.Name)</h2>
    "                        
                    } -Process {
                        $_
                    } | 
                    New-WebPage -Title "$moduleBlogTitle - $($groupPage.Name)" -Rss @{"Start-Scripting"= "$moduleRssName.xml"} |
                    Set-Content "$outputDirectory/$catLink"
                
                                    
            }
        }        
        
        #endregion HTML Based Blog 
        
        
        $embedUnpackItem = "`$unpackItem = {$unpackItem
        }"
        
        # This seems counter-intuitive, and so bears a little explanation.  
        # This makes schematics have a natural priority order according to how they were specified
        # That is, if you have multiple schematics, you want the first item to be the most important 
        # (and it's default page to be the default page).  If it was processed first, this wouldn't happen.
        # If this was sorted, also no.  So, it's flipped.
        
        if ($psboundParameters.useSchematic) {
            $useSchematic = $useSchematic[-1..(0 -$useSchematic.Length)]
        }
        
            
        foreach ($schematic in $useSchematic) {
            $moduleList = (@($realModule) + @($module.RequiredModules) + @(Get-Module Pipeworks))
            $moduleList  =  $moduleList  | Select-Object -Unique
            foreach ($moduleInfo in $moduleList  ) {
                $thisModuleDir = $moduleInfo | Split-Path
                $schematics = "$thisModuleDir\Schematics\$Schematic\" | Get-ChildItem -Filter "Use-*Schematic.ps1" -ErrorAction SilentlyContinue
                foreach ($s in $schematics) {
                    if (-not $s) { continue } 
                    if (-not $pipeworksManifest.$Schematic) {
                        Write-Error "Missing $schematic schematic parameters for $($module.Name)"
                        continue
                    }
                    $pagesToMerge = & {                            
                        . $s.Fullname
                        $schematicCmd = 
                            Get-Command -Verb Use -Noun *Schematic | 
                            Where-Object {$_.Name -ne 'Use-Schematic'} | 
                            Select-Object -First 1 
                        
                        $schematicParameters = @{
                            Parameter = $pipeworksManifest.$schematic
                            Manifest = $PipeworksManifest 
                            DeploymentDirectory = $outputDirectory 
                            inputDirectory = $moduleRoot
                        }
                        if ($schematicCmd.Name) {
                            & $schematicCmd @schematicParameters
                            Remove-Item "function:\$($schematicCmd.Name)"
                        }
                    }
                    
                    if ($pagesToMerge) {
                        foreach ($kv in $pagesToMerge.GetEnumerator()) {
                            $pipeworksManifest.pages[$kv.Key] = $kv.Value
                        }                   
                    }
                }                    
            }                
        }
        
        if ($pipeworksManifest.Table) {
            $RequiresPipeworks = $module.RequiredModules | Where-Object { $_.Name -eq 'Pipeworks'}             
            if (-not $requiresPipeworks -and ($module.Name -ne 'Pipeworks')) { 
                Write-Error "Modules that use the Pipeworks Manifest table features must require Pipeworks in the module manifest.  Please add RequiredModules='Pipeworks' to the module manifest.'"
                return
            }
            
            if ($PipeworksManifest.Table.StorageAccountSetting) {
                $storageAccount = $configSetting[$PipeworksManifest.Table.StorageAccountSetting]                
            }
            
            if ($PipeworksManifest.Table.StorageKeySetting) {
                $storageKey = $configSetting[$PipeworksManifest.Table.StorageKeySetting]                
            }                        
            
            if ($pipeworksManifest.Table.IndexBy) {
                $nolongerindexingForABitSplittingthisOffintoACommandLater = {
                if (-not $pipeworksManifest.Table.SqlAzureConnectionSetting) {
                    Write-Error "Modules that index tables must also declare a SqlAzureConnectionSetting within the table"
                    return
                }
            
                # Indexes the table entries by any number of fields                                
                Write-Progress "Building Index for $($pipeworksManifest.Table.Name)" "Querying for $($pipeworksManifest.Table.IndexBy -join ',')" 
                
                $indexProperties = 
                    Search-AzureTable -TableName $pipeworksManifest.Table.Name -StorageAccount $storageACcount -StorageKey $storageKey -Select ([string[]]($pipeworksManifest.Table.IndexBy + "RowKey", "PartitionKey", "Timestamp")) |
                    ForEach-Object $unpackItem
                
                Write-Progress "Building Index for $($pipeworksManifest.Table.Name)" "Indexing into SQL" 
                                
                $connectionString = $configSetting[$pipeworksManifest.Table.SqlAzureConnectionSetting]
                
                $sqlConnection = New-Object Data.SqlClient.SqlConnection "$connectionString"
                $sqlConnection.Open()
                                                
                #region Check if index exists 
                $tableExists = "Select table_name from information_schema.tables where table_name='$($pipeworksManifest.Table.Name)'"                
                
                $sqlAdapter= New-Object "Data.SqlClient.SqlDataAdapter" ($tableExists, $sqlConnection)
                $sqlAdapter.SelectCommand.CommandTimeout = 0
                $dataSet = New-Object Data.DataSet
                if ($sqlAdapter.Fill($dataSet)) {
                    #endregion Check if index exists 
                    #region Delete the existing index and table
                    $getAllIds = "select Id from $($pipeworksManifest.Table.Name)"
                    $sqlAdapter= New-Object Data.SqlClient.SqlDataAdapter ($getAllIds, $sqlConnection)
                    $sqlAdapter.SelectCommand.CommandTimeout = 0
                    $dataSet = New-Object Data.DataSet 
                    $null = $sqlAdapter.Fill($dataSet)
                    $allIds = @($dataSet.Tables | 
                        Select-Object -ExpandProperty Rows | 
                        Select-Object -ExpandProperty Id)
                    #endregion Delete the existing index and table
                } else {
                    $allIds = @()
                    $indexBySql = ($pipeworksManifest.Table.IndexBy -join ' varchar(max),
') + ' varchar(max)'                
                
                    #region Create the table and an index
                    $createTableAndIndex = @"
CREATE TABLE $($pipeworksManifest.Table.Name) (

Id char(100) NOT NULL Unique CLUSTERED ,
$indexBySql 
)
"@
                    #endregion Create the table and an index
                                                   
                    $sqlAdapter= New-Object Data.SqlClient.SqlDataAdapter ($createTableAndIndex, $sqlConnection)
                    $sqlAdapter.SelectCommand.CommandTimeout = 0
                    $dataSet = New-Object Data.DataSet 
                    $null = $sqlAdapter.Fill($dataSet)
                }
                
                
                
                
                
                $index = @{}
                
                #region Put the items into the index
                    
                $c = 0 
                
                if (-not ($allIds.Count -eq $indexProperties.Count)) {  
                    # drop the table and rebuild it
                    
                                                   
                    
                                              
                    foreach ($item in $indexProperties) 
                    {       
                        $itemId = "$($item.PartitionKey):$($item.RowKey)"
                        $cacheItem = @{Id=$itemId}
                        $idExists = $null
                        $idExists = 
                            foreach ($_ in $allIds) { if ($_ -and $_.StartsWith($itemId)) { $_; break; } }                    
                        $c++
                        
                        if ($idExists) {
                            continue
                        }

                        $perc = $c * 100 / $indexProperties.count                    

                        Write-Progress "Building Index for $($pipeworksManifest.Table.Name)" "$itemId" -PercentComplete $perc

                        $otherValues = foreach ($propertyName in $pipeworksManifest.Table.IndexBy) {
                            "$($item.$propertyName)"  -replace "'", "''"
                        }
                        
                        
                        $sqlInsertStatement = "Insert Into $($pipeworksManifest.Table.Name) (Id, $($pipeworksManifest.Table.IndexBy -join ','))
                        VALUES ('$itemId','$($otherValues -join "','")')
                        "                    
                        $sqlAdapter= New-Object Data.SqlClient.SqlDataAdapter ($sqlInsertStatement, $sqlConnection)
                        $sqlAdapter.SelectCommand.CommandTimeout = 0
                        $dataSet = New-Object Data.DataSet 
                        try {
                            $null = $sqlAdapter.Fill($dataSet)
                        } catch {
                            Write-Debug $_
                        }
                        
                    }
                }
                #endregion Put the items into the index
                
                $sqlConnection.Close()
                <#
                $tables= foreach ($c in $cache) {
                    Write-PowerShellHashtable -inputObject $c
                }
                ('(' + ($tables -join '),(') + ')' )| 
                    Set-Content "$outputDirectory/$($pipeworksManifest.Table.Name).Cache.psd1"
                #>
                
                Write-Progress "Building Index for $($pipeworksManifest.Table.Name)" "Indexing Complete" -Completed
                }
            }
    
            
            
            
            
            
            #endregion Handle Schematics
    
            #region Simple Search Table Page
                                                                                 
    }
        
        if ($hasPosts -and $ModuleRss) {
            # Generate the main page, which is an expanded first item with popouts linking to other items            
            $moduleRss | 
                Select-Xml //item/pubDate | 
                Sort-Object -Descending { ([DateTime]$_.Node.'#text') } | 
                Select-Object -First 1 | 
                ForEach-Object { 
                        $_.Node.SelectSingleNode("..")
                } | 
                Select-Object title, creator, pubdate, link, category, @{
                    Name='Description';
                    Expression={
                        $_.Description.InnerXml.Substring("<![CDATA[".Length).TrimEnd("]]>")
                    }
                } | 
                New-RssItem -AsHTML |
                New-Region -ItemType http://schema.org/BlogPosting -AsWidget -Style @{
                    'margin-left' = $MarginPercentLeftString
                    'margin-right' = $MarginPercentRightString
                    'margin-top' = '10px'   
                    'border' = '0px' 
                }|
                ForEach-Object -Begin {
                    New-Region -Container 'Headerbar' -Border '0px' -Style @{
                        "margin-top"="1%"
                        'margin-left' = $MarginPercentLeftString
                        'margin-right' = $MarginPercentRightString
                    } -Content "        
<h1 class='blogTitle'><a href='$moduleBlogLink'>$moduleBlogTitle</a></h1>
<p class='blogDescription'>$moduleBlogDescription</p>
"                        
                } -Process {
                    $_
                } | 
                New-WebPage -Title "$moduleBlogTitle" -Rss @{"$moduleBlogTitle"= "$moduleRssName.xml"} |
                Set-Content "$outputDirectory/Blog.html"
        }
        
        $usesDynamicPages = $false

        if ($AllowDownload) {
            # Generate the download page now, so the site can be baked and so that we don't waste time rending the page
            if ($downloadUrl) {
                $page = New-WebPage -Title "Download $($module.Name)" -RedirectTo "$downloadUrl" 
                $pipeworksManifest.Pages["Download.html"] = $page 
            } elseif ($allowDownload) {                  

                $modulezip = $module.name + '.' + $module.Version + '.zip'
                $page = (New-object PSObject -Property @{RedirectTo=$modulezip;RedirectIn='0:0:0.50'}),(New-object PSObject -Property @{RedirectTo="./";RedirectIn='0:0:5'}) | New-WebPage 
                $pipeworksManifest.Pages["Download.html"] = $page 
            }
        }

                
        #region Pages
        #If the manifest declares additional web pages, create a page for each item
        if ($PipeworksManifest.Pages -and 
            $PipeworksManifest.Pages.GetType() -eq [Hashtable] ) {
            
            $pageCounter = 0
            foreach ($pageAndContent in $PipeworksManifest.Pages.GetEnumerator()) {
                
                $pageName = $pageAndContent.Key 
                $pageCounter++
                $pagePercent = $pageCounter * 100 / $pipeworksManifest.Pages.Count
                Write-Progress "Creating Pages" "$pageName" -PercentComplete $pagePercent 
                $safePageName = $pageName.Replace("|", " ").Replace("/", "-").Replace(":","-").Replace("!", "-").Replace(";", "-").Replace(" ", "_").Replace("@","at")
                $pageContent = $pageAndContent.Value
                $realPageContent = 
                    if ($pageContent -is [Hashtable]) {                    
                        if (-not $pageContent.Css -and $pipeworksManifest.Style) {
                            $pageContent.Css = $pipeworksManifest.Style
                        }
                        if ($pageContent.PageContent) {
                            $pageContent.PageContent = try { [ScriptBlock]::Create($pageContent.PageContent) } catch {}                                                         
                        }
                        if ($hasPosts) {
                            # If there are posts, add a link to the feed to all pages
                            $pageContent.Rss = @{
                                "$($Module.Name) Blog" = "$($module.Name).xml"
                            }
                        }
                        
                        # Pass down the analytics ID to the page if one is not explicitly set
                        if (-not $pageContent.AnalyticsId -and $analyticsId) {
                            $pageContent.AnalyticsId = $analyticsId
                        }
                        New-WebPage @pageContent
                    } elseif ($pageContent -like ".\*.pspg" -or $pageName -like "*.pspg" -or $pageName -like "*.pspage"){
                        # .PSPages.  These are mixed syntax HTML and Powershell inlined in markup <| |>  
                        # Because they are loaded within the moudule, a PSPAge will contain $embedCommand, which imports the module
                        if ($pageContent -notlike ".\*.pspg" -and $pageContent -notlike ".\*.pspage") {
                            # the content isn't a filepath, so treat it as inline code 
                            $wholePageContent = "<| $embedCommand |>" + $pageContent                           
                            ConvertFrom-InlinePowerShell -PowerShellAndHtml $wholePageContent -RunScriptMethod this.RunScript -CodeFile PowerShellPageBase.cs -Inherit PowerShellPage | 
                                Add-Member NoteProperty IsPsPage $true -PassThru
                        } else {
                            # The content is a path, treat it like one
                            $pagePath = Join-Path $moduleRoot $pageContent.TrimStart(".\")
                            if (Test-Path $pagePath) {
                                $pageContent = [IO.File]::ReadAllText($pagePath)
                                $wholePageContent = "<| $embedCommand |>" + $pageContent 
                                ConvertFrom-InlinePowerShell -PowerShellAndHtml $wholePageContent -CodeFile PowerShellPageBase.cs -Inherit PowerShellPage -RunScriptMethod this.RunScript  | 
                                    Add-Member NoteProperty IsPsPage $true -PassThru
                            }         
                        }
                        $usesDynamicPages= $true
                    } elseif ($pageName -like "*.*" -and $pageContent -as [Byte[]]) {
                        # Path to item
                        $itemPath = Join-Path $outputDirectory $pageName.TrimStart(".\")
                        $parentPath = $itemPath | Split-Path
                        if (-not (Test-Path "$parentPath")) {
                            $null = New-Item -ItemType Directory -Path "$parentPath"
                        }
                        [IO.File]::WriteAllBytes("$itemPath", $pageContent)
                    } elseif ($pageContent -like ".\*.htm*" -or $pagename -like "*.htm?"){
                        # .HTML files
                        $pagePath = Join-Path (Join-Path $moduleRoot "Pages") $pageName.TrimStart(".\")
                        if (Test-Path $pagePath) {
                            try {
                                $pageItem =(Get-Item $pagePath)
                                
                                $potentialPagecontent = [IO.File]::ReadAllText($pageItem.FullName)                                
                                # Include the page header information for each page
                                $relativepath = $pageItem.Fullname -ireplace $moduleRoot.Replace(".", "\.").Replace("\","\\"),"" -ireplace "\\Pages\\", ""
                                $depth = @($relativepath -split "\\").Count - 1
                                $pageHeaderHtml = (& { $null = . New-WebPage -Depth $depth; $pageHeaderHtml })
                                if (-not $allAboutFiles) {
                                    $allAboutFiles = @{}
                                    foreach ($cult in ([Globalization.CultureInfo]::GetCultures([Globalization.CultureTypes]::AllCultures))) {                
                                        $allAboutFiles[$cult.Name] = @(Get-ChildItem -Filter *.help.txt -Path "$moduleRoot\$($cult.Name)" -ErrorAction SilentlyContinue)
                                    }
                                }
                                $headStart = $potentialPagecontent.IndexOf("<head>", [StringComparison]::InvariantCultureIgnoreCase)
                                $potentialPagecontent = $potentialPagecontent.Insert(($headStart + "<head>".Length), $pageHeaderHtml)
                                
                                
                                if ($pageItem.Directory.Name -eq 'Templates' -or $pageItem.Directory.Name -eq 'Template') {
                                    $regions = Get-WebTemplateEditableRegion -FilePath $pageItem.FullName
                                    
                                    
                                    
                                    $moduleParts = 
                                            'docTypeText','Title','pageHeaderHtml','titleArea',
                                            'descriptionArea', 'rssLink','socialArea','navBarHtml',
                                            'confirmationArea','upperBannerSlot', 'topicHtml', 'defaultCommandSection', 
                                            'slideShowHtml', 'rest', 'bottomBannerSlot','orgArea', 'brandingSlot'

                                    $commandParts = $topicParts = 
                                        'docTypeText','Title','pageHeaderHtml','titleArea',
                                        'descriptionArea', 'rssLink','socialArea','navBarHtml',
                                        'confirmationArea','upperBannerSlot', 'rest', 'bottomBannerSlot','orgArea', 'brandingSlot'

                                    
                                    if ($pageItem.Name -like "Module*") {
                                        $difference = 
                                            $regions.Region | Compare-Object $moduleParts
                                    } elseif ($PageItem.Name) {
                                        $difference = 
                                            $regions.Region | Compare-Object $commandParts


                                    }

                                    foreach ($rinf in $regions.MatchInfo)
                                    {
                                            $null =$rinf
                                            $start = $potentialPagecontent.IndexOf($rinf.Value)
                                            $end = 
                                                $potentialPagecontent.IndexOf("<!-- #EndEditable -->", $start, [StringComparison]::InvariantCultureIgnoreCase)

                                            $part = $potentialPagecontent.Substring($start, $end-$start + "<!-- #EndEditable -->".Length)


                                            $potentialPagecontent = $potentialPagecontent.Replace($part, '$' + $rinf.Groups[1])

                                            $pagename = $pagename -iReplace "\.html", ".pswt" -iReplace "\.htm",".pswt"
                                    }
                                    
                                }

                                # 9/16/2013 - Adding support for embedded topics and commands in HTML
                                # If any HTML file contains a variable (i.e. $foo) that matches the name
                                # of an about topic, walkthru, or command, then the item will be embedded in the HTML.
                                # Topics and Walkthrus will be directly embedded
                                # Commands will be embedded with Write-Ajax.
                                # Unmatched items will be unchanged, but will warn the user
                                
                                $variableMatches = New-Object Collections.ArrayList
                                $fn = $pageItem.Fullname
                                $m = [Regex]::Matches($potentialPagecontent, "\`$([\w-]{1,})") |
                                        Add-Member NoteProperty FileName $fn -Force -PassThru
                                
                                        
                                $variablesUsed = 
                                    if ($m) {
                                        foreach ($ma in $m) {
                                            if (-not ($ma.Value -as [double])) {
                                                $ma.Value
                                                $null = $variableMatches.Add($ma)
                                            }
                
                                        }
            
                                    }        
                                    
                                $variablesUsed = $variablesUsed | 
                                    Select-Object -Unique | 
                                    Sort-Object -Descending



                                $foundVariables = @()

                                $topicsToReplace = 
                                    $allAboutFiles.Values |    
                                        where-object {
                                            $_
                                        } |
                                        Where-Object {
                                            $variablesUsed -like "?$($_.Name -ireplace '\.walkthru\.help\.txt', '' -ireplace '\.help\.txt', '')"
                                        } |
                                        ForEach-Object {
        
                                            foreach ($f in $_) {
                                            $used = $($variablesUsed -like "?$($_.Name -ireplace '\.walkthru\.help\.txt', '' -ireplace '\.help\.txt', '')")
                                                New-Object PSObject -Property @{
                                                    TopicFile = $f
                                                    UsedInFile = $variableMatches | Where-Object { $used -contains $_.Value   }  | Select-Object -ExpandProperty Filename 
                                                    Variable = $used
                                                    Matches = $variableMatches | Where-Object { $used -contains $_.Value   } 
                                                }
                                            }

                                            $foundVariables += $used
                                        }


                                $moduleCommands = Get-Command -Module $Name -CommandType Alias, Function, Cmdlet

                                $commandsUsed = foreach ($m in $moduleCommands) {
                                    $m | Where-Object {
                                        $variablesUsed -like "?$($_.Name -ireplace '\.walkthru\.help\.txt', '' -ireplace '\.help\.txt', '')"
                                    } | ForEach-Object {
                                        $used = $($variablesUsed -like "?$($_.Name -ireplace '\.walkthru\.help\.txt', '' -ireplace '\.help\.txt', '')")
                                        New-Object PSObject -Property @{
                                            Command = $m
                                            UsedInFile = $variableMatches | Where-Object { $used -contains $_.Value   }  | Select-Object -ExpandProperty Filename 
                                            Variable = $used
                                            Matches = $variableMatches | Where-Object { $used -contains $_.Value   } 
                                        }
                                        $foundVariables+=$used
                                    }
                                }


                                foreach ($cmd in $commandsUsed) {
                                    foreach ($matchInf in $cmd.Matches) {

                                        $relativepath = $matchInf.Filename -ireplace $moduleRoot.Replace(".", "\.").Replace("\","\\"),"" -ireplace "\\Pages\\", ""
                                        $resolvedCommand = if ($cmd.Command.ResolvedCommand) {
                                            $cmd.Command.ResolvedCommand
                                        } else {
                                            $cmd.Command
                                        }
                                        $depth = @($relativepath -split "\\").Count - 1
                                        $cmdLink = "$("../" * $depth)$($resolvedCommand)/?snug=true&ajax=true"
                                        $fc = [IO.File]::ReadAllText($matchInf.FileName)
        
                                        $cmdIFrame = "$($resolvedCommand.Name.Replace('-',''))frame"
                                        $cmdHtml = "<iframe style='width:100%;border:0' src='$cmdLink' id='$cmdIFrame' seamless=''></iframe>"
                                        $cmdHtml = 
                                "
                                <div style='height:100%'>
                                
                                <div id='$($resolvedCommand.Name.Replace("-", ''))'>
                                </div>
                                $cmdHtml                                
                                </div>
                                <script>
                                    var buffer = 20; //scroll bar buffer
                                    var iframe = document.getElementById('$cmdIFrame');

                                    function pageY(elem) {
                                        return elem.offsetParent ? (elem.offsetTop + pageY(elem.offsetParent)) : elem.offsetTop;
                                    }

                                    function resize$cmdIFrame() {
                                        var height = document.documentElement.clientHeight;
                                        height -= pageY(document.getElementById('$cmdIFrame'))+ buffer ;
                                        height = (height < 0) ? 0 : height;
                                        document.getElementById('$cmdIFrame').style.height = height + 'px';
                                    }

                                    // .onload doesn't work with IE8 and older.
                                    if (iframe.attachEvent) {
                                        iframe.attachEvent('onload', resize$cmdIFrame);
                                    } else {
                                        iframe.onload=resize$cmdIFrame;
                                    }

                                    if (window.addEventListener) {
                                        window.addEventListener('onresize', function() {
                                            resize$cmdIFrame();
                                        });
                
                                        window.addEventListener('onorientationchange', function() {
                                            resize$cmdIFrame();
                                        });   
                                    } else {
                                        if (window.attachEvent) {
                                            window.attachEvent('onresize', function(e) {                        
                                                resize$cmdIFrame();
                                            });
                                        }
                                    }
                                </script>
                                "
        
                                        $potentialPagecontent = [Regex]::Replace($potentialPagecontent, $matchInf.Value.Replace('$', '\$'), $cmdHtml)                                        
                                    }
                                }
                                $ShowDataInTopic = if ($pipeworksManifest.HideDataInTopic) {
                                    $false
                                } else {
                                    $true
                                }
                                foreach ($topic in $topicsToReplace) {
                                    $topicHtml = 
                                        if ($topic.TopicFile -like "*.walkthru*") {
                                            Write-WalkthruHTML -WalkThru (Get-Walkthru -File $topic.TopicFile)
                                        } else {
                                            $topicHelp = [IO.File]::ReadAllText($TOPIC.TopicFile.FullName)
                                            ConvertFrom-Markdown -Markdown $topicHelp -ShowData:$ShowDataInTopic
                                        }

                                    $matchInf = $topic.Matches
                                    foreach ($matchInf in $topic.Matches) {
                                        
                                        $potentialPagecontent = [Regex]::Replace($potentialPagecontent, $matchInf.Value.Replace('$', '\$'), $topicHtml)
                                        
                                    }
                                }

                                $missingvariables = $variablesUsed | Where-Object { $foundVariables -notcontains $_ } 
                                foreach ($missing in $missingvariables) {
                                    Write-Warning "$($pagePath) references $missing, but there is no topic, walkthru, or command named $missing"
                                }
                                
                                $pageContent = $potentialPagecontent 
                            } catch {
                                $_ | Write-Error
                            }
                        }
                    } elseif ($pageName -like ".\*.md" -or $pagename -like "*.md") {
                        $pagePath = Join-Path (Join-Path $moduleRoot "Pages")  $pageName.TrimStart(".\")
                        if (Test-Path $pagePath) {
                            try {
                                $ShowDataInTopic = if ($pipeworksManifest.HideDataInTopic) {
                                    $false
                                } else {
                                    $true
                                }
                                $potentialPagecontent = [IO.File]::ReadAllText((Get-Item $pagePath).Fullname)                                
                                $wholePageContent =  "
<| 
$embedCommand
ConvertFrom-Markdown -ShowData:`$$showDataInTopic -Markdown @`"
$potentialPagecontent
`"@ |
    New-Webpage

|>
"
                                ConvertFrom-InlinePowerShell -PowerShellAndHtml $wholePageContent -CodeFile PowerShellPageBase.cs -Inherit PowerShellPage -RunScriptMethod this.RunScript  | 
                                    Add-Member NoteProperty IsPsPage $true -PassThru

                                
                            } catch {
                                $_ | Write-Error
                            }
                        }
                    } elseif ($pageName -like ".\*.psmd" -or $pagename -like "*.psmd") {
                        $pagePath = Join-Path (Join-Path $moduleRoot "Pages") $pageName.TrimStart(".\")
                        if (Test-Path $pagePath) {
                            try {
                                $ShowDataInTopic = if ($pipeworksManifest.HideDataInTopic) {
                                    $false
                                } else {
                                    $true
                                }
                                $potentialPagecontent = [IO.File]::ReadAllText((Get-Item $pagePath).Fullname)                                
                                $wholePageContent =  "
<| 
$embedCommand
ConvertFrom-Markdown -Splat -ScriptAsPowershell -ShowData:`$showDataInTopic -Markdown @`"
$potentialPagecontent
`"@ |
    New-Webpage
|>
"


                            ConvertFrom-InlinePowerShell -PowerShellAndHtml $wholePageContent -CodeFile PowerShellPageBase.cs -Inherit PowerShellPage -RunScriptMethod this.RunScript  | 
                                Add-Member NoteProperty IsPsPage $true -PassThru
                            } catch {
                                $_ | Write-Error
                            }
                            $usesDynamicPages = $true
                        }

                    } else {
                        $pageContentAsScriptBlock = try { [ScriptBlock]::Create($pageContent) } catch { } 
                        if ($pageContentAsScriptBlock) {
                            & $pageContentAsScriptBlock
                        } else {
                            $pageContent
                        }
                    }
                
              
                
                if ($realPageContent.IsPsPage) {
                    $safePageName = $safePageName.Replace(".pspage", "").Replace(".pspg", "").Replace(".md", "").Replace(".psmd", "")
                    $parentPath = $safePageName | Split-Path
                    if (-not (Test-Path "$outputDirectory\$parentPath")) {
                        $null = New-Item -ItemType Directory -Path "$outputDirectory\$parentPath"
                    }
                    $realPageContent | 
                        Set-Content "$outputDirectory\${safepageName}.aspx"
                    $usesDynamicPages = $true
                } else {
                    # Output the bytes
                    $parentPath = $safePageName | Split-Path
                    if (-not (Test-Path "$outputDirectory\$parentPath")) {
                        $null = New-Item -ItemType Directory -Path "$outputDirectory\$parentPath"
                    }
                    if ($pageContent -as [Byte[]]) {
                        [IO.File]::WriteAllBytes("$outputDirectory\$($pageName)", $pageContent)
                    } else {
                        [IO.File]::WriteAllText("$outputDirectory\$($pageName)", $pageContent)
                    }
                    <#                    
                    $safePageName = $safePageName.Replace(".html", "").Replace(".htm", "")
                    $parentPath = $safePageName | Split-Path
                    if (-not (Test-Path "$outputDirectory\$parentPath")) {
                        $null = New-Item -ItemType Directory -Path "$outputDirectory\$parentPath"
                    }
                    $realPageContent | 
                        Set-Content "$outputDirectory\${safepageName}.html"
                    #>
                }
            }            
        }
        #endregion Pages
        
        
               
        #region Command Handlers
        $webCmds = @()
        $downloadableCmds = @()
        $cmdOutputDirs = @()
        foreach ($command in $module.ExportedCommands.Values) {
            # Generate individual handlers
            $extraParams = if ($pipeworksManifest -and $pipeworksManifest.WebCommand.($Command.Name)) {                
                @{} + $pipeworksManifest.WebCommand.($Command.Name)
            } else { 
                @{
                    ShowHelp = $true
                } 
            }             
            
            if ($pipeworksManifest -and $pipeworksManifest.Style -and (-not $extraParams.Style)) {
                $extraParams.Style = $pipeworksManifest.Style 
            }
            if ($extraParams.Count -gt 1) {
                # Very explicitly make sure it's there, and not explicitly false
                if (-not $extra.RunOnline -or 
                    $extraParams.Contains("RunOnline") -and $extaParams.RunOnline -ne $false) {
                    $extraParams.RunOnline = $true                     
                }                
            } 
            
            if ($extaParams.PipeInto) {
                $extaParams.RunInSandbox = $true
            }
            
            if (-not $extraParams.AllowDownload) {
                $extraParams.AllowDownload = $allowDownload
            }
            
            if ($extraParams.RunOnline) {
                # Commands that can be run online
                $webCmds += $command.Name
            }
            
            if ($extraParams.RequireAppKey -or $extraParams.RequireLogin -or $extraParams.IfLoggedAs -or $extraParams.ValidUserPartition) {
                $extraParams.UserTable = $pipeworksManifest.Usertable.Name
                $extraParams.UserPartition = $pipeworksManifest.Usertable.Partition
                $extraParams.StorageAccountSetting = $pipeworksManifest.Usertable.StorageAccountSetting
                $extraParams.StorageKeySetting = $pipeworksManifest.Usertable.StorageKeySetting 
            }
            
            if ($extraParams.AllowDownload) {
                # Downloadable Commands
                $downloadableCommands += $command.Name                
            }
                        
            
            
            if ($psBoundParameters.OutputDirectory) {
                $extraParams.OutputDirectory = Join-Path $psBoundParameters.OutputDirectory $command.Name
                $cmdOutputDirs += "$(Join-Path $psBoundParameters.OutputDirectory $command.Name)"                
            } else {
                $extraParams.OutputDirectory = Join-Path $OutputDirectory $command.Name
            }
            
            if ($MarginPercentLeftString -and (-not $extraParams.MarginPercentLeft)) {
                $extraParams.MarginPercentLeft = $MarginPercentLeftString.TrimEnd("%")
            }
            
            if ($MarginPercentRightString-and -not $extraParams.MarginPercentRight) {
                $extraParams.MarginPercentRight = $MarginPercentRightString.TrimEnd("%")
            }
            
            if ($IsolateRunspace) {
                $extraParams.IsolateRunspace = $IsolateRunspace
            }
            
            if ($psBoundParameters.StartOnCommand) {
                # only create a full command service when the Module service starts on a command
                #ConvertTo-CommandService -Command $command @extraParams -AnalyticsId "$AnalyticsId" -AdSlot "$AdSlot" -AdSenseID "$AdSenseId"
            }
                        
            $cmdOutputDir = $extraParams.OutputDirectory.ToString()
            
        }
                                                             
        #endregion Command Handlers
        
        foreach ($cmdOutputDir in $cmdOutputDirs) {
            
        }

        if (-not $CommandOrder) {
            if ($pipeworksManifest.CommandOrder) {
                $CommandOrder = $pipeworksManifest.CommandOrder
            } else {
                $CommandOrder = $module.ExportedCommmands.Keys | Sort-Object
            }
        }
        



        $useLoginHandlers = 
            foreach ($wc in $pipeworksManifest.WebCommand.Values) {
                if ($wc.RequireLogin -or 
                    $wc.RequiresLogin -or 
                    $wc.IfLoggedInAS -or 
                    $wc.ValidUserTable -or 
                    $wc.RequireAppKey -or 
                    $wc.RequiresAppKey) {
                    $true
                    break
                }
            }


        
        


        # This script is embedded in the module handler
            $getModuleMetaData = {



# 
$moduleRoot = [IO.Path]::GetDirectoryName($module.Path)
$psd1Path = $moduleRoot + '\' + $module.Name + '.psd1'

<#


$versionHistoryPath = $moduleRoot + '\' + $module.Name + '.versionHistory.txt'
$versionHistoryExists = [IO.File]::Exists($versionHistoryPath)
$versionHistoryDetails = if ($versionHistoryExists) {
    [IO.File]::ReadAllText($versionHistoryPath)
} else {$null } 
#>        

# $currentPageCulture = 


# 
if (-not $allAboutFiles) {
    $allAboutFiles = @{}
    foreach ($cult in ([Globalization.CultureInfo]::GetCultures([Globalization.CultureTypes]::AllCultures))) {        
        
        $allAboutFiles[$cult.Name] = @(Get-ChildItem -Filter *.help.txt -Path "$moduleRoot\$($cult.Name)" -ErrorAction SilentlyContinue)
    }
}

$requestCulture = 
    if ($request -and $request["HTTP_ACCEPT_LANGUAGE"]) {
        $request["HTTP_ACCEPT_LANGUAGE"]
    } else {
        "en-us"
    }

if (-not $cachedAboutTopics) {
    $cachedAboutTopics = @{}
}

# en-us and the current request culture get are used to create a list of help topics
$aboutFiles  =  @($AllaboutFiles["en-us"])

if ($requestCulture -and ($requestCulture -ine 'en-us')) {
    $aboutFiles  +=  @($AllaboutFiles["$requestCulture"])
}




$walkThrus = @{}
$aboutTopics = @()

$aboutTopicsByName = @{}

$HiddenTopicsByName = @{}

$hiddenTopic = if ($pipeworksManifest.HiddenTopic) {
    @($pipeworksManifest.HiddenTopic)
} elseif ($pipeworksManifest.HiddenTopics) {
    @($pipeworksManifest.HiddenTopics)
}


$memberTopic = if ($pipeworksManifest.MemberTopic) {
    @($pipeworksManifest.MemberTopic)
} elseif ($pipeworksManifest.MemberTopics) {
    @($pipeworksManifest.MemberTopics)
}



$namedTopics = @{}
if (-not $customAnyHandler) {
    $customAnyHandler = [IO.File]::Exists("$searchDirectory\AnyUrl.aspx")
}

$spacingDiv = "<div style='clear:both;margin-top:1.5%;margin-bottom:1.5%'></div>"

if ($aboutFiles) {
    foreach ($topic in $aboutFiles) {       
        if (-not $topic) { continue }                  
        if (-not $topic.Name) { continue }                  
        if ($topic.fullname -ilike "*.walkthru.help.txt") {
            $topicName = $topic.Name.Replace('_',' ') -iReplace '\.walkthru\.help\.txt',''
            $walkthruContent = Get-Walkthru -File $topic.Fullname            
            $walkThruName = $topicName             
            $walkThrus[$walkThruName] = $walkthruContent                                     
        } else {
            $topicName = $topic.Name.Replace(".help.txt","")
            $nat = New-Object PSObject -Property @{
                    Name = $topicName.Replace("_", " ")
                    SystemName = $topicName
                    Topic = [IO.File]::ReadAllText($topic.Fullname)
                    LastWriteTime = $topic.LastWriteTime
                } 
            $aboutTopics += $nat
                 
            $aboutTopicsByName[$nat.Name] = $nat
        }


    }
}
}

        $moduleFeedHandler = {
            if ($application -and $application["$($module.Name)_Feed"]) {
                $response.ContentType = "text/xml"                
                $response.Write("$($application["$($module.Name)_Feed"])")        
                return
            }
            
            $feedItems = @()

            if ($aboutTopics) {
                $feedItems += 
                    $aboutTopics |
                        Select-Object @{
                            Name = 'Author'
                            Expression = {
                                if ($module.Author) {
                                    $module.Author
                                } else {
                                    " "
                                }           
                            }
                        }, @{
                            Name = 'Title'
                            Expression = { $_.Name } 
                        }, @{
                            Name = 'Description'
                            Expression = {
                                $ShowDataInTopic = if ($pipeworksManifest.HideDataInTopic) {
                                    $false
                                } else {
                                    $true
                                }
                                ConvertFrom-Markdown -Markdown "$($_.Topic) " -ScriptAsPowerShell -ShowData:$ShowDataInTopic
                            }
                        }, @{
                            Name = 'DatePublished'
                            Expression = {
                                $_.LastWriteTime
                            }
                        }, @{
                            Name = 'Link'
                            Expression = {
                                if ($customAnyHandler) {                    
                                    "?About=" + $_.Name                    
                                } else {                    
                                    $_.Name + "/"                    
                                }
                            }
                        } | Where-Object {
                            $_.Title -ne "About $Module"
                        }

            }

            if ($walkThrus) {
                $feedItems += 
                    $walkThrus.Keys |
                        Select-Object @{
                            Name = 'Author'
                            Expression = {
                                if ($module.Author) {
                                    $module.Author
                                } else {
                                    " "
                                }           
                            }
                        }, @{
                            Name = 'Title'
                            Expression = { $_ } 
                        }, @{
                            Name = 'Description'
                            Expression = {
                                Write-WalkthruHTML -WalkThru ($walkThrus[$_]) 
                            }
                        }, @{
                            Name = 'DatePublished'
                            Expression = {
                                $walkThrus[$_] | Select-Object -ExpandProperty LastWriteTime -Unique
                            }
                        }, @{
                            Name = 'Link'
                            Expression = {
                                if ($customAnyHandler) {                    
                                    "?Walkthru=" + $_
                                } else {                    
                                    $_ + "/"                    
                                }
                            }
                        }

            }
            


            $feedName = if ($pipeworksManifest.Blog.Name) {
                $pipeworksManifest.Blog.Name
            } else {
                $module.Name
            }


            $feedDescription = if ($pipeworksManifest.Blog.Description) {
                $pipeworksManifest.Blog.Description
            } else {
                $module.Description
            }

            $postFilters = @($pipeworksManifest.Blog.Posts) + @($pipeworksManifest.Blog.Post)

            if ($postFilters) {
                $feedItems = 
                    @(foreach ($fi in $feedItems) {
                        $ItemIsOk = $false
                        foreach ($po in $postFilters) {
                            if ($fi.Name -like $po) {
                                $ItemIsOk = $true
                                break
                            }
                        }

                        if ($ItemIsOk) {
                            $fi  
                        }
                    })
            }

            $feed = $feedItems | 
                Sort-Object { $_.DatePublished -as [DateTime] } -Descending |
                New-RssItem -Description { "$($_.Description) " }|
                Out-RssFeed -Title "$feedname " -Description "$feedDescription " -Link "/"
             

            $response.ContentType = "text/xml"
            $strWrite = New-Object IO.StringWriter
            ([xml]($feed)).Save($strWrite)
            $resultToOutput  = "$strWrite" -replace "encoding=`"utf-16`"", "encoding=`"utf-8`""
            $application["$($module.Name)_Feed"] = "$resultToOutput"
            $response.Write("$resultToOutput")        

        }

        $topicRssHandler = {
        

    if ($aboutTopics) {
        $feed = $aboutTopics | 
            New-RssItem -Author {
                if ($module.Author) {
                    $module.Author
                } else {
                    " "
                }
            } -Title {$_.Name } -Description { 
                $ShowDataInTopic = if ($pipeworksManifest.HideDataInTopic) {
                    $false
                } else {
                    $true
                }
                ConvertFrom-Markdown -Markdown $_.Topic -ScriptAsPowerShell -ShowData:$ShowDataInTopic
            } -DatePublished { $_.LastWriteTime } -Link {
                if ($customAnyHandler) {                    
                    "?About=" + $_.Name                    
                } else {                    
                    $_.Name + "/"                    
                }
            } |
            Out-RssFeed -Title "$($module.Name) | Topics" -Description "$($module.Description) " -Link "/"

        $response.ContentType = "text/xml"
        $strWrite = New-Object IO.StringWriter
        ([xml]($feed)).Save($strWrite)
        $resultToOutput  = "$strWrite" -replace "encoding=`"utf-16`"", "encoding=`"utf-8`""
        $response.Write("$resultToOutput")        
    } 

}

        $walkThruRssHandler = {


        $feed = $walkThrus.Keys |
            Sort-Object {
                $walkthrus[$_] | Select-Object -ExpandProperty LastWriteTime -Unique
            } |
            New-RssItem -Title { 
                $_
            } -Author {
                if ($module.Author) {
                    $module.Author
                } else {
                    " "
                }
            } -Description {
                Write-WalkthruHTML -WalkThru ($walkThrus[$_]) 
            } -DatePublished {
                $walkThrus[$_] | Select-Object -ExpandProperty LastWriteTime -Unique
            } -Link {
                if ($customAnyHandler) {                    
                    "?Walkthru=" + $_
                } else {                    
                    $_ + "/"                    
                }
            } |
            Out-RssFeed -Title "$($module.Name) | Topics" -Description "$($module.Description) " -Link "/"

        if ($feed) {
            $response.ContentType = "text/xml"
            $strWrite = New-Object IO.StringWriter
            ([xml]($feed)).Save($strWrite)
            $resultToOutput  = "$strWrite" -replace "encoding=`"utf-16`"", "encoding=`"utf-8`""
            $response.Write("$resultToOutput")        
        }

}
        

        #region About Topic Handler
        $aboutHandler = {

$theTopic = $aboutTopics | 
    Where-Object { 
    $_.SystemName -eq $request['about'].Trim() -or 
    $_.Name -eq $request['About'].Trim()
}

$topicMatch = if ($theTopic) {
    $ShowDataInTopic = if ($pipeworksManifest.HideDataInTopic) {
        $false
    } else {
        $true
    }
    ConvertFrom-Markdown -Markdown $theTopic.Topic -ScriptAsPowerShell -ShowData:$ShowDataInTopic
} else {
    '<span style=''color:red''>Topic not found</span>'
}
    
    
    $page =(New-Region -LayerID "About$($module.Name)Header" -AsWidget -Style @{
            'margin-left' = $MarginPercentLeftString
            'margin-right' = $MarginPercentRightString
        } -Content "
            <h1 itemprop='name' class='ui-widget-header'><a href='.'>$($module.Name)</a> | $($Request['about'].Replace('_', ' '))</h1>            
        "),(New-Region -Container "About$($module.Name)" -Style @{
            'margin-left' = $MarginPercentLeftString
            'margin-right' = $MarginPercentRightString
        } -AsAccordian -HorizontalRuleUnderTitle -DefaultToFirst -Layer @{
            $request['about'].Replace("_", " ") = "
            <div itemprop='ArticleText'>
            $topicMatch
            </div>
            "   
        }) |
        New-WebPage -UseJQueryUI -Css $cssStyle -Title "$($module.Name) | About $($Request['about'])" -AnalyticsID "$analyticsId"
    $response.contentType = 'text/html'
    $response.Write("$page")
        }
        #endregion About Topic Handler

        #region Show Groups
        
        #endregion Show Groups
                        
        #region Walkthru (Demo) Handler
        $walkThruHandler = {
$pipeworksManifestPath = Join-Path (Split-Path $module.Path) "$($module.Name).Pipeworks.psd1"
$pipeworksManifest = if (Test-Path $pipeworksManifestPath) {
    try {                     
        & ([ScriptBlock]::Create(
            "data -SupportedCommand Add-Member, New-WebPage, New-Region, Write-CSS, Write-Ajax, Out-Html, Write-Link { $(
                [ScriptBlock]::Create([IO.File]::ReadAllText($pipeworksManifestPath))                    
            )}"))            
    } catch {
        Write-Error "Could not read pipeworks manifest: ($_ | Out-String)" 
    }                                                
} else { $null } 
    
    
$topicMatch = 
    if ($walkthrus.($request['walkthru'].Trim())) {
        # Use splatting to tack on any extra parameters
        $params = @{
            Walkthru = $walkthrus.($request['walkthru'].Trim())
            WalkThruName = $request['walkthru'].Trim()
            StepByStep = $true
        }    

        if ($pipeworksManifest.TrustedWalkthrus -contains $request['Walkthru'].Trim()) {
            $params['RunDemo'] = $true
        }
        if ($pipeworksManifest.WebWalkthrus -contains $request['Walkthru'].Trim()) {
            $params['OutputAsHtml'] = $true
        }
        Write-WalkthruHTML @params
    } else {
        '<span style=''color:red''>Topic not found</span>'
    }
        $page = (New-Region -LayerID "About$($module.Name)Header" -AsWidget -Style @{
            'margin-left' = $MarginPercentLeftString
            'margin-right' = $MarginPercentRightString
        } -Content "
            <h1 itemprop='name' class='ui-widget-header'><a href='.'>$($module.Name)</a> | $($Request['walkthru'].Replace('_', ' '))</h1>            
        "), 
        (New-Region -LayerId WalkthruContainer -Style @{
            'margin-left' = $MarginPercentLeftString
            'margin-right' = $MarginPercentRightString
        } -Content $topicMatch ) |
        New-WebPage -UseJQueryUI -Css $cssStyle -Title "$($module.Name) | Walkthrus | $($Request['walkthru'].Replace('_', ' '))" -AnalyticsID '$analyticsId' 
$response.contentType = 'text/html'
$response.Write("$page")

        }
        #endregion Walkthru (Demo) Handler   
        
        #region Help Handler
        $helpHandler = {
            $RequestedCommand = $Request["GetHelp"]               
            
            $webCmds = @()
            $downloadableCmds = @()
            $cmdOutputDirs = @()
            
            $command = $module.ExportedCommands[$RequestedCommand]
            
            if (-not $command)  {
                throw "$requestedCommand not found in module $module"
            }
         
            $extraParams = if ($pipeworksManifest -and $pipeworksManifest.WebCommand.($Command.Name)) {                
                @{} + $pipeworksManifest.WebCommand.($Command.Name)
            } else { @{} }                
            
            $extraParams.ShowHelp=$true

            
            $linkUrl = "$FinalUrl".Substring(0, "$FinalUrl".LastIndexOf("/"))
            $titleArea = 
                if ($PipeworksManifest -and $pipeworksManifest.Logo) {
                    "<a href='$linkUrl' class='brand'><img src='$($pipeworksManifest.Logo)' alt='$($module)' style='border:0' /></a>"
                } else {
                    "<a href='$linkUrl' class='brand'>$($Module.Name)</a>"
                }

            


            

            # Create a Social Row (Facebook Likes, Google +1, Twitter)
            $socialArea = "
                <div style='padding:20px'>
            "

            if (-not $antiSocial) {
                if ($pipeworksManifest -and $pipeworksManifest.Facebook.AppId) {
                    $socialArea +=  
                        
                        (Write-Link "facebook:like" )                         
                }
                if ($pipeworksManifest -and ($pipeworksManifest.GoogleSiteVerification -or $pipeworksManifest.AddPlusOne)) {
                    $socialArea += 
                        
                        (Write-Link "google:plusone" )
                }
                if ($pipeworksManifest -and ($pipeworksManifest.Tweet -or $pipeworksManifest.AddTweet)) {
                    $socialArea += 
                        
                        (Write-Link "twitter:tweet" )
                } elseif ($pipeworksManifest -and ($pipeworksManifest.TwitterId)) {
                    $socialArea += 
                        (Write-Link "twitter:tweet" )
                    $socialArea +=                         
                        (Write-Link "twitter:follow@$($pipeworksManifest.TwitterId.TrimStart('@'))" ) 
                }
            }
                     
            $socialArea  += "</div>"        
            
            $result = 
                Invoke-Webcommand -Command $command @extraParams -AnalyticsId "$AnalyticsId" -AdSlot "$AdSlot" -AdSenseID "$AdSenseId" -ServiceUrl $finalUrl 2>&1

            if ($result) {
                if ($Request.params["AsRss"] -or 
                    $Request.params["AsCsv"] -or
                    $Request.params["AsXml"] -or
                    $Request.Params["bare"]) {
                    $response.Write($result)
                } else {
                    $outputPage = "<div style='float:left'>$($titleArea + $descriptionArea)</div>" + "<div style='float:right'>$socialArea</div>" + +($spacingDiv * 4) +$result |
                        New-Region -Style @{
                            "Margin-Left" = $marginPercentLeftString
                            "Margin-Right" = $marginPercentLeftString
                        }|
                        New-WebPage -Title "$($module.Name) | $command" -UseJQueryUI 
                    $response.Write($outputPage)
                }                
            }
            
        }
        #endregion Help Handler
        
        #region Command Handler
        $commandHandler = {
            
            
            $RequestedCommand = $Request["Command"]                                                   
            
            
            . $getCommandExtraInfo $RequestedCommand

            $result = try {
                Invoke-Webcommand -Command $command @extraParams -AnalyticsId "$AnalyticsId" -AdSlot "$AdSlot" -AdSenseID "$AdSenseId" -ServiceUrl $finalUrl 2>&1
            } catch {
                $_
            }
            $linkUrl = "$FinalUrl".Substring(0, "$FinalUrl".LastIndexOf("/"))
            $titleArea = 
                if ($PipeworksManifest -and $pipeworksManifest.Logo) {
                    "<a href='$linkUrl'><img src='$($pipeworksManifest.Logo)' alt='$($module)' style='border:0' /></a>"
                } else {
                    "<a href='$linkUrl'>" + $Module.Name + "</a>"
                }
            
            $commandDescription  = ""                        
            $commandHelp = Get-Help $command -ErrorAction SilentlyContinue | Select-Object -First 1 
            if ($commandHelp.Description) {
                $commandDescription = $commandHelp.Description[0].text
                $commandDescription = $commandDescription -replace "`n", ([Environment]::NewLine) 
            }

            $descriptionArea = "
            $(ConvertFrom-Markdown -Markdown "$commandDescription ")            
            "

            if ($result) {
                if ($Request.params["AsRss"] -or 
                    $Request.params["AsCsv"] -or
                    $Request.params["AsXml"] -or
                    $Request.Params["bare"] -or 
                    $extraParams.ContentType -or
                    $extraParams.PlainOutput) {
                            
                            
                    if (-not ($extraParams.ContentType) -and                        
                        $result -like "*<*>*" -and 
                        $result -like '*`$(*)*') {
                        # If it's not HTML or XML, but contains tags, then render it in a page with JQueryUI
                        $outputPage = $socialArea +  $spacingDiv + $descriptionArea + $spacingDiv + $result |
                            New-WebPage -Title "$($module.Name) | $command"
                        $response.Write($outputPage)
                    } elseif ($extraParams.ContentType -eq 'text/html' -and
                        $result -like "*$($command)_Input*" -and 
                        $result -notlike "*<html>*")
                    {
                        $outputPage = $socialArea +  $spacingDiv + $descriptionArea + $spacingDiv + $result |
                            New-WebPage -Title "$($module.Name) | $command"
                        $response.Write($outputPage)
                    } else {
                        $response.Write($result)

                        
                    }
                            
                } else {
                    if (($result -is [Collections.IEnumerable]) -or ($result -isnot [string])) {
                        $Result = $result | Out-HTML                                
                    }
                    if ($request["Snug"]) {
                        $outputPage = "<div style='clear:both;margin-top:1%'> </div>" + $result |
                            New-Region -Style @{
                                "Margin-Left" = "1%"
                                "Margin-Right" = "1%"
                            }|
                            New-WebPage -Title "$($module.Name) | $command"
                        $response.Write($outputPage)
                    } else {
                        $outputPage = $socialArea + $titleArea +  "<div style='clear:both;margin-top:1%'></div>" + $descriptionArea + $spacingDiv + $result |
                        New-Region -Style @{
                            "Margin-Left" = $marginPercentLeftString
                            "Margin-Right" = $marginPercentLeftString
                        }|
                        New-WebPage -Title "$($module.Name) | $command"
                        $response.Write($outputPage)
                    }
                            
                }                
            }
                        
            
        }
                
        #endregion Command Handler
        $validateUserTable = {
            if (-not ($pipeworksManifest.UserTable.Name -and $pipeworksManifest.UserTable.StorageAccountSetting -and $pipeworksManifest.UserTable.StorageKeySetting)) {
                throw 'The Pipeworks manifest must include these settings in order to manage users: UserTable.Name, UserTable.EmailAddress, UserTable.ExchangeServer, UserTable.ExchangePasswordSetting UserTable.StorageAccountSetting, and UserTable.StorageKeySetting'
                return
            }            
        }
                
        
        
        #region Join Handler
        $joinHandler = $validateUserTable.ToString()  + {
            $DisplayForm = $false
            $FormErrors = ""
          
            
          
            
            if (-not $request["Join-$($module.Name)_EmailAddress"]) {
                #$missingFields 
                $displayForm = $true
            }
            
            $newUserData =@{}
            $missingFields = @()
            $paramBlock = @()
            if ($session['ProfileEditMode'] -eq $true) {
                $editMode = $true
            }
            $defaultValue = if ($editMode -and $session['User'].UserEmail) {
                "|Default $($session['User'].UserEmail)"
            } else {
                ""
            }
            
            if ($Request['ReferredBy']) {
                $session['ReferredBy'] = $Request['ReferredBy']
            }
            $paramBlock += "
            #$defaultValue
            [Parameter(Mandatory=`$true,Position=0)]
            [string]
            `$EmailAddress
            "
            if ($pipeworksManifest.UserTable.RequiredInfo) {
                $Position = 1
                foreach ($k in $pipeworksManifest.UserTable.RequiredInfo.Keys) {
                    $newUserData[$k] = $request["Join-$($module.Name)_${k}"] -as $pipeworksManifest.UserTable.RequiredInfo[$k]
                    $defaultValue = if ($session['User'].$k) {
                        "|Default $($session['User'].$k)"
                    } else {
                        ""
                    }
                    
                    $paramBlock += "
            #$defaultValue
            [Parameter(Mandatory=`$true,Position=$position)]
            [$($pipeworksManifest.UserTable.RequiredInfo[$k].Fullname)]
            `$$k
            "
                    $Position++
                    if (-not $newUserData[$k]) { 
                        $missingFields += $k
                    }
                }
            }
            
            
            if ($pipeworksManifest.UserTable.OptionalInfo) {
                foreach ($k in $pipeworksManifest.UserTable.OptionalInfo.Keys) {
                    $newUserData[$k] = $request["Join-$($module.Name)_${k}"] -as $pipeworksManifest.UserTable.OptionalInfo[$k]
                    $defaultValue = if ($session['User'].$k) {
                        "|Default $($session['User'].$k)"
                    } else {
                        ""
                    }
                    $paramBlock += "
            #${defaultValue}
            [Parameter(Position=$position)]
            [$($pipeworksManifest.UserTable.OptionalInfo[$k].Fullname)]
            `$$k
            "
                }
            }
            
            
            if ($pipeworksManifest.UserTable.TermsOfService) {
            
            }
            
            .([ScriptBlock]::Create(
                "function Join-$($module.Name) {
                    <#
                    .Synopsis
                        Joins $($module.Name) or edits a profile
                    .Description
                           
                    #>
                    param(
                    $($paramBlock -join ",$([Environment]::NewLine)")
                    )
                }                
                "))
            
            $cmdInput = Get-WebInput -CommandMetaData (Get-Command "Join-$($module.Name)" -CommandType Function)
            if ($cmdInput.Count -gt 0) {
                $DisplayForm = $false
            }
            
            
            if ($missingFields) {
                $email = $request["Join-$($module.Name)_EmailAddress"]
                $emailFound = [ScriptBlock]::Create("`$_.UserEmail -eq '$email'")
                $storageAccount = (Get-WebConfigurationSetting -Setting $pipeworksManifest.UserTable.StorageAccountSetting)
                $storageKey = (Get-WebConfigurationSetting -Setting $pipeworksManifest.UserTable.StorageKeySetting)

                $mailAlreadyExists = 
                    Search-AzureTable -TableName $pipeworksManifest.UserTable.Name -StorageAccount $storageAccount -StorageKey $storageKey  -Where $emailFound

                if (-not $mailAlreadyExists) {
                    # Get required fields
                    $DisplayForm = $true
                } elseif ($editMode -and $session['User']) {
                    # Get required fields
                    $DisplayForm = $true
                } else {
                    # Reconfirm
                    $DisplayForm = $false
                }
                
            }

                    
            $sendMailParams = @{
                BodyAsHtml = $true
                To = $request["Join-$($module.Name)_EmailAddress"]
                
            }
            
            $sendMailCommand = if ($pipeworksManifest.UserTable.SmtpServer -and $pipeworksManifest.UserTable.FromEmail -and $pipeworksManifest.UserTable.FromUser -and $pipeworksManifest.UserTable.EmailPasswordSetting) {
                $($ExecutionContext.InvokeCommand.GetCommand("Send-MailMessage", "All"))
                $un  = $pipeworksManifest.UserTable.FromUser
                $pass = Get-WebConfigurationSetting -Setting $pipeworksManifest.UserTable.EmailPasswordSetting
                $pass = ConvertTo-SecureString $pass  -AsPlainText -Force 
                $cred = 
                    New-Object Management.Automation.PSCredential ".\$un", $pass 
                        
                $sendMailParams += @{
                    SmtpServer = $pipeworksManifest.UserTable.SmtpServer 
                    From = $pipeworksManifest.UserTable.FromEmail
                    Credential = $cred
                    UseSsl = $true
                }

            } else {
                $($ExecutionContext.InvokeCommand.GetCommand("Send-Email", "All"))
                $sendMailParams += @{
                    UseWebConfiguration = $true
                    AsJob = $true
                }
            }
            
            
            if ($displayForm) {
                $formErrors = if ($missingFields -and ($cmdInput.Count -ne 0)) {
                    "Missing $missingFields"
                } else {
                
                }                                
                
                $buttonText = if ($mailAlreadyExists -or $session['User']) {
                    "Edit Profile"                    
                } else {
                    "Join / Login"
                }

                
                $response.Write("
                $FormErrors
                $(Request-CommandInput -ButtonText $buttonText -Action "${FinalUrl}?join=true" -CommandMetaData (Get-Command "Join-$($module.Name)" -CommandType Function))
                ")
                
            } else {
                $session['UserEmail'] = $request["Join-$($module.Name)_EmailAddress"]
                $session['UserData'] = $newUserData
                $session['EditMode'] = $editMode
                
                
                $storageAccount = (Get-WebConfigurationSetting -Setting $pipeworksManifest.UserTable.StorageAccountSetting)
                $storageKey = (Get-WebConfigurationSetting -Setting $pipeworksManifest.UserTable.StorageKeySetting)

                $email = $Session['UserEmail']
                $editMode = $session['EditMode']
                $session['EditMode'] = $null
                $emailFound = [ScriptBlock]::Create("`$_.UserEmail -eq '$email'")

                $userProfilePartition =
                    if (-not $pipeworksManifest.UserTable.Partition) {
                        "UserProfiles"
                    } else {
                        $pipeworksManifest.UserTable.Partition
                    }

                
                $mailAlreadyExists = 
                    Search-AzureTable -TableName $pipeworksManifest.UserTable.Name -StorageAccount $storageAccount -StorageKey $storageKey  -Where $emailFound |
                    Where-Object {
                        $_.PartitionKey -eq $userProfilePartition
                    }
                
                
                $newUserObject = New-Object PSObject -Property @{
                    UserEmail = $Session['UserEmail']
                    UserID = [GUID]::NewGuid()
                    Confirmed = $false
                    Created = Get-Date                
                }
                
                
                $ConfirmCode = [Guid]::NewGuid()
                $newUserObject.pstypenames.clear()
                $newUserObject.pstypenames.add("$($module.Name)_UserInfo")
                
                $extraPropCommonParameters = @{
                    InputObject = $newUserObject
                    MemberType = 'NoteProperty'
                }
                        
                Add-Member @extraPropCommonParameters -Name ConfirmCode -Value "$confirmCode"
                if ($session['UserData']) {
                    foreach ($kvp in $session['UserData'].GetEnumerator()) {
                        Add-Member @extraPropCommonParameters -Name $kvp.Key -Value $kvp.Value
                    }
                }
                
                $commonAzureParameters = @{
                    TableName = $pipeworksManifest.UserTable.Name
                    PartitionKey = $userProfilePartition
                }
                
                
                
                if ($mailAlreadyExists) {
                    
                    
                    
                    if ((-not $editMode) -or (-not $session['User'])) {
                    
                        # Creating a brand new item via the email system.  Email the confirmation code out.
                    
                    
                        $rootLocation= "$finalUrl".Substring(0, $finalUrl.LAstIndexOf("/"))
                        $introMessage = if ($pipeworksManifest.UserTable.IntroMessage) {
                            $pipeworksManifest.UserTable.IntroMessage + "<br/> <a href='${finalUrl}?confirmUser=$confirmCode'>Confirm Email Address</a>"
                        } else {
                            "<br/> <a href='${finalUrl}?confirmUser=$confirmCode'>Re-confirm Email Address to login</a>"
                        }
                        
                        $sendMailParams += @{
                            Subject= "Please re-confirm your email for $($module.Name)"
                            Body = $introMessage
                        }                    
                        
                        
                        & $sendMailcommand @sendMailParams 
                        
                        "Account already exists.  A request to login has been sent to $($mailAlreadyExists.UserEmail)." |
                            New-WebPage -Title "Email address is already registered, sending reconfirmation mail" -RedirectTo $rootLocation -RedirectIn "0:0:5"  |
                            Out-HTML -WriteResponse                                                           #
                            
                        <# Send-Email -To $newUserObject.UserEmail -UseWebConfiguration - -Body $introMessage -BodyAsHtml -AsJob                
                        "Account already exists.  A request to login has been sent to $($mailAlreadyExists.UserEmail)." |
                            New-WebPage -Title "Email address is already registered, sending reconfirmation mail" -RedirectTo $rootLocation -RedirectIn "0:0:5"  |
                            Out-HTML -WriteResponse                                                           #>
                        
                        $mailAlreadyExists |
                            Add-Member NoteProperty ConfirmCode "$confirmCode" -Force -PassThru | 
                            Update-AzureTable @commonAzureParameters -RowKey $mailAlreadyExists.RowKey -Value { $_}
                    } else {
                        
                        # Reconfirmation of Changes.  If the user is logged in via facebook, then simply make the change.  Otherwise, make the changes pending.
                        if (-not $pipeworksManifest.Facebook.AppId) {
                        
                            $introMessage = 
                            "<br/> <a href='${finalUrl}?confirmUser=$confirmCode'>Please confirm changes to your $($module.Name) account</a>"                   
                            
                            $introMessage += "<br/><br/>"
                            $introMessage += New-Object PSObject -Property $session['UserData'] |
                                Out-HTML
                         
                            $sendMailParams += @{
                                Subject= "Please confirm changes to your $($module.Name) account"
                                Body = $introMessage
                            }   
                            
                            & $sendMailcommand @sendMailParams
                            
                            "An email has been sent to $($mailAlreadyExists.UserEmail) to confirm the changes to your acccount" |
                                New-WebPage -Title "Confirming Changes" -RedirectTo $rootLocation -RedirectIn "0:0:5" |
                                Out-HTML -WriteResponse
                            
                            $mailAlreadyExists |
                                Add-Member NoteProperty ConfirmCode "$confirmCode" -Force -PassThru | 
                                Update-AzureTable @commonAzureParameters -RowKey $mailAlreadyExists.RowKey -Value { $_}
                            $changeToMake = @{} + $commonAzureParameters
                            
                            $changeToMake.PartitionKey = "${userProfilePartition}_PendingChanges"
                                                
                            # Create a row in the pending change table
                            $newUserObject.psobject.properties.Remove('ConfirmCode')
                            $newUserObject |
                                Set-AzureTable @changeToMake -RowKey {[GUID]::NewGuid() } 
                        } else {
                            # Make the profile change
                            $newUserObject |
                                Update-AzureTable @commonAzureParameters -RowKey $mailAlreadyExists.RowKey
                        }
                        
                            
                            
                    }
                    
                    
                } else {
                    
                    if ($pipeworksManifest.UserTable.BlacklistParition) {
                        $blackList = 
                            Search-AzureTable -TableName $pipeworks.UserTable.Name -Filter "PartitionKey eq '$($pipeworksManifest.UserTable.BlacklistParition)'"                        
                            
                        if ($blacklist) {
                            foreach ($uInfo in $Blacklist) {
                                if ($newUserObject.UserEmail -like "*$uInfo*") {
                                    Write-Error "$($newUserObject.UserEmai) is blacklisted from $($module.Name)"
                                    return
                                }
                            }
                        }
                    }
                    
                    if ($pipeworksManifest.UserTable.WhitelistPartition) {
                        $whiteList = 
                            Search-AzureTable -TableName $pipeworks.UserTable.Name -Filter "PartitionKey eq '$($pipeworksManifest.UserTable.WhitelistParition)'"                        
                            
                        if ($whiteList) {
                            $inWhiteList = $false
                            foreach ($uInfo in $whiteList) {
                                if ($newUserObject.UserEmail -like "*$uInfo*") {
                                    $inWhiteList = $true
                                    break
                                }
                            }
                            if (-not $inWhiteList) {
                                Write-Error "$($newUserObject.UserEmail) is not on the whitelist for $($module.Name)"
                            }
                        }

                    }
                    
                    if ($pipeworksManifest.UserTable.InitialBalance) {
                        $newUserObject | 
                            Add-Member NoteProperty Balance (0- ([Double]$pipeworksManifest.UserTable.InitialBalance))
                    }
                
                    if ($session['RefferedBy']) {
                        $newUserObject |
                            Add-Member NoteProperty RefferedBy $session['RefferedBy'] -PassThru |
                            Add-Member NoteProperty RefferalCreditApplied $false 
                    }
                
                    $newUserObject |
                        Set-AzureTable @commonAzureParameters -RowKey $newUserObject.UserId
                        
                        
                    $introMessage = if ($pipeworksManifest.UserTable.IntroMessage) {
                        $pipeworksManifest.UserTable.IntroMessage + "<br/> <a href='${finalUrl}?confirmUser=$confirmCode'>Confirm Email Address</a>"
                    } else {
                        "<br/> <a href='${finalUrl}?confirmUser=$confirmCode'>Confirm Email Address</a>"
                    }
                    
                    $sendMailParams += @{
                        Subject= "Please confirm your email for $($module.Name)"
                        Body = $introMessage
                    }
                    & $sendMailcommand @sendMailParams
                                    
                    if ($passThru) {
                        $newUserObject
                    }
                    
                    $almostWelcomeScreen  = if ($pipeworksManifest.UserTable.ConfirmationMailSent) {
                        $pipeworksManifest.UserTable.ConfirmationMailSent 
                    } else {
                        "A confirmation mail has been sent to $($newUserObject.UserEmail)"
                    }
                                    
                    $html = New-Region -Content $almostWelcomeScreen -AsWidget -Style @{
                        'margin-left' = $MarginPercentLeftString
                        'margin-right' = $MarginPercentRightString
                        'margin-top' = '10px'   
                        'border' = '0px' 
                    } |
                    New-WebPage -Title "Welcome to $($module.Name) | Confirmation Mail Sent" 
                    
                    $response.Write($html)                      
                    
                    
                }
                
            }
            
        }


        if ($useLoginHandlers) {
            $joinHandler = [ScriptBlock]::Create($joinHandler)
        } else {
            $joinHandler = {}
        }
        #endregion

        $AddUserStat = $validateUserTable.ToString() + { 
            if (-not $session["User"]) {
                throw "Must be logged in"
               
            }
                        


        }

        
        
        $ShowApiKeyHandler = $validateUserTable.ToString() + {
            if ($request.Cookies["$($module.Name)_ConfirmationCookie"]) {
                $response.Write($request.Cookies["$($module.Name)_ConfirmationCookie"]["Key"])
            }
        }
        
        $logoutUserHandler = $validateUserTable.ToString()  + {                        
            $secondaryApiKey = $session["$($module.Name)_ApiKey"]
            $confirmCookie = New-Object Web.HttpCookie "$($module.Name)_ConfirmationCookie"
            $confirmCookie["Key"] = "$secondaryApiKey"
            $confirmCookie["CookiedIssuedOn"] = (Get-Date).ToString("r")
            $confirmCookie.Expires = (Get-Date).AddDays(-365)                    
            $response.Cookies.Add($confirmCookie)
            $session['User'] = $null            
            $html = New-WebPage -Title "Logging Out" -RedirectTo "$finalUrl"
            $response.Write($html)                        
        }
        
        $loginUserHandler = $validateUserTable.ToString()  + {

            $storageAccount = (Get-WebConfigurationSetting -Setting $pipeworksManifest.UserTable.StorageAccountSetting)
            $storageKey = (Get-WebConfigurationSetting -Setting $pipeworksManifest.UserTable.StorageKeySetting)
            $confirmCookie= $Request.Cookies["$($module.Name)_ConfirmationCookie"]
            
            if ($confirmCookie) {            
                $matchApiInfo = [ScriptBLock]::Create("`$_.SecondaryApiKey -eq '$($confirmCookie.Values['Key'])'")           
                $userFound = 
                    Search-AzureTable -TableName $pipeworksManifest.UserTable.Name -StorageAccount $storageAccount -StorageKey $storageKey -Where $matchApiInfo 
                
                if (-not $userFound) {
                    $secondaryApiKey = $session["$($module.Name)_ApiKey"]
                    $confirmCookie = New-Object Web.HttpCookie "$($module.Name)_ConfirmationCookie"
                    $confirmCookie["Key"] = "$secondaryApiKey"
                    $confirmCookie["CookiedIssuedOn"] = (Get-Date).ToString("r")
                    $confirmCookie.Expires = (Get-Date).AddDays(-365)                    
                    $response.Cookies.Add($confirmCookie)
                    $response.Flush()
                    
                    $response.Write("User $($confirmCookie | Out-String) Not Found, ConfirmationCookie Set to Expire")                                        
                    return
                }                                        

                $userIsConfirmed = $userFound |
                    Where-Object {
                        $_.Confirmed -ilike "*$true*" 
                    }
                    
                $userIsConfirmedOnThisMachine = $userIsConfirmed |
                    Where-Object {
                        $_.ConfirmedOn -ilike "*$($Request['REMOTE_ADDR'] + $request['REMOTE_HOST'])*"
                    }
                    
                $sendMailParams = @{
                    BodyAsHtml = $true
                    To = $newUserObject.UserEmail
                }
                
                $sendMailCommand = if ($pipeworksManifest.UserTable.SmtpServer -and 
                    $pipeworksManifest.UserTable.FromEmail -and 
                    $pipeworksManifest.UserTable.FromUser -and 
                    $pipeworksManifest.UserTable.EmailPasswordSetting) {
                    $($ExecutionContext.InvokeCommand.GetCommand("Send-MailMessage", "All"))
                    $un  = $pipeworksManifest.UserTable.FromUser
                    $pass = Get-WebConfigurationSetting -Setting $pipeworksManifest.UserTable.EmailPasswordSetting
                    $pass = ConvertTo-SecureString $pass  -AsPlainText -Force 
                    $cred = 
                        New-Object Management.Automation.PSCredential ".\$un", $pass 
                    $sendMailParams += @{
                        SmtpServer = $pipeworksManifest.UserTable.SmtpServer 
                        From = $pipeworksManifest.UserTable.FromEmail
                        Credential = $cred
                        UseSsl = $true
                    }
                    
                } else {
                    $($ExecutionContext.InvokeCommand.GetCommand("Send-Email", "All"))
                    $sendMailParams += @{
                        UseWebConfiguration = $true
                        AsJob = $true
                    }
                }
                        
                if (-not $userIsConfirmedOnThisMachine) {
                    $confirmCode = [guid]::NewGuid()
                    Add-Member -MemberType NoteProperty -InputObject $userIsConfirmed -Name ConfirmCode -Force -Value "$confirmCode"
                    
                    
                    $introMessage = if ($pipeworksManifest.UserTable.IntroMessage) {
                        $pipeworksManifest.UserTable.IntroMessage + "<br/> <a href='${finalUrl}?confirmUser=$confirmCode'>Confirm Email Address</a>"
                    } else {
                        "<br/> <a href='${finalUrl}?confirmUser=$confirmCode'>Confirm Email Address</a>"
                    }
                    
                    $sendMailParams += @{
                        Subject= "Welcome to $($module.Name)"
                        Body = $introMessage
                    }                    
                    
                    
                    & $sendMailcommand @sendMailParams

                    # Send-Email -To $userIsConfirmed.UserEmail -UseWebConfiguration -Subject  -Body $introMessage -BodyAsHtml -AsJob
                    $partitionKey = $userIsConfirmed.PartitionKey
                    $rowKey = $userIsConfirmed.RowKey
                    $tableName = $userIsConfirmed.TableName
                    $userIsConfirmed.psobject.properties.Remove('PartitionKey')
                    $userIsConfirmed.psobject.properties.Remove('RowKey')
                    $userIsConfirmed.psobject.properties.Remove('TableName')                    
                    $userIsConfirmed |
                        Update-AzureTable -TableName $tableName -RowKey $rowKey -PartitionKey $partitionKey -Value { $_} 
                    
                    $message = "User Not confirmed on this machine/ IPAddress.  A confirmation mail has been sent to $($userFound.UserEmail)"
                    
                    $html = New-Region -Content $message -AsWidget -Style @{
                        'margin-left' = $MarginPercentLeftString
                        'margin-right' = $MarginPercentRightString
                        'margin-top' = '10px'   
                        'border' = '0px' 
                    } |
                    New-WebPage -Title "$($module.Name)| Login Error: Unrecognized Machine"                    

                    
                    
                    $response.Write("$html")
                    
                    
                    return
                } else {
                    $session['User'] = $userIsConfirmedOnThisMachine
                    $session['UserId'] = $userIsConfirmedOnThisMachine.UserId
                    $welcomeBackMessage = "Welcome back " + $(
                        if ($userIsConfirmedOnThisMachine.Name) {
                            $userIsConfirmedOnThisMachine.Name
                        } else {
                            $userIsConfirmedOnThisMachine.UserEmail
                        }
                    )
                    
                    $secondaryApiKey = "$($confirmCookie.Values['Key'])"                    
                    
                    $backToUrl = if ($session['BackToUrl']) {
                        $session['BackToUrl']
                        $session['BackToUrl'] = $null
                    } else {
                        $finalUrl.ToString().Substring(0,$finalUrl.ToString().LastIndexOf("/"))
                    }
                    
                    $html = New-Region -Content $welcomeBackMessage -AsWidget -Style @{
                        'margin-left' = $MarginPercentLeftString
                        'margin-right' = $MarginPercentRightString
                        'margin-top' = '10px'   
                        'border' = '0px' 
                    } |
                    New-WebPage -Title "Welcome to $($module.Name)" -RedirectTo $backToUrl -RedirectIn "0:0:0.125"
                    $response.Write("$html")
                    
                    
   
                    
                    $partitionKey = $userIsConfirmedOnThisMachine.PartitionKey
                    $rowKey = $userIsConfirmedOnThisMachine.RowKey
                    $tableName = $userIsConfirmedOnThisMachine.TableName
                    $userIsConfirmedOnThisMachine.psobject.properties.Remove('PartitionKey')
                    $userIsConfirmedOnThisMachine.psobject.properties.Remove('RowKey')
                    $userIsConfirmedOnThisMachine.psobject.properties.Remove('TableName')                    
                    $userIsConfirmedOnThisMachine | Add-Member -MemberType NoteProperty -Name LastLogon -Force -Value (Get-Date)
                    $userIsConfirmedOnThisMachine | Add-Member -MemberType NoteProperty -Name LastLogonFrom -Force -Value "$($Request['REMOTE_ADDR'] + $request['REMOTE_HOST'])"
                    $userIsConfirmedOnThisMachine |
                        Update-AzureTable -TableName $tableName -RowKey $rowKey -PartitionKey $partitionKey -Value { $_} 
                        
                    $session['User'] = $userIsConfirmedOnThisMachine
                }
                
                
                
            } else {
            
                $html = New-WebPage -Title "User Information Not Found - Redirecting to Signup Page" -RedirectTo "${finalUrl}?join=true"
                $response.Write($html)
                return
            }

        }
        
        
        $confirmUserHandler = $validateUserTable.ToString()  + {
            
            $confirmationCode = [Web.HttpUtility]::UrlDecode($request['confirmUser']).TrimEnd(" ").TrimEnd("#").TrimEnd(">").TrimEnd("<")
            
            $session['ProfileEditMode'] = $false            
            
            $storageAccount = (Get-WebConfigurationSetting -Setting $pipeworksManifest.UserTable.StorageAccountSetting)
            $storageKey = (Get-WebConfigurationSetting -Setting $pipeworksManifest.UserTable.StorageKeySetting)
            $confirmCodeFilter = 
                [ScriptBLock]::Create("`$_.ConfirmCode -eq '$confirmationCode'")
            $confirmationCodeFound = 
                Search-AzureTable -TableName $pipeworksManifest.UserTable.Name -StorageAccount $storageAccount -StorageKey $storageKey -Where $confirmCodeFilter
            
            if (-not $confirmationCodeFound) {
                Write-Error "Confirmation Code Not Found"
                return
            }
                        
            $confirmedOn = ($confirmationCodeFound.ConfirmedOn + "," +
                ($Request['REMOTE_ADDR'] + $request['REMOTE_HOST'])) -split "," -ne "" | Select-Object -Unique
            
            $confirmSalts = @($confirmationCodeFound.ConfirmSalt -split "\|")
            
            $confirmationCodeFound | 
                Add-Member NoteProperty Confirmed $true -Force
            $confirmationCodeFound |
                Add-Member NoteProperty ConfirmedOn ($confirmedOn -join ',') -Force
                
            
            # When we confirm the item, we set two cookies.  One keeps the Secondary API key, and the other a confirmation salt.  Both are HTTP only
            $ThisConfirmationSalt = [GUID]::NewGuid()
            $confirmSalts += $ThisConfirmationSalt 
            $confirmationCodeFound |                
                Add-Member NoteProperty ConfirmedOn ($confirmedOn -join ',') -Force
<#            $confirmationCodeFound |                
                Add-Member NoteProperty ConfirmSalt ($confirmSalts -join '|') -Force
#>            
            if (-not $confirmationCodeFound.PrimaryApiKey) { 
                $primaryApiKey  =[guid]::NewGuid()
                $secondaryApiKey = [guid]::NewGuid()
                $confirmationCodeFound |
                    Add-Member NoteProperty PrimaryApiKey "$primaryApiKey" -PassThru -ErrorAction SilentlyContinue |
                    Add-Member NoteProperty SecondaryApiKey "$secondaryApiKey" -ErrorAction SilentlyContinue  
            } else {
                $primaryApiKey = $confirmationCodeFound.PrimaryApiKey
                $secondaryApiKey = $confirmationCodeFound.SecondaryApiKey
                $sessionApiKey = [Convert]::ToBase64String(([Guid]$secondaryApiKey).ToByteArray())
                $session["$($module.Name)_ApiKey"] = $sessionApiKey
            }
            
            $confirmCookie = New-Object Web.HttpCookie "$($module.Name)_ConfirmationCookie"
            $confirmCookie["Key"] = "$secondaryApiKey"
            $confirmCookie["CookiedIssuedOn"] = (Get-Date).ToString("r")
            $confirmCookie["ConfirmationSalt"] = $ThisConfirmationSalt
            $confirmCookie["Email"] = $confirmationCodeFound.UserEmail
            $confirmCookie.Expires = (Get-Date).AddDays(365)
            $response.Cookies.Add($confirmCookie)
            
                
            $partitionKey = $confirmationCodeFound.PartitionKey
            $rowKey = $confirmationCodeFound.RowKey
            $tableName = $confirmationCodeFound.TableName
            $confirmCount =$confirmationCodeFound.ConfirmCount -as [int] 
            $confirmCount++
            $confirmationCodeFound | Add-Member NoteProperty ConfirmCount $ConfirmCount -Force
            $confirmationCodeFound.psobject.properties.Remove('PartitionKey')
            $confirmationCodeFound.psobject.properties.Remove('RowKey')
            $confirmationCodeFound.psobject.properties.Remove('TableName')
            $confirmationCodeFound.psobject.properties.Remove('ConfirmCode')
            
            
            # At this point they are actually confirmed
            $confirmationCodeFound | 
                Update-AzureTable -TableName $pipeworksManifest.UserTable.Name  -RowKey $rowKey -PartitionKey $partitionKey -Value { $_} 
                
            if ($confirmationCodeFound.ConfirmCount -eq 1 ) {
                $ConfirmMessage = @"
$($pipeworksManifest.UserTable.WelcomeEmailMessage)
<BR/>
Thanks for confirming,<br/>
<br/>
Your API key is: $secondaryApiKey <br/>
<br/>

Whenever you need to use a software service in $($module.Name), use this API key.

(It's also being emailed to you)
"@
                                            
                $html = New-Region -Content $confirmMessage -AsWidget -Style @{
                    'margin-left' = $MarginPercentLeftString
                    'margin-right' = $MarginPercentRightString
                    'margin-top' = '10px'   
                    'border' = '0px' 
                } |
                New-WebPage -Title "Welcome to $($module.Name)" -RedirectTo "${finalUrl}?login=true" -RedirectIn "0:0:5"
                $session['User']  = Get-AzureTable -TableName $pipeworksManifest.UserTable.Name  -RowKey $rowKey -PartitionKey $partitionKey
                $response.Write("$html")
                
                
                $sendMailParams = @{
                    BodyAsHtml = $true
                    To = $newUserObject.UserEmail
                }
                
                $sendMailCommand = if ($pipeworksManifest.UserTable.SmtpServer -and 
                    $pipeworksManifest.UserTable.FromEmail -and 
                    $pipeworksManifest.UserTable.FromUser -and 
                    $pipeworksManifest.UserTable.EmailPasswordSetting) {
                    $($ExecutionContext.InvokeCommand.GetCommand("Send-MailMessage", "All"))
                    $un  = $pipeworksManifest.UserTable.FromUser
                    $pass = Get-WebConfigurationSetting -Setting $pipeworksManifest.UserTable.EmailPasswordSetting
                    $pass = ConvertTo-SecureString $pass  -AsPlainText -Force 
                    $cred = 
                        New-Object Management.Automation.PSCredential ".\$un", $pass 
                    $sendMailParams += @{
                        SmtpServer = $pipeworksManifest.UserTable.SmtpServer 
                        From = $pipeworksManifest.UserTable.FromEmail
                        Credential = $cred
                        UseSsl = $true
                    }
                    

                } else {
                    $($ExecutionContext.InvokeCommand.GetCommand("Send-Email", "All"))
                    $sendMailParams += @{
                        UseWebConfiguration = $true
                        AsJob = $true
                    }
                }
                
                
                $sendMailParams += @{
                    Subject= "Welcome to $($module.Name)"
                    Body = @"
$($pipeworksManifest.UserTable.WelcomeEmailMessage)
<BR/>
Thanks for confirming,<br/>
<br/>
Your API key is: $secondaryApiKey <br/>
<br/>
"@                    
                }
                
                & $sendMailcommand @sendMailParams 
                   
                # Send-Email -UseWebConfiguration -AsJob -To $confirmationCodeFound.UserEmail -BodyAsHtml  
                
            } else {  
                # Check to see if this is confirming an update, and make the changes
                $emailFilter = [ScriptBlock]::Create("`$_.UserEmail -eq '$($confirmationCodeFound.UserEmail)'")
                $emailEditsByTime = Search-AzureTable -TableName $pipeworksManifest.UserTable.Name -Where $emailFilter  | 
                    Sort-Object { [DateTime]$_.Timestamp } 
                
                $userProfilePartition =
                    if (-not $pipeworksManifest.UserTable.Partition) {
                        "UserProfiles"
                    } else {
                        $pipeworksManifest.UserTable.Partition
                    }
                
                $original  = $emailEditsByTime|
                    Where-Object { $_.PartitionKey -eq $userProfilePartition } |
                    Select-Object -First 1 
                    
                $update =  $emailEditsByTime|
                    Where-Object { $_.PartitionKey -ne $userProfilePartition } |
                    Select-Object -Last 1 
                
                                                    
                if ($original -and $update) {
                    $changeProperties = @($pipeworksManifest.UserTable.RequiredInfo.Keys) + @($pipeworksManifest.UserTable.OptionalInfo.Keys)
                    $toChange = $update | Select-Object -First 1 | Select-Object $changeProperties 
                    
                    foreach ($prop in $toChange.psobject.properties) {
                        $original | Add-Member NoteProperty $prop.Name $prop.Value -Force
                    }

                    
                    $original | 
                        Update-AzureTable -TableName $pipeworksManifest.UserTable.name -PartitionKey $userProfilePartition -RowKey $original.UserId -Value { $_}
                        
                    $userInfo  =
                        Get-AzureTable -TableName $pipeworksManifest.UserTable.name -PartitionKey $userProfilePartition -RowKey $original.UserId
                    $session['User']  = $userInfo
                    
                    $update |
                        Remove-AzureTable -Confirm:$false
                    
                    $ConfirmMessage = @"
<BR/>
Thanks for confirming.  The following changes have been made to your account:<br/>

$($toChange | Out-HTML)
"@
                
                
                } else {
                    $ConfirmMessage = @"
$($pipeworksManifest.UserTable.WelcomeBackMessage)
<BR/>
Thanks for re-confirming, and welcome back<br/>
"@
                }
                
                
                
                $html = New-Region -Content $confirmMessage -AsWidget -Style @{
                    'margin-left' = $MarginPercentLeftString
                    'margin-right' = $MarginPercentRightString
                    'margin-top' = '10px'   
                    'border' = '0px' 
                } |
                New-WebPage -Title "Welcome back to $($module.Name)" -RedirectTo "${finalUrl}?login=true"
                $response.Write("$html")
            }
        }
        
        
        $TextHandler = {
            # Handle text input for all commands in WebCommand
            
            
                    
        }
        
        $MeHandler = {
            $confirmPersonHtml = . Confirm-Person -WebsiteUrl $finalUrl
            if ($session -and $session["User"]) {
                $profilePage = $session["User"] | 
                    Out-HTML | 
                    New-WebPage
                $response.Write($profilePage)
            } else {
                throw "Not Logged In"
            }
        }

        if (-not $useLoginHandlers) {
            $MeHandler = {}
        }
        
        $settleHandler = $validateUserTable.ToString() + {
            if (-not ($session -and $session["User"])) {
                throw "Not Logged in"
            }
            
                        New-WebPage -RedirectTo "?Purchase=true&ItemName=Settle Account Balance&ItemPrice=$($session["User"].Balance)" |
                Out-html -writeresponse
        }


        $buywithCodeHandler = $validateUserTable.ToString() + {
            
            if (-not $pipeworksManifest.PaymentProcessing.BuyCodeHandler) {
                return
            }

            if (-not $pipeworksManifest.PaymentProcessing.BuyCodePartition) {
                return
            }

            if (-not ($request -and $request["PotentialBuyCode"])) {
                return
            }

            $storageAccount = Get-SecureSetting $pipeworksManifest.UserTable.StorageAccountSetting -ValueOnly
            $storageKey = Get-SecureSetting $pipeworksManifest.UserTable.StorageKeySetting -ValueOnly
            $buyCodeFound = Get-AzureTable -StorageAccount $storageAccount -StorageKey $storageAccount -PartitionKey $pipeworksManifest.PaymentProcessing.BuyCodePartition -RowKey $($request["PotentialBuyCode"])
            if ($buyCodeFound) {
                if (($buyCode.NumberOfUses -as [int]) -ge 0) {

                } else {
                    "Buy code not found" | 
                    New-WebPage -Title "Buy code not found" |
                        Out-html -writeresponse
                }
            } else {
                "Buy code not found" | 
                New-WebPage -Title "Buy code not found" |
                    Out-html -writeresponse
            }
            <#
            
                
            } else {             
                
                
            }
            #>
        }
        

        
        $addCartHandler = {
            if (-not ($request -and $request["ItemId"] -and $request["ItemName"] -and $Request["ItemPrice"])) {
                throw "Must provide an ItemID and ItemName and ItemPrice"    
            }
            $cartCookie = $request.Cookies["$($module.Name)_CartCookie"]
            if (-not $cartCookie) {
                $CartCookie = New-Object Web.HttpCookie "$($module.Name)_CartCookie"            
            }
            $CartCookie["Item_" + $request["ItemID"]]= $request["ItemName"] + "|" + $request["ItemPrice"]
            $CartCookie["LastUpdatedOn"] = (Get-Date).ToString("r")
            $CartCookie.Expires = (Get-Date).AddMinutes(60)                    
            $response.Cookies.Add($CartCookie )            
            $response.Write("<p style='display:none'>")
            $response.Flush()
            return
        }

        $showCartHandler = {
            $cartCookie = $request.Cookies["$($module.Name)_CartCookie"]
            if (-not $cartCookie) {
                $CartCookie = New-Object Web.HttpCookie "$($module.Name)_CartCookie"            
            }
            
            
            $cartCookie.Values.GetEnumerator()  |
                Where-Object {
                    $_ -like "Item_*"
                } |
                Foreach-Object -Begin {
                    $items = @()
                    
                } {
                    $itemId = $_.Replace("Item_", "")
                    $itemName, $itemPrice = $cartCookie.Values[$_] -split "\|"       
                    
                    if (-not ($itemPrice -as [Double])) {
                        if ($itemPrice.Substring(1) -as [Double]) {
                            $itemPrice = $itemPrice.Substring(1)
                        }
                    }             
                    $items+= New-Object PSObject |
                        Add-Member NoteProperty Name $itemName -passthru | 
                        Add-Member NoteProperty Price ($itemPrice -as [Double]) -passthru 
                } -End {
                    $subtotal = $items | 
                        Measure-Object -Sum Price | 
                        Select-Object -ExpandProperty Sum
                    ($items | Out-HTML ) + 
                        "<HR/>" + 
                        ("<div style='float:right;text-align:right'><b>Subtotal:</b><br/><br/><span style='margin:5px'>$Subtotal</span></div><div style='clear:both'></div>")
                }|
                Out-HTML -WriteResponse


            if ($session -and $session["User"]) {
            
            } else {
                function Request-ContactInfo
                {
                    <#
                    .Synopsis
                    
                    .Description
                        Please let us know how to get in touch with you in case there's a problem with your order
                    .Example

                    #>
                    param(
                    # Your Name
                    [string]
                    $Name,

                    # Your email
                    [string]
                    $Email,


                    # Your Phone number
                    [string]
                    $PhoneNumber
                    )
                }

                Request-CommandInput -CommandMetaData (Get-Command Request-Contactinfo) -ButtonText "Checkout" -Action "${finalUrl}?Checkout=true" | Out-HTML -WriteResponse
                
            }
            
            return
        }


        $checkoutCartHandler = {
            
            if ($pipeworksManifest.Checkout.To -and
                $pipeworksManifest.Checkout.SmtpServer -and 
                $pipeworksManifest.Checkout.SmtpUserSetting -and 
                $pipeworksManifest.Checkout.SmtpPasswordSetting) {
                # Email based cart, send the order along

                $emailContent = $cartCookie.Values.GetEnumerator()  |
                    Where-Object {
                        $_ -like "Item_*"
                    } |
                    Foreach-Object -Begin {
                        $items = @()
                    
                    } {
                        $itemId = $_.Replace("Item_", "")
                        $itemName, $itemPrice = $cartCookie.Values[$_] -split "\|"       
                    
                        if (-not ($itemPrice -as [Double])) {
                            if ($itemPrice.Substring(1) -as [Double]) {
                                $itemPrice = $itemPrice.Substring(1)
                            }
                        }             
                        $items+= New-Object PSObject |
                            Add-Member NoteProperty Name $itemName -passthru | 
                            Add-Member NoteProperty Price ($itemPrice -as [Double]) -passthru 
                    } -End {
                        $subtotal = $items | 
                            Measure-Object -Sum Price | 
                            Select-Object -ExpandProperty Sum
                        ($items | Out-HTML ) + 
                            "<HR/>" + 
                            ("<div style='float:right;text-align:right'><b>Subtotal:</b><br/><br/><span style='margin:5px'>$Subtotal</span></div><div style='clear:both'></div>")
                    }


                $emailAddress = Get-SecureSetting -Name $pipeworksManifest.Checkout.SmtpUserSetting
                $emailPassword = Get-SecureSetting -Name $pipeworksManifest.Checkout.SmtpPasswordSetting 

                $emailCred = New-Object Management.Automation.PSCredential ".\$emailAddress", (ConvertTo-SecureString -AsPlainText -Force $emailPassword)


                $to = $pipeworksManifest.Checkout.To -split "\|"
                Send-MailMessage -SmtpServer $pipeworksManifest.Checkout.SmtpServer -From $emailAddress -UseSsl -BodyAsHtml -Body $emailContent -Subject "Order From $from" -To $to -Credential $emailCred 
            }
        }


        $AddPurchaseHandler = $validateUserTable.ToString() + {                        
            if ($request["Rent"]) {
                $isRental = $true
                $billingFrequency = $request["BillingFrequency"]
            } else {
                $isRental = $false
                $billingFrequency = ""
            }
            if (-not ($session -and $session["User"])) {
                throw "Not Logged in"
            }
            
            if (-not ($Request -and $request["ItemName"])) {
                throw "Must Provide an ItemName"
            }
            
            if (-not ($Request -and $request["ItemPrice"])) {
                throw "Must Provide an ItemPrice"
            }
            
            $currency = "USD"
            if ($request -and $request["Currency"]) {
                $currency  = $reqeust["Currency"]
            }
            
            if (-not ($Request -and $request["ItemPrice"])) {
                throw "Must Provide an ItemPrice"
            }

            $PostPaymentParameter,$postPaymentCommand = $null
            
            if ($session["PostPaymentCommand"]) {
                
                $postPaymentCommand= $session["PostPaymentCommand"]
                if ($session["PostPaymentParameter"]) {
                    try {
                        $PostPaymentParameter= $session["PostPaymentParameter"]
                    } catch {
                    }

                }
                
            }
            
                        
            $userPart = if ($pipeworksManifest.UserTable.Partition) {
                $pipeworksManifest.UserTable.Partition
            } else {
                "Users"
            }
            
            $purchaseHistory = $userPart + "_Purchases"
            
            $purchaseId = [GUID]::NewGuid()
            
            
            $purchase = New-Object PSObject
            $purchase.pstypenames.clear()
            $purchase.pstypenames.add('http://shouldbeonschema.org/ReceiptItem')
            
            
            $purchase  = $purchase |
                Add-Member NoteProperty PurchaseId $purchaseId -PassThru |
                Add-Member NoteProperty ItemName $request["ItemName"] -PassThru |
                Add-Member NoteProperty ItemPrice $request["ItemPrice"] -PassThru |
                Add-Member NoteProperty Currency $request["Currency"] -PassThru |
                Add-Member NoteProperty OrderTime $request["OrderTime"] -PassThru |
                Add-Member NoteProperty UserID $session["User"].UserID -PassThru

            if ($postPaymentCommand) {
                $purchase = $purchase |
                    Add-Member NoteProperty PostPaymentCommand $postPaymentCommand -PassThru
            }

            if ($PostPaymentParameter) {
                $purchase  = $purchase |
                    Add-Member NoteProperty PostPaymentParameter $PostPaymentParameter -PassThru
            }
            
            $azureStorageAccount = Get-WebConfigurationSetting -Setting $pipeworksManifest.UserTable.StorageAccountSetting
            $azureStorageKey= Get-WebConfigurationSetting -Setting $pipeworksManifest.UserTable.StorageKeySetting

            $purchase | 
                Set-AzureTable -TableName $pipeworksManifest.UserTable.Name -PartitionKey $purchaseHistory -RowKey $purchaseId -StorageAccount $azureStorageAccount  -StorageKey $azureStorageKey
            
            $payLinks = ""
            $payLinks += 
                if ($pipeworksManifest.PaymentProcessing.AmazonPaymentsAccountId -and 
                    $pipeworksManifest.PaymentProcessing.AmazonAccessKey) {
                    Write-Link -ItemName $request["ItemName"] -Currency $currency -ItemPrice $request["ItemPrice"] -AmazonPaymentsAccountId $pipeworksManifest.PaymentProcessing.AmazonPaymentsAccountId -AmazonAccessKey $pipeworksManifest.PaymentProcessing.AmazonAccessKey
                }
                
            
            $payLinks += 
                if ($pipeworksManifest.PaymentProcessing.PaypalEmail) {
                    Write-Link -ItemName $request["ItemName"] -Currency $currency -ItemPrice $request["ItemPrice"] -PaypalEmail $pipeworksManifest.PaymentProcessing.PaypalEmail -PaypalIPN "${FinalUrl}?-PaypalIPN" -PaypalCustom $purchaseId -Subscribe:$isRental
                }


                
            $paypage = $payLinks | 
                New-WebPage -Title "Buy $($Request["ItemName"]) for $($Request["ItemPrice"])"  
                
            $paypage|
                Out-html -writeresponse

            if ($PipeworksManifest.Mail.SmtpServer -and
                $pipeworksManifest.Mail.SmtpUserSetting -and
                $pipeworksManifest.Mail.SmtpPasswordSetting -and
                $pipeworksManifest.Mail.From) {
                $smtpServer = $pipeworksManifest.Mail.SmtpServer
                $smtpUser = Get-WebConfigurationSetting -Setting $pipeworksManifest.Mail.SmtpUserSetting
                $smtpPassword =  Get-WebConfigurationSetting -Setting $pipeworksManifest.Mail.SmtpPasswordSetting

                $smtpCred = New-Object Management.Automation.PSCredential ".\$smtpUser",
                    (ConvertTo-SecureString -String $smtpPassword -AsPlainText -Force)

                Send-MailMessage -UseSsl -SmtpServer $smtpServer -Subject $Request["ItemName"] -Body $payPage -BodyAsHtml -Credential $smtpCred 
            }
            
        }
        
        
        
        $payPalIpnHandler =  $validateUserTable.ToString() + {
            
            $error.Clear()

            $userPart = 
                if ($pipeworksManifest.UserTable.Partition) {
                    $pipeworksManifest.UserTable.Partition
                } else {
                    "Users"
                }
            
            $purchaseHistory = $userPart + "_Purchases"                        
            $req = [Net.HttpWebRequest]::Create("https://www.paypal.com/cgi-bin/webscr") 
            # //Set values for the request back
            $req.Method = "POST";
            $req.ContentType = "application/x-www-form-urlencoded"
            
            $strRequest = $request.Form.ToString() + 
                "&cmd=_notify-validate";
            $req.ContentLength = $strRequest.Length;
 
            $parsed = [Web.HttpUtility]::ParseQueryString($strRequest)

            $streamOut = New-Object IO.StreamWriter $req.GetRequestStream()
            $streamOut.Write($strRequest);
            $streamOut.Close();
            $streamIn = New-Object IO.StreamReader($req.GetResponse().GetResponseStream());
            $strResponse = $streamIn.ReadToEnd();
            $streamIn.Close();
 
            $azureStorageAccount = Get-WebConfigurationSetting -Setting $pipeworksManifest.UserTable.StorageAccountSetting
            $azureStorageKey= Get-WebConfigurationSetting -Setting $pipeworksManifest.UserTable.StorageKeySetting
            
            
            $custom = $Request["Custom"]
            $ipnResponse = $strResponse

            $ipn = 
                New-Object PSObject -Property @{
                    Custom = "$custom"
                    Request = $strRequest 
                    IPNResponse = $ipnResponse
                    UserPart = $purchaseHistory 
                } 
            $ipn |
                Set-AzureTable -TableName $pipeworksManifest.UserTable.Name -RowKey { [GUID]::NewGuid() } -PartitionKey "PaypalIPN" -StorageAccount $azureStorageAccount -StorageKey $azureStorageKey
                

            if ($ipnResponse -eq "VERIFIED")
            {
            <#    //check the payment_status is Completed
                //check that txn_id has not been previously processed
                //check that receiver_email is your Primary PayPal email
                //check that payment_amount/payment_currency are correct
                //process payment
            #>                
                
                
                
                $filterString = "PartitionKey eq '$purchaseHistory' and RowKey eq '$($ipn.Custom)'" 
                $transactionExists = Search-AzureTable -TableName $pipeworksManifest.UserTable.Name -Filter $filterString
                
                if ($transactionExists) {
                    # Alter the user balance 
                    
                    if ($transactionExists.Processed -like "True*") {
                        # already processed, skip
                        New-Object PSObject -Property @{
                            Custom = "$custom"
                            SkippingProcessedTransaction=$true                        
                            
                        } |
                            Set-AzureTable -TableName $pipeworksManifest.UserTable.Name -RowKey { [GUID]::NewGuid() } -PartitionKey "PaypalIPN"

                        return
                    }

                    $result = " " 
                    if ($request["Payment_Status"] -ne "Completed") {
                        New-Object PSObject -Property @{
                            Custom = $custom                        
                            TransactionIncomplete = $request["Payment_Status"]
                        } |
                            Set-AzureTable -TableName $pipeworksManifest.UserTable.Name -RowKey { [GUID]::NewGuid() } -PartitionKey "PaypalIPN"
                    } else {
                        $userInfo =
                            Search-AzureTable -TableName $pipeworksManifest.UserTable.Name -Filter "PartitionKey eq '$userPart' and RowKey eq '$($transactionExists.UserID)'"
                        
                        $balance = $userInfo.Balance -as [Double]                    
                        $balance -= $request["payment_gross"] -as [Double]
                        $userInfo |
                            Add-Member NoteProperty Balance $balance -Force -PassThru | 
                            Update-AzureTable -TableName $pipeworksManifest.UserTable.Name -Value { $_ } 
                        
                        $session["User"] = $userInfo

                        if ($transactionExists.postPaymentCommand) {
                            $postPaymentCommand = Get-Command -Module $module.Name -Name "$($transactionExists.postPaymentCommand)".Trim()
                            $PostPaymentParameter = if ($transactionExists.postPaymentParameter) {
                                invoke-expression "data { $($transactionExists.postPaymentParameter) }"
                            } else {
                                @{}
                            }

                            $extra = if ($pipeworksManifest.WebCommand."$($transactionExists.postPaymentCommand)".Trim()) {
                                $pipeworksManifest.WebCommand."$($transactionExists.postPaymentCommand)".Trim()
                            } else {
                                @{}
                            }

                            if ($extra.RunWithoutInput) {
                                $null = $extra.Remove("RunWithoutInput")                                
                            }

                            if ($extra.ParameterDefaultValue) {
                                try {
                                    $postPaymentParameter += $extra.ParameterDefaultValue
                                } catch {
                                }
                                $null = $extra.Remove("ParameterDefaultValue")                                
                            }


                            if ($extra.RequireAppKey -or 
                                $extra.RequireLogin -or 
                                $extra.IfLoggedAs -or 
                                $extra.ValidUserPartition -or 
                                $extra.Cost -or 
                                $extra.CostFactor) {

                                $extra.UserTable = $pipeworksManifest.Usertable.Name
                                $extra.UserPartition = $pipeworksManifest.Usertable.Partition
                                $extra.StorageAccountSetting = $pipeworksManifest.Usertable.StorageAccountSetting
                                $extra.StorageKeySetting = $pipeworksManifest.Usertable.StorageKeySetting 

                            }

                            
                            $result = Invoke-WebCommand @extra -RunWithoutInput -PaymentProcessed -Command $postPaymentCommand -ParameterDefaultValue $PostPaymentParameter -AsEmail $userInfo.UserEmail -PlainOutput 2>&1 
                            
                        }

                        $transactionExists |
                            Add-Member NoteProperty Processed $true -Force -PassThru |
                            Add-Member NoteProperty CommandResult ($result | Out-Html) -force -passthru | 
                            Add-Member NoteProperty PayPalIpnID $request['Transacation_Subject'] -Force -PassThru |
                            Update-AzureTable -TableName $pipeworksManifest.UserTable.Name -Value { $_ } 


                        $smtpServer = $pipeworksManifest.UserTable.SmtpServer
                        if ($smtpServer) {

                        }        
                    }
                    
                    
                    
                    
                } else {
                    New-Object PSObject -Property @{
                        Custom = $custom
                        Errors = "$($error | Select-Object -First 1 | Out-String)"
                        TransactionNotFound = $true
                        Filter = $filterString 
                    } |
                        Set-AzureTable -TableName $pipeworksManifest.UserTable.Name -RowKey { [GUID]::NewGuid() } -PartitionKey "PaypalIPN"
                }
            } elseif ($strResponse -eq "INVALID") {
                # //log for manual investigation
                $strResponse
            } else {
                # //log response/ipn data for manual investigation
                
            }
        }
        
        
        $facebookConfirmUser = {
            
            
            if (-not ($pipeworksManifest.Facebook.AppId -or $pipeworksManifest.Facebook.AppIdSetting)) {
                throw 'The Pipeworks manifest must include a facebook section with an AppId or AppIdSetting'
                return
            }
            
            
            
            $fbAppId = $pipeworksManifest.Facebook.AppId
            
            if (-not $fbAppId) {
                $fbAppId= Get-WebConfigurationSetting -Setting $pipeworksManifest.Facebook.AppIdSetting
            }
            
            if (-not $fbAppId) {
                throw "No Facebook AppID found"
                return
            }
            
            
            if ($request.Params["accesstoken"]) {
                $accessToken = $request.Params["accesstoken"]
                . Confirm-Person -FacebookAccessToken $accessToken -FacebookAppId $fbAppId -WebsiteUrl $finalUrl
            } elseif ($request.Params["code"]) {
                $code = $request.Params["code"]

                $fbSecret = Get-WebConfigurationSetting -Setting $pipeworksManifest.Facebook.AppSecretSetting

                $result =Get-Web -url "https://graph.facebook.com/oauth/access_token?client_id=$fbAppId&redirect_uri=$([Web.HttpUtility]::UrlEncode("${finalUrl}?FacebookConfirmed=true"))&client_secret=$fbsecret&code=$code"

                $token = [web.httputility]::ParseQueryString($result)["access_token"]                

                . Confirm-Person -FacebookAccessToken $Token -FacebookAppId $fbAppId -WebsiteUrl $finalUrl
            }

            
            
            
            if ($request.Params["ReturnTo"]) {
                $returnUrl = [Web.HttpUtility]::UrlDecode($request.Params["ReturnTo"])
                New-WebPage -AnalyticsId "" -title "Welcome to $($module.Name)" -RedirectTo $returnUrl |
                    Out-HTML -WriteResponse
            } elseif ($Request.Params["ThenRun"]) { 
                . $getCommandExtraInfo $Request.Params["ThenRun"]

                $result = 
                    Invoke-Webcommand -Command $command @extraParams -AnalyticsId "$AnalyticsId" -AdSlot "$AdSlot" -AdSenseID "$AdSenseId" -ServiceUrl $finalUrl 2>&1
            } else {
                New-WebPage -AnalyticsId "" -title "Welcome to $($module.Name)" -RedirectTo "/" |
                    Out-HTML -WriteResponse
            }                         
        }
        
        
        $liveIdConfirmUserHandler = {
            if ($request.Params["accesstoken"]) {
                $accessToken = $request.Params["accesstoken"]
                . Confirm-Person -liveIDAccessToken $accessToken -WebsiteUrl $finalUrl
            } elseif ($request.Params["code"]) {
                $code = $request.Params["code"]

                $appId = $pipeworksManifest.LiveConnect.ClientId                
                $appSecret = Get-SecureSetting -Name $pipeworksManifest.LiveConnect.ClientSecretSetting -ValueOnly

                $redirectUri = if ($session["LiveIDRedirectURL"]) {
                    $session["LiveIDRedirectURL"]
                } elseif ($pipeworksManifest.LiveConnect.RedirectUrl) {
                    $pipeworksManifest.LiveConnect.RedirectUrl
                } else {
                    $finalUrl
                }

                
                $result =Get-Web -url "https://login.live.com/oauth20_token.srf" -RequestBody "client_id=$([Web.HttpUtility]::UrlEncode($appId))&redirect_uri=$([Web.HttpUtility]::UrlEncode($redirectUri))&client_secret=$([Web.HttpUtility]::UrlEncode($appSecret.Trim()))&code=$([Web.HttpUtility]::UrlEncode($code.Trim()))&grant_type=authorization_code" -UseWebRequest -Method POST -AsJson

                
                $token = $result.access_token
                if (-not $Token) {
                    New-Object PSObject -Property @{
                        Code = $code
                        Error = ($Error |Out-String)
                        AppId = $appId
                        Result = $result
                        RedirectUrl = $redirectUri
                    } | Out-HTML -WriteResponse
                } else {
                    if ($response.Cookies) {
                        $confirmCookie = New-Object Web.HttpCookie ("LiveConnectCode_For_$($pipeworksManifest.LiveConnect.ClientID)", $code)
                        $confirmCookie.Expires = (Get-Date).AddMinutes(15)                    
                        $response.Cookies.Add($confirmCookie)                    
                    }
                    . Confirm-Person -LiveIDAccessToken $token -WebsiteUrl $finalUrl 
                }
            }


            if ($session["User"]) {
                if ($request.Params["ReturnTo"]) {
                    $returnUrl = [Web.HttpUtility]::UrlDecode($request.Params["ReturnTo"])
                    New-WebPage -AnalyticsId "" -title "Welcome to $($module.Name)" -RedirectTo $returnUrl |
                        Out-HTML -WriteResponse
                } elseif ($Request.Params["ThenRun"]) { 
                    . $getCommandExtraInfo $Request.Params["ThenRun"]

                    $result = 
                        Invoke-Webcommand -Command $command @extraParams -AnalyticsId "$AnalyticsId" -AdSlot "$AdSlot" -AdSenseID "$AdSenseId" -ServiceUrl $finalUrl 2>&1

                    if ($result) {
                        $result |
                            New-WebPage
                    }
                } else {
                    New-WebPage -AnalyticsId "" -title "Welcome to $($module.Name)" -RedirectTo "/" |
                        Out-HTML -WriteResponse
                }
            }

            
        }             
        
        
        #region Facebook Login Chunk
        $facebookLoginDisplay = {
            if (-not ($pipeworksManifest.Facebook.AppId -or $pipeworksManifest.Facebook.AppIdSetting)) {
                throw 'The Pipeworks manifest must include a facebook section with an AppId or AppIdSetting'
                return
            }
            
            
            
            $fbAppId = $pipeworksManifest.Facebook.AppId
            
            if (-not $fbAppId) {
                $fbAppId= Get-WebConfigurationSetting -Setting $pipeworksManifest.Facebook.AppIdSetting
            }
            
            if (-not $fbAppId) {
                throw "No Facebook AppID found"
                return
            }
            
            #if (-not $pipew
            $scope = if ($pipeworksManifest -and $pipeworksManifest.Facebook.Scope) {
                @($pipeworksManifest.Facebook.Scope) + "email" | 
                    Select-Object -Unique
            } else {
                "email"
            }
            
            
            $response.Write(("$(Write-Link -ToFacebookLogin -FacebookAppId $fbAppId -FacebookLoginScope $scope |
    New-WebPage -Title "Login with Facebook")"))
            
                       
        }        
        #endregion                
        
        #region MailHandler
        $mailHandler = {
            $to = $request["To"]
            $from = $Request["From"]
            $replyTo = $request["Replyto"]
            $body = $Request["Body"]
            $subject= $Request["Subject"]
            $useSsl = -not $pipeworksManifest.Mail.DoNotUseSsl
            $smtpServer = $pipeworksManifest.Mail.SmtpServer
            $smtpUser = Get-WebConfigurationSetting -Setting $pipeworksManifest.Mail.SmtpUserSetting
            $smtpPassword =  Get-WebConfigurationSetting -Setting $pipeworksManifest.Mail.SmtpPasswordSetting
            
            if (-not $pipeworksManifest.Mail.CanSendTo) {
                throw "Must add a CanSendTo list to the mail section" 
                
            }
            
            $canSend = $false
            foreach ($couldSendTo in $pipeworksManifest.Mail.CanSendTo) {
                if ($to -like $couldSendto) {
                    $canSend = $true
                }
                
            }
            
            if (-not $canSend) {
                throw "Cannot send mail to $to"
            }
            
            $smtpCred = New-Object Management.Automation.PSCredential ".\$smtpUser",
                (ConvertTo-SecureString -String $smtpPassword -AsPlainText -Force)
                
            $emailParams = @{
                From=$from
                To=$To
                Body=$body+"
----
Reply To:$replyTo 
"                 
                             
                Subject=$subject
                UseSsl=$useSsl
                SmtpServer=$smtpServer
                Credential=$smtpCred            
            }
            Send-MailMessage @emailParams
            
            
            $redirectto = $Request["RedirectTo"]
            if ($redirectTo){
                New-WebPage -RedirectTo $redirectTo | Out-HTML -WriteResponse
            }
        }
        #endregion MailHandler
        
        $tableItemProcess = {
            $BeginTableItem = {
                $itemsToShow = @()
            }
            $endTableItem = {
                $itemsToShow | Out-HTML -WriteResponse
            } 
            
            $ProcessEachTableItem = {
                # If there's a content type, set the response's content type to match                
                
                if ($_.RequireSessionHandShake -and 
                    -not $session[$_.RequireSessionHandShake]) {
                    throw "Required Session Handshake is not present $($_.RequireSessionHandShake)"
                    return
                }
                
                if ($_.ExpirationDate -and (
                    [DateTime]::Now -gt $_.ExpirationDate)) {
                    throw "Content is Expired"
                    return
                }
                
                # Unpack any properties on the item without spaces (or try)
                . $unpackItem
                
                if ($Request['LinkOnly']) {
                    $item = Write-Link -Caption Name -Url $item.Url
                }
                if ($_.ContentType) {
                    $response.ContentType = $_.ContentType
                }
                if ($_.Bytes) {                    
                    $response.BufferOutput = $true
                    $response.BinaryWrite([Convert]::FromBase64String($_.Bytes))
                    $response.Flush()                        
                } elseif ($_.Xml) {
                    $strWrite = New-Object IO.StringWriter
                    ([xml]($_.Xml)).Save($strWrite)
                    $resultToOutput  = "$strWrite" -replace "encoding=`"utf-16`"", "encoding=`"utf-8`""
                    if (-not $cmdOptions.ContentType) {
                        $response.ContentType ="text/xml"
                    }
                    $response.Write("$resultToOutput")    
                } elseif ($_.Html) {                    
                    $itemsToShow += $_.Html
                } else {
                    $itemsToShow += $_                    
                }                                                
                
                if ($_.TimesViewed) {
                    $timesViewed = [int]$_.TimesViewed + 1
                    $putItBack = $_
                    $rowKey = $_.psobject.properties['RowKey']
                    $_.psobject.properties.Remove('RowKey')
                    $partitionKey = $_.psobject.properties['PartitionKey']                    
                    $_.psobject.properties.Remove('PartitionKey')
                    $tableName= $_.psobject.properties['TableName']
                    $_.psobject.properties.Remove('TableName')
                    $putItBack | Add-Member NoteProperty TimesViewed $timesViewed -Force
                    $putItBack | Update-AzureTable -TableName $tableName -PartitionKey $partitionKey -RowKey $rowKey
                }
            }
        }
        
        
        #region SearchHandler                        
        $SearchHandler = $embedUnpackItem + $tableItemProcess.ToString() + {
            if (-not ($pipeworksManifest.Table -and $pipeworksManifest.Table.StorageAccountSetting -and $pipeworksManifest.Table.StorageKeySetting)) {
                throw 'The Pipeworks manifest must include three settings in order to retrieve items from table storage: Table, TableStorageAccountSetting, and TableStorageKeySetting'
                return
            }
            $storageAccount = (Get-WebConfigurationSetting -Setting $pipeworksManifest.Table.StorageAccountSetting)
            $storageKey = (Get-WebConfigurationSetting -Setting $pipeworksManifest.Table.StorageKeySetting)
            
            $lastSearchTime = $application["KeywordSearchTime_$($request['Search'])"]
            $lastResults = $application["SearchResults_$($request['Search'])"]
            
            # If the PipeworksManifest is going to index table data, then load this up rather than query                        
            if ($pipeworksManifest.Table.IndexBy) {
                if (-not $pipeworksManifest.Table.SqlAzureConnectionSetting) {
                    Write-Error "Modules that index tables must also declare a SqlAzureConnectionString within the table"
                    return
                }
                            
                $connectionString = Get-WebConfigurationSetting -Setting $pipeworksManifest.Table.SqlAzureConnectionSetting
                $sqlConnection = New-Object Data.SqlClient.SqlConnection "$connectionString"
                $sqlConnection.Open()
                
                $matchSql = @(foreach ($indexTerm in $pipeworksManifest.Table.IndexBy) {
                    "$indexTerm like '%$($request['search'].Replace("'","''"))%'" 
                }) -join ' or ' 
                                                
                $searchSql = "select id from $($pipeworksManifest.Table.Name) where $matchSql"
                
                
                $sqlAdapter= new-object "Data.SqlClient.SqlDataAdapter" ($searchSql, $sqlConnection)
                $sqlAdapter.SelectCommand.CommandTimeout = 0
                $dataSet = New-Object Data.DataSet 
                $null = $sqlAdapter.Fill($dataSet)
                $allIds = @($dataSet.Tables | Select-Object -ExpandProperty Rows | Select-Object -ExpandProperty Id)
                foreach ($id in $allIds) {
                    if (-not $id) { 
                        continue 
                    } 
                    $part,$row = $id -split ":"
                    
                    Get-AzureTable -TableName $pipeworksManifest.Table.Name -Row $row.Trim() -Partition $part.Trim() -StorageAccount $storageAccount -StorageKey $storageKey| 
                        ForEach-Object -Begin $BeginTableItem -Process $ProcessEachTableItem -End $EndTableItem
                }
                
            
            } else {
                Search-AzureTable -TableName $pipeworksManifest.Table.Name -Select Name, Description, Keyword, PartitionKey, RowKey -StorageAccount $storageAccount -StorageKey $storageKey |
                ForEach-Object $UnpackItem |
                Where-Object {                    
                    ($_.Name -ilike "*$($request['Search'])*") -or
                    ($_.Description -ilike "*$($request['Search'])*") -or
                    ($_.Keyword -ilike "*$($request['Search'])*") -or
                    ($_.Keywords -ilike "*$($request['Search'])*")                                      
                } |
                
                Get-AzureTable -TableName $pipeworksManifest.Table.Name | 
                    ForEach-Object -Begin $BeginTableItem -Process $ProcessEachTableItem -End $EndTableItem
                
            }
            
            if (-not $lastResults) {                      
                if (-not $application['TableIndex'] -or (-not $pipeworksManifest.Table.IndexBy)) {
                    # If theres' not an index, or the manifest does not build one, search the table
                    $application['TableIndex'] = 
                        Search-AzureTable -TableName $pipeworksManifest.Table.Name -Select Name, Description, Keyword, PartitionKey, RowKey -StorageAccount $storageAccount -StorageKey $storageKey
                }
                                                                
            } else {
                $lastResults | 
                    ForEach-Object -Begin $BeginTableItem -Process $ProcessEachTableItem -End $EndTableItem
            }
        }
        #endregion
        
        #region NameHandler
        $nameHandler = $tableItemProcess.ToString() + $embedUnpackItem + {
            if (-not ($pipeworksManifest.Table -and $pipeworksManifest.Table.StorageAccountSetting -and $pipeworksManifest.Table.StorageKeySetting)) {
                throw 'The Pipeworks manifest must include three settings in order to retrieve items from table storage: Table, TableStorageAccountSetting, and TableStorageKeySetting'
                return
            }
            $storageAccount = (Get-WebConfigurationSetting -Setting $pipeworksManifest.Table.StorageAccountSetting)
            $storageKey = (Get-WebConfigurationSetting -Setting $pipeworksManifest.Table.StorageKeySetting)
            $nameMatch  =([ScriptBLock]::Create("`$_.Name -eq '$($request['name'])'"))
            Search-AzureTable -Where $nameMatch -TableName $pipeworksManifest.Table.Name -StorageAccount $storageAccount -StorageKey $storageKey | 
                ForEach-Object -Begin $BeginTableItem -Process $ProcessEachTableItem -End $EndTableItem
        }
        #endregion
        
               
        #region LatestHandler
        $latestHandler = $tableItemProcess.ToString() + $embedUnpackItem +  {
            $PartitionKey = $request['Latest']
        } + $refreshLatest + {
            $latest |                 
                ForEach-Object -Begin $BeginTableItem -Process $ProcessEachTableItem -End $EndTableItem
        } 
        #endregion LatestHandler 
        
        #region RssHandler
        $rssHandler = $embedUnpackItem + {
            $PartitionKey = $request['Rss']
        } + $refreshLatest.ToString() + {
            if (-not ($pipeworksManifest.Table -and $pipeworksManifest.Table.StorageAccountSetting -and $pipeworksManifest.Table.StorageKeySetting)) {
                throw 'The Pipeworks manifest must include three settings in order to retrieve items from table storage: Table, TableStorageAccountSetting, and TableStorageKeySetting'
                return
            }
            $storageAccount = (Get-WebConfigurationSetting -Setting $pipeworksManifest.Table.StorageAccountSetting)
            $storageKey = (Get-WebConfigurationSetting -Setting $pipeworksManifest.Table.StorageKeySetting)            
            $finalSite = $finalUrl.ToString().Substring(0,$finalUrl.ToString().LastIndexOf("/"))

            $blogName = 
                if ($pipeworksManifest.Blog.Name) {
                    $pipeworksManifest.Blog.Name
                } else {
                    $module.Name
                }
                
            $blogDescription = 
                if ($pipeworksManifest.Blog.Description) {
                    $pipeworksManifest.Blog.Description
                } else {
                    $module.Description
                }
                
            $syncTime = [Datetime]::Now - [Timespan]"0:20:0"
            if (-not ($session["RssFeed$($blogName)LastSyncTime"] -ge $syncTime)) {
                $session["RssFeed$($blogName)"] = $null
            }
           

            if (-not $session["RssFeed$($blogName)"]) {
            
                $feedlength = if ($pipeworksManifest.Blog.FeedLength -as [int]) {
                    $pipeworksManifest.Blog.FeedLength -as [int]
                } else {
                    25
                }
                
                if ($feedLength -eq -1 ) { $feedLength = [int]::Max } 
                
                $getDateScript = {
                    if ($_.DatePublished) {
                        [DateTime]$_.DatePublished
                    } elseif ($_.TimeCreated) {
                        [DateTime]$_.TimeCreated
                    } elseif ($_.TimeGenerated) {
                        [DateTime]$_.TimeGenerated
                    } elseif ($_.Timestamp) {
                        [DateTime]$_.Timestamp
                    } else {
                        Get-Date
                    }
                }
                
                $rssFeed = 
                    Search-AzureTable -TableName $pipeworksManifest.Table.Name -Filter "PartitionKey eq '$PartitionKey'" -Select Timestamp, DatePublished, PartitionKey, RowKey -StorageAccount $storageAccount -StorageKey $storageKey |
                    Sort-Object $getDateScript -Descending  |
                    Select-Object -First $feedlength | 
                    Get-AzureTable -TableName $pipeworksManifest.Table.Name |
                    ForEach-Object $UnpackItem |
                    New-RssItem -Title  {
                        if ($_.Name) {                    
                            $_.Name
                        } else {
                            ' '
                        }
                    } -DatePublished $getDateScript -Author { 
                        if ($_.Author) { $_.Author} else { ' '  } 
                    } -Url {
                        if ($_.Url) {
                            $_.Url
                        } else {
                            "$($finalSite.TrimEnd('/') + '/')?post=$($_.Name)"
                        }
                    } |                 
                    Out-RssFeed -Title $blogName -Description $blogDescription -ErrorAction SilentlyContinue -Link $finalSite                 
                $session["RssFeed$($blogName)"] = $rssFeed
                $session["RssFeed$($blogName)LastSyncTime"]  = Get-Date
            } else {
                $rssFeed = $session["RssFeed$($blogName)"]
            }
            
            $response.ContentType = 'text/xml'
            $response.Write($rssFeed)
        }
        #endregion RssHandler
        
        #region TypeHandler
        $typeHandler = $tableItemProcess.ToString() + $embedUnpackItem +{
            if (-not ($pipeworksManifest.Table -and $pipeworksManifest.Table.StorageAccountSetting -and $pipeworksManifest.Table.StorageKeySetting)) {
                throw 'The Pipeworks manifest must include three settings in order to retrieve items from table storage: Table, TableStorageAccountSetting, and TableStorageKeySetting'
                return
            }
            $storageAccount = (Get-WebConfigurationSetting -Setting $pipeworksManifest.Table.StorageAccountSetting)
            $storageKey = (Get-WebConfigurationSetting -Setting $pipeworksManifest.Table.StorageKeySetting)
            $nameMatch  =([ScriptBLock]::Create("`$_.psTypeName -eq '$($request['Type'])'"))
            Search-AzureTable -Where $nameMatch -TableName $pipeworksManifest.Table.Name -StorageAccount $storageAccount -StorageKey $storageKey | 
                ForEach-Object -Begin $BeginTableItem -Process $ProcessEachTableItem -End $EndTableItem
        }
        #endregion TypeHandler
                
        


        #region IdHandler
        $idHandler = $tableItemProcess.ToString() + $embedUnpackItem + {
            if (-not ($pipeworksManifest.Table -and $pipeworksManifest.Table.StorageAccountSetting -and $pipeworksManifest.Table.StorageKeySetting)) {
                throw 'The Pipeworks manifest must include three settings in order to retrieve items from table storage: Table, TableStorageAccountSetting, and TableStorageKeySetting'
                return
            }
            
            $partition, $row = $request['id'] -split ':'       
                             
            <#$rowMatch= [ScriptBLock]::Create("`$_.RowKey -eq '$row'")
            $partitionMatch = [ScriptBLock]::Create("`$_.PartitionKey -eq '$partition'")
            #>
            $storageAccount = (Get-WebConfigurationSetting -Setting $pipeworksManifest.Table.StorageAccountSetting)
            $storageKey = (Get-WebConfigurationSetting -Setting $pipeworksManifest.Table.StorageKeySetting)
            Search-AzureTable -TableName $pipeworksManifest.Table.Name -StorageAccount $storageAccount -StorageKey $storageKey -Filter "RowKey eq '$row' and PartitionKey eq '$partition'" |
                ForEach-Object -Begin $BeginTableItem -Process $ProcessEachTableItem -End $EndTableItem
            
             
            
        }
        #endregion              

                
        #region PrivacyPolicyHandler

        $privacyPolicyHandler = {
$siteUrl = $finalUrl.ToString().Substring(0, $finalUrl.LastIndexOf("/")) + "/"
$OrgInfo = if ($module.CompanyName) {
    $module.CompanyName
} elseif ($pipeworksManifest.Organization.Name) {
    $pipeworksManifest.Organization.Name
} else {
    " THE COMPANY"
}

$policy = if ($pipeworksManifest.PrivacyPolicy) {
    $pipeworksManifest.PrivacyPolicy    
} else {

@"
<!-- START PRIVACY POLICY CODE -->
<div style="font-family:arial">
  <strong>What information do we collect?</strong>
  <br />
  <br />
We ( $OrgInfo ) collect information from you when you register on our site ( $siteUrl ) or place an order.  <br /><br />
When ordering or registering on our site, as appropriate, you may be asked to enter your: name, e-mail address or phone number. You may, however, visit our site anonymously.<br /><br />
Google, as a third party vendor, uses cookies to serve ads on your site.
Google's use of the DART cookie enables it to serve ads to your users based on their visit to your sites and other sites on the Internet.
Users may opt out of the use of the DART cookie by visiting the Google ad and content network privacy policy..<br /><br /><strong>What do we use your information for?</strong><br /><br />
Any of the information we collect from you may be used in one of the following ways: <br /><br />
<br/>
 To personalize your experience<br />
(your information helps us to better respond to your individual needs)<br /><br />
<br/>
To improve our website<br />
(we continually strive to improve our website offerings based on the information and feedback we receive from you)<br /><br />
<br/>
To improve customer service<br />
(your information helps us to more effectively respond to your customer service requests and support needs)<br /><br />
<br/>
To process transactions<br /><blockquote>Your information, whether public or private, will not be sold, exchanged, transferred, or given to any other company for any reason whatsoever, without your consent, other than for the express purpose of delivering the purchased product or service requested.</blockquote><br />
<br/>To send periodic emails<br /><blockquote>The email address you provide for order processing, may be used to send you information and updates pertaining to your order, in addition to receiving occasional company news, updates, related product or service information, etc.</blockquote><br /><br /><strong>How do we protect your information?</strong><br /><br />
We offer the use of a secure server. All supplied sensitive/credit information is transmitted via Secure Socket Layer (SSL) technology and then encrypted into our Payment gateway providers database only to be accessible by those authorized with special access rights to such systems, and are required to?keep the information confidential.<br /><br />
After a transaction, your private information (credit cards, social security numbers, financials, etc.) will not be stored on our servers.<br /><br /><strong>Do we use cookies?</strong><br /><br />
Yes (Cookies are small files that a site or its service provider transfers to your computers hard drive through your Web browser (if you allow) that enables the sites or service providers systems to recognize your browser and capture and remember certain information<br /><br />
 We use cookies to help us remember and process the items in your shopping cart, understand and save your preferences for future visits and keep track of advertisements and .<br /><br /><strong>Do we disclose any information to outside parties?</strong><br /><br />
We do not sell, trade, or otherwise transfer to outside parties your personally identifiable information. This does not include trusted third parties who assist us in operating our website, conducting our business, or servicing you, so long as those parties agree to keep this information confidential. We may also release your information when we believe release is appropriate to comply with the law, enforce our site policies, or protect ours or others rights, property, or safety. However, non-personally identifiable visitor information may be provided to other parties for marketing, advertising, or other uses.<br /><br /><strong>Third party links</strong><br /><br />
 Occasionally, at our discretion, we may include or offer third party products or services on our website. These third party sites have separate and independent privacy policies. We therefore have no responsibility or liability for the content and activities of these linked sites. Nonetheless, we seek to protect the integrity of our site and welcome any feedback about these sites.<br /><br /><strong>California Online Privacy Protection Act Compliance</strong><br /><br />
Because we value your privacy we have taken the necessary precautions to be in compliance with the California Online Privacy Protection Act. We therefore will not distribute your personal information to outside parties without your consent.<br /><br /><strong>Online Privacy Policy Only</strong><br /><br />
This online privacy policy applies only to information collected through our website and not to information collected offline.<br /><br /><strong>Your Consent</strong><br /><br />
By using our site, you consent to our web site privacy policy.<br /><br /><strong>Changes to our Privacy Policy</strong><br /><br />
If we decide to change our privacy policy, we will post those changes on this page.


Hope this Helps,

$OrgInfo
"@        
}

            $response.Write("$policy")    
            return
        }
        #endregion 

        #region Anything Handler
        $anythingHandler = $tableItemProcess.ToString() + $embedUnpackItem + {        
            
            
            # Determine the Relative Path, Full URL, and Depth
                        
            # First, parse and chunk the full path, so we can see what to do with it
            <#
            if ($request -and 
                $request.Params -and 
                $request.Params["HTTP_X_ORIGINAL_URL"]) {
                
                
                $originalUrl = $context.Request.ServerVariables["HTTP_X_ORIGINAL_URL"]
                $urlString = $request.Url.ToString().TrimEnd("/")
                $pathInfoUrl = $urlString.Substring(0, 
                    $urlString.LastIndexOf("/"))
                                                                
                $protocol = ($request['Server_Protocol'].Split("/", 
                    [StringSplitOptions]"RemoveEmptyEntries"))[0] 
                $serverName= $request['Server_Name']                     
                
                $port=  $request.Url.Port
                if (($Protocol -eq 'http' -and $port -eq 80) -or
                    ($Protocol -eq 'https' -and $port -eq 443)) {
                    $fullOriginalUrl = $protocol+ "://" + $serverName + $originalUrl 
                } else {
                    $fullOriginalUrl = $protocol+ "://" + $serverName + ':' + $port + $originalUrl 
                }
                                                                
                $rindex = $fullOriginalUrl.IndexOf($pathInfoUrl, [StringComparison]"InvariantCultureIgnoreCase")
                $relativeUrl = $fullOriginalUrl.Substring(($rindex + $pathInfoUrl.Length))
                $rootUrl = $fullOriginalUrl.Substring(0, $pathInfoUrl.Length)
                if ($relativeUrl -like "*/*") {
                    $depth = @($relativeUrl -split "/" -ne "").Count - 1                    
                    if ($fullOriginalUrl.EndsWith("/")) { 
                        $depth++
                    }                                        
                } else {
                    $depth  = 0
                }
                
            }   
            #>                    
                                


            # Create a Social Row (Facebook Likes, Google +1, Twitter)
            $socialArea = ""

            if (-not $antiSocial) {
                if ($pipeworksManifest -and $pipeworksManifest.Facebook.AppId) {
                    $socialArea +=  
                        
                        (Write-Link "facebook:like" )  
                        
                }
                if ($pipeworksManifest -and ($pipeworksManifest.GoogleSiteVerification -or $pipeworksManifest.AddPlusOne)) {
                    $socialArea += 
                        
                        (Write-Link "google:plusone" )
                        
                }
                if ($pipeworksManifest -and $pipeworksManifest.ShowTweet) {
                    $socialArea += 
                        
                        (Write-Link "twitter:tweet" ) 
                        
                } elseif ($pipeworksManifest -and ($pipeworksManifest.TwitterId)) {
                    $socialArea += 
                        
                        (Write-Link "twitter:tweet" ) 
                        
                    $socialArea += 
                        
                        (Write-Link "twitter:follow@$($pipeworksManifest.TwitterId.TrimStart('@'))" )
                        
                }
            }
                     
            
            $relativeUrlParts = @($relativeUrl.Split("/", [StringSplitOptions]"RemoveEmptyEntries"))
            $linkUrl = "$FinalUrl".Substring(0, "$FinalUrl".LastIndexOf("/"))
            $titleArea = 
                if ($PipeworksManifest -and $pipeworksManifest.Logo) {
                    "<a href='$linkUrl'><img src='$($pipeworksManifest.Logo)' alt='$($module)' style='border:0' /></a>"
                } else {
                    "<a href='$linkUrl'>" + $Module.Name + "</a>"
                }             

            $descriptionArea = 
"
            $($module.Description -ireplace "`n", "<br/>")
"    


            $rest = ""

            if ($relativeUrlParts.Count -ge 1) {
                # If it's a command, invoke the command
                $found = $false

                $plainOutput = $false
                $part = $RelativeUrlParts[0]
                if ($module.ExportedFunctions.$part -or 
                    $module.ExportedAliases.$part -or 
                    $module.ExportedCmdlets.$part -or (
                    (-not $pipeworksManifest.IgnoreBuiltInCommand) -and 
                    $ExecutionContext.SessionState.InvokeCommand.GetCommand("$part", "Alias,Function,Cmdlet") | Select-Object -First 1
                    )) {
                    
                    $found = $true
                    if ($module.ExportedAliases.$part) {
                        $command = $module.ExportedAliases.$part
                    } elseif ($module.ExportedFunctions.$part) {
                        $command = $module.ExportedFunctions.$part
                    } elseif ($module.ExportedCmdlets.$part) {
                        $command = $module.ExportedCmdlets.$part
                    } elseif (-not $pipeworksManifest.IgnoreBuiltInCommand) {
                        $command = $ExecutionContext.SessionState.InvokeCommand.GetCommand("$part", "Alias,Function,Cmdlet") | Select-Object -First 1
                    }

                    # The display name of the command.  By default, the alias or the command
                    $displayedCommand = "$command"
                    
                    if ($command.ResolvedCommand) {
                        $command = $command.ResolvedCommand
                    }


                    #$titleArea = $displayedCommand
                    
                    if ($command) {
                        $found = $true
                    }
                    $commandDescription  = ""                        
                    $commandHelp = Get-Help $command -ErrorAction SilentlyContinue | Select-Object -First 1 
                    if ($commandHelp.Description) {
                        $commandDescription = $commandHelp.Description[0].text
                        $commandDescription = $commandDescription -replace "`n", ([Environment]::NewLine) 
                    }
                    

                    $descriptionArea = "                    
                    <div style='font-size:.66em;margin-top:1%;margin-left:3%;vertical-align:middle'>
                        $(ConvertFrom-Markdown -Markdown "$commandDescription ")
                    </div>
                    "
                    $extraParams = if ($pipeworksManifest -and $pipeworksManifest.WebCommand.($Command.Name)) {                
                        @{} + $pipeworksManifest.WebCommand.($Command.Name)
                    } elseif ($pipeworksManifest -and $pipeworksManifest.WebAlias.($Command.Name) -and
                        $pipeworksManifest.WebCommand.($pipeworksManifest.WebAlias.($Command.Name).Command)) { 
                
                        $webAlias = $pipeworksManifest.WebAlias.($Command.Name)
                        $paramBase = $pipeworksManifest.WebCommand.($pipeworksManifest.WebAlias.($Command.Name).Command)
                        foreach ($kv in $webAlias.GetEnumerator()) {
                            if (-not $kv) { continue }
                            if ($kv.Key -eq 'Command') { continue }
                            $paramBase[$kv.Key] = $kv.Value
                        }

                        @{} + $paramBase
                    } else { @{
                        ShowHelp = $true
                    } }             
                    
                    if ($pipeworksManifest -and $pipeworksManifest.Style -and (-not $extraParams.Style)) {
                        $extraParams.Style = $pipeworksManifest.Style 
                    }


                    # Change the display name of the command has a friendly name
                    if ($extraParams.FriendlyName) {
                        $displayedCommand = $extraParams.FriendlyName
                    }


                    if ($extraParams.Count -gt 1) {
                        # Very explicitly make sure it's there, and not explicitly false
                        if (-not $extra.RunOnline -or 
                            $extraParams.Contains("RunOnline") -and $extaParams.RunOnline -ne $false) {
                            $extraParams.RunOnline = $true                     
                        }                
                    } 
                    
                    if ($extaParams.PipeInto) {
                        $extaParams.RunInSandbox = $true
                    }
                    
                    if (-not $extraParams.AllowDownload) {
                        $extraParams.AllowDownload = $allowDownload
                    }
                    
                    if ($extraParams.RunOnline) {
                        # Commands that can be run online
                        $webCmds += $command.Name
                    }
                    
                    if ($extraParams.RequireAppKey -or 
                        $extraParams.RequireLogin -or 
                        $extraParams.IfLoggedAs -or 
                        $extraParams.ValidUserPartition -or 
                        $extraParams.Cost -or 
                        $extraParams.CostFactor) {

                        $extraParams.UserTable = $pipeworksManifest.UserTable.Name
                        $extraParams.UserPartition = $pipeworksManifest.UserTable.Partition
                        $extraParams.StorageAccountSetting = $pipeworksManifest.Usertable.StorageAccountSetting
                        $extraParams.StorageKeySetting = $pipeworksManifest.Usertable.StorageKeySetting 

                    }
                    
                    if ($extraParams.AllowDownload) {
                        # Downloadable Commands
                        $downloadableCommands += $command.Name                
                    }
                                
                    
                    
                    
                    
                    if ($MarginPercentLeftString -and (-not $extraParams.MarginPercentLeft)) {
                        $extraParams.MarginPercentLeft = $MarginPercentLeftString.TrimEnd("%")
                    }
                    
                    if ($MarginPercentRightString-and -not $extraParams.MarginPercentRight) {
                        $extraParams.MarginPercentRight = $MarginPercentRightString.TrimEnd("%")
                    }
                                            
        
                    if ($relativeUrlParts.Count -gt 1 ) {
                        $commandMetaData = $command -as [Management.Automation.CommandMetadata]
                        
                        $hideParameter = if ($extraParams.HideParameter) {
                            @($extraParams.HideParameter )
                        } else {
                            @()
                        }

                        
                        
                        $allowedParameter  = $CommandMetaData.Parameters.Keys 
            
                        # Remove the denied parameters    
                        $allParameters = foreach ($param in $allowedParameter) {
                            if ($hideParameter -notcontains $param) {
                                $param
                            }
                        }
            
                        $order = 
                             @($allParameters| 
                                Select-Object @{
                                    Name = "Name"
                                    Expression = { $_ }
                                },@{
                                    Name= "NaturalPosition"
                                    Expression = { 
                                        $p = @($commandMetaData.Parameters[$_].ParameterSets.Values)[0].Position
                                        if ($p -ge 0) {
                                            $p
                                        } else { 1gb }                                              
                                    }
                                } |
                                Where-Object {                                   
                                    $_.NaturalPosition -ne 1gb                                     
                                } |
                                Sort-Object NaturalPosition| 
                                Select-Object -ExpandProperty Name)
                        $cmdPart, $orderedParams = @($relativeUrlParts |
                            Where-Object {
                                -not "$_".Contains("?")
                            })
                        
                        if (-not $extraParams.ParameterDefaultValue) {
                             $extraParams.ParameterDefaultValue = @{}
                        }
                        if ($orderedParams) {
                            $orderedParams = @($orderedParams)
                            $lastParameter = $null
                            for ($n =0 ;$n -lt $orderedParams.Count;$n++) {                                                                

                                $ParameterValue = [Web.HttpUtility]::UrlDecode($orderedParams[$n])
                                
                                if ($n -ge $order.Count) {
                                    $acceptsRemainingArguments = $command.Parameters.$($order[$order.Count -1]).Attributes | 
                                        Where-Object {$_.ValueFromRemainingArguments } 
                                    if ($acceptsRemainingArguments) {
                                        if ($command.Parameters.$($order[$order.Count -1]).ParameterType.IsSubclassOf([Array])) {
                                            $extraParams.ParameterDefaultValue.($order[$order.Count -1]) = @($extraParams.ParameterDefaultValue.($order[$order.Count -1])) + $parameterValue
                                        } elseif ($command.Parameters.$($order[$order.Count -1]).ParameterType -is [ScriptBlock]) {
                                            $extraParams.ParameterDefaultValue.($order[$order.Count -1]) = [ScriptBlock]::Create(($extraParams.ParameterDefaultValue.($order[$order.Count -1])).ToString() + $parameterValue)
                                        } else {
                                            $extraParams.ParameterDefaultValue.($order[$order.Count -1]) += $ParameterValue
                                        }
                                        
                                    }
                                    #$command.Parameter.$($order[$n])
                                } else {
                                    $extraParams.ParameterDefaultValue.($order[$n]) = $ParameterValue
                                    
                                    if ($command.Parameters.($order[$n]).ParameterType -eq 
                                        [ScriptBlock]) {
                                        $extraParams.ParameterDefaultValue.($order[$n]) =
                                            [ScriptBlock]::Create($extraParams.ParameterDefaultValue.($order[$n]))
                                    }
                                }

                                if ($extraParams.ParameterDefaultValue.Count) {
                                    $extraParams.RunWithoutInput = $true
                                }                                
                            }
                        }
                        
                        
                    }
                    

                    if ($extraParams.DefaultParameter -and $extraParams.ParameterDefaultValue) {
                        # Reconcile aliases


                        $combinedTable = @{}
                        foreach ($kv in $extraParams.ParameterDefaultValue.GetEnumerator()) {
                            $combinedTable[$kv.Key] = $kv.Value
                        }
                        foreach ($kv in $extraParams.DefaultParameter.GetEnumerator()) {
                            $combinedTable[$kv.Key] = $kv.Value                            
                        }

                        $null = $extraParams.Remove('DefaultParameter')
                        $extraParams['ParameterDefaultValue'] = $combinedTable
                    }
                                        


                                            

                    $result = 
                        try {
                            Invoke-Webcommand -Command $command @extraParams -AnalyticsId "$AnalyticsId" -AdSlot "$AdSlot" -AdSenseID "$AdSenseId" -ServiceUrl $finalUrl 2>&1
                        } catch {
                            $_        
                        }
                    
                    # If it's not HTML or XML, but contains tags, then render it in a page with JQueryUI
                    $rest = $result


                    if ($result) {
                        if ($result -is [Management.Automation.ErrorRecord]) {
                            $result = "$($result | Out-String -Width 10kb)"
                        } elseif ($result -is [Exception]) {
                            $result = "$($result | Out-String -Width 10kb)"
                        }

                        
                        if ($Request.params["AsRss"] -or 
                            $Request.params["AsCsv"] -or
                            $Request.params["AsXml"] -or
                            $Request.Params["bare"] -or 
                            $extraParams.ContentType -or
                            $extraParams.PlainOutput) {
                            
                            $ifTemplateFound = @{}
                            if ($pipeworksManifest.CommandTemplate) {
                                $ifTemplateFound.Template =$pipeworksManifest.CommandTemplate
                            } elseif ($pipeworksManifest.DefaultTemplate) {
                                $ifTemplateFound.Template =$pipeworksManifest.DefaultTemplate
                            } elseif ($pipeworksManifest.Template) {
                                $ifTemplateFound.Template =$pipeworksManifest.Template
                            }


                            $realOrder = @()
                            $navBarData = @{}
                            $navBarOrder = @{}
                            $navBarUrls = @{}
                            $cmdTabs = @{}
                            $cmdUrls = @{}

                            
                            if (((-not $extraParams.ContentType)) -or (
                                $extraParams.ContentType -notlike "text*" -and 
                                $result -is [string]
                                ) -or (
                                $extraParams.ContentType -eq "text/html" -and 
                                $result -like "*class=?$($command)*"
                                ) -or (
                                $result -is [string] -and
                                $result -like "*class=?$($command)*"
                                )) {
                                # If it's not HTML or XML, but contains tags, then render it in a page with JQueryUI
                                $rest = $result

                                . $getGroups -NavBarOnly

                                . $getBanners


                                $navBarHtml = if ($navBarData -and $PipeworksManifest.UseBootstrap) {
    
    
    New-Region -LayerID "MainNavBar" -Layer $navBarData -AsNavbar -Style @{"float"="right"} -Order $realOrder -LayerUrl $navBarUrls -LayerInnerOrder $navBarOrder
} elseif ($navBarData) {
    New-Region -LayerId "MainMenu" -AsMenu -Style @{"float"="right"} -Order $realOrder -LayerUrl $navBarUrls -Layer $navBarData -LayerInnerOrder $navBarOrder   
} else {
    ""
}

                                
"
<div style='float:right;position:absolute;zindex:30;right:15px;top:15px;'>
$socialArea
</div>
<div style='float:left'>
<h1 style='float:left'>$titleArea</h1>
<h2 style='text-align:right;float:left;margin-top:75px;margin-left:50px'>
$descriptionArea 
</h2>
$navBarHtml
</div>
$spacingDiv
$spacingDiv
$spacingDiv
<div style='clear:both;margin-top:1%'>$upperBannerSlot</div>
$rest 
<div style='clear:both;margin-top:1%'>$bottomBannerSlot</div>
<div style='float:right;margin-top:15%'>$brandingSlot</div>
" | 
                            New-Region -Style @{
                                "Margin-Left" = $marginPercentLeftString
                                "Margin-Right" = $marginPercentLeftString
                            } |
                            New-WebPage -Title "$($module.Name) | $displayedCommand" @ifTemplateFound |
                            Out-HTML -WriteResponse
                                return
                                
                                
                            } else {
                                $plainOutput = $true
                                if ($result -and $extraParams.ContentType ) {
                                    if ((
                                        $result -is [string] -and
                                        $result -like "*class=?$($command)*"
                                        )-or (
                                        $extraParams.ContentType -ne "text/html" -and 
                                        $result -like "*class=?$($command)*"
                                        ) -or (
                                        $extraParams.ContentType -notlike "text*" -and 
                                        $result -is [string]
                                        )) {
                                        . $getGroups -NavBarOnly

                                        . $getBanners


                                        $navBarHtml = if ($navBarData -and $PipeworksManifest.UseBootstrap) {
    
    
                                            New-Region -LayerID "MainNavBar" -Layer $navBarData -AsNavbar -Style @{"float"="right"} -Order $realOrder -LayerUrl $navBarUrls -LayerInnerOrder $navBarOrder
                                        } elseif ($navBarData) {
                                            New-Region -LayerId "MainMenu" -AsMenu -Style @{"float"="right"} -Order $realOrder -LayerUrl $navBarUrls -Layer $navBarData -LayerInnerOrder $navBarOrder   
                                        } else {
                                            ""
                                        }  

                                        New-WebPage -Title "$($module.Name) | $displayedCommand" @ifTemplateFound |
                                        Out-HTML -WriteResponse
                                    } else {
                                        $response.ContentType=  $extraParams.ContentType
                                        
                                        $response.Write("$result")
                                    }
                                } elseif ($result) {
                                    $response.Write($result)
                                }
                            }
                            
                        } else {
                            if (($result -is [Collections.IEnumerable]) -and ($result -isnot [string])) {
                                $Result = $result | Out-HTML                                
                            }

                            $rest = $result

                            if ($request["Snug"]) {
                                $outputPage = "<div style='clear:both;margin-top:1%'> </div>" + $result |
                                    New-Region -Style @{
                                        "margin-left" = "3%"
                                        "margin-right" = "3%"
                                    }|
                                    New-WebPage -Title "$($module.Name) | $displayedCommand"
                                $response.Write($outputPage)
                            } else {

                                
                                $rest = $result
                                
                                $ifTemplateFound = @{}
                                if ($pipeworksManifest.CommandTemplate) {
                                    $ifTemplateFound.Template =$pipeworksManifest.CommandTemplate
                                } elseif ($pipeworksManifest.DefaultTemplate) {
                                    $ifTemplateFound.Template =$pipeworksManifest.DefaultTemplate
                                } elseif ($pipeworksManifest.Template) {
                                    $ifTemplateFound.Template =$pipeworksManifest.Template
                                }


                                $realOrder = @()
                                $navBarData = @{}
                                $navBarOrder = @{}
                                $navBarUrls = @{}
                                $cmdTabs = @{}
                                $cmdUrls = @{}

                                . $getGroups -NavBarOnly

                                . $getBanners


$navBarHtml = if ($navBarData -and $PipeworksManifest.UseBootstrap) {    
    New-Region -LayerID "MainNavBar" -Layer $navBarData -AsNavbar -Style @{"float"="right"} -Order $realOrder -LayerUrl $navBarUrls -LayerInnerOrder $navBarOrder
} elseif ($navBarData) {
    New-Region -LayerId "MainMenu" -AsMenu -Style @{"float"="right"} -Order $realOrder -LayerUrl $navBarUrls -Layer $navBarData -LayerInnerOrder $navBarOrder   
} else {
    ""
}


                                
"
<div style='float:right;position:absolute;zindex:30;right:15px;top:15px;'>
$socialArea
</div>
<div style='float:left'>
<h1 style='float:left'>$titleArea</h1>
<h2 style='text-align:right;float:left;margin-top:75px;margin-left:50px'>
$descriptionArea 
</h2>
</div>
" + ($spacingDiv * 3) +    
    "<div style='clear:both;margin-top:1%'>$upperBannerSlot</div>" +
    $rest +
    "<div style='clear:both;margin-top:1%'>$bottomBannerSlot</div>" +
    "<div style='float:right;margin-top:15%'>$brandingSlot</div>" |
                            New-Region -Style @{
                                "Margin-Left" = $marginPercentLeftString
                                "Margin-Right" = $marginPercentLeftString
                            } |
                            New-WebPage -Title "$($module.Name) | $command" @ifTemplateFound |
                            Out-HTML -WriteResponse
                            return
                            }
                            
                        }                
                    }                    
                } elseif (($relativeUrlParts[0].EndsWith("-?")) -or 
                    ($relativeUrlParts[1] -eq '-?')) {
                    $CommandNameGuess = $RelativeUrlParts[0].TrimEnd("?").TrimEnd("-")
                    
                    
                    $command = $module.ExportedCommands[$commandNameGuess]
                    if ($command) {
                        $extraParams = if ($pipeworksManifest -and $pipeworksManifest.WebCommand.($Command.Name)) {                
                            @{} + $pipeworksManifest.WebCommand.($Command.Name)
                        } else { @{} }             
                        $extraParams.ShowHelp = $true
                        $result =Invoke-WebCommand -Command $command @extraParams -ServiceUrl $finalUrl 2>&1

                    }

                    
                    if ($result) {
                        
                        $result |
                            New-Region -Style @{
                                "Margin-Left" = $marginPercentLeftString
                                "Margin-Right" = $marginPercentLeftString
                            }|
                            New-WebPage -Title "$($module.Name) | $command" |
                            Out-HTML -WriteResponse 
                        
                    }
                    return
                }
                
                
                
                
                $potentialTopicName = $relativeUrlParts[0].Replace("+"," ").Replace("_", " ").Replace("%20"," ")
                $potentialTopicName =  [Regex]::Replace($potentialTopicName , 
                        "\b(\w)", 
                        { param($a) $a.Value.ToUpper() })                                                 
                # If it's a topic, display the topic
                $theTopic = foreach ($top in $aboutTopics) {
                    if ($top.Name -eq $potentialTopicName) {
                        $top
                    }
                }
                    

                if ($theTopic) {
                    $found = $true


                    if (-not $script:CachedTopics) {
                        $script:CachedTopics  = @{}
                    }


                    $descriptionArea = "$potentialTopicName"
                    $ShowDataInTopic = if ($pipeworksManifest.HideDataInTopic) {
                        $false
                    } else {
                        $true
                    }
                    $rest = ConvertFrom-Markdown -Markdown $theTopic.Topic -ScriptAsPowerShell -ShowData:$ShowDataInTopic
                } 
                
                $theWalkthru = if ($walkthrus) {
                    $walkthrus.GetEnumerator() | 
                        Where-Object { 
                            $_.Key -eq $potentialTopicName 
                        }
                } 

                if ($theWalkthru) {
                    $found = $true
                    $descriptionArea = "$potentialTopicName"

                    $params = @{}
                    if ($pipeworksManifest.TrustedWalkthrus -contains $theWalkThru.Key) {
                        $params['RunDemo'] = $true
                    }
                    if ($pipeworksManifest.WebWalkthrus -contains $theWalkThru.Key) {
                        $params['OutputAsHtml'] = $true
                    }
                    $rest = Write-WalkthruHTML -WalkthruName $theWalkthru.Key -WalkThru $theWalkthru.Value -StepByStep @params
                    
                    if ($request["Snug"]) {
                    
                    } else {
                        


                        
                        
                        
                    }


                    
                }
                
                
                
                               
                


                if ($found -and $rest -and -not ($plainOutput) -and (-not $Request["Snug"])) {


$ifTemplateFound = @{}
if ($pipeworksManifest.TopicTemplate) {
    $ifTemplateFound.Template =$pipeworksManifest.TopicTemplate
} elseif ($pipeworksManifest.DefaultTemplate) {
    $ifTemplateFound.Template =$pipeworksManifest.DefaultTemplate
} elseif ($pipeworksManifest.Template) {
    $ifTemplateFound.Template =$pipeworksManifest.Template
}

if ($request["Snug"]) {
$socialArea + "<div style='clear:both;margin-top:1%'></div>" + ($spacingDiv * 4) + $rest |
                        New-Region -Style @{
                            "Margin-Left" = $marginPercentLeftString
                            "Margin-Right" = $marginPercentLeftString
                        }|
                        New-WebPage -Title "$($module.Name) | $potentialTopicName" |
                        Out-HTML -WriteResponse 

} else {



                        $realOrder = @()
                        $navBarData = @{}
                        $navBarOrder = @{}
                        $navBarUrls = @{}
                        $cmdTabs = @{}
                        $cmdUrls = @{}

                        . $getGroups -NavBarOnly

                        . $getBanners

$navBarHtml = if ($navBarData -and $PipeworksManifest.UseBootstrap) {    
    New-Region -LayerID "MainNavBar" -Layer $navBarData -AsNavbar -Style @{"float"="right"} -Order $realOrder -LayerUrl $navBarUrls -LayerInnerOrder $navBarOrder
} elseif ($navBarData) {
    New-Region -LayerId "MainMenu" -AsMenu -Style @{"float"="right"} -Order $realOrder -LayerUrl $navBarUrls -Layer $navBarData -LayerInnerOrder $navBarOrder   
} else {
    ""
}



    if ($ifTemplateFound.Template -and $ifTemplateFound.Template.Trim()) {
        $content = "
<div style='float:right;position:absolute;zindex:30;right:15px;top:15px;'>
$socialArea
</div>
<div style='float:left'>
<h1 style='float:left'>$titleArea</h1>
<h2 style='text-align:right;float:left;margin-top:75px;margin-left:50px'>
$descriptionArea 
</h2>
</div>
" + ($spacingDiv * 3) +    
    "<div style='clear:both;margin-top:1%'>$upperBannerSlot</div>" +
    $rest +
    "<div style='clear:both;margin-top:1%'>$bottomBannerSlot</div>" +
    "<div style='float:right;margin-top:15%'>$brandingSlot</div>" |
                            New-Region -Style @{
                                "Margin-Left" = $marginPercentLeftString
                                "Margin-Right" = $marginPercentLeftString
                            }

    } else {
        $content = ""
    }
 
    "$content " |
        New-WebPage -Title "$($module.Name) | $potentialTopicName" @ifTemplateFound |
        Out-HTML -WriteResponse                                                                
    }
                } 
                
                
                






                if (-not $found) {
                    $thePage = $module | 
                        Split-Path | 
                        Get-ChildItem -Filter "Pages" -ErrorAction SilentlyContinue | 
                        Get-ChildItem -ErrorAction SilentlyContinue | 
                        Where-Object { '.html', '.htm', '.ps1', '.pspage' -contains $_.Extension }|
                        Where-Object {
                            $pageNAme = $_.Name.Substring(0, $_.Name.Length - $_.Extension.Length)
                            ($pageName -eq $potentialTopicName) 
                        }

                    if ($thePage)  {
                        $found = $true
                    }

                    if ($thePage.Extension -eq '.html' -or $thePage.Extension -eq '.htm') {
                        $response.Write([IO.File]::ReadAllText($thePage.FullName))
                        
                    } elseif ($thePage.Extension -eq '.ps1') {
                        $responseContent = . $module $thePage.FullName
                        $response.Write("$responseContent")
                    }
                }

                # If there's not a topic, walkthru, command, or page
                # See if there's a schema.

                if ($pipeworksManifest.Schema -or $pipeworksManifest.Schemas) {
                    
                    $schemaList = if ($pipeworksManifest.Schema) {
                        Import-PSData -Hashtable $pipeworksManifest.Schema
                    } else {
                        Import-PSData -Hashtable $pipeworksManifest.Schemas
                    }


                    
                    $matchingSchema = $schemaList.$potentialTopicName

                    

                    if ($matchingSchema) {
                        $ifTemplateFound = @{}
                    
                        if ($pipeworksManifest.TopicTemplate) {
                            $ifTemplateFound.Template =$pipeworksManifest.TopicTemplate
                        } elseif ($pipeworksManifest.DefaultTemplate) {
                            $ifTemplateFound.Template =$pipeworksManifest.DefaultTemplate
                        } elseif ($pipeworksManifest.Template) {
                            $ifTemplateFound.Template =$pipeworksManifest.Template
                        }

                    

                        $rest = $content = $matchingSchema | Out-HTML
 
                        "$content " |
                            New-WebPage -Title "$($module.Name) | $potentialTopicName" @ifTemplateFound |
                            Out-HTML -WriteResponse                                                                
                        

                        $found = $true
                    }
                }


                if ($potentialTopicName -eq 'Awards' -or $potentialTopicName -eq 'Award') {
                    $awardsList = if ($pipeworksManifest.Award) {
                        Import-PSData -Hashtable $pipeworksManifest.Award
                    } elseif ($pipeworksManifest.Awards) {
                        Import-PSData -Hashtable $pipeworksManifest.Awards
                    } else {
                        $null
                    }

                    $ifTemplateFound = @{}
                    
                    if ($pipeworksManifest.TopicTemplate) {
                        $ifTemplateFound.Template =$pipeworksManifest.TopicTemplate
                    } elseif ($pipeworksManifest.DefaultTemplate) {
                        $ifTemplateFound.Template =$pipeworksManifest.DefaultTemplate
                    } elseif ($pipeworksManifest.Template) {
                        $ifTemplateFound.Template =$pipeworksManifest.Template
                    }

                    if ($awardsList) {
                        $rest = ($awardsList.psobject.properties |
                            Sort-Object Name |
                            ForEach-Object { 
                                $_.Value | Out-HTML 
                            }) -join "<hr style='clear:both' />"                            

                        "$rest" |
                            New-WebPage -Title "$($module.Name) | $potentialTopicName" @ifTemplateFound |
                            Out-HTML -WriteResponse                                                                

                        $found = $true
                    }
                }

                if ($potentialTopicName -eq 'Schemas' -or $potentialTopicName -eq 'Schema') {
                    if ($pipeworksManifest.Schema -or $pipeworksManifest.Schemas) {
                    
                        $schemaList = if ($pipeworksManifest.Schema) {
                            Import-PSData -Hashtable $pipeworksManifest.Schema
                        } elseif ($pipeworksManifest.Schemas) {
                            Import-PSData -Hashtable $pipeworksManifest.Schemas
                        } else {
                            $null
                        }

                        $ifTemplateFound = @{}
                    
                        if ($pipeworksManifest.TopicTemplate) {
                            $ifTemplateFound.Template =$pipeworksManifest.TopicTemplate
                        } elseif ($pipeworksManifest.DefaultTemplate) {
                            $ifTemplateFound.Template =$pipeworksManifest.DefaultTemplate
                        } elseif ($pipeworksManifest.Template) {
                            $ifTemplateFound.Template =$pipeworksManifest.Template
                        }

                        if ($schemaList) {
                            $rest = ($schemaList.psobject.properties |
                                Sort-Object Name |
                                ForEach-Object { 
                                    $_.Value | Out-HTML 
                                }) -join "<hr style='clear:both' />"                            

                            "$rest" |
                                New-WebPage -Title "$($module.Name) | $potentialTopicName" @ifTemplateFound |
                                Out-HTML -WriteResponse                                                                

                            $found = $true
                        }
                    }
                }

                if ($potentialTopicName -eq 'Profile' -or $potentialTopicName -eq 'Me') {
                    $ifTemplateFound = @{}
                    
                    if ($pipeworksManifest.TopicTemplate) {
                        $ifTemplateFound.Template =$pipeworksManifest.TopicTemplate
                    } elseif ($pipeworksManifest.DefaultTemplate) {
                        $ifTemplateFound.Template =$pipeworksManifest.DefaultTemplate
                    } elseif ($pipeworksManifest.Template) {
                        $ifTemplateFound.Template =$pipeworksManifest.Template
                    }

                            
                    $userName = ""
                    $rest = if ($session -and $session["User"]) {
                        $session["User"] | Out-HTML
                        $userName = $session["User"].Name
                    } else {
                        $confirmed = Confirm-Person -WebsiteUrl $finalUrl
                        if ($session -and $session["User"]) {
                            $session["User"] | Out-HTML
                        } else {
                            $confirmed
                        }
                        
                    }
                    
                    if ($request["Snug"]) {
                    "<div style='clear:both;margin-top:1%'> </div>" + $rest |
                            New-Region -Style @{
                                "Margin-Left" = "1%"
                                "Margin-Right" = "1%"
                            }|
                            New-WebPage -Title "$($module.Name) | $($Session["User"].Name)" |
                            Out-HTML -WriteResponse
                    } else {
                        "$rest" |
                        New-WebPage -Title "$($module.Name) | $userName" @ifTemplateFound |
                        Out-HTML -WriteResponse                                                                
                    }
                    

                    $found = $true
                }


                if (-not $found) {
                    $response.StatusCode = 404
                    
                    $response.Write("Not Found")
                    return
                }
                
            } else {
            
            }
        
        
        }                                
        #endregion Anything Handler
        
        #region ObjectHandler
        $objectHandler = {
            if (-not ($pipeworksManifest.Table -and $pipeworksManifest.Table.StorageAccountSetting -and $pipeworksManifest.Table.StorageKeySetting)) {
                throw 'The Pipeworks manifest must include three settings in order to retrieve items from table storage: Table, TableStorageAccountSetting, and TableStorageKeySetting'
                return
            }
            
            $partition, $row = $request['Object'] -split ':'       
                             
            $rowMatch= [ScriptBLock]::Create("`$_.RowKey -eq '$row'")
            $partitionMatch = [ScriptBLock]::Create("`$_.PartitionKey -eq '$partition'")
            $storageAccount = (Get-WebConfigurationSetting -Setting $pipeworksManifest.Table.StorageAccountSetting)
            $storageKey = (Get-WebConfigurationSetting -Setting $pipeworksManifest.Table.StorageKeySetting)
            Show-WebObject -Table $pipeworksManifest.Table.Name -Row $row -Part $partition |
                New-Region -Style @{
                    'margin-left' = '7.5%'
                    'margin-right' = '7.5%'
                    'margin-top' = '2%'                
                } -layerid objectHolder |
                New-WebPage -Title $row |
                Out-HTML -WriteResponse
            
             
            
        }
        #endregion ObjectHandler             

        # The Import Handler 
        $importHandler = {



$returnedScript = {

}.ToString() + @"
    `$moduleName = '$($module.Name)'
    if (Get-Module `$moduleName) { 
        Write-Warning '$($module.Name) Already Exists'
        return
    }
    `$xhttp = New-Object -ComObject Microsoft.XmlHttp
    `$xhttp.open('GET', '${finalUrl}?-GetManifest', 1)
    `$xhttp.Send()
    do {
        Write-Progress "Downloading Manifest" '${finalUrl}?-GetManifest'    
    } while (`$xHttp.ReadyState -ne 4)

    `$manifest = `$xHttp.ResponseText
    if (-not `$toDirectory) {    
        `$targetModuleDirectory =Join-Path `$home '\Documents\WindowsPowerShell\Modules\$($module.Name)'
    } else {
        `$targetModuleDirectory = `$toDirectory
    }

Write-Progress "Downloading Commands" "${finalUrl}?-GetManifest"
"@ + {



$importScript = $manifest | 
        Select-Xml //AllCommands | 
        ForEach-Object {
            $_.Node.Command 
        } |
        ForEach-Object -Begin {
            $stringBuilder = New-Object Text.StringBuilder
        } {        
            $cmdName = $_.Name
            Write-Progress "Downloading Metadata" "$cmdName"
            $xhttp.open('GET', "$($_.Url.Trim('/'))/?-GetMetaData", 1)
            $xhttp.Send()
            do {
                Write-Progress "Downloading Metadata" "$cmdName"    
            } while ($xHttp.ReadyState -ne 4)

            $commandMetaData = $xHttp.responseText
            $cxml = $commandMetaData -as [xml]
            if ($cxml.CommandManifest.AllowDownload -eq 'true') {
                # Download it
                $xhttp.open('GET', "$($_.Url.TrimEnd('/'))/?-Download", 1)
                $xhttp.Send()
                do {
                    Write-Progress "Downloading" "$cmdName"    
                } while ($xHttp.ReadyState -ne 4 )

                try {
                    $sb = $xHttp.responseText
                    $null = ([ScriptBlock]::Create($sb))
                    $null = $stringBuilder.Append("$sb
")
                } catch {
                    Write-Debug $xHttp.ResponseText
                    $_ | Write-Error
  
                } 
            } elseif ($cxml.CommandManifest.RunOnline -eq 'true') {
                # Download the proxy
                $xhttp.open('GET', "$($_.Url.TrimEnd('/'))/?-DownloadProxy", 1)
                $xhttp.Send()
                do {
                    Write-Debug "Downloading" "$cmdName"    
                } while ($xHttp.ReadyState -ne 4)
                
                $sb = $xHttp.responseText
                . ([ScriptBlock]::Create($sb))
                if ($?) {  
                    $null = $stringBuilder.Append("$sb
")
}
            }
                     
        } -End {
            [ScriptBLock]::Create($stringBuilder)
        }

New-Module -ScriptBlock $importScript -Name $moduleName

}
$response.ContentType = 'text/plain'
$response.Write("$returnedScript")
$response.Flush()
}
        
        # The Self-Install Handler
        $installMeHandler = {
        
$returnedScript = {

param([string]$toDirectory)
    $webClient = New-Object Net.WebClient 
    
}.ToString() + @"
    Write-Progress "Downloading Manifest" '${finalUrl}?-GetManifest'
    `$manifest = `$webClient.DownloadString('${finalUrl}?-GetManifest')
    if (-not `$toDirectory) {    
        `$targetModuleDirectory =Join-Path `$home '\Documents\WindowsPowerShell\Modules\$($module.Name)'
    } else {
        `$targetModuleDirectory = `$toDirectory
    }
"@ + {

Write-Progress "Downloading Commands" '${finalUrl}?-GetManifest'
if ((Test-Path $targetModuleDirectory) -and (-not $toDirectory)) {
    Write-Warning "$targetModuleDirectory Exists, Creating ${targetModuleDirectory}Proxy"    
    $targetModuleDirectory = "${targetModuleDirectory}Proxy"
} 

$null = New-Item -ItemType Directory -Path $targetModuleDirectory

$directoryName = Split-Path $targetModuleDirectory -Leaf

$xmlMan = $manifest -as [xml]
$moduleVersion = $xmlMan.ModuleManifest.Version -as [Version]
if (-not $moduleVersion) { 
    $moduleVersion = "0.0"
}

$guidLine = if ($xmlMan.ModuleManifest.Guid) {
    "Guid = '$($xmlMan.ModuleManifest.Guid)'"
} else { ""} 

$companyLine = if ($xmlMan.ModuleManifest.Company) {
    "CompanyName = '$($xmlMan.ModuleManifest.Company)'"
} else { ""} 


$authorLine = if ($xmlMan.ModuleManifest.Author) {
    "Author = '$($xmlMan.ModuleManifest.Author)'"
} else { ""} 

$CopyrightLine = if ($xmlMan.ModuleManifest.Copyright) {
    "Copyright = '$($xmlMan.ModuleManifest.Copyright)'"
} else { ""} 


$descriptionLine= if ($xmlMan.ModuleManifest.Description) {
    "Description = @'
$($xmlMan.ModuleManifest.Description)
'@"
} else { ""} 



$psd1 = @"
@{
    ModuleVersion = '$($moduleVersion)'
    
    ModuleToProcess = '${directoryName}.psm1'
    
    $descriptionLine
    
    $guidLine
    
    $companyLine 
    
    $authorLine
    
    $CopyrightLine
    
    PrivateData = @{
        Url = '$($xmlMan.ModuleManifest.Url)'
        XmlManifest = @'
$(
$strWrite = New-Object IO.StringWriter
$xmlMan.Save($strWrite)
$strWrite 
)
'@        
    }   
}
"@

        

$psm1 = $manifest | 
    Select-Xml //AllCommands | 
    ForEach-Object {
        $_.Node.Command 
    } |
    ForEach-Object -Begin {
        $psm1 = ""
    } {        
        $targetPath = Join-Path $targetModuleDirectory "$($_.Name).ps1"
        Write-Progress "Downloading $($_.Name)" "From $($_.Url) to $targetPath"
        $commandMetaData = $webClient.DownloadString("$($_.Url.Trim('/'))/?-GetMetaData")
        $cxml = $commandMetaData -as [xml]
        if ($cxml.CommandManifest.AllowDownload -eq 'true') {
            # Download it
            $webClient.DownloadString("$($_.Url.Trim('/'))/?-AllowDownload") | 
                Set-Content $targetPath
        } elseif ($cxml.CommandManifest.RunOnline -eq 'true') {
            # Download the proxy
            $webClient.DownloadString("$($_.Url.Trim('/'))/?-DownloadProxy") | 
                Set-Content $targetPath
            
        } else {
            # Download the stub
            $webClient.DownloadString("$($_.Url.Trim('/'))/?-Stub") | 
                Set-Content $targetPath
        }
        
        $psm1 += '. $psScriptRoot\' + $_.Name + '.ps1' + ([Environment]::NewLine) 
    } -End {
        $psm1 
    }
    
    $psm1 | 
        Set-Content "$targetModuleDirectory\$directoryName.psm1" 
        
    $psd1 | 
        Set-Content "$targetModuleDirectory\$directoryName.psd1"

}



$response.ContentType = 'text/plain'
$response.Write("$returnedScript")
$response.Flush()
}
        # all Commands page
        $allCommandsPage = {


$commandUrlList=  Get-Command | Where-Object { $_.Module.Name -eq $module.Name } | Sort-Object | Select-Object -ExpandProperty Name | Write-Link -List
$order = @()
$layerTitle = "$($module.Name) | All Commands" 
$order += $layerTitle
$layers = @{
    $layerTitle = '<div style=''margin-left:15px''>' + $commandUrlList+ '</div>'
}

# Group by Verb
Get-Command | Where-Object { $_.Module.Name -eq $module.Name }  | 
    Group-Object {$_.Name.Substring(0,$_.Name.IndexOf("-")) } |
    ForEach-Object {
        $order += $_.Name
        $layers[$_.Name] = '<div style=''margin-left:15px''>'  + ($_.Group | Select-Object -ExpandProperty Name | Write-Link) + '</div>'
    }

$region = 
    New-Region -AutoSwitch '0:0:15' -HorizontalRuleUnderTitle -DefaultToFirst -Order $order -Container 'CommandList' -Layer $layers
$page = New-WebPage -Css $cssStyle -Title $layerTitle -AnalyticsID '$analyticsId' -PageBody $region
$response.ContentType = 'text/html'
$response.Write("     $page                ")        

        } 
        
        # -GetCommand list
        $getCommandList = {
$baseUrl = $request.URL
    $commandUrlList = foreach ($cmd in $moduleCommands) {
        $cmd.Name
    }
    $commandUrlList = $commandUrlList | Sort-Object
    $response.ContentType = 'text/plain'
    $commandList = ($commandUrlList -join ([Environment]::NewLine))
    $response.Write([string]"
$commandList
")
        
        }

        $newRobotsTxt = {
    param($RemoteCommandUrl)
"User-Agent: *
Crawl-Delay: 5
Host: $RemoteCommandUrl       
"
        }

        $NewSiteMap = {
    param($RemoteCommandUrl)

$aboutFiles  =  @(Get-ChildItem -Filter *.help.txt -Path "$moduleRoot\en-us" -ErrorAction SilentlyContinue)

if ($requestCulture -and ($requestCulture -ine 'en-us')) {
    $aboutFiles  +=  @(Get-ChildItem -Filter *.help.txt -Path "$moduleRoot\$requestCulture" -ErrorAction SilentlyContinue)
}


$walkThrus = @{}
$aboutTopics = @()
$namedTopics = @{}

$aboutTopicsByName  = @{}


if ($aboutFiles) {
    foreach ($topic in $aboutFiles) {        
        if ($topic.fullname -like "*.walkthru.help.txt") {
            $topicName = $topic.Name.Replace('_',' ').Replace('.walkthru.help.txt','')
            $walkthruContent = Get-Walkthru -File $topic.Fullname            
            $walkThruName = $topicName             
            $walkThrus[$walkThruName] = $walkthruContent                                     
        } else {
            $topicName = $topic.Name.Replace(".help.txt","")
            $nat = New-Object PSObject -Property @{

                    Name = $topicName.Replace("_", " ")
                    SystemName = $topicName
                    Topic = [IO.File]::readalltext($topic.Fullname)
                    LastWriteTime = $topic.LastWriteTime
                }
            $aboutTopics += $nat
            $aboutTopicsByName[$nat.Name] = $nat
                 
        }
    }
}

$blogChunk = if ($pipeworksManifest.Blog -and $pipeworksManifest.Blog.Link -and $pipeworksManifest.Blog.Name) {
    $blogLink = if ($pipeworksManifest.Blog.Link -like "http*" -and $pipeworksManifest.Blog.Name -and $pipeworksManifest.Blog.Description) {
        # Absolute link to module base, 
        $pipeworksManifest.Blog.Link.TrimEnd("/") + "/Module.ashx?rss=$($pipeworksManifest.Blog.Name)"
    } else {
        $pipeworksManifest.Blog.Link
    }
    "<url>        
        <loc>$([Security.Securityelement]::Escape($BlogLink))</loc>        
    </url>"
} else {
    ""
}
$aboutChunk = ""
$aboutChunk = foreach ($topic in $aboutTopics) {
    if (-not $topic) { continue }
    $isInGroup = $false

    if (($pipeworksManifest.TopicGroup | 
            Where-Object { $_.Values | 
                Where-Object { $_ -eq ($Topic.Name) }
            }) -or
        ($pipeworksManifest.Group | 
            Where-Object { $_.Values | 
                Where-Object { $_ -eq ($Topic.Name) }
            })) {

        $isInGroup = $true
    }

    "<url>
        <loc>$($remoteCommandUrl.TrimEnd('/'))/$($topic.Name)/</loc>
        <changefreq>weekly</changefreq>
        $(if ($isInGroup) {
            "<priority>0.8</priority>"
        })
    </url>"
}

$walkthruChunk = ""
$walkthruChunk = foreach ($walkthruName in ($walkthrus.Keys | Sort-Object)) {
    $isInGroup = $false
    if (($pipeworksManifest.TopicGroup | 
            Where-Object { $_.Values | 
                Where-Object { $_ -eq $walkthruName }
            }) -or
            ($pipeworksManifest.Group | 
            Where-Object { $_.Values | 
                Where-Object { $_ -eq $walkthruName }
            })) {

        $isInGroup = $true
    }


    "<url>
        
        <loc>$($remoteCommandUrl.TrimEnd('/'))/$($walkthruName)/</loc>
        <changefreq>weekly</changefreq>
        $(if ($isInGroup) {
            "<priority>0.8</priority>"
        })
    </url>"
}

$CommandChunk = ""
$CommandChunk = foreach ($cmd in ($pipeworksManifest.WebCommand.Keys | Sort-Object)) {
    if ($pipeworksManifest.WebCommand[$Cmd].Hidden -or
        $pipeworksManifest.WebCommand[$Cmd].IfLoggedInAs -or
        $pipeworksManifest.WebCommand[$Cmd].ValidUserPartition -or 
        $pipeworksManifest.WebCommand[$Cmd].RequireLogin -or 
        $pipeworksManifest.WebCommand[$Cmd].RequireAppKey) {
        continue
    }

    $aliased = Get-Command -Module $module -CommandType Alias | Where-Object { $_.ResolvedCommand.Name -eq $cmd } 
    $isInGroup = $false
    if (($pipeworksManifest.Group | 
            Where-Object { $_.Values | 
                Where-Object { $_ -eq $cmd }
            })) {

        $isInGroup = $true
    }
    if ($aliased) {
        foreach ($a in $aliased) {
            "
    <url>
        <loc>$($remoteCommandUrl.TrimEnd('/'))/$($a.Name)/</loc>        
        $(if ($isInGroup) {
            "<priority>1</priority>"
        } else {
            "<priority>0.7</priority>"
        })
    </url>
        "
        }
    }
    "<url>
        <loc>$($remoteCommandUrl.TrimEnd('/'))/$($cmd)/</loc>        
        $(if ($isInGroup) {
            "<priority>0.9</priority>"
        } else {
            "<priority>0.6</priority>"
        })
    </url>"
}

$siteMapXml = [xml]"<urlset xmlns=`"http://www.sitemaps.org/schemas/sitemap/0.9`">
    <url>
        <loc>$($remoteCommandUrl.TrimEnd('/'))/</loc>
        <priority>1.0</priority>
    </url>
    $aboutChunk
    $WalkThruChunk
    $CommandChunk 
</urlset>"

return $siteMapXml        
        }


        $getSiteMapHandler = {
if ($application -and $application["SitemapFor_$($module.Name)"]) {
    $manifestXml = $application["SitemapFor_$($module.Name)"]
    $strWrite = New-Object IO.StringWriter
    $manifestXml.Save($strWrite)
    $response.ContentType = 'text/xml'
    $response.Write("$strWrite")
    return
}        



$blogChunk = if ($pipeworksManifest.Blog -and $pipeworksManifest.Blog.Link -and $pipeworksManifest.Blog.Name) {
    $blogLink = if ($pipeworksManifest.Blog.Link -like "http*" -and $pipeworksManifest.Blog.Name -and $pipeworksManifest.Blog.Description) {
        # Absolute link to module base, 
        $pipeworksManifest.Blog.Link.TrimEnd("/") + "/Module.ashx?rss=$($pipeworksManifest.Blog.Name)"
    } else {
        $pipeworksManifest.Blog.Link
    }
    "<url>        
        <loc>$([Security.Securityelement]::Escape($BlogLink))</loc>        
    </url>"
} else {
    ""
}
$aboutChunk = ""
$aboutChunk = foreach ($topic in $aboutTopics) {
    if (-not $topic) { continue }
    $isInGroup = $false

    if (($pipeworksManifest.TopicGroup | 
            Where-Object { $_.Values | 
                Where-Object { $_ -eq ($Topic.Name) }
            }) -or
            ($pipeworksManifest.Group | 
            Where-Object { $_.Values | 
                Where-Object { $_ -eq ($Topic.Name) }
            })) {

        $isInGroup = $true
    }

    "<url>
        <loc>$($remoteCommandUrl.TrimEnd('/'))/$($topic.Name)</loc>
        <changefreq>weekly</changefreq>
        $(if ($isInGroup) {
            "<priority>0.8</priority>"
        })
    </url>"
}

$walkthruChunk = ""
$walkthruChunk = foreach ($walkthruName in ($walkthrus.Keys | Sort-Object)) {
    $isInGroup = $false
    if (($pipeworksManifest.TopicGroup | 
            Where-Object { $_.Values | 
                Where-Object { $_ -eq $walkthruName }
            }) -or
            ($pipeworksManifest.Group | 
            Where-Object { $_.Values | 
                Where-Object { $_ -eq $walkthruName }
            })) {

        $isInGroup = $true
    }


    "<url>
        
        <loc>$($remoteCommandUrl.TrimEnd('/'))/$($walkthruName)</loc>
        <changefreq>weekly</changefreq>
        $(if ($isInGroup) {
            "<priority>0.8</priority>"
        })
    </url>"
}

$CommandChunk = ""
$CommandChunk = foreach ($cmd in ($pipeworksManifest.WebCommand.Keys | Sort-Object)) {
    if ($pipeworksManifest.WebCommand[$Cmd].Hidden -or
        $pipeworksManifest.WebCommand[$Cmd].IfLoggedInAs -or
        $pipeworksManifest.WebCommand[$Cmd].ValidUserPartition -or 
        $pipeworksManifest.WebCommand[$Cmd].RequireLogin -or 
        $pipeworksManifest.WebCommand[$Cmd].RequireAppKey) {
        continue
    }

    $aliased = Get-Command -Module $module -CommandType Alias | Where-Object { $_.ResolvedCommand.Name -eq $cmd } 
    $isInGroup = $false
    if (($pipeworksManifest.Group | 
            Where-Object { $_.Values | 
                Where-Object { $_ -eq $cmd }
            })) {

        $isInGroup = $true
    }
    if ($aliased) {
        foreach ($a in $aliased) {
            "
    <url>
        <loc>$($remoteCommandUrl.TrimEnd('/'))/$($a.Name)</loc>        
        $(if ($isInGroup) {
            "<priority>1</priority>"
        } else {
            "<priority>0.7</priority>"
        })
    </url>
        "
        }
    }
    "<url>
        <loc>$($remoteCommandUrl.TrimEnd('/'))/$($cmd)</loc>        
        $(if ($isInGroup) {
            "<priority>0.9</priority>"
        } else {
            "<priority>0.6</priority>"
        })
    </url>"
}

$siteMapXml = [xml]"<urlset xmlns=`"http://www.sitemaps.org/schemas/sitemap/0.9`">
    <url>
        <loc>$($remoteCommandUrl.TrimEnd('/'))/</loc>
        <priority>1.0</priority>
    </url>
    $aboutChunk
    $WalkThruChunk
    $CommandChunk 
</urlset>"



$application["SitemapFor_$($module.Name)"] = $siteMapXml;
$strWrite = New-Object IO.StringWriter
$siteMapXml.Save($strWrite)
$response.ContentType = 'text/xml'
$response.Write("$strWrite")





        }


                
        $getManifestXmlHandler = {

if ($application -and $application["ManifestXmlFor_$($module.Name)"]) {
    $manifestXml = $application["ManifestXmlFor_$($module.Name)"]
    $strWrite = New-Object IO.StringWriter
    $manifestXml.Save($strWrite)
    $response.ContentType = 'text/xml'
    $response.Write("$strWrite")
    return
}



# The Manifest XML is used to help interact with a module from a remote service.  
# It contains module metadata and discovery information that will be used by most clients.
$commandGroupChunk = ""
$commandGroupChunk = foreach ($commandGroup in $pipeworksmanifest.Group) {
    if (-not $commandGroup) { continue } 
    if ($commandGroup -isnot [Hashtable]) { continue } 

    foreach ($kv in $commandGroup.GetEnumerator()) {
        $groupItems = $null
        $groupItems= foreach ($cmd in $kv.Value) {
            if ($pipeworksManifest.WebCommand.$cmd) {
                "<Command>$cmd</Command>"
            }
            
        }

        if ($groupItems) {
            "<CommandGroup>
                <Name>
                    $($kv.Key)
                </Name>
                $groupItems
            </CommandGroup>"
        }
        
    }

    
        $cmdGroups
    
}
if ($commandGroupChunk) {
    $commandGroupChunk = "<CommandGroups>
$commandGroupChunk
</CommandGroups>"

}

$topicGroupChunk = ""
$topicGroupChunk  = foreach ($topicGroup in $pipeworksmanifest.Group) {
    if (-not $topicGroup) { continue } 
    if ($topicGroup -isnot [Hashtable]) { continue } 
    
    foreach ($kv in $topicGroup.GetEnumerator()) {
        $groupItems= foreach ($cmd in $kv.Value) {       
            if (-not (Get-Command -Module $module -Name $Cmd -ErrorAction SilentlyContinue)) {     
                "<Topic>$cmd</Topic>"
            }            
        }
        if ($groupItems) {
            "<TopicGroup>
                <Name>
                    $($kv.Key)
                </Name>
            $groupItems
            </TopicGroup>"
        }
    }

}

if ($topicGroupChunk  ) {
    $topicGroupChunk  = "<TopicGroups>
$topicGroupChunk  
</TopicGroups>"

}


$blogChunk = if ($pipeworksManifest.Blog -and $pipeworksManifest.Blog.Link -and $pipeworksManifest.Blog.Name) {
    $blogLink = if ($pipeworksManifest.Blog.Link -like "http*" -and $pipeworksManifest.Blog.Name -and $pipeworksManifest.Blog.Description) {
        # Absolute link to module base, 
        $pipeworksManifest.Blog.Link.TrimEnd("/") + "/Module.ashx?rss=$($pipeworksManifest.Blog.Name)"
    } else {
        $pipeworksManifest.Blog.Link
    }
    "<Blog>
        <Name>$([Security.Securityelement]::Escape($pipeworksManifest.Blog.Name))</Name>
        <Feed>$([Security.Securityelement]::Escape($BlogLink))</Feed>        
    </Blog>"
} else {
    ""
}
$ShowDataInTopic = if ($pipeworksManifest.HideDataInTopic) {
        $false
    } else {
        $true
    }
$aboutChunk = foreach ($topic in $aboutTopics) {
    if (-not $topic) { continue }

    "<Topic>
        <Name>
$([Security.Securityelement]::Escape($topic.Name))
        </Name>
        <Content>
$([Security.Securityelement]::Escape((

ConvertFrom-Markdown -Markdown $topic.Topic -ScriptAsPowerShell -ShowData:$ShowDataInTopic
)))
        </Content>
    </Topic>"
}


$styleChunk = if ($pipeworksmanifest.Style) {
    $styleXml = "<Style>"
    if ($pipeworksmanifest.Style.Body."font-family") {
        $fonts = foreach ($fontName in ($pipeworksmanifest.Style.Body."font-family" -split ",")) {
            "<Font>$([Security.SecurityElement]::Escape($FontName))</Font>"
        }
        $styleXml += "<Fonts>$Fonts</Fonts>"
    }
    if ($pipeworksmanifest.Style.Body.color) { 
        $styleXml += "<Foreground>$([Security.SecurityElement]::Escape($pipeworksmanifest.Style.Body.color))</Foreground>"
    }
    if ($pipeworksmanifest.Style.Body.'background-color') { 
        $styleXml += "<Background>$([Security.SecurityElement]::Escape($pipeworksmanifest.Style.Body.'background-color'))</Background>"
    }
    $styleXml += "</Style>"
    $styleXml 
} else {
    ""
}

$walkthruChunk = foreach ($walkthruName in ($walkthrus.Keys | Sort-Object)) {
    $steps = foreach ($step in $walkthrus[$walkthruName]) {
        $videoChunk = if ($step.videoFile) {
            "<Video>$($step.videoFile)</Video>"
        } else {
            ""
        }
        "<Step>
            <Explanation>
$([Security.SecurityElement]::Escape($step.Explanation))
            </Explanation>
            <Script>

$(
if ($Step.Script -ne '$null') {
    [Security.SecurityElement]::Escape((Write-ScriptHTML -Text $step.Script))
})
            </Script>                        
            $videoChunk
        </Step>"
    }
    "<Walkthru>
        <Name>$([Security.SecurityElement]::Escape($WalkthruName))</Name>
        $steps
    </Walkthru>"
}


if ($aboutChunk -or $walkthruChunk) {
    $aboutChunk = "
<About>
$aboutChunk
$WalkthruChunk
</About>
"
}




# This handler creates a Manifest XML.  
$psd1Content = (Get-Content $psd1Path -ReadCount 0 -ErrorAction SilentlyContinue)
$psd1Content = $psd1Content -join ([Environment]::NewLine)
$manifestObject=  New-Object PSObject (& ([ScriptBlock]::Create(
     $psd1Content
)))
$protocol = ($request['Server_Protocol'] -split '/')[0]
$serverName= $request['Server_Name']
$shortPath = Split-Path $request['PATH_INFO']

$remoteCommandUrl= $Protocol + '://' + $ServerName.Replace('\', '/').TrimEnd('/') + '/' + $shortPath.Replace('\','/').TrimStart('/')
$remoteCommandUrl = ($finalUrl -replace 'Module\.ashx', "" -replace 'Default.ashx', "").TrimEnd("/")


$pipeworksManifestPath = Join-Path (Split-Path $module.Path) "$($module.Name).Pipeworks.psd1"
$pipeworksManifest = if (Test-Path $pipeworksManifestPath) {
    try {                     
        & ([ScriptBlock]::Create(
            "data -SupportedCommand Add-Member, New-WebPage, New-Region, Write-CSS, Write-Ajax, Out-Html, Write-Link { $(
                [ScriptBlock]::Create([IO.File]::ReadAllText($pipeworksManifestPath))                    
            )}"))            
    } catch {
        Write-Error "Could not read pipeworks manifest: ($_ | Out-String)" 
    }                                                
} else { $null } 

$allCommandChunks = New-Object Text.StringBuilder
$cmdsInModule = Get-Command | Where-Object { $_.Module.Name -eq $module.Name }
foreach ($cmd in  $cmdsInModule) {
    $help = Get-Help $cmd.Name
    if ($help.Synopsis) {
        $description = $help.Synopsis
        $null = $allCommandChunks.Append("<Command Name='$($cmd.Name)' Url='$($remoteCommandUrl.TrimEnd('/') + '/' + $cmd.Name + '/')'>$([Security.SecurityElement]::Escape($description))</Command>")    
    } else {
        $null  = $allCommandChunks.Append("<Command Name='$($cmd.Name)' Url='$($remoteCommandUrl.TrimEnd('/') + '/' + $cmd.Name + '/')'/>")
    }    
}
$allCommandChunks = "$allCommandChunks"

$defaultCommmandChunk  = if ($pipeworksManifest.DefaultCommand) {
    $defaultParams =  if ($pipeworksManifest.DefaultCommand.Parameter) {
        foreach ($kv in ($pipeworksManifest.DefaultCommand.Parameter | Sort-Object Key)) {
        "        
        <Parameter>
            <Name>$([Security.SecurityElement]::Escape($kv.Key))</Name>
            <Value>$([Security.SecurityElement]::Escape($kv.Value))</Value>
        </Parameter>
        "
        }
        
    } else {
        ""
    }
   "<DefaultCommand>
        <Name>$($pipeworksManifest.DefaultCommand.Name)</Name>
        $defaultParams
   </DefaultCommand>"
} else {
    ""
}

if ($pipeworksManifest.WebCommand) {
    $webCommandsChunk = "<WebCommand>"    
    $webcommandOrder = if ($pipeworksManifest.CommandOrder) {
        $pipeworksManifest.CommandOrder
    } else {
        $pipeworksManifest.WebCommand.Keys | Sort-Object
    }


    foreach ($wc in $webcommandOrder) {
        $LoginRequired= 
            $pipeworksManifest.WebCommand.$($wc).RequireLogin -or
            $pipeworksManifest.WebCommand.$($wc).RequiresLogin -or
            $pipeworksManifest.WebCommand.$($wc).RequireAppKey -or 
            $pipeworksManifest.WebCommand.$($wc).RequiresAppKey -or 
            $pipeworksManifest.WebCommand.$($wc).IfLoggedInAs -or
            $pipeworksManifest.WebCommand.$($wc).ValidUserPartition
        

        $LoginRequiredChunk = 
            if ($loginRequired) {
                " RequireLogin='true'"
            } else {
                ""
            }

        $isHiddenChunk = 
            if ($pipeworksManifest.WebCommand.$($wc).IfLoggedInAs -or
                $pipeworksManifest.WebCommand.$($wc).ValidUserPartition -or
                $pipeworksManifest.WebCommand.$($wc).Hidden) 
            {
                " Hidden='true'"
            } else {
                " "
            }

        $cmdFriendlyName = if ($pipeworksManifest.WebCommand.$wc.FriendlyName) {
            $pipeworksManifest.WebCommand.$wc.FriendlyName
        } else {
            $wc
        }

        $runWithoutInputChunk = if ($pipeworksManifest.WebCommand.$($wc).RunWithoutInput) {
            " RunWithoutInput='true'"
        } else {
            ""
        }

        $selectivelyVisibleChunk = if ($pipeworksManifest.WebCommand.$($wc).IfLoggedInAs -or 
            $pipeworksManifest.WebCommand.$($wc).ValidUserPartition) {
            " SelectivelyVisible='true'"
        } else {
            ""
        }



        $redirectToChunk = if ($pipeworksManifest.WebCommand.$($wc).RedirectTo) {
            " RedirectTo='$([web.httputility]::HtmlAttributeEncode($pipeworksManifest.WebCommand.$($wc).RedirectTo))'"
        } else {
            ""
        }

        $redirectInChunk = if ($pipeworksManifest.WebCommand.$($wc).RedirectIn) {
            " RedirectIn='$([web.httputility]::HtmlAttributeEncode($pipeworksManifest.WebCommand.$($wc).RedirectIn))'"
        } elseif ($pipeworksManifest.WebCommand.$($wc).RedirectTo) {
            " RedirectIn='$([web.httputility]::HtmlAttributeEncode("00:00:00.25"))'"
        } else {
            ""
        }

        $help = Get-Help $wc
        if ($help.Synopsis) {
            $description = $help.Synopsis
            $webCommandsChunk += "<Command Name='$([Security.SecurityElement]::Escape($cmdFriendlyName))' RealName='$wc' ${LoginRequiredChunk}${isHiddenChunk}${runWithoutInputChunk}${selectivelyVisibleChunk} Url='$($remoteCommandUrl.TrimEnd('/') + '/' + $wc + '/')' $redirectToChunk $redirectInChunk>$([Security.SecurityElement]::Escape($description))</Command>"    
        } else {
            $webCommandsChunk += "<Command Name='$([Security.SecurityElement]::Escape($cmdFriendlyName))' RealName='$wc' ${LoginRequiredChunk}${isHiddenChunk}${runWithoutInputChunk}${selectivelyVisibleChunk} Url='$($remoteCommandUrl.TrimEnd('/') + '/' + $wc + '/')' $redirectToChunk $redirectInChunk />"
        }   
    }
    $webCommandsChunk += "</WebCommand>"
}

if ($pipeworksManifest.ModuleUrl) {
    $remoteCommandUrl = $pipeworksManifest.ModuleUrl
}




$moduleUrl = if ($request['Url'] -like "*.ashx*" -and $request['Url'] -notlike "*Default.ashx*") {
    $u = $request['Url'].ToString()
    $u = $u.Substring($u.LastIndexOf('/'))
    $remoteCommandUrl + $u
} elseif ($request['Url'] -like "*.ashx*" -and$moduleUrl -like "*Default.ashx") {
    
    $remoteCommandUrl.Substring(0,$remoteCommandUrl.Length - "Default.ashx".Length - 1)
} else {
    $remoteCommandUrl + "/"
}



$zipDownloadUrl  = if ($allowDownload) {
    
    "<DirectDownload>$($moduleUrl.Substring(0,$moduleUrl.LastIndexOf("/")) + '/' + $module.Name + '.' + $module.Version + '.zip')</DirectDownload>"
} else {
    ""
}




$facebookChunk = 
if ($pipeworksManifest.Facebook.AppId) {
    $scopeString = 
        if ($pipeworksManifest.Facebook.Scope) {
            $pipeworksManifest.Facebook.Scope -join ", "
        } else {
            "email, user_birthday"
        }
    "<Facebook>
        <AppId>$($pipeworksManifest.Facebook.AppId)</AppId>
        <Scope>$scopeString</Scope>
    </Facebook>"
} else {
    ""
}


$LogoChunk = if ($pipeworksManifest.Logo) {
    "<Logo>$([Security.SecurityElement]::Escape($pipeworksManifest.Logo))</Logo>"
} else {
    ""
}

$pubCenterChunk =if ($pipeworksManifest.PubCenter) {
    $pubCenterId = if ($pipeworksmanifest.PubCenter.ApplicationId) {
        $pipeworksmanifest.PubCenter.ApplicationId
    } elseif ($pipeworksmanifest.PubCenter.Id) {
        $pipeworksmanifest.PubCenter.Id
    }
    if (-not $pubCenterId) {
        ""
    } else {
        "
<PubCenter>
    <ApplicationID>$($pubCenterId)</ApplicationID>
    <TopAdUnit>$($pipeworksmanifest.PubCenter.TopAdUnit)</TopAdUnit>
    <BottomAdUnit>$($pipeworksmanifest.PubCenter.BottomAdUnit)</BottomAdUnit>    
</PubCenter>"
    }

} else {
    ""
}


$adSenseChunk = if ($pipeworksManifest.AdSense) {
    $theAdSenseId =  if ($pipeworksmanifest.AdSense.AdSenseId) {
        $pipeworksmanifest.AdSense.AdSenseId
    } elseif ($pipeworksmanifest.AdSense.Id) {
        $pipeworksmanifest.AdSense.Id
    }

"<AdSense>
    <ApplicationID>$($TheAdSenseId)</ApplicationID>
    <TopSlot>$($pipeworksmanifest.AdSense.TopSlot)</TopSlot>
    <BottomSlot>$($pipeworksmanifest.AdSense.BottomAdSlot)</BottomSlot>
</AdSense>
"
} else {
    ""
}



$commandTriggerChunk = if ($pipeworksmanifest.CommandTrigger) {
    $sortedTriggers = $pipeworksmanifest.CommandTrigger.GetEnumerator() | Sort-Object Key
   
    $commandTriggerXml = foreach ($trigger in $sortedTriggers) {
        "
        <CommandTrigger>
            <Trigger>$([Security.SecurityElement]::Escape($Trigger.Key))</Trigger>
            <Command>$([Security.SecurityElement]::Escape($Trigger.Value))</Command>
        </CommandTrigger>"        
    }
    "<CommandTriggers>
    $($commandTriggerXml)
    </CommandTriggers>"
} else {
    ""
}


$manifestXml = [xml]"<ModuleManifest>
    <Name>$($module.Name)</Name>
    <Url>$($moduleUrl)</Url>
    <Version>$($module.Version)</Version>
    <Description>$([Security.SecurityElement]::Escape($module.Description))</Description>
    $LogoChunk
    $styleChunk
    <Company>$($manifestObject.CompanyName)</Company>
    <Author>$($manifestObject.Author)</Author>
    <Copyright>$($manifestObject.Copyright)</Copyright>    
    <Guid>$($manifestObject.Guid)</Guid> 
    $zipDownloadUrl   
    
    $facebookChunk 
    $blogChunk
    $aboutChunk
    $topicGroupChunk
    $defaultCommmandChunk  
    <AllCommands>
        $allCommandChunks
    </AllCommands>
    
    $webCommandsChunk
    
    $commandGroupChunk 
    $commandTriggerChunk
    $pubCenterChunk
    $AdSenseChunk
</ModuleManifest>"

$application["ManifestXmlFor_$($module.Name)"] = $manifestXml;
$strWrite = New-Object IO.StringWriter
$manifestXml.Save($strWrite)
$response.ContentType = 'text/xml'
$response.Write("$strWrite")
        }
               
               
        $mailHandlers =  if ($pipeworksManifest.Mail) {
@"
elseif (`$request['SendMail']) {
    $($mailHandler.ToString().Replace('"','""'))
}
"@        
        } else {
""
        }

        $checkoutHandlers = 
@"
elseif (`$request['AddItemToCart']) {
    $($addCartHandler.ToString().Replace('"','""'))
} elseif (`$request['ShowCart']) {
    $($ShowCartHandler.ToString().Replace('"','""'))
} elseif (`$request['Checkout']) {
    $($checkoutCartHandler.ToString().Replace('"','""'))    
}
"@
        
        $TableHandlers = if ($pipeworksManifest.Table) { @"
elseif (`$request['id']) {
    $($idHandler.ToString().Replace('"','""'))
} elseif (`$request['object']) {
    $($objectHandler.ToString().Replace('"','""'))
} elseif (`$request['Name']) {
    $($nameHandler.ToString().Replace('"','""'))
} elseif (`$request['Latest']) {
    $($latestHandler.ToString().Replace('"','""'))
} elseif (`$request['Rss']) {
    $($RssHandler.ToString().Replace('"','""'))
} elseif (`$request['Type']) {
    $($typeHandler.ToString().Replace('"','""'))
} elseif (`$request['Search']) {
    $($searchHandler.ToString().Replace('"','""'))
} 
"@.TrimEnd()
} else {
    ""
}
        
    $userTableHandlers = if ($pipeworksManifest.UserTable) {
@" 
elseif (`$request['Join']) {
    `$session['ProfileEditMode'] = `$true    
    $($JoinHandler.ToString().Replace('"','""'))
} elseif (`$request['EditProfile']) {
    `$editMode = `$true
    $($JoinHandler.ToString().Replace('"','""'))
} elseif (`$request['ConfirmUser']) {
    $($ConfirmUserHandler.ToString().Replace('"','""'))
} elseif (`$request['Login']) {
    $($LoginUserHandler.ToString().Replace('"','""'))
} elseif (`$request['Logout']) {
    $($LogoutUserHandler.ToString().Replace('"','""'))
} elseif (`$request['ShowApiKey']) {
    $($ShowApiKeyHandler.ToString().Replace('"','""'))
} elseif (`$request['FacebookConfirmed']) {
    $($facebookConfirmUser.ToString().Replace('"','""'))
} elseif (`$request['LiveIDConfirmed']) {
    $($liveIdConfirmUserHandler.ToString().Replace('"','""'))
} elseif (`$request['FacebookLogin']) {
    $($facebookLoginDisplay.ToString().Replace('"','""'))
} elseif (`$request['Purchase'] -or `$request['Rent']) {
    $($addPurchaseHandler.ToString().Replace('"','""'))
} elseif (`$request['Settle']) {
    $($settleHandler.ToString().Replace('"','""'))
} elseif (`$request['BuyCode']) {
    $($settleHandler.ToString().Replace('"','""'))
}
"@        
        } else {
            ""
        }
        
        
        #region GetExtraCommandInfo
        $getCommandExtraInfo = {
            param([string]$RequestedCommand) 

            $command = 
                if ($module.ExportedAliases[$RequestedCommand]) {
                    $module.ExportedAliases[$RequestedCommand]
                } elseif ($module.ExportedFunctions[$requestedCommand]) {
                    $module.ExportedFunctions[$RequestedCommand]
                } elseif ($module.ExportedCmdlets[$requestedCommand]) {
                    $module.ExportedCmdlets[$RequestedCommand]
                }
            
            if ($command.ResolvedCommand) {
                $command = $command.Resolvedcommand
            }
            
            if (-not $command)  {
                throw "$requestedCommand not found in module $module"
            }
            
            
            # Generate individual handlers
            $extraParams = if ($pipeworksManifest -and $pipeworksManifest.WebCommand.($Command.Name)) {                
                $pipeworksManifest.WebCommand.($Command.Name)
            } elseif ($pipeworksManifest -and $pipeworksManifest.WebAlias.($Command.Name) -and
                $pipeworksManifest.WebCommand.($pipeworksManifest.WebAlias.($Command.Name).Command)) { 
                
                $webAlias = $pipeworksManifest.WebAlias.($Command.Name)
                $paramBase = $pipeworksManifest.WebCommand.($pipeworksManifest.WebAlias.($Command.Name).Command)
                foreach ($kv in $webAlias.GetEnumerator()) {
                    if (-not $kv) { continue }
                    if ($kv.Key -eq 'Command') { continue }
                    $paramBase[$kv.Key] = $kv.Value
                }

                $paramBase
            } else { @{
                    ShowHelp=$true

            } }             
            
            if ($pipeworksManifest -and $pipeworksManifest.Style -and (-not $extraParams.Style)) {
                $extraParams.Style = $pipeworksManifest.Style 
            }
            if ($extraParams.Count -gt 1) {
                # Very explicitly make sure it's there, and not explicitly false
                if (-not $extra.RunOnline -or 
                    $extraParams.Contains("RunOnline") -and $extaParams.RunOnline -ne $false) {
                    $extraParams.RunOnline = $true                     
                }                
            } 
            
            if ($extaParams.PipeInto) {
                $extaParams.RunInSandbox = $true
            }
            
            if (-not $extraParams.AllowDownload) {
                $extraParams.AllowDownload = $allowDownload
            }
            
                
            
            if ($extraParams.RequireAppKey -or 
                $extraParams.RequireLogin -or 
                $extraParams.IfLoggedAs -or 
                $extraParams.ValidUserPartition -or 
                $extraParams.Cost -or 
                $extraParams.CostFactor) {

                $extraParams.UserTable = $pipeworksManifest.Usertable.Name
                $extraParams.UserPartition = $pipeworksManifest.Usertable.Partition
                $extraParams.StorageAccountSetting = $pipeworksManifest.Usertable.StorageAccountSetting
                $extraParams.StorageKeySetting = $pipeworksManifest.Usertable.StorageKeySetting 

            }
            
            if ($extraParams.AllowDownload) {
                # Downloadable Commands
                $downloadableCommands += $command.Name                
            }
                        
            
            
            
            
            if ($MarginPercentLeftString -and (-not $extraParams.MarginPercentLeft)) {
                $extraParams.MarginPercentLeft = $MarginPercentLeftString.TrimEnd("%")
            }
            
            if ($MarginPercentRightString-and -not $extraParams.MarginPercentRight) {
                $extraParams.MarginPercentRight = $MarginPercentRightString.TrimEnd("%")
            }
        }        


        $getCommandTab = {
            param($cmd, [switch]$NavBarOnly)

            # If the command is Marked Hidden, then it will not be displayed on a web interface.

            if ($pipeworksManifest.WebCommand.$cmd.Hidden) {
                return
            }


            $realCmd = $cmd


            if ($pipeworksManifest.WebAlias.$Cmd) {
                $realCmd = $pipeworksManifest.WebAlias.$cmd.Command
            }

            if (-not $realCmd) { return }

            $resolvedCommand = Get-Command $realcmd -ErrorAction SilentlyContinue
            
            if (-not $resolvedCommand) { return }        






            $commandHelp = Get-Help $realCmd -ErrorAction SilentlyContinue | Select-Object -First 1 
            if ($commandHelp.Description) {
                $commandDescription = $commandHelp.Description[0].text
                $commandDescription = $commandDescription -replace "`n", "
<BR/>
"       
            }
            $cmdUrl = "${cmd}/?-widget"
            $hideParameter =@($pipeworksManifest.WebCommand.$realcmd.HideParameter)
            $cmdOptions = $pipeworksManifest.WebCommand.$realcmd


            if ($pipeworksManifest.WebAlias.$cmd) {
                foreach ($kv in ($pipeworksManifest.WebAlias.$cmd).GetEnumerator()) {
                    if (-not $kv) {
                        continue
                    }
                    if ($kv.Key -eq 'Command') { continue } 
                    $cmdOptions[$kv.Key] = $kv.Value
                }
            }




            
            $cmdFriendlyName = if ($pipeworksManifest.WebCommand.$realcmd.FriendlyName) {
                $pipeworksManifest.WebCommand.$realcmd.FriendlyName
            } else {
                $realCmd
            }   
            $cmdIsVisible = $true
            if ($pipeworksManifest.WebCommand.$realcmd.IfLoggedInAs -or $pipeworksManifest.WebCommand.$realcmd.ValidUserPartition) {
                $confirmParams = @{
                    IfLoggedInAs = $pipeworksManifest.WebCommand.$realcmd.IfLoggedInAs
                    ValidUserPartition = $pipeworksManifest.WebCommand.$realcmd.ValidUserPartition
                    CheckId = $true
                    WebsiteUrl = $finalUrl
                }
                $cmdIsVisible = Confirm-Person @confirmParams
            }
            if ($cmdIsVisible) {
                
                
                
                $commandaction = 
                    if ($customAnyHandler) {
                        "?Command=$realcmd"
                    } else {
                        "$realcmd/"
                    }

            "
<div>
$(ConvertFrom-markdown -markdown "$commandDescription ")

</div>

<div id='${cmd}_container' style='padding:20px'>
$(
if ($cmdOptions.RequireLogin -and (-not $session['User'])) {    
    $confirmHtml = . Confirm-Person -WebsiteUrl $finalUrl
    # Localize Content Here
    'You have to log in'  + $confirmHtml   

    return
} 

if ($NavBarOnly) {
    return " " 
}

if ($cmdOptions.RunWithoutInput ) {
    $extraParams = @{} + $cmdOptions
    if ($pipeworksManifest -and $pipeworksManifest.Style -and (-not $extraParams.Style)) {
        $extraParams.Style = $pipeworksManifest.Style 
    }
    if ($extraParams.Count -gt 1) {
        # Very explicitly make sure it's there, and not explicitly false
        if (-not $extra.RunOnline -or 
            $extraParams.Contains("RunOnline") -and $extaParams.RunOnline -ne $false) {
            $extraParams.RunOnline = $true                     
        }                
    } 
            
    if ($extaParams.PipeInto) {
        $extaParams.RunInSandbox = $true
    }
            
    if (-not $extraParams.AllowDownload) {
        $extraParams.AllowDownload = $allowDownload
    }
            
    if ($extraParams.RunOnline) {
        # Commands that can be run online
        $webCmds += $command.Name
    }
            
    if ($extraParams.RequireAppKey -or $extraParams.RequireLogin -or $extraParams.IfLoggedAs -or $extraParams.ValidUserPartition) {
        $extraParams.UserTable = $pipeworksManifest.Usertable.Name
        $extraParams.UserPartition = $pipeworksManifest.Usertable.Partition
        $extraParams.StorageAccountSetting = $pipeworksManifest.Usertable.StorageAccountSetting
        $extraParams.StorageKeySetting = $pipeworksManifest.Usertable.StorageKeySetting 
    }
    
    
    
    Invoke-Webcommand -Command $resolvedCommand @extraParams -AnalyticsId "$AnalyticsId" -AdSlot "$AdSlot" -AdSenseID "$AdSenseId" -ServiceUrl $finalUrl 2>&1
    
} else {
    $useAjax = 
        if ($pipeworksManifest.NoAjax -or $cmdOptions.ContentType -or $cmdOptions.RedirectTo -or $cmdOptions.PlainOutput) {
            if ($request -and $request["Ajax"]) {
                $true
            } else {
                $false
            }
        } else {
            $true
        }

     
    Request-CommandInput -Action "$commandaction" -CommandMetaData (Get-Command $realcmd -Module "$($module.Name)") -DenyParameter $hideParameter -Ajax:$useAjax  -ButtonText $cmdFriendlyName
})            
</div>" 
            }  
            
                        
            
        }

        $getGroups = {
            param([switch]$NavBarOnly)
        
        if ($pipeworksManifest.Group -or $pipeworksManifest.Groups) {
            $groups = @()

            $groupInfo = if ($pipeworksManifest.Group) {
                $pipeworksManifest.Group
            } else {
                $pipeworksManifest.Groups
            }

            foreach ($grp in $groupInfo ) {
                if (-not $grp) { continue } 
                if ($grp -isnot [hashtable]) { continue } 
                $GroupIsVisible =  $false
                foreach ($key in ($grp.Keys | Sort-Object)) {
                    $innerLayers = @{}
                    $navBarData[$key] = @{}
                    $values = @($grp[$key])
                    $innerOrder = @()
                    foreach ($cmd in $values) {
                        $top = $cmd                                            
                        $tab = 
                            if ($walkthrus[$top]) {                                               
                                $cmdFriendlyName = $top
                                $namedtopics[$top] = $top
                                $params = @{}
                                if ($pipeworksManifest.TrustedWalkthrus -contains $top) {
                                    $params['RunDemo'] = $true
                                }
                                if ($pipeworksManifest.WebWalkthrus -contains $top) {
                                    $params['OutputAsHtml'] = $true
                                }
                                if (-not $NavBarOnly) {
                                    if (-not $script:CachedWalkthrus) {
                                        $script:CachedWalkthrus = @{}
                                    }
                                    if (-not $script:CachedWalkthrus["${module}_${top}"]) {
                                        $script:CachedWalkthrus["${module}_${top}"] = Write-WalkthruHTML -StepByStep -WalkthruName $top -WalkThru $walkthrus[$top] @params
                                    }                                    

                                    $script:CachedWalkthrus["${module}_${top}"]
                                    . ([ScriptBlock]::create("
`${Global:$($Top)} = `$script:CachedWalkthrus[`"`${module}_`${top}`"]
"))

                                } else {
                                    " " 
                                }
                            } elseif ($aboutTopics | Where-Object { $_.Name -eq $top })  {
                                $cmdFriendlyName= $top
                                $namedtopics[$top] = $top
                                $topicMatch = $aboutTopics | Where-Object { $_.Name -eq $top }

                                 
                                if (-not $NavBarOnly) {                                    
                                    if (-not $script:CachedTopics) {
                                        $script:CachedTopics = @{}
                                    }
                                    
                                    if (-not $script:CachedTopics["${module}_${top}"]) {
                                        $ShowDataInTopic = if ($pipeworksManifest.HideDataInTopic) {
                                                $false
                                            } else {
                                                $true
                                            }

                                        $script:CachedTopics["${module}_${top}"] = ConvertFrom-Markdown -Markdown "$($topicMatch.Topic) " -ScriptAsPowerShell -ShowData:$ShowDataInTopic
                                    }    
                                    $script:CachedTopics["${module}_${top}"]
                                    . ([ScriptBlock]::create("
`${Global:$($Top)} = `$script:CachedTopics[`"`${module}_`${top}`"]
"))
                                } else {
                                    " " 
                                }
                                
                            } else {
            
                                
                                . $getCommandTab $cmd -navbarOnly:$NavBarOnly

                                

                                
                            }
                        
                        if ($tab) {
                            if (-not $NavBarOnly){
                                . ([ScriptBlock]::create("
`${Global:$($cmdFriendlyName)} = `$tab
`${Global:$($cmd)} = `$tab
"))

                            }
                            $innerLayers[$cmdFriendlyName] = $tab       
                            
                            $innerOrder += $cmdFriendlyName

                            $navBarData[$key][$cmdFriendlyName] = "$(("../" * $depth))$($cmd)".Replace(" ", "_").TrimEnd("/") + "/"
                            $GroupIsVisible = $true
                        }
                        
                    }
                    
                    $regionLayoutParams = 
                        if ($pipeworksManifest.InnerRegion -as [Hashtable]) {
                            $pipeworksManifest.InnerRegion
                        } else {
                            #The UserAgent based check is to make sure that the default view looks less ugly in Compatibility mode in IE
                            if ($PipeworksManifest.UseBootstrap -or -not $pipeworksManifest.UseJQueryUI) {
                                @{
                                    AsHangingSpan = $true
                                    Style = @{                                       
                                        'Font-Size' = '.95em'
                                    }
                                    
                                }
                            } else {
                                @{
                                    AsTree = $true
                                    Style = @{
                                        "padding" = '15px'                                        
                                        'margin-top' = '20px'
                                        'margin-bottom' = '20px'                                        
                                        'Font-Size' = '.95em'
                                    }
                                    'BranchColor' = $siteforegroundColor
                                }
                        
                            }

                        }

                    if ($GroupIsVisible) {
                    $cmdTabs[$key] = New-Region @regionLayoutParams  -LayerID $Key -Layer $innerLayers -Order $innerOrder
                    $navBarOrder[$key] = $innerOrder
                    
                    $groups += "$key"     
                    }                                   
                }
                
            }
            $realOrder += $groups
            # Filter out anything displayed elsewhere
            $screencasts = @($screenCasts | Where-Object { $_.Caption -and -not $namedtopics[$_.Caption] }) 
            $onlineWalkthrus = @($onlineWalkthrus | Where-Object { $_.Caption -and -not $namedtopics[$_.Caption] } )
            $codeWalkThrus = @($codeWalkThrus | Where-Object { $_.Caption -and -not $namedtopics[$_.Caption] } )
            $aboutItems  = @($aboutItems | Where-Object { $_.Caption -and -not $namedtopics[$_.Caption] } )
            $tutorialItems = @($tutorialItems  | Where-Object { $_.Caption -and -not $namedtopics[$_.Caption] } )


        } else { 
            $commandOrder = if ($pipeworksManifest.CommandOrder) {
                $pipeworksManifest.CommandOrder
            } else {
                $pipeworksManifest.WebCommand.Keys | Sort-Object
            }

        
        

            
            foreach ($cmd in $commandOrder) {            
            
                $tab = . $getCommandTab $cmd
                if ($tab) {
                    . ([ScriptBlock]::create("
`${Global:$($cmdFriendlyName)} = `$tab
`${Global:$($cmd)} = `$tab
"))

                    $cmdTabs[$cmdFriendlyName] = $tab 
                    $realOrder += $cmdFriendlyName

                    $navBarData[$cmdFriendlyName] = "$(("../" * $depth))$($cmd)".Replace(" ", "_").TrimEnd("/") + "/"
                    $navBarUrls[$cmdFriendlyName] = "$(("../" * $depth))$($cmd)".Replace(" ", "_").TrimEnd("/") + "/"
                    
                }
                
        
            }
            
        }
        }                
        #endregion


        $getBanners = {
$bottomBannerSlot = 
    if ($pipeworksManifest.AdSense -and $PipeworksManifest.AdSense.BottomAdSlot) {
    
        if ($PipeworksManifest.AdSense.BottomAdSlot -like "*/*") {
            $slotAdSenseId = $pipeworksManifest.AdSense.BottomAdSlot.Split("/")[0]
            $slotAdSlot =  $pipeworksManifest.AdSense.BottomAdSlot.Split("/")[1]
        } elseif ($pipeworksManifest.AdSense.Id) {
            $slotAdSenseId = $pipeworksManifest.AdSense.Id
            $slotAdSlot = $PipeworksManifest.AdSense.BottomAdSlot
        }
        
        "<p style='text-align:center'>
        <script type='text/javascript'>
        <!--
        google_ad_client = 'ca-pub-$($slotAdSenseId)';
        /* AdSense Banner */
        google_ad_slot = '$($slotAdSlot)';
        google_ad_width = 728;
        google_ad_height = 90;
        //-->
        </script>
        <script type='text/javascript'
        src='http://pagead2.googlesyndication.com/pagead/show_ads.js'>
        </script>
        </p>"    
    } else {
        ""
    }


$upperBannerSlot = 
    if ($pipeworksManifest.AdSense -and $PipeworksManifest.AdSense.TopAdSlot) {
        if ($PipeworksManifest.AdSense.TopAdSlot -like "*/*") {
            $slotAdSenseId = $pipeworksManifest.AdSense.TopAdSlot.Split("/")[0]
            $slotAdSlot =  $pipeworksManifest.AdSense.TopAdSlot.Split("/")[1]
        } elseif ($pipeworksManifest.AdSense.Id) {
            $slotAdSenseId = $pipeworksManifest.AdSense.Id
            $slotAdSlot = $PipeworksManifest.AdSense.TopAdSlot 
        }
        "<p style='text-align:center'>
<script type='text/javascript'>
<!--
google_ad_client = 'ca-pub-$($slotAdSenseId)';
/* AdSense Banner */
google_ad_slot = '$($slotAdSlot)';
google_ad_width = 728;
google_ad_height = 90;
//-->
</script>
<script type='text/javascript'
src='http://pagead2.googlesyndication.com/pagead/show_ads.js'>
</script>
</p>"  
    
    
} else {
    ""
}


$brandingSlot = 
if ($script:CachedBrandingSlot) {
    $script:CachedBrandingSlot
} else {
    if ($pipeworksManifest.Branding) {
        if ($pipeworksManifest.Branding) {
            $ShowDataInTopic = if ($pipeworksManifest.HideDataInTopic) {
                $false
            } else {
                $true
            }

            ConvertFrom-Markdown $pipeworksManifest.Branding -ShowData:$ShowDataInTopic
                      
        } else {
            ""
        }
    } elseif ($ModuleMaker -eq 'Start-Automating') {
@"
<div style='font-size:.75em;text-align:right'>
Provided By 
<a href='http://start-automating.com'>
<img src='http://StartAutomating.com/Assets/StartAutomating_100_Transparent.png' align='middle' style='width:60px;height:60px;border:0' />
</a>

</div>

<div style='font-size:.75em;text-align:right'>
Powered With
<a href='http://powershellpipeworks.com'>
<img src='http://powershellpipeworks.com/assets/powershellpipeworks_150.png' align='middle' style='width:60px;height:60px;border:0' />
</a>

</div>
"@
    } else {
@"
<div style='font-size:.75em;text-align:right'>
Powered With
<a href='http://powershellpipeworks.com'>
<img src='http://powershellpipeworks.com/assets/powershellpipeworks_150.png' align='middle' style='width:60px;height:60px;border:0' />
</a>

</div>
"@        

    
    }

}

$script:CachedBrandingSlot = $brandingSlot

}    
        $coreModuleHandler = {




# Here is where the default module experience happens.


<#

# This consists of declaring several variables that can be used within templates

    $TitleArea - 
        An area containing the title of the module the module logo
    $descriptionArea -
        An area containing the description of the module or the current command        
    $socialArea
        An area containing social media, login links, and company contact info
#>




<#
$TitleArea - 
        An area containing the title of the module the module logo
#> 
$linkUrl = if ("$finalUrl") {
    "$FinalUrl".Substring(0, "$FinalUrl".LastIndexOf("/"))
} else {
    "./"
}

$titleArea = 
    if ($PipeworksManifest -and $pipeworksManifest.Logo) {
        "<a href='$linkUrl' class='brand'><img src='$($pipeworksManifest.Logo)' alt='$($module.Name)' style='border:0' /></a>"
    } else {
        "<a href='$linkUrl' class='brand'>$($Module.Name)</a>"
    }

$socialArea = ''
$titleArea = "$titleArea"


$descriptionArea = "
$($module.Description -ireplace "`n", "<br/>")
"    


$cmdTabs = @{}
$navBarData = @{}
$navBarUrls = @{}
$navBarOrder = @{}
if ($AllowDownload) {
    if ($pipeworksManifest.Technet.Url -or $pipeworksManifest.Win8.PublishedUrl) {
        $downloads = @{
            "Download Latest"  = "Download.html"            
        }

        


        if ($PipeworksManifest.Technet.Url) {
            $downloads+= @{            
                "Download From Technet"  = "$($pipeworksManifest.Technet.Url)"            
            }
        }

        if ($PipeworksManifest.Win8.PublishedUrl) {
            $downloads+= @{            
                "Download Windows App"  = "$($PipeworksManifest.Win8.PublishedUrl)"            
            }
        }
        $navBarData["Download"] = $downloads        
    } else {
        $navBarData["Download"] = ""    
        $navBarUrls["Download"] = "Download.html"
    }
    
}
if ($pipeworksManifest.Win.PublishedUrl -and -not $allowDownload) {

}
$cmdUrls = @{}
$cmdLinks = @{}



$telephoneArea = ""
$addressArea = ""
$emailArea = ""
$orgArea = ""
$orgItems = @()
$OrgInfoSlot = if ($pipeworksManifest.Organization) {
    
    if ($pipeworksManifest.Organization.Telephone) {
        $telephoneArea = ($pipeworksManifest.Organization.Telephone -join ' | ') + "<BR/>"        
        $orgItems += $telephoneArea 
    }
    if ($pipeworksManifest.Organization.Address) {
        $addressArea = $pipeworksManifest.Organization.Address -split ([Environment]::NewLine) -join '<br/>'
        $orgItems += $addressArea 
    }

    if ($pipeworksManifest.Organization.Email) {
        $emailArea = (
        "<a href='mailto:$($pipeworksManifest.Organization.Email)'>$($pipeworksManifest.Organization.Email)</a>"  + "<BR/>"
        )        
        $orgItems += $emailArea
    }
    $orgArea = $orgItems -ne '' -join '<br/>'
    # $socialArea +=  $orgText

} else {
    ""
}


$loginRequired = ($pipeworksManifest -and @(
    $pipeworksManifest.WebCommand.Values  |
        Where-Object {
            $_.RequireLogin -or $_.RequireAppKey -or $_.IfLoggedInAs -or $_.ValidUserPartition
        })) -as [bool]


if (-not $antiSocial) {
    if ($pipeworksManifest -and $pipeworksManifest.Facebook.AppId) {
        $socialArea +=  
            (Write-Link "facebook:like" )
            
    }
    if ($pipeworksManifest -and ($pipeworksManifest.GoogleSiteVerification -or $pipeworksManifest.AddPlusOne)) {
        $socialArea += 
            (Write-Link "google:plusone" )
            
    }
    if ($pipeworksManifest -and $pipeworksManifest.ShowTweet) {
        $socialArea += 
            (Write-Link "twitter:tweet" )
            
    } elseif ($pipeworksManifest -and ($pipeworksManifest.TwitterId)) {
        $socialArea += 
            (Write-Link "twitter:tweet" )
            
        $socialArea += 
            (Write-Link "twitter:follow@$($pipeworksManifest.TwitterId.TrimStart('@'))" )
            
    }

}


$confirmationArea = ""
if ($loginRequired) {
    $confirmationArea  = . Confirm-Person -WebsiteUrl $finalUrl                
}

$topicHtml  = ""

$subtopics = @{
    LayerId = 'MoreInfo'
    Layer = @{}
}

$webPageRss = @{}

$ShowBuiltInBlog = $true

if ($PipeworksManifest.Blog -and $PipeworksManifest.Blog.Name) {    
    $blogLink = if ($pipeworksManifest.Blog.Link -like "http*" -and $pipeworksManifest.Blog.Name -and $pipeworksManifest.Blog.Description) {
        # Absolute link to module base, 
        $pipeworksManifest.Blog.Link.TrimEnd("/") + "/Module.ashx?rss=$($pipeworksManifest.Blog.Name)"
    } elseif ($pipeworksManifest.Blog.Link) {
        $pipeworksManifest.Blog.Link
    } else {
        "/?Rss=true"
        $ShowBuiltInBlog  = $false
    }
    $webPageRss += @{
        $PipeworksManifest.Blog.Name=$blogLink 
    }
} 


$topicsByName = @{}


if ($aboutTopics) {
    $coreAboutTopic = $null
    $otherAboutTopics = 
        @(foreach ($_ in $aboutTopics) {
            if (-not $_) {continue } 
            if ($_.Name -ne "About $($Module.Name)") {
                $_
            } elseif ($hiddenTopics -contains $_.Name) {
                continue
            } elseif ($memberTopics -contains $_.Name -and 
                (-not $session -or (-not $session["User"]))){
                continue
            } else {
                $coreAboutTopic = $_                
            }
        })
        
    
    if ($coreAboutTopic) {
        $coreAboutTopic = $coreAboutTopic | Select-Object -First 1
        $ShowDataInTopic = if ($pipeworksManifest.HideDataInTopic) {
            $false
        } else {
            $true
        }
        $topicHtml = ConvertFrom-Markdown -Markdown "$($coreAboutTopic.Topic) "  -ScriptAsPowerShell -ShowData:$ShowDataInTopic
    }         
    
    if ($otherAboutTopics) {               
        $aboutItems = @()
        $tutorialItems = @()
        
        foreach ($oat in $otherAboutTopics) {
            
            $tutorialItems += 
                if ($customAnyHandler) {
                    New-Object PSObject -Property @{
                        Caption = $oat.Name
                        Url = "?About=" + $oat.Name
                    }
                } else {
                    New-Object PSObject -Property @{
                        Caption = $oat.Name
                        Url = $oat.Name + "/"
                    }
                }
                
            
            
        }                
        
        if ($ShowBuiltInBlog) {
            $webPageRss["$($module)"] = "/?rss=true"        
        }
        if ($tutorialLayer.Count) {
            
        } 
        if ($aboutLayer.Count) {
        
        }    
    }
    
}


    
if ($walkthrus) {
    $screenCasts = @()
    $onlineWalkthrus = @()
    $codeWalkThrus = @()
    
    foreach ($walkthruName in $walkThrus.Keys) {
        if ($walkThruName -like "*Video*" -or 
            $walkThruName -like "*Screencasts*") {
            $screenCasts +=
                if ($customAnyHandler) {
                    New-Object PSObject -Property @{
                        Caption = $walkThruName.Replace('.walkthru.help.txt', '').Replace('_', ' ')
                        Url = "?Walkthru=" + $walkThruName.Replace('.walkthru.help.txt', '').Replace('_', ' ')
                    }
                } else {
                    New-Object PSObject -Property @{
                        Caption = $walkThruName.Replace('.walkthru.help.txt', '').Replace('_', ' ')
                        Url = $walkThruName.Replace('.walkthru.help.txt', '').Replace('_', ' ') + "/"
                    }
                }
                
        } elseif ($pipeworksManifest.TrustedWalkthrus -contains $walkThruName) {
            $onlineWalkThrus += 
                if ($customAnyHandler) { 
                    New-Object PSObject -Property @{
                        Caption = $walkThruName
                        Url = "?Walkthru=" + $walkThruName
                    }
                } else {
                    New-Object PSObject -Property @{
                        Caption = $walkThruName
                        Url = $walkThruName + "/"
                    }
                }
        } else {
            $codeWalkThrus += 
                if ($customAnyHandler) { 
                    New-Object PSObject -Property @{
                        Caption = $walkThruName
                        Url = "?Walkthru=" + $walkThruName
                    }
                } else {
                    New-Object PSObject -Property @{
                        Caption = $walkThruName
                        Url = $walkThruName + "/"
                    }
                }
        }
        
        
    }

    $realOrder=  @()        
    
    # Topics that have been explicitly called out within a group do not get shown within the sublists
    
    if ($pipeworksManifest.TopicGroup -or $PipeworksManifest.TopicGroups) {
        $topicGroup = if ($pipeworksManifest.TopicGroups) {
            $pipeworksManifest.TopicGroups
        } else {
            $pipeworksManifest.TopicGroup
        }


        $topicGroups = @()

        
        foreach ($tGroup in $topicGroup) {
            if (-not $tGroup) { continue }
            if ($tGroup -isnot [hashtable]) { continue } 
                
            foreach ($key in ($tGroup.Keys | Sort-Object)) {
                
                
                $innerLayers = @{}
                $values = @($tGroup[$key])
                $innerOrder = @()
                foreach ($top in $values) {
                    $tab = if ($walkthrus[$top]) {                                               
                        $params = @{}
                        if ($pipeworksManifest.TrustedWalkthrus -contains $top) {
                            $params['RunDemo'] = $true
                        }
                        if ($pipeworksManifest.WebWalkthrus -contains $top) {
                            $params['OutputAsHtml'] = $true
                        }
                        Write-WalkthruHTML -StepByStep -WalkthruName $top -WalkThru $walkthrus[$top] @params
                    } elseif ($aboutTopics | Where-Object { $_.Name -eq $top })  {
                        $topicMatch = $aboutTopics | Where-Object { $_.Name -eq $top } 
                        $ShowDataInTopic = if ($pipeworksManifest.HideDataInTopic) {
                            $false
                        } else {
                            $true
                        }
                        ConvertFrom-Markdown -Markdown "$($topicMatch.Topic) "  -ScriptAsPowerShell -ShowData:$ShowDataInTopic
                    }
                        
                    if ($tab) {
                        $innerLayers[$top] = $tab       
                        $innerOrder += $top
                        $namedTopics[$top] = $top
                    }
                }
                    
                $regionLayoutParams = 
                    if ($pipeworksManifest.InnerRegion -as [Hashtable]) {
                        $pipeworksManifest.InnerRegion
                    } else {
                        #The UserAgent based check is to make sure that the default view looks less ugly in Compatibility mode in IE
                        if ($PipeworksManifest.UseBootstrap -or -not $pipeworksManifest.UseJQueryUI) {
                            @{
                                AsHangingSpan = $true
                                Style = @{                                       
                                    'Font-Size' = '.95em'
                                }
                            }
                        } else {
                            @{
                                AsTree = $true
                                Style = @{
                                    "padding" = '15px'   
                                    'margin-top' = '20px'                                     
                                    'margin-bottom' = '20px'                                        
                                    'Font-Size' = '.95em'
                                }
                                'BranchColor' = $siteforegroundColor
                            }
                        
                        }
                        
                        
                    }
                $cmdTabs[$key] = New-Region @regionLayoutParams -LayerID $Key -Layer $innerLayers -Order $innerOrder
                $topicGroups += "$key"
            }
    
        }
        
    
        $realOrder += $topicGroups  
        
        
        # Filter out anything displayed elsewhere
        $screencasts = @($screenCasts | Where-Object { $_.Caption -and -not $namedtopics[$_.Caption] }) 
        $onlineWalkthrus = @($onlineWalkthrus | Where-Object { $_.Caption -and -not $namedtopics[$_.Caption] } )
        $codeWalkThrus = @($codeWalkThrus | Where-Object { $_.Caption -and -not $namedtopics[$_.Caption] } )
        $aboutItems  = @($aboutItems | Where-Object { $_.Caption -and -not $namedtopics[$_.Caption] } )
        $tutorialItems = @($tutorialItems  | Where-Object { $_.Caption -and -not $namedtopics[$_.Caption] } )
    }    
}        
#endregion Walkthrus Tab
    

        
if ($request -and $request["Snug"]) {
    $MarginPercentLeftString = $MarginPercentRightString = "1%"
}

   


#region Services Tab
    if ($pipeworksManifest -and 
        $pipeworksManifest.WebCommand -and
        $pipeworksManifest.WebCommand -is [Hashtable]) {
        
        

        


    }
    
    . $getGroups 

    
    $videosOrder = @()
    $screenCastSection = if ($screenCasts) {
        $navBarData["Videos"] = @{}
        $subTopics.Layer."Videos"  = @"
<p class='ModuleWalkthruExplanation'>
        
Watch these videos to get started:

$($ScreenCasts |
    Sort-Object Caption | 
    ForEach-Object {
        $navBarData["Videos"][$($_.Caption)] = "$(("../" * $depth))$($_.Url)".Replace(' ', '%')
        $videosOrder  += $_.Caption
        $_
    } |
    Write-Link -AsList)
</p>
"@

        $navBarOrder["Videos"] = $videosOrder
    } else {
        ""
    }

    $demoOrder = @()
    
    $onlineWalkthruSection = if ($onlineWalkthrus) {
        
        $navBarData["Demos"] = @{}
        $subTopics.Layer."Demos" = @"
<p class='ModuleWalkthruExplanation'>
        
See each step, and see each step's results.

$($OnlineWalkthrus|
    Sort-Object Caption|
    ForEach-Object {
        $navBarData["Demos"][$_.Caption] = "$(("../" * $depth))$($_.Url)".Replace(' ', '%')
        $demoOrder += $_.Caption
        $_
    } |
    Write-Link -AsList )
</p>
"@
    $navBarOrder["Demos"] = $demoOrder
    } else {
        ""
    }


    
    $walkthruOrder = @()
    $codeWalkthruSection = if ($codeWalkThrus) {
        $navBarData["Walkthrus"] = @{}
        $subTopics.Layer."Walkthrus" = @"
<p class='ModuleWalkthruExplanation'>
        
See the code step by step.

$($CodeWalkthrus |  
    Sort-Object Caption|
    ForEach-Object {
        $navBarData["Walkthrus"][$_.Caption] = "$(("../" * $depth))$($_.Url)".Replace(' ', '%')
        $walkthruOrder += $_.Caption
        $_
    } |
    Write-Link -AsList)
</p>
"@
        $navBarOrder["Walkthrus"] = $walkthruOrder 
    } else {
        ""
    } 
    
    if ($aboutItems -or $tutorialItems -and -not $pipeworksManifest.HideUngrouped -or $pipeworksManifest.HideUngroupedTopics) {
        $MoreAboutModule = @()
        $navBarData["More About $Module"] = @{}
        $subTopics.Layer."More About $Module" = @"
<p class='ModuleWalkthruExplanation'>
        


$($aboutItems + $tutorialItems |  
    Sort-Object Caption |
    ForEach-Object {
        
        $navBarData["More About $Module"]["$($_.Caption)"] = "$(("../" * $depth))$($_.Url)".Replace(' ', '%')
        $MoreAboutModule += $_.Caption
        $_
    } | 
    Write-Link -AsList)
</p>

"@                
        $navBarOrder["More About $Module"] =$MoreAboutModule
    }
    
    $learnMore = if ($subtopics.Layer.Count) {
        foreach ($layerName in "More About $module", "Videos", "Walkthrus", "Demos") {
            if( $subtopics.Layer.$layerName) {
                $realOrder += $layerName
                if (-not $cmdTabs) {
                    $cmdTabs = @{}
                }
                $cmdTabs[$layerName] = $subtopics.Layer.$layerName

                
            }
        } 
        
        
        
        
        
        ""
    } else {
        ""
    }
    


    
    if ($AllowDownload) {
        


        if ($pipeworksManifest.Technet.Url -or $PipeworksManifest.Win8.PublishedURL) {
            
            $downloads = @{
                "Download Latest"  = "Download.html"
            }
            $downloadLayers = @{
                "Download Latest" =  " "
            }

            if ($PipeworksManifest.Technet.Url) {
                $downloads += @{
                    "Download From Technet"  = $PipeworksManifest.Technet.Url
                }
                $downloadLayers += @{
                    "Download From Technet" =  " "
                }
            }

            if ($PipeworksManifest.Win8.PublishedURL) {
                $downloads +=@{
                    "Download Windows App"  = $PipeworksManifest.Win8.PublishedURL
                }
                $downloadLayers += @{
                    "Download Windows App" =  " "
                }
            }
            
            $layerName = "Download"
            $cmdTabs[$layerName] = New-Region -LayerID 'DownloadLayer' -LayerUrl $downloads -AsHangingSpan -Layer $downloadLayers
            
            $realOrder += "Download"
            
        } else {
            $layerName = "Download"
            $realOrder += "Download"
            $cmdTabs[$layerName] = " "
            
            $cmdLinks += @{Download="Download.html"}
            
        }                               
    }


    if ($pipeworksManifest.Win8.PublishedUrl) {
        if (-not $allowDownload) {
            $cmdLinks += @{"Download Windows App"=$pipeworksManifest.Win8.PublishedUrl}
            $layerName = "Download Windows App"
            $realOrder += "Download Windows App"
            $cmdTabs[$layerName] = " "
        }
        
    }
    
    $regionLayoutParams = if ($pipeworksManifest.MainRegion -as [hashtable]) {
        $pipeworksManifest.MainRegion
    } else {
        #The UserAgent based check is to make sure that the default view looks less ugly in Compatibility mode in IE
        if ($PipeworksManifest.UseBootstrap -or -not $pipeworksManifest.UseJQueryUI) {
            @{                               
                AsHangingSpan = $true
                Style = @{                                        
                    'Font-Size' = '1.05em'
                }
                SpanButtonSize = 3                                
            }
        } else {
            @{
                AsTree = $true
                Style = @{
                    "padding" = '25px'                                        
                    'margin-top' = '30px'
                    'margin-bottom' = '30px'                                         
                    'Font-Size' = '1.11em'
                }
                'BranchColor' = $siteforegroundColor
            }
            
                        
        }
        



    }
    $rest = New-Region -LayerID Items -Layer $cmdTabs -order $realOrder @regionLayoutParams -LayerUrl $cmdUrls -layerLink $cmdLinks
    
    #endregion Services Tab
    



. $getBanners
$ifTemplateFound = @{}

$rssLink = 
if ($webPageRss.Count -ge 1 -and $otherAboutTopics.Count -and $pipeworksManifest.Blog) {
    $rsslinks = foreach ($rss in $webPageRss.GetEnumerator()) {
        if (-not $rss) { continue }
        "<a href='$($rss.Value)'><img src='/rss.png' style='border:0;' alt='$([Web.HttpUtility]::HtmlAttributeEncode($rss.Key))' /></a>"
    }
    $rsslinks -join ("<br/>")
} else {
    " " 
}

if ($pipeworksManifest.ModuleTemplate) {
    $ifTemplateFound.Template =$pipeworksManifest.ModuleTemplate
} elseif ($pipeworksManifest.DefaultTemplate) {
    $ifTemplateFound.Template =$pipeworksManifest.DefaultTemplate
} elseif ($pipeworksManifest.Template) {
    $ifTemplateFound.Template =$pipeworksManifest.Template
}



if (-not $global:ModuleTemplateExists) {
    $global:ModuleTemplateExists = "Template", "Templates" | Get-ChildItem -ErrorAction SilentlyContinue -Filter "$($ifTemplateFound.Template).pswt" | Select-Object -First 1
}


# If the template won't make use of automatically generated sections, then don't generate them.
$makeNavBar = $true
$makeSlideShow = $true
$showDefaultCommand = $true

if ($global:ModuleTemplateExists) {
    $templateText = [IO.File]::ReadAllText($global:ModuleTemplateExists.FullName)

    $makeNavBar = [Regex]::Match($templateText, '\$navBarHtml')
    $makeSlideShow = [Regex]::Match($templateText, '\$slideShowHtml')
    $showDefaultCommand = [Regex]::Match($templateText, '\$defaultCommandSection')
}



if ($makeNavBar) {
    $navBarHtml = 
        if ($navBarData -and $PipeworksManifest.UseBootstrap) {    
            New-Region -LayerID "MainNavBar" -Layer $navBarData -AsNavbar -Style @{"float"="right"} -Order $realOrder -LayerUrl $navBarUrls -LayerInnerOrder $navBarOrder
        } elseif ($navBarData) {
            New-Region -LayerId "MainMenu" -AsMenu -Style @{"float"="right"} -Order $realOrder -LayerUrl $navBarUrls -Layer $navBarData -LayerInnerOrder $navBarOrder   
        } else {
            ""
        }
}

if ($makeSlideShow) {

    $slideShowHtml = ""
    if ($pipeworksManifest.Slideshow) {
        $slidesInShow  = @{}
        $slideShowNaturalOrder = @()    
        $slideCount = 0
            $slideList = 
                if ($pipeworksManifest.SlideShow.Slide) {
                    $pipeworksManifest.SlideShow.Slide
                } elseif ($pipeworksManifest.SlideShow.Slides){
                    $pipeworksManifest.SlideShow.Slides
                } else {
                    $null
                }



            foreach ($slide in $slideList) {
                if (-not $slide) { continue }
                if ($slide -is [Hashtable]) {
                    foreach ($k in  ($slide.Keys | Sort-Object)) {
                        $slideName  = $k
                        $slideShowNaturalOrder += $k
                        $slidesInShow[$k] = $slide[$k]
                    }
                } elseif ($slide -as [string]) {
                    $slideName = "Slide" + $slideCount
                    $slideCount++
                    $slidesInShow[$slideName] = "<img src='$($slide)' style='border:0;max-width:75%' />"
                    $slideShowNaturalOrder += $slideName
                }
            }

        if ($pipeworksManifest.Slideshow.Order) {
            $slideShowOrder  = $pipeworksManifest.Slideshow.Order
        } else {
            $slideShowOrder  = $slideShowNaturalOrder
        }

        $slideShowParams = @{}

        if ($PipeworksManifest.UseBootstrap) {
            $slideShowParams["AsCarousel"] = $true
            $slideShowParams["HideSlideNameButton"] = $true
        } elseif ($PipeworksManifest.UseJqueryUI -or $pipeworksManifest.JQueryUITheme) {
            $slideShowParams["AsSlideShow"] = $true
            $slideShowParams["HideSlideNameButton"] = $true
        }
        $slideShowHtml = New-Region -LayerID MainSlideshow -Layer $slidesInShow -Order $slideShowOrder @slideShowParams
    
    }
}

if ($showDefaultCommand) {
$defaultCommandSection  = if ($pipeworksManifest.DefaultCommand) {
    $defaultCmd = @($ExecutionContext.InvokeCommand.GetCommand($pipeworksManifest.DefaultCommand.Name, "All"))[0]
    
    $defaultCmdParameter = if ($pipeworksManifest.DefaultCommand.Parameter) {
        $pipeworksManifest.DefaultCommand.Parameter
    } else {
        @{}
    }
    
    $cmdOutput = & $defaultcmd @defaultCmdParameter
    
    if ($pipeworksManifest.DefaultCommand.GroupBy) {
        $defaulItem  =""
        $CmdOutputGrouped = $cmdOutput | 
            Group-Object $pipeworksManifest.DefaultCommand.GroupBy |
            Foreach-Object -Begin {
                $groupedLayers = @{}
                $asStyle = if ($pipeworksManifest.DefaultCommand.DisplayAs) {
                    "As$($pipeworksManifest.DefaultCommand.DisplayAs)"
                } else {
                    "AsSlideshow"
                }
            } {
                if (-not $defaulItem ) {
                    $defaultItem = $_.Name
                } 
                
                $groupedLayers[$_.Name] = $_.Group | Out-HTML
            } -End {
                $asStyleParam = @{
                    $AsStyle = $true
                }
                New-Region  -Default $defaultItem -Layer $groupedLayers -LayerID DefaultcommandSection @asStyleParam 
            }
        $cmdOutputGrouped
    } else {
        $cmdOutput | Out-Html
    }
} else {
    ""
}
}

$pageHtml = if (-not $ifTemplateFound.Template) {
"
<div style='float:right;position:absolute;zindex:30;right:15px;top:15px;'>
$socialArea
</div>
<div style='float:left'>
<h1 style='float:left'>$titleArea</h1>
<h2 style='text-align:right;float:left;margin-top:75px'>
$descriptionArea 
</h2>
$(if ($navBarData -and $PipeworksManifest.UseBootstrap) {    
    New-Region -LayerID "MainNavBar" -Layer $navBarData -AsNavbar -Style @{"float"="right"} -Order $realOrder -LayerUrl $navBarUrls -LayerInnerOrder $navBarOrder
} elseif ($navBarData) {
    New-Region -LayerId "MainMenu" -AsMenu -Style @{"float"="right"} -Order $realOrder -LayerUrl $navBarUrls -Layer $navBarData -LayerInnerOrder $navBarOrder   
} else {
    ''
})
</div>
" + ($spacingDiv * 3) +
    "<div style='margin-top:1%'>$topicHtml</div>" +   
    "<div style='clear:both;margin-top:1%'>$upperBannerSlot</div>" +
    "<div style='clear:both;margin-top:1%'>$defaultCommandSection</div>" +    
    $rest +
    "<div style='clear:both;margin-top:1%'>$bottomBannerSlot</div>" +
    "<div style='float:right;margin-top:15%'>$brandingSlot</div>" |
    
    New-Region -Style @{
        "Margin-Left" = $MarginPercentLeftString
        "Margin-Right" = $MarginPercentRightString
    } 
} else {
    " "
}
    if (-not $BakingPage) {
    $pageHtml |
    New-WebPage -NoCache -Title $module.Name -Description $module.Description -Rss $webPageRss @ifTemplateFound |
    Out-HTML -WriteResponse 
    return
    } else {
        $pageHtml |
            New-WebPage -NoCache -Title $module.Name -Description $module.Description -Rss $webPageRss @ifTemplateFound
    }
    

}

        $antiSocial = if ($pipeworksManifest.AntiSocial) {
            $true 
        } else {
            $false
        }

        $getVisibleGroups = {
            if (-not ($session -and $session["User"]) -and $request["LiveIdAccessToken"]) {
                $accessToken = $request["LiveIdaccesstoken"]
                . Confirm-Person -liveIDAccessToken $accessToken -WebsiteUrl $finalUrl
            }
            #if (-not ($session -and $session["User"])) { return } 

            
            if ($pipeworksManifest.Group) {
                $groupVisibilityXml = "<VisibleGroups>"
                foreach ($g in $pipeworksManifest.Group) {
                    
                    
                    
                    
                    foreach ($i in $g.GetEnumerator()) {
                        $groupIsVisible = $false 
                        $groupXml = "<Group Name='$([security.securityElement]::Escape($i.Key))'>"    
                        foreach ($v in $i.Value) {
                            if ($pipeworksManifest.WebCommand.$v) {
                                if ($pipeworksManifest.WebCommand.$v.IfLoggedInAs -or $pipeworksManifestPath.WebCommand.$v.ValidUserPartition) {
                                    $ok = Confirm-person -websiteUrl $finalUrl -IfLoggedInAs $pipeworksManifest.WebCommand.IfLoggedInAs -ValidUserPartition $pipeworksManifest.WebCommand.ValidUserPartition -CheckId
                                    if ($ok) {
                                        $groupIsVisible = $true
                                        $groupXml += "<Item>$($v)</Item>"
                                    }
                                } else {
                                    $groupIsVisible = $true
                                    $groupXml += "<Item>$($v)</Item>"
                                }
                                
                                # It's a command
                            } else {
                                # It's a topic
                                $groupXml += "<Item>$($v)</Item>"
                                $groupIsVisible = $true 
                            }
                        }
                            
                        if ($groupIsVisible) {
                            $groupXml += "</Group>"
                            $groupVisibilityXml += $groupXml
                        }
                    }

                    
                }
            }

            if ($groupVisibilityXml) {
                if ($session -and $session["User"]) {
                    $groupVisibilityXml+="<LoggedIn/>"
                } else {
                }
                $groupVisibilityXml += "</VisibleGroups>"
                $response.ContentType = "text/xml"
                $strWrite = New-Object IO.StringWriter
                ([xml]($groupVisibilityXml)).Save($strWrite)
                $resultToOutput  = "$strWrite" -replace "encoding=`"utf-16`"", "encoding=`"utf-8`""
                $response.Write("$ResultToOutput")
                
            }
            return
        }

        <#$moduleInit = @"
$embedCommand
$getModuleMetaData
`$getCommandExtraInfo = { $($getCommandExtraInfo.ToString())
}
`$getCommandTab = { $($getCommandTab.ToString())
}
`$getGroups = { $($getGroups.ToString())
}

`$getBanners ={ $($getBanners.ToString())
} 
`$cssStyle = $((Write-PowerShellHashtable $Style))
`$HalfMarginPercentLeftString = '$(($MarginPercentLeftString.Replace('%', '') -as [double])/2)%'
`$HalfMarginPercentRightString = '$(($MarginPercentRightString.Replace('%', '') -as [double])/2)%'

`$MarginPercentLeftString = '$MarginPercentLeftString'.Trim()
`$MarginPercentRightString  = '$MarginPercentRightString'.Trim()

`$DownloadUrl = '$DownloadUrl'
`$analyticsId = '$analyticsId'

`$allowDownload = $(if ($allowDownload) { '$true'} else {'$false'}) 
`$antiSocial= $(if ($antiSocial) { '$true'} else {'$false'}) 
`$highlightedModuleCommands = '$($CommandOrder -join "','")'

$($resolveFinalUrl.ToString())

"@#>


        $moduleHandler = @"
WebCommandSequence.InvokeScript(@"

$($embedCommand.ToString().Replace('"','""'))
$($getModuleMetaData.ToString().Replace('"', '""'))
`$getCommandExtraInfo = { $($getCommandExtraInfo.ToString().Replace('"', '""'))
}
`$getCommandTab = { $($getCommandTab.ToString().Replace('"', '""'))
}
`$getGroups = { $($getGroups.ToString().Replace('"', '""'))
}

`$getBanners ={ $($getBanners.ToString().Replace('"', '""'))
} 
`$cssStyle = $((Write-PowerShellHashtable $Style).Replace('"','""'))
`$HalfMarginPercentLeftString = '$(($MarginPercentLeftString.Replace('%', '') -as [double])/2)%'
`$HalfMarginPercentRightString = '$(($MarginPercentRightString.Replace('%', '') -as [double])/2)%'

`$MarginPercentLeftString = '$MarginPercentLeftString'.Trim()
`$MarginPercentRightString  = '$MarginPercentRightString'.Trim()

`$DownloadUrl = '$DownloadUrl'
`$analyticsId = '$analyticsId'

`$allowDownload = $(if ($allowDownload) { '$true'} else {'$false'}) 
`$antiSocial= $(if ($antiSocial) { '$true'} else {'$false'}) 
`$highlightedModuleCommands = '$($CommandOrder -join "','")'



$($resolveFinalUrl.ToString().Replace('"', '""'))

`if (`$request['about']) {
    $($aboutHandler.ToString().Replace('"','""'))
} elseif (`$request['VisibleGroup']) {
    $($getVisibleGroups.ToString().Replace('"','""'))
} elseif (`$request['ShowPrivacyPolicy']) {
    $($privacyPolicyHandler.ToString().Replace('"','""').Replace('THE COMPANY', $module.CompanyName))
} elseif  (`$request['walkthru']){
    $($walkthruHandler.ToString().Replace('"','""'))
} elseif (`$request.QueryString.ToString() -ieq '-TopicRSS' -or `$request['TopicRSS']) {
    $($topicRssHandler.ToString().Replace('"','""')) 
} elseif (`$request.QueryString.ToString() -ieq '-WalkthruRSS' -or `$request['WalkthruRSS']) {
    $($walkthruRssHandler.ToString().Replace('"','""')) 
} elseif (`$request.QueryString.ToString() -ieq '-ModuleRSS' -or `$request['ModuleRss'] -or `$request['Rss']) {
    $($moduleFeedHandler.ToString().Replace('"','""')) 
} elseif (`$Request['GetHelp']) {
    $($helpHandler.ToString().Replace('"','""'))
} elseif (`$Request['Command']) {
    $($commandHandler.ToString().Replace('"','""'))
} $tableHandlers $checkoutHandlers $userTableHandlers $mailHandlers  elseif  (`$request.QueryString.ToString() -eq '-Download') {
    `$page = New-WebPage -Css `$cssStyle -Title ""`$(`$module.Name) | Download"" -AnalyticsID '$analyticsId' -RedirectTo '?-DownloadNow'
    `$response.Write(`$page )
} elseif (`$request.QueryString.ToString() -eq '-Me' -or `$request['ShowMe']) {
    $($meHandler.ToString().Replace('"', '""'))
} elseif (`$request.QueryString.Tostring() -eq '-GetPSD1' -or `$request['PSD1']) {
    `$baseUrl = `$request.URL
    `$response.ContentType = 'text/plain'  
    `$response.Write([string]""
`$((Get-Content `$psd1Path -ErrorAction SilentlyContinue) -join ([Environment]::NewLine))
"")

} elseif (`$request.QueryString.Tostring() -eq '-GetManifest' -or `$request['GetManifest']) {
    $($getManifestXmlHandler.ToString().Replace('"','""'))
} elseif (`$request.QueryString.Tostring() -eq '-Sitemap' -or `$request['GetSitemap']) {
    $($getSitemapHandler.ToString().Replace('"','""'))
} elseif (`$request.QueryString.Tostring() -eq '-Css' -or `$request.QueryString.Tostring() -eq '-Style') {
    if (`$pipeworksManifest -and `$pipeworksManifest.Style) {
        `$outcss = Write-CSS -NoStyleTag -Css `$pipeworksManifest.Style
        `$response.ContentType = 'text/css'
        `$response.Write([string]`$outCss)      
    } else {
        `$response.ContentType = 'text/plain'
        `$response.Write([string]'')      
    }
} elseif  (`$request.QueryString.ToString() -eq '-DownloadNow' -or `$request['DownloadNow']) {         
    if (`$downloadUrl) {
        `$page = New-WebPage -Title ""Download `$(`$module.Name)"" -RedirectTo ""`$downloadUrl""
        `$response.Write([string]`$page)
    } elseif (`$allowDownload) {                  

        `$modulezip = `$module.name + '.' + `$module.Version + '.zip'
         `$page = (New-object PSObject -Property @{RedirectTo=`$modulezip;RedirectIn='0:0:0.50'}),(New-object PSObject -Property @{RedirectTo=""/"";RedirectIn='0:0:7'}) | New-WebPage
        `$response.Write([string]`$page)
        `$response.Flush()                
    }
} elseif (`$request.QueryString.Tostring() -eq '-PaypalIPN' -or `$request['PayPalIPN']) {
    $($payPalIpnHandler.ToString().Replace('"','""'))
} elseif (`$request['AnythingGoes']) {
    $($anythingHandler.ToString().Replace('"','""'))
} else {
`

"@ + $coreModuleHandler.ToString().Replace('"', '""') + @"
}
", context, null, false, $((-not $IsolateRunspace).ToString().ToLower()));
"@
        
        $moduleAshxInsteadOfDefault = $psBoundParameters.StartOnCommand -or $psBoundParameters.AsBlog
        $AcceptAnyUrl= $true
        if ($pipeworksManifest.AcceptanyUrl) {
            $AcceptAnyUrl= $true
        } 

        if ($pipeworksManifest.DomainSchematics -and -not $PipeworksManifest.Stealth) {
            $firstdomain  = $pipeworksManifest.DomainSchematics.GetEnumerator() | Sort-Object Key | Select-Object -First 1 -ExpandProperty Key
            $firstdomain  = $firstdomain  -split "\|" | ForEach-Object { $_.Trim() } | Select-Object -First 1

            $x = & $NewSiteMap "http://$firstdomain"
            $x.Save("$outputDirectory\sitemap.xml")


            $x = & $NewRobotsTxt "http://$firstdomain"
            [IO.File]::WriteAllText("$outputDirectory\robots.txt", $x)


        }
        
        $importsPipeworks = 
            $module.Name -eq 'Pipeworks' -or
            $module.RequiredModules -like "Pipeworks"


        $commandTokens= 
            Get-Variable -Name *handler | Where-Object {$_.Value -is [ScriptBlock] } |
                ForEach-Object {
                    [Management.Automation.PSParser]::Tokenize($_.Value, [ref]$null)                    
                }

        
        $loadedCommands = @{}
        $loadCommandQueue = New-Object Collections.Queue
        $commandsUsedInHandler = @($commandTokens + $tokensInPages |
            Where-Object {
                $_.Type -eq 'Command'
            } | 
            Select-Object -ExpandProperty Content -Unique |
            Get-Command -Type Function -ErrorAction SilentlyContinue |
            ForEach-Object {
                $loadedCommands[$_.Name] = $_
                $null = $loadCommandQueue.Enqueue($_)
            })

        $loadedCommandCount = $loadedCommands.Count


        do {
            if ($loadCommandQueue.Count -eq 0) { 
                break 
            } 
            $loadedCmd = $loadCommandQueue.Dequeue()
            
            
            $commandTokens= 
                [Management.Automation.PSParser]::Tokenize($loadedCmd.Definition, [ref]$null)                    
                    

            @($commandTokens |
            Where-Object {
                $_.Type -eq 'Command'
            } | 
            Select-Object -ExpandProperty Content -Unique |
            Get-Command -Type Function -ErrorAction SilentlyContinue |
            ForEach-Object {
                if (-not ($loadedCommands[$_.Name]) -and -not ($loadCommandQueue -like "$($_.Name)")) {
                    $loadedCommands[$_.Name] = $_
                    $null = $loadCommandQueue.Enqueue($_)
                }
            })
        } while ($loadCommandQueue.Count)

        

        $commandsUsedInHandler = @('Write-Link', 'Write-CSS', 'Get-Walkthru', 'Get-Person', 'ConvertFrom-Markdown', 'Get-Hash', 'Out-HTML', 'New-Region', 'New-WebPage', 'Write-Ajax') + 
            @($loadedCommands.Values | Where-Object { $_.Module.Name -eq 'Pipeworks' }  | Select-Object -ExpandProperty Name )
        
        $commandsUsedInHandler = ($commandsUsedInHandler | Select-Object -Unique)

        #region CommonPageCodeBehind
        if ($usesDynamicPages) {
            $embedSection = ""
            if (-not $ImportsPipeworks) {                                
                $commandsUsedInHandler = $commandsUsedInHandler | Select-Object -Unique
            } else {

                $commandsUsedInHandler = 'Out-HTML'
            }
            $embedSection += foreach ($func in (Get-Command -Name $commandsUsedInHandler -CommandType Function)) {

@"
        string compressed$($func.Name.Replace('-', ''))Defintion = "$(Compress-Data -String $func.Definition.ToString())";
        byte[] binaryDataFor$($func.Name.Replace('-', '')) = System.Convert.FromBase64String(compressed$($func.Name.Replace('-', ''))Defintion);
        System.IO.MemoryStream memoryStreamFor$($func.Name.Replace('-', '')) = new System.IO.MemoryStream(); 
        memoryStreamFor$($func.Name.Replace('-', '')).Write(binaryDataFor$($func.Name.Replace('-', '')), 0, binaryDataFor$($func.Name.Replace('-', '')).Length);
        memoryStreamFor$($func.Name.Replace('-', '')).Seek(0, 0);
        System.IO.Compression.GZipStream decompressorFor$($func.Name.Replace('-', '')) = 
            new System.IO.Compression.GZipStream(memoryStreamFor$($func.Name.Replace('-', '')), System.IO.Compression.CompressionMode.Decompress);
        System.IO.StreamReader readerFor$($func.Name.Replace('-', '')) = new System.IO.StreamReader(decompressorFor$($func.Name.Replace('-', '')));
        string decompressedDefinitionFor$($func.Name.Replace('-', '')) = readerFor$($func.Name.Replace('-', '')).ReadToEnd();
        SessionStateFunctionEntry $($func.Name.Replace('-',''))Command = new SessionStateFunctionEntry(
            "$($func.Name)", decompressedDefinitionFor$($func.Name.Replace('-', ''))
        );
        iss.Commands.Add($($func.Name.Replace('-',''))Command);
"@
            }

            

            $codeBehind = @"
using System;
using System.Web.UI;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Collections;
using System.Collections.ObjectModel;
public partial class PowerShellPage : Page {
    public InitialSessionState InitializeRunspace() {
        InitialSessionState iss = InitialSessionState.CreateDefault();
        $embedSection
        string[] commandsToRemove = new String[] { "$($functionBlacklist -join '","')"};
        foreach (string cmdName in commandsToRemove) {
            iss.Commands.Remove(cmdName, null);
        }
        return iss;
    }
    public void RunScript(string script) {
        bool shareRunspace = $((-not $IsolateRunspace).ToString().ToLower());
        UInt16 poolSize = $PoolSize;
        PowerShell powerShellCommand = PowerShell.Create();
        bool justLoaded = false;
        PSInvocationSettings invokeNoHistory = new PSInvocationSettings();
        invokeNoHistory.AddToHistory = false;
        Collection<PSObject> results;
        if (shareRunspace) {
            if (Application["RunspacePool"] == null) {                        
                justLoaded = true;
                
                RunspacePool rsPool = RunspaceFactory.CreateRunspacePool(InitializeRunspace());
                rsPool.SetMaxRunspaces($PoolSize);
                
                rsPool.ApartmentState = System.Threading.ApartmentState.STA;            
                rsPool.ThreadOptions = PSThreadOptions.ReuseThread;
                rsPool.Open();                                
                powerShellCommand.RunspacePool = rsPool;
                Application.Add("RunspacePool",rsPool);
                
                // Initialize the pool
                Collection<IAsyncResult> resultCollection = new Collection<IAsyncResult>();
                for (int i =0; i < $poolSize; i++) {
                    PowerShell execPolicySet = PowerShell.Create().
                        AddScript(@"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force 
`$pulseTimer = New-Object Timers.Timer -Property @{
    #Interval = ([Timespan]'$pulseInterval').TotalMilliseconds
}


Register-ObjectEvent -InputObject `$pulseTimer -EventName Elapsed -SourceIdentifier PipeworksPulse -Action {
    
    
    `$global:LastPulse = Get-Date        
    
}
`$pulseTimer.Start()



", false);
                    execPolicySet.RunspacePool = rsPool;
                    resultCollection.Add(execPolicySet.BeginInvoke());
                }
                
                foreach (IAsyncResult lastResult in resultCollection) {
                    if (lastResult != null) {
                        lastResult.AsyncWaitHandle.WaitOne();
                    }
                }
                
                powerShellCommand.Commands.Clear();
            }
            
            
                        
            
            powerShellCommand.RunspacePool = Application["RunspacePool"] as RunspacePool;
            
            
            
            string newScript = @"param(`$Request, `$Response, `$Server, `$session, `$Cache, `$Context, `$Application, `$JustLoaded, `$IsSharedRunspace, [Parameter(ValueFromRemainingArguments=`$true)]`$args)
            if (`$request -and `$request.Params -and `$request.Params['PATH_TRANSLATED']) {
                Split-Path `$request.Params['PATH_TRANSLATED'] |
                    Set-Location
            }
            
            " + script;            
            powerShellCommand.AddScript(newScript, false);
                       
            
            powerShellCommand.AddParameter("Request", Request);
            powerShellCommand.AddParameter("Response", Response);
            powerShellCommand.AddParameter("Session", Session);
            powerShellCommand.AddParameter("Server", Server);
            powerShellCommand.AddParameter("Cache", Cache);
            powerShellCommand.AddParameter("Context", Context);
            powerShellCommand.AddParameter("Application", Application);
            powerShellCommand.AddParameter("JustLoaded", justLoaded);
            powerShellCommand.AddParameter("IsSharedRunspace", true);
            results = powerShellCommand.Invoke();        
        
        } else {
            Runspace runspace;
            if (Session["UserRunspace"] == null) {
                
                Runspace rs = RunspaceFactory.CreateRunspace(InitializeRunspace());
                rs.ApartmentState = System.Threading.ApartmentState.STA;            
                rs.ThreadOptions = PSThreadOptions.ReuseThread;
                rs.Open();
                powerShellCommand.Runspace = rs;
                powerShellCommand.
                    AddCommand("Set-ExecutionPolicy", false).
                    AddParameter("Scope", "Process").
                    AddParameter("ExecutionPolicy", "Bypass").
                    AddParameter("Force", true).
                    Invoke(null, invokeNoHistory);
                powerShellCommand.Commands.Clear();

                Session.Add("UserRunspace",rs);
                justLoaded = true;
            }

            runspace = Session["UserRunspace"] as Runspace;

            if (Application["Runspaces"] == null) {
                Application["Runspaces"] = new Hashtable();
            }
            if (Application["RunspaceAccessTimes"] == null) {
                Application["RunspaceAccessTimes"] = new Hashtable();
            }
            if (Application["RunspaceAccessCount"] == null) {
                Application["RunspaceAccessCount"] = new Hashtable();
            }

            Hashtable runspaceTable = Application["Runspaces"] as Hashtable;
            Hashtable runspaceAccesses = Application["RunspaceAccessTimes"] as Hashtable;
            Hashtable runspaceAccessCounter = Application["RunspaceAccessCount"] as Hashtable;
            
            
            if (! runspaceTable.Contains(runspace.InstanceId.ToString())) {
                runspaceTable[runspace.InstanceId.ToString()] = runspace;
            }

            if (! runspaceAccessCounter.Contains(runspace.InstanceId.ToString())) {
                runspaceAccessCounter[runspace.InstanceId.ToString()] = 0;
            }
            runspaceAccessCounter[runspace.InstanceId.ToString()] = ((int)runspaceAccessCounter[runspace.InstanceId.ToString()]) + 1;
            runspaceAccesses[runspace.InstanceId.ToString()] = DateTime.Now;


            runspace.SessionStateProxy.SetVariable("Request", Request);
            runspace.SessionStateProxy.SetVariable("Response", Response);
            runspace.SessionStateProxy.SetVariable("Session", Session);
            runspace.SessionStateProxy.SetVariable("Server", Server);
            runspace.SessionStateProxy.SetVariable("Cache", Cache);
            runspace.SessionStateProxy.SetVariable("Context", Context);
            runspace.SessionStateProxy.SetVariable("Application", Application);
            runspace.SessionStateProxy.SetVariable("JustLoaded", justLoaded);
            runspace.SessionStateProxy.SetVariable("IsSharedRunspace", false);
            powerShellCommand.Runspace = runspace;


        
            powerShellCommand.AddScript(@"
`$timeout = (Get-Date).AddMinutes(-20)
`$oneTimeTimeout = (Get-Date).AddMinutes(-1)
foreach (`$key in @(`$application['Runspaces'].Keys)) {
    if ('Closed', 'Broken' -contains `$application['Runspaces'][`$key].RunspaceStateInfo.State) {
        `$application['Runspaces'][`$key].Dispose()
        `$application['Runspaces'].Remove(`$key)
        continue
    }
    
    if (`$application['RunspaceAccessTimes'][`$key] -lt `$Timeout) {
        
        `$application['Runspaces'][`$key].CloseAsync()
        continue
    }    
}
            ").Invoke(null, invokeNoHistory);
            powerShellCommand.Commands.Clear();        

            powerShellCommand.AddCommand("Split-Path", false).AddParameter("Path", Request.ServerVariables["PATH_TRANSLATED"]).AddCommand("Set-Location").Invoke(null, invokeNoHistory);
            powerShellCommand.Commands.Clear();        

            results = powerShellCommand.AddScript(script, false).Invoke();        

        }
            
        
        foreach (Object obj in results) {
            if (obj != null) {
                if (obj is IEnumerable) {
                    if (obj is String) {
                        Response.Write(obj);
                    } else {
                        IEnumerable enumerableObj = (obj as IEnumerable);
                        foreach (Object innerObject in enumerableObj) {
                            if (innerObject != null) {
                                Response.Write(innerObject);
                            }
                        }
                    }
                    
                } else {
                    Response.Write(obj);
                }
                    
            }
        }
        
        foreach (ErrorRecord err in powerShellCommand.Streams.Error) {
            Response.Write("<span class='ErrorStyle' style='color:red'>" + err + "<br/>" + err.InvocationInfo.PositionMessage + "</span>");
        }

        powerShellCommand.Dispose();
    
    }
}
"@ | 
            Set-Content "$outputDirectory\PowerShellPageBase.cs"
        }
        #endregion CommonPageCodeBehind

        #region Module Output

        if ($pipeworksManifest.PoolSize -as [uint32]) {
            $poolSize = $pipeworksManifest.PoolSize
        }

        $newDefaultExtensions  = Get-ChildItem $outputDirectory -Filter default.* | Select-Object -ExpandProperty Extension
        $handlerText = & $writeSimpleHandler -PoolSize:$PoolSize -sharerunspace:(-not $isolateRunspace) -csharp $moduleHandler -ImportsPipeworks:$importsPipeworks -EmbeddedCommand $commandsUsedInHandler
        $defaultFile = if ($newDefaultExtensions -contains '.aspx') {
            
            $moduleAshxInsteadOfDefault = $true
             
            
            [IO.File]::WriteAllText("$outputDirectory\Module.ashx", $handlerText)
        } elseif ($newDefaultExtensions -contains '.html') { 
            "default.html"
            
        } elseif ($newDefaultExtensions -contains '.ashx') {
            "default.ashx"            
        } else {
        
            if ($AcceptAnyUrl) {
                $null
            } else {
                "default.ashx"
            }            
        }
        
        if ($moduleAshxInsteadOfDefault) {
            if ($psBoundParameters.AsBlog) {
                Copy-Item "$outputDirectory\Blog.html" "$outputDirectory\Default.htm"
            }
            [IO.File]::WriteAllText("$outputDirectory\Module.ashx", $handlerText)
        } else {
            [IO.File]::WriteAllText("$outputDirectory\Module.ashx", $handlerText)
            $defaultFile = "Module.ashx"
            #[IO.File]::WriteAllText("$outputDirectory\Default.ashx", $handlerText)
        }
                
        #endregion Module Output



        #region Module Nesting


        
        # In some cases, one might want to publish multiple modules to different sublocations at the same time.
        
        # A good example would be having a main site, a blog, and an online store.
        
        # In order to nest, make a Pipeworks Manifest section called "Nest", "Nested", or "NestedModules".  
        # This section will be a hashtable, 
        # The key will be the subdirectory where the nested module will be placed.  
        # The value will contain the module placed in the subdirectory. 
        # It can optionally be followed by a : and a comma-separated list of schematics.
        # It can also start with a : and contain the schematics that will be published.  
        # If this occurs, the current module will be published to the subdirectory, using the specified schematics.

        # For example:        
        # @{Blog='Start-Scripting:Blog'} # nest the module Start-Scripting to the subdirectory blog.

        $nestedModules = @($pipeworksManifest.Nest) + $pipeworksManifest.Nested + $pipeworksManifestPath.NestedModule + $pipeworksManifest.NestedModules
        $nestedModules = @($nestedModules -ne $null )
        foreach ($nested in $nestedModules) {
            if ($nested -isnot [Hashtable]) { continue }

            foreach ($ni in $nested.GetEnumerator()) {
                $nestedOutputDirectory = Join-Path $OutputDirectory $ni.Key
                $nestedModule = if ($ni.Value -like ":*") {
                    $realModule.Name
                } else {
                    @($ni.Value -split ":")[0]
                }


                $nestedSchematic = if ($ni.Value -notlike "*:*") {
                    @("Default")
                } else {
                    @(@($ni.Value -split ":")[1] -split "," -ne '')

                }


                $nestedSchematic = @(foreach ($ns in $nestedSchematic) {
                    $ns.Trim()
                })

                ConvertTo-ModuleService -OutputDirectory $nestedOutputDirectory -Name $nestedModule -UseSchematic $nestedSchematic -Force -IsNested
            }
        }

        
        # 11/2/2013 

        #endregion Module Nesting
        
        #region Configuration Settings          
        $configSettingsChunk = ''
                
        if ($ConfigSetting.Count) {
             $configSettingsChunk = "<appSettings>" + (@(foreach ($kv in $configSetting.GetEnumerator()) {"
        <add key='$($kv.Key)' value='$($kv.Value)'/>"                
             }) -join ('')) + "</appSettings>"
        }
        
        $acceptAnyUrl = $true          
        
        if ($pipeworksManifest.MaximumRequestLength) {
            $maximumRequestLength = $pipeworksManifest.MaximumRequestLength
        }

        $realMax = [Math]::Ceiling(($maximumRequestLength  / 1kb))

        
        if ($pipeworksManifest.ExecutionTimeout -as [timespan]) {
            $ExecutionTimeout = $pipeworksManifest.ExecutionTimeout -as [timespan]
        }         

        $cacheControl = "
    <staticContent>
      <clientCache cacheControlMode='UseMaxAge' cacheControlMaxAge='$($CacheStaticContentFor)' />
    </staticContent>
        "
        
        $runTimeChunk  ="
<httpRuntime 
executionTimeout='$($executionTimeout.TotalSeconds -as [uint32])' 
maxRequestLength='$realMax' 
useFullyQualifiedRedirectUrl='false'
appRequestQueueLimit='100'
enableVersionHeader='false' />"                          

        $childDirectories = Get-ChildItem -Path $OutputDirectory | 
            Where-Object { $_.PSIsContainer } 
        
        $excludeChildDirectories = foreach ($child in $childDirectories) { 
            @"
            <add input="{URL}" pattern="^$($child.Name)/" negate="true" />
            <add input="{URL}" pattern="^$($child.Name)$" negate="true" />    
"@
        }
        $rewriteUrlChunk = "<rewrite>
            <rules>
                <rule name='RewriteAll_For$($psBoundParameters.Name + $(if ($psBoundParameters.UseSchematic) { "_$($psBoundParameters.UseSchematic)" }))'>
                    <match url='.*' />
                    <conditions logicalGrouping='MatchAll'>
                        <add input='{REQUEST_FILENAME}' matchType='IsDirectory' negate='true' />
                        $excludeChildDirectories
                        <add input='{URL}' pattern='^.*\.(ashx|axd|css|gif|png|ico|jpg|jpeg|js|flv|f4v|zip|xlsx|docx|mp3|mp4|xml|html|htm|aspx|php|pdf)$' negate='true' />
                        
                    </conditions>

                    <action type='Rewrite' url='AnyUrl.aspx' />
                </rule>
            </rules>
        </rewrite>"
       
        if (-not $AcceptAnyUrl) {

            $rewriteUrlChunk = ""
        } else {
            if (-not (Test-Path "$outputDirectory\AnyUrl.aspx")) {
                $rewriteUrlChunk = $rewriteUrlChunk.Replace("AnyUrl.aspx", "Module.ashx?AnythingGoes=true")
            }
        }
        # $rewriteUrlChunk= ""

        $defaultFound = (
            (Join-Path (Split-Path $OutputDirectory) "web.config") | 
                Get-Content -path  { $_ } -ErrorAction SilentlyContinue | 
                Select-String defaultDocument
            ) -as [bool]

        
        if ($Isnested) {
            $defaultFound = $true
        }
        $defaultDocumentChunk = if ((-not ($defaultFile))) {
@"    
    <system.webServer>
        $(if (-not $defaultFound) { @"
<defaultDocument>
            <files>
                <add value="default.ashx" />
            </files>
        </defaultDocument>
"@})
        $rewriteUrlChunk
        $cacheControl
    </system.webServer>
        
"@        
        }  else {
@"
    <system.webServer>
        $(if (-not $defaultFound) { @"
        <defaultDocument>
            <files>
                <add value="${defaultFile}" />
            </files>
        </defaultDocument>
"@})
        $rewriteUrlChunk
        $cacheControl
    </system.webServer>
"@
        }
        
                           
    
$webConfig = @"
<configuration>
    $ConfigSettingsChunk
    $defaultDocumentChunk 
    $net4Compat
    <system.web>
        <customErrors mode='Off' />        
        $runTimeChunk 
    </system.web>
</configuration>
"@

    $webConfig |
        Set-Content "$outputDirectory\web.config"
        
    
    # If nothing on the page requires a login, "bake" the finished page.  This will only work if the output directory is beneath the WWWRoot of the local server.


    $anyCommandRequiresLogin = $pipeworksManifest.WebCommand.Values | 
        Where-Object { $_.RequiresLogin -or $_.RequireLogin -or $_.ValidUserTable -or $_.IfLoggedInAs } 
    $anyCommandRunsWithoutInput = $pipeworksManifest.WebCommand.Values | 
        Where-Object { $_.RunWithoutInput -and -not $_.Hidden } 
    $thereIsADefaultCommand = $pipeworksManifest.DefaultCommand
    $noServices = $PipeworksManifest.WebCommand -as [bool]

    $shouldBakePages = $true

    if ($anyCommandRequiresLogin -or $anyCommandRunsWithoutInput -or $thereIsADefaultCommand) {
        $shouldBakePages = $false
    }

    if (($newDefaultExtensions -like '.aspx') -and (-not $pipeworksManifest.BakePage)) {
        $shouldBakePages = $false
    }

    if ($newDefaultExtensions -like ".htm*") {
        
        $shouldBakePages = $false
    }
        

    if ($shouldBakePages) {
        if ($newDefaultExtensions -like '.aspx') {

        }


        #$cssStyle = $((Write-PowerShellHashtable $Style))
        $HalfMarginPercentLeftString = "$(($MarginPercentLeftString.Replace('%', '') -as [double])/2)%"
        $HalfMarginPercentRightString = "$(($MarginPercentRightString.Replace('%', '') -as [double])/2)%"

        $MarginPercentLeftString = $MarginPercentLeftString.Trim()
        $MarginPercentRightString  = $MarginPercentRightString.Trim()

        $DownloadUrl = '$DownloadUrl'
        $analyticsId = '$analyticsId'

        $modulemaker = $module.CompanyName
        

        $bakingPage = $true
        $null = . ([ScriptBlock]::Create($embedCommand))
        $null = . ([ScriptBlock]::Create($initModuleDefaults))
        $null = . ([ScriptBlock]::Create($getModuleMetaData))
        $pipeworksManifest = @{} + $Global:pipeworksManifest
        
        $bakedDefault = . $coreModuleHandler
        $global:PipeworksManifest = $null
        $bakingPage = $false
        #$bakedDefault = Get-Web -Url "http://localhost/$realModule/" -UseWebRequest -Timeout 01:00:00
        if ($bakedDefault) {
            [IO.File]::WriteAllText("$outputDirectory/Default.htm", $bakedDefault)

            $defaultDocumentChunk = @"    
    <system.webServer>       
        $rewriteUrlChunk
        $cacheControl
    </system.webServer>
        
"@        
        
            $webConfig = @"
<configuration>
    $ConfigSettingsChunk
    $defaultDocumentChunk 
    $net4Compat
    <system.web>
        <customErrors mode='Off' />        
        $runTimeChunk 
    </system.web>
</configuration>
"@

            $webConfig |
                Set-Content "$outputDirectory\web.config"

        }
    }
    
        
    if ($AsIntranetSite) {
        Import-Module WebAdministration -Global -Force
        $allSites = Get-Website
        
        $AlreadyExists = $allSites |
            Where-Object {$_.Name -eq "$Name" } 
            
        if (-not $alreadyExists) {
            $targetPort = $Port
            $portIsOccupied  = $null
            do {
                if (-not $targetPort) {
                    $targetPort = 80
                } else {
                    $oldTargetPort = $targetPort
                    if ($portIsOccupied) {
                        $targetPort = Get-Random -Maximum 64kb
                        Write-Warning "Port $oldTargetPort occupied, trying Port $targetPort"
                    }
                }

                $portIsOccupied = Get-Website | 
                    Where-Object { 
                        $_.Bindings.Collection | 
                            Where-Object { 
                                $_-like "*:$targetPort*" 
                            }  
                        }                    
            }
            while ($portIsOccupied) 
           
            $w = New-Website -Name "$Name" -Port $targetPort -PhysicalPath $outputDirectory -Force 
            
            
            $AlreadyExists = Get-Website |
                Where-Object {$_.Name -eq "$Name" } 

            
        }

        if ($Realm) {
            Set-WebConfigurationProperty -filter /system.webServer/security/authentication/anonymousAuthentication -name enabled -value false -PSPath IIS:\ -Location $Name
            Set-WebConfigurationProperty -filter /system.webServer/security/authentication/windowsAuthentication -name enabled -value true -PSPath IIS:\ -Location $Name
        } else {
            Set-WebConfigurationProperty -filter /system.webServer/security/authentication/anonymousAuthentication -name enabled -value false -PSPath IIS:\ -Location $Name
            Set-WebConfigurationProperty -filter /system.webServer/security/authentication/windowsAuthentication -name enabled -value true -PSPath IIS:\ -Location $Name

        }

    
        if ($appPoolCredential) {
            $appPool = Get-Item "IIS:\AppPools\${name}AppPool" -ErrorAction SilentlyContinue 
            if (-not $appPool) {
                $pool = New-WebAppPool -Name "${name}AppPool" -Force
                $appPool = Get-Item "IIS:\AppPools\${name}AppPool" -ErrorAction SilentlyContinue 
           
            }
            $appPool.processModel.userName = $appPoolCredential.username
            $appPool.processModel.password = $appPoolCredential.GetNetworkCredential().password
            $appPool.processModel.identityType = 3
            $appPool | Set-Item
            $AlreadyExists = Get-Website |
                Where-Object {$_.Name -eq "$Name" } 

            $siteInf = Get-ChildItem 

            Set-ItemPRoperty iis:\sites\$name -Name ApplicationPool -Value "${name}AppPool" -Force
        }        
    }
#region Global.asax Session Cleanup
@'
<%@ Assembly Name="System.Management.Automation, Version=1.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35" %>
<script language="C#" runat="server">
public void Session_OnEnd()
{
    System.Management.Automation.Runspaces.Runspace rs = Session["User_Runspace"] as System.Management.Automation.Runspaces.Runspace;
    if (rs != null)
    {
        rs.Close();
        rs.Dispose();
    }
    System.GC.Collect();
}
</script>
'@ |         Set-Content "$outputDirectory\Global.asax" 

    
#endregion

        }
        Pop-Location       

        if ($IISReset) {
            iisreset /noforce | ForEach-Object { Write-Progress "Resetting IIS" "$_ " } 
        }


        if ($Show) {
            
            if ($port) {
                Start-Process -FilePath "http://localhost:$Port/"
            } else {
                Start-Process -FilePath "http://localhost/$Module/"
            }
        }


        if ($do) {
            if (-not $do.DnsSafeHost) {
                if ($port) {
                    Start-Process -FilePath "http://localhost:$Port/$("$Do".TrimStart('/'))"
                } else {
                    Start-Process -FilePath "http://localhost/$Module/$("$Do".TrimStart('/'))"
                }
            } else {
                Start-Process -FilePath "$Do"
            }            
        }

        #endregion Configuration Settings               
    }
}