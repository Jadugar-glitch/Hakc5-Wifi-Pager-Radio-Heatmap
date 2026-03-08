# Radio Heatmapper V6.1

**The Ultimate Interactive WiFi Recon Multi-Tool for the Hak5 WiFi Pineapple Pager**

Radio Heatmapper is a high-performance offensive reconnaissance tool that transforms your Pager into a tactical scanner. It provides real-time visualization of WiFi congestion, target tracking, and active deauthentication capabilities—all controlled directly via physical buttons.

## Dynamic Views
Radio Heatmapper features 5 distinct operational modes:
1.  **Main View:** Real-time summary of the noisiest channels, hidden network detection, and open AP flags.
2.  **Noise Trend:** ASCII scrolling graph of environmental congestion over time.
3.  **Density View:** Instant plot of the 4 absolute loudest APs in your vicinity.
4.  **Drill-Down:** Focused view of a specific channel's top offenders.
5.  **Client View:** Passive sniffer that maps active client MAC addresses to their parent APs.

## Active Capabilities
- **Target Lock:** Select an AP to monitor its specific channel and clients.
- **Targeted Deauth:** Launch a manual deauthentication attack against a locked target (via `pineapcli`).
- **Context-Aware PCAP:** Record raw traffic. If a target is locked, the recorder automatically follows the target's channel.
- **Offline Analysis:** Includes `parse_loot.py` to deduplicate recon data and visualize Client-to-AP relationships.

## Hardware Controls
| Button | Action | Context |
| --- | --- | --- |
| **LEFT** | Noise Trend | Main -> Trend |
| **RIGHT** | Density View | Main -> Density |
| **DOWN** | Drill-Down / Client | Level 1: Drill-Down / Level 2: Client Sniff |
| **UP** | Target Lock / Attack | Interactive Confirmation Loop for Deauth |
| **B** | Toggle PCAP | Records to `/root/loot/` (`[REC]` status flag) |
| **A** | Emergency Exit | Safe shutdown and radio reset |

## Installation & Setup

1. Copy the `Radio_Heatmapper` directory to your Pager:
   ```bash
   scp -r Radio_Heatmapper root@172.16.52.1:/mmc/root/payloads/user/recon/
   ```
2. Ensure the script is executable:
   ```bash
   ssh root@172.16.52.1 "chmod +x /mmc/root/payloads/user/recon/Radio_Heatmapper/payload.sh"
   ```

## Post-Mission Analysis
Use the included Python helper to clean up your loot:
```bash
python3 parse_loot.py /root/loot/client_recon_YYYY-MM-DD.csv
```
