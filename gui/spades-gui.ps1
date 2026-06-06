# SPAdes for Windows - minimal graphical front-end for non-technical users.
# Pure PowerShell + WinForms (.NET Framework, present on every Windows 10/11) — no
# extra runtime. It just drives the bundled SPAdes (embedded Python + spades.py).
# Launched console-less via SPAdes-GUI.vbs. Run with -SelfTest to build the UI and
# exit (used by CI to verify the form constructs).
param([switch]$SelfTest)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# --- locate the bundled SPAdes (installed layout: <app>\gui, <app>\python, <app>\bin) ---
$app    = Split-Path $PSScriptRoot -Parent
$python = Join-Path $app 'python\python.exe'
$spades = Join-Path $app 'bin\spades.py'
if (-not (Test-Path $python)) { $python = 'python' }            # dev fallback: system Python
if (-not (Test-Path $spades)) { $spades = Join-Path $app 'bin\spades.py' }

# --- palette ---
$NAVY  = [System.Drawing.Color]::FromArgb(31,58,95)
$BLUE  = [System.Drawing.Color]::FromArgb(46,111,183)
$BG    = [System.Drawing.Color]::FromArgb(245,246,248)
$INK   = [System.Drawing.Color]::FromArgb(33,37,41)
$UIFONT = New-Object System.Drawing.Font('Segoe UI', 9.75)

# --- sensible defaults from the machine ---
$cpu = [Environment]::ProcessorCount
try { $ramGB = [math]::Round((Get-CimInstance Win32_ComputerSystem -ErrorAction Stop).TotalPhysicalMemory/1GB) } catch { $ramGB = 16 }
$defThreads = [math]::Min([math]::Max($cpu,1), 16)
$defMem     = [math]::Max(4, [math]::Floor($ramGB * 0.75))

# assembly-mode presets: display label -> spades extra flag(s)
$modes = [ordered]@{
    'Isolate - high-coverage, fast (recommended)' = '--isolate'
    'Standard - with read error correction'       = ''
    'Careful - small genomes, fewer mismatches'   = '--careful'
    'Metagenome (--meta)'                          = '--meta'
    'Plasmid (--plasmid)'                          = '--plasmid'
    'RNA-seq (--rna)'                              = '--rna'
}

# ---------------------------------------------------------------- form
$form = New-Object System.Windows.Forms.Form
$form.Text = 'SPAdes for Windows'
$form.Size = New-Object System.Drawing.Size(680, 620)
$form.MinimumSize = New-Object System.Drawing.Size(560, 520)
$form.StartPosition = 'CenterScreen'
$form.BackColor = $BG
$form.Font = $UIFONT
try { $form.Icon = [System.Drawing.SystemIcons]::Application } catch {}

# header strip
$header = New-Object System.Windows.Forms.Panel
$header.Size = New-Object System.Drawing.Size(680, 58)
$header.Location = New-Object System.Drawing.Point(0, 0)
$header.BackColor = $NAVY
$header.Anchor = 'Top,Left,Right'
$title = New-Object System.Windows.Forms.Label
$title.Text = 'SPAdes for Windows'
$title.ForeColor = [System.Drawing.Color]::White
$title.Font = New-Object System.Drawing.Font('Segoe UI', 15, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(16, 8); $title.AutoSize = $true
$subtitle = New-Object System.Windows.Forms.Label
$subtitle.Text = 'native de novo genome assembly - no setup required'
$subtitle.ForeColor = [System.Drawing.Color]::FromArgb(190,205,225)
$subtitle.Location = New-Object System.Drawing.Point(18, 36); $subtitle.AutoSize = $true
$header.Controls.AddRange(@($title, $subtitle))
$form.Controls.Add($header)

# helper: labelled row with a textbox (+ optional Browse button)
function New-Label($text, $x, $y) {
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $text; $l.Location = New-Object System.Drawing.Point($x, $y); $l.AutoSize = $true; $l.ForeColor = $INK
    return $l
}
function New-TextBox($x, $y, $w) {
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = New-Object System.Drawing.Point($x, $y); $t.Size = New-Object System.Drawing.Size($w, 24)
    $t.Anchor = 'Top,Left,Right'
    return $t
}
function New-Button($text, $x, $y, $w) {
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $text; $b.Location = New-Object System.Drawing.Point($x, $y); $b.Size = New-Object System.Drawing.Size($w, 25)
    $b.FlatStyle = 'Flat'; $b.BackColor = [System.Drawing.Color]::White
    return $b
}

$lblR1 = New-Label 'Forward reads (R1)' 16 76; $form.Controls.Add($lblR1)
$txtR1 = New-TextBox 16 98 530; $form.Controls.Add($txtR1)
$btnR1 = New-Button 'Browse...' 552 97 96; $btnR1.Anchor='Top,Right'; $form.Controls.Add($btnR1)

$lblR2 = New-Label 'Reverse reads (R2)  -  optional for single-end' 16 130; $form.Controls.Add($lblR2)
$txtR2 = New-TextBox 16 152 530; $form.Controls.Add($txtR2)
$btnR2 = New-Button 'Browse...' 552 151 96; $btnR2.Anchor='Top,Right'; $form.Controls.Add($btnR2)

$lblOut = New-Label 'Output folder' 16 184; $form.Controls.Add($lblOut)
$txtOut = New-TextBox 16 206 530; $form.Controls.Add($txtOut)
$btnOut = New-Button 'Browse...' 552 205 96; $btnOut.Anchor='Top,Right'; $form.Controls.Add($btnOut)

$lblMode = New-Label 'Assembly mode' 16 238; $form.Controls.Add($lblMode)
$cmbMode = New-Object System.Windows.Forms.ComboBox
$cmbMode.Location = New-Object System.Drawing.Point(16, 260); $cmbMode.Size = New-Object System.Drawing.Size(360, 24)
$cmbMode.DropDownStyle = 'DropDownList'
foreach ($k in $modes.Keys) { [void]$cmbMode.Items.Add($k) }
$cmbMode.SelectedIndex = 0
$form.Controls.Add($cmbMode)

$lblT = New-Label 'Threads' 396 238; $form.Controls.Add($lblT)
$numT = New-Object System.Windows.Forms.NumericUpDown
$numT.Location = New-Object System.Drawing.Point(396, 260); $numT.Size = New-Object System.Drawing.Size(70, 24)
$numT.Minimum = 1; $numT.Maximum = 256; $numT.Value = $defThreads; $form.Controls.Add($numT)

$lblM = New-Label 'Memory (GB)' 476 238; $form.Controls.Add($lblM)
$numM = New-Object System.Windows.Forms.NumericUpDown
$numM.Location = New-Object System.Drawing.Point(476, 260); $numM.Size = New-Object System.Drawing.Size(70, 24)
$numM.Minimum = 1; $numM.Maximum = 4096; $numM.Value = $defMem; $form.Controls.Add($numM)

# run / open buttons
$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = 'Run assembly'; $btnRun.Location = New-Object System.Drawing.Point(16, 300)
$btnRun.Size = New-Object System.Drawing.Size(150, 34); $btnRun.FlatStyle = 'Flat'
$btnRun.BackColor = $BLUE; $btnRun.ForeColor = [System.Drawing.Color]::White
$btnRun.Font = New-Object System.Drawing.Font('Segoe UI', 10, [System.Drawing.FontStyle]::Bold)
$form.Controls.Add($btnRun)

$btnOpen = New-Button 'Open output folder' 176 304 150; $btnOpen.Enabled = $false; $form.Controls.Add($btnOpen)

# progress + status
$prog = New-Object System.Windows.Forms.ProgressBar
$prog.Location = New-Object System.Drawing.Point(16, 344); $prog.Size = New-Object System.Drawing.Size(632, 8)
$prog.Style = 'Marquee'; $prog.MarqueeAnimationSpeed = 0; $prog.Anchor='Top,Left,Right'; $form.Controls.Add($prog)

$status = New-Label 'Ready.' 16 356; $status.Anchor='Top,Left'; $status.ForeColor = $NAVY; $form.Controls.Add($status)

# log
$log = New-Object System.Windows.Forms.TextBox
$log.Location = New-Object System.Drawing.Point(16, 380); $log.Size = New-Object System.Drawing.Size(632, 190)
$log.Multiline = $true; $log.ReadOnly = $true; $log.ScrollBars = 'Vertical'; $log.WordWrap = $false
$log.BackColor = [System.Drawing.Color]::FromArgb(30,30,30); $log.ForeColor = [System.Drawing.Color]::FromArgb(212,212,212)
$log.Font = New-Object System.Drawing.Font('Consolas', 9)
$log.Anchor = 'Top,Bottom,Left,Right'
$form.Controls.Add($log)

# ---------------------------------------------------------------- behaviour
$script:proc = $null
$script:logPath = $null
$script:logPos = 0
$script:outDir = $null

function Pick-File($box) {
    $d = New-Object System.Windows.Forms.OpenFileDialog
    $d.Filter = 'FASTQ reads (*.fastq;*.fq;*.fastq.gz;*.fq.gz)|*.fastq;*.fq;*.fastq.gz;*.fq.gz|All files (*.*)|*.*'
    if ($d.ShowDialog() -eq 'OK') { $box.Text = $d.FileName }
}
$btnR1.Add_Click({ Pick-File $txtR1 })
$btnR2.Add_Click({ Pick-File $txtR2 })
$btnOut.Add_Click({
    $d = New-Object System.Windows.Forms.FolderBrowserDialog
    if ($d.ShowDialog() -eq 'OK') { $txtOut.Text = $d.SelectedPath }
})
$btnOpen.Add_Click({ if ($script:outDir -and (Test-Path $script:outDir)) { Start-Process explorer.exe $script:outDir } })

function Read-NewLog {
    if (-not $script:logPath -or -not (Test-Path $script:logPath)) { return '' }
    try {
        $fs = [System.IO.File]::Open($script:logPath, 'Open', 'Read', 'ReadWrite')
        [void]$fs.Seek($script:logPos, 'Begin')
        $sr = New-Object System.IO.StreamReader($fs)
        $new = $sr.ReadToEnd(); $script:logPos = $fs.Position
        $sr.Close(); $fs.Close(); return $new
    } catch { return '' }
}

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 700
$timer.Add_Tick({
    $new = Read-NewLog
    if ($new.Length) { $log.AppendText($new) }
    if ($script:proc -and $script:proc.HasExited) {
        $timer.Stop()
        $log.AppendText((Read-NewLog))
        $prog.MarqueeAnimationSpeed = 0
        $btnRun.Enabled = $true
        if ($script:proc.ExitCode -eq 0) {
            $status.Text = "Done. Contigs: $(Join-Path $script:outDir 'contigs.fasta')"
            $status.ForeColor = [System.Drawing.Color]::FromArgb(20,120,60)
            $btnOpen.Enabled = $true
        } else {
            $status.Text = "SPAdes failed (exit $($script:proc.ExitCode)). See the log / spades.log."
            $status.ForeColor = [System.Drawing.Color]::FromArgb(170,30,30)
            $btnOpen.Enabled = (Test-Path $script:outDir)
        }
    }
})

$btnRun.Add_Click({
    $r1 = $txtR1.Text.Trim(); $r2 = $txtR2.Text.Trim(); $out = $txtOut.Text.Trim()
    if (-not $r1 -or -not (Test-Path $r1)) { [System.Windows.Forms.MessageBox]::Show('Please choose a valid forward-reads (R1) file.','SPAdes'); return }
    if ($r2 -and -not (Test-Path $r2)) { [System.Windows.Forms.MessageBox]::Show('The reverse-reads (R2) file does not exist.','SPAdes'); return }
    if (-not $out) { [System.Windows.Forms.MessageBox]::Show('Please choose an output folder.','SPAdes'); return }
    if (-not (Test-Path $spades)) { [System.Windows.Forms.MessageBox]::Show("Bundled SPAdes not found at:`n$spades",'SPAdes'); return }
    New-Item -ItemType Directory -Force -Path $out | Out-Null

    $argv = New-Object System.Collections.ArrayList
    [void]$argv.Add($spades)
    $flag = $modes[$cmbMode.SelectedItem]
    if ($flag) { foreach ($f in $flag.Split(' ')) { [void]$argv.Add($f) } }
    [void]$argv.Add('-1'); [void]$argv.Add($r1)
    if ($r2) { [void]$argv.Add('-2'); [void]$argv.Add($r2) } else { [void]$argv.Add('-s'); [void]$argv.Add($r1) }
    [void]$argv.Add('-o'); [void]$argv.Add($out)
    [void]$argv.Add('-t'); [void]$argv.Add([string]$numT.Value)
    [void]$argv.Add('-m'); [void]$argv.Add([string]$numM.Value)

    $script:outDir = $out
    $script:logPath = Join-Path $out 'gui_run.log'
    $errPath = Join-Path $out 'gui_run.err.log'
    Set-Content -Path $script:logPath -Value '' -Encoding utf8
    $script:logPos = 0
    $log.Clear()
    $log.AppendText("> " + $python + " " + ($argv -join ' ') + "`r`n`r`n")
    $btnRun.Enabled = $false; $btnOpen.Enabled = $false
    $prog.MarqueeAnimationSpeed = 30
    $status.Text = 'Running... (error correction + assembly can take several minutes)'
    $status.ForeColor = $NAVY
    try {
        $script:proc = Start-Process -FilePath $python -ArgumentList $argv.ToArray() `
            -NoNewWindow -PassThru -RedirectStandardOutput $script:logPath -RedirectStandardError $errPath
        $timer.Start()
    } catch {
        $prog.MarqueeAnimationSpeed = 0; $btnRun.Enabled = $true
        $status.Text = "Could not start SPAdes: $($_.Exception.Message)"
        $status.ForeColor = [System.Drawing.Color]::FromArgb(170,30,30)
    }
})

if ($SelfTest) { Write-Output 'SELFTEST OK'; return }
[void]$form.ShowDialog()
