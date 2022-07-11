Set-Variable -Name "ProgressPreference" -Value "SilentlyContinue"

# ${APP_PATHS} = "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths"
${DEBUG} = (Test-Path -PathType "Container" -Path (Join-Path -Path ${PSScriptRoot} -ChildPath ".git"))
${PS1_HOME} = (Join-Path -Path ${HOME} -ChildPath ".get-bin")
${PS1_FILE} = (Join-Path -Path ${PS1_HOME} -ChildPath "get-bin.ps1")
${GITHUB_PATH} = (Join-Path -Path ${PS1_HOME} -ChildPath ".github")
${STORE_PATH} = (Join-Path -Path ${PS1_HOME} -ChildPath ".store")
${7ZIP} = (Join-Path -Path ${ENV:PROGRAMFILES} -ChildPath (Join-Path -Path "7-Zip" -ChildPath "7z.exe"))
${PER_PAGE} = 100
${VERSION} = "v0.5.1"
${HELP} = @"
Usage:
get-bin self-install                  - update get-bin to latest version
get-bin install helm@3.7              - install helm binary version 3.7
get-bin list-supported helm           - list all supported helm versions
get-bin list-supported                - list all supported binaries
get-bin init                          - add binaries to current path
get-bin setup                         - add init to current profile

${VERSION}
"@

# NOTE: common
if (${args}.Count -eq 0) {
  Write-Host ${HELP}
  if ((${Env:Path} -split ";") -cnotcontains ${PS1_HOME}) {
    Write-Host @"
---------------------------------------------------------
The script are not found in the current PATH, please run:
> ${PS1_HOME} init
---------------------------------------------------------
"@
  }
  if (${PSVersionTable}.PSVersion.Major -lt 7) {
    Write-Host @"
-----------------------------------------------------------------
The PowerShell Core is preferable to use this script, please run:
> winget install Microsoft.PowerShell
-----------------------------------------------------------------
"@
  }
  if ((Get-ExecutionPolicy -Scope "LocalMachine") -ne "RemoteSigned") {
    Write-Host @"
-------------------------------------------------------------------------------
The RemoteSigned execution policy is preferable to use this script, please run:
> Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine
-------------------------------------------------------------------------------
"@
  }
  exit
}

function GetBinaries {
  if (${DEBUG}) {
    return (Get-Content -Path (Join-Path -Path ${PSScriptRoot} -ChildPath "binaries.json") | ConvertFrom-Json | Sort-Object -Property "binary")
  }
  ${uri} = "https://raw.githubusercontent.com/pwsh-bin/get-bin/main/binaries.json"
  ${binaries} = $null
  if (${DEBUG}) {
    Write-Host "[DEBUG] GET ${uri}"
  }
  try {
    ${binaries} = (Invoke-RestMethod -Method "Get" -Uri ${uri})
  }
  catch {
    Write-Host "[ERROR] GET ${uri}:"
    Write-Host $_
    exit
  }
  return (${binaries} | Sort-Object -Property "binary")
}

# NOTE: common
function GetGitHubToken {
  if (Test-Path -PathType "Leaf" -Path ${GITHUB_PATH}) {
    return (Import-Clixml -Path ${GITHUB_PATH})
  }
  Write-Host @"
Generate GitHub API Token w/o expiration and public_repo scope: https://github.com/settings/tokens/new
Enter GitHub API Token:
"@
  ${token} = (Read-Host -AsSecureString)
  Export-Clixml -InputObject ${token} -Path ${GITHUB_PATH}
  return ${token}
}

# NOTE: common
function GetGitHubTagNamesFromReleases {
  param (
    ${RepositoryUri},
    ${Token},
    ${Pattern}
  )
  ${page} = 0
  ${uri} = "${RepositoryUri}/releases"
  while ($true) {
    ${page} += 1
    ${releases} = $null
    if (${DEBUG}) {
      Write-Host "[DEBUG] GET ${uri}"
    }
    try {
      # NOTE: compat
      ${headers} = @{
        "Authentication" = ("Bearer " + ${Token})
      }
      ${releases} = (Invoke-RestMethod -Method "Get" -Uri ${uri} -Headers ${headers} -Body @{
          "per_page" = ${PER_PAGE}
          "page"     = ${page}
        })
    }
    catch {
      Write-Host "[ERROR] GET ${uri}:"
      Write-Host $_
      exit
    }
    if (${releases}.Length -eq 0) {
      return $null
    }
    ${result} = (${releases} | Where-Object -FilterScript { ($_.prerelease -eq $false) -and ($_.tag_name -cmatch ${Pattern}) } | Select-Object -ExpandProperty "tag_name")
    if (${result}.Length -ne 0) {
      return ${result}
    }
  }
}

# NOTE: common
function GetGitHubTagNamesFromTags {
  param (
    ${RepositoryUri},
    ${Token},
    ${Pattern}
  )
  ${uri} = "${RepositoryUri}/tags"
  ${page} = 0
  while ($true) {
    ${page} += 1
    ${tags} = $null
    if (${DEBUG}) {
      Write-Host "[DEBUG] GET ${uri}"
    }
    try {
      # NOTE: compat
      ${headers} = @{
        "Authentication" = ("Bearer " + ${Token})
      }
      ${tags} = (Invoke-RestMethod -Method "Get" -Uri ${uri} -Headers ${headers} -Body @{
          "per_page" = ${PER_PAGE}
          "page"     = ${page}
        })
    }
    catch {
      Write-Host "[ERROR] GET ${uri}:"
      Write-Host $_
      exit
    }
    if (${tags}.Length -eq 0) {
      return $null
    }
    ${result} = (${tags} | Where-Object -Property "name" -cmatch ${Pattern} | Select-Object -ExpandProperty "name")
    if (${result}.Length -ne 0) {
      return ${result}
    }
  }
}

# NOTE: common
function GetGitHubTagNames {
  param (
    ${Repository},
    ${VersionPrefix},
    ${Version}
  )
  ${repository_uri} = "https://api.github.com/repos/${Repository}"
  ${token} = (GetGitHubToken)
  ${tag_names} = $null
  if ($null -eq ${Version}) {
    ${tag_names} = (GetGitHubTagNamesFromReleases -RepositoryUri ${repository_uri} -Token ${token} -Pattern "^${VersionPrefix}[-TZ\.\d]*$")
    if ($null -eq ${tag_names}) {
      ${tag_names} = (GetGitHubTagNamesFromTags -RepositoryUri ${repository_uri} -Token ${token} -Pattern "^${VersionPrefix}[-TZ\.\d]*$")
    }
  }
  else {
    ${tag_names} = (GetGitHubTagNamesFromTags -RepositoryUri ${repository_uri} -Token ${token} -Pattern "^${VersionPrefix}${Version}[-TZ\.\d]*$")
  }
  return ${tag_names}
}

function GetVersions {
  param (
    ${Object},
    ${Version}
  )
  ${repository} = ${Object}.repository
  ${versionPrefix} = ${Object}.versionPrefix
  ${tag_names} = (GetGitHubTagNames -Repository ${Repository} -VersionPrefix ${VersionPrefix} -Version ${Version})
  if (${tag_names}.Count -eq 0) {
    Write-Host "[ERROR] Maintenance required."
    exit
  }
  return (${tag_names} | ForEach-Object -Process { $_ -creplace ${VersionPrefix}, "" } )
}

function Install {
  param (
    ${Object},
    ${Version}
  )
  ${versions} = (GetVersions -Object ${Object} -Version ${Version})
  if (${versions}.Count -eq 0) {
    Write-Host "[ERROR] Unsupported version argument."
    exit
  }
  if (${versions} -is [string]) {
    ${version} = ${versions}
  }
  else {
    ${version} = ${versions}[0]
  }
  New-Item -Force -ItemType "Directory" -Path ${STORE_PATH} | Out-Null
  ${directory} = (Join-Path -Path ${STORE_PATH} -ChildPath ((${Object}.repository -creplace "/", "\") + "@${version}"))
  if (-not (Test-Path -PathType "Container" -Path ${directory})) {
    New-Item -Force -ItemType "Directory" -Path ${directory} | Out-Null
    ${uri} = (${Object}.uriTemplate -creplace "%version%", ${version})
    ${filename} = ${uri}.SubString(${uri}.LastIndexOf("/") + 1)
    ${outfile} = (Join-Path -Path ${directory} -ChildPath ${filename})
    if (${DEBUG}) {
      Write-Host "[DEBUG] GET ${uri}"
    }
    try {
      Invoke-RestMethod -Method "Get" -Uri ${uri} -OutFile ${outfile}
    }
    catch {
      Write-Host "[ERROR] GET ${uri}:"
      Write-Host $_
      exit
    }
    ${is_archive} = $false
    if (${filename}.EndsWith(".zip")) {
      ${is_archive} = $true
      Expand-Archive -Force -Path ${outfile} -DestinationPath ${directory}
    }
    elseif (${filename}.EndsWith(".tar.gz")) {
      ${is_archive} = $true
      ${command} = "tar --extract --file ${outfile} --directory ${directory}"
      Invoke-Expression -Command ${command} | Out-Null
    }
    elseif (${filename}.EndsWith(".7z")) {
      ${is_archive} = $true
      ${command} = "& '${7ZIP}' x -y -o${directory} ${outfile}"
      Invoke-Expression -Command ${command} | Out-Null
    }
    if (${is_archive} -eq $true) {
      Remove-Item -Force -Path ${outfile}
    }
  }
  foreach (${path} in ${Object}.paths) {
    ${target} = (Join-Path -Path ${directory} -ChildPath (${path}[0] -creplace "%version%", ${version}))
    if (-not (Test-Path -PathType "Leaf" -Path ${target})) {
      Write-Host ("[WARN] Binary " + ${target} + " does not exists. Will skip it.")
      continue
    }
    ${link} = (Join-Path -Path ${PS1_HOME} -ChildPath ${path}[1])
    New-Item -Force -ItemType "HardLink" -Path ${link} -Target ${target} | Out-Null
    # TODO
    # New-Item -Force -Path ${APP_PATHS} -Name ${path}[1] -Value ${target} | Out-Null
    # New-ItemProperty -Force -Path (Join-Path -Path ${APP_PATHS} -ChildPath ${path}[1]) -Name "Path" -Value (Split-Path -Path ${target}) | Out-Null
    if (${path}.Count -eq 3) {
      ${command} = (${link} + " " + ${path}[2])
      Invoke-Expression -Command ${command}
    }
  }
}

function GetObject {
  param (
    ${Binary}
  )
  ${objects} = (GetBinaries | Where-Object -Property "binary" -clike "${Binary}*")
  if (${objects}.Count -eq 0) {
    Write-Host "[ERROR] Unsupported binary argument."
    exit
  }
  ${object} = ${objects}[0]
  if ((${objects}.Count -gt 1) -and (${object}.binary.Length -ne ${Binary}.Length)) {
    Write-Host ("[WARN] Found many supported binaries. Will proceed with " + ${object}.binary)
  }
  elseif (${Binary} -ne ${object}.binary) {
    Write-Host ("[WARN] Found supported binary. Will proceed with " + ${object}.binary)
  }
  return ${object}
}

switch (${args}[0]) {
  { $_ -in "si", "self-install" } {
    ${uri} = "https://raw.githubusercontent.com/pwsh-bin/get-bin/main/install.ps1"
    ${command} = $null
    if (${DEBUG}) {
      Write-Host "[DEBUG] GET ${uri}"
    }
    try {
      ${command} = Invoke-RestMethod -Method "Get" -Uri ${uri}
    }
    catch {
      Write-Host "[ERROR] GET ${uri}:"
      Write-Host $_
      exit
    }
    Invoke-Expression -Command ${command}
  }
  { $_ -in "i", "install" } {
    if (${args}.Count -eq 1) {
      Write-Host "[ERROR] Missing binary argument."
      exit
    }
    ${binary}, ${version} = (${args}[1] -csplit "@")
    Install -Object (GetObject -Binary ${binary}) -Version ${version}
  }
  { $_ -in "ls", "list-supported" } {
    if (${args}.Count -eq 1) {
      Write-Host ((GetBinaries | Select-Object -ExpandProperty "binary") -join "`n")
      exit
    }
    ${binary}, ${version} = (${args}[1] -csplit "@")
    Write-Host ((GetVersions -Object (GetObject -Binary ${binary}) -Version ${version}) -join "`n")
  }
  { $_ -in "init" } {
    if ((${Env:Path} -split ";") -cnotcontains ${PS1_HOME}) {
      ${Env:Path} += ";${PS1_HOME}"
    }
  }
  # NOTE: common
  { $_ -in "setup" } {
    New-Item -Force -ItemType "File" -Path ${PROFILE} | Out-Null
    ${value} = "& '${PS1_FILE}' init"
    if (((Get-Content -Path ${PROFILE}) -split "`n") -cnotcontains ${value}) {
      Add-Content -Path ${PROFILE} -Value ${value}
      if (${DEBUG}) {
        Write-Host "[DEBUG] ${PROFILE}"
      }
    }
  }
  default {
    Write-Host "[ERROR] Unsupported command argument."
  }
}
