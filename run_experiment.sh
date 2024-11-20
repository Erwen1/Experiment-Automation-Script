#!/bin/bash

# Prompt for IoT-LAB login credentials
read -p "Enter your IoT-LAB username: " username
echo

# Authenticate with IoT-LAB
echo "Authenticating with IoT-LAB..."
iotlab-auth -u "$username" <<EOF
$password
EOF

if [ $? -ne 0 ]; then
    echo "Authentication failed. Please check your username and password."
    exit 1
fi
echo "Authentication completed successfully."

# Fetch available sites
echo "Fetching available sites..."
sites=$(iotlab-status --sites | jq -r '.items[].site')
if [[ -z "$sites" ]]; then
    echo "Failed to fetch sites. Exiting."
    exit 1
fi

echo "Available sites:"
select site in $sites; do
    if [[ -n "$site" ]]; then
        selected_site="$site"
        echo "You selected: $selected_site"
        break
    else
        echo "Invalid selection. Try again."
    fi
done

# Fetch architectures for the selected site
echo "Fetching architectures for site '$selected_site'..."
archis=$(iotlab-status --sites | jq -r --arg site "$selected_site" '.items[] | select(.site==$site) | .archis[].archi')
if [[ -z "$archis" ]]; then
    echo "Failed to fetch architectures for site '$selected_site'. Exiting."
    exit 1
fi

echo "Available architectures at '$selected_site':"
select archi in $archis; do
    if [[ -n "$archi" ]]; then
        selected_archi="$archi"
        echo "You selected: $selected_archi"
        break
    else
        echo "Invalid selection. Try again."
    fi
done

# Fetch alive nodes for the selected architecture
echo "Fetching alive nodes for architecture '$selected_archi' at site '$selected_site'..."
alive_nodes=$(iotlab-status --nodes --archi "$selected_archi" --site "$selected_site" --state Alive | jq -r '.items[].network_address')

if [[ -z "$alive_nodes" ]]; then
    echo "No alive nodes found for architecture '$selected_archi' at site '$selected_site'. Exiting."
    exit 1
fi

alive_nodes_array=($alive_nodes)
echo "Available alive nodes: ${#alive_nodes_array[@]}"
read -p "Enter the number of nodes you want to use (max: ${#alive_nodes_array[@]}): " num_nodes

if ! [[ "$num_nodes" =~ ^[0-9]+$ ]] || [[ "$num_nodes" -lt 1 ]] || [[ "$num_nodes" -gt "${#alive_nodes_array[@]}" ]]; then
    echo "Invalid number of nodes. Exiting."
    exit 1
fi

selected_nodes=$(printf ",%s" "${alive_nodes_array[@]:0:num_nodes}")
selected_nodes="${selected_nodes:1}" # Remove leading comma

# Submit the experiment with the selected nodes
echo "Submitting experiment..."
experiment_id=$(iotlab-experiment submit -n profile_example -d 20 -l "$num_nodes",archi="$selected_archi"+site="$selected_site" | jq -r '.id')

if [[ -z "$experiment_id" || "$experiment_id" == "null" ]]; then
    echo "Experiment submission failed. Exiting."
    exit 1
fi

echo "Experiment submitted with ID: $experiment_id"

# Wait for the experiment to start running
echo "Waiting for the experiment to start..."
while true; do
    experiment_state=$(iotlab-experiment get -i "$experiment_id" -s | jq -r '.state')
    if [[ "$experiment_state" == "Running" ]]; then
        echo "The experiment is running."
        break
    else
        echo "Waiting..."
        sleep 5
    fi
done

# Get experiment node info
echo "Fetching experiment node information..."
node_info=$(iotlab-experiment get -i "$experiment_id" -n)
echo "Experiment node information:"
echo "$node_info"

# Get deployment results
echo "Fetching deployment results..."
deployment_status=$(iotlab-experiment get -i "$experiment_id" -d | jq -r '."0"')
if [[ "$deployment_status" == "null" ]]; then
    echo "Deployment error detected."
    exit 1
else
    echo "Deployment successful."
    echo "$deployment_status"
fi

# Start debugging
echo "Starting debugging for selected nodes..."
debug_status=$(iotlab-node --debug-start -i "$experiment_id" | jq -r '."0"')

if [[ "$debug_status" == "null" ]]; then
    echo "Debugging failed. Please check the nodes and configurations."
else
    echo "Debugging successful for nodes:"
fi

echo "Script execution completed!"
