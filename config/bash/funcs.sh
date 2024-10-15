stderr(){ echo "$@" >/dev/stderr; }
error(){ stderr "Error: $@"; }
fault(){ test -n "$1" && error $1; stderr "Exiting."; exit 1; }
cancel(){ stderr "Canceled."; exit 2; }
exe() { (set -x; "$@"); }
print_array(){ printf '%s\n' "$@"; }
trim_trailing_whitespace() { sed -e 's/[[:space:]]*$//'; }
trim_leading_whitespace() { sed -e 's/^[[:space:]]*//'; }
trim_whitespace() { trim_leading_whitespace | trim_trailing_whitespace; }
upper_case() { tr '[:lower:]' '[:upper:]'; }
lower_case() { tr '[:upper:]' '[:lower:]'; }
wizard() { ~/.cargo/bin/script-wizard "$@"; }
check_var(){
    local __missing=false
    local __vars="$@"
    for __var in ${__vars}; do
        if [[ -z "${!__var}" ]]; then
            error "${__var} variable is missing."
            __missing=true
        fi
    done
    if [[ ${__missing} == true ]]; then
        fault
    fi
}

check_num(){
    local var=$1
    check_var var
    if ! [[ ${!var} =~ ^[0-9]+$ ]] ; then
        fault "${var} is not a number: '${!var}'"
    fi
}

debug_var() {
    local var=$1
    check_var var
    stderr "## DEBUG: ${var}=${!var}"
}

debug_array() {
    local -n ary=$1
    echo "## DEBUG: Array '$1' contains:"
    for i in "${!ary[@]}"; do
        echo "## ${i} = ${ary[$i]}"
    done
}

ask() {
    ## Ask the user a question and set the given variable name with their answer
    local __prompt="${1}"; local __var="${2}"; local __default="${3}"
    read -e -p "${__prompt}"$'\x0a: ' -i "${__default}" ${__var}
    export ${__var}
}

ask_no_blank() {
    ## Ask the user a question and set the given variable name with their answer
    ## If the answer is blank, repeat the question.
    local __prompt="${1}"; local __var="${2}"; local __default="${3}"
    while true; do
        read -e -p "${__prompt}"$'\x0a: ' -i "${__default}" ${__var}
        export ${__var}
        [[ -z "${!__var}" ]] || break
    done
}

ask_echo() {
    ## Ask the user a question then print the non-blank answer to stdout
    (
        prompt=$1; shift
        ask_no_blank "$1" ASK_ECHO_VARNAME $@ >/dev/stderr
        echo "${ASK_ECHO_VARNAME}"
    )
}


require_input() {
    ## require_input {PROMPT} {VAR} {DEFAULT}
    ## Read variable, set default if blank, error if still blank
    test -z ${3} && dflt="" || dflt=" (${3})"
    read -e -p "$1$dflt: " $2
    eval $2=${!2:-${3}}
    test -v ${!2} && fault "$2 must not be blank."
}

make_var_name() {
    # Make an environment variable out of any string
    # Replaces all invalid characters with a single _
    echo "$@" | sed -e 's/  */_/g' -e 's/--*/_/g' -e 's/[^a-zA-Z0-9_]/_/g' -e 's/__*/_/g' -e 's/.*/\U&/' -e 's/__*$//' -e 's/^__*//'
}

color() {
    ## Print text in ANSI color
    set -e
    if [[ $# -lt 2 ]]; then
        fault "Not enough args: expected COLOR and TEXT arguments"
    fi
    local COLOR_CODE_PREFIX='\033['
    local COLOR_CODE_SUFFIX='m'
    local COLOR=$1; shift
    local TEXT="$*"
    local LIGHT=1
    check_var COLOR TEXT
    case "${COLOR}" in
        "black") COLOR=30; LIGHT=0;;
        "red") COLOR=31; LIGHT=0;;
        "green") COLOR=32; LIGHT=0;;
        "brown") COLOR=33; LIGHT=0;;
        "orange") COLOR=33; LIGHT=0;;
        "blue") COLOR=34; LIGHT=0;;
        "purple") COLOR=35; LIGHT=0;;
        "cyan") COLOR=36; LIGHT=0;;
        "light gray") COLOR=37; LIGHT=0;;
        "dark gray") COLOR=30; LIGHT=1;;
        "light red") COLOR=31; LIGHT=1;;
        "light green") COLOR=32; LIGHT=1;;
        "yellow") COLOR=33; LIGHT=1;;
        "light blue") COLOR=34; LIGHT=1;;
        "light purple") COLOR=35; LIGHT=1;;
        "light cyan") COLOR=36; LIGHT=1;;
        "white") COLOR=37; LIGHT=1;;
        *) fault "Unknown color"
    esac
    echo -en "${COLOR_CODE_PREFIX}${LIGHT};${COLOR}${COLOR_CODE_SUFFIX}${TEXT}${COLOR_CODE_PREFIX}0;0${COLOR_CODE_SUFFIX}"
}

colorize() {
    ## Highlight text patterns in stdin with ANSI color
    set -e
    if [[ $# -lt 2 ]]; then
        fault "Not enough args: expected COLOR and PATTERN arguments"
    fi
    local COLOR=$1; shift
    local PATTERN=$1; shift
    check_var COLOR PATTERN
    case "${COLOR}" in
        "black") COLOR=30;;
        "red") COLOR=31;;
        "green") COLOR=32;;
        "brown") COLOR=33;;
        "orange") COLOR=33;;
        "blue") COLOR=34;;
        "purple") COLOR=35;;
        "cyan") COLOR=36;;
        "white") COLOR=37;;
        *) fault "Unknown color"
    esac
    PATTERN='^.*'"${PATTERN}"'.*$|'
    readarray stdin
    echo "${stdin[@]}" | \
        GREP_COLORS="mt=01;${COLOR}" grep --color -E "${PATTERN}"
}

element_in_array () {
    # element_in_array "${profile}" "${ALL_PROFILES[@]}"
    local e match="$1"; shift;
    for e; do [[ "$e" == "$match" ]] && return 0; done
    return 1
}

gen_password() {
    set -eo pipefail
    LENGTH=${1:-30}
    openssl rand -base64 ${LENGTH} | tr '=' '0' | tr '+' '0' | tr '/' '0' | tr '\n' '0' | head -c ${LENGTH}
}

version_spec() {
    ## Check the lock file to see if the apps INSTALLED_VERSION is ok
    # version_spec APP_NAME INSTALLED_VERSION
    set -eo pipefail
    # The name of the app:
    local APP=$1;
    check_var APP
    # The installed version to check against the lock file version, could be blank:
    local CHECK_VERSION=$2;
    local VERSION_LOCK="${ROOT_DIR}/.tools.lock.json"
    if [[ ! -f "$VERSION_LOCK" ]]; then
        fault "The version lock spec file is missing: ${VERSION_LOCK}"
    fi
    # Grab the locked version of APP from the lock file:
    local LOCKED_VERSION=$(jq -r ".dependencies.\"${APP}\"" ${ROOT_DIR}/.tools.lock.json)
    (test -z "${LOCKED_VERSION}" || test "${LOCKED_VERSION}" == "null") && fault "The app '${APP}' is not listed in ${VERSION_LOCK}"

    # Return the locked version string:
    echo ${LOCKED_VERSION}

    # But error if the installed version is different than the locked version:
    if [[ -n "${CHECK_VERSION}" ]] && [[ "${VERSION}" != "${CHECK_VERSION}" ]]; then
        fault "Installed ${APP} version ${CHECK_VERSION} does not match the locked version: ${LOCKED_VERSION}"
    fi
}

text_centered() {
    local columns="$1"
    check_var columns
    shift
    local text="$@"
    check_var text
    printf "%*s\n" $(( (${#text} + columns) / 2)) "$text"
}

text_centered_full() {
    local columns="$(tput cols)"
    text_centered ${columns} "$@"
}

text_centered_wrap() {
    local wrap="$1"
    check_var wrap
    shift;
    local wrap_rev="${wrap}"
    wrap_rev=$(text_reverse "${wrap}")
    local columns="$1"
    check_var columns
    shift;
    local wrap_length=${#wrap}
    local text="$@"
    check_var text
    centered_text=$(text_centered "${columns}" "${text}")
    trailing_whitespace=$(text_repeat $((${#centered_text}-${#text})) " ")
    whitespace_offset=${wrap_length}
    new_text="${wrap}${centered_text:${#wrap}}${trailing_whitespace:${whitespace_offset}}${wrap}"
    if [[ $((wrap_length%2)) -eq 0 ]] && [[ $((${#new_text}%2)) -eq 1 ]]; then
        whitespace_offset=$((whitespace_offset-1))
    elif [[ $((wrap_length%2)) -eq 1 ]] && [[ $((${#new_text}%2)) -eq 1 ]]; then
        whitespace_offset=$((whitespace_offset-1))
    fi
    new_text="${wrap}${centered_text:${#wrap}}${trailing_whitespace:${whitespace_offset}}${wrap_rev}"
    echo "${new_text}"
}

text_repeat() {
    local repeat="$1";
    check_var repeat
    shift
    local text="$@"
    check_var text
    readarray -t repeated < <(yes "${text}" | head -n ${repeat})
    printf "%s" "${repeated[@]}"
    echo
}

text_reverse() {
    local text="$@"
    check_var text
    for((i=${#text}-1;i>=0;i--)); do rev="$rev${text:$i:1}"; done
    echo "${rev}"
}

text_mirror() {
    local text="$@"
    check_var text
    rev=$(text_reverse "${text}")
    echo "${text}${rev}"
}

text_line() {
    # Fill a line of the target width with a repeating pattern
    # If width is 0, fill the entire line.
    local width="$1";
    local pattern="$2";
    check_var width
    shift 2
    if [[ "${width}" == "0" ]]; then
        width="$(tput cols)"
    fi
    local pattern_length="${#pattern}"
    text_repeat $((width/pattern_length)) "${pattern}"
    if [[ "$#" -gt 0 ]]; then
        echo "$(text_centered "$*")"
        text_repeat $((width/pattern_length)) "${pattern}"
    fi
}

separator() {
    local pattern="$1"
    check_var pattern
    shift
    local width="$1"
    check_var width
    shift
    if [[ "${width}" == "0" ]]; then
        width="$(tput cols)"
    fi
    local text="$@"
    echo
    local sep=$(text_line ${width} "${pattern}")
    local index_half=$((${#sep}/2))
    sep="${sep:0:${index_half}}"
    sep=$(text_mirror "${sep}")
    local columns="${#sep}"
    echo "${sep}"
    if [[ -n "${text}" ]]; then
        text_centered_wrap "${pattern}" "${columns}" "${text}"
        echo "${sep}"
    fi
    echo
}


random_element() {
    local arr=("$@")
    if [[ "${#@}" -lt 1 ]]; then
        fault "Need more args"
    fi
    echo "${arr[ $RANDOM % ${#arr[@]} ]}"
}

confirm() {
    ## Confirm with the user.
    ## Check env for the var YES, if it equals "yes" then bypass this confirm.
    ## This version depends on `script-wizard` being installed.
    test ${YES:-no} == "yes" && exit 0

    local default=$1; local prompt=$2; local question=${3:-". Proceed?"}

    check_var default prompt question

    if [[ -f ${BIN}/script-wizard ]]; then
        ## Check if script-wizard is installed, and prefer to use that:
        local exit_code=0
        if [[ $default == "y" || $default == "true" ]]; then
            default="yes"
        elif [[ $default == "n" || $default == "false" ]]; then
            default="no"
        fi
        wizard confirm --cancel-code=2 "$prompt$question" "$default" && exit_code=$? || exit_code=$?
        if [[ "${exit_code}" == "2" ]]; then
            cancel
        fi
        return ${exit_code}
    else
        ## Otherwise use a pure bash version:
        if [[ $default == "y" || $default == "yes" || $default == "true" ]]; then
            dflt="Y/n"
        else
            dflt="y/N"
        fi

        read -e -p "${prompt}${question} (${dflt}): " answer
        answer=${answer:-${default}}

        if [[ ${answer,,} == "y" || ${answer,,} == "yes" || ${answer,,} == "true" ]]; then
            return 0
        else
            return 1
        fi
    fi
}

choose() {
    local exit_code=0
    wizard choose --cancel-code=2 "$@" && exit_code=$? || exit_code=$?
    if [[ "${exit_code}" == "2" ]]; then
        cancel
    fi
    return ${exit_code}
}

select_wizard() {
    local exit_code=0
    wizard select --cancel-code=2 "$@" && exit_code=$? || exit_code=$?
    if [[ "${exit_code}" == "2" ]]; then
        cancel
    fi
    return ${exit_code}
}

