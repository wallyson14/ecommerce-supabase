
-- Habilitar RLS em todas as tabelas
ALTER TABLE customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE products ENABLE ROW LEVEL SECURITY;
ALTER TABLE orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE order_status_history ENABLE ROW LEVEL SECURITY;

-- POLÍTICAS PARA CUSTOMERS


CREATE POLICY "Customers can view own data"
    ON customers FOR SELECT
    USING (auth.uid() = user_id);

CREATE POLICY "Customers can update own data"
    ON customers FOR UPDATE
    USING (auth.uid() = user_id)
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Customers can insert own data"
    ON customers FOR INSERT
    WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Admins can view all customers"
    ON customers FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM auth.users
            WHERE auth.users.id = auth.uid()
            AND auth.users.raw_user_meta_data->>'role' = 'admin'
        )
    );

CREATE POLICY "Admins can update any customer"
    ON customers FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM auth.users
            WHERE auth.users.id = auth.uid()
            AND auth.users.raw_user_meta_data->>'role' = 'admin'
        )
    );


-- POLÍTICAS PARA ADDRESSES

CREATE POLICY "Customers can view own addresses"
    ON addresses FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM customers
            WHERE customers.id = addresses.customer_id
            AND customers.user_id = auth.uid()
        )
    );

CREATE POLICY "Customers can insert own addresses"
    ON addresses FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM customers
            WHERE customers.id = addresses.customer_id
            AND customers.user_id = auth.uid()
        )
    );

CREATE POLICY "Customers can update own addresses"
    ON addresses FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM customers
            WHERE customers.id = addresses.customer_id
            AND customers.user_id = auth.uid()
        )
    );

CREATE POLICY "Customers can delete own addresses"
    ON addresses FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM customers
            WHERE customers.id = addresses.customer_id
            AND customers.user_id = auth.uid()
        )
    );

CREATE POLICY "Admins can manage all addresses"
    ON addresses FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM auth.users
            WHERE auth.users.id = auth.uid()
            AND auth.users.raw_user_meta_data->>'role' = 'admin'
        )
    );

-- POLÍTICAS PARA PRODUCTS


CREATE POLICY "Anyone can view active products"
    ON products FOR SELECT
    USING (is_active = true OR auth.role() = 'authenticated');

CREATE POLICY "Only admins can insert products"
    ON products FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM auth.users
            WHERE auth.users.id = auth.uid()
            AND auth.users.raw_user_meta_data->>'role' = 'admin'
        )
    );

CREATE POLICY "Only admins can update products"
    ON products FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM auth.users
            WHERE auth.users.id = auth.uid()
            AND auth.users.raw_user_meta_data->>'role' = 'admin'
        )
    );

CREATE POLICY "Only admins can delete products"
    ON products FOR DELETE
    USING (
        EXISTS (
            SELECT 1 FROM auth.users
            WHERE auth.users.id = auth.uid()
            AND auth.users.raw_user_meta_data->>'role' = 'admin'
        )
    );


-- POLÍTICAS PARA ORDERS

CREATE POLICY "Customers can view own orders"
    ON orders FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM customers
            WHERE customers.id = orders.customer_id
            AND customers.user_id = auth.uid()
        )
    );

CREATE POLICY "Customers can create orders"
    ON orders FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM customers
            WHERE customers.id = orders.customer_id
            AND customers.user_id = auth.uid()
        )
    );

CREATE POLICY "Admins can view all orders"
    ON orders FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM auth.users
            WHERE auth.users.id = auth.uid()
            AND auth.users.raw_user_meta_data->>'role' = 'admin'
        )
    );

CREATE POLICY "Admins can update any order"
    ON orders FOR UPDATE
    USING (
        EXISTS (
            SELECT 1 FROM auth.users
            WHERE auth.users.id = auth.uid()
            AND auth.users.raw_user_meta_data->>'role' = 'admin'
        )
    );


-- POLÍTICAS PARA ORDER_ITEMS


CREATE POLICY "Customers can view own order items"
    ON order_items FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM orders o
            JOIN customers c ON o.customer_id = c.id
            WHERE o.id = order_items.order_id
            AND c.user_id = auth.uid()
        )
    );

CREATE POLICY "Customers can insert own order items"
    ON order_items FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM orders o
            JOIN customers c ON o.customer_id = c.id
            WHERE o.id = order_items.order_id
            AND c.user_id = auth.uid()
        )
    );

CREATE POLICY "Admins can manage all order items"
    ON order_items FOR ALL
    USING (
        EXISTS (
            SELECT 1 FROM auth.users
            WHERE auth.users.id = auth.uid()
            AND auth.users.raw_user_meta_data->>'role' = 'admin'
        )
    );


-- POLÍTICAS PARA ORDER


CREATE POLICY "Customers can view own order history"
    ON order_status_history FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM orders o
            JOIN customers c ON o.customer_id = c.id
            WHERE o.id = order_status_history.order_id
            AND c.user_id = auth.uid()
        )
    );

CREATE POLICY "Admins can view all order history"
    ON order_status_history FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM auth.users
            WHERE auth.users.id = auth.uid()
            AND auth.users.raw_user_meta_data->>'role' = 'admin'
        )
    );

CREATE POLICY "System can insert order history"
    ON order_status_history FOR INSERT
    WITH CHECK (true);

-- =====================================================
-- FUNÇÃO HELPER PARA VERIFICAR ADMIN
-- =====================================================

CREATE OR REPLACE FUNCTION is_admin()
RETURNS BOOLEAN AS $$
BEGIN
    RETURN EXISTS (
        SELECT 1 FROM auth.users
        WHERE id = auth.uid()
        AND raw_user_meta_data->>'role' = 'admin'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;