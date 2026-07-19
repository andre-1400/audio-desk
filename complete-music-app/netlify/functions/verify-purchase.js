const https = require('https');

exports.handler = async (event) => {
  const sessionId = event.queryStringParameters && event.queryStringParameters.session_id;

  if (!sessionId || !/^cs_/.test(sessionId)) {
    return { statusCode: 400, body: JSON.stringify({ ok: false }) };
  }

  try {
    const session = await fetchStripeSession(sessionId);
    const ok = session.payment_status === 'paid';
    return { statusCode: 200, body: JSON.stringify({ ok }) };
  } catch (err) {
    return { statusCode: 200, body: JSON.stringify({ ok: false }) };
  }
};

function fetchStripeSession(sessionId) {
  return new Promise((resolve, reject) => {
    const options = {
      hostname: 'api.stripe.com',
      path: `/v1/checkout/sessions/${encodeURIComponent(sessionId)}`,
      method: 'GET',
      headers: {
        Authorization: `Bearer ${process.env.STRIPE_SECRET_KEY}`,
      },
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        try {
          const parsed = JSON.parse(data);
          if (res.statusCode >= 200 && res.statusCode < 300) {
            resolve(parsed);
          } else {
            reject(new Error('Stripe request failed'));
          }
        } catch (e) {
          reject(e);
        }
      });
    });

    req.on('error', reject);
    req.end();
  });
}
