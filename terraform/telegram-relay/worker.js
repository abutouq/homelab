// Telegram Bot API relay. api.telegram.org is blocked in Jordan, so the homelab
// bots call https://<relay>/bot<token>/<method> instead and this Worker,
// placed outside Jordan, forwards the request unchanged.
//
// Only the bot methods the bots use are forwarded: it is not a general proxy.
const ALLOWED = /^\/bot\d+:[A-Za-z0-9_-]+\/(sendMessage|sendDocument|getMe)$/;

export default {
  async fetch(request) {
    const url = new URL(request.url);
    if (!ALLOWED.test(url.pathname)) return new Response('not found', { status: 404 });
    if (request.method !== 'POST' && request.method !== 'GET') {
      return new Response('method not allowed', { status: 405 });
    }
    const headers = new Headers();
    const type = request.headers.get('content-type');
    if (type) headers.set('content-type', type);
    return fetch(`https://api.telegram.org${url.pathname}${url.search}`, {
      method: request.method,
      headers,
      body: request.method === 'POST' ? request.body : undefined,
    });
  },
};
