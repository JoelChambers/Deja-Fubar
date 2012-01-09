#!/bin/sh

DIR=`dirname $0`

if [ $DIR == '.' ]; then
  DIR=`pwd`
fi

if [ $# -eq 1 ]; then
  DIR=$1
fi

CONFIGDIR=$DIR/config
STOREDIR=$DIR/storage
SCRIPTDIR=$DIR/scripts

SUBJECTLINE="DBF device differences"

DIFFFLAGS="-u"
NULLFILE="/dev/null"

DEBUG=0

function debug {
  toprint="$1"
  if [ $DEBUG == 1 ]; then
    echo "$toprint"
  fi
}

function error {
  toprint="$1"

  echo "$toprint"
}

function do_device {
  DEVICEGROUP="$1"
  DEVICENAME="$2"
  DEVICETYPE="$3"
  ARGS="$4"
  OUTFILE=`mktemp -t`
  ARGS="$ARGS\nOutFile=$OUTFILE\nDeviceName=$DEVICENAME\nDeviceGroup=$DEVICEGROUP"
  LASTFILE="$STOREDIR/$DEVICEGROUP/$DEVICENAME-last"
  NEXTFILE="$STOREDIR/$DEVICEGROUP/$DEVICENAME-`date +%F_%T`"
  DIFFFILE="$STOREDIR/$DEVICEGROUP/$DEVICENAME-`date +%F_%T`.diff"
  
  debug do_device "$DEVICENAME" "$DEVICETYPE"
  
  if [ ! -f "$SCRIPTDIR/dfb-$DEVICETYPE" ]; then
    error "Error: script for device type \"$DEVICETYPE\" does not exist (group \"$GROUPNAME\" DEVICE \"$DEVICENAME\")"
    return 1;
  fi
  if [ ! -x "$SCRIPTDIR/dfb-$DEVICETYPE" ]; then
    error "Error: script for device type \"$DEVICETYPE\" is not marked executable (group \"$GROUPNAME\" DEVICE \"$DEVICENAME\")"
    return 1;
  fi
  echo -e "$ARGS" | "$SCRIPTDIR/dfb-$DEVICETYPE"
  # do error-checking
  if [ $? != 0 ]; then
    error "$DEVICEGROUP:$DEVICENAME: $SCRIPTDIR/dfb-$DEVICETYPE error"
    return 1
  fi
  
  # do comparison
  mv "$OUTFILE" "$NEXTFILE"

  if [ ! -f "$LASTFILE" ]; then
    ln -s "$NULLFILE" "$LASTFILE"
  fi
  diff $DIFFFLAGS "$LASTFILE" "$NEXTFILE" > "$DIFFFILE"
  if [ $? == 0 ]; then
    # files are identical
    rm -f "$DIFFFILE" "$NEXTFILE"
  elif [ $? == 1 ]; then
    # files differ
    debug "$DEVICEGROUP:$DEVICENAME: found differences!"
    cat "$DIFFFILE" >> "$MAILFILE"

    rm "$LASTFILE"; ln -s "$NEXTFILE" "$LASTFILE"
  fi
}

function do_group {
  GROUPFILE="$1"
  GROUPNAME=`basename "$GROUPFILE"`
  
  MAILFILE=`mktemp -t`

  debug "do_group $GROUPNAME using file $GROUPFILE"
  
  if [ ! -d "$STOREDIR/$GROUPNAME" ]; then
    debug "do_group: creating \"$STOREDIR/$GROUPNAME\""
    mkdir -p "$STOREDIR/$GROUPNAME"
  fi
  contents=`cat "$GROUPFILE"|sed -e 's/#.*//' -e 's/[ ^I]*$//' -e '/^$/ d'`
  OLDIFS="$IFS"
  IFS=$'\n'
  GLOBALS=""
  PERDEVICE=""
  DEVICENAME=""
  DEVICETYPE=""
  GLOBALTYPE=""
  MAILTO=""

  for line in $contents; do
    if [ ${line:0:1} != "[" ]; then
      # not a new device definition
      if [ -z "$DEVICENAME" ]; then
        GLOBALS="$GLOBALS\n$line"
        if [ ${line:0:5} == 'Type=' ]; then
          GLOBALTYPE="${line:5}"
        elif [ ${line:0:7} == 'MailTo=' ]; then
          MAILTO="${line:7}"
        fi
      else
        PERDEVICE="$PERDEVICE\n$line"
        if [ ${line:0:5} == 'Type=' ]; then
          DEVICETYPE="${line:5}"
        fi
      fi
    else
      #new device definition
      if [ ! -z "$DEVICENAME" ]; then
        # take care of the previous DEVICE
        if [[ -z "$DEVICETYPE" ]] && [[ ! -z "$GLOBALTYPE" ]]; then
          DEVICETYPE="$GLOBALTYPE"
        fi
        do_device "$GROUPNAME" "$DEVICENAME" "$DEVICETYPE" "$GLOBALS\n$PERDEVICE"
      fi
      DEVICENAME=""
      DEVICETYPE=""
      PERDEVICE=""
      bracketOffset=`expr index $line ]`
      DEVICENAME="${line:1:$[bracketOffset-2]}"
    fi
  done
  
  if [ ! -z "$DEVICENAME" ]; then
    # take care of the last device
    if [[ -z "$DEVICETYPE" ]] && [[ ! -z "$GLOBALTYPE" ]]; then
          DEVICETYPE="$GLOBALTYPE"
    fi
    do_device "$GROUPNAME" "$DEVICENAME" "$DEVICETYPE" "$GLOBALS\n$PERDEVICE"
  fi
  IFS="$OLDIFS"

  if [[ ! -z "$MAILTO" ]] && [[ -s "$MAILFILE" ]]; then
    mail -s "$SUBJECTLINE: Group $GROUPNAME" "$MAILTO" < "$MAILFILE"
  fi

  rm -rf "$MAILFILE"
}

for group in $CONFIGDIR/*; do
  do_group "$group"
done

