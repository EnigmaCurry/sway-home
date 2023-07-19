#!/bin/bash
MAX_ATTEMPTS=10
ATTEMPTS=0

until ping -c1 1.1.1.1; do
    sleep 1;
    let "ATTEMPTS+=1"
    [[ ${ATTEMPTS} -gt ${MAX_ATTEMPTS} ]] && echo "No network connection" && exit 1
done

echo "Network ready"
[[ "$#" -gt 0 ]] && $@

