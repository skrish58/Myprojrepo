$logPath = "\\fileshare\bde_share\s6\server_logs\"
$log = "application"
$computers = "DC1"

# Start HTML Output file style
$style = "<style>"
$style = $style + "Body{background-color:white;font-family:Arial;font-size:10pt;}"
$style = $style + "Table{border-width: 1px; border-style: solid; border-color: black; border-collapse: collapse;}"
$style = $style + "TH{border-width: 1px; padding: 2px; border-style: solid; border-color: black; background-color: #cccccc;}"
$style = $style + "TD{border-width: 1px; padding: 5px; border-style: solid; border-color: black; background-color: white;}"
$style = $style + "</style>"

# End HTML Output file style

$date = get-date -format M.d.yyyy

$now = get-date
$subtractDays = New-Object System.TimeSpan 5,0,0,0,0
$then = $Now.Subtract($subtractDays)

$systemErrors = Get-EventLog -Computername $computers -LogName $log -After $then -Before $now -EntryType Error |
select EventID,MachineName,Message,Source,TimeGenerated

$systemErrors | ConvertTo-HTML -head $style | Out-File "$logPath\$computers-$log-$date.htm"
