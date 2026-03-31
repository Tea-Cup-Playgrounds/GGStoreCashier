document.getElementById('login-form').addEventListener('submit', async (e) => {
  e.preventDefault();
  const btn = document.getElementById('submit-btn');
  const errEl = document.getElementById('error-msg');
  errEl.style.display = 'none';
  btn.disabled = true;
  btn.textContent = 'Signing in...';

  const username = document.getElementById('username').value.trim();
  const password = document.getElementById('password').value;
  const remember = document.getElementById('remember').checked;

  try {
    const res = await fetch('/api/docs/login', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      credentials: 'include',
      body: JSON.stringify({ username, password, remember }),
    });
    const data = await res.json();
    if (res.ok) {
      window.location.href = '/api/docs';
    } else {
      errEl.textContent = data.error || 'Login failed';
      errEl.style.display = 'block';
    }
  } catch {
    errEl.textContent = 'Network error. Please try again.';
    errEl.style.display = 'block';
  } finally {
    btn.disabled = false;
    btn.textContent = 'Sign In';
  }
});
