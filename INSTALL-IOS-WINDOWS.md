# Build and install the iPhone app from Windows

You do not need to own a Mac. The practical free path is: use a free macOS cloud runner to compile the unsigned IPA, then use AltStore Classic on Windows to sign and install it with your Apple ID.

## Part 1: Build the IPA in GitHub Actions

The project is already complete locally; GitHub is only being used as a macOS build machine.

1. Create an empty GitHub repository.
2. Upload the contents of this `AudioBridge` folder, including the hidden `.github` folder.
3. Make the default branch `main`.
4. Open the repository's **Actions** tab and select **Build iPhone app**.
5. Click **Run workflow**.
6. When the run finishes, open it and download the `AudioBridge-iPhone-unsigned` artifact.
7. Extract the downloaded ZIP to obtain `AudioBridge-unsigned.ipa`.

The workflow generates the Xcode project, runs the Swift unit tests in an iPhone simulator, compiles an unsigned device build, and packages the IPA. Standard runners are free and unlimited for public repositories. GitHub Free private repositories have a monthly Actions allowance, but macOS consumes that allowance faster than Linux/Windows.

## Part 2: Install AltStore Classic from Windows

Follow the current [official AltStore Windows instructions](https://faq.altstore.io/altstore-classic/how-to-install-altstore-windows). Their guide currently requires the desktop versions of iTunes and iCloud downloaded directly from Apple, not the Microsoft Store versions, followed by AltServer for Windows.

In outline:

1. Install Apple's desktop iTunes and iCloud as directed by AltStore.
2. Install and run AltServer.
3. Connect the iPhone to Windows by USB, unlock it, and tap **Trust** if asked.
4. Use AltServer's tray icon to install AltStore to the iPhone and sign in with your Apple ID when prompted.
5. On the iPhone, trust the developer profile if iOS requests it.
6. Enable **Settings → Privacy & Security → Developer Mode**, restart, and confirm. Apple documents the current process in [Enabling Developer Mode on a device](https://developer.apple.com/documentation/xcode/enabling-developer-mode-on-a-device).
7. Transfer `AudioBridge-unsigned.ipa` to the iPhone (iCloud Drive, USB file transfer, or another private method).
8. In the Files app, share/open the IPA with AltStore, or open AltStore's **My Apps** page and select the IPA using the `+` button.
9. Keep AltServer running on Windows and keep both devices on the same Wi-Fi when refreshing.

With a free Apple ID, AltStore apps expire after seven days. AltStore can refresh them while AltServer is available; the official [AltStore getting-started guide](https://faq.altstore.io/altstore-classic/your-altstore) explains the seven-day and active-app limits.

## Part 3: First launch

1. Connect the Lightning EarPods to the iPhone.
2. Launch AudioBridge and allow **Local Network** access.
3. Run AudioBridge Sender on Windows.
4. Enter its local address, UDP port `43120`, and current six-digit code.
5. Leave **Balanced** selected and tap **Connect**.
6. Start the sender's test tone before trying system audio.

If **Developer Mode** is initially missing, finish the AltStore/device pairing attempt first, then check Privacy & Security again. Do not disable Windows Firewall globally; use the included narrow private-network firewall rule instead.
