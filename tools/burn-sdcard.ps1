param(
    [Parameter(Mandatory = $true)][string]$Image,
    [Parameter(Mandatory = $true)][int]$DiskNumber,
    [switch]$DryRun,
    [switch]$ConfirmWrite
)

# 把整盘镜像原样写到 SD 卡（Windows 端，等价于 Linux 的 dd）。
#   .\tools\burn-sdcard.ps1 -Image out\imx6ull-mini-sdcard.img -DiskNumber 3
# 需要管理员权限（直接写 \\.\PhysicalDriveN）。写错盘会毁掉那块盘，务必核对 -DiskNumber。

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $Image)) { throw "镜像不存在：$Image" }
$img = Get-Item $Image
$size = $img.Length
$disk = Get-Disk -Number $DiskNumber
if (-not $disk) { throw "找不到磁盘 $DiskNumber" }

Write-Host "镜像 : $($img.FullName)  $([math]::Round($size/1MB)) MB"
Write-Host "目标 : Disk $DiskNumber  $($disk.FriendlyName)  $([math]::Round($disk.Size/1GB,1)) GB  $($disk.BusType)  $($disk.OperationalStatus)"
Get-Partition -DiskNumber $DiskNumber -ErrorAction SilentlyContinue |
    Select-Object PartitionNumber, DriveLetter, @{n = 'SizeGB'; e = { [math]::Round($_.Size / 1GB, 2) } }, Type |
    Format-Table -AutoSize | Out-Host

if ($disk.Size -lt $size) { throw "目标盘比镜像小，写不下" }
if ($DryRun) { Write-Host "DryRun：未写入。"; return }

$answer = Read-Host "确认把 $($img.Name) 整盘写入 Disk $DiskNumber？输入 YES 继续"
if ($answer -ne 'YES') { Write-Host "已取消"; return }

$handle = [System.IO.File]::Open("\\.\PhysicalDrive$DiskNumber", 'Open', 'ReadWrite', 'None')
try {
    $buf = New-Object byte[] (4 * 1024 * 1024)
    $src = [System.IO.File]::OpenRead($img.FullName)
    $written = 0
    $sw = [Diagnostics.Stopwatch]::StartNew()
    try {
        while ($true) {
            $read = $src.Read($buf, 0, $buf.Length)
            if ($read -le 0) { break }
            $handle.Write($buf, 0, $read)
            $written += $read
            if ($written % (32 * 1024 * 1024) -lt $read) {
                Write-Progress -Activity "写入 SD 卡" -Status "$([math]::Round($written/1MB)) / $([math]::Round($size/1MB)) MB" `
                    -PercentComplete ([math]::Min(100, 100 * $written / $size))
            }
        }
        $handle.Flush()
    } finally { $src.Dispose() }
}
finally { $handle.Dispose() }

Write-Host ("完成：写入 {0:N0} 字节，用时 {1:N0} 秒" -f $written, $sw.Elapsed.TotalSeconds)
Write-Host "把 SD 卡插到板子上电，U-Boot 会从 mmc 0:1 的 /boot 启动。"
