#!/bin/sh
#
# USB-PM tool tests whether a USB device correctly auto-suspends.
#
# Copyright (c) 2008, Intel Corporation.
#
# This program is free software; you can redistribute it and/or modify it
# under the terms and conditions of the GNU General Public License,
# version 2, as published by the Free Software Foundation.
#
# This program is distributed in the hope it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
# more details.
#
# You should have received a copy of the GNU General Public License along with
# this program; if not, write to the Free Software Foundation, Inc., 
# 51 Franklin St - Fifth Floor, Boston, MA 02110-1301 USA.

# Author: Sarah Sharp <sarah.a.sharp@linux.intel.com>

# Todo - present the user with a list of their USB devices they can test.
# Exclude root hubs from that list (I think they are 0000:000x on older
# systems?)
# Then let them pick the device from the list.
# To find out the non-root hubs in the system:
NUM_DEVS=`sudo lsusb | grep -v -e ".*ID 1d6b:000.*" -e ".*ID 0000:000.*" | wc -l`
# Find out how many devices we have

echo ""
echo "USB Power Management Tool v 0.1"
echo "Copyright Sarah Sharp 2008"
echo ""

DEVS_FILE=/tmp/usb-pm-devices.txt
sudo lsusb | grep -v -e ".*ID 1d6b:000.*" -e ".*ID 0000:000.*" > $DEVS_FILE
cat $DEVS_FILE | nl
echo -n "Which USB devices would you like to test: "
# Can't have more than 255 devices plugged in anyway...
read -n 3 devnum
echo ""
MAX_DEVNUM=`cat $DEVS_FILE | wc -l`
if [ "$devnum" -gt "$MAX_DEVNUM" ]; then
	echo "Device $devnum does not exist"
	exit 0
fi
# Now to map the user's selection to a device's VID/PID
TEST_DEV=`head -n $devnum $DEVS_FILE | tail -n 1`
VID=`echo $TEST_DEV | sed -r -e "s/.*([[:xdigit:]]{4}):([[:xdigit:]]{4}).*/\1/"`
PID=`echo $TEST_DEV | sed -r -e "s/.*([[:xdigit:]]{4}):([[:xdigit:]]{4}).*/\2/"`

# Finally we map the VID:PID to the sysfs file that represents that device
# Only take the first VID:PID match
SYSFS_DIR=`find -L /sys/bus/usb/devices -maxdepth 1 -type d -exec grep -s -q $VID {}/idVendor \; -exec grep -s -q $PID {}/idProduct \; -print | head -n 1`
DEVNUM=`cat "$SYSFS_DIR"/devnum`
BUSNUM=`cat "$SYSFS_DIR"/busnum`

# Does the user have CONFIG_USB_PM enabled?  I.e. is the power directory and
# level file there?  Suggest they also have CONFIG_USB_DEBUG turned on.
if [ ! -d "$SYSFS_DIR"/power ]; then
	echo 'ERROR: CONFIG_USB_PM must be enabled in your kernel'
	exit -1
fi

echo 'This test will enable a low power mode on your USB device.
It may cause broken devices to disconnect or stop responding.
Usually a reset or unplug-replug cycle will clear this error condition.'
echo
echo $TEST_DEV
echo "The following drivers are using this device:"
DRIVERS=`find "$SYSFS_DIR/" -mindepth 2 -maxdepth 3 -name driver -execdir readlink {} \; | xargs -n1 --no-run-if-empty basename`
echo $DRIVERS
echo
if echo $DRIVERS | grep -q -e ".*usb-storage.*" -e ".*ub.*" - ; then
	echo "WARNING: This device contains a USB flash drive or hard disk."
	echo "You may want to backup your files before proceeding."
	echo
fi
echo -n "Do you wish to test this device? (y/n): "
read -n 4 go
echo ""
if [ "$go" != 'y' -a  "$go" != 'Y' -a  "$go" != 'yes'  -a  "$go" != 'Yes' ]; then
	echo "Please try with a different device.  Thanks!"
	exit 0
fi

# Do all the interface drivers support autosuspend?
# If not, there's no point in continuing the test.
SUPPORTED=1
for f in `find "$SYSFS_DIR/" -name '[0-9]*-[0-9]*:*'`;
do
	if [ ! -e "$f/supports_autosuspend" ]; then
		break
	fi

	if [ -e "$f/driver" ]; then
		READLINK=`readlink "$f/driver"`
		DRIVER=`basename "$READLINK"`
	else
		DRIVER=""
	fi

	if [ `cat "$f/supports_autosuspend"` = 0 ]; then
		# unclaimed interfaces will have supports_autosuspend set to 1
		echo "WARN: $DRIVER driver for interface `cat $f/bInterfaceNumber` does not support autosuspend."
		echo "Autosuspend can only be tested when all interface drivers support autosuspend."
		SUPPORTED=0
	else
		if [ "$DRIVER" = "" ]; then
			echo "Interface `cat $f/bInterfaceNumber` is unclaimed"
		else
			echo "$DRIVER driver for interface `cat $f/bInterfaceNumber` supports autosuspend."
		fi
	fi
done

if [ $SUPPORTED == 0 ]; then
	exit 1
fi

# For cleanup later
WAIT=`cat "$1/power/autosuspend"`

# Set level file to auto and monitor the activity using active_duration.
echo "Enabling auto-suspend"
# Don't want to wait too long...
echo 1 > "$SYSFS_DIR/power/autosuspend"

echo "auto" > "$SYSFS_DIR/power/level"
echo
echo "Waiting for device activity to cease..."
sleep 2
TIME=$(cat "$SYSFS_DIR/power/active_duration")
sleep 0.2
TIME2=$(cat "$SYSFS_DIR/power/active_duration")

# Be paranoid at this point about files, because the device might break and the
# files might go away.
if [ ! $? ]; then
	echo "Device died?"
	exit 1
fi
# Need to calculate a buffer, but jiffies is based on HZ and yuck.
# Maybe use connected duration (read with TIME and TIME2), use a fraction of it
# as a buffer?
echo "Device active at $TIME jiffies and $TIME2 jiffies"
if [ $TIME != $TIME2 ]; then
	echo "Device still active, test inconclusive."
	exit 1
fi
echo "Your device auto-suspended correctly!"

# Test remote wakeup?  Or just set level to on?
WAKEUP=`cat $SYSFS_DIR/power/wakeup`
if [ $WAKEUP == "enabled" ]; then
	echo "Remote wakeup is enabled."
	TIME=`cat "$SYSFS_DIR/power/active_duration"`
	echo "Try to cause your device to wakeup, e.g. wiggle your mouse"
	echo -n "or type on your keyboard.  Type enter when done (30 second timeout): "
	read -n 1 -t 30
	TIME2=`cat "$SYSFS_DIR/power/active_duration"`
	if [ ! $? ]; then
		echo "Device died?"
		exit 1
	fi
	echo "Device active at $TIME jiffies and $TIME2 jiffies"
	if [ $TIME != $TIME2 ]; then
		echo "Remote wakeup worked!"
		# FIXME: not necessarily, since a userspace program could have
		# woken this device up.
	fi
fi


# Ask user: does this device still work?  E.g. mouse moves on screen, it prints,
# etc.  Record response.

# Ask user if they want to send an HTTP post report.  Tell them their IP address
# will not be used to identify which USB devices they own.

# If the device correctly auto-suspends, generate a udev rule to turn on
# auto-suspend for that device whenever it gets added to the /dev tree.  Send
# that via HTTP_POST too.

echo "Suggested udev rule:"
echo "SUBSYSTEMS==\"usb\", ATTR{idVendor}==\"$VID\", ATTR{idProduct}==\"$PID\", \\"
echo "	ATTR{power/level}=\"auto\""
# TODO ask user if they want to add this rule to their udev rules.

# Ask them to enter their email address if they wish to be contacted by Linux
# kernel USB developers.

# TODO: figure out how to grab dmesg output, lsusb -v output for that device
# (and maybe all devices in the system, just in case they have a misbehaving hub
# in between?), does pci -vvv make sense to get host controller information?
# Also want /proc/bus/usb/ entry, right?
