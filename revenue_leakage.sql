# CUSTOMER ACQUISITION REVENUE ANALYSIS


-- Calculate Customer Acquisition Cost (CAC) and Revenue by Channel
WITH marketing_spend AS (
    SELECT 
        ms.campaign_date,
        ms.marketing_channel,
        ms.campaign_name,
        SUM(ms.spend_amount) as total_marketing_spend,
        COUNT(DISTINCT ms.campaign_id) as number_of_campaigns
    FROM marketing_spend ms
    WHERE ms.campaign_date >= DATEADD(YEAR, -2, GETDATE())
    GROUP BY ms.campaign_date, ms.marketing_channel, ms.campaign_name
),

acquired_customers AS (
    SELECT 
        c.acquisition_date,
        c.acquisition_channel,
        c.acquisition_campaign,
        c.customer_id,
        c.first_purchase_amount,
        c.first_purchase_date,
        DATEDIFF(DAY, c.acquisition_date, c.first_purchase_date) as days_to_first_purchase
    FROM customers c
    WHERE c.acquisition_date >= DATEADD(YEAR, -2, GETDATE())
      AND c.acquisition_channel IS NOT NULL
),

customer_acquisition_metrics AS (
    SELECT 
        DATE_TRUNC('month', ac.acquisition_date) as acquisition_month,
        ac.acquisition_channel,
        ac.acquisition_campaign,
        COUNT(DISTINCT ac.customer_id) as customers_acquired,
        SUM(ac.first_purchase_amount) as total_first_purchase_revenue,
        AVG(ac.first_purchase_amount) as avg_first_purchase_value,
        AVG(ac.days_to_first_purchase) as avg_days_to_purchase
    FROM acquired_customers ac
    GROUP BY DATE_TRUNC('month', ac.acquisition_date), ac.acquisition_channel, ac.acquisition_campaign
)

SELECT 
    cam.acquisition_month,
    cam.acquisition_channel,
    cam.acquisition_campaign,
    COALESCE(ms.total_marketing_spend, 0) as marketing_spend,
    cam.customers_acquired,
    cam.total_first_purchase_revenue,
    cam.avg_first_purchase_value,
    cam.avg_days_to_purchase,
    
    -- Calculate Customer Acquisition Cost (CAC)
    CASE 
        WHEN cam.customers_acquired > 0 THEN 
            COALESCE(ms.total_marketing_spend, 0) / cam.customers_acquired
        ELSE 0
    END as customer_acquisition_cost,
    
    -- Calculate Return on Ad Spend (ROAS) for first purchase
    CASE 
        WHEN COALESCE(ms.total_marketing_spend, 0) > 0 THEN 
            cam.total_first_purchase_revenue / ms.total_marketing_spend
        ELSE NULL
    END as first_purchase_roas,
    
    -- Calculate Cost per Dollar of Revenue
    CASE 
        WHEN cam.total_first_purchase_revenue > 0 THEN 
            COALESCE(ms.total_marketing_spend, 0) / cam.total_first_purchase_revenue
        ELSE NULL
    END as cost_per_revenue_dollar

FROM customer_acquisition_metrics cam
LEFT JOIN marketing_spend ms ON (
    DATE_TRUNC('month', ms.campaign_date) = cam.acquisition_month
    AND ms.marketing_channel = cam.acquisition_channel
    AND ms.campaign_name = cam.acquisition_campaign
)
ORDER BY cam.acquisition_month DESC, cam.acquisition_channel;

-- =====================================================
-- 2. CUSTOMER LIFETIME VALUE (CLV) CALCULATIONS
-- =====================================================

-- Calculate comprehensive Customer Lifetime Value metrics
WITH customer_purchase_history AS (
    SELECT 
        o.customer_id,
        COUNT(DISTINCT o.order_id) as total_orders,
        SUM(o.order_total) as total_revenue,
        AVG(o.order_total) as avg_order_value,
        MIN(o.order_date) as first_order_date,
        MAX(o.order_date) as last_order_date,
        DATEDIFF(DAY, MIN(o.order_date), MAX(o.order_date)) as customer_lifespan_days,
        
        -- Calculate purchase frequency
        CASE 
            WHEN COUNT(DISTINCT o.order_id) > 1 THEN
                DATEDIFF(DAY, MIN(o.order_date), MAX(o.order_date)) / 
                NULLIF(COUNT(DISTINCT o.order_id) - 1, 0)
            ELSE NULL
        END as avg_days_between_orders
        
    FROM orders o
    WHERE o.order_status = 'Completed'
      AND o.order_date >= DATEADD(YEAR, -3, GETDATE())
    GROUP BY o.customer_id
),

customer_segments AS (
    SELECT 
        c.customer_id,
        c.acquisition_channel,
        c.acquisition_date,
        c.customer_segment,
        c.geographic_region,
        cph.total_orders,
        cph.total_revenue,
        cph.avg_order_value,
        cph.first_order_date,
        cph.last_order_date,
        cph.customer_lifespan_days,
        cph.avg_days_between_orders,
        
        -- Calculate customer age in days
        DATEDIFF(DAY, c.acquisition_date, GETDATE()) as customer_age_days,
        
        -- Calculate predicted CLV using historical data
        CASE 
            WHEN cph.avg_days_between_orders IS NOT NULL AND cph.avg_days_between_orders > 0 THEN
                -- Predict future purchases based on purchase frequency
                (365.0 / cph.avg_days_between_orders) * cph.avg_order_value * 
                -- Assume 3-year customer lifetime
                (3 * 365 - DATEDIFF(DAY, c.acquisition_date, GETDATE())) / 365.0
            ELSE cph.total_revenue
        END as predicted_clv,
        
        -- Calculate revenue per day
        CASE 
            WHEN DATEDIFF(DAY, c.acquisition_date, GETDATE()) > 0 THEN
                cph.total_revenue / DATEDIFF(DAY, c.acquisition_date, GETDATE())
            ELSE 0
        END as revenue_per_day
        
    FROM customers c
    LEFT JOIN customer_purchase_history cph ON c.customer_id = cph.customer_id
    WHERE c.acquisition_date >= DATEADD(YEAR, -3, GETDATE())
),

clv_by_acquisition_channel AS (
    SELECT 
        cs.acquisition_channel,
        COUNT(DISTINCT cs.customer_id) as total_customers,
        SUM(cs.total_revenue) as total_actual_revenue,
        SUM(cs.predicted_clv) as total_predicted_clv,
        AVG(cs.total_revenue) as avg_actual_clv,
        AVG(cs.predicted_clv) as avg_predicted_clv,
        AVG(cs.avg_order_value) as avg_order_value,
        AVG(cs.total_orders) as avg_orders_per_customer,
        AVG(cs.customer_lifespan_days) as avg_customer_lifespan_days,
        AVG(cs.revenue_per_day) as avg_revenue_per_day
    FROM customer_segments cs
    GROUP BY cs.acquisition_channel
)

SELECT 
    clv.acquisition_channel,
    clv.total_customers,
    ROUND(clv.total_actual_revenue, 2) as total_actual_revenue,
    ROUND(clv.total_predicted_clv, 2) as total_predicted_clv,
    ROUND(clv.avg_actual_clv, 2) as avg_actual_clv,
    ROUND(clv.avg_predicted_clv, 2) as avg_predicted_clv,
    ROUND(clv.avg_order_value, 2) as avg_order_value,
    ROUND(clv.avg_orders_per_customer, 1) as avg_orders_per_customer,
    ROUND(clv.avg_customer_lifespan_days, 0) as avg_customer_lifespan_days,
    ROUND(clv.avg_revenue_per_day, 2) as avg_revenue_per_day,
    
    -- Calculate CLV to CAC ratio (assuming average CAC of $50 per channel)
    ROUND(clv.avg_predicted_clv / 50, 2) as clv_to_cac_ratio

FROM clv_by_acquisition_channel clv
ORDER BY clv.avg_predicted_clv DESC;

-- =====================================================
-- 3. MONTHLY RECURRING REVENUE (MRR) ANALYSIS
-- =====================================================

-- Calculate MRR for subscription-based business model
WITH monthly_subscriptions AS (
    SELECT 
        s.customer_id,
        s.subscription_id,
        s.plan_type,
        s.monthly_price,
        s.start_date,
        s.end_date,
        s.status,
        
        -- Generate date series for each month of subscription
        DATE_TRUNC('month', month_series.month_date) as revenue_month
        
    FROM subscriptions s
    CROSS JOIN (
        SELECT DATEADD(MONTH, n, '2022-01-01') as month_date
        FROM (
            SELECT ROW_NUMBER() OVER (ORDER BY (SELECT NULL)) - 1 as n
            FROM sys.objects o1
            CROSS JOIN sys.objects o2
        ) months
        WHERE n <= DATEDIFF(MONTH, '2022-01-01', GETDATE())
    ) month_series
    
    WHERE month_series.month_date >= DATE_TRUNC('month', s.start_date)
      AND month_series.month_date <= COALESCE(DATE_TRUNC('month', s.end_date), DATE_TRUNC('month', GETDATE()))
      AND s.start_date >= '2022-01-01'
),

mrr_calculations AS (
    SELECT 
        ms.revenue_month,
        ms.plan_type,
        COUNT(DISTINCT ms.customer_id) as active_subscribers,
        SUM(ms.monthly_price) as total_mrr,
        AVG(ms.monthly_price) as avg_revenue_per_user
    FROM monthly_subscriptions ms
    GROUP BY ms.revenue_month, ms.plan_type
),

mrr_trends AS (
    SELECT 
        mc.revenue_month,
        mc.plan_type,
        mc.active_subscribers,
        mc.total_mrr,
        mc.avg_revenue_per_user,
        
        -- Calculate month-over-month growth
        LAG(mc.total_mrr, 1) OVER (PARTITION BY mc.plan_type ORDER BY mc.revenue_month) as prev_month_mrr,
        LAG(mc.active_subscribers, 1) OVER (PARTITION BY mc.plan_type ORDER BY mc.revenue_month) as prev_month_subscribers,
        
        -- Calculate growth rates
        CASE 
            WHEN LAG(mc.total_mrr, 1) OVER (PARTITION BY mc.plan_type ORDER BY mc.revenue_month) > 0 THEN
                (mc.total_mrr - LAG(mc.total_mrr, 1) OVER (PARTITION BY mc.plan_type ORDER BY mc.revenue_month)) /
                LAG(mc.total_mrr, 1) OVER (PARTITION BY mc.plan_type ORDER BY mc.revenue_month) * 100
            ELSE NULL
        END as mrr_growth_rate,
        
        CASE 
            WHEN LAG(mc.active_subscribers, 1) OVER (PARTITION BY mc.plan_type ORDER BY mc.revenue_month) > 0 THEN
                (mc.active_subscribers - LAG(mc.active_subscribers, 1) OVER (PARTITION BY mc.plan_type ORDER BY mc.revenue_month)) /
                CAST(LAG(mc.active_subscribers, 1) OVER (PARTITION BY mc.plan_type ORDER BY mc.revenue_month) AS FLOAT) * 100
            ELSE NULL
        END as subscriber_growth_rate
        
    FROM mrr_calculations mc
)

SELECT 
    mt.revenue_month,
    mt.plan_type,
    mt.active_subscribers,
    ROUND(mt.total_mrr, 2) as total_mrr,
    ROUND(mt.avg_revenue_per_user, 2) as arpu,
    ROUND(mt.prev_month_mrr, 2) as prev_month_mrr,
    mt.prev_month_subscribers,
    ROUND(mt.mrr_growth_rate, 2) as mrr_growth_rate_percent,
    ROUND(mt.subscriber_growth_rate, 2) as subscriber_growth_rate_percent,
    
    -- Calculate Annual Run Rate (ARR)
    ROUND(mt.total_mrr * 12, 2) as annual_run_rate,
    
    -- Calculate net new MRR
    ROUND(mt.total_mrr - COALESCE(mt.prev_month_mrr, 0), 2) as net_new_mrr

FROM mrr_trends mt
WHERE mt.revenue_month >= DATEADD(MONTH, -12, GETDATE())
ORDER BY mt.revenue_month DESC, mt.plan_type;

-- =====================================================
-- 4. CAMPAIGN ROI AND ATTRIBUTION ANALYSIS
-- =====================================================

-- Calculate marketing campaign ROI with multi-touch attribution
WITH campaign_touchpoints AS (
    SELECT 
        ct.customer_id,
        ct.campaign_id,
        ct.touchpoint_date,
        ct.marketing_channel,
        ct.campaign_name,
        ct.touchpoint_type,
        ct.attribution_weight,
        
        -- Rank touchpoints for first/last touch attribution
        ROW_NUMBER() OVER (PARTITION BY ct.customer_id ORDER BY ct.touchpoint_date ASC) as first_touch_rank,
        ROW_NUMBER() OVER (PARTITION BY ct.customer_id ORDER BY ct.touchpoint_date DESC) as last_touch_rank
        
    FROM customer_touchpoints ct
    WHERE ct.touchpoint_date >= DATEADD(YEAR, -1, GETDATE())
),

customer_revenue_attribution AS (
    SELECT 
        cra.customer_id,
        SUM(cra.order_total) as total_customer_revenue,
        MIN(cra.order_date) as first_order_date,
        MAX(cra.order_date) as last_order_date,
        COUNT(DISTINCT cra.order_id) as total_orders
    FROM (
        SELECT DISTINCT 
            o.customer_id,
            o.order_id,
            o.order_total,
            o.order_date
        FROM orders o
        INNER JOIN campaign_touchpoints ct ON o.customer_id = ct.customer_id
        WHERE o.order_date >= ct.touchpoint_date
          AND o.order_date <= DATEADD(DAY, 90, ct.touchpoint_date) -- 90-day attribution window
          AND o.order_status = 'Completed'
    ) cra
    GROUP BY cra.customer_id
),

campaign_attribution_revenue AS (
    SELECT 
        ct.campaign_id,
        ct.campaign_name,
        ct.marketing_channel,
        
        -- First touch attribution
        SUM(CASE WHEN ct.first_touch_rank = 1 THEN cra.total_customer_revenue ELSE 0 END) as first_touch_revenue,
        COUNT(CASE WHEN ct.first_touch_rank = 1 THEN ct.customer_id END) as first_touch_customers,
        
        -- Last touch attribution  
        SUM(CASE WHEN ct.last_touch_rank = 1 THEN cra.total_customer_revenue ELSE 0 END) as last_touch_revenue,
        COUNT(CASE WHEN ct.last_touch_rank = 1 THEN ct.customer_id END) as last_touch_customers,
        
        -- Multi-touch attribution (weighted)
        SUM(cra.total_customer_revenue * ct.attribution_weight) as multi_touch_revenue,
        SUM(ct.attribution_weight) as total_attribution_weight,
        
        -- Total influenced revenue (any touch)
        SUM(cra.total_customer_revenue) as total_influenced_revenue,
        COUNT(DISTINCT ct.customer_id) as total_influenced_customers
        
    FROM campaign_touchpoints ct
    INNER JOIN customer_revenue_attribution cra ON ct.customer_id = cra.customer_id
    GROUP BY ct.campaign_id, ct.campaign_name, ct.marketing_channel
),

campaign_costs AS (
    SELECT 
        c.campaign_id,
        c.campaign_name,
        c.marketing_channel,
        SUM(c.campaign_cost) as total_campaign_cost,
        SUM(c.impressions) as total_impressions,
        SUM(c.clicks) as total_clicks,
        SUM(c.conversions) as total_conversions
    FROM campaigns c
    WHERE c.campaign_start_date >= DATEADD(YEAR, -1, GETDATE())
    GROUP BY c.campaign_id, c.campaign_name, c.marketing_channel
)

SELECT 
    car.campaign_id,
    car.campaign_name,
    car.marketing_channel,
    COALESCE(cc.total_campaign_cost, 0) as campaign_cost,
    
    -- Attribution Revenue
    ROUND(car.first_touch_revenue, 2) as first_touch_revenue,
    car.first_touch_customers,
    ROUND(car.last_touch_revenue, 2) as last_touch_revenue,
    car.last_touch_customers,
    ROUND(car.multi_touch_revenue, 2) as multi_touch_revenue,
    ROUND(car.total_influenced_revenue, 2) as total_influenced_revenue,
    car.total_influenced_customers,
    
    -- ROI Calculations
    CASE 
        WHEN COALESCE(cc.total_campaign_cost, 0) > 0 THEN
            ROUND((car.first_touch_revenue - cc.total_campaign_cost) / cc.total_campaign_cost * 100, 2)
        ELSE NULL
    END as first_touch_roi_percent,
    
    CASE 
        WHEN COALESCE(cc.total_campaign_cost, 0) > 0 THEN
            ROUND((car.last_touch_revenue - cc.total_campaign_cost) / cc.total_campaign_cost * 100, 2)
        ELSE NULL
    END as last_touch_roi_percent,
    
    CASE 
        WHEN COALESCE(cc.total_campaign_cost, 0) > 0 THEN
            ROUND((car.multi_touch_revenue - cc.total_campaign_cost) / cc.total_campaign_cost * 100, 2)
        ELSE NULL
    END as multi_touch_roi_percent,
    
    -- ROAS (Return on Ad Spend)
    CASE 
        WHEN COALESCE(cc.total_campaign_cost, 0) > 0 THEN
            ROUND(car.first_touch_revenue / cc.total_campaign_cost, 2)
        ELSE NULL
    END as first_touch_roas,
    
    -- Performance Metrics
    COALESCE(cc.total_impressions, 0) as impressions,
    COALESCE(cc.total_clicks, 0) as clicks,
    COALESCE(cc.total_conversions, 0) as conversions,
    
    CASE 
        WHEN COALESCE(cc.total_impressions, 0) > 0 THEN
            ROUND(CAST(cc.total_clicks AS FLOAT) / cc.total_impressions * 100, 3)
        ELSE NULL
    END as click_through_rate_percent,
    
    CASE 
        WHEN COALESCE(cc.total_clicks, 0) > 0 THEN
            ROUND(CAST(cc.total_conversions AS FLOAT) / cc.total_clicks * 100, 3)
        ELSE NULL
    END as conversion_rate_percent

FROM campaign_attribution_revenue car
LEFT JOIN campaign_costs cc ON car.campaign_id = cc.campaign_id
ORDER BY car.multi_touch_revenue DESC;

-- =====================================================
-- 5. REVENUE COHORT ANALYSIS
-- =====================================================

-- Analyze revenue patterns by customer acquisition cohorts
WITH customer_cohorts AS (
    SELECT 
        c.customer_id,
        DATE_TRUNC('month', c.acquisition_date) as cohort_month,
        c.acquisition_channel
    FROM customers c
    WHERE c.acquisition_date >= DATEADD(YEAR, -2, GETDATE())
),

monthly_revenue AS (
    SELECT 
        o.customer_id,
        DATE_TRUNC('month', o.order_date) as revenue_month,
        SUM(o.order_total) as monthly_revenue
    FROM orders o
    WHERE o.order_status = 'Completed'
      AND o.order_date >= DATEADD(YEAR, -2, GETDATE())
    GROUP BY o.customer_id, DATE_TRUNC('month', o.order_date)
),

cohort_revenue_data AS (
    SELECT 
        cc.cohort_month,
        cc.acquisition_channel,
        mr.revenue_month,
        DATEDIFF(MONTH, cc.cohort_month, mr.revenue_month) as months_since_acquisition,
        SUM(mr.monthly_revenue) as cohort_monthly_revenue,
        COUNT(DISTINCT cc.customer_id) as cohort_size,
        COUNT(DISTINCT mr.customer_id) as active_customers
    FROM customer_cohorts cc
    LEFT JOIN monthly_revenue mr ON cc.customer_id = mr.customer_id
    WHERE mr.revenue_month IS NOT NULL
    GROUP BY cc.cohort_month, cc.acquisition_channel, mr.revenue_month
),

cohort_revenue_summary AS (
    SELECT 
        crd.cohort_month,
        crd.acquisition_channel,
        crd.months_since_acquisition,
        crd.cohort_size,
        crd.active_customers,
        ROUND(crd.cohort_monthly_revenue, 2) as cohort_monthly_revenue,
        ROUND(crd.cohort_monthly_revenue / crd.cohort_size, 2) as revenue_per_customer,
        ROUND(CAST(crd.active_customers AS FLOAT) / crd.cohort_size * 100, 2) as retention_rate_percent,
        
        -- Calculate cumulative revenue
        SUM(crd.cohort_monthly_revenue) OVER (
            PARTITION BY crd.cohort_month, crd.acquisition_channel 
            ORDER BY crd.months_since_acquisition
        ) as cumulative_revenue,
        
        -- Calculate cumulative revenue per customer
        SUM(crd.cohort_monthly_revenue) OVER (
            PARTITION BY crd.cohort_month, crd.acquisition_channel 
            ORDER BY crd.months_since_acquisition
        ) / crd.cohort_size as cumulative_revenue_per_customer
        
    FROM cohort_revenue_data crd
    WHERE crd.months_since_acquisition >= 0
      AND crd.months_since_acquisition <= 12 -- First 12 months
)

SELECT 
    crs.cohort_month,
    crs.acquisition_channel,
    crs.months_since_acquisition,
    crs.cohort_size,
    crs.active_customers,
    crs.cohort_monthly_revenue,
    crs.revenue_per_customer,
    crs.retention_rate_percent,
    ROUND(crs.cumulative_revenue, 2) as cumulative_revenue,
    ROUND(crs.cumulative_revenue_per_customer, 2) as cumulative_revenue_per_customer,
    
    -- Calculate payback period (months to recover acquisition cost)
    CASE 
        WHEN crs.cumulative_revenue_per_customer >= 50 THEN -- Assuming $50 CAC
            'Payback Achieved'
        ELSE 'Not Yet'
    END as payback_status

FROM cohort_revenue_summary crs
ORDER BY crs.cohort_month, crs.acquisition_channel, crs.months_since_acquisition;
