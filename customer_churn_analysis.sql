-- CREATE DATABASE & USE
DROP DATABASE IF EXISTS ecomm;
CREATE DATABASE ecomm;
USE ecomm;

CREATE TABLE customer_churn (
    CustomerID INT PRIMARY KEY,
    Tenure INT,
    PreferredLoginDevice VARCHAR(50),
    CityTier INT,
    WarehouseToHome INT,
    PreferredPaymentMode VARCHAR(50),
    Gender ENUM('Male','Female'),
    HoursSpentOnApp INT,
    NumberOfDeviceRegistered INT,
    PreferredOrderCat VARCHAR(50),
    SatisfactionScore INT,
    MaritalStatus VARCHAR(20),
    NumberOfAddress INT,
    Complain BIT,
    OrderAmountHikeFromlastYear INT,
    CouponUsed INT,
    OrderCount INT,
    DaySinceLastOrder INT,
    CashbackAmount FLOAT,
    Churn BIT
);

SET SQL_SAFE_UPDATES = 0;

--  DATA CLEANING
-- Handle missing values (mean)
-- 1. WarehouseToHome
SET @avg_w = (SELECT ROUND(AVG(WarehouseToHome)) FROM customer_churn WHERE WarehouseToHome IS NOT NULL);
UPDATE customer_churn SET WarehouseToHome = @avg_w WHERE WarehouseToHome IS NULL;

-- 2. HoursSpentOnApp
SET @avg_h = (SELECT ROUND(AVG(HoursSpentOnApp)) FROM customer_churn WHERE HoursSpentOnApp IS NOT NULL);
UPDATE customer_churn SET HoursSpentOnApp = @avg_h WHERE HoursSpentOnApp IS NULL;

-- 3. OrderAmountHikeFromlastYear
SET @avg_hike = (SELECT ROUND(AVG(OrderAmountHikeFromlastYear)) FROM customer_churn WHERE OrderAmountHikeFromlastYear IS NOT NULL);
UPDATE customer_churn SET OrderAmountHikeFromlastYear = @avg_hike WHERE OrderAmountHikeFromlastYear IS NULL;

-- 4. DaySinceLastOrder
SET @avg_day = (SELECT ROUND(AVG(DaySinceLastOrder)) FROM customer_churn WHERE DaySinceLastOrder IS NOT NULL);
UPDATE customer_churn SET DaySinceLastOrder = @avg_day WHERE DaySinceLastOrder IS NULL;


-- Mode imputation
SET @mode_t = (
    SELECT Tenure 
    FROM (
        SELECT Tenure, COUNT(*) AS c 
        FROM customer_churn 
        WHERE Tenure IS NOT NULL 
        GROUP BY Tenure 
        ORDER BY c DESC 
        LIMIT 1
    ) AS temp
);

UPDATE customer_churn 
SET Tenure = @mode_t 
WHERE Tenure IS NULL;


-- Remove outliers
DELETE FROM customer_churn WHERE WarehouseToHome > 100;

-- Fix inconsistencies
UPDATE customer_churn SET PreferredLoginDevice='Mobile Phone' WHERE PreferredLoginDevice IN ('Phone','phone');
UPDATE customer_churn SET PreferredOrderCat='Mobile Phone' WHERE PreferredOrderCat IN ('Mobile','mobile');
UPDATE customer_churn SET PreferredPaymentMode='Cash on Delivery' WHERE PreferredPaymentMode IN ('COD','cod','Cash On Delivery');
UPDATE customer_churn SET PreferredPaymentMode='Credit Card' WHERE PreferredPaymentMode IN ('CC','cc','Credit Card');

-- DATA TRANSFORMATION

ALTER TABLE customer_churn ADD COLUMN ComplaintReceived VARCHAR(3);
ALTER TABLE customer_churn ADD COLUMN ChurnStatus VARCHAR(10);

UPDATE customer_churn SET ComplaintReceived = CASE WHEN Complain=1 THEN 'Yes' ELSE 'No' END;
UPDATE customer_churn SET ChurnStatus = CASE WHEN Churn=1 THEN 'Churned' ELSE 'Active' END;

ALTER TABLE customer_churn DROP COLUMN Complain, DROP COLUMN Churn;

--  DATA ANALYSIS
-- 1) Churn vs Active
SELECT ChurnStatus, COUNT(*) AS Total_Customers FROM customer_churn GROUP BY ChurnStatus;

-- 2) Avg Tenure & Cashback for churned
SELECT ROUND(AVG(Tenure),2) AS AvgTenure, ROUND(AVG(CashbackAmount),2) AS AvgCashback
FROM customer_churn WHERE ChurnStatus='Churned';

-- 3) Complaint % among churned
SELECT ROUND((SUM(CASE WHEN ComplaintReceived='Yes' THEN 1 ELSE 0 END)/COUNT(*))*100,2) AS ComplaintPercent
FROM customer_churn WHERE ChurnStatus='Churned';

-- 4) CityTier highest churn preferring Laptop & Accessory
SELECT CityTier, COUNT(*) AS Total
FROM customer_churn WHERE ChurnStatus='Churned' AND PreferredOrderCat='Laptop & Accessory'
GROUP BY CityTier ORDER BY Total DESC LIMIT 1;

-- 5) Most preferred payment among Active
SELECT PreferredPaymentMode, COUNT(*) AS Total
FROM customer_churn WHERE ChurnStatus='Active'
GROUP BY PreferredPaymentMode ORDER BY Total DESC LIMIT 1;

-- 6) Total order hike for Single Mobile Phone users
SELECT SUM(OrderAmountHikeFromlastYear) AS TotalHike
FROM customer_churn WHERE MaritalStatus='Single' AND PreferredOrderCat='Mobile Phone';

-- 7) Avg devices registered by UPI users
SELECT ROUND(AVG(NumberOfDeviceRegistered),2) AS AvgDevices
FROM customer_churn WHERE PreferredPaymentMode='UPI';

-- 8) City with most customers
SELECT CityTier, COUNT(*) AS Total FROM customer_churn GROUP BY CityTier ORDER BY Total DESC LIMIT 1;

-- 9) Gender with highest coupon use
SELECT Gender, SUM(CouponUsed) AS TotalCoupons
FROM customer_churn GROUP BY Gender ORDER BY TotalCoupons DESC LIMIT 1;

-- 10) Customers & Max Hours per Category
SELECT PreferredOrderCat, COUNT(*) AS Total, MAX(HoursSpentOnApp) AS MaxHours
FROM customer_churn GROUP BY PreferredOrderCat;

-- 11) Total order count for Credit Card & max satisfaction
SELECT SUM(OrderCount) AS TotalOrderCount
FROM customer_churn
WHERE PreferredPaymentMode='Credit Card'
AND SatisfactionScore=(SELECT MAX(SatisfactionScore) FROM customer_churn);

-- 12) Avg satisfaction of customers who complained
SELECT ROUND(AVG(SatisfactionScore),2) AS AvgSatisfaction
FROM customer_churn WHERE ComplaintReceived='Yes';

-- 13) Categories for customers who used >5 coupons
SELECT DISTINCT PreferredOrderCat FROM customer_churn WHERE CouponUsed>5;

-- 14) Top 3 categories by avg cashback
SELECT PreferredOrderCat, ROUND(AVG(CashbackAmount),2) AS AvgCashback
FROM customer_churn GROUP BY PreferredOrderCat ORDER BY AvgCashback DESC LIMIT 3;

-- 15) Payment modes for Tenure=10 & OrderCount>500
SELECT DISTINCT PreferredPaymentMode FROM customer_churn WHERE Tenure=10 AND OrderCount>500;

-- 16) Distance category vs churn
SELECT 
  CASE 
    WHEN WarehouseToHome<=5 THEN 'Very Close'
    WHEN WarehouseToHome<=10 THEN 'Close'
    WHEN WarehouseToHome<=15 THEN 'Medium'
    ELSE 'Far'
  END AS DistanceCategory,
  ChurnStatus,
  COUNT(*) AS Total_Customers
FROM customer_churn GROUP BY DistanceCategory, ChurnStatus;

-- 17) Married, CityTier=1, OrderCount > avg
SELECT * FROM customer_churn
WHERE MaritalStatus='Married' AND CityTier=1
AND OrderCount>(SELECT AVG(OrderCount) FROM customer_churn);

-- CUSTOMER RETURNS TABLE
CREATE TABLE customer_returns (
  ReturnID INT PRIMARY KEY,
  CustomerID INT,
  ReturnDate DATE,
  RefundAmount FLOAT
);

INSERT INTO customer_returns VALUES
(1001,50022,'2023-01-01',2130),
(1002,50316,'2023-01-23',2000),
(1003,51099,'2023-02-14',2290),
(1004,52321,'2023-03-08',2510),
(1005,52928,'2023-03-20',3000),
(1006,53749,'2023-04-17',1740),
(1007,54206,'2023-04-21',3250),
(1008,54838,'2023-04-30',1990);

-- Join with churned + complained
SET SQL_SAFE_UPDATES = 0;
SELECT r.*, c.* 
FROM customer_returns r
JOIN customer_churn c ON r.CustomerID=c.CustomerID
WHERE c.ChurnStatus='Churned' AND c.ComplaintReceived='Yes'




























