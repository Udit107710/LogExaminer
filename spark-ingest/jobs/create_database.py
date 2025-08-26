#!/usr/bin/env python3

import sys
from pyspark.sql import SparkSession

def main():
    # Initialize Spark session
    spark = SparkSession.builder \
        .appName("CreateAnalyticsDatabase") \
        .enableHiveSupport() \
        .getOrCreate()

    try:
        print("Creating analytics database...")
        
        # Create the analytics database
        create_db_sql = """
        CREATE DATABASE IF NOT EXISTS analytics
        LOCATION 's3a://data-platform-iceberg-3e1b0c/warehouse/analytics'
        """
        
        spark.sql(create_db_sql)
        print("Analytics database created successfully!")
        
        # Verify it was created
        databases = spark.sql("SHOW DATABASES")
        print("Available databases:")
        databases.show()
        
        # Check the database location
        spark.sql("USE analytics")
        print("Successfully switched to analytics database")
        
    except Exception as e:
        print(f"Error creating database: {str(e)}")
        raise e
    finally:
        spark.stop()

if __name__ == "__main__":
    main()
