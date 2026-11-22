export function requiredD1String(
  result: { results?: unknown[] } | undefined,
  column: string,
  context: string,
): string {
  const row = result?.results?.[0];
  if (!row || typeof row !== 'object' || !(column in row)) {
    throw new Error(`D1 did not return ${column} for ${context}`);
  }
  const value = Reflect.get(row, column);
  if (typeof value !== 'string') {
    throw new Error(`D1 returned an invalid ${column} for ${context}`);
  }
  return value;
}
