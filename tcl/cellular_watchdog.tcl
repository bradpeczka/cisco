::cisco::eem::event_register_timer watchdog name cellular_watchdog.tcl time "$timer" maxrun 120

##-
# Copyright (c) 2015 Dan Frey <dafrey@cisco.com>
# Copyright (c) 2018 Brad Peczka <brad@bradpeczka.com>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY

# =====================================================================
# GSM Cellular Watchdog
# =====================================================================
##-
# Date     : 8 Nov 2018
# Version  : 1.0
#
# Description: GSM modems operating in areas of poor cellular service
# occasionally go offline, and will not try to reconnect.
#
# This policy monitors the health of the GSM modem and attempts to
# restart the modem if it goes into error or offline.
#
# Installation Steps
# Place this file on the router media, typically the flash drive.
# Execute these three CLI commands in global config mode:
# event manager environment timer 300
#	event manager directory user policy "flash:/scripts"
#	event manager policy <filename> type user
# 
# Timer should not be set to any less than 120 (seconds).
#
# For deployments that utilise TACACS, also add the following command:
# event manager session cli username "<username>"
# (Where <username> is a user with rights to run commands on the device)
#
# Debug via:
# debug event manager tcl cli_library
#
# Acknowledgements:
# Dan Frey <dafrey@cisco.com> for his "Restore LTE service"
# (restore_lte.tcl) script on which this is based.
# https://community.cisco.com/t5/network-architecture-documents/restore-lte-service/ta-p/3158356
######################################################################

namespace import ::cisco::eem::*
namespace import ::cisco::lib::*

if {![info exists timer]} {
    set result \
      "Policy cannot be run: variable timer has not been set"
    error $result $errorInfo
}

set oid "1.3.6.1.4.1.9.9.661.1.3.2.1.2"
array set status_arr [sys_reqinfo_snmp oid $oid get_type next]
set c3gGsmCurrentServiceStatus $status_arr(value)

foreach {element value} [array get status_arr] {
puts "$element $value"
}

set oid "1.3.6.1.4.1.9.9.661.1.3.2.1.3"
array set error_arr [sys_reqinfo_snmp oid $oid get_type next]
set c3gGsmCurrentServiceError $error_arr(value)

foreach {element value} [array get error_arr] {
puts "$element $value"
}

set oid "1.3.6.1.4.1.9.9.661.1.3.4.1.1.1"
array set error_arr [sys_reqinfo_snmp oid $oid get_type next]
set c3gCurrentGsmRssi $error_arr(value)

foreach {element value} [array get error_arr] {
puts "$element $value"
}

if {$c3gGsmCurrentServiceStatus != "3"} {
  if [catch {cli_open} result] {
    error $result $errorInfo
  } else {
    array set cli1 $result
  }
  # Go into enable mode
  if [catch {cli_exec $cli1(fd) "enable"} result] {
   error $result $errorInfo
  }
    if [catch {cli_exec $cli1(fd) "show run | inc ^interface Cellular" } intf ] {
   error $intf $errorInfo
  }

    regexp {(Cellular[0-9\/]+)} $intf -> interface
    regsub -all {r} $interface "r " interface

    action_syslog msg "ERROR: Abnormal Service Status ($c3gGsmCurrentServiceStatus). Power cycling Cellular radio now."
    if [catch {cli_exec $cli1(fd) "test $interface modem-power-cycle" } result ] {
      error $result $errorInfo
    }
     puts "\nwaiting 30 seconds\n"
     after 30000
     array set status_arr [sys_reqinfo_snmp oid 1.3.6.1.4.1.9.9.661.1.3.2.1.2 get_type next]
     set c3gGsmCurrentServiceStatus $status_arr(value)
     action_syslog msg "INFO: Cellular modem status is now $c3gGsmCurrentServiceStatus. Current RSSI is $c3gCurrentGsmRssi."

  if [catch {cli_exec $cli1(fd) "show $interface network" } result ] {
     error $result $errorInfo
  }
  puts "\n#####Cellular Network Attributes######
  $result
  \n"
   catch {cli_close $cli1(fd) $cli1(tty_id)}
} else {
  if {$c3gGsmCurrentServiceError != "2"} {
    if [catch {cli_open} result] {
      error $result $errorInfo
    } else {
      array set cli1 $result
    }
    # Go into enable mode
    if [catch {cli_exec $cli1(fd) "enable"} result] {
     error $result $errorInfo
    }
      if [catch {cli_exec $cli1(fd) "show run | inc ^interface Cellular" } intf ] {
     error $intf $errorInfo
    }

      regexp {(Cellular[0-9\/]+)} $intf -> interface
      regsub -all {r} $interface "r " interface

      action_syslog msg "ERROR: Abnormal Service Error ($c3gGsmCurrentServiceError). Power cycling Cellular radio now."
      if [catch {cli_exec $cli1(fd) "test $interface modem-power-cycle" } result ] {
        error $result $errorInfo
      }
       puts "\nwaiting 30 seconds\n"
       after 30000
       array set error_arr [sys_reqinfo_snmp oid 1.3.6.1.4.1.9.9.661.1.3.2.1.3 get_type next]
       set c3gGsmCurrentServiceError $error_arr(value)
       action_syslog msg "INFO: Cellular modem error is now $c3gGsmCurrentServiceError. Current RSSI is $c3gCurrentGsmRssi."

    if [catch {cli_exec $cli1(fd) "show $interface network" } result ] {
       error $result $errorInfo
    }
    puts "\n#####Cellular Network Attributes######
    $result
    \n"
     catch {cli_close $cli1(fd) $cli1(tty_id)}
    } else {
      action_syslog msg "INFO: Cellular Modem Status: $c3gGsmCurrentServiceStatus, Error Code: $c3gGsmCurrentServiceError, RSSI $c3gCurrentGsmRssi - no action required."
    }
}
