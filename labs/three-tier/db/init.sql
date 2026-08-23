-- DB 層。AP からのみ接続される。
CREATE TABLE IF NOT EXISTS items (
    id       SERIAL PRIMARY KEY,
    sku      TEXT NOT NULL UNIQUE,
    name     TEXT NOT NULL,
    quantity INTEGER NOT NULL DEFAULT 0,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- 復元演習で件数を突き合わせるための初期データ。
INSERT INTO items (sku, name, quantity) VALUES
    ('SKU-0001', 'ラベルプリンタ用ラベル', 120),
    ('SKU-0002', 'ピッキングカート',       8),
    ('SKU-0003', 'ハンディターミナル',    24),
    ('SKU-0004', 'パレット',             300),
    ('SKU-0005', '梱包用テープ',          75)
ON CONFLICT (sku) DO NOTHING;
