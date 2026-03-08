#!/usr/bin/env python3
import csv
import sys
from collections import defaultdict

def parse_loot(file_path):
    # Dictionary to map Target -> Set of unique Client MACs
    targets = defaultdict(set)

    try:
        with open(file_path, 'r') as f:
            reader = csv.reader(f)
            for row in reader:
                # Expecting: Timestamp, SSID, Target MAC, Client MAC
                if len(row) < 4: continue
                time, ssid, t_mac, c_mac = row
                
                # Create a readable target key
                target_key = f"{ssid} ({t_mac})"
                targets[target_key].add(c_mac)

        print(f"\n[*] Parsing Recon Data: {file_path}")
        print("-" * 40)
        
        for target, clients in targets.items():
            print(f"\n[+] Target AP : {target}")
            for client in clients:
                print(f"    \\_ Client : {client}")
                
        print(f"\n[*] Total Unique APs Tracked: {len(targets)}\n")

    except FileNotFoundError:
        print(f"[!] Error: Could not find {file_path}")
    except Exception as e:
        print(f"[!] An error occurred: {e}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 parse_loot.py <path_to_client_recon.csv>")
    else:
        parse_loot(sys.argv[1])
