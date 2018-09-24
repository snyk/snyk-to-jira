#!/bin/bash

## Prerequisites:
#
# 1. Add custom field for snyk-vuln-id in JIRA:
#  - Settings --> Issues --> Custom Fields --> Add Custom Field -->
#       Text Field Single Line
#       'snyk-vuln-id'
#       Select relevant project screens
#
# 2. Add custom field for snyk-path in JIRA:
#  - Settings --> Issues --> Custom Fields --> Add Custom Field -->
#       Text Field Single Line
#       'snyk-path'
#       Select relevant project screens
#
# 3. Create .jirac file in local directorty with four lines
# export JIRA_USER=<USER>
# export JIRA_PASSWORD=<PWD>
# export BASE_JIRA_URL=<URL>
# export JIRA_PROJECT_NAME=<PROJECT>

## Debug: DEBUG=1 to activate, DEBUG= to deactivate
DEBUG=
## Add comment: ADD_COMMENT=1 to add comment if open issue with same vuln already exists. ADD_COMMENT= to skip
ADD_COMMENT=

JIRA_SNYK_CUSTOM_FIELD_VULN_NAME=snyk-vuln-id
JIRA_SNYK_CUSTOM_FIELD_PATH_NAME=snyk-path


## .jirarc format:
# export JIRA_USER=<USER>
# export JIRA_PASSWORD=<PWD>
if [[ -r '.jirarc' ]]
then
  source '.jirarc'
else
  echo ".jirarc file not found"
  exit 1
fi

[[ -z "${JIRA_USER}" ]] || (echo JIRA_USER not specified && exit 1)
[[ -z "${JIRA_PASSWORD}" ]] || (echo JIRA_PASSWORD not specified && exit 1)
[[ -z "${BASE_JIRA_URL}" ]] || (echo BASE_JIRA_URL not specified && exit 1)
[[ "${JIRA_PROJECT_NAME}" ]] || (echo BASE_JIRA_URL not specified && exit 1)

function usage()
{
  echo "Usage: ${0} <snyk_test.json>"
  echo "snyk_test.json should be the output of running 'snyk test --json > snyk_test.json'"
}

function debug()
{
  local -r MSG="${1}"
  if ((DEBUG == 1)); then
    echo "${MSG}"
  fi
}

function uc_first()
{
  local UC_FIRST=$(echo -n "${1:0:1}" | tr '[:lower:]' '[:upper:]')${1:1}
  echo "${UC_FIRST}"
}

function urlencode()
{
    local length="${#1}"
    local i
    local c
    for (( i = 0; i < length; i++ )); do
        c="${1:i:1}"
        case "${c}" in
            [a-zA-Z0-9.~_-]) printf "%s" "${c}" ;;
            *) printf '%%%02X' "'$c" ;;
        esac
    done
}

function jira_curl()
{
  local API="${1}"
  local COMMAND=${2:-"GET"}
  local DATA_FILE="${3}"
  if [[ ${COMMAND} == "POST" ]]; then
    curl -s -S -u "${JIRA_USER}:${JIRA_PASSWORD}" -X "${COMMAND}" --data @"${DATA_FILE}" -H "Content-Type: application/json" "${BASE_JIRA_URL}/rest/api/2/${API}"
  else
    curl -s -S -u "${JIRA_USER}:${JIRA_PASSWORD}" -X "${COMMAND}" -H "Content-Type: application/json" "${BASE_JIRA_URL}/rest/api/2/${API}"
  fi
}

function jira_get_project_id()
{
  local PROJECT_NAME="${1}"
  local PROJECT_ID=$(jira_curl issue/createmeta | jq ".projects[] | select(.name==\"$PROJECT_NAME\") | .id" | tr -d '\"')
  local re='^[0-9]+$'
  if ! [[ $PROJECT_ID =~ $re  ]] ; then
   echo "Error: could not find project with name $PROJECT_NAME" >&2
   exit 1
  fi
  echo "${PROJECT_ID}"
}

function jira_get_custom_field_id()
{
  local CUSTOM_FIELD_NAME="${1}"
  local CUSTOM_FIELD_ID=$(jira_curl field | jq ".[] | select(.name==\"$CUSTOM_FIELD_NAME\") | .id" | tr -d '\"')
  local re='^customfield_[0-9]+$'
  if ! [[ $CUSTOM_FIELD_ID =~ $re  ]] ; then
   echo "Error: could not find field with name $CUSTOM_FIELD_NAME" >&2
   exit 1
  fi
  echo "${CUSTOM_FIELD_ID}"
}

function jira_create_issue()
{
  local PROJECT_ID="${1}"
  local SUMMARY="${2}"
  local SNYK_VULN_ID="${3}"
  local SNYK_PATH="${4}"
  local SEVERITY=$(uc_first "${5}")

  local SNYK_VULN_ID_ENC=$(urlencode "${SNYK_VULN_ID}")
  local SNYK_PATH_ENC=$(urlencode "$SNYK_PATH")

  local PAYLOAD_FILE=$(mktemp)

  local ISSUE_KEY=$(jira_curl "search?jql=project=$PROJECT_ID+AND+status!=Done+AND+$JIRA_SNYK_CUSTOM_FIELD_VULN_NAME~$SNYK_VULN_ID_ENC+AND+$JIRA_SNYK_CUSTOM_FIELD_PATH_NAME~\"$SNYK_PATH_ENC\"&maxResults=1&fields=id,key" | jq '.issues[0].key' | tr -d '"')

  local re='^[A-Za-z]{3}-[0-9]+$'
  if [[ $ISSUE_KEY =~ $re ]] ; then
    ## Issue with same vuln and path exists
    if [[ $ADD_COMMENT == 1 ]] ; then
      debug "Found exising issue with snyk-vuln-id=$SNYK_VULN_ID (id=$ISSUE_KEY) [$SNYK_PATH] --> Adding comment"
      cat > "${PAYLOAD_FILE}" <<EOM
{
    "body": "Vulnerability not resolved yet"
}
EOM
      jira_curl "issue/${ISSUE_KEY}/comment" POST "${PAYLOAD_FILE}" | grep -v "self"
    else
      debug "Found exising issue with snyk-vuln-id=${SNYK_VULN_ID} (id=${ISSUE_KEY}) [${SNYK_PATH}] --> Skipping"
    fi
  else
    ## New issue
    debug "Creating new issue for snyk-vuln-id=${SNYK_VULN_ID}: $SUMMARY"

    cat > "${PAYLOAD_FILE}" <<EOM
{
  "fields": {
    "project": {
      "id": "$PROJECT_ID"
    },
    "summary": "$SUMMARY",
    "priority": {
      "name": "$SEVERITY"
    },
    "issuetype": {
      "name": "Bug"
    },
    "description": "For more information please refer to https://snyk.io/vuln/$SNYK_VULN_ID",
    "$JIRA_SNYK_CUSTOM_FIELD_VULN_ID": "$SNYK_VULN_ID",
    "$JIRA_SNYK_CUSTOM_FIELD_PATH_ID": "$SNYK_PATH"
  }
}
EOM
    jira_curl issue POST "${PAYLOAD_FILE}"
    echo
  fi

}

####################
# START OF PROGRAM
####################
if ((${#} != 1)); then
  usage
  exit 1
fi

readonly JSON_FILE="${1}"
if [[ ! -r "${JSON_FILE}" ]]; then
  echo "Could not open ${JSON_FILE} for reading"
  exit 1
fi

readonly N_VULNS=$(jq '.vulnerabilities | length' < "${JSON_FILE}")

re='^[0-9]+$'
if ! [[ "${N_VULNS}" =~ ${re} ]]; then
  echo "${JSON_FILE} does not [${N_VULNS}] seem to be an output of 'snyk test --json'"
  exit 1
fi

if ((N_VULNS == 0)); then
  echo "Good for you! No vulns found."
  exit 0
fi

debug "Found ${N_VULNS} vulns"

debug "Connecting with user ${JIRA_USER}"
debug "Base JIRA URL: ${BASE_JIRA_URL}"

JIRA_PROJECT_ID=$(jira_get_project_id "${JIRA_PROJECT_NAME}")
debug "Found project id ${JIRA_PROJECT_ID} for ${JIRA_PROJECT_NAME}"

JIRA_SNYK_CUSTOM_FIELD_VULN_ID=$(jira_get_custom_field_id "${JIRA_SNYK_CUSTOM_FIELD_VULN_NAME}")
debug "Found custom field id ${JIRA_SNYK_CUSTOM_FIELD_VULN_ID} for ${JIRA_SNYK_CUSTOM_FIELD_VULN_NAME}"

JIRA_SNYK_CUSTOM_FIELD_PATH_ID=$(jira_get_custom_field_id "${JIRA_SNYK_CUSTOM_FIELD_PATH_NAME}")
debug "Found custom field id ${JIRA_SNYK_CUSTOM_FIELD_PATH_ID} for ${JIRA_SNYK_CUSTOM_FIELD_PATH_NAME}"


for ((i = 0; i < N_VULNS ; i++)); do
    TITLE=$(jq ".vulnerabilities[$i].title" < "${JSON_FILE}" | tr -d '"')
    SEVERITY=$(jq ".vulnerabilities[$i].severity" < "${JSON_FILE}" | tr -d '"')
    SNYK_VULN_ID=$(jq ".vulnerabilities[$i].alternativeIds[0]" < "${JSON_FILE}" | tr -d '"')
    MODULE=$(jq ".vulnerabilities[$i].moduleName" < "${JSON_FILE}" | tr -d '"')
    PACKAGE=$(jq ".vulnerabilities[$i].from[0] | split(\"@\") | .[0]" < "${JSON_FILE}" | tr -d '"')
    SNYK_PATH=$(jq ".vulnerabilities[$i].from | join(\" -> \")" < "${JSON_FILE}" | tr -d '"')
    SUMMARY="[SNYK] ${TITLE/\"/g}: $SEVERITY severity vulnerability found in '$MODULE' for $PACKAGE ($SNYK_VULN_ID)"

    jira_create_issue "${JIRA_PROJECT_ID}" "$SUMMARY" "$SNYK_VULN_ID" "$SNYK_PATH" "$SEVERITY"
done

exit 0