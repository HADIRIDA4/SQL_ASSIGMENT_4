


-- Create a temporary table to store rental statistics per customer
CREATE TEMPORARY TABLE CustomerRentalStats AS
SELECT
    c.customer_id,
    c.first_name,
    c.last_name,
    AVG(EXTRACT(DAY FROM (r.return_date - r.rental_date))) AS avg_rental_duration,
    SUM(p.amount) AS total_revenue
FROM
    customer c
JOIN rental r ON c.customer_id = r.customer_id
JOIN payment p ON r.rental_id = p.rental_id
GROUP BY
    c.customer_id, c.first_name, c.last_name;

-- Create a temporary table to store film category rankings per customer
CREATE TEMPORARY TABLE RankedFilmCategories AS
SELECT
    c.customer_id,
    cat.name AS film_category,
    COUNT(*) AS category_count
FROM
    customer c
JOIN rental r ON c.customer_id = r.customer_id
JOIN inventory i ON r.inventory_id = i.inventory_id
JOIN film_category fc ON i.film_id = fc.film_id
JOIN category cat ON fc.category_id = cat.category_id
GROUP BY
    c.customer_id, cat.name
ORDER BY
    c.customer_id, category_count DESC;

-- Retrieve the top 3 film categories rented by each customer
SELECT
    crs.customer_id,
    crs.first_name,
    crs.last_name,
    crs.avg_rental_duration,
    crs.total_revenue,
    rfc.film_category
FROM
    CustomerRentalStats crs
LEFT JOIN (
    SELECT
        customer_id,
        film_category
    FROM
        RankedFilmCategories
    WHERE
        category_count <= 3
) rfc ON crs.customer_id = rfc.customer_id
ORDER BY
    crs.customer_id;

-- Drop the temporary tables
-- DROP TEMPORARY TABLE IF EXISTS CustomerRentalStats;
-- DROP TEMPORARY TABLE IF EXISTS RankedFilmCategories;

	
	
--- Identify customers who have never rented films but have made payments.
 SELECT
    c.customer_id,
    c.first_name,
    c.last_name
FROM
    customer c
JOIN payment p ON c.customer_id = p.customer_id
LEFT JOIN rental r ON c.customer_id = r.customer_id
WHERE
    r.rental_id IS NULL;
--- Find the correlation between customer rental frequency and the average rating of the rented films
WITH CustomerRentalInfo AS (
    SELECT
        customer.customer_id,
        COUNT(rental.rental_id) AS rental_frequency,
        AVG(CASE
            WHEN film.rating = 'R' THEN 4
            WHEN film.rating = 'PG-13' THEN 3
            WHEN film.rating = 'PG' THEN 2
            WHEN film.rating = 'G' THEN 1
            ELSE 0
        END) AS average_rating
    FROM
        customer
    INNER JOIN rental ON customer.customer_id = rental.customer_id
    INNER JOIN inventory ON rental.inventory_id = inventory.inventory_id
    INNER JOIN film ON inventory.film_id = film.film_id
    GROUP BY customer.customer_id
)
SELECT
    CORR(rental_frequency, average_rating) AS correlation
FROM
    CustomerRentalInfo;
--- Determine the average number of films rented per customer, broken down by city.
SELECT
    city,
    AVG(films_rented) AS average_films_rented
FROM (
    SELECT
        ct.city,
        c.customer_id,
        COUNT(r.rental_id) AS films_rented
    FROM
        customer c
    LEFT JOIN
        rental r ON c.customer_id = r.customer_id
    JOIN
        address a ON c.address_id = a.address_id
    JOIN
        city ct ON a.city_id = ct.city_id
    GROUP BY
        ct.city, c.customer_id
) AS customer_rental_counts
GROUP BY
    city;

-- Identify films that have been rented more than the average number of times and are currently not in inventory.
WITH FilmRentalCounts AS (
    SELECT
        f.film_id,
        f.title,
        COUNT(r.rental_id) AS sefilmrentalcount
    FROM
        film f
    LEFT JOIN
        inventory i ON f.film_id = i.film_id
    LEFT JOIN
        rental r ON i.inventory_id = r.inventory_id
    GROUP BY
        f.film_id, f.title
),
AverageRentalCount AS (
    SELECT
        AVG(sefilmrentalcount) AS avg_rental_count
    FROM
        FilmRentalCounts
)
SELECT
    frc.title,
    frc.sefilmrentalcount
FROM
    FilmRentalCounts frc
JOIN
    AverageRentalCount arc ON frc.sefilmrentalcount > arc.avg_rental_count AND
    frc.film_id IN (
        SELECT DISTINCT film_id
        FROM inventory
        WHERE NOT EXISTS (
            SELECT 1
            FROM rental
            WHERE inventory.inventory_id = rental.inventory_id
        )
    );
	
---Calculate the replacement cost of lost films for each store, considering the rental history.
WITH FilmRentalCounts AS (
    SELECT
        f.film_id,
        f.title,
        i.store_id,
        COUNT(r.rental_id) AS sefilmrentalcount
    FROM
        film f
    LEFT JOIN
        inventory i ON f.film_id = i.film_id
    LEFT JOIN
        rental r ON i.inventory_id = r.inventory_id
    GROUP BY
        f.film_id, f.title, i.store_id
),
AverageRentalCount AS (
    SELECT
        AVG(sefilmrentalcount) AS avg_rental_count
    FROM
        FilmRentalCounts
)
SELECT
    frc.store_id,
    SUM(frc.sefilmrentalcount * film.replacement_cost) AS replacement_cost
FROM
    FilmRentalCounts frc
JOIN
    AverageRentalCount arc ON frc.sefilmrentalcount > arc.avg_rental_count AND
    frc.film_id IN (
        SELECT DISTINCT film_id
        FROM inventory
        WHERE NOT EXISTS (
            SELECT 1
            FROM rental
            WHERE inventory.inventory_id = rental.inventory_id
        )
    )
JOIN
    film ON frc.film_id = film.film_id
GROUP BY
    frc.store_id
ORDER BY
    replacement_cost 
	DESC;

---Create a report that shows the top 5 most rented films in each category, along with their corresponding rental counts and revenue.
WITH CategoryFilmCombinations AS (
    SELECT
        c.category_id,
        c.name AS category_name,
        f.film_id,
        f.title AS film_title
    FROM
        category c
    CROSS JOIN film f
),
FilmRentalInfo AS (
    SELECT
        cfc.category_id,
        cfc.category_name,
        cfc.film_id,
        cfc.film_title,
        COUNT(r.rental_id) AS rental_count,
        SUM(p.amount) AS total_revenue
    FROM
        CategoryFilmCombinations cfc
    INNER JOIN inventory i ON cfc.film_id = i.film_id
    INNER JOIN rental r ON i.inventory_id = r.inventory_id
    INNER JOIN payment p ON r.rental_id = p.rental_id
    GROUP BY
        cfc.category_id, cfc.category_name, cfc.film_id, cfc.film_title
)
SELECT
    category_name,
    film_title,
    rental_count,
    total_revenue
FROM
    FilmRentalInfo fri
WHERE
    rental_count > 0
    AND (
        SELECT COUNT(*) FROM FilmRentalInfo fri2
        WHERE fri2.category_id = fri.category_id AND fri2.rental_count >= fri.rental_count
    ) <= 6
ORDER BY
    category_id, rental_count DESC;

---Identify stores where the revenue from film rentals exceeds the revenue from payments for all customers.
SELECT
        i.store_id,
        SUM(f.rental_duration * f.rental_rate) AS rental_revenue,
        SUM(p.amount) AS payment_revenue
    FROM
        inventory i
    INNER JOIN rental r ON i.inventory_id = r.inventory_id
    INNER JOIN film f ON i.film_id = f.film_id
    INNER JOIN payment p ON r.rental_id = p.rental_id
    GROUP BY
        i.store_id;
----Determine the average rental duration and total revenue for each store

SELECT
    s.store_id,
    AVG(EXTRACT(DAY FROM (r.return_date - r.rental_date))) AS average_rental_duration_days,
    SUM(p.amount) AS total_revenue
FROM
    store s
JOIN
    staff st ON s.store_id = st.store_id
JOIN
    customer c ON st.store_id = c.store_id
JOIN
    rental r ON c.customer_id = r.customer_id
JOIN
    payment p ON r.rental_id = p.rental_id
GROUP BY
    s.store_id;
