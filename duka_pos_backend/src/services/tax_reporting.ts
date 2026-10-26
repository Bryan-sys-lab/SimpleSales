/** Deployment-level tax reporting gate.
 *
 * KRA/eTIMS is deliberately off for this release. Risiti is the planned
 * server-side provider; its API key and merchant onboarding stay off the
 * mobile client and are only usable after deployment approval.
 */
export const TAX_REPORTING_PROVIDER = 'risiti';
export const TAX_PROVIDER_DISPLAY_NAME = 'Risiti by PesaStack Limited';

export function taxReportingActivated(): boolean {
  return process.env.TAX_REPORTING_ACTIVATED === 'true';
}

export function taxReportingStatus() {
  const activated = taxReportingActivated();
  return {
    provider: TAX_REPORTING_PROVIDER,
    provider_name: TAX_PROVIDER_DISPLAY_NAME,
    tax_reporting_activated: activated,
    // This mirrors the deployment gate. Local/dev deployments keep the
    // variable false; when production is approved, status must not lie about
    // the state the server is actually willing to use.
    kra_activated: activated,
    local_vat_reporting: true,
  };
}
