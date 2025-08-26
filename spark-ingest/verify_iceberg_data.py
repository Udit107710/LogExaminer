#!/usr/bin/env python3
"""
Simple verification script to query the Iceberg table and verify data
"""
import os
from pyspark.sql import SparkSession
from pyspark.sql.functions import col, count

def main():
    # Create Spark session with Iceberg support
    spark = SparkSession.builder \
        .appName("VerifyIcebergData") \
        .config("spark.sql.extensions", "org.apache.iceberg.spark.extensions.IcebergSparkSessionExtensions") \
        .config("spark.sql.catalog.iceberg", "org.apache.iceberg.spark.SparkCatalog") \
        .config("spark.sql.catalog.iceberg.type", "hive") \
        .config("spark.sql.catalog.iceberg.uri", os.getenv('HIVE_METASTORE_URIS', 'thrift://localhost:9083')) \
        .config("spark.sql.catalog.iceberg.warehouse", "s3a://data-platform-iceberg-3e1b0c/warehouse/") \
        .config("spark.hadoop.fs.s3a.impl", "org.apache.hadoop.fs.s3a.S3AFileSystem") \
        .config("spark.hadoop.fs.s3a.aws.credentials.provider", "com.amazonaws.auth.WebIdentityTokenCredentialsProvider") \
        .getOrCreate()

    print("=== Iceberg Data Verification ===")
    
    try:
        # Show all databases
        print("\n1. Available databases:")
        spark.sql("SHOW DATABASES").show()
        
        # Show tables in analytics database
        print("\n2. Tables in analytics database:")
        spark.sql("SHOW TABLES IN analytics").show()
        
        # Describe the logs table
        print("\n3. Table schema for analytics.logs:")
        spark.sql("DESCRIBE analytics.logs").show()
        
        # Count total records
        print("\n4. Total record count:")
        record_count = spark.sql("SELECT COUNT(*) as total_records FROM analytics.logs").collect()[0]['total_records']
        print(f"Total records: {record_count}")
        
        # Show sample data
        print("\n5. Sample data (first 10 rows):")
        spark.sql("SELECT * FROM analytics.logs LIMIT 10").show(truncate=False)
        
        # Show data by level
        print("\n6. Data grouped by log level:")
        spark.sql("SELECT level, COUNT(*) as count FROM analytics.logs GROUP BY level ORDER BY count DESC").show()
        
        print("\n✅ Verification completed successfully!")
        
    except Exception as e:
        print(f"❌ Error during verification: {e}")
        raise
    finally:
        spark.stop()

if __name__ == "__main__":
    main()
