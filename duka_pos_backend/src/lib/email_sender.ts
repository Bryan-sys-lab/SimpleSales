/**
 * Verification email, sent through Cloudflare Email Service.
 *
 * Keys live only in this process; the app asks the server to send the mail.
 */
import {
  NERVA_LOGO_BASE64,
  NERVA_LOGO_CONTENT_ID,
  NERVA_LOGO_FILENAME,
  NERVA_LOGO_MIME_TYPE,
} from "./nerva_logo";

export type VerificationEmail = {
  kind?: 'verification';
  to: string;
  code: string;
  shopName?: string;
  ttlMinutes: number;
};

export type AccessVoucherEmail = {
  kind: 'access_voucher';
  to: string;
  code: string;
  durationMonths: number;
};

export type EmailMessage = VerificationEmail | AccessVoucherEmail;

export type EmailTransport = (message: EmailMessage) => Promise<void>;

/** Native Cloudflare Email Sending binding exposed by a Worker. */
export type CloudflareEmailBinding = {
  send: (message: Record<string, unknown>) => Promise<unknown>;
};

let nativeEmailBinding: CloudflareEmailBinding | null = null;

/**
 * Installs the Worker Email Sending binding for the current isolate.
 *
 * The REST API token is intentionally only a fallback. Deployment tokens often
 * have Workers permissions but not Email Sending permissions, which previously
 * made account verification fail even though the Worker itself was healthy.
 */
export function setCloudflareEmailBinding(
  binding: CloudflareEmailBinding | null,
): void {
  nativeEmailBinding = binding;
}

export type CloudflareEmailOptions = {
  accountId: string;
  apiToken: string;
  from?: string;
  appName?: string;
  /** Injectable for tests; the default is global fetch. */
  post?: (
    url: string,
    init: { method: string; headers: Record<string, string>; body: string },
  ) => Promise<{ status: number; text: () => Promise<string> }>;
};

export const CLOUDFLARE_EMAIL_ENDPOINT = (accountId: string) =>
  `https://api.cloudflare.com/client/v4/accounts/${accountId}/email/sending/send`;

export class EmailSendError extends Error {
  readonly status: number;
  constructor(status: number) {
    super(`Email provider refused the message (${status})`);
    this.name = "EmailSendError";
    this.status = status;
  }
}

const DEFAULT_FROM = "security@nerva.co.ke";

export function createCloudflareEmailTransport(
  options: CloudflareEmailOptions,
): { configured: boolean; send: EmailTransport } {
  const from = options.from || DEFAULT_FROM;
  const post =
    options.post ??
    (async (url, init) => {
      const response = await fetch(url, init as RequestInit);
      return { status: response.status, text: () => response.text() };
    });

  const configured = Boolean(
    nativeEmailBinding || (options.accountId && options.apiToken && from),
  );

  const buildBody = (message: EmailMessage) => {
    const appName = options.appName ?? "SimpleSales";
    const logoHtml = `<img src="cid:${NERVA_LOGO_CONTENT_ID}" alt="Nerva" width="180" style="display:block;width:180px;height:auto;margin:0 auto 28px;border:0;" />`;
    const escapeHtml = (value: string) =>
      value
        .replaceAll("&", "&amp;")
        .replaceAll("<", "&lt;")
        .replaceAll(">", "&gt;")
        .replaceAll('"', "&quot;")
        .replaceAll("'", "&#39;");
    const safeAppName = escapeHtml(appName);
    if (message.kind === "access_voucher") {
      const safeVoucher = escapeHtml(message.code);
      const duration = `${message.durationMonths} month${message.durationMonths === 1 ? "" : "s"}`;
      const subject = `${appName} — your access voucher`;
      const text = [
        appName,
        "",
        "Your access voucher is ready",
        "",
        `Voucher: ${message.code}`,
        `Access duration: ${duration}`,
        "This code does not expire. Its access period begins when you claim it in the app.",
        "Open the SimpleSales paywall and choose Claim voucher, or enter the code manually.",
        "",
        "If you did not expect this message, contact SimpleSales support.",
      ].join("\n");
      const html = `<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#f3f5f7;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;color:#1b1d21;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f3f5f7;padding:32px 12px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border:1px solid #e5e7eb;border-radius:18px;padding:40px 36px;">
        <tr><td align="center" style="padding-bottom:4px;">${logoHtml}</td></tr>
        <tr><td style="font-size:24px;line-height:1.25;font-weight:750;color:#111;padding-bottom:16px;">Your access voucher is ready</td></tr>
        <tr><td style="font-size:15px;line-height:1.6;color:#4b5563;padding-bottom:20px;">Your administrator has issued ${escapeHtml(duration)} of SimpleSales access.</td></tr>
        <tr><td align="center" style="padding:4px 0 20px;">
          <div style="display:inline-block;background:#f1f5f9;border:1px solid #e2e8f0;border-radius:12px;padding:18px 24px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:20px;line-height:1.2;font-weight:800;letter-spacing:1px;color:#111;">${safeVoucher}</div>
        </td></tr>
        <tr><td style="font-size:13px;line-height:1.6;color:#4b5563;">This code does not expire. Its access period starts when claimed. Open the SimpleSales paywall and tap <strong>Claim voucher</strong>, or enter the code manually.</td></tr>
        <tr><td style="font-size:12px;line-height:1.5;color:#9ca3af;padding-top:24px;"><em>If you did not expect this message, contact SimpleSales support.</em></td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`.trim();
      return {
        to: [message.to],
        from,
        subject,
        text,
        html,
        attachments: [
          {
            content: NERVA_LOGO_BASE64,
            filename: NERVA_LOGO_FILENAME,
            type: NERVA_LOGO_MIME_TYPE,
            disposition: "inline",
            contentId: NERVA_LOGO_CONTENT_ID,
          },
        ],
      };
    }

    const subject = `${appName} — your verification code`;
    const safeCode = escapeHtml(message.code);

    const text = [
      `${appName}`,
      "",
      "Confirm your account",
      "",
      "Hi,",
      "",
      "You're almost there. Enter the verification code below to confirm your email address.",
      "",
      message.code,
      "",
      `Expires in ${message.ttlMinutes} minutes`,
      "",
      "If you didn't request this code, no action is required. For your security, never share your verification code with anyone.",
      "",
      `Thank you for choosing ${appName}.`,
      "",
      `${appName} Security`,
      "",
      "This is an automated security email. Please do not reply.",
    ].join("\n");

    const html = `<!DOCTYPE html>
<html lang="en">
<head><meta charset="UTF-8"><meta name="viewport" content="width=device-width,initial-scale=1"></head>
<body style="margin:0;padding:0;background:#f3f5f7;font-family:-apple-system,BlinkMacSystemFont,'Segoe UI',Arial,sans-serif;color:#1b1d21;">
  <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background:#f3f5f7;padding:32px 12px;">
    <tr><td align="center">
      <table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="max-width:520px;background:#ffffff;border:1px solid #e5e7eb;border-radius:18px;padding:40px 36px;">
        <tr><td align="center" style="padding-bottom:4px;">
          ${logoHtml}
        </td></tr>
        <tr><td style="font-size:24px;line-height:1.25;font-weight:750;color:#111;padding-bottom:16px;">Confirm your account</td></tr>
        <tr><td style="font-size:15px;line-height:1.6;color:#4b5563;padding-bottom:24px;">Hi,<br><br>You're almost there. Enter the verification code below to confirm your email address.</td></tr>
        <tr><td align="center" style="padding:4px 0 24px;">
          <div style="display:inline-block;background:#f1f5f9;border:1px solid #e2e8f0;border-radius:12px;padding:18px 30px;font-family:ui-monospace,SFMono-Regular,Menlo,monospace;font-size:30px;line-height:1;font-weight:800;letter-spacing:8px;color:#111;">${safeCode}</div>
        </td></tr>
        <tr><td style="font-size:13px;line-height:1.5;color:#6b7280;padding-bottom:24px;">Expires in ${message.ttlMinutes} minutes.</td></tr>
        <tr><td style="font-size:13px;line-height:1.5;color:#6b7280;padding-bottom:24px;">If you didn't request this code, no action is required. For your security, never share your verification code with anyone.</td></tr>
        <tr><td style="font-size:13px;line-height:1.5;color:#374151;padding-bottom:8px;">Thank you for choosing <strong>${safeAppName}</strong>.</td></tr>
        <tr><td style="font-size:12px;line-height:1.5;color:#9ca3af;"><em>This is an automated security email. Please do not reply.</em></td></tr>
      </table>
    </td></tr>
  </table>
</body>
</html>`.trim();

    return {
      // Cloudflare's structured Email Sending REST API accepts recipients as
      // an array. Sending the single address as a string makes the provider
      // reject the entire verification message before delivery.
      to: [message.to],
      from,
      subject,
      text,
      html,
      attachments: [
        {
          content: NERVA_LOGO_BASE64,
          filename: NERVA_LOGO_FILENAME,
          type: NERVA_LOGO_MIME_TYPE,
          disposition: "inline",
          contentId: NERVA_LOGO_CONTENT_ID,
        },
      ],
    };
  };

  return {
    configured,
    send: async (message: EmailMessage) => {
      const body = buildBody(message);
      if (nativeEmailBinding) {
        // The Worker binding accepts a single address directly; the REST
        // structured API uses the recipient array below.
        await nativeEmailBinding.send({ ...body, to: message.to });
        return;
      }
      const url = CLOUDFLARE_EMAIL_ENDPOINT(options.accountId);
      const response = await post(url, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${options.apiToken}`,
        },
        body: JSON.stringify(body),
      });
      if (response.status < 200 || response.status >= 300) {
        throw new EmailSendError(response.status);
      }
    },
  };
}

// Backwards-compatible alias while callers migrate.
export const createEmailJsTransport = createCloudflareEmailTransport;
