#!/usr/bin/env bash

set -euo pipefail

greenColour='\033[0;32m'
redColour='\033[0;31m'
blueColour='\033[0;34m'
yellowColour='\033[1;33m'
grayColour='\033[0;37m'
endColour='\033[0m'

### GLOBALS ###
VERSION='1.0.0'
IP4_REGEX='(?!0|22[4-9]|23[0-9])((\d|[1-9]\d|1\d{2}|2[0-4]\d|25[0-5])\.){3}(\d|[1-9]\d|1\d{2}|2[0-4]\d|25[0-5])'
IP6_REGEX='((?:[0-9a-fA-F]{1,4}:){7}[0-9a-fA-F]{1,4}|(?:[0-9a-fA-F]{1,4}:){6}(?::[0-9a-fA-F]{1,4}){1,2}|(?:[0-9a-fA-F]{1,4}:){5}(?::[0-9a-fA-F]{1,4}){1,3}|(?:[0-9a-fA-F]{1,4}:){4}(?::[0-9a-fA-F]{1,4}){1,4}|(?:[0-9a-fA-F]{1,4}:){3}(?::[0-9a-fA-F]{1,4}){1,5}|(?:[0-9a-fA-F]{1,4}:){2}(?::[0-9a-fA-F]{1,4}){1,6}|(?:[0-9a-fA-F]{1,4}:){1}(?::[0-9a-fA-F]{1,4}){1,7}|(?::(?::[0-9a-fA-F]{1,4}){1,7}){1})(?:::[0-9a-fA-F]{1,4}[0-9a-fA-F]{1,4})?'

DATA_SOURCE=''
DATA_SOURCE_TYPE='text'
MODE='both'
declare -i GEOLOCATION=0
declare -A IP_GEOLOCATION_DICTIONARY=()
OUTPUT_FILE=''
IP4_MATCHES=''
IP6_MATCHES=''
GREP_COMMAND='grep' # GNU Linux grep command by default

if [[ $OSTYPE == 'darwin'* ]]; then 
    GREP_COMMAND='ggrep'
    if ! command -v "$GREP_COMMAND" >/dev/null 2>&1; then
        echo -e "$redColour GNU grep$endColour is required. Install it with$yellowColour 'brew install grep'$endColour." >&2
        exit 1
    fi
fi

### ###

banner() {
    cat << EOF

___ _           _      _ _____ 
 | |_)__|_| /\ |_)\  /|_(_  |  
_|_|    | |/--\| \ \/ |___) | v(${VERSION})


EOF
}

show_version() {
cat << 'EOF'
ipsoak v1.0.0 (v1.0.0)
Source available at https://github.com/0xp1n/ipsoak
EOF

exit 0
}


show_help() {
    cat <<'EOF'
USAGE:
    ipharvest [OPTIONS]  [--] [FILE]...

EXAMPLES:
    ipharvest --source data.txt
    ipharvest -s "192.168.1.1/24,10.10.10.25,2404:6800:4008:c02::8b" -m ipv6
    ipharvest -s https://example.com/log.txt --geolocation
    ipharvest -s ipv6.txt --mode ipv6 -o documents/reports/ipv6.json
    ipharvest -source /var/log/example.log --geolocation --mode both -o reports/ip_harvest.csv

OPTIONS:
    -s, --source                      Choose the source data to extract ips from
    -m  --mode <type>                 Choose the mode of extraction (ipv4,ipv6,both)
        --geolocation                 Geolocate all the IP matches
    -o  --output                      Define a file path to save the report generated by the tool in plain text (also supported JSON and CSV)
    -v  --version                     Display the actual version
    -h  --help                        Print help information
EOF
}

data_source_is_empty() {
    echo -e "$redColour You need to provide a valid source of data (file, text or url).$endColour Example:$yellowColour ipsoak -s log.dat$endColour"
    exit 1
}

is_empty() {
    local var=$1

    [[ -z $var ]]
}

to_lowercase() {
    echo "$1" | tr '[:upper:]' '[:lower:]'
}

is_url() {
    local url=$1
    regex='(https?|ftp|file)://[-[:alnum:]\+&@#/%?=~_|!:,.;]*[-[:alnum:]\+&@#/%=~_|]'

    [[ $url =~ $regex ]]
}

command_exists() {
    local COMMAND=$1

    [[ -n "$(command -v "$COMMAND")" ]]
  }

extract_json_property() {
    local json="$1"
    local property="$2"

    if command_exists "jq"; then 
        echo "$json" | jq ".$property"
    else 
        # Use grep to match the property name and extract the value
        local regex="\"${property}\":\s*([^,}]+)"
        if [[ $json =~ $regex ]]; then
            local value="${BASH_REMATCH[1]}"

            # If the value is a string with quotes, remove them
            if [[ $value =~ ^\"(.*)\"$ ]]; then
                echo "${BASH_REMATCH[1]}"
            else
                echo "$value"
            fi
        else
            # If the property is not found, return an empty string
            echo ""
        fi
    
    fi
}

show_ip_report_message() {
    local filepath=$1 
    echo -e "$greenColour [ REPORT ]$endColour IP report writed to$yellowColour $filepath$endColour"
}

extract_ipv4_from_source() {
    local source=$1
    local source_type=$2

    if [ "$source_type" = 'file' ]; then
        get_ipv4_from_file "$source"

    elif [ "$source_type" = 'text' ]; then
        get_ipv4_from_text "$source"

    elif [ "$source_type" = 'url' ]; then
        get_ipv4_from_url "$source"
       
    else  
        echo -e "$redColour [ FAILED ] The data source type is invalid, the tool only allows$endColour $yellowColour file|text|url$endColour,$redColour aborting operation...$endColour"
        exit 1
    fi
}

extract_ipv6_from_source() {
    local source=$1
    local source_type=$2

    if [ "$source_type" = 'file' ]; then
        get_ipv6_from_file "$source"

    elif [ "$source_type" = 'text' ]; then
        get_ipv6_from_text "$source"

    elif [ "$source_type" = 'url' ]; then
        get_ipv6_from_url "$source"
    else  
        echo -e "$redColour [ FAILED ] The data source type is invalid, the tool only allows$endColour $yellowColour file|text|url$endColour,$redColour aborting operation...$endColour"
        exit 1
    fi
}

get_ipv4_from_file() {
    local file=$1
    IP4_MATCHES=$($GREP_COMMAND  -Pohw "$IP4_REGEX" "$file")
}

get_ipv4_from_text() {
    local text=$1
    IP4_MATCHES=$(echo "$text" | $GREP_COMMAND -Pohw "$IP4_REGEX")
}

get_ipv4_from_url() {
    local url=$1

     if command_exists 'curl'; then 
        curl -ksLo downloaded_file "$url" \
            && get_ipv4_from_file downloaded_file

    elif command_exists 'wget'; then 
        wget -O download_file "$url" \
            && get_ipv4_from_file downloaded_file

    else 
        echo -e "$redColour [ FAILED ]We couldn't fetch the source from$endColour$blueColour$url $endColour because commands$yellowColour wget$endColour and$yellowColour curl$endColour$redColour are not available in your system$endColour"
    fi
}

get_ipv6_from_url() {
    local url=$1

     if command_exists 'curl'; then 
        curl -ksLo downloaded_file "$url" \
            && get_ipv6_from_file downloaded_file

    elif command_exists 'wget'; then 
        wget -O download_file "$url" \
            && get_ipv6_from_file downloaded_file

    else 
        echo -e "$redColour [ FAILED ]We couldn't fetch the source from$endColour$blueColour$url $endColour because commands$yellowColour wget$endColour and$yellowColour curl$endColour$redColour are not available in your system$endColour"
    fi
}

get_ipv6_from_file() {
    local file=$1
    IP6_MATCHES=$($GREP_COMMAND  -Pohw "$IP6_REGEX" "$file")
}

get_ipv6_from_text() {
    local file=$1
    IP6_MATCHES=$(echo "$DATA_SOURCE_TYPE" | $GREP_COMMAND  -Pohw "$IP6_REGEX")
}

###
#JSON STRUCTURE EXAMPLE
# {"status":"success","description":"Data successfully received.","data":{"geo":{"host":"74.220.199.8","ip":"74.220.199.8","rdns":"parking.hostmonster.com","asn":46606,"isp":"UNIFIEDLAYER-AS-1","country_name":"United States","country_code":"US","region_name":null,"region_code":null,"city":null,"postal_code":null,"continent_name":"North America","continent_code":"NA","latitude":37.751,"longitude":-97.822,"metro_code":null,"timezone":"America\/Chicago","datetime":"2023-03-18 04:23:49"}}}
###
geolocate_ip() { 
    local ip_address=$1
    # The user agent only needs to have this format, it does not need to be a real domain or ip
    local user_agent='keycdn-tools:http://10.10.10.25'
    local url="https://tools.keycdn.com/geo.json?host=$ip_address"

    if command_exists 'curl'; then 
        curl -s -H "User-Agent: $user_agent" "$url"

    elif command_exists 'wget'; then 
        wget -qO- --user-agent="$user_agent" "$url"
    else 
        echo -e "We couldn't geolocate the IP $ip_address because commands wget and curl are not available in your system"
    fi    
}


set_mode() {
    declare -a available_modes=("ipv4" "ipv6" "both")
    declare -i valid_mode=0
    local selected_mode
    selected_mode=$(to_lowercase "$1")

    for mode in "${available_modes[@]}"; do
        if [ "$mode" = "$selected_mode" ]; then
            MODE=$mode
            valid_mode=1
            break
        fi
    done

    if [ $valid_mode -eq 0 ]; then
        echo -e "The selected mode $selected_mode is invalid, allowed values are: ${available_modes[*]}. The default mode $MODE will be used instead"
    fi
}

set_data_source() {
    local source=$1

    is_empty "$source" && data_source_is_empty

    if [ -f "$source" ]; then
        DATA_SOURCE_TYPE='file'
    fi 
    
    if is_url "$source"; then 
        DATA_SOURCE_TYPE='url'
    fi

    DATA_SOURCE=$source
}

calculate_geolocation() {
    if ! is_empty "$IP4_MATCHES"; then
        readarray -t ip_addreses <<< "$IP4_MATCHES"

        for ip in "${ip_addreses[@]}"; do
            if [[ ! -v IP_GEOLOCATION_DICTIONARY["$ip"] ]]; then 
                IP_GEOLOCATION_DICTIONARY[$ip]=$(geolocate_ip "$ip")
            fi
        done 
    fi

    if ! is_empty "$IP6_MATCHES"; then 
        readarray -t <<< "$IP6_MATCHES"

        for ip in "${MAPFILE[@]}"; do 
            if [[ ! -v IP_GEOLOCATION_DICTIONARY["$ip"] ]]; then 
                IP_GEOLOCATION_DICTIONARY[$ip]=$(geolocate_ip "$ip")
            fi
        done 
    fi
}

remove_duplicates() {
    local text=$1
    echo "$text" | sort -u --numeric-sort
}

extract_ip_addreses_based_on_mode() {
    if is_empty "$DATA_SOURCE"; then
        data_source_is_empty
    fi

    echo -e "$greenColour [ HARVEST ]$endColour$grayColour Extracting IPs from data source provided$endColour\n"
    case $MODE in 
    ipv4)
        extract_ipv4_from_source "$DATA_SOURCE" "$DATA_SOURCE_TYPE"
        ;;
    ipv6) 
        extract_ipv6_from_source "$DATA_SOURCE" "$DATA_SOURCE_TYPE"
        ;;
    both) 
        extract_ipv4_from_source "$DATA_SOURCE" "$DATA_SOURCE_TYPE"
        extract_ipv6_from_source "$DATA_SOURCE" "$DATA_SOURCE_TYPE"
        ;;
    *) 
        echo -e "$redColour The selected mode$endColour$yellowColour $MODE$endColour is not supported"
        exit 1
        ;; 
    esac
}

function classify_ips() {
    local ips=$1
    echo "$ips" | tr ' ' '\n' | sort | uniq -c | sort -nr | awk '{print $2"\t"$1}'
}

build_information_table() {
    table_header="IP-ADDRESS COUNT COUNTRY LATITUDE LONGITUDE TIMEZONE ISP\n"

    ! is_empty "$IP4_MATCHES" && { [ "$MODE" = 'ipv4' ] || [ "$MODE" = 'both' ]; } \
        && table_body+="$(classify_ips "$IP4_MATCHES")"

    ! is_empty "$IP6_MATCHES" && { [ "$MODE" = 'ipv6' ] || [ "$MODE" = 'both' ]; } \
        && table_body+="$(classify_ips "$IP6_MATCHES")"

    if [ $GEOLOCATION -eq 1 ]; then
        readarray -t table_rows <<< "$table_body"

        table_geo=''

        for row in "${table_rows[@]}"; do

            row=$(echo -n "$row" | sed 's/\n$//')
            ip=$(echo "$row" | awk '{print $1}')

            if ! is_empty "$ip" && [[ -v IP_GEOLOCATION_DICTIONARY["$ip"] ]]; then
                geo_data=${IP_GEOLOCATION_DICTIONARY["$ip"]}
                
                country_property="data.geo.country_name"
                latitude_property="data.geo.latitude"
                longitude_property="data.geo.longitude"
                timezone_property="data.geo.timezone"
                isp_property="data.geo.isp"

                if command_exists "jq"; then 
                    country_property=".$country_property"
                    latitude_property=".$latitude_property"
                    longitude_property=".$longitude_property"    
                    timezone_property=".$timezone_property"    
                    isp_property=".$isp_property"    

                    country=$(echo "$geo_data" | jq "$country_property" | sed 's/[[:space:]]\{1,\}/_/g' | sed 's/\"//g')
                    latitude=$(echo "$geo_data" | jq "$latitude_property")
                    longitude=$(echo "$geo_data" | jq "$longitude_property")  
                    timezone=$(echo "$geo_data" | jq "$timezone_property" | sed 's/\"//g')  
                    isp=$(echo "$geo_data" | jq "$isp_property" | sed 's/[[:space:]]\{1,\}/_/g' | sed 's/\"//g')
                else 
                    country=$(extract_json_property "$geo_data" "$country_property" | sed 's/[[:space:]]\{1,\}/_/g' | sed 's/\"//g')
                    latitude=$(extract_json_property "$geo_data" "$latitude_property")
                    longitude=$(extract_json_property "$geo_data" "$longitude_property")
                    timezone=$(extract_json_property "$geo_data" "$timezone_property" | sed 's/\"//g')
                    isp=$(extract_json_property "$geo_data" "$isp_property" | sed 's/[[:space:]]\{1,\}/_/g' | sed 's/\"//g')
                fi
                table_geo+="$row $country $latitude $longitude $timezone $isp\n"
            fi
        done 
        echo -e "\n$table_header $table_geo" | column -t
    else 
        echo -e "\n$table_header $table_body" | column -t
    fi
}

save_result_to_file() {
    local result=$1
    local filepath=$2

    if ! is_empty "$filepath"; then
        if [[ "$filepath" =~ (.json)$ ]]; then
            if command_exists 'jq'; then 
                echo "$result" | tail -n+2 | sed 's/  */ /g' | jq -Rsr 'split("\n") | map(select(length > 0)) | map(split(" ")) | map({("IP-ADDRESS"): .[0], ("COUNT"): .[1], ("COUNTRY"): .[2:-4] | join(" "), ("LATITUDE"): .[-4], ("LONGITUDE"): .[-3], ("TIMEZONE"): .[-2], ("ISP"): .[1-2:] | join(" ")})' 1> "$filepath"
                
                # Only get ip address and count properties when geolocation is not calculated
                if [ $GEOLOCATION -eq 0 ]; then
                    # This behavior with tmp_file is because jq -i flag is not available always
                    jq 'map(del(.COUNTRY, .LATITUDE, .LONGITUDE, .TIMEZONE, .ISP))' "$filepath" > tmp_file && mv tmp_file "$filepath"
                fi 

                show_ip_report_message "$filepath"
            else 
                echo -e "[ FAILED ]$redColour The save the file in format .json the tool$endColour$yellowColour jq$endColour$redColour needs to be installed$endColour"
            fi 
        elif [[ "$filepath" =~ (.csv)$ ]]; then
            echo "$result" | awk -F ' ' 'BEGIN{OFS=","} {print $1,$2,$3,$4,$5,$6,$7}' 1> "$filepath"
            show_ip_report_message "$filepath"
        else
            if echo "$result" > "$filepath"; then
                show_ip_report_message "$filepath"
            else
                echo -e "$redColour [ FAILED ] Failed to write IP report to$endColour$yellowColour $filepath$endColour "
                exit 1
            fi
        fi
    fi
}

## Check if no arguments are provided to the script
if [ "$#" -eq 0 ]; then
    data_source_is_empty
fi

for arg in "$@"; do
shift
    case "$arg" in
        '--output')            set -- "$@" '-o'   ;;
        '--geolocation')       set -- "$@" '-g'   ;;
        '--source')            set -- "$@" '-s'   ;;
        '--mode')              set -- "$@" '-m'   ;;
        '--version')           set -- "$@" '-v'   ;;
        '--help')              set -- "$@" '-h'   ;;
        *)                     set -- "$@" "$arg" ;;
    esac
done

while getopts ":s:m:o:gvh:" arg; do
    case $arg in
        s) set_data_source "$OPTARG";;
        m) set_mode "$OPTARG";;
        o) OUTPUT_FILE="$OPTARG";;
        g) GEOLOCATION=1;;
        v) show_version;;
        h | *)
            show_help
        ;;
    esac
done
shift $(( OPTIND - 1))

banner
extract_ip_addreses_based_on_mode

if [ $GEOLOCATION -eq 1 ]; then
    echo -e "$greenColour [ GEOLOCATION ]$endColour$grayColour Fetching geolocation data for each IP found in the source...$endColour"
    calculate_geolocation
fi

result=$(build_information_table)

save_result_to_file "$result" "$OUTPUT_FILE"

# Only shows the total result if no output file was provided
is_empty "$OUTPUT_FILE" \
    && echo -e "$result"
