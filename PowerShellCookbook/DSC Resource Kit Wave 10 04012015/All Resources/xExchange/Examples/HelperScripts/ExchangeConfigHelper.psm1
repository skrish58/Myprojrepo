#Takes a Servers.Csv file generated by the Exchange Server Role Requirements Calculator and turns the listed disks
#into a DbMap which can be used with xExchAutoMountPoint.
#
#Params:
#ServersCsvPath: The full path to the Servers.csv file to read
#ServerNameInCsv: The name of the server in the Servers.csv file that matches this server. For instance, if SRV-##-01 was a server name in Servers.csv, but this server is SRV-01-01, you would pass in 'SRV-##-01' to correctly find the right set of databases
#DbNameReplacements: Any replacements that should be in the database name. For instance, if a database name in the file was DAG-##-DB01, I would specificy: @{"##" = "01 }. This would replace all database name instance of ## with 01
function DBMapFromServersCsv
{
    param([string]$ServersCsvPath, [string]$ServerNameInCsv, [Hashtable]$DbNameReplacements = @{})

    #Output variable for the function
    [string[]]$dbMapOut = @()

    if ((Test-Path -LiteralPath "$($ServersCsvPath)") -eq $true)
    {
        $serversCsv = Import-Csv -LiteralPath "$($ServersCsvPath)"

        $foundServer = $false

        #Loop through until we find a matching server
        for ($i = 0; $i -lt $serversCsv.Count -and $foundServer -eq $false; $i++)
        {           
            if ($serversCsv[$i].ServerName -like $ServerNameInCsv)
            {
                #We found a match, proceed
                $foundServer = $true

                $dbPerVolume = $serversCsv[$i].DbPerVolume

                if ($dbPerVolume -eq 0)
                {
                    throw "DbPerVolume for server '$($ServerNameInCsv)'is 0"
                }

                #Turn the DbMap from string into an array
                $dbMapIn = $serversCsv[$i].DbMap.Split(',')

                if ($dbMapIn.Count -gt 0)
                {
                    #Loop through the DbMap in increments of dbPerVolume and figure out which DB's will go on a single disk
                    for ($j = 0; $j -lt $dbMapIn.Count; $j += $dbPerVolume)
                    {
                        [string]$currentDisk = ""

                        #Loop through the individual DB's for this disk
                        for ($k = $j; $k -lt $j + $dbPerVolume; $k++)
                        {
                            #This isn't the first DB on the disk so prepend a comma
                            if ($k -gt $j)
                            {
                                $currentDisk += ","
                            }

                            #Make any requested replacements in the DB name
                            $currentDb = StringReplaceFromHashtable -StringIn $dbMapIn[$k] -Replacements $DbNameReplacements

                            #Add the db to the current disk string
                            $currentDisk += $currentDb
                        }

                        #Add the finished disk to the output variable
                        $dbMapOut += $currentDisk
                    }
                }
                else
                {
                    throw "No databases found in DbMap for server '$($ServerNameInCsv)' in file: $($ServersCsvPath)"
                }
            }
        }

        if ($foundServer -eq $false)
        {
            throw "Unable to find server '$($ServerNameInCsv)' in file: $($ServersCsvPath)"
        }
    }
    else
    {
        throw "Unable to access file at path: $($ServersCsvPath)"
    }

    return $dbMapOut
}

#Takes a MailboxDatabases.csv file generated by the Exchange Server Role Requirements Calculator and returns a list of databases and their properties.
#This can then be used as input for the xExchMailboxDatabase resource.
#
#Params:
#MailboxDatabasesCsvPath: The full path to the MailboxDatabases.csv file to read
#ServerNameInCsv: The name of the server in the MailboxDatabases.csv file that matches this server. For instance, if SRV-##-01 was a server name in Servers.csv, but this server is SRV-01-01, you would pass in 'SRV-##-01' to correctly find the right set of databases
#DbNameReplacements: Any replacements that should be in the database name, log path, or edb path. For instance, if a database name in the file was DAG-##-DB01, I would specificy: @{"##" = "01 }. This would replace all database name instance of ## with 01
function DBListFromMailboxDatabasesCsv
{
    param([string]$MailboxDatabasesCsvPath, [string]$ServerNameInCsv, [Hashtable]$DbNameReplacements = @{})

    #Output variable for the function
    [Array]$dbList = @()

    if ((Test-Path -LiteralPath "$($MailboxDatabasesCsvPath)") -eq $true)
    {
        $databasesCsv = Import-Csv -LiteralPath "$($MailboxDatabasesCsvPath)"

        #Loop through each database, and if it belongs to this server, at it to the list
        for ($i = 0; $i -lt $databasesCsv.Count; $i++)
        {
            if ($databasesCsv[$i].Server -like $ServerNameInCsv)
            {
                $dbIn = $databasesCsv[$i]

                #Build a custom object to hold all the DB props
                $currentDb = New-Object PSObject

                $currentDb | Add-Member NoteProperty Name (StringReplaceFromHashtable -StringIn $dbIn.Name -Replacements $DbNameReplacements)
                $currentDb | Add-Member NoteProperty DBFilePath (StringReplaceFromHashtable -StringIn $dbIn.DBFilePath -Replacements $DbNameReplacements)
                $currentDb | Add-Member NoteProperty LogFolderPath (StringReplaceFromHashtable -StringIn $dbIn.LogFolderPath -Replacements $DbNameReplacements)
                $currentDb | Add-Member NoteProperty DeletedItemRetention $dbIn.DeletedItemRetention
                $currentDb | Add-Member NoteProperty GC $dbIn.GC
                $currentDb | Add-Member NoteProperty OAB $dbIn.OAB
                $currentDb | Add-Member NoteProperty RetainDeletedItemsUntilBackup $dbIn.RetainDeletedItemsUntilBackup
                $currentDb | Add-Member NoteProperty IndexEnabled $dbIn.IndexEnabled
                $currentDb | Add-Member NoteProperty CircularLoggingEnabled $dbIn.CircularLoggingEnabled
                $currentDb | Add-Member NoteProperty ProhibitSendReceiveQuota $dbIn.ProhibitSendReceiveQuota
                $currentDb | Add-Member NoteProperty ProhibitSendQuota $dbIn.ProhibitSendQuota
                $currentDb | Add-Member NoteProperty IssueWarningQuota $dbIn.IssueWarningQuota
                $currentDb | Add-Member NoteProperty AllowFileRestore $dbIn.AllowFileRestore
                $currentDb | Add-Member NoteProperty BackgroundDatabaseMaintenance $dbIn.BackgroundDatabaseMaintenance
                $currentDb | Add-Member NoteProperty IsExcludedFromProvisioning $dbIn.IsExcludedFromProvisioning
                $currentDb | Add-Member NoteProperty IsSuspendedFromProvisioning $dbIn.IsSuspendedFromProvisioning
                $currentDb | Add-Member NoteProperty MailboxRetention $dbIn.MailboxRetention
                $currentDb | Add-Member NoteProperty MountAtStartup $dbIn.MountAtStartup
                $currentDb | Add-Member NoteProperty EventHistoryRetentionPeriod $dbIn.EventHistoryRetentionPeriod
                $currentDb | Add-Member NoteProperty AutoDagExcludeFromMonitoring $dbIn.AutoDagExcludeFromMonitoring
                $currentDb | Add-Member NoteProperty CalendarLoggingQuota $dbIn.CalendarLoggingQuota
                $currentDb | Add-Member NoteProperty IsExcludedFromInitialProvisioning $dbIn.IsExcludedFromInitialProvisioning
                $currentDb | Add-Member NoteProperty DataMoveReplicationConstraint $dbIn.DataMoveReplicationConstraint
                $currentDb | Add-Member NoteProperty RecoverableItemsQuota $dbIn.RecoverableItemsQuota
                $currentDb | Add-Member NoteProperty RecoverableItemsWarningQuota $dbIn.RecoverableItemsWarningQuota

                $dbList += $currentDb
            }
        }
    }
    else
    {
        throw "Unable to access file at path: $($MailboxDatabasesCsvPath)"
    }

    return $dbList
}

#Takes a MailboxDatabaseCopies.csv file generated by the Exchange Server Role Requirements Calculator and returns a list of databases and their properties.
#This can then be used as input for the xExchMailboxDatabase resource.
#
#Params:
#MailboxDatabaseCopiesCsvPath: The full path to the MailboxDatabaseCopies.csv file to read
#ServerNameInCsv: The name of the server in the MailboxDatabaseCopies.csv file that matches this server. For instance, if SRV-##-01 was a server name in Servers.csv, but this server is SRV-01-01, you would pass in 'SRV-##-01' to correctly find the right set of databases
#DbNameReplacements: Any replacements that should be in the database name, log path, or edb path. For instance, if a database name in the file was DAG-##-DB01, I would specificy: @{"##" = "01 }. This would replace all database name instance of ## with 01
function DBListFromMailboxDatabaseCopiesCsv
{
    param([string]$MailboxDatabaseCopiesCsvPath, [string]$ServerNameInCsv, [Hashtable]$DbNameReplacements = @{})

    #Output variable for the function
    [Array]$dbList = @()

    if ((Test-Path -LiteralPath "$($MailboxDatabaseCopiesCsvPath)") -eq $true)
    {
        $databasesCsv = Import-Csv -LiteralPath "$($MailboxDatabaseCopiesCsvPath)"

        #Loop through each database, and if it belongs to this server, at it to the list
        for ($i = 0; $i -lt $databasesCsv.Count; $i++)
        {
            if ($databasesCsv[$i].Server -like $ServerNameInCsv)
            {
                $dbIn = $databasesCsv[$i]

                #Build a custom object to hold all the DB props
                $currentDb = New-Object PSObject

                $currentDb | Add-Member NoteProperty Name (StringReplaceFromHashtable -StringIn $dbIn.Name -Replacements $DbNameReplacements)
                $currentDb | Add-Member NoteProperty ActivationPreference $dbIn.ActivationPreference
                $currentDb | Add-Member NoteProperty ReplayLagTime $dbIn.ReplayLagTime
                $currentDb | Add-Member NoteProperty TruncationLagTime $dbIn.TruncationLagTime

                $dbList += $currentDb
            }
        }
    }
    else
    {
        throw "Unable to access file at path: $($MailboxDatabasesCsvPath)"
    }

    return $dbList
}

#Takes a string, makes any replacements specified in the hashtable, and then returns the new string
function StringReplaceFromHashtable
{
    param([string]$StringIn, $Replacements = @{})

    if ($Replacements.Count -gt 0)
    {
        foreach ($key in $Replacements.Keys)
        {
            $StringIn = $StringIn.Replace($key, $Replacements[$key])
        }
    }

    return $StringIn
}

Export-ModuleMember -Function *
