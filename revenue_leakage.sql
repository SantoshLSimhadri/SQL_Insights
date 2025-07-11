-- SQL to identify revenue leakage
SELECT order_id FROM orders WHERE discount > 50;