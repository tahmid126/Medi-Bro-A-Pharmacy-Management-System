-- ==============================================================================
-- MEDIBRO ENTERPRISE MULTI-TENANT SAAS DATABASE SCHEMA
-- Target: Supabase (PostgreSQL 15+)
-- ==============================================================================

-- Enable UUID extension
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ==============================================================================
-- 1. PHARMACIES (TENANTS)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.pharmacies (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    name VARCHAR(255) NOT NULL,
    license_no VARCHAR(100),
    phone VARCHAR(30),
    email VARCHAR(100),
    address TEXT,
    logo_url TEXT,
    plan_type VARCHAR(50) DEFAULT 'free_trial', -- 'free_trial', 'basic', 'standard', 'pro', 'enterprise'
    status VARCHAR(50) DEFAULT 'active',        -- 'active', 'past_due', 'suspended', 'cancelled'
    currency VARCHAR(10) DEFAULT 'BDT',
    trial_ends_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '14 days'),
    subscription_ends_at TIMESTAMPTZ,
    settings JSONB DEFAULT '{"print_type": "thermal_80mm", "auto_print": true, "vat_enabled": false, "vat_percent": 0, "low_stock_threshold": 10}'::jsonb,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ==============================================================================
-- 2. USER PROFILES & ROLES
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    pharmacy_id UUID REFERENCES public.pharmacies(id) ON DELETE CASCADE,
    full_name VARCHAR(150),
    phone VARCHAR(30),
    role VARCHAR(50) DEFAULT 'owner', -- 'super_admin', 'owner', 'manager', 'cashier'
    avatar_url TEXT,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ==============================================================================
-- 3. SUBSCRIPTIONS & PAYMENTS
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.subscriptions (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pharmacy_id UUID NOT NULL REFERENCES public.pharmacies(id) ON DELETE CASCADE,
    plan_name VARCHAR(50) NOT NULL,
    billing_cycle VARCHAR(20) DEFAULT 'monthly', -- 'monthly', 'annual', 'lifetime'
    amount NUMERIC(12, 2) NOT NULL DEFAULT 0,
    start_date TIMESTAMPTZ DEFAULT NOW(),
    end_date TIMESTAMPTZ NOT NULL,
    payment_status VARCHAR(50) DEFAULT 'paid', -- 'pending', 'paid', 'failed'
    payment_method VARCHAR(50), -- 'bkash', 'nagad', 'bank', 'manual'
    trx_id VARCHAR(100),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ==============================================================================
-- 4. MASTER GLOBAL MEDICINE LIBRARY (Searchable by all pharmacies)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.global_medicines (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    brand_name VARCHAR(255) NOT NULL,
    generic_name VARCHAR(255),
    dosage_form VARCHAR(100), -- Tablet, Capsule, Syrup, Injection, etc.
    strength VARCHAR(100),    -- e.g. 500mg, 10mg, 20mg
    company VARCHAR(255),     -- Square, Beximco, Incepta, etc.
    default_unit VARCHAR(50) DEFAULT 'Pcs',
    default_mrp NUMERIC(10, 2) DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_global_med_brand ON public.global_medicines(brand_name);
CREATE INDEX IF NOT EXISTS idx_global_med_generic ON public.global_medicines(generic_name);

-- ==============================================================================
-- 5. PHARMACY INVENTORY (MEDICINES & BATCHES)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.medicines (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pharmacy_id UUID NOT NULL REFERENCES public.pharmacies(id) ON DELETE CASCADE,
    global_id UUID REFERENCES public.global_medicines(id) ON DELETE SET NULL,
    brand_name VARCHAR(255) NOT NULL,
    generic_name VARCHAR(255),
    dosage_form VARCHAR(100) DEFAULT 'Tablet',
    strength VARCHAR(100),
    company VARCHAR(255),
    category VARCHAR(100),
    rack_location VARCHAR(100),
    unit VARCHAR(50) DEFAULT 'Pcs',
    min_stock_alert INT DEFAULT 10,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_pharmacy_med_name ON public.medicines(pharmacy_id, brand_name);

CREATE TABLE IF NOT EXISTS public.batches (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pharmacy_id UUID NOT NULL REFERENCES public.pharmacies(id) ON DELETE CASCADE,
    medicine_id UUID NOT NULL REFERENCES public.medicines(id) ON DELETE CASCADE,
    batch_number VARCHAR(100) NOT NULL,
    expiry_date DATE NOT NULL,
    purchase_price NUMERIC(12, 2) NOT NULL DEFAULT 0,
    selling_price NUMERIC(12, 2) NOT NULL DEFAULT 0,
    mrp NUMERIC(12, 2) NOT NULL DEFAULT 0,
    stock_qty INT NOT NULL DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_batch_med ON public.batches(pharmacy_id, medicine_id, expiry_date);

-- Medicine Add Requests (Sent by pharmacy staff to Admin / System)
CREATE TABLE IF NOT EXISTS public.medicine_requests (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pharmacy_id UUID NOT NULL REFERENCES public.pharmacies(id) ON DELETE CASCADE,
    requested_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    brand_name VARCHAR(255) NOT NULL,
    generic_name VARCHAR(255),
    dosage_form VARCHAR(100),
    strength VARCHAR(100),
    company VARCHAR(255),
    notes TEXT,
    status VARCHAR(50) DEFAULT 'pending', -- 'pending', 'approved', 'rejected'
    admin_remarks TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ==============================================================================
-- 6. CONTACTS: CUSTOMERS & SUPPLIERS
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.customers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pharmacy_id UUID NOT NULL REFERENCES public.pharmacies(id) ON DELETE CASCADE,
    name VARCHAR(200) NOT NULL,
    phone VARCHAR(30),
    email VARCHAR(100),
    address TEXT,
    notes TEXT,
    total_purchased NUMERIC(14, 2) DEFAULT 0,
    current_due NUMERIC(14, 2) DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_customer_phone ON public.customers(pharmacy_id, phone);

CREATE TABLE IF NOT EXISTS public.suppliers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pharmacy_id UUID NOT NULL REFERENCES public.pharmacies(id) ON DELETE CASCADE,
    name VARCHAR(200) NOT NULL,
    company_name VARCHAR(200),
    phone VARCHAR(30),
    email VARCHAR(100),
    address TEXT,
    total_supplied NUMERIC(14, 2) DEFAULT 0,
    current_due NUMERIC(14, 2) DEFAULT 0,
    is_active BOOLEAN DEFAULT true,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ==============================================================================
-- 7. SALES / POS (EXPORT) & INVOICES
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.invoices (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pharmacy_id UUID NOT NULL REFERENCES public.pharmacies(id) ON DELETE CASCADE,
    invoice_number VARCHAR(100) NOT NULL,
    customer_id UUID REFERENCES public.customers(id) ON DELETE SET NULL,
    customer_name VARCHAR(200) DEFAULT 'Walking Customer',
    customer_phone VARCHAR(30),
    subtotal NUMERIC(14, 2) NOT NULL DEFAULT 0,
    discount_type VARCHAR(20) DEFAULT 'fixed', -- 'fixed' or 'percent'
    discount_amount NUMERIC(12, 2) DEFAULT 0,
    vat_percent NUMERIC(5, 2) DEFAULT 0,
    vat_amount NUMERIC(12, 2) DEFAULT 0,
    grand_total NUMERIC(14, 2) NOT NULL DEFAULT 0,
    paid_amount NUMERIC(14, 2) NOT NULL DEFAULT 0,
    due_amount NUMERIC(14, 2) NOT NULL DEFAULT 0,
    payment_method VARCHAR(50) DEFAULT 'cash', -- 'cash', 'card', 'bkash', 'nagad', 'mixed'
    status VARCHAR(50) DEFAULT 'completed',    -- 'completed', 'returned', 'void'
    notes TEXT,
    served_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_invoice_date ON public.invoices(pharmacy_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_invoice_no ON public.invoices(pharmacy_id, invoice_number);

CREATE TABLE IF NOT EXISTS public.invoice_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pharmacy_id UUID NOT NULL REFERENCES public.pharmacies(id) ON DELETE CASCADE,
    invoice_id UUID NOT NULL REFERENCES public.invoices(id) ON DELETE CASCADE,
    medicine_id UUID NOT NULL REFERENCES public.medicines(id) ON DELETE RESTRICT,
    batch_id UUID NOT NULL REFERENCES public.batches(id) ON DELETE RESTRICT,
    medicine_name VARCHAR(255) NOT NULL,
    batch_number VARCHAR(100),
    expiry_date DATE,
    quantity INT NOT NULL,
    unit_price NUMERIC(12, 2) NOT NULL,
    mrp NUMERIC(12, 2) NOT NULL,
    purchase_price NUMERIC(12, 2) NOT NULL DEFAULT 0, -- Needed for profit calculation
    total_price NUMERIC(14, 2) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ==============================================================================
-- 8. PURCHASES / STOCK-IN (IMPORT)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.purchases (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pharmacy_id UUID NOT NULL REFERENCES public.pharmacies(id) ON DELETE CASCADE,
    purchase_number VARCHAR(100) NOT NULL,
    supplier_id UUID REFERENCES public.suppliers(id) ON DELETE SET NULL,
    supplier_name VARCHAR(200),
    total_amount NUMERIC(14, 2) NOT NULL DEFAULT 0,
    discount_amount NUMERIC(12, 2) DEFAULT 0,
    grand_total NUMERIC(14, 2) NOT NULL DEFAULT 0,
    paid_amount NUMERIC(14, 2) NOT NULL DEFAULT 0,
    due_amount NUMERIC(14, 2) NOT NULL DEFAULT 0,
    payment_method VARCHAR(50) DEFAULT 'cash',
    purchase_date DATE DEFAULT CURRENT_DATE,
    notes TEXT,
    received_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.purchase_items (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pharmacy_id UUID NOT NULL REFERENCES public.pharmacies(id) ON DELETE CASCADE,
    purchase_id UUID NOT NULL REFERENCES public.purchases(id) ON DELETE CASCADE,
    medicine_id UUID NOT NULL REFERENCES public.medicines(id) ON DELETE RESTRICT,
    batch_id UUID REFERENCES public.batches(id) ON DELETE SET NULL,
    medicine_name VARCHAR(255) NOT NULL,
    batch_number VARCHAR(100) NOT NULL,
    expiry_date DATE NOT NULL,
    quantity INT NOT NULL,
    purchase_price NUMERIC(12, 2) NOT NULL,
    selling_price NUMERIC(12, 2) NOT NULL,
    total_price NUMERIC(14, 2) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ==============================================================================
-- 9. DUE LEDGERS (CUSTOMER & SUPPLIER ACCOUNTS)
-- ==============================================================================
CREATE TABLE IF NOT EXISTS public.customer_ledgers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pharmacy_id UUID NOT NULL REFERENCES public.pharmacies(id) ON DELETE CASCADE,
    customer_id UUID NOT NULL REFERENCES public.customers(id) ON DELETE CASCADE,
    invoice_id UUID REFERENCES public.invoices(id) ON DELETE SET NULL,
    entry_type VARCHAR(50) NOT NULL, -- 'invoice_due', 'payment_received', 'adjustment', 'opening'
    debit NUMERIC(14, 2) DEFAULT 0,  -- increases customer due
    credit NUMERIC(14, 2) DEFAULT 0, -- decreases customer due
    balance NUMERIC(14, 2) NOT NULL, -- remaining due balance after this transaction
    payment_method VARCHAR(50),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.supplier_ledgers (
    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
    pharmacy_id UUID NOT NULL REFERENCES public.pharmacies(id) ON DELETE CASCADE,
    supplier_id UUID NOT NULL REFERENCES public.suppliers(id) ON DELETE CASCADE,
    purchase_id UUID REFERENCES public.purchases(id) ON DELETE SET NULL,
    entry_type VARCHAR(50) NOT NULL, -- 'purchase_due', 'payment_made', 'adjustment', 'opening'
    debit NUMERIC(14, 2) DEFAULT 0,  -- decreases supplier due (we paid)
    credit NUMERIC(14, 2) DEFAULT 0, -- increases supplier due (we took credit)
    balance NUMERIC(14, 2) NOT NULL, -- remaining due balance after this transaction
    payment_method VARCHAR(50),
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- ==============================================================================
-- 10. ROW LEVEL SECURITY (RLS) HELPER FUNCTIONS
-- ==============================================================================

-- Helper: Get current user's pharmacy_id
CREATE OR REPLACE FUNCTION public.current_pharmacy_id()
RETURNS UUID AS $$
  SELECT pharmacy_id FROM public.profiles WHERE id = auth.uid() LIMIT 1;
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- Helper: Check if current user is Super Admin
CREATE OR REPLACE FUNCTION public.is_super_admin()
RETURNS BOOLEAN AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles WHERE id = auth.uid() AND role = 'super_admin'
  );
$$ LANGUAGE sql STABLE SECURITY DEFINER;

-- ==============================================================================
-- 11. ENABLE RLS ON ALL TABLES
-- ==============================================================================
ALTER TABLE public.pharmacies ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.subscriptions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.global_medicines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.medicines ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.batches ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.medicine_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.suppliers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.invoice_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchases ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.purchase_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.customer_ledgers ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.supplier_ledgers ENABLE ROW LEVEL SECURITY;

-- ==============================================================================
-- 12. RLS POLICIES (TENANT ISOLATION)
-- ==============================================================================

-- Global Medicines: readable by all authenticated users, editable by Super Admin
CREATE POLICY "global_medicines_read" ON public.global_medicines
    FOR SELECT TO authenticated USING (true);
CREATE POLICY "global_medicines_admin_all" ON public.global_medicines
    FOR ALL TO authenticated USING (public.is_super_admin());

-- Pharmacies: users can view and update their own pharmacy
CREATE POLICY "pharmacies_tenant_access" ON public.pharmacies
    FOR ALL TO authenticated USING (id = public.current_pharmacy_id() OR public.is_super_admin());

-- Profiles: users can view members of their pharmacy and update their own
CREATE POLICY "profiles_tenant_access" ON public.profiles
    FOR SELECT TO authenticated USING (pharmacy_id = public.current_pharmacy_id() OR public.is_super_admin());
CREATE POLICY "profiles_self_update" ON public.profiles
    FOR UPDATE TO authenticated USING (id = auth.uid());

-- Tenant Tables Macro Policies: Each pharmacy only sees and manages its own rows
CREATE POLICY "medicines_tenant_isolation" ON public.medicines
    FOR ALL TO authenticated USING (pharmacy_id = public.current_pharmacy_id() OR public.is_super_admin());

CREATE POLICY "batches_tenant_isolation" ON public.batches
    FOR ALL TO authenticated USING (pharmacy_id = public.current_pharmacy_id() OR public.is_super_admin());

CREATE POLICY "medicine_requests_tenant_isolation" ON public.medicine_requests
    FOR ALL TO authenticated USING (pharmacy_id = public.current_pharmacy_id() OR public.is_super_admin());

CREATE POLICY "customers_tenant_isolation" ON public.customers
    FOR ALL TO authenticated USING (pharmacy_id = public.current_pharmacy_id() OR public.is_super_admin());

CREATE POLICY "suppliers_tenant_isolation" ON public.suppliers
    FOR ALL TO authenticated USING (pharmacy_id = public.current_pharmacy_id() OR public.is_super_admin());

CREATE POLICY "invoices_tenant_isolation" ON public.invoices
    FOR ALL TO authenticated USING (pharmacy_id = public.current_pharmacy_id() OR public.is_super_admin());

CREATE POLICY "invoice_items_tenant_isolation" ON public.invoice_items
    FOR ALL TO authenticated USING (pharmacy_id = public.current_pharmacy_id() OR public.is_super_admin());

CREATE POLICY "purchases_tenant_isolation" ON public.purchases
    FOR ALL TO authenticated USING (pharmacy_id = public.current_pharmacy_id() OR public.is_super_admin());

CREATE POLICY "purchase_items_tenant_isolation" ON public.purchase_items
    FOR ALL TO authenticated USING (pharmacy_id = public.current_pharmacy_id() OR public.is_super_admin());

CREATE POLICY "customer_ledgers_tenant_isolation" ON public.customer_ledgers
    FOR ALL TO authenticated USING (pharmacy_id = public.current_pharmacy_id() OR public.is_super_admin());

CREATE POLICY "supplier_ledgers_tenant_isolation" ON public.supplier_ledgers
    FOR ALL TO authenticated USING (pharmacy_id = public.current_pharmacy_id() OR public.is_super_admin());

CREATE POLICY "subscriptions_tenant_isolation" ON public.subscriptions
    FOR SELECT TO authenticated USING (pharmacy_id = public.current_pharmacy_id() OR public.is_super_admin());

-- ==============================================================================
-- 13. ATOMIC POS SALE STORED PROCEDURE (RACE-CONDITION FREE)
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.process_pos_sale(
    p_customer_id UUID,
    p_customer_name VARCHAR,
    p_customer_phone VARCHAR,
    p_subtotal NUMERIC,
    p_discount_type VARCHAR,
    p_discount_amount NUMERIC,
    p_vat_percent NUMERIC,
    p_vat_amount NUMERIC,
    p_grand_total NUMERIC,
    p_paid_amount NUMERIC,
    p_due_amount NUMERIC,
    p_payment_method VARCHAR,
    p_notes TEXT,
    p_items JSONB -- Array of {medicine_id, batch_id, medicine_name, quantity, unit_price, mrp, purchase_price}
)
RETURNS JSONB AS $$
DECLARE
    v_pharmacy_id UUID;
    v_invoice_id UUID;
    v_invoice_no VARCHAR;
    v_item JSONB;
    v_batch_id UUID;
    v_medicine_id UUID;
    v_qty INT;
    v_current_stock INT;
    v_item_total NUMERIC;
    v_new_customer_id UUID := p_customer_id;
    v_current_due NUMERIC := 0;
BEGIN
    -- 1. Identify Tenant
    v_pharmacy_id := public.current_pharmacy_id();
    IF v_pharmacy_id IS NULL THEN
        RAISE EXCEPTION 'Unauthorized: User is not linked to any pharmacy.';
    END IF;

    -- 2. Generate Unique Invoice Number (e.g. INV-YYYYMMDD-XXXX)
    v_invoice_no := 'INV-' || TO_CHAR(NOW(), 'YYYYMMDD') || '-' || LPAD(FLOOR(RANDOM() * 10000)::TEXT, 4, '0');

    -- 3. If Customer Due exists but customer_id is null, create or lookup customer by phone
    IF p_due_amount > 0 AND v_new_customer_id IS NULL THEN
        IF p_customer_phone IS NOT NULL AND p_customer_phone <> '' THEN
            SELECT id INTO v_new_customer_id FROM public.customers 
            WHERE pharmacy_id = v_pharmacy_id AND phone = p_customer_phone LIMIT 1;
            
            IF v_new_customer_id IS NULL THEN
                INSERT INTO public.customers (pharmacy_id, name, phone, current_due)
                VALUES (v_pharmacy_id, COALESCE(p_customer_name, 'Due Customer'), p_customer_phone, 0)
                RETURNING id INTO v_new_customer_id;
            END IF;
        ELSE
            RAISE EXCEPTION 'Customer phone number is required to save due amount.';
        END IF;
    END IF;

    -- 4. Create Invoice Record
    INSERT INTO public.invoices (
        pharmacy_id, invoice_number, customer_id, customer_name, customer_phone,
        subtotal, discount_type, discount_amount, vat_percent, vat_amount,
        grand_total, paid_amount, due_amount, payment_method, notes, served_by
    ) VALUES (
        v_pharmacy_id, v_invoice_no, v_new_customer_id, COALESCE(p_customer_name, 'Walking Customer'), p_customer_phone,
        p_subtotal, p_discount_type, p_discount_amount, p_vat_percent, p_vat_amount,
        p_grand_total, p_paid_amount, p_due_amount, p_payment_method, p_notes, auth.uid()
    ) RETURNING id INTO v_invoice_id;

    -- 5. Loop through Items: Validate stock, deduct stock, insert invoice_items
    FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
    LOOP
        v_batch_id := (v_item->>'batch_id')::UUID;
        v_medicine_id := (v_item->>'medicine_id')::UUID;
        v_qty := (v_item->>'quantity')::INT;
        v_item_total := ((v_item->>'unit_price')::NUMERIC * v_qty);

        -- Check batch stock with row lock
        SELECT stock_qty INTO v_current_stock 
        FROM public.batches 
        WHERE id = v_batch_id AND pharmacy_id = v_pharmacy_id
        FOR UPDATE;

        IF v_current_stock IS NULL OR v_current_stock < v_qty THEN
            RAISE EXCEPTION 'Insufficient stock for medicine % (Available: %, Requested: %)', 
                (v_item->>'medicine_name'), COALESCE(v_current_stock, 0), v_qty;
        END IF;

        -- Deduct stock
        UPDATE public.batches 
        SET stock_qty = stock_qty - v_qty, updated_at = NOW()
        WHERE id = v_batch_id;

        -- Insert item record
        INSERT INTO public.invoice_items (
            pharmacy_id, invoice_id, medicine_id, batch_id, medicine_name,
            batch_number, expiry_date, quantity, unit_price, mrp, purchase_price, total_price
        ) VALUES (
            v_pharmacy_id, v_invoice_id, v_medicine_id, v_batch_id, (v_item->>'medicine_name'),
            (v_item->>'batch_number'), (v_item->>'expiry_date')::DATE, v_qty,
            (v_item->>'unit_price')::NUMERIC, (v_item->>'mrp')::NUMERIC,
            COALESCE((v_item->>'purchase_price')::NUMERIC, 0), v_item_total
        );
    END LOOP;

    -- 6. Update Customer stats & Ledger if applicable
    IF v_new_customer_id IS NOT NULL THEN
        UPDATE public.customers 
        SET total_purchased = total_purchased + p_grand_total,
            current_due = current_due + p_due_amount,
            updated_at = NOW()
        WHERE id = v_new_customer_id
        RETURNING current_due INTO v_current_due;

        -- Log in Customer Ledger if there's due
        IF p_due_amount > 0 THEN
            INSERT INTO public.customer_ledgers (
                pharmacy_id, customer_id, invoice_id, entry_type,
                debit, credit, balance, notes
            ) VALUES (
                v_pharmacy_id, v_new_customer_id, v_invoice_id, 'invoice_due',
                p_due_amount, 0, v_current_due, 'Due from Invoice #' || v_invoice_no
            );
        END IF;
    END IF;

    RETURN jsonb_build_object(
        'success', true,
        'invoice_id', v_invoice_id,
        'invoice_number', v_invoice_no
    );
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- ==============================================================================
-- 14. AUTH HOOK TRIGGER: Auto-create Profile on User Signup
-- ==============================================================================
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
DECLARE
    v_pharmacy_id UUID;
    v_pharmacy_name TEXT;
BEGIN
    -- Check if user metadata passed pharmacy_name
    v_pharmacy_name := NEW.raw_user_meta_data->>'pharmacy_name';
    
    -- If registering as a new store owner, create Pharmacy automatically
    IF v_pharmacy_name IS NOT NULL AND v_pharmacy_name <> '' THEN
        INSERT INTO public.pharmacies (name, phone, email)
        VALUES (v_pharmacy_name, NEW.phone, NEW.email)
        RETURNING id INTO v_pharmacy_id;
    END IF;

    INSERT INTO public.profiles (
        id, 
        pharmacy_id, 
        full_name, 
        phone, 
        role
    ) VALUES (
        NEW.id,
        v_pharmacy_id,
        COALESCE(NEW.raw_user_meta_data->>'full_name', 'Pharmacy Admin'),
        NEW.phone,
        COALESCE(NEW.raw_user_meta_data->>'role', 'owner')
    );

    RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Trigger execution on auth.users
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
