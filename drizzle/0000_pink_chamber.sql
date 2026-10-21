CREATE TYPE "public"."certificate_type" AS ENUM('gas', 'eicr', 'epc', 'legionella', 'fire_risk');--> statement-breakpoint
CREATE TYPE "public"."compliance_state" AS ENUM('current', 'chasing', 'waiting', 'in_review', 'escalated', 'ended');--> statement-breakpoint
CREATE TYPE "public"."crm_source" AS ENUM('reapit', 'alto', 'iamproperty', 'manual');--> statement-breakpoint
CREATE TYPE "public"."document_review_state" AS ENUM('pending', 'approved', 'rejected', 'unreadable');--> statement-breakpoint
CREATE TABLE "agency" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"name" text NOT NULL,
	"active_crm" "crm_source" DEFAULT 'manual' NOT NULL,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "agency_certificate_setting" (
	"agency_id" uuid NOT NULL,
	"type" "certificate_type" NOT NULL,
	"chase_window_days" integer DEFAULT 60 NOT NULL,
	"escalate_after_unanswered" integer DEFAULT 3 NOT NULL,
	CONSTRAINT "agency_certificate_setting_agency_id_type_pk" PRIMARY KEY("agency_id","type")
);
--> statement-breakpoint
CREATE TABLE "certificate_document" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"agency_id" uuid NOT NULL,
	"compliance_item_id" uuid NOT NULL,
	"storage_key" text NOT NULL,
	"original_filename" text,
	"content_hash" text NOT NULL,
	"issued_on" date,
	"expires_on" date,
	"extracted_data" jsonb,
	"extraction_confidence" numeric(4, 3),
	"review_state" "document_review_state" DEFAULT 'pending' NOT NULL,
	"reviewed_by" uuid,
	"reviewed_at" timestamp with time zone,
	"rejection_reason" text,
	"received_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "compliance_item" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"agency_id" uuid NOT NULL,
	"property_id" uuid NOT NULL,
	"type" "certificate_type" NOT NULL,
	"state" "compliance_state" DEFAULT 'current' NOT NULL,
	"expires_on" date,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL,
	"updated_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "landlord" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"agency_id" uuid NOT NULL,
	"external_source" "crm_source",
	"external_id" text,
	"name" text NOT NULL,
	"email" text,
	"phone" text,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
CREATE TABLE "property" (
	"id" uuid PRIMARY KEY DEFAULT gen_random_uuid() NOT NULL,
	"agency_id" uuid NOT NULL,
	"landlord_id" uuid NOT NULL,
	"external_source" "crm_source",
	"external_id" text,
	"address_line1" text NOT NULL,
	"address_line2" text,
	"city" text,
	"postcode" text NOT NULL,
	"postcode_normalised" text GENERATED ALWAYS AS (upper(replace(postcode, ' ', ''))) STORED,
	"managed_start" date,
	"managed_end" date,
	"created_at" timestamp with time zone DEFAULT now() NOT NULL
);
--> statement-breakpoint
ALTER TABLE "agency_certificate_setting" ADD CONSTRAINT "agency_certificate_setting_agency_id_agency_id_fk" FOREIGN KEY ("agency_id") REFERENCES "public"."agency"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "certificate_document" ADD CONSTRAINT "certificate_document_agency_id_agency_id_fk" FOREIGN KEY ("agency_id") REFERENCES "public"."agency"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "certificate_document" ADD CONSTRAINT "certificate_document_compliance_item_id_compliance_item_id_fk" FOREIGN KEY ("compliance_item_id") REFERENCES "public"."compliance_item"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "compliance_item" ADD CONSTRAINT "compliance_item_agency_id_agency_id_fk" FOREIGN KEY ("agency_id") REFERENCES "public"."agency"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "compliance_item" ADD CONSTRAINT "compliance_item_property_id_property_id_fk" FOREIGN KEY ("property_id") REFERENCES "public"."property"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "landlord" ADD CONSTRAINT "landlord_agency_id_agency_id_fk" FOREIGN KEY ("agency_id") REFERENCES "public"."agency"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "property" ADD CONSTRAINT "property_agency_id_agency_id_fk" FOREIGN KEY ("agency_id") REFERENCES "public"."agency"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
ALTER TABLE "property" ADD CONSTRAINT "property_landlord_id_landlord_id_fk" FOREIGN KEY ("landlord_id") REFERENCES "public"."landlord"("id") ON DELETE no action ON UPDATE no action;--> statement-breakpoint
CREATE UNIQUE INDEX "certificate_document_hash_unique" ON "certificate_document" USING btree ("agency_id","content_hash");--> statement-breakpoint
CREATE INDEX "certificate_document_item_idx" ON "certificate_document" USING btree ("compliance_item_id","received_at");--> statement-breakpoint
CREATE INDEX "certificate_document_review_idx" ON "certificate_document" USING btree ("agency_id","review_state","received_at");--> statement-breakpoint
CREATE UNIQUE INDEX "compliance_item_unique" ON "compliance_item" USING btree ("property_id","type");--> statement-breakpoint
CREATE INDEX "compliance_item_dashboard_idx" ON "compliance_item" USING btree ("agency_id","state","expires_on");--> statement-breakpoint
CREATE INDEX "compliance_item_missing_expiry_idx" ON "compliance_item" USING btree ("agency_id") WHERE expires_on is null;--> statement-breakpoint
CREATE UNIQUE INDEX "landlord_external_unique" ON "landlord" USING btree ("agency_id","external_source","external_id");--> statement-breakpoint
CREATE UNIQUE INDEX "property_external_unique" ON "property" USING btree ("agency_id","external_source","external_id");--> statement-breakpoint
CREATE INDEX "property_postcode_idx" ON "property" USING btree ("agency_id","postcode_normalised");