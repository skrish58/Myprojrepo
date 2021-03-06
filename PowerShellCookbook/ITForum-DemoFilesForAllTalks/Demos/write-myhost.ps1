cmdlet Write-MyHost `
{
    param(
    [ParameterSetName("__AllParameterSets")]
    [Position(0)]
    [ValueFromPipeline]
    [System.Object]
    $Object,

    [ParameterSetName("__AllParameterSets")]
    [Switch]
    $NoNewline,

    [ParameterSetName("__AllParameterSets")]
    [System.Object]
    $Separator,

    [ParameterSetName("__AllParameterSets")]
    [System.ConsoleColor]
    $BackgroundColor)

    Begin
    { 
        $wrappedCmdlet = Microsoft.PowerShell.Core\get-command -type cmdlet Write-Host
        $scriptCmd = {& $wrappedCmdlet @CommandLineParameters }
        $steppablePipeline = $scriptCmd.GetSteppablePipeline()
        $steppablePipeline.Begin($cmdlet)        
    }

    Process
    {  $steppablePipeline.Process($_) }

    End
    {  $steppablePipeline.End() }
}

