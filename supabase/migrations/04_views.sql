
-- 1. View de Pedidos Completos
CREATE OR REPLACE VIEW vw_orders_complete AS
SELECT 
    o.id AS order_id,
    o.order_number,
    o.status,
    o.total_amount,
    o.payment_method,
    o.created_at AS order_date,
    o.updated_at AS last_updated,
    c.id AS customer_id,
    c.full_name AS customer_name,
    c.email AS customer_email,
    c.phone AS customer_phone,
    a.street,
    a.number,
    a.complement,
    a.neighborhood,
    a.city,
    a.state,
    a.zip_code,
    (SELECT COUNT(*) FROM order_items WHERE order_id = o.id) AS total_items,
    (SELECT SUM(quantity) FROM order_items WHERE order_id = o.id) AS total_quantity
FROM orders o
LEFT JOIN customers c ON o.customer_id = c.id
LEFT JOIN addresses a ON o.shipping_address_id = a.id;

-- 2. View de Itens do Pedido com Detalhes
CREATE OR REPLACE VIEW vw_order_items_details AS
SELECT 
    oi.id AS item_id,
    oi.order_id,
    o.order_number,
    o.status AS order_status,
    oi.product_id,
    oi.product_name,
    oi.quantity,
    oi.unit_price,
    oi.subtotal,
    p.name AS current_product_name,
    p.price AS current_product_price,
    p.stock_quantity AS current_stock,
    c.full_name AS customer_name,
    c.email AS customer_email,
    oi.created_at
FROM order_items oi
JOIN orders o ON oi.order_id = o.id
LEFT JOIN products p ON oi.product_id = p.id
LEFT JOIN customers c ON o.customer_id = c.id;

-- 3. View de Produtos com Estatísticas de Vendas
CREATE OR REPLACE VIEW vw_products_sales_stats AS
SELECT 
    p.id AS product_id,
    p.name,
    p.description,
    p.price,
    p.stock_quantity,
    p.category,
    p.is_active,
    COALESCE(SUM(oi.quantity), 0) AS total_sold,
    COALESCE(SUM(oi.subtotal), 0) AS total_revenue,
    COUNT(DISTINCT oi.order_id) AS total_orders,
    MAX(oi.created_at) AS last_sale_date,
    p.created_at,
    p.updated_at
FROM products p
LEFT JOIN order_items oi ON p.id = oi.product_id
GROUP BY p.id;

-- 4. View de Clientes com Estatísticas
CREATE OR REPLACE VIEW vw_customers_stats AS
SELECT 
    c.id AS customer_id,
    c.full_name,
    c.email,
    c.phone,
    c.cpf,
    c.created_at AS registered_at,
    COUNT(DISTINCT o.id) AS total_orders,
    COALESCE(SUM(o.total_amount), 0) AS total_spent,
    COALESCE(AVG(o.total_amount), 0) AS average_order_value,
    COUNT(CASE WHEN o.status = 'pending' THEN 1 END) AS pending_orders,
    COUNT(CASE WHEN o.status = 'confirmed' THEN 1 END) AS confirmed_orders,
    COUNT(CASE WHEN o.status = 'delivered' THEN 1 END) AS delivered_orders,
    COUNT(CASE WHEN o.status = 'cancelled' THEN 1 END) AS cancelled_orders,
    MAX(o.created_at) AS last_order_date,
    (SELECT COUNT(*) FROM addresses WHERE customer_id = c.id) AS total_addresses
FROM customers c
LEFT JOIN orders o ON c.id = o.customer_id
GROUP BY c.id;

-- 5. View de Vendas Diárias
CREATE OR REPLACE VIEW vw_daily_sales AS
SELECT 
    DATE(o.created_at) AS sale_date,
    COUNT(DISTINCT o.id) AS total_orders,
    COUNT(DISTINCT o.customer_id) AS unique_customers,
    SUM(o.total_amount) AS total_revenue,
    AVG(o.total_amount) AS average_order_value,
    SUM(oi.quantity) AS total_items_sold,
    COUNT(CASE WHEN o.status = 'delivered' THEN 1 END) AS delivered_orders,
    COUNT(CASE WHEN o.status = 'cancelled' THEN 1 END) AS cancelled_orders,
    SUM(CASE WHEN o.status = 'delivered' THEN o.total_amount ELSE 0 END) AS delivered_revenue
FROM orders o
LEFT JOIN (
    SELECT order_id, SUM(quantity) AS quantity
    FROM order_items
    GROUP BY order_id
) oi ON o.id = oi.order_id
GROUP BY DATE(o.created_at)
ORDER BY sale_date DESC;

-- 6. View de Top Produtos
CREATE OR REPLACE VIEW vw_top_products AS
SELECT 
    p.id AS product_id,
    p.name,
    p.category,
    p.price,
    p.stock_quantity,
    COUNT(DISTINCT oi.order_id) AS times_ordered,
    SUM(oi.quantity) AS total_quantity_sold,
    SUM(oi.subtotal) AS total_revenue,
    AVG(oi.quantity) AS avg_quantity_per_order,
    MAX(oi.created_at) AS last_sold_at
FROM products p
INNER JOIN order_items oi ON p.id = oi.product_id
INNER JOIN orders o ON oi.order_id = o.id
WHERE o.status NOT IN ('cancelled')
GROUP BY p.id, p.name, p.category, p.price, p.stock_quantity
ORDER BY total_revenue DESC;

-- 7. View de Pedidos Pendentes com Tempo de Espera
CREATE OR REPLACE VIEW vw_pending_orders AS
SELECT 
    o.id AS order_id,
    o.order_number,
    o.status,
    o.total_amount,
    o.created_at,
    EXTRACT(EPOCH FROM (NOW() - o.created_at))/3600 AS hours_since_creation,
    c.full_name AS customer_name,
    c.email AS customer_email,
    c.phone AS customer_phone,
    CONCAT(a.street, ', ', a.number, ' - ', a.city, '/', a.state) AS shipping_address,
    (SELECT COUNT(*) FROM order_items WHERE order_id = o.id) AS total_items
FROM orders o
JOIN customers c ON o.customer_id = c.id
LEFT JOIN addresses a ON o.shipping_address_id = a.id
WHERE o.status IN ('pending', 'confirmed', 'processing')
ORDER BY o.created_at ASC;

-- 8. View de Produtos com Baixo Estoque
CREATE OR REPLACE VIEW vw_low_stock_products AS
SELECT 
    p.id AS product_id,
    p.name,
    p.category,
    p.price,
    p.stock_quantity,
    p.is_active,
    COALESCE(
        (SELECT SUM(oi.quantity) 
         FROM order_items oi
         JOIN orders o ON oi.order_id = o.id
         WHERE oi.product_id = p.id
         AND o.created_at >= NOW() - INTERVAL '30 days'
         AND o.status NOT IN ('cancelled')
        ), 0
    ) AS sold_last_30_days,
    CASE 
        WHEN COALESCE(
            (SELECT SUM(oi.quantity) 
             FROM order_items oi
             JOIN orders o ON oi.order_id = o.id
             WHERE oi.product_id = p.id
             AND o.created_at >= NOW() - INTERVAL '30 days'
             AND o.status NOT IN ('cancelled')
            ), 0
        ) > 0 
        THEN ROUND((p.stock_quantity::DECIMAL / (
            SELECT SUM(oi.quantity) 
            FROM order_items oi
            JOIN orders o ON oi.order_id = o.id
            WHERE oi.product_id = p.id
            AND o.created_at >= NOW() - INTERVAL '30 days'
            AND o.status NOT IN ('cancelled')
        )) * 30, 0)
        ELSE NULL
    END AS estimated_days_until_stockout
FROM products p
WHERE p.stock_quantity < 10
AND p.is_active = true
ORDER BY p.stock_quantity ASC;

-- 9. View de Histórico Completo de Status
CREATE OR REPLACE VIEW vw_order_status_timeline AS
SELECT 
    osh.id,
    osh.order_id,
    o.order_number,
    osh.old_status,
    osh.new_status,
    osh.notes,
    osh.created_at AS changed_at,
    LAG(osh.created_at) OVER (PARTITION BY osh.order_id ORDER BY osh.created_at) AS previous_change_at,
    EXTRACT(EPOCH FROM (
        osh.created_at - LAG(osh.created_at) OVER (PARTITION BY osh.order_id ORDER BY osh.created_at)
    ))/3600 AS hours_in_previous_status,
    u.email AS changed_by_email,
    c.full_name AS customer_name
FROM order_status_history osh
JOIN orders o ON osh.order_id = o.id
LEFT JOIN customers c ON o.customer_id = c.id
LEFT JOIN auth.users u ON osh.changed_by = u.id
ORDER BY osh.order_id, osh.created_at DESC;