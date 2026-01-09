param (
    [string]$FolderPath = "$HOME\Pictures\wallpapers"
)

# 1. Check if folder exists
if (-not (Test-Path -Path $FolderPath)) {
    Write-Host "Creating folder: $FolderPath"
    New-Item -ItemType Directory -Path $FolderPath | Out-Null
}

# 2. Define robust C# to handle the binary conversion safely
$Definition = @'
using System;
using System.Runtime.InteropServices;

public class WallpaperHelper {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHParseDisplayName(string pszName, IntPtr pbc, out IntPtr ppidl, uint sfgaoIn, out uint psfgaoOut);

    [DllImport("shell32.dll")]
    private static extern int ILGetSize(IntPtr pidl);

    [DllImport("ole32.dll")]
    private static extern void CoTaskMemFree(IntPtr pv);

    public static byte[] GetPathPIDL(string path) {
        IntPtr pidl = IntPtr.Zero;
        uint attribs;
        
        // Convert path to PIDL
        int result = SHParseDisplayName(path, IntPtr.Zero, out pidl, 0, out attribs);

        if (result != 0 || pidl == IntPtr.Zero) {
            return null;
        }

        // Get the exact size of the binary structure
        int size = ILGetSize(pidl);
        byte[] bytes = new byte[size];

        // Copy bytes safely
        Marshal.Copy(pidl, bytes, 0, size);

        // Free memory
        CoTaskMemFree(pidl);
        return bytes;
    }
}
'@

# Only add type if not already added (prevents errors in ISE/repeated runs)
if (-not ([System.Management.Automation.PSTypeName]'WallpaperHelper').Type) {
    Add-Type -TypeDefinition $Definition
}

# 3. Generate the Binary PIDL
Write-Host "Generating IDList for: $FolderPath"
$pidlBytes = [WallpaperHelper]::GetPathPIDL($FolderPath)

if ($null -eq $pidlBytes) {
    Write-Error "Failed to parse folder path. Ensure the path is correct and accessible."
    exit 1
}

# 4. Write to Registry
$RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers"

# Ensure the registry key exists
if (-not (Test-Path $RegPath)) {
    New-Item -Path $RegPath -Force | Out-Null
}

# 0=Picture, 1=Solid Color, 2=Slideshow
Set-ItemProperty -Path $RegPath -Name "BackgroundType" -Value 2 -Type DWord

# Set the binary ID of the folder (Critical for Slideshow)
Set-ItemProperty -Path $RegPath -Name "ImagesFolderPIDL" -Value $pidlBytes -Type Binary

# Set the readable path (Legacy/fallback)
Set-ItemProperty -Path $RegPath -Name "SlideshowSourcePath" -Value $FolderPath -Type String

Write-Host "Registry settings updated."

# 5. Restart Explorer Safely
Write-Host "Restarting Explorer to apply changes..."

# Gracefully stop explorer, suppressing errors if it's already dead
Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue

# Wait a moment for the process to terminate fully
Start-Sleep -Seconds 1

# Check if it auto-restarted; if not, start it manually
if (-not (Get-Process -Name "explorer" -ErrorAction SilentlyContinue)) {
    Start-Process "explorer.exe"
}

Write-Host "Done! Your wallpaper should now be set to Slideshow."