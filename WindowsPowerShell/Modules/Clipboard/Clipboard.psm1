﻿Add-Type -Namespace PowershellPlatformInterop -Name Clipboard -MemberDefinition @"
[DllImport("user32.dll", SetLastError=true)]
public static extern bool EmptyClipboard();

[DllImport("user32.dll", SetLastError=true)]
public static extern IntPtr SetClipboardData(uint uFormat, IntPtr hMem);

[DllImport("user32.dll", SetLastError=true)]
public static extern IntPtr GetClipboardData(uint uFormat);

[DllImport("user32.dll", SetLastError=true)]
public static extern bool OpenClipboard(IntPtr hWndNewOwner);

[DllImport("user32.dll", SetLastError=true)]
public static extern bool CloseClipboard();

[DllImport("user32.dll", SetLastError=true)]
public static extern uint EnumClipboardFormats(uint format);
"@

function Assert-Win32CallSuccess {
    param(
        [Switch]$PassThru,
        [Switch]$NullIsError,
        [ScriptBlock]$Action)

    $result = & $Action

    if($NullIsError -and $result -eq 0 -or -not $NullIsError -and $result -ne 0) {
        $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
        [Runtime.InteropServices.Marshal]::ThrowExceptionForHR($errorCode)
    } 
    
    if ($PassThru) {
        $result
    }
}

function Use-Clipboard {
    param([ScriptBlock]$Action)

    if($script:isClipboardOwned) { return & $Action }

    $script:isClipboardOwned = $true

    Assert-Win32CallSuccess {
        [PowershellPlatformInterop.Clipboard]::OpenClipboard([IntPtr]::Zero)
    }

    try { & $Action }
    finally {
        Assert-Win32CallSuccess {
            [PowershellPlatformInterop.Clipboard]::CloseClipboard()
        }

        $script:isClipboardOwned = $false
    }
}

function Clear-Clipboard {
    Use-Clipboard { 
        Assert-Win32CallSuccess {
            [PowershellPlatformInterop.Clipboard]::EmptyClipboard()
        }
    }
}

$ansiTextFormat = 1
$unicodeTextFormat = 13

function Set-ClipboardText {
    param([Parameter(ValueFromPipeline=$true)][string]$Value)
    Use-Clipboard {
        Clear-Clipboard

        $ptr = [Runtime.InteropServices.Marshal]::StringToHGlobalUni($Value)
        Assert-Win32CallSuccess -NullIsError {
            [PowershellPlatformInterop.Clipboard]::SetClipboardData($unicodeTextFormat, $ptr)
        }

        $ptr = [Runtime.InteropServices.Marshal]::StringToHGlobalAnsi($Value)

        Assert-Win32CallSuccess -NullIsError {
            [PowershellPlatformInterop.Clipboard]::SetClipboardData($ansiTextFormat, $ptr)
        }
    }
}

function Get-ClipboardFormats {
    Use-Clipboard {
        $prev = 0

        while($true) {
            $prev = Assert-Win32CallSuccess -NullIsError -PassThru {
              [PowershellPlatformInterop.Clipboard]::EnumClipboardFormats($prev)
            }

            if ($prev -eq 0) { break; }

            $prev
        }
    }
}

function Get-ClipboardText {
    Use-Clipboard {
        $formats = Get-ClipboardFormats

        if($formats -contains $unicodeTextFormat) {
            $ptr = Assert-Win32CallSuccess -PassThru -NullIsError {
                [PowershellPlatformInterop.Clipboard]::GetClipboardData($unicodeTextFormat)
            }

            if ($ptr -ne 0) { 
                [Runtime.InteropServices.Marshal]::PtrToStringUni($ptr) 
            }
        } elseif($formats -contains $ansiTextFormat) {
            $ptr = Assert-Win32CallSuccess -PassThru -NullIsError {
                [PowershellPlatformInterop.Clipboard]::GetClipboardData($ansiTextFormat)
            }

            if ($ptr -ne 0) {
                [Runtime.InteropServices.Marshal]::PtrToStringAnsi($ptr) 
            }
        }
    }
}

Export-ModuleMember Get-ClipboardText, Set-ClipboardText, Clear-Clipboard