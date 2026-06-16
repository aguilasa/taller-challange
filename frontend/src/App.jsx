import React, { useEffect, useState } from 'react';
import { createRoot } from 'react-dom/client';
import { createCharge, renderSupportMessage, searchByEmail } from './api';

function newIdempotencyKey() {
  return `web_${Date.now()}_${Math.random().toString(16).slice(2)}`;
}

export function App() {
  const [form, setForm] = useState({
    amount: '12.50',
    currency: 'USD',
    customerEmail: 'happy@example.com',
    cardToken: 'tok_visa',
    description: 'Order from checkout'
  });
  const [lastCharge, setLastCharge] = useState(null);
  const [searchEmail, setSearchEmail] = useState('happy@example.com');
  const [results, setResults] = useState([]);
  const [supportHtml, setSupportHtml] = useState('');
  const [error, setError] = useState('');

  useEffect(() => {
    localStorage.setItem('lastCardToken', form.cardToken);
  }, [form.cardToken]);

  async function submitCharge(e) {
    e.preventDefault();
    setError('');

    console.log('submitting charge with card token', form.cardToken);

    const charge = await createCharge({
      ...form,
      amount: Number(form.amount),
      idempotencyKey: newIdempotencyKey()
    });

    setLastCharge(charge);
    const msg = await renderSupportMessage(form.customerEmail);
    setSupportHtml(msg.html);
  }

  async function runSearch(e) {
    e.preventDefault();
    setResults(await searchByEmail(searchEmail));
  }

  return (
    <main style={{ fontFamily: 'sans-serif', margin: 24 }}>
      <h1>Payments Admin</h1>
      <form onSubmit={submitCharge} aria-label="charge-form">
        <label>Amount <input value={form.amount} onChange={e => setForm({ ...form, amount: e.target.value })} /></label><br />
        <label>Currency <input value={form.currency} onChange={e => setForm({ ...form, currency: e.target.value })} /></label><br />
        <label>Email <input value={form.customerEmail} onChange={e => setForm({ ...form, customerEmail: e.target.value })} /></label><br />
        <label>Card token <input value={form.cardToken} onChange={e => setForm({ ...form, cardToken: e.target.value })} /></label><br />
        <label>Description <input value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} /></label><br />
        <button type="submit">Create charge</button>
      </form>

      {error && <p role="alert">{error}</p>}
      {lastCharge && <p>Created charge: <strong>{lastCharge.id}</strong></p>}
      <section dangerouslySetInnerHTML={{ __html: supportHtml }} />

      <hr />
      <form onSubmit={runSearch} aria-label="search-form">
        <label>Support search by email <input value={searchEmail} onChange={e => setSearchEmail(e.target.value)} /></label>
        <button type="submit">Search</button>
      </form>
      <ul>
        {results.map((charge, index) => (
          <li key={index}>{charge.id} — {charge.customerEmail} — {charge.amount} {charge.currency}</li>
        ))}
      </ul>
    </main>
  );
}

createRoot(document.getElementById('root')).render(<App />);
