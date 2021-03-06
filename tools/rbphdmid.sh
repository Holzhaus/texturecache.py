#!/bin/sh

#
# Copyright (C) 2013 Neil MacLeod (rbphdmid@nmacleod.com)
#
# Hack to turn off HDMI power when XBMC screensaver
# has been active for the specified number of seconds.
# Default interval is 900 seconds, or 15 minutes.
#
# When the screensaver is disabled, HDMI power will be
# restored and XBMC restarted (Application.Quit()) so that
# the EGL context[1] may be re-established.
#
# If the screensaver is disabled before the power off interval,
# the interval will be cancelled.
#
# Arguments:
#  #1: Power off interval in seconds (after screensaver activated)
#  #2: Optional, enable debug with "-d"
#
# In OpenELEC, add the following line to the end of /storage/.config/autostart.sh:
#
# /storage/rbphdmid.sh &
#
# Requires: texturecache.py[2] in /storage with execute permissions.
#
# 1. http://forum.xbmc.org/showthread.php?tid=163016
# 2. https://github.com/MilhouseVH/texturecache.py
#
# Version 0.0.1
#

TVSERVICE=/usr/bin/tvservice
TEXTURECACHE=/storage/texturecache.py
TEXTURECACHE_ARGS="@xbmc.host=localhost @checkupdate=no @logfile="
DELAY=900
DEBUG=N
TIMERPID=0

while [ $1 ]; do
  case "$1" in
    -d|--debug) DEBUG=Y;;
    *) DELAY=$1;;
  esac
  shift
done

logmsg ()
{
  logger -t $(basename $0) "$1"
}

logdbg ()
{
  [ $DEBUG = Y ] && logmsg "$1"
}

enable_hdmi()
{
  if [ -n "$(${TVSERVICE} --status | grep "TV is off")" ]; then
    logdbg "Restoring HDMI power"
    ${TVSERVICE} --preferred >/dev/null
    ${TEXTURECACHE} ${TEXTURECACHE_ARGS} power exit
  fi
}

disable_hdmi()
{
  ${TVSERVICE} --off >/dev/null
}

start_timer()
{
  if [ ${TIMERPID} = 0 ]; then
    if [ -n "$(${TEXTURECACHE} ${TEXTURECACHE_ARGS} status | grep "^Player *: None$")" ]; then
      logdbg "HDMI power off in $1 seconds unless screensaver deactivated"
      (sleep $1 && disable_hdmi) & 
      TIMERPID=$!
    else
      logdbg "Not starting power off timer while a player is active"
    fi
  else
    logdbg "Power off timer already active - ignored"
  fi
}

stop_timer()
{
  # Check TIMERPID is still our scheduled call to disable_hdmi()...
  if [ ${TIMERPID} != 0 ]; then
    PIDS=" $(pidof $(basename $0)) "
    if [ -n "$(echo "${PIDS}" | grep " ${TIMERPID} ")" ]; then
      kill ${TIMERPID} 2>/dev/null
      if [ $? = 0 ]; then
        logdbg "Cancelled HDMI power off timer"
        sleep 1
      fi
    fi
    TIMERPID=0
  fi
}

#Check we can execute stuff
if [ ! -x ${TVSERVICE} -o ! -x ${TEXTURECACHE} ]; then
  logmsg "Cannot find ${TVSERVICE} or ${TEXTURECACHE} - exiting"
  exit 1
fi

#Exit if we're already running
if [ "$(pidof $(basename $0))" != "$$" ]; then
  logmsg "Already running - exiting"
  exit 1
fi

logmsg "Starting HDMI Power daemon for Raspberry Pi"
logmsg "HDMI Power off delay: ${DELAY} seconds"

while [ : ]; do
  SS_STATE=OFF

  logdbg "Establishing connection with XBMC..."

  ${TEXTURECACHE} ${TEXTURECACHE_ARGS} monitor 2>/dev/null | 
    while IFS= read -r line; do
      METHOD="$(echo "${line}" | awk '{x=$3; sub(":","",x); print x}')"

      if [ "${METHOD}" = "GUI.OnScreensaverActivated" ]; then
        logdbg "Screensaver activated"
        start_timer ${DELAY}
        SS_STATE=ON
      elif [ "${METHOD}" = "GUI.OnScreensaverDeactivated" ]; then
        logdbg "Screensaver deactivated"
        stop_timer
        enable_hdmi
        SS_STATE=OFF
      elif [ "${METHOD}" = "Player.OnStop" -a ${SS_STATE}=ON ]; then
        start_timer ${DELAY}
      fi
    done

  logdbg "Waiting for XBMC to (re)start"
  sleep 15
done
