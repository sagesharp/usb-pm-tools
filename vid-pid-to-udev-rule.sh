#!/bin/sh
#
# Turn a file with one USB device VID:PID per line into a udev rules
# file that will enable auto-suspend for that USB device.  Test the
# device first to make sure it can correctly handle an autosuspend,
# using USB-PM tool if possible.
#
# Copyright (c) 2008, Intel Corporation.
#
# This program is free software; you can redistribute it and/or modify
# it under the terms and conditions of the GNU General Public License,
# version 2, as published by the Free Software Foundation.
#
# This program is distributed in the hope it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
# for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin St - Fifth Floor, Boston, MA 02110-1301
# USA.
#
# Author: Sarah Sharp <sarah.a.sharp@linux.intel.com>

OUTFILE="/etc/udev/usb-autosuspend.rules"
UDEV_RULE="/etc/udev/rules.d/025_usb-autosuspend.rules"

if [ $# -ne 1 ]; then
	echo 'Usage `vid-pid-to-udev-rule [input file]`'
	exit -1
fi

# Specify that this udev rule should only run for USB devices,
# and only when the USB device is first connected (i.e. added).

echo "Regenerating udev rule file $OUTFILE"
echo "from PID:VID list in $1"

echo '# udev rules file for enabling autosuspend for USB devices on device connect.' > $OUTFILE
echo '# This file is automatically generated.  Do not edit.' >> $OUTFILE
echo '#' >> $OUTFILE
echo 'SUBSYSTEM!="usb", GOTO="usb-autosuspend_rules_end"' >> $OUTFILE
echo 'ACTION!="add", GOTO="usb-autosuspend_rules_end"' >> $OUTFILE
echo >> $OUTFILE

# Ignore root hubs, since all hubs have autosuspend enabled by default.
# The VID:PID for root hubs is 1d6b:0001 for USB 1.1 hubs
# 1d6b:0002 for USB 2.0 hubs, and 1d6b:0003 for USB 3.0 hubs.
# Turn on autosuspend by setting
# 	/sys/bus/usb/devices/<device>/power/level to auto
# It is "on" by default for all peripherial (non-hub) devices.

# If there is a number after the VID:PID, assume it's the number of seconds of
# idleness before the USB core suspends the device (default is 2, 0 means
# suspend immediately).
sed -r -e '/1d6b:000[1-3]/d' -e "s/([[:xdigit:]]{4}):([[:xdigit:]]{4})$/ATTR{idVendor}==\"\1\", ATTR{idProduct}==\"\2\", ATTR{power\/level}=\"auto\"/" -e "s/([[:xdigit:]]{4}):([[:xdigit:]]{4}) ([[:xdigit:]])/ATTR{idVendor}==\"\1\", ATTR{idProduct}==\"\2\", ATTR{power\/level}=\"auto\", ATTR{power\/autosuspend}=\"\3\"/" $1 >> $OUTFILE

echo >> $OUTFILE
echo 'LABEL="usb-autosuspend_rules_end"' >> $OUTFILE

chmod 644 $OUTFILE

echo
echo "Symlinking $UDEV_RULE"
echo "to $OUTFILE"
if [ -e $UDEV_RULE ]; then
	rm $UDEV_RULE
fi
ln -s $OUTFILE $UDEV_RULE
/etc/init.d/udev restart
