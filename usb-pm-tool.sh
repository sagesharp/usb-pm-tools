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


# argument 1 is the device under test, e.g. /sys/bus/usb/devices/3-8/
if [ $# -ne 1 -o ! -d "$1" -o ! -e "$1"/devnum ]; then
	echo 'Usage `usb-suspend-test dev` where dev is e.g. /sys/bus/usb/devices/3-8'
	exit -1
fi
DEVNUM=`cat "$1"/devnum`
BUSNUM=`cat "$1"/busnum`
lsusb -s $BUSNUM:$DEVNUM

# Does the user have CONFIG_USB_PM enabled?  I.e. is the power directory and
# level file there?  Suggest they also have CONFIG_USB_DEBUG turned on.
if [ ! -d "$1"/power ]; then
	echo 'ERROR: CONFIG_USB_PM must be enabled in your kernel'
	exit -1
fi

echo
echo 'This test will enable a low power mode on your USB device.
It may cause broken devices to disconnect or stop responding.
Usually a reset or unplug-replug cycle will clear this error condition.
Please be careful when testing USB hard drives.'
echo
echo -n "Do you wish to test this device ($BUSNUM:$DEVNUM)? (y/n): "
read -n 4 go
echo ""
if [ "$go" != 'y' -a  "$go" != 'Y' -a  "$go" != 'yes'  -a  "$go" != 'Yes' ]; then
	echo "Please try with a different device.  Thanks!"
	exit 0
fi

# Do all the interface drivers support autosuspend?
# If not, there's no point in continuing the test.
SUPPORTED=1
for f in `find "$1/" -name '[0-9]*-[0-9]*:*'`;
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
echo 1 > "$1/power/autosuspend"

echo "auto" > "$1/power/level"
echo
echo "Waiting for device activity to cease..."
sleep 2
TIME=$(cat "$1/power/active_duration")
sleep 2
TIME2=$(cat "$1/power/active_duration")

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
WAKEUP=$(cat "$1/power/wakeup")
if [ $WAKEUP == "enabled" ]; then
	echo "Remote wakeup is enabled."
	TIME=$(cat "$1/power/active_duration")
	echo "Try to cause your device to wakeup, e.g. wiggle your mouse"
	echo -n "or type on your keyboard.  Type enter when done (30 second timeout): "
	read -n 1 -t 30
	TIME2=$(cat "$1/power/active_duration")
	if [ ! $? ]; then
		echo "Device died?"
		exit 1
	fi
	echo "Device active at $TIME jiffies and $TIME2 jiffies"
	if [ $TIME != $TIME2 ]; then
		echo "Remote wakeup worked!"
	fi
fi


# Ask user: does this device still work?  E.g. mouse moves on screen, it prints,
# etc.  Record response.

# Ask user if they want to send an HTTP post report.  Tell them their IP address
# will not be used to identify which USB devices they own.

# If the device correctly auto-suspends, generate a HAL rule to turn on
# auto-suspend for that device whenever it gets added to the /dev tree.  Send
# that via HTTP_POST too.

# Ask them to enter their email address if they wish to be contacted by Linux
# kernel USB developers.

# TODO: figure out how to grab dmesg output, lsusb -v output for that device
# (and maybe all devices in the system, just in case they have a misbehaving hub
# in between?), does pci -vvv make sense to get host controller information?
# Also want /proc/bus/usb/ entry, right?
