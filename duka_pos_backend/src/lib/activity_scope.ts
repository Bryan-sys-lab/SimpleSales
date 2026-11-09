/**
 * Applies an optional shop filter to an already-resolved owner scope.
 *
 * The filter can narrow access but can never introduce a tenant that was not
 * authorized by the caller's account identity.
 */
export function activityTenantScope(
  authorizedTenantIds: readonly string[],
  requestedTenantId?: string,
): string[] | null {
  const authorized = new Set(authorizedTenantIds);
  if (requestedTenantId && !authorized.has(requestedTenantId)) return null;
  return requestedTenantId ? [requestedTenantId] : [...authorized];
}
