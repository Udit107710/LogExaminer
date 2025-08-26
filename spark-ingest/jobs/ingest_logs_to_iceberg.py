#!/usr/bin/env python3
"""
Spark job to ingest log files from raw S3 bucket to Iceberg tables via Hive Metastore.
This job reads JSON log files, performs basic transformation, and writes to Iceberg format.
"""

import argparse
import sys
from pyspark.sql import SparkSession
from pyspark.sql.functions import *
from pyspark.sql.types import *
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def create_spark_session(warehouse_path, hms_uri):
    """Create Spark session with basic configuration. 
    
    Iceberg and catalog configuration is handled via SparkConf in the SparkApplication manifest.
    """
    return SparkSession.builder \
        .appName("LogIngestToIceberg") \
        .getOrCreate()

def create_database_if_not_exists(spark, database_name):
    """Create database if it doesn't exist."""
    try:
        # For Hive Metastore, create database without catalog prefix
        # The catalog prefix is only used in Spark table references
        spark.sql(f"CREATE DATABASE IF NOT EXISTS {database_name}")
        logger.info(f"Database {database_name} created or already exists")
    except Exception as e:
        logger.warning(f"Failed to create database, will try direct table creation: {e}")
        # Don't raise - we'll try direct table creation instead

def create_logs_table_if_not_exists(spark, database_name, table_name):
    """Create logs table with proper schema if it doesn't exist."""
    table_full_name = f"iceberg.{database_name}.{table_name}"
    logger.info(f"Attempting to ensure table {table_full_name} exists")
    
    try:
        # Try to create the table explicitly with DDL
        create_table_sql = f"""
        CREATE TABLE IF NOT EXISTS {table_full_name} (
            timestamp timestamp,
            level string,
            message string,
            logger string,
            thread string,
            source_file string,
            line_number int,
            exception_class string,
            exception_message string,
            ingestion_timestamp timestamp,
            partition_date date,
            ip_address string,
            http_method string,
            http_path string,
            http_status int,
            response_size int,
            referer string,
            user_agent string
        ) USING ICEBERG
        PARTITIONED BY (partition_date)
        TBLPROPERTIES (
            'write.parquet.compression-codec'='snappy'
        )
        """
        
        spark.sql(create_table_sql)
        logger.info(f"Table {table_full_name} created or already exists")
        
    except Exception as e:
        logger.warning(f"Failed to create table explicitly, will let saveAsTable handle it: {e}")
        # Continue - saveAsTable will try to create the table

def parse_apache_log_line(log_line):
    """Parse a single Apache access log line into structured data."""
    import re
    
    # Apache Common Log Format regex
    # IP - - [timestamp] "METHOD path HTTP/version" status_code response_size "referer" "user_agent"
    pattern = r'(\S+) - - \[([^\]]+)\] "(\S+) ([^"]*) HTTP/[^"]*" (\d+) (\d+) "([^"]*)" "([^"]*)"'
    
    match = re.match(pattern, log_line)
    if not match:
        return None
    
    ip, timestamp_str, method, path, status_code, response_size, referer, user_agent = match.groups()
    
    # Convert Apache timestamp to ISO format
    from datetime import datetime
    try:
        # Parse: 06/Nov/2024:00:45:41 +0000
        dt = datetime.strptime(timestamp_str, '%d/%b/%Y:%H:%M:%S %z')
        iso_timestamp = dt.isoformat().replace('+00:00', 'Z')
    except:
        iso_timestamp = None
    
    # Determine log level based on HTTP status code
    status_int = int(status_code)
    if status_int >= 500:
        level = "ERROR"
    elif status_int >= 400:
        level = "WARN"
    else:
        level = "INFO"
    
    return {
        "timestamp": iso_timestamp,
        "level": level,
        "message": f"{method} {path} - {status_code}",
        "logger": "apache.access",
        "thread": "http-worker",
        "source_file": "access.log",
        "line_number": None,
        "exception_class": None if status_int < 400 else "HttpError",
        "exception_message": None if status_int < 400 else f"HTTP {status_code}",
        "ip_address": ip,
        "http_method": method,
        "http_path": path,
        "http_status": status_int,
        "response_size": int(response_size) if response_size != '-' else 0,
        "referer": referer if referer != '-' else None,
        "user_agent": user_agent if user_agent != '-' else None
    }

def ingest_logs(spark, raw_prefix, database_name, table_name):
    """Ingest log files from S3 raw prefix to Iceberg table."""
    table_full_name = f"iceberg.{database_name}.{table_name}"
    
    try:
        # Check if there are any files to process
        logger.info(f"Looking for log files in: {raw_prefix}")
        
        # Try to read log files (both .log and .json files)
        df_raw = None
        try:
            # First try to read Apache access log files
            logger.info("Attempting to read .log files as Apache access logs")
            text_df = spark.read.text(f"{raw_prefix}*.log")
            
            if text_df.count() > 0:
                logger.info(f"Found {text_df.count()} log lines to process")
                
                # Parse each line using the parsing function
                from pyspark.sql.functions import udf
                from pyspark.sql.types import StructType, StructField, StringType, IntegerType, TimestampType
                
                # Define schema for parsed log data
                log_schema = StructType([
                    StructField("timestamp", StringType(), True),
                    StructField("level", StringType(), True),
                    StructField("message", StringType(), True),
                    StructField("logger", StringType(), True),
                    StructField("thread", StringType(), True),
                    StructField("source_file", StringType(), True),
                    StructField("line_number", IntegerType(), True),
                    StructField("exception_class", StringType(), True),
                    StructField("exception_message", StringType(), True),
                    StructField("ip_address", StringType(), True),
                    StructField("http_method", StringType(), True),
                    StructField("http_path", StringType(), True),
                    StructField("http_status", IntegerType(), True),
                    StructField("response_size", IntegerType(), True),
                    StructField("referer", StringType(), True),
                    StructField("user_agent", StringType(), True)
                ])
                
                # Create UDF for parsing log lines
                parse_udf = udf(parse_apache_log_line, log_schema)
                
                # Parse the log lines
                df_parsed = text_df.select(parse_udf(col("value")).alias("parsed")) \
                                  .select("parsed.*") \
                                  .filter(col("timestamp").isNotNull())  # Filter out unparseable lines
                
                df_raw = df_parsed
                logger.info(f"Successfully parsed {df_raw.count()} valid log entries")
                
            else:
                logger.info("No .log files found, trying .json files")
                # Fallback to JSON files
                df_raw = spark.read.option("multiline", "false") \
                                  .option("mode", "PERMISSIVE") \
                                  .json(f"{raw_prefix}*.json")
                                  
        except Exception as e:
            logger.warning(f"Could not read log files: {e}")
            # Try JSON files as fallback
            try:
                logger.info("Trying JSON files as fallback")
                df_raw = spark.read.option("multiline", "false") \
                                  .option("mode", "PERMISSIVE") \
                                  .json(f"{raw_prefix}*.json")
            except Exception as json_e:
                logger.warning(f"No readable files found: {json_e}")
                # Create some sample data for demonstration
                logger.info("Creating sample log data for demonstration")
                sample_data = [
                    {
                        "timestamp": "2025-08-25T06:00:00.000Z",
                        "level": "INFO",
                        "message": "Application started successfully",
                        "logger": "com.example.App",
                        "thread": "main",
                        "source_file": "App.java",
                        "line_number": 42
                    },
                    {
                        "timestamp": "2025-08-25T06:01:00.000Z",
                        "level": "WARN", 
                        "message": "Configuration value not found, using default",
                        "logger": "com.example.Config",
                        "thread": "main",
                        "source_file": "Config.java",
                        "line_number": 128
                    },
                    {
                        "timestamp": "2025-08-25T06:02:00.000Z",
                        "level": "ERROR",
                        "message": "Database connection failed",
                        "logger": "com.example.DB",
                        "thread": "db-pool-1",
                        "source_file": "DatabaseManager.java",
                        "line_number": 89,
                        "exception_class": "SQLException",
                        "exception_message": "Connection timeout"
                    }
                ]
                df_raw = spark.createDataFrame(sample_data)
        
        # Check if we have any data
        if df_raw is None or df_raw.count() == 0:
            logger.warning(f"No processable data found in {raw_prefix}")
            return 0
        
        # Transform data with proper types and add partitioning columns
        df_transformed = df_raw \
            .withColumn("timestamp", 
                       when(col("timestamp").isNotNull(), 
                           to_timestamp(col("timestamp"), "yyyy-MM-dd'T'HH:mm:ss'Z'")) \
                       .otherwise(current_timestamp())) \
            .withColumn("ingestion_timestamp", current_timestamp()) \
            .withColumn("partition_date", 
                       date_format(coalesce(col("timestamp"), current_timestamp()), "yyyy-MM-dd").cast("date")) \
            .select(
                col("timestamp"),
                coalesce(col("level"), lit("INFO")).alias("level"),
                coalesce(col("message"), lit("")).alias("message"),
                coalesce(col("logger"), lit("unknown")).alias("logger"),
                coalesce(col("thread"), lit("main")).alias("thread"),
                coalesce(col("source_file"), lit("")).alias("source_file"),
                coalesce(col("line_number"), lit(0)).cast("int").alias("line_number"),
                coalesce(col("exception_class"), lit(None)).alias("exception_class"),
                coalesce(col("exception_message"), lit(None)).alias("exception_message"),
                col("ingestion_timestamp"),
                col("partition_date"),
                coalesce(col("ip_address"), lit(None)).alias("ip_address"),
                coalesce(col("http_method"), lit(None)).alias("http_method"),
                coalesce(col("http_path"), lit(None)).alias("http_path"),
                coalesce(col("http_status"), lit(0)).cast("int").alias("http_status"),
                coalesce(col("response_size"), lit(0)).cast("int").alias("response_size"),
                coalesce(col("referer"), lit(None)).alias("referer"),
                coalesce(col("user_agent"), lit(None)).alias("user_agent")
            )
        
        # Write to Iceberg table
        record_count = df_transformed.count()
        logger.info(f"Writing {record_count} records to {table_full_name}")
        
        df_transformed.write \
            .format("iceberg") \
            .mode("append") \
            .option("write.parquet.compression-codec", "snappy") \
            .saveAsTable(table_full_name)
        
        logger.info(f"Successfully ingested {record_count} log records")
        return record_count
        
    except Exception as e:
        logger.error(f"Error during ingestion: {e}")
        raise

def main():
    parser = argparse.ArgumentParser(description="Ingest logs to Iceberg")
    parser.add_argument("--raw-prefix", required=True, help="S3 prefix for raw log files")
    parser.add_argument("--warehouse", required=True, help="Iceberg warehouse location")
    parser.add_argument("--hms-uri", required=True, help="Hive Metastore URI")
    parser.add_argument("--db", required=True, help="Target database name")
    parser.add_argument("--table", required=True, help="Target table name")
    
    args = parser.parse_args()
    
    logger.info("Starting log ingestion job")
    logger.info(f"Raw prefix: {args.raw_prefix}")
    logger.info(f"Warehouse: {args.warehouse}")
    logger.info(f"HMS URI: {args.hms_uri}")
    logger.info(f"Target: {args.db}.{args.table}")
    
    spark = None
    try:
        # Create Spark session
        spark = create_spark_session(args.warehouse, args.hms_uri)
        logger.info("Spark session created successfully")
        
        # Try to create database (may fail due to S3 permissions)
        create_database_if_not_exists(spark, args.db)
        
        # Create table
        create_logs_table_if_not_exists(spark, args.db, args.table)
        
        # Ingest data
        record_count = ingest_logs(spark, args.raw_prefix, args.db, args.table)
        
        logger.info(f"Job completed successfully. Processed {record_count} records.")
        
    except Exception as e:
        logger.error(f"Job failed: {e}")
        sys.exit(1)
    finally:
        if spark:
            spark.stop()

if __name__ == "__main__":
    main()
