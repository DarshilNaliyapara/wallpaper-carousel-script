param (
    [string]$FolderPath = "$env:USERPROFILE\Pictures\wallpapers"
)

# --- 0. DEFINE TOOLS (C#) ---
$INTERVAL=3600
# Tool 1: PIDL Generator (For folder linking)
$pidlCode = @'
using System;
using System.Runtime.InteropServices;
public class PidlGenerator {
    [DllImport("shell32.dll", CharSet = CharSet.Unicode)]
    private static extern int SHParseDisplayName(string pszName, IntPtr pbc, out IntPtr ppidl, uint sfgaoIn, out uint psfgaoOut);
    [DllImport("shell32.dll")]
    private static extern int ILGetSize(IntPtr pidl);
    [DllImport("ole32.dll")]
    private static extern void CoTaskMemFree(IntPtr pv);
    public static byte[] GetID(string path) {
        IntPtr pidl = IntPtr.Zero;
        uint attribs;
        if (SHParseDisplayName(path, IntPtr.Zero, out pidl, 0, out attribs) != 0) return null;
        int size = ILGetSize(pidl);
        byte[] bytes = new byte[size];
        Marshal.Copy(pidl, bytes, 0, size);
        CoTaskMemFree(pidl);
        return bytes;
    }
}
'@
if (-not ([System.Management.Automation.PSTypeName]'PidlGenerator').Type) { Add-Type -TypeDefinition $pidlCode }

# Tool 2: Focus Helper (To bring this window back)
$focusCode = @'
using System;
using System.Runtime.InteropServices;
public class FocusHelper {
    [DllImport("kernel32.dll")]
    public static extern IntPtr GetConsoleWindow();

    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
'@
if (-not ([System.Management.Automation.PSTypeName]'FocusHelper').Type) { Add-Type -TypeDefinition $focusCode }


# --- 1. SETUP: Check Folder & Images ---
Write-Host "1. Checking Source Folder..." -ForegroundColor Cyan
if (-not (Test-Path -Path $FolderPath)) {
    Write-Error "Folder not found: $FolderPath"
    exit
}
$count = (Get-ChildItem $FolderPath -Include *.jpg, *.png, *.jpeg -Recurse).Count
if ($count -eq 0) {
    Write-Error "Folder is empty! Please add images."
    exit
}
Write-Host "   Found $count images. Good." -ForegroundColor Green


# --- 2. SETUP: Prepare the Registry Data ---
$pidl = [PidlGenerator]::GetID($FolderPath)


# --- 3. INTERACTION: The "Human" Step ---
$RegPath = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers"
$Status = Get-ItemProperty -Path $RegPath -Name "BackgroundType" -ErrorAction SilentlyContinue

if ($Status.BackgroundType -ne 2) {
    Write-Host "`nACTION REQUIRED" -ForegroundColor Yellow
    Write-Host "I am opening Settings. Please switch 'Personalize your background' to [Slideshow]."
    
    Start-Sleep -Seconds 2
    Start-Process "ms-settings:personalization-background"
    
    # --- THE AUTO-DETECT LOOP ---
    Write-Host "Waiting for you to change the setting..." -NoNewline
    
    do {
        # Wait 1 second before checking again to save CPU
        Start-Sleep -Seconds 1
        
        # Re-read the registry value
        $CurrentStatus = Get-ItemProperty -Path $RegPath -Name "BackgroundType" -ErrorAction SilentlyContinue
        
        # Visual feedback (a dot every second)
        Write-Host "." -NoNewline
        
    } until ($CurrentStatus.BackgroundType -eq 2)
    
    Write-Host "`nDetected! You switched to Slideshow." -ForegroundColor Green

    # --- THE FOCUS STEALER ---
    Write-Host "Returning focus to this script..."
    Start-Sleep -Milliseconds 500 # Brief pause to let Windows settle
    $hWnd = [FocusHelper]::GetConsoleWindow()
    [FocusHelper]::ShowWindow($hWnd, 9) # 9 = Restore (if minimized)
    [FocusHelper]::SetForegroundWindow($hWnd) # Force to front

} else {
    Write-Host "Already in Slideshow mode." -ForegroundColor Green
}


# --- 4. FINALIZATION: Inject the Folder & Time ---
Write-Host "`n4. Locking in Folder and 30-Minute Interval..." -ForegroundColor Cyan

# Inject the binary link (Critical Fix)
Set-ItemProperty -Path $RegPath -Name "ImagesFolderPIDL" -Value $pidl -Type Binary
Set-ItemProperty -Path $RegPath -Name "SlideshowSourcePath" -Value $FolderPath -Type String

$SlidePath = "HKCU:\Control Panel\Personalization\Desktop Slideshow"
Set-ItemProperty -Path $SlidePath -Name "Interval" -Value $INTERVAL -Type DWord 
Set-ItemProperty -Path $SlidePath -Name "Shuffle" -Value 1 -Type DWord


# --- 5. REFRESH: Restart Explorer ---
Write-Host "5. Refreshing Desktop..." -ForegroundColor Cyan
Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Start-Process "explorer.exe"

Write-Host " SUCCESS! Your slideshow is now configured." -ForegroundColor Green
Write-Host "   - Folder: $FolderPath"
Write-Host "   - Interval: $INTERVAL"