#####################################################################################################################
#          Script used to get PerfMon counter data from the local computer and export the data                      #
#          Script will eventually run from 7am to 5pm via scheduled task                                            #
#          During this time it will do a perfmon check every 900 seconds (15 minutes) 40 times (maxsamples)         #
#####################################################################################################################
clear-host
start-transcript "d:\Excluded_From_Backups\PerfmonStats\performance.txt"
###################################################################################
#          Define Variables#######Also creates a new directory based on the date  #
#          Interval in seconds, 900 seconds = 15 minutes                          #
###################################################################################
$date = get-date -format "MM_dd_yyyy"
$exportlocation = New-Item c:\logs\$date -type directory -force
$proccounter = "\Processor(*)\% Processor Time"
$memcounter = "\Memory\Available Bytes"
$diskcounter = "\LogicalDisk(*)\Current Disk Queue Length"
$interval = 900
$maxsmpl = 40
################################################################################################################################################################################
get-counter -counter $proccounter,$memcounter,$diskcounter -SampleInterval $interval -MaxSamples $maxsmpl | export-counter -path $exportlocation\perf.blg -force
get-counter -counter $proccounter,$memcounter,$diskcounter -SampleInterval $interval -MaxSamples $maxsmpl | export-counter -path $exportlocation\perf.csv -Fileformat csv -force
#################################################################################################################################################################################
#           csv file to convert   #
###################################
$csv = "$exportlocation\perf.csv";
###################################
#           xml file to create    #
###################################
$xml = "$exportlocation\perf.xml";
##################################################
#           convert csv file to xml file         #
##################################################
Import-Csv -Path $csv | Export-Clixml -Path $xml;
##################################################
stop-transcript