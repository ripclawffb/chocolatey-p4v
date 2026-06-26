$packageName = 'p4v'
$version = 'r26.2'
$baseurl = "https://filehost.perforce.com/perforce/$version"
$url = "$baseurl/bin.ntx64/p4vinst64.exe"
# $checksum64 = ((Invoke-WebRequest "$baseurl/bin.ntx64/SHA256SUMS" -UseBasicParsing).RawContent.ToString().Split() | Select-String -Pattern 'p4vinst64.exe' -SimpleMatch -Context 1,0 ).ToString().Trim().Split()[0]
$checksum64 = '80c592bd948ffe22799d005302eca50dd5780e80f7c08f3b54436c3867c9b64d'

$packageArgs = @{
  packageName    = $packageName
  installerType	 = 'EXE'
  url            = $url
  checksum       = $checksum64
  checksumType   = 'sha256'
  silentArgs	 = '/s /v"/qn"'
}

Install-ChocolateyPackage @packageArgs
