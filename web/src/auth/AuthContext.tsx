import { createContext, useContext, useEffect, useMemo, type ReactNode } from 'react';
import { useQuery, useQueryClient, type QueryClient } from '@tanstack/react-query';
import { Navigate, Outlet, useLocation } from 'react-router';
import { api, ApiError, SESSION_EXPIRED } from '../api/client';
import { Access, type AccessJson } from './access';
import { Spinner } from '../components/ui';

export interface SessionUser {
  id: number;
  name: string;
  username: string;
  last_active_at?: string | null;
}

interface Me {
  user: SessionUser;
  access: AccessJson;
}

interface AuthValue {
  user: SessionUser | null;
  access: Access;
  loading: boolean;
  login: (username: string, password: string) => Promise<void>;
  logout: () => Promise<void>;
}

const AuthContext = createContext<AuthValue | null>(null);

// Drops cached data from the previous session. The ['me'] query is updated in place rather than
// removed, so components watching it keep their subscription.
const resetSession = (qc: QueryClient, me: Me | null) => {
  qc.removeQueries({ predicate: (q) => q.queryKey[0] !== 'me' });
  qc.setQueryData(['me'], me);
};
const NO_ACCESS = new Access({ isOwner: false, assignments: [] });

// After an explicit sign-out the next person starts fresh; only an expired session returns the
// user to the page they were on.
let signedOutOnPurpose = false;

export function AuthProvider({ children }: { children: ReactNode }) {
  const qc = useQueryClient();
  const me = useQuery({
    queryKey: ['me'],
    queryFn: () =>
      api<Me>('/auth/me').catch((error) => {
        if (error instanceof ApiError && error.status === 401) return null;
        throw error;
      }),
    retry: false,
    staleTime: 5 * 60 * 1000,
  });

  useEffect(() => {
    const expired = () => resetSession(qc, null);
    window.addEventListener(SESSION_EXPIRED, expired);
    return () => window.removeEventListener(SESSION_EXPIRED, expired);
  }, [qc]);

  const value = useMemo<AuthValue>(() => {
    const data = me.data ?? null;
    return {
      user: data?.user ?? null,
      access: data ? new Access(data.access) : NO_ACCESS,
      loading: me.isPending,
      login: async (username, password) => {
        const res = await api<Me>('/auth/login', { method: 'POST', body: { username, password } });
        signedOutOnPurpose = false;
        resetSession(qc, { user: res.user, access: res.access });
      },
      logout: async () => {
        signedOutOnPurpose = true;
        await api('/auth/logout', { method: 'POST' }).catch(() => undefined);
        resetSession(qc, null);
      },
    };
  }, [me.data, me.isPending, qc]);

  return <AuthContext.Provider value={value}>{children}</AuthContext.Provider>;
}

export function useAuth(): AuthValue {
  const value = useContext(AuthContext);
  if (!value) throw new Error('useAuth outside AuthProvider');
  return value;
}

/** Route guard: renders child routes for signed-in users, else sends them to /login. */
export function RequireAuth() {
  const { user, loading } = useAuth();
  const location = useLocation();
  if (loading) {
    return (
      <div className="flex h-full items-center justify-center">
        <Spinner />
      </div>
    );
  }
  if (!user) return <Navigate to="/login" replace state={signedOutOnPurpose ? undefined : { from: location.pathname + location.search }} />;
  return <Outlet />;
}
