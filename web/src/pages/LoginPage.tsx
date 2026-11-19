import { useState, type FormEvent } from 'react';
import { Navigate, useLocation, useNavigate } from 'react-router';
import { useAuth } from '../auth/AuthContext';
import { errorMessage } from '../api/client';
import { Button, Field, Input } from '../components/ui';

export function LoginPage() {
  const { user, login } = useAuth();
  const navigate = useNavigate();
  const location = useLocation();
  const from = (location.state as { from?: string } | null)?.from ?? '/';
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [error, setError] = useState<string | null>(null);
  const [busy, setBusy] = useState(false);

  if (user) return <Navigate to={from} replace />;

  const submit = async (e: FormEvent) => {
    e.preventDefault();
    setBusy(true);
    setError(null);
    try {
      await login(username.trim(), password);
      navigate(from, { replace: true });
    } catch (err) {
      setError(errorMessage(err));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="flex min-h-full items-center justify-center bg-ink-900 px-4 py-10">
      <form onSubmit={submit} className="w-full max-w-sm overflow-hidden rounded-lg border-2 border-ink-900 bg-white">
        <div className="flex items-center gap-3 bg-brand-500 px-6 py-5">
          <div aria-hidden className="flex size-12 items-center justify-center rounded-md bg-ink-900 text-lg font-black text-brand-500">
            GG
          </div>
          <div>
            <h1 className="text-xl font-extrabold text-ink-900">GG Store</h1>
            <p className="text-sm font-semibold text-ink-900">Masuk ke back-office</p>
          </div>
        </div>
        <div className="space-y-4 p-6">
          <Field label="Username">
            <Input autoFocus autoComplete="username" value={username} onChange={(e) => setUsername(e.target.value)} required />
          </Field>
          <Field label="Password">
            <Input type="password" autoComplete="current-password" value={password} onChange={(e) => setPassword(e.target.value)} required />
          </Field>
          {error && (
            <p role="alert" className="rounded-md border-2 border-red-600 bg-red-50 px-3 py-2 text-sm font-medium text-red-800">
              {error}
            </p>
          )}
          <Button type="submit" variant="primary" loading={busy} className="h-11 w-full text-base">
            Masuk
          </Button>
        </div>
      </form>
    </div>
  );
}
