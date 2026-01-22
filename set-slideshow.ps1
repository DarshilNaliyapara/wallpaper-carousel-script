param (
    [string]$FolderPath = "$env:USERPROFILE\Pictures\wallpapers",
    [int]$Interval = 3600  # Default value
)

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
    Write-Host "ONE-TIME SETUP REQUIRED (Due to Windows Security" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Windows Settings will open in 2 seconds..." -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Click the dropdown under 'Personalize your background'" -ForegroundColor White
    Write-Host "Select 'Slideshow' from the list" -ForegroundColor White
    Write-Host "This script will detect the change automatically!" -ForegroundColor White
    Write-Host ""
    Write-Host "(This is required only once per computer)" -ForegroundColor Gray
    
    Start-Sleep -Seconds 2
    Start-Process "ms-settings:personalization-background"
    
    # --- THE AUTO-DETECT LOOP ---
    Write-Host "`nWaiting for slideshow mode" -NoNewline -ForegroundColor Cyan
    
    do {
        Start-Sleep -Seconds 1
        $CurrentStatus = Get-ItemProperty -Path $RegPath -Name "BackgroundType" -ErrorAction SilentlyContinue
        Write-Host "." -NoNewline -ForegroundColor Cyan
    } until ($CurrentStatus.BackgroundType -eq 2)
    
    Write-Host "Slideshow mode detected!" -ForegroundColor Green

    # --- THE FOCUS STEALER ---
    Write-Host "Returning focus to this script..." -ForegroundColor Gray
    Start-Sleep -Milliseconds 500
    $hWnd = [FocusHelper]::GetConsoleWindow()
    [FocusHelper]::ShowWindow($hWnd, 9)
    [FocusHelper]::SetForegroundWindow($hWnd)

} else {
    Write-Host "`nAlready in Slideshow mode." -ForegroundColor Green
}


# --- 4. FINALIZATION: Inject the Folder & Time ---
Write-Host "`n4. Configuring slideshow settings..." -ForegroundColor Cyan

# Inject the binary link (Critical Fix)
Set-ItemProperty -Path $RegPath -Name "ImagesFolderPIDL" -Value $pidl -Type Binary
Set-ItemProperty -Path $RegPath -Name "SlideshowSourcePath" -Value $FolderPath -Type String

$SlidePath = "HKCU:\Control Panel\Personalization\Desktop Slideshow"
$IntervalMs = $Interval * 1000
Set-ItemProperty -Path $SlidePath -Name "Interval" -Value $IntervalMs -Type DWord 
Set-ItemProperty -Path $SlidePath -Name "Shuffle" -Value 1 -Type DWord

Write-Host "   Setting interval to $Interval" -ForegroundColor Gray



# --- 5. REFRESH: Restart Explorer ---
Write-Host "5. Refreshing Desktop..." -ForegroundColor Cyan
Stop-Process -Name "explorer" -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 1
Start-Process "explorer.exe"

Write-Host "SUCCESS! Slideshow is now configured" -ForegroundColor Green
Write-Host "   Folder:   $FolderPath" -ForegroundColor White
Write-Host "   Interval: $Interval seconds ($([math]::Round($Interval/60, 1)) minutes)" -ForegroundColor White
exit
