# Ecommerce Supabase

Backend de e-commerce construído sobre Supabase (PostgreSQL), com foco em modelagem relacional, segurança em nível de linha e automações via Edge Functions.

## Estrutura

- **`supabase/migrations`** — schema relacional (`01_schema.sql`), funções de banco (`02_functions.sql`), políticas de Row-Level Security (`03_rls.sql`) e views (`04_views.sql`)
- **`supabase/functions`**
  - `export-order-csv` — exporta pedidos para CSV
  - `send-order-confirmation` — envia confirmação de pedido por e-mail

## Stack

PostgreSQL • PL/pgSQL • Supabase (Auth, RLS, Edge Functions)

## Como rodar

```bash
supabase start
supabase db reset   # aplica as migrations em supabase/migrations
supabase functions serve
```
