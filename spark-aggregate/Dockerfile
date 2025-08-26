# Use Apache Spark 3.5.1 with Scala 2.12 as base image
FROM apache/spark:3.5.1-scala2.12-java11-python3-r-ubuntu

# Switch to root user to install packages
USER root

# Install additional dependencies if needed
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    && rm -rf /var/lib/apt/lists/*

# Create directories for jars and jobs
RUN mkdir -p /opt/jobs /opt/jobs/sql

# Download Iceberg Spark Runtime JAR (version 1.6.1 - stable version for Spark 3.5.1)
RUN wget -O /opt/spark/jars/iceberg-spark-runtime-3.5_2.12-1.6.1.jar \
    https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-spark-runtime-3.5_2.12/1.6.1/iceberg-spark-runtime-3.5_2.12-1.6.1.jar

# Download Hadoop AWS JAR for S3A support (compatible with Spark 3.5.1)
RUN wget -O /opt/spark/jars/hadoop-aws-3.3.4.jar \
    https://repo1.maven.org/maven2/org/apache/hadoop/hadoop-aws/3.3.4/hadoop-aws-3.3.4.jar

# Download AWS Java SDK Bundle (compatible version)
RUN wget -O /opt/spark/jars/aws-java-sdk-bundle-1.12.767.jar \
    https://repo1.maven.org/maven2/com/amazonaws/aws-java-sdk-bundle/1.12.767/aws-java-sdk-bundle-1.12.767.jar

# Download Iceberg AWS bundle for S3 FileIO support (matching Iceberg version)
RUN wget -O /opt/spark/jars/iceberg-aws-1.6.1.jar \
    https://repo1.maven.org/maven2/org/apache/iceberg/iceberg-aws/1.6.1/iceberg-aws-1.6.1.jar

# Download PostgreSQL JDBC driver for Hive Metastore connectivity
RUN wget -O /opt/spark/jars/postgresql-42.7.4.jar \
    https://repo1.maven.org/maven2/org/postgresql/postgresql/42.7.4/postgresql-42.7.4.jar

# Copy job files
COPY jobs/ /opt/jobs/

# Make job files executable
RUN chmod +x /opt/jobs/*.py

# Set working directory
WORKDIR /opt/spark

# Switch back to spark user
USER spark

# Set environment variables for Spark
ENV SPARK_HOME=/opt/spark
ENV PATH=$PATH:$SPARK_HOME/bin:$SPARK_HOME/sbin

# Default command (can be overridden)
CMD ["/bin/bash"]
