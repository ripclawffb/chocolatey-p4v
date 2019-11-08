$packageName = 'p4v'
$url32 = 'https://cdist2.perforce.com/perforce/r19.2/bin.ntx86/p4vinst.exes'
$url64 = 'https://cdist2.perforce.com/perforce/r19.2/bin.ntx64/p4vinst64.exe'

$packageArgs = @{
  packageName    = $packageName
  installerType	 = 'EXE'
  url            = $url32
  url64Bit       = $url64
  silentArgs	 = '/s /v"/qn"'
}

Install-ChocolateyPackage @packageArgs