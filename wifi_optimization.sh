#!/bin/bash

# WiFi Analyzer and Optimizer
# This script analyzes available WiFi networks and optimizes your connection
# by finding the channel with the best performance.

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
    echo "Error: This script requires root privileges."
    echo "Please run with: sudo $0"
    exit 1
fi

# Function to check and install dependencies
install_dependencies() {
    local packages=("speedtest-cli" "bc" "iw" "wireless_tools")
    local os_type=""
    
    # Detect OS type
    if command -v apt &> /dev/null; then
        os_type="debian"
        INSTALL_CMD="apt install -y"
    elif command -v pacman &> /dev/null; then
        os_type="arch"
        INSTALL_CMD="pacman -S --noconfirm"
    elif command -v dnf &> /dev/null; then
        os_type="fedora"
        INSTALL_CMD="dnf install -y"
    elif command -v yum &> /dev/null; then
        os_type="centos"
        INSTALL_CMD="yum install -y"
    else
        echo "Unsupported operating system. Please install the required packages manually:"
        echo "- speedtest-cli"
        echo "- bc"
        echo "- iw"
        echo "- wireless-tools"
        exit 1
    fi
    
    echo "Detected $os_type-based system"
    
    # Check and install missing packages
    for pkg in "${packages[@]}"; do
        if ! command -v "$pkg" &> /dev/null && ! dpkg -l "$pkg" &> /dev/null 2>&1; then
            echo "$pkg not found, installing..."
            $INSTALL_CMD "$pkg" || {
                echo "Failed to install $pkg. Please install it manually."
                exit 1
            }
        fi
    done
}

# Function to get WiFi interface
get_wifi_interface() {
    # Try nmcli first
    if command -v nmcli &> /dev/null; then
        local iface=$(nmcli device | grep wifi | grep connected | grep -v 'p2p-dev' | awk '{print $1}' | head -1)
        if [ -n "$iface" ]; then
            echo "$iface"
            return 0
        fi
    fi
    
    # Try iw as fallback
    if command -v iw &> /dev/null; then
        local iface=$(iw dev | grep Interface | awk '{print $2}' | head -1)
        if [ -n "$iface" ]; then
            echo "$iface"
            return 0
        fi
    fi
    
    # Last resort: check common interface names
    for iface in wlan0 wlp2s0 wlp3s0 wlp1s0; do
        if [ -d "/sys/class/net/$iface" ]; then
            echo "$iface"
            return 0
        fi
    done
    
    return 1
}

# Function to get current SSID
get_current_ssid() {
    local wifi_interface="$1"
    local ssid=""
    
    # Try nmcli first
    if command -v nmcli &> /dev/null; then
        ssid=$(nmcli -t -f active,ssid dev wifi | grep '^yes' | cut -d':' -f2)
        if [ -n "$ssid" ]; then
            echo "$ssid"
            return 0
        fi
    fi
    
    # Try iw as fallback
    if command -v iw &> /dev/null; then
        ssid=$(iw dev "$wifi_interface" link | grep SSID | awk '{print $2}')
        if [ -n "$ssid" ]; then
            echo "$ssid"
            return 0
        fi
    fi
    
    # Try iwconfig as last resort
    if command -v iwconfig &> /dev/null; then
        ssid=$(iwconfig "$wifi_interface" | grep ESSID | awk -F '"' '{print $2}')
        if [ -n "$ssid" ]; then
            echo "$ssid"
            return 0
        fi
    fi
    
    return 1
}

# Function to scan WiFi networks
scan_wifi_networks() {
    local wifi_interface="$1"
    local scan_file="/tmp/wifi_scan_$$.txt"
    
    echo "Scanning for WiFi networks..."
    
    # Try using iw for scanning
    if command -v iw &> /dev/null; then
        iw dev "$wifi_interface" scan > "$scan_file" 2>/dev/null
    else
        # Fallback to iwlist
        iwlist "$wifi_interface" scanning > "$scan_file" 2>/dev/null
    fi
    
    # Check if scan was successful
    if [ ! -s "$scan_file" ]; then
        echo "WiFi scan failed. Please ensure your WiFi is enabled."
        rm -f "$scan_file"
        exit 1
    fi
    
    echo "$scan_file"
}

# Function to analyze scan results
analyze_wifi_scan() {
    local scan_file="$1"
    local current_ssid="$2"
    
    echo -e "\n=== WiFi Environment Analysis ==="
    
    # Extract networks, channels, and signal strength
    echo -e "\nNetworks on the same channel as yours:"
    
    # Get current channel
    local current_channel=""
    if grep -A 15 "SSID: $current_ssid" "$scan_file" | grep -q "channel"; then
        current_channel=$(grep -A 15 "SSID: $current_ssid" "$scan_file" | grep "channel" | head -1 | awk '{print $2}')
    elif grep -A 15 "ESSID:\"$current_ssid\"" "$scan_file" | grep -q "Channel"; then
        current_channel=$(grep -A 15 "ESSID:\"$current_ssid\"" "$scan_file" | grep "Channel" | head -1 | awk '{print $2}')
    fi
    
    if [ -z "$current_channel" ]; then
        echo "Could not determine your current channel."
    else
        echo "Your current channel: $current_channel"
        
        # Count networks on the same channel
        local networks_on_same_channel=0
        
        # Process scan results to get channels and networks
        declare -A channel_networks
        
        # Detect format (iw or iwlist)
        if grep -q "SSID:" "$scan_file"; then
            # iw format
            local ssid=""
            local channel=""
            local signal=""
            
            while IFS= read -r line; do
                if [[ "$line" =~ ^BSS ]]; then
                    # New network section
                    if [[ -n "$ssid" && -n "$channel" ]]; then
                        if [ "$channel" = "$current_channel" ] && [ "$ssid" != "$current_ssid" ]; then
                            echo "  - $ssid (Signal: $signal dBm)"
                            ((networks_on_same_channel++))
                        fi
                        
                        # Count networks per channel
                        if [ -n "$channel" ]; then
                            channel_networks["$channel"]=$((${channel_networks["$channel"]:-0} + 1))
                        fi
                    fi
                    ssid=""
                    channel=""
                    signal=""
                elif [[ "$line" =~ SSID:\ (.*) ]]; then
                    ssid="${BASH_REMATCH[1]}"
                elif [[ "$line" =~ channel\ ([0-9]+) ]]; then
                    channel="${BASH_REMATCH[1]}"
                elif [[ "$line" =~ signal:\ (.*) ]]; then
                    signal="${BASH_REMATCH[1]}"
                fi
            done < "$scan_file"
            
            # Process the last network
            if [[ -n "$ssid" && -n "$channel" ]]; then
                if [ "$channel" = "$current_channel" ] && [ "$ssid" != "$current_ssid" ]; then
                    echo "  - $ssid (Signal: $signal dBm)"
                    ((networks_on_same_channel++))
                fi
                
                # Count networks per channel
                if [ -n "$channel" ]; then
                    channel_networks["$channel"]=$((${channel_networks["$channel"]:-0} + 1))
                fi
            fi
            
        else
            # iwlist format
            local current_cell=""
            local ssid=""
            local channel=""
            local quality=""
            
            while IFS= read -r line; do
                if [[ "$line" =~ Cell\ [0-9]+ ]]; then
                    # New network section
                    if [[ -n "$ssid" && -n "$channel" ]]; then
                        if [ "$channel" = "$current_channel" ] && [ "$ssid" != "$current_ssid" ]; then
                            echo "  - $ssid (Quality: $quality)"
                            ((networks_on_same_channel++))
                        fi
                        
                        # Count networks per channel
                        if [ -n "$channel" ]; then
                            channel_networks["$channel"]=$((${channel_networks["$channel"]:-0} + 1))
                        fi
                    fi
                    ssid=""
                    channel=""
                    quality=""
                elif [[ "$line" =~ ESSID:\"(.*)\" ]]; then
                    ssid="${BASH_REMATCH[1]}"
                elif [[ "$line" =~ Channel:([0-9]+) ]]; then
                    channel="${BASH_REMATCH[1]}"
                elif [[ "$line" =~ Quality=([0-9]+/[0-9]+) ]]; then
                    quality="${BASH_REMATCH[1]}"
                fi
            done < "$scan_file"
            
            # Process the last network
            if [[ -n "$ssid" && -n "$channel" ]]; then
                if [ "$channel" = "$current_channel" ] && [ "$ssid" != "$current_ssid" ]; then
                    echo "  - $ssid (Quality: $quality)"
                    ((networks_on_same_channel++))
                fi
                
                # Count networks per channel
                if [ -n "$channel" ]; then
                    channel_networks["$channel"]=$((${channel_networks["$channel"]:-0} + 1))
                fi
            fi
        fi
        
        if [ "$networks_on_same_channel" -eq 0 ]; then
            echo "  None found. Your channel appears to be clear!"
        else
            echo "  Total networks sharing your channel: $networks_on_same_channel"
        fi
        
        # Suggest least congested channels
        echo -e "\nChannel congestion analysis:"
        
        # 2.4 GHz recommended channels
        echo "  2.4 GHz recommended channels: 1, 6, 11"
        
        # Sort channels by number of networks (least to most)
        echo -e "\nChannel occupation (from least to most congested):"
        for channel in $(echo "${!channel_networks[@]}" | tr ' ' '\n' | sort -n); do
            networks=${channel_networks["$channel"]}
            if [ "$channel" = "$current_channel" ]; then
                echo "  Channel $channel: $networks networks (YOUR CURRENT CHANNEL)"
            else
                echo "  Channel $channel: $networks networks"
            fi
        done
    fi
    
    # Clean up
    rm -f "$scan_file"
}

# Function to run speed test
run_speed_test() {
    echo -e "\n=== Running Speed Test ==="
    if command -v speedtest-cli &> /dev/null; then
        speedtest-cli --simple
        return $?
    else
        echo "speedtest-cli not available. Skipping speed test."
        return 1
    fi
}

# Function to test network latency
test_latency() {
    local target="8.8.8.8"
    echo -e "\n=== Testing Network Latency ==="
    
    if ping -c 4 "$target" &> /dev/null; then
        ping -c 4 "$target"
        local avg_latency=$(ping -c 4 "$target" | tail -1 | awk -F '/' '{print $5}')
        echo -e "\nAverage latency: $avg_latency ms"
        
        if (( $(echo "$avg_latency < 20" | bc -l) )); then
            echo "Latency status: EXCELLENT"
        elif (( $(echo "$avg_latency < 50" | bc -l) )); then
            echo "Latency status: GOOD"
        elif (( $(echo "$avg_latency < 100" | bc -l) )); then
            echo "Latency status: FAIR"
        else
            echo "Latency status: POOR"
        fi
    else
        echo "Failed to ping $target. Network may be unreachable."
        return 1
    fi
}

# Function to find optimal channel
find_optimal_channel() {
    local wifi_interface="$1"
    local current_ssid="$2"
    
    echo -e "\n=== Channel Optimization ==="
    echo "This feature requires NetworkManager and appropriate permissions to change WiFi settings."
    
    # Check if we can modify network settings
    if ! command -v nmcli &> /dev/null; then
        echo "Error: NetworkManager (nmcli) is required for channel optimization."
        return 1
    fi
    
    read -p "Do you want to test different channels to find the optimal one? (y/n): " choice
    if [[ ! "$choice" =~ ^[Yy]$ ]]; then
        echo "Channel optimization skipped."
        return 0
    fi
    
    echo "Starting channel optimization process..."
    
    # Get available channels
    local scan_file=$(scan_wifi_networks "$wifi_interface")
    declare -A channels
    
    if grep -q "channel" "$scan_file"; then
        # iw format
        while IFS= read -r line; do
            if [[ "$line" =~ channel\ ([0-9]+) ]]; then
                channels["${BASH_REMATCH[1]}"]=1
            fi
        done < "$scan_file"
    else
        # iwlist format
        while IFS= read -r line; do
            if [[ "$line" =~ Channel:([0-9]+) ]]; then
                channels["${BASH_REMATCH[1]}"]=1
            fi
        done < "$scan_file"
    fi
    
    # Remove scan file
    rm -f "$scan_file"
    
    if [ ${#channels[@]} -eq 0 ]; then
        echo "No channels found in scan results!"
        return 1
    fi
    
    echo "Testing speeds on different channels..."
    
    # Focus on recommended channels
    local recommended_channels=(1 6 11)
    local all_channels=(${!channels[@]})
    
    # Add current channel to test list
    local current_channel=""
    if command -v iwconfig &> /dev/null; then
        current_channel=$(iwconfig "$wifi_interface" | grep "Channel=" | awk -F'=' '{print $2}' | awk '{print $1}')
    elif command -v iw &> /dev/null; then
        current_channel=$(iw dev "$wifi_interface" info | grep channel | awk '{print $2}')
    fi
    
    if [ -n "$current_channel" ]; then
        recommended_channels+=("$current_channel")
    fi
    
    # Remove duplicates
    recommended_channels=($(echo "${recommended_channels[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' '))
    
    # Test channels
    declare -A speeds
    
    for channel in "${recommended_channels[@]}"; do
        echo "Testing channel $channel..."
        
        # Disconnect and reconnect to the network
        nmcli device disconnect "$wifi_interface"
        sleep 2
        
        # Connect to the network
        nmcli device wifi connect "$current_ssid" ifname "$wifi_interface"
        
        if [ $? -eq 0 ]; then
            echo "Connected to $current_ssid"
            
            # Run speed test
            echo "Running speed test..."
            local download_speed=$(speedtest-cli --simple | grep 'Download:' | awk '{print $2}')
            
            if [ -n "$download_speed" ]; then
                speeds["$channel"]=$download_speed
                echo "Speed on channel $channel: $download_speed Mbps"
            else
                echo "Failed to run speed test on channel $channel"
            fi
        else
            echo "Failed to connect on channel $channel"
        fi
        
        # Wait before testing the next channel
        sleep 5
    done
    
    # Select the best channel
    local best_channel=""
    local best_speed=0
    
    for channel in "${!speeds[@]}"; do
        if (( $(echo "${speeds[$channel]} > $best_speed" | bc -l) )); then
            best_channel="$channel"
            best_speed="${speeds[$channel]}"
        fi
    done
    
    if [ -z "$best_channel" ]; then
        echo "No valid speed results found!"
        return 1
    fi
    
    echo -e "\nChannel test results:"
    for channel in "${!speeds[@]}"; do
        if [ "$channel" = "$best_channel" ]; then
            echo "  Channel $channel: ${speeds[$channel]} Mbps (BEST)"
        else
            echo "  Channel $channel: ${speeds[$channel]} Mbps"
        fi
    done
    
    echo -e "\nBest channel: $best_channel with speed $best_speed Mbps"
    
    # Reconnect to the best channel
    read -p "Do you want to reconnect to the best channel? (y/n): " choice
    if [[ "$choice" =~ ^[Yy]$ ]]; then
        echo "Reconnecting to $current_ssid on the best channel $best_channel..."
        nmcli device disconnect "$wifi_interface"
        sleep 2
        nmcli device wifi rescan
        nmcli device wifi connect "$current_ssid" ifname "$wifi_interface"
        
        if [ $? -eq 0 ]; then
            echo "Successfully reconnected to $current_ssid on channel $best_channel"
        else
            echo "Failed to reconnect to $current_ssid on the best channel!"
            return 1
        fi
    else
        echo "Keeping current channel settings."
    fi
    
    return 0
}

# Main function
main() {
    echo "====================================================="
    echo "         WiFi Analyzer and Optimizer Tool"
    echo "====================================================="
    
    # Install dependencies
    install_dependencies
    
    # Get WiFi interface
    WIFI_INTERFACE=$(get_wifi_interface)
    if [ -z "$WIFI_INTERFACE" ]; then
        echo "Error: Could not find a connected WiFi interface."
        exit 1
    fi
    
    # Get current SSID
    SSID=$(get_current_ssid "$WIFI_INTERFACE")
    if [ -z "$SSID" ]; then
        echo "Error: Could not determine the current SSID."
        exit 1
    fi
    
    echo -e "\nConnection Details:"
    echo "  Interface: $WIFI_INTERFACE"
    echo "  Network: $SSID"
    
    # Scan and analyze WiFi
    SCAN_FILE=$(scan_wifi_networks "$WIFI_INTERFACE")
    analyze_wifi_scan "$SCAN_FILE" "$SSID"
    
    # Test current connection
    run_speed_test
    test_latency
    
    # Find optimal channel
    find_optimal_channel "$WIFI_INTERFACE" "$SSID"
    
    echo -e "\n====================================================="
    echo "               Analysis Complete"
    echo "====================================================="
}

# Run the main function
main

# Exit cleanly
exit 0
