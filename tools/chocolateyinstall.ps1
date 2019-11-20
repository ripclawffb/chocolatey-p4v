$packageName = 'p4v'
$version = 'r19.2'
$baseurl = "https://cdist2.perforce.com/perforce/$version"
$url32 = "$baseurl/bin.ntx86/p4vinst.exe"
$url64 = "$baseurl/bin.ntx64/p4vinst64.exe"
$checksum32 = ((Invoke-WebRequest "$baseurl/bin.ntx86/SHA256SUMS" -UseBasicParsing).RawContent.ToString().Split() | Select-String -Pattern 'p4vinst.exe' -SimpleMatch -Context 1,0 ).ToString().Trim().Split()[0]
$checksum64 = ((Invoke-WebRequest "$baseurl/bin.ntx64/SHA256SUMS" -UseBasicParsing).RawContent.ToString().Split() | Select-String -Pattern 'p4vinst64.exe' -SimpleMatch -Context 1,0 ).ToString().Trim().Split()[0]

$packageArgs = @{
  packageName    = $packageName
  installerType	 = 'EXE'
  url            = $url32
  url64Bit       = $url64
  checksum       = $checksum32
  checksum64     = $checksum64
  checksumType   = 'sha256'
  checksumType64 = 'sha256'
  silentArgs	 = '/s /v"/qn"'
}

Install-ChocolateyPackage @packageArgs
