#!/usr/bin/env python3

import sys
from pyspark.sql import SparkSession

def main():
    # Initialize Spark session with Hive support
    spark = SparkSession.builder \
        .appName("ListDatabases") \
        .enableHiveSupport() \
        .getOrCreate()

    try:
        print("=== Checking Hive databases ===")
        
        # Show databases from Hive context
        databases = spark.sql("SHOW DATABASES")
        print("Available databases in Hive:")
        databases.show()
        
        # Try to create analytics database again if not exists
        print("\n=== Creating analytics database ===")
        spark.sql("CREATE DATABASE IF NOT EXISTS analytics LOCATION 's3a://data-platform-iceberg-3e1b0c/warehouse/analytics'")
        print("Analytics database creation attempted")
        
        # Show databases again
        print("\n=== After creation attempt ===")
        databases = spark.sql("SHOW DATABASES")
        databases.show()
        
        # Try using the analytics database
        print("\n=== Trying to use analytics database ===")
        spark.sql("USE analytics")
        print("Successfully switched to analytics database")
        
        # Show current database
        current_db = spark.sql("SELECT current_database()").collect()[0][0]
        print(f"Current database: {current_db}")
        
        # Show tables in analytics
        print("\n=== Tables in analytics database ===")
        tables = spark.sql("SHOW TABLES")
        tables.show()
        
    except Exception as e:
        print(f"Error: {str(e)}")
        import traceback
        traceback.print_exc()
    finally:
        spark.stop()

if __name__ == "__main__":
    main()
