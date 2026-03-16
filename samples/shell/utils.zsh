#!/bin/zsh
# Sample zsh script with issues

# SC2154 - variable referenced but not assigned
echo $UNSET_VARIABLE

# SC2086 - unquoted variable
FILE_PATH=/some/path with spaces
cat $FILE_PATH

# SC2004 - $/${} is unnecessary on arithmetic variables
count=5
result=$(( $count + 1 ))

echo "Result: $result"
