export const COMMERCIAL_CONSENT_SCOPES = [
  'business_activity',
  'product_demand',
  'availability',
  'procurement_patterns',
  'operating_cost_bands',
  'digitisation_metrics',
] as const;

export type CommercialConsentScope = (typeof COMMERCIAL_CONSENT_SCOPES)[number];

export function isCommercialConsentScope(value: string): value is CommercialConsentScope {
  return (COMMERCIAL_CONSENT_SCOPES as readonly string[]).includes(value);
}
