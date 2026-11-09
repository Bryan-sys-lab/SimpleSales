/** Online reports are intentionally bounded to the supported one-year view. */
export const MAX_REPORT_RANGE_DAYS = 366;

export function isReportRangeAllowed(from: Date, to: Date): boolean {
  const start = from.getTime();
  const end = to.getTime();
  return Number.isFinite(start) &&
      Number.isFinite(end) &&
      start < end &&
      end - start <= MAX_REPORT_RANGE_DAYS * 24 * 60 * 60 * 1000;
}
