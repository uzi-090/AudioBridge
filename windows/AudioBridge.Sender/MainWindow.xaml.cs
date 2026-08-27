using System.Net;
using System.Windows;
using System.Windows.Media;
using System.Windows.Threading;
using AudioBridge.Protocol;
using AudioBridge.Sender.Networking;
using AudioBridge.Sender.Services;
using AudioBridge.Sender.Utilities;

namespace AudioBridge.Sender;

public partial class MainWindow : Window
{
    private readonly PairingServer _server = new();
    private readonly StreamingCoordinator _streaming;
    private readonly DispatcherTimer _metricsTimer;
    private readonly string _localAddress;
    private bool _closing;

    public MainWindow()
    {
        InitializeComponent();
        _streaming = new StreamingCoordinator(_server);
        _localAddress = NetworkAddressResolver.GetPreferredLocalAddress();
        _metricsTimer = new DispatcherTimer(TimeSpan.FromMilliseconds(250), DispatcherPriority.Background, UpdateMetrics, Dispatcher);

        _server.ClientPaired += ServerOnClientPaired;
        _server.ClientDisconnected += ServerOnClientDisconnected;
        _server.Log += AddLog;
        _streaming.Log += AddLog;

        Loaded += MainWindow_OnLoaded;
        Closed += MainWindow_OnClosed;
        RefreshConnectionDetails();
    }

    private void MainWindow_OnLoaded(object sender, RoutedEventArgs eventArgs)
    {
        try
        {
            _server.Start();
            _metricsTimer.Start();
            AddLog("Ready. Connect the iPhone, then start the test tone.");
        }
        catch (Exception exception)
        {
            AddLog($"Could not start network listener: {exception.Message}");
            MessageBox.Show(
                this,
                $"AudioBridge could not listen on UDP port {ProtocolConstants.DefaultPort}.\n\n{exception.Message}",
                "AudioBridge network error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
        }
    }

    private async void TestToneButton_OnClick(object sender, RoutedEventArgs eventArgs) =>
        await StartStreamingAsync(StreamSource.TestTone);

    private async void SystemAudioButton_OnClick(object sender, RoutedEventArgs eventArgs) =>
        await StartStreamingAsync(StreamSource.SystemAudio);

    private async void StopButton_OnClick(object sender, RoutedEventArgs eventArgs)
    {
        await _streaming.StopAsync();
        SetStreamingButtons(StreamSource.None);
    }

    private async Task StartStreamingAsync(StreamSource source)
    {
        SetControlsEnabled(false);
        try
        {
            await _streaming.StartAsync(source);
            SetStreamingButtons(source);
        }
        catch (Exception exception)
        {
            AddLog($"Could not start audio: {exception.Message}");
            MessageBox.Show(
                this,
                exception.Message,
                "AudioBridge audio error",
                MessageBoxButton.OK,
                MessageBoxImage.Error);
            SetStreamingButtons(StreamSource.None);
        }
        finally
        {
            SetControlsEnabled(true);
        }
    }

    private void CopyDetailsButton_OnClick(object sender, RoutedEventArgs eventArgs)
    {
        var details = $"Address: {_localAddress}\nPort: {ProtocolConstants.DefaultPort}\nPairing code: {_server.PairingCode}";
        Clipboard.SetText(details);
        AddLog("Connection details copied to the clipboard.");
    }

    private void NewCodeButton_OnClick(object sender, RoutedEventArgs eventArgs)
    {
        _server.RegeneratePairingCode();
        RefreshConnectionDetails();
        ShowWaitingState();
    }

    private void ServerOnClientPaired(IPEndPoint endpoint) => Dispatcher.InvokeAsync(() =>
    {
        HeaderStatusDot.Fill = FindBrush("SuccessBrush", Brushes.MediumSpringGreen);
        HeaderStatusText.Text = "iPhone connected";
        ConnectionStatusText.Text = "Connected";
        ConnectionDetailText.Text = $"Receiving device: {endpoint.Address}";
    });

    private void ServerOnClientDisconnected() => Dispatcher.InvokeAsync(ShowWaitingState);

    private void ShowWaitingState()
    {
        HeaderStatusDot.Fill = FindBrush("TextSecondaryBrush", Brushes.Gray);
        HeaderStatusText.Text = "Waiting for iPhone";
        ConnectionStatusText.Text = "No iPhone connected";
        ConnectionDetailText.Text = "Start the iPhone app and enter the details above.";
    }

    private void RefreshConnectionDetails()
    {
        PairingCodeText.Text = _server.PairingCode;
        AddressText.Text = _localAddress;
        PortText.Text = ProtocolConstants.DefaultPort.ToString();
    }

    private void AddLog(string message) => Dispatcher.InvokeAsync(() =>
    {
        LogList.Items.Add($"{DateTime.Now:HH:mm:ss}  {message}");
        while (LogList.Items.Count > 100)
        {
            LogList.Items.RemoveAt(0);
        }

        LogList.ScrollIntoView(LogList.Items[^1]);
    });

    private void UpdateMetrics(object? sender, EventArgs eventArgs)
    {
        var metrics = _streaming.Metrics;
        SourceText.Text = metrics.Source switch
        {
            StreamSource.SystemAudio => "System audio",
            StreamSource.TestTone => "Test tone",
            _ => "Stopped",
        };
        PacketsText.Text = metrics.PacketsSent.ToString("N0");
        BytesText.Text = FormatBytes(metrics.BytesSent);
        PeakMeter.Value = metrics.PeakLevel;
    }

    private void SetStreamingButtons(StreamSource source)
    {
        TestToneButton.IsEnabled = source != StreamSource.TestTone;
        SystemAudioButton.IsEnabled = source != StreamSource.SystemAudio;
        StopButton.IsEnabled = source != StreamSource.None;
    }

    private void SetControlsEnabled(bool enabled)
    {
        TestToneButton.IsEnabled = enabled;
        SystemAudioButton.IsEnabled = enabled;
        StopButton.IsEnabled = enabled && _streaming.Source != StreamSource.None;
    }

    private Brush FindBrush(string key, Brush fallback) =>
        TryFindResource(key) as Brush ?? fallback;

    private static string FormatBytes(ulong bytes)
    {
        if (bytes >= 1_048_576)
        {
            return $"{bytes / 1_048_576.0:F1} MB";
        }

        return $"{bytes / 1024.0:F1} KB";
    }

    private async void MainWindow_OnClosed(object? sender, EventArgs eventArgs)
    {
        if (_closing)
        {
            return;
        }

        _closing = true;
        _metricsTimer.Stop();
        await _streaming.DisposeAsync();
        await _server.DisposeAsync();
    }
}
