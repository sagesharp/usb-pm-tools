#!/bin/sh
#
# Turn a file with one USB device VID:PID per line into udev rules that
# will enable auto-suspend for that USB device.  Test the device first
# to make sure it can correctly handle an autosuspend, using USB-PM tool
# if possible.
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
#
# Author: Sarah Sharp <sarah.a.sharp@linux.intel.com>

if [ $# -ne 1 ]; then
	echo 'Usage `vid-pid-to-udev-rule [input file]`'
	exit -1
fi

# Ignore root hubs, since all hubs have autosuspend enabled by default.
# The VID:PID for root hubs is 1d6b:0001 for USB 1.1 hubs
# and 1d6b:0002 for USB 2.0 hubs.

sed -r -e /1d6b:0001/d -e /1d6b:0002/d -e "s/([[:xdigit:]]{4}):([[:xdigit:]]{4})/SUBSYSTEMS==\"usb\", ATTR{idVendor}==\"\1\", ATTR{idProduct}==\"\2\", ATTR{power\/level}=\"auto\"/" $1
