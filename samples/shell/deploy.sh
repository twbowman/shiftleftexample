#!/bin/bash
# Sample shell script with intentional shellcheck issues

# SC2034 - unused variable
UNUSED_VAR="hello"

# SC2086 - double quote to prevent globbing and word splitting
APP_DIR=/opt/myapp
echo "Deploying to $APP_DIR"
ls $APP_DIR

# SC2046 - quote to prevent word splitting
export PATH=$(dirname $0):$PATH

# SC2006 - use $(...) instead of backticks
CURRENT_DATE=`date +%Y-%m-%d`

# SC2035 - use ./*.log so names with dashes won't be treated as options
cd /var/log
rm *.log.old

# SC2162 - read without -r will mangle backslashes
echo "Enter server name:"
read SERVER_NAME

# SC2181 - check exit code directly
grep -q "error" /var/log/syslog
if [ $? -ne 0 ]; then
    echo "No errors found"
fi

# SC2129 - consider using { } to group commands
echo "Deploy started" >> /var/log/deploy.log
echo "Date: $CURRENT_DATE" >> /var/log/deploy.log
echo "Server: $SERVER_NAME" >> /var/log/deploy.log

# SC2091 - remove surrounding $() to avoid executing output
$(echo "hello world")

# Clean function for comparison
cleanup() {
    local log_dir="$1"
    if [[ -d "$log_dir" ]]; then
        find "$log_dir" -name "*.log" -mtime +30 -delete
        echo "Cleanup complete"
    fi
}

cleanup "/var/log/myapp"
