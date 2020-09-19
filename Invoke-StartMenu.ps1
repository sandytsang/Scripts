$wshell = New-Object -ComObject wscript.shell -ErrorAction Stop
$wshell.SendKeys('^{ESC}')
$wshell = $null