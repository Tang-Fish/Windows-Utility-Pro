Add-Type -AssemblyName PresentationFramework, PresentationCore, System.Windows.Forms, Microsoft.VisualBasic

$PresetColors = @('

$StartFullScreen = {
    param($StartColor, $AllMonitors)
    $script:ColorIndex = [Math]::Max(0, [Array]::IndexOf($PresetColors, $StartColor))
    $script:Brightness = 1.0

    $Targets = if ($AllMonitors) { [Windows.Forms.Screen]::AllScreens } else { @([Windows.Forms.Screen]::PrimaryScreen) }
    $Windows = @()

    $UpdateScreenColor = {
        param($ColorVal, $BrightVal)
        $c = if ($ColorVal -is [Windows.Media.Color]) { $ColorVal } else { [Windows.Media.ColorConverter]::ConvertFromString($ColorVal) }
        $brush = New-Object Windows.Media.SolidColorBrush([Windows.Media.Color]::FromRgb(
            [byte]($c.R * $BrightVal),
            [byte]($c.G * $BrightVal),
            [byte]($c.B * $BrightVal)
        ))
        $Windows | ForEach-Object { $_.Background = $brush }
    }

    foreach ($Screen in $Targets) {
        $fsWin = New-Object Windows.Window -Property @{
            WindowStyle           = 'None'
            ResizeMode            = 'NoResize'
            Topmost               = $true
            Cursor                = 'None'
            WindowStartupLocation = 'Manual'
            Left                  = $Screen.Bounds.Left
            Top                   = $Screen.Bounds.Top
            Width                 = 100
            Height                = 100
        }

        $fsWin.Add_Loaded({ $this.WindowState = 'Maximized' })
        $fsWin.Add_MouseDown({ $Windows | ForEach-Object { $_.Close() } })
        $fsWin.Add_KeyDown({
            param($sender, $e)
            if ($e.Key -in 'Right', 'Space') {
                $script:ColorIndex = ($script:ColorIndex + 1) % $PresetColors.Count
                & $UpdateScreenColor $PresetColors[$script:ColorIndex] $script:Brightness
            }
            elseif ($e.Key -eq 'Left') {
                $script:ColorIndex = ($script:ColorIndex - 1 + $PresetColors.Count) % $PresetColors.Count
                & $UpdateScreenColor $PresetColors[$script:ColorIndex] $script:Brightness
            }
            elseif ($e.Key -eq 'Up') {
                $script:Brightness = [Math]::Min(1.0, $script:Brightness + 0.1)
                & $UpdateScreenColor $PresetColors[$script:ColorIndex] $script:Brightness
            }
            elseif ($e.Key -eq 'Down') {
                $script:Brightness = [Math]::Max(0.1, $script:Brightness - 0.1)
                & $UpdateScreenColor $PresetColors[$script:ColorIndex] $script:Brightness
            }
            else {
                $Windows | ForEach-Object { $_.Close() }
            }
        })
        $Windows += $fsWin
    }

    & $UpdateScreenColor $StartColor 1.0
    if ($Windows.Count -gt 1) {
        0..($Windows.Count - 2) | ForEach-Object { $Windows[$_].Show() }
    }
    [void]$Windows[-1].ShowDialog()
}

$RunWingetTasks = {
    param([array]$Tasks, [scriptblock]$OnComplete = $null)

    [xml]$ProgXaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WinUtil Progress" Height="215" Width="460"
        WindowStyle="None" AllowsTransparency="True" Background="Transparent"
        WindowStartupLocation="CenterOwner" ResizeMode="NoResize" Topmost="True">
    <Window.Resources>
        <Style TargetType="ProgressBar">
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="ProgressBar">
                        <Grid Height="12">
                            <Border Name="PART_Track" Background="
                            <Border Name="PART_Indicator" HorizontalAlignment="Left" Background="{TemplateBinding Foreground}" CornerRadius="6"/>
                        </Grid>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
    </Window.Resources>
    <Border Background="
        <Grid>
            <Grid.RowDefinitions>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="Auto"/>
                <RowDefinition Height="*"/>
            </Grid.RowDefinitions>

            <!-- Top Header -->
            <DockPanel Grid.Row="0" Margin="0,0,0,12">
                <TextBlock Text="WINUTIL PRO" FontSize="11" FontWeight="Bold" Foreground="
                <Border DockPanel.Dock="Right" Background="
                    <TextBlock Name="TxtStep" Text="Step 1 of 1" FontSize="11" Foreground="
                </Border>
            </DockPanel>

            <!-- Task Title & Big Percentage -->
            <DockPanel Grid.Row="1" Margin="0,0,0,8">
                <TextBlock Name="TxtPercent" DockPanel.Dock="Right" Text="0%" FontSize="22" FontWeight="Bold" Foreground="
                <TextBlock Name="TxtTitle" Text="Preparing Winget..." FontSize="15" FontWeight="SemiBold" Foreground="
            </DockPanel>

            <!-- Smooth Progress Bar -->
            <ProgressBar Name="ProgBar" Grid.Row="2" Minimum="0" Maximum="100" Value="0" Foreground="

            <!-- Live Winget Detail Line -->
            <Border Grid.Row="3" Background="
                <TextBlock Name="TxtDetail" Text="Initializing package manager..." FontFamily="Consolas" FontSize="11" Foreground="
            </Border>

            <!-- Footer / Cancel -->
            <DockPanel Grid.Row="4" Margin="0,12,0,0">
                <TextBlock Name="TxtFooter" Text="Window will close automatically when finished" FontSize="11" Foreground="
                <Button Name="BtnCancel" DockPanel.Dock="Right" Content="Cancel" Background="
            </DockPanel>
        </Grid>
    </Border>
</Window>
"@

    $pWin = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $ProgXaml))
    $pWin.Owner = $Win
    $pWin.Add_MouseLeftButtonDown({ $pWin.DragMove() })

    $txtStep    = $pWin.FindName("TxtStep")
    $txtTitle   = $pWin.FindName("TxtTitle")
    $txtPercent = $pWin.FindName("TxtPercent")
    $progBar    = $pWin.FindName("ProgBar")
    $txtDetail  = $pWin.FindName("TxtDetail")
    $txtFooter  = $pWin.FindName("TxtFooter")
    $btnCancel  = $pWin.FindName("BtnCancel")

    $Sync = [Hashtable]::Synchronized(@{
        StepText   = "Step 1 of $($Tasks.Count)"
        Title      = "Checking Winget..."
        Detail     = "Verifying Microsoft App Installer..."
        Pct        = 2
        Done       = $false
        Cancelled  = $false
        ActiveProc = $null
    })

    $btnCancel.Add_Click({
        $Sync.Cancelled = $true
        $txtTitle.Text  = "Cancelling..."
        $btnCancel.IsEnabled = $false
        if ($Sync.ActiveProc -and -not $Sync.ActiveProc.HasExited) {
            try { $Sync.ActiveProc.Kill() } catch {}
        }
    })

    $ps = [PowerShell]::Create()
    [void]$ps.AddScript({
        param($Sync, $Tasks)

        if (-not (Get-AppxPackage Microsoft.DesktopAppInstaller) -or ([version](Get-AppxPackage Microsoft.DesktopAppInstaller).Version -lt [version]"1.17.0.0")) {
            $Sync.Title  = "Repairing Winget..."
            $Sync.Detail = "Downloading Microsoft App Installer..."
            try { Add-AppxPackage -RegisterByFamilyName -MainPackage Microsoft.DesktopAppInstaller_8wekyb3d8bbwe -ErrorAction Stop } catch {}
            if (-not (Get-AppxPackage Microsoft.DesktopAppInstaller) -or ([version](Get-AppxPackage Microsoft.DesktopAppInstaller).Version -lt [version]"1.17.0.0")) {
                $p = "$env:TEMP\wg.msixbundle"
                Invoke-WebRequest -Uri https://aka.ms/getwinget -OutFile $p -UseBasicParsing
                try {
                    Add-AppxPackage $p -ErrorAction Stop
                } catch {
                    $v = "$env:TEMP\vc.appx"; $u = "$env:TEMP\ui.appx"
                    Invoke-WebRequest -Uri https://aka.ms/Microsoft.VCLibs.x64.14.00.Desktop.appx -OutFile $v -UseBasicParsing
                    Invoke-WebRequest -Uri https://github.com/microsoft/microsoft-ui-xaml/releases/download/v2.8.6/Microsoft.UI.Xaml.2.8.x64.appx -OutFile $u -UseBasicParsing
                    Add-AppxPackage $v; Add-AppxPackage $u; Add-AppxPackage $p
                }
            }
        }

        $wge = Join-Path (Get-AppxPackage Microsoft.DesktopAppInstaller | Select-Object -Last 1).InstallLocation "winget.exe"
        $total = $Tasks.Count

        $RunSingleWinget = {
            param($ArgString, $TaskIndex)
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $wge
            $psi.Arguments = $ArgString
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError  = $true
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow  = $true

            $proc = [System.Diagnostics.Process]::Start($psi)
            $Sync.ActiveProc = $proc

            $reader = $proc.StandardOutput
            $buf = New-Object char[] 256
            $lineBuf = ""
            $subPct = 5

            while (-not $reader.EndOfStream) {
                if ($Sync.Cancelled) { break }
                $readCount = $reader.Read($buf, 0, $buf.Length)
                if ($readCount -le 0) { break }

                for ($c = 0; $c -lt $readCount; $c++) {
                    $ch = $buf[$c]
                    if ($ch -eq "`r" -or $ch -eq "`n") {
                        $clean = ($lineBuf -replace '\x1b\[[0-9;?]*[a-zA-Z]', '').Trim()
                        if ($clean -and $clean -notmatch '^[\-\|\\\/]+$' -and $clean -notmatch '^[█░▒▓\s]+$') {
                            $Sync.Detail = $clean
                            if ($clean -match '(\d{1,3})\s*%') {
                                $subPct = [Math]::Min(98, [int]$matches[1])
                            }
                            elseif ($clean -match '([\d\.]+)\s*(KB|MB|GB)\s*/\s*([\d\.]+)\s*(KB|MB|GB)') {
                                $uMap = @{ KB = 1; MB = 1024; GB = 1048576 }
                                $cur = [double]$matches[1] * $uMap[$matches[2]]
                                $tot = [double]$matches[3] * $uMap[$matches[4]]
                                if ($tot -gt 0) { $subPct = [Math]::Min(95, [int](($cur / $tot) * 100)) }
                            }
                            elseif ($clean -match 'Starting package|Successfully verified|Installing|Uninstalling') {
                                $subPct = [Math]::Max($subPct, 80)
                            }
                            elseif ($subPct -lt 40) {
                                $subPct += 3
                            }
                            $Sync.Pct = [Math]::Min(99, [int](($TaskIndex * 100 + $subPct) / $total))
                        }
                        $lineBuf = ""
                    } else {
                        $lineBuf += $ch
                    }
                }
            }

            $proc.WaitForExit()
            return $proc.ExitCode
        }

        for ($i = 0; $i -lt $total; $i++) {
            if ($Sync.Cancelled) { break }
            $t = $Tasks[$i]
            $Sync.StepText = "Step $($i + 1) of $total"
            $Sync.Title    = $t.Label
            $Sync.Detail   = "Starting..."
            $Sync.Pct      = [int](($i * 100) / $total)

            $exitCode = & $RunSingleWinget $t.Args $i
            if (-not $Sync.Cancelled -and $exitCode -ne 0 -and $t.FallbackArgs) {
                $Sync.Detail = "Retrying match..."
                $null = & $RunSingleWinget $t.FallbackArgs $i
            }

            if (-not $Sync.Cancelled) {
                $Sync.Pct = [int]((($i + 1) * 100) / $total)
            }
        }

        $Sync.Done = $true
    }).AddArgument($Sync).AddArgument($Tasks)

    $asyncHandle = $ps.BeginInvoke()

    $uiTimer = New-Object Windows.Threading.DispatcherTimer -Property @{ Interval = [TimeSpan]::FromMilliseconds(80) }
    $closing = $false

    $uiTimer.Add_Tick({
        if ($closing) { return }
        $txtStep.Text    = $Sync.StepText
        $txtTitle.Text   = $Sync.Title
        $txtDetail.Text  = $Sync.Detail
        $progBar.Value   = $Sync.Pct
        $txtPercent.Text = "$($Sync.Pct)%"
        & $SetStatus "$($Sync.Title) ($($Sync.Pct)%)"

        if ($Sync.Done) {
            $closing = $true
            $uiTimer.Stop()
            $ps.EndInvoke($asyncHandle)
            $ps.Dispose()

            if ($Sync.Cancelled) {
                & $SetStatus "Operation cancelled."
                $pWin.Close()
                return
            }

            $progBar.Value         = 100
            $txtPercent.Text       = "100%"
            $txtPercent.Foreground = "
            $progBar.Foreground    = "
            $txtTitle.Text         = "Completed!"
            $txtDetail.Text        = "All tasks finished successfully."
            $txtFooter.Text        = "Closing now..."
            $btnCancel.Visibility  = 'Collapsed'
            & $SetStatus "Finished! (100%)"

            if ($OnComplete) { & $OnComplete }

            $closeTimer = New-Object Windows.Threading.DispatcherTimer -Property @{ Interval = [TimeSpan]::FromSeconds(1.2) }
            $closeTimer.Add_Tick({
                $closeTimer.Stop()
                $pWin.Close()
            })
            $closeTimer.Start()
        }
    })

    $uiTimer.Start()
    [void]$pWin.ShowDialog()
}

[xml]$Xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="WinUtil Pro" Height="520" Width="830"
        Background="
    <Window.Resources>
        <Style TargetType="RadioButton">
            <Setter Property="Foreground" Value="
            <Setter Property="FontSize" Value="13"/>
            <Setter Property="FontWeight" Value="SemiBold"/>
            <Setter Property="Cursor" Value="Hand"/>
            <Setter Property="Template">
                <Setter.Value>
                    <ControlTemplate TargetType="RadioButton">
                        <Border x:Name="b" Background="Transparent" BorderBrush="Transparent" BorderThickness="3,0,0,0" Padding="15,10">
                            <ContentPresenter/>
                        </Border>
                        <ControlTemplate.Triggers>
                            <Trigger Property="IsMouseOver" Value="True">
                                <Setter TargetName="b" Property="Background" Value="
                                <Setter Property="Foreground" Value="
                            </Trigger>
                            <Trigger Property="IsChecked" Value="True">
                                <Setter TargetName="b" Property="Background" Value="
                                <Setter TargetName="b" Property="BorderBrush" Value="
                                <Setter Property="Foreground" Value="
                            </Trigger>
                        </ControlTemplate.Triggers>
                    </ControlTemplate>
                </Setter.Value>
            </Setter>
        </Style>
        <Style TargetType="Button">
            <Setter Property="Background" Value="
            <Setter Property="Foreground" Value="
            <Setter Property="BorderBrush" Value="
            <Setter Property="Padding" Value="10,6"/>
            <Setter Property="Margin" Value="3"/>
            <Setter Property="Cursor" Value="Hand"/>
        </Style>
    </Window.Resources>

    <Grid>
        <Grid.ColumnDefinitions>
            <ColumnDefinition Width="175"/>
            <ColumnDefinition Width="*"/>
        </Grid.ColumnDefinitions>
        <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="26"/>
        </Grid.RowDefinitions>

        <!-- Sidebar -->
        <Border Background="
            <StackPanel Name="Nav">
                <TextBlock Text="WINUTIL PRO" FontSize="16" FontWeight="Bold" Foreground="
                <RadioButton Tag="V0" Content="Performance" IsChecked="True"/>
                <RadioButton Tag="V1" Content="Install Apps"/>
                <RadioButton Tag="V2" Content="Uninstall Apps"/>
                <RadioButton Tag="V3" Content="System &amp; Tools"/>
                <RadioButton Tag="V4" Content="Display Light"/>
            </StackPanel>
        </Border>

        <!-- Content Area -->
        <Grid Grid.Column="1" Margin="16,12">
            <!-- Tab 0: Performance -->
            <StackPanel Name="V0">
                <TextBlock Text="Performance &amp; Optimization" FontSize="17" FontWeight="Bold" Margin="0,0,0,10"/>
                <UniformGrid Name="Meters" Columns="3" Margin="0,0,0,10"/>
                <TextBlock Text="Power Plan &amp; Tweaks" Foreground="
                <UniformGrid Name="TwkGrid" Columns="3"/>
                <TextBlock Name="TxtUp" Foreground="
            </StackPanel>

            <!-- Tab 1: Install Apps -->
            <Grid Name="V1" Visibility="Collapsed">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <TextBlock Text="Install Apps (Winget)" FontSize="17" FontWeight="Bold" Margin="0,0,0,8"/>
                <UniformGrid Name="AppGrid" Grid.Row="1" Columns="3"/>
                <DockPanel Grid.Row="2" Margin="0,6">
                    <Button Name="BtnCid" Content="Install ID" DockPanel.Dock="Right"/>
                    <TextBox Name="TxtCid" Background="
                </DockPanel>
                <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right">
                    <Button Name="BtnFix" Content="Repair Winget"/>
                    <Button Name="BtnClr" Content="Clear"/>
                    <Button Name="BtnUpg" Content="Upgrade All"/>
                    <Button Name="BtnInst" Content="Install Selected" Background="
                </StackPanel>
            </Grid>

            <!-- Tab 2: Uninstall Apps -->
            <Grid Name="V2" Visibility="Collapsed">
                <Grid.RowDefinitions>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="Auto"/>
                    <RowDefinition Height="*"/>
                    <RowDefinition Height="Auto"/>
                </Grid.RowDefinitions>
                <TextBlock Text="Uninstall Apps" FontSize="17" FontWeight="Bold" Margin="0,0,0,8"/>
                <DockPanel Grid.Row="1" Margin="0,0,0,6">
                    <Button Name="BtnRef" Content="Refresh" DockPanel.Dock="Right"/>
                    <TextBox Name="TxtSrc" Background="
                </DockPanel>
                <Border Grid.Row="2" Background="
                    <ScrollViewer><StackPanel Name="UList"/></ScrollViewer>
                </Border>
                <DockPanel Grid.Row="3" Margin="0,6,0,0">
                    <TextBlock Name="TxtCnt" Foreground="
                    <StackPanel Orientation="Horizontal" HorizontalAlignment="Right">
                        <Button Name="BtnUClr" Content="Clear"/>
                        <Button Name="BtnUn" Content="Uninstall Selected" Background="
                    </StackPanel>
                </DockPanel>
            </Grid>

            <!-- Tab 3: System & Tools -->
            <StackPanel Name="V3" Visibility="Collapsed">
                <TextBlock Text="System Specs &amp; Admin Tools" FontSize="17" FontWeight="Bold" Margin="0,0,0,10"/>
                <Border Background="
                    <TextBlock Name="TxtSys" FontFamily="Consolas" Foreground="
                </Border>
                <UniformGrid Name="SysGrid" Columns="3"/>
            </StackPanel>

            <!-- Tab 4: Display Light -->
            <StackPanel Name="V4" Visibility="Collapsed">
                <TextBlock Text="Display Studio Light" FontSize="17" FontWeight="Bold" Margin="0,0,0,8"/>
                <Border Name="Prev" Height="56" Background="
                    <TextBlock Text="Up/Down: Dim | Left/Right: Cycle | Click/Esc: Exit" Background="
                </Border>
                <DockPanel Margin="0,0,0,4">
                    <TextBlock Text="Brightness " Width="85"/>
                    <TextBlock Name="TxtBr" Text="100%" DockPanel.Dock="Right" Width="45" Foreground="
                    <Slider Name="SldBr" Minimum="10" Maximum="100" Value="100"/>
                </DockPanel>
                <DockPanel Margin="0,0,0,10">
                    <TextBlock Text="Color Temp " Width="85"/>
                    <TextBlock Name="TxtTmp" Text="Neutral" DockPanel.Dock="Right" Width="45" Foreground="
                    <Slider Name="SldTmp" Minimum="0" Maximum="100" Value="50"/>
                </DockPanel>
                <UniformGrid Name="ColGrid" Columns="4" Rows="2" Height="105"/>
                <DockPanel Margin="0,10,0,0">
                    <CheckBox Name="all" Content="All Monitors" Foreground="
                    <Button Name="go" Content="LAUNCH STUDIO LIGHT" DockPanel.Dock="Right" Background="
                </DockPanel>
            </StackPanel>
        </Grid>

        <!-- Bottom Status Bar -->
        <Border Grid.Row="1" Grid.ColumnSpan="2" Background="
            <TextBlock Name="St" Text="Ready." FontSize="11" Foreground="
        </Border>
    </Grid>
</Window>
"@

$Win = [Windows.Markup.XamlReader]::Load((New-Object Xml.XmlNodeReader $Xaml))
$SetStatus = { param($Msg) $Win.FindName("St").Text = $Msg }

$Win.FindName("Nav").Children | Where-Object { $_ -is [Windows.Controls.RadioButton] } | ForEach-Object {
    $_.Add_Checked({
        param($sender, $e)
        0..4 | ForEach-Object { $Win.FindName("V$_").Visibility = 'Collapsed' }
        $Win.FindName($sender.Tag).Visibility = 'Visible'
    })
}

$AddMeter = {
    param($Label, $Color)
    $border = New-Object Windows.Controls.Border -Property @{ Background = '
    $stack  = New-Object Windows.Controls.StackPanel
    $lbl    = New-Object Windows.Controls.TextBlock -Property @{ Text = $Label; FontSize = 11; Foreground = '
    $val    = New-Object Windows.Controls.TextBlock -Property @{ Text = '--'; FontSize = 18; FontWeight = 'Bold'; Foreground = $Color; Margin = '0,2,0,5' }
    $bar    = New-Object Windows.Controls.ProgressBar -Property @{ Height = 5; Maximum = 100; Foreground = $Color; Background = '
    @($lbl, $val, $bar) | ForEach-Object { [void]$stack.Children.Add($_) }
    $border.Child = $stack
    [void]$Win.FindName("Meters").Children.Add($border)
    @($val, $bar)
}

$MeterCpu  = & $AddMeter "CPU LOAD" "
$MeterRam  = & $AddMeter "MEMORY"   "
$MeterDisk = & $AddMeter "DRIVE C:" "

try { $CpuCounter = New-Object Diagnostics.PerformanceCounter("Processor", "% Processor Time", "_Total"); [void]$CpuCounter.NextValue() } catch { $CpuCounter = $null }
$CompInfo = New-Object Microsoft.VisualBasic.Devices.ComputerInfo

$PerfTimer = New-Object Windows.Threading.DispatcherTimer -Property @{ Interval = [TimeSpan]::FromSeconds(1.5) }
$UpdatePerf = {
    $cpu = if ($CpuCounter) { [Math]::Round($CpuCounter.NextValue()) } else { (Get-CimInstance Win32_Processor).LoadPercentage }
    $MeterCpu[0].Text  = "$cpu%"
    $MeterCpu[1].Value = $cpu

    $totRam = [Math]::Round($CompInfo.TotalPhysicalMemory / 1GB, 1)
    $useRam = [Math]::Round(($CompInfo.TotalPhysicalMemory - $CompInfo.AvailablePhysicalMemory) / 1GB, 1)
    $MeterRam[0].Text  = "$useRam / $totRam GB"
    $MeterRam[1].Value = [Math]::Round(($useRam / $totRam) * 100)

    $drv = New-Object IO.DriveInfo("C")
    $freeD = [Math]::Round($drv.AvailableFreeSpace / 1GB, 0)
    $totD  = [Math]::Round($drv.TotalSize / 1GB, 0)
    $MeterDisk[0].Text  = "$freeD GB Free"
    $MeterDisk[1].Value = [Math]::Round((($totD - $freeD) / $totD) * 100)

    $up = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
    $Win.FindName("TxtUp").Text = "System Uptime: $($up.Days)d $($up.Hours)h $($up.Minutes)m"
}
$PerfTimer.Add_Tick($UpdatePerf)
& $UpdatePerf
$PerfTimer.Start()
$Win.Add_Closed({ $PerfTimer.Stop() })

$Tweaks = @(
    @("Balanced",         { powercfg /setactive 381b4222-f694-41f0-9685-ff5bb260df2e; & $SetStatus "Power: Balanced" }),
    @("High Perf",        { powercfg /setactive 8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c; & $SetStatus "Power: High Performance" }),
    @("Ultimate Perf",    { powercfg /duplicatescheme e9a42b02-d5df-448d-aa00-03f14749eb61 | Out-Null; powercfg /setactive e9a42b02-d5df-448d-aa00-03f14749eb61; & $SetStatus "Power: Ultimate" }),
    @("Clean Temp",       { Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue; & $SetStatus "Temp folder cleaned." }),
    @("Flush DNS",        { ipconfig /flushdns | Out-Null; & $SetStatus "DNS cache flushed." }),
    @("Dark Mode",        { $p = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Set-ItemProperty $p AppsUseLightTheme 0; Set-ItemProperty $p SystemUsesLightTheme 0; & $SetStatus "Dark mode enabled." }),
    @("Light Mode",       { $p = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'; Set-ItemProperty $p AppsUseLightTheme 1; Set-ItemProperty $p SystemUsesLightTheme 1; & $SetStatus "Light mode enabled." }),
    @("Show Extensions",  { Set-ItemProperty 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' HideFileExt 0; & $SetStatus "File extensions shown." }),
    @("Restart Explorer", { Stop-Process -Name explorer -Force; & $SetStatus "Explorer restarted." })
)
foreach ($t in $Tweaks) {
    $btn = New-Object Windows.Controls.Button -Property @{ Content = $t[0] }
    $btn.Add_Click($t[1])
    [void]$Win.FindName("TwkGrid").Children.Add($btn)
}

$AppCatalog = @(
    @("Browsers & Social", @(
        "Firefox|Mozilla.Firefox",
        "Brave|Brave.Brave",
        "Chrome|Google.Chrome",
        "Discord|Discord.Discord",
        "Spotify|Spotify.Spotify",
        "Telegram|Telegram.TelegramDesktop"
    )),
    @("Utilities", @(
        "7-Zip|7zip.7zip",
        "PowerToys|Microsoft.PowerToys",
        "Everything|voidtools.Everything",
        "ShareX|ShareX.ShareX",
        "Notepad++|Notepad++.Notepad++",
        "WizTree|AntibodySoftware.WizTree"
    )),
    @("Media & Dev", @(
        "VLC|VideoLAN.VLC",
        "OBS Studio|OBSProject.OBSStudio",
        "VS Code|Microsoft.VisualStudioCode",
        "Git|Git.Git",
        "Python 3.12|Python.Python.3.12",
        "Steam|Valve.Steam"
    ))
)

$AppCheckboxes = @()
foreach ($cat in $AppCatalog) {
    $sp = New-Object Windows.Controls.StackPanel -Property @{ Margin = '4' }
    [void]$sp.Children.Add((New-Object Windows.Controls.TextBlock -Property @{ Text = $cat[0]; Foreground = '
    foreach ($item in $cat[1]) {
        $parts = $item -split '\|'
        $cb = New-Object Windows.Controls.CheckBox -Property @{ Content = $parts[0]; Tag = $parts[1]; Foreground = '
        [void]$sp.Children.Add($cb)
        $AppCheckboxes += $cb
    }
    [void]$Win.FindName("AppGrid").Children.Add($sp)
}

$Win.FindName("BtnClr").Add_Click({ $AppCheckboxes | ForEach-Object { $_.IsChecked = $false } })

$Win.FindName("BtnFix").Add_Click({
    & $RunWingetTasks @(
        @{ Label = "Verifying Winget"; Args = "--version" }
    )
})

$Win.FindName("BtnUpg").Add_Click({
    & $RunWingetTasks @(
        @{ Label = "Upgrading All Packages"; Args = "upgrade --all --accept-source-agreements --accept-package-agreements" }
    )
})

$Win.FindName("BtnInst").Add_Click({
    $selected = @($AppCheckboxes | Where-Object { $_.IsChecked })
    if (-not $selected) { & $SetStatus "Select at least one app first."; return }
    $taskList = @($selected | ForEach-Object {
        @{
            Label = "Installing $($_.Content)"
            Args  = "install --id $($_.Tag) -e --accept-source-agreements --accept-package-agreements"
        }
    })
    & $RunWingetTasks $taskList
})

$Win.FindName("BtnCid").Add_Click({
    $id = $Win.FindName("TxtCid").Text.Trim()
    if (-not $id) { & $SetStatus "Enter a Winget ID first."; return }
    & $RunWingetTasks @(
        @{
            Label = "Installing $id"
            Args  = "install --id `"$id`" -e --accept-source-agreements --accept-package-agreements"
        }
    )
})

$UninstList  = $Win.FindName("UList")
$SearchBox   = $Win.FindName("TxtSrc")
$CountLabel  = $Win.FindName("TxtCnt")

$LoadInstalledApps = {
    $SearchBox.Text = ''
    $UninstList.Children.Clear()
    $regPaths = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $apps = Get-ItemProperty $regPaths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName -and -not $_.SystemComponent -and -not $_.ParentKeyName -and $_.DisplayName -notmatch '^(KB\d+|Update for|Security Update|Hotfix)' } |
        Sort-Object DisplayName -Unique

    foreach ($app in $apps) {
        [void]$UninstList.Children.Add((New-Object Windows.Controls.CheckBox -Property @{
            Content    = $app.DisplayName
            Tag        = $app.DisplayName
            Foreground = '
            Margin     = '0,3'
        }))
    }
    $CountLabel.Text = "$($apps.Count) apps detected"
}

$SearchBox.Add_TextChanged({
    $q = $SearchBox.Text
    foreach ($cb in $UninstList.Children) {
        $cb.Visibility = if (-not $q -or $cb.Content -like "*$q*") { 'Visible' } else { 'Collapsed' }
    }
})

$Win.FindName("BtnRef").Add_Click({ & $LoadInstalledApps; & $SetStatus "App list refreshed." })
$Win.FindName("BtnUClr").Add_Click({ $UninstList.Children | ForEach-Object { $_.IsChecked = $false } })
$Win.FindName("BtnUn").Add_Click({
    $selected = @($UninstList.Children | Where-Object { $_.IsChecked } | ForEach-Object { $_.Tag })
    if (-not $selected) { & $SetStatus "Select an app to uninstall first."; return }
    if ([Windows.MessageBox]::Show("Uninstall $($selected.Count) selected app(s)?", "Confirm Uninstall", "YesNo", "Warning") -ne "Yes") { return }

    $taskList = @($selected | ForEach-Object {
        $safeName = $_ -replace '"', '\"'
        @{
            Label        = "Uninstalling $_"
            Args         = "uninstall --name `"$safeName`" -e --accept-source-agreements"
            FallbackArgs = "uninstall --name `"$safeName`" --accept-source-agreements"
        }
    })

    & $RunWingetTasks $taskList $LoadInstalledApps
})
& $LoadInstalledApps

$os  = Get-CimInstance Win32_OperatingSystem
$cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
$gpu = Get-CimInstance Win32_VideoController | Select-Object -First 1
$ip  = (Get-NetIPAddress -AddressFamily IPv4 | Where-Object { $_.InterfaceAlias -notmatch 'Loopback' -and $_.IPAddress -notlike '169.254.*' } | Select-Object -First 1).IPAddress

$Win.FindName("TxtSys").Text = "OS      : $($os.Caption) (Build $($os.BuildNumber))`nCPU     : $($cpu.Name.Trim()) ($($cpu.NumberOfCores)C/$($cpu.NumberOfLogicalProcessors)T)`nGPU     : $($gpu.Name)`nRAM     : $([Math]::Round($CompInfo.TotalPhysicalMemory / 1GB, 1)) GB`nHost/IP : $env:COMPUTERNAME | $ip"

$AdminTools = @(
    @("Task Manager",     "taskmgr"),
    @("Device Manager",   "devmgmt.msc"),
    @("Disk Cleanup",     "cleanmgr"),
    @("Resource Monitor", "resmon"),
    @("Network Adapters", "ncpa.cpl"),
    @("System Info",      "msinfo32")
)
foreach ($tool in $AdminTools) {
    $cmd = $tool[1]
    $btn = New-Object Windows.Controls.Button -Property @{ Content = $tool[0] }
    $btn.Add_Click({ Start-Process $cmd }.GetNewClosure())
    [void]$Win.FindName("SysGrid").Children.Add($btn)
}

$script:CustomLightColor = [Windows.Media.Colors]::White
$UpdateLightPreview = {
    $b = $Win.FindName("SldBr").Value / 100.0
    $t = $Win.FindName("SldTmp").Value
    if ($t -lt 50) {
        $r = 255; $g = 195 + (60 * ($t / 50.0)); $bl = 120 + (135 * ($t / 50.0))
        $Win.FindName("TxtTmp").Text = "Warm"
    } elseif ($t -gt 50) {
        $r = 255 - (55 * (($t - 50) / 50.0)); $g = 255 - (20 * (($t - 50) / 50.0)); $bl = 255
        $Win.FindName("TxtTmp").Text = "Cool"
    } else {
        $r = 255; $g = 255; $bl = 255
        $Win.FindName("TxtTmp").Text = "Neutral"
    }
    $script:CustomLightColor = [Windows.Media.Color]::FromRgb([byte]($r * $b), [byte]($g * $b), [byte]($bl * $b))
    $Win.FindName("Prev").Background = New-Object Windows.Media.SolidColorBrush($script:CustomLightColor)
    $Win.FindName("TxtBr").Text = "$([Math]::Round($Win.FindName("SldBr").Value))%"
}
$Win.FindName("SldBr").Add_ValueChanged($UpdateLightPreview)
$Win.FindName("SldTmp").Add_ValueChanged($UpdateLightPreview)

$ColorNames = @("Pure White", "Warm", "Cool", "50% Gray", "Red", "Green", "Blue", "Black")
$ColorText  = @("
0..7 | ForEach-Object {
    $hex = $PresetColors[$_]
    $btn = New-Object Windows.Controls.Button -Property @{ Content = $ColorNames[$_]; Background = $hex; Foreground = $ColorText[$_]; FontWeight = 'Bold' }
    $btn.Add_Click({ & $StartFullScreen $hex $Win.FindName("all").IsChecked }.GetNewClosure())
    [void]$Win.FindName("ColGrid").Children.Add($btn)
}
$Win.FindName("go").Add_Click({ & $StartFullScreen $script:CustomLightColor $Win.FindName("all").IsChecked })

[void]$Win.ShowDialog()
