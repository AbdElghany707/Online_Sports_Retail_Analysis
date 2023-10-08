--check missing data
SELECT COUNT(*) AS total_rows,
COUNT(I.description) AS count_description,
COUNT(F.listing_price) AS count_listing_price,
COUNT(T.last_visited) AS count_last_visited
FROM info I INNER JOIN finance F ON F.product_id = I.product_id
            INNER JOIN traffic T ON T.product_id = I.product_id;
GO

-----------------------------------------------------------------------------------------------------------
--delete wrong enterd data
DELETE FROM finance 
WHERE listing_price =0;
GO

------------------------------------------------------------------------------------------------------------
--sale_price column from finance table isn't calculated correctly and we will not make use of it
ALTER TABLE finance
DROP COLUMN sale_price;
GO 

-----------------------------------------------------------------------------------------------------------
--listing price comparision for addidas and nike products
WITH pricing as(
SELECT B.brand, ROUND(F.listing_price,0) AS price,COUNT(F.product_id) AS num_products_price_category
FROM brands B INNER JOIN FINANCE F ON B.product_id = F.product_id
WHERE listing_price > 0
GROUP BY brand,listing_price
)
SELECT brand,price,num_products_price_category,
SUM(num_products_price_category) OVER(PARTITION BY brand) AS Total_number_of_products_for_each_brand
FROM pricing;
GO
--------------------------------------------------------------------------------------------------------
-- products with high revenue
WITH top_products AS(
SELECT B.brand,F.revenue,I.product_name
FROM brands B
INNER JOIN FINANCE F ON B.product_id = F.product_id
INNER JOIN info I ON B.product_id = I.product_id
WHERE b.brand IS NOT NULL)
SELECT TOP(5) brand, product_name,ROUND(SUM(revenue),0) AS total_revenue,
DENSE_RANK() OVER(ORDER BY SUM(revenue) DESC) AS rank
FROM top_products
WHERE brand = 'Adidas'
GROUP BY brand,product_name
UNION
SELECT DISTINCT TOP(5) brand, product_name,ROUND(SUM(revenue),0) AS total_revenue,
DENSE_RANK() OVER(ORDER BY SUM(revenue) DESC) AS rank
FROM top_products
WHERE brand = 'Nike'
GROUP BY brand,product_name
ORDER BY total_revenue DESC;

--------------------------------------------------------------------------------------------------------

--Labeling price ranges
WITH CTE_price_category AS(
SELECT B.brand,F.product_id,F.revenue,
CASE WHEN listing_price < 42 THEN 'Budget'
WHEN listing_price BETWEEN 42 AND 73 THEN 'Average'
WHEN listing_price BETWEEN 74 AND 128 THEN 'Expensive'
ELSE 'Elite'
END AS price_category
FROM brands B INNER JOIN FINANCE F ON B.product_id = F.product_id
WHERE b.brand IS NOT NULL)
SELECT brand,COUNT(product_id) AS num_products_price_category, ROUND(SUM(revenue),0) AS total_revenue,price_category,
ROUND(SUM(revenue)/COUNT(product_id),0) AS average_revenue
FROM CTE_price_category
GROUP BY brand, price_category
ORDER BY average_revenue DESC; 
GO

------------------------------------------------------------------------------------------------------------

--Average discount per brand
SELECT B.brand, AVG(F.discount)*100AS average_discount
FROM finance F INNER JOIN brands B ON B.product_id = F.product_id
GROUP BY brand
HAVING brand IS NOT NULL;
GO

-------------------------------------------------------------------------------------------------------------

--Ratings and reviews by product description length
SELECT ROUND(LEN(i.description), -2) AS description_length,
ROUND(AVG(r.rating), 2) AS average_rating
FROM info AS i
INNER JOIN reviews AS r 
ON i.product_id = r.product_id
WHERE i.description IS NOT NULL
GROUP BY ROUND(LEN(i.description), -2)
ORDER BY description_length;
GO

-----------------------------------------------------------------------------------------------------------------

--Time series analysis
SELECT B.brand, DATEPART(month, T.last_visited) AS month,
COUNT(R.product_id) AS num_reviews,ROUND(SUM(F.revenue), 0) AS total_revenue,
Round(AVG(F.discount)*100,2) AS average_monthly_discount 
FROM brands B JOIN traffic T ON B.product_id = T.product_id
                JOIN reviews R ON B.product_id = R.product_id
				JOIN finance F ON B.product_id = F.product_id
GROUP BY brand, DATEPART(month, T.last_visited)
HAVING (brand IS NOT NULL) AND (DATEPART(month, t.last_visited) IS NOT NULL)
ORDER BY brand, month;
GO

-----------------------------------------------------------------------------------------------------------------------

--Footwear product performance
WITH footwear AS
(
    SELECT i.description, Round(f.revenue,0) as revenue,R.reviews,R.rating
    FROM info AS i
    INNER JOIN finance AS f 
        ON i.product_id = f.product_id
    INNER JOIN reviews  AS R
        ON R.product_id = f.product_id
    WHERE i.description LIKE '%shoe%'
        OR i.description LIKE '%trainer%'
        OR i.description LIKE '%foot%'
        AND i.description IS NOT NULL
)
SELECT COUNT(*) AS num_footwear_products ,
(SELECT TOP(1) percentile_disc(0.5) WITHIN GROUP (ORDER BY revenue) OVER() AS median_footwear_revenue FROM footwear)  AS median_footwear_revenue
FROM footwear;
GO

-------------------------------------------------------------------------------------------------------------------------

--Clothing product performance
WITH clothwear AS
(
    SELECT i.description, f.revenue, R.reviews,R.rating
    FROM info AS i
    INNER JOIN finance AS f 
        ON i.product_id = f.product_id
    INNER JOIN reviews  AS R
        ON R.product_id = f.product_id
    WHERE i.description NOT LIKE '%shoe%'
        AND i.description NOT LIKE '%trainer%'
        AND i.description NOT LIKE '%foot%'
        AND i.description IS NOT NULL
)
SELECT COUNT(*) AS num_footwear_products ,
(SELECT TOP(1) percentile_disc(0.5) WITHIN GROUP (ORDER BY revenue) OVER() AS median_footwear_revenue FROM clothwear)  AS median_clothwear_revenue
FROM clothwear;
GO

--------------------------------------------------------------------------------------------------------------------------

--Create table for the actions happens 
CREATE TABLE dbo.brands_audits(
    product_id INT IDENTITY PRIMARY KEY,
    brand varchar(7),
    updated_at DATETIME NOT NULL,
    operation CHAR(3) NOT NULL,
    CHECK(operation = 'INS' or operation='DEL')
);
GO

--CREATE DML TRIGGER 
CREATE TRIGGER trg_brands_audit
ON brands 
AFTER INSERT, DELETE
AS
BEGIN
 SET NOCOUNT ON;
    INSERT INTO brands_audits(
    product_id ,
    brand,
    updated_at,
    operation
	)

SELECT
	i.product_id,
	brand,
	GETDATE(),
	'INS'
FROM
	inserted i
UNION ALL
SELECT
	d.product_id,
	brand,
	GETDATE(),
	'DEL'
FROM
	deleted d;
END
GO

--------------------------------------------------------------------------------------------------------------