Set-Variable -Name "ProgressPreference" -Value "SilentlyContinue"

# ${APP_PATHS} = "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths"
${DEBUG} = Test-Path -PathType "Container" -Path (Join-Path -Path ${PSScriptRoot} -ChildPath ".git")
${PS1_HOME} = Join-Path -Path ${HOME} -ChildPath ".get-bin"
${PS1_FILE} = Join-Path -Path ${PS1_HOME} -ChildPath "get-bin.ps1"
${GITHUB_PATH} = Join-Path -Path ${PS1_HOME} -ChildPath ".github"
${STORE_PATH} = Join-Path -Path ${PS1_HOME} -ChildPath ".store"
${7ZIP} = Join-Path -Path ${ENV:PROGRAMFILES} -ChildPath "7-Zip" -AdditionalChildPath "7z.exe"
${VERSION} = "v0.4.2"
${HELP} = @"
Usage:
get-bin self-install         - update get-bin to latest version
get-bin install helm@3.7     - install helm binary version 3.7
get-bin list                 - list all supported binaries
get-bin init                 - add binaries to current path
get-bin setup                - add init to current profile

${VERSION}
"@

if (${args}.Count -eq 0) {
  Write-Host ${HELP}
  exit
}

function GetBinaries {
  if (${DEBUG}) {
    return (Get-Content -Path (Join-Path -Path ${PSScriptRoot} -ChildPath "binaries.json") | ConvertFrom-Json | Sort-Object -Property "binary")
  }
  else {
    ${uri} = "https://raw.githubusercontent.com/pwsh-bin/get-bin/main/binaries.json"
    ${binaries} = $null
    if (${DEBUG}) {
      Write-Host "[DEBUG] GET ${uri}"
    }
    try {
      ${binaries} = Invoke-RestMethod -Method "Get" -Uri ${uri}
    }
    catch {
      Write-Host "[ERROR] GET ${uri}:"
      Write-Host $_
      exit
    }
    return (${binaries} | Sort-Object -Property "binary")
  }
}

function GetGitHubToken {
  if (Test-Path -PathType "Leaf" -Path ${GITHUB_PATH}) {
    return (Import-Clixml -Path ${GITHUB_PATH})
  }
  else {
    Write-Host "Generate GitHub API Token w/o expiration and any scope: https://github.com/settings/tokens/new"
    Write-Host "Paste GitHub API Token:"
    ${token} = (Read-Host -AsSecureString)
    Export-Clixml -InputObject ${token} -Path ${GITHUB_PATH}
    return ${token}
  }
}

function GetGitHubTagNameFromReleases {
  param (
    ${RepositoryUri},
    ${Token}
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
      ${releases} = (Invoke-RestMethod -Method "Get" -Uri ${uri} -Authentication "Bearer" -Token ${Token} -Body @{
          "per_page" = 100
          "page"     = ${page}
        })
    }
    catch {
      Write-Host "[ERROR] GET ${uri}:"
      Write-Host $_
      exit
    }
    ${filtered_releases} = (${releases} | Where-Object -Property "prerelease" -eq $false)
    if (${filtered_releases}.Count -eq 0) {
      return $null
    }
    return ${filtered_releases}[0].tag_name
  }
}

function GetGitHubTagNameFromTags {
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
      ${tags} = (Invoke-RestMethod -Method "Get" -Uri ${uri} -Authentication "Bearer" -Token ${Token} -Body @{
          "per_page" = 100
          "page"     = ${page}
        })
    }
    catch {
      Write-Host "[ERROR] GET ${uri}:"
      Write-Host $_
      exit
    }
    ${filtered_tags} = (${tags} | Where-Object -Property "name" -clike ${Pattern})
    if (${filtered_tags}.Count -eq 0) {
      return $null
    }
    return ${filtered_tags}[0].name
  }
}

function GetVersionFromGitHub {
  param (
    ${Repository},
    ${Version},
    ${VersionPrefix}
  )
  ${repository_uri} = "https://api.github.com/repos/${Repository}"
  ${token} = (GetGitHubToken)
  ${tag_name} = $null
  if ($null -eq ${Version}) {
    ${tag_name} = (GetGitHubTagNameFromReleases -RepositoryUri ${repository_uri} -Token ${token})
    if ($null -eq ${tag_name}) {
      ${tag_name} = (GetGitHubTagNameFromTags -RepositoryUri ${repository_uri} -Token ${token} -Pattern "${VersionPrefix}*")
    }
  }
  else {
    ${tag_name} = (GetGitHubTagNameFromTags -RepositoryUri ${repository_uri} -Token ${token} -Pattern "${VersionPrefix}${Version}*")
  }
  if ($null -eq ${tag_name}) {
    Write-Host "[ERROR] Unsupported version argument."
    exit
  }
  return (${tag_name} -creplace ${VersionPrefix}, "")
}

function DownloadFromGitHub {
  param (
    ${Paths},
    ${Repository},
    ${UriTemplate},
    ${Version},
    ${VersionPrefix}
  )
  ${version} = (GetVersionFromGitHub -Repository ${Repository} -Version ${Version} -VersionPrefix ${VersionPrefix})
  New-Item -Force -ItemType "Directory" -Path ${STORE_PATH} | Out-Null
  ${directory} = Join-Path -Path ${STORE_PATH} -ChildPath ((${Repository} -creplace "/", "\") + "@${version}")
  if (-not (Test-Path -PathType "Container" -Path ${directory})) {
    New-Item -Force -ItemType "Directory" -Path ${directory} | Out-Null
    ${uri} = (${UriTemplate} -creplace "%version%", ${version})
    ${filename} = ${uri}.SubString(${uri}.LastIndexOf("/") + 1)
    ${outfile} = Join-Path -Path ${directory} -ChildPath ${filename}
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
  foreach (${path} in ${Paths}) {
    ${target} = Join-Path -Path ${directory} -ChildPath (${path}[0] -creplace "%version%", ${version})
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
    ${objects} = (GetBinaries | Where-Object -Property "binary" -clike "${binary}*")
    if (${objects}.Count -eq 0) {
      Write-Host "[ERROR] Unsupported binary argument."
      exit
    }
    ${object} = ${objects}[0]
    ${paths} = ${object}.paths
    ${repository} = ${object}.repository
    ${uriTemplate} = ${object}.uriTemplate
    ${versionPrefix} = ${object}.versionPrefix
    if ((${objects}.Count -gt 1) -and (${object}.binary.Length -ne ${binary}.Length)) {
      Write-Host ("[WARN] Found many supported binaries. Will proceed with " + ${object}.binary)
    }
    elseif (${binary} -ne ${object}.binary) {
      Write-Host ("[WARN] Found supported binary. Will proceed with " + ${object}.binary)
    }
    DownloadFromGitHub -Paths ${paths} -Repository ${repository} -UriTemplate ${uriTemplate} -Version ${version} -VersionPrefix ${versionPrefix}
  }
  { $_ -in "l", "list" } {
    Write-Host ((GetBinaries | Select-Object -ExpandProperty "binary") -join "`n")
  }
  { $_ -in "init" } {
    if (${env:PATH} -split ";" -cnotcontains ${PS1_HOME}) {
      ${env:PATH} += ";${PS1_HOME}"
    }
  }
  { $_ -in "setup" } {
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
