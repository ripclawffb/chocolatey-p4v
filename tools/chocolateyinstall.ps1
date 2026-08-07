$packageName = 'p4v'
$version = 'r26.2'
$baseurl = "https://filehost.perforce.com/perforce/$version"
$url = "$baseurl/bin.ntx64/p4vinst64.exe"
# $checksum64 = ((Invoke-WebRequest "$baseurl/bin.ntx64/SHA256SUMS" -UseBasicParsing).RawContent.ToString().Split() | Select-String -Pattern 'p4vinst64.exe' -SimpleMatch -Context 1,0 ).ToString().Trim().Split()[0]
$checksum64 = '24e147557a4ac4092b2e80c1e182b3a640c5fe662ecc8ab95d468c323a789c28'

$packageArgs = @{
  packageName    = $packageName
  installerType	 = 'EXE'
  url            = $url
  checksum       = $checksum64
  checksumType   = 'sha256'
  silentArgs	 = '/s /v"/qn"'
}

Install-ChocolateyPackage @packageArgs
