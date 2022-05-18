Set-Variable -Name "ProgressPreference" -Value "SilentlyContinue"

${VERSION} = "v0.2.1"
${HELP} = @"
Usage:
gh-get self-install         - update gh-get to latest version
gh-get install helm@3.7     - install helm binary version 3.7
gh-get list                 - list all supported binaries

${VERSION}
"@

if (${args}.count -eq 0) {
  Write-Host ${HELP}
  exit
}

${DEBUG} = Test-Path -PathType "Container" -Path (Join-Path -Path ${PSScriptRoot} -ChildPath ".git")

${GITHUB_PATH} = Join-Path -Path ${env:GH_GET_HOME} -ChildPath ".github"

${STORE_PATH} = Join-Path -Path ${env:GH_GET_HOME} -ChildPath ".store"
if (-not (Test-Path -PathType "Container" -Path ${STORE_PATH})) {
  New-Item -Force -ItemType "Directory" -Path ${STORE_PATH} | Out-Null
}

${APP_PATHS} = "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths"

function GetBinaries {
  if (${DEBUG}) {
    return (Get-Content -Path (Join-Path -Path ${PSScriptRoot} -ChildPath "binaries.json")
    | ConvertFrom-Json
    | Sort-Object -Property "binary")
  }
  else {
    ${uri} = "https://raw.githubusercontent.com/pwsh-bin/gh-get/main/binaries.json"
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
    if (${releases}.count -eq 0) {
      return $null
    }
    ${filtered_releases} = (${releases}
      | Where-Object -Property "prerelease" -eq $false)
    if ($null -ne ${filtered_releases}) {
      return ${filtered_releases}[0].tag_name
    }
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
    if (${tags}.count -eq 0) {
      return $null
    }
    ${filtered_tags} = (${tags}
      | Where-Object -Property "name" -clike ${Pattern})
    if ($null -ne ${filtered_tags}) {
      return ${filtered_tags}[0].name
    }
  }
}

function DownloadFromGitHub {
  param (
    ${Paths},
    ${Repository},
    ${UriTemplate},
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
    return $null
  }
  ${version} = (${tag_name} -creplace ${VersionPrefix}, "")
  ${directory} = Join-Path -Path ${STORE_PATH} -ChildPath ((${Repository} -creplace "/", "\") + "@${version}")
  if (-not (Test-Path -PathType "Container" -Path ${directory})) {
    New-Item -Force -ItemType "Directory" -Path ${directory} | Out-Null
    ${uri} = (${UriTemplate} -creplace "%version%", ${version})
    ${filename} = (${uri} -csplit "/")[-1]
    ${outfile} = "${directory}/${filename}"
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
      Invoke-Expression -Command ${command}
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
    New-Item -Force -ItemType "HardLink" -Path (Join-Path -Path ${env:GH_GET_HOME} -ChildPath ${path}[1]) -Target ${target} | Out-Null
    # TODO
    # New-Item -Force -Path ${APP_PATHS} -Name ${path}[1] -Value ${target} | Out-Null
    # New-ItemProperty -Force -Path (Join-Path -Path ${APP_PATHS} -ChildPath ${path}[1]) -Name "Path" -Value (Split-Path -Path ${target}) | Out-Null
    if (${path}.count -eq 3) {
      ${command} = (${path}[1] + " " + ${path}[2])
      Invoke-Expression -Command ${command}
    }
  }
}

switch (${args}[0]) {
  { $_ -in "si", "self-install" } {
    ${uri} = "https://raw.githubusercontent.com/pwsh-bin/gh-get/main/install.ps1"
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
    if (${args}.count -eq 1) {
      Write-Host "[ERROR] Missing binary argument."
      exit
    }
    ${binary}, ${version} = (${args}[1] -csplit "@")
    ${objects} = (GetBinaries
      | Where-Object -Property "binary" -clike "${binary}*")
    if (${objects}.count -eq 0) {
      Write-Host "[ERROR] Unsupported binary argument."
      exit
    }
    ${object} = ${objects}[0]
    ${paths} = ${object}.paths
    ${repository} = ${object}.repository
    ${uriTemplate} = ${object}.uriTemplate
    ${versionPrefix} = ${object}.versionPrefix
    if ((${objects}.count -gt 1) -and (${object}.binary.length -ne ${binary}.length)) {
      Write-Host ("[WARN] Found many supported binaries. Will proceed with " + ${object}.binary)
    }
    elseif (${binary} -ne ${object}.binary) {
      Write-Host ("[WARN] Found supported binary. Will proceed with " + ${object}.binary)
    }
    DownloadFromGitHub -Paths ${paths} -Repository ${repository} -UriTemplate ${uriTemplate} -Version ${version} -VersionPrefix ${versionPrefix}
  }
  { $_ -in "l", "list" } {
    Write-Host ((GetBinaries
        | Select-Object -ExpandProperty "binary") -join "`n")
  }
  default {
    Write-Host "[ERROR] Unsupported command argument."
  }
}
