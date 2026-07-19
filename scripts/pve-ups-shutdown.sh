#!/bin/bash
# PVE UPS Manager - NUT/apcupsd shutdown hook
# This script safely shuts down all VMs and containers before host shutdown
# Installed to /usr/local/bin/pve-ups-shutdown

LOG=/var/log/pve-ups-shutdown.log
echo "===== PVE UPS Shutdown Started: $(date) =====" > "$LOG"

# Shutdown all running VMs
echo "Shutting down VMs..." >> "$LOG"
# qm list output: VMID NAME STATUS MEM(UNITS) BOOTDISK(GB) PID
# Status column is typically column 3 (index varies), so we match "running" in status column
for vmid in $(qm list 2>/dev/null | awk '{if(NR>1 && $3=="running") print $1}'); do
    echo "  Shutting down VM $vmid..." >> "$LOG"
    qm shutdown "$vmid" --timeout 30 >> "$LOG" 2>&1
done

# Shutdown all running containers
echo "Shutting down containers..." >> "$LOG"
# pct list output: VMID STATUS
for vmid in $(pct list 2>/dev/null | awk '{if(NR>1 && $2=="running") print $1}'); do
    echo "  Shutting down CT $vmid..." >> "$LOG"
    pct shutdown "$vmid" --timeout 30 >> "$LOG" 2>&1
done

# Wait for all VMs/CTs to stop
echo "Waiting for all VMs/CTs to stop..." >> "$LOG"
for i in $(seq 1 30); do
    running_vm=$(qm list 2>/dev/null | awk '{if(NR>1 && $3=="running") print $1}' | wc -l)
    running_ct=$(pct list 2>/dev/null | awk '{if(NR>1 && $2=="running") print $1}' | wc -l)
    total=$((running_vm + running_ct))
    if [ "$total" -eq 0 ]; then
        echo "  All VMs/CTs stopped" >> "$LOG"
        break
    fi
    echo "  Waiting... $total still running (attempt $i/30)" >> "$LOG"
    sleep 5
done

# Final force stop if anything is still running
for vmid in $(qm list 2>/dev/null | awk '{if(NR>1 && $3=="running") print $1}'); do
    echo "  Force stopping VM $vmid..." >> "$LOG"
    qm stop "$vmid" >> "$LOG" 2>&1
done
for vmid in $(pct list 2>/dev/null | awk '{if(NR>1 && $2=="running") print $1}'); do
    echo "  Force stopping CT $vmid..." >> "$LOG"
    pct stop "$vmid" >> "$LOG" 2>&1
done

# Shutdown host
echo "Shutting down host..." >> "$LOG"
shutdown -h now "UPS battery low - PVE UPS Manager initiated shutdown" >> "$LOG" 2>&1

echo "===== PVE UPS Shutdown Complete: $(date) =====" >> "$LOG"
