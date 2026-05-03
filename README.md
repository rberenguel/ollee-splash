# OlleeSplash

An iOS app that lets you send custom splash text to an **Ollee (Casio mod) watch** over Bluetooth Low Energy. It also exposes a **Shortcuts App Intent**, so you can automate splash updates from Siri or the Shortcuts app.

## How it works

The Ollee watch exposes a Nordic UART service (`6E400001-B5A3-F393-E0A9-E50E24DCCA9E`). This app discovers the watch by that service signature, connects, and sends packets formatted exactly like the Android [FreeOllee](https://github.com/arthur86000/freeollee) app.

## Setup

1. **Pair the watch in iOS Settings**  
   Go to **Settings → Bluetooth**, put the watch in pairing mode, and connect to it. The watch may not show a friendly name—this is normal.

2. **Open OlleeSplash** and tap **Scan for Watches**.  
   The app looks for the Ollee UART service, so you should see only your watch (plus any other device with the same service). If the name is blank, it will show as `Ollee (Unknown Name)` with its UUID underneath.

3. **Tap the watch to save it**.  
   The app stores the peripheral UUID and will auto-reconnect in the background.

4. **Use Shortcuts**  
   Open the Shortcuts app, add the **"Send Splash to Ollee"** action, and type up to 6 characters. You can now trigger it from Siri, automations, or the Shortcuts widget.

## Files

| File | Purpose |
|------|---------|
| `OlleeProtocol.swift` | Builds the BLE packet and CRC-16 exactly like FreeOllee |
| `OlleeBTManager.swift` | CoreBluetooth central manager: scan, connect, write, persist, reconnect |
| `SendSplashIntent.swift` | App Intent exposed to Shortcuts |
| `ContentView.swift` | Minimal SwiftUI to select/forget the watch |
| `Info.plist` | Declares `bluetooth-central` background mode and Bluetooth permission string |
| `OlleeWeather.js` | Scriptable script: fetches weather via Open-Meteo and encodes to 6 chars |
| `icon.png` | App icon (1024×1024, placed in the asset catalog) |

## Weather Integration (Scriptable)

`OlleeWeather.js` fetches the Open-Meteo forecast for the given location and encodes it into exactly 6 characters for the watch splash.

### Encoding
- **Morning** (08:00–12:00): 2 chars
- **Mid-day** (12:00–16:00): 2 chars
- **Evening** (16:00–20:00): 2 chars

For each block:
- **First char** = minimum temperature bucket:
  - `a` = below 0°C
  - `b` = 0–4°C
  - `c` = 5–9°C
  - `d` = 10–14°C
  - `e` = 15–19°C
  - `f` = 20–24°C
  - `g` = 25°C and above
- **Second char** = max precipitation probability, rounded to deciles (`0`–`9`).

Example: `c3e7d2` → morning 5–9°C/30%, midday 15–19°C/70%, evening 10–14°C/20%.

### Setup in Scriptable
1. Copy `OlleeWeather.js` into the **Scriptable** app on your iPhone.
2. Name the script `OlleeWeather`.

### Setup in Shortcuts
Create a new Shortcut:
1. **Run Scriptable** → choose `OlleeWeather`
   - **Parameter**: pass a text string with your latitude and longitude, e.g. `51.5074,-0.1278`
   - *(Enable “Show When Run” off for silent execution)*
2. **Send Splash to Ollee** → pass the Scriptable result as the `text` input

You can now run the shortcut manually, via Siri, or schedule it as an automation (e.g., every morning at 07:30).

## Notes

- The value sent to the watch is **padded to exactly 6 characters** with spaces, matching the Android behavior.
- If the watch is disconnected when a Shortcut runs, the text is queued and sent as soon as the watch reconnects.
- iOS hides MAC addresses; the app stores the system-generated `CBPeripheral` identifier. If you unpair and re-pair the watch in iOS Settings, you may need to re-select it in the app.
- The weather script uses [Open-Meteo](https://open-meteo.com/), a free API with no key required.
