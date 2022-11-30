${binaries} = (Get-Content -Path (Join-Path -Path ${PSScriptRoot} -ChildPath 'binaries.json') | ConvertFrom-Json)
foreach (${binary} in ${binaries}) {
  .\get-bin.ps1 ls ${binary}.binary
}
foreach (${binary} in ${binaries}) {
  .\get-bin.ps1 i ${binary}.binary
}
