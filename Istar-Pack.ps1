#Requires -Version 5.1
<#
.SYNOPSIS
    Istar Pack - One-shot PowerShell terminal setup with multi-theme support.

.DESCRIPTION
    Installs Scoop, Oh My Posh, Zoxide, FZF, 7-Zip, Nerd Fonts and the
    recommended PowerShell modules (Terminal-Icons, PSReadLine, CompletionPredictor,
    PSFzf). Writes a hardened profile tuned for both PowerShell 7 and
    Windows PowerShell 5.1, with autodetection. Ships a curated catalog of
    Oh My Posh themes - the signature one being "Garden's Dream" (minimalist
    green).

    Designed as a single-file deliverable: download the .ps1, run it,
    pick a theme, done. No manual steps, no editing JSON by hand.

.NOTES
    File Name      : Istar-Pack.ps1
    Project        : Istar Pack
    Author         : Istar Pack contributors
    Prerequisite   : PowerShell 5.1+ (PS 7+ features used when available)
    Encoding       : UTF-8 with BOM (required for box-drawing chars on PS 5.1)

.EXAMPLE
    .\Istar-Pack.ps1
    Launches the interactive main menu.

.EXAMPLE
    .\Istar-Pack.ps1 -Silent
    Runs the full installation non-interactively with default theme (Garden's Dream).

.EXAMPLE
    .\Istar-Pack.ps1 -NoPersist
    Runs without loading or saving the settings JSON file.
#>

[CmdletBinding()]
param(
    [switch]$Silent,
    [int]$ShowProgress = -1,
    [int]$EnableDebug  = -1,
    [switch]$NoPersist
)

# ============================================================================
# 1. BOOTSTRAP: Encoding, error preferences, version detection
# ============================================================================
$ErrorActionPreference = 'Stop'
$ProgressPreference    = 'SilentlyContinue'

# Force UTF-8 on the console layer. The .ps1 file itself is saved as
# UTF-8 with BOM so that Windows PowerShell 5.1 parses box-drawing chars
# correctly (without BOM, PS 5.1 falls back to ANSI and corrupts them).
try {
    $utf8 = New-Object System.Text.UTF8Encoding $false
    [Console]::OutputEncoding = $utf8
    [Console]::InputEncoding  = $utf8
    $OutputEncoding = $utf8
    $null = & chcp.com 65001 2>$null
} catch {}
$PSDefaultParameterValues['Out-File:Encoding'] = 'utf8'
try { $Host.UI.RawUI.WindowTitle = 'Istar Pack - Terminal Setup' } catch {}

# Detect PowerShell version (used for graceful feature toggling later)
$Script:PSVersion = $PSVersionTable.PSVersion
$Script:IsPS7     = $Script:PSVersion.Major -ge 7
$Script:IsCore    = $Script:PSVersion.PSEdition -eq 'Core'

# ----------------------------------------------------------------------------
# Console resize: try to give the script enough vertical room so the tall
# screens (Verification, Theme Catalog, About) fit without being cut off.
# Falls back gracefully on terminals that refuse to grow (Windows Terminal
# user-locked, ISE, piped output) by leaving a tall scrollback buffer so
# the user can still scroll to see everything.
# ----------------------------------------------------------------------------
function Initialize-ConsoleSize {
    [CmdletBinding()] param()
    try {
        $raw = $Host.UI.RawUI
        if (-not $raw) { return }

        # 50 rows comfortably fits every screen in Istar Pack
        # (banner ~14 + tallest box ~32 + prompt ~2 = ~48 rows).
        $desiredHeight = 50
        $bufferHeight  = 9999   # generous scrollback either way

        # Cap to what the physical screen can actually display.
        $maxH = $desiredHeight
        try {
            $phys = $raw.MaxPhysicalWindowSize
            if ($phys.Height -gt 0 -and $phys.Height -lt $maxH) {
                $maxH = $phys.Height
            }
        } catch {}

        # Never shrink below what the user already has.
        $curWin = $raw.WindowSize
        $curBuf = $raw.BufferSize
        $targetH = [Math]::Max($curWin.Height, $maxH)
        if ($targetH -lt 24) { $targetH = 24 }

        # Step 1: grow the buffer FIRST. The buffer must be >= window or
        # the WindowSize setter throws. Keep current width.
        $newBufH = [Math]::Max($curBuf.Height, $bufferHeight)
        if ($newBufH -ge $targetH) {
            try {
                $raw.BufferSize = (New-Object System.Management.Automation.Host.Size `
                    $curBuf.Width, $newBufH)
            } catch {}
        }

        # Step 2: grow the window itself. This is what actually makes the
        # viewport taller in conhost and most Windows Terminal setups.
        if ($curWin.Height -lt $targetH) {
            try {
                $raw.WindowSize = (New-Object System.Management.Automation.Host.Size `
                    $curWin.Width, $targetH)
            } catch {
                # Window cannot grow (WT user-locked, headless, etc.).
                # The tall buffer from step 1 still lets the user scroll.
            }
        }
    } catch {
        # Silent: non-interactive hosts (piped output, CI runners) may
        # not implement any of these operations.
    }
}

# ============================================================================
# 2. METADATA & PATHS
# ============================================================================
$Script:AppName      = 'Istar Pack'
$Script:AppVersion   = '1.0.0'
$Script:AppAuthor    = 'Istar Pack contributors'
$Script:ScriptDir    = Split-Path -Parent $MyInvocation.MyCommand.Path
if (-not $Script:ScriptDir) { $Script:ScriptDir = $PWD.Path }

# Config lives at the USER'S ROOT ($HOME), not next to the script. This way
# settings/backups survive even if the .ps1 is moved or re-downloaded, and
# the script never writes inside its own folder (which may be read-only or
# shadowed by a future re-download). A hidden .istar-pack folder keeps the
# home directory tidy.
$Script:AppDir       = Join-Path $HOME '.istar-pack'
$Script:SettingsFile = Join-Path $Script:AppDir 'settings.json'
$Script:BackupDir    = Join-Path $Script:AppDir 'backups'

# ============================================================================
# 3. SETTINGS MANAGEMENT (JSON persistence)
# ============================================================================
$Script:Settings = [ordered]@{
    ShowProgress      = $true
    DebugMode         = $false
    SelectedTheme     = 'GardensDream'
    InstallModules    = $true
    InstallScoop      = $true
    InstallFont       = $true
    LastFullInstall   = $null
}

function Import-Settings {
    [CmdletBinding()] param()
    if ($NoPersist) { return }
    if (-not (Test-Path -LiteralPath $Script:SettingsFile)) { return }
    try {
        $json = Get-Content -LiteralPath $Script:SettingsFile -Raw -Encoding UTF8 |
            ConvertFrom-Json
        if ($null -ne $json.ShowProgress)    { $Script:Settings.ShowProgress    = [bool]$json.ShowProgress }
        if ($null -ne $json.DebugMode)       { $Script:Settings.DebugMode       = [bool]$json.DebugMode }
        if ($null -ne $json.SelectedTheme)   { $Script:Settings.SelectedTheme   = [string]$json.SelectedTheme }
        if ($null -ne $json.InstallModules)  { $Script:Settings.InstallModules  = [bool]$json.InstallModules }
        if ($null -ne $json.InstallScoop)    { $Script:Settings.InstallScoop    = [bool]$json.InstallScoop }
        if ($null -ne $json.InstallFont)     { $Script:Settings.InstallFont     = [bool]$json.InstallFont }
        if ($null -ne $json.LastFullInstall) { $Script:Settings.LastFullInstall = [string]$json.LastFullInstall }
    } catch {
        Write-Debug "Settings load failed: $($_.Exception.Message)"
    }
}

function Export-Settings {
    [CmdletBinding()] param()
    if ($NoPersist) { return }
    try {
        # Make sure $HOME/.istar-pack exists before we try to write into it.
        $parent = Split-Path -Parent $Script:SettingsFile
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        $obj = [PSCustomObject]@{
            ShowProgress    = $Script:Settings.ShowProgress
            DebugMode       = $Script:Settings.DebugMode
            SelectedTheme   = $Script:Settings.SelectedTheme
            InstallModules  = $Script:Settings.InstallModules
            InstallScoop    = $Script:Settings.InstallScoop
            InstallFont     = $Script:Settings.InstallFont
            LastFullInstall = $Script:Settings.LastFullInstall
        }
        $obj | ConvertTo-Json -Depth 5 |
            Set-Content -LiteralPath $Script:SettingsFile -Encoding UTF8
    } catch {
        Write-Debug "Settings save failed: $($_.Exception.Message)"
    }
}

# ============================================================================
# 4. COLOR PALETTE & BOX-DRAWING GLYPHS
# ============================================================================
$Script:Palette = @{
    Logo    = 'Magenta'
    Primary = 'White'
    Muted   = 'DarkGray'
    Accent  = 'Cyan'
    On      = 'Green'
    Off     = 'DarkGray'
    Success = 'Green'
    Warning = 'Yellow'
    Danger  = 'Red'
    Info    = 'Cyan'
    Prompt  = 'White'
}

$Script:Box = @{
    TopLeft  = [string][char]0x256D   # ╭
    TopRight = [string][char]0x256E   # ╮
    BotLeft  = [string][char]0x2570   # ╰
    BotRight = [string][char]0x256F   # ╯
    H        = [string][char]0x2500   # ─
    V        = [string][char]0x2502   # │
    CrossL   = [string][char]0x251C   # ├
    CrossR   = [string][char]0x2524   # ┤
    Bullet   = [string][char]0x25BA   # ►
}

# ============================================================================
# 5. UI HELPERS: Inline status markers
# ============================================================================
function Write-Step {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Text)
    Write-Host ("  > $Text") -ForegroundColor $Script:Palette.Muted
}

function Write-Ok {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Text)
    Write-Host ("  [+] $Text") -ForegroundColor $Script:Palette.Success
}

function Write-Warn {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Text)
    Write-Host ("  [!] $Text") -ForegroundColor $Script:Palette.Warning
}

function Write-Err {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Text)
    Write-Host ("  [x] $Text") -ForegroundColor $Script:Palette.Danger
}

function Write-Info {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Text)
    Write-Host ("  [i] $Text") -ForegroundColor $Script:Palette.Info
}

function Write-Log {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Text)
    if ($Script:Settings.DebugMode) {
        $ts = (Get-Date).ToString('HH:mm:ss')
        Write-Host ("  [LOG $ts] $Text") -ForegroundColor DarkGray
    }
}

# ============================================================================
# 6. BOX RENDERING: Modern curved borders with adaptive width
# ============================================================================
$Script:BoxWidth = 62

function Update-BoxWidth {
    $width = 62
    try {
        $cw = $Host.UI.RawUI.WindowSize.Width
        if ($cw -gt 40 -and $cw -lt 200) { $width = [Math]::Min(80, $cw - 4) }
    } catch {}
    if ($width -lt 50) { $width = 50 }
    $Script:BoxWidth = $width
}

function Write-BoxTop {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Title)
    Update-BoxWidth
    $width     = $Script:BoxWidth
    $title     = [string]$Title
    $innerSpan = $width - 2
    if ($title.Length -gt ($innerSpan - 4)) {
        $title = $title.Substring(0, $innerSpan - 4)
    }
    $decoLen   = $innerSpan - $title.Length - 2
    $sideLen   = [int][Math]::Floor($decoLen / 2)
    $rightLen  = $decoLen - $sideLen
    $line = $Script:Box.TopLeft +
            ($Script:Box.H * $sideLen) +
            ' ' + $title + ' ' +
            ($Script:Box.H * $rightLen) +
            $Script:Box.TopRight
    Write-Host ('  ' + $line) -ForegroundColor $Script:Palette.Muted
}

function Write-BoxLine {
    [CmdletBinding()] param([string]$Text = '')
    $width = $Script:BoxWidth
    $inner = $width - 4
    $t = if ($null -eq $Text) { '' } else { [string]$Text }
    while ($t.Length -gt $inner) {
        $chunk = $t.Substring(0, $inner)
        $lastSpace = $chunk.LastIndexOf(' ')
        if ($lastSpace -gt 20) {
            $chunk = $t.Substring(0, $lastSpace)
            $t = $t.Substring($lastSpace + 1)
        } else {
            $t = $t.Substring($inner)
        }
        $pad = $inner - $chunk.Length
        Write-Host ("  " + $Script:Box.V + " " + $chunk + (' ' * $pad) + " " + $Script:Box.V) -ForegroundColor $Script:Palette.Primary
    }
    $pad = $inner - $t.Length
    Write-Host ("  " + $Script:Box.V + " " + $t + (' ' * $pad) + " " + $Script:Box.V) -ForegroundColor $Script:Palette.Primary
}

function Write-BoxSeparator {
    [CmdletBinding()] param()
    $width     = $Script:BoxWidth
    $innerSpan = $width - 2
    $line = $Script:Box.CrossL + ($Script:Box.H * $innerSpan) + $Script:Box.CrossR
    Write-Host ('  ' + $line) -ForegroundColor $Script:Palette.Muted
}

function Write-BoxSubtitle {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Title)
    $width = $Script:BoxWidth
    $inner = $width - 4
    $t = [string]$Title
    if ($t.Length -gt ($inner - 6)) { $t = $t.Substring(0, $inner - 6) }
    $decoLen  = $inner - $t.Length - 2
    $sideLen  = [int][Math]::Floor($decoLen / 2)
    $rightLen = $decoLen - $sideLen
    $content = ($Script:Box.H * $sideLen) + ' ' + $t + ' ' + ($Script:Box.H * $rightLen)
    $pad = $inner - $content.Length
    if ($pad -lt 0) { $content = $content.Substring(0, $inner); $pad = 0 }
    Write-Host ("  " + $Script:Box.V + " " + $content + (' ' * $pad) + " " + $Script:Box.V) -ForegroundColor $Script:Palette.Accent
}

function Write-BoxKeyValue {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][string]$Key,
        [Parameter(Mandatory)][string]$Value,
        [string]$KeyColor,
        [string]$ValueColor
    )
    $width = $Script:BoxWidth
    $inner = $width - 4
    $k = [string]$Key
    $v = [string]$Value
    $keyPart = "  " + $k
    $minDots = 3
    $maxKeyLen = $inner - $minDots - 1
    if ($keyPart.Length -gt $maxKeyLen) {
        $keyPart = $keyPart.Substring(0, $maxKeyLen)
    }
    $availForValue = $inner - $keyPart.Length - $minDots
    if ($availForValue -lt 1) { $availForValue = 1 }
    if ($v.Length -gt $availForValue) { $v = $v.Substring(0, $availForValue) }
    $dotsCount = $inner - $keyPart.Length - $v.Length
    if ($dotsCount -lt 1) { $dotsCount = 1 }

    $kColor = if ($KeyColor)   { $KeyColor }   else { $Script:Palette.Accent  }
    $vColor = if ($ValueColor) { $ValueColor } else { $Script:Palette.Primary }

    Write-Host -NoNewline ("  " + $Script:Box.V + " ") -ForegroundColor $Script:Palette.Muted
    Write-Host -NoNewline $keyPart -ForegroundColor $kColor
    Write-Host -NoNewline ('.' * $dotsCount) -ForegroundColor $Script:Palette.Muted
    Write-Host -NoNewline $v -ForegroundColor $vColor
    Write-Host -NoNewline (" " + $Script:Box.V) -ForegroundColor $Script:Palette.Muted
    Write-Host ''
}

function Write-BoxBottom {
    [CmdletBinding()] param()
    $width     = $Script:BoxWidth
    $innerSpan = $width - 2
    $line = $Script:Box.BotLeft + ($Script:Box.H * $innerSpan) + $Script:Box.BotRight
    Write-Host ('  ' + $line) -ForegroundColor $Script:Palette.Muted
}

function Write-Box {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter()][string[]]$Lines = @()
    )
    Write-BoxTop -Title $Title
    foreach ($l in $Lines) { Write-BoxLine -Text $l }
    Write-BoxBottom
}

# ============================================================================
# 7. PROGRESS BAR
# ============================================================================
function Write-ProgressBar {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][int]$Percent,
        [ValidateSet('Blocks','Dots','Arrow','Solid')][string]$Style = 'Blocks',
        [int]$Width = 30,
        [string]$Label
    )
    if ($Percent -lt 0)   { $Percent = 0 }
    if ($Percent -gt 100) { $Percent = 100 }
    $filled = [int][Math]::Floor(($Percent / 100) * $Width)
    $empty  = $Width - $filled

    $fillChar  = '='
    $emptyChar = ' '
    switch ($Style) {
        'Blocks' { $fillChar = [char]0x2588; $emptyChar = [char]0x2591 }
        'Dots'   { $fillChar = [char]0x25CF; $emptyChar = [char]0x25CB }
        'Arrow'  { $fillChar = '=';          $emptyChar = '.' }
        'Solid'  { $fillChar = [char]0x2593; $emptyChar = ' ' }
    }

    if ($Style -eq 'Arrow') {
        if ($filled -gt 0) {
            $bar = ('=' * ($filled - 1)) + '>' + ('.' * $empty)
        } else {
            $bar = '.' * $Width
        }
    } else {
        $bar = ([string]$fillChar * $filled) + ([string]$emptyChar * $empty)
    }
    $pctStr   = ('{0,3}%' -f $Percent)
    $labelStr = if ($Label) { "  $Label" } else { '' }
    Write-Host ("  [$bar] $pctStr$labelStr") -ForegroundColor $Script:Palette.Accent
}

# ============================================================================
# 8. SPINNER (synchronous, repaint-in-place)
# ============================================================================
function New-Spinner {
    [CmdletBinding()] param(
        [string]$Label = 'Working',
        [ValidateSet('Braille','Block','Classic','Geometric')][string]$Style = 'Braille'
    )
    $frames = switch ($Style) {
        'Braille'   { @(([char]0x280B),([char]0x2819),([char]0x2839),([char]0x2838),([char]0x283C),([char]0x2834)) }
        'Block'     { @(([char]0x2596),([char]0x2598),([char]0x259D),([char]0x2592)) }
        'Classic'   { @('|','/','-','\') }
        'Geometric' { @(([char]0x25E4),([char]0x25E5),([char]0x25E2),([char]0x25E3)) }
    }
    return [PSCustomObject]@{
        Frames = $frames
        Index  = 0
        Label  = $Label
        Top    = [Console]::CursorTop
    }
}

function Update-Spinner {
    [CmdletBinding()] param([Parameter(Mandatory)]$Spinner)
    $frame = $Spinner.Frames[$Spinner.Index]
    $Spinner.Index = ($Spinner.Index + 1) % $Spinner.Frames.Count
    try { [Console]::SetCursorPosition(0, $Spinner.Top) } catch {}
    $line = "  $frame $($Spinner.Label)...   "
    Write-Host -NoNewline $line -ForegroundColor $Script:Palette.Accent
}

function Complete-Spinner {
    [CmdletBinding()] param(
        [Parameter(Mandatory)]$Spinner,
        [string]$FinalMessage,
        [switch]$Success
    )
    try { [Console]::SetCursorPosition(0, $Spinner.Top) } catch {}
    Write-Host -NoNewline (' ' * 80)
    try { [Console]::SetCursorPosition(0, $Spinner.Top) } catch {}
    if ($FinalMessage) {
        if ($Success) {
            Write-Host ("  [+] $FinalMessage") -ForegroundColor $Script:Palette.Success
        } else {
            Write-Host ("  [-] $FinalMessage") -ForegroundColor $Script:Palette.Danger
        }
    } else {
        Write-Host ''
    }
}

# ============================================================================
# 9. INPUT HELPERS
# ============================================================================
function Read-YesNo {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Prompt)
    while ($true) {
        Write-Host -NoNewline "  $Prompt [y/n] " -ForegroundColor $Script:Palette.Prompt
        $ans = (Read-Host).Trim().ToLower()
        if ($ans -eq 'y' -or $ans -eq 'yes') { return $true }
        if ($ans -eq 'n' -or $ans -eq 'no')  { return $false }
        Write-Warn 'Please answer y or n.'
    }
}

function Read-AnyKey {
    [CmdletBinding()] param([string]$Prompt = 'Press any key to continue...')
    Write-Host -NoNewline "  $Prompt " -ForegroundColor $Script:Palette.Muted
    try {
        $null = [Console]::ReadKey($true)
        Write-Host ''
    } catch {
        $null = Read-Host
    }
}

function Test-InteractiveConsole {
    try {
        $null = [Console]::KeyAvailable
        return $true
    } catch {
        return $false
    }
}

function Read-MenuSelection {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][string]$Title,
        [Parameter(Mandatory)][string[]]$Options,
        [int]$DefaultIndex = 0,
        [string]$Footer
    )
    $selected = if ($DefaultIndex -ge 0 -and $DefaultIndex -lt $Options.Count) { $DefaultIndex } else { 0 }

    if (-not (Test-InteractiveConsole)) {
        Write-Banner
        Write-BoxTop -Title $Title
        for ($i = 0; $i -lt $Options.Count; $i++) {
            Write-BoxLine ("[{0}] {1}" -f ($i + 1), $Options[$i])
        }
        if ($Footer) { Write-BoxSeparator; Write-BoxLine $Footer }
        Write-BoxBottom
        while ($true) {
            Write-Host -NoNewline '  Select an option: ' -ForegroundColor $Script:Palette.Prompt
            $c = (Read-Host).Trim()
            if ($c -match '^\d+$') {
                $n = [int]$c
                if ($n -ge 1 -and $n -le $Options.Count) { return ($n - 1) }
            }
            Write-Warn 'Invalid option.'
        }
    }

    # Interactive: arrow-key navigation with in-place repaint.
    # The banner + box top/bottom are drawn ONCE; only the option rows are
    # repainted on each key press (using SetCursorPosition). This eliminates
    # the flicker / latency caused by Clear-Host + full redraw.
    Update-PaletteFromTheme
    Update-BoxWidth
    Write-Banner
    Write-BoxTop -Title $Title
    # Capture the cursor row of the FIRST option line so we can jump back to it.
    $menuTop = [Console]::CursorTop
    for ($i = 0; $i -lt $Options.Count; $i++) { Write-BoxLine '' }   # placeholders
    if ($Footer) {
        Write-BoxSeparator
        Write-BoxLine ''
    }
    Write-BoxBottom
    $footerRow = [Console]::CursorTop - 1
    Write-Host "  Use up/down arrows to navigate, ENTER to select, ESC to cancel" -ForegroundColor $Script:Palette.Muted
    $hintRow = [Console]::CursorTop - 1

    $inner = $Script:BoxWidth - 4

    $drawOption = {
        param($index, $isSelected)
        $row = $menuTop + $index
        try { [Console]::SetCursorPosition(0, $row) } catch { return }
        $opt  = $Options[$index]
        $marker = if ($isSelected) { $Script:Box.Bullet } else { ' ' }
        $line  = " $marker  $opt"
        if ($line.Length -gt $inner) { $line = $line.Substring(0, $inner) }
        $pad = $inner - $line.Length
        # Clear the row first (overwrite with spaces), then paint.
        Write-Host -NoNewline ('  ' + $Script:Box.V + ' ' + (' ' * $inner) + ' ' + $Script:Box.V) -ForegroundColor $Script:Palette.Muted
        try { [Console]::SetCursorPosition(0, $row) } catch { return }
        if ($isSelected) {
            Write-Host -NoNewline ("  " + $Script:Box.V + " ") -ForegroundColor $Script:Palette.Muted
            Write-Host -NoNewline $line -ForegroundColor $Script:Palette.Accent
            Write-Host -NoNewline (' ' * $pad) -ForegroundColor $Script:Palette.Accent
            Write-Host -NoNewline (" " + $Script:Box.V) -ForegroundColor $Script:Palette.Muted
        } else {
            Write-Host -NoNewline ("  " + $Script:Box.V + " ") -ForegroundColor $Script:Palette.Muted
            Write-Host -NoNewline $line -ForegroundColor $Script:Palette.Primary
            Write-Host -NoNewline (' ' * $pad) -ForegroundColor $Script:Palette.Primary
            Write-Host -NoNewline (" " + $Script:Box.V) -ForegroundColor $Script:Palette.Muted
        }
    }

    $drawFooter = {
        if ($Footer) {
            try { [Console]::SetCursorPosition(0, $footerRow - 1) } catch {}
            $t = $Footer
            if ($t.Length -gt ($inner - 6)) { $t = $t.Substring(0, $inner - 6) }
            $decoLen  = $inner - $t.Length - 2
            $sideLen  = [int][Math]::Floor($decoLen / 2)
            $rightLen = $decoLen - $sideLen
            $content = ($Script:Box.H * $sideLen) + ' ' + $t + ' ' + ($Script:Box.H * $rightLen)
            $pad = $inner - $content.Length
            if ($pad -lt 0) { $content = $content.Substring(0, $inner); $pad = 0 }
            Write-Host -NoNewline ('  ' + $Script:Box.V + ' ' + $content + (' ' * $pad) + ' ' + $Script:Box.V) -ForegroundColor $Script:Palette.Accent
        }
    }

    # Initial paint of all options + footer
    for ($i = 0; $i -lt $Options.Count; $i++) {
        & $drawOption $i ($i -eq $selected)
    }
    & $drawFooter

    # Position cursor somewhere harmless so it doesn't blink on an option
    try { [Console]::SetCursorPosition(0, $hintRow) } catch {}

    while ($true) {
        $key = [Console]::ReadKey($true)
        $oldSelected = $selected
        switch ($key.Key) {
            'UpArrow'   { $selected = ($selected - 1 + $Options.Count) % $Options.Count }
            'DownArrow' { $selected = ($selected + 1) % $Options.Count }
            'Home'      { $selected = 0 }
            'End'       { $selected = $Options.Count - 1 }
            'Enter'     {
                # Move cursor below the menu before returning so subsequent
                # output starts on a fresh line.
                try { [Console]::SetCursorPosition(0, $hintRow + 1) } catch {}
                Write-Host ''
                return $selected
            }
            'Escape'    {
                try { [Console]::SetCursorPosition(0, $hintRow + 1) } catch {}
                Write-Host ''
                return -1
            }
            default {
                $dk = $key.KeyChar
                if ($dk -match '^\d$') {
                    $n = [int]$dk.ToString()
                    if ($n -ge 1 -and $n -le $Options.Count) {
                        try { [Console]::SetCursorPosition(0, $hintRow + 1) } catch {}
                        Write-Host ''
                        return ($n - 1)
                    }
                }
            }
        }
        # Only repaint the two rows that changed (old and new selected)
        if ($selected -ne $oldSelected) {
            & $drawOption $oldSelected $false
            & $drawOption $selected   $true
            try { [Console]::SetCursorPosition(0, $hintRow) } catch {}
        }
    }
}

# ============================================================================
# 10. BANNER
# ============================================================================
function Write-FadeIn {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][string[]]$Lines,
        [int]$DelayMs = 40,
        [string]$Color = 'Magenta'
    )
    foreach ($line in $Lines) {
        Write-Host $line -ForegroundColor $Color
        if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
    }
}

function Write-Banner {
    [CmdletBinding()] param()
    # Recolor palette based on the currently selected theme so the whole
    # banner reflects the user's choice.
    Update-PaletteFromTheme

    Clear-Host
    Write-Host ''
    $bar = '  ' + ([string]([char]0x2500) * 78)
    Write-Host $bar -ForegroundColor $Script:Palette.Muted
    Write-Host ''

    # 6-line ANSI shadow banner: ISTAR PACK
    $bannerLines = @(
        ' ██████╗ ██╗    ██╗███████╗██╗  ██╗   ███████╗███████╗████████╗██╗   ██╗██████╗ ',
        ' ██╔══██╗██║    ██║██╔════╝██║  ██║   ██╔════╝██╔════╝╚══██╔══╝██║   ██║██╔══██╗',
        ' ██████╔╝██║ █╗ ██║███████╗███████║   ███████╗█████╗     ██║   ██║   ██║██████╔╝',
        ' ██╔═══╝ ██║███╗██║╚════██║██╔══██║   ╚════██║██╔══╝     ██║   ██║   ██║██╔═══╝ ',
        ' ██║     ╚███╔███╔╝███████║██║  ██║   ███████║███████╗   ██║   ╚██████╔╝██║     ',
        ' ╚═╝      ╚══╝╚══╝ ╚══════╝╚═╝  ╚═╝   ╚══════╝╚══════╝   ╚═╝    ╚═════╝ ╚═╝     '
    )
    Write-FadeIn -Lines $bannerLines -DelayMs 25 -Color $Script:Palette.Logo

    Write-Host ''
    Write-Host ("                      v$($Script:AppVersion)  -  Istar Pack by Israleche") -ForegroundColor $Script:Palette.Muted
    Write-Host ''
    Write-Host $bar -ForegroundColor $Script:Palette.Muted

    $prog    = if ($Script:Settings.ShowProgress)   { 'ON' } else { 'OFF' }
    $debug   = if ($Script:Settings.DebugMode)      { 'ON' } else { 'OFF' }
    $psVer   = "PS $($Script:PSVersion.ToString())"
    $edition = if ($Script:IsCore) { 'Core' } else { 'Desktop' }
    $themeName = $Script:Themes[$Script:Settings.SelectedTheme]
    if (-not $themeName) { $themeName = "Garden's Dream" }

    Write-Host -NoNewline '  progress:' -ForegroundColor $Script:Palette.Muted
    $progColor = if ($prog -eq 'ON') { $Script:Palette.On } else { $Script:Palette.Off }
    Write-Host -NoNewline " $prog" -ForegroundColor $progColor

    Write-Host -NoNewline '   debug:' -ForegroundColor $Script:Palette.Muted
    $dbgColor = if ($debug -eq 'ON') { $Script:Palette.On } else { $Script:Palette.Off }
    Write-Host -NoNewline " $debug" -ForegroundColor $dbgColor

    Write-Host -NoNewline '   runtime:' -ForegroundColor $Script:Palette.Muted
    Write-Host -NoNewline " $psVer ($edition)" -ForegroundColor $Script:Palette.Accent

    Write-Host -NoNewline '   theme:' -ForegroundColor $Script:Palette.Muted
    Write-Host -NoNewline " $themeName" -ForegroundColor $Script:Palette.Logo

    Write-Host ''
    Write-Host $bar -ForegroundColor $Script:Palette.Muted
    Write-Host ''
}

# ============================================================================
# 11. ENVIRONMENT CHECKS
# ============================================================================
function Test-RunningAsAdmin {
    try {
        $id = [Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = New-Object Security.Principal.WindowsPrincipal($id)
        return $pr.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Test-PowerShellVersion {
    try { return $Script:PSVersion -ge [version]'5.1' } catch { return $false }
}

function Test-CommandAvailable {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Command $Name -ErrorAction SilentlyContinue)
}

function Test-ScoopAvailable { return Test-CommandAvailable 'scoop' }
function Test-OhMyPoshAvailable { return Test-CommandAvailable 'oh-my-posh' }
function Test-ZoxideAvailable { return Test-CommandAvailable 'zoxide' }
function Test-FzfAvailable { return Test-CommandAvailable 'fzf' }
function Test-7zipAvailable { return Test-CommandAvailable '7z' }
function Test-GitAvailable { return Test-CommandAvailable 'git' }

function Test-ModuleInstalled {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Name)
    return [bool](Get-Module -ListAvailable -Name $Name -ErrorAction SilentlyContinue)
}

function Get-ProfilePathAuto {
    <#
    .SYNOPSIS
        Returns the path of the profile for the current PowerShell edition.
        PS 7  -> $HOME\Documents\PowerShell\Microsoft.PowerShell_profile.ps1
        PS 5.1-> $HOME\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1
    #>
    try {
        $p = $PROFILE.CurrentUserCurrentHost
        if ($p) { return $p }
    } catch {}
    # Fallback computation
    if ($Script:IsPS7) {
        return Join-Path $HOME 'Documents\PowerShell\Microsoft.PowerShell_profile.ps1'
    } else {
        return Join-Path $HOME 'Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
    }
}

function Get-ThemeDirAuto {
    <#.SYNOPSIS Returns the theme directory for the current PowerShell edition.#>
    $profilePath = Get-ProfilePathAuto
    $dir = Split-Path -Parent $profilePath
    return $dir
}

function Get-ThemePathAuto {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$ThemeKey)
    $dir = Get-ThemeDirAuto
    return Join-Path $dir ("$ThemeKey.omp.json")
}

# ============================================================================
# 12. THEME CATALOG
# ============================================================================
# Each theme is a self-contained Oh My Posh v2 JSON definition. The function
# Get-ThemeJson returns the JSON string for the given key; Install-Theme writes
# that JSON to the right path on disk and rewrites the profile so it points
# to the new theme.

$Script:Themes = [ordered]@{
    'GardensDream'   = 'Garden''s Dream'
    'MidnightCyber'  = 'Midnight Cyber'
    'SakuraBloom'    = 'Sakura Bloom'
    'SolarFlare'     = 'Solar Flare'
    'MonoSlate'      = 'Mono Slate'
    'DraculaReborn'  = 'Dracula Reborn'
}

$Script:ThemeDescriptions = @{
    'GardensDream'   = 'Minimalist green. User + path + git. The signature Istar Pack look.'
    'MidnightCyber'  = 'Dark blue with neon cyan accents. Cyberpunk vibe, single block.'
    'SakuraBloom'    = 'Pink / magenta pastel. Soft and warm, ideal for daytime coding.'
    'SolarFlare'     = 'Orange-red gradient on dark background. Bold and energetic.'
    'MonoSlate'      = 'Pure grayscale, no colors. Maximum focus, zero distraction.'
    'DraculaReborn'  = 'Classic Dracula palette (purple/pink/cyan) in a single-line layout.'
}

# Per-theme accent colors used by the Istar Pack TUI itself (banner ASCII,
# progress bar, box titles). When the user switches themes, the WHOLE Istar
# Pack UI recolors to match the chosen theme.
$Script:ThemeAccents = @{
    'GardensDream'   = @{ Primary = 'Green';    Accent = 'DarkGreen';  Banner = 'Green'    }
    'MidnightCyber'  = @{ Primary = 'Cyan';     Accent = 'DarkCyan';   Banner = 'Cyan'     }
    'SakuraBloom'    = @{ Primary = 'Magenta';  Accent = 'DarkMagenta';Banner = 'Magenta'  }
    'SolarFlare'     = @{ Primary = 'Yellow';   Accent = 'DarkYellow'; Banner = 'Yellow'   }
    'MonoSlate'      = @{ Primary = 'White';    Accent = 'DarkGray';   Banner = 'DarkGray' }
    'DraculaReborn'  = @{ Primary = 'Magenta';  Accent = 'DarkCyan';   Banner = 'Magenta'  }
}

function Get-ThemeAccent {
    <#.SYNOPSIS Returns the accent hashtable for the active theme.#>
    [CmdletBinding()] param([string]$ThemeKey)
    if (-not $ThemeKey) { $ThemeKey = $Script:Settings.SelectedTheme }
    if (-not $ThemeKey) { $ThemeKey = 'GardensDream' }
    $acc = $Script:ThemeAccents[$ThemeKey]
    if (-not $acc) { $acc = $Script:ThemeAccents['GardensDream'] }
    return $acc
}

function Update-PaletteFromTheme {
    <#.SYNOPSIS Recolors $Script:Palette based on the currently selected theme.#>
    $acc = Get-ThemeAccent
    $Script:Palette.Logo   = $acc.Banner
    $Script:Palette.Accent = $acc.Primary
}

function Get-ThemeJson {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Key)
    switch ($Key) {
        'GardensDream' {
            return @'
{
  "$schema": "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json",
  "version": 2,
  "final_space": true,
  "blocks": [
    {
      "type": "prompt",
      "alignment": "left",
      "segments": [
        {
          "type": "session",
          "style": "diamond",
          "leading_diamond": "\ue0b6",
          "trailing_diamond": "",
          "background": "#1B4332",
          "foreground": "#D8F3DC",
          "template": " {{ .UserName }} "
        },
        {
          "type": "path",
          "style": "diamond",
          "leading_diamond": "",
          "trailing_diamond": "",
          "background": "#2B2D30",
          "foreground": "#A7C957",
          "template": " {{ .Path }} ",
          "properties": { "style": "full" }
        },
        {
          "type": "git",
          "style": "diamond",
          "leading_diamond": "",
          "trailing_diamond": "",
          "background": "#3A5A40",
          "foreground": "#DAD7CD",
          "template": " {{ .HEAD }}{{ if .Working.Changed }} <#FF6B6B>*{{ end }}{{ if .Staging.Changed }} <#FFD166>+{{ end }} ",
          "properties": { "branch_icon": "\ue725 ", "fetch_status": true }
        },
        {
          "type": "text",
          "style": "diamond",
          "leading_diamond": "",
          "trailing_diamond": "\ue0b4",
          "background": "#2B2D30",
          "foreground": "#1B4332",
          "template": " \u276f "
        }
      ]
    }
  ]
}
'@
        }
        'MidnightCyber' {
            return @'
{
  "$schema": "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json",
  "version": 2,
  "final_space": true,
  "blocks": [
    {
      "type": "prompt",
      "alignment": "left",
      "segments": [
        {
          "type": "session",
          "style": "diamond",
          "leading_diamond": "\ue0b6",
          "trailing_diamond": "",
          "background": "#0F1B30",
          "foreground": "#00E5FF",
          "template": " \uf0e7 {{ .UserName }} "
        },
        {
          "type": "path",
          "style": "diamond",
          "leading_diamond": "",
          "trailing_diamond": "",
          "background": "#1A2238",
          "foreground": "#9FA8FF",
          "template": " \uf07c {{ .Path }} ",
          "properties": { "style": "full" }
        },
        {
          "type": "git",
          "style": "diamond",
          "leading_diamond": "",
          "trailing_diamond": "\ue0b4",
          "background": "#393E64",
          "foreground": "#00FFB3",
          "template": " \ue725 {{ .HEAD }}{{ if .Working.Changed }} <#FF4D6D>!{{ end }}{{ if .Staging.Changed }} <#FFD93D>?{{ end }} ",
          "properties": { "branch_icon": "", "fetch_status": true }
        }
      ]
    },
    {
      "type": "prompt",
      "alignment": "right",
      "segments": [
        {
          "type": "text",
          "style": "plain",
          "foreground": "#00E5FF",
          "template": "\u203a "
        }
      ]
    }
  ]
}
'@
        }
        'SakuraBloom' {
            return @'
{
  "$schema": "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json",
  "version": 2,
  "final_space": true,
  "blocks": [
    {
      "type": "prompt",
      "alignment": "left",
      "segments": [
        {
          "type": "session",
          "style": "diamond",
          "leading_diamond": "\ue0b6",
          "trailing_diamond": "",
          "background": "#FFC8DD",
          "foreground": "#6D0F4A",
          "template": " \ue26b {{ .UserName }} "
        },
        {
          "type": "path",
          "style": "diamond",
          "leading_diamond": "",
          "trailing_diamond": "",
          "background": "#FFAFCC",
          "foreground": "#5A1145",
          "template": " \uf07c {{ .Path }} ",
          "properties": { "style": "full" }
        },
        {
          "type": "git",
          "style": "diamond",
          "leading_diamond": "",
          "trailing_diamond": "\ue0b4",
          "background": "#BDE0FE",
          "foreground": "#264653",
          "template": " \ue725 {{ .HEAD }}{{ if .Working.Changed }} <#E63946>*{{ end }}{{ if .Staging.Changed }} <#F4A261>+{{ end }} ",
          "properties": { "branch_icon": "", "fetch_status": true }
        }
      ]
    },
    {
      "type": "prompt",
      "alignment": "right",
      "segments": [
        {
          "type": "text",
          "style": "plain",
          "foreground": "#FF85A1",
          "template": "\u273f "
        }
      ]
    }
  ]
}
'@
        }
        'SolarFlare' {
            return @'
{
  "$schema": "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json",
  "version": 2,
  "final_space": true,
  "blocks": [
    {
      "type": "prompt",
      "alignment": "left",
      "segments": [
        {
          "type": "session",
          "style": "diamond",
          "leading_diamond": "\ue0b6",
          "trailing_diamond": "",
          "background": "#7A1F00",
          "foreground": "#FFE5B4",
          "template": " \uf2bd {{ .UserName }} "
        },
        {
          "type": "path",
          "style": "diamond",
          "leading_diamond": "",
          "trailing_diamond": "",
          "background": "#B23A0E",
          "foreground": "#FFF1C1",
          "template": " \uf07c {{ .Path }} ",
          "properties": { "style": "full" }
        },
        {
          "type": "git",
          "style": "diamond",
          "leading_diamond": "",
          "trailing_diamond": "\ue0b4",
          "background": "#E85D04",
          "foreground": "#1A0F00",
          "template": " \ue725 {{ .HEAD }}{{ if .Working.Changed }} <#FFD60A>!{{ end }}{{ if .Staging.Changed }} <#FFBA08>?{{ end }} ",
          "properties": { "branch_icon": "", "fetch_status": true }
        }
      ]
    },
    {
      "type": "prompt",
      "alignment": "right",
      "segments": [
        {
          "type": "text",
          "style": "plain",
          "foreground": "#F48C06",
          "template": "\u2600 "
        }
      ]
    }
  ]
}
'@
        }
        'MonoSlate' {
            return @'
{
  "$schema": "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json",
  "version": 2,
  "final_space": true,
  "blocks": [
    {
      "type": "prompt",
      "alignment": "left",
      "segments": [
        {
          "type": "session",
          "style": "diamond",
          "leading_diamond": "\ue0b6",
          "trailing_diamond": "",
          "background": "#2B2B2B",
          "foreground": "#E0E0E0",
          "template": " {{ .UserName }} "
        },
        {
          "type": "path",
          "style": "diamond",
          "leading_diamond": "",
          "trailing_diamond": "",
          "background": "#1A1A1A",
          "foreground": "#BDBDBD",
          "template": " {{ .Path }} ",
          "properties": { "style": "full" }
        },
        {
          "type": "git",
          "style": "diamond",
          "leading_diamond": "",
          "trailing_diamond": "\ue0b4",
          "background": "#3A3A3A",
          "foreground": "#9E9E9E",
          "template": " {{ .HEAD }}{{ if .Working.Changed }} *{{ end }}{{ if .Staging.Changed }} +{{ end }} ",
          "properties": { "branch_icon": "", "fetch_status": true }
        }
      ]
    },
    {
      "type": "prompt",
      "alignment": "right",
      "segments": [
        {
          "type": "text",
          "style": "plain",
          "foreground": "#757575",
          "template": "\u203a "
        }
      ]
    }
  ]
}
'@
        }
        'DraculaReborn' {
            return @'
{
  "$schema": "https://raw.githubusercontent.com/JanDeDobbeleer/oh-my-posh/main/themes/schema.json",
  "version": 2,
  "final_space": true,
  "blocks": [
    {
      "type": "prompt",
      "alignment": "left",
      "segments": [
        {
          "type": "session",
          "style": "diamond",
          "leading_diamond": "\ue0b6",
          "trailing_diamond": "",
          "background": "#282A36",
          "foreground": "#50FA7B",
          "template": " \uf1d3 {{ .UserName }} "
        },
        {
          "type": "path",
          "style": "diamond",
          "leading_diamond": "",
          "trailing_diamond": "",
          "background": "#44475A",
          "foreground": "#F8F8F2",
          "template": " \uf07c {{ .Path }} ",
          "properties": { "style": "full" }
        },
        {
          "type": "git",
          "style": "diamond",
          "leading_diamond": "",
          "trailing_diamond": "\ue0b4",
          "background": "#6272A4",
          "foreground": "#FF79C6",
          "template": " \ue725 {{ .HEAD }}{{ if .Working.Changed }} <#FF5555>!{{ end }}{{ if .Staging.Changed }} <#F1FA8C>?{{ end }} ",
          "properties": { "branch_icon": "", "fetch_status": true }
        }
      ]
    },
    {
      "type": "prompt",
      "alignment": "right",
      "segments": [
        {
          "type": "text",
          "style": "plain",
          "foreground": "#BD93F9",
          "template": "\u276f "
        }
      ]
    }
  ]
}
'@
        }
        default {
            return Get-ThemeJson -Key 'GardensDream'
        }
    }
}

# ============================================================================
# 13. INSTALLATION: Scoop
# ============================================================================
function Install-ScoopIfNeeded {
    <#
    .SYNOPSIS
        Installs Scoop if missing. Sets execution policy first.
    #>
    [CmdletBinding()] param()
    Write-Step 'Checking Scoop...'
    if (Test-ScoopAvailable) {
        Write-Ok 'Scoop already installed.'
        return $true
    }
    if (-not $Script:Settings.InstallScoop) {
        Write-Warn 'Scoop install disabled in settings. Skipping.'
        return $false
    }
    Write-Step 'Setting execution policy RemoteSigned (CurrentUser)...'
    try {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force -ErrorAction Stop
    } catch {
        Write-Warn "Could not set execution policy: $($_.Exception.Message)"
    }
    Write-Step 'Downloading and installing Scoop...'
    $spin = New-Spinner -Label 'Installing Scoop' -Style Braille
    $job = Start-Job -ScriptBlock {
        try {
            $null = & chcp.com 65001 2>$null
            irm get.scoop.sh | iex
        } catch {
            Write-Output "ERR: $($_.Exception.Message)"
        }
    }
    while ($job.State -eq 'Running') {
        Update-Spinner $spin
        Start-Sleep -Milliseconds 120
    }
    $out = Receive-Job $job
    Remove-Job $job -Force
    # Refresh PATH for current session
    try {
        $env:PATH = [Environment]::GetEnvironmentVariable('PATH','User') + ';' + [Environment]::GetEnvironmentVariable('PATH','Machine')
    } catch {}
    if (Test-ScoopAvailable) {
        Complete-Spinner $spin -FinalMessage 'Scoop installed' -Success
        return $true
    } else {
        Complete-Spinner $spin -FinalMessage 'Scoop install failed' -Success:$false
        Write-Err "Scoop output: $out"
        Write-Warn 'You may need to install Scoop manually from https://scoop.sh'
        return $false
    }
}

function Ensure-ScoopBuckets {
    [CmdletBinding()] param()
    if (-not (Test-ScoopAvailable)) { return }
    Write-Step 'Ensuring extras bucket...'
    $spin = New-Spinner -Label 'Adding extras bucket' -Style Braille
    try {
        $buckets = & scoop bucket list 2>$null
        if ($buckets -notcontains 'extras') {
            & scoop bucket add extras 2>&1 | Out-Null
        }
    } catch {}
    Start-Sleep -Milliseconds 200
    Complete-Spinner $spin -FinalMessage 'Buckets ready' -Success
}

# ============================================================================
# 14. INSTALLATION: CLI Tools via Scoop
# ============================================================================
function Install-ScoopPackage {
    [CmdletBinding()] param([Parameter(Mandatory)][string]$Package)
    try {
        $installed = & scoop list 2>$null | Select-String -Pattern "^$Package\s" -SimpleMatch
        if ($installed) { return $true }
    } catch {}
    Write-Step "Installing $Package..."
    try {
        & scoop install $Package 2>&1 | Out-Null
        return $true
    } catch {
        Write-Warn "Failed to install $Package : $($_.Exception.Message)"
        return $false
    }
}

function Install-AllCliTools {
    <#
    .SYNOPSIS
        Installs git, fzf, zoxide, oh-my-posh, 7zip via Scoop.
    #>
    [CmdletBinding()] param()
    if (-not (Test-ScoopAvailable)) {
        Write-Warn 'Scoop not available. Cannot install CLI tools.'
        return $false
    }
    Ensure-ScoopBuckets

    $packages = @('git','fzf','zoxide','oh-my-posh','7zip')
    $total = $packages.Count
    $ok = 0
    $i = 0
    foreach ($pkg in $packages) {
        $i++
        $pct = [int](($i / $total) * 100)
        if (Install-ScoopPackage -Package $pkg) {
            Write-Ok "$pkg ready"
            $ok++
        } else {
            Write-Err "$pkg failed"
        }
        if ($Script:Settings.ShowProgress) {
            Write-ProgressBar -Percent $pct -Style Blocks -Label "($i/$total)"
        }
    }
    # Refresh PATH
    try {
        $env:PATH = [Environment]::GetEnvironmentVariable('PATH','User') + ';' + [Environment]::GetEnvironmentVariable('PATH','Machine')
    } catch {}
    Write-Info "Installed $ok/$total CLI tools."
    return ($ok -eq $total)
}

# ============================================================================
# 15. INSTALLATION: Nerd Font
# ============================================================================
function Install-NerdFontIfNeeded {
    <#
    .SYNOPSIS
        Installs CascadiaCode Nerd Font via Oh My Posh.
    #>
    [CmdletBinding()] param()
    if (-not $Script:Settings.InstallFont) {
        Write-Step 'Font install disabled. Skipping.'
        return $true
    }
    if (-not (Test-OhMyPoshAvailable)) {
        Write-Warn 'oh-my-posh not available. Cannot install font.'
        return $false
    }
    Write-Step 'Installing CascadiaCode Nerd Font...'
    $spin = New-Spinner -Label 'Installing Cascadia Code Nerd Font' -Style Braille
    try {
        & oh-my-posh font install CascadiaCode 2>&1 | Out-Null
        Start-Sleep -Milliseconds 500
        Complete-Spinner $spin -FinalMessage 'CascadiaCode Nerd Font installed' -Success
        return $true
    } catch {
        Complete-Spinner $spin -FinalMessage 'Font install failed' -Success:$false
        Write-Warn "Font install error: $($_.Exception.Message)"
        Write-Warn 'You can install manually: oh-my-posh font install CascadiaCode'
        return $false
    }
}

# ============================================================================
# 16. INSTALLATION: PowerShell Modules
# ============================================================================
function Install-PsModule {
    [CmdletBinding()] param(
        [Parameter(Mandatory)][string]$Name,
        [switch]$AllowPrerelease,
        [switch]$AllowClobber
    )
    if (Test-ModuleInstalled -Name $Name) {
        Write-Ok "$Name already installed"
        return $true
    }
    if (-not $Script:Settings.InstallModules) {
        Write-Step "Module install disabled. Skipping $Name."
        return $true
    }
    Write-Step "Installing module: $Name..."
    try {
        $params = @{
            Name           = $Name
            Repository     = 'PSGallery'
            Force          = $true
            Scope          = 'CurrentUser'
            ErrorAction    = 'Stop'
        }
        if ($AllowClobber)    { $params.AllowClobber    = $true }
        if ($AllowPrerelease -and $Script:IsPS7) { $params.AllowPrerelease = $true }
        Install-Module @params
        Write-Ok "$Name installed"
        return $true
    } catch {
        Write-Warn "Could not install $Name : $($_.Exception.Message)"
        return $false
    }
}

function Install-AllPsModules {
    <#
    .SYNOPSIS
        Installs Terminal-Icons, PSReadLine, PSFzf, and (on PS7) CompletionPredictor.
    #>
    [CmdletBinding()] param()
    Write-Step 'Trusting PSGallery repository...'
    try {
        Set-PSRepository -Name PSGallery -InstallationPolicy Trusted -ErrorAction SilentlyContinue
    } catch {}

    $ok = $true
    $ok = (Install-PsModule -Name 'Terminal-Icons') -and $ok
    $ok = (Install-PsModule -Name 'PSReadLine' -AllowClobber -AllowPrerelease) -and $ok
    $ok = (Install-PsModule -Name 'PSFzf') -and $ok
    # CompletionPredictor only works on PS 7+
    if ($Script:IsPS7) {
        $ok = (Install-PsModule -Name 'CompletionPredictor') -and $ok
    } else {
        Write-Step 'CompletionPredictor requires PS 7+. Skipping (use History prediction instead).'
    }
    return $ok
}

# ============================================================================
# 17. PROFILE BACKUP / WRITE
# ============================================================================
function Backup-ExistingProfile {
    <#
    .SYNOPSIS
        Copies the current $PROFILE to Istar-Pack-Backups with a timestamp.
    #>
    [CmdletBinding()] param()
    $profilePath = Get-ProfilePathAuto
    if (-not (Test-Path -LiteralPath $profilePath)) {
        Write-Step 'No existing profile to back up.'
        return $true
    }
    if (-not (Test-Path -LiteralPath $Script:BackupDir)) {
        try { New-Item -ItemType Directory -Path $Script:BackupDir -Force | Out-Null } catch {}
    }
    $stamp = (Get-Date -Format 'yyyyMMdd_HHmmss')
    $edition = if ($Script:IsPS7) { 'PS7' } else { 'PS5' }
    $backupName = "profile_${edition}_$stamp.ps1"
    $backupPath = Join-Path $Script:BackupDir $backupName
    try {
        Copy-Item -LiteralPath $profilePath -Destination $backupPath -Force
        Write-Ok "Profile backed up to: $backupPath"
        return $true
    } catch {
        Write-Warn "Backup failed: $($_.Exception.Message)"
        return $false
    }
}

function Get-ProfileContent {
    <#
    .SYNOPSIS
        Returns the profile script body tuned for the current PS edition.
        PS 7 uses HistoryAndPlugin + native `e escape; PS 5.1 uses History +
        [char]27. Avoids the UpArrow/DownArrow/ListView conflict identified
        in the original Istar Pack analysis.
    #>
    [CmdletBinding()] param([Parameter(Mandatory)][string]$ThemeKey)

    $themePath = Join-Path (Get-ThemeDirAuto) "$ThemeKey.omp.json"

    if ($Script:IsPS7) {
        return @"
# ============================================================
#  Istar Pack - PowerShell 7 Profile
#  Theme: $ThemeKey
#  Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# ============================================================

`$themePath = '$themePath'
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    if (Test-Path `$themePath) {
        oh-my-posh init pwsh --config `$themePath | Invoke-Expression
    } else {
        Write-Host "Istar Pack: theme file not found at `$themePath" -ForegroundColor Yellow
    }
} else {
    Write-Host 'Istar Pack: oh-my-posh not installed. Run: scoop install oh-my-posh' -ForegroundColor Yellow
}

Import-Module Terminal-Icons -ErrorAction SilentlyContinue
Import-Module CompletionPredictor -ErrorAction SilentlyContinue

if (Get-Module PSReadLine) {
    try {
        Set-PSReadLineOption -PredictionSource HistoryAndPlugin
        Set-PSReadLineOption -PredictionViewStyle ListView
    } catch {
        try { Set-PSReadLineOption -PredictionSource History } catch {}
    }
    Set-PSReadLineOption -EditMode Emacs
    Set-PSReadLineOption -MaximumHistoryCount 4096
    Set-PSReadLineOption -HistoryNoDuplicates
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineOption -BellStyle None

    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Key RightArrow -Function AcceptNextSuggestionWord
    Set-PSReadLineKeyHandler -Key Ctrl+RightArrow -Function ForwardWord
    Set-PSReadLineKeyHandler -Key Ctrl+r -Function ReverseSearchHistory
    Set-PSReadLineKeyHandler -Key Ctrl+UpArrow   -Function HistorySearchBackward
    Set-PSReadLineKeyHandler -Key Ctrl+DownArrow -Function HistorySearchForward

    Set-PSReadLineOption -Colors @{
        Command                = '#A7C957'
        Parameter              = '#D8F3DC'
        String                 = '#6A994E'
        Number                 = '#B5E48C'
        Operator               = '#81C784'
        Variable               = '#D8F3DC'
        Comment                = '#6C757D'
        InlinePrediction       = '#6C757D'
        ListPrediction         = '#81C784'
        Emphasis               = '#4DB6AC'
        Selection              = "`e[48;2;27;67;50m"
        ListPredictionSelected = "`e[48;2;27;67;50m"
    }
}

if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

if (Get-Module -ListAvailable PSFzf) {
    Import-Module PSFzf
    Set-PsFzfOption -PSReadlineChordProvider 'Ctrl+t' -PSReadlineChordReverseHistory 'Ctrl+r'
}

Set-Alias -Name ll    -Value Get-ChildItem
Set-Alias -Name which -Value Get-Command
Set-Alias -Name touch -Value New-Item
Set-Alias -Name grep  -Value Select-String

function la { Get-ChildItem -Force }
function lh { Get-ChildItem -Force -Hidden }
function op  { Invoke-Item . }
function ..  { Set-Location .. }
function ... { Set-Location ../.. }
function gs { git status }
function gl { git log --oneline --graph --decorate -15 }
function gd { git diff }

function extract {
    if (-not `$args[0]) { Write-Host 'Uso: extract <archivo>' -ForegroundColor Yellow; return }
    if (-not (Get-Command 7z -ErrorAction SilentlyContinue)) {
        Write-Host '7-Zip no esta instalado. Ejecuta: scoop install 7zip' -ForegroundColor Red
        return
    }
    `$file = (Resolve-Path `$args[0] -ErrorAction SilentlyContinue).Path
    if (-not `$file) { Write-Host "Archivo no encontrado: `$(`$args[0])" -ForegroundColor Red; return }
    & 7z x `$file
}

function mkcd {
    param([Parameter(Mandatory)][string]`$path)
    New-Item -ItemType Directory -Path `$path -Force | Out-Null
    Set-Location `$path
}

function Get-PublicIP { (Invoke-RestMethod -Uri 'https://api.ipify.org?format=json').ip }

`$host.UI.RawUI.WindowTitle = "PS `$(`$PSVersionTable.PSVersion) - `$env:USERNAME"
"@
    } else {
        # PowerShell 5.1
        return @"
# ============================================================
#  Istar Pack - Windows PowerShell 5.1 Profile
#  Theme: $ThemeKey
#  Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
# ============================================================

`$themePath = '$themePath'
if (Get-Command oh-my-posh -ErrorAction SilentlyContinue) {
    if (Test-Path `$themePath) {
        oh-my-posh init pwsh --config `$themePath | Invoke-Expression
    } else {
        Write-Host "Istar Pack: theme file not found at `$themePath" -ForegroundColor Yellow
    }
} else {
    Write-Host 'Istar Pack: oh-my-posh not installed. Run: scoop install oh-my-posh' -ForegroundColor Yellow
}

Import-Module Terminal-Icons -ErrorAction SilentlyContinue
# CompletionPredictor is PS7-only, intentionally omitted here.

if (Get-Module PSReadLine) {
    `$psrlVersion = (Get-Module PSReadLine).Version
    if (`$psrlVersion -ge [Version]'2.2.0') {
        try {
            Set-PSReadLineOption -PredictionSource History
            Set-PSReadLineOption -PredictionViewStyle ListView
        } catch {}
    }
    Set-PSReadLineOption -EditMode Emacs
    Set-PSReadLineOption -MaximumHistoryCount 4096
    Set-PSReadLineOption -HistoryNoDuplicates
    Set-PSReadLineOption -HistorySearchCursorMovesToEnd
    Set-PSReadLineOption -BellStyle None

    Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete
    Set-PSReadLineKeyHandler -Key Ctrl+r -Function ReverseSearchHistory
    Set-PSReadLineKeyHandler -Key Ctrl+RightArrow -Function ForwardWord
    if (`$psrlVersion -ge [Version]'2.2.0') {
        Set-PSReadLineKeyHandler -Key RightArrow -Function AcceptNextSuggestionWord
        Set-PSReadLineKeyHandler -Key Ctrl+UpArrow   -Function HistorySearchBackward
        Set-PSReadLineKeyHandler -Key Ctrl+DownArrow -Function HistorySearchForward
    } else {
        Set-PSReadLineKeyHandler -Key UpArrow   -Function HistorySearchBackward
        Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward
    }

    `$esc = [char]27
    Set-PSReadLineOption -Colors @{
        Command   = "`$esc[38;2;167;201;87m"
        Parameter = "`$esc[38;2;216;243;220m"
        String    = "`$esc[38;2;106;153;78m"
        Number    = "`$esc[38;2;181;228;140m"
        Operator  = "`$esc[38;2;129;199;132m"
        Variable  = "`$esc[38;2;216;243;220m"
        Comment   = "`$esc[38;2;108;117;125m"
        Selection = "`$esc[48;2;27;67;50m"
        Emphasis  = "`$esc[38;2;77;182;172m"
    }
}

if (Get-Command zoxide -ErrorAction SilentlyContinue) {
    Invoke-Expression (& { (zoxide init powershell | Out-String) })
}

Set-Alias -Name ll    -Value Get-ChildItem
Set-Alias -Name which -Value Get-Command
Set-Alias -Name touch -Value New-Item
Set-Alias -Name grep  -Value Select-String

function la { Get-ChildItem -Force }
function lh { Get-ChildItem -Force -Hidden }
function op  { Invoke-Item . }
function ..  { Set-Location .. }
function ... { Set-Location ../.. }
function gs { git status }
function gl { git log --oneline --graph --decorate -15 }
function gd { git diff }

function extract {
    if (-not `$args[0]) { Write-Host 'Uso: extract <archivo>' -ForegroundColor Yellow; return }
    if (-not (Get-Command 7z -ErrorAction SilentlyContinue)) {
        Write-Host '7-Zip no esta instalado. Ejecuta: scoop install 7zip' -ForegroundColor Red
        return
    }
    `$file = (Resolve-Path `$args[0] -ErrorAction SilentlyContinue).Path
    if (-not `$file) { Write-Host "Archivo no encontrado: `$(`$args[0])" -ForegroundColor Red; return }
    & 7z x `$file
}

function mkcd {
    param([Parameter(Mandatory=`$true)][string]`$path)
    New-Item -ItemType Directory -Path `$path -Force | Out-Null
    Set-Location `$path
}

function Get-PublicIP { (Invoke-RestMethod -Uri 'https://api.ipify.org?format=json').ip }

`$host.UI.RawUI.WindowTitle = "Windows PS `$(`$PSVersionTable.PSVersion) - `$env:USERNAME"

Write-Host "Istar Pack loaded. Tip: install PowerShell 7 for the full experience." -ForegroundColor DarkGray
Write-Host "  winget install Microsoft.PowerShell" -ForegroundColor DarkGray
"@
    }
}

function Write-ProfileToDisk {
    <#
    .SYNOPSIS
        Writes the Istar Pack profile to the correct $PROFILE path for the
        current PowerShell edition. Creates parent dir if missing.
    #>
    [CmdletBinding()] param([Parameter(Mandatory)][string]$ThemeKey)
    $profilePath = Get-ProfilePathAuto
    $profileDir  = Split-Path -Parent $profilePath
    if (-not (Test-Path -LiteralPath $profileDir)) {
        try { New-Item -ItemType Directory -Path $profileDir -Force | Out-Null } catch {}
    }
    Write-Step "Writing profile to: $profilePath"
    $content = Get-ProfileContent -ThemeKey $ThemeKey
    try {
        # UTF-8 with BOM so PS 5.1 reads box-drawing chars correctly
        $utf8Bom = New-Object System.Text.UTF8Encoding $true
        [System.IO.File]::WriteAllText($profilePath, $content, $utf8Bom)
        Write-Ok 'Profile written.'
        return $true
    } catch {
        Write-Err "Could not write profile: $($_.Exception.Message)"
        return $false
    }
}

function Install-ThemeToDisk {
    <#
    .SYNOPSIS
        Writes the selected theme JSON to the theme directory.
    #>
    [CmdletBinding()] param([Parameter(Mandatory)][string]$ThemeKey)
    $themeDir = Get-ThemeDirAuto
    if (-not (Test-Path -LiteralPath $themeDir)) {
        try { New-Item -ItemType Directory -Path $themeDir -Force | Out-Null } catch {}
    }
    $themePath = Join-Path $themeDir "$ThemeKey.omp.json"
    Write-Step "Writing theme to: $themePath"
    $json = Get-ThemeJson -Key $ThemeKey
    try {
        $utf8Bom = New-Object System.Text.UTF8Encoding $false
        [System.IO.File]::WriteAllText($themePath, $json, $utf8Bom)
        Write-Ok 'Theme written.'
        return $true
    } catch {
        Write-Err "Could not write theme: $($_.Exception.Message)"
        return $false
    }
}

# ============================================================================
# 18. FULL INSTALLATION ORCHESTRATOR
# ============================================================================
function Invoke-FullInstall {
    <#
    .SYNOPSIS
        Runs the full Istar Pack setup: scoop -> tools -> modules -> font ->
        backup -> theme -> profile. Returns $true if everything succeeded.
    #>
    [CmdletBinding()] param(
        [string]$ThemeKey = $Script:Settings.SelectedTheme
    )
    Write-Banner
    Write-BoxTop -Title 'ISTAR PACK - FULL INSTALLATION'
    Write-BoxLine ''
    Write-BoxLine 'This will:'
    Write-BoxLine '  1. Install Scoop (if missing)'
    Write-BoxLine '  2. Install git, fzf, zoxide, oh-my-posh, 7zip'
    Write-BoxLine '  3. Install Terminal-Icons, PSReadLine, PSFzf'
    if ($Script:IsPS7) {
        Write-BoxLine '  4. Install CompletionPredictor (PS 7 only)'
        Write-BoxLine '  5. Install CascadiaCode Nerd Font'
        Write-BoxLine '  6. Back up your existing profile'
        Write-BoxLine "  7. Apply theme: $($Script:Themes[$ThemeKey])"
        Write-BoxLine '  8. Write the Istar Pack profile'
    } else {
        Write-BoxLine '  4. Install CascadiaCode Nerd Font'
        Write-BoxLine '  5. Back up your existing profile'
        Write-BoxLine "  6. Apply theme: $($Script:Themes[$ThemeKey])"
        Write-BoxLine '  7. Write the Istar Pack profile'
    }
    Write-BoxLine ''
    Write-BoxKeyValue -Key 'PowerShell'   -Value $Script:PSVersion.ToString()
    Write-BoxKeyValue -Key 'Edition'      -Value $(if ($Script:IsPS7) { 'Core (PS 7+)' } else { 'Desktop (PS 5.1)' })
    Write-BoxKeyValue -Key 'Profile path' -Value (Get-ProfilePathAuto)
    Write-BoxKeyValue -Key 'Theme dir'    -Value (Get-ThemeDirAuto)
    Write-BoxLine ''
    Write-BoxBottom
    Write-Host ''

    if (-not $Silent) {
        if (-not (Read-YesNo 'Proceed with full installation?')) {
            Write-Warn 'Installation cancelled.'
            Read-AnyKey 'Press any key to return to the menu...'
            return $false
        }
    }

    $steps = 0; $ok = 0

    # 1. Scoop
    $steps++; Write-Step "[1/$steps] Scoop";  if (Install-ScoopIfNeeded)  { $ok++ }

    # 2. CLI tools
    $steps++; Write-Step "[2/$steps] CLI tools";  if (Install-AllCliTools) { $ok++ }

    # 3. Modules
    $steps++; Write-Step "[3/$steps] Modules";   if (Install-AllPsModules)  { $ok++ }

    # 4. Font
    $steps++; Write-Step "[4/$steps] Nerd Font"; if (Install-NerdFontIfNeeded) { $ok++ }

    # 5. Backup
    $steps++; Write-Step "[5/$steps] Backup profile"; if (Backup-ExistingProfile) { $ok++ }

    # 6. Theme
    $steps++; Write-Step "[6/$steps] Theme ($ThemeKey)"; if (Install-ThemeToDisk -ThemeKey $ThemeKey) { $ok++ }

    # 7. Profile
    $steps++; Write-Step "[7/$steps] Write profile"; if (Write-ProfileToDisk -ThemeKey $ThemeKey) { $ok++ }

    Write-Host ''
    if ($ok -eq $steps) {
        Write-ProgressBar -Percent 100 -Style Blocks -Label 'All steps complete'
        Write-Ok "Istar Pack installation complete. ($ok/$steps steps)"
        $Script:Settings.LastFullInstall = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
        Export-Settings
        Write-Info 'Open a NEW terminal to load the new profile.'
    } else {
        Write-Warn "Installation finished with issues. ($ok/$steps steps succeeded)"
        Write-Info 'Check the warnings above. You can re-run "Full install" any time.'
    }
    Write-Host ''
    if (-not $Silent) { Read-AnyKey 'Press any key to return to the menu...' }
    return ($ok -eq $steps)
}

# ============================================================================
# 19. THEME BROWSER
# ============================================================================
function Show-ThemeBrowser {
    <#.SYNOPSIS Displays all available themes with descriptions.#>
    [CmdletBinding()] param()
    Write-Banner
    Write-BoxTop -Title 'THEME CATALOG'
    Write-BoxLine ''
    foreach ($key in $Script:Themes.Keys) {
        $name = $Script:Themes[$key]
        $desc = $Script:ThemeDescriptions[$key]
        $marker = if ($key -eq $Script:Settings.SelectedTheme) { '[ACTIVE]' } else { '        ' }
        Write-BoxLine ("$marker $name")
        Write-BoxLine ("         $desc")
        Write-BoxLine ''
    }
    Write-BoxBottom
    Write-Host ''
    Read-AnyKey 'Press any key to return to the menu...'
}

function Invoke-SelectTheme {
    <#.SYNOPSIS Interactive theme picker. Applies the chosen theme immediately.#>
    [CmdletBinding()] param()
    $opts = @()
    foreach ($key in $Script:Themes.Keys) {
        $name = $Script:Themes[$key]
        $marker = if ($key -eq $Script:Settings.SelectedTheme) { ' (current)' } else { '' }
        $opts += "$name$marker"
    }
    $opts += 'Cancel'
    $sel = Read-MenuSelection -Title 'SELECT THEME' -Options $opts -DefaultIndex 0
    if ($sel -lt 0 -or $sel -ge $Script:Themes.Count) {
        Write-Warn 'Theme selection cancelled.'
        Start-Sleep -Milliseconds 400
        return
    }
    $keys = @($Script:Themes.Keys)
    $newKey = $keys[$sel]
    $Script:Settings.SelectedTheme = $newKey
    Export-Settings
    Write-Ok "Selected theme: $($Script:Themes[$newKey])"

    Write-Step 'Writing theme JSON to disk...'
    if (Install-ThemeToDisk -ThemeKey $newKey) {
        Write-Step 'Updating profile to use new theme...'
        if (Write-ProfileToDisk -ThemeKey $newKey) {
            Write-Ok 'Theme applied. Open a NEW terminal to see it.'
        }
    }
    Start-Sleep -Milliseconds 800
}

# ============================================================================
# 20. VERIFICATION
# ============================================================================
function Show-Verification {
    <#.SYNOPSIS Runs sanity checks and renders a status report.#>
    [CmdletBinding()] param()
    Write-Banner
    Write-BoxTop -Title 'INSTALLATION VERIFICATION'
    Write-BoxLine ''
    Write-BoxSubtitle -Title 'COMMAND-LINE TOOLS'
    $tools = @(
        @('scoop',      { Test-ScoopAvailable }),
        @('git',        { Test-GitAvailable }),
        @('fzf',        { Test-FzfAvailable }),
        @('zoxide',     { Test-ZoxideAvailable }),
        @('oh-my-posh', { Test-OhMyPoshAvailable }),
        @('7z',         { Test-7zipAvailable })
    )
    foreach ($t in $tools) {
        $name = $t[0]
        $check = & $t[1]
        $state = if ($check) { 'OK' } else { 'MISSING' }
        $color = if ($check) { $Script:Palette.On } else { $Script:Palette.Danger }
        Write-BoxKeyValue -Key $name -Value $state -ValueColor $color
    }
    Write-BoxLine ''
    Write-BoxSeparator
    Write-BoxSubtitle -Title 'POWERSHELL MODULES'
    $modules = @('Terminal-Icons','PSReadLine','PSFzf')
    if ($Script:IsPS7) { $modules += 'CompletionPredictor' }
    foreach ($m in $modules) {
        $state = if (Test-ModuleInstalled -Name $m) { 'OK' } else { 'MISSING' }
        $color = if ($state -eq 'OK') { $Script:Palette.On } else { $Script:Palette.Danger }
        Write-BoxKeyValue -Key $m -Value $state -ValueColor $color
    }
    Write-BoxLine ''
    Write-BoxSeparator
    Write-BoxSubtitle -Title 'PROFILE & THEME'
    $profilePath = Get-ProfilePathAuto
    $profileExists = Test-Path -LiteralPath $profilePath
    Write-BoxKeyValue -Key 'Profile path' -Value $profilePath
    Write-BoxKeyValue -Key 'Profile present' -Value $(if ($profileExists) { 'YES' } else { 'NO' }) -ValueColor $(if ($profileExists) { $Script:Palette.On } else { $Script:Palette.Danger })

    $themeKey = $Script:Settings.SelectedTheme
    $themePath = Join-Path (Get-ThemeDirAuto) "$themeKey.omp.json"
    $themeExists = Test-Path -LiteralPath $themePath
    Write-BoxKeyValue -Key 'Active theme'  -Value $Script:Themes[$themeKey]
    Write-BoxKeyValue -Key 'Theme path'    -Value $themePath
    Write-BoxKeyValue -Key 'Theme present' -Value $(if ($themeExists) { 'YES' } else { 'NO' }) -ValueColor $(if ($themeExists) { $Script:Palette.On } else { $Script:Palette.Danger })
    Write-BoxLine ''
    Write-BoxSeparator
    Write-BoxSubtitle -Title 'SESSION'
    Write-BoxKeyValue -Key 'PowerShell version' -Value $Script:PSVersion.ToString()
    Write-BoxKeyValue -Key 'Edition'            -Value $(if ($Script:IsPS7) { 'Core (PS 7+)' } else { 'Desktop (PS 5.1)' })
    Write-BoxKeyValue -Key 'Running as admin'   -Value $(if (Test-RunningAsAdmin) { 'YES' } else { 'NO' })
    $last = if ($Script:Settings.LastFullInstall) { $Script:Settings.LastFullInstall } else { 'never' }
    Write-BoxKeyValue -Key 'Last full install'   -Value $last
    Write-BoxLine ''
    Write-BoxBottom
    Write-Host ''
    Read-AnyKey 'Press any key to return to the menu...'
}

# ============================================================================
# 21. BACKUP MENU
# ============================================================================
function Show-BackupMenu {
    <#.SYNOPSIS Backs up the current profile on demand.#>
    [CmdletBinding()] param()
    Write-Banner
    Write-BoxTop -Title 'BACKUP CURRENT PROFILE'
    Write-BoxLine ''
    $profilePath = Get-ProfilePathAuto
    if (Test-Path -LiteralPath $profilePath) {
        Write-BoxLine "Current profile: $profilePath"
        $size = (Get-Item -LiteralPath $profilePath).Length
        Write-BoxLine "Size: $size bytes"
        $mtime = (Get-Item -LiteralPath $profilePath).LastWriteTime
        Write-BoxLine "Last modified: $($mtime.ToString('yyyy-MM-dd HH:mm:ss'))"
        Write-BoxLine ''
        Write-BoxLine 'A timestamped copy will be saved to:'
        Write-BoxLine $Script:BackupDir
    } else {
        Write-BoxLine 'No existing profile was found at:'
        Write-BoxLine $profilePath
        Write-BoxLine ''
        Write-BoxLine 'Nothing to back up. Run Full Install first.'
    }
    Write-BoxLine ''
    Write-BoxBottom
    if (Test-Path -LiteralPath $profilePath) {
        if (Read-YesNo 'Create backup now?') {
            Backup-ExistingProfile | Out-Null
        }
    }
    Write-Host ''
    Read-AnyKey 'Press any key to return to the menu...'
}

# ============================================================================
# 22. SETTINGS MENU
# ============================================================================
function Show-SettingsMenu {
    [CmdletBinding()] param()
    while ($true) {
        $progState  = if ($Script:Settings.ShowProgress) { 'ON' } else { 'OFF' }
        $debugState = if ($Script:Settings.DebugMode)    { 'ON' } else { 'OFF' }
        $scoopState = if ($Script:Settings.InstallScoop) { 'ON' } else { 'OFF' }
        $modState   = if ($Script:Settings.InstallModules) { 'ON' } else { 'OFF' }
        $fontState  = if ($Script:Settings.InstallFont) { 'ON' } else { 'OFF' }
        $themeName  = $Script:Themes[$Script:Settings.SelectedTheme]
        $opts = @(
            "Toggle progress bar (currently: $progState)",
            "Toggle debug mode (currently: $debugState)",
            "Toggle Scoop install (currently: $scoopState)",
            "Toggle module install (currently: $modState)",
            "Toggle Nerd Font install (currently: $fontState)",
            "Select theme (currently: $themeName)",
            'Save settings now',
            'Return to main menu'
        )
        $sel = Read-MenuSelection -Title 'ISTAR PACK SETTINGS' -Options $opts -DefaultIndex 0
        switch ($sel) {
            0  { $Script:Settings.ShowProgress   = -not $Script:Settings.ShowProgress;   Export-Settings; Write-Ok 'Setting updated.'; Start-Sleep -Milliseconds 600 }
            1  { $Script:Settings.DebugMode      = -not $Script:Settings.DebugMode;      Export-Settings; Write-Ok 'Setting updated.'; Start-Sleep -Milliseconds 600 }
            2  { $Script:Settings.InstallScoop   = -not $Script:Settings.InstallScoop;   Export-Settings; Write-Ok 'Setting updated.'; Start-Sleep -Milliseconds 600 }
            3  { $Script:Settings.InstallModules = -not $Script:Settings.InstallModules; Export-Settings; Write-Ok 'Setting updated.'; Start-Sleep -Milliseconds 600 }
            4  { $Script:Settings.InstallFont    = -not $Script:Settings.InstallFont;    Export-Settings; Write-Ok 'Setting updated.'; Start-Sleep -Milliseconds 600 }
            5  { Invoke-SelectTheme }
            6  { Export-Settings; Write-Ok 'Settings saved.'; Start-Sleep -Milliseconds 600 }
            7  { return }
            -1 { return }
            default { Write-Warn 'Invalid option.'; Start-Sleep -Milliseconds 400 }
        }
    }
}

# ============================================================================
# 23. HELP / ABOUT
# ============================================================================
function Show-About {
    [CmdletBinding()] param()
    Write-Banner
    Write-BoxTop -Title 'ABOUT ISTAR PACK'
    Write-BoxLine ''
    Write-BoxLine 'Istar Pack is a one-shot PowerShell terminal setup.'
    Write-BoxLine 'It installs Scoop, Oh My Posh, Zoxide, FZF, 7-Zip,'
    Write-BoxLine 'Nerd Fonts and the recommended PS modules, then'
    Write-BoxLine 'writes a hardened profile tuned for PS 5.1 and PS 7.'
    Write-BoxLine ''
    Write-BoxSeparator
    Write-BoxSubtitle -Title 'WHAT IT FIXES'
    Write-BoxLine '- Resolves the UpArrow/ListView conflict'
    Write-BoxLine '- Adds Ctrl+Up/Ctrl+Down for history navigation'
    Write-BoxLine '- Robust extract() with 7z verification'
    Write-BoxLine '- MaximumHistoryCount + HistoryNoDuplicates'
    Write-BoxLine '- Conditional module loads (no errors if missing)'
    Write-BoxLine '- Profile backup before every overwrite'
    Write-BoxLine '- Auto-detects PS 5.1 vs PS 7 features'
    Write-BoxLine ''
    Write-BoxSeparator
    Write-BoxSubtitle -Title 'CREDITS'
    Write-BoxKeyValue -Key 'Project'   -Value $Script:AppName
    Write-BoxKeyValue -Key 'Version'   -Value $Script:AppVersion
    Write-BoxKeyValue -Key 'Inspired by' -Value 'TUI Template by Israleche'
    Write-BoxKeyValue -Key 'Oh My Posh'  -Value 'Jan De Dobbeleer'
    Write-BoxKeyValue -Key 'Scoop'       -Value 'Luke Sampson'
    Write-BoxKeyValue -Key 'Zoxide'      -Value "Ajeet D'Souza"
    Write-BoxLine ''
    Write-BoxBottom
    Write-Host ''
    Read-AnyKey 'Press any key to return to the menu...'
}

# ============================================================================
# 24. MAIN MENU
# ============================================================================
function Show-MainMenu {
    [CmdletBinding()] param()
    while ($true) {
        $themeName = $Script:Themes[$Script:Settings.SelectedTheme]
        $opts = @(
            "Full install (recommended) - theme: $themeName",
            'Install only Scoop + CLI tools',
            'Install only PowerShell modules',
            'Install only Nerd Font',
            'Select theme',
            'Browse theme catalog',
            'Back up current profile',
            'Verify installation',
            'Open settings',
            'About Istar Pack',
            'Exit'
        )
        $footer = if ($Script:Settings.DebugMode) { 'DEBUG MODE IS ACTIVE' } else { $null }
        $sel = Read-MenuSelection -Title 'MAIN MENU' -Options $opts -DefaultIndex 0 -Footer $footer
        try {
            switch ($sel) {
                0  { Invoke-FullInstall }
                1  {
                    Write-Banner
                    if (Install-ScoopIfNeeded) { Install-AllCliTools | Out-Null }
                    Read-AnyKey 'Press any key to return to the menu...'
                }
                2  {
                    Write-Banner
                    Install-AllPsModules | Out-Null
                    Read-AnyKey 'Press any key to return to the menu...'
                }
                3  {
                    Write-Banner
                    Install-NerdFontIfNeeded | Out-Null
                    Read-AnyKey 'Press any key to return to the menu...'
                }
                4  { Invoke-SelectTheme }
                5  { Show-ThemeBrowser }
                6  { Show-BackupMenu }
                7  { Show-Verification }
                8  { Show-SettingsMenu }
                9  { Show-About }
                10 {
                    Write-Host ''
                    Write-Ok 'Goodbye from Istar Pack!'
                    Start-Sleep -Milliseconds 500
                    exit 0
                }
                -1 { return }
                default { Write-Warn 'Invalid option.'; Start-Sleep -Milliseconds 500 }
            }
        } catch {
            Write-Host ''
            Write-Err ('Execution exception: ' + $_.Exception.Message)
            Read-AnyKey 'Press any key to continue...'
        }
    }
}

# ============================================================================
# 25. ENTRY POINT
# ============================================================================
function Start-App {
    [CmdletBinding()] param()

    if (-not (Test-PowerShellVersion)) {
        Write-Err 'PowerShell 5.1 or later is required to run Istar Pack.'
        Read-AnyKey 'Press any key to exit...'
        exit 1
    }

    # Grow the console window before rendering anything, so the tall screens
    # (Verification, Theme Catalog, About) fit without being cut off.
    Initialize-ConsoleSize

    Import-Settings
    if ($ShowProgress -ge 0) { $Script:Settings.ShowProgress = [bool]$ShowProgress }
    if ($EnableDebug  -ge 0) { $Script:Settings.DebugMode    = [bool]$EnableDebug  }

    # Test hook: when ISTAR_TEST_MODE is set, define functions but don't enter the menu loop.
    if ($env:ISTAR_TEST_MODE -eq '1') { return }

    if ($Silent) {
        Write-Host "Istar Pack: silent mode. Theme = $($Script:Themes[$Script:Settings.SelectedTheme])" -ForegroundColor Cyan
        Invoke-FullInstall -ThemeKey $Script:Settings.SelectedTheme | Out-Null
        return
    }

    Show-MainMenu
}

# ============================================================================
# SCRIPT ENTRY POINT (global try/catch)
# ============================================================================
try { Start-App }
catch {
    Write-Host ''
    Write-Err ("FATAL UNHANDLED ERROR: " + $_.Exception.Message)
    try { Write-Host $_.ScriptStackTrace -ForegroundColor DarkGray } catch {}
    Read-AnyKey 'Press any key to exit...'
    exit 1
}
