#!/bin/bash

if [ x$1 == x ]; then
   echo $0 program args ...
   echo this command will run inside autohck namespace
   echo RUN as admin!
   exit
fi

pid=`ps ax | grep 'ruby bin/auto_hck' | grep -v grep | head -n1 | awk '{print $1;}'`
if [ x$pid == x ]; then
    echo Ruby instance is not found
else
    echo Found ruby process $pid
    echo command to run: $*
    sudo nsenter -m -n -t $pid $*
fi
