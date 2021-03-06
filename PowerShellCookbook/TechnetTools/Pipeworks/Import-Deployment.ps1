function Import-Deployment
{
    <#
    .Synopsis

    .Description

    #>
    [CmdletBinding(DefaultParameterSetName='AllDeployments')]
    [OutputType([Management.Automation.PSModuleInfo])]
    param(
    # The name of the deployment 
    [Parameter(Mandatory=$true,ValueFromPipeline=$true,ValueFromPipelineByPropertyName=$true,ParameterSetName='SpecificDeployments')]
    [string]
    $Name
    )

    begin {
        $deployments = Get-Deployment
        
        $progId = Get-Random
        $loadModule = {            
            $c++
            $perc = ($c / $total) * 100
            
            $in = $_
            Write-Progress "Importing Modules" $in.Name -PercentComplete $perc -Id $progId
            $module = @(Import-Module $_.Path -PassThru -Global -Force)

            if ($module.ExportedFunctions.Keys -like "*SecureSetting*") {
                $reloadPipeworks = $true
                Import-Module Pipeworks -Force -Global
            }

            if ($module.Count -gt 1 ) {
                $module | Where-Object {$_.Name -eq $in.Name } 
            } else {
                $module
            }
        }

    }

    process {
        $reloadPipeworks = $false
        if ($PSCmdlet.ParameterSetName -eq 'AllDeployments') {
            $deploymentsToLoad = $deployments |
                Sort-Object Name
        } else {
            $deploymentsToLoad = $deployments|                
                Where-Object { $_.Name -like $name } |
                Sort-Object Name
        }
        if ($deploymentsToLoad) {
            $c =0; $total = @($deploymentsToLoad).Count 
            foreach ($_ in $deploymentsToLoad) {
                . $loadModule
            }
        }
    }
} 
