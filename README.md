# ProTee Labs + GSPro Simulator Startup

Automated startup script for a golf simulator rig running [ProTee Labs](https://www.proteegolf.com/) with [GSPro](https://gsprogolf.com/). Optionally controls a Samsung TV via SmartThings for a fully automated experience.

## Features

- **Network Awareness** - Waits for internet connectivity before proceeding
- **Samsung TV Control** - Powers on your TV automatically via SmartThings (optional)
- **Application Launcher** - Starts ProTee Labs (which launches GSPro)
- **Window Management** - Minimizes the GSPconnect window for a clean setup
- **Task Scheduler Ready** - Designed to run unattended at system startup

## Prerequisites

- Windows 10/11
- PowerShell 5.1 or later
- [ProTee Labs](https://www.proteegolf.com/) installed
- (Optional) [SmartThings CLI](https://github.com/SmartThingsCommunity/smartthings-cli) for TV control
- (Optional) Samsung TV registered with SmartThings

## Quick Start

1. **Clone the repository**
   ```powershell
   git clone https://github.com/jannesep/protee-gspro-startup.git
   cd protee-gspro-startup
   ```

2. **Create your configuration**
   ```powershell
   Copy-Item config.example.json config.json
   ```

3. **Edit `config.json`** with your settings:
   - Set `smartThings.enabled` to `false` if you don't need TV control
   - Update paths to match your installation

4. **(If using SmartThings)** Set up OAuth tokens:
   ```powershell
   Copy-Item samsung_auth.example.json samsung_auth.json
   ```
   Then populate with your actual OAuth tokens from SmartThings. For help getting the initial tokens, check [this](https://levelup.gitconnected.com/smartthings-api-taming-the-oauth-2-0-beast-5d735ecc6b24) for help

5. **Run the script**
   ```powershell
   .\start-simulator.ps1
   ```
   Instructions for Task Scheduler for automatic startup on login below

## Configuration

### config.json

| Setting | Description | Default |
|---------|-------------|---------|
| `smartThings.enabled` | Enable/disable Samsung TV control | `true` |
| `smartThings.clientId` | SmartThings OAuth client ID | - |
| `smartThings.clientSecret` | SmartThings OAuth client secret | - |
| `smartThings.deviceId` | Your Samsung TV device ID | - |
| `smartThings.cliPath` | Path to SmartThings CLI executable | `C:\Scripts\smartthings.exe` |
| `paths.logDir` | Directory for log files | `C:\Scripts` |
| `paths.proteeLabsExe` | Path to ProTee Labs executable | `C:\Program Files\ProTee Labs\ProTee Labs.exe` |
| `paths.authFile` | OAuth token file (relative or absolute) | `samsung_auth.json` |
| `network.maxRetries` | Network connectivity check attempts | `10` |
| `network.retryIntervalSeconds` | Seconds between retry attempts | `2` |
| `window.processTimeoutSeconds` | Timeout waiting for GSPconnect | `60` |
| `window.pollIntervalSeconds` | Poll interval for process detection | `1` |

### Disabling SmartThings

If you don't have a Samsung TV or SmartThings setup, simply set:

```json
{
  "smartThings": {
    "enabled": false,
    ...
  }
}
```

The script will skip all TV-related operations.

## Task Scheduler Setup

To run automatically at startup:

1. Open **Task Scheduler** (`taskschd.msc`)
2. Create a new task:
   - **Trigger**: At log on (or At startup)
   - **Action**: Start a program
     - Program: `powershell.exe`
     - Arguments: `-ExecutionPolicy Bypass -WindowStyle Hidden -File "C:\path\to\start-simulator.ps1"`
   - **Conditions**: Uncheck "Start only if on AC power" for laptops
   - **Settings**: Enable "Run task as soon as possible after a scheduled start is missed"

## File Structure

```
protee-gspro-startup/
├── start-simulator.ps1      # Main startup script
├── hide-gspconnect.ps1      # Window manager (minimizes GSPconnect)
├── config.example.json      # Configuration template
├── samsung_auth.example.json # OAuth token template
├── config.json              # Your configuration (git-ignored)
├── samsung_auth.json        # Your OAuth tokens (git-ignored)
└── README.md                # This file
```

## Logs

Logs are written to the configured `logDir`:
- `startup-log-YYYYMMDD-HHMMSS.txt` - Main script transcript
- `hide-gspconnect.log` - Window manager operations

## Troubleshooting

### Script fails to start ProTee Labs
- Verify the path in `config.json` → `paths.proteeLabsExe`
- Check if ProTee Labs runs manually

### SmartThings token refresh fails
- Ensure your `samsung_auth.json` has valid tokens
- Verify client credentials in `config.json`
- Check if tokens have expired (you may need to re-authenticate)

### GSPconnect window doesn't minimize
- The script waits up to 60 seconds for GSPconnect to appear
- Check `hide-gspconnect.log` for details
- Ensure GSPconnect is launching (it's started by ProTee Labs)

### Network timeout at startup
- Increase `network.maxRetries` if your network is slow to connect
- Check Windows network adapter settings

## Contributing

Contributions are welcome! Please feel free to submit issues or pull requests.

## License

MIT License - See [LICENSE](LICENSE) for details.


