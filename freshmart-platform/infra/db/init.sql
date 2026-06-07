-- ─────────────────────────────────────────────────────────────────────────────
-- FreshMart PostgreSQL Initialisation
-- Run once when the PostgreSQL StatefulSet starts.
-- Each service also auto-creates its own tables via SQLAlchemy/pgx on startup,
-- so this file is the authoritative schema reference.
-- ─────────────────────────────────────────────────────────────────────────────

-- ─── Products (owned by product-service) ─────────────────────────────────────
CREATE TABLE IF NOT EXISTS products (
    id          SERIAL        PRIMARY KEY,
    name        VARCHAR(255)  NOT NULL,
    price       NUMERIC(10,2) NOT NULL,
    category    VARCHAR(100)  NOT NULL,
    image       TEXT,
    description TEXT,
    in_stock    BOOLEAN       NOT NULL DEFAULT TRUE,
    badge       VARCHAR(50),
    created_at  TIMESTAMPTZ   DEFAULT NOW(),
    updated_at  TIMESTAMPTZ   DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_products_category ON products(category);
CREATE INDEX IF NOT EXISTS idx_products_in_stock  ON products(in_stock);

-- ─── Cart (owned by cart-service) ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS cart_sessions (
    session_id  VARCHAR(255) PRIMARY KEY,
    created_at  TIMESTAMPTZ  DEFAULT NOW(),
    updated_at  TIMESTAMPTZ  DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS cart_items (
    id            SERIAL        PRIMARY KEY,
    session_id    VARCHAR(255)  NOT NULL REFERENCES cart_sessions(session_id) ON DELETE CASCADE,
    product_id    INTEGER       NOT NULL,
    product_name  VARCHAR(255)  NOT NULL,
    product_price NUMERIC(10,2) NOT NULL,
    quantity      INTEGER       NOT NULL DEFAULT 1,
    CONSTRAINT uq_session_product UNIQUE (session_id, product_id)
);

CREATE INDEX IF NOT EXISTS idx_cart_items_session ON cart_items(session_id);

-- ─── Orders (owned by order-service) ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS orders (
    id            VARCHAR(50)   PRIMARY KEY,
    session_id    VARCHAR(255)  NOT NULL,
    status        VARCHAR(50)   NOT NULL DEFAULT 'pending',
    subtotal      NUMERIC(10,2) NOT NULL,
    delivery_fee  NUMERIC(10,2) NOT NULL DEFAULT 3.99,
    total         NUMERIC(10,2) NOT NULL,
    full_name     VARCHAR(255),
    address_line1 TEXT,
    city          VARCHAR(100),
    postcode      VARCHAR(20),
    created_at    TIMESTAMPTZ   DEFAULT NOW(),
    updated_at    TIMESTAMPTZ   DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS order_items (
    id            SERIAL        PRIMARY KEY,
    order_id      VARCHAR(50)   NOT NULL REFERENCES orders(id) ON DELETE CASCADE,
    product_id    INTEGER       NOT NULL,
    product_name  VARCHAR(255)  NOT NULL,
    product_price NUMERIC(10,2) NOT NULL,
    quantity      INTEGER       NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_orders_session    ON orders(session_id);
CREATE INDEX IF NOT EXISTS idx_orders_status     ON orders(status);
CREATE INDEX IF NOT EXISTS idx_order_items_order ON order_items(order_id);

-- ─── Payments (owned by payment-service) ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS payments (
    id             VARCHAR(50)    PRIMARY KEY,
    order_id       VARCHAR(50)    NOT NULL,
    amount         NUMERIC(10,2)  NOT NULL,
    status         VARCHAR(50)    NOT NULL DEFAULT 'pending',
    card_last_four VARCHAR(4),
    created_at     TIMESTAMPTZ    DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_payments_order_id ON payments(order_id);

-- ─── Seed Products ────────────────────────────────────────────────────────────
-- Only inserts if table is empty (idempotent)
INSERT INTO products (id, name, price, category, image, description, in_stock)
SELECT * FROM (VALUES
    (1,  'Organic Bananas',    1.50, 'Fruit',      'https://images.unsplash.com/photo-1603833665858-e61d17a86224?auto=format&fit=crop&w=400&q=80', 'Sweet, ripe organic bananas. A great source of potassium and natural energy.', TRUE),
    (2,  'Whole Milk (2L)',    2.10, 'Dairy',      'https://images.unsplash.com/photo-1550583724-1255818c053b?auto=format&fit=crop&w=400&q=80', 'Fresh whole milk from grass-fed cows. Rich in calcium and vitamins.', TRUE),
    (3,  'Sourdough Bread',    3.20, 'Bakery',     'https://images.unsplash.com/photo-1585478259715-876acc5be8eb?auto=format&fit=crop&w=400&q=80', 'Crusty, artisanal sourdough baked fresh every morning. Slow-fermented for 24 hours.', TRUE),
    (4,  'Avocados (2pk)',     2.50, 'Fruit',      'https://images.unsplash.com/photo-1523049673857-eb18f1d7b578?auto=format&fit=crop&w=400&q=80', 'Creamy, ripe avocados perfect for salads or toast. Locally sourced and organic.', TRUE),
    (5,  'Vine Tomatoes',      1.80, 'Vegetables', 'https://images.unsplash.com/photo-1592924357228-91a4daadcfea?auto=format&fit=crop&w=400&q=80', 'Juicy vine-ripened tomatoes bursting with flavour.', TRUE),
    (6,  'Greek Yogurt',       1.95, 'Dairy',      'https://images.unsplash.com/photo-1488477181946-6428a0291777?auto=format&fit=crop&w=400&q=80', 'Thick, creamy Greek yogurt. High in protein and probiotics.', TRUE),
    (7,  'Spinach (200g)',     1.20, 'Vegetables', 'https://images.unsplash.com/photo-1576045057995-568f588f82fb?auto=format&fit=crop&w=400&q=80', 'Fresh baby spinach leaves, pre-washed and ready to eat. Packed with iron.', TRUE),
    (8,  'Pink Lady Apples',   2.00, 'Fruit',      'https://images.unsplash.com/photo-1560806887-1e480c8ca0ff?auto=format&fit=crop&w=400&q=80', 'Crisp, sweet-tart Pink Lady apples. Sustainably grown in Kent.', TRUE),
    (9,  'Fresh Strawberries', 2.80, 'Fruit',      'https://images.unsplash.com/photo-1464965911861-746a04b4bca6?auto=format&fit=crop&w=400&q=80', 'Sweet, juicy British strawberries picked at peak ripeness.', TRUE),
    (10, 'Free Range Eggs',    2.40, 'Dairy',      'https://images.unsplash.com/photo-1506976785307-8732e854ad03?auto=format&fit=crop&w=400&q=80', 'A dozen large free-range eggs from happy hens. Rich golden yolks.', TRUE),
    (11, 'Red Bell Pepper',    0.80, 'Vegetables', 'https://images.unsplash.com/photo-1563513130-18458788448d?auto=format&fit=crop&w=400&q=80', 'Sweet, crunchy red peppers. Great for stir-fries or eating raw.', TRUE),
    (12, 'Unsalted Butter',    1.75, 'Dairy',      'https://images.unsplash.com/photo-1589985270826-4b7bb135bc9d?auto=format&fit=crop&w=400&q=80', 'Churned from the finest cream. Ideal for baking and cooking.', TRUE)
) AS v(id, name, price, category, image, description, in_stock)
WHERE NOT EXISTS (SELECT 1 FROM products LIMIT 1)
ON CONFLICT (id) DO NOTHING;

-- Reset sequence to avoid PK collision after manual inserts
SELECT setval('products_id_seq', (SELECT MAX(id) FROM products));
