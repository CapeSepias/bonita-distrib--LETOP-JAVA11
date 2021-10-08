#!/bin/bash
set -eo pipefail

# Path to deploy the Tomcat Bundle
BONITA_PATH=/opt/bonita
# Templates directory
BONITA_TPL=/opt/templates
# Files directory
BONITA_FILES=/opt/files
# Flag to allow or not the SQL queries to automatically check and create the databases
ENSURE_DB_CHECK_AND_CREATION=${ENSURE_DB_CHECK_AND_CREATION:-true}
# Java OPTS
JAVA_OPTS=${JAVA_OPTS:--Xms1024m -Xmx1024m}
# Flag to enable or not dynamic authorization checking on Bonita REST API
REST_API_DYN_AUTH_CHECKS=${REST_API_DYN_AUTH_CHECKS:-true}

# retrieve the db parameters from the container linked
if [ -n "$POSTGRES_PORT_5432_TCP_PORT" ]
then
	DB_VENDOR='postgres'
	DB_HOST=$POSTGRES_PORT_5432_TCP_ADDR
	DB_PORT=$POSTGRES_PORT_5432_TCP_PORT
elif [ -n "$MYSQL_PORT_3306_TCP_PORT" ]
then
	DB_VENDOR='mysql'
	DB_HOST=$MYSQL_PORT_3306_TCP_ADDR
	DB_PORT=$MYSQL_PORT_3306_TCP_PORT
else
	DB_VENDOR=${DB_VENDOR:-h2}
fi

case $DB_VENDOR in
	"h2")
		DB_HOST=${DB_HOST:-localhost}
		DB_PORT=${DB_PORT:-9091}
		;;
	"postgres")
		DB_PORT=${DB_PORT:-5432}
		;;
	"mysql")
		DB_PORT=${DB_PORT:-3306}
		;;
	*)
		;;
esac
# BIZ_DB_VENDOR is currently set to the same value than DB_VENDOR
BIZ_DB_VENDOR=$DB_VENDOR

# if not enforced, set the default values to configure the databases
DB_NAME=${DB_NAME:-bonitadb}
DB_USER=${DB_USER:-bonitauser}
DB_PASS=${DB_PASS:-bonitapass}
DB_DROP_EXISTING=${DB_DROP_EXISTING:-N}
BIZ_DB_NAME=${BIZ_DB_NAME:-businessdb}
BIZ_DB_USER=${BIZ_DB_USER:-businessuser}
BIZ_DB_PASS=${BIZ_DB_PASS:-businesspass}
BIZ_DB_DROP_EXISTING=${BIZ_DB_DROP_EXISTING:-N}

# if not enforced, set the default credentials
PLATFORM_LOGIN=${PLATFORM_LOGIN:-platformAdmin}
PLATFORM_PASSWORD=${PLATFORM_PASSWORD:-platform}
TENANT_LOGIN=${TENANT_LOGIN:-install}
TENANT_PASSWORD=${TENANT_PASSWORD:-install}

# apply conf
# copy templates
cp ${BONITA_TPL}/setenv.sh ${BONITA_PATH}/setup/tomcat-templates/setenv.sh
cp ${BONITA_TPL}/database.properties ${BONITA_PATH}/setup/database.properties

# if required, uncomment dynamic checks on REST API
if [ "$REST_API_DYN_AUTH_CHECKS" = 'true' ]
then
    sed -i -e 's/^#GET|/GET|/' -e 's/^#POST|/POST|/' -e 's/^#PUT|/PUT|/' -e 's/^#DELETE|/DELETE|/' ${BONITA_PATH}/setup/platform_conf/initial/tenant_template_portal/dynamic-permissions-checks-custom.properties
fi

# replace variables
find ${BONITA_PATH}/setup/platform_conf/initial -name "*.properties" | xargs -n10 sed -i \
    -e 's/^#userName\s*=.*/'"userName=${TENANT_LOGIN}"'/' \
    -e 's/^#userPassword\s*=.*/'"userPassword=${TENANT_PASSWORD}"'/' \
    -e 's/^platform.tenant.default.username\s*=.*/'"platform.tenant.default.username=${TENANT_LOGIN}"'/' \
    -e 's/^platform.tenant.default.password\s*=.*/'"platform.tenant.default.password=${TENANT_PASSWORD}"'/' \
    -e 's/^#platformAdminUsername\s*=.*/'"platformAdminUsername=${PLATFORM_LOGIN}"'/' \
    -e 's/^#platformAdminPassword\s*=.*/'"platformAdminPassword=${PLATFORM_PASSWORD}"'/'

echo "Using JAVA_OPTS: ${JAVA_OPTS}"
sed -i -e 's/{{JAVA_OPTS}}/'"${JAVA_OPTS}"'/' ${BONITA_PATH}/setup/tomcat-templates/setenv.sh

if [ -n "$JDBC_DRIVER" ]
then
    # if $JDBC_DRIVER is set and the driver is not present, copy the JDBC driver into the Bundle
    file=$(basename $JDBC_DRIVER)
    if [ ! -e ${BONITA_PATH}/setup/lib/$file ]
    then
        cp ${BONITA_FILES}/${JDBC_DRIVER} ${BONITA_PATH}/setup/lib/
    fi
fi

echo "Using DB_VENDOR: ${DB_VENDOR}"
echo "Using DB_NAME: ${DB_NAME}"
echo "Using DB_HOST: ${DB_HOST}"
echo "Using DB_PORT: ${DB_PORT}"
echo "Using BIZ_DB_NAME: ${BIZ_DB_NAME}"

sed -e 's/{{DB_VENDOR}}/'"${DB_VENDOR}"'/' \
    -e 's/{{DB_USER}}/'"${DB_USER}"'/' \
    -e 's/{{DB_PASS}}/'"${DB_PASS}"'/' \
    -e 's/{{DB_NAME}}/'"${DB_NAME}"'/' \
    -e 's/{{DB_HOST}}/'"${DB_HOST}"'/' \
    -e 's/{{DB_PORT}}/'"${DB_PORT}"'/' \
    -e 's/{{BIZ_DB_USER}}/'"${BIZ_DB_USER}"'/' \
    -e 's/{{BIZ_DB_PASS}}/'"${BIZ_DB_PASS}"'/' \
    -e 's/{{BIZ_DB_NAME}}/'"${BIZ_DB_NAME}"'/' \
    -i ${BONITA_PATH}/setup/database.properties

# apply logging configuration
LOGGING_FILE=${BONITA_PATH}/server/conf/logging.properties
mv ${LOGGING_FILE} ${LOGGING_FILE}.original
awk -f ${BONITA_FILES}/logging.awk ${LOGGING_FILE}.original > ${LOGGING_FILE}

# use the setup tool to initialize and configure Bonita Tomcat bundle

# platform setup tool logging configuration file
BONITA_SETUP_LOGGING_FILE=${BONITA_SETUP_LOGGING_FILE:-/opt/bonita/setup/logback.xml}
./opt/bonita/setup/setup.sh init -Dh2.noconfirm -Dlogging.config=${BONITA_SETUP_LOGGING_FILE}
./opt/bonita/setup/setup.sh configure -Dlogging.config=${BONITA_SETUP_LOGGING_FILE}
