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
echo "Copyright (c) 2008 Intel Corporation"
echo "Author Sarah Sharp <sarah.a.sharp@linux.intel.com>"
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
	echo "    WARNING: This test may cause broken devices to disconnect or"
	echo "    stop responding.  Usually a reset or unplug-replug cycle will"
	echo "    clear this error condition."
	echo ""

	exit 0
else
	echo 'Type `./usb-pm-tool.sh --help` for more info'
	echo
fi

USB_PM_TOOL_DIR="/etc/usb-pm-tool/"
SAFE_DEVS_FILE=$USB_PM_TOOL_DIR"pm-enabled-devices.txt"
UNSAFE_DEVS_FILE=$USB_PM_TOOL_DIR"pm-broken-devices.txt"

if [ ! -d $USB_PM_TOOL_DIR ]; then
	if ! mkdir $USB_PM_TOOL_DIR; then
		echo "usb-pm-tool.sh must be run as root"
		exit -1
	fi
	touch $SAFE_DEVS_FILE
	chmod go= $SAFE_DEVS_FILE
	touch $UNSAFE_DEVS_FILE
	chmod go= $UNSAFE_DEVS_FILE
else
	if ! cat $SAFE_DEVS_FILE > /dev/null; then
		echo "usb-pm-tool.sh must be run as root"
		exit -1
	fi
fi


# Find all USB devices on the system
DEVS_FILE=/tmp/usb-pm-devices.txt
lsusb | grep -v -e ".*ID 1d6b:000.*" -e ".*ID 0000:000.*" > $DEVS_FILE

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
echo
echo -n "Which USB device would you like to test (0 cancels test): "
# Can't have more than 255 devices plugged in anyway...
read -n 3 devnum
echo ""
MAX_DEVNUM=`cat $DEVS_FILE | wc -l`
if [ "$devnum" -eq "0" ]; then
	exit 0
fi
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
echo -n "Enabling auto-suspend.  "
# Don't want to wait too long...
echo 1 > "$SYSFS_DIR/power/autosuspend"
# Force the roothub to stay active to provide a time delta to compare against.
echo "on" > "$PARENT/power/level"
# Turn on auto-suspend for the device under test.
echo "auto" > "$SYSFS_DIR/power/level"
echo "Waiting for device activity to cease..."
echo

sleep 2
PARENT_TIME=$(cat "$PARENT/power/active_duration")
# Be paranoid at this point about files, because the device might break and the
# files might go away.  FIXME this should probably be a function...
if ! TIME=$(cat "$SYSFS_DIR/power/active_duration"); then
	echo "Device died?  Not enabling auto-suspend udev rule."
	# Clean up
	echo $OLD_PARENT_LEVEL > "$PARENT/power/level"
	# FIXME - offer to send a message that the device died?
	exit 1
fi

sleep 0.2
PARENT_TIME2=$(cat "$PARENT/power/active_duration")
if ! TIME2=$(cat "$SYSFS_DIR/power/active_duration"); then
	echo "Device died?  Not enabling auto-suspend udev rule."
	# Clean up
	echo $OLD_PARENT_LEVEL > "$PARENT/power/level"
	# FIXME - offer to send a message that the device died?
	exit 1
fi

# Was the device's active time delta less than
# it's parent's active time delta?  If so, the device suspended successfully.
# The delta times can be off because of delay between the cat commands.
# Put in a slight buffer
if [ $(($TIME2 - $TIME)) -ge $((($PARENT_TIME2 - $PARENT_TIME) * 7 / 8)) ]; then
	echo "Device still active, test inconclusive."
	# Clean up
	echo $OLD_WAIT > "$SYSFS_DIR/power/autosuspend"
	echo $OLD_LEVEL > "$SYSFS_DIR/power/level"
	echo $OLD_PARENT_LEVEL > "$PARENT/power/level"
	exit 1
fi


# Now test to see if the device correctly wakes up.

echo "Your device suspended correctly.  Now we need to make sure it wakes up."
echo
echo "You should initiate device activity by using a program for that device."
# FIXME: have specific examples based on the driver for the USB device.
echo "For example, you might use the cheese program to test a USB video camera,"
echo "or the thinkfinger program to test a USB fingerprint reader."
# Glossing over remote wakeup for now.
echo "If you have a USB mouse or keyboard, you can hit a button to wakeup the device."
echo


# Take the first sample before prompting the user to activate the device.
# This way the user won't need to be actively using the device when they
# press enter.  FIXME: this is copy-paste code, make a function!
if ! URB_NUM1=$(cat "$SYSFS_DIR/urbnum"); then
	echo "Device died?  Not enabling auto-suspend udev rule."
	echo "Appending VID:PID $VID:$PID to $UNSAFE_DEVS_FILE"
	# Avoid duplicate entries
	if ! grep -q "$VID:$PID" $UNSAFE_DEVS_FILE; then
		echo "$VID:$PID" >> $UNSAFE_DEVS_FILE
	fi
	# Clean up
	echo $OLD_PARENT_LEVEL > "$PARENT/power/level"
	# FIXME - offer to send a message that the device died?
	exit 1
fi

echo -n "Type enter once you are actively using the device:"
# 5 minute timeout.  FIXME: can they skip this step if they don't plan on
# using the device?  I would rather they not, but if the USB device isn't
# supported, they should at least have good power management with it.
# Maybe offer to skip this step if there isn't a driver loaded for the device?
# Oh, wait, what about libusb userspace programs?
read -n 1 -t 300
echo

if ! URB_NUM2=$(cat "$SYSFS_DIR/urbnum"); then
	echo "Device died?  Not enabling auto-suspend udev rule."
	echo "Appending VID:PID $VID:$PID to $UNSAFE_DEVS_FILE"
	# Avoid duplicate entries
	if ! grep -q "$VID:$PID" $UNSAFE_DEVS_FILE; then
		echo "$VID:$PID" >> $UNSAFE_DEVS_FILE
	fi
	# Clean up
	echo $OLD_PARENT_LEVEL > "$PARENT/power/level"
	# FIXME - offer to send a message that the device died?
	exit 1
fi

if [ $URB_NUM1 -eq $URB_NUM2 ]; then
	echo "Device still suspended, test inconclusive."
	# Clean up
	echo $OLD_WAIT > "$SYSFS_DIR/power/autosuspend"
	echo $OLD_LEVEL > "$SYSFS_DIR/power/level"
	echo $OLD_PARENT_LEVEL > "$PARENT/power/level"
	exit 1
fi


# Ask user: does this device still work?  E.g. mouse moves on screen, it prints,
# etc.  Record response.
echo -n "Device successfully resumed.  Does this device still work? (y/n): "
read -n 4 working
echo ""
if [ "$working" != 'y' -a  "$working" != 'Y' -a  "$working" != 'yes'  -a  "$working" != 'Yes' -a "$working" != 'YES' ]; then
	SUCCESS=0
	echo "What was wrong with the device: "
	read -n 500 -t 300 notes
	echo ""
	# FIXME make a bug report - might be something to do with the driver?
	# If the device didn't suspend properly, clean up the device pm files
	# and make it so the device will always be on.
	echo "Disabling auto-suspend for this device."
	echo $OLD_WAIT > "$SYSFS_DIR/power/autosuspend"
	echo "on" > "$SYSFS_DIR/power/level"
	echo "Appending VID:PID $VID:$PID to $UNSAFE_DEVS_FILE"
	# Avoid duplicate entries
	if ! grep -q "$VID:$PID" $UNSAFE_DEVS_FILE; then
		echo "$VID:$PID" >> $UNSAFE_DEVS_FILE
	fi
else
	SUCCESS=1
	echo "You can enable auto-suspend for this device whenever it is"
	echo "plugged into the system.  This step will append the device's"
	echo "vendor and product ID to $SAFE_DEVS_FILE"
	echo "and regenerate udev rules in /etc/udev/rules.d/025_usb-autosuspend.rules."
	echo
	echo "Do you want to always enable auto-suspend for this device?"
	echo -n "This will decrease system power consumption.  (y/n): "
	read -n 4 rule
	echo ""
	if [ "$rule" == 'y' -o  "$rule" == 'Y' -o  "$rule" == 'yes'  -o  "$rule" == 'Yes' -o "$rule" == 'YES' ]; then
		# Avoid duplicate entries
		if ! grep -q "$VID:$PID" $SAFE_DEVS_FILE; then
			echo "$VID:$PID" >> $SAFE_DEVS_FILE
		fi
		if ! ./vid-pid-to-udev-rule.sh $SAFE_DEVS_FILE; then
			echo "WARNING: could not regenerate udev rules."
			echo "Is vid-pid-to-udev-rule.sh in the current directory?"
		fi
	fi
fi

# Clean up the root hub's files we messed with
echo $OLD_PARENT_LEVEL > "$PARENT/power/level"


# Ask user if they want to send an HTTP post report.  Tell them their IP address
# will not be used to identify which USB devices they own.

# Ask them to enter their email address if they wish to be contacted by Linux
# kernel USB developers.

# TODO: figure out how to grab dmesg output, lsusb -v output for that device
# (and maybe all devices in the system, just in case they have a misbehaving hub
# in between?), does pci -vvv make sense to get host controller information?
# Also want /proc/bus/usb/ entry, right?
