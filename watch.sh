#!/usr/bin/env bash
# Emits one tab-separated line whenever the keyboard state changes:
#   caps num scroll wired dongle bluetooth <TAB> wired-name <TAB> dongle-name
# Reads sysfs only, with bash builtins, so the loop costs one `sleep` per tick.
# $1 = case-insensitive name match ("" = auto-detect).

match="${1,,}"
interval="${2:-0.4}"
mouse_re='mouse|trackball|g502|g pro|mx master|mx anywhere|deathadder|viper'
last=""

while :; do
  caps=0 num=0 scroll=0 wired=0 dongle=0 bt=0 wname="" dname="" led_dir=""

  for d in /sys/class/input/input*; do
    [ -r "$d/name" ] || continue
    IFS= read -r name < "$d/name"
    lname="${name,,}"
    IFS= read -r bus < "$d/id/bustype" 2>/dev/null || bus=""

    if [ -n "$match" ]; then
      [[ "$lname" == *"$match"* ]] || continue
    else
      # Auto: USB or Bluetooth nodes carrying a Caps Lock LED, minus mice.
      [[ "$bus" == 0003 || "$bus" == 0005 ]] || continue
      compgen -G "$d/input*::capslock" >/dev/null || continue
      [[ "$lname" =~ $mouse_re ]] && continue
    fi

    # Strip sub-interface suffixes so siblings share one display name.
    short="${name% Keyboard}"; short="${short% Consumer Control}"
    short="${short% System Control}"; short="${short% Mouse}"

    if [[ "$lname" == *dongle* || "$lname" == *2.4g* || "$lname" == *receiver* ]]; then
      dongle=1; [ -z "$dname" ] && dname="$short"
    elif [ "$bus" = 0005 ]; then
      bt=1; [ -z "$wname" ] && wname="$short"
    else
      wired=1; [ -z "$wname" ] && wname="$short"
    fi

    if [ -z "$led_dir" ]; then
      for l in "$d"/input*::capslock; do [ -e "$l" ] && led_dir="${l%::capslock}"; break; done
    fi
  done

  # Lock state is seat-wide, so any keyboard LED speaks for it.
  if [ -z "$led_dir" ]; then
    for l in /sys/class/leds/input*::capslock; do [ -e "$l" ] && led_dir="${l%::capslock}"; break; done
  fi
  if [ -n "$led_dir" ]; then
    read -r caps < "$led_dir::capslock/brightness" 2>/dev/null || caps=0
    read -r num < "$led_dir::numlock/brightness" 2>/dev/null || num=0
    read -r scroll < "$led_dir::scrolllock/brightness" 2>/dev/null || scroll=0
  fi
  [ "$caps" != 0 ] && caps=1; [ "$num" != 0 ] && num=1; [ "$scroll" != 0 ] && scroll=1

  line="$caps $num $scroll $wired $dongle $bt"$'\t'"$wname"$'\t'"$dname"
  if [ "$line" != "$last" ]; then
    printf '%s\n' "$line"
    last="$line"
  fi
  sleep "$interval"
done
