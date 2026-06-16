const API_BASE = import.meta.env.VITE_API_BASE || 'http://localhost:8080';

export async function createCharge(payload) {
  const response = await fetch(`${API_BASE}/charges`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(payload)
  });

  if (!response.ok) {
    throw new Error(`Charge failed: ${response.status}`);
  }
  return response.json();
}

export async function searchByEmail(email) {
  const response = await fetch(`${API_BASE}/customers/search?email=${email}`);
  if (!response.ok) throw new Error('Search failed');
  return response.json();
}

export async function renderSupportMessage(customerName) {
  const response = await fetch(`${API_BASE}/support/render-message`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ customerName })
  });
  return response.json();
}
