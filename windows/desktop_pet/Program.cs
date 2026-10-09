using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Effects;
using System.Windows.Shapes;
using Path = System.IO.Path;
using System.Windows.Threading;
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

        var fullConfigPath = Path.GetFullPath(configPath);
        var mutexKey = Convert.ToHexString(
            SHA256.HashData(
                Encoding.UTF8.GetBytes(fullConfigPath.ToUpperInvariant())
            )
        );
        using var singleInstance = new Mutex(
            initiallyOwned: true,
            name: @"Local\AdventurersGuild.DesktopPet." + mutexKey,
            createdNew: out var createdNew
        );
        if (!createdNew)
        {
            return 0;
        }

        try
        {
            var app = new Application
            {
                ShutdownMode = ShutdownMode.OnMainWindowClose,
            };
            var window = new DesktopPetWindow(fullConfigPath, parentPid);
            app.Run(window);
            return 0;
        }
        finally
        {
            singleInstance.ReleaseMutex();
        }
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

    private readonly string _configPath;
    private readonly string _windowStatePath;
    private readonly int _parentPid;
    private readonly Grid _root;
    private readonly StackPanel _layoutPanel;
    private readonly Grid _headerRow;
    private readonly StackPanel _bubbleHost;
    private readonly Polygon _bubbleTail;
    private readonly Border _focusClock;
    private readonly TextBlock _focusClockText;
    private readonly Grid _imageViewport;
    private readonly Image _petImage;
    private readonly Border _bubble;
    private readonly TextBlock _bubbleText;
    private readonly DispatcherTimer _reloadDebounce;
    private readonly DispatcherTimer _parentTimer;
    private readonly DispatcherTimer _deadlineTimer;
    private readonly DispatcherTimer _focusTimer;
    private readonly GlobalInputActivityHook _inputHook;
    private readonly GraphCore _graphCore;

    private FileSystemWatcher? _watcher;
    private PetConfig _config = new();
    private Picture? _activePicture;
    private string? _activeImagePath;
    private bool _inputActive;
    private bool _closed;

    public DesktopPetWindow(string configPath, int parentPid)
    {
        _configPath = configPath;
        _parentPid = parentPid;
        var configDirectory = Path.GetDirectoryName(configPath) ?? AppContext.BaseDirectory;
        _windowStatePath = Path.Combine(configDirectory, "window-state.json");

        Title = "冒险者公会 · 桌宠";
        SizeToContent = SizeToContent.WidthAndHeight;
        MinWidth = 0;
        MinHeight = 0;
        MaxWidth = 760;
        MaxHeight = 760;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        ShowInTaskbar = false;
        Topmost = true;
        ShowActivated = false;
        Opacity = 0;

        _root = new Grid
        {
            Background = Brushes.Transparent,
            Margin = new Thickness(4),
        };

        _layoutPanel = new StackPanel
        {
            Orientation = Orientation.Vertical,
            Background = Brushes.Transparent,
        };
        _root.Children.Add(_layoutPanel);

        _headerRow = new Grid
        {
            Background = Brushes.Transparent,
        };

        _bubbleText = new TextBlock
        {
            TextWrapping = TextWrapping.Wrap,
            TextAlignment = TextAlignment.Left,
            FontSize = 14,
            MaxWidth = 270,
        };
        _bubble = new Border
        {
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(16),
            Padding = new Thickness(14, 11, 14, 11),
            Child = _bubbleText,
        };
        _bubbleTail = new Polygon
        {
            Stretch = Stretch.Fill,
            Width = 18,
            Height = 12,
            StrokeThickness = 1,
        };
        _bubbleHost = new StackPanel
        {
            Orientation = Orientation.Vertical,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        };
        _bubbleHost.Children.Add(_bubble);
        _bubbleHost.Children.Add(_bubbleTail);

        _focusClockText = new TextBlock
        {
            Text = "⏱ 00:00",
            FontSize = 13,
            FontWeight = FontWeights.SemiBold,
            TextAlignment = TextAlignment.Center,
        };
        _focusClock = new Border
        {
            CornerRadius = new CornerRadius(999),
            BorderThickness = new Thickness(1),
            Padding = new Thickness(10, 7, 10, 7),
            Margin = new Thickness(8),
            HorizontalAlignment = HorizontalAlignment.Right,
            VerticalAlignment = VerticalAlignment.Top,
            Child = _focusClockText,
        };

        _imageViewport = new Grid
        {
            Width = 280,
            Height = 280,
            ClipToBounds = true,
            Background = Brushes.Transparent,
            Margin = new Thickness(8, 0, 8, 4),
        };

        _petImage = new Image
        {
            Stretch = Stretch.Uniform,
            HorizontalAlignment = HorizontalAlignment.Stretch,
            VerticalAlignment = VerticalAlignment.Stretch,
            RenderTransformOrigin = new Point(0.5, 0.5),
        };
        _imageViewport.Children.Add(_petImage);
        _imageViewport.SizeChanged += (_, _) => ApplyCurrentImagePlacement();

        _layoutPanel.Children.Add(_bubbleHost);
        _layoutPanel.Children.Add(_imageViewport);

        Content = _root;

        _root.MouseLeftButtonDown += (_, e) =>
        {
            if (e.LeftButton != MouseButtonState.Pressed) return;
            try
            {
                DragMove();
                SavePetWindowState();
            }
            catch (InvalidOperationException)
            {
                // Ignore a drag that lost capture while the window was moving.
            }
        };

        _graphCore = new GraphCore(1000, Dispatcher);

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

        _focusTimer = new DispatcherTimer
        {
            Interval = TimeSpan.FromSeconds(1),
        };
        _focusTimer.Tick += (_, _) => RefreshFocusClock();

        _inputHook = new GlobalInputActivityHook();
        _inputHook.ActivityChanged += active =>
        {
            Dispatcher.BeginInvoke(() =>
            {
                if (_inputActive == active) return;
                _inputActive = active;
                RefreshImage();
            });
        };

        Loaded += async (_, _) =>
        {
            RestorePetWindowState();
            StartConfigWatcher();
            _inputHook.Start();
            _parentTimer.Start();
            _deadlineTimer.Start();
            _focusTimer.Start();
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

        ApplyLayoutAndTheme();
        RefreshImage(force: true);
        RefreshBubble();
        RefreshFocusClock();
    }

    private void ApplyLayoutAndTheme()
    {
        var petScale = Math.Clamp(_config.PetScale, 0.5, 1.8);
        var bubbleScale = Math.Clamp(_config.BubbleScale, 0.65, 1.8);
        var clockScale = Math.Clamp(_config.FocusClockScale, 0.65, 1.8);
        var side = string.Equals(
            _config.BubblePosition,
            "side",
            StringComparison.OrdinalIgnoreCase
        );

        var petSize = 280 * petScale;
        _imageViewport.Width = petSize;
        _imageViewport.Height = petSize;
        _imageViewport.Margin = new Thickness(0);

        var background = BrushFromArgb(_config.BubbleBackgroundArgb, 0xFFF7F7F7);
        var foreground = BrushFromArgb(_config.BubbleForegroundArgb, 0xFF202020);
        var border = BrushFromArgb(_config.BubbleBorderArgb, 0x33202020);
        var accentColor = ColorFromArgb(_config.BubbleAccentArgb, 0xFF6C7A6B);

        _bubble.Background = background;
        _bubble.BorderBrush = border;
        _bubble.BorderThickness = new Thickness(Math.Max(1, bubbleScale));
        _bubble.CornerRadius = new CornerRadius(15 * bubbleScale);
        _bubble.Padding = new Thickness(
            13 * bubbleScale,
            9 * bubbleScale,
            13 * bubbleScale,
            9 * bubbleScale
        );
        _bubble.Margin = new Thickness(0);

        _bubbleText.Foreground = foreground;
        _bubbleText.FontSize = 14 * bubbleScale;

        _bubbleTail.Fill = background;
        _bubbleTail.Stroke = border;
        _bubbleTail.StrokeThickness = Math.Max(1, bubbleScale);

        _focusClock.Background = background;
        _focusClock.BorderBrush = border;
        _focusClock.BorderThickness = new Thickness(Math.Max(1, clockScale));
        _focusClock.CornerRadius = new CornerRadius(10 * clockScale);
        _focusClockText.Foreground = foreground;
        _focusClockText.FontSize = 13 * clockScale;
        _focusClock.Padding = new Thickness(
            10 * clockScale,
            7 * clockScale,
            10 * clockScale,
            7 * clockScale
        );
        _focusClock.HorizontalAlignment = HorizontalAlignment.Left;
        _focusClock.VerticalAlignment = VerticalAlignment.Top;
        _focusClock.Margin = new Thickness(
            5 * clockScale,
            Math.Max(12, petSize * 0.16),
            0,
            0
        );
        _focusClock.Effect = new DropShadowEffect
        {
            BlurRadius = 10 * clockScale,
            ShadowDepth = 2 * clockScale,
            Opacity = 0.14,
            Color = accentColor,
        };
        _bubble.Effect = new DropShadowEffect
        {
            BlurRadius = 14 * bubbleScale,
            ShadowDepth = 2 * bubbleScale,
            Opacity = 0.18,
            Color = accentColor,
        };

        _layoutPanel.Children.Clear();
        _layoutPanel.Orientation = Orientation.Vertical;
        _layoutPanel.HorizontalAlignment = HorizontalAlignment.Left;
        _layoutPanel.VerticalAlignment = VerticalAlignment.Top;

        _headerRow.Children.Clear();
        _headerRow.ColumnDefinitions.Clear();
        _headerRow.RowDefinitions.Clear();
        _bubbleHost.Children.Clear();

        if (side)
        {
            _headerRow.ColumnDefinitions.Add(
                new ColumnDefinition { Width = GridLength.Auto }
            );
            _headerRow.ColumnDefinitions.Add(
                new ColumnDefinition { Width = GridLength.Auto }
            );
            _headerRow.ColumnDefinitions.Add(
                new ColumnDefinition { Width = GridLength.Auto }
            );
            _headerRow.RowDefinitions.Add(
                new RowDefinition { Height = GridLength.Auto }
            );

            _bubbleHost.Orientation = Orientation.Horizontal;
            _bubbleHost.HorizontalAlignment = HorizontalAlignment.Right;
            _bubbleHost.VerticalAlignment = VerticalAlignment.Top;
            _bubbleHost.Margin = new Thickness(
                0,
                Math.Max(10, petSize * 0.12),
                0,
                0
            );

            _bubbleText.TextWrapping = TextWrapping.NoWrap;
            _bubbleText.TextAlignment = TextAlignment.Center;
            _bubbleText.MinWidth = 20 * bubbleScale;
            _bubbleText.MaxWidth = 32 * bubbleScale;
            _bubbleText.MinHeight = 150 * bubbleScale;
            _bubbleText.MaxHeight = Math.Max(180, petSize * 0.78);
            _bubble.MinWidth = 44 * bubbleScale;
            _bubble.MaxWidth = 62 * bubbleScale;
            _bubble.MinHeight = 185 * bubbleScale;
            _bubble.MaxHeight = Math.Max(210, petSize * 0.9);

            _bubbleTail.Width = 15 * bubbleScale;
            _bubbleTail.Height = 22 * bubbleScale;
            _bubbleTail.Points = new PointCollection
            {
                new Point(0, 0),
                new Point(15, 11),
                new Point(0, 22),
            };
            _bubbleTail.VerticalAlignment = VerticalAlignment.Top;
            _bubbleTail.HorizontalAlignment = HorizontalAlignment.Left;
            _bubbleTail.Margin = new Thickness(
                -1.5 * bubbleScale,
                48 * bubbleScale,
                0,
                0
            );

            _bubbleHost.Children.Add(_bubble);
            _bubbleHost.Children.Add(_bubbleTail);

            Grid.SetColumn(_bubbleHost, 0);
            Grid.SetRow(_bubbleHost, 0);
            Grid.SetColumn(_imageViewport, 1);
            Grid.SetRow(_imageViewport, 0);
            Grid.SetColumn(_focusClock, 2);
            Grid.SetRow(_focusClock, 0);

            _headerRow.Children.Add(_bubbleHost);
            _headerRow.Children.Add(_imageViewport);
            _headerRow.Children.Add(_focusClock);
        }
        else
        {
            _headerRow.ColumnDefinitions.Add(
                new ColumnDefinition { Width = GridLength.Auto }
            );
            _headerRow.ColumnDefinitions.Add(
                new ColumnDefinition { Width = GridLength.Auto }
            );
            _headerRow.RowDefinitions.Add(
                new RowDefinition { Height = GridLength.Auto }
            );
            _headerRow.RowDefinitions.Add(
                new RowDefinition { Height = GridLength.Auto }
            );

            _bubbleHost.Orientation = Orientation.Vertical;
            _bubbleHost.HorizontalAlignment = HorizontalAlignment.Center;
            _bubbleHost.VerticalAlignment = VerticalAlignment.Bottom;
            _bubbleHost.Margin = new Thickness(0, 0, 0, -1 * bubbleScale);

            _bubbleText.TextWrapping = TextWrapping.Wrap;
            _bubbleText.TextAlignment = TextAlignment.Left;
            _bubbleText.MinWidth = 170 * bubbleScale;
            _bubbleText.MaxWidth = Math.Max(220, petSize * 0.95);
            _bubbleText.MinHeight = 0;
            _bubbleText.MaxHeight = double.PositiveInfinity;
            _bubble.MinWidth = 190 * bubbleScale;
            _bubble.MaxWidth = Math.Max(250, petSize * 1.06);
            _bubble.MinHeight = 0;
            _bubble.MaxHeight = double.PositiveInfinity;

            _bubbleTail.Width = 22 * bubbleScale;
            _bubbleTail.Height = 14 * bubbleScale;
            _bubbleTail.Points = new PointCollection
            {
                new Point(0, 0),
                new Point(22, 0),
                new Point(11, 14),
            };
            _bubbleTail.HorizontalAlignment = HorizontalAlignment.Left;
            _bubbleTail.VerticalAlignment = VerticalAlignment.Top;
            _bubbleTail.Margin = new Thickness(
                38 * bubbleScale,
                -1.5 * bubbleScale,
                0,
                0
            );

            _bubbleHost.Children.Add(_bubble);
            _bubbleHost.Children.Add(_bubbleTail);

            Grid.SetColumn(_bubbleHost, 0);
            Grid.SetRow(_bubbleHost, 0);
            Grid.SetColumn(_imageViewport, 0);
            Grid.SetRow(_imageViewport, 1);
            Grid.SetColumn(_focusClock, 1);
            Grid.SetRow(_focusClock, 1);

            _headerRow.Children.Add(_bubbleHost);
            _headerRow.Children.Add(_imageViewport);
            _headerRow.Children.Add(_focusClock);
        }

        _layoutPanel.Children.Add(_headerRow);
    }

    private void RefreshFocusClock()
    {
        if (!DateTime.TryParse(_config.FocusStartedAt, out var startedAt))
        {
            _focusClockText.Text = "⏱ 00:00";
            return;
        }

        var start = startedAt.ToUniversalTime();
        var elapsed = DateTime.UtcNow - start;
        if (elapsed < TimeSpan.Zero) elapsed = TimeSpan.Zero;
        var totalHours = (int)Math.Floor(elapsed.TotalHours);
        _focusClockText.Text = totalHours > 0
            ? $"⏱ {totalHours:00}:{elapsed.Minutes:00}:{elapsed.Seconds:00}"
            : $"⏱ {elapsed.Minutes:00}:{elapsed.Seconds:00}";
    }

    private static SolidColorBrush BrushFromArgb(long value, long fallback)
    {
        return new SolidColorBrush(ColorFromArgb(value, fallback));
    }

    private static Color ColorFromArgb(long value, long fallback)
    {
        var raw = unchecked((uint)(value == 0 ? fallback : value));
        return Color.FromArgb(
            (byte)(raw >> 24),
            (byte)(raw >> 16),
            (byte)(raw >> 8),
            (byte)raw
        );
    }

    private void RefreshImage(bool force = false)
    {
        if (!IsUsableImage(_config.ImageA))
        {
            _activeImagePath = null;
            _activePicture?.Dispose();
            _activePicture = null;
            _petImage.Source = null;
            _petImage.Visibility = Visibility.Collapsed;
            _bubbleHost.Visibility = Visibility.Collapsed;
            Opacity = 0;
            if (IsVisible)
            {
                Hide();
            }
            return;
        }

        var useB = _inputActive && IsUsableImage(_config.ImageB);
        var path = useB ? _config.ImageB : _config.ImageA;
        var placement = useB ? _config.PlacementB : _config.PlacementA;
        ApplyImagePlacement(placement);

        if (!IsUsableImage(path))
        {
            _activeImagePath = null;
            _activePicture?.Dispose();
            _activePicture = null;
            _petImage.Source = null;
            _petImage.Visibility = Visibility.Collapsed;
            _bubbleHost.Visibility = Visibility.Collapsed;
            Opacity = 0;
            if (IsVisible)
            {
                Hide();
            }
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
            _activePicture?.Dispose();

            var picture = new Picture(
                _graphCore,
                path,
                new GraphInfo(
                    _inputActive ? "guild-input-active" : "guild-idle",
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
            Opacity = 1;
            if (!IsVisible)
            {
                Show();
            }
        }
        catch
        {
            _activeImagePath = null;
            _petImage.Source = null;
            _petImage.Visibility = Visibility.Collapsed;
            _bubbleHost.Visibility = Visibility.Collapsed;
            Opacity = 0;
            if (IsVisible)
            {
                Hide();
            }
        }

        RefreshBubble();
    }

    private void ApplyCurrentImagePlacement()
    {
        var useB = _inputActive && IsUsableImage(_config.ImageB);
        ApplyImagePlacement(useB ? _config.PlacementB : _config.PlacementA);
    }

    private void ApplyImagePlacement(PetPlacement? placement)
    {
        placement ??= new PetPlacement();
        var scale = Math.Clamp(placement.Scale, 0.35, 3.0);
        var offsetX = Math.Clamp(placement.OffsetX, -1.0, 1.0);
        var offsetY = Math.Clamp(placement.OffsetY, -1.0, 1.0);
        var width = Math.Max(1, _imageViewport.ActualWidth);
        var height = Math.Max(1, _imageViewport.ActualHeight);

        var transforms = new TransformGroup();
        transforms.Children.Add(new ScaleTransform(scale, scale));
        transforms.Children.Add(
            new TranslateTransform(
                offsetX * width / 2.0,
                offsetY * height / 2.0
            )
        );
        _petImage.RenderTransform = transforms;
    }

    private void RefreshBubble()
    {
        if (!IsUsableImage(_config.ImageA))
        {
            _bubbleHost.Visibility = Visibility.Collapsed;
            return;
        }

        string text;
        if (string.Equals(_config.TextMode, "custom", StringComparison.OrdinalIgnoreCase))
        {
            var custom = (_config.CustomText ?? string.Empty).Trim();
            text = custom.Length == 0 ? " " : custom;
        }
        else
        {
            var title = (_config.CurrentOrderTitle ?? string.Empty).Trim();
            if (title.Length == 0)
            {
                text = "当前没有在画订单";
            }
            else
            {
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

                text = details.Count == 0
                    ? title
                    : title + Environment.NewLine + string.Join(" · ", details);
            }
        }

        var side = string.Equals(
            _config.BubblePosition,
            "side",
            StringComparison.OrdinalIgnoreCase
        );
        _bubbleText.Text = side ? ToVerticalBubbleText(text) : text;
        _bubbleHost.Visibility = Visibility.Visible;
    }

    private static string ToVerticalBubbleText(string value)
    {
        var normalized = value
            .Replace("\r\n", "\n", StringComparison.Ordinal)
            .Replace('\r', '\n');
        var runes = new List<string>();
        foreach (var rune in normalized.EnumerateRunes())
        {
            var token = rune.ToString();
            if (token == "\n")
            {
                if (runes.Count == 0 || runes[^1] != string.Empty)
                {
                    runes.Add(string.Empty);
                }
                continue;
            }
            if (char.IsWhiteSpace(token, 0))
            {
                continue;
            }
            runes.Add(token);
        }

        const int maxCharacters = 24;
        if (runes.Count > maxCharacters)
        {
            runes = runes.Take(maxCharacters - 1).ToList();
            runes.Add("…");
        }
        return string.Join(Environment.NewLine, runes);
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

    private void RestorePetWindowState()
    {
        try
        {
            if (File.Exists(_windowStatePath))
            {
                var state = JsonSerializer.Deserialize<PetWindowState>(
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
        var fallbackWidth = ActualWidth > 0 && !double.IsNaN(ActualWidth)
            ? ActualWidth
            : 320;
        var fallbackHeight = ActualHeight > 0 && !double.IsNaN(ActualHeight)
            ? ActualHeight
            : 390;
        Left = SystemParameters.WorkArea.Right - fallbackWidth - 36;
        Top = SystemParameters.WorkArea.Bottom - fallbackHeight - 36;
    }

    private bool IsVisiblePosition(double left, double top)
    {
        var windowWidth = ActualWidth > 0 && !double.IsNaN(ActualWidth)
            ? ActualWidth
            : 320;
        var windowHeight = ActualHeight > 0 && !double.IsNaN(ActualHeight)
            ? ActualHeight
            : 390;
        var right = left + Math.Max(120, windowWidth);
        var bottom = top + Math.Max(120, windowHeight);
        var virtualRight = SystemParameters.VirtualScreenLeft + SystemParameters.VirtualScreenWidth;
        var virtualBottom = SystemParameters.VirtualScreenTop + SystemParameters.VirtualScreenHeight;

        return right >= SystemParameters.VirtualScreenLeft + 40 &&
               left <= virtualRight - 40 &&
               bottom >= SystemParameters.VirtualScreenTop + 40 &&
               top <= virtualBottom - 40;
    }

    private void SavePetWindowState()
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
                JsonSerializer.Serialize(new PetWindowState(Left, Top))
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
        _focusTimer.Stop();

        if (_watcher is not null)
        {
            _watcher.EnableRaisingEvents = false;
            _watcher.Dispose();
            _watcher = null;
        }

        _inputHook.Dispose();
        _activePicture?.Dispose();
        _activePicture = null;
        _graphCore.Dispose();
    }

    private sealed record PetWindowState(double Left, double Top);

    private sealed class PetConfig
    {
        public bool Enabled { get; set; }
        public string? ImageA { get; set; }
        public string? ImageB { get; set; }
        public PetPlacement PlacementA { get; set; } = new();
        public PetPlacement PlacementB { get; set; } = new();
        public string BubblePosition { get; set; } = "above";
        public double PetScale { get; set; } = 1;
        public double BubbleScale { get; set; } = 1;
        public double FocusClockScale { get; set; } = 1;
        public long BubbleBackgroundArgb { get; set; } = 0xFFF7F7F7;
        public long BubbleForegroundArgb { get; set; } = 0xFF202020;
        public long BubbleBorderArgb { get; set; } = 0x33202020;
        public long BubbleAccentArgb { get; set; } = 0xFF6C7A6B;
        public string? FocusStartedAt { get; set; }
        public string? TextMode { get; set; }
        public string? CustomText { get; set; }
        public string? CurrentOrderTitle { get; set; }
        public string? CurrentOrderNode { get; set; }
        public string? CurrentOrderDeadline { get; set; }
    }

    private sealed class PetPlacement
    {
        public double Scale { get; set; } = 1;
        public double OffsetX { get; set; }
        public double OffsetY { get; set; }
    }
}

internal sealed class GlobalInputActivityHook : IDisposable
{
    private const int WhKeyboardLl = 13;
    private const int WhMouseLl = 14;

    private const int WmKeyDown = 0x0100;
    private const int WmKeyUp = 0x0101;
    private const int WmSysKeyDown = 0x0104;
    private const int WmSysKeyUp = 0x0105;

    private const int WmLButtonDown = 0x0201;
    private const int WmLButtonUp = 0x0202;
    private const int WmRButtonDown = 0x0204;
    private const int WmRButtonUp = 0x0205;
    private const int WmMButtonDown = 0x0207;
    private const int WmMButtonUp = 0x0208;

    private readonly HashSet<int> _pressedKeys = new();
    private readonly HashSet<int> _pressedMouseButtons = new();
    private readonly LowLevelKeyboardProc _keyboardCallback;
    private readonly LowLevelMouseProc _mouseCallback;

    private IntPtr _keyboardHook;
    private IntPtr _mouseHook;
    private bool _active;

    public GlobalInputActivityHook()
    {
        _keyboardCallback = KeyboardHookCallback;
        _mouseCallback = MouseHookCallback;
    }

    public event Action<bool>? ActivityChanged;

    public void Start()
    {
        using var process = Process.GetCurrentProcess();
        using var module = process.MainModule;
        var moduleHandle = GetModuleHandle(module?.ModuleName);

        if (_keyboardHook == IntPtr.Zero)
        {
            _keyboardHook = SetWindowsHookExKeyboard(
                WhKeyboardLl,
                _keyboardCallback,
                moduleHandle,
                0
            );
        }

        if (_mouseHook == IntPtr.Zero)
        {
            _mouseHook = SetWindowsHookExMouse(
                WhMouseLl,
                _mouseCallback,
                moduleHandle,
                0
            );
        }
    }

    public void Dispose()
    {
        if (_keyboardHook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_keyboardHook);
            _keyboardHook = IntPtr.Zero;
        }

        if (_mouseHook != IntPtr.Zero)
        {
            UnhookWindowsHookEx(_mouseHook);
            _mouseHook = IntPtr.Zero;
        }

        _pressedKeys.Clear();
        _pressedMouseButtons.Clear();
        SetActive(false);
    }

    private IntPtr KeyboardHookCallback(int code, IntPtr wParam, IntPtr lParam)
    {
        if (code >= 0)
        {
            var message = wParam.ToInt32();
            var data = Marshal.PtrToStructure<KbdLlHookStruct>(lParam);

            if (message is WmKeyDown or WmSysKeyDown)
            {
                _pressedKeys.Add(data.VirtualKeyCode);
                RefreshActiveState();
            }
            else if (message is WmKeyUp or WmSysKeyUp)
            {
                _pressedKeys.Remove(data.VirtualKeyCode);
                RefreshActiveState();
            }
        }

        return CallNextHookEx(_keyboardHook, code, wParam, lParam);
    }

    private IntPtr MouseHookCallback(int code, IntPtr wParam, IntPtr lParam)
    {
        if (code >= 0)
        {
            switch (wParam.ToInt32())
            {
                case WmLButtonDown:
                    _pressedMouseButtons.Add(1);
                    RefreshActiveState();
                    break;
                case WmLButtonUp:
                    _pressedMouseButtons.Remove(1);
                    RefreshActiveState();
                    break;
                case WmRButtonDown:
                    _pressedMouseButtons.Add(2);
                    RefreshActiveState();
                    break;
                case WmRButtonUp:
                    _pressedMouseButtons.Remove(2);
                    RefreshActiveState();
                    break;
                case WmMButtonDown:
                    _pressedMouseButtons.Add(3);
                    RefreshActiveState();
                    break;
                case WmMButtonUp:
                    _pressedMouseButtons.Remove(3);
                    RefreshActiveState();
                    break;
            }
        }

        return CallNextHookEx(_mouseHook, code, wParam, lParam);
    }

    private void RefreshActiveState()
    {
        SetActive(_pressedKeys.Count > 0 || _pressedMouseButtons.Count > 0);
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
    private delegate IntPtr LowLevelMouseProc(int code, IntPtr wParam, IntPtr lParam);

    [DllImport("user32.dll", SetLastError = true, EntryPoint = "SetWindowsHookExW")]
    private static extern IntPtr SetWindowsHookExKeyboard(
        int idHook,
        LowLevelKeyboardProc callback,
        IntPtr module,
        uint threadId
    );

    [DllImport("user32.dll", SetLastError = true, EntryPoint = "SetWindowsHookExW")]
    private static extern IntPtr SetWindowsHookExMouse(
        int idHook,
        LowLevelMouseProc callback,
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
