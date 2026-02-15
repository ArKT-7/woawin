#!/data/data/com.termux/files/usr/bin/bash
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GRAY='\033[0;37m'
DARKGRAY='\033[1;30m'
GREEN='\033[0;32m'
RED='\033[0;31m'
MAGENTA='\033[0;35m'
NC='\033[0m'
REPO="ArKT-7/woawin"
WORKDIR="$HOME/woawin"
FINALDIR="/sdcard/Download/woawin"

if [ ! -z "$1" ]; then
    API="https://api.github.com/repos/$REPO/releases/tags/$1"
    MODE="Release: $1"
else
    API="https://api.github.com/repos/$REPO/releases/latest"
    MODE="Release: Latest"
fi

clear
echo -e "\n${CYAN} WOAWIN Auto-Downloader & Extractor${NC}"
# echo -e " $MODE\n"

if ! command -v jq &> /dev/null || ! command -v 7z &> /dev/null || ! command -v bc &> /dev/null; then
    echo -e "\n\n${YELLOW} Installing Termux dependencies (curl, 7zip, jq)...${NC}\n"
    pkg update -y
    pkg upgrade -y
    pkg install curl p7zip jq bc -y
fi
if [ ! -w "/sdcard/Download" ]; then
    echo -e "\n\n${RED} STORAGE PERMISSION ERROR ${NC}"
    echo -e "${YELLOW} Unable to write to /sdcard/Download ${NC}\n"
    echo -e "${GRAY} Attempitng to request permission...${NC}"
    sleep 1
    termux-setup-storage
    sleep 2

    if [ ! -w "/sdcard/Download" ]; then
        echo -e "\n${RED} AUTOMATIC REQUEST FAILED ${NC}"
        echo -e "${YELLOW} Please fix this manually:${NC}\n"
        echo -e " 1. Open Android Settings"
        echo -e " 2. Go to: Apps > Termux > Permssions"
        echo -e " 3. Set Storage/Files to: ${GREEN}ALLOW${NC}"
        echo -e " 4. Restart Termux and run this script again."
        echo -e "\n${GREEN} Or re-run this script again to ask permission automatically${NC}\n"
        exit 1
    fi
fi
if [ ! -d "$FINALDIR" ]; then
    mkdir -p "$FINALDIR"
fi

{
    echo -e "\n\n${YELLOW} Fetching Release Info...${NC}\n"
    RESPONSE=$(curl -s "$API")

    if echo "$RESPONSE" | grep -q "Not Found"; then
        if [ ! -z "$1" ]; then
            echo -e "${RED} Could not find release with tag: $1${NC}"
            exit 1
        else
            echo -e "${RED} Could not find the latest release information.${NC}"
            exit 1
        fi
    fi

    ASSETS=$(echo "$RESPONSE" | jq -c '.assets[] | select(.name | test("\\.zip\\.[0-9]{3}$"))')
    if [ -z "$ASSETS" ]; then
        echo -e "${RED} No .zip.00x files found in this release!${NC}"
        exit 1
    fi
    echo -e "${GRAY} Parts Detected:${NC}"

    echo "$ASSETS" | jq -r -s 'sort_by(.name) | .[] | @base64' | while read -r asset_base64; do
        _jq() {
        echo ${asset_base64} | base64 --decode | jq -r "${1}"
        }
        NAME=$(_jq '.name')
        SIZE_BYTES=$(_jq '.size')
        SIZE_MB=$(echo "scale=2; $SIZE_BYTES / 1048576" | bc)
        HASH=$(_jq '.digest // empty' | sed 's/sha256://')

        echo -e "${GRAY} $NAME${NC}"
        echo -e "${DARKGRAY} Size:   $SIZE_MB MB${NC}"
        if [ ! -z "$HASH" ]; then
            echo -e "${DARKGRAY} SHA256: $HASH${NC}"
        else
            # echo -e "${DARKGRAY} SHA256: Not Provided in API...${NC}"
            :
        fi
    done

    if [ ! -d "$WORKDIR" ]; then
        mkdir -p "$WORKDIR"
    fi
    cd "$WORKDIR" || exit
    echo -e "${GRAY} Working Directory (Temp):${NC}"
    echo -e "${GRAY} $WORKDIR\n${NC}"

    FIRST_ASSET=$(echo "$ASSETS" | jq -s 'sort_by(.name) | .[0]')
    FIRST_NAME=$(echo "$FIRST_ASSET" | jq -r .name)
    FOLDER_NAME=$(echo "$FIRST_NAME" | sed -E 's/\.zip\.[0-9]{3}$//')
    SUBDIR="$WORKDIR/$FOLDER_NAME"

    if [ ! -d "$SUBDIR" ]; then mkdir -p "$SUBDIR"; fi
    cd "$SUBDIR" || exit

    COUNT=0
    TOTAL=$(echo "$ASSETS" | jq -s 'length')

    echo "$ASSETS" | jq -r -s 'sort_by(.name) | .[] | @base64' | while read -r asset_base64; do
        _jq() {
        echo ${asset_base64} | base64 --decode | jq -r "${1}"
        }

        COUNT=$((COUNT+1))
        URL=$(_jq '.browser_download_url')
        NAME=$(_jq '.name')
        EXPECTED_HASH=$(_jq '.digest // empty' | sed 's/sha256://')

        echo -e "\n${YELLOW} Downloading Part $COUNT of $TOTAL...${NC}\n"
        curl -L -o "$NAME" "$URL" --retry 5 -C - --fail

        if [ $? -ne 0 ]; then
            echo -e "${RED} Failed to download $NAME${NC}"
            exit 1
        fi

        if [ ! -z "$EXPECTED_HASH" ]; then
            echo -n -e "\n${DARKGRAY} Verifying SHA256 Checksum... ${NC}"

            CALC_HASH=$(sha256sum "$NAME" | awk '{print $1}')

            if [ "$CALC_HASH" == "$EXPECTED_HASH" ]; then
                echo -e "${GREEN}Done!${NC}"
            else
                echo -e "${RED} Error!${NC}"
                echo -e "${RED} Expected: $EXPECTED_HASH${NC}"
                echo -e "${RED} Got:      $CALC_HASH${NC}"
                rm -f "$NAME"
                echo -e "${RED} Hash mismatch for $NAME! File deleted, Please try again...${NC}"
                exit 1
            fi
        fi
    done

    echo -e "\n\n${MAGENTA} Verifying Archive Integrity...${NC}"

    if [ -f "$FIRST_NAME" ]; then
        7z t "$FIRST_NAME" -y
        if [ $? -ne 0 ]; then
            echo -e "${RED} Integrty Check Failed, Files are corrupted!${NC}"
            exit 1
        fi
        echo -e "\n${GREEN} Integrity Verified!${NC}"

        echo -e "\n\n${MAGENTA} Extracting ESD file...${NC}"
        7z x "$FIRST_NAME" -o"$SUBDIR" -y
        if [ $? -ne 0 ]; then
            echo -e "${RED} Extraction Failed${NC}"
            exit 1
        fi

        INNER_ZIP=$(find . -maxdepth 2 -name "*.zip" | head -n 1)
        if [ ! -z "$INNER_ZIP" ]; then
            echo -e "\n${CYAN} Nested ZIP detected, Extracting...${NC}"
            7z x "$INNER_ZIP" -o"$SUBDIR" -y
            if [ $? -ne 0 ]; then
                echo -e "${RED} ESD Extracton Failed${NC}"
                exit 1
            fi
            rm -f "$INNER_ZIP"
        fi

        ESD=$(find . -maxdepth 2 -name "*.esd" | head -n 1)
        MOVED=false

        if [ ! -z "$ESD" ]; then
            ESD_NAME=$(basename "$ESD")
            echo -e "\n${GREEN} Found: $ESD_NAME${NC}"
            echo -e "${YELLOW} Moving to Downloads folder...${NC}"
            mv -f "$ESD" "$FINALDIR/"
            if [ -f "$FINALDIR/$ESD_NAME" ]; then
                MOVED=true
            fi
        fi

        if [ "$MOVED" = true ]; then
            echo -e "\n\n${DARKGRAY} Cleaning up temporary files...${NC}"
            cd "$HOME"
            rm -rf "$WORKDIR"
            cd "$FINALDIR"
            echo -e "${GREEN} Download Complete, Opening folder...\n${NC}"
            termux-open .
        else
            echo -e "\n${RED} ERROR: .ESD file not fund or move failed!${NC}"
            echo -e "${RED} Check inside: $SUBDIR${NC}"
        fi
        sleep 3
    else
        echo -e "${RED} Part 1 ($FIRST_NAME) not found!\n${NC}"
        exit 1
    fi

} || {
    echo -e "\n\n${RED} Error: Script encountered an issue.${NC}"
    read -p " Press Enter to exit..."
}
