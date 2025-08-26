#!/bin/bash
set -e

# Force correct environment variables (override any incorrect ones from deployment)
export JAVA_HOME=/usr/local/openjdk-8
export HADOOP_HOME=/opt/hadoop
export HIVE_HOME=/opt/hive
export HADOOP_CONF_DIR=/opt/hive/conf
export HIVE_CONF_DIR=/opt/hive/conf
# Add Hadoop prefix as an alternative (some tools look for this)
export HADOOP_PREFIX=/opt/hadoop
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:$JAVA_HOME/bin:$HIVE_HOME/bin:$HADOOP_HOME/bin

echo "Environment:"
echo "  JAVA_HOME: $JAVA_HOME"
echo "  HADOOP_HOME: $HADOOP_HOME"
echo "  HIVE_HOME: $HIVE_HOME"
echo "  PATH: $PATH"

echo "Checking if schema exists..."
if /opt/hive/bin/schematool -dbType mysql -info; then
    echo "Schema already exists, skipping initialization"
    exit 0
else
    echo "Schema not found, initializing..."
    if /opt/hive/bin/schematool -dbType mysql -initSchema; then
        echo "Schema initialized successfully"
        exit 0
    else
        echo "Schema initialization failed"
        exit 1
    fi
fi
