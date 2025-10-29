#!/bin/bash

# Step 1: Show all disks and their storage usage
echo "=== List of disks and partitions ==="
lsblk -o NAME,SIZE,MOUNTPOINT
echo ""
df -h --total | grep -E "Filesystem|total"
echo ""

# Step 2: Ask which disk or directory to compress
read -p "Enter the mount point or path of the disk you want to compress (e.g., /mnt/data or /): " DISK_PATH

# Check if the path exists
if [ ! -d "$DISK_PATH" ]; then
    echo "❌ Error: The path '$DISK_PATH' does not exist."
    exit 1
fi

# Step 3: Ask for the destination of the compressed file
read -p "Enter the full destination path for the .zip file (e.g., /home/user/backup.zip): " DEST_PATH

# Step 4: Start compression
echo "Compressing... this may take a while ⏳"
zip -r "$DEST_PATH" "$DISK_PATH" >/dev/null 2>&1

# Step 5: Check if successful
if [ $? -eq 0 ]; then
    echo "✅ Compression completed successfully!"
    echo "File created at: $DEST_PATH"
else
    echo "❌ Compression failed."
fi
