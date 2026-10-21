import { sql } from 'drizzle-orm';
import {
  pgTable, pgEnum, uuid, text, timestamp, date, jsonb,
  numeric, integer, uniqueIndex, index, primaryKey,
} from 'drizzle-orm/pg-core';

export const certificateType = pgEnum('certificate_type', [
  'gas', 'eicr', 'epc', 'legionella', 'fire_risk',
]);

export const complianceState = pgEnum('compliance_state', [
  'current', 'chasing', 'waiting', 'in_review', 'escalated', 'ended',
]);

export const crmSource = pgEnum('crm_source', [
  'reapit', 'alto', 'iamproperty', 'manual',
]);

export const documentReviewState = pgEnum('document_review_state', [
  'pending',      // extracted, waiting for a human
  'approved',     // human confirmed, expiry copied to the compliance item
  'rejected',     // human looked and said no, reason recorded
  'unreadable',   // extraction confidence too low to show anyone
]);

export const agency = pgTable('agency', {
  id: uuid('id').primaryKey().defaultRandom(),
  name: text('name').notNull(),
  // The CRM you push approved data back INTO today. Not where any given row
  // originally came from, which is why landlord and property carry their own
  // externalSource.
  activeCrm: crmSource('active_crm').notNull().default('manual'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
});

// A row existing here means "this agency chases this type". No row means the
// agency handles it in house and LetTrack leaves it alone.
export const agencyCertificateSetting = pgTable('agency_certificate_setting', {
  agencyId: uuid('agency_id').notNull().references(() => agency.id),
  type: certificateType('type').notNull(),
  chaseWindowDays: integer('chase_window_days').notNull().default(60),
  escalateAfterUnanswered: integer('escalate_after_unanswered').notNull().default(3),
}, (t) => ({
  // No separate id. The pair identifies the row, and making it the primary key
  // makes two conflicting gas settings impossible.
  pk: primaryKey({ columns: [t.agencyId, t.type] }),
}));

export const landlord = pgTable('landlord', {
  id: uuid('id').primaryKey().defaultRandom(),
  agencyId: uuid('agency_id').notNull().references(() => agency.id),
  externalSource: crmSource('external_source'),
  externalId: text('external_id'),
  name: text('name').notNull(),
  email: text('email'),
  phone: text('phone'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
}, (t) => ({
  externalUnique: uniqueIndex('landlord_external_unique')
    .on(t.agencyId, t.externalSource, t.externalId),
}));

export const property = pgTable('property', {
  id: uuid('id').primaryKey().defaultRandom(),
  agencyId: uuid('agency_id').notNull().references(() => agency.id),
  // Single landlord only in v1. Joint landlords need a join table; the
  // limitation is recorded in ADR 001.
  landlordId: uuid('landlord_id').notNull().references(() => landlord.id),
  externalSource: crmSource('external_source'),
  externalId: text('external_id'),
  addressLine1: text('address_line1').notNull(),
  addressLine2: text('address_line2'),
  city: text('city'),
  postcode: text('postcode').notNull(),
  // Postgres computes this on write and nothing else can set it.
  // Matching uses this column, display uses postcode.
  postcodeNormalised: text('postcode_normalised').generatedAlwaysAs(
    sql`upper(replace(postcode, ' ', ''))`,
  ),
  managedStart: date('managed_start'),
  managedEnd: date('managed_end'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
}, (t) => ({
  externalUnique: uniqueIndex('property_external_unique')
    .on(t.agencyId, t.externalSource, t.externalId),
  byPostcode: index('property_postcode_idx').on(t.agencyId, t.postcodeNormalised),
}));

// The obligation. Exists whether or not a document does, which is why this is
// separate from certificate_document.
export const complianceItem = pgTable('compliance_item', {
  id: uuid('id').primaryKey().defaultRandom(),
  // Derivable through property, stored anyway: every tenant-scoped query
  // filters on it, and it lets the dashboard index start with agency_id
  // without a join. Deliberate denormalisation.
  agencyId: uuid('agency_id').notNull().references(() => agency.id),
  propertyId: uuid('property_id').notNull().references(() => property.id),
  type: certificateType('type').notNull(),
  state: complianceState('state').notNull().default('current'),
  // Copied from the approved certificate_document. The authority lives on the
  // document; this copy makes the dashboard an index-only read. The approve
  // path must write both inside one transaction. The database does not enforce
  // that, so it needs a test.
  expiresOn: date('expires_on'),
  createdAt: timestamp('created_at', { withTimezone: true }).notNull().defaultNow(),
  updatedAt: timestamp('updated_at', { withTimezone: true }).notNull().defaultNow(),
}, (t) => ({
  oneTypePerProperty: uniqueIndex('compliance_item_unique').on(t.propertyId, t.type),
  dashboard: index('compliance_item_dashboard_idx')
    .on(t.agencyId, t.state, t.expiresOn),
  // Partial index: holds only the rows with no expiry date, so it stays tiny.
  // Feeds the "missing dates" list. The chase loop must exclude these rows,
  // since a chase window cannot be computed from a null.
  missingExpiry: index('compliance_item_missing_expiry_idx')
    .on(t.agencyId)
    .where(sql`expires_on is null`),
}));

export const certificateDocument = pgTable('certificate_document', {
  id: uuid('id').primaryKey().defaultRandom(),
  agencyId: uuid('agency_id').notNull().references(() => agency.id),
  complianceItemId: uuid('compliance_item_id').notNull().references(() => complianceItem.id),
  storageKey: text('storage_key').notNull(),
  originalFilename: text('original_filename'),
  // SHA-256 of the file bytes. Identical files hash the same whatever they are
  // named, so the same certificate arriving twice is rejected by the database
  // rather than by someone noticing.
  contentHash: text('content_hash').notNull(),
  issuedOn: date('issued_on'),
  expiresOn: date('expires_on'),
  extractedData: jsonb('extracted_data'),
  extractionConfidence: numeric('extraction_confidence', { precision: 4, scale: 3 }),
  reviewState: documentReviewState('review_state').notNull().default('pending'),
  // Becomes a foreign key to user once that table exists, in slice 3.
  reviewedBy: uuid('reviewed_by'),
  reviewedAt: timestamp('reviewed_at', { withTimezone: true }),
  rejectionReason: text('rejection_reason'),
  receivedAt: timestamp('received_at', { withTimezone: true }).notNull().defaultNow(),
}, (t) => ({
  duplicateFile: uniqueIndex('certificate_document_hash_unique')
    .on(t.agencyId, t.contentHash),
  byItem: index('certificate_document_item_idx')
    .on(t.complianceItemId, t.receivedAt),
  // The review queue: oldest pending first.
  reviewQueue: index('certificate_document_review_idx')
    .on(t.agencyId, t.reviewState, t.receivedAt),
}));