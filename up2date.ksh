#!/bin/ksh

SELF="$(basename "${0}")"
LSRC="$(readlink -e "$(which ${0})")"
LSELF="$(basename "${LSRC}")"
DSELF="$(dirname "${LSRC}")"

# If conf script exists, parse it
# overrrides any of the above variables
CONFFILE=${DSELF}/${LSELF%.ksh}.conf
[ -r ${CONFFILE} ] \
  && . ${CONFFILE}
[ -e ${DSELF}/${SELF%.*}_common.ksh ] \
  && . ${DSELF}/${SELF%.*}_common.ksh

[ $# -eq 0 ] \
  && error "${SELF} ARCHIVE | DIRECTORY_WITH_ARCHIVES" \
    && exit 1
process_args ${MODE:-print} "${@}"
