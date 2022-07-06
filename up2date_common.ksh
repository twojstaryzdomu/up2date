TAR_OPTIONS='--delay-directory-restore --preserve --sort=inode'
MODEL_PREFIX=pi
SAME_FILE=0
SKIP_FILE=1
NEWER_IN_AR=2
NEWER_IN_FS=3
IGNORE_DIR=5

[ -e ${DSELF}/tar_common.conf ] \
  && . ${DSELF}/tar_common.conf

log(){
  echo "${@}"
}

# Throw an error
error(){
  rc=$?
  echo "${@}" 1>&2
  return $rc
}

# Debug output
debug(){
  [ -n "${DEBUG}" ] \
    && echo "${@}" 1>&2
  :
}

function debug_tee {
  typeset a
  while read a; do
    debug "${1}: ${a}"
    echo ${a}
  done
}

function list_tar {
  typeset f=${1}; shift
  LANG=C tar ${@:--tf} "${f}" 2>/dev/null \
    || error "unable to list ${f}"
}

list_tar_full(){
  list_tar "${1}" --quoting-style=c --full-time -tvf
}

_stat(){
  stat -c "${2}" "${1}"
}

get_mtime(){
  _stat "${1}" %Y
}

get_ownership(){
  _stat "${1}" %U:%G
}

get_absolute_path(){
  readlink -f "${@}"
}

debug_excl(){
  [ -n "${DEBUG_EXCL}" ] \
    && log "${@}"
}

function check_excluded {
  #typeset path="$(get_absolute_path "${1}")"
  typeset l m path
  realpath -s "${1}" \
  | read path
  debug_excl "check_excluded: path = $path"
  if [ -e "${EXCLUDELIST}" ]; then
    while read l; do
      m="${l}"
      debug_excl "check_excluded: attempting to match '${path}' on '${m}'"
      case "${path}" in
        ${m})
          debug "${path}: excluded due to matching exclusion: '${m}'"
          return ${SKIP_FILE}
        ;;
      esac
    done < "${EXCLUDELIST}"
    debug_excl "check_excluded: ${path} not matching ${m}"
    return 0
  else
    [ -z "$disclaimer" ] \
      && debug "exclude list missing, nothing will be excluded" \
        && disclaimer=y
    :
  fi
}

is_greater(){
  [ "${1}" -gt "${2}" ]
}

debug2(){
  is_greater "${DEBUG}" 1 \
    && echo "${@}" 1>&2
  :
}

is_equal(){
  [ "${1}" -eq "${2}" ]
}

exists(){
  [ -e "${1}" ] \
    || [ -h "${1}" ]
}

date_to_epoch(){
  date -d"${@}" +%s
}

function list_tar_epoch {
  typeset date file since_epoch time
  #LANG=C tar --quoting-style=shell-always --full-time -tvf ${@} | grep -Po "[0-9]{4}(-[0-9]{2}){2} [0-9]{2}(:[0-9]{2}){2}|(?<! -> )'[^']+'" | \
#sed -ne '1{h;b};/^[0-9]/!H;/^[0-9]/{x;:s;s/\n/ /;ts;p};${x;:s;s/\n/ /;ts;p}' | while read date time files; do
  list_tar_full ${@} \
  | grep -Po '[0-9]{4}(-[0-9]{2}){2} [0-9]{2}(:[0-9]{2}){2}(\.[0-9]+)? +"[^"]+"' \
  | while read date time file; do
    since_epoch=$(date_to_epoch "${date} ${time}") \
      || error "malformed date ${date} ${time}"
    echo ${since_epoch} $(eval echo ${file})
  done
}

function delete_nullified {
  typeset f list
  IFS= list=$(list_tar "${1}")
  echo $list \
  | while read f; do
    [ -h "/${f}" ] \
      && sudo find -L "/${f}" \( -samefile /dev/null ! -path '*/systemd/*' \) \
      | grep -q "/${f}" \
        && sudo rm -f /${f} \
          && debug "delete_nullified: deleted /${f}"
  done
}

extract(){
  sudo tar -C / --no-recursion --keep-newer-files -xzf "${1}" "${2}" 2>/dev/null \
    || error "failure while extracting ${2} from ${1}"
}

# Not in use
function exclude_nullified {
  typeset l
  while read l; do
    # Exclude all links pointing to /dev/null but ones with systemd in their pathname
    echo "${l}" \
    | grep -Po '[0-9]{4}(-[0-9]{2}){2} [0-9]{2}(:[0-9]{2}){2} ((\K".*systemd.*"(?= -> "/dev/null"))|"[^"]+"(?= -> "/dev/null")\K|\K"[^"]+"(?=( -> ".*"|$)))'
    is_equal $? 0 \
      || (debug "exclude_nullified: excluded " \
            && echo "${l}" \
            | grep -Po '[0-9]{4}(-[0-9]{2}){2} [0-9]{2}(:[0-9]{2}){2} \K"[^"]+"(?=( -> "/dev/null"|$))')
  done
}

strip_quotes(){
  sed -e 's#^"##g;s#"$##g'
}

function exclude_missing {
  typeset f
  while read f; do
    if exists "${f}"; then
      echo "${f}"
    else
      debug "exclude_missing: ${f}"
    fi
  done
}

function parse_null_in_fs {
  typeset f mtime_file mtime_tfile p tfile
  while read mtime_tfile tfile; do
    f="${tfile:+${TAR_ROOT:-/}${tfile}}"
    if [ -h "${f}" ] \
         && find -L "${f}" \( -samefile /dev/null ! -path '*/systemd/*' \) \
         | grep -q "${f}"; then
      realpath -s "${f}" \
      | read p
      check_excluded "${p}" \
        || continue
      mtime_file=$(get_mtime "${p}") \
        || error "Unable to get time of ${p}"
      if is_greater $mtime_file $mtime_tfile; then
        # Compress if filesystem /dev/null link more recent that in archive
        echo "${f}"
      else
        debug "parse_null_in_fs: ${f} not more recent (${mtime_file}) than its archived copy (${mtime_tfile}), excluding from compress"
      fi
    else
      # Pass through for all other files
      echo "${f}"
    fi
  done
}

get_os_release(){
  grep -Po '(?<=^VERSION_ID=|^VERSION_CODENAME=)"?\K[^"]*(?="?)|(?<=^PRETTY_NAME=).*\s\K[^\/]+(?=.*")' /etc/os-release \
  | tail -1
}

get_pi_model(){
  [ -f /proc/device-tree/model ] \
    && cut -f3 -d' ' /proc/device-tree/model \
    | sed -e 's|Zero|0|g'
}

function check_last_component {
  typeset c last_component model release
  get_os_release \
  | read release
  get_pi_model \
  | read model
  basename "${1}" .tar.gz \
  | read c
  last_component="${c##*_}"
  debug2 "check_last_component: model = ${model}; release = ${release}; last_component = ${last_component}"
  case "${last_component}" in
  "${release:-${TESTING_OS_CODENAME}}"|"${release:-testing}"|"${MODEL_PREFIX}${model:-none_specified}")
    debug2 "check_last_component: last component ${last_component} matching model ${MODEL_PREFIX}${model} or release ${release}, updating if requested"
    :
  ;;
  testing|buster|${OPENSUSE_RELEASE}|${TESTING_OS_CODENAME})
    log "${1}: ${last_component} branch tagged archive does not match os release ${release}, skipping archive"
    return ${SKIP_FILE}
  ;;
  ${MODEL_PREFIX}*)
    log "${1}: pi model ${last_component#${MODEL_PREFIX}} tagged archive does not match this hardware (model ${model}), skipping archive"
    return ${SKIP_FILE}
  ;;
  esac
}

compress(){
  list_tar_epoch "${1}" \
  | parse_null_in_fs \
  | exclude_missing \
  | debug_tee compress \
  | sudo tar -C / --no-recursion -czf "${1}" -T - 2>/dev/null \
    && sudo chown ${USER}:${GROUP} "${1}" \
      || error "failure while compressing ${1}, filelist: ${list}"
}

function update_tar {
  typeset mtime_file mtime_tar rc s tar tfile
  read rc tar mtime_tar mtime_file tfile <<< "${@}"
  debug2 "update_tar: ${rc:+rc=${rc}}; ${tar:+tar=${tar}}; ${mtime_tar:+mtime_tar=${mtime_tar}}; ${tfile:+tfile=${tfile}}; ${mtime_file:+mtime_file=${mtime_file}}"
  check_last_component "${tar}" \
    || return $?
  [ $rc -gt ${SAME_FILE} ] \
    && for s in ${NEWER_IN_AR} ${NEWER_IN_FS}; do
      is_equal $((${rc} % ${s})) 0 \
        && case ${s} in
        ${IGNORE_DIR})
          log "${tar}: ignoring directory ${tfile}"
          rc=${SAME_FILE}
        ;;
        ${NEWER_IN_FS})
          log "${tar}: more recent files in file system, compressing"
          compress $tar
          delete_nullified $tar
          rc=$?
        ;;
        ${NEWER_IN_AR})
          log "${tar}: contains newer files, extracting${tfile:+: ${tfile}}"
          extract $tar $tfile
          rc=$?
        ;;
        esac
      done
  return $rc
}

function print_mtimes_status {
  typeset err msg mtime_file mtime_tar mtime_tfile rc status tar tfile
  read rc tar mtime_tar mtime_file mtime_tfile tfile <<< "${@}"
  debug2 "print_mtimes_status: ${rc:+rc=${rc}}; ${tar:+tar=${tar}}; ${mtime_tar:+mtime_tar=${mtime_tar}}; ${tfile:+tfile=${tfile}}; ${mtime_file:+mtime_file=${mtime_file}}"
  msg="${tar}: ${msg}${tfile} "
  case $rc in
  ${IGNORE_DIR})
    msg="${msg}is a directory, ignoring as update trigger ($mtime_tfile $mtime_file)"
  ;;
  ${NEWER_IN_FS})
    status="more recent"
  ;;
  ${NEWER_IN_AR})
    status="older"
  ;;
  ${SKIP_FILE})
    msg="${msg}not present in the file system"
  ;;
  ${SAME_FILE})
    msg="${msg}same time ($mtime_tfile $mtime_file)"
  ;;
  esac
  err=${status:+${msg}(${mtime_file}) ${status} than archived file (${mtime_tfile})}
  [ -n "${err}" ] \
    && log "${err}" \
      || debug "${msg}"
}

function update_rc {
  typeset current previous rc
  read current previous <<< "${@}"
  if is_greater ${current} 0; then
    is_equal "$((${previous:-${SKIP_FILE}} % ${current}))" 0 \
      && rc=${previous} \
        || rc=$((${previous:-${SKIP_FILE}}*${current}))
  else
    rc=${previous}
  fi
  debug2 "update_rc: current=${current}; previous=${previous}; rc=${rc}"
  echo $rc
}

function compare_mtimes {
  typeset mode mtime_tar mtime_tfile rc tar tfile
  read mode tar mtime_tar mtime_tfile tfile <<< "${@}"
  debug2 "compare_mtimes: ${mode:+mode=${mode}}; ${tar:+tar=${tar}}; ${tfile:+tfile=${tfile}}; ${mtime_tfile:+mtime_tfile=${mtime_tfile}}"
  typeset mtime_file rc f
  f="${tfile:+${TAR_ROOT:-/}${tfile}}"
  if exists "${f}"; then
    realpath -s "${f}" \
    | read p
    check_excluded "${p}" \
      || continue
    mtime_file=$(get_mtime "${p}") \
      || error "Unable to get time of ${p}"
    #is_greater $mtime_file $mtime_tar && msg="${msg} ${p} (${mtime_file}) more recent than archive (${mtime_tar})" && rc=1 || msg="${msg} ${p} not more recent $mtime_file $mtime_tar"
    if is_equal $mtime_file $mtime_tfile; then
      rc=${SAME_FILE}
    else
      # Overlook when local directory is more recent, should not trigger an update
      if [ -d "${f}" ]; then
        rc=${IGNORE_DIR}
      else
        is_greater $mtime_file $mtime_tfile \
          && rc=${NEWER_IN_FS} \
            || rc=${NEWER_IN_AR}
      fi
    fi
  else
    rc=${SKIP_FILE}
  fi
  whence -q ${mode}_mtimes_status \
    && ${mode}_mtimes_status $rc "${tar}" "${mtime_tar}" "${mtime_file:-mtime_file=NOT_SET}" "${mtime_tfile:-mtime_tfile=NOT_SET}" "${f}"
  return $rc
}

function process_tar {
  typeset mode mtime_tar mtime_tfile rc tar tfile
  read mode tar <<< "${@}"
  if exists "${tar}"; then
    [ -n "${CHECK}" ] \
      || check_last_component "${tar}" \
        || return ${SKIP_FILE}
    mtime_tar=$(get_mtime "${tar}") \
      || error "Unable to get time of ${tar}"
    debug2 "process_tar: tar=${tar}; mtime_tar=${mtime_tar}"
    list_tar_epoch "${tar}" \
    | while read mtime_tfile tfile; do
      debug2 "list_tar_epoch: ${tfile:+tfile=${tfile}}; ${mtime_tfile:+mtime_tfile=${mtime_tfile}}; ${mtime_tar:+mtime_tar=${mtime_tar}}"
      compare_mtimes "${mode}" "${tar}" "${mtime_tar}" "${mtime_tfile}" "${tfile}"
      rc=$(update_rc $? $rc)
      debug2 "process_tar: rc=${rc}"
    done
  else
    error "${tar} does not exist" && return ${SKIP_FILE}
  fi
  rc=${rc:-${SAME_FILE}}
  debug2 "process_tar: rc=${rc}"
  whence -q ${mode}_tar \
    && (${mode}_tar $rc "${tar}" "${mtime_tar}" "${mtime_tfile}" "${tfile}"; rc=$?) \
      || debug2 "process_tar: no ${mode}_tar registered"
  return ${rc}
}

function process_args {
  typeset mode rc
  mode=${1}
  shift
  while [ $# -gt 0 ]; do
    debug2 "processing arg: ${1}"
    if [ -f "${1}" ]; then
      process_tar "${mode}" "${1}"
    else
      [ -d "${1}" ] \
        && process_args "${mode}" "${1}"/*
    fi
    rc=$?
    shift
  done
  debug2 "process_args: mode=${mode}; rc=${rc}"
  return $rc
}
