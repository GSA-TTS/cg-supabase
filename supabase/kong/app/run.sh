#!/bin/bash -e

source ./set_kong_env.sh

# Ensure references to /usr/local resolve correctly
grep -irIl '/usr/local' ../deps/0/apt | xargs sed -i -e "s|/usr/local|$LOCAL|"

# Generate the kong.yaml state file
envsubst < kong-config.yml > ~/kong.yml
envsubst < kong.conf.template > ~/kong.conf

watch_certs() {
    while true ; do 
        # wait to make sure the main kong process has started
        sleep 1m

        # Sanity check to ensure 'kong' is on the current $PATH
        kong version 

        instance_identity_cert_folder=$(dirname "$CF_INSTANCE_CERT")

        # Infinite-loop that will watch the cf instance identity certs for changes
        # and tell kong to reload its configuration if the files are updated.
        while inotifywait -q -e modify "$instance_identity_cert_folder" ; do 
            kong reload -c ./kong.conf --v
        done
    done
}

# Fork the certificate-watcher into the background
watch_certs &

# Start the main Kong application.
kong start -c ./kong.conf --v
