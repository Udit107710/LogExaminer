#!/usr/bin/env python3
"""
Create the analytics database and access_logs table in Iceberg format.
This should be run before the ingestion job.
"""

import sys
import argparse
import logging
from pyspark.sql import SparkSession
from pyspark.sql.types import StructType, StructField, StringType, IntegerType, TimestampType

# Configure logging
logging.basicConfig(level=logging.INFO, format='%(levelname)s:%(name)s:%(message)s')
logger = logging.getLogger(__name__)

def create_spark_session(warehouse_path, hms_uri):
    """Create Spark session with Iceberg configuration."""
    return SparkSession.builder \
        .appName("CreateSchema") \
        .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions") \
        .config("spark.sql.catalog.iceberg", "org.apache.iceberg.spark.SparkCatalog") \
        .config("spark.sql.catalog.iceberg.catalog-impl", "org.apache.iceberg.hive.HiveCatalog") \
        .config("spark.sql.catalog.iceberg.uri", hms_uri) \
        .config("spark.sql.catalog.iceberg.warehouse", warehouse_path) \
        .config("spark.serializer", "org.apache.spark.serializer.KryoSerializer") \
        .config("spark.sql.catalog.iceberg.lock-impl", "org.apache.iceberg.util.LockManagers$NullLockManager") \
        .getOrCreate()

def create_database_and_table(spark, db_name, table_name):
    """Create the analytics database and access_logs table."""
    try:
        # Create database if it doesn't exist
        logger.info(f"Creating database: {db_name}")
        spark.sql(f"CREATE DATABASE IF NOT EXISTS iceberg.{db_name}")
        
        # Define the table schema
        schema = StructType([
            StructField("timestamp", TimestampType(), True),
            StructField("remote_ip", StringType(), True),
            StructField("remote_user", StringType(), True),
            StructField("method", StringType(), True),
            StructField("url", StringType(), True),
            StructField("protocol", StringType(), True),
            StructField("status", IntegerType(), True),
            StructField("size", IntegerType(), True),
            StructField("referer", StringType(), True),
            StructField("user_agent", StringType(), True),
            StructField("year", IntegerType(), True),
            StructField("month", IntegerType(), True),
            StructField("day", IntegerType(), True),
            StructField("hour", IntegerType(), True),
        ])
        
        # Create the table
        logger.info(f"Creating table: {db_name}.{table_name}")
        spark.sql(f"DROP TABLE IF EXISTS iceberg.{db_name}.{table_name}")
        
        # Create empty DataFrame with schema
        empty_df = spark.createDataFrame([], schema)
        
        # Write as Iceberg table with partitioning
        empty_df.writeTo(f"iceberg.{db_name}.{table_name}") \
            .using("iceberg") \
            .partitionedBy("year", "month", "day") \
            .create()
        
        logger.info(f"Successfully created table: iceberg.{db_name}.{table_name}")
        
        # Verify table creation
        spark.sql(f"DESCRIBE TABLE iceberg.{db_name}.{table_name}").show()
        
        return True
        
    except Exception as e:
        logger.error(f"Error creating schema: {str(e)}")
        return False

def main():
    parser = argparse.ArgumentParser(description='Create Iceberg database and table schema')
    parser.add_argument('--warehouse', required=True, help='S3 warehouse path')
    parser.add_argument('--hms-uri', required=True, help='Hive Metastore URI')
    parser.add_argument('--db', default='analytics', help='Database name')
    parser.add_argument('--table', default='access_logs', help='Table name')
    
    args = parser.parse_args()
    
    logger.info("Starting schema creation job")
    logger.info(f"Warehouse: {args.warehouse}")
    logger.info(f"HMS URI: {args.hms_uri}")
    logger.info(f"Target: {args.db}.{args.table}")
    
    spark = create_spark_session(args.warehouse, args.hms_uri)
    
    try:
        success = create_database_and_table(spark, args.db, args.table)
        if success:
            logger.info("Schema creation completed successfully")
            sys.exit(0)
        else:
            logger.error("Schema creation failed")
            sys.exit(1)
            
    except Exception as e:
        logger.error(f"Job failed: {str(e)}")
        sys.exit(1)
        
    finally:
        spark.stop()

if __name__ == "__main__":
    main()
