function Get-MyTechnetProfile
{
    <#
    .Synopsis
        Gets your Technet profile 
    .Description
        Gets your Technet profile information
    #>
    param(
    )

    $n = 1
    $b = Open-Browser -Url "http://gallery.technet.microsoft.com/site/mydashboard?pageIndex=$n"  | Wait-Browser
    $h = $b.Document.body.innerHtml 
    $profileLink = Get-Web -Html $h -Tag 'a' | Where-Object { $_.Xml.InnerText -eq 'View Profile' } 
    $b = $b | Set-BrowserLocation -Url $profileLink.Xml.Href

    $h = $b.Document.documentElement.innerHtml 

    $statsLink = Get-Web -html $h -Tag script | 
        Where-Object { $_.Tag -like "*getStatsWhenReady*" }| 
        ForEach-Object {$_.Tag -split '"'} | 
        Where-Object { $_ -like "http*" } |
        Select-Object -First 1 

    $activitiesLink = Get-Web -Html $h -Tag 'link' |
        Where-Object { $_.Xml.Type -like "*/rss*" -and $_.Xml.Href -like "*/activities/feed*" } |
        ForEach-Object { $_.Xml.Href }

    $profileName = $activitiesLink.Substring($activitiesLink.LastIndexOf("=") + 1)
    

    $jsonStats = Get-Web -Url $statsLink -AsJson

    $jsonStats = $jsonStats.(@($jsonStats.psobject.Properties)[0].Name)

    $pointsByApplication = $jsonStats.Groups | Where-Object { $_.Key -eq 'PointsbyApplication' } | ForEach-Object {$_.Statistics }
    $activitiesByApplication = $jsonStats.Groups | Where-Object { $_.Key -eq 'ActivitiesbyApplication' } | ForEach-Object {$_.Statistics }
    $galleries = $jsonStats.Groups | Where-Object { $_.Key -eq 'Galleries' } | ForEach-Object {$_.Statistics }
    $blogs =  $jsonStats.Groups | Where-Object { $_.Key -eq 'Blogs' } | ForEach-Object {$_.Statistics }
    $translation =  $jsonStats.Groups | Where-Object { $_.Key -eq 'TranslationWiki' } | ForEach-Object {$_.Statistics }
    $wiki =  $jsonStats.Groups | Where-Object { $_.Key -eq 'TechnetWiki' } | ForEach-Object {$_.Statistics }
    $forums =  $jsonStats.Groups | Where-Object { $_.Key -eq 'Forums' } | ForEach-Object {$_.Statistics }


    $dataObject = New-Object PSObject -Property @{
        Name = $profileName
        Points= $pointsByApplication | Measure-Object -Sum -Property Value | Select-Object -ExpandProperty Sum
    }

    foreach ($obj in $galleries, $blogs, $translation, $wiki, $forums) {
        foreach ($o in $obj) {
            Add-Member -inputObject $dataObject -MemberType NoteProperty -Name $o.Key -Value $o.Value
        }
    }

    $dataObject
    $b.Quit()

        
} 
 
