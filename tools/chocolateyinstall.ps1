$packageName = 'p4v'
$version = 'r23.4'
$baseurl = "https://cdist2.perforce.com/perforce/$version"
$url = "$baseurl/bin.ntx64/p4vinst64.exe"
# $checksum64 = ((Invoke-WebRequest "$baseurl/bin.ntx64/SHA256SUMS" -UseBasicParsing).RawContent.ToString().Split() | Select-String -Pattern 'p4vinst64.exe' -SimpleMatch -Context 1,0 ).ToString().Trim().Split()[0]
$checksum64 = 'e40616c2852271f26294fbf3e16a880dcba4b1850ab4418df685e861ffe4e0c8'

$packageArgs = @{
  packageName    = $packageName
  installerType	 = 'EXE'
  url            = $url
  checksum       = $checksum64
  checksumType   = 'sha256'
  silentArgs	 = '/s /v"/qn"'
}

Install-ChocolateyPackage @packageArgs
