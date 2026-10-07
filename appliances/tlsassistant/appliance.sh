#!/usr/bin/env bash

# TLSAssistant Appliance Installation Script
# https://github.com/stfbk/tlsassistant
# Docker Image: ghcr.io/stfbk/tlsassistant:v3.2

set -o pipefail
# set -o errexit -o pipefail

# oneapp parameters
ONE_SERVICE_PARAMS=(
    'ONEAPP_SCAN_ENDPOINT_TARGET_URL'          'configure'  'Target URL or IP'                         'M|text'
    'ONEAPP_SCAN_ENDPOINT_RESOLVE_IP'          'configure'  'Resolve IP flag'                          'O|boolean'
    'ONEAPP_SCAN_VULN_MODULES'                 'configure'  'Vulnerability modules to run'             'O|list-multiple'
    'ONEAPP_STORAGE_S3_ENDPOINT'               'configure'  'S3 API Endpoint'                          'M|text'
    'ONEAPP_STORAGE_S3_BUCKET'                 'configure'  'S3 Bucket Name'                           'M|text'
    'ONEAPP_STORAGE_S3_ACCESS_KEY'             'configure'  'S3 Access Key'                            'M|text'
    'ONEAPP_STORAGE_S3_SECRET_KEY'             'configure'  'S3 Secret Key'                            'M|password'
    'ONEAPP_STORAGE_S3_REGION'                 'configure'  'S3 Region for URL signature'              'O|text'
    'ONEAPP_STORAGE_S3_CUSTOM_HOST_IP'         'configure'  'S3 Custom Host IP'                        'O|text'
    'ONEAPP_COMPLIANCE_CONFIG_ENABLED'         'configure'  'Enable compliance scan'                   'M|boolean'
    'ONEAPP_COMPLIANCE_CONFIG_COMPAREMANY'     'configure'  'Compare against multiple guidelines'      'M|boolean'
    'ONEAPP_COMPLIANCE_CONFIG_GUIDELINES_ONE'  'configure'  'Single guideline to evaluate against'     'O|list'
    'ONEAPP_COMPLIANCE_CONFIG_GUIDELINES_MANY' 'configure'  'Multiple guidelines to evaluate against'  'O|list-multiple'
    'ONEAPP_COMPLIANCE_CONFIG_GUIDELINES_FILENAME' 'configure' 'Custom guideline filename'             'O|text'
    'ONEAPP_COMPLIANCE_CONFIG_GUIDELINES_CUSTOM' 'configure' 'Custom guidelines (comma-separated)'     'O|text'
    'ONEAPP_COMPLIANCE_EXTRA_SECURITY'         'configure'  'Enable enhanced security'                 'O|boolean'
    'ONEAPP_COMPLIANCE_EXTRA_OPENSSL_VERSION'  'configure'  'Version to consider for the scan'         'O|list'
)

# defaults
DOCKER_IMAGE="ghcr.io/stfbk/tlsassistant:v3.2"
DEFAULT_TARGET_URL="opennebula.io"
DEFAULT_RESOLVE_IP="NO"
DEFAULT_S3_ENDPOINT=""
DEFAULT_VULN_MODULES="3shake alpaca beast breach ccs_injection certificate_transparency crime drown freak heartbleed hsts_preloading hsts_set https_enforced logjam lucky13 mitzvah nomore padding_oracle pfs raccoon renegotiation robot sloth sslpoodle sweet32 ticketbleed tlspoodle"
DEFAULT_S3_BUCKET="tlsa-reports"
DEFAULT_CONTAINER_NAME="tlsassistant"
DEFAULT_VOLUMES="/data:/tlsassistant/results"
DEFAULT_REGION="us-east-1"
DEFAULT_COMPLIANCE_ON="NO"
DEFAULT_COMPLIANCE_COMPAREMANY="NO"
DEFAULT_COMPLIANCE_EXTRA_SECURITY="NO"
DEFAULT_COMPLIANCE_GUIDELINES_ONE="ACN"
DEFAULT_COMPLIANCE_GUIDELINES_MANY="ACN,NIST"
DEFAULT_COMPLIANCE_GUIDELINES_FILENAME="custom_guidelines.json"
DEFAULT_PORTS=""
APP_NAME="TLSAssistant"
APPLIANCE_NAME="tlsassistant"

# metadata
ONE_SERVICE_NAME='TLSAssistant'
ONE_SERVICE_VERSION=   #latest
ONE_SERVICE_BUILD=$(date +%s)
ONE_SERVICE_SHORT_DESCRIPTION='TLSAssistant Docker Container Appliance'
ONE_SERVICE_DESCRIPTION='TLSAssistant running in Docker container'
ONE_SERVICE_RECONFIGURABLE=true

# error mappings
declare -A error_codes
error_codes[1]="The custom guideline could not be found: %s."
error_codes[2]="The s3 endpoint could not be resolved. Double check connection and routing."
error_codes[3]="Credentials for the s3 storage are invalid."
error_codes[4]="No report found. Container failed."
error_codes[5]="OneGate CLI not found or context token missing."
error_codes[6]="Container exited with error code: %s"

# additional context for formatted error messages
APP_ERROR_DETAIL=""

service_cleanup()
{
    :
}

service_install()
{
    export DEBIAN_FRONTEND=noninteractive

    apt-get update
    apt-get upgrade -y

    apt-get install -y ca-certificates curl
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    systemctl enable docker
    systemctl start docker

    msg info "Pulling Docker image: $DOCKER_IMAGE"
    docker pull "$DOCKER_IMAGE"

    systemctl stop unattended-upgrades 2>/dev/null || true
    systemctl disable unattended-upgrades 2>/dev/null || true

    apt-get install -y mingetty

    mkdir -p /etc/systemd/system/getty@tty1.service.d
    cat > /etc/systemd/system/getty@tty1.service.d/override.conf << 'CONSOLE_EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noissue --autologin root %I \\$TERM
Type=idle
CONSOLE_EOF

    mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d
    cat > /etc/systemd/system/serial-getty@ttyS0.service.d/override.conf << 'SERIAL_EOF'
[Service]
ExecStart=
ExecStart=-/sbin/agetty --noissue --autologin root %I 115200,38400,9600 vt102
Type=idle
SERIAL_EOF

    systemctl enable getty@tty1.service serial-getty@ttyS0.service

    cat > /etc/profile.d/99-${APPLIANCE_NAME}-welcome.sh << WELCOME_EOF
#!/bin/bash
case \\\$- in
    *i*) ;;
      *) return;;
esac

echo "=================================================="
echo "  $APP_NAME Appliance"
echo "=================================================="
echo "  Docker Image: $DOCKER_IMAGE"
echo "  Container: $DEFAULT_CONTAINER_NAME"
echo "  Ports: $DEFAULT_PORTS"
echo ""
echo "  Commands:"
echo "    docker ps                    - Show running containers"
echo "    docker logs $DEFAULT_CONTAINER_NAME   - View container logs"
echo ""
echo "  Access Methods:"
echo "    SSH: Enabled (key-only via OpenNebula context)"
echo "    Console: Auto-login as root (via OpenNebula console)"
echo "    Serial: Auto-login as root (via serial console)"
echo "=================================================="
WELCOME_EOF

    chmod +x /etc/profile.d/99-${APPLIANCE_NAME}-welcome.sh

    # install awscli from source
    curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip"
    unzip awscliv2.zip
    rm awscliv2.zip
    
    ./aws/install
    rm -rf aws

    apt-get autoremove -y
    apt-get autoclean
    find /var/log -type f -exec truncate -s 0 {} \;

    sync

    return 0
}

service_configure()
{
    msg info "Verifying Docker is running"

    if ! systemctl is-active --quiet docker; then
        msg info "Docker is not running"
        return 1
    fi

    msg info "Docker is running"
    return 0
}

service_bootstrap()
{
    msg info "Starting $APP_NAME service bootstrap"

    # this is an hack around a possible set -e errexit enforced by one-context
    local exit_status=0
    setup_app_container || exit_status=$?
    msg info "Container setup exited with code ($exit_status)"
    
    if [ "$exit_status" -ne 0 ]; then
        local template="${error_codes[$exit_status]}"
        local error_msg="placeholder error message"

        if [ -n "$template" ]; then
            if [[ "$template" == *"%s"* ]]; then
                error_msg=$(printf "$template" "${APP_ERROR_DETAIL:-}")
            else
                error_msg="$template"
            fi
        else
            error_msg="Unknown error occurred (code $exit_status)"
        fi

        msg info "Appliance setup failed: $error_msg"

        if [ -x "$(command -v onegate)" ]; then
            onegate vm update --data ERROR_MESSAGE="$error_msg" || msg info "ERROR_MESSAGE upload failes"
        fi
    fi

    # msg info "Scan completed successfully, shutting down..."
    msg info "Shutting down..."
    poweroff
}

setup_app_container()
{
    local target_url="${ONEAPP_SCAN_ENDPOINT_TARGET_URL:-$DEFAULT_TARGET_URL}"
    
    local resolve_ip="${ONEAPP_SCAN_ENDPOINT_RESOLVE_IP:-$DEFAULT_RESOLVE_IP}"
    local resolve_ip_flag=""
    if [ "$resolve_ip" = "YES" ] || [ "$resolve_ip" = "true" ]; then
        resolve_ip_flag="--resolve-ip"
    fi

    local scan_modules="${ONEAPP_SCAN_VULN_MODULES:-all}"
    scan_modules="${scan_modules//,/ }"
    local -a module_args=()

    if [[ "$scan_modules" =~ (^|[[:space:]])all($|[[:space:]]) ]]; then
        read -r -a module_args <<< "$DEFAULT_VULN_MODULES"
    elif [[ "$scan_modules" =~ (^|[[:space:]])none($|[[:space:]]) ]]; then
        module_args=()
    else
        read -r -a module_args <<< "$scan_modules"
    fi

    local s3_endpoint="${ONEAPP_STORAGE_S3_ENDPOINT:-$DEFAULT_S3_ENDPOINT}"
    s3_endpoint="${s3_endpoint%/}"

    local s3_bucket="${ONEAPP_STORAGE_S3_BUCKET:-$DEFAULT_S3_BUCKET}"
    local s3_access="${ONEAPP_STORAGE_S3_ACCESS_KEY:-}"
    local s3_secret="${ONEAPP_STORAGE_S3_SECRET_KEY:-}"
    local s3_region="${ONEAPP_STORAGE_S3_REGION:-$DEFAULT_REGION}"
    local s3_custom_host_ip="${ONEAPP_STORAGE_S3_CUSTOM_HOST_IP:-}"

    local compliance_flag="${ONEAPP_COMPLIANCE_CONFIG_ENABLED:-$DEFAULT_COMPLIANCE_ON}"
    local compare_many_flag="${ONEAPP_COMPLIANCE_CONFIG_COMPAREMANY:-$DEFAULT_COMPLIANCE_COMPAREMANY}"
    local compliance_guidelines=""
    local custom_guidelines_source=""
    local custom_guidelines_filename=""
    local custom_guidelines_path=""
    local security_flag=""

    if [ "$compliance_flag" = "YES" ] || [ "$compliance_flag" = "true" ]; then
        if [ "$compare_many_flag" = "YES" ] || [ "$compare_many_flag" = "true" ]; then
            local guidelines_many="${ONEAPP_COMPLIANCE_CONFIG_GUIDELINES_MANY:-$DEFAULT_COMPLIANCE_GUIDELINES_MANY}"
            local guidelines_filename="${ONEAPP_COMPLIANCE_CONFIG_GUIDELINES_FILENAME:-$DEFAULT_COMPLIANCE_GUIDELINES_FILENAME}"
            local guidelines_custom="${ONEAPP_COMPLIANCE_CONFIG_GUIDELINES_CUSTOM:-}"
            local -a guidelines_parts=()
            local guideline_part=""

            if [[ ",${guidelines_many}," == *",custom,"* ]]; then
                msg info "custom guidelines found, trying to find custom file"

                local found_tmp
                found_tmp=$(find /run/one-context/ -type f \( -name "$DEFAULT_COMPLIANCE_GUIDELINES_FILENAME" -o -name "$guidelines_filename" \) -print -quit 2>/dev/null)
                                
                if [ -n "$found_tmp" ]; then
                    custom_guidelines_source="$found_tmp"
                    custom_guidelines_filename="$guidelines_filename"
                    msg info "Custom guideline file found at $custom_guidelines_source"
                else
                    APP_ERROR_DETAIL="$guidelines_filename"
                    msg info "Could not find custom guideline file payload inside context directory!"
                    return 1
				fi
            fi

            if [ -n "$guidelines_many" ]; then
                local custom_found=false
                IFS=',' read -r -a guidelines_parts <<< "$guidelines_many"
                for guideline_part in "${guidelines_parts[@]}"; do
                    if [ "$guideline_part" = "custom" ]; then
                        if [ "$custom_found" = "true" ]; then
                            msg info "Duplicate 'custom' entry in guidelines list, this is not supported (yet)"
                            continue
                        fi
                        custom_found=true
                        guideline_part="$guidelines_custom"
                    fi

                    if [ -n "$compliance_guidelines" ]; then
                        compliance_guidelines="$compliance_guidelines,$guideline_part"
                    else
                        compliance_guidelines="$guideline_part"
                    fi
                done
            fi
            module_args+=(compare_many)
        else
            compliance_guidelines="${ONEAPP_COMPLIANCE_CONFIG_GUIDELINES_ONE:-$DEFAULT_COMPLIANCE_GUIDELINES_ONE}"
            module_args+=(compare_one)
        fi
        if [ "${ONEAPP_COMPLIANCE_EXTRA_SECURITY:-$DEFAULT_COMPLIANCE_EXTRA_SECURITY}" = "YES" ] || \
               [ "${ONEAPP_COMPLIANCE_EXTRA_SECURITY:-$DEFAULT_COMPLIANCE_EXTRA_SECURITY}" = "true" ]; then
            security_flag="" # defaults to true is missing
        else
            security_flag="--security=false"
        fi
    fi

    local container_name="${ONEAPP_CONTAINER_NAME:-$DEFAULT_CONTAINER_NAME}"
    local container_volumes="${ONEAPP_CONTAINER_VOLUMES:-$DEFAULT_VOLUMES}"
    local -a volume_args=()
    
    # handle ONEAPP_STORAGE_S3_CUSTOM_HOST_IP
    if [ -n "$s3_custom_host_ip" ] && [ -n "$s3_endpoint" ]; then

        # strip protocol and path/port
        local s3_host=$(echo "$s3_endpoint" | sed -e 's|^[^/]*//||' -e 's|/.*$||' -e 's|:.*$||')

        if [ -n "$s3_host" ]; then
            msg info "Seeding /etc/hosts: $s3_custom_host_ip -> $s3_host"
            echo "$s3_custom_host_ip $s3_host" >> /etc/hosts
        fi
    fi
        
    export AWS_ACCESS_KEY_ID="$s3_access"
    export AWS_SECRET_ACCESS_KEY="$s3_secret"
    export AWS_DEFAULT_REGION="$s3_region"
    
    if ! resolve_endpoint "$s3_endpoint"; then
        return 2
    fi

    # force awscli to use path-style addressing (CRITICAL for minio and IP addresses)
    aws configure set default.s3.addressing_style path
    aws configure set default.s3.signature_version s3v4
    aws configure set default.region "$s3_region" 
     
    msg info "Setting up $APP_NAME container: $container_name"

    if docker ps -a --format '{{.Names}}' | grep -q "^${container_name}$"; then
        msg info "Stopping existing container: $container_name"
        docker stop "$container_name" 2>/dev/null || true
        docker rm "$container_name" 2>/dev/null || true
    fi

    local host_path="/data"
    if [ -n "$container_volumes" ]; then
        IFS=',' read -ra VOL_ARRAY <<< "$container_volumes"
        for vol in "${VOL_ARRAY[@]}"; do
            host_path=$(echo "$vol" | cut -d':' -f1)
            if [ ! -e "$host_path" ]; then
                mkdir -p "$host_path"
                chown -R 1000:1000 "$host_path" 2>/dev/null || true
            fi
            volume_args+=(-v "$vol")
        done
    fi

    if [ -n "$custom_guidelines_source" ] && [ -n "$custom_guidelines_filename" ]; then
        cp "$custom_guidelines_source" "/data/$custom_guidelines_filename"
        custom_guidelines_path="/tlsassistant/results/$custom_guidelines_filename"
    fi

    msg info "Starting $APP_NAME container with:"
    msg info "  Volumes: $container_volumes"
    msg info "  Target: $target_url"
    msg info "  Modules: ${module_args[*]}"
    if [ -n "$compliance_guidelines" ]; then
        msg info "  Guidelines: $compliance_guidelines"
    fi
    
    local -a docker_cmd=(docker run --name "$container_name")
    if [ "${#volume_args[@]}" -gt 0 ]; then
        docker_cmd+=("${volume_args[@]}")
    fi

    docker_cmd+=("$DOCKER_IMAGE" -s "$target_url" -m)
    docker_cmd+=("${module_args[@]}")

    if [ -n "$compliance_guidelines" ]; then
        docker_cmd+=(--guidelines "$compliance_guidelines")
    fi

    if [ -n "$custom_guidelines_path" ]; then
        docker_cmd+=(--custom_guidelines "$custom_guidelines_path")
    fi

    if [ -n "$resolve_ip_flag" ]; then
        docker_cmd+=("$resolve_ip_flag")
    fi

    if [ -n "$security_flag" ]; then
        docker_cmd+=("$security_flag")
    fi

    docker_cmd+=(-ot pdf)

    local openssl_version="${ONEAPP_COMPLIANCE_EXTRA_OPENSSL_VERSION:-ignore}"
    if [ -z "$openssl_version" ] || [ "$openssl_version" = "ignore" ]; then
        docker_cmd+=(--ignore-openssl)
    else
        docker_cmd+=(--openssl-version "$openssl_version")
    fi

    "${docker_cmd[@]}"
    local docker_exit=$?
    
    docker_command_full=$(docker inspect --format='{{.Path}} {{range .Args}} {{.}} {{end}}' "$container_name" 2>/dev/null || true)
    msg info "  Command: $docker_command_full"
    
    msg info "Scan complete, locating report..."
    local report_file
    report_file=$(find "$host_path" -name '*.pdf' -print -quit 2>/dev/null || true)

    if [ -z "$report_file" ]; then
        # APP_ERROR_DETAIL="$docker_exit"
        msg info "No report found in $host_path!"
        return 4
    fi

    # even if the file is found, we could still have all invalid scans
    if [ "$docker_exit" = 1 ]; then
        APP_ERROR_DETAIL="(1) hostname unreachable"
        msg info "Non 0 exit code found after scan completion, report file found."
        return 6
    fi
    
    local filename=$(basename "$report_file")
    local s3_key="tls-report-$filename"
    msg info "Uploading $report_file to s3://$s3_bucket/$s3_key"

    if ! aws s3 cp "$report_file" "s3://$s3_bucket/$s3_key" \
         --endpoint-url "$s3_endpoint" \
         --region "$s3_region" \
         --content-type "application/pdf"; then
        APP_ERROR_DETAIL="$s3_bucket"
        msg info "Failed to upload report to S3"
        return 3
    fi

    msg info "Generating pre-signed URL..."
    local presigned_url=$(aws s3 presign "s3://$s3_bucket/$s3_key" \
                              --endpoint-url "$s3_endpoint" \
                              --region "$s3_region" \
                              --expires-in 604800)

    # public url if the user allows unsigned access to the reports
    local public_url="${presigned_url%%\?*}"
    
    # this is needed since onegate does not escape the '&' correctly
    local clean_presigned_url=$(echo "$presigned_url" | sed 's/&/%26/g')
    
    msg info "Pushing URL ($clean_presigned_url) to OpenNebula via OneGate..."
    if [ -x "$(command -v onegate)" ]; then
        onegate vm update --data REPORT_URL="$clean_presigned_url"
        onegate vm update --data PUBLIC_URL="$public_url"
        msg info "Successfully pushed REPORT_URL to OneGate."
    else
        msg info "OneGate CLI not found or context token missing."
        return 5
    fi
}

###############################################################################

# helper functions

resolve_endpoint() {
    local endpoint="$1"
    
    local hostname=$(echo "$endpoint" | sed -e 's|^[^/]*//||' -e 's|/.*$||' -e 's|:.*$||')
    
    if [ -n "$hostname" ] && [[ ! "$hostname" =~ ^[0-9.]+$ ]]; then
        msg info "Waiting for $hostname to be resolvable (timeout 60s)..."
        local retry=0
        while ! getent hosts "$hostname" &>/dev/null; do
            if [[ $retry -ge 60 ]]; then
                APP_ERROR_DETAIL="$hostname"
                msg info "Timeout: $hostname never became resolvable."
                return 1
            fi
            sleep 1
            ((retry++))
        done
        msg info "$hostname is now reachable."
    fi

    return 0
}
