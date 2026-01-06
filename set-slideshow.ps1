param (
    [string]$FolderPath = "$HOME\Pictures\wallpapers"
)

# 1. Check if folder exists
if (-not (Test-Path $FolderPath)) {
    Write-Host "Creating folder: $FolderPath"
    New-Item -ItemType Directory -Path $FolderPath | Out-Null
}

# 2. Define C# to convert String Path -> Windows ID List (PIDL)
$Definition = @'
using System;
using System.Runtime.InteropServices;

public class Win32 {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    public static extern int SHParseDisplayName(string pszName, IntPtr pbc, out IntPtr ppidl, uint sfgaoIn, out uint psfgaoOut);

    [DllImport("ole32.dll")]
    public static extern void CoTaskMemFree(IntPtr pv);
}
'@
Add-Type -TypeDefinition $Definition

# 3. Generate the Binary PIDL
$pidlPtr = [IntPtr]::Zero
$sfgaoOut = 0
$result = [Win32]::SHParseDisplayName($FolderPath, [IntPtr]::Zero, [ref]$pidlPtr, 0, [ref]$sfgaoOut)

if ($result -eq 0) {
    # Copy the raw bytes from memory
    $byteList = new-object System.Collections.Generic.List[byte]
    $offset = 0
    # Read memory until we hit the double-null terminator of the PIDL
    do {
        $cb = [System.Runtime.InteropServices.Marshal]::ReadByte($pidlPtr, $offset)
        $byteList.Add($cb)
        $cb2 = [System.Runtime.InteropServices.Marshal]::ReadByte($pidlPtr, $offset + 1)
        $offset++
    } while ($offset -lt 4096) # Safety limit, usually much smaller

    [Win32]::CoTaskMemFree($pidlPtr)
    $pidlBytes = $byteList.ToArray()
} else {
    Write-Error "Failed to parse folder path."
    exit 1
}

# 4. Write to Registry
$RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers"

# 0=Picture, 1=Solid Color, 2=Slideshow
Set-ItemProperty -Path $RegPath -Name "BackgroundType" -Value 2

# Set the binary ID of the folder
Set-ItemProperty -Path $RegPath -Name "ImagesFolderPIDL" -Value $pidlBytes

# Also set the timestamp to force a refresh (optional but helpful)
Set-ItemProperty -Path $RegPath -Name "SlideshowSourcePath" -Value $FolderPath

# 5. Restart Explorer to apply changes
# This is required because Explorer caches the wallpaper settings aggressively
Stop-Process -Name explorer