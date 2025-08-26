# Hive Metastore 2.3.9 with MySQL and S3 support - Compatible with Spark 3.5.1
FROM openjdk:8-jdk-slim

# Set environment variables for Hive 2.3.9 (matching Spark 3.5.1 client version)
ENV HIVE_VERSION=2.3.9
ENV HADOOP_VERSION=3.2.4
ENV MYSQL_CONNECTOR_VERSION=8.0.28

# Install dependencies
RUN apt-get update && apt-get install -y \
    wget \
    curl \
    procps \
    netcat \
    bash \
    coreutils \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /bin/bash /usr/bin/bash

# Create hive user and directories
RUN groupadd -r hive && useradd -r -g hive hive
RUN mkdir -p /opt/hive /opt/hadoop /tmp/hive

# Download and install Hadoop (using version contemporary with Hive 2.3.9)
RUN wget -q https://archive.apache.org/dist/hadoop/common/hadoop-${HADOOP_VERSION}/hadoop-${HADOOP_VERSION}.tar.gz \
    && tar -xzf hadoop-${HADOOP_VERSION}.tar.gz -C /tmp/ \
    && mv /tmp/hadoop-${HADOOP_VERSION}/* /opt/hadoop/ \
    && rmdir /tmp/hadoop-${HADOOP_VERSION} \
    && rm hadoop-${HADOOP_VERSION}.tar.gz

# Download and install Hive 2.3.9 (matching Spark 3.5.1 client version)
RUN wget -q https://archive.apache.org/dist/hive/hive-${HIVE_VERSION}/apache-hive-${HIVE_VERSION}-bin.tar.gz \
    && tar -xzf apache-hive-${HIVE_VERSION}-bin.tar.gz -C /tmp/ \
    && mv /tmp/apache-hive-${HIVE_VERSION}-bin/* /opt/hive/ \
    && rmdir /tmp/apache-hive-${HIVE_VERSION}-bin \
    && rm apache-hive-${HIVE_VERSION}-bin.tar.gz \
    && find /opt/hive/bin -type f -exec sed -i '1s|^#!/usr/bin/env bash|#!/bin/bash|' {} \;

# Ensure lib directory exists and download MySQL JDBC driver
RUN mkdir -p /opt/hive/lib \
    && wget -q https://repo1.maven.org/maven2/mysql/mysql-connector-java/${MYSQL_CONNECTOR_VERSION}/mysql-connector-java-${MYSQL_CONNECTOR_VERSION}.jar \
    -O /opt/hive/lib/mysql-connector-java-${MYSQL_CONNECTOR_VERSION}.jar

# Download AWS S3 support JARs (compatible versions with Hadoop 3.2.4)
RUN wget -q https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/${HADOOP_VERSION}/hadoop-aws-${HADOOP_VERSION}.jar \
    -O /opt/hive/lib/hadoop-aws-${HADOOP_VERSION}.jar \
    && wget -q https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.11.1026/aws-java-sdk-bundle-1.11.1026.jar \
    -O /opt/hive/lib/aws-java-sdk-bundle-1.11.1026.jar

# Fix Guava and other version compatibility issues
# Remove all existing Guava versions and use a compatible one
RUN rm -f /opt/hive/lib/guava-*.jar \
    && rm -f /opt/hadoop/share/hadoop/common/lib/guava-*.jar \
    && wget -q https://repo1.maven.org/maven2/com/google/guava/guava/27.0-jre/guava-27.0-jre.jar \
       -O /opt/hive/lib/guava-27.0-jre.jar \
    && cp /opt/hive/lib/guava-27.0-jre.jar /opt/hadoop/share/hadoop/common/lib/

# Remove SLF4J conflicts
RUN rm -f /opt/hadoop/share/hadoop/common/lib/slf4j-*.jar

# Set environment variables
ENV JAVA_HOME=/usr/local/openjdk-8
ENV HADOOP_HOME=/opt/hadoop
ENV HIVE_HOME=/opt/hive
ENV PATH=$PATH:$HIVE_HOME/bin:$HADOOP_HOME/bin:$JAVA_HOME/bin

# Copy configuration files (if any)
COPY conf/ /opt/hive/conf/

# Copy schema initialization script
COPY init-schema.sh /usr/local/bin/init-schema.sh
RUN chmod +x /usr/local/bin/init-schema.sh

# Set ownership
RUN chown -R hive:hive /opt/hive /opt/hadoop /tmp/hive

# Create startup script
RUN echo '#!/bin/bash\n\
set -e\n\
\n\
# Wait for database to be ready if METASTORE_DB_HOSTNAME is set\n\
if [ -n "$METASTORE_DB_HOSTNAME" ]; then\n\
  echo "Waiting for database at $METASTORE_DB_HOSTNAME:${METASTORE_DB_PORT:-3306}..."\n\
  while ! nc -z "$METASTORE_DB_HOSTNAME" "${METASTORE_DB_PORT:-3306}"; do\n\
    sleep 1\n\
  done\n\
  echo "Database is ready!"\n\
fi\n\
\n\
# Initialize schema if needed\n\
if [ "$1" = "schematool" ]; then\n\
  exec "$@"\n\
elif [ "$1" = "/opt/hive/bin/hive" ] || [ "$1" = "start-metastore" ]; then\n\
  # In Hive 2.3.9, use hive --service metastore for starting\n\
  echo "Starting Hive Metastore service (version 2.3.9)..."\n\
  exec /opt/hive/bin/hive --service metastore\n\
else\n\
  exec "$@"\n\
fi' > /entrypoint.sh \
    && chmod +x /entrypoint.sh

# Switch to hive user
USER hive

# Expose metastore port
EXPOSE 9083

# Set working directory
WORKDIR /opt/hive

# Default command
ENTRYPOINT ["/entrypoint.sh"]
CMD ["start-metastore"]
