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


echo ""
echo "USB Power Management Tool v 0.1"
echo "Copyright Sarah Sharp 2008"
echo ""

if [ $# -gt 0 ]; then
	echo 'Usage `./usb-pm-tool.sh`'
	echo "This script must be run with root privileges."
	echo ""
	echo "    This tool will test whether you can safely place a USB device"
	echo "    into a low power state (suspend).  Suspending inactive USB"
	echo "    devices can reduce power consumption and increase battery life."
	echo ""
	echo "    If the device correctly suspends, the tool will generate"
	echo "    a udev rule to allow the kernel to automatically suspend"
	echo "    the USB device when it is inactive.  The udev rule will"
	echo "    trigger whenever the device is plugged in."
	echo ""
	echo "    You will need to have programs installed that use your"
	echo "    USB device, so that wakeup out of suspend can be tested."
	echo "    For example, you might use the 'cheese' program to test"
	echo "    a USB video camera, or the thinkfinger program to test"
	echo "    a USB fingerprint reader."
	echo ""
	echo "    Currently, not all USB drivers support automatic suspension"
	echo "    (auto-suspend) of inactive devices.  This test is only useful"
	echo "    for USB devices that use drivers that support auto-suspend."
	echo ""
	exit 0
fi

# FIXME: check to make sure the script is running as root.

# Find all USB devices on the system
DEVS_FILE=/tmp/usb-pm-devices.txt
sudo lsusb | grep -v -e ".*ID 1d6b:000.*" -e ".*ID 0000:000.*" > $DEVS_FILE

# Do some processing on the file to filter USB devices.
#
# Sort into devices that do support autosuspend versus those that don't.
# Simply display those that don't support autosuspend, and offer to test
# any that do support autosuspend.  If the system doesn't have the
# supports_autosuspend files, offer to test them all.  E.g.
#
# These devices have drivers that don't support auto-suspend yet:
#
# vid:pid device foo
# vid:pid device bar
#
# Which USB device do you want to test?
#
#        Auto-suspend     device
#        status
#     --------------------------------------------------------------------
#     1  enabled          vid:pid device baz
#     2  disabled         vid:pid device baz

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

# Find the USB drivers that have claimed this device
DRIVERS=`find "$SYSFS_DIR/" -mindepth 2 -maxdepth 3 -name driver -execdir readlink {} \; | xargs -n1 --no-run-if-empty basename`

echo 'This test will enable a low power mode on your USB device.
It may cause broken devices to disconnect or stop responding.
Usually a reset or unplug-replug cycle will clear this error condition.'
echo

# For testing purposes only, remove driver echoing for final script
echo $TEST_DEV
echo "The following drivers are using this device:"
echo $DRIVERS
echo

# Warn users if they're testing USB mass storage devices.
if echo $DRIVERS | grep -q -e ".*usb-storage.*" -e ".*ub.*" - ; then
	echo "WARNING: This device contains a USB flash drive or hard disk."
	echo "You may want to backup your files before proceeding."
	echo
	echo -n "Do you wish to test this device? (y/n): "
	read -n 4 go
	echo ""
	if [ "$go" != 'y' -a  "$go" != 'Y' -a  "$go" != 'yes'  -a  "$go" != 'Yes' -a "$go" != 'YES' ]; then
		echo "Please try with a different device.  Thanks!"
		exit 0
	fi
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
		echo "$DRIVER driver for interface `cat $f/bInterfaceNumber` does not support autosuspend."
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
# TODO: reset the files to the old values after testing the device.
OLD_WAIT=`cat "$SYSFS_DIR/power/autosuspend"`
OLD_LEVEL=`cat "$SYSFS_DIR/power/level"`
# Find the roothub that is the ancestor of the device in the tree.
PARENT="/sys/bus/usb/devices/usb$BUSNUM"
OLD_PARENT_LEVEL=`cat "$PARENT/power/level"`

# TODO: set the parent hub or roothub's level to on
# take activity time stamps for both device and parent hub,
# after setting the device level to off and waiting 2 seconds.
# sleep a short amount of time and sample again.
# Compare the difference between the parent (who we know is on)
# and the device (which should be autosuspended by now).
# If the delta activities are the same, then we know the device didn't autosuspend.

# Set level file to auto and monitor the activity using active_duration.
echo "Enabling auto-suspend"
# Don't want to wait too long...
echo 1 > "$SYSFS_DIR/power/autosuspend"
# Force the roothub to stay active to provide a time delta to compare against.
echo "on" > "$PARENT/power/level"
# Turn on auto-suspend for the device under test.
echo "auto" > "$SYSFS_DIR/power/level"
echo
echo "Waiting for device activity to cease..."
echo

sleep 2
PARENT_TIME=$(cat "$PARENT/power/active_duration")
TIME=$(cat "$SYSFS_DIR/power/active_duration")
# Be paranoid at this point about files, because the device might break and the
# files might go away.  FIXME this should probably be a function...
if [ ! $? ]; then
	echo "Device died?  Not enabling auto-suspend udev rule."
	# FIXME - offer to send a message that the device died?
	exit 1
fi

sleep 0.2
PARENT_TIME2=$(cat "$PARENT/power/active_duration")
TIME2=$(cat "$SYSFS_DIR/power/active_duration")
if [ ! $? ]; then
	echo "Device died?  Not enabling auto-suspend udev rule."
	# FIXME - offer to send a message that the device died?
	exit 1
fi

# Was the device's active time delta less than
# it's parent's active time delta?  If so, the device suspended successfully.
# The delta times can be off because of delay between the cat commands.
# Put in a slight buffer
if [ $(($TIME2 - $TIME)) -ge $((($PARENT_TIME2 - $PARENT_TIME) * 7 / 8)) ]; then
	echo "Device still active, test inconclusive."
	exit 1
fi


# Now test to see if the device correctly wakes up.

echo "Your device suspended correctly.  Now we need to make sure it wakes up."
echo "You should initiate device activity by using a program for that device."
# FIXME: have specific examples based on the driver for the USB device.
echo "For example, you might use the 'cheese' program to test a USB video camera"
echo "or the thinkfinger program to test a USB fingerprint reader."
echo "If you can't find a program to use, just hit enter at the next prompt."
echo

# Test remote wakeup?  Or just set level to on?
WAKEUP=`cat $SYSFS_DIR/power/wakeup`
if [ "$WAKEUP" = "enabled" ]; then
	echo "Remote wakeup is enabled for this device."
	echo "The device may be able to request wakeup out of the suspend state."
	echo "For example, a USB mouse may wakeup if you wiggle it or click a button,"
	echo "or a USB keyboard may wake up if you hit the CTRL key."
	echo
fi

echo "Type enter once you are actively using the device:"
# 5 minute timeout.  FIXME: can they skip this step if they don't plan on
# using the device?  I would rather they not, but if the USB device isn't
# supported, they should at least have good power management with it.
# Maybe offer to skip this step if there isn't a driver loaded for the device?
# Oh, wait, what about libusb userspace programs?
read -n 1 -t 300
echo

# Figure out if the device is active now
# FIXME: this is copy-paste code, make a function!
PARENT_TIME=$(cat "$PARENT/power/active_duration")
TIME=$(cat "$SYSFS_DIR/power/active_duration")
# Be paranoid at this point about files, because the device might break and the
# files might go away.  FIXME this should probably be a function...
if [ ! $? ]; then
	echo "Device died?  Not enabling auto-suspend udev rule."
	# FIXME - offer to send a message that the device died?
	exit 1
fi
# XXX: Not sure about this delta time value...
sleep 0.2
PARENT_TIME2=$(cat "$PARENT/power/active_duration")
TIME2=$(cat "$SYSFS_DIR/power/active_duration")
if [ ! $? ]; then
	echo "Device died?  Not enabling auto-suspend udev rule."
	# FIXME - offer to send a message that the device died?
	exit 1
fi

if [ $(($TIME2 - $TIME)) -le $((($PARENT_TIME2 - $PARENT_TIME) * 7 / 8)) ]; then
	echo "Device still suspended, test inconclusive."
	exit 1
fi


# Ask user: does this device still work?  E.g. mouse moves on screen, it prints,
# etc.  Record response.
echo "Device successfully resumed.  Does this device still work? (y/n):"
read -n 4 working
echo ""
if [ "$working" != 'y' -a  "$working" != 'Y' -a  "$working" != 'yes'  -a  "$working" != 'Yes' -a "$working" != 'YES' ]; then
	echo "What was wrong with the device: "
	read -n 500 notes
	echo ""
# FIXME make a bug report - might be something to do with the driver?
	exit 0
fi

# Clean up the root hub's files we messed with
echo $OLD_PARENT_LEVEL > "$PARENT/power/level"

# If the device didn't suspend properly, clean up the device files too.
# FIXME: do this later, clean them up always for now.
OLD_WAIT=`cat "$SYSFS_DIR/power/autosuspend"`
OLD_LEVEL=`cat "$SYSFS_DIR/power/level"`
# Find the roothub that is the ancestor of the device in the tree.

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
