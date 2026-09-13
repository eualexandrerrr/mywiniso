# Roda 30 s depois do logon (tarefa agendada "Startup OnLogon", criada pelo setup.ps1).
# Maximiza o Discord, abre e fecha o Spotify, põe duas janelas do Chrome no monitor vertical
# e faz backup do histórico do terminal em D:\Utils\TerminalHistory.
try {
    Add-Type @"
    using System;
    using System.Collections.Generic;
    using System.Runtime.InteropServices;
    using System.Text;

    public class WinAPI {
        public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);

        [DllImport("user32.dll")]
        public static extern bool MoveWindow(IntPtr hWnd, int X, int Y, int nWidth, int nHeight, bool bRepaint);

        [DllImport("user32.dll")]
        public static extern bool IsWindowVisible(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

        [DllImport("user32.dll")]
        public static extern bool SetForegroundWindow(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern void keybd_event(byte bVk, byte bScan, uint dwFlags, UIntPtr dwExtraInfo);

        [DllImport("user32.dll")]
        public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

        [DllImport("user32.dll")]
        public static extern IntPtr GetForegroundWindow();

        [DllImport("user32.dll")]
        public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

        [DllImport("kernel32.dll")]
        public static extern uint GetCurrentThreadId();

        [DllImport("user32.dll", CharSet = CharSet.Auto)]
        public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);

        [DllImport("user32.dll")]
        public static extern int GetWindowTextLength(IntPtr hWnd);

        [DllImport("user32.dll")]
        public static extern bool GetWindowRect(IntPtr hWnd, out RECT lpRect);

        [DllImport("user32.dll")]
        public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);

        [DllImport("user32.dll")]
        public static extern bool PostMessage(IntPtr hWnd, uint Msg, IntPtr wParam, IntPtr lParam);

        [StructLayout(LayoutKind.Sequential)]
        public struct RECT {
            public int Left;
            public int Top;
            public int Right;
            public int Bottom;
        }

        public const uint WM_CLOSE = 0x0010;
        public const int SW_MAXIMIZE = 3;
        public const int SW_RESTORE = 9;

        public static void ForceForeground(IntPtr hWnd) {
            uint VK_MENU = 0x12;
            uint KEYEVENTF_EXTENDEDKEY = 0x0001;
            uint KEYEVENTF_KEYUP = 0x0002;

            IntPtr foreWnd = GetForegroundWindow();
            uint foreThread;
            GetWindowThreadProcessId(foreWnd, out foreThread);
            uint curThread = GetCurrentThreadId();

            if (foreThread != curThread) {
                AttachThreadInput(foreThread, curThread, true);
                keybd_event((byte)VK_MENU, 0, KEYEVENTF_EXTENDEDKEY, UIntPtr.Zero);
                keybd_event((byte)VK_MENU, 0, KEYEVENTF_EXTENDEDKEY | KEYEVENTF_KEYUP, UIntPtr.Zero);
                SetForegroundWindow(hWnd);
                AttachThreadInput(foreThread, curThread, false);
            } else {
                SetForegroundWindow(hWnd);
            }
        }

        public static List<IntPtr> GetChromeWindows() {
            List<IntPtr> result = new List<IntPtr>();
            HashSet<uint> chromePids = new HashSet<uint>();

            foreach (var p in System.Diagnostics.Process.GetProcessesByName("chrome")) {
                chromePids.Add((uint)p.Id);
            }

            EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) {
                if (!IsWindowVisible(hWnd)) return true;

                uint pid;
                GetWindowThreadProcessId(hWnd, out pid);
                if (!chromePids.Contains(pid)) return true;

                StringBuilder className = new StringBuilder(256);
                GetClassName(hWnd, className, 256);
                if (className.ToString() != "Chrome_WidgetWin_1") return true;

                int len = GetWindowTextLength(hWnd);
                if (len == 0) return true;

                StringBuilder title = new StringBuilder(len + 1);
                GetWindowText(hWnd, title, len + 1);
                string t = title.ToString();
                if (string.IsNullOrEmpty(t)) return true;

                result.Add(hWnd);
                return true;
            }, IntPtr.Zero);

            return result;
        }

        public static IntPtr FindWindowByProcess(string processName) {
            IntPtr found = IntPtr.Zero;

            HashSet<uint> pids = new HashSet<uint>();
            foreach (var p in System.Diagnostics.Process.GetProcessesByName(processName)) {
                pids.Add((uint)p.Id);
            }

            EnumWindows(delegate(IntPtr hWnd, IntPtr lParam) {
                if (!IsWindowVisible(hWnd)) return true;

                uint pid;
                GetWindowThreadProcessId(hWnd, out pid);
                if (!pids.Contains(pid)) return true;

                int len = GetWindowTextLength(hWnd);
                if (len == 0) return true;

                StringBuilder title = new StringBuilder(len + 1);
                GetWindowText(hWnd, title, len + 1);
                if (string.IsNullOrEmpty(title.ToString())) return true;

                found = hWnd;
                return false;
            }, IntPtr.Zero);

            return found;
        }
    }
"@
} catch {}

Start-Sleep -Seconds 3

Write-Host "=== Maximizando Discord ==="
$discordHwnd = [WinAPI]::FindWindowByProcess("Discord")
if ($discordHwnd -ne [IntPtr]::Zero) {
    $sb = New-Object System.Text.StringBuilder 256
    [WinAPI]::GetWindowText($discordHwnd, $sb, 256) | Out-Null
    Write-Host "Discord encontrado: $($sb.ToString())"
    [WinAPI]::ShowWindow($discordHwnd, [WinAPI]::SW_RESTORE) | Out-Null
    Start-Sleep -Milliseconds 200
    [WinAPI]::ShowWindow($discordHwnd, [WinAPI]::SW_MAXIMIZE) | Out-Null
    [WinAPI]::ForceForeground($discordHwnd)
    Write-Host "Discord maximizado"
} else {
    Write-Host "Discord nao encontrado"
}

Write-Host "=== Maximizando Spotify ==="
$spotifyHwnd = [WinAPI]::FindWindowByProcess("Spotify")
if ($spotifyHwnd -ne [IntPtr]::Zero) {
    $sb = New-Object System.Text.StringBuilder 256
    [WinAPI]::GetWindowText($spotifyHwnd, $sb, 256) | Out-Null
    Write-Host "Spotify encontrado: $($sb.ToString())"
    [WinAPI]::ShowWindow($spotifyHwnd, [WinAPI]::SW_RESTORE) | Out-Null
    Start-Sleep -Milliseconds 200
    [WinAPI]::ShowWindow($spotifyHwnd, [WinAPI]::SW_MAXIMIZE) | Out-Null
    [WinAPI]::ForceForeground($spotifyHwnd)
    Write-Host "Spotify maximizado"

    Start-Sleep -Seconds 2

    Write-Host "=== Fechando Spotify ==="
    [WinAPI]::PostMessage($spotifyHwnd, [WinAPI]::WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    Write-Host "Spotify fechado"
} else {
    Write-Host "Spotify nao encontrado"
}

Write-Host "=== Buscando janelas do Chrome ==="

$chromeWindows = [WinAPI]::GetChromeWindows()

Write-Host "Janelas encontradas: $($chromeWindows.Count)"

foreach ($h in $chromeWindows) {
    $sb = New-Object System.Text.StringBuilder 256
    [WinAPI]::GetWindowText($h, $sb, 256) | Out-Null
    $rect = New-Object WinAPI+RECT
    [WinAPI]::GetWindowRect($h, [ref]$rect) | Out-Null
    Write-Host "Handle: $h | Titulo: $($sb.ToString()) | Pos: L=$($rect.Left) T=$($rect.Top) R=$($rect.Right) B=$($rect.Bottom)"
}

if ($chromeWindows.Count -lt 2) {
    Write-Host "Precisa de pelo menos 2 janelas do Chrome abertas."
    exit
}

$xPos = -1080
$width = 1080
$halfHeight = 960

$sb0 = New-Object System.Text.StringBuilder 256
[WinAPI]::GetWindowText($chromeWindows[0], $sb0, 256) | Out-Null
if ($sb0.ToString() -match "Michigan|txAdmin") {
    Write-Host "Swap: janela Michigan/txAdmin encontrada no indice 0, movendo para topo"
    $temp = $chromeWindows[0]
    $chromeWindows[0] = $chromeWindows[1]
    $chromeWindows[1] = $temp
}

for ($i = 0; $i -lt 2; $i++) {
    $h = $chromeWindows[$i]
    $sb = New-Object System.Text.StringBuilder 256
    [WinAPI]::GetWindowText($h, $sb, 256) | Out-Null

    if ($i -eq 0) {
        $yPos = 482
        Write-Host "Movendo para BAIXO: $($sb.ToString()) -> X=$xPos Y=$yPos W=$width H=$halfHeight"
    } else {
        $yPos = -478
        Write-Host "Movendo para TOPO: $($sb.ToString()) -> X=$xPos Y=$yPos W=$width H=$halfHeight"
    }

    [WinAPI]::ShowWindow($h, 1) | Out-Null
    [WinAPI]::ForceForeground($h)
    $result = [WinAPI]::MoveWindow($h, $xPos, $yPos, $width, $halfHeight, $true)
    Write-Host "MoveWindow resultado: $result"

    $rect = New-Object WinAPI+RECT
    [WinAPI]::GetWindowRect($h, [ref]$rect) | Out-Null
    Write-Host "Nova pos: L=$($rect.Left) T=$($rect.Top) R=$($rect.Right) B=$($rect.Bottom)"
    Write-Host "---"
}

Start-Sleep -Milliseconds 500
[WinAPI]::ForceForeground($chromeWindows[0])
[WinAPI]::ForceForeground($chromeWindows[1])

Write-Host "=== Backup do historico do terminal ==="
$historySource = "$env:APPDATA\Microsoft\Windows\PowerShell\PSReadLine\ConsoleHost_history.txt"
$historyBackup = "D:\Utils\TerminalHistory\history.txt"
if (Test-Path $historySource) {
    if (Test-Path $historyBackup) {
        $backupLines = @(Get-Content $historyBackup)
        $localLines = @(Get-Content $historySource)
        $merged = ($backupLines + $localLines) | Select-Object -Unique
        $merged | Set-Content $historyBackup -Encoding UTF8
    } else {
        Copy-Item $historySource $historyBackup -Force
    }
    Write-Host "Backup salvo em TerminalHistory"
}

Write-Host "=== Concluido ==="
