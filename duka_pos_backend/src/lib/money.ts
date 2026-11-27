export function toMinorUnits(value: number): number {
  if (!Number.isFinite(value)) throw new RangeError('Amount must be finite');
  const scaled = value * 100;
  const minor = Math.round(scaled);
  if (!Number.isSafeInteger(minor) || Math.abs(scaled - minor) > 1e-7) {
    throw new RangeError('Amount must have no more than two decimal places');
  }
  return minor;
}

export function toMajorUnits(minor: number): number {
  if (!Number.isSafeInteger(minor)) throw new RangeError('Amount is out of range');
  return minor / 100;
}

export function wholeShillingsFromMinor(minor: number): number {
  if (!Number.isSafeInteger(minor) || minor <= 0 || minor % 100 !== 0) {
    throw new RangeError('PayHero requires a positive whole-shilling amount');
  }
  return minor / 100;
}
