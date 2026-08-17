$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$listener = $null
$port = 0
for ($p = 8765; $p -le 8800; $p++) {
  try {
    $l = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $p)
    $l.Start()
    $listener = $l; $port = $p; break
  } catch { }
}
if (-not $listener) {
  Write-Host '无法启动本地服务（端口 8765-8800 均被占用），请关闭占用端口的程序后重试。'
  Read-Host '按回车键退出'
  exit 1
}
Write-Host '============================================================'
Write-Host '  XRD Analyze 已启动'
Write-Host "  访问地址: http://localhost:$port/index.html"
Write-Host '  浏览器将自动打开；若未打开请手动复制上面的地址到浏览器。'
Write-Host '  使用完毕后，关闭本窗口即可停止服务。'
Write-Host '============================================================'
Start-Process "http://localhost:$port/index.html"

$mime = @{ '.html'='text/html; charset=utf-8'; '.js'='text/javascript'; '.css'='text/css'; '.png'='image/png'; '.jpg'='image/jpeg'; '.ico'='image/x-icon'; '.svg'='image/svg+xml'; '.json'='application/json'; '.uxd'='application/octet-stream'; '.txt'='text/plain; charset=utf-8' }

while ($true) {
  $client = $null
  try { $client = $listener.AcceptTcpClient() } catch { break }
  try {
    $stream = $client.GetStream()
    $stream.ReadTimeout = 10000
    $ms = New-Object System.IO.MemoryStream
    $buf = New-Object byte[] 8192
    $headerDone = $false
    for ($i = 0; $i -lt 64; $i++) {
      $n = $stream.Read($buf, 0, $buf.Length)
      if ($n -le 0) { break }
      $ms.Write($buf, 0, $n)
      if ([Text.Encoding]::ASCII.GetString($ms.ToArray()) -match "`r`n`r`n") { $headerDone = $true; break }
    }
    $reqText = [Text.Encoding]::ASCII.GetString($ms.ToArray())
    $firstLine = (($reqText -split "`r`n")[0] -split "`n")[0]
    $parts = $firstLine -split ' '
    $rawUrl = if ($parts.Length -ge 2) { $parts[1] } else { '/' }
    $path = ($rawUrl -split '\?')[0]
    $path = [Uri]::UnescapeDataString($path)
    if ($path -eq '/' -or $path -eq '') { $path = '/index.html' }
    $rel = $path.TrimStart('/').Replace('/', '\')
    $file = Join-Path $root $rel
    $status = '200 OK'; $contentType = 'application/octet-stream'; $body = [byte[]]@()
    if (Test-Path -LiteralPath $file -PathType Leaf) {
      $ext = [IO.Path]::GetExtension($file).ToLower()
      if ($mime.ContainsKey($ext)) { $contentType = $mime[$ext] }
      $body = [IO.File]::ReadAllBytes($file)
    } else {
      $status = '404 Not Found'
      $body = [Text.Encoding]::UTF8.GetBytes('Not Found')
    }
    $header = "HTTP/1.1 $status`r`nContent-Type: $contentType`r`nContent-Length: $($body.Length)`r`nConnection: close`r`nCache-Control: no-store`r`n`r`n"
    $hbytes = [Text.Encoding]::ASCII.GetBytes($header)
    $stream.Write($hbytes, 0, $hbytes.Length)
    $stream.Write($body, 0, $body.Length)
    $stream.Flush()
  } catch { }
  finally { try { if ($client) { $client.Close() } } catch { } }
}