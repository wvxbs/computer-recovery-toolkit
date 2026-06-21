using System.Diagnostics;
using System.Text;
using Microsoft.Win32;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;
using Windows.Graphics;

namespace ComputerRecoveryToolkit.WinUI;

public sealed partial class MainWindow : Window
{
    private readonly StringBuilder _output = new();
    private readonly Dictionary<string, Dictionary<string, string>> _strings = BuildStrings();
    private string _language = "pt";

    private Grid _root = null!;
    private InfoBar _status = null!;
    private TextBox _outputBox = null!;
    private NumberBox _hibernateMinutes = null!;
    private NumberBox _downloadTimer = null!;
    private NumberBox _idleTimer = null!;
    private NumberBox _cpuCap = null!;
    private ComboBox _languageBox = null!;
    private Button _diagnosticsButton = null!;
    private Button _energyButton = null!;
    private Button _powerPreviewButton = null!;
    private Button _powerApplyButton = null!;
    private Button _downloadButton = null!;
    private Button _gpuButton = null!;
    private Button _refreshListButton = null!;
    private Button _refreshInstallButton = null!;
    private Button _installButton = null!;
    private Button _repairButton = null!;
    private Button _uninstallButton = null!;
    private TextBlock _installStateText = null!;
    private Button _openRepoButton = null!;

    public MainWindow()
    {
        InitializeComponent();
        Title = "Computer Recovery Toolkit";
        AppWindow.Title = Title;
        AppWindow.Resize(new SizeInt32(1120, 820));

        TryApplyBackdrop();
        Content = BuildContent();
        ApplyLanguage();
        RefreshInstallState();
    }

    private UIElement BuildContent()
    {
        _root = new Grid
        {
            Padding = new Thickness(24),
            RowSpacing = 16,
            Background = ResolvePageBackground()
        };
        _root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        _root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        _root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });
        _root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        _root.Children.Add(BuildHeader());

        _status = new InfoBar
        {
            IsOpen = true,
            Severity = InfoBarSeverity.Informational
        };
        Grid.SetRow(_status, 1);
        _root.Children.Add(_status);

        var tabs = new TabView
        {
            IsAddTabButtonVisible = false,
            CanDragTabs = false
        };
        tabs.TabItems.Add(new TabViewItem { Header = T("tabDiagnostics"), Content = BuildDiagnosticsTab() });
        tabs.TabItems.Add(new TabViewItem { Header = T("tabPower"), Content = BuildPowerTab() });
        tabs.TabItems.Add(new TabViewItem { Header = T("tabGpu"), Content = BuildGpuTab() });
        tabs.TabItems.Add(new TabViewItem { Header = T("tabDownloads"), Content = BuildDownloadsTab() });
        tabs.TabItems.Add(new TabViewItem { Header = T("tabInstall"), Content = BuildInstallTab() });
        Grid.SetRow(tabs, 2);
        _root.Children.Add(tabs);

        _outputBox = new TextBox
        {
            AcceptsReturn = true,
            IsReadOnly = true,
            TextWrapping = TextWrapping.NoWrap,
            FontFamily = new FontFamily("Consolas"),
            MinHeight = 180,
            MaxHeight = 240
        };
        ScrollViewer.SetHorizontalScrollBarVisibility(_outputBox, ScrollBarVisibility.Auto);
        ScrollViewer.SetVerticalScrollBarVisibility(_outputBox, ScrollBarVisibility.Auto);
        Grid.SetRow(_outputBox, 3);
        _root.Children.Add(_outputBox);

        return _root;
    }

    private UIElement BuildHeader()
    {
        var grid = new Grid { ColumnSpacing = 16 };
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        grid.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });

        var title = new StackPanel { Spacing = 4 };
        title.Children.Add(new TextBlock
        {
            Text = "Computer Recovery Toolkit",
            FontSize = 26,
            FontWeight = new Windows.UI.Text.FontWeight { Weight = 650 }
        });
        title.Children.Add(new TextBlock
        {
            Text = T("subtitle"),
            Opacity = 0.78,
            TextWrapping = TextWrapping.Wrap
        });
        grid.Children.Add(title);

        var right = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8, VerticalAlignment = VerticalAlignment.Top };
        _languageBox = new ComboBox { Width = 150 };
        _languageBox.Items.Add(new ComboBoxItem { Content = "Português", Tag = "pt" });
        _languageBox.Items.Add(new ComboBoxItem { Content = "English", Tag = "en" });
        _languageBox.SelectedIndex = 0;
        _languageBox.SelectionChanged += (_, _) =>
        {
            if (_languageBox.SelectedItem is ComboBoxItem item && item.Tag is string tag)
            {
                _language = tag;
                ApplyLanguage();
            }
        };
        right.Children.Add(_languageBox);

        _openRepoButton = new Button { Content = T("openFolder") };
        _openRepoButton.Click += (_, _) => Process.Start(new ProcessStartInfo { FileName = RepoRoot, UseShellExecute = true });
        right.Children.Add(_openRepoButton);

        Grid.SetColumn(right, 1);
        grid.Children.Add(right);
        return grid;
    }

    private UIElement BuildDiagnosticsTab()
    {
        var panel = NewPanel();
        panel.Children.Add(SectionTitle("diagnosticsTitle", "diagnosticsText"));

        var row = NewButtonRow();
        _diagnosticsButton = ActionButton("runDiagnostics", async (_, _) => await RunScriptAsync("Collect-ComputerDiagnostics.ps1"));
        _energyButton = ActionButton("runEnergy", async (_, _) => await RunScriptAsync("Collect-ComputerDiagnostics.ps1", "-IncludeEnergyTrace", "-EnergyTraceSeconds", "60"));
        row.Children.Add(_diagnosticsButton);
        row.Children.Add(_energyButton);
        panel.Children.Add(row);
        return Wrap(panel);
    }

    private UIElement BuildPowerTab()
    {
        var panel = NewPanel();
        panel.Children.Add(SectionTitle("powerTitle", "powerText"));

        _hibernateMinutes = new NumberBox
        {
            Value = 120,
            Minimum = 30,
            Maximum = 1440,
            SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact,
            Header = T("hibernateMinutes")
        };
        panel.Children.Add(_hibernateMinutes);

        var row = NewButtonRow();
        _powerPreviewButton = ActionButton("previewPower", async (_, _) => await RunPowerPolicyAsync(apply: false));
        _powerApplyButton = ActionButton("applyPower", async (_, _) => await RunPowerPolicyAsync(apply: true));
        row.Children.Add(_powerPreviewButton);
        row.Children.Add(_powerApplyButton);
        panel.Children.Add(row);
        return Wrap(panel);
    }

    private UIElement BuildGpuTab()
    {
        var panel = NewPanel();
        panel.Children.Add(SectionTitle("gpuTitle", "gpuText"));

        var row = NewButtonRow();
        _gpuButton = ActionButton("checkGpu", async (_, _) => await RunScriptAsync("Get-DgpuProcesses.ps1"));
        _refreshListButton = ActionButton("listDisplays", async (_, _) => await RunScriptAsync("Set-InternalDisplayRefresh.ps1", "-Mode", "List"));
        _refreshInstallButton = ActionButton("installRefresh", async (_, _) => await RunScriptAsync("Set-InternalDisplayRefresh.ps1", "-Mode", "InstallTask", "-BatteryHz", "60", "-AcHz", "120"));
        row.Children.Add(_gpuButton);
        row.Children.Add(_refreshListButton);
        row.Children.Add(_refreshInstallButton);
        panel.Children.Add(row);
        return Wrap(panel);
    }

    private UIElement BuildDownloadsTab()
    {
        var panel = NewPanel();
        panel.Children.Add(SectionTitle("downloadsTitle", "downloadsText"));

        _downloadTimer = new NumberBox
        {
            Value = 0,
            Minimum = 0,
            Maximum = 1440,
            SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact,
            Header = T("maxMinutes")
        };
        _idleTimer = new NumberBox
        {
            Value = 15,
            Minimum = 0,
            Maximum = 240,
            SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact,
            Header = T("idleMinutes")
        };
        _cpuCap = new NumberBox
        {
            Value = 70,
            Minimum = 20,
            Maximum = 100,
            SpinButtonPlacementMode = NumberBoxSpinButtonPlacementMode.Compact,
            Header = T("cpuCap")
        };

        var values = new Grid { ColumnSpacing = 12 };
        values.ColumnDefinitions.Add(new ColumnDefinition());
        values.ColumnDefinitions.Add(new ColumnDefinition());
        values.ColumnDefinitions.Add(new ColumnDefinition());
        values.Children.Add(_downloadTimer);
        Grid.SetColumn(_idleTimer, 1);
        values.Children.Add(_idleTimer);
        Grid.SetColumn(_cpuCap, 2);
        values.Children.Add(_cpuCap);
        panel.Children.Add(values);

        _downloadButton = ActionButton("startDownloadMode", async (_, _) => await StartDownloadModeAsync());
        panel.Children.Add(_downloadButton);
        return Wrap(panel);
    }

    private UIElement BuildInstallTab()
    {
        var panel = NewPanel();
        panel.Children.Add(SectionTitle("installTitle", "installText"));

        _installStateText = new TextBlock
        {
            TextWrapping = TextWrapping.Wrap,
            Opacity = 0.82
        };
        panel.Children.Add(_installStateText);

        var row = NewButtonRow();
        _installButton = ActionButton("installApp", async (_, _) => await InstallOrRepairAsync(repair: false));
        _repairButton = ActionButton("repairApp", async (_, _) => await InstallOrRepairAsync(repair: true));
        _uninstallButton = ActionButton("uninstallApp", async (_, _) => await UninstallAsync());
        row.Children.Add(_installButton);
        row.Children.Add(_repairButton);
        row.Children.Add(_uninstallButton);
        panel.Children.Add(row);
        return Wrap(panel);
    }

    private static StackPanel NewPanel() => new() { Spacing = 14, Padding = new Thickness(2) };

    private static StackPanel NewButtonRow() => new() { Orientation = Orientation.Horizontal, Spacing = 8 };

    private Button ActionButton(string key, RoutedEventHandler handler)
    {
        var button = new Button { Content = T(key), MinWidth = 150 };
        button.Click += handler;
        return button;
    }

    private UIElement SectionTitle(string titleKey, string bodyKey)
    {
        var panel = new StackPanel { Spacing = 4 };
        panel.Children.Add(new TextBlock
        {
            Text = T(titleKey),
            FontSize = 19,
            FontWeight = new Windows.UI.Text.FontWeight { Weight = 600 }
        });
        panel.Children.Add(new TextBlock
        {
            Text = T(bodyKey),
            TextWrapping = TextWrapping.Wrap,
            Opacity = 0.78
        });
        return panel;
    }

    private static UIElement Wrap(UIElement element) => new ScrollViewer
    {
        Content = new Border
        {
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(8),
            Padding = new Thickness(16),
            BorderBrush = new SolidColorBrush(Windows.UI.Color.FromArgb(0x30, 0x80, 0x80, 0x80)),
            Child = element
        },
        VerticalScrollBarVisibility = ScrollBarVisibility.Auto
    };

    private async Task RunPowerPolicyAsync(bool apply)
    {
        var minutes = Math.Clamp((int)_hibernateMinutes.Value, 30, 1440);
        if (apply)
        {
            await RunScriptAsync("Apply-ComputerPowerPolicy.ps1", "-Apply", "-BatteryHibernateAfterMinutes", minutes.ToString());
        }
        else
        {
            await RunScriptAsync("Apply-ComputerPowerPolicy.ps1", "-BatteryHibernateAfterMinutes", minutes.ToString());
        }
    }

    private async Task StartDownloadModeAsync()
    {
        var args = new List<string>
        {
            "-CpuMaxPercent", Math.Clamp((int)_cpuCap.Value, 20, 100).ToString(),
            "-IdleExitMinutes", Math.Clamp((int)_idleTimer.Value, 0, 240).ToString()
        };
        var max = (int)_downloadTimer.Value;
        if (max > 0) { args.AddRange(["-MaxMinutes", max.ToString()]); }
        await RunScriptDetachedAsync("Start-TemporaryDownloadMode.ps1", args.ToArray());
    }

    private async Task InstallOrRepairAsync(bool repair)
    {
        SetBusy(true);
        ClearOutput();
        try
        {
            await Task.Run(() =>
            {
                Directory.CreateDirectory(InstallDir);
                if (!IsRunningFromInstallDir)
                {
                    CopyDirectory(AppContext.BaseDirectory, InstallDir);
                }

                CreateStartMenuLauncher();
                CreateUninstaller();
                RegisterUninstallEntry();
            });

            RefreshInstallState();
            _status.Severity = InfoBarSeverity.Success;
            _status.Title = repair ? T("repaired") : T("installed");
            _status.Message = InstallDir;
            AppendOutput($"{T("installLocation")}: {InstallDir}");
        }
        catch (Exception ex)
        {
            _status.Severity = InfoBarSeverity.Error;
            _status.Title = T("failed");
            _status.Message = ex.Message;
            AppendOutput(ex.ToString());
        }
        finally
        {
            SetBusy(false);
        }
    }

    private async Task UninstallAsync()
    {
        SetBusy(true);
        ClearOutput();
        try
        {
            await Task.Run(() =>
            {
                RemoveStartMenuLauncher();
                RemoveUninstallEntry();

                if (IsRunningFromInstallDir)
                {
                    var cleanup = Path.Combine(Path.GetTempPath(), $"computer-recovery-toolkit-uninstall-{Guid.NewGuid():N}.cmd");
                    File.WriteAllText(cleanup, BuildSelfRemovalCommand(), Encoding.ASCII);
                    Process.Start(new ProcessStartInfo
                    {
                        FileName = cleanup,
                        UseShellExecute = true,
                        CreateNoWindow = true,
                        WindowStyle = ProcessWindowStyle.Hidden
                    });
                    DispatcherQueue.TryEnqueue(Close);
                }
                else if (Directory.Exists(InstallDir))
                {
                    Directory.Delete(InstallDir, recursive: true);
                }
            });

            RefreshInstallState();
            _status.Severity = InfoBarSeverity.Success;
            _status.Title = T("uninstalled");
            _status.Message = T("uninstalledText");
        }
        catch (Exception ex)
        {
            _status.Severity = InfoBarSeverity.Error;
            _status.Title = T("failed");
            _status.Message = ex.Message;
            AppendOutput(ex.ToString());
        }
        finally
        {
            SetBusy(false);
        }
    }

    private void RefreshInstallState()
    {
        if (_installStateText is null) return;
        var installed = File.Exists(InstalledExe);
        var runningInstalled = IsRunningFromInstallDir;
        _installStateText.Text = installed
            ? string.Format(T("installedState"), InstallDir, runningInstalled ? T("yes") : T("no"))
            : T("notInstalledState");
        if (_repairButton is not null) _repairButton.IsEnabled = installed;
        if (_uninstallButton is not null) _uninstallButton.IsEnabled = installed;
    }

    private static void CopyDirectory(string sourceDir, string destinationDir)
    {
        var source = new DirectoryInfo(sourceDir);
        Directory.CreateDirectory(destinationDir);

        foreach (var file in source.EnumerateFiles())
        {
            var target = Path.Combine(destinationDir, file.Name);
            file.CopyTo(target, overwrite: true);
        }

        foreach (var directory in source.EnumerateDirectories())
        {
            if (directory.FullName.Equals(destinationDir, StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }
            CopyDirectory(directory.FullName, Path.Combine(destinationDir, directory.Name));
        }
    }

    private static void CreateStartMenuLauncher()
    {
        Directory.CreateDirectory(StartMenuProgramsDir);
        var content = $"""
        @echo off
        start "" "{InstalledExe}" %*
        """;
        File.WriteAllText(StartMenuLauncher, content, Encoding.ASCII);
    }

    private static void RemoveStartMenuLauncher()
    {
        File.Delete(StartMenuLauncher);
    }

    private static void CreateUninstaller()
    {
        File.WriteAllText(UninstallCommand, BuildExternalUninstallCommand(), Encoding.ASCII);
    }

    private static void RegisterUninstallEntry()
    {
        using var key = Registry.CurrentUser.CreateSubKey(UninstallRegistryPath);
        key?.SetValue("DisplayName", "Computer Recovery Toolkit");
        key?.SetValue("DisplayVersion", AppVersion);
        key?.SetValue("Publisher", "Gabriel Ferreira");
        key?.SetValue("InstallLocation", InstallDir);
        key?.SetValue("DisplayIcon", InstalledExe);
        key?.SetValue("NoModify", 1, RegistryValueKind.DWord);
        key?.SetValue("NoRepair", 0, RegistryValueKind.DWord);
        key?.SetValue("UninstallString", $"\"{UninstallCommand}\"");
        key?.SetValue("QuietUninstallString", $"\"{UninstallCommand}\"");
    }

    private static void RemoveUninstallEntry()
    {
        Registry.CurrentUser.DeleteSubKeyTree(UninstallRegistryPath, throwOnMissingSubKey: false);
    }

    private static string BuildExternalUninstallCommand() => $"""
        @echo off
        set "APPDIR={InstallDir}"
        del "{StartMenuLauncher}" >nul 2>nul
        reg delete "HKCU\Software\Microsoft\Windows\CurrentVersion\Uninstall\ComputerRecoveryToolkit" /f >nul 2>nul
        taskkill /IM ComputerRecoveryToolkit.WinUI.exe /F >nul 2>nul
        timeout /t 2 /nobreak >nul
        rmdir /s /q "%APPDIR%" >nul 2>nul
        """;

    private static string BuildSelfRemovalCommand() => $"""
        @echo off
        timeout /t 2 /nobreak >nul
        rmdir /s /q "{InstallDir}" >nul 2>nul
        del "%~f0" >nul 2>nul
        """;

    private async Task RunScriptAsync(string scriptName, params string[] args)
    {
        SetBusy(true);
        ClearOutput();
        try
        {
            var result = await Task.Run(() => ExecutePowerShell(scriptName, args, detached: false));
            AppendOutput(result.Output);
            AppendOutput(result.Error);
            _status.Severity = result.ExitCode == 0 ? InfoBarSeverity.Success : InfoBarSeverity.Error;
            _status.Title = result.ExitCode == 0 ? T("done") : T("failed");
            _status.Message = string.Format(T("exitCode"), result.ExitCode);
        }
        catch (Exception ex)
        {
            _status.Severity = InfoBarSeverity.Error;
            _status.Title = T("failed");
            _status.Message = ex.Message;
            AppendOutput(ex.ToString());
        }
        finally
        {
            SetBusy(false);
        }
    }

    private async Task RunScriptDetachedAsync(string scriptName, params string[] args)
    {
        SetBusy(true);
        try
        {
            await Task.Run(() => ExecutePowerShell(scriptName, args, detached: true));
            _status.Severity = InfoBarSeverity.Success;
            _status.Title = T("started");
            _status.Message = T("downloadStarted");
        }
        catch (Exception ex)
        {
            _status.Severity = InfoBarSeverity.Error;
            _status.Title = T("failed");
            _status.Message = ex.Message;
        }
        finally
        {
            SetBusy(false);
        }
    }

    private ScriptResult ExecutePowerShell(string scriptName, string[] args, bool detached)
    {
        var scriptPath = Path.Combine(AppContext.BaseDirectory, "scripts", scriptName);
        if (!File.Exists(scriptPath))
        {
            scriptPath = Path.Combine(RepoRoot, "scripts", scriptName);
        }
        if (!File.Exists(scriptPath))
        {
            throw new FileNotFoundException("Script not found.", scriptName);
        }

        var startInfo = new ProcessStartInfo
        {
            FileName = PowerShellPath,
            UseShellExecute = detached,
            CreateNoWindow = !detached,
            RedirectStandardOutput = !detached,
            RedirectStandardError = !detached,
            WorkingDirectory = Path.GetDirectoryName(scriptPath)!
        };

        startInfo.ArgumentList.Add("-NoProfile");
        startInfo.ArgumentList.Add("-ExecutionPolicy");
        startInfo.ArgumentList.Add("Bypass");
        if (detached) { startInfo.ArgumentList.Add("-NoExit"); }
        startInfo.ArgumentList.Add("-File");
        startInfo.ArgumentList.Add(scriptPath);
        foreach (var arg in args) { startInfo.ArgumentList.Add(arg); }

        using var process = Process.Start(startInfo) ?? throw new InvalidOperationException("Could not start PowerShell.");
        if (detached)
        {
            return new ScriptResult(0, "", "");
        }

        var output = process.StandardOutput.ReadToEnd();
        var error = process.StandardError.ReadToEnd();
        process.WaitForExit();
        return new ScriptResult(process.ExitCode, output, error);
    }

    private void ApplyLanguage()
    {
        if (_status is not null)
        {
            _status.Title = T("ready");
            _status.Message = T("readyText");
        }
        if (_openRepoButton is not null) _openRepoButton.Content = T("openFolder");
        if (_diagnosticsButton is not null) _diagnosticsButton.Content = T("runDiagnostics");
        if (_energyButton is not null) _energyButton.Content = T("runEnergy");
        if (_powerPreviewButton is not null) _powerPreviewButton.Content = T("previewPower");
        if (_powerApplyButton is not null) _powerApplyButton.Content = T("applyPower");
        if (_downloadButton is not null) _downloadButton.Content = T("startDownloadMode");
        if (_gpuButton is not null) _gpuButton.Content = T("checkGpu");
        if (_refreshListButton is not null) _refreshListButton.Content = T("listDisplays");
        if (_refreshInstallButton is not null) _refreshInstallButton.Content = T("installRefresh");
        if (_installButton is not null) _installButton.Content = T("installApp");
        if (_repairButton is not null) _repairButton.Content = T("repairApp");
        if (_uninstallButton is not null) _uninstallButton.Content = T("uninstallApp");
        if (_hibernateMinutes is not null) _hibernateMinutes.Header = T("hibernateMinutes");
        if (_downloadTimer is not null) _downloadTimer.Header = T("maxMinutes");
        if (_idleTimer is not null) _idleTimer.Header = T("idleMinutes");
        if (_cpuCap is not null) _cpuCap.Header = T("cpuCap");
        RefreshInstallState();
    }

    private void AppendOutput(string text)
    {
        if (string.IsNullOrWhiteSpace(text)) return;
        _output.AppendLine(text.TrimEnd());
        _outputBox.Text = _output.ToString();
    }

    private void ClearOutput()
    {
        _output.Clear();
        _outputBox.Text = "";
    }

    private void SetBusy(bool busy)
    {
        _root.Opacity = busy ? 0.72 : 1.0;
        if (busy)
        {
            _status.Severity = InfoBarSeverity.Informational;
            _status.Title = T("running");
            _status.Message = T("runningText");
        }
    }

    private void TryApplyBackdrop()
    {
        try { SystemBackdrop = new MicaBackdrop(); }
        catch
        {
            try { SystemBackdrop = new DesktopAcrylicBackdrop(); }
            catch { }
        }
    }

    private static Brush ResolvePageBackground()
    {
        if (Application.Current.Resources.TryGetValue("ApplicationPageBackgroundThemeBrush", out var brush) && brush is Brush themeBrush)
        {
            return themeBrush;
        }
        return new SolidColorBrush(Windows.UI.Color.FromArgb(0xFF, 0x20, 0x20, 0x20));
    }

    private string T(string key) => _strings[_language].TryGetValue(key, out var value) ? value : key;

    private static string PowerShellPath =>
        File.Exists(Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe"))
            ? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.System), "WindowsPowerShell", "v1.0", "powershell.exe")
            : "powershell.exe";

    private static string InstallDir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "Programs", "ComputerRecoveryToolkit");

    private static string InstalledExe => Path.Combine(InstallDir, "ComputerRecoveryToolkit.WinUI.exe");

    private static string StartMenuProgramsDir =>
        Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "Microsoft", "Windows", "Start Menu", "Programs");

    private static string StartMenuLauncher => Path.Combine(StartMenuProgramsDir, "Computer Recovery Toolkit.cmd");

    private static string UninstallCommand => Path.Combine(InstallDir, "uninstall.cmd");

    private const string UninstallRegistryPath = @"Software\Microsoft\Windows\CurrentVersion\Uninstall\ComputerRecoveryToolkit";

    private static string AppVersion =>
        typeof(MainWindow).Assembly.GetName().Version?.ToString(3) ?? "0.1.0";

    private static bool IsRunningFromInstallDir =>
        Path.GetFullPath(AppContext.BaseDirectory).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)
            .Equals(Path.GetFullPath(InstallDir).TrimEnd(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar), StringComparison.OrdinalIgnoreCase);

    private static string RepoRoot
    {
        get
        {
            var baseDir = AppContext.BaseDirectory;
            var candidate = Path.GetFullPath(Path.Combine(baseDir, "..", "..", "..", ".."));
            return File.Exists(Path.Combine(candidate, "README.md")) && Directory.Exists(Path.Combine(candidate, "scripts"))
                ? candidate
                : baseDir;
        }
    }

    private static Dictionary<string, Dictionary<string, string>> BuildStrings() => new()
    {
        ["pt"] = new()
        {
            ["subtitle"] = "Diagnostico, energia, GPU e modo download em uma interface nativa opcional.",
            ["openFolder"] = "Abrir pasta",
            ["ready"] = "Pronto",
            ["readyText"] = "Escolha uma acao. Scripts que alteram o sistema ainda pedem elevacao quando necessario.",
            ["running"] = "Executando",
            ["runningText"] = "Aguarde o PowerShell terminar.",
            ["done"] = "Concluido",
            ["failed"] = "Falhou",
            ["started"] = "Iniciado",
            ["exitCode"] = "PowerShell terminou com codigo {0}.",
            ["downloadStarted"] = "Modo download aberto em uma janela propria.",
            ["tabDiagnostics"] = "Diagnostico",
            ["tabPower"] = "Energia",
            ["tabGpu"] = "GPU e tela",
            ["tabDownloads"] = "Downloads",
            ["tabInstall"] = "Instalacao",
            ["diagnosticsTitle"] = "Relatorios do computador",
            ["diagnosticsText"] = "Gera pacotes de diagnostico e traces de energia para analise humana ou por LLM.",
            ["runDiagnostics"] = "Gerar diagnostico",
            ["runEnergy"] = "Trace de energia",
            ["powerTitle"] = "Politicas de energia",
            ["powerText"] = "Pré-visualize ou aplique a politica conservadora de Modern Standby e bateria.",
            ["hibernateMinutes"] = "Hibernar na bateria após minutos",
            ["previewPower"] = "Pré-visualizar",
            ["applyPower"] = "Aplicar",
            ["gpuTitle"] = "GPU hibrida e tela interna",
            ["gpuText"] = "Inspeciona processos na dGPU e instala a automacao de taxa da tela interna.",
            ["checkGpu"] = "Ver dGPU",
            ["listDisplays"] = "Listar telas",
            ["installRefresh"] = "Instalar 60/120 Hz",
            ["downloadsTitle"] = "Modo download temporario",
            ["downloadsText"] = "Mantem launchers baixando na tomada, com timer e saida automatica por ociosidade.",
            ["maxMinutes"] = "Timer maximo, 0 = sem limite",
            ["idleMinutes"] = "Sair apos minutos ociosos",
            ["cpuCap"] = "Limite de CPU (%)",
            ["startDownloadMode"] = "Abrir modo download"
            ,
            ["installTitle"] = "Instalacao local",
            ["installText"] = "Copia o app portable para o perfil do usuario, cria atalho no Menu Iniciar e registra a desinstalacao sem pedir admin.",
            ["installApp"] = "Instalar",
            ["repairApp"] = "Reparar",
            ["uninstallApp"] = "Desinstalar",
            ["installed"] = "Instalado",
            ["repaired"] = "Reparado",
            ["uninstalled"] = "Desinstalado",
            ["uninstalledText"] = "A instalacao local foi removida.",
            ["installLocation"] = "Local de instalacao",
            ["installedState"] = "Instalado em: {0}\nRodando da instalacao local: {1}",
            ["notInstalledState"] = "Ainda nao instalado neste usuario. Voce pode usar como portable ou instalar para aparecer no Menu Iniciar.",
            ["yes"] = "sim",
            ["no"] = "nao"
        },
        ["en"] = new()
        {
            ["subtitle"] = "Diagnostics, power, GPU, and download mode in an optional native Windows UI.",
            ["openFolder"] = "Open folder",
            ["ready"] = "Ready",
            ["readyText"] = "Choose an action. System-changing scripts still request elevation when needed.",
            ["running"] = "Running",
            ["runningText"] = "Waiting for PowerShell to finish.",
            ["done"] = "Done",
            ["failed"] = "Failed",
            ["started"] = "Started",
            ["exitCode"] = "PowerShell exited with code {0}.",
            ["downloadStarted"] = "Download mode opened in its own window.",
            ["tabDiagnostics"] = "Diagnostics",
            ["tabPower"] = "Power",
            ["tabGpu"] = "GPU and display",
            ["tabDownloads"] = "Downloads",
            ["tabInstall"] = "Install",
            ["diagnosticsTitle"] = "Computer reports",
            ["diagnosticsText"] = "Creates diagnostic bundles and energy traces for human or LLM analysis.",
            ["runDiagnostics"] = "Collect diagnostics",
            ["runEnergy"] = "Energy trace",
            ["powerTitle"] = "Power policies",
            ["powerText"] = "Preview or apply the conservative Modern Standby and battery policy.",
            ["hibernateMinutes"] = "Hibernate on battery after minutes",
            ["previewPower"] = "Preview",
            ["applyPower"] = "Apply",
            ["gpuTitle"] = "Hybrid GPU and internal display",
            ["gpuText"] = "Inspects dGPU processes and installs internal display refresh automation.",
            ["checkGpu"] = "Check dGPU",
            ["listDisplays"] = "List displays",
            ["installRefresh"] = "Install 60/120 Hz",
            ["downloadsTitle"] = "Temporary download mode",
            ["downloadsText"] = "Keeps launchers downloading on AC, with a timer and automatic idle exit.",
            ["maxMinutes"] = "Max timer, 0 = unlimited",
            ["idleMinutes"] = "Exit after idle minutes",
            ["cpuCap"] = "CPU cap (%)",
            ["startDownloadMode"] = "Open download mode",
            ["installTitle"] = "Local install",
            ["installText"] = "Copies the portable app to the user profile, creates a Start Menu launcher, and registers uninstall without admin rights.",
            ["installApp"] = "Install",
            ["repairApp"] = "Repair",
            ["uninstallApp"] = "Uninstall",
            ["installed"] = "Installed",
            ["repaired"] = "Repaired",
            ["uninstalled"] = "Uninstalled",
            ["uninstalledText"] = "The local install was removed.",
            ["installLocation"] = "Install location",
            ["installedState"] = "Installed at: {0}\nRunning from local install: {1}",
            ["notInstalledState"] = "Not installed for this user yet. You can keep using it as portable or install it into the Start Menu.",
            ["yes"] = "yes",
            ["no"] = "no"
        }
    };

    private sealed record ScriptResult(int ExitCode, string Output, string Error);
}
