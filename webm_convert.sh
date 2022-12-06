#/bin/bash

# webm_convert.sh V. 0.3
#
# Created by Lars Kirches on 2020-09-13.
# Copyright (c) 2020 acidWEB All rights reserved.
#
# Script to Convert Recursive folder in webm v9 Format. 
# Once git is installed it only makes sense to use git to update git.
#



threads="4"
speed="3"


YELLOW='\033[1;33m'
BLUE='\033[0;34m'
RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

_SELF=${BASH_SOURCE[0]};
_DATE=$(date '+%Y-%m-%d-%H-%M')
_LOG="/var/log/$(basename $_SELF).log"
_PIDFILE="/tmp/$(basename $_SELF).pid"
_LASTRUN_FILE="/tmp/$(basename $_SELF).last"
_MAIL="acid2542@gmail.com"
_TTY="/dev/tty11"

exec &> >(tee -a "$_LOG" "$_TTY")
echo "OUTPUT: $(tty) | $_LOG | $_TTY"


function delete_pid_file
    {
    if [ -f "${_PIDFILE}" ]; then
        rm "$_PIDFILE"
        if [ $? -eq 0 ]; then
            :
        else
            echo "ERROR: deleting $_PIDFILE"
        fi
    fi
    }

function running_once
    {
    if [ -f "${_PIDFILE}" ]; then
        logger warning "##### $(basename $_SELF) can only run once."
        echo -e "${RED}$(basename $_SELF) can only run once. $_PIDFILE exists ${NC}"
        echo -e "${CYAN}type: tail -f $_LOG to watch result.${NC}"
        exit 1
    else
        logger notice "##### $_DATE - START | SCRIPT: $_SELF | USER: $USER"
        echo "$_DATE - START | $_SELF | USER: $USER"
        echo "$$" > "$_PIDFILE"
    fi
    }

INPUT=$1
if [[ -z "$INPUT" ]]; then 
    echo -e "${RED}[ ERROR ]${NC} use: $(basename $0) ${GREEN}<DIR>/<File>${NC}"
    exit 1
fi


if [[ -d "${INPUT}" ]]; then 
    echo -e "${BLUE}[ DIR ]${NC} RUNNING ON ${GREEN}${INPUT}${NC}"
    trap 'delete_pid_file; exit' SIGHUP SIGINT SIGQUIT EXIT SIGINT
    clear
    running_once
    #find "$INPUT" -type f \( -iname "*.avi" -o -iname "*.mpg" -o -iname "*.mpeg" -o -iname "*.mkv" -o -iname "*.mp4" \) -exec "webm_filelist" '{}' \;
    IFS=$'\n' eval 'for i in $(find $INPUT -type f -name "*.mp4");
        do 
           ${_SELF} "$i";
        done'
    delete_pid_file

elif [[ -f "${INPUT}" ]]; then 
    echo -e "${GREEN}[ FILE ]${NC} CONVERT FILE: ${GREEN}${INPUT}${NC}"
    echo "waiting 1s...."
SOURCE_FILE=$(basename -- "${INPUT}")
SOURCE_DIR=$(dirname "${INPUT}")
SOURCE="${SOURCE_DIR}/${SOURCE_FILE}"

LOG_FILE="$SOURCE_DIR/webm.log"

TARGET_FILE="${SOURCE_FILE%.*}".webm
TARGET_DIR=$(dirname "${INPUT}")"/webm"
TARGET="${TARGET_DIR}/processing.${TARGET_FILE}"

READY="${SOURCE_DIR}/${TARGET_FILE}"

INFO="${TARGET_DIR}/${TARGET_FILE}.txt"

if [ -f "${INFO}" ]; then
        echo "SKIPPED ${INFO} exists" >> "${LOG_FILE}"
        echo "${INFO} -> file available"
        sleep 1
        clear
        exit 0
fi

BITRATE=$(mplayer -vo null -ao null -identify -frames 0 "${SOURCE}" | grep kbps | awk '{print $7}' | awk '{print int($1)}')
FPS=$(mplayer -vo null -ao null -identify -frames 0 "${SOURCE}" | grep kbps | awk '{print $5}' | awk '{print int($1)}')
DIMENSIONS=$(mplayer -vo null -ao null -identify -frames 0 "${SOURCE}" | grep kbps | awk '{print $3}')

BITDEF=$BITRATE

if (( ${BITRATE} > 2047 )); then
	BITDEF="2048"

elif (( ${BITRATE} > 1023 )); then
	BITDEF="1024"

elif (( ${BITRATE} > 785 )); then
	BITDEF="786"

elif (( ${BITRATE} > 511 )); then
	BITDEF="512"
fi

BR_AVG=$(( $BITDEF ))
BR_MIN=$(( $BITDEF / 2 ))
BR_MAX=$(( $BITDEF * 2 ))



echo "convert video 2 => webm (vp9/vorbis) 2 pass"
echo "==========================================="
echo "Source: 		 ${SOURCE}"
echo "Target: 		" $(basename "${TARGET}")
echo "READY : 		" $(basename "${READY}")
echo "INFO  : 		" $(basename "${INFO}") 
echo
echo "==========================================="
echo "Diemnsions:	${DIMENSIONS}"
echo "Bitrate:	${BITRATE} => $BR_AVG"
echo "fps:		${FPS} => 25"
echo
echo "New(min,avg,max): ${BR_MIN},${BR_AVG},${BR_MAX}"
echo "==========================================="
echo "ffmpeg -i ${SOURCE} -c:v libvpx-vp9 -c:a libopus $(basename ${TARGET})"
echo
sleep 2

if [ -f "${INFO}" ]; then
	echo "SKIPPED ${INFO} exists" >> "${LOG_FILE}"
	echo "${INFO} -> file available"
	sleep 1
	clear
	exit 0
fi

if [ ! -f "${READY}" ]; then
	if [ -f "${TARGET}" ]; then
		rm "${TARGET}"
	fi
	if [ ! -d "${TARGET_DIR}" ]; then
		mkdir -m0777 -p "${TARGET_DIR}"
	fi
	ffmpeg -i "${SOURCE}" -c:v libvpx-vp9 -minrate ${BR_MIN}k -b:v ${BR_AVG}k -maxrate ${BR_MAX}k -pass 1 -an -threads ${threads} -speed ${speed} -lag-in-frames 25 -f null /dev/null

read -r -d "" PYTHONCODE << EOD
import sys, json 

data = json.load(sys.stdin)

replace = {
        "5.0(side)": "5.0",
        "5.1(side)": "5.1",
        # you can add more mappings here
    }

filter_string = "[:%d]channelmap=channel_layout='%s'" 
copy_string = "[:%d]anull"

maps = [filter_string % (stream["index"], replace[stream["channel_layout"]])
        if stream.get("channel_layout") in replace.keys() else
        copy_string % (stream["index"])
        for stream in data["streams"]
        if stream["codec_type"] == "audio"]

print(";".join(maps))
EOD


ffmpeg 	-i "${SOURCE}" -map 0 \
	-c:v libvpx-vp9  -minrate ${BR_MIN}k \
	-b:v ${BR_AVG}k -maxrate ${BR_MAX}k -pass 2 \
	-c:a libopus -filter_complex \
        	`ffprobe -hide_banner -show_streams -print_format json "${SOURCE}" | \
        	python3 -c "$PYTHONCODE"` \
	-b:a 128K \
	"${TARGET}" \
	-threads ${threads} -speed ${speed}

	echo "SLEEPING 1/s"
	sleep 1
fi

echo "move 2 ready"
echo "${TARGET} 2 ${READY}"


mv "${TARGET}" "${READY}"

INS=$( du "$SOURCE" | awk '{print $1}' )
OUS=$( du "$READY" | awk '{print $1}' )
DIFF=$(( ${INS} - ${OUS} ))
DIFFSHOW=$(( ${DIFF} / 1048576 ))


echo "$DIFF = $INS - $OUS is $DIFFSHOW";


MSG="ERROR ( ${DIFFSHOW} ) : ${SOURCE} ( ${INS} ) => ${READY} ( ${OUS} )"


VIDDATE=$(date '+%d-%m-%Y %H:%M:%S');

echo -e "${NC}"

if (( $OUS > $INS )); then
	rm "${READY}"
	MSG="TOBIG ( ${DIFFSHOW} ) : ${SOURCE} ( ${INS} ${BITRATE}k ) => ${READY} ( ${OUS} ${BR_AVG}k )"
	echo -e "${RED}"

elif (( $OUS <= 10  )); then
	rm "${READY}"
	MSG="NULL ( ${DIFFSHOW} ): ${SOURCE} ( ${INS} ${BITRATE}k ) => ${READY} ( ${OUS}  ${BR_AVG}k )"
	echo -e "${RED}"

else
	MSG="OK ( ${DIFFSHOW} ): ${SOURCE} ( ${INS}  ${BITRATE}k ) => ${READY} ( ${OUS}  ${BR_AVG}k )"
	echo -e "${GREEN}"
	rw ${SOURCE} 
fi
echo "${VIDDATE} | ${MSG}" > "${INFO}"
echo "${VIDDATE} | ${MSG}" >> "${LOG_FILE}"
echo
echo
echo "=========================================="
echo "${MSG}"
echo -e "${NC}"
echo "=========================================="
echo -e "DIFF 			: ${DIFFWSHOW}"
echo -e "IN   			: ${INS}"
echo -e "OUT  			: ${OUS}"
echo -e "BIT(min,avg,max)	: ${BR_MIN},${BR_AVG},${BR_MAX}"
echo "=========================================="
echo
rm ffmpeg2pass*
sleep 1
echo "DONE!..."


fi

