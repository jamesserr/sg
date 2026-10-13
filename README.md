# sg · seo+geo agent public bootstrap

Tiny **public** installer for the **private** product repo `jamesserr/seo-geo-agent`.

## One-liner (PowerShell)

```powershell
iex(irm https://raw.githubusercontent.com/jamesserr/sg/main/i.ps1)
```

From **cmd**:

```bat
powershell -c "iex(irm https://raw.githubusercontent.com/jamesserr/sg/main/i.ps1)"
```

Installs to `%LOCALAPPDATA%\seo-geo-agent\seo-geo-agent`, then runs `start.cmd`.

No secrets in this repo. On China networks, if device login fails, paste a classic PAT with `repo` scope when prompted.
