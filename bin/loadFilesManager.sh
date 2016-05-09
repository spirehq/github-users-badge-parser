#!/bin/bash

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SETTINGS=$1
CURRENT=0
MAX=21000000
STEP=1000

while [ $CURRENT -lt $MAX ]
do
    echo $CURRENT
    NEXT=$[CURRENT+STEP]
    `$DIR/loadFiles.coffee --settings $SETTINGS --from $CURRENT --to $NEXT >> loadFiles.out 2>&1`
    RESULT=$?
    while [ $RESULT -ne 0 ]
    do
        echo "Process exit with code $RESULT"
        `$DIR/loadFiles.coffee --settings $SETTINGS --from $CURRENT --to $NEXT >> loadFiles.out 2>&1`
        RESULT=$?
    done

    CURRENT=$NEXT
done