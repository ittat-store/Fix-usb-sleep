#!/bin/sh

#  ramdisk.sh
#  
#
#  Created by syscl/lighting/Yating Zhou on 16/4/9.
#

#================================= GLOBAL VARS ==================================

#
# The script expects '0.5' but non-US localizations use '0,5' so we export
# LC_NUMERIC here (for the duration of the deploy.sh) to prevent errors.
#
export LC_NUMERIC="en_US.UTF-8"

#
# Prevent non-printable/control characters.
#
unset GREP_OPTIONS
unset GREP_COLORS
unset GREP_COLOR

#
# Display style setting.
#
BOLD="\033[1m"
RED="\033[1;31m"
GREEN="\033[1;32m"
BLUE="\033[1;34m"
OFF="\033[m"

#
# Located repository.
#
REPO=$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )

#
# Define vars.
#
gArgv=""
gDebug=1
gVirt=""
gR_NAME=RAMDISK
gMnt=1
gVirtual_Disk=$(diskutil list | grep -i "disk image" | sed -e "s| (disk image):||" | awk -F'\/' '{print $3}')
gRAMDISK="/Volumes/$gR_NAME"
gUSR_Size=""
gAlloc_RAM=""

#
# Path and filename setup.
#
gConfig="/tmp/com.syscl.ramdisk.plist"
gRAMScript=$(echo $0)

#
#--------------------------------------------------------------------------------
#

function _PRINT_MSG()
{
    local message=$1

    case "$message" in
      OK*    ) local message=$(echo $message | sed -e 's/.*OK://')
               echo "[  ${GREEN}OK${OFF}  ] ${message}."
               ;;

      FAILED*) local message=$(echo $message | sed -e 's/.*://')
               echo "[${RED}FAILED${OFF}] ${message}."
               ;;

      ---*   ) local message=$(echo $message | sed -e 's/.*--->://')
               echo "[ ${GREEN}--->${OFF} ] ${message}"
               ;;

      NOTE*  ) local message=$(echo $message | sed -e 's/.*NOTE://')
               echo "[ ${RED}Note${OFF} ] ${message}."
               ;;
    esac
}

#
#--------------------------------------------------------------------------------
#

function tidy_execute()
{
    if [ $gDebug -eq 0 ];
      then
        #
        # Using debug mode to output all the details.
        #
        _PRINT_MSG "DEBUG: $2"
        $1
      else
        #
        # Make the output clear.
        #
        $1 >/tmp/report 2>&1 && RETURN_VAL=0 || RETURN_VAL=1

        if [ "${RETURN_VAL}" == 0 ];
          then
            _PRINT_MSG "OK: $2"
          else
            _PRINT_MSG "FAILED: $2"
            cat /tmp/report
        fi

        rm /tmp/report &> /dev/null
    fi
}

#
#--------------------------------------------------------------------------------
#

function _initCache()
{
    #
    # Check if virtual disk has been mounted.
    #
    for disk in ${gVirtual_Disk[@]}
    do
      _checkRAM ${disk}
    done

    #
    # Mount RAMDSIK.
    #
    if [ $gMnt -eq 1 ];
      then
        diskutil erasevolume HFS+ ${gR_NAME} `hdiutil attach -nomount ram://$(($gAlloc_RAM * 2))`
    fi

    #
    # Create target dir.
    #
    mkdir -p $gRAMDISK/Library/Developer/Xcode/DerivedData
    mkdir -p $gRAMDISK/Library/Developer/CoreSimulator/Devices
    mkdir -p $gRAMDISK/Library/Caches/Google
    mkdir -p $gRAMDISK/Library/Caches/com.apple.Safari/fsCachedData
    mkdir -p $gRAMDISK/Library/Caches/Firefox
}

#
#--------------------------------------------------------------------------------
#

function _checkRAM()
{
    #
    # Check if virtual disk is mounted.
    #
    local gDev=$1
    gVirt=$(diskutil info $gDev | grep -i "Virtual" | tr '[:lower:]' '[:upper:]')

    if [[ "$gVirt" == *"YES"* ]];
      then
        #
        # Yes, virtual disk exist.
        #
        gMnt=1
        gR_NAME=$(diskutil list | grep -i "$gDev" | tail -n1 | awk  '{print $2}')
      else
        #
        # No, we need to mount virtual disk.
        #
        gMnt=0
    fi

}

#
#--------------------------------------------------------------------------------
#

function _printConfig()
{
    if [ -f ${gConfig} ];
      then
        rm ${gConfig}
    fi

    echo '<?xml version="1.0" encoding="UTF-8"?>'                                                                                                           > "$gConfig"
    echo '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'                                          >> "$gConfig"
    echo '<plist version="1.0">'                                                                                                                           >> "$gConfig"
    echo '<dict>'                                                                                                                                          >> "$gConfig"
    echo '	<key>KeepAlive</key>'                                                                                                                          >> "$gConfig"
    echo '	<false/>'                                                                                                                                      >> "$gConfig"
    echo '	<key>Label</key>'                                                                                                                              >> "$gConfig"
    echo '	<string>com.syscl.ramdisk</string>'                                                                                                            >> "$gConfig"
    echo '	<key>ProgramArguments</key>'                                                                                                                   >> "$gConfig"
    echo '	<array>'                                                                                                                                       >> "$gConfig"
    echo "		<string>/etc/syscl.ramdisk</string>"                                                                                                       >> "$gConfig"
    echo "		<string>-a $gUSR_Size</string>"                                                                                                            >> "$gConfig"
    echo '	</array>'                                                                                                                                      >> "$gConfig"
    echo '	<key>RunAtLoad</key>'                                                                                                                          >> "$gConfig"
    echo '	<true/>'                                                                                                                                       >> "$gConfig"
    echo '</dict>'                                                                                                                                         >> "$gConfig"
    echo '</plist>'                                                                                                                                        >> "$gConfig"
}

#
#--------------------------------------------------------------------------------
#

function _install_launch()
{
    _gRAM_Size
    _PRINT_MSG "--->: Install syscl.ramdisk..."
    _PRINT_MSG "NOTE: Ramdisk size is: $gUSR_Size""MB"
    tidy_execute "_printConfig" "Generate configuration file of syscl.ramdisk launch daemon"
    tidy_execute "sudo cp "${gConfig}" "/Library/LaunchDaemons"" "Install configuration of ramdisk daemon"
    tidy_execute "sudo cp "${gRAMScript}" "/etc/syscl.ramdisk"" "Install ramdisk script"
    tidy_execute "sudo chmod 744 /etc/syscl.ramdisk" "Fix permission"
    tidy_execute "sudo chown root:wheel /etc/syscl.ramdisk" "Fix own wheel"
    tidy_execute "sudo launchctl load /Library/LaunchDaemons/com.syscl.ramdisk.plist" "Trigger startup service of syscl.ramdisk"
    tidy_execute "rm $gConfig" "Clean up"
}

#
#--------------------------------------------------------------------------------
#

function _uninstall_ramdisk
{
    _PRINT_MSG "--->: Uninstalling syscl.ramdisk..."
    #
    # Unload service(s).
    #
    tidy_execute "sudo launchctl unload /Library/LaunchDaemons/com.syscl.ramdisk.plist" "Unload com.syscl.ramdisk.plist service"
    if [ -f /Library/LaunchDaemons/com.syscl.ramdisk.plist ];
      then
        tidy_execute "sudo rm /Library/LaunchDaemons/com.syscl.ramdisk.plist" "Remove service config file(s)"
    fi

    #
    # Remove target dir(s).
    #
    if [ -d $gRAMDISK/Library/ ];
      then
        tidy_execute "sudo rm -R $gRAMDISK/Library/" "Remove target directories"
    fi

    #
    # Remove syscl.ramdisk
    #
    if [ -f /etc/syscl.ramdisk ];
      then
        tidy_execute "sudo rm /etc/syscl.ramdisk" "Remove syscl.ramdisk"
    fi

    #
    # Detach virtual disk(s).
    #
    for disk in ${gVirtual_Disk[@]}
    do
      gVirt=$(diskutil info ${disk} | grep -i "Virtual" | tr '[:lower:]' '[:upper:]')

      if [[ "$gVirt" == *"YES"* ]];
        then
          tidy_execute "diskutil eject ${disk}" "Eject ${disk}"
      fi

    done

    _PRINT_MSG "NOTE: UNINSTALL has been finished"
}

#
#--------------------------------------------------------------------------------
#

function _gRAM_Size()
{
    local gMEM_Size=$(sysctl hw.memsize | sed -e 's/.*: //')
    local gRAM_UPPER=$(_setDEFAULT_RAM $gMEM_Size)
    read -p "Enter ramdisk size, e.g. 1024M, 2048M, etc...: " gUSR_Size

    if [ -z $gUSR_Size ];
      then
        #
        # Zero size, use default setting.
        #
        gAlloc_RAM=$gRAM_UPPER
        gUSR_Size=$(_reverse_Size $gAlloc_RAM)
      else
        #
        # User define.
        #
        # Check if user define size is greater than memory size?
        #
        gAlloc_RAM=$(_convert_Size $gUSR_Size)
    fi

    if [ $gAlloc_RAM -gt $gRAM_UPPER ];
      then
        _PRINT_MSG "NOTE: Assertion failed: ${BLUE}gAlloc_RAM${OFF} ${GREEN}<=${OFF} ${BLUE}gRAM_UPPER${OFF}"
        _PRINT_MSG "NOTE: Please enter valid ramdisk size"
        _gRAM_Size
      else
        #
        # Transfer user define size.
        #
        gAlloc_RAM=${gUSR_Size}
    fi
}

#
#--------------------------------------------------------------------------------
#

function _setDEFAULT_RAM()
{
    #
    # Default ramdisk size cannot greater than 2/3 hardware memory size.
    #
    echo $(($1 * 2 / 3 / 1024))
}

#
#--------------------------------------------------------------------------------
#

function _convert_Size()
{
    #
    # Convert MBytes to KBytes.
    #
    local gTEMP_Size=$(echo $1 | sed  -e 's/M.*//')
    echo $(($gTEMP_Size * 1024))
}

#
#--------------------------------------------------------------------------------
#

function _reverse_Size()
{
    #
    # Reverse KBytes to MBytes.
    #
    echo $(($1 / 1024))
}

#
#--------------------------------------------------------------------------------
#

function main()
{
    #
    # Get argument.
    #
    gArgv=$(echo "$@" | tr '[:lower:]' '[:upper:]')
    if [[ "$gArgv" == *"-D"* || "$gArgv" == *"-DEBUG"* ]];
      then
        #
        # Yes, we do need debug mode.
        #
        _PRINT_MSG "NOTE: Use ${BLUE}DEBUG${OFF} mode"
        gDebug=0
      else
        #
        # No, we need a clean output style.
        #
        gDebug=1
    fi

    #
    # Detect which progress to execute.
    #
    if [[ "${REPO}" == "/etc" ]];
      then
        #
        # Create virtual disk.
        #

        gAlloc_RAM=$(_convert_Size `awk '/<string>-a.*/,/<\/string>/' /Library/LaunchDaemons/com.syscl.ramdisk.plist | sed -e 's/.*-a //' -e 's/-.*//' -e 's/M.*//' -e 's/<.*//'`)
        _initCache
      else
        if [[ "$gArgv" == *"-U"* || "$gArgv" == *"-UNINSTALL"* ]];
          then
            #
            # "-u" found, uninstall syscl.ramdisk.
            #
            _uninstall_ramdisk
          else
            #
            # Install syscl.ramdisk.
            #
            _install_launch
        fi
    fi
}

#==================================== START =====================================

main "$@"

exit 0

#================================================================================