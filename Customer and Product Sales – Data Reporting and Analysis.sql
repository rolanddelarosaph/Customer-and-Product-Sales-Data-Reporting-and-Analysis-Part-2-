USE master;
GO

IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'DataWarehouseAnalytics')
BEGIN
    ALTER DATABASE DataWarehouseAnalytics SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE DataWarehouseAnalytics;
END;
GO

CREATE DATABASE DataWarehouseAnalytics;
GO

USE DataWarehouseAnalytics;
GO

CREATE SCHEMA gold;
GO

CREATE TABLE gold.dim_customers(
    customer_key int,
    customer_id int,
    customer_number nvarchar(50),
    first_name nvarchar(50),
    last_name nvarchar(50),
    country nvarchar(50),
    marital_status nvarchar(50),
    gender nvarchar(50),
    birthdate date,
    create_date date
);
GO

CREATE TABLE gold.dim_products(
    product_key int,
    product_id int,
    product_number nvarchar(50),
    product_name nvarchar(50),
    category_id nvarchar(50),
    category nvarchar(50),
    subcategory nvarchar(50),
    maintenance nvarchar(50),
    cost int,
    product_line nvarchar(50),
    start_date date 
);
GO

CREATE TABLE gold.fact_sales(
    order_number nvarchar(50),
    product_key int,
    customer_key int,
    order_date date,
    shipping_date date,
    due_date date,
    sales_amount int,
    quantity tinyint,
    price int 
);
GO

TRUNCATE TABLE gold.dim_customers;
GO

BULK INSERT gold.dim_customers
FROM '/var/opt/mssql/data/gold.dim_customers.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    TABLOCK
);
GO

TRUNCATE TABLE gold.dim_products;
GO

BULK INSERT gold.dim_products
FROM '/var/opt/mssql/data/gold.dim_products.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    TABLOCK
);
GO

TRUNCATE TABLE gold.fact_sales;
GO

BULK INSERT gold.fact_sales
FROM '/var/opt/mssql/data/gold.fact_sales.csv'
WITH (
    FIRSTROW = 2,
    FIELDTERMINATOR = ',',
    TABLOCK
);
GO

/*
===============================================================================
Change Over Time Analysis
===============================================================================
- Here, I'm analyzing how sales metrics like revenue, customer count, and quantity evolve month-to-month and year-to-year.
- The goal is to spot trends, seasonal effects, and periods of growth or decline, which inform business strategy and forecasting.
===============================================================================
*/

-- Sales performance grouped by year and month
SELECT
    YEAR(order_date) AS order_year,
    MONTH(order_date) AS order_month,
    SUM(sales_amount) AS total_sales,
    COUNT(DISTINCT customer_key) AS total_customers,
    SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY YEAR(order_date), MONTH(order_date)
ORDER BY YEAR(order_date), MONTH(order_date);

-- Sales aggregated by the first date of each month
SELECT
    DATEADD(MONTH, DATEDIFF(MONTH, 0, order_date), 0) AS order_month_start,
    SUM(sales_amount) AS total_sales,
    COUNT(DISTINCT customer_key) AS total_customers,
    SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATEADD(MONTH, DATEDIFF(MONTH, 0, order_date), 0)
ORDER BY DATEADD(MONTH, DATEDIFF(MONTH, 0, order_date), 0);

-- Time series labels using year and short month name (SQL Server safe, no FORMAT)
SELECT
    CAST(YEAR(order_date) AS VARCHAR(4)) + '-' + LEFT(DATENAME(MONTH, order_date), 3) AS order_period,
    SUM(sales_amount) AS total_sales,
    COUNT(DISTINCT customer_key) AS total_customers,
    SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY YEAR(order_date), MONTH(order_date), DATENAME(MONTH, order_date)
ORDER BY YEAR(order_date), MONTH(order_date);



/*
===============================================================================
Cumulative Analysis
===============================================================================
- In this section, I'm calculating running totals and moving averages for sales, grouped by year.
- This helps me spot cumulative growth trends as well as smooth out short-term fluctuations for better performance visualization.
===============================================================================
*/

-- Running total and moving average of sales by year
SELECT
    order_year,
    total_sales,
    SUM(total_sales) OVER (ORDER BY order_year) AS running_total_sales,
    AVG(avg_price) OVER (ORDER BY order_year) AS moving_average_price
FROM (
    SELECT 
        YEAR(order_date) AS order_year,
        SUM(sales_amount) AS total_sales,
        AVG(price) AS avg_price
    FROM gold.fact_sales
    WHERE order_date IS NOT NULL
    GROUP BY YEAR(order_date)
) t;




/*
===============================================================================
Performance Analysis (Year-over-Year, Month-over-Month)
===============================================================================
- Here, I'm benchmarking product sales by year, comparing each year's result to the product's historical average and previous year's value.
- This lets me identify products that are improving, declining, or performing above/below their average.
- It's a powerful way to track product lifecycles and spot top/bottom performers.
===============================================================================
*/

;WITH yearly_product_sales AS (
    SELECT
        YEAR(f.order_date) AS order_year,
        p.product_name,
        SUM(f.sales_amount) AS current_sales
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products p
        ON f.product_key = p.product_key
    WHERE f.order_date IS NOT NULL
    GROUP BY YEAR(f.order_date), p.product_name
)
SELECT
    order_year,
    product_name,
    current_sales,
    AVG(current_sales) OVER (PARTITION BY product_name) AS avg_sales,
    current_sales - AVG(current_sales) OVER (PARTITION BY product_name) AS diff_avg,
    -- Shows if sales are above/below historical average for each product
    CASE 
        WHEN current_sales - AVG(current_sales) OVER (PARTITION BY product_name) > 0 THEN 'Above Avg'
        WHEN current_sales - AVG(current_sales) OVER (PARTITION BY product_name) < 0 THEN 'Below Avg'
        ELSE 'Avg'
    END AS avg_change,
    -- Year-over-year analysis for growth/decline tracking
    LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) AS py_sales,
    current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) AS diff_py,
    CASE 
        WHEN current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) > 0 THEN 'Increase'
        WHEN current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) < 0 THEN 'Decrease'
        ELSE 'No Change'
    END AS py_change
FROM yearly_product_sales
ORDER BY product_name, order_year;




/*
===============================================================================
Data Segmentation Analysis
===============================================================================
- In this section, I'm grouping products by cost ranges and customers by spending history and loyalty.
- Product segmentation reveals pricing strategy impacts, while customer segmentation helps me design targeted marketing and retention activities.
- These segments make my analytics more actionable and focused.
===============================================================================
*/

;WITH product_segments AS (
    SELECT
        product_key,
        product_name,
        cost,
        CASE 
            WHEN cost < 100 THEN 'Below 100'
            WHEN cost BETWEEN 100 AND 500 THEN '100-500'
            WHEN cost BETWEEN 500 AND 1000 THEN '500-1000'
            ELSE 'Above 1000'
        END AS cost_range
    FROM gold.dim_products
)
SELECT 
    cost_range,
    COUNT(product_key) AS total_products
FROM product_segments
GROUP BY cost_range
ORDER BY total_products DESC;

;WITH customer_spending AS (
    SELECT
        c.customer_key,
        SUM(f.sales_amount) AS total_spending,
        MIN(order_date) AS first_order,
        MAX(order_date) AS last_order,
        DATEDIFF(month, MIN(order_date), MAX(order_date)) AS lifespan
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_customers c
        ON f.customer_key = c.customer_key
    GROUP BY c.customer_key
)
SELECT 
    customer_segment,
    COUNT(customer_key) AS total_customers
FROM (
    SELECT 
        customer_key,
        CASE 
            WHEN lifespan >= 12 AND total_spending > 5000 THEN 'VIP'
            WHEN lifespan >= 12 AND total_spending <= 5000 THEN 'Regular'
            ELSE 'New'
        END AS customer_segment
    FROM customer_spending
) AS segmented_customers
GROUP BY customer_segment
ORDER BY total_customers DESC;




/*
===============================================================================
Part-to-Whole Analysis
===============================================================================
- This part compares every product category's sales to the total sales, showing which categories are driving the business.
- It helps me prioritize investment, marketing, and identify underperforming categories for review.
===============================================================================
*/

;WITH category_sales AS (
    SELECT
        p.category,
        SUM(f.sales_amount) AS total_sales
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products p
        ON p.product_key = f.product_key
    GROUP BY p.category
)
SELECT
    category,
    total_sales,
    SUM(total_sales) OVER () AS overall_sales,
    ROUND((CAST(total_sales AS FLOAT) / SUM(total_sales) OVER ()) * 100, 2) AS percentage_of_total
FROM category_sales
ORDER BY total_sales DESC;




/*
===============================================================================
Customer Report
===============================================================================
- This section creates a summary report of customer activity and demographics for my analytics project.
- It pulls together key fields, aggregates each customer's total orders, sales, quantity, and product diversity.
- Customers are segmented by age group and loyalty (VIP, Regular, New), and KPIs like recency, average order value, and monthly spend are calculated.
- This report helps me analyze engagement patterns, identify valuable customers, and understand retention.
===============================================================================
*/

-- Drop the view if it exists; ensures the latest version is created
IF OBJECT_ID('gold.report_customers', 'V') IS NOT NULL
    DROP VIEW gold.report_customers;
GO

CREATE VIEW gold.report_customers AS
WITH base_query AS (
    SELECT
        f.order_number,
        f.product_key,
        f.order_date,
        f.sales_amount,
        f.quantity,
        c.customer_key,
        c.customer_number,
        CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
        DATEDIFF(year, c.birthdate, GETDATE()) AS age
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_customers c
        ON c.customer_key = f.customer_key
    WHERE order_date IS NOT NULL
),
customer_aggregation AS (
    SELECT 
        customer_key,
        customer_number,
        customer_name,
        age,
        COUNT(DISTINCT order_number) AS total_orders,
        SUM(sales_amount) AS total_sales,
        SUM(quantity) AS total_quantity,
        COUNT(DISTINCT product_key) AS total_products,
        MAX(order_date) AS last_order_date,
        DATEDIFF(month, MIN(order_date), MAX(order_date)) AS lifespan
    FROM base_query
    GROUP BY 
        customer_key,
        customer_number,
        customer_name,
        age
)
SELECT
    customer_key,
    customer_number,
    customer_name,
    age,
    CASE 
        WHEN age < 20 THEN 'Under 20'
        WHEN age BETWEEN 20 AND 29 THEN '20-29'
        WHEN age BETWEEN 30 AND 39 THEN '30-39'
        WHEN age BETWEEN 40 AND 49 THEN '40-49'
        ELSE '50 and above'
    END AS age_group,
    CASE 
        WHEN lifespan >= 12 AND total_sales > 5000 THEN 'VIP'
        WHEN lifespan >= 12 AND total_sales <= 5000 THEN 'Regular'
        ELSE 'New'
    END AS customer_segment,
    last_order_date,
    DATEDIFF(month, last_order_date, GETDATE()) AS recency,
    total_orders,
    total_sales,
    total_quantity,
    total_products,
    lifespan,
    -- Compute average order value (AOV)
    CASE WHEN total_orders = 0 THEN 0 ELSE total_sales / total_orders END AS avg_order_value,
    -- Compute average monthly spend
    CASE WHEN lifespan = 0 THEN total_sales ELSE total_sales / lifespan END AS avg_monthly_spend
FROM customer_aggregation;
GO

/*
===============================================================================
Product Report
===============================================================================
- Here, I'm creating a product report to summarize performance metrics for each item in my catalog.
- I track orders, sales, quantity, customer base, recency, and segment products by their sales performance.
- This lets me spot bestsellers, underperformers, and monitor how products evolve over time.
===============================================================================
*/

;IF OBJECT_ID('gold.report_products', 'V') IS NOT NULL
    DROP VIEW gold.report_products;
GO

CREATE VIEW gold.report_products AS
WITH base_query AS (
    SELECT
        f.order_number,
        f.order_date,
        f.customer_key,
        f.sales_amount,
        f.quantity,
        p.product_key,
        p.product_name,
        p.category,
        p.subcategory,
        p.cost
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products p
        ON f.product_key = p.product_key
    WHERE order_date IS NOT NULL
),
product_aggregations AS (
    SELECT
        product_key,
        product_name,
        category,
        subcategory,
        cost,
        DATEDIFF(MONTH, MIN(order_date), MAX(order_date)) AS lifespan,
        MAX(order_date) AS last_sale_date,
        COUNT(DISTINCT order_number) AS total_orders,
        COUNT(DISTINCT customer_key) AS total_customers,
        SUM(sales_amount) AS total_sales,
        SUM(quantity) AS total_quantity,
        ROUND(AVG(CAST(sales_amount AS FLOAT) / NULLIF(quantity, 0)),1) AS avg_selling_price
    FROM base_query
    GROUP BY product_key, product_name, category, subcategory, cost
)
SELECT 
    product_key,
    product_name,
    category,
    subcategory,
    cost,
    last_sale_date,
    DATEDIFF(MONTH, last_sale_date, GETDATE()) AS recency_in_months,
    CASE
        WHEN total_sales > 50000 THEN 'High-Performer'
        WHEN total_sales >= 10000 THEN 'Mid-Range'
        ELSE 'Low-Performer'
    END AS product_segment,
    lifespan,
    total_orders,
    total_sales,
    total_quantity,
    total_customers,
    avg_selling_price,
    CASE WHEN total_orders = 0 THEN 0 ELSE total_sales / total_orders END AS avg_order_revenue,
    CASE WHEN lifespan = 0 THEN total_sales ELSE total_sales / lifespan END AS avg_monthly_revenue
FROM product_aggregations
GO