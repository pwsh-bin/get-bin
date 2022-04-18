Set-Variable -Name "ProgressPreference" -Value "SilentlyContinue"

${VERSION} = "v0.1.5"
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

${DEBUG} = Test-Path -Path "${PSScriptRoot}\.git" -PathType "Container"

${GITHUB_PATH} = "${env:GH_GET_HOME}\.github"

${TEMP_PATH} = "${env:GH_GET_HOME}\.temp"
if (-not (Test-Path -Path ${TEMP_PATH} -PathType "Container")) {
  New-Item -Path ${TEMP_PATH} -ItemType "Directory" | Out-Null
}

function GetBinaries {
  if (${DEBUG}) {
    return (Get-Content -Path "${PSScriptRoot}\binaries.json"
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
  if (Test-Path -Path ${GITHUB_PATH} -PathType "Leaf") {
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
  ${uri} = (${UriTemplate} -creplace "%version%", ${version})
  ${filename} = (${uri} -csplit "/")[-1]
  ${filepath} = "${TEMP_PATH}\${filename}"
  if (${DEBUG}) {
    Write-Host "[DEBUG] GET ${uri}"
  }
  try {
    Invoke-RestMethod -Method "Get" -Uri ${uri} -OutFile ${filepath}
  }
  catch {
    Write-Host "[ERROR] GET ${uri}:"
    Write-Host $_
    exit
  }
  if (${filename}.EndsWith(".zip")) {
    Expand-Archive -Force -Path ${filepath} -DestinationPath ${TEMP_PATH}
    Remove-Item -Force -Path ${filepath}
  }
  elseif (${filename}.EndsWith(".tar.gz")) {
    ${command} = "tar --extract --lzma --file ${filepath} --directory ${TEMP_PATH}"
    Invoke-Expression -Command ${command}
  }
  foreach (${path} in ${Paths}) {
    ${from} = "${TEMP_PATH}\$(${path}[0] -creplace "%version%", ${version})"
    if (-not (Test-Path -Path ${from} -PathType "Leaf")) {
      continue
    }
    ${to} = "${env:GH_GET_HOME}\$(${path}[1])"
    if (Test-Path -Path ${to} -PathType "Leaf") {
      Remove-Item -Force -Recurse -Path ${to}
    }
    Move-Item -Force -Path ${from} -Destination ${to}
    if (${path}.count -eq 3) {
      ${arguments} = ${path}[2]
      ${command} = "${to} ${arguments}"
      Invoke-Expression -Command ${command}
    }
  }
  Remove-Item -Force -Recurse -Path ${TEMP_PATH}
}

switch (${args}[0]) {
  { $_ -in "si", "self-install" } {
    ${uri} = "https://raw.githubusercontent.com/pwsh-bin/gh-get/main/install.ps1"
    ${command} = $null
    if (${DEBUG}) {
      Write-Host "[DEBUG] GET ${uri}"
    }
    try {
      ${command} = Invoke-RestMethod -Method "Get" -Uri ${uri} -OutFile ${filepath}
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
      Write-Host "[WARN] Found many supported binaries. Will proceed with $(${object}.binary)"
    }
    elseif (${binary} -ne ${object}.binary) {
      Write-Host "[WARN] Found supported binary. Will proceed with $(${object}.binary)"
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
