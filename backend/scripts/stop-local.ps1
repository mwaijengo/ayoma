# Stops the local API and its embedded Postgres started by `npm run dev:local`.
Get-CimInstance Win32_Process -Filter "Name='node.exe'" |
  Where-Object { $_.CommandLine -match 'localServer|dev:local' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
Get-CimInstance Win32_Process -Filter "Name='postgres.exe'" |
  Where-Object { $_.CommandLine -match '\.local-pg' -or $_.ExecutablePath -match 'embedded-postgres' } |
  ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue }
