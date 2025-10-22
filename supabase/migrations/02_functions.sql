
-- 1. Função para calcular o total do pedido
CREATE OR REPLACE FUNCTION calculate_order_total(p_order_id UUID)
RETURNS DECIMAL AS $$
DECLARE
    v_total DECIMAL(10, 2);
BEGIN
    SELECT COALESCE(SUM(subtotal), 0)
    INTO v_total
    FROM order_items
    WHERE order_id = p_order_id;
    
    UPDATE orders
    SET total_amount = v_total,
        updated_at = NOW()
    WHERE id = p_order_id;
    
    RETURN v_total;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 2. Trigger para calcular subtotal do item automaticamente
CREATE OR REPLACE FUNCTION calculate_item_subtotal()
RETURNS TRIGGER AS $$
BEGIN
    NEW.subtotal = NEW.quantity * NEW.unit_price;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER calculate_order_item_subtotal
    BEFORE INSERT OR UPDATE ON order_items
    FOR EACH ROW
    EXECUTE FUNCTION calculate_item_subtotal();

-- 3. Trigger para recalcular total do pedido quando itens mudam
CREATE OR REPLACE FUNCTION recalculate_order_total()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM calculate_order_total(
        CASE 
            WHEN TG_OP = 'DELETE' THEN OLD.order_id
            ELSE NEW.order_id
        END
    );
    RETURN COALESCE(NEW, OLD);
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_order_total_on_item_change
    AFTER INSERT OR UPDATE OR DELETE ON order_items
    FOR EACH ROW
    EXECUTE FUNCTION recalculate_order_total();

-- 4. Função para atualizar status do pedido
CREATE OR REPLACE FUNCTION update_order_status(
    p_order_id UUID,
    p_new_status VARCHAR(50),
    p_notes TEXT DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
    v_old_status VARCHAR(50);
    v_result JSON;
BEGIN
    SELECT status INTO v_old_status
    FROM orders
    WHERE id = p_order_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Pedido não encontrado'
        );
    END IF;
    
    IF v_old_status = 'cancelled' THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Não é possível alterar status de pedido cancelado'
        );
    END IF;
    
    IF v_old_status = 'delivered' AND p_new_status != 'cancelled' THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Pedido já foi entregue'
        );
    END IF;
    
    UPDATE orders
    SET status = p_new_status,
        updated_at = NOW()
    WHERE id = p_order_id;
    
    INSERT INTO order_status_history (order_id, old_status, new_status, notes, changed_by)
    VALUES (p_order_id, v_old_status, p_new_status, p_notes, auth.uid());
    
    RETURN json_build_object(
        'success', true,
        'message', 'Status atualizado com sucesso',
        'old_status', v_old_status,
        'new_status', p_new_status
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 5. Função para criar um novo pedido
CREATE OR REPLACE FUNCTION create_order(
    p_customer_id UUID,
    p_items JSONB,
    p_address_id UUID,
    p_payment_method VARCHAR(50) DEFAULT 'credit_card',
    p_notes TEXT DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
    v_order_id UUID;
    v_item JSONB;
    v_product RECORD;
    v_total DECIMAL(10, 2) := 0;
BEGIN
    IF NOT EXISTS (SELECT 1 FROM customers WHERE id = p_customer_id) THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Cliente não encontrado'
        );
    END IF;
    
    INSERT INTO orders (
        customer_id,
        shipping_address_id,
        payment_method,
        notes,
        status
    ) VALUES (
        p_customer_id,
        p_address_id,
        p_payment_method,
        p_notes,
        'pending'
    ) RETURNING id INTO v_order_id;
    
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        SELECT * INTO v_product
        FROM products
        WHERE id = (v_item->>'product_id')::UUID
        AND is_active = true;
        
        IF NOT FOUND THEN
            DELETE FROM orders WHERE id = v_order_id;
            RETURN json_build_object(
                'success', false,
                'message', 'Produto não encontrado: ' || (v_item->>'product_id')
            );
        END IF;
        
        IF v_product.stock_quantity < (v_item->>'quantity')::INTEGER THEN
            DELETE FROM orders WHERE id = v_order_id;
            RETURN json_build_object(
                'success', false,
                'message', 'Estoque insuficiente para: ' || v_product.name
            );
        END IF;
        
        INSERT INTO order_items (
            order_id,
            product_id,
            product_name,
            quantity,
            unit_price
        ) VALUES (
            v_order_id,
            v_product.id,
            v_product.name,
            (v_item->>'quantity')::INTEGER,
            v_product.price
        );
        
        UPDATE products
        SET stock_quantity = stock_quantity - (v_item->>'quantity')::INTEGER
        WHERE id = v_product.id;
    END LOOP;
    
    SELECT calculate_order_total(v_order_id) INTO v_total;
    
    RETURN json_build_object(
        'success', true,
        'message', 'Pedido criado com sucesso',
        'order_id', v_order_id,
        'total_amount', v_total
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 6. Função para obter detalhes completos do pedido
CREATE OR REPLACE FUNCTION get_order_details(p_order_id UUID)
RETURNS JSON AS $$
DECLARE
    v_result JSON;
BEGIN
    SELECT json_build_object(
        'order', row_to_json(o.*),
        'customer', row_to_json(c.*),
        'address', row_to_json(a.*),
        'items', (
            SELECT json_agg(row_to_json(oi.*))
            FROM order_items oi
            WHERE oi.order_id = o.id
        ),
        'status_history', (
            SELECT json_agg(row_to_json(osh.*))
            FROM order_status_history osh
            WHERE osh.order_id = o.id
            ORDER BY osh.created_at DESC
        )
    ) INTO v_result
    FROM orders o
    LEFT JOIN customers c ON o.customer_id = c.id
    LEFT JOIN addresses a ON o.shipping_address_id = a.id
    WHERE o.id = p_order_id;
    
    RETURN v_result;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- 7. Função para cancelar pedido e restaurar estoque
CREATE OR REPLACE FUNCTION cancel_order(
    p_order_id UUID,
    p_reason TEXT DEFAULT NULL
)
RETURNS JSON AS $$
DECLARE
    v_current_status VARCHAR(50);
BEGIN
    SELECT status INTO v_current_status
    FROM orders
    WHERE id = p_order_id;
    
    IF NOT FOUND THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Pedido não encontrado'
        );
    END IF;
    
    IF v_current_status IN ('delivered', 'cancelled') THEN
        RETURN json_build_object(
            'success', false,
            'message', 'Pedido não pode ser cancelado (status: ' || v_current_status || ')'
        );
    END IF;
    
    UPDATE products p
    SET stock_quantity = stock_quantity + oi.quantity
    FROM order_items oi
    WHERE oi.product_id = p.id
    AND oi.order_id = p_order_id;
    
    UPDATE orders
    SET status = 'cancelled',
        notes = COALESCE(notes || E'\n\n', '') || 'Cancelado: ' || COALESCE(p_reason, 'Sem motivo especificado')
    WHERE id = p_order_id;
    
    RETURN json_build_object(
        'success', true,
        'message', 'Pedido cancelado com sucesso'
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;
