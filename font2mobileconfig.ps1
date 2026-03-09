param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$FontFile
)

if (-not (Test-Path -LiteralPath $FontFile -PathType Leaf)) {
    Write-Error "Font file not found: $FontFile"
    exit 1
}

function Test-TtfBytes {
    param([byte[]]$Bytes)
    return (
        $Bytes.Length -ge 4 -and
        $Bytes[0] -eq 0x00 -and
        $Bytes[1] -eq 0x01 -and
        $Bytes[2] -eq 0x00 -and
        $Bytes[3] -eq 0x00
    )
}

$fontPath = (Resolve-Path -LiteralPath $FontFile).Path
$fontDir = Split-Path -Parent $fontPath
$fontBaseName = [IO.Path]::GetFileNameWithoutExtension($fontPath)
$fontExt = [IO.Path]::GetExtension($fontPath).ToLowerInvariant()

$ttfOutFile = Join-Path $fontDir "$fontBaseName.ttf"
$woff2OutFile = Join-Path $fontDir "$fontBaseName.woff2"
$outFile = "$fontPath.mobileconfig"

$sourceBytes = [IO.File]::ReadAllBytes($fontPath)
$hasTtfInput = Test-TtfBytes -Bytes $sourceBytes

if ($hasTtfInput) {
    if ($fontPath -ieq $ttfOutFile) {
        Write-Output "TTF already present: $ttfOutFile"
    } else {
        [IO.File]::WriteAllBytes($ttfOutFile, $sourceBytes)
        Write-Output "Wrote $ttfOutFile"
    }
} elseif ($fontExt -eq ".ttx") {
    $ttxTool = Get-Command ttx -ErrorAction SilentlyContinue
    if (-not $ttxTool) {
        Write-Warning "ttx tool not found; cannot export TTF from TTX input."
    } else {
        & ttx -o "$ttfOutFile" "$fontPath" | Out-Null
        if (Test-Path -LiteralPath $ttfOutFile -PathType Leaf) {
            Write-Output "Wrote $ttfOutFile"
        } else {
            Write-Warning "ttx ran but did not produce $ttfOutFile."
        }
    }
} elseif ($fontExt -eq ".woff2") {
    $woff2DecompressTool = Get-Command woff2_decompress -ErrorAction SilentlyContinue
    if (-not $woff2DecompressTool) {
        Write-Warning "woff2_decompress not found; cannot export TTF from WOFF2 input."
    } else {
        & woff2_decompress "$fontPath" | Out-Null
        if (Test-Path -LiteralPath $ttfOutFile -PathType Leaf) {
            Write-Output "Wrote $ttfOutFile"
        } else {
            Write-Warning "woff2_decompress ran but did not produce $ttfOutFile."
        }
    }
} else {
    Write-Warning "Input is not TTF/WOFF2. Skipping TTF export."
}

if (Test-Path -LiteralPath $ttfOutFile -PathType Leaf) {
    $woff2CompressTool = Get-Command woff2_compress -ErrorAction SilentlyContinue
    if (-not $woff2CompressTool) {
        Write-Warning "woff2_compress not found; cannot export WOFF2."
    } else {
        & woff2_compress "$ttfOutFile" | Out-Null
        $candidateA = "$ttfOutFile.woff2"
        $candidateB = [IO.Path]::ChangeExtension($ttfOutFile, ".woff2")
        if (Test-Path -LiteralPath $candidateA -PathType Leaf -and -not ($candidateA -ieq $woff2OutFile)) {
            Move-Item -LiteralPath $candidateA -Destination $woff2OutFile -Force
        }
        if (Test-Path -LiteralPath $candidateB -PathType Leaf -and -not ($candidateB -ieq $woff2OutFile)) {
            Move-Item -LiteralPath $candidateB -Destination $woff2OutFile -Force
        }
        if (Test-Path -LiteralPath $woff2OutFile -PathType Leaf) {
            Write-Output "Wrote $woff2OutFile"
        } elseif ($fontExt -eq ".woff2" -and (Test-Path -LiteralPath $fontPath -PathType Leaf)) {
            Copy-Item -LiteralPath $fontPath -Destination $woff2OutFile -Force
            Write-Output "Wrote $woff2OutFile"
        } else {
            Write-Warning "woff2_compress ran but no WOFF2 output was found."
        }
    }
}

$payloadFontPath = $fontPath
if (Test-Path -LiteralPath $ttfOutFile -PathType Leaf) {
    $payloadFontPath = $ttfOutFile
}

$outerUuid = [guid]::NewGuid().ToString()
$innerUuid = [guid]::NewGuid().ToString()
$hostname = [System.Net.Dns]::GetHostName()

# Keep 72-character line wrapping to match the original shell script behavior.
$base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($payloadFontPath))
$wrappedBase64 = ($base64 -split "(.{1,72})" | Where-Object { $_ }) -join "`n"

$content = @"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>PayloadDisplayName</key><string>$([IO.Path]::GetFileName($payloadFontPath))</string>
<key>PayloadIdentifier</key>
<string>$hostname.$outerUuid</string>
<key>PayloadType</key><string>Configuration</string>
<key>PayloadUUID</key><string>$outerUuid</string><key>PayloadVersion</key><integer>1</integer>
<key>PayloadContent</key>
<array>
<dict>
<key>PayloadType</key><string>com.apple.font</string>
<key>Font</key>
<data>
$wrappedBase64
</data>
<key>Name</key>
<string>$([IO.Path]::GetFileName($payloadFontPath))</string>
<key>PayloadIdentifier</key>
<string>$hostname.$outerUuid.com.apple.font.$innerUuid</string>
<key>PayloadVersion</key><integer>1</integer>
<key>PayloadUUID</key><string>$innerUuid</string>
</dict>
</array>
</dict>
</plist>
"@

[IO.File]::WriteAllText($outFile, $content, [Text.UTF8Encoding]::new($false))
Write-Output "Wrote $outFile"
