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
using System.Windows.Media.Imaging;
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
    private readonly StackPanel _thoughtDots;
    private readonly Ellipse _thoughtDotLarge;
    private readonly Ellipse _thoughtDotSmall;
    private readonly StackPanel _bubbleContent;
    private readonly Image _bubbleArt;
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
    private readonly GlobalInputActivityMonitor _inputHook;
    private readonly GraphCore _graphCore;

    private FileSystemWatcher? _watcher;
    private PetConfig _config = new();
    private Picture? _activePicture;
    private string? _activeImagePath;
    private string? _bubbleArtPath;
    private DateTime _bubbleArtChangedAt;
    private ImageSource? _bubbleArtCache;
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
        MaxWidth = 1400;
        MaxHeight = 1400;
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
        _thoughtDotLarge = new Ellipse { Width = 10, Height = 10 };
        _thoughtDotSmall = new Ellipse { Width = 5, Height = 5 };
        _thoughtDots = new StackPanel { Orientation = Orientation.Vertical };
        _thoughtDots.Children.Add(_thoughtDotLarge);
        _thoughtDots.Children.Add(_thoughtDotSmall);
        _bubbleArt = new Image
        {
            Width = 88,
            MaxHeight = 100,
            Stretch = Stretch.Uniform,
            HorizontalAlignment = HorizontalAlignment.Center,
            Margin = new Thickness(0, 0, 0, 4),
        };
        _bubbleContent = new StackPanel { Orientation = Orientation.Vertical };
        _bubble.Child = null;
        _bubbleContent.Children.Add(_bubbleText);
        _bubble.Child = _bubbleContent;
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

        _inputHook = new GlobalInputActivityMonitor();
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

        try
        {
            ApplyLayoutAndTheme();
            RefreshImage(force: true);
            RefreshBubble();
            RefreshFocusClock();
        }
        catch (ArgumentException)
        {
            // A malformed or mid-write layout value must never terminate the
            // optional desktop-pet host. Keep the last valid frame instead.
        }
        catch (InvalidOperationException)
        {
            // WPF can reject a layout mutation while it is re-measuring after
            // a config reload. The next watcher tick will retry safely.
        }
    }

    private void ApplyLayoutAndTheme()
    {
        var petScale = Math.Clamp(_config.PetScale, 0.5, 1.8);
        var bubbleTextScale = Math.Clamp(
            _config.BubbleTextScale ?? _config.BubbleScale,
            0.65,
            1.8
        );
        var clockScale = Math.Clamp(_config.FocusClockScale, 0.65, 1.8);
        var side = string.Equals(
            _config.BubblePosition,
            "side",
            StringComparison.OrdinalIgnoreCase
        );

        var thought = string.Equals(_config.BubbleStyle, "thought", StringComparison.OrdinalIgnoreCase);
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
        _bubble.BorderThickness = new Thickness(1);
        _bubble.CornerRadius = new CornerRadius(thought ? 40 : 15);
        _bubble.Padding = new Thickness(13, 9, 13, 9);
        _bubble.Margin = new Thickness(0);
        _bubble.MinWidth = 0;
        _bubble.MinHeight = 0;
        _bubble.MaxWidth = double.PositiveInfinity;
        _bubble.MaxHeight = double.PositiveInfinity;

        _bubbleText.Foreground = foreground;
        _bubbleText.FontSize = 14 * bubbleTextScale;

        _bubbleTail.Fill = background;
        _bubbleTail.Stroke = Brushes.Transparent;
        _bubbleTail.StrokeThickness = 0;
        _thoughtDotLarge.Fill = background;
        _thoughtDotLarge.Stroke = border;
        _thoughtDotLarge.StrokeThickness = 1;
        _thoughtDotSmall.Fill = background;
        _thoughtDotSmall.Stroke = border;
        _thoughtDotSmall.StrokeThickness = 1;

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
        _focusClock.Visibility = _config.FocusEnabled
            ? Visibility.Visible
            : Visibility.Collapsed;
        _focusClock.Effect = new DropShadowEffect
        {
            BlurRadius = 10 * clockScale,
            ShadowDepth = 2 * clockScale,
            Opacity = 0.14,
            Color = accentColor,
        };
        _bubble.Effect = new DropShadowEffect
        {
            BlurRadius = 14,
            ShadowDepth = 2,
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
            _bubbleHost.VerticalAlignment = VerticalAlignment.Center;
            _bubbleHost.Margin = new Thickness(0);

            _bubbleText.TextWrapping = TextWrapping.NoWrap;
            _bubbleText.TextAlignment = TextAlignment.Center;
            _bubbleText.MinWidth = 0;
            _bubbleText.MaxWidth = double.PositiveInfinity;
            _bubbleText.MinHeight = 0;
            _bubbleText.MaxHeight = double.PositiveInfinity;

            _bubbleTail.Width = 15;
            _bubbleTail.Height = 22;
            _bubbleTail.Points = new PointCollection
            {
                new Point(0, 0),
                new Point(15, 11),
                new Point(0, 22),
            };
            _bubbleTail.VerticalAlignment = VerticalAlignment.Top;
            _bubbleTail.HorizontalAlignment = HorizontalAlignment.Left;
            _bubbleTail.Margin = new Thickness(-1.5, 34, 0, 0);

            _bubbleHost.Children.Add(_bubble);
            if (thought)
            {
                _thoughtDots.Orientation = Orientation.Horizontal;
                _thoughtDots.VerticalAlignment = VerticalAlignment.Center;
                _thoughtDots.Margin = new Thickness(1, 16, 0, 0);
                _thoughtDotLarge.Margin = new Thickness(0, 0, 5, 0);
                _thoughtDotSmall.Margin = new Thickness(0, 12, 0, 0);
                _bubbleHost.Children.Add(_thoughtDots);
            }
            else
            {
                _bubbleHost.Children.Add(_bubbleTail);
            }

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
            _bubbleHost.Margin = new Thickness(0, 0, 0, -1);
            _bubbleHost.Width = double.NaN;

            _bubbleText.TextWrapping = TextWrapping.Wrap;
            _bubbleText.TextAlignment = TextAlignment.Left;
            _bubbleText.MinWidth = 0;
            _bubbleText.MaxWidth = Math.Clamp(petSize * 0.95, 180, 320);
            _bubbleText.MinHeight = 0;
            _bubbleText.MaxHeight = double.PositiveInfinity;
            _bubble.MaxWidth = _bubbleText.MaxWidth + 26;

            _bubbleTail.Width = 22;
            _bubbleTail.Height = 14;
            _bubbleTail.Points = new PointCollection
            {
                new Point(0, 0),
                new Point(22, 0),
                new Point(11, 14),
            };
            _bubbleTail.HorizontalAlignment = HorizontalAlignment.Left;
            _bubbleTail.VerticalAlignment = VerticalAlignment.Top;
            _bubbleTail.Margin = new Thickness(38, -1.5, 0, 0);

            _bubbleHost.Children.Add(_bubble);
            if (thought)
            {
                _thoughtDots.Orientation = Orientation.Vertical;
                _thoughtDots.HorizontalAlignment = HorizontalAlignment.Left;
                _thoughtDots.Margin = new Thickness(36, 0, 0, 0);
                _thoughtDotLarge.Margin = new Thickness(0, -1, 0, 3);
                _thoughtDotSmall.Margin = new Thickness(13, 0, 0, 0);
                _bubbleHost.Children.Add(_thoughtDots);
            }
            else
            {
                _bubbleHost.Children.Add(_bubbleTail);
            }

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

        ApplyOverlayOffsets(petSize);
        _layoutPanel.Children.Add(_headerRow);
    }

    private void ApplyOverlayOffsets(double petSize)
    {
        var bubbleOffset = string.Equals(
            _config.BubblePosition,
            "side",
            StringComparison.OrdinalIgnoreCase
        )
            ? _config.BubbleSideOffset
            : _config.BubbleAboveOffset;
        bubbleOffset ??= new PetOverlayOffset();
        var clockOffset = _config.FocusClockOffset ?? new PetOverlayOffset();

        var bubbleX = Math.Clamp(bubbleOffset.X, -0.85, 0.85) * petSize;
        var bubbleY = Math.Clamp(bubbleOffset.Y, -0.85, 0.85) * petSize;
        var clockX = Math.Clamp(clockOffset.X, -0.85, 0.85) * petSize;
        var clockY = Math.Clamp(clockOffset.Y, -0.85, 0.85) * petSize;

        _bubbleHost.RenderTransform = new TranslateTransform(bubbleX, bubbleY);
        _focusClock.RenderTransform = new TranslateTransform(clockX, clockY);

        var leftPad = Math.Max(0, Math.Max(-bubbleX, -clockX));
        var topPad = Math.Max(0, Math.Max(-bubbleY, -clockY));
        var rightPad = Math.Max(0, Math.Max(bubbleX, clockX));
        var bottomPad = Math.Max(0, Math.Max(bubbleY, clockY));
        _root.Margin = new Thickness(
            4 + leftPad,
            4 + topPad,
            4 + rightPad,
            4 + bottomPad
        );
    }

    private void RefreshFocusClock()
    {
        if (!_config.FocusEnabled)
        {
            _focusClock.Visibility = Visibility.Collapsed;
            return;
        }
        _focusClock.Visibility = Visibility.Visible;
        if (!DateTime.TryParse(_config.FocusStartedAt, out var startedAt))
        {
            _focusClockText.Text = "⏱ 00:00:00";
            return;
        }

        var start = startedAt.ToUniversalTime();
        var elapsed = DateTime.UtcNow - start;
        if (elapsed < TimeSpan.Zero) elapsed = TimeSpan.Zero;
        var totalHours = (int)Math.Floor(elapsed.TotalHours);
        _focusClockText.Text =
            $"⏱ {totalHours:00}:{elapsed.Minutes:00}:{elapsed.Seconds:00}";
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
        _bubbleContent.Children.Clear();
        var art = LoadBubbleArt(_config.BubbleImage);
        if (art is not null)
        {
            _bubbleArt.Source = art;
            _bubbleContent.Children.Add(_bubbleArt);
        }
        else
        {
            _bubbleArt.Source = null;
        }
        if (side)
        {
            _bubbleContent.Children.Add(BuildVerticalBubbleContent(text));
        }
        else
        {
            _bubbleText.Text = text;
            _bubbleContent.Children.Add(_bubbleText);
        }
        _bubbleHost.Visibility = Visibility.Visible;
    }

    private ImageSource? LoadBubbleArt(string? path)
    {
        if (!IsUsableImage(path))
        {
            _bubbleArtPath = null;
            _bubbleArtCache = null;
            return null;
        }
        try
        {
            var fullPath = Path.GetFullPath(path!);
            var changedAt = File.GetLastWriteTimeUtc(fullPath);
            if (string.Equals(_bubbleArtPath, fullPath, StringComparison.OrdinalIgnoreCase)
                && _bubbleArtChangedAt == changedAt) return _bubbleArtCache;

            // Keep transparency; decode once without locking the source PNG.
            using var stream = File.OpenRead(fullPath);
            var bitmap = new BitmapImage();
            bitmap.BeginInit();
            bitmap.CacheOption = BitmapCacheOption.OnLoad;
            bitmap.DecodePixelWidth = 192;
            bitmap.StreamSource = stream;
            bitmap.EndInit();
            bitmap.Freeze();
            _bubbleArtCache = bitmap;
            _bubbleArtPath = fullPath;
            _bubbleArtChangedAt = changedAt;
            return bitmap;
        }
        catch (IOException) { return null; }
        catch (ArgumentException) { return null; }
        catch (NotSupportedException) { return null; }
    }

    private UIElement BuildVerticalBubbleContent(string value)
    {
        var normalized = value
            .Replace("\r\n", "\n", StringComparison.Ordinal)
            .Replace('\r', '\n');
        var runes = new List<string>();
        foreach (var rune in normalized.EnumerateRunes())
        {
            var token = rune.ToString();
            if (token == "\n" || char.IsWhiteSpace(token, 0))
            {
                continue;
            }
            runes.Add(token);
        }

        const int rowsPerColumn = 14;
        const int maxColumns = 4;
        const int maxCharacters = rowsPerColumn * maxColumns;
        if (runes.Count > maxCharacters)
        {
            runes = runes.Take(maxCharacters - 1).ToList();
            runes.Add("…");
        }

        var textScale = Math.Clamp(
            _config.BubbleTextScale ?? _config.BubbleScale,
            0.65,
            1.8
        );
        var characterCount = Math.Max(1, runes.Count);
        var columns = Math.Max(
            1,
            (int)Math.Ceiling(characterCount / (double)rowsPerColumn)
        );
        var rows = Math.Min(rowsPerColumn, characterCount);
        var cellWidth = 23 * textScale;
        var cellHeight = 20 * textScale;

        var grid = new Grid
        {
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
        };

        for (var column = 0; column < columns; column++)
        {
            grid.ColumnDefinitions.Add(
                new ColumnDefinition { Width = new GridLength(cellWidth) }
            );
        }
        for (var row = 0; row < rows; row++)
        {
            grid.RowDefinitions.Add(
                new RowDefinition { Height = new GridLength(cellHeight) }
            );
        }

        for (var index = 0; index < runes.Count; index++)
        {
            var logicalColumn = index / rowsPerColumn;
            var row = index % rowsPerColumn;
            var visualColumn = columns - 1 - logicalColumn;
            var cell = new TextBlock
            {
                Text = runes[index],
                Foreground = _bubbleText.Foreground,
                FontFamily = _bubbleText.FontFamily,
                FontSize = 14 * textScale,
                FontWeight = _bubbleText.FontWeight,
                TextAlignment = TextAlignment.Center,
                HorizontalAlignment = HorizontalAlignment.Stretch,
                VerticalAlignment = VerticalAlignment.Center,
                LineHeight = cellHeight,
            };
            Grid.SetColumn(cell, visualColumn);
            Grid.SetRow(cell, row);
            grid.Children.Add(cell);
        }

        return grid;
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
        public string BubbleStyle { get; set; } = "speech";
        public string? BubbleImage { get; set; }
        public double PetScale { get; set; } = 1;
        public double BubbleScale { get; set; } = 1;
        public double? BubbleTextScale { get; set; }
        public double FocusClockScale { get; set; } = 1;
        public PetOverlayOffset BubbleAboveOffset { get; set; } = new();
        public PetOverlayOffset BubbleSideOffset { get; set; } = new();
        public PetOverlayOffset FocusClockOffset { get; set; } = new();
        public bool FocusEnabled { get; set; } = true;
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

    private sealed class PetOverlayOffset
    {
        public double X { get; set; }
        public double Y { get; set; }
    }
}

// Global WH_KEYBOARD_LL / WH_MOUSE_LL hooks can stall input system-wide
// if screenshot software blocks the installing WPF UI thread.
// Polling does not intercept input and survives lost key-up events.
internal sealed class GlobalInputActivityMonitor : IDisposable
{
    private readonly DispatcherTimer _timer;
    private DateTime _holdUntil = DateTime.MinValue;
    private bool _active;

    public GlobalInputActivityMonitor()
    {
        _timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(40) };
        _timer.Tick += (_, _) => Poll();
    }

    public event Action<bool>? ActivityChanged;

    public void Start() => _timer.Start();

    private void Poll()
    {
        var pressed = false;
        for (var key = 0x08; key <= 0xFE; key++)
        {
            if ((GetAsyncKeyState(key) & 0x8000) == 0) continue;
            pressed = true;
            break;
        }
        if (!pressed)
        {
            for (var button = 0x01; button <= 0x06; button++)
            {
                if ((GetAsyncKeyState(button) & 0x8000) == 0) continue;
                pressed = true;
                break;
            }
        }

        // Brief hold catches taps; absent an input, always fall back to A.
        if (pressed) _holdUntil = DateTime.UtcNow.AddMilliseconds(120);
        var active = DateTime.UtcNow < _holdUntil;
        if (_active == active) return;
        _active = active;
        ActivityChanged?.Invoke(active);
    }

    public void Dispose()
    {
        _timer.Stop();
        _holdUntil = DateTime.MinValue;
        _active = false;
    }

    [DllImport("user32.dll")]
    private static extern short GetAsyncKeyState(int virtualKey);
}
