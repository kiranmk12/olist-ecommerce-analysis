USE [ols data]

select top 5 * from orders_clean 

-- making the raw imported python files to clean,lean and properly structured one
--star Schema

--DIMCUSTOMER

CREATE TABLE DimCustomer (
    customer_key        INT IDENTITY(1,1) PRIMARY KEY,
    customer_id         VARCHAR(50),
    customer_unique_id  VARCHAR(50),
    customer_city       VARCHAR(100),
    customer_state      VARCHAR(10),
    customer_zip        VARCHAR(20)
)

INSERT INTO DimCustomer (customer_id, customer_unique_id, customer_city, customer_state, customer_zip)
SELECT 
    customer_id,
    customer_unique_id,
    customer_city,
    customer_state,
    CAST(customer_zip_code_prefix AS VARCHAR(20))
FROM customers

SELECT COUNT(*) AS total_customers FROM DimCustomer


--DIMPRODUCT

CREATE TABLE DimProduct (
    product_key                     INT IDENTITY(1,1) PRIMARY KEY,
    product_id                      VARCHAR(50),
    product_category_portuguese     VARCHAR(100),
    product_category_english        VARCHAR(100),
    product_weight_g                FLOAT,
    product_length_cm               FLOAT,
    product_height_cm               FLOAT,
    product_width_cm                FLOAT
)

INSERT INTO DimProduct (product_id, product_category_portuguese, product_category_english,
                        product_weight_g, product_length_cm, product_height_cm, product_width_cm)
SELECT 
    product_id,
    product_category_name,
    product_category_name_english,
    product_weight_g,
    product_length_cm,
    product_height_cm,
    product_width_cm
FROM products_clean

SELECT COUNT(*) AS total_products FROM DimProduct

--DIMSELLER

CREATE TABLE DimSeller (
    seller_key      INT IDENTITY(1,1) PRIMARY KEY,
    seller_id       VARCHAR(50),
    seller_city     VARCHAR(100),
    seller_state    VARCHAR(10),
    seller_zip      VARCHAR(20)
)

INSERT INTO DimSeller (seller_id, seller_city, seller_state, seller_zip)
SELECT 
    seller_id,
    seller_city,
    seller_state,
    CAST(seller_zip_code_prefix AS VARCHAR(20))
FROM sellers

SELECT COUNT(*) AS total_sellers FROM DimSeller

--FACTORDERS

CREATE TABLE FactOrders (
    order_key           INT IDENTITY(1,1) PRIMARY KEY,
    order_id            VARCHAR(50),
    customer_key        INT,
    seller_key          INT,
    product_key         INT,
    date_key            INT,
    revenue             FLOAT,
    freight_value       FLOAT,
    delivery_days       INT,
    estimated_days      INT,
    delay_days          INT,
    is_late             INT,
    review_score        FLOAT,
    payment_value       FLOAT,
    payment_type        VARCHAR(50),
    order_year          INT,
    order_month         INT
)

INSERT INTO FactOrders (
    order_id, customer_key, seller_key, product_key, date_key,
    revenue, freight_value, delivery_days, estimated_days,
    delay_days, is_late, review_score, payment_value, payment_type,
    order_year, order_month
)
SELECT
    o.order_id,
    dc.customer_key,
    ds.seller_key,
    dp.product_key,
    CAST(FORMAT(CAST(o.order_purchase_timestamp AS DATE), 'yyyyMMdd') AS INT),
    oi.price,
    oi.freight_value,
    o.delivery_days,
    o.estimated_days,
    o.delay_days,
    o.is_late,
    r.review_score,
    p.payment_value,
    p.payment_type,
    o.order_year,
    o.order_month
FROM orders_clean o
LEFT JOIN DimCustomer  dc ON o.customer_id   = dc.customer_id
LEFT JOIN order_items  oi ON o.order_id      = oi.order_id
LEFT JOIN DimSeller    ds ON oi.seller_id    = ds.seller_id
LEFT JOIN DimProduct   dp ON oi.product_id   = dp.product_id
LEFT JOIN order_reviews_clean r ON o.order_id = r.order_id
LEFT JOIN order_payments p ON o.order_id     = p.order_id

SELECT COUNT(*) AS total_fact_rows FROM FactOrders

---

ALTER TABLE FactOrders ADD order_date DATE

UPDATE f
SET f.order_date = CAST(o.order_purchase_timestamp AS DATE)
FROM FactOrders f
JOIN orders_clean o ON f.order_id = o.order_id



-- TOTAL REVENUE BY MONTH

SELECT 
    order_year,
    order_month,
    COUNT(DISTINCT order_id)  AS total_orders,
    ROUND(SUM(revenue), 2)    AS total_revenue,
    ROUND(AVG(revenue), 2)    AS avg_order_value
FROM FactOrders
GROUP BY order_year, order_month
ORDER BY order_year, order_month


--TOP 10 CATEGORIES BY REVENUE

SELECT TOP 10
    dp.product_category_english,
    COUNT(DISTINCT f.order_id)     AS total_orders,
    ROUND(SUM(f.revenue), 2)       AS total_revenue,
    ROUND(AVG(f.review_score), 2)  AS avg_review_score
FROM FactOrders f
LEFT JOIN DimProduct dp ON f.product_key = dp.product_key
GROUP BY dp.product_category_english
ORDER BY total_revenue DESC


--DELIVERY PERFORMANCE BY STATE

SELECT 
    dc.customer_state,
    COUNT(DISTINCT f.order_id)        AS total_orders,
    ROUND(AVG(f.delivery_days), 1)    AS avg_delivery_days,
    ROUND(AVG(f.delay_days), 1)       AS avg_delay_days,
    SUM(f.is_late)                    AS late_orders,
    ROUND(SUM(f.is_late) * 100.0 / 
          COUNT(f.order_id), 1)       AS late_percentage
FROM FactOrders f
LEFT JOIN DimCustomer dc ON f.customer_key = dc.customer_key
GROUP BY dc.customer_state
ORDER BY late_percentage DESC



--TOP 10 SELLERS BY REVENUE

SELECT TOP 10
    ds.seller_id,
    ds.seller_city,
    ds.seller_state,
    COUNT(DISTINCT f.order_id)          AS total_orders,
    ROUND(SUM(f.revenue), 2)            AS total_revenue,
    ROUND(AVG(f.review_score), 2)       AS avg_review_score,
    ROUND(AVG(f.delivery_days), 1)      AS avg_delivery_days
FROM FactOrders f
LEFT JOIN DimSeller ds ON f.seller_key = ds.seller_key
GROUP BY ds.seller_id, ds.seller_city, ds.seller_state
ORDER BY total_revenue DESC



-- RANK MONTHLY YEAR BY REVENUE

SELECT 
    order_year,
    order_month,
    ROUND(SUM(revenue), 2) AS monthly_revenue,
    RANK() OVER (
        PARTITION BY order_year 
        ORDER BY SUM(revenue) DESC
    ) AS revenue_rank,
    ROUND(SUM(revenue) - LAG(SUM(revenue)) OVER (
        ORDER BY order_year, order_month
    ), 2) AS mom_change
FROM FactOrders
GROUP BY order_year, order_month
ORDER BY order_year, order_month


-- DOES LATE REVIEW AFFECT THE SCORE

SELECT 
    is_late,
    COUNT(order_id)                 AS total_orders,
    ROUND(AVG(review_score), 2)     AS avg_review_score,
    ROUND(AVG(delivery_days), 1)    AS avg_delivery_days
FROM FactOrders
GROUP BY is_late
ORDER BY is_late


--PAYMENT TYPE ANALYSIS

SELECT 
    payment_type,
    COUNT(DISTINCT order_id)        AS total_orders,
    ROUND(SUM(payment_value), 2)    AS total_value,
    ROUND(AVG(payment_value), 2)    AS avg_value
FROM FactOrders
WHERE payment_type IS NOT NULL
GROUP BY payment_type
ORDER BY total_orders DESC



--SELLERS PERFORMANCE RANKING USING NTILE

SELECT 
    ds.seller_id,
    ds.seller_state,
    ROUND(SUM(f.revenue), 2)    AS total_revenue,
    ROUND(AVG(f.review_score), 2) AS avg_score,
    NTILE(4) OVER (
        ORDER BY SUM(f.revenue) DESC
    ) AS revenue_quartile      
FROM FactOrders f
LEFT JOIN DimSeller ds ON f.seller_key = ds.seller_key
GROUP BY ds.seller_id, ds.seller_state
ORDER BY total_revenue DESC


---STORED PROCEDURE FOR MONTHLY REVENUE



CREATE PROCEDURE GetMonthlyRevenue
    (@Year INT)
AS
BEGIN
    SELECT 
        order_year,
        order_month,
        COUNT(DISTINCT order_id)    AS total_orders,
        ROUND(SUM(revenue), 2)      AS total_revenue,
        ROUND(AVG(revenue), 2)      AS avg_order_value,
        SUM(is_late)                AS late_orders,
        ROUND(SUM(is_late) * 100.0 /
              COUNT(order_id), 1)   AS late_percentage
    FROM FactOrders
    WHERE order_year = @Year
    GROUP BY order_year, order_month
    ORDER BY order_month
END


EXEC GetMonthlyRevenue @Year = 2018

EXEC GetMonthlyRevenue @Year = 2017



-- UDF TO CALCULATE THE  DELIVERY STATUS LABEL


CREATE FUNCTION fn_DeliveryStatus (@delay_days INT)
RETURNS VARCHAR(20)
AS
BEGIN
    DECLARE @status VARCHAR(20)

    IF @delay_days <= 0
        SET @status = 'On Time'
    ELSE IF @delay_days <= 7
        SET @status = 'Slightly Late'
    ELSE
        SET @status = 'Very Late'
    RETURN @status
END


SELECT TOP 20
    order_id,
    delay_days,
    dbo.fn_DeliveryStatus(delay_days) AS delivery_status
FROM FactOrders
ORDER BY delay_days DESC


-- Give me a single analysis-ready table
-- with order details, customer location, product category
-- and seller info without writing joins every time

CREATE VIEW vw_OrderSummary AS
SELECT 
    f.order_id,
    f.order_year,
    f.order_month,
    f.revenue,
    f.freight_value,
    f.delivery_days,
    f.delay_days,
    f.is_late,
    dbo.fn_DeliveryStatus(f.delay_days) AS delivery_status,
    f.review_score,
    f.payment_type,
    f.payment_value,
    dc.customer_city,
    dc.customer_state,
    dp.product_category_english,
    dp.product_category_portuguese,
    ds.seller_id,
    ds.seller_city,
    ds.seller_state
FROM FactOrders f
LEFT JOIN DimCustomer dc ON f.customer_key = dc.customer_key
LEFT JOIN DimProduct  dp ON f.product_key  = dp.product_key
LEFT JOIN DimSeller   ds ON f.seller_key   = ds.seller_key


SELECT TOP 10 * FROM vw_OrderSummary
