/*Аудиторные метрики*/
-- DAU --
SELECT DATE(watch_date) as days, COUNT(DISTINCT user_id) as dau
FROM watch_history
GROUP BY DATE(watch_date);

-- MAU -- 
SELECT DATE_TRUNC('Month', watch_date)::date as month, COUNT(DISTINCT user_id) as mau
FROM watch_history 
GROUP BY DATE_TRUNC('Month', watch_date);

-- Sticky Factory-“прилипание” пользователей: --
-- чем выше, тем больше пользователи активно используют продукт каждый день -- 
WITH dau_value as(
 			SELECT DATE(watch_date) as days, COUNT(DISTINCT user_id) as dau
			FROM watch_history
			GROUP BY DATE(watch_date)
),
mau_value as(
			SELECT DATE_TRUNC('Month', watch_date)::date as month, COUNT(DISTINCT user_id) as mau
			FROM watch_history 
			GROUP BY DATE_TRUNC('Month', watch_date)
)

SELECT d.days, d.dau, m.mau, ROUND((d.dau::numeric)/m.mau, 3) as sticky_factor
FROM dau_value as d JOIN mau_value as m ON DATE_TRUNC('month', d.days) = m.month
ORDER BY d.days
;
-- New users August 2025 -- 
SELECT DATE(created_at) as date_create_acc, COUNT(DISTINCT user_id) as new_users
FROM users
WHERE EXTRACT(MONTH FROM created_at) = '08' AND EXTRACT(YEAR FROM created_at) = '2025'
GROUP BY DATE(created_at);

-- Feature Adoption Rate - Доля использования фичи --
--Пример, сделали приложение на Mobile, нужно посмотреть как используют--
WITH dau_all as(
				SELECT DATE(watch_date) as days, COUNT(DISTINCT user_id) as dau_all
				FROM watch_history
				WHERE device_type NOT IN('Mobile')
				GROUP BY DATE(watch_date) 
),
dau_mobile as( SELECT DATE(watch_date) as days, COUNT(DISTINCT user_id) as dau_mobile
				FROM watch_history
				WHERE device_type IN('Mobile')
				GROUP BY DATE(watch_date) 

)			

SELECT da.days, da.dau_all, dm.dau_mobile,  ROUND(dm.dau_mobile::numeric/da.dau_all::numeric, 3) as part_mob
FROM dau_all as da JOIN dau_mobile as dm ON da.days = dm.days;

-- AARPU(Average action per user) - Среднее число целевых действий на пользователя--
--целевое действие - просмотренный фильм--
SELECT watch_date, 
       COUNT(DISTINCT user_id) as dau, 
       COUNT(DISTINCT CASE WHEN action='completed' THEN user_id ELSE NULL END) as feature_dau,
	   
       ROUND((COUNT(DISTINCT CASE WHEN action='completed' THEN user_id ELSE NULL END)::numeric / 
	   COUNT(DISTINCT user_id)::numeric), 3) as percent_f_dau,
       
	   SUM(CASE WHEN action='completed' THEN 1 ELSE 0 END) as events,
       
	   ROUND((SUM(CASE WHEN action='completed' THEN 1 ELSE 0 END)::numeric/ 
	   COUNT(DISTINCT CASE WHEN action='completed' THEN user_id ELSE NULL END)::numeric), 3) as mean_events
FROM watch_history
GROUP BY watch_date;


/*Метрики удовлетворенности*/
-- Lifetime -- 
-- дата повторного использования-дата регистрации --

SELECT  u.user_id, u.created_at::date as registration_date, MAX(wh.watch_date) as last_date,
		MAX(wh.watch_date) - u.created_at::date as lifetime_days
FROM users as u JOIN watch_history as wh ON u.user_id=wh.user_id
GROUP BY u.user_id, u.created_at
ORDER BY lifetime_days DESC


-- Average lifetime -- 
-- Средняя/Медианная/Максимальная продолжительность нахождения пользователя в продукте -- 
WITH lifetime as(
					SELECT  u.user_id, u.created_at::date as registration_date, MAX(wh.watch_date) as last_date,
							MAX(wh.watch_date) - u.created_at::date as lifetime_days
					FROM users as u JOIN watch_history as wh ON u.user_id=wh.user_id
					GROUP BY u.user_id, u.created_at
					ORDER BY lifetime_days DESC
)
SELECT ROUND(AVG(lifetime_days)) as avg_lifetime, 
		PERCENTILE_CONT(0.5) WITHIN GROUP(ORDER BY lifetime_days) as median_lifetime,
		MAX(lifetime_days) as max_lifetime
FROM lifetime

-- Retention rate = -- 
-- Удержание, насколько активно новые пользователи продолжают пользоваться продуктом --
-- Удержание 10-го дня по типам устройств --
WITH activity as(
    SELECT wh.device_type,
           EXTRACT(DAY FROM (wh.watch_date - u.created_at))::int as lifetime,
           COUNT(DISTINCT wh.user_id) as retained
    FROM watch_history wh
    JOIN users u USING(user_id)
    WHERE u.created_at BETWEEN '2025-01-01' AND '2025-01-31'
    GROUP BY wh.device_type, EXTRACT(DAY FROM (wh.watch_date - u.created_at))::int
),
retention as(
    SELECT device_type, lifetime, retained,
           SUM(CASE WHEN lifetime = 0 THEN retained ELSE 0 END) 
               OVER (PARTITION BY device_type) as cohort_size,
           CAST(retained as FLOAT) / NULLIF(
               SUM(CASE WHEN lifetime = 0 THEN retained ELSE 0 END) 
               OVER (PARTITION BY device_type), 0
        ) as retention_rate
    FROM activity
)
SELECT *
FROM retention
WHERE lifetime = 10
ORDER BY retention_rate DESC;


-- NPS -- 
-- Удовлетворенность пользователей продуктом -- 
SELECT device_type,
       SUM(CASE WHEN rating <= 3 THEN 1 ELSE 0 END) as detractors,
       SUM(CASE WHEN rating > 3 THEN 1 ELSE 0 END) as promoters,
       COUNT(*) as total,
       ROUND((SUM(CASE WHEN rating > 3 THEN 1 ELSE 0 END)::numeric / COUNT(*) 
            - SUM(CASE WHEN rating <= 3 THEN 1 ELSE 0 END)::numeric / COUNT(*)) * 100, 0) as nps
FROM reviews
GROUP BY device_type
ORDER BY nps DESC;
