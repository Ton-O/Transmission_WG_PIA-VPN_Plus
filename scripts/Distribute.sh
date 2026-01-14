#! /bin/bash

declare -a RPC_Port_array
declare -a RPC_Call_array
declare -a RPC_Session_ID_array
declare -a RPC_Torrents_array
declare -a RPC_DownSpeed_array
declare -a RPC_UpSpeed_array

BASE_RPC=1
RPC_COUNT=9
Multi_Watch_Dir="/Media/MultiWatch"
Default_bandwidthPriority=0 
PrintHeader=1
# MY_INTERNAL_IP has to be defined as an environment variable through docker-compose.yml

function Extract_Session_ID {
    local This_RPC=$1
    SESSION_DATA=$2
    SESSION_ID=$(echo "$SESSION_DATA"   |  sed -n 's/.*X-Transmission-Session-Id: \(.*\)<\/code>.*/\1/p')    
    if [ -z "${SESSION_ID}" ]; then
        echo "Transmission did not return Session ID; cannot continue"
        return 1
    fi 
    RPC_Session_ID_array[${This_RPC}]=$SESSION_ID
    RPC_Call_array[${This_RPC}]="http://${MY_INTERNAL_IP}:${RPC_Port_array[${This_RPC}]}/transmission/rpc"
    echo "We have a session id for ${RPC_Port_array[${This_RPC}]} : ${RPC_Session_ID_array[${This_RPC}]}"
    return 0 
} 

function Get_DEFAULT_Download_Dir {
    local This_RPC=$1
    local TORRENT_ID="${2}"
    local JSON_PAYLOAD

    JSON_PAYLOAD='{"jsonrpc": "2.0","method": "session-get","arguments": { "fields": [ "download-dir"]  },"id": 3}'
    DoRPC_call "$This_RPC" "$JSON_PAYLOAD"
    if [[ "$?" -ne "0" ]] ; then
        echo "Failed to get default download directory from RPC port ${RPC_Port_array[$This_RPC]}"
        return 1
    fi
    DEFAULT_download_dir=$(echo $RPC_RESULT | jq -r '.arguments["download-dir"]')

}

function Initially_get_session_id {
    local This_RPC=$1
    RPC_Port_array[${This_RPC}]="909${This_RPC}"
    SESSION_DATA=$(curl -s http://${MY_INTERNAL_IP}:${RPC_Port_array[${This_RPC}]}/transmission/rpc -d '{"jsonrpc": "2.0","method": "session-get","arguments": { "fields": [ "download-dir"] },"id": 2}' $AUTH)
    Extract_Session_ID ${This_RPC} "${SESSION_DATA}"
}

function StopTorrent {
    local This_RPC=$1
    local TORRENT_ID="${2}"
    local JSON_PAYLOAD
    echo "Stopping torrent ID: ${TORRENT_ID} in RPC port ${RPC_Port_array[$This_RPC]}"
    JSON_PAYLOAD='{"jsonrpc": "2.0","method": "torrent-stop", "arguments": { "ids": [ '"${TORRENT_ID}"' ] },"id": 3}'
    DoRPC_call "$This_RPC" "$JSON_PAYLOAD"
    RESPONSE=$RPC_RESULT
    if [[ $(echo $RESPONSE | jq -r '.result') == "success" ]] ; then
        echo "Torrent ID: ${TORRENT_ID} stopped successfully."
        return 0
    else
        echo "Failed to stop torrent ID: ${TORRENT_ID}."
        return 1
    fi
}

function AddTorrent {

    local This_RPC=$4
    local TORRENT_FILE_PATH="${1}"
    local TORRENT_DOWNLOAD_DIR="${2}"
    local bandwidthPriority="${3}"
    local JSON_PAYLOAD

    echo "Adding torrent file: ${TORRENT_FILE_PATH} with download dir: ${TORRENT_DOWNLOAD_DIR} to $This_RPC"
    JSON_PAYLOAD='{"jsonrpc": "2.0", "method": "torrent-add", "arguments": { "filename": "'"$TORRENT_FILE_PATH"'", "download-dir": "'"$TORRENT_DOWNLOAD_DIR"'", "bandwidthPriority": "'"$bandwidthPriority"'", }, "id": "4" }'
    DoRPC_call "$This_RPC" "$JSON_PAYLOAD"
    RESPONSE=$RPC_RESULT
    # .arguments .torrentduplicate
    if [[ $(echo $RESPONSE | jq -r '.result') == "success" ]] ; then
        echo "Torrent added successfully to RPC port $This_RPC"
        return 0
    else
        echo "Failed to add torrent to RPC port  $This_RPC."
        return 1
    fi
}

function RemoveTorrent {

    local This_RPC=$1
    local TORRENT_ID="${2}"
    local JSON_PAYLOAD

    echo "Removing torrent ID: ${TORRENT_ID} in RPC port "${RPC_Port_array[$This_RPC]}
    JSON_PAYLOAD='{"jsonrpc": "2.0", "method": "torrent-remove", "arguments": {"ids":  '"${TORRENT_ID}"' }, "id": "5" }'
    DoRPC_call "$This_RPC" "$JSON_PAYLOAD"
    RESPONSE=$RPC_RESULT
    if [[ $(echo $RESPONSE | jq -r '.result') == "success" ]] ; then
        echo "Torrent ID: ${TORRENT_ID} removed successfully."
        return 0
    else
        echo "Failed to remove torrent ID: ${TORRENT_ID}."
        return 1
    fi
}

function DoRPC_call {
#    echo $2

    local This_RPC=$1
    local cmd_payload="$2"
    local Again=$3
    local CURL_CMD 
    local TMPRESPONSE

    CURL_CMD=( curl -s -X POST "${RPC_Call_array[$This_RPC]}" )
    CURL_CMD+=( ${AUTH} ) 
    CURL_CMD+=( -d "$cmd_payload" ) 
    CURL_CMD+=( -H "X-Transmission-Session-Id: ${RPC_Session_ID_array[$This_RPC]}" )

    RPC_RESULT=$("${CURL_CMD[@]}")
    RC=$?

    if [[  $(echo "$RPC_RESULT"   |  sed -n 's/.*X-Transmission-Session-Id: \(.*\)<\/code>.*/\1/p')  ]] ; then
        Extract_Session_ID "${This_RPC}" "$RPC_RESULT"
        if [[ "$?" -ne "0" ]] ; then
            echo "RPC call failed with response: $RPC_RESULT"
            return 1
        fi
        DoRPC_call "$This_RPC" "$cmd_payload" "$Again"
        return $?
    fi

    if [[ $(echo $RPC_RESULT | jq -r '.result') == "success" ]] ; then
        return 0
    else
        if [[ "$Again" == "1" ]] ; then
            echo "RPC call failed again with response: $RPC_RESULT"
            return 1
        fi 
        TMPRESPONSE="$RPC_RESULT"

        Extract_Session_ID "${This_RPC}" "$RPC_RESULT"
        if [[ "$?" -ne "0" ]] ; then
            echo "RPC call failed with response: $TMPRESPONSE"
            return 1
        fi
        DoRPC_call "$This_RPC" "$cmd_payload" "1"
    fi
    return 0 
}

function GetTorrentList {
    local This_RPC=$1
    local JSON_PAYLOAD

    #echo "Getting torrent list from RPC port ${RPC_Port_array[$This_RPC]}"
    JSON_PAYLOAD='{"jsonrpc": "2.0","method": "torrent-get","arguments": { "fields": [   "status", "name", "torrentFile", "downloadDir", "id", "rateDownload", "rateUpload", "bandwidthPriority"] },"id": 2}'
    DoRPC_call "$This_RPC" "$JSON_PAYLOAD"
    TorrentList=$RPC_RESULT
}

function Get_All_Client_statistics {
    #echo "Getting all client statistics"
    for ((i=2; i<=$RPC_COUNT; i++))
    do
        Get_Client_statistics $i
    done
}

function Get_Client_statistics {
    local This_RPC=$1
    local Torrents 
    local TotalTorrents=0
    local TotalDownSpeed=0
    local TotalUpSpeed=0

    GetTorrentList $This_RPC
    
    mapfile -t TORRENT_LIST < <(echo "$TorrentList" | jq -c '.arguments.torrents[]')

    #echo "Aantal gevonden torrents: ${#TORRENT_LIST[@]}"

    for TORRENT_ENTRY in "${TORRENT_LIST[@]}"; do
        #echo "Processing GCS torrent entry: $TORRENT_ENTRY"
        rateDownload=$(echo "$TORRENT_ENTRY"         | jq -r '.TotalDownSpeed')
        rateUpload=$(echo "$TORRENT_ENTRY"         | jq -r '.rateUpload')
        TotalTorrents+=1 
        TotalDownSpeed+=rateDownload
        TotalUpSpeed+=rateUpload
    done
    RPC_Torrents_array[$This_RPC]=$TotalTorrents
    RPC_DownSpeed_array[$This_RPC]=$TotalDownSpeed
    RPC_UpSpeed_array[$This_RPC]=$TotalUpSpeed
}

function Get_Best_RPC_Client {

    local Best_RPC=2
    local Min_Torrents=${RPC_Torrents_array[2]}
    for ((i=3; i<=$RPC_COUNT; i++)); do
        if [[ ${RPC_Torrents_array[$i]} -lt $Min_Torrents ]] ; then
            Min_Torrents=${RPC_Torrents_array[$i]}
            Best_RPC=$i
        fi
    done
    #echo "Lowest torrent count is $Min_Torrents on $Best_RPC}"
    return $Best_RPC
}

function ProcessRPCTorrentList { 
    local This_RPC=$1
    local JSON_PAYLOAD
    local name
    local downloadDir
    local TorrentID
    local status
    local torrentFile

    mapfile -t TORRENT_LIST < <(echo "$TorrentList" | jq -c '.arguments.torrents[]')

    #echo "Aantal gevonden torrents: ${#TORRENT_LIST[@]}"

    for TORRENT_ENTRY in "${TORRENT_LIST[@]}"; do
        #echo "Processing torrent entry: $TORRENT_ENTRY"
        status=$(echo "$TORRENT_ENTRY"       | jq -r '.status')
        if [[ "$status" -eq "6" ]] ; then                       # Download completed in ?   
        echo "PrintHeader = $PrintHeader"    
            if [[ "$PrintHeader" -eq "1" ]] ; then
                echo "Process RPC Client loop - $(date '+%Y-%m-%d %H:%M:%S')" 
                PrintHeader=0
            fi       
            name=$(echo "$TORRENT_ENTRY"         | jq -r '.name')
            torrentFile=$(echo "$TORRENT_ENTRY"         | jq -r '.torrentFile')
            downloadDir=$(echo "$TORRENT_ENTRY" | jq -r '.downloadDir')
            TorrentID=$(echo "$TORRENT_ENTRY"    | jq -r '.id')
            bandwidthPriority=$(echo "$TORRENT_ENTRY"    | jq -r '.bandwidthPriority')
            echo "Finished torrent found at port ${RPC_Port_array[This_RPC]}: $name ($TorrentID) }); moving to RPC port $BASE_RPC"
            StopTorrent $This_RPC $id                            # stop the "temporarily set-aside torrent"
            if [[ "$?" -eq "0" ]] ; then                        # if successfully stopped  
                #echo "Adding torrent to RPC port $BASE_RPC" 
                AddTorrent "$torrentFile" "$downloadDir" $bandwidthPriority $BASE_RPC    # place torrent back in normal Transmisson-daemon
                if [[ "$?" -eq "0" ]] ; then                    # if successfully added
                    RemoveTorrent "$This_RPC" "$TorrentID"                  # remove the "temporarily set-aside torrent"
                fi
            fi
            echo ""

        fi
    done
    #echo 
}

function CheckActiveRPCTorrents {
    local This_RPC=$1
    GetTorrentList $This_RPC
    ProcessRPCTorrentList $This_RPC

}

function AddTorrentToBestRPC {
    local file=$1
    local ThisDir=$2
    local bandwidthPriority=$3

    if [[ "$INITDONE" -eq "0" ]] ; then
        Get_All_Client_statistics 
        INITDONE=1
    fi
    Get_Best_RPC_Client
    Best_RPC=$?
    echo "Adding torrent to best RPC client: $Best_RPC"
    AddTorrent "$file" "$ThisDir" $bandwidthPriority $Best_RPC
    RC=$?
}

function CheckWatchList {

    # Check if the directory exists
    if [ ! -d "$Multi_Watch_Dir" ]; then
        echo "Error: $Multi_Watch_Dir is not a valid directory."
        return 1 
    fi
    INITDONE=0
    # Loop through all items in the directory
    for file in "$Multi_Watch_Dir"/*; do
        # Check if the current item is a regular file (skips directories)
        if [ -f "$file" ]; then
            # Check if the file has a .torrent extension
            if [[ "${file##*.}" != "torrent" ]]; then
                echo "Skipping non-torrent file: $file"
                continue
            fi            
            # We have a valid torrent file; add this to the bets fitting RPC client
            echo "Found watch file $file - $(date '+%Y-%m-%d %H:%M:%S')"
            AddTorrentToBestRPC $file $Default_bandwidthPriority $DEFAULT_download_dir
            if [[ "$RC" -eq "0" ]] ; then
                # Move processed file to Processed subdirectory
                mv "$file" "$Multi_Watch_Dir/Processed/"
                echo "Moved processed watch file $file to $Multi_Watch_Dir/Processed/"
            else
                echo "Failed to add torrent from watch file $file to RPC client $Best_RPC"
            fi

        fi
    #echo "."
    INITDONE=0                                                        # Reset so we will get all client statistics again nexttime
    done
}

function DistributeTorrents {
    local This_RPC=$1

    GetTorrentList $This_RPC
    mapfile -t TORRENT_LIST < <(echo "$TorrentList" | jq -c '.arguments.torrents[]')
    echo "Aantal gevonden torrents: ${#TORRENT_LIST[@]}"

    for TORRENT_ENTRY in "${TORRENT_LIST[@]}"; do
        name=$(echo "$TORRENT_ENTRY"         | jq -r '.name')
        echo "Checking torrent entry: $name"
        status=$(echo "$TORRENT_ENTRY"       | jq -r '.status')
        if [[ "$status" -eq "4" ]] ; then                       # Downloading?      
            if [[ "$PrintHeader" -eq "1" ]] ; then
                echo "Process Distribute loop - $(date '+%Y-%m-%d %H:%M:%S')" 
                PrintHeader=0
            fi       
            torrentFile=$(echo "$TORRENT_ENTRY"  | jq -r '.torrentFile')
            downloadDir=$(echo "$TORRENT_ENTRY"  | jq -r '.downloadDir')
            TorrentID=$(echo "$TORRENT_ENTRY"    | jq -r '.id')
            bandwidthPriority=$(echo "$TORRENT_ENTRY"    | jq -r '.bandwidthPriority')
            echo "Torrent $name will be moved"
            StopTorrent $This_RPC $id                            # stop the "temporarily set-aside torrent"
            if [[ "$?" -eq "0" ]] ; then                        # if successfully stopped  
                #echo "Adding torrent to RPC port $BASE_RPC" 
                AddTorrentToBestRPC  "$torrentFile" "$downloadDir" $bandwidthPriority
                if [[ "$RC" -eq "0" ]] ; then                    # if successfully added
                    RemoveTorrent "$This_RPC" "$TorrentID"                  # remove the "temporarily set-aside torrent"
                fi
            fi
        fi
    done
    #echo 

}
function ConsolidateTorrents {
    local This_RPC 
    local bandwidthPriority

    PrintHeader=1 
    for ((i=2; i<=$RPC_COUNT; i++)) ; do
        This_RPC=$i
        GetTorrentList $This_RPC
        mapfile -t TORRENT_LIST < <(echo "$TorrentList" | jq -c '.arguments.torrents[]')
        echo "Aantal gevonden torrents: ${#TORRENT_LIST[@]}"

        for TORRENT_ENTRY in "${TORRENT_LIST[@]}"; do
            name=$(echo "$TORRENT_ENTRY"         | jq -r '.name')
            echo "Checking torrent entry: $name"
            status=$(echo "$TORRENT_ENTRY"       | jq -r '.status')
            if [[ "$status" -eq "4" ]] ; then                       # Downloading?      
                if [[ "$PrintHeader" -eq "1" ]] ; then
                    echo "Process Distribute loop - $(date '+%Y-%m-%d %H:%M:%S')" 
                    PrintHeader=0
                fi       
                torrentFile=$(echo "$TORRENT_ENTRY"  | jq -r '.torrentFile')
                downloadDir=$(echo "$TORRENT_ENTRY"  | jq -r '.downloadDir')
                TorrentID=$(echo "$TORRENT_ENTRY"    | jq -r '.id')
                bandwidthPriority=$(echo "$TORRENT_ENTRY"    | jq -r '.bandwidthPriority')
                echo "Torrent $name will be moved"
                StopTorrent $This_RPC $id                            # stop the "temporarily set-aside torrent"
                if [[ "$?" -eq "0" ]] ; then                        # if successfully stopped  
                    AddTorrent "$torrentFile" "$downloadDir" $bandwidthPriority $BASE_RPC    # place torrent back in normal Transmisson-daemon
                    if [[ "$RC" -eq "0" ]] ; then                    # if successfully added
                        RemoveTorrent "$This_RPC" "$TorrentID"                  # remove the "temporarily set-aside torrent"
                    fi
                fi
            fi
        done
    done

    #echo 

}

if [[ "$TRANSMISSION_RPC_AUTHENTICATION_REQUIRED" -eq "true" ]]; then 
    AUTH="-u $TRANSMISSION_RPC_USERNAME:TRANSMISSION_RPC_PASSWORD"
else
    AUTH=""
fi

    PrintHeader=1 

Initially_get_session_id 1 
Get_DEFAULT_Download_Dir 1 
$(mkdir -p "$Multi_Watch_Dir/Processed/" )

for ((i=2; i<=$RPC_COUNT; i++)) ; do
    Initially_get_session_id $i 
done
if [[ "$1" == "CONSOLIDATE" ]] ; then
    echo "Single run mode - consolidating all "downloading" torrents from secondary torrent clients to primary torrent client"
    ConsolidateTorrents
    exit 0
fi
if [[ "$1" == "DISTRIBUTE" ]] ; then
    echo "Single run mode - moving all "downloading" torrents from primary torrent client to RPC"
    DistributeTorrents $BASE_RPC
    exit 0
fi

if [[ "$1" -ne "NORMAL" ]] ; then
    echo "Please specify function to execute: NORMAL, DISTRIBUTE or CONSOLIDATE 
    echo "Received $1 which is invalid; Execution aborted"
    exit 12
fi

echo "Transmission CPU-use optimizer"
echo "  Offloads intensive downloads to secondary Transmission-daemons"
echo "  Monitors their completion and moves completed downloads back to main Transmission-daemon"
echo "" 
echo "Initializing....; this script will be running continuously (mainly sleeping)"
echo 


while(true)
do
    PrintHeader=1 
    for ((i=2; i<=$RPC_COUNT; i++)) ; do
        CheckActiveRPCTorrents $i
    done
    CheckWatchList 
    sleep 20s
 done