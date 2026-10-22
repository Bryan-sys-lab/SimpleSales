// Money across the API boundary.
//
// ## WHY MINOR UNITS COME IN AND MAJOR UNITS GO IN
//
// A till keeps its ledger in integer minor units — the cents. It counts in
// them because a ledger that counts in floats does not reconcile: 40.55
// shillings as a double is 40.549999999999997, and a drawer that is a cent
// out is a drawer nobody can reconcile.
//
// The columns store DECIMAL major units, which is what a reader of the
// database wants to see ("this product costs 40.55"). So the two meet here,
// ONCE, and the conversion is exact: `Decimal(minor) / 100` in decimal
// arithmetic is 40.55 for 4055, with no rounding anywhere.
//
// The other direction — minor units back out to the app — is the same
// conversion the other way, and it is the one the read endpoints use: the
// app's figures are read as minor units, so the endpoints answer in them.
//
// ## WHY NOT FLOATS
//
// A float cannot hold 40.55 shillings. It holds something very close to it,
// and "very close" is a figure that does not reconcile against a drawer. The
// conversions below go through `Prisma.Decimal`, which is exact, and the only
// rounding in the whole path is the one at the far end, where a value that
// somehow carries a third decimal is rounded rather than truncated.

import { Prisma } from '@prisma/client';

/** Minor units to the major-unit DECIMAL the columns store. */
export function majorFromMinor(minor: number): Prisma.Decimal {
  return new Prisma.Decimal(minor).div(100);
}

/**
 * Major units back to minor units.
 *
 * The stored value is a DECIMAL with two places, so the multiplication is
 * exact and the result is an integer. `Math.round` is the belt to that
 * braces: a value that somehow carries a third decimal is rounded rather
 * than truncated, so 40.554 becomes 4055 and not 4055.4.
 */
export function minorFromMajor(major: Prisma.Decimal | number | null | undefined): number {
  if (major === null || major === undefined) return 0;
  const value = major instanceof Prisma.Decimal ? major : new Prisma.Decimal(major);
  return Math.round(value.mul(100).toNumber());
}

/** The sum of a list of minor-unit amounts, in minor units. */
export function sumMinor(amounts: number[]): number {
  return amounts.reduce((total, amount) => total + amount, 0);
}
