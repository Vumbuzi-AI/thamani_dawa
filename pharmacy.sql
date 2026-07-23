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
ON COLUMN
    "batches"."approver_id" IS 'the staff member who confirmed receipt of this batch — receiving and approving are the same single step, so there is no separate received_by_id; approval state is just "approver_id is not null", no separate is_approved flag either';
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
CREATE TABLE "prescriptions"(
    "id" BIGSERIAL NOT NULL,
    "organization_id" BIGINT NOT NULL,
    "user_id" BIGINT NULL,
    "patient_visit_id" BIGINT NULL,
    "payment_type" VARCHAR(255) NULL,
    "has_paid" BOOLEAN NOT NULL DEFAULT FALSE,
    "total_amount" NUMERIC NULL,
    "status" VARCHAR(255) NOT NULL DEFAULT 'pending',
    "notes" TEXT NULL,
    "doctors_note" TEXT NULL,
    "is_external" BOOLEAN NOT NULL DEFAULT FALSE,
    "source_facility" TEXT NULL,
    "referring_doctor" TEXT NULL,
    "referral_date" DATE NULL,
    "inserted_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL,
    "updated_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL
);
ALTER TABLE
    "prescriptions" ADD PRIMARY KEY("id");
COMMENT
ON COLUMN
    "prescriptions"."user_id" IS 'the pharmacist who entered it';
COMMENT
ON COLUMN
    "prescriptions"."patient_visit_id" IS 'nullable at the DB level, but required by the application changeset — every prescription is expected to have a visit in practice';
CREATE TABLE "prescription_items"(
    "id" BIGSERIAL NOT NULL,
    "organization_id" BIGINT NOT NULL,
    "prescription_id" BIGINT NOT NULL,
    "product_id" BIGINT NOT NULL,
    "quantity_prescribed" INTEGER NOT NULL,
    "dosage_instructions" VARCHAR(255) NULL,
    "frequency" VARCHAR(255) NULL,
    "duration_in_days" INTEGER NULL,
    "route_of_administration" VARCHAR(255) NULL,
    "quantity_dispensed" INTEGER NOT NULL DEFAULT 0,
    "is_verified" BOOLEAN NOT NULL DEFAULT FALSE,
    "inserted_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL,
    "updated_at" TIMESTAMP(0) WITHOUT TIME ZONE NULL
);
ALTER TABLE
    "prescription_items" ADD PRIMARY KEY("id");
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
    "prescriptions" ADD CONSTRAINT "prescriptions_organization_id_foreign" FOREIGN KEY("organization_id") REFERENCES "organizations"("id") ON DELETE CASCADE;
ALTER TABLE
    "prescriptions" ADD CONSTRAINT "prescriptions_user_id_foreign" FOREIGN KEY("user_id") REFERENCES "users"("id") ON DELETE SET NULL;
ALTER TABLE
    "prescriptions" ADD CONSTRAINT "prescriptions_patient_visit_id_foreign" FOREIGN KEY("patient_visit_id") REFERENCES "patient_visits"("id") ON DELETE RESTRICT;
ALTER TABLE
    "prescription_items" ADD CONSTRAINT "prescription_items_organization_id_foreign" FOREIGN KEY("organization_id") REFERENCES "organizations"("id") ON DELETE CASCADE;
ALTER TABLE
    "prescription_items" ADD CONSTRAINT "prescription_items_prescription_id_foreign" FOREIGN KEY("prescription_id") REFERENCES "prescriptions"("id") ON DELETE CASCADE;
ALTER TABLE
    "prescription_items" ADD CONSTRAINT "prescription_items_product_id_foreign" FOREIGN KEY("product_id") REFERENCES "products"("id") ON DELETE CASCADE;
