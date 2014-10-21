#!/usr/bin/bash

RUBY="/usr/local/src/rbenv/shims/ruby"

LOG_LOCATION="/usr/local/src/chiffon-viewer/log"
#SKL2_USER_AHASIMOTO="/home/ACTIVEDIRECTORY/a_hasimoto/skl2/users/a_hasimoto"
LOGGER_DIR="/usr/local/src/logger"

## disintegrate the log to each session.
#DISINTEGRATOR="${RUBY} ${SKL2_USER_AHASIMOTO}/ChiffonCommunication/chiffon_log_extraction.rb"
DISINTEGRATOR="${RUBY} ${LOGGER_DIR}/chiffon_log_extraction.rb"
${DISINTEGRATOR} ${LOG_LOCATION}/development.log
${DISINTEGRATOR} ${LOG_LOCATION}/production.log

## send the logs to each user 
SENDER="${RUBY} ${LOGGER_DIR}/sendDailyLog.rb"
STORAGE_PRIOD="14"
CHIFFON_LOG_SENDER='tsurugi.chiffon_log@mm.media.kyoto-u.ac.jp'


AHASIMOTO='ahasimoto@mm.media.kyoto-u.ac.jp'
${SENDER} -s ${STORAGE_PRIOD} -t "${AHASIMOTO}" -f ${CHIFFON_LOG_SENDER} "${LOG_LOCATION}/development.log" "${LOG_LOCATION}/production.log" "${LOG_LOCATION}/guest*.log" "${LOG_LOCATION}/a_hasimoto*.log" -a

# delete all empty files of session log.
SWEEPER="${RUBY} ${LOGGER_DIR}/sweep_session_log.rb"
${SWEEPER} ${LOG_LOCATION}
