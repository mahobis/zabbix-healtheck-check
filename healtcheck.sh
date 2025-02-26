#!/bin/bash
# Cloudflare API information
CF_API_TOKEN=""
CF_API_EMAIL=""
# Zabbix serverio informacija
ZABBIX_URL=""
AUTH_TOKEN=""

# Get host ID by name"
HOST_ID=""


# file whit domains that responded
FILE="domain-exist.txt"

# File with all domains
FILEALL="domain.txt"

# Check if the file exists
if [[ ! -f "$FILE" ]]; then
    echo "Failas domain-exist.txt nerastas!"
else
        rm -rf $FILE
fi

# Check if the file exists
if [[ ! -f "$FILEALL" ]]; then
    echo "Failas domain.txt nerastas!"
else
        rm -rf $FILEALL
fi




# Function to get all zones (domains) associated with the account
get_all_zones() {
    curl -s -X GET "https://api.cloudflare.com/client/v4/zones" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" | jq -r '.result[] | .name'
}

# Fetch all domains
DOMAINS=($(get_all_zones))

# Loop through each domain
for domain in "${DOMAINS[@]}"; do
    echo "Checking domain: $domain"

    # Get Zone ID for the domain
    ZONE_ID=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones?name=$domain" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json" | jq -r '.result[0].id')

    if [[ -z "$ZONE_ID" || "$ZONE_ID" == "null" ]]; then
        echo "Failed to find Zone ID for domain: $domain"
        continue
    else
        echo "Zone ID for $domain: $ZONE_ID"
    fi

    # List DNS Records for the domain
    DNS_RECORDS=$(curl -s -X GET "https://api.cloudflare.com/client/v4/zones/$ZONE_ID/dns_records" \
    -H "Authorization: Bearer $CF_API_TOKEN" \
    -H "Content-Type: application/json")

    # Check if DNS records were retrieved successfully
    if [[ -z "$DNS_RECORDS" || $(echo "$DNS_RECORDS" | jq '.success') != "true" ]]; then
        echo "Failed to retrieve DNS records for domain: $domain"
        continue
    else
        echo "DNS records for $domain (A and CNAME only):"
        echo "$DNS_RECORDS" | jq -r '.result[] | select(.type == "A" or .type == "CNAME") | "\(.name)"' >> $FILEALL
    fi
done

echo "DNS records retrieved for all domains!"


# Check each domain from the file
while IFS= read -r domain; do
    url="https://${domain}/healthcheck"
    response=$(curl -s --max-time 5 "$url" | jq -r '.status')

    if [[ "$response" == "green" ]]; then
        echo "$domain: OK (green)"
        echo "https://${domain}" >> $FILE
    else
        echo "$domain: NOT OK (response: $response)"
    fi
done < "$FILEALL"

# Check if host ID was obtained
if [[ -z "$HOST_ID" || "$HOST_ID" == "null" ]]; then
    echo "Failed to find host ID for the server"
    exit 1
else
    echo "Host ID found: $HOST_ID"
fi

# Check if the file exists
if [[ ! -f "$FILE" ]]; then
    echo "File not found domain-exist.txt !"
    exit 1
fi

# Create Web scenario for each domain
STEP_NO=1
while IFS= read -r domain; do
    url="${domain}/healthcheck"
    scenario_name="${domain} Healthcheck"
    cleaned_scenario_name=$(echo "$scenario_name" | sed 's|https://||')

    echo "Tikrinamas esamas scenarijus: $scenario_name"

    # Check if the scenario already exists
    result=$(curl -s -X POST -H "Content-Type: application/json" -d '{
        "jsonrpc": "2.0",
        "method": "httptest.get",
        "params": {
            "output": "extend",
            "filter": {
                "name": "'"$cleaned_scenario_name"'",
                "hostid": "'"$HOST_ID"'"
            }
        },
        "auth": "'"$AUTH_TOKEN"'",
        "id": 2
    }' "$ZABBIX_URL")

    scenario_id=$(echo $result | jq -r '.result[0].httptestid')

    if [[ -n "$scenario_id" && "$scenario_id" != "null" ]]; then
        echo "Scenarijus jau egzistuoja: $scenario_name"
    else
        echo "Kuriamas Web scenarijus: $domain"

        curl -s -X POST -H "Content-Type: application/json" -d '{
            "jsonrpc": "2.0",
            "method": "httptest.create",
            "params": {
                "name": "'"$cleaned_scenario_name"'",
                "hostid": "'"$HOST_ID"'",
                "steps": [
                    {
                        "no": '$STEP_NO',
                        "name": "'"$domain"'",
                        "url": "'"$url"'",
                        "required": "green"
                    }
                ],
                "retries": "3",
                "tags": [
                    {
                        "tag": "Application",
                        "value": "health check"
                    }
                ]
            },
            "auth": "'"$AUTH_TOKEN"'",
            "id": 5
        }' "$ZABBIX_URL"

        STEP_NO=$((STEP_NO + 1))
    fi

done < "$FILE"

echo "Web scenarios created on the Zabbix server"


# Function to get Host Name by Host ID
get_host_name() {
    local host_id=$1
    host_name=$(curl -s -X POST -H "Content-Type: application/json" -d '{
        "jsonrpc": "2.0",
        "method": "host.get",
        "params": {
            "hostids": "'"$host_id"'",
            "output": ["host"]
        },
        "auth": "'"$AUTH_TOKEN"'",
        "id": 1
    }' "$ZABBIX_URL" | jq -r '.result[0].host')

    echo "$host_name"
}

# Function to create a trigger
create_trigger() {
    local scenario_name=$1
    local trigger_name="${scenario_name} - Health Check Failed"

    # Escape special characters in scenario_name to avoid JSON parsing errors
    local escaped_scenario_name=$(echo "$scenario_name" | sed 's/\"/\\\"/g')

    # Get the host name dynamically by host ID
    HOST_NAME=$(get_host_name "$HOST_ID")

    # Format the expression according to the Zabbix requirement
    local expression="last(/$HOST_NAME/web.test.fail[$escaped_scenario_name])<>0"

    # Check if the trigger already exists
    trigger_exists=$(curl -s -X POST -H "Content-Type: application/json" -d '{
        "jsonrpc": "2.0",
        "method": "trigger.get",
        "params": {
            "filter": {
                "description": "'"$trigger_name"'"
            },
            "auth": "'"$AUTH_TOKEN"'",
            "id": 1
        }
    }' "$ZABBIX_URL" | jq -r '.result | length')

    # If trigger does not exist, create it
    if [[ "$trigger_exists" -eq 0 ]]; then
        echo "Creating trigger for scenario: $escaped_scenario_name"

        # Ensure the expression is correctly formatted with quotes and escape characters
        json_data=$(jq -n \
            --arg description "$trigger_name" \
            --arg expression "$expression" \
            --arg auth "$AUTH_TOKEN" \
            '{
                jsonrpc: "2.0",
                method: "trigger.create",
                params: {
                    description: $description,
                    expression: $expression,
                    priority: 4
                },
                auth: $auth,
                id: 1
            }')

        # Send request to Zabbix API using curl to create the trigger
        curl -s -X POST -H "Content-Type: application/json" -d "$json_data" "$ZABBIX_URL"
    else
        echo "Trigger for scenario: $escaped_scenario_name already exists."
    fi
}

# Read each domain from the file and create a trigger
while IFS= read -r domain; do
    scenario_name="${domain} Healthcheck"
    cleaned_scenario_name=$(echo "$scenario_name" | sed 's|https://||')

    create_trigger "$cleaned_scenario_name"
done < "$FILE"

echo "Process complete!"
