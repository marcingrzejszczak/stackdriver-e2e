#!/usr/bin/env bash

# requires:
# git, maven

set -e

# FUNCTIONS
function build_the_app() {
  mvn clean install
}

# Runs the `java -jar` for given application $1 jars $2 and env vars $3
function java_jar() {
    local APP_NAME=$1
    local APP_JAVA_PATH=$2
    local ENV_VARS=$3
    local EXPRESSION="${ENV_VARS} nohup ${JAVA_PATH_TO_BIN}java -jar $2 $APP_JAVA_PATH >${LOGS_DIR}/${APP_NAME}.log &"
    echo -e "\nTrying to run [$EXPRESSION]"
    eval ${EXPRESSION}
    pid=$!
    echo ${pid} > ${LOGS_DIR}/${APP_NAME}.pid
    echo -e "[${APP_NAME}] process pid is [${pid}]"
    echo -e "Env vars are [${ENV_VARS}]"
    echo -e "Logs are under [${LOGS_DIR}/${APP_NAME}.log]\n"
    return 0
}

function run_maven_exec() {
  local CLASS_NAME=$1
  local EXPRESSION="nohup ./mvnw exec:java -Dexec.mainClass=sleuth.webmvc.${CLASS_NAME} >${LOGS_DIR}/${CLASS_NAME}.log &"
  echo -e "\nTrying to run [$EXPRESSION]"
  eval ${EXPRESSION}
  pid=$!
  echo ${pid} > ${LOGS_DIR}/${CLASS_NAME}.pid
  echo -e "[${CLASS_NAME}] process pid is [${pid}]"
  echo -e "Env vars are [${ENV_VARS}]"
  echo -e "Logs are under [${LOGS_DIR}/${CLASS_NAME}.log]\n"
  return 0
}

# ${RETRIES} number of times will try to curl to /health endpoint to passed port $1 and host $2
function curl_health_endpoint() {
    local PORT=$1
    local PASSED_HOST="${2:-$HEALTH_HOST}"
    local READY_FOR_TESTS=1
    for i in $( seq 1 "${RETRIES}" ); do
        sleep "${WAIT_TIME}"
        curl -m 5 "${PASSED_HOST}:${PORT}/health" && READY_FOR_TESTS=0 && break
        echo "Fail #$i/${RETRIES}... will try again in [${WAIT_TIME}] seconds"
    done
    if [[ "${READY_FOR_TESTS}" == 1 ]] ; then
        echo "Failed to start the app..."
        kill_all
    fi
    return ${READY_FOR_TESTS}
}

# ${RETRIES} number of times will try to curl to /health endpoint to passed port $1 and localhost
function curl_local_health_endpoint() {
    curl_health_endpoint $1 "127.0.0.1"
}

function send_a_test_request() {
    curl -m 5 "127.0.0.1:8081" && curl -m 5 "127.0.0.1:8081" && echo -e "\n\nSuccessfully sent two test requests!!!"
}

# kills all apps
function kill_all() {
    ${ROOT}/scripts/kill.sh
}

# VARIABLES

STACKDRIVER_VERSION="v0.2.0"
JAVA_PATH_TO_BIN="${JAVA_HOME}/bin/"
if [[ -z "${JAVA_HOME}" ]] ; then
    JAVA_PATH_TO_BIN=""
fi
ROOT=`pwd`
LOGS_DIR="${ROOT}/target/"
HEALTH_HOST="127.0.0.1"
RETRIES=10
WAIT_TIME=5

mkdir -p target

cat <<'EOF'

This Bash file will try to see if a Boot app using Sleuth is able to properly communicate with stackdriver.
We will do the following steps to achieve this:

01) Clone stackdriver-zipkin repo (it's not yet available in central)
02) Build that jar with the version locally
03) Run the stackdriver collector
04) Wait for it to start (port 9411)
05) Run Sleuth client
06) Wait for it to start (port 8081)
07) Run Sleuth server
08) Wait for it to start (port 9000)
09) Hit the frontend twice (GET http://localhost:8081)
10) See the results in the collector

_______ _________ _______  _______ _________
(  ____ \\__   __/(  ___  )(  ____ )\__   __/
| (    \/   ) (   | (   ) || (    )|   ) (
| (_____    | |   | (___) || (____)|   | |
(_____  )   | |   |  ___  ||     __)   | |
      ) |   | |   | (   ) || (\ (      | |
/\____) |   | |   | )   ( || ) \ \__   | |
\_______)   )_(   |/     \||/   \__/   )_(
EOF
cd "${ROOT}/target"

if [[ ! -e "${ROOT}/target/stackdriver-zipkin/.git" ]]; then
  echo -e "\n\nCloning stackdriver zipkin\n\n"
  git clone https://github.com/GoogleCloudPlatform/stackdriver-zipkin
fi

cd "${ROOT}/target/stackdriver-zipkin"

echo -e "\n\nBuilding version [${STACKDRIVER_VERSION}]\n\n"
git checkout ${STACKDRIVER_VERSION}
mvn clean install -DskipTests

echo -e "\n\nRunning the collector\n\n"
java_jar "stackdriver-zipkin-collector" "./collector/target/collector*.jar" "GOOGLE_APPLICATION_CREDENTIALS=${ROOT}/credentials.json PROJECT_ID=zipkin-demo"
curl_local_health_endpoint 9411

echo -e "\n\nCloning the Sleuth Web MVC example"
cd "${ROOT}/target"
git clone https://github.com/openzipkin/sleuth-webmvc-example
cd "${ROOT}/target/sleuth-webmvc-example"
echo -e "\n\nRunning apps\n\n"
build_the_app
run_maven_exec "Frontend"
curl_local_health_endpoint 8081
run_maven_exec "Backend"
curl_local_health_endpoint 9000
send_a_test_request
