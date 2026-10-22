import { describe, expect, it } from 'vitest';
import { EmailSendError, createEmailJsTransport } from '../lib/email_sender.js';

function fakePost(status: number, body: string) {
  const calls: Array<{ url: string; body: unknown }> = [];
  const post = async (url: string, init: { method: string; headers: Record<string, string>; body: string }) => {
    calls.push({ url, body: JSON.parse(init.body) });
    return { status, text: async () => body };
  };
  return { post, calls };
}

const message = { to: 'owner@example.com', code: '481503', shopName: 'Amina Duka', ttlMinutes: 10 };

describe('EmailJS transport', () => {
  it('is unconfigured without the full keypair', () => {
    expect(createEmailJsTransport({ serviceId: '', templateId: 't', publicKey: 'p', privateKey: 'k' }).configured).toBe(false);
    expect(
      createEmailJsTransport({ serviceId: 's', templateId: 't', publicKey: 'p', privateKey: '' }).configured,
    ).toBe(false);
  });

  it('sends to EmailJS with the code in the template parameters', async () => {
    const fake = fakePost(200, 'OK');
    const transport = createEmailJsTransport({
      serviceId: 'service_1',
      templateId: 'template_1',
      publicKey: 'public_key',
      privateKey: 'private_key',
      post: fake.post,
    });
    await transport.send(message);
    const [call] = fake.calls;
    expect(call.url).toBe('https://api.emailjs.com/api/v1.0/email/send');
    expect(call.body).toEqual({
      service_id: 'service_1',
      template_id: 'template_1',
      user_id: 'public_key',
      accessToken: 'private_key',
      template_params: {
        to_email: 'owner@example.com',
        code: '481503',
        shop_name: 'Amina Duka',
        app_name: 'SimpleSales',
        expires_minutes: 10,
      },
    });
  });

  it('treats any 2xx as delivered', async () => {
    const transport = createEmailJsTransport({
      serviceId: 's',
      templateId: 't',
      publicKey: 'p',
      privateKey: 'k',
      post: fakePost(204, '').post,
    });
    await expect(transport.send(message)).resolves.toBeUndefined();
  });

  it('raises a send error the route turns into "try again", not a silent success', async () => {
    const transport = createEmailJsTransport({
      serviceId: 's',
      templateId: 't',
      publicKey: 'p',
      privateKey: 'k',
      post: fakePost(400, 'Bad request').post,
    });
    await expect(transport.send(message)).rejects.toBeInstanceOf(EmailSendError);
  });

  it('never lets the code reach an error message', async () => {
    // The failure path is logged and shown to the operator; the code itself
    // must not be reconstructable from it.
    try {
      const transport = createEmailJsTransport({
        serviceId: 's',
        templateId: 't',
        publicKey: 'p',
        privateKey: 'k',
        post: fakePost(429, 'Too many requests').post,
      });
      await transport.send(message);
      expect.unreachable();
    } catch (error) {
      expect((error as Error).message).not.toContain('481503');
      expect((error as Error).message).toContain('429');
    }
  });
});
