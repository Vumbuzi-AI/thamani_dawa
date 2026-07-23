CREATE TABLE "organizations"(
    "id" BIGSERIAL NOT NULL,
    "name" VARCHAR(255) NOT NULL,
    "slug" VARCHAR(255) NULL,
    "license_number" VARCHAR(255) NULL,
    "is_active" BOOLEAN NOT NULL DEFAULT TRUE,
    "is_subscription_active" BOOLEAN NOT NULL DEFAULT FALSE,
    "kyc_details" jsonb NOT NULL DEFAULT '{}',
    "name_key" VARCHAR(255) NULL,
    "inserted_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL,
    "updated_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL
);
ALTER TABLE
    "organizations" ADD PRIMARY KEY("id");
COMMENT
ON COLUMN
    "organizations"."name_key" IS 'normalized (lowercased, diacritics/punctuation stripped) form of the slug, unique-indexed to catch near-duplicate org names distinct from the slug uniqueness check';
CREATE TABLE "sites"(
    "id" BIGSERIAL NOT NULL,
    "organization_id" BIGINT NOT NULL,
    "name" VARCHAR(255) NOT NULL,
    "site_type" VARCHAR(255) NOT NULL,
    "gln" VARCHAR(255) NULL,
    "address" VARCHAR(255) NULL,
    "lat" DOUBLE PRECISION NULL,
    "long" DOUBLE PRECISION NULL,
    "is_active" BOOLEAN NOT NULL DEFAULT TRUE,
    "inserted_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL,
    "updated_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL
);
ALTER TABLE
    "sites" ADD PRIMARY KEY("id");
CREATE TABLE "users"(
    "id" BIGSERIAL NOT NULL,
    "organization_id" BIGINT NOT NULL,
    "site_id" BIGINT NULL,
    "invited_by_id" BIGINT NULL,
    "name" VARCHAR(255) NOT NULL,
    "email" VARCHAR(255) NOT NULL,
    "hashed_password" VARCHAR(255) NULL,
    "hashed_pin" VARCHAR(255) NULL,
    "role" VARCHAR(255) NOT NULL,
    "is_active" BOOLEAN NOT NULL DEFAULT TRUE,
    "last_logged_in_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL,
    "last_logged_out_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL,
    "inserted_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL,
    "updated_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL
);
ALTER TABLE
    "users" ADD PRIMARY KEY("id");
COMMENT
ON COLUMN
    "users"."hashed_pin" IS 'supports quick PIN-based re-auth at shared pharmacy/lab terminals, separate from hashed_password';
CREATE TABLE "user_login_sessions"(
    "id" BIGSERIAL NOT NULL,
    "user_id" BIGINT NOT NULL,
    "logged_in_at" TIMESTAMP(0) WITHOUT TIME ZONE NOT NULL,
    "logged_out_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL,
    "inserted_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL,
    "updated_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL
);
ALTER TABLE
    "user_login_sessions" ADD PRIMARY KEY("id");
CREATE TABLE "patients"(
    "id" BIGSERIAL NOT NULL,
    "organization_id" BIGINT NOT NULL,
    "full_name" VARCHAR(255) NOT NULL,
    "date_of_birth" DATE NOT NULL,
    "gender" VARCHAR(255) NOT NULL,
    "phone" VARCHAR(255) NOT NULL,
    "national_id" VARCHAR(255) NULL,
    "gsrn" BIGINT NOT NULL,
    "inserted_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL,
    "updated_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL
);
ALTER TABLE
    "patients" ADD PRIMARY KEY("id");
CREATE TABLE "patient_visits"(
    "id" BIGSERIAL NOT NULL,
    "organization_id" BIGINT NOT NULL,
    "patient_id" BIGINT NOT NULL,
    "site_id" BIGINT NOT NULL,
    "user_id" BIGINT NOT NULL,
    "visit_type" VARCHAR(255) NOT NULL,
    "inserted_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL,
    "updated_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL
);
ALTER TABLE
    "patient_visits" ADD PRIMARY KEY("id");
COMMENT
ON COLUMN
    "patient_visits"."user_id" IS 'the staff member who served this patient at this encounter';
CREATE TABLE "products"(
    "id" BIGSERIAL NOT NULL,
    "organization_id" BIGINT NOT NULL,
    "generic_name" VARCHAR(255) NULL,
    "brand_name" VARCHAR(255) NULL,
    "category" VARCHAR(255) NULL,
    "uom" VARCHAR(255) NULL,
    "gtin" VARCHAR(255) NULL,
    "is_otc" BOOLEAN NOT NULL DEFAULT FALSE,
    "is_dangerous_drug" BOOLEAN NOT NULL DEFAULT FALSE,
    "reorder_level" INTEGER NULL,
    "price" INTEGER NOT NULL,
    "inserted_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL,
    "updated_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL
);
ALTER TABLE
    "products" ADD PRIMARY KEY("id");
COMMENT
ON TABLE
    "products" IS 'shared with the pharmacy side — org-wide catalog, not site-scoped. Included here because lab consumables/reagents are also products.';
CREATE TABLE "suppliers"(
    "id" BIGSERIAL NOT NULL,
    "organization_id" BIGINT NOT NULL,
    "name" VARCHAR(255) NOT NULL,
    "contact" VARCHAR(255) NULL,
    "phone" VARCHAR(255) NULL,
    "email" VARCHAR(255) NULL,
    "gln" VARCHAR(255) NULL,
    "location" VARCHAR(255) NULL,
    "is_active" BOOLEAN NOT NULL DEFAULT TRUE,
    "inserted_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL,
    "updated_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL
);
ALTER TABLE
    "suppliers" ADD PRIMARY KEY("id");
CREATE TABLE "batches"(
    "id" BIGSERIAL NOT NULL,
    "organization_id" BIGINT NOT NULL,
    "product_id" BIGINT NOT NULL,
    "site_id" BIGINT NOT NULL,
    "gtin" VARCHAR(255) NOT NULL,
    "batch_no" VARCHAR(255) NOT NULL,
    "serial" VARCHAR(255) NULL,
    "manufacturer" VARCHAR(255) NULL,
    "manufacture_date" DATE NULL,
    "expiry_date" DATE NOT NULL,
    "quantity" INTEGER NOT NULL,
    "remaining_quantity" INTEGER NOT NULL,
    "cost_per_unit" NUMERIC NULL,
    "supplier_id" BIGINT NULL,
    "received_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL,
    "approver_id" BIGINT NULL,
    "inserted_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL,
    "updated_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL
);
ALTER TABLE
    "batches" ADD PRIMARY KEY("id");
COMMENT
ON TABLE
    "batches" IS 'the one unified stock table for both pharmacy and lab — a reagent/consumable batch is a row here just like a drug batch. Included here because lab_consumable_usage draws from it.';
COMMENT
ON COLUMN
    "batches"."approver_id" IS 'the staff member who confirmed receipt of this batch — receiving and approving are the same single step, so there is no separate received_by_id; approval state is just "approver_id is not null", no separate is_approved flag either';
CREATE TABLE "lab_test_categories"(
    "id" BIGSERIAL NOT NULL,
    "organization_id" BIGINT NOT NULL,
    "name" VARCHAR(255) NOT NULL,
    "description" TEXT NULL,
    "display_order" INTEGER NOT NULL DEFAULT 0,
    "inserted_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL,
    "updated_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL
);
ALTER TABLE
    "lab_test_categories" ADD PRIMARY KEY("id");
CREATE TABLE "lab_tests"(
    "id" BIGSERIAL NOT NULL,
    "organization_id" BIGINT NOT NULL,
    "name" VARCHAR(255) NOT NULL,
    "price" NUMERIC NOT NULL,
    "is_active" BOOLEAN NOT NULL DEFAULT TRUE,
    "field_definitions" jsonb NOT NULL,
    "category_id" BIGINT NOT NULL,
    "inserted_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL,
    "updated_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL
);
ALTER TABLE
    "lab_tests" ADD PRIMARY KEY("id");
CREATE TABLE "lab_orders"(
    "id" BIGSERIAL NOT NULL,
    "organization_id" BIGINT NOT NULL,
    "site_id" BIGINT NOT NULL,
    "patient_visit_id" BIGINT NOT NULL,
    "prescriber_name" VARCHAR(255) NULL,
    "ordered_by_id" BIGINT NULL,
    "urgency" VARCHAR(255) NULL,
    "payment_type" VARCHAR(255) NULL,
    "has_paid" BOOLEAN NOT NULL DEFAULT FALSE,
    "total_amount" NUMERIC NULL,
    "status" VARCHAR(255) NOT NULL DEFAULT 'pending',
    "lab_report" TEXT NULL,
    "test_findings" TEXT NULL,
    "lab_request" TEXT NULL,
    "referring_facility" TEXT NULL,
    "referring_doctor" TEXT NULL,
    "referred_date" DATE NULL,
    "inserted_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL,
    "updated_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL
);
ALTER TABLE
    "lab_orders" ADD PRIMARY KEY("id");
COMMENT
ON COLUMN
    "lab_orders"."patient_visit_id" IS 'the only path to the patient — every lab order exists in the context of one patient visit, no separate/denormalized patient_id';
CREATE TABLE "lab_order_results"(
    "id" BIGSERIAL NOT NULL,
    "organization_id" BIGINT NOT NULL,
    "lab_order_id" BIGINT NOT NULL,
    "lab_test_id" BIGINT NOT NULL,
    "template_id" INTEGER NULL,
    "results" jsonb NOT NULL DEFAULT '{}',
    "status" VARCHAR(255) NOT NULL DEFAULT 'pending',
    "sample_collected_on" DATE NULL,
    "test_performed_on" DATE NULL,
    "performed_by_id" BIGINT NULL,
    "collected_by_id" BIGINT NULL,
    "verified_by_id" BIGINT NULL,
    "collection_notes" TEXT NULL,
    "sample_type" VARCHAR(255) NOT NULL,
    "inserted_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL,
    "updated_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL
);
ALTER TABLE
    "lab_order_results" ADD PRIMARY KEY("id");
COMMENT
ON COLUMN
    "lab_order_results"."template_id" IS 'no matching lab_test_templates table exists yet — currently a bare integer with no computation behind it';
COMMENT
ON COLUMN
    "lab_order_results"."sample_type" IS 'coded specimen type (blood/urine/stool/swab) — distinct from collection_notes, which is free text about how/where it was collected';
CREATE UNIQUE INDEX "lab_order_results_unique_test_per_order" ON "lab_order_results"("lab_order_id", "lab_test_id");
CREATE TABLE "lab_consumable_usage"(
    "id" BIGSERIAL NOT NULL,
    "organization_id" BIGINT NOT NULL,
    "lab_order_id" BIGINT NULL,
    "batch_id" BIGINT NOT NULL,
    "quantity" INTEGER NOT NULL,
    "used_by_id" BIGINT NULL,
    "purpose" VARCHAR(255) NULL,
    "used_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL,
    "inserted_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL,
    "updated_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL
);
ALTER TABLE
    "lab_consumable_usage" ADD PRIMARY KEY("id");
COMMENT
ON COLUMN
    "lab_consumable_usage"."lab_order_id" IS 'nullable by design — a reagent draw does not have to tie back to a specific order (e.g. calibration/QC usage)';
ALTER TABLE
    "sites" ADD CONSTRAINT "sites_organization_id_foreign" FOREIGN KEY("organization_id") REFERENCES "organizations"("id") ON DELETE CASCADE;
ALTER TABLE
    "users" ADD CONSTRAINT "users_organization_id_foreign" FOREIGN KEY("organization_id") REFERENCES "organizations"("id") ON DELETE CASCADE;
ALTER TABLE
    "users" ADD CONSTRAINT "users_site_id_foreign" FOREIGN KEY("site_id") REFERENCES "sites"("id") ON DELETE SET NULL;
ALTER TABLE
    "users" ADD CONSTRAINT "users_invited_by_id_foreign" FOREIGN KEY("invited_by_id") REFERENCES "users"("id") ON DELETE SET NULL;
ALTER TABLE
    "user_login_sessions" ADD CONSTRAINT "user_login_sessions_user_id_foreign" FOREIGN KEY("user_id") REFERENCES "users"("id") ON DELETE CASCADE;
ALTER TABLE
    "patients" ADD CONSTRAINT "patients_organization_id_foreign" FOREIGN KEY("organization_id") REFERENCES "organizations"("id") ON DELETE CASCADE;
ALTER TABLE
    "patient_visits" ADD CONSTRAINT "patient_visits_organization_id_foreign" FOREIGN KEY("organization_id") REFERENCES "organizations"("id") ON DELETE CASCADE;
ALTER TABLE
    "patient_visits" ADD CONSTRAINT "patient_visits_patient_id_foreign" FOREIGN KEY("patient_id") REFERENCES "patients"("id") ON DELETE CASCADE;
ALTER TABLE
    "patient_visits" ADD CONSTRAINT "patient_visits_site_id_foreign" FOREIGN KEY("site_id") REFERENCES "sites"("id") ON DELETE CASCADE;
ALTER TABLE
    "patient_visits" ADD CONSTRAINT "patient_visits_user_id_foreign" FOREIGN KEY("user_id") REFERENCES "users"("id") ON DELETE RESTRICT;
ALTER TABLE
    "products" ADD CONSTRAINT "products_organization_id_foreign" FOREIGN KEY("organization_id") REFERENCES "organizations"("id") ON DELETE CASCADE;
ALTER TABLE
    "suppliers" ADD CONSTRAINT "suppliers_organization_id_foreign" FOREIGN KEY("organization_id") REFERENCES "organizations"("id") ON DELETE CASCADE;
ALTER TABLE
    "batches" ADD CONSTRAINT "batches_organization_id_foreign" FOREIGN KEY("organization_id") REFERENCES "organizations"("id") ON DELETE CASCADE;
ALTER TABLE
    "batches" ADD CONSTRAINT "batches_product_id_foreign" FOREIGN KEY("product_id") REFERENCES "products"("id") ON DELETE CASCADE;
ALTER TABLE
    "batches" ADD CONSTRAINT "batches_site_id_foreign" FOREIGN KEY("site_id") REFERENCES "sites"("id") ON DELETE CASCADE;
ALTER TABLE
    "batches" ADD CONSTRAINT "batches_supplier_id_foreign" FOREIGN KEY("supplier_id") REFERENCES "suppliers"("id") ON DELETE SET NULL;
ALTER TABLE
    "batches" ADD CONSTRAINT "batches_approver_id_foreign" FOREIGN KEY("approver_id") REFERENCES "users"("id") ON DELETE SET NULL;
ALTER TABLE
    "lab_test_categories" ADD CONSTRAINT "lab_test_categories_organization_id_foreign" FOREIGN KEY("organization_id") REFERENCES "organizations"("id") ON DELETE CASCADE;
ALTER TABLE
    "lab_tests" ADD CONSTRAINT "lab_tests_organization_id_foreign" FOREIGN KEY("organization_id") REFERENCES "organizations"("id") ON DELETE CASCADE;
ALTER TABLE
    "lab_tests" ADD CONSTRAINT "lab_tests_category_id_foreign" FOREIGN KEY("category_id") REFERENCES "lab_test_categories"("id") ON DELETE RESTRICT;
ALTER TABLE
    "lab_orders" ADD CONSTRAINT "lab_orders_organization_id_foreign" FOREIGN KEY("organization_id") REFERENCES "organizations"("id") ON DELETE CASCADE;
ALTER TABLE
    "lab_orders" ADD CONSTRAINT "lab_orders_site_id_foreign" FOREIGN KEY("site_id") REFERENCES "sites"("id") ON DELETE CASCADE;
ALTER TABLE
    "lab_orders" ADD CONSTRAINT "lab_orders_patient_visit_id_foreign" FOREIGN KEY("patient_visit_id") REFERENCES "patient_visits"("id") ON DELETE RESTRICT;
ALTER TABLE
    "lab_orders" ADD CONSTRAINT "lab_orders_ordered_by_id_foreign" FOREIGN KEY("ordered_by_id") REFERENCES "users"("id") ON DELETE SET NULL;
ALTER TABLE
    "lab_order_results" ADD CONSTRAINT "lab_order_results_organization_id_foreign" FOREIGN KEY("organization_id") REFERENCES "organizations"("id") ON DELETE CASCADE;
ALTER TABLE
    "lab_order_results" ADD CONSTRAINT "lab_order_results_lab_order_id_foreign" FOREIGN KEY("lab_order_id") REFERENCES "lab_orders"("id") ON DELETE CASCADE;
ALTER TABLE
    "lab_order_results" ADD CONSTRAINT "lab_order_results_lab_test_id_foreign" FOREIGN KEY("lab_test_id") REFERENCES "lab_tests"("id") ON DELETE RESTRICT;
ALTER TABLE
    "lab_order_results" ADD CONSTRAINT "lab_order_results_performed_by_id_foreign" FOREIGN KEY("performed_by_id") REFERENCES "users"("id") ON DELETE SET NULL;
ALTER TABLE
    "lab_order_results" ADD CONSTRAINT "lab_order_results_collected_by_id_foreign" FOREIGN KEY("collected_by_id") REFERENCES "users"("id") ON DELETE SET NULL;
ALTER TABLE
    "lab_order_results" ADD CONSTRAINT "lab_order_results_verified_by_id_foreign" FOREIGN KEY("verified_by_id") REFERENCES "users"("id");
ALTER TABLE
    "lab_consumable_usage" ADD CONSTRAINT "lab_consumable_usage_organization_id_foreign" FOREIGN KEY("organization_id") REFERENCES "organizations"("id") ON DELETE CASCADE;
ALTER TABLE
    "lab_consumable_usage" ADD CONSTRAINT "lab_consumable_usage_lab_order_id_foreign" FOREIGN KEY("lab_order_id") REFERENCES "lab_orders"("id") ON DELETE SET NULL;
ALTER TABLE
    "lab_consumable_usage" ADD CONSTRAINT "lab_consumable_usage_batch_id_foreign" FOREIGN KEY("batch_id") REFERENCES "batches"("id") ON DELETE CASCADE;
ALTER TABLE
    "lab_consumable_usage" ADD CONSTRAINT "lab_consumable_usage_used_by_id_foreign" FOREIGN KEY("used_by_id") REFERENCES "users"("id") ON DELETE SET NULL;
