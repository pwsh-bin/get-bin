# get-bin

### install

```powershell
irm "https://raw.githubusercontent.com/pwsh-bin/get-bin/main/install.ps1" | iex
```

### usage

```powershell
get-bin self-install         - update get-bin to latest version
get-bin install helm@3.7     - install helm binary version 3.7
get-bin list                 - list all supported binaries
get-bin init                 - add binaries to current path
get-bin setup                - add init to current profile
```

### example

```powershell
❯ get-bin.ps1 install gsudo
[DEBUG] GET https://api.github.com/repos/gerardog/gsudo/releases
[DEBUG] GET https://github.com/gerardog/gsudo/releases/download/v1.3.0/gsudo.v1.3.0.zip
gsudo v1.3.0 (Branch.master.Sha.24fb735f547e1e5dd7aa22fdd77777fa8c923a1c)
Copyright(c) 2019-2021 Gerardo Grignoli and GitHub contributors

❯ get-bin.ps1 install gsudo@1.2
[DEBUG] GET https://api.github.com/repos/gerardog/gsudo/tags
[DEBUG] GET https://github.com/gerardog/gsudo/releases/download/v1.2.0/gsudo.v1.2.0.zip
gsudo v1.2.0 (Branch.master.Sha.2e8cc8ac942dd01df05479412b526b13ba22c1bb)
Copyright(c) 2019-2021 Gerardo Grignoli and GitHub contributors
```
