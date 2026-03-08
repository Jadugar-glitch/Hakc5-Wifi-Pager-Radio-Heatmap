# Radio Heatmapper (V4.9 Efficiency Tuned): User Manual

## Overview

The **Radio Heatmapper V4.9** is a high-performance tactical standard for the WiFi Pineapple Pager. It transforms the device into a robust Swiss Army Knife for identifying congestion, hunting targets, tracking movement, conducting targeted Deauth attacks, and silently mapping client devices with minimal CPU impact.

By using the physical buttons on the Pager, you can navigate between 4 unique data views.

## 1. The Main View (Default)

Upon launch, you see a live map of the 3 most congested Wi-Fi channels, including warnings for hidden `(H)` or unencrypted `[OPEN]` networks, and the name of the loudest offender.

```text
Noisiest Channels: [TGT][REC][ATK]
CH 6 : 4 APs (1 H) [OPEN]
> "Conference-R"
CH 11: 2 APs
CH 1 : 1 APs

```

*(Note: Top-right flags indicate active states: `[TGT]` for Target Locked, `[REC]` for PCAP Recording, and `[ATK]` for an active Deauth attack).*

## 2. Interactive Menu Map

Navigate between views or trigger offensive actions using the Pager buttons.

| Button | Action | Description |
| --- | --- | --- |
| **DOWN** | **Drill-Down / Client View** | Zooms into the worst channel to show the top 3 APs causing congestion. Pressing **DOWN** again (from Density View) enters **Client View**, which sniffs for 2 seconds and **logs active client MACs** to `/root/loot/client_recon_YYYY-MM-DD.csv`. |
| **RIGHT** | **Density View** | Plots the 4 absolute loudest/closest APs to your physical location, regardless of channel. |
| **LEFT** | **Noise Trend Graph** | Displays a scrolling ASCII bar graph of total physical congestion over the last 15 seconds. Use this while walking to gauge proximity to an interference source. |
| **UP** | **Target Lock & Deauth** | Extracts the target MAC and saves it to `/root/target.txt`. **Triggers a manual confirmation loop:** Press **UP** again to launch a targeted Deauth Attack, or **DOWN** to lock the target without attacking. |
| **B** | **Toggle PCAP** | Records raw packets in the background (`[REC]` flag). **Context-Aware:** If a target is locked, it records strictly on the target's channel; otherwise, it records the globally loudest channel. Saves to `/root/loot/`. |
| **A** | **Emergency Exit** | Safely exits the payload, resets interfaces to managed mode, and kills all background recordings or active attacks. |

---

## 3. Post-Mission Analysis: `parse_loot.py`

The `parse_loot.py` script is the offline counterpart for data deduplication. Because the payload appends raw data every sniff, the CSV contains redundant entries. This script strips duplicates and builds a clean relationship tree mapping discovered clients to their target APs.

**Usage:**

```bash
# Basic Execution
python3 parse_loot.py client_recon_2026-03-07.csv

# If running directly on the Pineapple Pager via SSH
python3 parse_loot.py /root/loot/client_recon_2026-03-07.csv

```

**Example Output:**

```text
[*] Parsing Recon Data: client_recon_2026-03-07.csv
----------------------------------------
[+] Target AP : Conference-R (00:1A:2B:3C:4D:5E)
    \_ Client : a1:b2:c3:d4:e5:f6
    \_ Client : 12:34:56:78:90:ab
[*] Total Unique APs Tracked: 1

```

---

## 4. Prerequisites & Developer Reference

* **Hardware:** Hak5 WiFi Pineapple Pager
* **Payload Location:** `/mmc/root/payloads/user/recon/Radio_Heatmapper/payload.sh`

This script (`v4.9`) utilizes `IFS` field splitting for low CPU overhead and features context-aware PCAP recording and `timeout`-protected sniffing. Hardware safety is guaranteed via asynchronous state hooks and `cleanup` traps, ensuring the radio is always returned to a managed state.