export function requestContext(req: any, res: any, next: any) {
  const supplied = req.headers['x-request-id'];
  const requestId = typeof supplied === 'string' && supplied.length <= 80 ? supplied : crypto.randomUUID();
  req.requestId = requestId;
  res.setHeader('x-request-id', requestId);
  const started = process.hrtime.bigint();
  res.on('finish', () => log('info', 'http.request', { requestId, method: req.method, path: req.path, status: res.statusCode, durationMs: Number(process.hrtime.bigint() - started) / 1000000 }));
  next();
}

export function log(level: string, event: string, fields: Record<string, any> = {}) {
  const line = JSON.stringify({ timestamp: new Date().toISOString(), level, event, ...fields });
  if (level === 'error') {
    console.error(line);
  } else if (level === 'warn') {
    console.warn(line);
  } else {
    console.log(line);
  }
}
