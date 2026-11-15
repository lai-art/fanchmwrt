#!/bin/sh
# Execute the action command ($2, e.g. AT+CMGD=x or at+cmgl=4), then list &
# decode all SMS with multipart reassembly into /tmp/smsc.at for the web UI.
# $1 = port index (kept for compatibility; sendat auto-detects the real port)
sendat "$1" "$2" >/dev/null 2>&1
sendat 1 at+cmgl=4 | pdu_decoder --list > /tmp/smsc.at
