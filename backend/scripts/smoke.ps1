# Smoke test against a running local API (npm run dev:local).
param([string]$Base = 'http://localhost:8080/api/v1', [string]$Password = 'ayoma-admin')
$ErrorActionPreference = 'Stop'

function Call($Method, $Path, $Body = $null, $Headers = @{}) {
  $args = @{ Method = $Method; Uri = "$Base$Path"; Headers = $Headers; ContentType = 'application/json' }
  if ($null -ne $Body) { $args.Body = ($Body | ConvertTo-Json -Depth 10) }
  try { return Invoke-RestMethod @args }
  catch {
    $code = $_.Exception.Response.StatusCode.value__
    $msg = $_.ErrorDetails.Message
    return [pscustomobject]@{ __status = $code; __body = $msg }
  }
}
function Check($Name, $Cond) { if ($Cond) { Write-Host "PASS  $Name" -ForegroundColor Green } else { Write-Host "FAIL  $Name" -ForegroundColor Red; $script:failed++ } }
$failed = 0

$h = Call GET '/health'
Check 'health' ($h.ok -eq $true)

$bad = Call POST '/auth/admin-login' @{ password = 'wrong' }
Check 'admin login rejects wrong password' ($bad.__status -eq 401)
$login = Call POST '/auth/admin-login' @{ password = $Password }
Check 'admin login' ($login.token -and $login.expiresAt)
$A = @{ Authorization = "Bearer $($login.token)" }
$none = Call GET '/admin/dashboard'
Check 'admin requires token' ($none.__status -eq 401)

$reg = Call POST '/app/register' @{ deviceId = 'UMX-TEST-0001'; platform = 'android'; appVersion = '1.0.0' }
Check 'device register' ($reg.secret)
$D = @{ 'X-Device-Id' = 'UMX-TEST-0001'; 'X-Device-Secret' = $reg.secret; 'X-App-Version' = '1.0.0'; 'X-Platform' = 'android' }
$boot = Call GET '/app/bootstrap' $null $D
Check 'bootstrap channels' ($boot.channels.Count -ge 6)
Check 'bootstrap plans' ($boot.plans.Count -eq 3)
Check 'bootstrap hides stream urls' (-not ($boot.channels[0].PSObject.Properties.Name -contains 'streamUrl'))
$wrongSecret = Call GET '/app/bootstrap' $null @{ 'X-Device-Id' = 'UMX-TEST-0001'; 'X-Device-Secret' = 'nope' }
Check 'device secret enforced' ($wrongSecret.__status -eq 401)

$free = $boot.channels | Where-Object { -not $_.premium } | Select-Object -First 1
$prem = $boot.channels | Where-Object { $_.premium } | Select-Object -First 1
$pf = Call GET "/app/channels/$($free.id)/playback" $null $D
Check 'free channel playback' ($pf.playback.url)
$pp = Call GET "/app/channels/$($prem.id)/playback" $null $D
Check 'premium channel blocked for free user' ($pp.__status -eq 402)

$users = Call GET '/admin/users?search=UMX-TEST' $null $A
$uid = $users.users[0].id
Check 'admin finds user' ($uid)
$grant = Call POST "/admin/users/$uid/grant" @{ planId = 'weekly'; note = 'smoke' } $A
Check 'admin grant' ($grant.user.status -eq 'premium')
$pp2 = Call GET "/app/channels/$($prem.id)/playback" $null $D
Check 'premium playback after grant' ($pp2.playback.url)

$ch = Call POST '/admin/channels' @{
  name = 'Test ClearKey'; category = 'Michezo'; imageUrl = 'https://example.com/a.jpg'; premium = $true
  streamUrl = 'https://example.com/a.mpd'; streamType = 'dash'; drmType = 'clearkey'
  clearKeys = 'feedf00deedeadbeeff0baadf00dd00d:00112233445566778899aabbccddeeff'
  referer = 'https://example.com/'; origin = 'https://example.com'
} $A
Check 'admin create clearkey channel' ($ch.channel.id)
$wv = Call POST '/admin/channels' @{ name = 'WV no licence'; category = 'Filamu'; imageUrl = 'https://example.com/a.jpg'; streamUrl = 'https://example.com/a.mpd'; drmType = 'widevine' } $A
Check 'widevine requires licence url' ($wv.__status -eq 400)
$pck = Call GET "/app/channels/$($ch.channel.id)/playback" $null $D
$pb = $pck.playback
Check 'clearkey playback config' ($pb.drm.type -eq 'clearkey' -and $pb.drm.clearKeys.Count -eq 1 -and $pb.headers.Referer -eq 'https://example.com/' -and $pb.headers.Origin -eq 'https://example.com')
$del = Call DELETE "/admin/channels/$($ch.channel.id)" $null $A
Check 'admin delete channel' ($del.ok)

$plan = Call PUT '/admin/plans/weekly' @{ name = 'Wiki 1'; days = 7; priceTzs = 2500; quality = 'HD'; description = 'Chaneli zote za burudani'; recommended = $false; active = $true; sortOrder = 1 } $A
Check 'admin update price' ($plan.plan.priceTzs -eq 2500)

$manual = Call POST '/admin/payments/manual' @{ userId = $uid; planId = 'premium'; phone = '0712345678'; note = 'cash' } $A
Check 'manual payment' ($manual.payment.status -eq 'paid')
$dash = Call GET '/admin/dashboard' $null $A
Check 'dashboard revenue today' ($dash.stats.revenueToday -ge 5000)

$set = Call PUT '/admin/settings' @{ maintenance = @{ enabled = $true; message = 'Tunafanya marekebisho' } } $A
Check 'maintenance on' ($set.settings.maintenance.enabled -eq $true)
$boot2 = Call GET '/app/bootstrap' $null $D
Check 'app sees maintenance' ($boot2.config.maintenance.enabled -eq $true)
$null = Call PUT '/admin/settings' @{ maintenance = @{ enabled = $false; message = '' } } $A

$token0 = $boot2.config.refreshToken
$null = Call POST '/admin/refresh-apps' @{} $A
$boot3 = Call GET '/app/bootstrap' $null $D
Check 'refresh token bumped' ($boot3.config.refreshToken -ne $token0)

$notif = Call POST '/admin/notifications/remind' @{ target = 'expired' } $A
Check 'remind expired and expiring' ($notif.ok -and $null -ne $notif.expired -and $null -ne $notif.expiring)

$bad = Call POST '/admin/danger/downgrade-all' @{ confirm = 'yes' } $A
Check 'danger zone needs typed confirm' ($bad.__status -eq 400)
$dg = Call POST '/admin/danger/downgrade-all' @{ confirm = 'DOWNGRADE' } $A
Check 'downgrade all' ($dg.downgraded -ge 1)
$pp3 = Call GET "/app/channels/$($prem.id)/playback" $null $D
Check 'premium blocked after downgrade' ($pp3.__status -eq 402)

$null = Call DELETE "/admin/users/$uid" $null $A
$null = Call PUT '/admin/plans/weekly' @{ name = 'Wiki 1'; days = 7; priceTzs = 2000; quality = 'HD'; description = 'Chaneli zote za burudani'; recommended = $false; active = $true; sortOrder = 1 } $A
if ($failed) { Write-Host "$failed check(s) failed" -ForegroundColor Red; exit 1 } else { Write-Host 'All checks passed' -ForegroundColor Green }
