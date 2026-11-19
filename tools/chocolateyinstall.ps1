$packageName = 'p4v'
$version = 'r26.3'
$baseurl = "https://filehost.perforce.com/perforce/$version"
$url = "$baseurl/bin.ntx64/p4vinst64.exe"
# $checksum64 = ((Invoke-WebRequest "$baseurl/bin.ntx64/SHA256SUMS" -UseBasicParsing).RawContent.ToString().Split() | Select-String -Pattern 'p4vinst64.exe' -SimpleMatch -Context 1,0 ).ToString().Trim().Split()[0]
$checksum64 = '7ec701333a20bd91f1f94c8c22a46e6960126620099655a3c285c0b67588312b'

$packageArgs = @{
  packageName    = $packageName
  installerType	 = 'EXE'
  url            = $url
  checksum       = $checksum64
  checksumType   = 'sha256'
  silentArgs	 = '/s /v"/qn"'
}

Install-ChocolateyPackage @packageArgs
