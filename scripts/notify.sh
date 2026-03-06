#!/bin/bash
# Slack Notification Script for TTPOS
# scripts/notify.sh

set -e

# Colors (for terminal output)
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Default values
STATUS=""
SERVICE=""
ENV=""
TAG=""
MESSAGE=""

# Help message
usage() {
    cat << EOF
Usage: $(basename "$0") [OPTIONS]

Send deployment notification to Slack.

Options:
    --status STATUS      Deployment status (success, failure, rollback, unhealthy)
    --service SERVICE    Service name
    --env ENVIRONMENT    Environment name
    --tag TAG            Image tag
    --message MESSAGE    Custom message
    -h, --help           Show this help message

Environment Variables:
    SLACK_WEBHOOK_URL    Slack webhook URL (required)

Examples:
    $(basename "$0") --status success --service main --env staging --tag v1.2.3
    $(basename "$0") --status failure --service nginx --env production
    $(basename "$0") --status unhealthy --env production
EOF
    exit 0
}

# Parse arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            --status)
                STATUS="$2"
                shift 2
                ;;
            --service)
                SERVICE="$2"
                shift 2
                ;;
            --env)
                ENV="$2"
                shift 2
                ;;
            --tag)
                TAG="$2"
                shift 2
                ;;
            --message)
                MESSAGE="$2"
                shift 2
                ;;
            -h|--help)
                usage
                ;;
            *)
                shift
                ;;
        esac
    done
}

# Get emoji for status
get_emoji() {
    case $1 in
        success)
            echo ":white_check_mark:"
            ;;
        failure)
            echo ":x:"
            ;;
        rollback)
            echo ":rewind:"
            ;;
        rollback_failed)
            echo ":warning:"
            ;;
        unhealthy)
            echo ":rotating_light:"
            ;;
        *)
            echo ":information_source:"
            ;;
    esac
}

# Get color for attachment
get_color() {
    case $1 in
        success)
            echo "good"
            ;;
        failure)
            echo "danger"
            ;;
        rollback)
            echo "warning"
            ;;
        rollback_failed)
            echo "danger"
            ;;
        unhealthy)
            echo "danger"
            ;;
        *)
            echo "#808080"
            ;;
    esac
}

# Build Slack message
build_message() {
    local emoji=$(get_emoji "$STATUS")
    local color=$(get_color "$STATUS")

    local title=""
    local text=""

    case $STATUS in
        success)
            title="Deployment Successful"
            text="Service *${SERVICE:-all}* deployed successfully to *${ENV}*"
            ;;
        failure)
            title="Deployment Failed"
            text="Failed to deploy *${SERVICE:-all}* to *${ENV}*"
            ;;
        rollback)
            title="Rollback Complete"
            text="Service *${SERVICE}* rolled back to *${TAG}* in *${ENV}*"
            ;;
        rollback_failed)
            title="Rollback Failed"
            text="Failed to rollback *${SERVICE}* in *${ENV}*"
            ;;
        unhealthy)
            title="Health Check Failed"
            text="Services in *${ENV}* are unhealthy"
            ;;
        *)
            title="Deployment Notification"
            text="${MESSAGE:-No message provided}"
            ;;
    esac

    # Build JSON payload
    local payload=$(cat <<EOF
{
    "attachments": [
        {
            "color": "${color}",
            "title": "${emoji} ${title}",
            "text": "${text}",
            "fields": [
                {
                    "title": "Environment",
                    "value": "${ENV:-unknown}",
                    "short": true
                },
                {
                    "title": "Service",
                    "value": "${SERVICE:-all}",
                    "short": true
                },
                {
                    "title": "Image Tag",
                    "value": "${TAG:-latest}",
                    "short": true
                },
                {
                    "title": "Timestamp",
                    "value": "$(date -u '+%Y-%m-%d %H:%M:%S UTC')",
                    "short": true
                }
            ],
            "footer": "TTPOS Deploy",
            "footer_icon": "https://platform.slack-edge.com/img/default_application_icon.png"
        }
    ]
}
EOF
)

    echo "$payload"
}

# Send notification
send_notification() {
    # Check for Slack webhook URL
    if [[ -z "$SLACK_WEBHOOK_URL" ]]; then
        echo -e "${YELLOW}Warning: SLACK_WEBHOOK_URL not set, skipping notification${NC}"
        return 0
    fi

    local payload=$(build_message)

    # Send to Slack
    local response=$(curl -sf -X POST \
        -H 'Content-type: application/json' \
        --data "$payload" \
        "$SLACK_WEBHOOK_URL" 2>&1)

    if [[ $? -eq 0 ]] && [[ "$response" == "ok" ]]; then
        echo -e "${GREEN}Notification sent to Slack${NC}"
        return 0
    else
        echo -e "${YELLOW}Warning: Failed to send Slack notification${NC}"
        echo "Response: $response"
        return 1
    fi
}

# Main function
main() {
    parse_args "$@"

    if [[ -z "$STATUS" ]]; then
        echo -e "${RED}Error: --status is required${NC}"
        usage
    fi

    echo -e "${BLUE}Sending notification...${NC}"
    echo "  Status: $STATUS"
    echo "  Service: ${SERVICE:-all}"
    echo "  Environment: ${ENV:-unknown}"
    echo "  Tag: ${TAG:-latest}"

    send_notification
}

main "$@"
