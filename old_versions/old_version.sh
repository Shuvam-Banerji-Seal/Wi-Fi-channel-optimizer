#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root"
    exit
fi

# Install required tools if not present
if ! command -v speedtest-cli &> /dev/null; then
    echo "speedtest-cli not found, installing..."
    pacman -S --noconfirm speedtest-cli
fi

if ! command -v bc &> /dev/null; then
    echo "bc not found, installing..."
    pacman -S --noconfirm bc
fi

# Get the current Wi-Fi interface, ignoring p2p-dev devices
WIFI_INTERFACE=$(nmcli device | grep wifi | grep connected | grep -v 'p2p-dev' | awk '{print $1}')

# Ensure we have a connected Wi-Fi interface
if [ -z "$WIFI_INTERFACE" ]; then
    echo "No Wi-Fi connection found!"
    exit 1
fi

# Get the current connected SSID
SSID=$(nmcli -t -f active,ssid dev wifi | grep '^yes' | cut -d':' -f2)

# Ensure SSID is retrieved
if [ -z "$SSID" ]; then
    echo "Failed to get current connected SSID!"
    exit 1
fi

echo "Connected to SSID: $SSID on interface $WIFI_INTERFACE"

# Scan Wi-Fi and get information about networks
echo "Scanning for Wi-Fi networks..."
iwlist $WIFI_INTERFACE scanning > /tmp/wifi_scan.txt

# Extract useful information: SSID, Channel, Signal Strength
echo "Available networks and details:"
grep -E 'ESSID|Channel|Quality|Signal level' /tmp/wifi_scan.txt | sed 's/^\s*//'

# Process the scan data to get unique channels
declare -A CHANNELS

while IFS= read -r line; do
    if [[ "$line" =~ Channel\ ([0-9]+) ]]; then
        CHANNEL="${BASH_REMATCH[1]}"
        CHANNELS[$CHANNEL]=1
    fi
done < /tmp/wifi_scan.txt

if [ ${#CHANNELS[@]} -eq 0 ]; then
    echo "No channels found!"
    exit 1
fi

# Test speed on each channel
declare -A SPEEDS

for CHANNEL in "${!CHANNELS[@]}"; do
    echo "Testing channel $CHANNEL..."

    # Disconnect and reconnect to the network on a specific channel
    nmcli device disconnect "$WIFI_INTERFACE"
    nmcli device wifi rescan

    # Connect to the network
    nmcli device wifi connect "$SSID" ifname "$WIFI_INTERFACE"

    if [ $? -eq 0 ]; then
        echo "Connected to $SSID on channel $CHANNEL"
        
        # Run speed test
        SPEED=$(speedtest-cli --simple | grep 'Download:' | awk '{print $2}')
        
        if [ -n "$SPEED" ]; then
            SPEEDS[$CHANNEL]=$SPEED
            echo "Speed on channel $CHANNEL: $SPEED Mbps"
        else
            echo "Failed to run speed test on channel $CHANNEL"
        fi
    else
        echo "Failed to connect to channel $CHANNEL"
    fi

    # Wait a bit before testing the next channel
    sleep 10
done

# Select the best channel based on speed test results
BEST_CHANNEL=""
BEST_SPEED=0

for CHANNEL in "${!SPEEDS[@]}"; do
    # Compare speeds using bc if available, otherwise use integer comparison
    if command -v bc &> /dev/null; then
        if (( $(echo "${SPEEDS[$CHANNEL]} > $BEST_SPEED" | bc -l) )); then
            BEST_CHANNEL="$CHANNEL"
            BEST_SPEED="${SPEEDS[$CHANNEL]}"
        fi
    else
        if (( $(echo "${SPEEDS[$CHANNEL]}" > "$BEST_SPEED") )); then
            BEST_CHANNEL="$CHANNEL"
            BEST_SPEED="${SPEEDS[$CHANNEL]}"
        fi
    fi
done

if [ -z "$BEST_CHANNEL" ]; then
    echo "No valid speed results found!"
    exit 1
fi

echo "Best channel: $BEST_CHANNEL with speed $BEST_SPEED Mbps"

# Reconnect to the best channel
echo "Reconnecting to $SSID on the best channel $BEST_CHANNEL..."
nmcli device disconnect "$WIFI_INTERFACE"
nmcli device wifi rescan
nmcli device wifi connect "$SSID" ifname "$WIFI_INTERFACE"

if [ $? -eq 0 ]; then
    echo "Successfully reconnected to $SSID on channel $BEST_CHANNEL"

    # Final series of tests
    echo "Running final series of tests..."

    # Check connection stability with ping test
    echo "Pinging a reliable server to check stability..."
    PING_RESULT=$(ping -c 4 google.com)
    if [ $? -eq 0 ]; then
        echo "Ping test successful."
        echo "$PING_RESULT"
    else
        echo "Ping test failed!"
    fi

    # Run final speed test
    echo "Running final speed test..."
    FINAL_SPEED=$(speedtest-cli --simple | grep 'Download:' | awk '{print $2}')
    if [ -n "$FINAL_SPEED" ]; then
        echo "Final speed: $FINAL_SPEED Mbps"
    else
        echo "Failed to run final speed test!"
    fi

    # Check latency
    echo "Measuring latency..."
    LATENCY_RESULT=$(ping -c 4 google.com | tail -n 1 | awk -F '/' '{print $5}')
    if [ -n "$LATENCY_RESULT" ]; then
        echo "Average latency: $LATENCY_RESULT ms"
    else
        echo "Failed to measure latency!"
    fi

else
    echo "Failed to reconnect to $SSID on the best channel!"
fi

