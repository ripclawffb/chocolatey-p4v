﻿$packageName = 'p4v'
$version = 'r25.1'
$baseurl = "https://filehost.perforce.com/perforce/$version"
$url = "$baseurl/bin.ntx64/p4vinst64.exe"
# $checksum64 = ((Invoke-WebRequest "$baseurl/bin.ntx64/SHA256SUMS" -UseBasicParsing).RawContent.ToString().Split() | Select-String -Pattern 'p4vinst64.exe' -SimpleMatch -Context 1,0 ).ToString().Trim().Split()[0]
$checksum64 = '17dddda36095a0be7bbfc0bd8b43438f42de8a5780dd375105f19d7d6622d3cb'

$packageArgs = @{
  packageName    = $packageName
  installerType	 = 'EXE'
  url            = $url
  checksum       = $checksum64
  checksumType   = 'sha256'
  silentArgs	 = '/s /v"/qn"'
}

Install-ChocolateyPackage @packageArgs
