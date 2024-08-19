
# Wi-Fi Channel Optimization Script

This Bash script automates the process of optimizing Wi-Fi channels for better network performance. It performs several tasks including scanning available networks, testing speed on different channels, and selecting the optimal channel based on speed tests.

## Prerequisites

- **Root Access**: The script must be run as root.
- **Tools**: `speedtest-cli` and `bc` must be installed. The script will attempt to install these if they are not already present.
  
## Installation

To get started, you can clone the repository containing the script and then run it:

1. **Clone the Repository**:
   ```bash
   git clone https://github.com/Shuvam-Banerji-Seal/Wi-Fi-channel-optimizer.git
   ```

2. **Navigate to the Repository Directory**:
   ```bash
   cd Wi-Fi-channel-optimizer
   ```

3. **Make the Script Executable**:
   ```bash
   chmod +x wifi_optimization.sh
   ```

## Usage

Run the script with root privileges to start optimizing your Wi-Fi connection:

```bash
sudo ./wifi_optimization.sh
```

## Script Overview

1. **Check for Root Privileges**:
   - The script checks if it is being run with root privileges. If not, it exits with an error message.

2. **Install Required Tools**:
   - Installs `speedtest-cli` and `bc` if they are not found on the system.

3. **Identify Wi-Fi Interface**:
   - Uses `nmcli` to find the active Wi-Fi interface, excluding any peer-to-peer devices.

4. **Retrieve Current SSID**:
   - Fetches the SSID (network name) of the currently connected Wi-Fi network.

5. **Scan Available Networks**:
   - Performs a scan of available Wi-Fi networks and saves the results to a temporary file.

6. **Extract and Display Network Information**:
   - Parses the scan results to display useful information such as SSID, Channel, and Signal Strength.

7. **Test Speed on Each Channel**:
   - Disconnects and reconnects to the network on different channels to test the speed using `speedtest-cli`.

8. **Determine the Best Channel**:
   - Compares the speeds recorded on each channel and selects the best one.

9. **Reconnect to the Optimal Channel**:
   - Reconnects to the network on the best channel and performs a final set of tests to ensure stability and performance.

10. **Final Tests**:
    - Runs a final speed test and ping test to verify network stability and performance on the chosen channel.

## Detailed Explanation

### 1. Ensure Script is Run as Root

```bash
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit
fi
```

- **Purpose**: Ensures the script is executed with root privileges. Many network-related commands require elevated permissions.

### 2. Install Required Tools

```bash
if ! command -v speedtest-cli &> /dev/null; then
    echo "speedtest-cli not found, installing..."
    pacman -S --noconfirm speedtest-cli
fi

if ! command -v bc &> /dev/null; then
    echo "bc not found, installing..."
    pacman -S --noconfirm bc
fi
```

- **Purpose**: Checks if `speedtest-cli` and `bc` are installed. Installs them using `pacman` if they are missing.

### 3. Get the Current Wi-Fi Interface

```bash
WIFI_INTERFACE=$(nmcli device | grep wifi | grep connected | grep -v 'p2p-dev' | awk '{print $1}')
```

- **Purpose**: Identifies the Wi-Fi interface currently in use by filtering out peer-to-peer devices.

### 4. Retrieve the Current SSID

```bash
SSID=$(nmcli -t -f active,ssid dev wifi | grep '^yes' | cut -d':' -f2)
```

- **Purpose**: Fetches the SSID of the currently connected network. The script ensures that the SSID is retrieved successfully.

### 5. Scan for Wi-Fi Networks

```bash
iwlist $WIFI_INTERFACE scanning > /tmp/wifi_scan.txt
```

- **Purpose**: Scans for available Wi-Fi networks and saves the output to a temporary file.

### 6. Extract Useful Information

```bash
grep -E 'ESSID|Channel|Quality|Signal level' /tmp/wifi_scan.txt | sed 's/^\s*//'
```

- **Purpose**: Extracts and displays information about each network's SSID, Channel, and Signal Strength.

### 7. Test Speed on Each Channel

```bash
declare -A CHANNELS
# ... loop to test speed on each channel
```

- **Purpose**: Tests the network speed on each available channel by disconnecting and reconnecting to the Wi-Fi network on each channel.

### 8. Determine the Best Channel

```bash
declare -A SPEEDS
# ... loop to find the best channel
```

- **Purpose**: Determines the channel with the highest speed based on the recorded results.

### 9. Reconnect to the Optimal Channel

```bash
nmcli device disconnect "$WIFI_INTERFACE"
nmcli device wifi rescan
nmcli device wifi connect "$SSID" ifname "$WIFI_INTERFACE"
```

- **Purpose**: Reconnects to the Wi-Fi network on the optimal channel identified in the previous step.

### 10. Final Tests

```bash
# Run final tests including ping and speed test
```

- **Purpose**: Verifies the stability and performance of the connection on the chosen channel with final tests.



