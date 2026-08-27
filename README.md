# AudioBridge

AudioBridge sends Windows 11 system audio over the local Wi-Fi network to a native iPhone receiver. On an iPhone SE (3rd generation), the native app plays through the active iOS output route, including connected Lightning EarPods.

This repository contains:

- a Windows 11 WPF sender using WASAPI loopback capture through NAudio;
- a native SwiftUI iPhone receiver using Network.framework and AVAudioEngine;
- an authenticated, low-overhead UDP PCM protocol;
- protocol unit tests and free cloud build workflows;
- Windows/AltStore installation instructions.

## Current verification status

The Windows solution builds with zero warnings and all six automated tests pass, including a live local UDP pairing/audio test and a byte-for-byte Swift/C# protocol vector. The iOS project and tests are ready for XcodeGen, but an iPhone build cannot be compiled on Windows; the included macOS GitHub Actions workflow performs that build and packages an unsigned IPA. Real iPhone testing is still required before calling the app production-ready.

## Expected latency on your Wi-Fi

Your approximately 33 Mbps down / 34 Mbps up connection is more than enough because AudioBridge uses the **local network**, not internet upload/download speed. The raw stream is about 1.6 Mbps. Wi-Fi congestion, router isolation, band, signal quality, and the Windows/iPhone audio buffers matter more than the speed-test result.

Reasonable first-version targets on a clean local network are:

| Buffer mode | Likely end-to-end delay | Use |
|---|---:|---|
| Low Delay | 55–100 ms | Clean 5 GHz Wi-Fi |
| Balanced | 75–130 ms | Recommended for videos |
| Stable | 115–180 ms | Busy or weak Wi-Fi |

These are engineering estimates, not measured promises. The iPhone screen reports buffer/jitter information, but final latency must be measured on the physical device. Windows video is not delayed automatically, so the sound may trail the picture slightly.

## First end-to-end test

1. Build/install the iPhone IPA using [INSTALL-IOS-WINDOWS.md](INSTALL-IOS-WINDOWS.md).
2. On Windows, run `AudioBridge.Sender.exe`. Allow private-network access if Windows Firewall asks.
3. Put the laptop and iPhone on the same Wi-Fi. Guest Wi-Fi or AP/client isolation must be off.
4. Connect the Lightning EarPods to the iPhone before connecting AudioBridge.
5. Enter the Windows address, port, and six-digit code in the iPhone app, then tap **Connect**.
6. In Windows AudioBridge, click **Start test tone**. Confirm the iPhone route card names the EarPods and that the tone is clean.
7. Stop the tone and click **Stream system audio**, then play a YouTube video.
8. Try Netflix only after YouTube works; see the DRM note below.

If the phone cannot connect, run `scripts/add-firewall-rule.ps1` from an Administrator PowerShell. It adds one inbound UDP 43120 rule for **Private** networks only.

## Build Windows locally

Install the .NET 8 SDK, then run:

```powershell
./scripts/build-windows.ps1
```

The self-contained x64 app is written to `artifacts/windows-x64`. It does not require a separate .NET installation on the target PC.

## Important limitations

- Protocol v1 is paired but not encrypted. Use it only on a trusted local network; do not port-forward UDP 43120.
- WASAPI loopback normally captures browser, YouTube, music, and ordinary media-player output. Content using the Windows protected media path can block loopback capture. AudioBridge does not and will not bypass DRM; Netflix behavior must be tested with the exact browser/app and playback mode.
- Exclusive-mode audio applications may bypass or interfere with the default shared Windows output.
- The iPhone app is designed primarily for foreground use. Background audio mode is declared, but iOS can still suspend networking in some conditions and it needs physical testing.
- A free Apple ID sideload expires after seven days and must be refreshed through AltStore/AltServer.
- AudioBridge v1 does not use the EarPods microphone and does not provide call/headset input back to Windows.

## Architecture

```text
Windows default output
       ↓ WASAPI loopback
48 kHz stereo PCM → 5 ms UDP packets → jitter buffer → AVAudioEngine
                                                        ↓
                                              iPhone output route
                                                        ↓
                                                Lightning EarPods
```

The detailed packet contract is in [protocol/README.md](protocol/README.md).

## Premium roadmap

A more polished second version is feasible. High-value upgrades are automatic discovery and QR pairing, adaptive jitter buffering, Opus compression, authenticated encryption, clock-drift correction, interruption/reconnect handling, selectable Windows output devices, and measured round-trip latency. A separate browser extension or compatible video player could delay video to match audio; Netflix cannot be universally synchronized from an ordinary sender app.

