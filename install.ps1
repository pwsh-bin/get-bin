if (-not ${env:GH_GET_HOME}) {
  ${env:GH_GET_HOME} = "${HOME}\.gh-get"
  [System.Environment]::SetEnvironmentVariable("GH_GET_HOME", ${env:GH_GET_HOME}, [System.EnvironmentVariableTarget]::User)
}

if (${env:PATH} -cnotlike "*${env:GH_GET_HOME}*") {
  ${env:PATH} = "${env:GH_GET_HOME};${env:PATH}"
  [System.Environment]::SetEnvironmentVariable("PATH", ${env:PATH}, [System.EnvironmentVariableTarget]::User)
}

if (-not (Test-Path -PathType "Container" -Path ${env:GH_GET_HOME})) {
  New-Item -Force -ItemType "Directory" -Path ${env:GH_GET_HOME} | Out-Null
}

Set-Variable -Name "ProgressPreference" -Value "SilentlyContinue"
Invoke-RestMethod -Method "Get" -Uri "https://raw.githubusercontent.com/pwsh-bin/gh-get/main/gh-get.ps1" -OutFile "${env:GH_GET_HOME}/gh-get.ps1"
Invoke-Expression -Command "gh-get.ps1"
