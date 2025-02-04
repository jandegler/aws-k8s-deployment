#!/bin/bash

#### Worker Node
# Retrieving the join command and joining the cluster.


### Variables

## User Data Script - Manual Environment Variables Setup
export HOME=/root
export USER=root

## S3 URI for sharing the join command
JOIN_COMMAND_S3_URI=${TF_JOIN_COMMAND_S3_URI}


### Retrieve and Execute Join Command
RETRY_INTERVAL=15  # seconds
echo "Trying to retrieve and execute the join command"
while true; do
    JOIN_COMMAND=$(aws s3 cp "$JOIN_COMMAND_S3_URI" -)
    if [[ $? -eq 0  ]]; then
        echo "Join command retrieved."

        echo "Executing join command."
        # Careful, eval is notoriously dangerous due to the possibility of command injection. Rewrite this into an
        # explicit kubeadm join command for anything other than a simple experimental environment.
        eval "$JOIN_COMMAND"
        if [[ $? -eq 0  ]]; then
            echo "Join command execution finished successfully."
            break
        fi

        echo "Join command execution failed. Retrying in $RETRY_INTERVAL seconds..."
        sleep $RETRY_INTERVAL
    else
      echo "Join command retrieval from S3 failed. Retrying in $RETRY_INTERVAL seconds..."
      sleep $RETRY_INTERVAL
    fi
done

echo "Worker node script finished"

