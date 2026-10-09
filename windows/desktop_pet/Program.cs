using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text.Json;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Threading;
using LinePutScript;
using VPet_Simulator.Core;

namespace AdventurersGuild.DesktopPet;

internal static class Program
{
    [STAThread]
    public static int Main(string[] args)
    {
        var configPath = GetArgument(args, "--config");
        if (string.IsNullOrWhiteSpace(configPath))
        {
            return 2;
        }

        _ = int.TryParse(GetArgument(args, "--parent-pid"), out var parentPid);

        var app = new Application
        {
            ShutdownMode = ShutdownMode.OnMainWindowClose,
        };
        var window = new DesktopPetWindow(Path.GetFullPath(configPath), parentPid);
        app.Run(window);
        return 0;
    }

    private static string? GetArgument(string[] args, string name)
    {
        for (var i = 0; i + 1 < args.Length; i++)
        {
            if (string.Equals(args[i], name, StringComparison.OrdinalIgnoreCase))
            {
                return args[i + 1];
            }
        }
        return null;
    }
}

internal sealed class DesktopPetWindow : Window
{
    private const string MinimalVPetGraphConfig = """
touchhead:|px#0:|py#0:|sw#500:|sh#500:|
touchbody:|px#0:|py#0:|sw#500:|sh#500:|
touchraised:|happy_px#0:|happy_py#0:|happy_sw#500:|happy_sh#500:|nomal_px#0:|nomal_py#0:|nomal_sw#500:|nomal_sh#500:|poorcondition_px#0:|poorcondition_py#0:|poorcondition_sw#500:|poorcondition_sh#500:|ill_px#0:|ill_py#0:|ill_sw#500:|ill_sh#500:|
raisepoint:|happy_x#250:|happy_y#250:|nomal_x#250:|nomal_y#250:|poorcondition_x#250:|poorcondition_y#250:|ill_x#250:|ill_y#250:|
str:|
duration:|
""";

    private readonly string _configPath;
    private readonly string _windowStatePath;
    private readonly int _parentPid;
    private readonly Image _petImage;
    private readonly Border _bubble;
    private readonly TextBlock _bubbleText;
    private readonly DispatcherTimer _reloadDebounce;
    private readonly DispatcherTimer _parentTimer;
    private readonly DispatcherTimer _deadlineTimer;
    private readonly GlobalKeyboardActivityHook _keyboardHook;
    private readonly GraphCore _graphCore;

    private FileSystemWatcher? _watcher;
    private PetConfig _config = new();
    private Picture? _activePicture;
    private string? _activeImagePath;
    private bool _keyActive;
    private bool _closed;

    public DesktopPetWindow(string configPath, int parentPid)
    {
        _configPath = configPath;
        _parentPid = parentPid;
        var configDirectory = Path.GetDirectoryName(configPath) ?? AppContext.BaseDirectory;
        _windowStatePath = Path.Combine(configDirectory, "window-state.json");

        Title = "冒险者公会 · 桌宠";
        Width = 320;
        Height = 390;
        MinWidth = 220;
        MinHeight = 260;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ShowInTaskbar = false;
        Topmost = true;

        var root = new Grid
        {
            Background = Brushes.Transparent,
        };
        root.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        root.RowDefinitions.Add(new RowDefinition { Height = new GridLength(1, GridUnitType.Star) });

        _bubbleText = new TextBlock
        {
            TextWrapping = TextWrapping.Wrap,
            FontSize = 14,
            Foreground = new SolidColorBrush(Color.FromRgb(38, 38, 38)),
            MaxWidth = 270,
        };
        _bubble = new Border
        {
            Background = new SolidColorBrush(Color.FromArgb(238, 255, 255, 255)),
            BorderBrush = new SolidColorBrush(Color.FromArgb(40, 0, 0, 0)),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(16),
            Padding = new Thickness(14, 11, 14, 11),
            Margin = new Thickness(12, 8, 12, 6),
            Child = _bubbleText,
            Effect = new DropShadowEffect
            {
                BlurRadius = 16,
                ShadowDepth = 3,
                Opacity = 0.18,
            },
        };
        Grid.SetRow(_bubble, 0);
        root.Children.Add(_bubble);

        _petImage = new Image
        {
            Stretch = Stretch.Uniform,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Bottom,
            Margin = new Thickness(8, 0, 8, 4),
        };
        Grid.SetRow(_petImage, 1);
        root.Children.Add(_petImage);

        Content = root;

        root.MouseLeftButtonDown += (_, e) =>
        {
            if (e.LeftButton != MouseButtonState.Pressed) return;
            try
            {
                DragMove();
                SaveWindowState();
            }
            catch (InvalidOperationException)
            {
                // Ignore a drag that lost capture while the window was moving.
            }
        };

        var graphDocument = new LpsDocument(MinimalVPetGraphConfig);
        _graphCore = new GraphCore(
            1000,
            Dispatcher,
            new GraphCore.Config(graphDocument)
        );

        _reloadDebounce = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(180),
        };
        _reloadDebounce.Tick += async (_, _) =>
        {
            _reloadDebounce.Stop();
            await ReloadConfigAsync();
        };

        _parentTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(350),
        };
        _parentTimer.Tick += (_, _) => CheckParentProcess();

        _deadlineTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(20),
        };
        _deadlineTimer.Tick += (_, _) => RefreshBubble();

        _keyboardHook = new GlobalKeyboardActivityHook();
        _keyboardHook.ActivityChanged += active =>
        {
            Dispatcher.BeginInvoke(() =>
            {
                if (_keyActive == active) return;
                _keyActive = active;
                RefreshImage();
            });
        };

        Loaded += async (_, _) =>
        {
            RestoreWindowState();
            StartConfigWatcher();
            _keyboardHook.Start();
            _parentTimer.Start();
            _deadlineTimer.Start();
            await ReloadConfigAsync();
        };

        Closed += (_, _) => DisposeResources();
    }

    private void StartConfigWatcher()
    {
        var directory = Path.GetDirectoryName(_configPath);
        var fileName = Path.GetFileName(_configPath);
        if (string.IsNullOrWhiteSpace(directory) || string.IsNullOrWhiteSpace(fileName))
        {
            return;
        }

        Directory.CreateDirectory(directory);
        _watcher = new FileSystemWatcher(directory, fileName)
        {
            NotifyFilter = NotifyFilters.LastWrite | NotifyFilters.Size | NotifyFilters.FileName,
            EnableRaisingEvents = true,
        };
        _watcher.Changed += OnConfigChanged;
        _watcher.Created += OnConfigChanged;
        _watcher.Renamed += OnConfigChanged;
    }

    private void OnConfigChanged(object? sender, FileSystemEventArgs e)
    {
        Dispatcher.BeginInvoke(() =>
        {
            _reloadDebounce.Stop();
            _reloadDebounce.Start();
        });
    }

    private async Task ReloadConfigAsync()
    {
        PetConfig? next = null;
        for (var attempt = 0; attempt < 4 && next is null; attempt++)
        {
            try
            {
                if (!File.Exists(_configPath)) return;
                var json = await File.ReadAllTextAsync(_configPath);
                next = JsonSerializer.Deserialize<PetConfig>(
                    json,
                    new JsonSerializerOptions
                    {
                        PropertyNameCaseInsensitive = true,
                    }
                );
            }
            catch (IOException)
            {
                await Task.Delay(80);
            }
            catch (JsonException)
            {
                await Task.Delay(80);
            }
        }

        if (next is null) return;
        _config = next;

        if (!_config.Enabled)
        {
            Close();
            return;
        }

        RefreshImage(force: true);
        RefreshBubble();
    }

    private void RefreshImage(bool force = false)
    {
        var path = _keyActive && IsUsableImage(_config.ImageB)
            ? _config.ImageB
            : _config.ImageA;

        if (!IsUsableImage(path))
        {
            if (!force && _activeImagePath is null) return;
            _activeImagePath = null;
            _activePicture?.Stop(true);
            _activePicture?.Dispose();
            _activePicture = null;
            _petImage.Source = null;
            _petImage.Visibility = Visibility.Collapsed;
            RefreshBubble();
            return;
        }

        path = Path.GetFullPath(path!);
        if (!force && string.Equals(
                _activeImagePath,
                path,
                StringComparison.OrdinalIgnoreCase))
        {
            return;
        }

        try
        {
            _activePicture?.Stop(true);
            _activePicture?.Dispose();

            var picture = new Picture(
                _graphCore,
                path,
                new GraphInfo(
                    _keyActive ? "guild-key-active" : "guild-idle",
                    GraphInfo.GraphType.Common,
                    GraphInfo.AnimatType.Single,
                    IGameSave.ModeType.Nomal
                ),
                length: int.MaxValue,
                isloop: true
            );

            _ = picture.Run(_petImage);
            _activePicture = picture;
            _activeImagePath = path;
            _petImage.Visibility = Visibility.Visible;
        }
        catch
        {
            _activeImagePath = null;
            _petImage.Source = null;
            _petImage.Visibility = Visibility.Collapsed;
        }

        RefreshBubble();
    }

    private void RefreshBubble()
    {
        if (!IsUsableImage(_config.ImageA))
        {
            _bubbleText.Text = "请先在冒险者公会 → 桌宠里导入当前预设的 A 图。";
            _bubble.Visibility = Visibility.Visible;
            return;
        }

        if (string.Equals(_config.TextMode, "custom", StringComparison.OrdinalIgnoreCase))
        {
            var custom = (_config.CustomText ?? string.Empty).Trim();
            _bubbleText.Text = custom.Length == 0 ? " " : custom;
            _bubble.Visibility = Visibility.Visible;
            return;
        }

        var title = (_config.CurrentOrderTitle ?? string.Empty).Trim();
        if (title.Length == 0)
        {
            _bubbleText.Text = "当前没有在画订单";
            _bubble.Visibility = Visibility.Visible;
            return;
        }

        var details = new List<string>();
        var node = (_config.CurrentOrderNode ?? string.Empty).Trim();
        if (node.Length > 0)
        {
            details.Add(node);
        }

        if (DateTime.TryParse(_config.CurrentOrderDeadline, out var deadline))
        {
            details.Add(FormatDeadline(deadline.ToLocalTime()));
        }
        else
        {
            details.Add("未设置截稿时间");
        }

        _bubbleText.Text = details.Count == 0
            ? title
            : title + Environment.NewLine + string.Join(" · ", details);
        _bubble.Visibility = Visibility.Visible;
    }

    private static string FormatDeadline(DateTime deadline)
    {
        var delta = deadline - DateTime.Now;
        if (delta <= TimeSpan.Zero) return "已超过截稿时间";
        if (delta.TotalDays >= 1)
        {
            return $"剩余 {(int)delta.TotalDays} 天 {delta.Hours} 小时";
        }
        if (delta.TotalHours >= 1)
        {
            return $"剩余 {(int)delta.TotalHours} 小时 {delta.Minutes} 分";
        }
        return $"剩余 {Math.Max(0, (int)Math.Ceiling(delta.TotalMinutes))} 分";
    }

    private static bool IsUsableImage(string? path)
    {
        if (string.IsNullOrWhiteSpace(path)) return false;
        try
        {
            return File.Exists(path);
        }
        catch
        {
            return false;
        }
    }

    private void CheckParentProcess()
    {
        if (_parentPid <= 0) return;
        try
        {
            using var parent = Process.GetProcessById(_parentPid);
            if (!parent.HasExited) return;
        }
        catch (ArgumentException)
        {
            // The parent PID no longer exists.
        }
        catch (InvalidOperationException)
        {
            // The parent process has already exited.
        }

        Close();
    }

    private void RestoreWindowState()
    {
        try
        {
            if (File.Exists(_windowStatePath))
            {
                var state = JsonSerializer.Deserialize<WindowState>(
                    File.ReadAllText(_windowStatePath)
                );
                if (state is not null && IsVisiblePosition(state.Left, state.Top))
                {
                    WindowStartupLocation = WindowStartupLocation.Manual;
                    Left = state.Left;
                    Top = state.Top;
                    return;
                }
            }
        }
        catch
        {
            // Fall back to a safe default position.
        }

        WindowStartupLocation = WindowStartupLocation.Manual;
        Left = SystemParameters.WorkArea.Right - Width - 36;
        Top = SystemParameters.WorkArea.Bottom - Height - 36;
    }

    private bool IsVisiblePosition(double left, double top)
    {
        var right = left + Math.Max(120, Width);
        var bottom = top + Math.Max(120, Height);
        var virtualRight = SystemParameters.VirtualScreenLeft + SystemParameters.VirtualScreenWidth;
        var virtualBottom = SystemParameters.VirtualScreenTop + SystemParameters.VirtualScreenHeight;

        return right >= SystemParameters.VirtualScreenLeft + 40 &&
               left <= virtualRight - 40 &&
               bottom >= SystemParameters.VirtualScreenTop + 40 &&
               top <= virtualBottom - 40;
    }

    private void SaveWindowState()
    {
        try
        {
            var directory = Path.GetDirectoryName(_windowStatePath);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }
            File.WriteAllText(
                _windowStatePath,
                JsonSerializer.Serialize(new WindowState(Left, Top))
            );
        }
        catch
        {
            // Position persistence is optional.
        }
    }

    private void DisposeResources()
    {
        if (_closed) return;
        _closed = true;

        _reloadDebounce.Stop();
        _parentTimer.Stop();
        _deadlineTimer.Stop();

        if (_watcher is not null)
        {
            _watcher.EnableRaisingEvents = false;
            _watcher.Dispose();
            _watcher = null;
        }

        _keyboardHook.Dispose();

        _activePicture?.Stop(true);
        _activePicture?.Dispose();
        _activePicture = null;
        _graphCore.Dispose();
    }

    private sealed record WindowState(double Left, double Top);

    private sealed class PetConfig
    {
        public bool Enabled { get; set; }
        public string? ImageA { get; set; }
        public string? ImageB { get; set; }
        public string? TextMode { get; set; }
        public string? CustomText { get; set; }
        public string? CurrentOrderTitle { get; set; }
        public string? CurrentOrderNode { get; set; }
        public string? CurrentOrderDeadline { get; set; }
    }
}

internal sealed class GlobalKeyboardActivityHook : IDisposable
{
    private const int WhKeyboardLl = 13;
    private const int WmKeyDown = 0x0100;
    private const int WmKeyUp = 0x0101;
    private const int WmSysKeyDown = 0x0104;
    private const int WmSysKeyUp = 0x0105;

    private readonly HashSet<int> _pressedKeys = new();
    private readonly LowLevelKeyboardProc _callback;
    private IntPtr _hook;
    private bool _active;

    public GlobalKeyboardActivityHook()
    {
        _callback = HookCallback;
    }

    public event Action<bool>? ActivityChanged;

    public void Start()
    {
        if (_hook != IntPtr.Zero) return;
        using var process = Process.GetCurrentProcess();
        using var module = process.MainModule;
        var moduleHandle = GetModuleHandle(module?.ModuleName);
        _hook = SetWindowsHookEx(WhKeyboardLl, _callback, moduleHandle, 0);
    }

    public void Dispose()
    {
        if (_hook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_hook);
            _hook = IntPtr.Zero;
        }
        _pressedKeys.Clear();
    }

    private IntPtr HookCallback(int code, IntPtr wParam, IntPtr lParam)
    {
        if (code >= 0)
        {
            var message = wParam.ToInt32();
            var data = Marshal.PtrToStructure<KbdLlHookStruct>(lParam);

            if (message is WmKeyDown or WmSysKeyDown)
            {
                _pressedKeys.Add(data.VirtualKeyCode);
                SetActive(_pressedKeys.Count > 0);
            }
            else if (message is WmKeyUp or WmSysKeyUp)
            {
                _pressedKeys.Remove(data.VirtualKeyCode);
                SetActive(_pressedKeys.Count > 0);
            }
        }

        return CallNextHookEx(_hook, code, wParam, lParam);
    }

    private void SetActive(bool active)
    {
        if (_active == active) return;
        _active = active;
        ActivityChanged?.Invoke(active);
    }

    [StructLayout(LayoutKind.Sequential)]
    private readonly struct KbdLlHookStruct
    {
        public readonly int VirtualKeyCode;
        public readonly int ScanCode;
        public readonly int Flags;
        public readonly int Time;
        public readonly UIntPtr ExtraInfo;
    }

    private delegate IntPtr LowLevelKeyboardProc(int code, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true)]
    private static extern IntPtr SetWindowsHookEx(
        int idHook,
        LowLevelKeyboardProc callback,
        IntPtr module,
        uint threadId
    );

    [DllImport("user32.dll", SetLastError = true)]
    [return: MarshalAs(UnmanagedType.Bool)]
    private static extern bool UnhookWindowsHookEx(IntPtr hook);

    [DllImport("user32.dll")]
    private static extern IntPtr CallNextHookEx(
        IntPtr hook,
        int code,
        IntPtr wParam,
        IntPtr lParam
    );

    [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
    private static extern IntPtr GetModuleHandle(string? moduleName);
}
