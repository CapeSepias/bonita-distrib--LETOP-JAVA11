#!/bin/bash
set -eo pipefail
# ensure to set the proper owner of data volume
if [ `stat -c %U /opt/bonita/` != 'bonita' ]
then
	chown -R bonita:bonita /opt/bonita/
fi
# ensure to apply the proper configuration
if [ ! -f /opt/${BONITA_VERSION}-configured ]
then
	gosu bonita /opt/files/config.sh \
      && touch /opt/${BONITA_VERSION}-configured || exit 1
fi
if [ -d /opt/custom-init.d/ ]
then
  echo "Custom scripts:"
  find /opt/custom-init.d -name '*.sh' | sort
	for f in $(find /opt/custom-init.d -name '*.sh' | sort)
	do
		[ -f "$f" ] && echo "Executing custom script $f" && . "$f"
	done
fi
# launch tomcat
export LOGGING_CONFIG="-Djava.util.logging.config.file=${BONITA_SERVER_LOGGING_FILE:-/opt/bonita/server/conf/logging.properties}"
exec gosu bonita /opt/bonita/server/bin/catalina.sh run
