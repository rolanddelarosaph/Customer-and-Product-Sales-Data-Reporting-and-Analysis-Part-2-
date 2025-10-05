#  Customer and Product Sales – Data Reporting and Analysis

##  Project Overview

A sales analytics project that builds a retail data warehouse by integrating customer, product, and sales data. Using SQL Server, I designed structured tables, imported CSV datasets, and conducted analyses to uncover business insights related to revenue, customer behavior, and product performance.

---

##  Project Workflow

### Database Creation
- Created a new database named `DataWarehouseAnalytics`.
- Designed the `gold` schema to organize dimension and fact tables.

### Data Integration
- Loaded datasets (`dim_customers`, `dim_products`, `fact_sales`) from CSV files using `BULK INSERT`.
- Structured dimensions for customers and products, and fact tables for sales transactions.

### Data Exploration
- Explored database metadata and table structure.
- Examined unique attributes such as countries, categories, and product lines.

### Analytical Queries
- Calculated total sales, order counts, and average prices.
- Analyzed customer demographics, product categories, and revenue distribution.
- Identified top-performing and underperforming products and customers using window functions.

---

##  Key Insights Generated
- Total and average sales metrics by month, year, and product category.
- Customer distribution by country, age, gender, and loyalty segment.
- Top-selling products and highest-spending customers.
- Revenue trends by product category and customer segment.
- Sales timelines and cumulative growth patterns.

---

##  Tools & Technologies
- **Azure Data Studio** (SQL environment)  
- **Docker + Azure SQL Edge** (database engine)  
- **CSV datasets** as data sources  

---

##  Dataset Files
- `gold.dim_customers.csv`  
- `gold.dim_products.csv`  
- `gold.fact_sales.csv`  
