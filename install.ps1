Set-Variable -Name "ProgressPreference" -Value "SilentlyContinue"
${PS1_HOME} = Join-Path -Path ${HOME} -ChildPath ".gh-get"
${PS1_FILE} = Join-Path -Path ${PS1_HOME} -ChildPath "gh-get.ps1"
New-Item -Force -ItemType "Directory" -Path ${PS1_HOME} | Out-Null
Invoke-RestMethod -Method "Get" -Uri "https://raw.githubusercontent.com/pwsh-bin/gh-get/main/gh-get.ps1" -OutFile ${PS1_FILE}
Invoke-Expression -Command ${PS1_FILE}
