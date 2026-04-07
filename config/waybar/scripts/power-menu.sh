#!/usr/bin/env bash

op=$( echo -e " Poweroff\n Reboot\n Suspend\n Lock\n Logout" | rofi -i -dmenu | awk '{print tolower($2)}' )

case $op in 
    poweroff)
    ;&
    reboot)
    ;&
    suspend)
        if command -v systemctl &>/dev/null; then
            systemctl $op
        else
            loginctl $op
        fi
        ;;
    lock)
		swaylock -c 000000
        ;;
    logout)
        swaymsg exit
        ;;
esac
