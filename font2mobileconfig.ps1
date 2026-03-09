param(
    [Parameter(Mandatory = $true, Position = 0)]
    [string]$FontFile
)

if (-not (Test-Path -LiteralPath $FontFile -PathType Leaf)) {
    Write-Error "Font file not found: $FontFile"
    exit 1
}

$outerUuid = [guid]::NewGuid().ToString()
$innerUuid = [guid]::NewGuid().ToString()
$hostname = [System.Net.Dns]::GetHostName()
$outFile = "$FontFile.mobileconfig"

# Keep 72-character line wrapping to match the original shell script behavior.
$base64 = [Convert]::ToBase64String([IO.File]::ReadAllBytes($FontFile))
$wrappedBase64 = ($base64 -split "(.{1,72})" | Where-Object { $_ }) -join "`n"

$content = @"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
<key>PayloadDisplayName</key><string>$FontFile</string>
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
<string>$FontFile</string>
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
