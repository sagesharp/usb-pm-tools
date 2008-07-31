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

# Author: Sarah Sharp <sarah.a.sharp@intel.com>


# argument 1 is the device under test, e.g. /sys/bus/usb/devices/3-8/
if [[ $# -ne 1 || ! -d "$1" || ! -e "$1"/devnum ]]; then
	echo 'Usage `usb-suspend-test dev` where dev is e.g. /sys/bus/usb/devices/3-8'
	exit -1
fi
echo $1
DEVNUM=`cat "$1"/devnum`
BUSNUM=`cat "$1"/busnum`
lsusb -s $BUSNUM:$DEVNUM

# Does the user have CONFIG_USB_PM enabled?  I.e. is the power directory and
# level file there?  Suggest they also have CONFIG_USB_DEBUG turned on.
if [[ ! -d "$1"/power ]]; then
	echo 'Please make sure you have CONFIG_USB_PM enabled in your kernel'
	exit -1
fi

echo 'This test will enable a low power mode on your USB device.
It may cause broken devices to disconnect, lose your data, or stop responding.
Usually a reset or unplug-replug cycle will clear this error condition.
Please be careful when testing USB hard drives.'
echo -n "Do you wish to test this device ($BUSNUM:$DEVNUM)? (y/n): "
read -n 1 go
echo ""
if [[ $go == 'n' ||  $go == 'N' ]]; then
	echo "Please try with a different device.  Thanks!"
	exit 0
fi

# Do a simple suspend (on/off) test - warn the user before doing this so we
# don't crash their USB hard drive.  Perhaps ask the user if they want to do
# this?

# Do all the interface drivers support autosuspend?

# Set level file to auto and monitor the activity using urbnum.

# Test remote wakeup?  Or just set level to on?

# Ask user: does this device still work?  E.g. mouse moves on screen, it prints,
# etc.  Record response.

# TODO: figure out how to grab dmesg output, lsusb -v output for that device
# (and maybe all devices in the system, just in case they have a misbehaving hub
# in between?), does pci -vvv make sense to get host controller information?
# Also want /proc/bus/usb/ entry, right?
