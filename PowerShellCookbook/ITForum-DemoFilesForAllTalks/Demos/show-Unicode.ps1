# japanese.ps1
Data Sunny {
    ConvertFrom-StringData @'
    English = It is sunny today
    Japanese =それは今日の晴れ
    Arabic = اليوم مشمس
'@
}
"English  " + $Sunny.English
"Japanese " + $Sunny.Japanese
"Arabic   " + $SUnny.Arabic
