function Publish-Technet
{
    <#
    .Synopsis
        Publishes a module to technet
    .Description
        Publishes modules to the Technet ScriptCenter.
    .Example
        Publish-Technet -ModuleName Pipeworks -Category "Windows Azure" -Subcategory "Cloud Services" -OperatingSystem "Windows Server 2008", "Windows Server 2008 R2", "Windows 7", "Windows 8", "Windows Server 2012" -MSLPL
    .Notes
        Because of an annoyance with how files have to be uploaded, this script has to be run interactively.  
        
        Also, you must already be logged into Technet with your Microsoft account.
    #>
    param(
    # The name of  the module
    [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
    [string]
    $ModuleName,

    # The category the module will be placed in.
    [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
    [string]
    $Category,

    # The subcategory that the module will be placed in
    [Parameter(Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
    [string]
    $Subcategory,

    # A summary of the module.
    [Parameter(ValueFromPipelineByPropertyName=$true)]
    [string]
    $Summary,

    # A list of operating systems the module can be deployed on
    [Parameter(ValueFromPipelineByPropertyName=$true,Mandatory=$true)]    
    [string[]]
    $OperatingSystem,

    # If set, will disable Q&A on the tool
    [Parameter(ValueFromPipelineByPropertyName=$true)]    
    [Switch]
    $DisableQAndA,

    # If set, will use MSLPL
    [Parameter(ValueFromPipelineByPropertyName=$true)]    
    [Switch]
    $MSLPL,

    # The tags used to categorize the module.  Please be nice, and tag required modules.
    [Parameter(ValueFromPipelineByPropertyName=$true)]    
    [Alias('Tags')]
    [string[]]
    $Tag
    )


    process {

    $realModule = Get-Module $ModuleName
    if (-not $realModule) { return }
    
    
    
    $outDir = "$env:Temp\$(Get-Random)"
    $realModule | ConvertTo-ModuleService -AllowDownload -OutputDirectory $outDir

    $zip = dir $outDir -Recurse -Filter "${moduleName}*.zip"
    $tmpZipFile = Join-Path $env:Temp "$(Get-Random)\$realModule.zip"
    $p = $tmpZipFile | Split-Path
    $null = New-Item -ItemType directory -Path $p  -Force -ErrorAction SilentlyContinue

    Move-Item $zip.FullName -Destination $tmpZipFile
    Remove-Item -Recurse -Force -Path $outDir




    $matchingModule = Get-MyTechnetContribution | Where-Object { $_.Name -eq $ModuleName } 

    $isEdit = $false

    if ($matchingModule) {
        $isEdit = $true
    }

    # Close out other technet browsers
    Get-browser | Where-Object { $_.LocationUrl -like "http://gallery.technet.microsoft.com/*" } | ForEach-Object { $_.Quit() } 


    [Windows.Clipboard]::SetText($tmpZipFile)
    $shell  =New-Object -ComObject WScript.Shell
    if ($isEdit) {
        
        $shell.Run("$($matchingModule.Url)/edit?newSession=True")
        Start-Sleep -Seconds 5 
        $br = Get-browser | Where-Object { $_.LocationUrl -like "http://gallery.technet.microsoft.com/*" } 
        $r = $br.Document.getElementById("GenericProject_uploadsForm") | ForEach-Object  {$_.GetElementsByTagName("a") | Where-Object { $_.InnerText -eq 'Remove' }  } 
        $null = $r.click()
        Start-Sleep -Seconds 5 
    } else {
        
        $shell.Run("http://gallery.technet.microsoft.com/site/upload")
        Start-Sleep -Seconds 5     
    }
    
    

    $shell.SendKeys("+{TAB}")
    $shell.SendKeys("+{TAB}")
    if ($isEdit) {
        Start-Sleep -Seconds 1
        $shell.SendKeys(" ")
    }
    $shell.SendKeys(" ")
    Start-Sleep -Seconds 2

    $shell.SendKeys("^V")
    $shell.SendKeys("{Enter}")

    Start-Sleep -Seconds 10

    $browser = Get-browser | Where-Object { $_.LocationUrl -like "http://gallery.technet.microsoft.com/*" }
    $b = $browser
    #[Windows.Clipboard]::SetText($ModuleName)
    
    Start-Sleep -Seconds 2 
    #$sh.SendKeys($ModuleName)                      
    
    $b  = $browser | Set-BrowserControl -Id "Title" -Value $ModuleName
        
    $null = $b.Document.getElementById("Description_code").click()

    
    Start-Sleep -Seconds 2

    $editorFrame = $b.Document.getElementsByTagName("iframe") |
        Where-Object { $_.Src -like "*source_editor.htm" }

    
    $aboutModuleTopic = [IO.File]::ReadAllText("$($realModule | Split-Path)\$(Get-Culture)\about_$ModuleName.help.txt")
    $aboutModule =""
    $modulePipeworksManifest = $realModule | Get-PipeworksManifest -ErrorAction SilentlyContinue

    
    $officialWebsite = ""
    # If there's an official website, mention it.
    if ($modulePipeworksManifest.DomainSchematics) {
        $domainList = $modulePipeworksManifest.DomainSchematics.Keys
        $officialWebsite = $domainList -split "\|" | ForEach-Object { $_.Trim() } | Select-Object -First 1        
    }
    


    
    
    if ($officialWebsite) {
        $logo = $modulePipeworksManifest.Logo
        if ($logo) {
            $aboutModule += "<a href='http://$officialWebsite'><img src='http://${officialWebSite}${Logo}' /></a><br/><br/>"
        }
        
    }

    $aboutModule += ConvertFrom-Markdown -Markdown $aboutModuleTopic

    
    # If the manifest has grouping, use it
    if ($modulePipeworksManifest.Group -and $officialWebsite) {
        foreach ($g in $modulePipeworksManifest.Group) {
            $aboutModule += foreach ($grp in $g.GetEnumerator()) {
                "
                <h3>
                    $($grp.Key)
                </h3>
                <ul>
                    $(foreach ($v in $grp.Value) {
                        "<li><a href='http://$officialWebsite/$v/'>$v</a></li>"
                    })
                </ul>
                "
            }
        }
    }
    if ($officialWebsite -and -not $logo) {
        $aboutModule += "<br/><br/><a href='http://$officialWebsite'>Visit Website</a>"
    }

    $editorFrame.contentDocument.getElementById("htmlSource").value = $aboutModule
    $editorFrame.contentDocument.getElementById("insert").click()


    if ($summary) {
        $null = $b.Document.getElementById("customSummary").click()
        Start-Sleep -Seconds 1
        $null = $b.Document.getElementById("Summary").getElementsByTagName("textarea") |
            ForEach-Object { 
                $_.Value = "$Summary".Trim()
            }            
    }
    #$sh.SendKeys("{TAB}")

    if (-not $isEdit) {
    
    $CategoryLabels =  @{}
    $browser.Document.getElementsByTagName("label") | 
        Where-Object {
            $_.Id -like "CategoryLabel*"             
        } |
        ForEach-Object {
            $CategoryLabels[$_.InnerText] = $_.previousSibling.id
        }
    
    
    if (-not $categoryLabels[$Category]) {
        Write-Error "Category $category not found"
        return
    }

    # Select the category
    $null = $browser.Document.getElementById($CategoryLabels[$Category]).click()

    # Wait a sec for the new items to be loaded
    Start-Sleep -Seconds 1


    $SubcategoryLabels =  @{}
    $browser.Document.getElementsByTagName("label") | 
        Where-Object {
            $_.Id -like "SubCategoryLabel*"             
        } |
        ForEach-Object {
            $SubcategoryLabels[$_.InnerText] = $_.previousSibling.id
        }

    Remove-Item $tmpZipFile

    if (-not $SubcategoryLabels[$Subcategory]) {
        Write-Error "Subcategory $Subcategory not found"
        return
    }

    $null = $browser.Document.getElementById($SubCategoryLabels[$Subcategory]).click()

    $null = $browser.Document.getElementById("TermsOfUseAccepted").click()
    
    $OSLabels =  @{}
    $browser.Document.getElementsByTagName("label") | 
        Where-Object {
            $_.Id -like "OperatingSystemsLabel*"             
        } |
        ForEach-Object {
            $OSLabels[$_.InnerText] = $_.previousSibling.id
        }


    $lang = $browser.Document.getElementById("Language")
    

    foreach ($os in $OperatingSystem) {
        if (-not $OSLabels[$os]) {
            Write-Error "Operating System $os not found"
            continue            
        }
        $null = $browser.Document.getElementById($OSLabels[$os]).click()
        $null = $browser.Document.getElementById($OSLabels[$os]).fireEvent("onchange", $null)
    }
    if ($DisableQAndA) {
        $null = $browser.Document.getElementById("AllowQandA").click()
    }


    $l = $b.Document.getElementsByTagName("input") | Where-Object {$_.Name -eq 'License'  } 

    if ($MSLPL) {
        $l|Where-Object{ $_.Value -eq 'MSLPL'} | ForEach-Object { $_.click() }
    }


    foreach ($t in $tag) {
        $tagElement = $b.Document.getElementById("tagCategoryInput_GENERAL")
        $tagElement.Value = $t
        $null = $tagElement.nextSibling.nextSibling.click()
        Start-Sleep -Seconds 2
    }
    }


    Start-Sleep -Seconds 5
    $null = $b.Document.getElementById("uploadButton").click()


    Start-Sleep -Seconds 3
    $browser = Get-browser | Where-Object { $_.LocationUrl -like "http://gallery.technet.microsoft.com/*" }    
    $null = $browser.Document.getElementById("title").getElementsByTagName("input") | Where-Object { $_.Id -eq 'Title' } | ForEach-Object { $_.Value = $ModuleName } 

    Start-Sleep -Seconds 1
    $null = $browser.Document.getElementById("uploadButton").click()
    }
}

 
