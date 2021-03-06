function Get-MyTechnetContribution
{
    <#
    .Synopsis
        Gets your Technet contributions
    .Description
        Gets the name and URL of your contributions from TechNet
    #>
    param(
    )

    $n = 1
    $b = Open-Browser
    do {
        $b = $b | Set-BrowserLocation -Url "http://gallery.technet.microsoft.com/site/mydashboard?pageIndex=$n" 
        $h = $b.Document.getElementById("Contributions_Content").innerHtml 

        $modulelinks = Get-Web -Html $h -Tag 'a' | Where-Object { $_.Xml.Href -like "/*" -and $_.Xml.Href -notlike "/*/*" } 

        foreach ($m in $modulelinks) {
            New-Object PSObject -Property @{
                Name = $m.Xml.InnerText
                Url = "http://gallery.technet.microsoft.com" + $m.Xml.Href
            }
        }
        $n++
        
    } while ($modulelinks)


    Get-browser | Where-Object { $_.LocationUrl -like "http://gallery.technet.microsoft.com/*" } | ForEach-Object { $_.Quit() } 
} 
